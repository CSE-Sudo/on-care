/// 동의가 남은 계정을 동의 화면에 붙드는 가드 — #2819.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/app_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';

void main() {
  group('동의가 남은 로그인 세션', () {
    test('앱 안 어느 주소로 가든 동의 화면으로 보낸다', () {
      for (final String location in <String>[
        AppRoutes.dashboard,
        AppRoutes.clients,
        AppRoutes.schedule,
        AppRoutes.signIn,
        AppRoutes.signUp,
        '${AppRoutes.clients}?q=kim',
      ]) {
        expect(
          sessionRedirect(
            SessionStatus.authenticated,
            location,
            consentRequired: true,
          ),
          AppRoutes.consent,
          reason: location,
        );
      }
    });

    test('동의 화면에서는 그대로 둔다 — 되돌림 고리가 없다', () {
      expect(
        sessionRedirect(
          SessionStatus.authenticated,
          AppRoutes.consent,
          consentRequired: true,
        ),
        isNull,
      );
    });

    test('약관·처리방침 문서는 동의 전에도 열린다', () {
      for (final String doc in <String>['terms', 'privacy']) {
        expect(
          sessionRedirect(
            SessionStatus.authenticated,
            AppRoutes.legalDocument(doc),
            consentRequired: true,
          ),
          isNull,
          reason: doc,
        );
      }
    });
  });

  group('동의 화면 주소에 다른 상태로 왔을 때', () {
    test('로그아웃·확인 전 상태는 로그인 화면으로', () {
      expect(
        sessionRedirect(SessionStatus.signedOut, AppRoutes.consent),
        AppRoutes.signIn,
      );
      expect(
        sessionRedirect(SessionStatus.unknown, AppRoutes.consent),
        AppRoutes.signIn,
      );
    });

    test('동의를 마쳤거나 데모라면 대시보드로', () {
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.consent),
        AppRoutes.dashboard,
      );
      expect(
        sessionRedirect(SessionStatus.demo, AppRoutes.consent),
        AppRoutes.dashboard,
      );
    });

    test('데모는 동의 플래그가 있어도 붙들지 않는다 — 계정이 없다', () {
      expect(
        sessionRedirect(
          SessionStatus.demo,
          AppRoutes.clients,
          consentRequired: true,
        ),
        isNull,
      );
    });
  });

  test('동의가 끝난 세션의 기존 가드는 그대로다', () {
    expect(
      sessionRedirect(SessionStatus.authenticated, AppRoutes.clients),
      isNull,
    );
    expect(
      sessionRedirect(SessionStatus.authenticated, AppRoutes.signIn),
      AppRoutes.dashboard,
    );
  });
}
