import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/app_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/nav_destinations.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

import '../../helpers/pump_app.dart';

/// 라벨 기대값은 로케일을 명시해 읽는다 — 기본 로케일이 바뀌어도 의도가 남는다.
final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

void main() {
  group('sessionRedirect', () {
    test('signed-out is forced onto sign-in from any app route', () {
      expect(
        sessionRedirect(SessionStatus.signedOut, AppRoutes.clients),
        '${AppRoutes.signIn}?from=%2Fclients',
      );
      expect(
        sessionRedirect(SessionStatus.unknown, AppRoutes.schedule),
        '${AppRoutes.signIn}?from=%2Fschedule',
      );
    });

    test('password reset opens in every session state (#2824)', () {
      // 메일 링크를 어느 상태에서 열어도 코드가 담긴 주소를 그대로 둔다.
      for (final SessionStatus status in SessionStatus.values) {
        expect(
          sessionRedirect(status, AppRoutes.passwordReset),
          isNull,
          reason: status.name,
        );
        expect(
          sessionRedirect(
            status,
            '${AppRoutes.passwordReset}?token=ABCDEFGHJKMNPQRS',
          ),
          isNull,
          reason: status.name,
        );
      }
    });

    test('signed-out stays on sign-in (no redirect loop)', () {
      expect(
        sessionRedirect(SessionStatus.signedOut, AppRoutes.signIn),
        isNull,
      );
    });

    test('in-app users are bounced off sign-in to the 대시보드', () {
      expect(
        sessionRedirect(SessionStatus.demo, AppRoutes.signIn),
        AppRoutes.dashboard,
      );
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.signIn),
        AppRoutes.dashboard,
      );
    });

    test('a fresh sign-up lands on profile edit to pick a gym (#2543)', () {
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.signUp),
        AppRoutes.mySection('edit'),
      );
    });

    test('in-app users stay put on app routes', () {
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.my),
        isNull,
      );
    });
  });

  // 새로고침·공유 링크는 부팅 위치가 곧 목적지다. 세션이 아직 unknown 인 첫
  // 평가에서 그 목적지를 버리면 복원 뒤에는 돌아갈 곳이 남지 않는다. (#701)
  group('deep-link resume', () {
    const String thread = '/messages?client=user-7d4e9a2c5f18';

    test('the destination is parked on the sign-in URL while restoring', () {
      expect(
        sessionRedirect(SessionStatus.unknown, thread),
        '${AppRoutes.signIn}?from=%2Fmessages%3Fclient%3Duser-7d4e9a2c5f18',
      );
    });

    test('a restored session lands back on the parked destination', () {
      final parked = sessionRedirect(SessionStatus.unknown, thread)!;
      expect(sessionRedirect(SessionStatus.authenticated, parked), thread);
      // 데모는 실서버 계정의 자리를 잇지 않는다(#2765).
      expect(sessionRedirect(SessionStatus.demo, parked), AppRoutes.dashboard);
    });

    test('the parked destination survives sitting on the login screen', () {
      // 로그인 화면에 머무는 동안 리다이렉트가 다시 돌아도 `from` 이 날아가면
      // 로그인 성공 시 돌아갈 자리를 잃는다.
      final parked = sessionRedirect(SessionStatus.signedOut, thread)!;
      expect(sessionRedirect(SessionStatus.signedOut, parked), isNull);
      expect(AppRoutes.resumeTarget(parked), thread);
    });

    test('no parked destination still lands on the 대시보드', () {
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.signIn),
        AppRoutes.dashboard,
      );
    });

    test('an off-site "from" is refused instead of redirected to', () {
      const String forged = '${AppRoutes.signIn}?from=https%3A%2F%2Felsewhere';
      expect(
        sessionRedirect(SessionStatus.authenticated, forged),
        AppRoutes.dashboard,
      );
      expect(AppRoutes.isRestorable('https://elsewhere/clients'), isFalse);
      expect(AppRoutes.isRestorable('//elsewhere/clients'), isFalse);
    });

    test('an unknown path is not worth parking or resuming to', () {
      expect(AppRoutes.isRestorable('/nope'), isFalse);
      expect(sessionRedirect(SessionStatus.unknown, '/nope'), AppRoutes.signIn);
      expect(
        sessionRedirect(
          SessionStatus.authenticated,
          '${AppRoutes.signIn}?from=%2Fnope',
        ),
        AppRoutes.dashboard,
      );
    });

    test('auth routes are never parked as a destination', () {
      expect(AppRoutes.isRestorable(AppRoutes.signIn), isFalse);
      expect(AppRoutes.isRestorable(AppRoutes.signUp), isFalse);
    });

    test('the platform root boots into the 대시보드, not an error screen', () {
      // 웹이 아닌 실행의 기본 부팅 위치는 `/` 이고, 어떤 라우트와도 맞지 않는다.
      expect(
        sessionRedirect(SessionStatus.authenticated, '/'),
        AppRoutes.dashboard,
      );
    });

    test('client sub-paths are restorable', () {
      expect(
        AppRoutes.isRestorable(AppRoutes.clientDetail('seed-client-1')),
        isTrue,
      );
    });
  });

  group('client detail locations', () {
    test('a bare client path is normalised onto the default section', () {
      expect(
        clientSectionRedirect('seed-client-1'),
        '/clients/seed-client-1/${AppRoutes.defaultClientSection}',
      );
    });

    test('a non-client match is left alone', () {
      expect(clientSectionRedirect(null), isNull);
    });

    test('ids are percent-encoded so a "/" in an id cannot forge a path', () {
      expect(AppRoutes.clientDetail('a/b'), '/clients/a%2Fb/diet');
    });

    test('an unknown section falls back instead of dead-ending', () {
      expect(
        AppRoutes.clientDetail('x', section: 'nope'),
        '/clients/x/${AppRoutes.defaultClientSection}',
      );
    });

    test('messages deep link preserves client and filter', () {
      expect(
        AppRoutes.messagesFor('seed-client-1', filter: 'unread'),
        '/messages?client=seed-client-1&f=unread',
      );
    });
  });

  group('app shell', () {
    test('AI coaching navigation label matches the page title', () {
      expect(navLabel(_ko, NavLabel.coaching), _ko.coachTitle);
      expect(navLabel(_en, NavLabel.coaching), _en.coachTitle);
    });

    test('schedule navigation label matches the page title', () {
      expect(navLabel(_ko, NavLabel.schedule), _ko.schedTitle);
      expect(navLabel(_en, NavLabel.schedule), _en.schedTitle);
    });

    test('messages sits immediately after clients in the sidebar', () {
      final clientsIndex = navDestinations.indexWhere(
        (destination) => destination.label == NavLabel.clients,
      );
      expect(navDestinations[clientsIndex + 1].label, NavLabel.messages);
    });

    testWidgets('unauthenticated boot lands on the login screen', (
      tester,
    ) async {
      await pumpTrainerApp(tester);
      // 로그인 화면의 표식 = 가입 링크. 데모 진입은 감춰 뒀다(#1526).
      expect(find.text('회원가입'), findsOneWidget);
    });

    testWidgets('restored session boots into the 대시보드', (tester) async {
      await pumpTrainerApp(tester, token: 'demo-trainer-token-existing');

      // Auth gate redirected past sign-in into the shell.
      expect(find.text('회원가입'), findsNothing);
      expect(find.text('대시보드'), findsWidgets);
    });

    testWidgets('a refresh on a deep link comes back to that screen', (
      tester,
    ) async {
      // 부팅 위치 = 브라우저 URL. 세션이 복원될 때까지 로그인 화면을 거치더라도
      // 열려 있던 스레드로 돌아와야 한다. (#701)
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
        bootAt: AppRoutes.messagesFor('seed-client-1'),
      );

      expect(find.text('회원가입'), findsNothing);
      expect(currentLocation(tester), AppRoutes.messagesFor('seed-client-1'));
    });

    testWidgets('a deep link opened signed-out resumes after login', (
      tester,
    ) async {
      // 데모 진입은 기본 빌드에서 감춰 뒀지만 경로는 살아 있다 — 이 테스트가
      // 보는 것은 '진입 뒤 원래 자리로 잇는가' 라서 플래그를 켜고 편다. (#1526)
      final container = await pumpTrainerApp(
        tester,
        bootAt: AppRoutes.clientDetail('seed-client-1'),
        demoEntry: true,
      );

      // 세션이 없으니 로그인 화면이지만, 가려던 자리는 URL 에 남아 있다.
      expect(find.text('로그인 없이 데모 둘러보기'), findsOneWidget);
      expect(
        AppRoutes.resumeTarget(currentLocation(tester)),
        AppRoutes.clientDetail('seed-client-1'),
      );

      // 이어 가기는 로그인한 계정의 몫이다 — 데모 진입은 늘 대시보드로 간다
      // (#2765). 그래서 이메일로 로그인해 원래 자리로 잇는지 본다.
      await tester.enterText(find.byType(TextField).at(0), 'coach@oncare.test');
      await tester.enterText(find.byType(TextField).at(1), 'pw');
      await tester.tap(find.widgetWithText(InkWell, '로그인'));
      await settle(tester);

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.authenticated,
      );
      expect(currentLocation(tester), AppRoutes.clientDetail('seed-client-1'));
    });

    testWidgets('the sidebar lists every destination on a wide viewport', (
      tester,
    ) async {
      await withWideSurface(tester, () async {
        await pumpTrainerApp(tester, token: 'demo-trainer-token-existing');
        for (final destination in navDestinations) {
          expect(
            find.text(navLabel(_ko, destination.label)),
            findsWidgets,
            reason: '${navLabel(_ko, destination.label)} 항목이 사이드바에 없어요',
          );
        }
        // 내 정보 is reachable from the footer, not the nav list.
        expect(
          find.byKey(const ValueKey<String>('sidebar-profile')),
          findsOneWidget,
        );
      });
    });

    testWidgets('navigating switches the branch', (tester) async {
      await pumpTrainerApp(tester, token: 'demo-trainer-token-existing');

      await goTo(tester, AppRoutes.schedule);
      expect(find.text('스케줄'), findsWidgets);

      await goTo(tester, AppRoutes.my);
      expect(find.text('자격증 · 인증'), findsOneWidget);
    });

    testWidgets('the trainer brand opens the dashboard', (tester) async {
      await withWideSurface(tester, () async {
        await pumpTrainerApp(tester, token: 'demo-trainer-token-existing');
        await goTo(tester, AppRoutes.schedule);

        await tester.tap(
          find.byKey(const ValueKey<String>('sidebar-brand-home')),
        );
        await settle(tester);

        expect(currentLocation(tester), AppRoutes.dashboard);
      });
    });

    for (final width in <double>[1280, 1920]) {
      testWidgets(
        'the six trainer workspaces fit a ${width.toInt()}px desktop',
        (tester) async {
          await withWideSurface(tester, size: Size(width, 1024), () async {
            await pumpTrainerApp(tester, token: 'demo-trainer-token-existing');
            final locations = <String>[
              AppRoutes.dashboard,
              AppRoutes.clientDetail('seed-client-1'),
              AppRoutes.scheduleAt(),
              AppRoutes.messagesFor('seed-client-1'),
              AppRoutes.coachingFor('seed-client-1'),
              AppRoutes.reportFor('seed-client-1'),
            ];
            for (final location in locations) {
              await goTo(tester, location);
              expect(
                tester.takeException(),
                isNull,
                reason: '$location overflowed at ${width.toInt()}px',
              );
            }
          });
        },
      );
    }
  });

  // 직접 로그아웃·탈퇴한 뒤에는 그 자리를 다음 로그인으로 잇지 않는다(#2765).
  group('explicit sign-out does not park', () {
    const String withdraw = '/my?t=withdraw';
    const String client = '/clients/user-7d4e9a2c5f18';

    test('signed out by the user goes to a bare sign-in URL', () {
      expect(
        sessionRedirect(SessionStatus.signedOut, withdraw, resume: false),
        AppRoutes.signIn,
      );
      expect(
        sessionRedirect(SessionStatus.signedOut, client, resume: false),
        AppRoutes.signIn,
      );
    });

    test('a leftover "from" on the sign-in URL is dropped', () {
      final parked = AppRoutes.signInResuming(withdraw);
      expect(
        sessionRedirect(SessionStatus.signedOut, parked, resume: false),
        AppRoutes.signIn,
      );
      expect(
        sessionRedirect(
          SessionStatus.signedOut,
          AppRoutes.signIn,
          resume: false,
        ),
        isNull,
      );
      expect(
        sessionRedirect(
          SessionStatus.signedOut,
          AppRoutes.signUp,
          resume: false,
        ),
        isNull,
      );
    });

    test('the next login after an explicit sign-out lands on the 대시보드', () {
      final landing = sessionRedirect(
        SessionStatus.signedOut,
        withdraw,
        resume: false,
      )!;
      expect(
        sessionRedirect(SessionStatus.authenticated, landing),
        AppRoutes.dashboard,
      );
    });

    test('expiry and deep links still park and resume', () {
      final parked = sessionRedirect(SessionStatus.signedOut, client)!;
      expect(AppRoutes.resumeTarget(parked), client);
      expect(sessionRedirect(SessionStatus.authenticated, parked), client);
      expect(sessionRedirect(SessionStatus.signedOut, parked), isNull);
    });

    test('demo entry always opens the 대시보드', () {
      expect(
        sessionRedirect(SessionStatus.demo, AppRoutes.signInResuming(client)),
        AppRoutes.dashboard,
      );
      expect(
        sessionRedirect(SessionStatus.demo, AppRoutes.signUp),
        AppRoutes.dashboard,
      );
      expect(sessionRedirect(SessionStatus.demo, '/'), AppRoutes.dashboard);
      expect(sessionRedirect(SessionStatus.demo, client), isNull);
    });
  });
}
