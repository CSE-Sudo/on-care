import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 회원 앱 웹 셸의 메타(#3015).
///
/// 로그인해야 쓰는 앱이라 검색 색인에서 빼고, 문서 언어를 한국어로 선언한다.
/// 회원 앱은 모바일 우선이라 매니페스트의 세로 고정은 의도대로 둔다.
void main() {
  final String html = File('web/index.html').readAsStringSync();
  final String head = html.substring(0, html.indexOf('</head>'));
  final Map<String, Object?> manifest =
      jsonDecode(File('web/manifest.json').readAsStringSync())
          as Map<String, Object?>;

  String? metaContent(String name) => RegExp(
    '<meta\\s+name="$name"\\s+content="([^"]*)"',
  ).firstMatch(head)?.group(1);

  test('문서 언어가 한국어로 선언돼 있다', () {
    expect(html, contains('<html lang="ko">'));
  });

  test('검색 색인에서 뺀다', () {
    final String? robots = metaContent('robots');
    expect(robots, isNotNull, reason: 'robots meta is missing');
    expect(robots, contains('noindex'));
  });

  test('CSP·description 메타는 그대로 있다', () {
    expect(head, contains('http-equiv="Content-Security-Policy"'));
    expect(metaContent('description'), manifest['description']);
  });

  test('모바일 우선 앱이라 매니페스트는 세로 고정을 지킨다', () {
    expect(manifest['orientation'], 'portrait-primary');
  });
}
