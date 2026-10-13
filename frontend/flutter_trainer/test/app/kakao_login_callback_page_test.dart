/// 카카오 웹 로그인 콜백 페이지(#330).
///
/// 카카오 콘솔에 등록하는 Redirect URI 가 이 파일이다. 앱 코드(oncare_social_login)가
/// 기다리는 채널 이름·파일 이름과 어긋나면 로그인 팝업이 돌아와도 앱이 코드를 받지 못한다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_social_login/oncare_social_login.dart';

void main() {
  final File page = File('web/$kKakaoLoginCallbackPage');
  final File script = File('web/js/kakao_login_callback.js');

  test('콜백 페이지와 스크립트가 web/ 에 있다', () {
    expect(page.existsSync(), isTrue);
    expect(script.existsSync(), isTrue);
  });

  test('인라인 스크립트 없이 같은 출처 파일 하나만 부른다', () {
    final String markup = page.readAsStringSync();
    final List<RegExpMatch> tags = RegExp(
      r'<script\b([^>]*)>(.*?)</script>',
      dotAll: true,
    ).allMatches(markup).toList();
    expect(tags, hasLength(1));
    expect(tags.single.group(1), contains('src="js/kakao_login_callback.js"'));
    expect(tags.single.group(2)!.trim(), isEmpty);
  });

  test('자체 CSP 는 같은 출처 스크립트만 열고, 코드를 리퍼러로 흘리지 않는다', () {
    final String markup = page.readAsStringSync();
    final String csp = RegExp(
      r'<meta http-equiv="Content-Security-Policy" content="([^"]+)"',
    ).firstMatch(markup)!.group(1)!;
    expect(csp, contains("default-src 'none'"));
    expect(csp, contains("script-src 'self'"));
    expect(csp, isNot(contains('unsafe-eval')));
    expect(csp, isNot(contains("script-src 'self' 'unsafe-inline'")));
    expect(markup, contains('<meta name="referrer" content="no-referrer">'));
  });

  test('앱이 듣는 채널로 code·state·error 를 보내고 주소에서 지운다', () {
    final String js = script.readAsStringSync();
    expect(js, contains('"$kKakaoLoginChannel"'));
    expect(js, contains('new BroadcastChannel(CHANNEL)'));
    for (final String field in <String>['code', 'state', 'error']) {
      expect(js, contains('params.get("$field")'));
    }
    expect(js, contains('history.replaceState'));
    expect(js, contains('window.close()'));
    // 문구는 textContent 로만 넣는다.
    expect(js, isNot(contains('innerHTML')));
  });
}
