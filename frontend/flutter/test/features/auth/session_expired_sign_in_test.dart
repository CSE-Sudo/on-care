/// 실행 중 세션이 끝나면 로그인 화면으로 가고 까닭을 한 번 알린다. (#1546)
///
/// 갱신이 거부된 뒤 쓰던 화면이 아무 말 없이 로그인 폼으로 바뀌면, 회원은 무엇이
/// 잘못됐는지 모른다. 실제 세션 가드([sessionRedirect])와 로그인 화면을 띄워
/// 흐름 전체를 본다. 반대로 갱신이 성공하면 화면은 그대로여야 한다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/token_backend.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://api.test/v1',
  useMockApi: true,
);

const Key _loadButton = Key('load-today');

/// 로그인 뒤 화면 대신 — 버튼을 누르면 인증이 필요한 조회를 한 번 보낸다.
class _Home extends ConsumerStatefulWidget {
  const _Home();

  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  String _result = '대기';

  Future<void> _load() async {
    try {
      final Response<Object?> res = await ref
          .read(dioProvider)
          .get<Object?>('/data/today');
      if (!mounted) return;
      setState(
        () => _result = '받음 ${(res.data! as Map<String, Object?>)['token']}',
      );
    } on DioException {
      if (!mounted) return;
      setState(() => _result = '실패');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        TextButton(key: _loadButton, onPressed: _load, child: const Text('조회')),
        Text(_result),
      ],
    ),
  );
}

Future<(ProviderContainer, TokenBackend)> _pump(
  WidgetTester tester, {
  required Locale locale,
}) async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    'access_token': 'access-0',
    'refresh_token': 'refresh-0',
  });
  final TokenBackend backend = TokenBackend();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_config),
      dioProvider.overrideWith((ref) {
        final Dio dio = Dio(
          BaseOptions(
            baseUrl: _config.apiBaseUrl,
            validateStatus: (int? s) => s != null && s < 400,
          ),
        );
        dio.httpClientAdapter = backend;
        dio.interceptors.add(authInterceptorFor(ref, retryClient: dio));
        return dio;
      }),
    ],
  );
  addTearDown(container.dispose);

  final ValueNotifier<int> refresh = ValueNotifier<int>(0);
  addTearDown(refresh.dispose);
  container.listen<SessionState>(
    sessionControllerProvider,
    (_, _) => refresh.value++,
  );
  final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (_, GoRouterState state) => sessionRedirect(
      container.read(sessionControllerProvider).status,
      state.matchedLocation,
    ),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => const Scaffold(body: Text('시작')),
      ),
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInPage()),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (_, _) => const Scaffold(body: Text('가입')),
      ),
      GoRoute(path: AppRoutes.dashboard, builder: (_, _) => const _Home()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await _settle(tester);
  expect(find.byType(_Home), findsOneWidget);
  return (container, backend);
}

/// 가짜 서버·보안 저장소의 비동기 사슬과 화면 전환을 끝까지 돌린다.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 떠 있는 토스트가 스스로 닫히게 시간을 흘려 보낸다.
Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (final (Locale locale, String message) in <(Locale, String)>[
    (const Locale('ko'), '로그인이 만료되었어요. 다시 로그인해 주세요'),
    (const Locale('en'), 'Your sign-in has expired. Please sign in again'),
  ]) {
    testWidgets('갱신이 거부되면 로그인 화면으로 가고 안내한다 (${locale.languageCode})', (
      WidgetTester tester,
    ) async {
      final (ProviderContainer container, TokenBackend backend) = await _pump(
        tester,
        locale: locale,
      );
      backend
        ..expireAccessTokens()
        ..refreshMode = RefreshMode.reject401;

      await tester.tap(find.byKey(_loadButton));
      await _settle(tester);

      expect(find.byType(SignInPage), findsOneWidget);
      expect(find.byType(_Home), findsNothing);
      expect(find.text(message), findsOneWidget);
      // 안내는 한 번만 — 다시 들어와도 또 뜨지 않는다.
      expect(container.read(sessionExpiredNoticeProvider), isFalse);
      await _drainToast(tester);
    });
  }

  testWidgets('갱신이 성공하면 화면을 떠나지 않고 결과를 받는다', (WidgetTester tester) async {
    final (ProviderContainer container, TokenBackend backend) = await _pump(
      tester,
      locale: const Locale('ko'),
    );
    backend.expireAccessTokens();

    await tester.tap(find.byKey(_loadButton));
    await _settle(tester);

    expect(find.byType(_Home), findsOneWidget);
    expect(find.text('받음 access-1'), findsOneWidget);
    expect(find.byType(SignInPage), findsNothing);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
  });

  testWidgets('망이 끊겨 갱신 못 하면 화면에 남고 조회만 실패한다', (WidgetTester tester) async {
    final (ProviderContainer container, TokenBackend backend) = await _pump(
      tester,
      locale: const Locale('ko'),
    );
    backend
      ..expireAccessTokens()
      ..refreshMode = RefreshMode.offline;

    await tester.tap(find.byKey(_loadButton));
    await _settle(tester);

    expect(find.byType(_Home), findsOneWidget);
    expect(find.text('실패'), findsOneWidget);
    expect(find.text('로그인이 만료되었어요. 다시 로그인해 주세요'), findsNothing);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.authenticated,
    );
  });

  testWidgets('직접 로그아웃한 로그인 화면에는 만료 안내가 없다', (WidgetTester tester) async {
    final (ProviderContainer container, _) = await _pump(
      tester,
      locale: const Locale('ko'),
    );

    await tester.runAsync(
      () => container.read(sessionControllerProvider.notifier).signOut(),
    );
    await _settle(tester);

    expect(find.byType(SignInPage), findsOneWidget);
    expect(find.text('로그인이 만료되었어요. 다시 로그인해 주세요'), findsNothing);
  });
}
