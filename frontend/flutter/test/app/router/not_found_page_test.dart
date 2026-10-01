/// 회원 앱 404 화면. (#2633)
///
/// 라우터에 `errorBuilder` 가 없어 없는 주소로 들어가면 go_router 기본 오류
/// 화면(영어 한 줄, 나갈 길 없음)이 떴다. 이제 회원 앱 모양의 안내와 돌아갈
/// 버튼이 뜬다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/not_found_page.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/gen/l10n/app_localizations_en.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 어떤 화면과도 맞지 않는 주소들. 앞부분이 실제 화면인 깊은 주소도 넣는다.
const List<String> _unknownPaths = <String>[
  '/nope',
  '/dashboard/nope',
  '/my-health/points/history/extra',
  '/gyms/g1/extra/deeper',
];

Finder get _page => find.byKey(NotFoundPage.bodyKey);
Finder get _action => find.byKey(NotFoundPage.actionKey);

void main() {
  // 저장된 세션이 없다 — 세션 컨트롤러의 복구가 곧 로그아웃으로 끝난다.
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  group('NotFoundPage 판단', () {
    test('데모·로그인만 앱 안이다', () {
      expect(NotFoundPage.isInApp(SessionStatus.authenticated), isTrue);
      expect(NotFoundPage.isInApp(SessionStatus.demo), isTrue);
      expect(NotFoundPage.isInApp(SessionStatus.signedOut), isFalse);
      expect(NotFoundPage.isInApp(SessionStatus.unknown), isFalse);
    });

    test('앱 안이면 홈으로, 아니면 로그인 화면으로 보낸다', () {
      expect(
        NotFoundPage.homeFor(SessionStatus.authenticated),
        AppRoutes.dashboard,
      );
      expect(NotFoundPage.homeFor(SessionStatus.demo), AppRoutes.dashboard);
      expect(NotFoundPage.homeFor(SessionStatus.signedOut), AppRoutes.signIn);
      expect(NotFoundPage.homeFor(SessionStatus.unknown), AppRoutes.signIn);
    });

    test('로그인 상태에서는 가드가 없는 주소를 그대로 둔다 — 404 가 뜬다', () {
      for (final String path in _unknownPaths) {
        expect(
          sessionRedirect(SessionStatus.authenticated, path),
          isNull,
          reason: path,
        );
        expect(sessionRedirect(SessionStatus.demo, path), isNull, reason: path);
      }
    });

    test('로그아웃 상태에서는 가드가 먼저 로그인 화면으로 보낸다', () {
      for (final String path in _unknownPaths) {
        expect(
          sessionRedirect(SessionStatus.signedOut, path),
          AppRoutes.signIn,
          reason: path,
        );
      }
    });
  });

  group('앱 라우터 연결', () {
    Future<GoRouter> pumpUnknown(
      WidgetTester tester,
      String path, {
      Locale locale = const Locale('ko'),
    }) async {
      // 앞 주소의 앱을 걷어 내고 새로 띄운다 — 라우터를 갈아 끼우지 않는다.
      await tester.pumpWidget(const SizedBox.shrink());
      final GoRouter router = buildAppRouter(config: _config);
      addTearDown(router.dispose);
      router.go(path);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[appConfigProvider.overrideWithValue(_config)],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('없는 주소는 회원 앱 404 로 받고 주소는 그대로 둔다', (tester) async {
      for (final String path in _unknownPaths) {
        final GoRouter router = await pumpUnknown(tester, path);

        expect(_page, findsOneWidget, reason: path);
        expect(find.text(_ko.notFoundTitle), findsOneWidget, reason: path);
        expect(find.text(_ko.notFoundMessage), findsOneWidget, reason: path);
        // go_router 기본 오류 화면의 영어 문구가 보이지 않는다.
        expect(find.text('Page Not Found'), findsNothing, reason: path);
        expect(
          router.routeInformationProvider.value.uri.path,
          path,
          reason: path,
        );
      }
    });

    testWidgets('흰 바탕에 빈 화면 안내 부품으로 그린다', (tester) async {
      await pumpUnknown(tester, '/nope');

      final Scaffold scaffold = tester.widget<Scaffold>(
        find.ancestor(of: _page, matching: find.byType(Scaffold)).first,
      );
      expect(scaffold.backgroundColor, OnCareColors.surfaceCard);
      expect(
        find.descendant(of: _page, matching: find.byType(AppEmptyState)),
        findsOneWidget,
      );
    });

    testWidgets('영어 설정에서는 영어로 안내한다', (tester) async {
      await pumpUnknown(tester, '/nope', locale: const Locale('en'));

      expect(find.text(_en.notFoundTitle), findsOneWidget);
      expect(find.text(_en.notFoundMessage), findsOneWidget);
      expect(find.text(_ko.notFoundTitle), findsNothing);
    });
  });

  group('돌아가기 버튼', () {
    /// 404 와 돌아갈 두 곳만 있는 작은 라우터. 실제 홈·로그인 화면은 무거워
    /// 자리표시로 둔다 — 여기서 보는 것은 버튼이 어디로 보내는가다.
    Future<void> pumpMini(
      WidgetTester tester, {
      required ProviderContainer container,
      Locale locale = const Locale('ko'),
    }) async {
      final GoRouter router = GoRouter(
        initialLocation: '/nope',
        errorBuilder: (context, state) => const NotFoundPage(),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (context, state) => const Text('홈 화면'),
          ),
          GoRoute(
            path: AppRoutes.signIn,
            builder: (context, state) => const Text('로그인 화면'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ProviderContainer container() {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[appConfigProvider.overrideWithValue(_config)],
      );
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('앱 안(데모)이면 `홈으로` 가 대시보드로 보낸다', (tester) async {
      final ProviderContainer c = container();
      c.read(sessionControllerProvider.notifier).enterDemo();
      await pumpMini(tester, container: c);

      expect(find.text(_ko.notFoundGoHome), findsOneWidget);
      expect(find.text(_ko.notFoundGoSignIn), findsNothing);

      await tester.tap(_action);
      await tester.pumpAndSettle();

      expect(find.text('홈 화면'), findsOneWidget);
      expect(_page, findsNothing);
    });

    testWidgets('로그인 전이면 로그인 화면으로 보낸다', (tester) async {
      final ProviderContainer c = container();
      await pumpMini(tester, container: c);
      expect(
        c.read(sessionControllerProvider).status,
        isNot(SessionStatus.demo),
      );

      expect(find.text(_ko.notFoundGoSignIn), findsOneWidget);
      expect(find.text(_ko.notFoundGoHome), findsNothing);

      await tester.tap(_action);
      await tester.pumpAndSettle();

      expect(find.text('로그인 화면'), findsOneWidget);
    });

    testWidgets('영어 설정의 버튼 이름', (tester) async {
      final ProviderContainer c = container();
      c.read(sessionControllerProvider.notifier).enterDemo();
      await pumpMini(tester, container: c, locale: const Locale('en'));

      expect(find.text(_en.notFoundGoHome), findsOneWidget);
    });
  });
}
