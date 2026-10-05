/// 세션이 끝나면 계정에 매인 기기 기록을 모두 지운다. (#3154)
///
/// 계정에 매인 기기 기록은 첫 설정(`onboarding_done`)과 홈 가이드
/// (`home_guide_done`) 두 가지다. 둘을 함께 지우는 [AppPrefs.clearAccountScoped]
/// 는 탈퇴할 때만 불렸고, 로그아웃·만료는 첫 설정 기록만 지웠다. 그래서 같은
/// 기기(가족 휴대폰·헬스장 공용 태블릿)에서 계정만 바꿔 로그인한 새 회원은 앞
/// 계정이 끝낸 홈 가이드를 한 번도 보지 못했다.
///
/// 여기서는 세션이 끝나는 세 길 — 직접 로그아웃, 저장된 세션의 만료, 실행 중
/// 갱신 거부로 인한 강제 로그아웃 — 이 모두 두 기록을 지우고, 언어와 설치 표식은
/// 남기는지 본다. 세션이 끝나지 않는 경우(같은 토큰으로 복구, 일시적 실패)는
/// 기록을 이어 쓴다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/features/app_guide/presentation/controllers/app_guide_controller.dart';
import 'package:oncare/features/app_guide/presentation/pages/guide_tour_page.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/network/session_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 첫 설정과 홈 가이드를 모두 끝낸 기기. 언어를 골라 두었고, 설치 표식도 있다.
const Map<String, Object> _seenDevice = <String, Object>{
  'onboarding_done': true,
  'home_guide_done': true,
  'locale_code': 'en',
  'installed': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, AppPrefs)> start({
    required Map<String, int> statusByPath,
    Map<String, Object> stored = _seenDevice,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final SharedPreferences shared = await SharedPreferences.getInstance();
    final Dio dio = _scriptedDio(statusByPath);
    addTearDown(dio.close);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        dioProvider.overrideWithValue(dio),
        sharedPreferencesProvider.overrideWithValue(shared),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionControllerProvider.notifier);
    return (container, container.read(appPrefsProvider));
  }

  SessionStatus statusOf(ProviderContainer container) =>
      container.read(sessionControllerProvider).status;

  /// 기기의 것은 남았는가 — 언어와 설치 표식.
  void expectDeviceRecordsKept(AppPrefs prefs) {
    expect(prefs.localeCode, 'en');
    expect(prefs.installed, isTrue);
  }

  /// 계정의 것은 지워졌는가 — 첫 설정과 홈 가이드.
  void expectAccountRecordsCleared(AppPrefs prefs) {
    expect(prefs.onboardingDone, isFalse);
    expect(prefs.homeGuideDone, isFalse);
  }

  group('AppPrefs.clearAccountScoped', () {
    test('첫 설정·홈 가이드 기록을 지우고 언어·설치 표식은 남긴다', () async {
      SharedPreferences.setMockInitialValues(_seenDevice);
      final AppPrefs prefs = AppPrefs(await SharedPreferences.getInstance());

      await prefs.clearAccountScoped();

      expectAccountRecordsCleared(prefs);
      expectDeviceRecordsKept(prefs);
    });

    test('지울 기록이 없어도 실패하지 않는다', () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final AppPrefs prefs = AppPrefs(await SharedPreferences.getInstance());

      await prefs.clearAccountScoped();

      expectAccountRecordsCleared(prefs);
      expect(prefs.localeCode, isNull);
    });

    test('첫 설정 기록만 지우는 함수는 홈 가이드를 건드리지 않는다', () async {
      // 로그인 때 쓰는 좁은 정리(#2630)는 그대로다.
      SharedPreferences.setMockInitialValues(_seenDevice);
      final AppPrefs prefs = AppPrefs(await SharedPreferences.getInstance());

      await prefs.forgetOnboardingDone();

      expect(prefs.onboardingDone, isFalse);
      expect(prefs.homeGuideDone, isTrue);
      expectDeviceRecordsKept(prefs);
    });
  });

  group('세션이 끝나는 길마다 지운다', () {
    test('직접 로그아웃', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/auth/login': 200, '/auth/logout': 200},
      );
      await _waitFor(() => statusOf(container) == SessionStatus.signedOut);
      await container
          .read(sessionControllerProvider.notifier)
          .login(email: 'a@oncare.com', password: 'password');
      // 로그인 뒤 그 계정이 첫 설정과 가이드를 마쳤다.
      await prefs.setOnboardingDone(true);
      await prefs.setHomeGuideDone(true);

      await container.read(sessionControllerProvider.notifier).signOut();

      expect(statusOf(container), SessionStatus.signedOut);
      expectAccountRecordsCleared(prefs);
      expectDeviceRecordsKept(prefs);
    });

    test('서버 폐기가 실패해도 지운다', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'stored-access',
        'refresh_token': 'stored-refresh',
      });
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/users/me': 200, '/auth/logout': 503},
      );
      await _waitFor(() => statusOf(container) == SessionStatus.authenticated);

      await container.read(sessionControllerProvider.notifier).signOut();

      expect(statusOf(container), SessionStatus.signedOut);
      expectAccountRecordsCleared(prefs);
      expectDeviceRecordsKept(prefs);
    });

    test('저장된 세션이 401 로 끝나고 갱신 수단이 없을 때', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'stored-access',
      });
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/users/me': 401},
      );
      await _waitFor(() => statusOf(container) == SessionStatus.signedOut);

      expectAccountRecordsCleared(prefs);
      expectDeviceRecordsKept(prefs);
    });

    test('저장된 세션의 갱신이 거부될 때', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'stored-access',
        'refresh_token': 'stored-refresh',
      });
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/users/me': 401, '/auth/refresh': 401},
      );
      await _waitFor(() => statusOf(container) == SessionStatus.signedOut);

      expectAccountRecordsCleared(prefs);
      expectDeviceRecordsKept(prefs);
    });

    test('저장된 토큰이 다른 역할 것이라 403 일 때', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'stored-access',
        'refresh_token': 'stored-refresh',
      });
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/users/me': 403},
      );
      await _waitFor(() => statusOf(container) == SessionStatus.signedOut);

      expectAccountRecordsCleared(prefs);
      expectDeviceRecordsKept(prefs);
    });

    test('실행 중 갱신이 거부되어 강제로 로그아웃될 때', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final Map<String, int> statusByPath = <String, int>{'/auth/login': 200};
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: statusByPath,
      );
      await _waitFor(() => statusOf(container) == SessionStatus.signedOut);
      final SessionController controller = container.read(
        sessionControllerProvider.notifier,
      );
      await controller.login(email: 'a@oncare.com', password: 'password');
      await prefs.setOnboardingDone(true);
      await prefs.setHomeGuideDone(true);

      // 하루가 지나 접근 토큰이 만료됐고, 갱신 토큰도 서버가 받지 않는다.
      statusByPath['/auth/refresh'] = 401;
      final TokenRefreshResult result = await controller
          .refreshAfterUnauthorized('next-access');

      expect(result.status, TokenRefreshStatus.rejected);
      expect(statusOf(container), SessionStatus.signedOut);
      expect(container.read(sessionExpiredNoticeProvider), isTrue);
      expectAccountRecordsCleared(prefs);
      expectDeviceRecordsKept(prefs);
    });

    test('실행 중 401 인데 갱신 토큰이 없을 때', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/auth/login': 200},
      );
      await _waitFor(() => statusOf(container) == SessionStatus.signedOut);
      final SessionController controller = container.read(
        sessionControllerProvider.notifier,
      );
      await controller.login(email: 'a@oncare.com', password: 'password');
      await prefs.setHomeGuideDone(true);
      // 갱신 토큰을 읽을 수 없는 기기 — 저장소가 비었다.
      await container.read(secureTokenStoreProvider).clear();

      await controller.refreshAfterUnauthorized('next-access');

      expect(statusOf(container), SessionStatus.signedOut);
      expectAccountRecordsCleared(prefs);
      expectDeviceRecordsKept(prefs);
    });
  });

  group('세션이 끝나지 않으면 이어 쓴다', () {
    test('같은 토큰으로 되살아나면 홈 가이드 기록이 남는다', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'stored-access',
      });
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/users/me': 200},
      );
      await _waitFor(() => statusOf(container) == SessionStatus.authenticated);

      expect(prefs.onboardingDone, isTrue);
      expect(prefs.homeGuideDone, isTrue);
    });

    test('복구가 일시적으로 실패하면 남는다', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'stored-access',
      });
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/users/me': 503},
      );
      await _waitFor(
        () => container.read(sessionControllerProvider).restoreFailed,
      );

      expect(prefs.onboardingDone, isTrue);
      expect(prefs.homeGuideDone, isTrue);
    });

    test('실행 중 갱신이 서버 오류로 실패하면 세션도 기록도 남는다', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final Map<String, int> statusByPath = <String, int>{'/auth/login': 200};
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: statusByPath,
      );
      await _waitFor(() => statusOf(container) == SessionStatus.signedOut);
      final SessionController controller = container.read(
        sessionControllerProvider.notifier,
      );
      await controller.login(email: 'a@oncare.com', password: 'password');
      await prefs.setHomeGuideDone(true);

      statusByPath['/auth/refresh'] = 503;
      final TokenRefreshResult result = await controller
          .refreshAfterUnauthorized('next-access');

      expect(result.status, TokenRefreshStatus.unavailable);
      expect(statusOf(container), SessionStatus.authenticated);
      expect(prefs.homeGuideDone, isTrue);
    });

    test('복구를 접고 로그인 화면으로 가는 것은 로그아웃이 아니다', () async {
      // 저장된 토큰을 남기는 탈출구(#1944) — 다음 실행에서 같은 계정이 돌아온다.
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'stored-access',
      });
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/users/me': 503},
      );
      await _waitFor(
        () => container.read(sessionControllerProvider).restoreFailed,
      );

      container.read(sessionControllerProvider.notifier).dismissRestore();

      expect(prefs.homeGuideDone, isTrue);
    });
  });

  group('같은 기기에서 계정 전환', () {
    test('A 가 가이드를 끝내고 로그아웃하면, B 는 가이드를 처음부터 본다', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final (ProviderContainer container, AppPrefs prefs) = await start(
        statusByPath: <String, int>{'/auth/login': 200},
        stored: const <String, Object>{'locale_code': 'en', 'installed': true},
      );
      await _waitFor(() => statusOf(container) == SessionStatus.signedOut);
      final SessionController session = container.read(
        sessionControllerProvider.notifier,
      );
      final AppGuideController guide = container.read(
        appGuideControllerProvider.notifier,
      );

      // A: 로그인 → 가이드를 끝까지 본다.
      await session.login(email: 'a@oncare.com', password: 'password');
      guide.start();
      expect(container.read(appGuideControllerProvider).active, isTrue);
      guide.skip();
      expect(prefs.homeGuideDone, isTrue);
      guide.start();
      expect(
        container.read(appGuideControllerProvider).active,
        isFalse,
        reason: 'A 는 이미 봤다',
      );

      // A 로그아웃 → B 로그인.
      await session.signOut();
      await session.login(email: 'b@oncare.com', password: 'password');

      guide.start();
      expect(container.read(appGuideControllerProvider).active, isTrue);
      expect(container.read(appGuideControllerProvider).stepNumber, 1);
      expectDeviceRecordsKept(prefs);
    });
  });

  testWidgets('계정 전환 뒤 홈 진입 시 가이드가 다시 뜬다', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 840));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    // 앞 계정이 가이드를 끝낸 기기.
    SharedPreferences.setMockInitialValues(_seenDevice);
    final SharedPreferences shared = await SharedPreferences.getInstance();
    final Dio dio = _scriptedDio(<String, int>{'/auth/login': 200});
    addTearDown(dio.close);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        dioProvider.overrideWithValue(dio),
        sharedPreferencesProvider.overrideWithValue(shared),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'https://dev.api.test',
            useMockApi: true,
          ),
        ),
        appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
      ],
    );
    addTearDown(container.dispose);

    // 앞 계정 로그아웃 → 다음 계정 로그인. 저장소 비동기는 실제 시간으로 돌린다.
    await tester.runAsync(() async {
      container.read(sessionControllerProvider.notifier);
      await _waitFor(() => statusOf(container) == SessionStatus.signedOut);
      final SessionController session = container.read(
        sessionControllerProvider.notifier,
      );
      await session.signOut();
      await session.login(email: 'b@oncare.com', password: 'password');
    });
    expect(statusOf(container), SessionStatus.authenticated);

    final GoRouter router = GoRouter(
      initialLocation: AppRoutes.guideTour,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.guideTour,
          builder: (_, _) => const GuideTourPage(),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (_, _) => const Scaffold(body: Text('dashboard-route')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 앞 계정 기록 때문에 홈으로 튕기지 않고, 예시 화면 위에서 가이드가 선다.
    expect(find.byKey(const Key('appGuideCard')), findsOneWidget);
    expect(find.text('dashboard-route'), findsNothing);
  });
}

/// 경로별 상태 코드로 답한다. 적지 않은 경로는 404. 200 이면 토큰 한 벌을 준다.
///
/// [statusByPath] 를 그대로 붙잡아 두므로, 테스트 도중 값을 바꾸면 다음 요청부터
/// 바뀐 상태로 답한다.
Dio _scriptedDio(Map<String, int> statusByPath) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        final int status = statusByPath[options.path] ?? 404;
        if (status >= 400) {
          handler.reject(
            DioException.badResponse(
              statusCode: status,
              requestOptions: options,
              response: Response<Object?>(
                requestOptions: options,
                statusCode: status,
              ),
            ),
          );
          return;
        }
        handler.resolve(
          Response<Map<String, Object?>>(
            requestOptions: options,
            statusCode: status,
            data: <String, Object?>{
              'access_token': 'next-access',
              'refresh_token': 'next-refresh',
            },
          ),
        );
      },
    ),
  );
  return dio;
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (condition()) {
      // 상태가 바뀐 뒤 남은 저장소 정리가 끝나도록 몇 틱 더 기다린다.
      for (var tick = 0; tick < 5; tick++) {
        await Future<void>.delayed(Duration.zero);
      }
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('조건이 채워지지 않았다');
}
