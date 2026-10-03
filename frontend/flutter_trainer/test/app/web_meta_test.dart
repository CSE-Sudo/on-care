import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 트레이너 웹 셸의 매니페스트·메타(#3015).
///
/// 트레이너 웹은 데스크톱·태블릿 가로 화면에서 쓰는 콘솔이고 웹 전용이다. 설치형
/// 으로 열 때 세로로 잠기거나, 설치 창·검색 결과에 "Android / iOS" 처럼 사실과
/// 다른 설명이 뜨면 안 된다. 로그인해야 쓰는 앱이라 검색 색인에서도 뺀다.
void main() {
  final String html = File('web/index.html').readAsStringSync();
  final String head = html.substring(0, html.indexOf('</head>'));
  final Map<String, Object?> manifest =
      jsonDecode(File('web/manifest.json').readAsStringSync())
          as Map<String, Object?>;
  final String pubspec = File('pubspec.yaml').readAsStringSync();

  String? metaContent(String name) => RegExp(
    '<meta\\s+name="$name"\\s+content="([^"]*)"',
  ).firstMatch(head)?.group(1);

  group('manifest', () {
    test('세로 고정이 아니다', () {
      final Object? orientation = manifest['orientation'];
      expect(orientation, isNot(startsWith('portrait')));
      expect(orientation, isNot(startsWith('landscape')));
    });

    test('설명에 모바일 플랫폼이 적혀 있지 않다', () {
      final String description = manifest['description']! as String;
      expect(description, isNot(contains('Android')));
      expect(description, isNot(contains('iOS')));
      expect(description, contains('트레이너'));
    });

    test('이름·아이콘은 그대로다', () {
      expect(manifest['name'], 'On-Care 트레이너');
      expect(manifest['icons'], isA<List<Object?>>());
    });
  });

  group('index.html', () {
    test('문서 언어가 한국어로 선언돼 있다', () {
      expect(html, contains('<html lang="ko">'));
    });

    test('검색 색인에서 뺀다', () {
      final String? robots = metaContent('robots');
      expect(robots, isNotNull, reason: 'robots meta is missing');
      expect(robots, contains('noindex'));
    });

    test('description 메타가 매니페스트 설명과 같다', () {
      expect(metaContent('description'), manifest['description']);
    });

    test('CSP·theme-color 메타는 그대로 있다', () {
      expect(head, contains('http-equiv="Content-Security-Policy"'));
      expect(metaContent('theme-color'), '#235C88');
    });
  });

  test('pubspec 설명도 웹 전용이다', () {
    final String line = pubspec
        .split('\n')
        .firstWhere((String l) => l.startsWith('description:'));
    expect(line, isNot(contains('Android')));
    expect(line, isNot(contains('iOS')));
  });
}
