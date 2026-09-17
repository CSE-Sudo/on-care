/// 세션 복구 중·실패의 시작 화면. (#1944)
///
/// 예전에는 복구 중인 상태를 로그아웃과 똑같이 라우팅해 완전히 눌리는 로그인
/// 폼이 떴다. 비-401 실패(오프라인·500·타임아웃)로 끝나면 아무 안내 없이 그
/// 폼에 남았고, 저장된 세션은 멀쩡한데 재시도는 "다음 실행" 뿐이었다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

void main() {
  test('복구 중에는 어디서 시작하든 시작 화면에 머문다', () {
    expect(
      sessionRedirect(SessionStatus.unknown, AppRoutes.signIn),
      AppRoutes.splash,
    );
    expect(
      sessionRedirect(SessionStatus.unknown, AppRoutes.dashboard),
      AppRoutes.splash,
    );
    // 이미 시작 화면이면 옮기지 않는다 — 옮기면 리다이렉트가 끝나지 않는다.
    expect(sessionRedirect(SessionStatus.unknown, AppRoutes.splash), isNull);
  });

  test('복구가 끝나면 시작 화면을 떠난다', () {
    expect(
      sessionRedirect(SessionStatus.authenticated, AppRoutes.splash),
      AppRoutes.dashboard,
    );
    expect(
      sessionRedirect(SessionStatus.demo, AppRoutes.splash),
      AppRoutes.dashboard,
    );
    expect(
      sessionRedirect(SessionStatus.signedOut, AppRoutes.splash),
      AppRoutes.signIn,
    );
  });

  test('로그아웃·로그인 화면의 판정은 그대로다', () {
    expect(sessionRedirect(SessionStatus.signedOut, AppRoutes.signIn), isNull);
    expect(
      sessionRedirect(SessionStatus.signedOut, AppRoutes.dashboard),
      AppRoutes.signIn,
    );
    expect(
      sessionRedirect(SessionStatus.authenticated, AppRoutes.dashboard),
      isNull,
    );
  });

  test('일시적 실패는 세션의 끝이 아니다', () {
    // 상태가 `unknown` 에 머물러야 시작 화면이 재시도를 띄운다 — 로그아웃으로
    // 넘기면 로그인 폼이 뜨고, 저장된 토큰이 멀쩡하다는 사실이 사라진다.
    const SessionState failed = SessionState(restoreFailed: true);
    expect(failed.status, SessionStatus.unknown);
    expect(failed.canEnterApp, isFalse);
    expect(
      sessionRedirect(failed.status, AppRoutes.splash),
      isNull,
    );
  });
}
