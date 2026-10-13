/// 동의가 남은 계정의 라우터 가드 — #2819.
///
/// 동의가 남으면 어느 주소로 가든 동의 화면에 붙들고, 동의를 마치면(또는 그럴
/// 일이 없는 세션이면) 동의 화면에 머물지 못한다.
///
/// 탈퇴 화면만은 예외다(#3340) — 동의하지 않기로 한 회원이 계정을 지울 수
/// 있어야 한다. 그 밖의 화면은 여전히 열리지 않는다.
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

  group('동의가 남은 계정의 탈퇴 (#3340)', () {
    test('탈퇴 화면은 열린다', () {
      expect(
        sessionRedirect(
          SessionStatus.authenticated,
          AppRoutes.withdraw,
          consentRequired: true,
        ),
        isNull,
      );
    });

    test('탈퇴 화면의 주소는 MY 설정의 그 주소 그대로다 — 새 화면을 두지 않는다', () {
      expect(AppRoutes.withdraw, AppRoutes.mySettingsPath('withdraw'));
      expect(AppRoutes.withdraw, '/my-health/settings/withdraw');
    });

    // 탈퇴 화면이 열렸다고 그 옆 화면이 함께 열리지는 않는다.
    for (final String path in <String>[
      AppRoutes.mySettingsPath('support'),
      AppRoutes.mySettingsPath('profile'),
      AppRoutes.mySettingsPath('goals'),
      AppRoutes.mySettingsPath('notifications'),
      AppRoutes.mySettingsPath('privacy'),
      AppRoutes.mySettingsPath(AppRoutes.passwordSettingsSection),
      // 주소가 탈퇴 화면으로 시작해도 같은 화면이 아니다.
      '${AppRoutes.withdraw}/more',
      '${AppRoutes.withdraw}2',
      AppRoutes.myHealth,
      AppRoutes.diet,
      AppRoutes.exercise,
      AppRoutes.aiCoach,
      AppRoutes.notification,
      AppRoutes.myPoints,
      AppRoutes.gyms,
    ]) {
      test('$path → 여전히 동의 화면', () {
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

    test('탈퇴가 끝나 로그아웃되면 탈퇴 화면에서 로그인 화면으로 간다', () {
      expect(
        sessionRedirect(SessionStatus.signedOut, AppRoutes.withdraw),
        AppRoutes.signIn,
      );
      // 세션이 먼저 비고 동의 값이 한 박자 늦게 꺼져도 같다.
      expect(
        sessionRedirect(
          SessionStatus.signedOut,
          AppRoutes.withdraw,
          consentRequired: true,
        ),
        AppRoutes.signIn,
      );
    });

    test('업데이트가 필요하면 탈퇴 화면보다 업데이트 화면이 먼저다', () {
      expect(
        sessionRedirect(
          SessionStatus.authenticated,
          AppRoutes.withdraw,
          consentRequired: true,
          updateRequired: true,
        ),
        AppRoutes.updateRequired,
      );
    });

    test('동의를 마친 회원의 탈퇴 화면은 전과 같다', () {
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.withdraw),
        isNull,
      );
      expect(sessionRedirect(SessionStatus.demo, AppRoutes.withdraw), isNull);
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
