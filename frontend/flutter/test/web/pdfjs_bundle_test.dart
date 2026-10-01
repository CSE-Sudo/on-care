import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 회원 앱이 싣는 pdf.js 사본 점검(#2818).
///
/// PDF 미리보기는 저장소에 실은 pdf.js 로 그린다. 3.11.174 는
/// CVE-2024-4367(조작된 글꼴로 임의 스크립트 실행) 영향 범위였다. 여기서 보는 것:
///
/// * 버전이 수정판(4.2.67) 이상이다.
/// * 본체·워커·`bundle.txt`·index.html 상수가 같은 버전을 말한다.
/// * 트레이너 웹 사본과 바이트까지 같다 — 한쪽만 바뀌면 실패한다.
/// * `getDocument` 가 `isEvalSupported: false` 로 감싸져 있다.
///
/// 갱신은 `frontend/tool/update_pdfjs.sh <버전>` 으로 두 앱을 함께 바꾼다.
void main() {
  const String dir = 'web/pdfjs';
  const String siblingDir = '../flutter_trainer/web/pdfjs';
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

  test('library, worker and index.html name the same version', () {
    final String quoted = '"$version"';
    expect(File('$dir/pdf.min.js').readAsStringSync(), contains(quoted));
    expect(File('$dir/pdf.worker.min.js').readAsStringSync(), contains(quoted));
    expect(
      File('web/index.html').readAsStringSync(),
      contains('const PDFJS_VERSION = $quoted;'),
    );
  });

  test('the copy matches the 트레이너 웹 copy byte for byte', () {
    for (final String name in <String>[
      'pdf.min.js',
      'pdf.worker.min.js',
      'bundle.txt',
    ]) {
      expect(
        File('$dir/$name').readAsBytesSync(),
        File('$siblingDir/$name').readAsBytesSync(),
        reason: '$name differs between the two web apps',
      );
    }
  });

  group('index.html', () {
    final String html = File('web/index.html').readAsStringSync();

    test('getDocument always runs with isEvalSupported: false', () {
      expect(
        html,
        contains(
          'hardened.getDocument = (src) => lib.getDocument(hardenedSource(src));',
        ),
      );
      expect(
        RegExp('isEvalSupported: false').allMatches(html).length,
        greaterThanOrEqualTo(3),
        reason: 'string, bytes and options sources must all be hardened',
      );
    });

    test('the old classic script tag is gone', () {
      expect(html, isNot(contains('<script src="pdfjs/pdf.min.js">')));
    });

    test('Flutter boots only after pdf.js is in place', () {
      final int load = html.indexOf('window.pdfjsLib =');
      final int boot = html.indexOf('boot.src = "flutter_bootstrap.js"');
      expect(load, greaterThan(0));
      expect(boot, greaterThan(load));
      expect(html, isNot(contains('<script src="flutter_bootstrap.js"')));
    });
  });
}
