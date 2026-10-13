/// 동의하지 않은 회원의 탈퇴 — #3340.
///
/// 소셜 첫 로그인처럼 계정이 먼저 생기고 동의 화면이 뒤따르는 흐름에서, 동의하지
/// 않기로 한 회원에게 로그아웃만 남으면 계정을 지울 길이 없다. 동의 화면이 MY 의
/// 탈퇴 화면을 그대로 열고, 가드는 그 화면만 열어 둔다.
///
/// 동의가 남은 계정은 프로필이 403 이다 — 본인 확인을 비밀번호로 받을지 소셜
/// 재로그인으로 받을지는 `GET /users/me` 로 읽는다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/pages/consent_page.dart';
import 'package:oncare/features/my_health/presentation/controllers/withdraw_preview_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/withdraw_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_account_repository.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 본인 확인에서 맞다고 보는 현재 비밀번호. 테스트 전용 값이다.
const String _currentPassword = 'pw-current-1';

/// 동의가 남은 계정 — 프로필은 403 으로 막힌다.
class _Repository extends MockAccountRepository {
  _Repository() : super(currentPassword: _currentPassword);

  @override
  Future<UserProfile> fetchProfile() async {
    throw DioException(
      requestOptions: RequestOptions(path: '/users/me/profile'),
      type: DioExceptionType.badResponse,
      response: Response<Object?>(
        requestOptions: RequestOptions(path: '/users/me/profile'),
        statusCode: 403,
      ),
    );
  }
}

/// 로그인·로그아웃만 받는 서버. 로그인 응답이 동의가 남았다고 알린다.
Dio _server(List<String> calls) {
  return Dio(BaseOptions(baseUrl: _config.apiBaseUrl))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final String route =
              '${options.method.toUpperCase()} ${options.path}';
          calls.add(route);
          switch (route) {
            case 'POST /auth/login':
              handler.resolve(
                Response<Object?>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, Object?>{
                    'access_token': 'access-1',
                    'refresh_token': 'refresh-1',
                    'consent_required': true,
                  },
                ),
              );
            case 'POST /auth/logout':
              handler.resolve(
                Response<Object?>(requestOptions: options, statusCode: 204),
              );
            default:
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<Object?>(
                    requestOptions: options,
                    statusCode: 404,
                  ),
                ),
              );
          }
        },
      ),
    );
}

Future<(ProviderContainer, GoRouter, _Repository)> _pump(
  WidgetTester tester, {
  bool hasPassword = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final Dio dio = _server(<String>[]);
  addTearDown(dio.close);
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final _Repository repository = _Repository()..hasPassword = hasPassword;
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_config),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(dio),
      sharedPreferencesProvider.overrideWithValue(prefs),
      accountRepositoryProvider.overrideWithValue(repository),
      withdrawPreviewLoaderProvider.overrideWithValue(
        repository.fetchDeletionPreview,
      ),
      sessionFeatureResetOverride(),
    ],
  );
  addTearDown(container.dispose);

  // 앱과 같은 가드를 건다 — 세션이 바뀔 때마다 다시 판단한다.
  final ValueNotifier<int> refresh = ValueNotifier<int>(0);
  addTearDown(refresh.dispose);
  container.listen<SessionState>(
    sessionControllerProvider,
    (_, _) => refresh.value++,
  );
  final GoRouter router = GoRouter(
    initialLocation: AppRoutes.signIn,
    refreshListenable: refresh,
    redirect: (_, GoRouterState state) {
      final SessionState session = container.read(sessionControllerProvider);
      return sessionRedirect(
        session.status,
        state.matchedLocation,
        consentRequired: session.consentRequired,
      );
    },
    routes: <RouteBase>[
      GoRoute(path: AppRoutes.consent, builder: (_, _) => const ConsentPage()),
      GoRoute(
        path: AppRoutes.mySettings,
        builder: (_, GoRouterState state) =>
            state.pathParameters['section'] == AppRoutes.withdrawSettingsSection
            ? const WithdrawPage()
            : const Scaffold(body: Text('다른 설정')),
      ),
      GoRoute(
        path: AppRoutes.myHealth,
        builder: (_, _) => const Scaffold(body: Text('MY')),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (_, _) => const Scaffold(body: Text('홈')),
      ),
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => const Scaffold(body: Text('시작 화면')),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (_, _) => const Scaffold(body: Text('로그인 화면')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();

  // 로그인하면 동의가 남아 가드가 동의 화면에 세운다.
  await tester.runAsync(() async {
    await container
        .read(sessionControllerProvider.notifier)
        .login(email: 'm@oncare.com', password: 'pw-12345678');
  });
  await tester.pumpAndSettle();
  expect(container.read(sessionControllerProvider).consentRequired, isTrue);
  expect(find.byType(ConsentPage), findsOneWidget);
  return (container, router, repository);
}

/// 맨 위에 놓인 화면의 주소. 동의 화면 위로 민(push) 화면도 그 주소로 읽는다.
String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

Finder _withdrawLink() =>
    find.byKey(const ValueKey<String>('consent-withdraw'));

Future<void> _openWithdraw(WidgetTester tester) async {
  await tester.ensureVisible(_withdrawLink());
  await tester.tap(_withdrawLink());
  await tester.pumpAndSettle();
}

/// 사유 칸을 건너뛰고 확인창까지 간다.
Future<void> _reachConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('withdrawNextButton')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('withdrawContinueButton')),
  );
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('동의 화면에 계정 탈퇴가 있다 — 로그아웃 아래, 위험 동작의 글자 버튼', (tester) async {
    await _pump(tester);
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ConsentPage)),
    );

    final AppButton link = tester.widget<AppButton>(_withdrawLink());
    expect(link.label, l.myWithdrawTitle);
    expect(link.variant, AppButtonVariant.destructiveText);
    expect(link.onPressed, isNotNull);
    expect(
      tester.getTopLeft(_withdrawLink()).dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('consent-sign-out')))
            .dy,
      ),
    );
  });

  testWidgets('탈퇴를 누르면 MY 의 탈퇴 화면이 그대로 열린다', (tester) async {
    final (_, GoRouter router, _Repository repository) = await _pump(tester);

    await _openWithdraw(tester);

    expect(find.byType(WithdrawPage), findsOneWidget);
    expect(_location(router), AppRoutes.withdraw);
    // 여는 것만으로는 아무것도 지우지 않는다.
    expect(repository.lastReauth, isNull);
  });

  testWidgets('탈퇴 화면에서 다른 화면으로는 여전히 못 간다', (tester) async {
    final (_, GoRouter router, _) = await _pump(tester);
    await _openWithdraw(tester);

    for (final String path in <String>[
      AppRoutes.dashboard,
      AppRoutes.myHealth,
      AppRoutes.mySettingsPath('support'),
      AppRoutes.mySettingsPath('profile'),
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(_location(router), AppRoutes.consent, reason: path);
      expect(find.byType(ConsentPage), findsOneWidget, reason: path);

      await _openWithdraw(tester);
      expect(find.byType(WithdrawPage), findsOneWidget, reason: path);
    }
  });

  testWidgets('뒤로 가면 동의 화면이다 — 동의할 길은 그대로 남는다', (tester) async {
    final (ProviderContainer container, GoRouter router, _) = await _pump(
      tester,
    );
    await _openWithdraw(tester);

    await tester.tap(find.byKey(const ValueKey<String>('withdrawNextButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('withdrawStayButton')));
    await tester.pumpAndSettle();

    expect(find.byType(ConsentPage), findsOneWidget);
    expect(_location(router), AppRoutes.consent);
    expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);
  });

  testWidgets('주소로 곧장 열린 탈퇴 화면에서 머물기를 고르면 동의 화면으로 돌아간다', (tester) async {
    final (_, GoRouter router, _) = await _pump(tester);
    // 웹 새로고침처럼 아래에 깔린 화면이 없다.
    router.go(AppRoutes.withdraw);
    await tester.pumpAndSettle();
    expect(find.byType(WithdrawPage), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('withdrawNextButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('withdrawStayButton')));
    await tester.pumpAndSettle();

    expect(_location(router), AppRoutes.consent);
    expect(find.byType(ConsentPage), findsOneWidget);
  });

  testWidgets('비밀번호 계정은 비밀번호를 확인하고 탈퇴한 뒤 로그인 화면으로 간다', (tester) async {
    final (
      ProviderContainer container,
      GoRouter router,
      _Repository repository,
    ) = await _pump(
      tester,
    );
    await _openWithdraw(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('withdrawReason-privacy')),
    );
    await tester.pump();
    await _reachConfirm(tester);

    // 막힌 프로필 대신 `GET /users/me` 로 본인 확인 방법을 읽었다.
    expect(repository.hasPasswordReads, 1);
    expect(
      find.byKey(const ValueKey<String>('reauth-password')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('reauth-password')),
      _currentPassword,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('reauth-confirm')));
    await _settle(tester);

    expect(repository.lastReauth?.currentPassword, _currentPassword);
    expect(repository.deletedWithReasons, <String>['privacy']);
    final SessionState session = container.read(sessionControllerProvider);
    expect(session.status, SessionStatus.signedOut);
    expect(session.consentRequired, isFalse);
    expect(_location(router), AppRoutes.signIn);
    expect(find.text('로그인 화면'), findsOneWidget);
  });

  testWidgets('소셜로 처음 들어온 계정은 비밀번호 칸이 아니라 다시 로그인으로 확인한다', (tester) async {
    final (
      ProviderContainer container,
      GoRouter router,
      _Repository repository,
    ) = await _pump(
      tester,
      hasPassword: false,
    );
    await _openWithdraw(tester);
    await _reachConfirm(tester);

    expect(repository.hasPasswordReads, 1);
    expect(find.byKey(const ValueKey<String>('reauth-password')), findsNothing);
    final Finder kakao = find.byKey(
      const ValueKey<String>('reauth-social-kakao'),
    );
    expect(kakao, findsOneWidget);

    await tester.tap(kakao);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('reauth-confirm')));
    await _settle(tester);

    expect(repository.lastReauth?.socialProvider, 'kakao');
    expect(container.read(sessionControllerProvider).isAuthenticated, isFalse);
    expect(_location(router), AppRoutes.signIn);
  });

  testWidgets('확인창을 취소하면 계정도 세션도 그대로다', (tester) async {
    final (
      ProviderContainer container,
      GoRouter router,
      _Repository repository,
    ) = await _pump(
      tester,
    );
    await _openWithdraw(tester);
    await _reachConfirm(tester);

    await tester.tap(find.byKey(const ValueKey<String>('reauth-cancel')));
    await tester.pumpAndSettle();

    expect(repository.lastReauth, isNull);
    expect(find.byType(WithdrawPage), findsOneWidget);
    expect(_location(router), AppRoutes.withdraw);
    final SessionState session = container.read(sessionControllerProvider);
    expect(session.isAuthenticated, isTrue);
    expect(session.consentRequired, isTrue);
  });
}
