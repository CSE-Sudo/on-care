import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

void main() {
  group('sessionRedirect (router login guard)', () {
    test('signed-out on a protected route → forced to sign-in', () {
      expect(
        sessionRedirect(SessionStatus.signedOut, AppRoutes.dashboard),
        AppRoutes.signIn,
      );
      expect(
        sessionRedirect(SessionStatus.signedOut, AppRoutes.myHealth),
        AppRoutes.signIn,
      );
      expect(
        sessionRedirect(SessionStatus.signedOut, AppRoutes.aiCoach),
        AppRoutes.signIn,
      );
    });

    test('복구 중(unknown)에는 시작 화면에 머문다 (#1944)', () {
      // 전에는 로그아웃과 같이 묶여 완전히 눌리는 로그인 폼이 떴다 — 복구가
      // 끝나면 입력하던 화면이 홈으로 튀고, 먼저 로그인을 누르면 진행 중이던
      // 복구가 버려졌다.
      expect(
        sessionRedirect(SessionStatus.unknown, AppRoutes.dashboard),
        AppRoutes.splash,
      );
      expect(
        sessionRedirect(SessionStatus.unknown, AppRoutes.signIn),
        AppRoutes.splash,
      );
      expect(sessionRedirect(SessionStatus.unknown, AppRoutes.splash), isNull);
    });

    test('signed-out already on sign-in → stays put (null)', () {
      expect(
        sessionRedirect(SessionStatus.signedOut, AppRoutes.signIn),
        isNull,
      );
    });

    test('demo / authenticated on sign-in → bounced into the app', () {
      expect(
        sessionRedirect(SessionStatus.demo, AppRoutes.signIn),
        AppRoutes.dashboard,
      );
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.signIn),
        AppRoutes.dashboard,
      );
    });

    test('demo / authenticated on a protected route → stays put (null)', () {
      expect(sessionRedirect(SessionStatus.demo, AppRoutes.dashboard), isNull);
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.exercise),
        isNull,
      );
    });

    test('sign-up route is public like sign-in', () {
      // signed-out may reach it; already-in-app is bounced out. 복구 중에는
      // 시작 화면이 먼저다(#1944) — 복구가 끝난 뒤에 가입으로 갈 수 있다.
      expect(sessionRedirect(SessionStatus.signedOut, AppRoutes.signUp), isNull);
      expect(
        sessionRedirect(SessionStatus.unknown, AppRoutes.signUp),
        AppRoutes.splash,
      );
      expect(
        sessionRedirect(SessionStatus.demo, AppRoutes.signUp),
        AppRoutes.dashboard,
      );
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.signUp),
        AppRoutes.dashboard,
      );
    });
  });
}
