import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 웹 셸의 CSP 는 `'unsafe-eval'` 을 열지 않는다(#2828). `printing` 의 웹
/// 구현은 pdf.js 를 `window.eval` 로 찾으므로 그 길을 타는 순간 PDF 미리보기·
/// 인쇄가 멈춘다(#2973). 앱 코드는 공용 `oncare_report` 의 `PdfPagesView`·
/// `rasterPdfPages`·`printPdf` 를 쓴다 — 웹은 pdf.js 를 직접 부르고, 네이티브는
/// 그 안에서 `printing` 을 쓴다.
void main() {
  const Map<String, String> banned = <String, String>{
    'PdfPreview(': 'PdfPagesView',
    'Printing.raster': 'rasterPdfPages',
    'Printing.layoutPdf': 'printPdf',
    "import 'package:printing/printing.dart'": 'package:oncare_report',
  };

  test('app code never calls the printing web entry points', () {
    final List<String> hits = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        banned.forEach((String pattern, String instead) {
          if (line.contains(pattern)) {
            hits.add('${entity.path}:${i + 1} $pattern → $instead');
          }
        });
      }
    }
    expect(hits, isEmpty);
  });
}
