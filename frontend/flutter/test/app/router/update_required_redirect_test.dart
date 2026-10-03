/// 최소 지원 버전보다 낮은 빌드의 라우터 가드(#3045).
///
/// 업데이트가 필요하면 어느 주소·어느 세션 상태에서든 업데이트 화면에 붙든다.
/// 필요 없으면 업데이트 화면에 들어올 수 없다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

void main() {
  const List<String> locations = <String>[
    AppRoutes.splash,
    AppRoutes.signIn,
    AppRoutes.signUp,
    AppRoutes.dashboard,
    AppRoutes.myHealth,
    AppRoutes.consent,
    AppRoutes.passwordReset,
  ];

  group('업데이트가 필요하면', () {
    test('어느 세션·어느 주소든 업데이트 화면으로 보낸다', () {
      for (final SessionStatus status in SessionStatus.values) {
        for (final String location in locations) {
          expect(
            sessionRedirect(status, location, updateRequired: true),
            AppRoutes.updateRequired,
            reason: '$status @ $location',
          );
        }
      }
    });

    test('동의가 남았어도 업데이트가 먼저다', () {
      expect(
        sessionRedirect(
          SessionStatus.authenticated,
          AppRoutes.dashboard,
          consentRequired: true,
          updateRequired: true,
        ),
        AppRoutes.updateRequired,
      );
    });

    test('이미 업데이트 화면이면 그대로 둔다', () {
      for (final SessionStatus status in SessionStatus.values) {
        expect(
          sessionRedirect(
            status,
            AppRoutes.updateRequired,
            updateRequired: true,
          ),
          isNull,
          reason: '$status',
        );
      }
    });
  });

  group('업데이트가 필요 없으면', () {
    test('업데이트 화면에서 세션에 맞는 곳으로 내보낸다', () {
      expect(
        sessionRedirect(SessionStatus.unknown, AppRoutes.updateRequired),
        AppRoutes.splash,
      );
      expect(
        sessionRedirect(SessionStatus.signedOut, AppRoutes.updateRequired),
        AppRoutes.signIn,
      );
      expect(
        sessionRedirect(SessionStatus.demo, AppRoutes.updateRequired),
        AppRoutes.dashboard,
      );
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.updateRequired),
        AppRoutes.dashboard,
      );
    });

    test('다른 주소는 기존 가드 그대로다', () {
      expect(
        sessionRedirect(SessionStatus.signedOut, AppRoutes.dashboard),
        AppRoutes.signIn,
      );
      expect(
        sessionRedirect(SessionStatus.authenticated, AppRoutes.dashboard),
        isNull,
      );
      expect(
        sessionRedirect(SessionStatus.unknown, AppRoutes.passwordReset),
        isNull,
      );
    });
  });
}
