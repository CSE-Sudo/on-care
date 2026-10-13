/// 재설정 링크는 어느 세션 상태에서 열려도 그 자리에 둔다(#2824).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

/// 서버 `reset_link()`(backend/app/services/password_reset.py)가 만드는 메일 링크와 같은
/// 모양(#3033). 앱은 해시 URL 전략이라 브라우저가 `#` 뒤를 라우터 위치로 넘긴다 — 그 위치가
/// 재설정 경로이고 `token` 이 그대로 읽혀야 한다. 서버 형식을 바꾸면 이 표도 같이 바꾼다.
const List<String> _mailLinks = <String>[
  'https://oncare.example/member/#/auth/password-reset?token=ABCD-EFGH-JKMN-PQRS',
  'https://oncare.example/member/?ref=mail#/auth/password-reset?token=ABCD-EFGH-JKMN-PQRS',
  'https://oncare.example/member/#/auth/password-reset?lang=ko&token=ABCD-EFGH-JKMN-PQRS',
];

/// 브라우저가 해시 URL 전략 앱에 넘기는 라우터 위치(`#` 뒤).
Uri _routerLocation(String link) => Uri.parse(Uri.parse(link).fragment);

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

  group('메일 링크 계약 (#3033)', () {
    for (final String link in _mailLinks) {
      test('해시형 링크는 재설정 화면과 코드로 열린다 — $link', () {
        final Uri location = _routerLocation(link);
        expect(location.path, AppRoutes.passwordReset);
        expect(location.queryParameters['token'], 'ABCD-EFGH-JKMN-PQRS');
        for (final SessionStatus status in SessionStatus.values) {
          expect(
            sessionRedirect(status, location.path),
            isNull,
            reason: status.name,
          );
        }
      });
    }

    test('해시 없는 경로형 링크는 라우터에 코드가 닿지 않는다', () {
      // 운영 기동 경고가 잡는 형식이다 — 브라우저가 정적 경로를 먼저 찾는다.
      const String pathStyle =
          'https://oncare.example/auth/password-reset?token=ABCD-EFGH-JKMN-PQRS';
      expect(Uri.parse(pathStyle).fragment, isEmpty);
    });
  });
}
