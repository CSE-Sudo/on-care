import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 회원 앱이 싣는 pdf.js 사본 점검(#2818).
///
/// PDF 미리보기는 저장소에 실은 pdf.js 로 그린다. 3.11.174 는
/// CVE-2024-4367(조작된 글꼴로 임의 스크립트 실행) 영향 범위였다. 여기서 보는 것:
///
/// * 버전이 수정판(4.2.67) 이상이다.
/// * 본체·워커·`bundle.txt`·로더(`web/js/pdfjs_loader.js`) 상수가 같은 버전을 말한다.
/// * 트레이너 웹 사본과 바이트까지 같다 — 한쪽만 바뀌면 실패한다.
/// * `getDocument` 가 `isEvalSupported: false` 로 감싸져 있고, index.html 은
///   인라인 스크립트 없이 로더 파일만 부른다.
///
/// 갱신은 `frontend/tool/update_pdfjs.sh <버전>` 으로 두 앱을 함께 바꾼다.
void main() {
  const String dir = 'web/pdfjs';
  const List<int> minimumFixed = <int>[4, 2, 67];

  Map<String, String> bundle(String base) {
    final Map<String, String> out = <String, String>{};
    for (final String line in File('$base/bundle.txt').readAsLinesSync()) {
      final int eq = line.indexOf('=');
      if (eq > 0) out[line.substring(0, eq)] = line.substring(eq + 1);
    }
    return out;
  }

  List<int> parts(String version) =>
      version.split('.').map(int.parse).toList(growable: false);

  bool atLeast(List<int> v, List<int> min) {
    for (int i = 0; i < min.length; i++) {
      final int part = i < v.length ? v[i] : 0;
      if (part != min[i]) return part > min[i];
    }
    return true;
  }

  final String version = bundle(dir)['version'] ?? '';

  test('the bundled pdf.js is at or above the CVE-2024-4367 fix', () {
    expect(version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    expect(
      atLeast(parts(version), minimumFixed),
      isTrue,
      reason: 'pdf.js $version < 4.2.67',
    );
  });

  test('library, worker and loader name the same version', () {
    final String quoted = '"$version"';
    expect(File('$dir/pdf.min.js').readAsStringSync(), contains(quoted));
    expect(File('$dir/pdf.worker.min.js').readAsStringSync(), contains(quoted));
    expect(
      File('web/js/pdfjs_loader.js').readAsStringSync(),
      contains('const PDFJS_VERSION = $quoted;'),
    );
  });

  test('the copy matches the 트레이너 웹 copy byte for byte', () {
    for (final String name in <String>[
      'pdfjs/pdf.min.js',
      'pdfjs/pdf.worker.min.js',
      'pdfjs/bundle.txt',
      'js/pdfjs_loader.js',
    ]) {
      expect(
        File('web/$name').readAsBytesSync(),
        File('../flutter_trainer/web/$name').readAsBytesSync(),
        reason: '$name differs between the two web apps',
      );
    }
  });

  group('loader', () {
    final String loader = File('web/js/pdfjs_loader.js').readAsStringSync();
    final String html = File('web/index.html').readAsStringSync();

    test('getDocument always runs with isEvalSupported: false', () {
      expect(
        loader,
        contains(
          'hardened.getDocument = (src) => lib.getDocument(hardenedSource(src));',
        ),
      );
      expect(
        RegExp('isEvalSupported: false').allMatches(loader).length,
        greaterThanOrEqualTo(3),
        reason: 'string, bytes and options sources must all be hardened',
      );
    });

    test('Flutter boots only after pdf.js is in place', () {
      final int load = loader.indexOf('window.pdfjsLib =');
      final int boot = loader.indexOf('boot.src = "flutter_bootstrap.js"');
      expect(load, greaterThan(0));
      expect(boot, greaterThan(load));
    });

    test('index.html calls only the loader file', () {
      expect(
        html,
        contains('<script type="module" src="js/pdfjs_loader.js"></script>'),
      );
      expect(html, isNot(contains('<script src="pdfjs/pdf.min.js">')));
      expect(html, isNot(contains('<script src="flutter_bootstrap.js"')));
      // CSP 와 맞추기 위해 PDF 경로에 인라인 스크립트를 두지 않는다.
      expect(html, isNot(contains('pdfjsLib')));
    });
  });
}
