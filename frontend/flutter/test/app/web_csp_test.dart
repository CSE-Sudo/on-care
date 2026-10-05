import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 웹 셸의 Content-Security-Policy(#2828).
///
/// 페이지에 스크립트가 주입돼도 돌지 못하게 하는 것이 목적이다. 정책이 빠지거나
/// 누가 인라인 `<script>` 를 다시 넣으면(그러면 `'unsafe-inline'` 을 열어야 한다)
/// 여기서 잡는다. 실제로 불러오는 출처(CanvasKit·카카오맵·pdf.js·drift)가 막히지
/// 않는지도 본다 — 막히면 화면이 뜨지 않거나 지도·PDF 미리보기가 깨진다.
void main() {
  final String html = File('web/index.html').readAsStringSync();
  final String head = html.substring(0, html.indexOf('</head>'));
  // 주석 속 `<script>` 설명 글은 태그가 아니다.
  final String markup = html.replaceAll(
    RegExp(r'<!--.*?-->', dotAll: true),
    '',
  );

  String policy() {
    final RegExpMatch? m = RegExp(
      r'<meta\s+http-equiv="Content-Security-Policy"\s+content="([^"]*)"',
    ).firstMatch(head);
    expect(m, isNotNull, reason: 'CSP meta is missing from <head>');
    return m!.group(1)!;
  }

  Map<String, List<String>> directives() {
    final Map<String, List<String>> out = <String, List<String>>{};
    for (final String part in policy().split(';')) {
      final List<String> tokens = part
          .trim()
          .split(RegExp(r'\s+'))
          .where((String t) => t.isNotEmpty)
          .toList();
      if (tokens.isEmpty) continue;
      expect(out.containsKey(tokens.first), isFalse, reason: tokens.first);
      out[tokens.first] = tokens.sublist(1);
    }
    return out;
  }

  group('content security policy', () {
    test('is declared once, before any script', () {
      expect(
        RegExp('http-equiv="Content-Security-Policy"').allMatches(markup),
        hasLength(1),
      );
      expect(
        markup.indexOf('Content-Security-Policy'),
        lessThan(markup.indexOf('<script')),
      );
    });

    test('falls back to same origin and blocks plugins and base hijack', () {
      final Map<String, List<String>> d = directives();
      expect(d['default-src'], <String>["'self'"]);
      expect(d['object-src'], <String>["'none'"]);
      expect(d['base-uri'], <String>["'self'"]);
      expect(d['form-action'], <String>["'self'"]);
    });

    test('script-src allows no inline code or eval', () {
      final List<String> script = directives()['script-src']!;
      expect(script, isNot(contains("'unsafe-inline'")));
      expect(script, isNot(contains("'unsafe-eval'")));
      expect(script, isNot(contains('https:')));
      expect(script, isNot(contains('*')));
    });

    test('script-src opens only the sources the app loads', () {
      final List<String> script = directives()['script-src']!;
      expect(
        script,
        unorderedEquals(<String>[
          "'self'",
          // CanvasKit·drift(sqlite3.wasm) 의 WebAssembly 컴파일.
          "'wasm-unsafe-eval'",
          // CanvasKit 렌더러(Flutter 기본 CDN).
          'https://www.gstatic.com',
          // 카카오맵 SDK 와 SDK 가 이어 올리는 본체.
          'https://dapi.kakao.com',
          'https://t1.daumcdn.net',
          // 구글 로그인 버튼(Google Identity Services, #330).
          'https://accounts.google.com/gsi/client',
        ]),
      );
    });

    test('Google sign-in button sources are open and nothing wider (#330)', () {
      final Map<String, List<String>> d = directives();
      expect(d['frame-src'], contains('https://accounts.google.com/gsi/'));
      expect(d['style-src'], contains('https://accounts.google.com/gsi/style'));
      // 구글 출처 전체(accounts.google.com)를 열지 않는다 — GIS 경로만.
      for (final List<String> sources in d.values) {
        expect(sources, isNot(contains('https://accounts.google.com')));
      }
      // 카카오 웹 로그인은 팝업 + 같은 출처 콜백이라 카카오 인증 출처를 열지 않는다.
      expect(
        d.values.expand((s) => s),
        isNot(contains('https://kauth.kakao.com')),
      );
    });

    test('engine fonts and workers are reachable', () {
      final Map<String, List<String>> d = directives();
      expect(d['font-src'], contains('https://fonts.gstatic.com'));
      expect(
        d['connect-src'],
        anyOf(contains('https://fonts.gstatic.com'), contains('https:')),
      );
      expect(d['connect-src'], contains("'self'"));
      // pdf.js·drift 워커는 같은 출처 파일이다.
      expect(d['worker-src'], contains("'self'"));
      // `printing` 의 웹 인쇄는 blob: iframe 을 쓴다.
      expect(d['frame-src'], contains('blob:'));
    });
  });

  group('scripts', () {
    test('every <script> tag loads a same-origin file', () {
      final Iterable<RegExpMatch> tags = RegExp(
        r'<script\b([^>]*)>(.*?)</script>',
        dotAll: true,
      ).allMatches(markup);
      expect(tags, isNotEmpty);
      for (final RegExpMatch tag in tags) {
        final String attrs = tag.group(1)!;
        final RegExpMatch? src = RegExp(r'src="([^"]+)"').firstMatch(attrs);
        expect(src, isNotNull, reason: 'inline <script> needs unsafe-inline');
        expect(tag.group(2)!.trim(), isEmpty, reason: attrs);
        expect(src!.group(1)!, isNot(startsWith('http')), reason: attrs);
        expect(src.group(1)!, isNot(startsWith('//')), reason: attrs);
      }
    });

    test('moved helpers ship next to index.html', () {
      // index.html 은 pdf.js 로더만 부른다. pdf.js 본체·워커는 로더가
      // `pdfjs/` 아래에서 올린다(#2818).
      final String loader = File('web/js/pdfjs_loader.js').readAsStringSync();
      for (final String path in <String>['web/js/pdfjs_loader.js']) {
        expect(File(path).existsSync(), isTrue, reason: path);
        expect(markup, contains(path.replaceFirst('web/', '')), reason: path);
      }
      expect(loader, contains('"pdfjs/"'));
      for (final String name in <String>['pdf.min.js', 'pdf.worker.min.js']) {
        expect(File('web/pdfjs/$name').existsSync(), isTrue, reason: name);
        expect(loader, contains(name), reason: name);
      }
    });

    test('pdf.js loads before Flutter boots', () {
      // 로더가 pdf.js 를 올린 뒤에 Flutter 를 띄운다 — 먼저 뜨면 `printing` 이
      // 자기 로더(CDN)로 빠진다. index.html 은 Flutter 를 따로 부르지 않는다.
      final String loader = File('web/js/pdfjs_loader.js').readAsStringSync();
      final int lib = loader.indexOf('pdf.min.js');
      final int boot = loader.indexOf('"flutter_bootstrap.js"');
      expect(lib, greaterThan(0));
      expect(boot, greaterThan(lib));
      expect(markup, isNot(contains('src="flutter_bootstrap.js"')));
    });

    test('no HTML-renderer font fix is shipped', () {
      // 웹은 CanvasKit 으로만 그려 HTML 렌더러용 글꼴 보정은 효과가 없고,
      // 스크립트는 열려 있는 내내 0.15초마다 문서를 조회했다(#3159).
      expect(File('web/js/font_fix.js').existsSync(), isFalse);
      expect(markup, isNot(contains('font_fix')));
      expect(markup, isNot(contains('flt-glass-pane')));
    });
  });

  test('referrer policy does not leak full URLs cross-origin', () {
    expect(
      RegExp(
        r'<meta\s+name="referrer"\s+content="strict-origin-when-cross-origin"',
      ).hasMatch(head),
      isTrue,
    );
  });

  test('old service worker cleanup runs from a same-origin file (#3204)', () {
    // 예전 빌드의 서비스 워커를 지우는 스크립트도 인라인으로 두면 'unsafe-inline' 을
    // 열어야 한다. 같은 출처 파일이고, 정책은 그대로다. 워커를 더 쓰지 않으므로
    // worker-src 는 pdf.js·drift 워커용 그대로다.
    expect(File('web/js/sw_cleanup.js').existsSync(), isTrue);
    expect(markup, contains('<script src="js/sw_cleanup.js"></script>'));
    expect(directives()['script-src'], isNot(contains("'unsafe-inline'")));
    expect(directives()['worker-src'], <String>["'self'", 'blob:']);
  });
}
