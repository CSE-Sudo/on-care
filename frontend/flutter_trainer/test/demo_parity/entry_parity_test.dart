/// 데모와 실서버가 같은 화면에서 같은 진입점을 보이는지 비교한다. (#2792)
///
/// 데모와 실서버 화면이 다르면 데모가 기준이고, 실서버에 있는데 데모에 없는
/// 것은 데모에 더한다. 그런데 빈 목록·고정값·시드에 없는 데이터 종류처럼
/// **데이터 때문에** 생기는 차이는 코드 텍스트에 드러나지 않아 PR gate 의
/// 검사(#2791)로는 못 잡는다(예: 회원별 지난 식단이 데모에서만 비던 #2667).
/// 여기서는 같은 화면을 두 번 그린다.
///
///  * **데모** — 앱의 목업 모드 그대로: `useMockApi: true`, 시드한 drift, 목업
///    저장소. 데이터 provider 는 덮지 않는다 — 덮으면 데모가 실제로 무엇을
///    주는지 볼 수 없다.
///  * **실서버** — `useMockApi: false` 에, 이 화면들이 읽는 저장소만 실서버와
///    같은 모양의 고정 값을 주는 대역으로 바꾼다. 나머지는 앱의 실서버 구현
///    그대로다(시험 환경의 HTTP 는 실패로 돌아온다).
///
/// 비교는 값이 아니라 진입점(버튼·탭·카드)이 **있다·없다** 만 본다 — 데모 시드의
/// 값이 바뀌어도 흔들리지 않게. 실서버 쪽은 고정 값이라 진입점이 모두 서야
/// 한다. 데모에서 빠진 것이 있으면 데모를 실서버에 맞춘다.
///
/// 일부러 다르게 둔 곳은 `.github/demo-divergence-allowlist.txt`(PR gate 와 같은
/// 목록)에 적는다. 진입점이 [ParityEntry.allowlisted] 로 그 경로를 달고 있으면,
/// 그 줄이 목록에 남아 있는 동안 비교에서 뺀다.
///
/// **아이콘·키·문구로 진입점을 찾는다.** 화면의 아이콘·키·버튼 문구를 일괄로
/// 바꿀 때는 `test_e2e/`·`integration_test/` 와 함께 이 파일도 고친다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_analysis.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_day_record_tile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_period_section.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/sent_delivery.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/pages/notifications_page.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../helpers/demo_parity.dart';
import '../helpers/fixed_clock.dart';
import '../helpers/pump_app.dart';
import '../helpers/record_span.dart';

/// 시드의 김민수. 실서버 대역도 같은 id 를 써서 같은 경로로 연다.
const String _clientId = 'seed-client-1';

enum _Mode { demo, real }

/// 한 화면 안의 한 단계 — 이동·누르기 뒤에 보이는 진입점.
class _Stage {
  const _Stage(this.go, this.entries);

  final Future<void> Function(WidgetTester tester) go;
  final List<ParityEntry> entries;
}

Finder _key(String key, {bool skipOffstage = true}) =>
    find.byKey(ValueKey<String>(key), skipOffstage: skipOffstage);

Finder _keyPrefix(String prefix, {bool skipOffstage = true}) =>
    find.byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(prefix),
      skipOffstage: skipOffstage,
    );

/// [finder] 가 있을 때만 누른다 — 한쪽 모드에 버튼이 없으면 그 뒤 단계의
/// 진입점이 없는 것으로 남게 둔다(누르다 던지면 무엇이 빠졌는지 안 보인다).
Future<void> _tapIfPresent(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) return;
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await settle(tester);
}

AppLocalizations _l(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Navigator).first));

// ---------------------------------------------------------------------------
// 실서버 대역 — 실서버와 같은 모양의 고정 값
// ---------------------------------------------------------------------------

const TrainerClient _client = TrainerClient(
  id: _clientId,
  name: '비교회원',
  avatar: '',
  goal: '체지방 감량',
  lastMessage: '',
  lastTime: '',
  active: true,
  calories: 1500,
  sodiumMg: 1800,
  sugarG: 30,
  lastRoutine: '',
  weekCompletion: <int>[80, 80, 80, 80, 0, 0, 0],
  sodiumWeek: <int>[1800, 1800, 1800, 1800, 0, 0, 0],
);

const ClientDietEntry _meal = ClientDietEntry(
  id: 'meal-1',
  meal: '점심',
  items: '현미밥, 닭가슴살',
  calories: 600,
  sodiumMg: 700,
  timeLabel: '12:30',
  foods: <ClientDietFood>[
    ClientDietFood(name: '현미밥', calories: 300),
    ClientDietFood(name: '닭가슴살', calories: 300),
  ],
);

final AssignedRoutine _routine = AssignedRoutine(
  id: 'routine-1',
  name: '플랭크',
  minutes: 10,
  type: '근력',
  reason: '코어 보강',
  source: 'trainer',
  date: todayKst(),
);

/// 오늘 이전의 날만 기록이 있다 — 지난 식단·운동이 날짜별 기록에 선다.
bool _past(DateTime date) => date.isBefore(todayKst());

class _RealClientRepository implements ClientRepository {
  const _RealClientRepository();

  @override
  bool get supportsRosterMutations => false;

  @override
  Stream<List<TrainerClient>> watchClients() =>
      Stream<List<TrainerClient>>.value(const <TrainerClient>[_client]);

  @override
  Stream<Map<String, DateTime>> watchLastChatAt() =>
      Stream<Map<String, DateTime>>.value(const <String, DateTime>{});

  @override
  Stream<List<ClientDietEntry>> watchDiet(String clientId) =>
      Stream<List<ClientDietEntry>>.value(const <ClientDietEntry>[_meal]);

  @override
  Future<List<ClientDietEntry>> fetchDietOn(
    String clientId,
    DateTime date,
  ) async => const <ClientDietEntry>[_meal];

  @override
  Future<List<ClientExerciseItem>> fetchExercisesOn(
    String clientId,
    DateTime date,
  ) async => const <ClientExerciseItem>[
    ClientExerciseItem(name: '스쿼트', type: '근력', minutes: 20, sets: 3),
  ];

  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) =>
      Stream<List<RoutineHistoryEntry>>.value(const <RoutineHistoryEntry>[]);

  @override
  Future<MemberHealthProfile> fetchHealthProfile(String clientId) async =>
      MemberHealthProfile(memberId: clientId, memberName: _client.name);

  @override
  Future<MemberHealthProfile> updateHealthProfile(
    String clientId,
    Map<String, Object?> values,
  ) => fetchHealthProfile(clientId);

  @override
  Future<ClientExerciseWeek> fetchExerciseWeek(
    String clientId, {
    DateTime? weekStart,
  }) async {
    final DateTime monday = weekStart ?? clientMondayOf(todayKst());
    final List<int> minutes = <int>[
      for (int d = 0; d < 7; d++)
        _past(DateTime(monday.year, monday.month, monday.day + d)) ? 30 : 0,
    ];
    return ClientExerciseWeek(
      dayLabels: const <String>['월', '화', '수', '목', '금', '토', '일'],
      dailyMinutes: minutes,
      dailyCalories: <int>[for (final int m in minutes) m * 6],
      totalMinutes: minutes.fold(0, (int a, int b) => a + b),
      totalCalories: minutes.fold(0, (int a, int b) => a + b * 6),
      weeklyGoalMinutes: 150,
    );
  }

  @override
  Future<List<ClientExercisePeriodWeek>> fetchExercisePeriod(
    String clientId,
    ClientDateRange range,
  ) async => <ClientExercisePeriodWeek>[
    for (final DateTime monday in clientRangeWeekStarts(range))
      (
        weekStart: monday,
        week: await fetchExerciseWeek(clientId, weekStart: monday),
      ),
  ];

  @override
  Future<ClientDietAnalysis> fetchDietAdvice(
    String clientId,
    ClientPeriod period, {
    required Locale locale,
  }) async => ClientDietAnalysis.empty;

  @override
  Future<ClientDietRecommendations> fetchDietRecommendations(
    String clientId, {
    required Locale locale,
  }) async => const ClientDietRecommendations();

  @override
  Future<ClientDietRecommendations> confirmDietRecommendation(
    String clientId, {
    required String slot,
    required String name,
    required Locale locale,
  }) async => const ClientDietRecommendations();

  @override
  Future<ClientDietPeriod> fetchDietPeriod(
    String clientId,
    ClientDateRange range,
  ) async => ClientDietPeriod(
    range: range,
    days: <ClientDietDay>[
      for (final DateTime date in clientRangeDates(range))
        _past(date)
            ? ClientDietDay(date: date, calories: 1500, sodiumMg: 1800)
            : ClientDietDay(date: date),
    ],
  );

  @override
  Future<ClientRecordSpan> fetchRecordSpan(String clientId) async =>
      testClientRecordSpan();

  @override
  Future<bool> clientNameExists(String name) async => false;

  @override
  Future<bool> addClient({required String name, required String goal}) async =>
      false;

  @override
  Future<void> setClientActive(String id, bool active) async {}

  @override
  Future<void> removeClient(String id) async {}

  @override
  Future<void> restoreClient(String id) async {}
}

class _RealNotificationRepository implements TrainerNotificationRepository {
  static final TrainerNotificationPage _page = TrainerNotificationPage(
    items: <TrainerNotification>[
      TrainerNotification(
        id: 'notification-1',
        title: '비교회원님이 메시지를 보냈어요',
        body: '오늘 운동 끝났어요.',
        kind: TrainerNotificationKind.message,
        read: false,
        createdAt: DateTime(2026, 8, 20, 9),
        timeAgo: '4시간 전',
        subjectId: _clientId,
      ),
    ],
  );

  @override
  bool get supportsInbox => true;

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async => before == null ? _page : TrainerNotificationPage.empty;

  @override
  Stream<TrainerNotificationPage> watch() =>
      Stream<TrainerNotificationPage>.value(_page);

  @override
  Future<int> unreadCount() async => 1;

  @override
  Stream<int> watchUnreadCount() => Stream<int>.value(1);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 1;
}

class _RealRoutineRepository implements TrainerRoutineRepository {
  @override
  Future<void> assignRoutine(
    String memberId,
    AssignedRoutine routine, {
    String? clientRequestId,
  }) async {}

  @override
  Future<void> assignProgram(
    String memberId,
    Map<String, Object?> payload,
  ) async {}

  @override
  Stream<List<AssignedRoutine>> watchAssignedRoutines(String memberId) =>
      Stream<List<AssignedRoutine>>.value(<AssignedRoutine>[_routine]);

  @override
  Future<SentDelivery?> fetchLatestDelivery(String memberId) async =>
      SentDelivery(
        kind: DeliveryKinds.routineOnly,
        sentOn: todayKst(),
        routines: <AssignedRoutine>[_routine],
      );

  @override
  Future<void> updateRoutine(
    String memberId,
    String routineId, {
    String? name,
    int? minutes,
    int? durationSeconds,
    String? type,
    String? reason,
  }) async {}

  @override
  Future<void> deleteRoutine(String memberId, String routineId) async {}
}

class _RealSuggestionRepository implements TrainerRoutineSuggestionRepository {
  @override
  Future<List<RoutineSuggestion>> pending(String memberId) async =>
      const <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'suggestion-1',
          name: '런지',
          minutes: 10,
          type: '근력',
          reason: '하체 보강',
        ),
      ];

  @override
  Future<void> approve(
    String suggestionId, {
    String? name,
    int? minutes,
    String? type,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
    String? reason,
  }) async {}

  @override
  Future<void> dismiss(String suggestionId) async {}
}

class _RealChatRepository implements ChatRepository {
  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) =>
      Stream<List<ClientChatMessage>>.value(const <ClientChatMessage>[]);

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
    String? emoteId,
  }) async {}

  @override
  Stream<Map<String, int>> watchUnreadCounts() =>
      Stream<Map<String, int>>.value(const <String, int>{});

  @override
  Future<void> markThreadRead(String clientId) async {}
}

/// 저장된 토큰으로 세션을 되살린다 — 실서버 모드의 로그인 대역.
class _RealAuthRepository implements TrainerAuthRepository {
  const _RealAuthRepository();

  static const TrainerAuthTokens _tokens = TrainerAuthTokens(
    access: 'access',
    refresh: 'refresh',
  );

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

List<Override> _realOverrides() => <Override>[
  appConfigProvider.overrideWithValue(
    const AppConfig(
      environment: Environment.dev,
      apiBaseUrl: 'http://localhost/v1',
      useMockApi: false,
    ),
  ),
  trainerAuthRepositoryProvider.overrideWithValue(const _RealAuthRepository()),
  clientRepositoryProvider.overrideWithValue(const _RealClientRepository()),
  trainerNotificationRepositoryProvider.overrideWithValue(
    _RealNotificationRepository(),
  ),
  trainerRoutineRepositoryProvider.overrideWithValue(_RealRoutineRepository()),
  trainerRoutineSuggestionRepositoryProvider.overrideWithValue(
    _RealSuggestionRepository(),
  ),
  chatRepositoryProvider.overrideWithValue(_RealChatRepository()),
  // 사이드바 배지의 주기적 폴링은 멈춘다. 알림 배지는 위 대역의 스트림이다.
  unreadCountsProvider.overrideWith(
    (ref) => Stream<Map<String, int>>.value(const <String, int>{}),
  ),
  consultationPendingCountProvider.overrideWith((ref) => Stream<int>.value(0)),
];

// ---------------------------------------------------------------------------
// 두 모드로 띄워 비교하기
// ---------------------------------------------------------------------------

Future<Set<String>> _collect(
  WidgetTester tester,
  _Mode mode,
  String at,
  List<_Stage> stages,
) async {
  final ProviderContainer container = await pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: at,
    seedClock: kMidWeekKst,
    extraOverrides: mode == _Mode.real ? _realOverrides() : const <Override>[],
  );
  final Set<String> present = <String>{};
  for (final _Stage stage in stages) {
    await stage.go(tester);
    final AppLocalizations l = _l(tester);
    for (final ParityEntry e in withoutAllowlisted(stage.entries)) {
      if (e.find(l).evaluate().isNotEmpty) present.add(e.name);
    }
  }
  // 앱을 내리고 컨테이너를 닫는다 — 실서버 구현(일정·상담·설정)의 주기적
  // 폴링이 이 모드에서 끝나야 다음 모드가 깨끗이 시작하고, 시험이 타이머를
  // 안고 끝나지 않는다. 남은 한 번짜리 지연은 시계를 돌려 흘려보낸다.
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await tester.pump(const Duration(minutes: 1));
  return present;
}

Future<void> _expectParity(
  WidgetTester tester, {
  required String at,
  required List<_Stage> stages,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 2400);
  addTearDown(tester.view.reset);

  final List<String> names = <String>[
    for (final _Stage s in stages)
      for (final ParityEntry e in withoutAllowlisted(s.entries)) e.name,
  ];
  final Set<String> demo = await _collect(tester, _Mode.demo, at, stages);
  final Set<String> real = await _collect(tester, _Mode.real, at, stages);

  expect(
    <String>[
      for (final String n in names)
        if (!real.contains(n)) n,
    ],
    isEmpty,
    reason: '실서버 대역에서 진입점이 서지 않았다 — 대역 값을 고친다.',
  );
  expect(
    <String>[
      for (final String n in names)
        if (!demo.contains(n)) n,
    ],
    isEmpty,
    reason:
        '실서버에 있는 진입점이 데모에 없다. 데모가 기준이므로 데모(시드·목업 '
        '저장소)에 더한다. 일부러 다르게 둔 것이면 '
        '.github/demo-divergence-allowlist.txt 에 적는다.',
  );
}

Future<void> _stay(WidgetTester tester) async {}

void main() {
  testWidgets('알림 — 머리의 종, 펼침, 알림함', (WidgetTester tester) async {
    await _expectParity(
      tester,
      at: AppRoutes.dashboard,
      stages: <_Stage>[
        _Stage(_stay, <ParityEntry>[
          ParityEntry('알림 종', (_) => _key('notification-bell')),
        ]),
        _Stage(
          (WidgetTester t) => _tapIfPresent(t, _key('notification-bell')),
          <ParityEntry>[
            ParityEntry('종 펼침', (_) => _key('notification-bell-panel')),
            ParityEntry('펼침의 모두 읽음', (_) => _key('notification-bell-read-all')),
            ParityEntry(
              '펼침의 알림 줄',
              (_) => find.descendant(
                of: _key('notification-bell-panel'),
                matching: find.byType(NotificationTile),
              ),
            ),
            ParityEntry('펼침의 전체 보기', (_) => _key('notification-bell-see-all')),
          ],
        ),
        _Stage(
          (WidgetTester t) =>
              _tapIfPresent(t, _key('notification-bell-see-all')),
          <ParityEntry>[
            ParityEntry('알림함의 알림 줄', (_) => find.byType(NotificationTile)),
            ParityEntry(
              '알림함의 모두 읽음',
              (_) => find.byWidgetPredicate(
                (Widget w) =>
                    w is AppButton && w.leadingIcon == AppIcons.markAllRead,
              ),
            ),
          ],
        ),
      ],
    );
  });

  testWidgets('회원 상세 — 식단·운동 탭, 바로가기, 지난 기록, 남은 개인운동', (
    WidgetTester tester,
  ) async {
    await _expectParity(
      tester,
      at: AppRoutes.clientDetail(_clientId, section: 'diet'),
      stages: <_Stage>[
        _Stage(_stay, <ParityEntry>[
          ParityEntry('식단·운동 탭', (_) => _key('client-detail-sub-tabs')),
          ParityEntry('건강 정보', (_) => _key('client-detail-open-health')),
          ParityEntry('메모', (_) => _key('client-detail-open-memo')),
          ParityEntry('메시지 바로가기', (_) => _key('client-detail-open-messages')),
          ParityEntry('코칭 바로가기', (_) => _key('client-detail-open-program')),
          ParityEntry('리포트 바로가기', (_) => _key('client-detail-open-report')),
          ParityEntry('영양 요약', (_) => _key('client-nutrition-summary-card')),
          ParityEntry('오늘 끼니', (_) => _keyPrefix('diet-meal-')),
        ]),
        _Stage(
          (WidgetTester t) => _tapIfPresent(
            t,
            find.descendant(
              of: _key('client-period-toggle'),
              matching: find.text(clientPeriodSegments(_l(t))[1].label),
            ),
          ),
          <ParityEntry>[
            ParityEntry(
              '이번 주 지난 식단',
              (_) => find.descendant(
                of: _key('diet-daily-records'),
                matching: find.byWidgetPredicate(
                  (Widget w) =>
                      w is ClientDayRecordTile &&
                      w.logged &&
                      w.date.isBefore(todayKst()),
                ),
              ),
            ),
          ],
        ),
        _Stage(
          (WidgetTester t) =>
              goTo(t, AppRoutes.clientDetail(_clientId, section: 'workout')),
          <ParityEntry>[
            ParityEntry('운동 현황', (_) => _key('client-exercise-status-card')),
            ParityEntry('남은 개인운동', (_) => _key('workout-pending-routines')),
            ParityEntry('날짜별 운동 기록', (_) => _key('exercise-daily-records')),
          ],
        ),
      ],
    );
  });

  testWidgets('코칭 — 직전 전송, AI 루틴 흐름, AI 제안', (WidgetTester tester) async {
    await _expectParity(
      tester,
      at: AppRoutes.coachingFor(_clientId),
      stages: <_Stage>[
        _Stage(_stay, <ParityEntry>[
          ParityEntry('직전 전송', (_) => _key('coach-last-delivery')),
          ParityEntry(
            'AI 루틴 흐름',
            (_) =>
                _keyPrefix('routine-options-$_clientId-', skipOffstage: false),
          ),
          ParityEntry('후보 만들기', (_) => _key('generate-routine-options')),
          ParityEntry('PT 건너뛰기', (_) => _key('skip-pt-program')),
        ]),
        _Stage(
          (WidgetTester t) => _tapIfPresent(t, _key('skip-pt-program')),
          <ParityEntry>[
            ParityEntry('개인운동 단계', (_) => _key('personal-routine-step')),
            ParityEntry('AI 제안 표시', (_) => _key('personal-routine-badge')),
          ],
        ),
      ],
    );
  });

  test('예외 목록을 읽는다', () {
    // 형식이 어긋나면 위 비교가 모두 무너진다 — 따로 드러낸다.
    expect(readDemoDivergenceAllowlist(), isNotEmpty);
  });
}
