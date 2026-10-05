import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 서비스 워커를 쓰지 않는 웹 부팅(#3204).
///
/// 등록된 Flutter 서비스 워커가 `main.dart.js` 를 자기 캐시에서 내주면 새 배포 뒤
/// 새로고침해도 옛 번들이 떠, 새 버전 안내가 되풀이된다. 그래서
///
/// * 부팅 템플릿(`web/flutter_bootstrap.js`)은 워커를 등록하지 않고,
/// * 예전 빌드가 설치한 워커는 `web/js/sw_cleanup.js` 가 해제한다(두 앱 같은 파일).
void main() {
  final String html = File('web/index.html').readAsStringSync();
  final String head = html.substring(0, html.indexOf('</head>'));
  final String markup = html.replaceAll(
    RegExp(r'<!--.*?-->', dotAll: true),
    '',
  );

  /// `//` 설명 주석 줄을 뺀 코드.
  String code(String source) => source
      .split('\n')
      .where((String line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  group('bootstrap template', () {
    final File template = File('web/flutter_bootstrap.js');

    test('exists so the build does not use the default worker template', () {
      expect(template.existsSync(), isTrue);
    });

    test('loads Flutter without service worker settings', () {
      final String body = code(template.readAsStringSync());
      expect(body, contains('{{flutter_js}}'));
      expect(body, contains('{{flutter_build_config}}'));
      expect(body, contains('_flutter.loader.load();'));
      expect(body, isNot(contains('serviceWorkerSettings')));
      expect(body, isNot(contains('flutter_service_worker_version')));
      expect(body, isNot(contains('serviceWorker')));
      // 폐기된 진입점도 쓰지 않는다.
      expect(body, isNot(contains('loadEntrypoint')));
    });

    test('loader order is unchanged: pdf.js loader still boots Flutter', () {
      final String loader = File('web/js/pdfjs_loader.js').readAsStringSync();
      expect(loader, contains('boot.src = "flutter_bootstrap.js"'));
      expect(markup, isNot(contains('src="flutter_bootstrap.js"')));
    });
  });

  group('old worker cleanup', () {
    final File script = File('web/js/sw_cleanup.js');

    test('runs from a same-origin file in <head> (CSP, no inline)', () {
      expect(script.existsSync(), isTrue);
      expect(head, contains('<script src="js/sw_cleanup.js"></script>'));
      expect(
        RegExp('<script src="js/sw_cleanup.js"></script>').allMatches(markup),
        hasLength(1),
      );
    });

    test('runs before Flutter boots', () {
      expect(
        markup.indexOf('js/sw_cleanup.js'),
        lessThan(markup.indexOf('js/pdfjs_loader.js')),
      );
    });

    test('is the same file in both web apps', () {
      expect(
        script.readAsBytesSync(),
        File('../flutter/web/js/sw_cleanup.js').readAsBytesSync(),
      );
    });

    test('unregisters only this app folder and reloads at most once', () {
      final String body = code(script.readAsStringSync());
      expect(body, contains('"serviceWorker" in navigator'));
      expect(body, contains('getRegistrations()'));
      expect(body, contains('registration.unregister()'));
      // 앱 폴더(`<base href>`) 아래 등록만 — 소개 페이지 등 다른 경로는 두지 않는다.
      expect(body, contains('new URL(".", document.baseURI).href'));
      expect(body, contains('indexOf(appScope) === 0'));
      // 통제받던 페이지만, 탭당 한 번만 다시 읽는다.
      expect(body, contains('if (removed && controlled) reloadOnce();'));
      expect(
        body,
        contains('window.sessionStorage.getItem(RELOAD_KEY) === "1"'),
      );
      expect(body, contains('window.sessionStorage.setItem(RELOAD_KEY, "1")'));
      // 실패는 앱 부팅을 막지 않는다.
      expect(body, contains('.catch('));
    });

    test('does not register a worker itself', () {
      final String body = code(script.readAsStringSync());
      expect(body, isNot(contains('.register(')));
    });
  });
}
