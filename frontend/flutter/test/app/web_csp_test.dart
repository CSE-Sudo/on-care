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
        ]),
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
      // 파일 → 그 파일을 부르는 곳. 워커는 index.html 이 아니라
      // js/pdfjs_worker.js 가 주소를 넘긴다.
      final String workerSetup = File(
        'web/js/pdfjs_worker.js',
      ).readAsStringSync();
      final Map<String, String> referencedFrom = <String, String>{
        'web/js/font_fix.js': markup,
        'web/js/pdfjs_worker.js': markup,
        'web/pdfjs/pdf.min.js': markup,
        'web/pdfjs/pdf.worker.min.js': workerSetup,
      };
      referencedFrom.forEach((String path, String referrer) {
        expect(File(path).existsSync(), isTrue, reason: path);
        expect(referrer, contains(path.replaceFirst('web/', '')), reason: path);
      });
    });

    test('pdf.js worker is configured right after pdf.js loads', () {
      final int lib = markup.indexOf('src="pdfjs/pdf.min.js"');
      final int worker = markup.indexOf('src="js/pdfjs_worker.js"');
      final int boot = markup.indexOf('src="flutter_bootstrap.js"');
      expect(lib, greaterThan(0));
      expect(worker, greaterThan(lib));
      expect(boot, greaterThan(worker));
    });

    test('font fix still runs from <head>', () {
      expect(head, contains('src="js/font_fix.js"'));
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
}
