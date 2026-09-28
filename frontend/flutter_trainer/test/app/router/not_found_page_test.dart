import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/app/router/app_router.dart';
import 'package:oncare_trainer/app/router/not_found_page.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/app_shell.dart';
import 'package:oncare_trainer/app/shell/nav_destinations.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

import '../../helpers/pump_app.dart';

/// 기대 문구는 로케일을 명시해 읽는다.
final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

const String _token = 'demo-trainer-token-existing';

/// 어떤 라우트와도 맞지 않는 주소들. 앞부분이 실제 화면인 깊은 주소가
/// 핵심이다 — 로그인을 거쳐도 `from` 으로 살아남아 404 까지 온다.
const List<String> _unknownPaths = <String>[
  '/nope',
  '/dashboard/nope',
  '/clients/seed-client-1/diet/old/deeper',
  '/schedule/consultations/nope',
  '/my/settings/extra',
  '/notifications/x/y/z',
];

Finder get _page => find.byKey(NotFoundPage.bodyKey);
Finder get _action => find.byKey(NotFoundPage.actionKey);

/// 화면에 있는 셸 Scaffold 중 드로어가 열린 것이 있는가.
bool _drawerOpen(WidgetTester tester) => tester
    .stateList<ScaffoldState>(find.byType(Scaffold))
    .any((scaffold) => scaffold.isDrawerOpen);

void main() {
  group('sessionRedirect — unknown paths', () {
    test('an in-app trainer is left on an unknown path (the 404 shows)', () {
      for (final path in _unknownPaths) {
        expect(
          sessionRedirect(SessionStatus.authenticated, path),
          isNull,
          reason: path,
        );
        expect(sessionRedirect(SessionStatus.demo, path), isNull, reason: path);
      }
    });

    test('signed-out visitors never reach the 404 — sign-in comes first', () {
      for (final path in _unknownPaths) {
        final target = sessionRedirect(SessionStatus.signedOut, path)!;
        expect(Uri.parse(target).path, AppRoutes.signIn, reason: path);
        final unknown = sessionRedirect(SessionStatus.unknown, path)!;
        expect(Uri.parse(unknown).path, AppRoutes.signIn, reason: path);
      }
    });

    test('a deep path under a real screen is parked and resumed as is', () {
      const path = '/clients/seed-client-1/diet/old/deeper';
      final parked = sessionRedirect(SessionStatus.unknown, path)!;
      expect(AppRoutes.resumeTarget(parked), path);
      expect(sessionRedirect(SessionStatus.authenticated, parked), path);
    });

    test('a path under no real screen is dropped, not parked', () {
      expect(sessionRedirect(SessionStatus.unknown, '/nope'), AppRoutes.signIn);
      expect(
        sessionRedirect(SessionStatus.signedOut, '/auth/nope'),
        AppRoutes.signIn,
      );
    });
  });

  group('AppShell.branchRoot', () {
    test('sidebar destinations map onto their own roots', () {
      for (var i = 0; i < navDestinations.length; i++) {
        expect(AppShell.branchRoot(i), navDestinations[i].route);
      }
    });

    test('the footer branches map onto 내 정보 and 알림함', () {
      expect(AppShell.branchRoot(AppShell.myBranchIndex), AppRoutes.my);
      expect(
        AppShell.branchRoot(AppShell.notificationsBranchIndex),
        AppRoutes.notifications,
      );
    });

    test('an out-of-range index falls back to the 대시보드', () {
      expect(AppShell.branchRoot(-1), AppRoutes.dashboard);
      expect(
        AppShell.branchRoot(AppShell.notificationsBranchIndex + 1),
        AppRoutes.dashboard,
      );
    });
  });

  group('NotFoundPage.isInApp', () {
    test('only demo and authenticated sessions are inside the console', () {
      expect(NotFoundPage.isInApp(SessionStatus.authenticated), isTrue);
      expect(NotFoundPage.isInApp(SessionStatus.demo), isTrue);
      expect(NotFoundPage.isInApp(SessionStatus.signedOut), isFalse);
      expect(NotFoundPage.isInApp(SessionStatus.unknown), isFalse);
    });
  });

  group('signed in', () {
    testWidgets('an unknown path shows the 404 in Korean, URL untouched', (
      tester,
    ) async {
      await pumpTrainerApp(tester, token: _token, at: '/nope');

      expect(_page, findsOneWidget);
      expect(find.text(_ko.notFoundTitle), findsOneWidget);
      expect(find.text(_ko.notFoundMessage), findsOneWidget);
      expect(find.text(_ko.notFoundGoDashboard), findsOneWidget);
      expect(find.text(_ko.notFoundGoSignIn), findsNothing);
      // go_router 기본 오류 화면이 아니다.
      expect(find.textContaining('Page Not Found'), findsNothing);
      expect(currentLocation(tester), '/nope');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the 404 reads in English under an English locale', (
      tester,
    ) async {
      await pumpTrainerApp(
        tester,
        token: _token,
        at: '/nope',
        locale: const Locale('en'),
      );

      expect(find.text(_en.notFoundTitle), findsOneWidget);
      expect(find.text(_en.notFoundMessage), findsOneWidget);
      expect(find.text(_en.notFoundGoDashboard), findsOneWidget);
      expect(find.text(_ko.notFoundTitle), findsNothing);
    });

    testWidgets('the primary button goes back to the 대시보드', (tester) async {
      await pumpTrainerApp(tester, token: _token, at: '/nope');

      await tester.tap(_action);
      await settle(tester);

      expect(currentLocation(tester), AppRoutes.dashboard);
      expect(_page, findsNothing);
    });

    for (final path in _unknownPaths) {
      testWidgets('in-app navigation to $path lands on the 404', (
        tester,
      ) async {
        await pumpTrainerApp(tester, token: _token, at: path);

        expect(_page, findsOneWidget, reason: path);
        expect(currentLocation(tester), path);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a refresh on a stale deep link comes back to the 404', (
      tester,
    ) async {
      // 앞부분이 실제 화면이라 복원 동안 로그인 URL 에 주차됐다가 돌아온다.
      // go_router 는 매치 실패 목록의 위치를 보고하지 않아 라우터 위치는
      // 주차된 로그인 URL 로 남는다 — 그래서 여기서는 화면으로 확인한다.
      const path = '/clients/seed-client-1/diet/old/deeper';
      final container = await pumpTrainerApp(
        tester,
        token: _token,
        bootAt: path,
      );

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(_page, findsOneWidget);
      expect(find.text(_ko.notFoundTitle), findsOneWidget);
      expect(find.text('회원가입'), findsNothing);
    });

    testWidgets('a refresh on a path under no screen lands on the 대시보드', (
      tester,
    ) async {
      // `/nope` 는 주차할 가치가 없어 복원 뒤 대시보드로 간다 — 404 가
      // 아니다(기존 동작 유지).
      await pumpTrainerApp(tester, token: _token, bootAt: '/nope');

      expect(currentLocation(tester), AppRoutes.dashboard);
      expect(_page, findsNothing);
    });

    testWidgets('the 404 sits inside the console with the sidebar', (
      tester,
    ) async {
      await withWideSurface(tester, () async {
        await pumpTrainerApp(tester, token: _token, at: '/nope');

        expect(_page, findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('sidebar-brand-home')),
          findsOneWidget,
        );
        for (final destination in navDestinations) {
          expect(
            find.byKey(ValueKey<String>('sidebar-${destination.route}')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a sidebar row on the 404 opens that workspace', (
      tester,
    ) async {
      await withWideSurface(tester, () async {
        await pumpTrainerApp(tester, token: _token, at: '/nope');

        await tester.tap(
          find.byKey(const ValueKey<String>('sidebar-${AppRoutes.schedule}')),
        );
        await settle(tester);

        expect(Uri.parse(currentLocation(tester)).path, AppRoutes.schedule);
        expect(_page, findsNothing);
      });
    });

    testWidgets('the brand on the 404 opens the 대시보드', (tester) async {
      await withWideSurface(tester, () async {
        await pumpTrainerApp(tester, token: _token, at: '/dashboard/nope');

        await tester.tap(
          find.byKey(const ValueKey<String>('sidebar-brand-home')),
        );
        await settle(tester);

        expect(currentLocation(tester), AppRoutes.dashboard);
      });
    });

    testWidgets('the icon rail form also frames the 404', (tester) async {
      await withWideSurface(tester, size: const Size(1100, 800), () async {
        await pumpTrainerApp(tester, token: _token, at: '/nope');

        expect(_page, findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('sidebar-${AppRoutes.clients}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('on a narrow viewport the drawer reaches the workspaces', (
      tester,
    ) async {
      // 기본 테스트 화면(800)은 드로어 형태다.
      await pumpTrainerApp(tester, token: _token, at: '/nope');

      expect(_page, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('compact-brand-home')),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('sidebar-${AppRoutes.clients}')),
      );
      await settle(tester);

      expect(Uri.parse(currentLocation(tester)).path, AppRoutes.clients);
      expect(_page, findsNothing);
      expect(_drawerOpen(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the drawer still closes after navigating inside the shell', (
      tester,
    ) async {
      // 드로어 닫기를 내비게이터 pop 에서 closeDrawer 로 바꾼 회귀 확인.
      await pumpTrainerApp(tester, token: _token, at: AppRoutes.dashboard);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await settle(tester);
      expect(_drawerOpen(tester), isTrue);
      await tester.tap(
        find.byKey(const ValueKey<String>('sidebar-${AppRoutes.schedule}')),
      );
      await settle(tester);

      expect(Uri.parse(currentLocation(tester)).path, AppRoutes.schedule);
      expect(_drawerOpen(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the compact brand on the 404 opens the 대시보드', (tester) async {
      await pumpTrainerApp(tester, token: _token, at: '/nope');

      await tester.tap(
        find.byKey(const ValueKey<String>('compact-brand-home')),
      );
      await settle(tester);

      expect(currentLocation(tester), AppRoutes.dashboard);
    });

    testWidgets('leaving and coming back to a real screen keeps working', (
      tester,
    ) async {
      await pumpTrainerApp(tester, token: _token, at: AppRoutes.schedule);
      await goTo(tester, '/schedule/nope');
      expect(_page, findsOneWidget);

      await goTo(tester, AppRoutes.messages);
      expect(_page, findsNothing);
      expect(currentLocation(tester), AppRoutes.messages);
    });

    testWidgets('signing out on the 404 hands over to the sign-in screen', (
      tester,
    ) async {
      final container = await pumpTrainerApp(
        tester,
        token: _token,
        at: '/dashboard/nope',
      );
      expect(_page, findsOneWidget);

      await container.read(sessionControllerProvider.notifier).signOut();
      await settle(tester);

      expect(Uri.parse(currentLocation(tester)).path, AppRoutes.signIn);
      expect(_page, findsNothing);
      expect(find.text(_ko.notFoundGoSignIn), findsNothing);
    });

    for (final width in <double>[1280, 1920]) {
      for (final locale in <Locale>[const Locale('ko'), const Locale('en')]) {
        testWidgets(
          'the 404 fits a ${width.toInt()}px desktop in ${locale.languageCode}',
          (tester) async {
            await withWideSurface(tester, size: Size(width, 900), () async {
              await pumpTrainerApp(
                tester,
                token: _token,
                at: '/clients/seed-client-1/diet/old',
                locale: locale,
              );
              expect(_page, findsOneWidget);
              expect(tester.takeException(), isNull);
            });
          },
        );
      }
    }
  });

  group('signed out', () {
    testWidgets('an unknown path under a real screen resumes after entry', (
      tester,
    ) async {
      const path = '/clients/seed-client-1/diet/old';
      final container = await pumpTrainerApp(
        tester,
        bootAt: path,
        demoEntry: true,
      );

      // 세션이 없으면 404 가 아니라 로그인 화면이고, 가려던 곳은 주차된다.
      expect(_page, findsNothing);
      expect(Uri.parse(currentLocation(tester)).path, AppRoutes.signIn);
      expect(AppRoutes.resumeTarget(currentLocation(tester)), path);

      await tester.ensureVisible(find.text('로그인 없이 데모 둘러보기'));
      await tester.pump();
      await tester.tap(find.text('로그인 없이 데모 둘러보기'));
      await settle(tester);

      expect(
        container.read(sessionControllerProvider).status,
        isNot(SessionStatus.signedOut),
      );
      expect(currentLocation(tester), path);
      expect(_page, findsOneWidget);
    });

    testWidgets('an unknown path under no screen just opens sign-in', (
      tester,
    ) async {
      await pumpTrainerApp(tester, bootAt: '/nope');

      expect(_page, findsNothing);
      expect(currentLocation(tester), AppRoutes.signIn);
    });

    testWidgets('an unknown auth path opens sign-in, not the 404', (
      tester,
    ) async {
      await pumpTrainerApp(tester, bootAt: '/auth/nope');

      expect(_page, findsNothing);
      expect(currentLocation(tester), AppRoutes.signIn);
    });

    // 인증 게이트가 다시 돌기 전 한 프레임을 흉내 낸다 — 세션이 없는데 404 가
    // 그려지는 경우. 게이트 없는 라우터로 직접 띄운다.
    Future<void> pumpGateless(WidgetTester tester, Locale locale) async {
      final container = await pumpTrainerApp(tester, seed: false);
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      final router = GoRouter(
        initialLocation: '/nope',
        errorBuilder: (context, state) => const NotFoundPage(),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.signIn,
            builder: (context, state) =>
                const Scaffold(body: Text('sign-in-stub')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            locale: locale,
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('signed-out 404 uses the sign-in layout and goes to sign-in', (
      tester,
    ) async {
      await pumpGateless(tester, const Locale('ko'));

      expect(_page, findsOneWidget);
      expect(find.text(_ko.notFoundTitle), findsOneWidget);
      expect(find.text(_ko.notFoundMessage), findsOneWidget);
      expect(find.text(_ko.notFoundGoSignIn), findsOneWidget);
      expect(find.text(_ko.notFoundGoDashboard), findsNothing);
      // 세션이 없으니 사이드바를 띄우지 않는다.
      expect(
        find.byKey(const ValueKey<String>('compact-brand-home')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('sidebar-brand-home')),
        findsNothing,
      );

      await tester.tap(_action);
      await settle(tester);
      expect(find.text('sign-in-stub'), findsOneWidget);
    });

    testWidgets('signed-out 404 reads in English under an English locale', (
      tester,
    ) async {
      await pumpGateless(tester, const Locale('en'));

      expect(find.text(_en.notFoundTitle), findsOneWidget);
      expect(find.text(_en.notFoundMessage), findsOneWidget);
      expect(find.text(_en.notFoundGoSignIn), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('every 404 string is filled in both locales', () {
    for (final l in <AppLocalizations>[_ko, _en]) {
      expect(l.notFoundTitle, isNotEmpty);
      expect(l.notFoundMessage, isNotEmpty);
      expect(l.notFoundGoDashboard, isNotEmpty);
      expect(l.notFoundGoSignIn, isNotEmpty);
    }
    expect(_en.notFoundTitle, isNot(_ko.notFoundTitle));
    expect(_en.notFoundGoDashboard, isNot(_ko.notFoundGoDashboard));
  });
}
