/// 동의가 남은 계정의 라우터 가드 — #2819.
///
/// 동의가 남으면 어느 주소로 가든 동의 화면에 붙들고, 동의를 마치면(또는 그럴
/// 일이 없는 세션이면) 동의 화면에 머물지 못한다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

void main() {
  group('동의가 남은 로그인 계정', () {
    for (final String path in <String>[
      AppRoutes.dashboard,
      AppRoutes.myHealth,
      AppRoutes.onboarding,
      AppRoutes.signIn,
      AppRoutes.splash,
      AppRoutes.mySettingsPath('terms'),
    ]) {
      test('$path → 동의 화면', () {
        expect(
          sessionRedirect(
            SessionStatus.authenticated,
            path,
            consentRequired: true,
          ),
          AppRoutes.consent,
        );
      });
    }

    test('동의 화면에서는 움직이지 않는다', () {
      expect(
        sessionRedirect(
          SessionStatus.authenticated,
          AppRoutes.consent,
          consentRequired: true,
        ),
        isNull,
      );
    });
  });

  group('동의 화면에 머물 이유가 없는 세션', () {
    test('동의를 마친 계정은 홈으로', () {
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.consent),
        AppRoutes.dashboard,
      );
    });

    test('데모는 계정이 없어 동의를 묻지 않는다 — 값이 참이어도 막지 않는다', () {
      expect(
        sessionRedirect(
          SessionStatus.demo,
          AppRoutes.dashboard,
          consentRequired: true,
        ),
        isNull,
      );
      expect(
        sessionRedirect(SessionStatus.demo, AppRoutes.consent),
        AppRoutes.dashboard,
      );
    });

    test('로그아웃 상태는 로그인 화면으로, 복구 중은 시작 화면으로', () {
      expect(
        sessionRedirect(SessionStatus.signedOut, AppRoutes.consent),
        AppRoutes.signIn,
      );
      expect(
        sessionRedirect(SessionStatus.unknown, AppRoutes.consent),
        AppRoutes.splash,
      );
    });
  });

  test('동의 요구가 없으면 지금까지의 가드와 같다', () {
    expect(
      sessionRedirect(SessionStatus.authenticated, AppRoutes.exercise),
      isNull,
    );
    expect(
      sessionRedirect(SessionStatus.authenticated, AppRoutes.signIn),
      AppRoutes.dashboard,
    );
    expect(
      sessionRedirect(SessionStatus.signedOut, AppRoutes.dashboard),
      AppRoutes.signIn,
    );
  });
}
