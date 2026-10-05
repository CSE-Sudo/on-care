import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 트레이너 웹 부팅 중 로딩 표시와 부팅 실패 안내(#3152).
///
/// 브라우저 없이 확인할 수 있는 범위에서 `web/index.html` 의 마크업과
/// `web/js/boot_status.js` 의 처리 규칙을 고정한다. 로딩 표시가 빠지면 느린 회선에서
/// 다시 빈 화면이 보이고, 첫 프레임에서 지우지 않으면 앱 화면을 덮는다.
void main() {
  final String html = File('web/index.html').readAsStringSync();
  final String head = html.substring(0, html.indexOf('</head>'));
  final String body = html.substring(html.indexOf('<body>'));
  // 주석 속 설명 글은 마크업이 아니다.
  final String markup = body.replaceAll(
    RegExp(r'<!--.*?-->', dotAll: true),
    '',
  );
  final String script = File('web/js/boot_status.js').readAsStringSync();
  // 주석을 뺀 코드만 본다 — 주석 속 낱말이 검사를 통과시키지 않게.
  final String code = script
      .split('\n')
      .where((String line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  group('index.html markup', () {
    test('logo and spinner are static markup shown before any script', () {
      final RegExpMatch? boot = RegExp(
        r'<div id="boot-status" class="boot"[^>]*>(.*?)</noscript>',
        dotAll: true,
      ).firstMatch(markup);
      expect(boot, isNotNull);
      final String block = boot!.group(1)!;
      expect(block, contains('class="boot-logo" src="icons/Icon-192.png"'));
      expect(File('web/icons/Icon-192.png').existsSync(), isTrue);
      expect(block, contains('class="boot-spinner"'));
      expect(block, contains('트레이너 웹을 불러오는 중입니다'));
      // 로딩 표시는 스크린 리더에도 알린다.
      expect(markup, contains('role="status" aria-live="polite"'));
    });

    test('failure panel with a reload button starts hidden', () {
      expect(markup, contains('<div class="boot-error" hidden>'));
      expect(markup, contains('트레이너 웹을 불러오지 못했습니다. 연결을 확인하고 새로고침해 주세요.'));
      expect(
        markup,
        contains('<button type="button" class="boot-reload">새로고침</button>'),
      );
    });

    test('noscript explains that JavaScript is required (ko and en)', () {
      final RegExpMatch? noscript = RegExp(
        r'<noscript>(.*?)</noscript>',
        dotAll: true,
      ).firstMatch(markup);
      expect(noscript, isNotNull);
      expect(noscript!.group(1)!, contains('JavaScript 가 필요합니다'));
      expect(noscript.group(1)!, contains('needs JavaScript'));
    });

    test('boot script runs before the loader that starts Flutter', () {
      final int status = markup.indexOf('src="js/boot_status.js"');
      final int loader = markup.indexOf('src="js/pdfjs_loader.js"');
      final int panel = markup.indexOf('id="boot-status"');
      expect(status, greaterThan(panel));
      expect(loader, greaterThan(status));
      // 실행 순서를 지키려고 async·defer·module 을 붙이지 않는다.
      expect(
        RegExp(r'<script src="js/boot_status.js"></script>').hasMatch(markup),
        isTrue,
      );
    });

    test('overlay covers the app and only uses inline styles in <head>', () {
      expect(head, contains('.boot {'));
      expect(head, contains('position: fixed; inset: 0;'));
      expect(head, contains('.boot-error[hidden] { display: none; }'));
      expect(head, contains('.boot-failed .boot-spinner { display: none; }'));
      expect(head, contains('prefers-reduced-motion'));
      // 첫 바이트에 바로 그리도록 외부 리소스(글꼴·이미지 URL)를 부르지 않는다.
      final String styles = RegExp(
        r'<style>(.*?)</style>',
        dotAll: true,
      ).allMatches(head).map((RegExpMatch m) => m.group(1)!).join();
      expect(styles, isNot(contains('url(')));
      expect(styles, isNot(contains('@import')));
    });
  });

  group('boot_status.js', () {
    test('removes the overlay on the first Flutter frame', () {
      expect(
        code,
        contains(
          'window.addEventListener("flutter-first-frame", done, { once: true });',
        ),
      );
      final String doneBody = _functionBody(code, 'done');
      expect(doneBody, contains('window.clearTimeout(timer);'));
      expect(doneBody, contains('root.parentNode.removeChild(root)'));
    });

    test('falls back to the failure panel after the timeout', () {
      expect(code, contains('var BOOT_TIMEOUT_MS = 20000;'));
      expect(
        code,
        contains('var timer = window.setTimeout(fail, BOOT_TIMEOUT_MS);'),
      );
      final String failBody = _functionBody(code, 'fail');
      expect(failBody, contains('if (finished || failed) return;'));
      expect(failBody, contains('panel.hidden = false;'));
      expect(failBody, contains('root.classList.add("boot-failed");'));
      expect(failBody, contains('root.setAttribute("role", "alert");'));
    });

    test('a failed boot script load shows the failure panel', () {
      // 리소스 로드 오류는 버블링하지 않아 캡처 단계에서만 받는다.
      expect(
        code,
        contains('window.addEventListener("error", onResourceError, true);'),
      );
      final String handler = _functionBody(code, 'onResourceError');
      expect(handler, contains('target.tagName === "SCRIPT"'));
      expect(handler, contains('fail()'));
      for (final String name in <String>[
        'flutter_bootstrap.js',
        'main.dart.js',
        'canvaskit.js',
      ]) {
        expect(code, contains('"$name"'), reason: name);
      }
    });

    test('a late first frame still clears the failure panel', () {
      // 안내를 띄운 뒤에도 done 은 `finished` 만 본다 — 아주 느린 회선에서 앱이
      // 결국 뜨면 안내가 앱을 덮지 않는다.
      final String doneBody = _functionBody(code, 'done');
      expect(doneBody, contains('if (finished) return;'));
      expect(doneBody, isNot(contains('failed')));
    });

    test('reload button reloads the page', () {
      expect(code, contains('window.location.reload();'));
      expect(code, contains('root.querySelector(".boot-reload")'));
    });

    test('Korean by default, English for other browser languages', () {
      expect(code, contains('트레이너 웹을 불러오지 못했습니다. 연결을 확인하고 새로고침해 주세요.'));
      expect(code, contains('트레이너 웹을 불러오는 중입니다'));
      expect(code, contains("Couldn't load the trainer web."));
      expect(code, contains('reload: "Refresh"'));
      expect(code, contains('.indexOf("ko") === 0 ? "ko" : "en"'));
      // 마크업의 한국어 문구와 스크립트의 한국어 문구가 같다.
      for (final String text in <String>[
        '트레이너 웹을 불러오지 못했습니다. 연결을 확인하고 새로고침해 주세요.',
        '트레이너 웹을 불러오는 중입니다',
        '새로고침',
      ]) {
        expect(markup, contains(text), reason: text);
      }
    });

    test('writes text safely and needs no relaxed CSP', () {
      expect(code, contains('node.textContent = value;'));
      for (final String unsafe in <String>[
        'innerHTML',
        'outerHTML',
        'insertAdjacentHTML',
        'document.write',
        'eval(',
        'new Function',
      ]) {
        expect(code, isNot(contains(unsafe)), reason: unsafe);
      }
      // 타이머는 함수로만 건다 — 문자열 타이머는 eval 과 같다.
      expect(RegExp(r'setTimeout\(\s*["`]').hasMatch(code), isFalse);
    });

    test('does nothing when the overlay markup is missing', () {
      expect(
        code,
        contains('var root = document.getElementById("boot-status");'),
      );
      expect(code, contains('if (!root) return;'));
    });
  });
}

/// `function name(...) { ... }` 의 본문을 중괄호 짝으로 꺼낸다.
String _functionBody(String code, String name) {
  final int start = code.indexOf('function $name(');
  expect(start, greaterThanOrEqualTo(0), reason: 'function $name');
  final int open = code.indexOf('{', start);
  int depth = 0;
  for (int i = open; i < code.length; i++) {
    if (code[i] == '{') depth++;
    if (code[i] == '}') {
      depth--;
      if (depth == 0) return code.substring(open + 1, i);
    }
  }
  fail('unbalanced braces in function $name');
}
