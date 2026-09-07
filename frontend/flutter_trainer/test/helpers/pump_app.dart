import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/app.dart';
import 'package:oncare_trainer/app/router/app_router.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixed_clock.dart';

/// Mock-mode config so widget tests resolve the in-memory repositories
/// (no real backend). Individual tests can override with [extraOverrides].
const AppConfig kTestAppConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

/// [kTestAppConfig] + 로그인 화면의 데모 진입 노출. 화면에서는 내렸지만 진입
/// 경로 자체는 살아 있어야 하므로(플래그로 되돌릴 수 있게), 그 경로를 지나는
/// 테스트는 이 설정으로 편다. `pumpTrainerApp(..., demoEntry: true)`. (#1526)
const AppConfig kTestAppConfigWithDemoEntry = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
  showDemoEntry: true,
);

/// Pumps the full trainer app for a widget test, backed by a fresh
/// in-memory (seeded) drift DB and an optional persisted session token.
///
/// Returns the [ProviderContainer] so tests can read providers directly.
///
/// NOTE: uses bounded `pump()`s rather than `pumpAndSettle()` — pages
/// backed by a drift `.watch()` stream keep a live subscription, so
/// `pumpAndSettle` never reaches an idle frame and times out. Two pumps
/// (one to build, one to let the stream emit + route transition finish)
/// are enough for the seeded data to render.
/// [bootAt] boots the router at a location instead of the platform one —
/// the widget-test stand-in for opening the console on a deep link (a
/// browser refresh or a shared URL). It differs from [at], which
/// navigates *after* the app is up and so never exercises the boot path.
/// [seedClock] 을 주면 데모 시딩과 **화면이 보는 '지금'** 이 함께 그 시각으로
/// 고정된다.
///
/// 시드는 주간 계열을 **오늘까지만** 채운다(`_upToToday`). 그래서 요일에 따라
/// 그 주에 기록된 날의 수가 달라지고, 이행률 평균이 달라지고, 배지의 우선순위가
/// 뒤집힌다. 특정 배지를 검증하는 테스트는 요일을 고정해야 어느 날 돌려도 같은
/// 값을 본다.
///
/// 시드만 고정하고 `nowKst()` 를 두면 둘이 어긋난다 — 시드는 목요일 기준으로
/// 수업을 놓는데 화면은 실제 오늘로 완료·예정을 가른다. 한쪽만 고정하는 것은
/// 고정하지 않은 것과 다를 바 없어, 여기서 함께 묶는다.
Future<ProviderContainer> pumpTrainerApp(
  WidgetTester tester, {
  String? token,
  bool seed = true,
  String? at,
  String? bootAt,
  List<Override> extraOverrides = const <Override>[],
  bool demoEntry = false,
  Locale locale = const Locale('ko'),
  DateTime? seedClock,
}) async {
  // A persisted session lives in secure storage now (access + refresh).
  // Reset the in-memory mock per test so state never leaks between them.
  FlutterSecureStorage.setMockInitialValues(
    token == null
        ? <String, String>{}
        : <String, String>{'access_token': token, 'refresh_token': '$token-r'},
  );
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  if (seedClock != null) useFixedKstDate(seedClock);
  if (seed) await seedIfEmpty(db, clock: seedClock);
  addTearDown(() async => db.close());

  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(
        demoEntry ? kTestAppConfigWithDemoEntry : kTestAppConfig,
      ),
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (bootAt != null)
        routerInitialLocationProvider.overrideWithValue(bootAt),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: OncareTrainerApp(locale: locale),
    ),
  );
  await settle(tester);
  if (at != null) await goTo(tester, at);
  return container;
}

/// Navigates the pumped app to [location] and settles.
///
/// Tests drive navigation through the router rather than by tapping the
/// sidebar: the console's nav is only in the tree above
/// [AppLayout.sidebarDrawerBreakpoint] (below that it lives in a
/// drawer), and the default 800x600 test surface is under that. Going by
/// location also keeps the tests honest about the URL contract.
Future<void> goTo(WidgetTester tester, String location) async {
  final context = tester.element(find.byType(Navigator).first);
  GoRouter.of(context).go(location);
  await settle(tester);
}

/// The location the pumped app is currently showing, query included —
/// the URL contract a browser refresh has to reproduce.
String currentLocation(WidgetTester tester) {
  final context = tester.element(find.byType(Navigator).first);
  return GoRouter.of(context).routeInformationProvider.value.uri.toString();
}

/// Runs [body] with a desktop-sized surface so the console renders its
/// expanded sidebar and any master-detail split, then restores the
/// default. Use for anything that asserts on the split layout.
Future<void> withWideSurface(
  WidgetTester tester,
  Future<void> Function() body, {
  Size size = const Size(1440, 900),
}) async {
  // Set the view directly (not `setSurfaceSize`): the shell reads
  // `MediaQuery.sizeOf`, which is derived from the view's physical size
  // and DPR, and a DPR of 1 keeps logical == physical so the numbers in
  // the test match the breakpoints in `AppLayout`.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}

/// Bounded settle for drift-stream-backed pages. `pumpAndSettle` never
/// idles here (a live `.watch()` subscription keeps a frame scheduled),
/// so instead we pump a fixed number of frames — enough for async chains
/// like mock-login delay → redirect → route transition → stream emit to
/// complete, without the infinite wait.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// 사이드바 배지를 **멈춘 값**으로 고정하는 override 묶음.
///
/// 실 API 모드로 콘솔을 띄우는 위젯 테스트용이다. 배지 세 개(안읽음 메시지·
/// 알림·상담 요청)는 실 백엔드에서 주기적으로 다시 읽는다(#917). 배지를 보지도
/// 않는 테스트가 그 타이머를 안고 끝나면 `flutter_test` 가 "A Timer is still
/// pending" 으로 실패하는데, 그건 그 테스트가 검증하려던 것과 아무 상관이 없다.
///
/// **배지 자체를 검증하는 테스트는 이 묶음을 쓰지 않는다** — 멈춰 둔 값을 보고
/// 통과하면 배지가 살아 있는지 아무것도 증명하지 못한다. 데모(목) 모드 테스트도
/// 마찬가지로 쓰지 않는다. 그쪽은 폴링이 아니라 drift 스트림이라 타이머가 없다.
List<Override> stillBadges() => <Override>[
  unreadCountsProvider.overrideWith(
    (ref) => Stream<Map<String, int>>.value(const <String, int>{}),
  ),
  trainerUnreadNotificationsProvider.overrideWith(
    (ref) => Stream<int>.value(0),
  ),
  consultationPendingCountProvider.overrideWith((ref) => Stream<int>.value(0)),
];

/// 회원 명단·식단·운동 기록을 **멈춘 빈 값**으로 고정하는 override.
///
/// 실 API 의 명단은 주기적으로 다시 읽는다(#918). 명단을 쓰지 않는 화면을
/// 검증하는 테스트(가입 흐름처럼 대시보드에 잠깐 내려앉을 뿐인 경우)는 그
/// 타이머까지 안고 끝날 이유가 없다. 자기 명단을 직접 넣는 테스트는 이걸
/// 쓰지 말고 그 저장소를 그대로 주입한다 — 여기서 덮으면 넣어 준 회원이
/// 사라진다.
Override stillRoster() =>
    clientRepositoryProvider.overrideWithValue(const _StillClientRepository());

/// 아무것도 돌려주지 않고 아무 타이머도 걸지 않는 명단 저장소.
class _StillClientRepository implements ClientRepository {
  @override
  Future<void> restoreClient(String id) async {}
  const _StillClientRepository();

  @override
  bool get supportsRosterMutations => false;

  @override
  Stream<List<TrainerClient>> watchClients() =>
      Stream<List<TrainerClient>>.value(const <TrainerClient>[]);

  @override
  Stream<Map<String, DateTime>> watchLastChatAt() =>
      Stream<Map<String, DateTime>>.value(const <String, DateTime>{});

  @override
  Stream<List<ClientDietEntry>> watchDiet(String clientId) =>
      Stream<List<ClientDietEntry>>.value(const <ClientDietEntry>[]);

  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) =>
      Stream<List<RoutineHistoryEntry>>.value(const <RoutineHistoryEntry>[]);

  @override
  Future<RoutineHistoryEntry> updateHistoryFeedback(
    String clientId,
    String historyId,
    String feedback,
  ) => throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<MemberHealthProfile> fetchHealthProfile(String clientId) =>
      throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<MemberHealthProfile> updateHealthProfile(
    String clientId,
    Map<String, Object?> values,
  ) => throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<ClientExerciseWeek> fetchExerciseWeek(
    String clientId, {
    DateTime? weekStart,
  }) => throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<String> fetchDietAdvice(String clientId, ClientPeriod period) =>
      throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<String> fetchExerciseAdvice(String clientId, ClientPeriod period) =>
      throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<List<ClientDietEntry>> fetchDietOn(String clientId, DateTime date) =>
      throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<List<String>> fetchExercisesOn(String clientId, DateTime date) =>
      throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<ClientDietPeriod> fetchDietPeriod(
    String clientId,
    ClientDateRange range,
  ) => throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<bool> clientNameExists(String name) =>
      throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<bool> addClient({required String name, required String goal}) =>
      throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<void> setClientActive(String id, bool active) =>
      throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');

  @override
  Future<void> removeClient(String id) =>
      throw UnsupportedError('명단을 멈춰 둔 테스트용 저장소다.');
}
