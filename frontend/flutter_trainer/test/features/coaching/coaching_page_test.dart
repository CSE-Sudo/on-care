import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/design_system/tokens/typography.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart'
    show trainerAuthRepositoryProvider;
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_exercise_status_card.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/ai_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/ai_routine_item.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/features/coaching/presentation/pages/ai_routine_options_flow.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_editor_workspace.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_nutrition_summary_card.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_suggestion_review_card.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/action_button.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';
import 'package:oncare_trainer/shared/widgets/mini_charts.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// A chat repository whose sends always fail.
class _FailingChatRepository extends DriftChatRepository {
  const _FailingChatRepository(super.db);

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
  }) async => throw Exception('chat write failed');
}

/// A chat repository whose sends resolve slowly, so a client switch can
/// land while a send is still in flight (review PR 239).
class _SlowChatRepository extends DriftChatRepository {
  const _SlowChatRepository(super.db);

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return super.sendTrainerMessage(
      clientId: clientId,
      text: text,
      reportWeekStart: reportWeekStart,
    );
  }
}

/// Counts registration calls and delays them, to test the in-flight
/// double-tap guard.
class _SlowCountingScheduleRepository extends DriftScheduleRepository {
  _SlowCountingScheduleRepository(
    super.db, {
    this.delay = const Duration(seconds: 5),
  });

  /// 이 write 를 붙잡아 두는 시간. 프로그램 탭이 길어질수록(#1028: AI 요청
  /// 흐름이 편집기 위에 항상 있다) 같은 화면 안에서 여러 번 스크롤해야 하는
  /// 테스트는 그 스크롤이 소비하는 가상 시계도 감안해야 한다 — 기본값보다
  /// 긴 지연이 필요하면 이 값을 올린다.
  final Duration delay;

  int registerCalls = 0;

  @override
  Future<bool> registerProgram({
    required String date,
    required String clientId,
    required String clientName,
    required String time,
    required int durationMinutes,
    required List<ProgramItem> program,
  }) async {
    registerCalls++;
    // Keep the write in flight across client-switching/scroll animations.
    await Future<void>.delayed(delay);
    return super.registerProgram(
      date: date,
      clientId: clientId,
      clientName: clientName,
      time: time,
      durationMinutes: durationMinutes,
      program: program,
    );
  }
}

/// Captures the schedule operation selected by the coaching page without
/// performing a local write. Dio behavior is covered by its repository test.
class _CapturingScheduleRepository extends DriftScheduleRepository {
  _CapturingScheduleRepository(super.db);

  int registerCalls = 0;
  String? clientId;
  String? time;
  int? durationMinutes;
  List<ProgramItem>? program;

  @override
  Future<bool> registerProgram({
    required String date,
    required String clientId,
    required String clientName,
    required String time,
    required int durationMinutes,
    required List<ProgramItem> program,
  }) async {
    registerCalls++;
    this.clientId = clientId;
    this.time = time;
    this.durationMinutes = durationMinutes;
    this.program = program;
    return true;
  }
}

/// Supplies explicit non-drift suggestions to tests that focus on real API
/// assignment behavior rather than on the initial recommendation source.
class _FixedAiRoutineRepository implements AiRoutineRepository {
  const _FixedAiRoutineRepository(this.items);

  final List<AiRoutineItem> items;

  @override
  Stream<List<AiRoutineItem>> watchRoutine(
    String clientId, {
    String? clientName,
  }) => Stream<List<AiRoutineItem>>.value(items);
}

/// A fixed one-client roster for real-API-mode tests (real
/// `ClientRepository` has no roster mutations and a single fetch, unlike
/// the reactive drift source).
class _FixedClientRepository implements ClientRepository {
  @override
  Future<void> restoreClient(String id) async {}
  const _FixedClientRepository(this._clients);

  final List<TrainerClient> _clients;

  @override
  bool get supportsRosterMutations => false;

  @override
  Stream<List<TrainerClient>> watchClients() => Stream.value(_clients);

  @override
  Stream<Map<String, DateTime>> watchLastChatAt() =>
      Stream<Map<String, DateTime>>.value(const <String, DateTime>{});

  @override
  Stream<List<ClientDietEntry>> watchDiet(String clientId) =>
      Stream.value(const <ClientDietEntry>[]);

  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) =>
      Stream.value(const <RoutineHistoryEntry>[]);

  @override
  Future<RoutineHistoryEntry> updateHistoryFeedback(
    String clientId,
    String historyId,
    String feedback,
  ) async => throw UnsupportedError('not used');

  @override
  Future<MemberHealthProfile> fetchHealthProfile(String clientId) async =>
      MemberHealthProfile(memberId: clientId, memberName: '회원');

  @override
  Future<MemberHealthProfile> updateHealthProfile(
    String clientId,
    Map<String, Object?> values,
  ) => fetchHealthProfile(clientId);
  @override
  Future<ClientExerciseWeek> fetchExerciseWeek(
    String clientId, {
    DateTime? weekStart,
  }) async => const ClientExerciseWeek(
    dayLabels: <String>[],
    dailyMinutes: <int>[],
    dailyCalories: <int>[],
    totalMinutes: 0,
    totalCalories: 0,
  );

  @override
  Future<String> fetchDietAdvice(String clientId, ClientPeriod period) async =>
      '';

  @override
  Future<String> fetchExerciseAdvice(
    String clientId,
    ClientPeriod period,
  ) async => '';

  @override
  Future<List<ClientDietEntry>> fetchDietOn(
    String clientId,
    DateTime date,
  ) async => const <ClientDietEntry>[];

  @override
  Future<List<String>> fetchExercisesOn(String clientId, DateTime date) async =>
      const <String>[];

  @override
  Future<ClientDietPeriod> fetchDietPeriod(
    String clientId,
    ClientDateRange range,
  ) async => ClientDietPeriod(range: range, days: const <ClientDietDay>[]);

  @override
  Future<bool> clientNameExists(String name) async => false;

  @override
  Future<bool> addClient({required String name, required String goal}) async =>
      false;

  @override
  Future<void> setClientActive(String id, bool active) async {}

  @override
  Future<void> removeClient(String id) async {}
}

/// Spies on `assignRoutine` (captures the [AssignedRoutine] sent) and can
/// be configured to throw a specific error, so tests can distinguish the
/// ambiguous (network) failure message from the generic one (subin21cc
/// review Major#2a).
class _SpyTrainerRoutineRepository implements TrainerRoutineRepository {
  @override
  Future<void> updateRoutine(
    String memberId,
    String routineId, {
    String? name,
    int? minutes,
    String? type,
    String? reason,
  }) async {}

  @override
  Future<void> deleteRoutine(String memberId, String routineId) async {}

  _SpyTrainerRoutineRepository({this.throwOnAssign});

  final Object? throwOnAssign;

  /// 마지막으로 배정된 프로그램 payload(세션·운동 구성 포함, #709).
  Map<String, Object?>? lastAssigned;

  /// 전송 시도마다 넘어온 멱등키. 재시도가 같은 키를 쓰는지 본다(#581).
  final List<String?> assignAttempts = <String?>[];

  @override
  Future<void> assignRoutine(
    String memberId,
    AssignedRoutine routine, {
    String? clientRequestId,
  }) async => throw UnsupportedError('프로그램 배정 경로만 쓴다 (#709)');

  @override
  Future<void> assignProgram(
    String memberId,
    Map<String, Object?> payload,
  ) async {
    assignAttempts.add(payload['client_request_id'] as String?);
    if (throwOnAssign != null) throw throwOnAssign!;
    lastAssigned = payload;
  }

  /// 배정된 첫 세션의 운동 목록 — 유형·출처 요약은 이제 서버가 접는다.
  List<Map<String, Object?>> get lastAssignedExercises {
    final sessions = lastAssigned?['sessions'] as List<Object?>?;
    if (sessions == null || sessions.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    final first = sessions.first! as Map<String, Object?>;
    return ((first['exercises'] as List<Object?>?) ?? const <Object?>[])
        .map((item) => (item! as Map<Object?, Object?>).cast<String, Object?>())
        .toList();
  }

  @override
  Stream<List<AssignedRoutine>> watchAssignedRoutines(String memberId) =>
      Stream.value(const <AssignedRoutine>[]);
}

/// A real-API-mode chat repository whose send can be made to fail, to
/// prove routine delivery (assignRoutine) doesn't touch chat at all — a
/// failing chat repo must have zero effect on the "전송 완료" claim
/// (subin21cc review Major#2a).
class _FakeRealChatRepository implements ChatRepository {
  _FakeRealChatRepository({this.failSend = false});

  final bool failSend;

  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) =>
      Stream.value(const <ClientChatMessage>[]);

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
  }) async {
    if (failSend) throw Exception('note failed');
  }

  @override
  Stream<Map<String, int>> watchUnreadCounts() =>
      Stream.value(const <String, int>{});

  @override
  Future<void> markThreadRead(String clientId) async {}
}

/// Resolves `fetchProfile` immediately with the seed trainer profile, so
/// `SessionController._restore()` doesn't hit a real Dio call during
/// real-API-mode tests (the persisted token would otherwise trigger
/// `DioTrainerAuthRepository.fetchProfile`).
class _FakeTrainerAuthRepository implements TrainerAuthRepository {
  const _FakeTrainerAuthRepository();

  static const _tokens = TrainerAuthTokens(access: 'a', refresh: 'r');

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
    required String inviteCode,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async => _tokens;

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async => _tokens;

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async =>
      seedTrainerProfile;
}

Finder _exerciseActionMenus() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return widget is PopupMenuButton<String> &&
      key is ValueKey<String> &&
      key.value.startsWith('exercise-edit-');
});

/// 프로그램 정보 박스는 AI 루틴을 생성/반영하기 전까지 빈 상태로 시작한다
/// (#1028) — AI 코칭 보조 제안 안내 배너의 `편집기에 반영` 단축 버튼은 이제
/// 없다(#1028 후속). 이 회원의 AI 추천 루틴을 편집기에 반영하는 유일한
/// 길인 AI 요청 흐름(생성 → 기존 추천 선택 → 검토 완료 → 템플릿에 반영)을
/// 끝까지 밟는다.
///
/// 좁은 화면은 `ListView` 라 아직 뷰포트 밖인 위젯은 빌드조차 되지 않는다 —
/// `find.text(...).evaluate().isEmpty` 로 미리 존재를 확인하면 항상 비어
/// 있는 것으로 보인다. 그래서 존재 여부를 먼저 묻지 않고, `scrollUntilVisible`
/// 이 스크롤해 가며 직접 찾게 한다.
Future<void> _applyRecommendedRoutine(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;

  final generate = find.byKey(
    const ValueKey<String>('generate-routine-options'),
  );
  await tester.scrollUntilVisible(
    generate,
    150,
    scrollable: scrollable,
    maxScrolls: 100,
  );
  await tester.ensureVisible(generate);
  await tester.pump();
  await tester.tap(generate);
  await tester.pumpAndSettle();

  // 세 후보(회복안·강화안·기존안) 중 기존 AI 추천 그대로인 `기존안` 을
  // 고른다 — 편집기에 들어갈 값이 이 회원의 seeded 추천과 같아야 한다.
  final existing = find.byKey(
    const ValueKey<String>('routine-option-recommended'),
  );
  await tester.scrollUntilVisible(
    existing,
    150,
    scrollable: scrollable,
    maxScrolls: 100,
  );
  await tester.ensureVisible(existing);
  await tester.pump();
  await tester.tap(existing);
  await tester.pumpAndSettle();

  final complete = find.byKey(
    const ValueKey<String>('complete-routine-review'),
  );
  await tester.scrollUntilVisible(
    complete,
    150,
    scrollable: scrollable,
    maxScrolls: 100,
  );
  await tester.ensureVisible(complete);
  await tester.pump();
  await tester.tap(complete);
  await tester.pumpAndSettle();

  final apply = find.byKey(const ValueKey<String>('apply-routine-to-template'));
  await tester.scrollUntilVisible(
    apply,
    150,
    scrollable: scrollable,
    maxScrolls: 100,
  );
  await tester.ensureVisible(apply);
  await tester.pump();
  await tester.tap(apply);
  await tester.pumpAndSettle();
}

Future<void> _openManualProgram(WidgetTester tester) async {
  final manual = find.byKey(const ValueKey<String>('ai-manual-create'));
  for (var i = 0; i < 30 && manual.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pump();
  }
  await tester.ensureVisible(manual);
  await tester.pump();
  await tester.tap(manual);
  await tester.pumpAndSettle();
  expect(find.byType(ProgramEditorWorkspace), findsOneWidget);
}

/// 편집기 하단의 `보내기` 버튼을 찾아 화면에 보이게 한다.
///
/// 비활성 상태면(운동이 없으면) 먼저 AI 추천을 반영해 채운다 — 편집기가
/// 이미 운동을 갖고 있으면(트레이너가 직접 채웠거나 이미 반영했다면)
/// 여기서 다시 채우지 않는다. 조건 없이 AI 흐름을 다시 밟으면 방금 지운
/// 운동이 되살아난다.
Future<Finder> _ensureSendButtonReady(WidgetTester tester) async {
  final send = find.byKey(const ValueKey<String>('program-editor-send'));
  if (send.evaluate().isEmpty) {
    await _applyRecommendedRoutine(tester);
  }
  await tester.scrollUntilVisible(
    send,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(send);
  await tester.pump();
  if (tester.widget<ActionButton>(send).onPressed == null) {
    final returnToAi = find.byKey(const ValueKey<String>('return-to-ai-flow'));
    if (returnToAi.evaluate().isNotEmpty) {
      await tester.tap(returnToAi);
      await tester.pumpAndSettle();
    }
    await _applyRecommendedRoutine(tester);
    // `일정 추가`/`보내기` 는 이제 박스 하단에 있다 — 화면 아래쪽에 뜨는
    // 스낵바(`템플릿에 반영` 등, 4초짜리)와 같은 자리라, 스낵바가 사라지기
    // 전에 탭하면 그 스낵바의 오버레이가 탭을 가로챈다. 표시 시간이 지나면
    // 닫힘 애니메이션이 시작되는데, 그 애니메이션은 한 번의 큰
    // `pump(duration)` 로는 끝까지 처리되지 않는다 — 그 다음 프레임이
    // 따로 있어야 실제로 트리에서 빠진다. `pumpAndSettle` 로 마저 재운다.
    await tester.pump(const Duration(seconds: 4, milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      send,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(send);
    await tester.pump();
  }
  return send;
}

/// `보내기` 를 눌러 확인창까지 통과하고 실제로 배정한다(#1029) — 이 버튼
/// 하나가 확인·배정·PT 등록을 함께 한다. `PT 스케줄에 등록` 버튼은 따로
/// 없다 — 그 결과(오늘 스케줄에 등록됨)를 보려는 테스트도 이 헬퍼를 쓴다.
Future<void> _sendProgram(WidgetTester tester) async {
  final send = await _ensureSendButtonReady(tester);
  await tester.tap(send);
  await tester.pumpAndSettle();
  // 텍스트가 아니라 키로 찾는다 — 확인 다이얼로그의 submit 버튼도 편집기의
  // `일정 추가` 버튼과 같은 라벨(`programEditorAddSchedule`)을 쓰므로,
  // 텍스트 찾기는 라벨이 한 곳 더 생기면 `findsOneWidget` 위반으로 깨진다.
  await tester.tap(
    find.byKey(const ValueKey<String>('program-assign-confirm-submit')),
  );
}

/// [showPortraitDatePicker] 의 세로형 달력에서 [date] 를 고르고 확인한다 (#1028).
///
/// 프로그램 편집 화면(`program_editor_workspace.dart`)도 앱의 다른 화면과 같은
/// `showPortraitDatePicker` 를 쓴다 — 확인 버튼은 취소 버튼과 나란히 있어
/// 텍스트가 아니라 키(`portraitDatePickerConfirm`)로 찾는다.
///
/// 지금 보이는 달과 [date] 의 달이 다르면(예: 오늘이 말일이라 "내일"이 다음
/// 달인 경우) 한 달 넘긴다 — 오늘에서 하루 넘어가는 것뿐이라 한 번이면 된다.
Future<void> _pickDateInPicker(WidgetTester tester, DateTime date) async {
  final dialog = find.byKey(const Key('portraitDatePicker'));
  final today = nowKst();
  if (date.year != today.year || date.month != today.month) {
    await tester.tap(
      find.descendant(of: dialog, matching: find.byIcon(Icons.chevron_right)),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(
    find.descendant(of: dialog, matching: find.text('${date.day}')).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('portraitDatePickerConfirm')));
  await tester.pumpAndSettle();
}

Future<void> _selectExerciseAction(
  WidgetTester tester,
  String action, {
  bool last = false,
}) async {
  final finder = last
      ? _exerciseActionMenus().last
      : _exerciseActionMenus().first;
  final menu = tester.widget<PopupMenuButton<String>>(finder);
  menu.onSelected?.call(action);
  await tester.pump();
}

void _expectNutritionStatusCardsInBounds(WidgetTester tester) {
  final nutrition = find.byKey(const Key('client-nutrition-summary-card'));
  expect(nutrition, findsOneWidget);
  final nutritionRect = tester.getRect(nutrition);
  final viewportWidth = tester.view.physicalSize.width;
  for (final status in <Finder>[
    find.byKey(const Key('client-nutrition-mineral-나트륨')),
    find.byKey(const Key('client-nutrition-mineral-당류')),
  ]) {
    expect(status, findsOneWidget);
    final statusRect = tester.getRect(status);
    expect(statusRect.left, greaterThanOrEqualTo(nutritionRect.left));
    expect(statusRect.right, lessThanOrEqualTo(nutritionRect.right));
    expect(statusRect.left, greaterThanOrEqualTo(0));
    expect(statusRect.right, lessThanOrEqualTo(viewportWidth));
  }
}

void main() {
  test('real API mode never exposes bundled drift recommendations', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'http://localhost/v1',
            useMockApi: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(aiRoutineRepositoryProvider),
      isA<EmptyAiRoutineRepository>(),
    );
    expect(
      await container.read(
        aiRoutineProvider((id: 'real-client-1', name: '김민수')).future,
      ),
      isEmpty,
    );
  });

  group('demo coaching repositories', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });
    tearDown(() => db.close());

    test('returns the seeded suggestions in order per client', () async {
      final repo = DriftAiRoutineRepository(db);
      final minsu = await repo.watchRoutine('seed-client-1').first;
      // 김민수의 개인 운동은 공유 픽스처가 정한다 — 네 건이다 (#1170).
      expect(minsu.length, 4);
      expect(minsu.first.name, '저강도 유산소 (걷기)');
      expect(minsu.first.minutes, 30);
      expect(minsu.first.type, '유산소');

      final jisu = await repo.watchRoutine('seed-client-2').first;
      expect(jisu.first.name, '인터벌 런닝');
    });

    test(
      'resolves live backend ids through the matching client name',
      () async {
        final repo = DriftAiRoutineRepository(db);

        final minsu = await repo
            .watchRoutine('user-7d4e9a2c5f18', clientName: '김민수')
            .first;

        expect(minsu.length, 4);
        expect(minsu.first.name, '저강도 유산소 (걷기)');
      },
    );

    test(
      'registerToTodaySchedule attaches to an existing 예정 session',
      () async {
        final repo = DriftScheduleRepository(db);
        final before = (await db.select(db.trainerScheduleEntries).get())
            .singleWhere(
              (row) =>
                  row.clientName == '박성호' &&
                  row.date == ymd(nowKst()) &&
                  row.status == '예정',
            );
        final attached = await repo.registerProgram(
          date: ymd(nowKst()),
          clientId: 'seed-client-3',
          clientName: '박성호',
          time: '10:00',
          durationMinutes: 75,
          program: const <ProgramItem>[
            ProgramItem(name: '저강도 유산소', type: '유산소', duration: 30),
          ],
        );
        expect(attached, isTrue);

        // 오늘 자리만 센다 — 시드는 이번 주 다른 요일에도 수업을 둔다(#1210).
        final rows = await db.select(db.trainerScheduleEntries).get();
        final his = rows
            .where((r) => r.clientName == '박성호' && r.date == ymd(nowKst()))
            .toList();
        expect(his.length, 1); // no extra slot booked
        expect(his.single.programJson, contains('저강도 유산소'));
        expect(his.single.time, before.time);
        expect(his.single.durationMinutes, before.durationMinutes);
      },
    );

    test(
      'registerToTodaySchedule books a new slot when no 예정 exists',
      () async {
        final repo = DriftScheduleRepository(db);
        // 김민수's only session today is 완료 — a new slot gets booked.
        final attached = await repo.registerProgram(
          date: ymd(nowKst()),
          clientId: 'seed-client-1',
          clientName: '김민수',
          time: '10:00',
          durationMinutes: 75,
          program: const <ProgramItem>[
            ProgramItem(name: '코어 강화', type: '스트레칭', duration: 10),
          ],
        );
        expect(attached, isFalse);

        final rows = await db.select(db.trainerScheduleEntries).get();
        final his = rows
            .where((r) => r.clientName == '김민수' && r.date == ymd(nowKst()))
            .toList();
        expect(his.length, 2);
        final booked = his.firstWhere((r) => r.status == '예정');
        expect(booked.programJson, contains('코어 강화'));
        expect(booked.id.startsWith('seed-'), isFalse);
        expect(booked.time, '10:00');
        expect(booked.durationMinutes, 75);
      },
    );
  });

  group('CoachingPage', () {
    Future<void> openTab(
      WidgetTester tester, {
      Size size = const Size(1600, 1200),
    }) async {
      // Desktop surface: the workspace splits into overview | editor,
      // so both columns are on screen the way a trainer sees them.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.coaching,
        seedClock: kMidWeekKst,
      );
    }

    testWidgets(
      'defaults to the first client with nutrition graph and routine',
      (tester) async {
        await openTab(tester);

        expect(find.text('프로그램'), findsWidgets);
        expect(find.byType(ProgramNutritionSummaryCard), findsOneWidget);
        expect(
          find.byKey(const Key('client-nutrition-summary-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('client-nutrition-calorie-progress')),
          findsOneWidget,
        );
        // 프로그램 정보 박스는 AI 루틴을 생성/반영하기 전까지 빈 상태로
        // 시작한다(#1028) — AI 요청 흐름을 끝까지 밟아야 기본 추천 운동이
        // 보인다. AI 흐름 자신의 검토 목록에도 같은 이름이 뜰 수 있어
        // 편집기 안으로 범위를 좁힌다.
        await _applyRecommendedRoutine(tester);
        expect(
          find.descendant(
            of: find.byType(ProgramEditorWorkspace),
            matching: find.text('저강도 유산소 (걷기)'),
          ),
          findsOneWidget,
        );
        expect(find.text('AI 생성 후 트레이너 검토 완료'), findsWidgets);
        final programCard = find.byKey(
          const ValueKey<String>('program-client-seed-client-1'),
        );
        expect(programCard, findsOneWidget);
        // 이행률 막대·퍼센트는 이 목록에서 뺐다(#1029) — 이 목록은 회원을
        // 고르는 자리다.
        expect(
          find.descendant(
            of: programCard,
            matching: find.byType(InlineBarValue),
          ),
          findsNothing,
        );
        final avatar = tester.widget<ClientAvatar>(
          find.descendant(of: programCard, matching: find.byType(ClientAvatar)),
        );
        expect(avatar.size, 32);
      },
    );

    testWidgets(
      'full workspace keeps AI centered and client data in the right rail',
      (tester) async {
        await openTab(tester, size: const Size(1600, 900));

        final mainColumn = find.byKey(
          const ValueKey<String>('coaching-wide-main-column'),
        );
        // `AI에게 맞춤 루틴 요청하기` 는 더 이상 배너가 아니다 — 이 흐름
        // 자체가 항상 메인 열의 맨 위에 있다(#1028 후속).
        final assistant = find.byType(AiRoutineOptionsFlow);
        final overview = find.byKey(
          const ValueKey<String>('coaching-wide-client-overview'),
        );
        final switcher = find.byKey(
          const ValueKey<String>('program-client-data-switcher'),
        );
        final nutrition = find.byKey(
          const Key('client-nutrition-summary-card'),
        );
        final sodium = find.byKey(const Key('client-nutrition-mineral-나트륨'));
        final sugar = find.byKey(const Key('client-nutrition-mineral-당류'));

        expect(mainColumn, findsOneWidget);
        expect(assistant, findsOneWidget);
        expect(overview, findsOneWidget);
        expect(
          tester.getTopLeft(assistant).dy,
          closeTo(tester.getTopLeft(overview).dy, 1),
        );
        expect(
          tester.getCenter(assistant).dx,
          closeTo(tester.getCenter(mainColumn).dx, 1),
        );
        expect(
          tester.getCenter(overview).dx,
          greaterThan(tester.getCenter(mainColumn).dx),
        );
        // 회원 요약 카드는 없어졌고(#1027), 그 자리를 식단·운동 영역이
        // 가져갔다 — 오른쪽 열의 **맨 위**다.
        expect(find.text('회원 요약'), findsNothing);
        expect(switcher, findsOneWidget);
        expect(
          tester.getTopLeft(switcher).dy,
          closeTo(tester.getTopLeft(overview).dy, 1),
        );
        expect(
          find.byKey(const ValueKey<String>('program-member-completion-chart')),
          findsNothing,
        );
        expect(tester.getSize(nutrition).width, greaterThan(310));
        expect(
          tester.getBottomRight(nutrition).dy,
          lessThanOrEqualTo(tester.view.physicalSize.height),
        );
        // 프로그램 탭 카드는 회원 탭과 독립적으로 관리된다(#1531) — 나트륨·
        // 당류는 위아래가 아니라 좌우로 나란히 놓인다.
        expect(
          tester.getTopLeft(sodium).dx,
          lessThan(tester.getTopLeft(sugar).dx),
        );
        _expectNutritionStatusCardsInBounds(tester);
        // 전송 이력은 편집기 아래가 아니라 오른쪽 열이다 — 이 회원에게 이미
        // 무엇이 나갔는지는 편집을 다 읽고 나서야 알 일이 아니다. (#1027)
        expect(find.text('전송 이력'), findsOneWidget);
        expect(
          find.descendant(of: overview, matching: find.text('전송 이력')),
          findsOneWidget,
        );
        expect(find.text('개인'), findsWidgets);
        expect(find.text('숙제'), findsNothing);
        final personalBadge = find
            .byKey(const ValueKey<String>('send-history-type-개인'))
            .first;
        final ptBadge = find
            .byKey(const ValueKey<String>('send-history-type-PT'))
            .first;
        expect(personalBadge, findsOneWidget);
        expect(ptBadge, findsOneWidget);
        expect(tester.getSize(personalBadge), tester.getSize(ptBadge));
        expect(find.text('벤치프레스 외 3개'), findsOneWidget);
        expect(find.text('1:1 PT · 운동 4개'), findsNothing);
        expect(
          tester.getBottomRight(sugar).dy,
          lessThanOrEqualTo(tester.view.physicalSize.height),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('three-column boundary preserves a usable editor width', (
      tester,
    ) async {
      await openTab(tester, size: const Size(1552, 900));

      final mainColumn = find.byKey(
        const ValueKey<String>('coaching-wide-main-column'),
      );
      final rightRail = find.byKey(
        const ValueKey<String>('coaching-wide-client-overview'),
      );
      expect(mainColumn, findsOneWidget);
      expect(rightRail, findsOneWidget);
      expect(tester.getSize(mainColumn).width, greaterThanOrEqualTo(600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('full workspace moves templates below the client list', (
      tester,
    ) async {
      await openTab(tester);

      final list = find.byKey(
        const ValueKey<String>('program-client-list-scroll'),
      );
      final templates = find.byKey(
        const ValueKey<String>('program-template-sidebar'),
      );
      expect(list, findsOneWidget);
      expect(templates, findsOneWidget);
      expect(
        tester.getTopLeft(templates).dy,
        greaterThan(tester.getBottomLeft(list).dy),
      );
      expect(
        tester.getCenter(templates).dx,
        closeTo(tester.getCenter(list).dx, 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('템플릿이 늘어나도 회원 목록은 자리·높이 그대로다 (레이아웃/스크롤 1차 수정)', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.coaching,
        seedClock: kMidWeekKst,
      );

      final listFinder = find.byKey(
        const ValueKey<String>('program-client-list-scroll'),
      );
      final beforeTopLeft = tester.getTopLeft(listFinder);
      final beforeSize = tester.getSize(listFinder);

      // 시작 구성 3개뿐이던 템플릿을 10개 더 저장해, 템플릿 카드가
      // 사이드바 높이를 훌쩍 넘도록 만든다.
      final repo = container.read(trainerProgramTemplateRepositoryProvider);
      for (var i = 0; i < 10; i++) {
        await repo.create(
          name: '늘어난 템플릿 $i',
          goal: '테스트',
          exercises: const <TemplateExercise>[
            TemplateExercise(name: '스쿼트', minutes: 15, type: '근력'),
          ],
        );
      }
      container.invalidate(programTemplatesProvider);
      await tester.pump();
      await tester.pump();

      // 회원 목록의 화면 위치·크기는 템플릿이 늘기 전과 똑같아야 한다 —
      // 템플릿 카드가 커진 만큼은 그 아래 영역 안에서만 흡수되어야 한다.
      expect(tester.getTopLeft(listFinder), beforeTopLeft);
      expect(tester.getSize(listFinder), beforeSize);
      expect(tester.takeException(), isNull);
    });

    testWidgets('짧은 화면에서 템플릿이 많아도 오버플로우 없이 템플릿 영역만 스크롤한다', (tester) async {
      // "화면 높이가 비교적 작은 경우" 케이스 — 폭은 3열이 뜨는 넓이를
      // 유지하고 높이만 줄인다.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.coaching,
        seedClock: kMidWeekKst,
      );

      final repo = container.read(trainerProgramTemplateRepositoryProvider);
      for (var i = 0; i < 10; i++) {
        await repo.create(
          name: '늘어난 템플릿 $i',
          goal: '테스트',
          exercises: const <TemplateExercise>[
            TemplateExercise(name: '스쿼트', minutes: 15, type: '근력'),
          ],
        );
      }
      container.invalidate(programTemplatesProvider);
      await tester.pump();
      await tester.pump();

      // 짧은 창에서도 RenderFlex 오버플로우 없이 그려져야 한다.
      expect(tester.takeException(), isNull);

      final templateScroll = find.byKey(
        const ValueKey<String>('coaching-template-scroll'),
      );
      expect(templateScroll, findsOneWidget);
      final scrollableState = tester.state<ScrollableState>(
        find
            .descendant(of: templateScroll, matching: find.byType(Scrollable))
            .first,
      );
      // 템플릿이 남는 공간보다 많아졌으니 이 컨테이너 안에서 스크롤할
      // 거리가 있어야 한다.
      expect(scrollableState.position.maxScrollExtent, greaterThan(0));

      final beforeOffset = scrollableState.position.pixels;
      await tester.drag(templateScroll, const Offset(0, -80));
      await tester.pump();
      expect(scrollableState.position.pixels, greaterThan(beforeOffset));
      expect(tester.takeException(), isNull);
    });

    testWidgets('아주 짧은 화면에서는 회원 목록 하나만으로도 빠듯해 오버플로우 없이 열 전체가 스크롤로 물러난다', (
      tester,
    ) async {
      // 실제로 1600×550 에서 "BOTTOM OVERFLOWED BY 60 PIXELS" 가 났던
      // 창 높이 — 회원 목록(5줄) 하나만으로도 이 열에 남는 여유가
      // 거의 없어, 템플릿 카드를 `Expanded` 로 억지로 나누면 카드
      // 헤더 한 줄 그릴 자리도 없다.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 550);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.coaching,
        seedClock: kMidWeekKst,
      );

      // 나누지 않고 예전처럼 열 전체를 한 스크롤로 묶은 경로로
      // 떨어져야 한다 — 오버플로우가 나지 않아야 한다.
      expect(
        find.byKey(const ValueKey<String>('coaching-sidebar-scroll')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('program-client-list-scroll')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('program-template-sidebar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('client data buttons switch the diet summary to workout data', (
      tester,
    ) async {
      await openTab(tester);
      await tester.pumpAndSettle();

      final tabs = find.byKey(
        const ValueKey<String>('program-client-data-tabs'),
      );
      expect(tabs, findsOneWidget);
      expect(find.byType(ProgramNutritionSummaryCard), findsOneWidget);

      await tester.tap(find.descendant(of: tabs, matching: find.text('운동')));
      await tester.pumpAndSettle();

      expect(find.byType(ProgramNutritionSummaryCard), findsNothing);
      expect(find.byType(ClientExerciseStatusCard), findsOneWidget);
      final workout = find.byKey(
        const ValueKey<String>('program-workout-seed-client-1'),
      );
      expect(workout, findsOneWidget);
      expect(
        tester.getBottomRight(workout).dy,
        lessThanOrEqualTo(tester.view.physicalSize.height),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('회원 목록 행에 상대시간이 남아 있지 않다 (#1027)', (tester) async {
      await openTab(tester);
      await tester.pumpAndSettle();

      // 씨앗 로스터의 `마지막 루틴` 은 `오늘`/`어제`/`5일 전` 같은 상대시간
      // 문자열이다. 완료율보다 시선을 먼저 가져가서 지웠다.
      final row = find.byKey(
        const ValueKey<String>('program-client-seed-client-1'),
      );
      expect(row, findsOneWidget);
      for (final String stale in <String>['오늘', '어제', '5일 전', '3주 전']) {
        expect(
          find.descendant(of: row, matching: find.text(stale)),
          findsNothing,
          reason: '$stale 이 아직 줄에 남아 있다',
        );
      }
      // 이행률 막대도 뺐다(#1029) — 이 줄에는 이제 이름·목표만 남는다.
      expect(
        find.descendant(of: row, matching: find.text('운동 이행률')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('운동 쪽에 세트·횟수까지 적힌 상세 내역이 있다 (#1027)', (tester) async {
      await openTab(tester);
      await tester.pumpAndSettle();

      final tabs = find.byKey(
        const ValueKey<String>('program-client-data-tabs'),
      );
      await tester.tap(find.descendant(of: tabs, matching: find.text('운동')));
      await tester.pumpAndSettle();

      // 그래프는 `얼마나 오래` 만 말한다. 다음 프로그램을 짜려면 `무엇을 몇
      // 세트` 가 함께 있어야 한다.
      final detail = find.byKey(
        const ValueKey<String>('client-exercise-detail'),
      );
      expect(detail, findsOneWidget);
      expect(
        find.descendant(of: detail, matching: find.text('운동 기록')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: detail,
          matching: find.text('벤치프레스 4세트 · 10회 · 40kg'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('오른쪽 회원 데이터 열은 편집기와 따로 스크롤한다 (#1027)', (tester) async {
      await openTab(tester, size: const Size(1600, 900));
      await tester.pumpAndSettle();

      final rail = find.byKey(
        const ValueKey<String>('coaching-wide-client-overview'),
      );
      final railScroll = find.byKey(
        const ValueKey<String>('coaching-client-rail-scroll'),
      );
      final pageScroll = find.byKey(
        const ValueKey<String>('coaching-program-page-scroll'),
      );
      expect(rail, findsOneWidget);
      // 열이 가운데 스크롤 **밖**에 있어야 편집기를 내려도 제자리에 남는다.
      expect(
        find.descendant(of: pageScroll, matching: railScroll),
        findsNothing,
      );

      final double before = tester.getTopLeft(rail).dy;
      await tester.drag(pageScroll, const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(rail).dy, closeTo(before, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide breakpoint keeps nutrition status cards in bounds', (
      tester,
    ) async {
      await openTab(tester, size: const Size(900, 1200));

      _expectNutritionStatusCardsInBounds(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('short desktop keeps the complete diet status above the fold', (
      tester,
    ) async {
      await openTab(tester, size: const Size(1366, 768));

      final sugar = find.byKey(const Key('client-nutrition-mineral-당류'));
      expect(sugar, findsOneWidget);
      expect(
        tester.getBottomRight(sugar).dy,
        lessThanOrEqualTo(tester.view.physicalSize.height),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide client list shows five rows and scrolls the rest', (
      tester,
    ) async {
      await openTab(tester);
      await tester.pumpAndSettle();

      final listFinder = find.byKey(
        const ValueKey<String>('program-client-list-scroll'),
      );
      expect(listFinder, findsOneWidget);
      // 한 줄에 이름 · 목표 두 줄만 남는다 — `오늘`/`5일 전` 같은 상대시간
      // 줄을 지우면서 104 에서 88 로(#1027), 이행률 막대까지 지우면서 88
      // 에서 64 로 내려왔다(#1029). 앱 기본 글씨 배율이 올라가면 줄 높이도
      // 함께 늘어난다 — 화면과 같은 식으로 기대값을 잡는다. (#995)
      final double expectedRow =
          64 + 56 * (AppTypography.textScale - 1).clamp(0.0, 2.0);
      expect(tester.getSize(listFinder).height, expectedRow * 5);
      final list = tester.widget<ListView>(listFinder);
      expect(list.controller, isNotNull);
      expect(list.controller!.position.maxScrollExtent, greaterThan(0));

      await tester.drag(listFinder, const Offset(0, -240));
      await tester.pumpAndSettle();

      expect(list.controller!.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('client list keeps five rows usable with enlarged text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openTab(tester);
      await tester.pumpAndSettle();

      final listFinder = find.byKey(
        const ValueKey<String>('program-client-list-scroll'),
      );
      expect(listFinder, findsOneWidget);
      expect(tester.getSize(listFinder).height, greaterThan(60 * 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact client picker stacks demographics below the name', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.coaching,
        seedClock: kMidWeekKst,
      );

      final minsuIdentity = find.byWidgetPredicate(
        (widget) =>
            widget is ClientIdentity &&
            widget.stacked &&
            widget.client.id == 'seed-client-1',
      );
      expect(minsuIdentity, findsOneWidget);
      final identity = tester.widget<ClientIdentity>(minsuIdentity);
      final demographics = clientDemographicsLabel(
        tester.element(minsuIdentity),
        identity.client,
      );
      final name = find.descendant(
        of: minsuIdentity,
        matching: find.text(identity.client.name),
      );
      final detail = find.descendant(
        of: minsuIdentity,
        matching: find.text(demographics),
      );
      expect(
        tester.getTopLeft(detail).dy,
        greaterThan(tester.getTopLeft(name).dy),
      );
      expect(find.byType(ProgramNutritionSummaryCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the AI routine assistant is always visible, not behind a click '
      '(#1028 후속)',
      (tester) async {
        await openTab(tester);

        // 클릭해야 나타나던 배너는 없다 — 흐름 자체가 항상 프로그램 정보
        // 박스 위에 있다.
        expect(find.text('운동 목표와 최근 활동, 오늘의 식단 정보를 확인했어요'), findsOneWidget);
        expect(find.byType(AiRoutineOptionsFlow), findsOneWidget);
        // The persistent shell proves this lives inline in the tab, not a
        // dialog/page. Asserted on the sidebar's profile footer rather than
        // a nav label, which now also appears as the page title.
        expect(
          find.byKey(const ValueKey<String>('sidebar-profile')),
          findsOneWidget,
        );
      },
    );

    testWidgets('AI 1·2·3단계에서 직접 만들기를 누르면 빈 편집기로 전환된다', (tester) async {
      await openTab(tester);

      Future<void> expectBlankManualEditor() async {
        await _openManualProgram(tester);
        expect(find.byType(AiRoutineOptionsFlow), findsNothing);
        expect(find.byType(ProgramEditorWorkspace), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ProgramEditorWorkspace),
            matching: find.text('저강도 걷기'),
          ),
          findsNothing,
        );
        expect(
          tester
              .widget<ActionButton>(
                find.byKey(const ValueKey<String>('program-editor-send')),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.byKey(const ValueKey<String>('program-client-seed-client-1')),
          findsOneWidget,
        );
      }

      Future<void> returnToAi() async {
        final back = find.byKey(const ValueKey<String>('return-to-ai-flow'));
        expect(
          find.descendant(of: back, matching: find.byIcon(Icons.chevron_left)),
          findsOneWidget,
        );
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.byType(AiRoutineOptionsFlow), findsOneWidget);
        expect(find.byType(ProgramEditorWorkspace), findsNothing);
      }

      // 1단계: 조건 설정.
      expect(find.byType(AiRoutineOptionsFlow), findsOneWidget);
      expect(find.byType(ProgramEditorWorkspace), findsNothing);
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('ai-manual-create')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey<String>('routine-stage-0')))
              .dy,
        ),
      );
      await expectBlankManualEditor();

      // 2단계: 후보 선택·편집.
      await returnToAi();
      await tester.tap(
        find.byKey(const ValueKey<String>('generate-routine-options')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('complete-routine-review')),
        findsOneWidget,
      );
      await expectBlankManualEditor();

      // 3단계: 최종 검토.
      await returnToAi();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('complete-routine-review')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('complete-routine-review')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('apply-routine-to-template')),
        findsOneWidget,
      );
      await expectBlankManualEditor();

      // 직접 작성 중에도 AI 흐름으로 돌아가 이전 단계부터 재요청할 수 있다.
      await returnToAi();
      await tester.tap(find.byKey(const ValueKey<String>('routine-stage-0')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('generate-routine-options')),
        findsOneWidget,
      );
    });

    testWidgets('템플릿에 반영을 눌러야 검토한 후보가 프로그램 정보에 반영된다 (#1028 후속)', (
      tester,
    ) async {
      await openTab(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('generate-routine-options')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('generate-routine-options')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('complete-routine-review')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('complete-routine-review')),
      );
      await tester.pumpAndSettle();

      // 검토 단계에 들어온 것만으로는 아직 편집기에 아무것도 반영되지
      // 않는다 — `템플릿에 반영`을 눌러야 한다.
      expect(
        find.descendant(
          of: find.byType(ProgramEditorWorkspace),
          matching: find.text('저강도 걷기'),
        ),
        findsNothing,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('apply-routine-to-template')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('apply-routine-to-template')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AiRoutineOptionsFlow), findsNothing);

      // 편집기 안으로 범위를 좁힌다 — 같은 이름의 운동이 오른쪽 `AI 개인운동
      // 제안` 영역(#790)에도 뜰 수 있고, 이 테스트가 확인하는 것은 검토한
      // 후보가 프로그램 정보에 반영됐는지다.
      expect(
        find.descendant(
          of: find.byType(ProgramEditorWorkspace),
          matching: find.text('저강도 걷기'),
        ),
        findsOneWidget,
      );
      expect(find.text('AI 생성 후 트레이너 검토 완료'), findsWidgets);
    });

    testWidgets(
      'switching client updates the nutrition graph and suggestions',
      (tester) async {
        await openTab(tester);

        final progressFinder = find.byKey(
          const Key('client-nutrition-calorie-progress'),
        );
        final initialProgress = tester
            .widget<CircularProgressIndicator>(progressFinder)
            .value;

        await tester.tap(find.text('이지수'));
        await settle(tester);

        expect(
          find.byKey(const Key('client-nutrition-summary-card')),
          findsOneWidget,
        );
        expect(
          tester.widget<CircularProgressIndicator>(progressFinder).value,
          isNot(initialProgress),
        );
        // 프로그램 정보 박스는 빈 상태로 시작한다(#1028) — 이 회원의 AI
        // 추천 루틴을 편집기에 반영해야 기본 추천이 보인다. AI 흐름 자신의
        // 검토 목록에도 같은 이름이 뜰 수 있어 편집기 안으로 범위를 좁힌다.
        await _applyRecommendedRoutine(tester);
        expect(
          find.descendant(
            of: find.byType(ProgramEditorWorkspace),
            matching: find.text('인터벌 런닝'),
          ),
          findsOneWidget,
        );
        expect(find.text('저강도 유산소 (걷기)'), findsNothing);
      },
    );

    testWidgets('adding and deleting a custom exercise', (tester) async {
      await openTab(tester);
      await _openManualProgram(tester);

      await tester.scrollUntilVisible(
        find.text('운동 추가'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('운동 추가'));
      await tester.pump();
      await tester.tap(find.text('운동 추가'));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-exercise-name')),
        '레그프레스 5세트',
      );
      await tester.ensureVisible(find.text('추가'));
      await tester.pump();
      await tester.tap(find.text('추가'));
      await tester.pump();
      // The new custom card may land below the fold.
      await tester.scrollUntilVisible(
        find.text('레그프레스 5세트'),
        150,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('레그프레스 5세트'), findsOneWidget);

      // Delete it again.
      await _selectExerciseAction(tester, 'delete', last: true);
      expect(find.text('레그프레스 5세트'), findsNothing);
    });

    testWidgets('다른 탭에 갔다 돌아와도 작성 중인 프로그램이 그대로 남는다 (#1028 후속)', (tester) async {
      await openTab(tester);
      await _openManualProgram(tester);

      // 안내 배너 없이도 편집기는 빈 상태로 시작한다 — 직접 운동을 하나
      // 추가해 "작성 중"인 상태를 만든다.
      await tester.scrollUntilVisible(
        find.text('운동 추가'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('운동 추가'));
      await tester.pump();
      await tester.tap(find.text('운동 추가'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-exercise-name')),
        '탭 이동 테스트 운동',
      );
      await tester.ensureVisible(find.text('추가'));
      await tester.pump();
      await tester.tap(find.text('추가'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('탭 이동 테스트 운동'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('탭 이동 테스트 운동'), findsOneWidget);

      // 다른 탭(대시보드)으로 갔다가 프로그램 탭으로 돌아온다 — 저장
      // 버튼을 누르지 않았다.
      await goTo(tester, AppRoutes.dashboard);
      await goTo(tester, AppRoutes.coaching);

      await tester.scrollUntilVisible(
        find.text('탭 이동 테스트 운동'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('탭 이동 테스트 운동'), findsOneWidget);
    });

    testWidgets('send reset also closes the add-exercise form', (tester) async {
      await openTab(tester);
      await _openManualProgram(tester);

      // Open the add form, then send with it still open.
      await tester.scrollUntilVisible(
        find.text('운동 추가'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('운동 추가'));
      await tester.pump();
      await tester.tap(find.text('운동 추가'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('custom-exercise-name')),
        findsOneWidget,
      );

      // The open form's TextField adds an inner Scrollable — target the
      // page ListView explicitly.
      await _sendProgram(tester);
      await tester.pump();

      await tester.pump(const Duration(seconds: 4)); // reset window
      // The add form must be closed again after the reset.
      expect(
        find.byKey(const ValueKey<String>('custom-exercise-name')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('운동 추가'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('운동 추가'), findsOneWidget);
    });

    testWidgets('an AI suggestion can be removed for this round', (
      tester,
    ) async {
      await openTab(tester);

      // 프로그램 정보 박스는 빈 상태로 시작한다(#1028) — 먼저 AI 추천
      // 루틴을 편집기에 반영한다. AI 흐름 자신의 검토 목록에도 같은 이름이
      // 남아 있을 수 있어 편집기 안으로 범위를 좁힌다.
      await _applyRecommendedRoutine(tester);
      final inEditor = find.descendant(
        of: find.byType(ProgramEditorWorkspace),
        matching: find.text('저강도 유산소 (걷기)'),
      );
      expect(inEditor, findsOneWidget);
      await _selectExerciseAction(tester, 'delete');
      expect(inEditor, findsNothing);

      // 다른 회원으로 옮겼다가 돌아오면 편집기는 새로 시작한다 — 지운 것이
      // 되살아나지 않는다(#1028 후속: 반영 전까지는 항상 빈 상태).
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
      await tester.pump();
      await tester.tap(find.text('이지수'));
      await settle(tester);
      await tester.tap(find.text('김민수'));
      await settle(tester);
      expect(find.text('저강도 유산소 (걷기)'), findsNothing);
    });

    testWidgets('오늘 스케줄에 등록 writes the routine onto the schedule tab', (
      tester,
    ) async {
      await openTab(tester);

      // 박성호 → his 15:00 예정 session receives the program.
      await tester.tap(find.text('박성호'));
      await settle(tester);

      await _sendProgram(tester);
      await settle(tester);

      // 박성호는 오늘 15:00 에 이미 예정된 세션이 있다 — 새 세션을 만드는
      // 게 아니라 그 세션에 프로그램만 붙으므로, 등록 시각으로 고른 값(기본
      // 오전 10시)은 적용되지 않는다. 그래서 성공 문구가 아니라 경고가
      // 뜬다.
      expect(
        find.text('오늘에 이미 예정된 세션이 있어 그 세션에 프로그램만 추가됐어요 — 고른 시간 범위는 적용되지 않았어요'),
        findsOneWidget,
      );
      expect(find.text('오늘 스케줄에 등록됐어요'), findsNothing);

      // The 스케줄 tab shows the registered plan on his 예정 session.
      await goTo(tester, AppRoutes.schedule);
      // 시간표 블록의 둘째 줄은 `이름 종류` 다(#1010).
      final Finder block = find.textContaining('박성호').first;
      await tester.ensureVisible(block);
      await tester.pump();
      await tester.tap(block);
      await settle(tester);
      // 세트 수는 이름이 아니라 칸이 든다(#1276) — 배정 이름은 `벤치프레스`
      // 이고, 세트·횟수·중량은 그 아래 줄에 따로 적힌다.
      await tester.ensureVisible(find.text('벤치프레스'));
      expect(find.text('벤치프레스'), findsOneWidget); // AI routine item
    });

    testWidgets('homework send does not create a trainer chat bubble', (
      tester,
    ) async {
      await openTab(tester);

      await _sendProgram(tester);
      await settle(tester);
      // 회원 전송 문구는 더 이상 뜨지 않는다(#1536) — 일정 등록 토스트가
      // 흐름이 끝까지 성공했다는 신호를 대신한다.
      expect(find.text('오늘 스케줄에 등록됐어요'), findsOneWidget);

      // Routine delivery is shown in the member's routine feed, not as a
      // trainer-authored blue chat bubble.
      await goTo(
        tester,
        AppRoutes.clientDetail('seed-client-1', section: 'chat'),
      );
      expect(find.textContaining('📋 AI 루틴 숙제를 보냈어요'), findsNothing);
    });

    testWidgets('date picker registers the routine on the picked day', (
      tester,
    ) async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.coaching);

      await _ensureSendButtonReady(tester);
      final dateButton = find.byKey(
        const ValueKey<String>('program-register-date'),
      );
      await tester.scrollUntilVisible(
        dateButton,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(dateButton);
      await tester.pump();
      // 기본값은 오늘 — YYYY-MM-DD 로 표시된다. 다이얼로그 없이 박스
      // 하단에 바로 보이는 칩이다.
      expect(
        find.descendant(of: dateButton, matching: find.text(ymd(nowKst()))),
        findsOneWidget,
      );
      await tester.tap(dateButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('portraitDatePicker')), findsOneWidget);
      await _pickDateInPicker(tester, nowKst().add(const Duration(days: 1)));

      await _sendProgram(tester);
      await settle(tester);
      expect(find.text('내일 스케줄에 등록됐어요'), findsOneWidget);

      // Booked under tomorrow's date, not today's. Reading a drift stream
      // must run outside the fake-async zone (`runAsync`), otherwise the
      // subscription never flushes and the test hangs.
      final tomorrow = ymd(nowKst().add(const Duration(days: 1)));
      final rows = await tester.runAsync(
        () => container
            .read(scheduleRepositoryProvider)
            .watchDate(tomorrow)
            .first,
      );
      // 시드가 이번 주를 채우므로(#1210) 내일에도 다른 수업이 있을 수 있다 —
      // 방금 등록한 것만 골라 본다.
      final booked = rows!.where((s) => s.clientName == '김민수').toList();
      expect(booked, hasLength(1));
      expect(booked.single.program, isNotEmpty);

      // Drain the 3s confirmation timer so it isn't left pending.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('시간 선택 박스로 고른 시각이 그대로 PT 등록에 쓰인다', (tester) async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.coaching);

      await _ensureSendButtonReady(tester);

      // `showTimePicker` 의 다이얼(원형) UI는 좌표로 값을 골라야 해서
      // 픽셀 위치에 취약하다 — 다른 팝업 콜백 테스트(`_selectExerciseAction`)
      // 처럼 위젯을 직접 잡아 콜백을 불러 값을 확정한다.
      final workspace = tester.widget<ProgramEditorWorkspace>(
        find.byType(ProgramEditorWorkspace),
      );
      workspace.onRegisterTimeRangeChanged((
        start: const TimeOfDay(hour: 14, minute: 30),
        end: const TimeOfDay(hour: 15, minute: 45),
      ));
      await tester.pump();

      // 날짜·시각 칩은 다이얼로그 없이 박스 하단에 바로 보인다 — 방금
      // 고른 시각이 그 칩에 그대로 보이는지 확인하고, 날짜는 내일로
      // 고른다. 오늘로 두면 이미 있는 세션과 섞인다 — 시드는 한 주 내내
      // 일정이 차 있으므로(#1210) 그날의 유일한 세션이 아니라 **고른
      // 시각으로** 찾는다.
      final timeButton = find.byKey(
        const ValueKey<String>('program-register-time'),
      );
      await tester.scrollUntilVisible(
        timeButton,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(timeButton);
      await tester.pump();
      expect(
        find.descendant(
          of: timeButton,
          matching: find.text(
            '${const TimeOfDay(hour: 14, minute: 30).format(tester.element(timeButton))} – '
            '${const TimeOfDay(hour: 15, minute: 45).format(tester.element(timeButton))}',
          ),
        ),
        findsOneWidget,
      );

      final dateButton = find.byKey(
        const ValueKey<String>('program-register-date'),
      );
      await tester.scrollUntilVisible(
        dateButton,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(dateButton);
      await tester.pump();
      await tester.tap(dateButton);
      await tester.pumpAndSettle();
      await _pickDateInPicker(tester, nowKst().add(const Duration(days: 1)));

      await _sendProgram(tester);
      await settle(tester);
      expect(find.text('내일 스케줄에 등록됐어요'), findsOneWidget);

      final tomorrow = ymd(nowKst().add(const Duration(days: 1)));
      final rows = await tester.runAsync(
        () => container
            .read(scheduleRepositoryProvider)
            .watchDate(tomorrow)
            .first,
      );
      expect(
        rows!.where((row) => row.time == '14:30'),
        hasLength(1),
        reason: '고른 시각 그대로 한 건만 등록된다',
      );
      expect(
        rows.singleWhere((row) => row.time == '14:30').durationMinutes,
        75,
      );

      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('send shows confirmation then resets edits', (tester) async {
      await openTab(tester);

      await _sendProgram(tester);
      // 배정에 이어 등록까지 끝나야 토스트가 뜬다 — 배정만 끝나는 시점을
      // 잡던 예전 단일 `pump()`로는 부족하다(#1536).
      await settle(tester);

      // 회원 전송 문구는 더 이상 뜨지 않는다(#1536) — 일정 등록 토스트와
      // "스케줄로 이동하기" 액션이 완료 안내를 대신한다.
      expect(find.text('오늘 스케줄에 등록됐어요'), findsOneWidget);
      expect(find.text('스케줄로 이동하기'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4)); // reset window
      // 초기화된 편집기는 다시 빈 프로그램 정보 박스로 시작한다(#1028) —
      // 보낸 운동이 자동으로 되살아나지 않아, 검토 버튼도 다시 잠긴다.
      expect(
        find.descendant(
          of: find.byType(ProgramEditorWorkspace),
          matching: find.text('저강도 유산소 (걷기)'),
        ),
        findsNothing,
      );
      final send = find.byKey(const ValueKey<String>('program-editor-send'));
      await tester.scrollUntilVisible(
        send,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<ActionButton>(send).onPressed, isNull);
    });

    testWidgets('mashing 스케줄 등록 registers only once', (tester) async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        extraOverrides: <Override>[
          scheduleRepositoryProvider.overrideWith(
            (ref) =>
                _SlowCountingScheduleRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.coaching);

      final send = await _ensureSendButtonReady(tester);
      await tester.tap(send);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('program-assign-confirm-submit')),
      );
      // 배정+PT 등록이 한 버튼에 묶였다(#1029) — 배정은 빠르지만 그 뒤로
      // 이어지는 등록이 느린 채로 남아 있는 동안, 버튼은 계속 잠겨 있다
      // (`sending`). 그 잠긴 창 안에서 두 번째 탭을 흉내 낸다.
      await tester.pump(const Duration(milliseconds: 50));
      // Second tap lands mid-flight — the button is now disabled, so this
      // must NOT trigger a second register.
      await tester.tap(
        find.byKey(const ValueKey<String>('program-editor-send')),
        warnIfMissed: false,
      );
      await settle(tester);

      final repo = container.read(
        scheduleRepositoryProvider,
      ) as _SlowCountingScheduleRepository;
      expect(repo.registerCalls, 1);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
    });

    testWidgets('switching clients mid-registration does not flash success '
        'on the new client', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        extraOverrides: <Override>[
          scheduleRepositoryProvider.overrideWith(
            (ref) =>
                _SlowCountingScheduleRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.coaching);

      await _sendProgram(tester);
      await tester.pump(const Duration(milliseconds: 50));

      // Switch client while the write for 김민수 is still in flight —
      // the picker is above the button, so scroll back up to it.
      await tester.scrollUntilVisible(
        find.text('이지수'),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('이지수'));
      await tester.pump();
      await tester.tap(find.text('이지수'));
      await settle(tester);

      // 이지수's card must not claim the registration, and her send button
      // must not be left disabled by the previous client's guard. The
      // editor is a lazy list, so bring the button back into view first.
      final send = await _ensureSendButtonReady(tester);
      expect(find.text('오늘 스케줄에 등록됐어요'), findsNothing);
      expect(tester.widget<ActionButton>(send).onPressed, isNotNull);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
    });

    testWidgets('homework delivery does not depend on the chat repository', (
      tester,
    ) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        extraOverrides: <Override>[
          chatRepositoryProvider.overrideWith(
            (ref) => _FailingChatRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.coaching);

      await _sendProgram(tester);
      await settle(tester);

      expect(find.text('전송에 실패했어요. 다시 시도해 주세요'), findsNothing);
      expect(find.text('오늘 스케줄에 등록됐어요'), findsOneWidget);
    });

    testWidgets('A → B → A cannot double-register while A is still saving', (
      tester,
    ) async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        extraOverrides: <Override>[
          scheduleRepositoryProvider.overrideWith(
            (ref) => _SlowCountingScheduleRepository(
              ref.watch(appDatabaseProvider),
              // 이 테스트만 회원을 세 번 오가며 매번 편집기 아래쪽까지
              // 스크롤한다(#1028: AI 요청 흐름이 편집기 위에 항상 있어 탭이
              // 길어졌다) — 그 스크롤이 쓰는 가상 시계만으로도 기본
              // 5초를 넘길 수 있어 넉넉히 늘려 둔다.
              delay: const Duration(seconds: 30),
            ),
          ),
        ],
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.coaching);

      // 편집기는 매번 빈 상태로 시작한다(#1028) — 회원을 오갈 때마다 그
      // 회원의 편집기는 새로 만들어지기 때문이다. `_ensureSendButtonReady` 가
      // AI 흐름 전체를 다시 밟게 두면(느려서) 아래 5초 지연과 우연히 겹칠 수
      // 있으므로, 이 타이밍 테스트에서는 직접 운동 하나를 빠르게 넣어 둔다.
      Future<void> quicklyFillEditor() async {
        if (find.byType(ProgramEditorWorkspace).evaluate().isEmpty) {
          await _openManualProgram(tester);
        }
        final scrollable = find.byType(Scrollable).first;
        final add = find.text('운동 추가');
        await tester.scrollUntilVisible(add, 150, scrollable: scrollable);
        await tester.pump();
        await tester.tap(add);
        await tester.pump();
        final nameField = find.byKey(
          const ValueKey<String>('custom-exercise-name'),
        );
        await tester.enterText(nameField, '등록 테스트 운동');
        tester.widget<TextField>(nameField).onSubmitted!('등록 테스트 운동');
        await tester.pump();
      }

      Future<void> tapRegister() async {
        // `보내기` 가 배정+PT 등록을 함께 한다(#1029) — 등록만의 재진입
        // 방지는 여전히 `_registeringClientIds`(회원별) 가 맡는다.
        await quicklyFillEditor();
        await _sendProgram(tester);
        await tester.pump(const Duration(milliseconds: 30));
      }

      Future<void> selectClient(String name) async {
        await tester.scrollUntilVisible(
          find.text(name),
          -150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text(name));
        await tester.pump();
        await tester.tap(find.text(name));
        await settle(tester);
      }

      // Start 김민수 and 이지수 independently, then return to 김민수 while
      // both writes are still pending.
      await tapRegister();
      await selectClient('이지수');
      await tapRegister();
      await selectClient('김민수');
      // Back on 김민수 while the first write is still in flight — the
      // button stays disabled, so this tap must NOT start a second one.
      await tapRegister();
      await settle(tester);

      final repo = container.read(
        scheduleRepositoryProvider,
      ) as _SlowCountingScheduleRepository;
      expect(repo.registerCalls, 2);
      // 두 write 모두 흘려보낸다 — 지연을 늘렸으니(30초) 그만큼 더 기다린다.
      await tester.pump(const Duration(seconds: 35));
      await settle(tester);
    });

    testWidgets('switching clients mid-send does not flash send success '
        'on the new client and keeps their edits', (tester) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        extraOverrides: <Override>[
          chatRepositoryProvider.overrideWith(
            (ref) => _SlowChatRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.coaching);

      // Start 김민수's (slow) send, then switch to 이지수 mid-flight.
      await _sendProgram(tester);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.scrollUntilVisible(
        find.text('이지수'),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('이지수'));
      await tester.pump();
      await tester.tap(find.text('이지수'));
      await settle(tester);
      await _openManualProgram(tester);

      // Make a fresh edit on 이지수 while 김민수's send is still in flight.
      await tester.scrollUntilVisible(
        find.text('운동 추가'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('운동 추가'));
      await tester.pump();
      await tester.tap(find.text('운동 추가'));
      await tester.pump();
      final nameField = find.byKey(
        const ValueKey<String>('custom-exercise-name'),
      );
      await tester.enterText(nameField, '레그프레스 5세트');
      tester.widget<TextField>(nameField).onSubmitted!('레그프레스 5세트');
      await tester.pump();
      await settle(tester); // let 김민수's send + reset window elapse

      // 김민수's send resolved while 이지수 is on screen: no success flash
      // lands on 이지수, and her edit survives — 김민수's reset timer must
      // not fire against her (review PR 239). 새 등록 토스트에는 회원
      // 이름이 없으므로(#1536) 문구 하나로 두 회원 다 대신 검증한다.
      expect(find.text('오늘 스케줄에 등록됐어요'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('레그프레스 5세트'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('레그프레스 5세트'), findsOneWidget);
    });

    testWidgets('registering with every exercise removed shows a hint', (
      tester,
    ) async {
      await openTab(tester);

      // 프로그램 정보 박스는 빈 상태로 시작한다(#1028 후속) — 지울 운동이
      // 있으려면 먼저 AI 코칭 보조 제안을 편집기에 반영해야 한다.
      await _applyRecommendedRoutine(tester);

      // 김민수의 개인 운동을 모두 지운다 — 공유 픽스처가 정한 네 건이다
      // (#1170).
      for (var i = 0; i < 4; i++) {
        await _selectExerciseAction(tester, 'delete');
      }

      // 운동이 하나도 없으면 `보내기` 자체가 잠긴다 — 확인창도 뜨지 않으니
      // 회원에게 갈 길도 함께 막힌다 (#1028).
      final send = find.byKey(const ValueKey<String>('program-editor-send'));
      await tester.scrollUntilVisible(
        send,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(send);
      await tester.pump();
      expect(tester.widget<ActionButton>(send).onPressed, isNull);
      expect(find.text('PT 스케줄에 등록'), findsNothing);
      expect(find.text('회원에게 배정'), findsNothing);
    });
  });

  group('CoachingPage — 전송은 보내기 확인창을 거쳐서만 (#1028)', () {
    Future<void> openTab(
      WidgetTester tester, {
      Size size = const Size(1600, 1200),
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.coaching,
        seedClock: kMidWeekKst,
      );
    }

    testWidgets('편집기 화면에는 배정·PT 등록이 아예 없다', (tester) async {
      await openTab(tester);

      // 화면 어디에도 실제 배정·등록 버튼이 없다 — 확인창을 열기 전까지는
      // 위젯 트리에 만들어지지 않는다.
      expect(
        find.byKey(const ValueKey<String>('program-editor-assign')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('program-editor-register')),
        findsNothing,
      );
      expect(find.text('회원에게 배정'), findsNothing);
      expect(find.text('PT 스케줄에 등록'), findsNothing);
    });

    testWidgets('보내기를 누르면 확인창이 뜨고, 취소하면 아무 일도 일어나지 않는다', (tester) async {
      await openTab(tester);

      final send = await _ensureSendButtonReady(tester);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('program-assign-confirm')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('program-assign-confirm')),
          matching: find.textContaining('오전 10:00 – 오전 11:00'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('program-assign-confirm-cancel')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('program-assign-confirm')),
        findsNothing,
      );
      expect(find.text('오늘 스케줄에 등록됐어요'), findsNothing);
      // 취소했으니 편집기 내용도 그대로 남아 있고, 다시 눌러 보낼 수 있다.
      expect(tester.widget<ActionButton>(send).onPressed, isNotNull);
    });

    testWidgets('AI 요청 흐름과 AI 개인운동 제안은 클릭 없이 동시에 보인다 (#1028 후속)', (
      tester,
    ) async {
      await openTab(tester, size: const Size(1920, 1200));

      // 둘 다 처음부터 트리에 있다 — 하나를 열기 위해 다른 하나가
      // 자리를 비켜 주지 않는다.
      expect(find.byType(AiRoutineOptionsFlow), findsOneWidget);
      expect(find.byType(RoutineSuggestionReviewCard), findsOneWidget);
    });

    testWidgets('좁은 화면에서도 AI 개인운동 제안이 사라지지 않는다', (tester) async {
      await openTab(tester, size: const Size(800, 1600));

      expect(find.byType(RoutineSuggestionReviewCard), findsOneWidget);
      expect(find.byType(AiRoutineOptionsFlow), findsOneWidget);
    });
  });

  group('CoachingPage — real API mode (subin21cc review)', () {
    const realClient = TrainerClient(
      id: 'real-client-1',
      name: '김민수',
      avatar: '김',
      goal: '혈압 관리',
      lastMessage: '-',
      lastTime: '-',
      active: true,
      calories: 0,
      sodiumMg: 2100,
      sugarG: 0,
      lastRoutine: '-',
      weekCompletion: <int>[0, 0, 0, 0, 0, 0, 0],
      sodiumWeek: <int>[],
    );

    const realSuggestions = <AiRoutineItem>[
      AiRoutineItem(
        id: 'real-suggestion-1',
        name: '저강도 유산소 (걷기)',
        minutes: 30,
        type: '유산소',
        reason: '실 API 배정 테스트',
      ),
      AiRoutineItem(
        id: 'real-suggestion-2',
        name: '코어 스트레칭',
        minutes: 15,
        type: '스트레칭',
        reason: '실 API 배정 테스트',
      ),
      AiRoutineItem(
        id: 'real-suggestion-3',
        name: '스쿼트',
        minutes: 15,
        type: '근력',
        reason: '실 API 배정 테스트',
      ),
    ];

    const realConfig = AppConfig(
      environment: Environment.dev,
      apiBaseUrl: 'http://localhost/v1',
      useMockApi: false,
    );

    Future<_SpyTrainerRoutineRepository> openRealApiTab(
      WidgetTester tester, {
      bool chatFails = false,
      Object? assignError,
      bool includeInitialSuggestions = true,
      void Function(_CapturingScheduleRepository repo)? captureSchedule,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final routineRepo = _SpyTrainerRoutineRepository(
        throwOnAssign: assignError,
      );
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        extraOverrides: <Override>[
          appConfigProvider.overrideWithValue(realConfig),
          // AI 코칭 탭을 보는 테스트다 — 사이드바 배지의 폴링은 여기서
          // 검증할 것이 아니라 멈춰 둔다.
          ...stillBadges(),
          clientRepositoryProvider.overrideWithValue(
            const _FixedClientRepository(<TrainerClient>[realClient]),
          ),
          trainerAuthRepositoryProvider.overrideWithValue(
            const _FakeTrainerAuthRepository(),
          ),
          // 실 API 모드지만 AI 후보 생성(`생성` 버튼)까지 실제 서버로 보낼
          // 것은 아니다 — 편집기가 빈 상태로 시작해(#1028) 검토 흐름을
          // 타야 하는 테스트가 이 저장소로 그 단계를 통과한다.
          trainerRoutineOptionsRepositoryProvider.overrideWithValue(
            const MockTrainerRoutineOptionsRepository(),
          ),
          trainerRoutineRepositoryProvider.overrideWithValue(routineRepo),
          if (includeInitialSuggestions)
            aiRoutineRepositoryProvider.overrideWithValue(
              const _FixedAiRoutineRepository(realSuggestions),
            ),
          if (captureSchedule != null)
            scheduleRepositoryProvider.overrideWith((ref) {
              final repo = _CapturingScheduleRepository(
                ref.watch(appDatabaseProvider),
              );
              captureSchedule(repo);
              return repo;
            }),
          chatRepositoryProvider.overrideWithValue(
            _FakeRealChatRepository(failSend: chatFails),
          ),
        ],
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.coaching);
      return routineRepo;
    }

    Future<void> tapSend(WidgetTester tester) async {
      final send = await _ensureSendButtonReady(tester);
      // `_ensureSendButtonReady` 가 편집기를 채우려고 AI 흐름을 지났다면
      // (#1028) `템플릿에 반영` 스낵바가 큐에 남아 있을 수 있다 — 같은
      // `ScaffoldMessenger` 를 쓰므로, 그 스낵바가 다 사라질 때까지 기다려
      // 둬야 전송 실패 스낵바가 곧바로 보인다.
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(send);
      await tester.pumpAndSettle();
      // `보내기` 는 곧장 mutation 하지 않고 확인창을 한 번 더 거친다
      // (#1029) — 배정과 PT 등록이 한 버튼에 묶인 만큼, 실제로 나가기
      // 전에 확인해야 한다.
      await tester.tap(
        find.byKey(const ValueKey<String>('program-assign-confirm-submit')),
      );
      await settle(tester);
    }

    testWidgets(
      'real-API schedule registration uses the selected member id and the '
      'shared schedule repository',
      (tester) async {
        late _CapturingScheduleRepository scheduleRepo;
        await openRealApiTab(
          tester,
          captureSchedule: (repo) => scheduleRepo = repo,
        );

        await tapSend(tester);

        expect(scheduleRepo.registerCalls, 1);
        expect(scheduleRepo.clientId, 'real-client-1');
        expect(scheduleRepo.time, '10:00');
        expect(scheduleRepo.durationMinutes, 60);
        expect(scheduleRepo.program, isNotEmpty);
        // 유형마다 재는 칸이 다르다(#1276). 근력은 세트·횟수·중량을 그대로
        // 들고 나가야 한다 — 횟수가 여기서만 빠져 있어, 편집기에서 채운
        // 값이 일정에 등록되는 순간 사라졌다.
        final strength = scheduleRepo.program!.singleWhere(
          (item) => item.type == '근력',
        );
        expect(strength.name, '스쿼트');
        expect(strength.sets, isNotNull);
        expect(strength.reps, isNotNull);
        expect(strength.weight, isNotNull);
        expect(strength.duration, isNull);
        final cardio = scheduleRepo.program!.singleWhere(
          (item) => item.type == '유산소',
        );
        expect(cardio.duration, 30);
        expect(cardio.sets, isNull);
        expect(cardio.reps, isNull);
        // `_CapturingScheduleRepository.registerProgram` 은 늘 `true`(기존
        // 세션에 붙었다)를 돌려준다 — 그래서 성공 문구가 아니라 경고가
        // 뜬다.
        expect(
          find.text(
            '오늘에 이미 예정된 세션이 있어 그 세션에 프로그램만 추가됐어요 — 고른 시간 범위는 적용되지 않았어요',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'real-API assign delivery does not depend on the chat repository '
      '(routine delivery shows in the member routine feed, not as a chat '
      'bubble)',
      (tester) async {
        final routineRepo = await openRealApiTab(tester, chatFails: true);

        await tapSend(tester);

        // 이 하네스는 PT 등록(schedule-program) 엔드포인트를 목킹하지
        // 않는다 — 배정이 채팅과 무관하게 끝난다는 것만 `routineRepo`로
        // 직접 확인한다. 회원 전송 안내 문구는 더 이상 없고(#1536), 등록
        // 성공 토스트는 이 케이스에서 뜨지 않는다.
        expect(routineRepo.lastAssigned, isNotNull);
      },
    );

    testWidgets('네트워크 실패도 재시도를 안내한다 — 멱등키를 함께 보내므로 다시 눌러도 '
        '회원에게 루틴이 두 번 배정되지 않는다 (#581)', (tester) async {
      await openRealApiTab(tester, assignError: const NetworkError());

      await tapSend(tester);

      expect(find.text('전송에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
      expect(
        find.text('응답을 받지 못했어요. 회원의 받은 루틴을 확인한 뒤 필요한 경우에만 다시 보내주세요'),
        findsNothing,
        reason: '멱등해진 뒤에는 "먼저 확인하라"고 막을 이유가 없다',
      );
    });

    testWidgets('a non-network assign failure shows the generic retry message '
        '(a clear failure, safe to retry)', (tester) async {
      await openRealApiTab(tester, assignError: const ServerError());

      await tapSend(tester);

      expect(find.text('전송에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
      expect(
        find.text('응답을 받지 못했어요. 회원의 받은 루틴을 확인한 뒤 필요한 경우에만 다시 보내주세요'),
        findsNothing,
      );
    });

    testWidgets('실패 후 재시도는 같은 멱등키를 다시 보낸다 (#581)', (tester) async {
      // 키가 매번 새로 생기면 서버의 유니크 제약이 아무것도 막지 못한다.
      final routineRepo = await openRealApiTab(
        tester,
        assignError: const NetworkError(),
      );

      await tapSend(tester);
      await tapSend(tester);

      expect(routineRepo.assignAttempts, hasLength(2));
      expect(routineRepo.assignAttempts.first, isNotNull);
      expect(
        routineRepo.assignAttempts.first,
        routineRepo.assignAttempts.last,
        reason: '재시도가 새 키를 만들면 중복 배정이 그대로 생긴다',
      );
    });

    testWidgets(
      'an all-custom send (every AI suggestion removed) assigns type/source '
      "from the custom exercises, not '근력'/'ai' by default",
      (tester) async {
        final routineRepo = await openRealApiTab(tester);

        // 프로그램 정보 박스는 빈 상태로 시작한다(#1028 후속) — 지울
        // 운동이 있으려면 먼저 AI 코칭 보조 제안을 편집기에 반영해야 한다.
        await _applyRecommendedRoutine(tester);

        // Remove all 3 seeded AI suggestions for 김민수.
        for (var i = 0; i < 3; i++) {
          await _selectExerciseAction(tester, 'delete');
        }

        await tester.scrollUntilVisible(
          find.text('운동 추가'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('운동 추가'));
        await tester.pump();
        await tester.tap(find.text('운동 추가'));
        await tester.pump();

        await tester.enterText(
          find.byKey(const ValueKey<String>('custom-exercise-name')),
          '스트레칭 A',
        );
        // Default category is 근력 — switch to 스트레칭 so the assigned
        // type is provably derived from the custom exercise, not a
        // coincidental default.
        final stretching = find.byKey(
          const ValueKey<String>('custom-exercise-category-스트레칭'),
        );
        await tester.ensureVisible(stretching);
        await tester.tap(stretching);
        await tester.pump();
        await tester.ensureVisible(find.text('추가'));
        await tester.pump();
        await tester.tap(find.text('추가'));
        await tester.pump();

        await tapSend(tester);

        // 이 하네스는 PT 등록 엔드포인트를 목킹하지 않는다 — 배정
        // payload만 `routineRepo`로 직접 확인한다.
        // 유형·출처 요약은 서버가 세션 단위로 접는다(#709) — 클라이언트는
        // 트레이너가 넣은 운동을 그대로 실어 보낸다.
        expect(
          routineRepo.lastAssignedExercises.map((e) => e['type']),
          everyElement('스트레칭'),
        );
        expect(
          routineRepo.lastAssignedExercises.map((e) => e['source']),
          everyElement('trainer'),
        );
      },
    );
  });
}
