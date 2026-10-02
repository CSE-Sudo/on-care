/// 재설정 링크는 어느 세션 상태에서 열려도 그 자리에 둔다(#2824).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

void main() {
  for (final SessionStatus status in SessionStatus.values) {
    test('$status 에서 재설정 화면은 막지 않는다', () {
      expect(sessionRedirect(status, AppRoutes.passwordReset), isNull);
    });
  }

  test('MY 비밀번호 변경은 로그인한 사람만 — 로그아웃이면 로그인 화면으로', () {
    final String path = AppRoutes.mySettingsPath(
      AppRoutes.passwordSettingsSection,
    );
    expect(sessionRedirect(SessionStatus.signedOut, path), AppRoutes.signIn);
    expect(sessionRedirect(SessionStatus.authenticated, path), isNull);
  });

  test('재설정 경로는 로그인·가입 경로와 겹치지 않는다', () {
    expect(AppRoutes.passwordReset, isNot(AppRoutes.signIn));
    expect(AppRoutes.passwordReset, isNot(AppRoutes.signUp));
    expect(AppRoutes.passwordReset.startsWith('/auth/'), isTrue);
  });
}
