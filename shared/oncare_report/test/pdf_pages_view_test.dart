import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';

/// 1×1 투명 PNG — 쪽 그림 자리를 채우는 가장 작은 그림.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00, //
  0x00, 0x05, 0x00, 0x01, 0xE9, 0xFA, 0xDC, 0xD8, 0x00, 0x00, 0x00, 0x00, //
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

final Uint8List _pdf = Uint8List.fromList('%PDF-1.4'.codeUnits);

const String _failed = '파일을 열지 못했어요';

Widget _app(Widget child) => MaterialApp(
  theme: reportSheetTheme(),
  home: Scaffold(body: child),
);

/// 쪽 그림. 위젯 테스트에서는 그림이 풀리기 전이라 높이가 0 이어서 화면 밖으로
/// 셈해진다 — 자리만 확인한다.
Finder _page(int index) =>
    find.byKey(ValueKey<String>('pdf-page-$index'), skipOffstage: false);

void main() {
  testWidgets('shows a spinner until the pages are ready', (tester) async {
    final Completer<List<Uint8List>> pages = Completer<List<Uint8List>>();
    await tester.pumpWidget(
      _app(
        PdfPagesView(
          pdf: _pdf,
          failedText: _failed,
          rasterize: (_) => pages.future,
        ),
      ),
    );
    expect(find.byKey(const ValueKey<String>('pdf-pages-loading')), findsOne);
    expect(find.text(_failed), findsNothing);

    pages.complete(<Uint8List>[_png]);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('pdf-pages-loading')),
      findsNothing,
    );
    expect(_page(0), findsOne);
  });

  testWidgets('builds one image for every page', (tester) async {
    await tester.pumpWidget(
      _app(
        PdfPagesView(
          pdf: _pdf,
          failedText: _failed,
          rasterize: (_) async => <Uint8List>[_png, _png],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_page(0), findsOne);
    expect(_page(1), findsOne);
  });

  testWidgets('hands the bytes it was given to the rasterizer', (tester) async {
    Uint8List? seen;
    await tester.pumpWidget(
      _app(
        PdfPagesView(
          pdf: _pdf,
          failedText: _failed,
          rasterize: (Uint8List pdf) async {
            seen = pdf;
            return <Uint8List>[_png];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(seen, same(_pdf));
  });

  testWidgets('says it failed instead of spinning forever', (tester) async {
    await tester.pumpWidget(
      _app(
        PdfPagesView(
          pdf: _pdf,
          failedText: _failed,
          rasterize: (_) async => throw StateError('pdf.js is not loaded'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_failed), findsOne);
    expect(
      find.byKey(const ValueKey<String>('pdf-pages-loading')),
      findsNothing,
    );
  });

  testWidgets('treats a document without pages as a failure', (tester) async {
    await tester.pumpWidget(
      _app(
        PdfPagesView(
          pdf: _pdf,
          failedText: _failed,
          rasterize: (_) async => <Uint8List>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_failed), findsOne);
  });

  testWidgets('rasterizes again when the document changes', (tester) async {
    int calls = 0;
    Future<List<Uint8List>> count(Uint8List _) async {
      calls++;
      return <Uint8List>[_png];
    }

    await tester.pumpWidget(
      _app(PdfPagesView(pdf: _pdf, failedText: _failed, rasterize: count)),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _app(
        PdfPagesView(
          pdf: Uint8List.fromList(_pdf),
          failedText: _failed,
          rasterize: count,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
