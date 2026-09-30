import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';

/// 흰 픽셀로 채운 그림.
CapturedWidget _white(int width, int height) => CapturedWidget(
  rgba: Uint8List.fromList(List<int>.filled(width * height * 4, 255)),
  width: width,
  height: height,
);

Future<Uint8List?> _noJpeg(
  Uint8List rgba, {
  required int width,
  required int height,
}) async => null;

Future<void> _noYield() async {}

/// PDF 의 쪽 수.
int _pages(Uint8List pdf) => RegExp(
  r'/Type\s*/Page(?!s)',
).allMatches(latin1.decode(pdf, allowInvalid: true)).length;

void main() {
  group('reportSheetPdf (#2652)', () {
    test('결과지를 결과지 폭·굽는 배율로 구워 한 쪽에 얹는다', () async {
      final List<(double, double)> calls = <(double, double)>[];
      Future<CapturedWidget> capture(
        Widget child, {
        required double width,
        required double pixelRatio,
      }) async {
        calls.add((width, pixelRatio));
        return _white(10, 14);
      }

      int yields = 0;
      final Uint8List pdf = await reportSheetPdf(
        const SizedBox(),
        capture: capture,
        encode: _noJpeg,
        yieldFrame: () async => yields++,
      );
      expect(calls, <(double, double)>[
        (ReportSheetDocument.width, kReportSheetPixelRatio),
      ]);
      expect(yields, greaterThan(0));
      expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(_pages(pdf), 1);
    });

    test('굽지 못하면 오류를 호출부로 올린다', () async {
      Future<CapturedWidget> capture(
        Widget child, {
        required double width,
        required double pixelRatio,
      }) async => throw StateError('boom');

      expect(
        reportSheetPdf(
          const SizedBox(),
          capture: capture,
          encode: _noJpeg,
          yieldFrame: _noYield,
        ),
        throwsStateError,
      );
    });
  });

  group('reportSheetOnePage', () {
    test('JPEG 를 주면 그대로 싣는다', () async {
      final List<(int, int)> asked = <(int, int)>[];
      Future<Uint8List?> encode(
        Uint8List rgba, {
        required int width,
        required int height,
      }) async {
        asked.add((width, height));
        return null;
      }

      final Uint8List pdf = await reportSheetOnePage(
        _white(4, 6),
        encode: encode,
        yieldFrame: _noYield,
      );
      expect(asked, <(int, int)>[(4, 6)]);
      expect(_pages(pdf), 1);
    });
  });
}
