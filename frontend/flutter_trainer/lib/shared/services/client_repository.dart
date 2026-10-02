import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/network/interceptors/client_access_interceptor.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_menu_plans.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/data/dtos/client_dtos.dart'
    show
        prioritizeClients,
        sortByLatestMessage,
        clientExerciseItems,
        clientSignalsFromJson;
import 'package:oncare_trainer/features/clients/data/repositories/dio_client_repository.dart';
import 'package:oncare_trainer/features/clients/domain/diet_analysis_rules.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_analysis.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/health_focus.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';

/// Reads a trainer's clients + their diet/history for the 고객 관리 tab.
///
/// Two implementations sit behind this contract (selected by
/// [clientRepositoryProvider] via [AppConfig.useMockApi]):
///  * [DriftClientRepository] — local drift, demo / `USE_MOCK_API=true`;
///  * [DioClientRepository] — the real FastAPI backend.
///
/// Reads are exposed as streams so the drift source can stay reactive; the
/// Dio source emits a single fetched value (loading/error surface through
/// the consuming `AsyncValue`).
abstract interface class ClientRepository {
  /// Whether this source can **add** clients to the roster.
  ///
  /// The real roster is defined by trainer↔member links created through
  /// consultation approval, and there is no add-client endpoint — so the
  /// 신규 고객 등록 entry stays demo-only.
  ///
  /// This no longer gates [setClientActive]: the 활성/휴면 state is a
  /// trainer-side management flag that both sources support (#707). The two
  /// used to share one flag, which kept the status badge read-only against
  /// the real API.
  bool get supportsRosterMutations;

  Stream<List<TrainerClient>> watchClients();

  /// Most recent chat activity per client id — the tiebreak used by
  /// [prioritizeClients]. Sources without a chat signal emit `{}`.
  Stream<Map<String, DateTime>> watchLastChatAt();

  /// [clientId] 의 **오늘** 끼니.
  Stream<List<ClientDietEntry>> watchDiet(String clientId);

  /// [clientId] 가 [date] 에 먹은 끼니. 기간 뷰에서 날짜를 눌러 그날을 펼칠
  /// 때 쓴다(#1025). 기록이 없으면 빈 목록이다.
  Future<List<ClientDietEntry>> fetchDietOn(String clientId, DateTime date);

  /// [clientId] 가 [date] 에 한 운동 이름들. 끝의 `✓`/`✗` 가 수행 여부다 —
  /// 운동 기록 카드가 쓰는 것과 같은 문자열이다(#1025).
  Future<List<ClientExerciseItem>> fetchExercisesOn(
    String clientId,
    DateTime date,
  );
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId);
  Future<MemberHealthProfile> fetchHealthProfile(String clientId);
  Future<MemberHealthProfile> updateHealthProfile(
    String clientId,
    Map<String, Object?> values,
  );

  /// [clientId] 의 한 주 운동 집계. [weekStart] 를 주지 않으면 이번 주다.
  ///
  /// 주를 인자로 받는 이유는 `이번 달` 때문이다 — 서버도 데모도 운동 이력을
  /// 주 단위로 들고 있어, 한 달을 그리려면 그 달에 걸친 주를 각각 읽어 이어
  /// 붙인다(#914).
  Future<ClientExerciseWeek> fetchExerciseWeek(
    String clientId, {
    DateTime? weekStart,
  });

  /// [range] 가 걸친 **주들** — GET /trainer/clients/{id}/exercise/weeks (#2247)
  ///
  /// `전체` 그래프가 쓰는 길이다. 예전에는 주마다 [fetchExerciseWeek] 을
  /// 불렀는데, `전체` 가 모든 기록을 그리게 되면서(#2079) 기록이 길수록 왕복이
  /// 그만큼 늘었다. 돌려주는 칸에는 세션 목록이 없다 — 한 주를 펼쳐 볼 때는
  /// [fetchExerciseWeek] 이다.
  Future<List<ClientExercisePeriodWeek>> fetchExercisePeriod(
    String clientId,
    ClientDateRange range,
  );

  /// [range] 가 덮는 날들의 일별 식단 집계.
  ///
  /// 회원 앱 식단 탭의 기간 뷰와 같은 것을 트레이너에게도 준다. 두 구현 모두
  /// **주 단위 이력**에서 만든다 — 데모는 drift 의 일별 지표에서, 실서버는
  /// 리포트 응답(`calories_week` · `sodium_week` · `sugar_week`)에서.
  /// 기간에 맞는 `식단 분석` — 원인까지 짚는 서술형 규칙 문장. (#2379)
  ///
  /// 회원 앱 조언과 **같은 기간·같은 판정**이다(이번 주는 월·화 지난주 회고,
  /// 전체는 최근 4주). 같은 회원의 같은 기간을 두 화면이 다른 기준으로 말하면
  /// 상담에서 둘이 다른 이야기를 들고 앉는다. 문장은 키·값으로 오고 화면이 ARB 로
  /// 그린다. 실서버는 [locale] 을 `Accept-Language` 로 보낸다(#2299) — 문장 키는
  /// 언어와 무관하다.
  Future<ClientDietAnalysis> fetchDietAdvice(
    String clientId,
    ClientPeriod period, {
    required Locale locale,
  });

  /// 회원에게 추천할 AI 식단 후보와 지금 확정한 추천. (#2378, #2379)
  ///
  /// 후보는 회원의 4주 추천 메뉴 리스트에서 급한 태그를 채우는 메뉴부터다. 조회로
  /// AI 를 새로 부르지 않는다.
  Future<ClientDietRecommendations> fetchDietRecommendations(
    String clientId, {
    required Locale locale,
  });

  /// 후보 하나를 회원에게 추천한다 — 회원 앱 홈 `추천 식단` 첫 장이 된다. 다시
  /// 부르면 바꾸기다. 돌려주는 것은 확정 뒤의 상태다.
  Future<ClientDietRecommendations> confirmDietRecommendation(
    String clientId, {
    required String slot,
    required String name,
    required Locale locale,
  });

  Future<ClientDietPeriod> fetchDietPeriod(
    String clientId,
    ClientDateRange range,
  );

  /// [clientId] 가 식단·운동을 **처음 남긴 날**. 기록이 없으면 null 이다.
  ///
  /// `전체` 그래프가 어디서부터 그릴지를 정하는 값이다(#2079). 회원 API
  /// (`GET /me/records/span`)와 같은 응답을 트레이너용으로 읽는다(#2236).
  Future<ClientRecordSpan> fetchRecordSpan(String clientId);

  /// Demo-only roster additions — the backend roster comes from
  /// trainer↔member links, so these are unsupported against the real API.
  Future<bool> clientNameExists(String name);
  Future<bool> addClient({required String name, required String goal});

  /// Moves [id] between 활성 and 휴면.
  ///
  /// Supported by both sources. This is the trainer's own management state,
  /// **not** an unassignment — the member keeps their coach and every record
  /// behind the link (#707).
  Future<void> setClientActive(String id, bool active);

  /// Removes the trainer-client assignment without deleting member data.
  Future<void> removeClient(String id);

  Future<void> restoreClient(String id);
}

/// 데모(drift)에서 미등록 상태를 나타내는 키. 트레이너-고객 행 자체는 지우지
/// 않고 이 id 목록에만 올려 둔다 — 원본 기록을 지우지 않는다는 정책과, 다시
/// 등록할 때 새 행이 아니라 같은 행을 되살려야 한다는 요구가 같이 걸려 있다.
///
/// [DriftClientRepository] 뿐 아니라 [DemoClientInviteRepository]도 이
/// 목록을 본다 — 고객 탭의 "새 회원 등록" 창으로 미등록 고객을 다시 연결할
/// 때, 이미 있는 행을 무시하고 새로 넣으면 기본 키 충돌로 "이미 연결됨"
/// 이라는 잘못된 안내가 뜬다.
const String demoUnregisteredClientsKey = 'trainer_unregistered_clients';

/// [readDemoUnregisteredClientIds] 가 채워 둔, db 인스턴스별 동기 스냅샷.
///
/// 오늘 일정·주간 캘린더·안읽음 배지처럼 여러 고객을 한 번에 훑는 조회는
/// 매 emission 마다 이 목록을 다시 읽으면(비동기 라운드트립) 이미 초 단위로
/// 고정된 pump 예산으로 검증하는 다른 위젯 테스트들의 타이밍을 밀어낸다
/// (#1623 구현 중 `client_status_toggle_test`·`dashboard_page_test` 에서
/// 실제로 깨졌다). 그 조회들은 이 동기 스냅샷으로 거른다.
///
/// db 를 연 직후, 아무 조회도 [readDemoUnregisteredClientIds] 를 부르기
/// 전에는 비어 있다 — 실제로는 앱 부팅 직후 사이드바·대시보드가 고객
/// 목록([DriftClientRepository.watchClients], 매 emission 마다 이 목록을
/// 새로 읽는다)을 거의 즉시 구독하므로 그 창은 실질적으로 없다. 그 뒤로는
/// [writeDemoUnregisteredClientIds] 가 (고객 삭제·(재)등록에서) 즉시
/// 갱신한다.
final Expando<Set<String>> _unregisteredSnapshots = Expando<Set<String>>();

/// [db] 의 현재 미등록 고객 id 스냅샷 — DB를 읽지 않는다.
Set<String> demoUnregisteredClientIdsSnapshot(AppDatabase db) =>
    _unregisteredSnapshots[db] ?? const <String>{};

/// [demoUnregisteredClientsKey] 에 저장된 미등록 고객 id 목록을 읽고,
/// [demoUnregisteredClientIdsSnapshot] 도 함께 갱신한다.
Future<Set<String>> readDemoUnregisteredClientIds(AppDatabase db) async {
  final raw = await db.readValue(demoUnregisteredClientsKey);
  final ids = raw == null || raw.isEmpty
      ? <String>{}
      : (jsonDecode(raw) as List<Object?>).whereType<String>().toSet();
  _unregisteredSnapshots[db] = ids;
  return ids;
}

/// [ids] 를 [demoUnregisteredClientsKey] 에 저장한다.
Future<void> writeDemoUnregisteredClientIds(
  AppDatabase db,
  Set<String> ids,
) async {
  _unregisteredSnapshots[db] = ids;
  await db.putValue(
    demoUnregisteredClientsKey,
    jsonEncode(ids.toList()..sort()),
  );
}

/// 고객을 삭제하거나(재)등록한 뒤, 그 결과로 노출이 바뀌는 여러 고객을
/// 한꺼번에 보여주는 조회들을 새로고침한다 — 오늘 일정, 주간 캘린더, 예약
/// 날짜 점, 사이드바 안읽음 배지.
///
/// 이 provider 들의 스트림은 [demoUnregisteredClientsKey] 변화를 직접 듣지
/// 않는다(#1623) — 앱 전체가 쓰는 키-값 테이블이라 거기 걸면 무관한 값 하나가
/// 바뀔 때마다 다시 돈다. 대신 미등록 상태를 바꾸는 이 두 호출부
/// (`MyPage._removeClient`, `ClientConnectDialog._connect`)가 명시적으로
/// 무효화한다.
void invalidateClientVisibilityDependentViews(WidgetRef ref) {
  ref.invalidate(todayScheduleProvider);
  ref.invalidate(scheduleForDateProvider);
  ref.invalidate(bookedDatesProvider);
  ref.invalidate(scheduleRangeProvider);
  ref.invalidate(unreadCountsProvider);
}

/// Reads client + schedule data from the local drift DB for the
/// 고객 관리 tab. Returns reactive streams so the UI updates if the
/// underlying rows change (e.g. a routine sent from another tab).
class DriftClientRepository implements ClientRepository {
  /// Creates the repository over [_db].
  const DriftClientRepository(this._db);

  final AppDatabase _db;

  @override
  bool get supportsRosterMutations => true;

  /// All clients, ordered as seeded (sortOrder).
  @override
  Stream<List<TrainerClient>> watchClients() {
    final trigger = _db.customSelect(
      'SELECT 1',
      readsFrom: <ResultSetImplementation<Object?, Object?>>{
        _db.trainerClients,
        _db.appKeyValues,
      },
    );
    return trigger.watch().asyncMap((_) async {
      final query = _db.select(_db.trainerClients)
        ..orderBy(<OrderingTerm Function($TrainerClientsTable)>[
          (t) => OrderingTerm(expression: t.sortOrder),
        ]);
      final rows = await query.get();
      final removed = await readDemoUnregisteredClientIds(_db);
      return rows
          .map((row) => _toEntity(row, registered: !removed.contains(row.id)))
          .toList();
    });
  }

  /// Most recent message time per client.
  ///
  /// A plain grouped aggregate over the chat table — deliberately NOT a
  /// join against `trainerClients`. The joined form (`select(t).join(...)
  /// ..groupBy(...)`) never completes against the sqlite3 WASM build the
  /// web app runs on, which stalled the roster and the dashboard on a
  /// spinner with no error to show.
  @override
  Stream<Map<String, DateTime>> watchLastChatAt() {
    final chat = _db.clientChatMessages;
    final latest = chat.createdAt.max();
    final query = _db.selectOnly(chat)
      ..addColumns(<Expression<Object>>[chat.clientId, latest])
      ..groupBy(<Expression<Object>>[chat.clientId]);
    return query.watch().map((rows) {
      final out = <String, DateTime>{};
      for (final row in rows) {
        final id = row.read(chat.clientId);
        final at = row.read(latest);
        if (id != null && at != null) out[id] = at;
      }
      return out;
    });
  }

  /// Whether a client with this display name already exists
  /// (whitespace- and case-insensitive). Counts in SQL rather than
  /// loading every row into memory (review PR 243).
  @override
  Future<bool> clientNameExists(String name) async {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return false;
    return _nameTaken(key);
  }

  /// SQL `COUNT(*)` of clients whose normalised name matches [key]
  /// (already trimmed + lower-cased). Runs inside the caller's
  /// transaction when there is one, so `addClient` can check-then-insert
  /// atomically.
  Future<bool> _nameTaken(String key) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM trainer_clients '
          'WHERE lower(trim(name)) = ?1',
          variables: <Variable<Object>>[Variable<String>(key)],
          readsFrom: <ResultSetImplementation<Object?, Object?>>{
            _db.trainerClients,
          },
        )
        .getSingle();
    return row.read<int>('c') > 0;
  }

  /// Registers a new client (e.g. after a 상담) with a fresh, empty
  /// profile. The non-`seed-` id survives the daily re-seed.
  ///
  /// Returns `false` — writing nothing — when the name is blank or
  /// already taken. Schedule rows reference a client by NAME (the chat
  /// shortcut and completion logging both look up `clientName`), so a
  /// duplicate name would attribute one client's chat/운동기록 to
  /// another. Keeping names unique closes that path until schedules
  /// carry a clientId (review PR 243).
  ///
  /// The duplicate check and the insert run in ONE transaction, so two
  /// concurrent adds of the same name can't both pass the check and both
  /// insert — exactly one wins, the other returns `false` (review 243).
  @override
  Future<bool> addClient({required String name, required String goal}) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return false;
    return _db.transaction(() async {
      if (await _nameTaken(trimmedName.toLowerCase())) return false;
      final now = nowKst();
      await _db
          .into(_db.trainerClients)
          .insert(
            TrainerClientsCompanion.insert(
              id: 'client-${now.microsecondsSinceEpoch}',
              name: trimmedName,
              // runes.first survives surrogate pairs without pulling the
              // characters package into this pure-Dart service.
              avatar: String.fromCharCode(trimmedName.runes.first),
              // 목표는 건강 목표만 남긴다 — 고르지 않았으면 비어 있다(#1818).
              goal: healthFocusGoal(goal),
              // 대화가 없으면 비워 둔다 — 화면이 로케일에 맞춰
              // "아직 대화가 없어요" 를 그린다.
              lastMessage: '',
              lastTime: '-',
              active: const Value(true),
              caloriesToday: 0,
              sodiumMg: 0,
              sugarG: 0,
              carbsG: const Value(0),
              proteinG: const Value(0),
              fatG: const Value(0),
              lastRoutine: '-',
              weekCompletionJson: '[0,0,0,0,0,0,0]',
              sodiumWeekJson: const Value('[]'),
              // Large key appends new clients after the seeded roster.
              sortOrder: Value(now.millisecondsSinceEpoch),
            ),
          );
      return true;
    });
  }

  /// Flips a client between 활성 and 휴면.
  @override
  Future<void> setClientActive(String id, bool active) async {
    await (_db.update(_db.trainerClients)..where((t) => t.id.equals(id))).write(
      TrainerClientsCompanion(active: Value(active)),
    );
  }

  @override
  Future<void> removeClient(String id) async {
    // 삭제 확인창이 트레이너에게 하는 약속(스케줄·루틴·리포트·메시지가
    // **트레이너 화면에서만** 사라지고, 원본은 지워지지 않는다)은 실
    // 백엔드(`trainer_service.remove_client`)와 같아야 한다. 예전에는 여기서
    // 스케줄·AI 루틴·운동 기록·채팅·리포트 피드백 행을 실제로 지웠는데, 그
    // 대가가 재등록 때 드러났다 — 카드의 주간 이행률(`weekCompletionJson`)은
    // 캐시라 손대지 않은 채 남는데 근거가 되는 `clientRoutineHistory` 는 이미
    // 사라져, 되살린 고객의 카드와 상세 화면이 서로 다른 값을 보여줬다(#1623).
    //
    // 이제는 행을 지우지 않고 미등록 id 목록에만 올린다. 여러 고객을 한 번에
    // 보여주는 조회(오늘 일정·전체 안읽음 배지)만 이 목록으로 걸러 낸다 — 특정
    // 고객 하나를 이미 알고 여는 조회(상세 화면 등)는 애초에 등록 고객만 그
    // 화면으로 갈 수 있어 걸러낼 필요가 없다.
    final removed = (await readDemoUnregisteredClientIds(_db))..add(id);
    await writeDemoUnregisteredClientIds(_db, removed);
  }

  @override
  Future<void> restoreClient(String id) async {
    final removed = (await readDemoUnregisteredClientIds(_db))..remove(id);
    await writeDemoUnregisteredClientIds(_db, removed);
  }

  @override
  Future<MemberHealthProfile> fetchHealthProfile(String clientId) async {
    final row = await (_db.select(
      _db.trainerClients,
    )..where((table) => table.id.equals(clientId))).getSingle();
    final savedJson = await _db.readValue('member_health_profile:$clientId');
    final saved = savedJson == null
        ? const <String, Object?>{}
        : jsonDecode(savedJson) as Map<String, Object?>;
    return MemberHealthProfile(
      memberId: clientId,
      memberName: row.name,
      // 키·체중은 저장된 적이 없으면 비운다. 예전에는 175/72 를 채웠는데,
      // 트레이너가 입력한 값과 앱이 지어낸 값이 화면에서 구분되지 않았고,
      // 그대로 저장하면 남의 신체 정보로 굳었다(#818).
      heightCm: (saved['height_cm'] as num?)?.toDouble(),
      weightKg: (saved['weight_kg'] as num?)?.toDouble(),
      // 성별은 로스터가 이미 말하고 있는 값을 따른다. 고정 'male' 을 두던
      // 시절에는 헤더가 '여성'인 회원의 대화상자가 '남성'으로 열렸다(#818).
      gender: saved['gender'] as String? ?? _toEntity(row).rosterGender,
      // 저장한 적이 없으면 로스터 목표에서 건강 목표를 읽는다(#1818).
      conditions:
          saved['conditions'] as String? ??
          formatHealthFocus(parseHealthFocus(row.goal)),
      // 데모에서 트레이너가 목표를 바꾼 기록 — 실서버와 같은 줄을 그린다(#1832).
      focusChangedBy: saved['focus_changed_by'] as String?,
      focusChangedAt: switch (saved['focus_changed_at']) {
        final String at => DateTime.tryParse(at),
        _ => null,
      },
      notesChangedBy: saved['notes_changed_by'] as String?,
      notesChangedAt: switch (saved['notes_changed_at']) {
        final String at => DateTime.tryParse(at),
        _ => null,
      },
      weeklyWorkoutGoal: saved.containsKey('weekly_workout_goal')
          ? (saved['weekly_workout_goal'] as num?)?.toInt()
          : 3,
      weeklyExerciseMinutesGoal:
          saved.containsKey('weekly_exercise_minutes_goal')
          ? (saved['weekly_exercise_minutes_goal'] as num?)?.toInt()
          : 150,
      // 주간 소모 목표의 기본값은 회원 앱과 같은 **하루 목표 × 7** 이다
      // (`kWeeklyBurnKcal`). 1500 은 어느 화면도 쓰지 않는 값이라, 회원이 자기
      // MY 에서 보는 목표와 트레이너의 회원 정보가 서로 달랐다. (#1170)
      weeklyBurnGoal: saved.containsKey('weekly_burn_goal')
          ? (saved['weekly_burn_goal'] as num?)?.toInt()
          : kWeeklyBurnKcal.round(),
      // 회원 앱 MY 와 같은 목표 10칸(#1449). 예전에는 여기서 읽지 않아, 트레이너가
      // 저장해도 창을 다시 열면 빈칸이었다(#2331). 저장한 적이 없으면 비운다 —
      // 화면이 회원 앱 기본값을 흐리게 보여 준다.
      dailyCalories: (saved['daily_calories'] as num?)?.toInt(),
      dailySodiumMg: (saved['daily_sodium_mg'] as num?)?.toInt(),
      dailySugarG: (saved['daily_sugar_g'] as num?)?.toInt(),
      dailyCarbsG: (saved['daily_carbs_g'] as num?)?.toInt(),
      dailyProteinG: (saved['daily_protein_g'] as num?)?.toInt(),
      dailyFatG: (saved['daily_fat_g'] as num?)?.toInt(),
      dailyBurnKcal: (saved['daily_burn_kcal'] as num?)?.toInt(),
      weeklyCardioMinutes: (saved['weekly_cardio_minutes'] as num?)?.toInt(),
      weeklyStrengthSets: (saved['weekly_strength_sets'] as num?)?.toInt(),
      weeklyFlexibilityMinutes: (saved['weekly_flexibility_minutes'] as num?)
          ?.toInt(),
    );
  }

  @override
  Future<MemberHealthProfile> updateHealthProfile(
    String clientId,
    Map<String, Object?> values,
  ) async {
    final current = await fetchHealthProfile(clientId);
    Object? value(String key, Object? fallback) =>
        values.containsKey(key) ? values[key] : fallback;
    final saved = <String, Object?>{
      'height_cm': value('height_cm', current.heightCm),
      'weight_kg': value('weight_kg', current.weightKg),
      'gender': value('gender', current.gender),
      'conditions': normalizeHealthFocusText(
        value('conditions', current.conditions) as String? ?? '',
      ),
      'weekly_workout_goal': value(
        'weekly_workout_goal',
        current.weeklyWorkoutGoal,
      ),
      'weekly_exercise_minutes_goal': value(
        'weekly_exercise_minutes_goal',
        current.weeklyExerciseMinutesGoal,
      ),
      'weekly_burn_goal': value('weekly_burn_goal', current.weeklyBurnGoal),
      'daily_calories': value('daily_calories', current.dailyCalories),
      'daily_sodium_mg': value('daily_sodium_mg', current.dailySodiumMg),
      'daily_sugar_g': value('daily_sugar_g', current.dailySugarG),
      'daily_carbs_g': value('daily_carbs_g', current.dailyCarbsG),
      'daily_protein_g': value('daily_protein_g', current.dailyProteinG),
      'daily_fat_g': value('daily_fat_g', current.dailyFatG),
      'daily_burn_kcal': value('daily_burn_kcal', current.dailyBurnKcal),
      'weekly_cardio_minutes': value(
        'weekly_cardio_minutes',
        current.weeklyCardioMinutes,
      ),
      'weekly_strength_sets': value(
        'weekly_strength_sets',
        current.weeklyStrengthSets,
      ),
      'weekly_flexibility_minutes': value(
        'weekly_flexibility_minutes',
        current.weeklyFlexibilityMinutes,
      ),
      'focus_changed_by': current.focusChangedBy,
      'focus_changed_at': current.focusChangedAt?.toIso8601String(),
      'notes_changed_by': current.notesChangedBy,
      'notes_changed_at': current.notesChangedAt?.toIso8601String(),
    };
    // 목표 칩이 실제로 바뀐 저장만 `마지막 변경` 으로 남긴다 — 실서버와 같은
    // 규칙이다(#1832). 주의사항 글·수치만 고친 저장은 목표 변경이 아니다.
    final Set<String> before = parseHealthFocus(current.conditions);
    final Set<String> after = parseHealthFocus(saved['conditions'] as String);
    if (before.length != after.length || !before.containsAll(after)) {
      saved['focus_changed_by'] = MemberHealthProfile.focusChangedByTrainer;
      saved['focus_changed_at'] = nowKst().toIso8601String();
    }
    // 건강상태·주의사항은 따로 남긴다 — 조각 순서만 바뀐 저장은 아니다(#2942).
    Set<String> notes(String raw) => healthFocusNotes(
      raw,
    ).split(', ').where((String t) => t.isNotEmpty).toSet();
    final Set<String> notesBefore = notes(current.conditions);
    final Set<String> notesAfter = notes(saved['conditions'] as String);
    if (notesBefore.length != notesAfter.length ||
        !notesBefore.containsAll(notesAfter)) {
      saved['notes_changed_by'] = MemberHealthProfile.focusChangedByTrainer;
      saved['notes_changed_at'] = nowKst().toIso8601String();
    }
    await _db.putValue('member_health_profile:$clientId', jsonEncode(saved));
    // 로스터의 회원 목표는 건강 목표다 — 실서버가 `conditions` 에서 읽는 것과 같다(#1818).
    if (values.containsKey('conditions')) {
      await (_db.update(
        _db.trainerClients,
      )..where((table) => table.id.equals(clientId))).write(
        TrainerClientsCompanion(
          goal: Value(healthFocusGoal(saved['conditions']! as String)),
        ),
      );
    }
    return fetchHealthProfile(clientId);
  }

  /// 데모의 이행률 → 운동 시간 환산. 100% 를 30분으로 본다.
  ///
  /// 지난 주를 읽을 때도 **같은 규칙**을 쓴다 — 주마다 환산이 다르면 한 달
  /// 그래프에서 주 경계마다 값이 튄다.
  static int _minutesFromCompletion(int rate) =>
      rate == 0 ? 0 : (30 * rate / 100).round();

  /// 데모의 유형 분해. 실서버는 세션이 유형을 들고 오지만 데모에는 이행률뿐이라,
  /// **날짜로 정해지는 고정 비율**로 나눈다(#943).
  ///
  /// 무작위가 아니라 요일에서 나온다 — 화면을 다시 열 때마다 근력과 유산소가
  /// 자리를 바꾸면 데모를 보는 사람이 그래프를 믿지 않는다. 남은 분은 유산소가
  /// 흡수해 셋의 합이 언제나 그날 총 분과 같다.
  static List<int> _typeSplit(int minutes, int weekdayIndex) {
    if (minutes <= 0) return const <int>[0, 0, 0];
    final int strength = (minutes * (weekdayIndex.isEven ? 0.40 : 0.25))
        .round();
    final int stretching = (minutes * 0.15).round();
    return <int>[minutes - strength - stretching, strength, stretching];
  }

  /// 데모 픽스처. 김민수의 운동은 이 파일 하나가 정한다.
  static final DemoFixture _fixture = DemoFixture.load();

  /// 픽스처가 들고 있는 회원의 주간 운동. 유형·분·칼로리·**세트**를 픽스처에서
  /// 그대로 옮긴다.
  ///
  /// 예전에는 이행률에서 분을 되만들고 요일로 유형을 나눴다. 같은 회원인데
  /// 회원 앱은 픽스처를, 트레이너 화면은 재구성한 값을 보여, 근력 세트도 소모
  /// 칼로리도 두 화면이 다른 수를 말했다. (#1077)
  ClientExerciseWeek? _fixtureWeek(
    String clientId,
    DateTime monday,
    _ExerciseGoals goals,
  ) {
    if (clientId != _fixture.trainerClientId) return null;
    final DateTime today = nowKst();
    final String mondayYmd = ymd(monday);
    final List<FixtureDay> days = _fixture
        .daysFor(today)
        .where((FixtureDay d) => d.weekStart == mondayYmd)
        .toList();
    if (days.isEmpty) return null;

    final List<int> minutes = List<int>.filled(7, 0);
    final List<int> calories = List<int>.filled(7, 0);
    final List<int> cardio = List<int>.filled(7, 0);
    final List<int> strength = List<int>.filled(7, 0);
    final List<int> stretching = List<int>.filled(7, 0);
    final List<int> other = List<int>.filled(7, 0);
    final List<int> sets = List<int>.filled(7, 0);
    // 유형별 칼로리는 픽스처가 운동마다 들고 있는 값을 그대로 모은다 — 분에서
    // 환산하지 않는다. 유형마다 분당 소모가 달라서다(#1289).
    final List<int> cardioCal = List<int>.filled(7, 0);
    final List<int> strengthCal = List<int>.filled(7, 0);
    final List<int> stretchingCal = List<int>.filled(7, 0);
    final List<int> otherCal = List<int>.filled(7, 0);
    for (final FixtureDay day in days) {
      final int i = DateTime.parse(day.date).weekday - 1;
      for (final FixtureExercise e in day.doneExercises) {
        minutes[i] += e.minutes;
        calories[i] += e.calories;
        switch (e.type) {
          case 'strength':
            strength[i] += e.minutes;
            strengthCal[i] += e.calories;
            sets[i] += e.sets ?? setsFromStrengthMinutes(e.minutes);
          case 'flexibility' || 'stretching' || 'yoga':
            stretching[i] += e.minutes;
            stretchingCal[i] += e.calories;
          case 'cardio' || 'walking':
            cardio[i] += e.minutes;
            cardioCal[i] += e.calories;
          default:
            other[i] += e.minutes;
            otherCal[i] += e.calories;
        }
      }
    }
    return ClientExerciseWeek(
      dayLabels: const ['월', '화', '수', '목', '금', '토', '일'],
      dailyMinutes: minutes,
      dailyCalories: calories,
      cardioMinutes: cardio,
      strengthMinutes: strength,
      stretchingMinutes: stretching,
      otherMinutes: other,
      cardioCalories: cardioCal,
      strengthCalories: strengthCal,
      stretchingCalories: stretchingCal,
      otherCalories: otherCal,
      strengthSets: sets,
      weeklyGoalMinutes: goals.minutes,
      weeklyGoalCalories: goals.calories,
      streakDays: _longestStreak(minutes),
      totalMinutes: minutes.fold(0, (int a, int b) => a + b),
      totalCalories: calories.fold(0, (int a, int b) => a + b),
    );
  }

  @override
  Future<List<ClientExercisePeriodWeek>> fetchExercisePeriod(
    String clientId,
    ClientDateRange range,
  ) async {
    // 데모는 주마다 같은 집계를 부른다 — 한 주 조회와 기간 조회의 숫자가
    // 갈리면 안 된다. 서버도 같은 함수를 기간만큼 부른다(#2247).
    final List<ClientExercisePeriodWeek> weeks = <ClientExercisePeriodWeek>[];
    for (final DateTime monday in clientRangeWeekStarts(range)) {
      weeks.add((
        weekStart: monday,
        week: await fetchExerciseWeek(clientId, weekStart: monday),
      ));
    }
    return weeks;
  }

  @override
  Future<ClientExerciseWeek> fetchExerciseWeek(
    String clientId, {
    DateTime? weekStart,
  }) async {
    final monday = clientMondayOf(weekStart ?? nowKst());
    final _ExerciseGoals goals = await _exerciseGoals(clientId);
    final ClientExerciseWeek? fromFixture = _fixtureWeek(
      clientId,
      monday,
      goals,
    );
    if (fromFixture != null) return fromFixture;
    final completion = await _weekCompletion(clientId, monday);
    final List<List<ClientExerciseItem>> done = await _weekExercises(
      clientId,
      monday,
    );
    final List<int> minutes = List<int>.filled(7, 0);
    final List<int> calories = List<int>.filled(7, 0);
    final List<int> cardio = List<int>.filled(7, 0);
    final List<int> strength = List<int>.filled(7, 0);
    final List<int> stretching = List<int>.filled(7, 0);
    final List<int> sets = List<int>.filled(7, 0);
    final List<int> cardioCal = List<int>.filled(7, 0);
    final List<int> strengthCal = List<int>.filled(7, 0);
    final List<int> stretchingCal = List<int>.filled(7, 0);
    for (var d = 0; d < 7; d++) {
      // 그날 한 운동에서 유형별로 센다(#2667) — 실서버가 세션에서 세는 것과
      // 같다. 값이 실리지 않은 옛 기록뿐인 날만 이행률에서 환산한다.
      for (final ClientExerciseItem item in done[d]) {
        final (int m, _DemoKind kind) = _demoMinutes(item);
        if (m <= 0) continue;
        final int kcal = m * kind.kcalPerMinute;
        switch (kind) {
          case _DemoKind.strength:
            strength[d] += m;
            strengthCal[d] += kcal;
            sets[d] += item.sets ?? setsFromStrengthMinutes(m);
          case _DemoKind.stretching:
            stretching[d] += m;
            stretchingCal[d] += kcal;
          case _DemoKind.cardio:
            cardio[d] += m;
            cardioCal[d] += kcal;
        }
        minutes[d] += m;
        calories[d] += kcal;
      }
      if (minutes[d] > 0) continue;
      final int fallback = _minutesFromCompletion(
        d < completion.length ? completion[d] : 0,
      );
      if (fallback == 0) continue;
      final List<int> split = _typeSplit(fallback, d);
      minutes[d] = fallback;
      cardio[d] = split[0];
      strength[d] = split[1];
      stretching[d] = split[2];
      // 데모의 옛 환산은 분에 일정 배수를 곱한다 — 유형별 몫도 분 비중과 같다.
      cardioCal[d] = split[0] * 6;
      strengthCal[d] = split[1] * 6;
      stretchingCal[d] = split[2] * 6;
      calories[d] = fallback * 6;
      sets[d] = setsFromStrengthMinutes(split[1]);
    }
    return ClientExerciseWeek(
      dayLabels: const ['월', '화', '수', '목', '금', '토', '일'],
      dailyMinutes: minutes,
      dailyCalories: calories,
      cardioMinutes: cardio,
      strengthMinutes: strength,
      stretchingMinutes: stretching,
      cardioCalories: cardioCal,
      strengthCalories: strengthCal,
      stretchingCalories: stretchingCal,
      strengthSets: sets,
      totalMinutes: minutes.fold(0, (sum, value) => sum + value),
      totalCalories: calories.fold(0, (sum, value) => sum + value),
      weeklyGoalMinutes: goals.minutes,
      weeklyGoalCalories: goals.calories,
      streakDays: _longestStreak(minutes),
    );
  }

  /// 회원의 주간 운동 목표 — 서버 `exercise_service.weekly_goals` 와 같은
  /// 순서다(#2667). 운동 시간은 저장된 목표, 없으면 150분. 소모 칼로리는 저장된
  /// 주간 목표, 없으면 회원 앱·운동 현황 도넛과 같은 **하루 목표 × 7** 이다.
  ///
  /// 예전에는 운동 시간 목표를 싣지 않아(0) 목표선이 없었고, 칼로리 목표는 회원이
  /// 정한 하루 소모 목표 대신 공통 상수였다.
  Future<_ExerciseGoals> _exerciseGoals(String clientId) async {
    final String? raw = await _db.readValue('member_health_profile:$clientId');
    final Map<String, Object?> saved = raw == null
        ? const <String, Object?>{}
        : jsonDecode(raw) as Map<String, Object?>;
    final int? minutes = (saved['weekly_exercise_minutes_goal'] as num?)
        ?.toInt();
    final int? weeklyBurn = (saved['weekly_burn_goal'] as num?)?.toInt();
    final num? dailyBurn = saved['daily_burn_kcal'] as num?;
    return (
      minutes: minutes != null && minutes > 0 ? minutes : 150,
      calories: weeklyBurn != null && weeklyBurn > 0
          ? weeklyBurn
          : ((dailyBurn ?? kDailyBurnKcal) * 7).round(),
    );
  }

  /// '연속 N일' — 운동한 요일 중 가장 긴 연속 구간. 서버
  /// `exercise_service._longest_streak` 와 같은 정의로, 분이 있는 날만 센다.
  static int _longestStreak(List<int> dailyMinutes) {
    var best = 0;
    var run = 0;
    for (final int m in dailyMinutes) {
      run = m > 0 ? run + 1 : 0;
      if (run > best) best = run;
    }
    return best;
  }

  /// [monday] 주의 요일별(월→일) 한 운동. 하루 지표에 함께 담긴 목록이다 —
  /// 날짜별 기록(`fetchExercisesOn`)이 읽는 것과 같은 자료다.
  Future<List<List<ClientExerciseItem>>> _weekExercises(
    String clientId,
    DateTime monday,
  ) async {
    final List<List<ClientExerciseItem>> week = <List<ClientExerciseItem>>[
      for (var d = 0; d < 7; d++) <ClientExerciseItem>[],
    ];
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final rows =
        await (_db.select(_db.clientDailyMetrics)..where(
              (t) =>
                  t.clientId.equals(clientId) &
                  t.date.isBiggerOrEqualValue(ymd(monday)) &
                  t.date.isSmallerOrEqualValue(ymd(sunday)),
            ))
            .get();
    for (final ClientDailyMetricRow row in rows) {
      final int d = DateTime.parse(row.date).difference(monday).inDays;
      if (d < 0 || d > 6) continue;
      final Object? decoded = jsonDecode(row.exercisesJson);
      if (decoded is! List<Object?>) continue;
      for (final Object? item in decoded) {
        if (item is Map<String, Object?>) {
          week[d].add(ClientExerciseItem.fromJson(item));
        } else if (item is String) {
          week[d].add(ClientExerciseItem.fromLegacyLine(item));
        }
      }
    }
    return week;
  }

  /// 운동 한 줄의 분과 유형. 근력은 세트에서, 버티는 운동도 세트에서 센다.
  /// 유형이 적히지 않은 옛 문장은 이름으로 스트레칭을 가르고, 분만 있으면
  /// 유산소로 본다.
  static (int, _DemoKind) _demoMinutes(ClientExerciseItem item) {
    final _DemoKind kind = switch (item.type) {
      'strength' => _DemoKind.strength,
      'flexibility' || 'stretching' || 'yoga' => _DemoKind.stretching,
      'cardio' || 'walking' => _DemoKind.cardio,
      _ when item.sets != null => _DemoKind.strength,
      _ when _stretchName.hasMatch(item.name) => _DemoKind.stretching,
      _ => _DemoKind.cardio,
    };
    final int minutes = item.minutes > 0
        ? item.minutes
        : (item.sets != null
              ? (item.sets! * kStrengthMinutesPerSet).round()
              : 0);
    return (minutes, kind);
  }

  static final RegExp _stretchName = RegExp(
    '스트레칭|요가|가동|이완|stretch|yoga|mobility',
    caseSensitive: false,
  );

  /// [monday] 주의 요일별 이행률(월→일, 길이 7).
  ///
  /// 일별 지표(`clientDailyMetrics`)를 먼저 본다 — 시드가 12주치를 쌓아 두므로
  /// 지난 주도 그 주의 값으로 읽힌다. 행이 하나도 없는 주는, 그 주가 이번
  /// 주라면 로스터의 계열로 떨어진다(시드 이전 상태에서도 이번 주는 그려야
  /// 한다). 그 밖에는 전부 0 — 기록이 없는 주다.
  Future<List<int>> _weekCompletion(String clientId, DateTime monday) async {
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final rows =
        await (_db.select(_db.clientDailyMetrics)..where(
              (t) =>
                  t.clientId.equals(clientId) &
                  t.date.isBiggerOrEqualValue(ymd(monday)) &
                  t.date.isSmallerOrEqualValue(ymd(sunday)),
            ))
            .get();
    if (rows.isEmpty) {
      if (monday != clientMondayOf(nowKst())) {
        return List<int>.filled(7, 0);
      }
      final row = await (_db.select(
        _db.trainerClients,
      )..where((table) => table.id.equals(clientId))).getSingle();
      final week = (jsonDecode(row.weekCompletionJson) as List<Object?>)
          .map((value) => (value as num).toInt())
          .toList(growable: false);
      return <int>[for (var d = 0; d < 7; d++) d < week.length ? week[d] : 0];
    }
    final byDate = <String, ClientDailyMetricRow>{
      for (final row in rows) row.date: row,
    };
    return <int>[
      for (var d = 0; d < 7; d++)
        byDate[ymd(DateTime(monday.year, monday.month, monday.day + d))]
                ?.completion ??
            0,
    ];
  }

  @override
  Future<ClientDietAnalysis> fetchDietAdvice(
    String clientId,
    ClientPeriod period, {
    required Locale locale,
  }) async {
    // 데모는 서버 규칙(`diet_trainer_analysis`)을 옮긴 [todaySentences]·
    // [weekSentences]·[allSentences] 로 로컬 기록을 읽는다(#2379). 고정 문장을
    // 돌려주면 어느 고객을 열어도 같은 말을 해서 기간을 바꿔도 분석이 따라 바뀌는지
    // 볼 수 없다. 문장 키는 언어와 무관하다 — 화면이 ARB 로 그린다.
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DietRuleTargets targets = _dietTargets(
      await fetchHealthProfile(clientId),
    );
    switch (period) {
      case ClientPeriod.today:
        final List<DietRuleEntry> entries = await _dietRuleEntries(
          clientId,
          ymd(today),
          ymd(today),
        );
        final int protein = pyRound(
          entries.fold<num>(0, (num a, DietRuleEntry e) => a + e.proteinG),
        );
        int? avg;
        if (targets.proteinG - protein >= 10) {
          avg = _avgProtein(
            await _dietRuleEntries(
              clientId,
              daysBefore(today, allWindowDays - 1),
              ymd(today),
            ),
          );
        }
        return ClientDietAnalysis(
          todaySentences(entries, targets, now, avgProteinG: avg),
        );
      case ClientPeriod.week:
        final DateTime twoWeeks = DateTime(
          today.year,
          today.month,
          today.day - (today.weekday - 1) - 7,
        );
        return ClientDietAnalysis(
          weekSentences(
            await _dietRuleEntries(clientId, ymd(twoWeeks), ymd(today)),
            targets,
            now,
          ).sentences,
        );
      case ClientPeriod.month:
        return ClientDietAnalysis(
          allSentences(
            await _dietRuleEntries(
              clientId,
              daysBefore(today, allWindowDays - 1),
              ymd(today),
            ),
            targets,
            today,
          ).sentences,
        );
    }
  }

  /// 회원 목표 → 규칙이 쓰는 하루 목표. 서버 `diet_coach_inputs.targets_of` 와 같은
  /// 순서(목표 → 체중 × 1.2g → 60g)다 — 영양 요약 카드와 같은 분모다(#2898).
  DietRuleTargets _dietTargets(MemberHealthProfile p) => (
    calories: p.dailyCalories ?? 2000,
    proteinG: p.effectiveDailyProteinG,
    sodiumMg: p.dailySodiumMg ?? sodiumTargetMg,
    sugarG: p.dailySugarG ?? sugarTargetG,
  );

  /// 기록이 있는 날의 하루 평균 단백질 — 서버 `digest` 와 같다. 기록이 없으면 null.
  int? _avgProtein(List<DietRuleEntry> entries) {
    final Map<String, num> perDay = <String, num>{};
    for (final DietRuleEntry e in entries) {
      perDay[e.date] = (perDay[e.date] ?? 0) + e.proteinG;
    }
    if (perDay.isEmpty) return null;
    return pyRound(
      perDay.values.fold<num>(0, (num a, num b) => a + b) / perDay.length,
    );
  }

  /// [from]…[to] 의 끼니를 규칙이 읽는 모양으로.
  Future<List<DietRuleEntry>> _dietRuleEntries(
    String clientId,
    String from,
    String to,
  ) async {
    final List<ClientDietEntryRow> rows =
        await (_db.select(_db.clientDietEntries)
              ..where((t) => t.clientId.equals(clientId))
              ..where((t) => t.date.isBiggerOrEqualValue(from))
              ..where((t) => t.date.isSmallerOrEqualValue(to))
              ..orderBy(<OrderingTerm Function($ClientDietEntriesTable)>[
                (t) => OrderingTerm(expression: t.date),
                (t) => OrderingTerm(expression: t.sortOrder),
              ]))
            .get();
    return <DietRuleEntry>[
      for (final ClientDietEntryRow row in rows)
        _dietRuleEntry(row.date, _toDietEntry(row)),
    ];
  }

  DietRuleEntry _dietRuleEntry(String date, ClientDietEntry e) => DietRuleEntry(
    date: date,
    slot: switch (e.meal) {
      '아침' => 'breakfast',
      '점심' => 'lunch',
      '저녁' => 'dinner',
      '야식' => 'lateNight',
      _ => 'snack',
    },
    foods: <DietRuleFood>[
      for (final ClientDietFood f in e.foods)
        DietRuleFood(
          f.name,
          calories: f.calories,
          sodiumMg: f.sodiumMg,
          sugarG: f.sugarG,
        ),
    ],
    calories: e.calories,
    proteinG: e.proteinG,
    sodiumMg: e.sodiumMg,
    sugarG: e.sugarG,
    carbsG: e.carbsG,
    fatG: e.fatG,
  );

  static String _demoPickKey(String clientId) => 'demo_diet_pick:$clientId';

  @override
  Future<ClientDietRecommendations> fetchDietRecommendations(
    String clientId, {
    required Locale locale,
  }) async {
    // 데모 후보는 회원별 4주 추천 메뉴 리스트([demoMenuPlanFor])다(#2667) — 실서버가
    // 회원마다 리스트를 따로 두는 것과 같다. 김민수는 회원 앱 데모가 다음 식사를
    // 고르는 공유 리스트([kDemoMenuPlan]) 그대로라, 두 앱이 같은 메뉴를 말한다.
    // 순서·해소는 서버(`diet_trainer_pick`)와 같은 규칙이다.
    final DateTime today = todayKst();
    final List<DietRuleEntry> recent = await _dietRuleEntries(
      clientId,
      daysBefore(today, allWindowDays - 1),
      ymd(today),
    );
    final DietRuleTargets targets = _dietTargets(
      await fetchHealthProfile(clientId),
    );
    final List<String> needs = _needsOf(recent, targets);
    final ClientDietPick? pick = await _demoPick(clientId, recent);
    final List<DemoPlanMenu> plan = demoMenuPlanFor(
      clientId,
      locale.languageCode,
    );
    final Set<String> days = <String>{
      for (final DietRuleEntry e in recent) e.date,
    };
    if (needs.isEmpty) {
      return ClientDietRecommendations(basisDays: days.length, pick: pick);
    }
    const List<String> tags = <String>[
      'protein_high',
      'sodium_low',
      'fiber_high',
      'calorie_low',
      'sugar_low',
      'calorie_high',
    ];
    final List<String> tagOrder = <String>[
      ...needs,
      for (final String t in tags)
        if (!needs.contains(t)) t,
    ];
    const List<String> slots = <String>[
      'breakfast',
      'lunch',
      'dinner',
      'snack',
    ];
    final List<DemoPlanMenu> menus = <DemoPlanMenu>[
      for (final DemoPlanMenu m in plan)
        if (pick == null || _norm(m.name) != _norm(pick.name)) m,
    ];
    final List<int> order = List<int>.generate(menus.length, (int i) => i)
      ..sort((int a, int b) {
        int rank(DemoPlanMenu m) =>
            tagOrder.indexOf(m.tag) * 10 + slots.indexOf(m.slot);
        final int byRank = rank(menus[a]).compareTo(rank(menus[b]));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    return ClientDietRecommendations(
      needs: needs,
      basisDays: days.length,
      pick: pick,
      candidates: <ClientDietCandidate>[
        for (final int i in order)
          ClientDietCandidate(
            slot: menus[i].slot,
            name: menus[i].name,
            tag: menus[i].tag,
            keyword: menus[i].keyword,
            urgent: needs.contains(menus[i].tag),
          ),
      ],
    );
  }

  @override
  Future<ClientDietRecommendations> confirmDietRecommendation(
    String clientId, {
    required String slot,
    required String name,
    required Locale locale,
  }) async {
    final List<DemoPlanMenu> plan = demoMenuPlanFor(
      clientId,
      locale.languageCode,
    );
    final DemoPlanMenu? menu = plan
        .where(
          (DemoPlanMenu m) => m.slot == slot && _norm(m.name) == _norm(name),
        )
        .firstOrNull;
    if (menu == null) {
      throw ArgumentError.value(name, 'name', '추천 후보에 없는 메뉴입니다.');
    }
    await _db.putValue(
      _demoPickKey(clientId),
      jsonEncode(<String, Object?>{
        'slot': menu.slot,
        'name': menu.name,
        'tag': menu.tag,
        'keyword': menu.keyword,
        'confirmed_at': nowKst().toIso8601String(),
      }),
    );
    return fetchDietRecommendations(clientId, locale: locale);
  }

  /// 데모 트레이너가 확정해 둔 추천. 확정한 날부터 그 메뉴를 기록했으면 해소다 —
  /// 데모 기록에는 시각이 없어 날로 본다.
  Future<ClientDietPick?> _demoPick(
    String clientId,
    List<DietRuleEntry> recent,
  ) async {
    final String? raw = await _db.readValue(_demoPickKey(clientId));
    if (raw == null) return null;
    final Map<String, Object?> saved = jsonDecode(raw) as Map<String, Object?>;
    final DateTime confirmedAt = DateTime.parse(
      saved['confirmed_at']! as String,
    );
    final String name = saved['name']! as String;
    final String since = ymd(confirmedAt);
    final DietRuleEntry? eaten = recent
        .where(
          (DietRuleEntry e) =>
              e.date.compareTo(since) >= 0 &&
              e.foodNames.any((String f) => _norm(f).contains(_norm(name))),
        )
        .firstOrNull;
    return ClientDietPick(
      slot: saved['slot']! as String,
      name: name,
      tag: saved['tag']! as String,
      keyword: (saved['keyword'] as String?) ?? '',
      resolved: eaten != null,
      confirmedAt: confirmedAt,
      resolvedAt: eaten == null ? null : DateTime.parse(eaten.date),
    );
  }

  /// 급한 태그 — 서버 `diet_menu_plan.needs_of` 와 같다(최근 4주 하루 평균 기준).
  List<String> _needsOf(List<DietRuleEntry> entries, DietRuleTargets t) {
    final Map<String, List<num>> perDay = <String, List<num>>{};
    for (final DietRuleEntry e in entries) {
      final List<num> d = perDay.putIfAbsent(e.date, () => <num>[0, 0, 0, 0]);
      d[0] += e.calories;
      d[1] += e.proteinG;
      d[2] += e.sodiumMg;
      d[3] += e.sugarG;
    }
    if (perDay.isEmpty) return const <String>[];
    int avg(int i) => pyRound(
      perDay.values.fold<num>(0, (num a, List<num> d) => a + d[i]) /
          perDay.length,
    );
    final int calories = avg(0),
        protein = avg(1),
        sodium = avg(2),
        sugar = avg(3);
    return <String>[
      if (sodium >= t.sodiumMg * 0.9) 'sodium_low',
      if (protein <= t.proteinG * 0.8) 'protein_high',
      if (calories >= t.calories * 1.1)
        'calorie_low'
      else if (calories <= t.calories * 0.7)
        'calorie_high',
      if (sugar >= t.sugarG * 0.9) 'sugar_low',
    ];
  }

  static String _norm(String name) =>
      name.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  @override
  Future<ClientRecordSpan> fetchRecordSpan(String clientId) async {
    // 데모의 기록은 두 곳에 있다 — 픽스처(시드 고객의 이력)와 drift(데모에서
    // 트레이너·회원이 남긴 것). 서버(`/records/span`)가 DB 한 곳을 보는 것과
    // 같은 답을 내려면 둘 다 봐야 한다. (#2079)
    DateTime? dietFirst;
    DateTime? exerciseFirst;
    void keepEarliest(DateTime date, {required bool diet}) {
      if (diet) {
        if (dietFirst == null || date.isBefore(dietFirst!)) dietFirst = date;
      } else {
        if (exerciseFirst == null || date.isBefore(exerciseFirst!)) {
          exerciseFirst = date;
        }
      }
    }

    if (clientId == _fixture.trainerClientId) {
      for (final FixtureDay day in _fixture.daysFor(nowKst())) {
        final DateTime? date = DateTime.tryParse(day.date);
        if (date == null) continue;
        if (day.meals.isNotEmpty) keepEarliest(date, diet: true);
        if (day.exercises.isNotEmpty) keepEarliest(date, diet: false);
      }
    }

    for (final ClientDietEntryRow row in await (_db.select(
      _db.clientDietEntries,
    )..where((t) => t.clientId.equals(clientId))).get()) {
      final DateTime? date = DateTime.tryParse(row.date);
      if (date != null) keepEarliest(date, diet: true);
    }
    for (final ClientDailyMetricRow row in await (_db.select(
      _db.clientDailyMetrics,
    )..where((t) => t.clientId.equals(clientId))).get()) {
      if (row.completion <= 0) continue;
      final DateTime? date = DateTime.tryParse(row.date);
      if (date != null) keepEarliest(date, diet: false);
    }

    return ClientRecordSpan(
      dietFirstDate: dietFirst,
      exerciseFirstDate: exerciseFirst,
    );
  }

  @override
  Future<ClientDietPeriod> fetchDietPeriod(
    String clientId,
    ClientDateRange range,
  ) async {
    final rows =
        await (_db.select(_db.clientDailyMetrics)..where(
              (t) =>
                  t.clientId.equals(clientId) &
                  t.date.isBiggerOrEqualValue(ymd(range.from)) &
                  t.date.isSmallerOrEqualValue(ymd(range.to)),
            ))
            .get();
    final byDate = <String, ClientDailyMetricRow>{
      for (final row in rows) row.date: row,
    };
    return ClientDietPeriod(
      range: range,
      days: <ClientDietDay>[
        for (final date in clientRangeDates(range))
          ClientDietDay(
            date: date,
            calories: byDate[ymd(date)]?.calories ?? 0,
            sodiumMg: byDate[ymd(date)]?.sodiumMg ?? 0,
            sugarG: byDate[ymd(date)]?.sugarG ?? 0,
            carbsG: byDate[ymd(date)]?.carbsG ?? 0,
            proteinG: byDate[ymd(date)]?.proteinG ?? 0,
            fatG: byDate[ymd(date)]?.fatG ?? 0,
          ),
      ],
    );
  }

  /// A client's meals for the 식단 sub-tab, in seeded order (아침 → 저녁).
  @override
  Stream<List<ClientDietEntry>> watchDiet(String clientId) {
    // 오늘 것만. 이 표는 이제 지난 날의 끼니도 담으므로(#1025), 거르지 않으면
    // 오늘 화면이 사흘치를 한 번에 늘어놓는다.
    final String todayYmd = ymd(nowKst());
    final query = _db.select(_db.clientDietEntries)
      ..where((t) => t.clientId.equals(clientId) & t.date.equals(todayYmd))
      ..orderBy(<OrderingTerm Function($ClientDietEntriesTable)>[
        (t) => OrderingTerm(expression: t.sortOrder),
      ]);
    return query.watch().map((rows) => rows.map(_toDietEntry).toList());
  }

  @override
  Future<List<ClientDietEntry>> fetchDietOn(
    String clientId,
    DateTime date,
  ) async {
    final query = _db.select(_db.clientDietEntries)
      ..where((t) => t.clientId.equals(clientId) & t.date.equals(ymd(date)))
      ..orderBy(<OrderingTerm Function($ClientDietEntriesTable)>[
        (t) => OrderingTerm(expression: t.sortOrder),
      ]);
    return (await query.get()).map(_toDietEntry).toList();
  }

  @override
  Future<List<ClientExerciseItem>> fetchExercisesOn(
    String clientId,
    DateTime date,
  ) async {
    // 데모는 하루 지표에 그날 한 운동을 함께 담아 둔다 — 기간 그래프가 읽는
    // 것과 같은 표라, 그래프의 분 수와 여기 종목이 같은 날을 말한다.
    final ClientDailyMetricRow? row =
        await (_db.select(_db.clientDailyMetrics)
              ..where((t) => t.clientId.equals(clientId))
              ..where((t) => t.date.equals(ymd(date))))
            .getSingleOrNull();
    if (row == null) return const <ClientExerciseItem>[];
    final Object? decoded = jsonDecode(row.exercisesJson);
    if (decoded is! List<Object?>) return const <ClientExerciseItem>[];
    return <ClientExerciseItem>[
      for (final Object? item in decoded)
        // 이름만 싣던 옛 시드도 읽는다 — 그때는 적힌 그대로 보여 준다.
        if (item is Map<String, Object?>)
          ClientExerciseItem.fromJson(item)
        else if (item is String)
          ClientExerciseItem.nameOnly(item),
    ];
  }

  ClientDietEntry _toDietEntry(ClientDietEntryRow row) => ClientDietEntry(
    id: row.id,
    meal: row.meal,
    items: row.items,
    calories: row.calories,
    sodiumMg: row.sodiumMg,
    timeLabel: row.timeLabel,
    foods: _dietFoods(row.foodsJson),
    sugarG: row.sugarG,
    carbsG: row.carbsG,
    proteinG: row.proteinG,
    fatG: row.fatG,
    photoAsset: row.photoAsset,
  );

  /// 시드가 넣어 둔 음식별 영양. 깨진 값은 없는 것으로 본다 — 끼니 카드는
  /// 그때 `items` 한 줄로 떨어져 예전과 같이 읽힌다. (#1166)
  static List<ClientDietFood> _dietFoods(String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! List<Object?>) return const <ClientDietFood>[];
    return <ClientDietFood>[
      for (final Object? food in decoded)
        if (food is Map<String, Object?>) ClientDietFood.fromJson(food),
    ];
  }

  /// A client's workout history for the 운동기록 sub-tab, newest first
  /// (seeded order).
  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) {
    final query = _db.select(_db.clientRoutineHistory)
      ..where((t) => t.clientId.equals(clientId))
      ..orderBy(<OrderingTerm Function($ClientRoutineHistoryTable)>[
        (t) => OrderingTerm(expression: t.sortOrder),
      ]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => RoutineHistoryEntry(
              id: row.id,
              dateLabel: row.dateLabel,
              label: row.label,
              completionRate: row.completionRate,
              exercises: clientExerciseItems(jsonDecode(row.exercisesJson)),
              clientFeedback: row.clientFeedback,
              trainerNote: row.trainerNote,
              completedAt: row.completedAt,
              // 데모는 이 기록이 붙는 날을 `completedAt` 으로 들고 있다. 날짜로
              // 넘겨 화면이 `9/27 (오늘)` 을 화면 언어로 그리게 한다(#2300).
              date: switch (row.completedAt) {
                final DateTime at => DateTime(at.year, at.month, at.day),
                null => null,
              },
            ),
          )
          .toList(),
    );
  }

  TrainerClient _toEntity(TrainerClientRow row, {bool registered = true}) =>
      trainerClientFromRow(row, registered: registered);
}

/// 데모 로스터 한 줄을 화면의 회원으로 옮긴다 — 리포트 저장소도 같은 변환을
/// 쓴다(#2669).
TrainerClient trainerClientFromRow(
  TrainerClientRow row, {
  bool registered = true,
}) {
  final week = (jsonDecode(row.weekCompletionJson) as List<Object?>)
      .map((e) => e as int)
      .toList();
  final sodiumWeek = (jsonDecode(row.sodiumWeekJson) as List<Object?>)
      // On web, JSON numbers can decode as double — `as int` would
      // throw, so normalise through num (review PR 247).
      .map((e) => (e as num).toInt())
      .toList();
  final caloriesWeek = (jsonDecode(row.caloriesWeekJson) as List<Object?>)
      .map((e) => (e as num).toInt())
      .toList();
  // 당류는 소수를 유지한다 — 반올림하면 식단 탭 수치와 어긋난다(#746).
  final sugarWeek = (jsonDecode(row.sugarWeekJson) as List<Object?>)
      .map((e) => (e as num).toDouble())
      .toList();
  return TrainerClient(
    id: row.id,
    name: row.name,
    avatar: row.avatar,
    goal: row.goal,
    lastMessage: row.lastMessage,
    lastTime: row.lastTime,
    active: row.active,
    registered: registered,
    calories: row.caloriesToday,
    sodiumMg: row.sodiumMg,
    sugarG: row.sugarG,
    carbsG: row.carbsG,
    proteinG: row.proteinG,
    fatG: row.fatG,
    lastRoutine: row.lastRoutine,
    weekCompletion: week,
    sodiumWeek: sodiumWeek,
    caloriesWeek: caloriesWeek,
    sugarWeek: sugarWeek,
    // 데모의 PT 관리 신호 — 서버 로스터와 같은 JSON 모양으로 저장한다(#2204).
    signals: clientSignalsFromJson(jsonDecode(row.signalsJson)),
    // 회원 ID로 연결한 고객만 채워진다 — 회원 본인의 실제 프로필 값이다.
    // 성별이 비어 있으면 예전 행을 위한 표시용 폴백(rosterGender)이 대신
    // 쓰이고, 나이가 비어 있으면 나이를 적지 않는다(#2744).
    gender: row.gender ?? '',
    age: row.age,
  );
}

/// Provides the [ClientRepository]: the real Dio-backed source against the
/// FastAPI backend, or the local drift source for demo / `USE_MOCK_API=true`.
final clientRepositoryProvider = Provider<ClientRepository>((ref) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) {
    return DriftClientRepository(ref.watch(appDatabaseProvider));
  }
  final repository = DioClientRepository(ref.watch(dioProvider));
  // 서버가 회원 데이터를 404 로 거절하면(담당 해제, #2281) 명단만 곧바로 다시
  // 읽는다. 명단에서 빠진 회원은 각 화면이 원래의 '찾을 수 없음' 상태로 보여 준다.
  final StreamSubscription<String> accessLost = ref
      .watch(clientAccessLostProvider)
      .stream
      .listen((_) => repository.refreshRoster());
  ref.onDispose(accessLost.cancel);
  return repository;
});

/// Streams the client list for the 고객 관리 tab.
final managedClientsProvider = StreamProvider.autoDispose<List<TrainerClient>>((
  ref,
) {
  keepAliveForAccount(ref);
  return ref.watch(clientRepositoryProvider).watchClients();
});

final clientsProvider = StreamProvider.autoDispose<List<TrainerClient>>((ref) {
  keepAliveForAccount(ref);
  return ref
      .watch(clientRepositoryProvider)
      .watchClients()
      .map((clients) => clients.where((client) => client.registered).toList());
});

/// Streams the coaching-priority ordering of the client list.
///
/// 주의 회원(PT 관리 신호) first, ties broken by the most recent chat. ONE
/// rule for both modes — the ordering lives in the pure
/// [prioritizeClients], and each source just supplies what it has (drift
/// has chat times, the real roster endpoint doesn't yet).
///
/// Derived from [clientsProvider] rather than issuing its own read, so a
/// screen watching both (the list + detail split) doesn't trigger two
/// `GET /trainer/clients` calls.
///
/// A plain `Provider<AsyncValue<…>>`, not a `StreamProvider`: re-wrapping
/// the roster in a stream meant the loading branch had to return an empty
/// stream, and an empty stream *completes* — the provider then sat in
/// `AsyncLoading` forever with nothing left to emit. Mapping the
/// `AsyncValue` keeps loading/error/data flowing through untouched.
final prioritizedClientsProvider =
    Provider.autoDispose<AsyncValue<List<TrainerClient>>>((ref) {
      final lastChat =
          ref.watch(lastChatAtProvider).valueOrNull ??
          const <String, DateTime>{};
      return ref
          .watch(clientsProvider)
          .whenData(
            (clients) => prioritizeClients(clients, lastChatAt: lastChat),
          );
    });

/// 마지막 메시지가 새로운 순으로 정렬된 로스터 — 메시지 탭 목록이 쓴다.
///
/// [prioritizedClientsProvider] 와 나뉘어 있는 이유: 두 화면이 서로 다른
/// 질문에 답한다. 고객 탭은 "누구를 먼저 챙길까"(주의 신호 우선), 메시지
/// 탭은 "방금 무슨 말이 오갔나"(최신순)다. 한 provider 를 돌려 쓰면 둘 중
/// 하나는 자기 화면과 맞지 않는 차례를 보게 된다.
final recentlyMessagedClientsProvider =
    Provider.autoDispose<AsyncValue<List<TrainerClient>>>((ref) {
      final lastChat =
          ref.watch(lastChatAtProvider).valueOrNull ??
          const <String, DateTime>{};
      return ref
          .watch(clientsProvider)
          .whenData(
            (clients) => sortByLatestMessage(clients, lastChatAt: lastChat),
          );
    });

/// Streams the last chat time per client (priority tiebreak).
final lastChatAtProvider = StreamProvider.autoDispose<Map<String, DateTime>>((
  ref,
) {
  keepAliveForAccount(ref);
  return ref.watch(clientRepositoryProvider).watchLastChatAt();
});

/// Today's booked-session count for the dashboard KPI ('오늘 예약').
///
/// Derived from [todayScheduleProvider] rather than the roster: the count is
/// a property of the schedule, and the dashboard already subscribes to that
/// stream, so composing here avoids a second request for the same data.
/// 공백 slots are placeholders, not bookings, so they don't count. 완료한
/// 세션은 **센다** — 오늘 잡혀 있던 일정이라는 사실은 끝나도 변하지 않는다.
/// 남은 일감을 세는 자리는 [todayPendingSessionCountProvider] 다(#860).
///
/// Stays an [AsyncValue] on purpose. When the schedule is loading or failed
/// there is no honest number to show, and `valueOrNull` is null — the UI
/// hides the badge instead of claiming "0명 예약", which would be wrong.
final todayReservationCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref
      .watch(todayScheduleProvider)
      .whenData(
        // 취소된 약속은 빠진다(#871) — 이 숫자는 "오늘 몇 건이 잡혀 있나" 이고,
        // 취소는 그 예약이 거두어졌다는 뜻이다. 노쇼는 센다: 자리는 그대로 잡혀
        // 있었고 회원이 오지 않았을 뿐이다.
        (sessions) => sessions.where((s) => !s.isGap && !s.isCancelled).length,
      );
});

/// 사이드바 스케줄 배지가 읽는 **아직 처리하지 않은** 오늘 세션 수. (#860)
///
/// [todayReservationCountProvider] 와 나뉘어 있는 이유: 두 자리가 서로 다른
/// 질문에 답한다. 대시보드 KPI '오늘 예약' 은 "오늘 몇 건이 잡혀 있나" 이므로
/// 끝난 수업도 세는 것이 맞다. 배지는 "여기 처리할 게 남았다" 는 신호라, 이미
/// 완료한 세션까지 세면 트레이너가 탭에 들어가 확인하고 나서야 남은 건이 더
/// 적다는 것을 알게 된다 — 그런 배지는 몇 번 겪고 나면 안 보게 된다.
///
/// 공백 슬롯은 예약이 아니고, 완료 세션은 할 일이 아니다. 따라서 예정만 센다.
///
/// [todayReservationCountProvider] 와 같은 이유로 [AsyncValue] 로 남는다 —
/// 스케줄을 못 읽으면 0 이 아니라 값 없음이고, 화면은 배지를 감춘다.
final todayPendingSessionCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref
      .watch(todayScheduleProvider)
      .whenData((sessions) => sessions.where((s) => s.isUpcoming).length);
});

/// Streams a client's meals for the 식단 sub-tab.
final clientDietProvider = StreamProvider.autoDispose
    .family<List<ClientDietEntry>, String>((ref, clientId) {
      keepAliveForAccount(ref);
      return ref.watch(clientRepositoryProvider).watchDiet(clientId);
    });

/// [clientDietAdviceProvider] 의 키 — 회원·기간과 **KST 오늘**(#2746).
///
/// 이 값은 계정 수명 동안 살아 있어, 날짜가 키에 없으면 자정을 넘겨 화면을
/// 켜 둔 트레이너에게 어제 기준 분석이 남았다. 오늘이 키에 들어 있으면 자정이
/// 지난 뒤 처음 그릴 때 새 키로 읽는다.
typedef ClientDietAdviceKey = ({
  String clientId,
  ClientPeriod period,
  DateTime day,
});

/// 지금(KST 오늘) 읽을 [ClientDietAdviceKey].
ClientDietAdviceKey clientDietAdviceKey(String clientId, ClientPeriod period) =>
    (clientId: clientId, period: period, day: todayKst());

/// [clientDietRecommendationsProvider] 의 키 — 회원과 KST 오늘(#2746).
typedef ClientDietRecommendationsKey = ({String clientId, DateTime day});

/// 지금(KST 오늘) 읽을 [ClientDietRecommendationsKey].
ClientDietRecommendationsKey clientDietRecommendationsKey(String clientId) =>
    (clientId: clientId, day: todayKst());

/// 회원 상세가 동기화 주기마다 식단 분석·추천을 다시 읽게 한다(#2746).
///
/// 두 값의 원천(`GET /trainer/clients/{id}/diet-advice`·`/diet-recommendations`)은
/// 규칙 문장과 저장된 후보를 읽기만 하고 AI 를 부르지 않는다 — 다시 불러도 비용이
/// 들거나 문장이 흔들리지 않는다. 다시 읽는 동안에는 이전 값을 그대로 그린다.
///
/// 키 하나가 아니라 family 전체를 무효로 한다. 자정을 넘긴 직후 화면이 듣고 있는
/// 것은 **어제** 키라, 오늘 키만 무효로 하면 아무도 다시 그리지 않는다. 전체를
/// 무효로 하면 듣고 있는 어제 키가 다시 읽히며 화면이 다시 그려지고, 그때 오늘
/// 키로 옮겨 간다. 듣는 쪽이 없는 키는 다음에 읽을 때까지 다시 부르지 않는다.
void refreshClientDietInsights(WidgetRef ref) {
  ref
    ..invalidate(clientDietAdviceProvider)
    ..invalidate(clientDietRecommendationsProvider);
}

/// 기간별 `식단 분석` 문장. (#1017, #2379)
///
/// 키에 KST 오늘이 들어 있다 — [clientDietAdviceKey] 로 만든다(#2746).
final clientDietAdviceProvider = FutureProvider.autoDispose
    .family<ClientDietAnalysis, ClientDietAdviceKey>((ref, key) async {
      keepAliveForAccount(ref);
      // 화면 언어가 바뀌면 다시 읽는다 — 조언 문장이 그 언어로 온다(#2299).
      final Locale locale = ref.watch(trainerResolvedLocaleProvider);
      return ref
          .watch(clientRepositoryProvider)
          .fetchDietAdvice(key.clientId, key.period, locale: locale);
    });

/// 회원에게 추천할 AI 식단 후보와 지금 확정한 추천. (#2379)
///
/// 확정하면 [ClientDietRecommendationsController.confirm] 이 이 값을 새 상태로 바꾼다.
/// 키에 KST 오늘이 들어 있다 — [clientDietRecommendationsKey] 로 만든다(#2746).
final clientDietRecommendationsProvider = FutureProvider.autoDispose
    .family<ClientDietRecommendations, ClientDietRecommendationsKey>((
      ref,
      key,
    ) async {
      keepAliveForAccount(ref);
      final Locale locale = ref.watch(trainerResolvedLocaleProvider);
      return ref
          .watch(clientRepositoryProvider)
          .fetchDietRecommendations(key.clientId, locale: locale);
    });

/// 추천 확정 — 저장한 뒤 후보·상태를 다시 읽는다. 실패는 호출한 쪽으로 던진다.
Future<void> confirmClientDietRecommendation(
  WidgetRef ref,
  String clientId,
  ClientDietCandidate candidate,
) async {
  final Locale locale = ref.read(trainerResolvedLocaleProvider);
  await ref
      .read(clientRepositoryProvider)
      .confirmDietRecommendation(
        clientId,
        slot: candidate.slot,
        name: candidate.name,
        locale: locale,
      );
  ref.invalidate(
    clientDietRecommendationsProvider(clientDietRecommendationsKey(clientId)),
  );
}

/// 한 고객이 [date] 에 먹은 끼니. 기간 뷰에서 펼친 날에만 읽는다(#1025).
///
/// `autoDispose` 다 — 날짜를 접으면 구독이 끝나고, 12주를 훑는 동안 읽은 날이
/// 메모리에 쌓이지 않는다.
final clientDietOnProvider = FutureProvider.autoDispose
    .family<List<ClientDietEntry>, ({String clientId, DateTime date})>((
      ref,
      key,
    ) async {
      return ref
          .watch(clientRepositoryProvider)
          .fetchDietOn(key.clientId, key.date);
    });

/// 한 고객이 [date] 에 한 운동들. 펼친 날에만 읽는다(#1025).
final clientExercisesOnProvider = FutureProvider.autoDispose
    .family<List<ClientExerciseItem>, ({String clientId, DateTime date})>((
      ref,
      key,
    ) async {
      return ref
          .watch(clientRepositoryProvider)
          .fetchExercisesOn(key.clientId, key.date);
    });

/// Streams a client's workout history for the 운동 sub-tab.
final clientHistoryProvider = StreamProvider.autoDispose
    .family<List<RoutineHistoryEntry>, String>((ref, clientId) {
      keepAliveForAccount(ref);
      return ref.watch(clientRepositoryProvider).watchHistory(clientId);
    });

final clientExerciseWeekProvider = FutureProvider.autoDispose
    .family<ClientExerciseWeek, String>((ref, clientId) {
      keepAliveForAccount(ref);
      return ref.watch(clientRepositoryProvider).fetchExerciseWeek(clientId);
    });

/// 고객 기간 조회의 조회 키 — 누구의, 어느 기간을, **어느 날 기준으로**.
///
/// [day] 가 키에 들어 있는 이유는 자정 때문이다. 범위를 provider 안에서
/// `nowKst()` 로 잡으면, 콘솔을 켜 둔 채 KST 자정을 넘겨도 같은 키의 캐시가
/// 어제 범위를 그대로 들고 있다 — 트레이너는 날이 바뀐 줄 모르고 어제의
/// `오늘` 을 본다. 날짜가 키의 일부면 다음 rebuild 에서 자연히 새 범위를 묻는다.
typedef ClientPeriodKey = ({
  String clientId,
  ClientPeriod period,
  DateTime day,
});

/// 지금(KST) 기준의 조회 키. 화면은 이 함수로 키를 만든다.
ClientPeriodKey clientPeriodKeyNow(String clientId, ClientPeriod period) =>
    (clientId: clientId, period: period, day: todayKst());

/// [ClientPeriodKey] 의 일별 식단 집계. (#914)
///
/// `autoDispose` 다 — 날이 바뀌면 어제 키는 아무도 보지 않게 되므로, 캐시가
/// 계속 쌓이지 않고 스스로 정리된다.
final clientDietPeriodProvider = FutureProvider.autoDispose
    .family<ClientDietPeriod, ClientPeriodKey>((ref, key) async {
      // `전체` 는 첫 기록일부터다(#2079). 아직 못 읽었으면 오늘 하루를 그리고,
      // 값이 오면 범위가 늘며 그래프가 다시 선다.
      final ClientRecordSpan span = await ref.watch(
        clientRecordSpanProvider(key.clientId).future,
      );
      return ref
          .watch(clientRepositoryProvider)
          .fetchDietPeriod(
            key.clientId,
            clientRangeFor(
              key.period,
              key.day,
              firstRecord: span.dietFirstDate,
            ),
          );
    });

/// 고객이 식단·운동을 처음 남긴 날. `전체` 그래프의 시작점이다(#2079, #2236).
///
/// 실패해도 그래프를 막지 않는다 — 값이 없으면 `전체` 가 오늘 하루(운동은 이번
/// 주)를 그린다.
final clientRecordSpanProvider = FutureProvider.autoDispose
    .family<ClientRecordSpan, String>((ref, clientId) async {
      try {
        return await ref
            .watch(clientRepositoryProvider)
            .fetchRecordSpan(clientId);
      } on Object {
        return ClientRecordSpan.empty;
      }
    });

/// [ClientPeriodKey] 의 일별 운동 집계. (#914)
///
/// 범위가 걸친 주를 각각 읽어 이어 붙인다 — 서버도 데모도 운동 이력을 주
/// 단위로 들고 있다. 한 주만 보는 경우에는 요청도 한 번이다.
final clientExercisePeriodProvider = FutureProvider.autoDispose
    .family<ClientExercisePeriod, ClientPeriodKey>((ref, key) async {
      final repository = ref.watch(clientRepositoryProvider);
      final ClientRecordSpan span = await ref.watch(
        clientRecordSpanProvider(key.clientId).future,
      );
      final ClientDateRange range = clientRangeFor(
        key.period,
        key.day,
        exercise: true,
        firstRecord: span.exerciseFirstDate,
      );
      final Map<String, ClientExerciseDay> byDate =
          <String, ClientExerciseDay>{};
      // 목표는 주마다 같다 — 마지막으로 읽은 주의 값을 쓴다. (#1015)
      int weeklyGoalMinutes = 0;
      int weeklyGoalCalories = 0;
      // 연속 일수도 마지막(가장 최근) 주의 값이 남는다 — 이 값을 읽는 곳은
      // `이번 주` 하나다. (#2195)
      int streakDays = 0;
      // 기간을 **한 번에** 읽는다 (#2247). `전체` 는 기록만큼 길어지므로, 주마다
      // 부르면 왕복이 그만큼 줄줄이 이어져 그래프가 늦게 선다.
      final List<ClientExercisePeriodWeek> weeks = await repository
          .fetchExercisePeriod(key.clientId, range);
      for (int w = 0; w < weeks.length; w++) {
        final DateTime monday = weeks[w].weekStart;
        final ClientExerciseWeek week = weeks[w].week;
        weeklyGoalMinutes = week.weeklyGoalMinutes;
        weeklyGoalCalories = week.weeklyGoalCalories;
        streakDays = week.streakDays;
        for (var d = 0; d < 7; d++) {
          final DateTime date = DateTime(
            monday.year,
            monday.month,
            monday.day + d,
          );
          // 유형 배열도 분·칼로리와 **같이 인덱스를 확인한다.** hasTypeSplit 은
          // 셋의 길이가 서로 같은지만 보는데, 이 루프는 언제나 7일을 돈다 —
          // 길이 2짜리 응답은 분해로 인정되면서 d == 2 에서 범위를 넘는다.
          int at(List<int> xs) => d < xs.length ? xs[d] : 0;
          byDate[ymd(date)] = ClientExerciseDay(
            date: date,
            minutes: at(week.dailyMinutes),
            calories: at(week.dailyCalories),
            cardioMinutes: at(week.cardioMinutes),
            strengthMinutes: at(week.strengthMinutes),
            stretchingMinutes: at(week.stretchingMinutes),
            otherMinutes: at(week.otherMinutes),
            cardioCalories: at(week.cardioCalories),
            strengthCalories: at(week.strengthCalories),
            stretchingCalories: at(week.stretchingCalories),
            otherCalories: at(week.otherCalories),
            // 서버가 세트를 주면 그 값, 아니면 분에서 환산한다.
            strengthSets: d < week.strengthSets.length
                ? week.strengthSets[d]
                : setsFromStrengthMinutes(at(week.strengthMinutes)),
            // 분해가 실려 왔는지는 **응답이 말한다**(#2195) — 값으로 되짚으면
            // 네 유형이 모두 0 인 날이 분해 없는 날로 읽힌다.
            typeSplitFromPayload: week.hasTypeSplit,
          );
        }
      }
      return ClientExercisePeriod(
        weeklyGoalMinutes: weeklyGoalMinutes,
        weeklyGoalCalories: weeklyGoalCalories,
        streakDays: streakDays,
        range: range,
        days: <ClientExerciseDay>[
          for (final DateTime date in clientRangeDates(range))
            byDate[ymd(date)] ?? ClientExerciseDay(date: date),
        ],
      );
    });

/// 데모 회원의 주간 운동 목표 — 운동 시간(분)·소모 칼로리. (#2667)
typedef _ExerciseGoals = ({int minutes, int calories});

/// 데모 운동 현황이 세는 유형과 분당 소모 칼로리(#2667). 실서버는 운동마다
/// 소모량을 기록하지만 데모 루틴에는 없어, 유형별 대략값으로 센다 — 유형마다
/// 분당 소모가 달라야 칼로리 비중이 분 비중과 갈린다(#1289).
enum _DemoKind {
  cardio(7),
  strength(6),
  stretching(3);

  const _DemoKind(this.kcalPerMinute);

  final int kcalPerMinute;
}
