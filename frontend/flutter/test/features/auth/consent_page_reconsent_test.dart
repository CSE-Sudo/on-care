/// 재동의 계정이 동의 화면을 지난 뒤 갈 곳 — #3231.
///
/// 문서 버전이 올라 재동의가 남은 계정은 로그인 화면이 첫 화면을 정하려 읽은
/// 프로필이 403(`consent_required`)으로 실패한 채 캐시에 남는다. 로그인이 기기의
/// 첫 설정 기록도 지우므로, 동의 뒤 그 캐시로 다시 판단하면 첫 설정을 마친
/// 회원이 첫 설정 화면으로 간다 — 끝까지 가면 신체정보·목표가 기본값으로 덮인다.
///
/// 저장 요청 중 토큰이 회전돼도 같은 세션이므로 동의가 풀리고, 결과를 버린
/// 경우에도 화면이 로딩에 묶이지 않는다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/account/presentation/first_run_route.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/pages/consent_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/network/session_refresh.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 동의 전에는 데이터 조회를 403 으로 막는 서버. 동의를 받으면 푼다.
class _Server {
  _Server({this.consentResult = const <String, Object?>{}});

  /// 동의 저장 응답에 덧붙일 칸.
  final Map<String, Object?> consentResult;

  /// 동의 저장 요청이 서버에 닿은 순간 부른다 — 응답 전에 토큰을 회전시킨다.
  Future<void> Function()? onConsentRequest;

  bool consented = false;
  final List<RequestOptions> requests = <RequestOptions>[];

  late final Dio dio = Dio(BaseOptions(baseUrl: _config.apiBaseUrl))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest:
            (RequestOptions options, RequestInterceptorHandler handler) async {
              requests.add(options);
              final String route =
                  '${options.method.toUpperCase()} ${options.path}';
              Response<Object?> ok(Object? data, [int status = 200]) =>
                  Response<Object?>(
                    requestOptions: options,
                    statusCode: status,
                    data: data,
                  );
              switch (route) {
                case 'POST /auth/login':
                  handler.resolve(
                    ok(<String, Object?>{
                      'access_token': 'access-1',
                      'refresh_token': 'refresh-1',
                      'consent_required': true,
                    }),
                  );
                case 'POST /auth/refresh':
                  handler.resolve(
                    ok(<String, Object?>{
                      'access_token': 'access-2',
                      'refresh_token': 'refresh-2',
                    }),
                  );
                case 'POST /auth/logout':
                  handler.resolve(ok(null, 204));
                case 'POST /users/me/consents':
                  await onConsentRequest?.call();
                  consented = true;
                  handler.resolve(
                    ok(<String, Object?>{
                      'consent_required': false,
                      'consent_pending': <String>[],
                      ...consentResult,
                    }),
                  );
                case 'GET /users/me/profile':
                  if (!consented) {
                    handler.reject(
                      DioException(
                        requestOptions: options,
                        type: DioExceptionType.badResponse,
                        response: Response<Object?>(
                          requestOptions: options,
                          statusCode: 403,
                          data: <String, Object?>{
                            'detail': <String, Object?>{
                              'code': 'consent_required',
                            },
                          },
                        ),
                      ),
                    );
                    return;
                  }
                  // 첫 설정을 이미 마친 회원.
                  handler.resolve(
                    ok(<String, Object?>{
                      'id': 'u1',
                      'name': '김민수',
                      'email': 'm@oncare.com',
                      'onboarded': true,
                    }),
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

  int count(String path) =>
      requests.where((RequestOptions r) => r.path == path).length;
}

Future<(ProviderContainer, GoRouter)> _pump(
  WidgetTester tester,
  _Server server,
) async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  // 이 기기에는 첫 설정을 끝냈다는 기록이 있었다 — 로그인이 지운다.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await AppPrefs(prefs).setOnboardingDone(true);
  addTearDown(server.dio.close);
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_config),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(server.dio),
      sharedPreferencesProvider.overrideWithValue(prefs),
      sessionFeatureResetOverride(),
    ],
  );
  addTearDown(container.dispose);
  final GoRouter router = GoRouter(
    initialLocation: AppRoutes.consent,
    routes: <RouteBase>[
      GoRoute(path: AppRoutes.consent, builder: (_, _) => const ConsentPage()),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, _) => const Scaffold(body: Text('첫 설정')),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (_, _) => const Scaffold(body: Text('홈')),
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
  return (container, router);
}

/// 로그인 화면이 하는 일을 그대로 한다 — 로그인하고 첫 화면을 정한다.
Future<void> _signInLikeSignInPage(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.runAsync(() async {
    await container
        .read(sessionControllerProvider.notifier)
        .login(email: 'm@oncare.com', password: 'pw-12345678');
    // 동의가 남아 403 을 받는다 — 그 오류가 프로필 캐시에 남는다.
    expect(await firstRouteAfterSignIn(container), AppRoutes.onboarding);
  });
  await tester.pump();
  expect(container.read(sessionControllerProvider).consentRequired, isTrue);
}

Future<void> _agreeAndSubmit(WidgetTester tester) async {
  final Finder all = find.byKey(const ValueKey<String>('consent-all'));
  await tester.ensureVisible(all);
  await tester.tap(all);
  await tester.pump();
  final Finder submit = find.byKey(const ValueKey<String>('consent-submit'));
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  for (int i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<AppButton>(find.byKey(ValueKey<String>(key))).onPressed !=
    null;

void main() {
  testWidgets('첫 설정을 마친 회원은 재동의 뒤 첫 설정 화면으로 가지 않는다', (tester) async {
    final _Server server = _Server();
    final (ProviderContainer container, GoRouter router) = await _pump(
      tester,
      server,
    );
    await _signInLikeSignInPage(tester, container);

    await _agreeAndSubmit(tester);

    expect(container.read(sessionControllerProvider).consentRequired, isFalse);
    // 403 캐시를 버리고 프로필을 다시 받았다.
    expect(server.count('/users/me/profile'), 2);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      isNot(AppRoutes.onboarding),
    );
    expect(find.text('첫 설정'), findsNothing);
    // 기기 기록도 다시 남는다.
    expect(container.read(appPrefsProvider).onboardingDone, isTrue);
  });

  testWidgets('저장 중 토큰이 회전돼도 같은 세션이라 동의가 풀린다', (tester) async {
    final _Server server = _Server();
    final (ProviderContainer container, GoRouter _) = await _pump(
      tester,
      server,
    );
    await _signInLikeSignInPage(tester, container);
    server.onConsentRequest = () async {
      final TokenRefreshResult result = await container
          .read(sessionControllerProvider.notifier)
          .refreshAfterUnauthorized('access-1');
      expect(result.accessToken, 'access-2');
    };

    await _agreeAndSubmit(tester);

    expect(container.read(authAccessTokenProvider), 'access-2');
    expect(container.read(sessionControllerProvider).consentRequired, isFalse);
  });

  testWidgets('서버가 아직 동의가 남았다고 하면 화면이 로딩에 묶이지 않는다', (tester) async {
    final _Server server = _Server(
      consentResult: const <String, Object?>{'consent_required': true},
    );
    final (ProviderContainer container, GoRouter _) = await _pump(
      tester,
      server,
    );
    await _signInLikeSignInPage(tester, container);

    await _agreeAndSubmit(tester);

    expect(container.read(sessionControllerProvider).consentRequired, isTrue);
    expect(find.byType(ConsentPage), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey<String>('consent-submit')),
          )
          .loading,
      isFalse,
    );
    expect(_enabled(tester, 'consent-sign-out'), isTrue);
  });
}
