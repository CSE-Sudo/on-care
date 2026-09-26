import 'dart:convert';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/data/dtos/client_dtos.dart'
    show
        prioritizeClients,
        sortByLatestMessage,
        clientExerciseItems,
        clientSignalsFromJson;
import 'package:oncare_trainer/features/clients/data/repositories/dio_client_repository.dart';
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
  Future<RoutineHistoryEntry> updateHistoryFeedback(
    String clientId,
    String historyId,
    String feedback,
  );
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
  /// 기간에 맞는 식단 조언. 회원 앱과 **같은 문장**이다 — 같은 회원의 같은
  /// 기간을 두 화면이 다르게 말하면 상담에서 둘이 다른 이야기를 들고 앉는다.
  /// (#1017)
  Future<String> fetchDietAdvice(String clientId, ClientPeriod period);

  /// 기간에 맞는 운동 조언. 식단(#1017)과 같은 규칙으로 서버가 만든다. (#1025)
  Future<String> fetchExerciseAdvice(String clientId, ClientPeriod period);

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
  Future<RoutineHistoryEntry> updateHistoryFeedback(
    String clientId,
    String historyId,
    String feedback,
  ) => throw UnsupportedError(
    'Assigned-routine feedback is available from the backend only.',
  );

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
              lastMessage: '아직 대화가 없어요',
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
      goals: saved['goals'] as String? ?? row.goal,
      // 데모에서 트레이너가 목표를 바꾼 기록 — 실서버와 같은 줄을 그린다(#1832).
      focusChangedBy: saved['focus_changed_by'] as String?,
      focusChangedAt: switch (saved['focus_changed_at']) {
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
      'goals': value('goals', current.goals),
      'weekly_workout_goal': value(
        'weekly_workout_goal',
        current.weeklyWorkoutGoal,
      ),
      'weekly_exercise_minutes_goal': value(
        'weekly_exercise_minutes_goal',
        current.weeklyExerciseMinutesGoal,
      ),
      'weekly_burn_goal': value('weekly_burn_goal', current.weeklyBurnGoal),
      'focus_changed_by': current.focusChangedBy,
      'focus_changed_at': current.focusChangedAt?.toIso8601String(),
    };
    // 목표 칩이 실제로 바뀐 저장만 `마지막 변경` 으로 남긴다 — 실서버와 같은
    // 규칙이다(#1832). 주의사항 글·수치만 고친 저장은 목표 변경이 아니다.
    final Set<String> before = parseHealthFocus(current.conditions);
    final Set<String> after = parseHealthFocus(saved['conditions'] as String);
    if (before.length != after.length || !before.containsAll(after)) {
      saved['focus_changed_by'] = MemberHealthProfile.focusChangedByTrainer;
      saved['focus_changed_at'] = nowKst().toIso8601String();
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
  ClientExerciseWeek? _fixtureWeek(String clientId, DateTime monday) {
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
      weeklyGoalCalories: kWeeklyBurnKcal.round(),
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
    final ClientExerciseWeek? fromFixture = _fixtureWeek(clientId, monday);
    if (fromFixture != null) return fromFixture;
    final completion = await _weekCompletion(clientId, monday);
    final minutes = completion
        .map(_minutesFromCompletion)
        .toList(growable: false);
    final calories = minutes.map((value) => value * 6).toList(growable: false);
    final splits = <List<int>>[
      for (var d = 0; d < minutes.length; d++) _typeSplit(minutes[d], d),
    ];
    return ClientExerciseWeek(
      dayLabels: const ['월', '화', '수', '목', '금', '토', '일'],
      dailyMinutes: minutes,
      dailyCalories: calories,
      cardioMinutes: <int>[for (final s in splits) s[0]],
      strengthMinutes: <int>[for (final s in splits) s[1]],
      stretchingMinutes: <int>[for (final s in splits) s[2]],
      // 데모의 칼로리는 분에 일정 배수를 곱한 값이라(위 `* 6`), 유형별 몫도 분
      // 비중과 같다. 실서버는 유형마다 분당 소모가 달라 `sessions` 에서 따로
      // 세지만(#1289), 여기서는 그 환산이 곧 같은 결과다.
      cardioCalories: <int>[for (final s in splits) s[0] * 6],
      strengthCalories: <int>[for (final s in splits) s[1] * 6],
      stretchingCalories: <int>[for (final s in splits) s[2] * 6],
      totalMinutes: minutes.fold(0, (sum, value) => sum + value),
      totalCalories: calories.fold(0, (sum, value) => sum + value),
      weeklyGoalCalories: kWeeklyBurnKcal.round(),
    );
  }

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
  Future<String> fetchDietAdvice(String clientId, ClientPeriod period) async {
    // 데모는 서버 규칙(`diet_service.period_coach_message`)을 로컬 데이터로
    // 흉내 낸다. 고정 문장을 돌려주면 어느 고객을 열어도 같은 말을 해서,
    // 기간을 바꿨을 때 조언이 따라 바뀌는지도 볼 수 없다. (#1017)
    if (period == ClientPeriod.today) {
      // 오늘 것만 합친다. 이 표는 이제 지난 날의 끼니도 담으므로(#1025),
      // 거르지 않으면 여러 달치 나트륨을 오늘 하루로 말하게 된다.
      final entries =
          await (_db.select(_db.clientDietEntries)
                ..where((t) => t.clientId.equals(clientId))
                ..where((t) => t.date.equals(ymd(nowKst()))))
              .get();
      final int sodium = entries.fold<int>(
        0,
        (int sum, ClientDietEntryRow row) => sum + row.sodiumMg,
      );
      return sodium > sodiumTargetMg
          ? '나트륨이 목표치를 ${sodium - sodiumTargetMg}mg 초과했어요. '
                '오늘 운동 프로그램에 유산소를 추가하면 도움이 돼요.'
          : '오늘 식단은 균형이 잘 맞아요. 현재 프로그램을 유지하세요.';
    }

    // 조언이 읽는 기간은 그래프와 다르다(#2079) — 그래프는 모든 기록을
    // 그리지만 조언은 최근 [kAdvicePeriodDays] 일이다. 서버
    // (`period_window.ALL_PERIOD_DAYS`)와 같은 창이다.
    final DateTime today = todayKst();
    final ClientDietPeriod window = await fetchDietPeriod(
      clientId,
      period == ClientPeriod.week
          ? clientRangeNow(period)
          : (
              from: DateTime(
                today.year,
                today.month,
                today.day - kAdvicePeriodDays + 1,
              ),
              to: today,
            ),
    );
    final List<ClientDietDay> logged = window.days
        .where((ClientDietDay day) => day.calories > 0)
        .toList();
    if (logged.isEmpty) {
      return period == ClientPeriod.week
          ? '이번 주 식단 기록이 아직 없어요. 한 끼만 남겨도 흐름이 보여요.'
          : '기록이 쌓이면 나트륨·칼로리 흐름을 짚어 드릴게요.';
    }
    final int over = logged
        .where((ClientDietDay day) => day.sodiumMg > sodiumTargetMg)
        .length;
    final bool weekendHeavy = _weekendRuns(logged);
    if (period == ClientPeriod.week) {
      if (over >= 3) {
        return '이번 주 $over일이나 나트륨을 넘겼어요. 국물은 건더기 위주로 드세요.';
      }
      if (weekendHeavy) {
        return '주중엔 잘 지키다 주말에 나트륨이 올라요. 주말 외식은 한 끼만 정해요.';
      }
      if (over > 0) {
        return '이번 주 $over일만 권장량을 넘었어요. 나머지 날의 균형은 좋았어요.';
      }
      return '이번 주 ${logged.length}일 모두 나트륨을 권장량 안에서 지켰어요!';
    }
    // 읽은 기간을 문구가 밝힌다 (#2079). `전체` 그래프는 모든 기록을 그리지만
    // 이 조언은 최근 12주만 읽는다 — "기록을 통틀어" 라고 말하면 그래프가
    // 보여 주는 앞 기록까지 본 것처럼 읽힌다. 서버
    // (`diet_service.period_coach_message`)와 같은 문구다.
    const int adviceWeeks = kAdvicePeriodDays ~/ 7;
    if (weekendHeavy) {
      return '최근 $adviceWeeks주 주말마다 나트륨이 올라요. 주말 한 끼만 담백하게 바꿔요.';
    }
    if (over * 10 >= logged.length * 4) {
      return '최근 $adviceWeeks주 중 ${(over * 100 / logged.length).round()}%가 '
          '나트륨 권장량을 넘었어요. 국물부터 남겨 봐요.';
    }
    return '최근 $adviceWeeks주 기록한 ${logged.length}일 대부분이 권장량 안이에요. '
        '지금 흐름이 좋아요.';
  }

  @override
  Future<String> fetchExerciseAdvice(
    String clientId,
    ClientPeriod period,
  ) async {
    // 데모도 서버 규칙(`exercise_service.period_coach_message`)을 로컬 데이터로
    // 흉내 낸다 — 고정 문장이면 기간을 바꿔도 조언이 그대로라, 이 화면이 무엇을
    // 하는지 데모에서 보이지 않는다. (#1025)
    final ClientExercisePeriod window = await _exercisePeriod(clientId, period);
    // 기록이 없는 날은 0 으로 채워져 온다. 쉰 날과 적지 않은 날을 갈라 세려면
    // 여기서 걸러야 서버(`daily_totals`)와 같은 수를 센다.
    final List<ClientExerciseDay> logged = window.days
        .where((ClientExerciseDay day) => day.minutes > 0)
        .toList();
    if (logged.isEmpty) {
      return switch (period) {
        ClientPeriod.week => '이번 주 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?',
        ClientPeriod.month => '기록이 쌓이면 운동량과 유형의 흐름을 짚어 드릴게요.',
        ClientPeriod.today => '오늘 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?',
      };
    }

    if (period == ClientPeriod.today) {
      final ClientExerciseDay day = logged.last;
      return '오늘 ${_mainTypeLabel(day)} 위주로 ${day.minutes}분, '
          '${day.calories}kcal 썼어요. 스트레칭으로 마무리해요.';
    }

    final int totalMinutes = logged.fold<int>(
      0,
      (int sum, ClientExerciseDay day) => sum + day.minutes,
    );
    if (period == ClientPeriod.week) {
      if (logged.length <= 1) {
        return '이번 주는 $totalMinutes분 하루뿐이에요. 한 번 더 나가면 흐름이 이어져요.';
      }
      final int cardio = logged.fold<int>(
        0,
        (int s, ClientExerciseDay d) => s + d.cardioMinutes,
      );
      final int strength = logged.fold<int>(
        0,
        (int s, ClientExerciseDay d) => s + d.strengthMinutes,
      );
      // 서버와 같은 8할 기준 — 한 유형에 쏠렸는지가 코칭의 첫 질문이다.
      if (totalMinutes > 0 && cardio * 10 >= totalMinutes * 8) {
        return '이번 주 ${logged.length}일 $totalMinutes분이 유산소에 몰렸어요. '
            '근력도 섞어 볼까요?';
      }
      if (totalMinutes > 0 && strength * 10 >= totalMinutes * 8) {
        return '이번 주 ${logged.length}일 $totalMinutes분이 근력에 몰렸어요. '
            '유산소도 섞어 볼까요?';
      }
      return '이번 주 ${logged.length}일 $totalMinutes분, 유형도 고르게 섞였어요.';
    }

    // 전체 — 최근 4주와 그 이전을 견준다.
    final DateTime recentFrom = logged.last.date.subtract(
      const Duration(days: 27),
    );
    final List<int> recent = <int>[
      for (final ClientExerciseDay d in logged)
        if (!d.date.isBefore(recentFrom)) d.minutes,
    ];
    final List<int> earlier = <int>[
      for (final ClientExerciseDay d in logged)
        if (d.date.isBefore(recentFrom)) d.minutes,
    ];
    double mean(List<int> xs) =>
        xs.isEmpty ? 0 : xs.fold<int>(0, (int a, int b) => a + b) / xs.length;
    if (recent.isNotEmpty && earlier.isNotEmpty) {
      if (mean(recent) > mean(earlier) * 1.1) {
        return '최근 4주 운동량이 그 전보다 늘었어요. 지금 방식이 잘 맞아요.';
      }
      if (mean(recent) < mean(earlier) * 0.9) {
        return '최근 4주 운동량이 줄고 있어요. 짧게라도 주 3일을 지켜 봐요.';
      }
    }
    return '12주 동안 ${logged.length}일 $totalMinutes분, 기복 없이 이어가고 있어요.';
  }

  /// [period] 가 덮는 구간의 일별 운동 집계.
  ///
  /// 운동 이력은 서버도 데모도 **주 단위**라, 구간이 걸친 주를 각각 읽어 이어
  /// 붙인다. `clientExercisePeriodProvider` 가 화면을 위해 하는 일과 같은데,
  /// 조언은 위젯 없이도 같은 수를 세야 해서 여기에 한 벌 더 둔다.
  Future<ClientExercisePeriod> _exercisePeriod(
    String clientId,
    ClientPeriod period,
  ) async {
    final ClientDateRange range = clientRangeNow(period, exercise: true);
    final Map<String, ClientExerciseDay> byDate = <String, ClientExerciseDay>{};
    int weeklyGoalMinutes = 0;
    int weeklyGoalCalories = 0;
    // 주를 한꺼번에 읽는다 — 위 provider 와 같은 이유다 (#1170).
    final List<DateTime> mondays = clientRangeWeekStarts(range);
    final List<ClientExerciseWeek> weeks =
        await Future.wait(<Future<ClientExerciseWeek>>[
          for (final DateTime monday in mondays)
            fetchExerciseWeek(clientId, weekStart: monday),
        ]);
    for (int w = 0; w < mondays.length; w++) {
      final DateTime monday = mondays[w];
      final ClientExerciseWeek week = weeks[w];
      weeklyGoalMinutes = week.weeklyGoalMinutes;
      weeklyGoalCalories = week.weeklyGoalCalories;
      for (var d = 0; d < 7; d++) {
        final DateTime date = DateTime(
          monday.year,
          monday.month,
          monday.day + d,
        );
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
        );
      }
    }
    return ClientExercisePeriod(
      weeklyGoalMinutes: weeklyGoalMinutes,
      weeklyGoalCalories: weeklyGoalCalories,
      range: range,
      days: <ClientExerciseDay>[
        for (final DateTime date in clientRangeDates(range))
          byDate[ymd(date)] ?? ClientExerciseDay(date: date),
      ],
    );
  }

  /// 그날 가장 오래 한 유형의 이름. 같으면 유산소 → 근력 → 스트레칭 순이다.
  String _mainTypeLabel(ClientExerciseDay day) {
    final Map<String, int> byType = <String, int>{
      '유산소': day.cardioMinutes,
      '근력': day.strengthMinutes,
      '스트레칭': day.stretchingMinutes,
      '기타': day.otherMinutes,
    };
    String best = '유산소';
    int bestMinutes = -1;
    for (final MapEntry<String, int> e in byType.entries) {
      if (e.value > bestMinutes) {
        best = e.key;
        bestMinutes = e.value;
      }
    }
    return best;
  }

  /// 주말(토·일) 평균이 평일보다 뚜렷하게 높은지 — 서버와 같은 1.3배 기준.
  bool _weekendRuns(List<ClientDietDay> days) {
    final List<int> weekend = <int>[
      for (final ClientDietDay day in days)
        if (day.date.weekday >= DateTime.saturday) day.sodiumMg,
    ];
    final List<int> weekday = <int>[
      for (final ClientDietDay day in days)
        if (day.date.weekday < DateTime.saturday) day.sodiumMg,
    ];
    if (weekend.isEmpty || weekday.isEmpty) return false;
    double mean(List<int> xs) =>
        xs.fold<int>(0, (int a, int b) => a + b) / xs.length;
    return mean(weekend) > mean(weekday) * 1.3;
  }

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
            ),
          )
          .toList(),
    );
  }

  TrainerClient _toEntity(TrainerClientRow row, {bool registered = true}) {
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
      // 비어 있으면 예전 행을 위한 표시용 폴백(rosterGender/rosterAge)이
      // 대신 쓰인다.
      gender: row.gender ?? '',
      age: row.age,
    );
  }
}

/// Provides the [ClientRepository]: the real Dio-backed source against the
/// FastAPI backend, or the local drift source for demo / `USE_MOCK_API=true`.
final clientRepositoryProvider = Provider<ClientRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) {
    return DriftClientRepository(ref.watch(appDatabaseProvider));
  }
  return DioClientRepository(ref.watch(dioProvider));
});

/// Streams the client list for the 고객 관리 tab.
final managedClientsProvider = StreamProvider<List<TrainerClient>>((ref) {
  return ref.watch(clientRepositoryProvider).watchClients();
});

final clientsProvider = StreamProvider<List<TrainerClient>>((ref) {
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
final prioritizedClientsProvider = Provider<AsyncValue<List<TrainerClient>>>((
  ref,
) {
  final lastChat =
      ref.watch(lastChatAtProvider).valueOrNull ?? const <String, DateTime>{};
  return ref
      .watch(clientsProvider)
      .whenData((clients) => prioritizeClients(clients, lastChatAt: lastChat));
});

/// 마지막 메시지가 새로운 순으로 정렬된 로스터 — 메시지 탭 목록이 쓴다.
///
/// [prioritizedClientsProvider] 와 나뉘어 있는 이유: 두 화면이 서로 다른
/// 질문에 답한다. 고객 탭은 "누구를 먼저 챙길까"(주의 신호 우선), 메시지
/// 탭은 "방금 무슨 말이 오갔나"(최신순)다. 한 provider 를 돌려 쓰면 둘 중
/// 하나는 자기 화면과 맞지 않는 차례를 보게 된다.
final recentlyMessagedClientsProvider =
    Provider<AsyncValue<List<TrainerClient>>>((ref) {
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
final lastChatAtProvider = StreamProvider<Map<String, DateTime>>((ref) {
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
final clientDietProvider = StreamProvider.family<List<ClientDietEntry>, String>(
  (ref, clientId) {
    return ref.watch(clientRepositoryProvider).watchDiet(clientId);
  },
);

/// 기간별 식단 조언. 회원 앱 `dietAdviceProvider` 와 같은 서버 문장이다. (#1017)
final clientDietAdviceProvider =
    FutureProvider.family<String, ({String clientId, ClientPeriod period})>((
      ref,
      key,
    ) async {
      return ref
          .watch(clientRepositoryProvider)
          .fetchDietAdvice(key.clientId, key.period);
    });

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

/// 기간에 맞는 운동 조언. 식단(`clientDietAdviceProvider`)과 같은 모양이다.
/// (#1025)
final clientExerciseAdviceProvider =
    FutureProvider.family<String, ({String clientId, ClientPeriod period})>((
      ref,
      key,
    ) async {
      return ref
          .watch(clientRepositoryProvider)
          .fetchExerciseAdvice(key.clientId, key.period);
    });

/// Streams a client's workout history for the 운동 sub-tab.
final clientHistoryProvider =
    StreamProvider.family<List<RoutineHistoryEntry>, String>((ref, clientId) {
      return ref.watch(clientRepositoryProvider).watchHistory(clientId);
    });

final clientExerciseWeekProvider =
    FutureProvider.family<ClientExerciseWeek, String>((ref, clientId) {
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
