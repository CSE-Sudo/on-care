import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_test_images.dart';

/// 양보한 횟수를 센다.
class _YieldCounter {
  int count = 0;

  Future<void> call() async => count++;
}

/// 받은 인자를 적어 두고 정해 둔 값을 돌려주는 인코더.
class _SpyEncoder {
  _SpyEncoder(this.result);

  final Uint8List? result;
  final List<(int, int, int)> calls = <(int, int, int)>[];

  Future<Uint8List?> call(
    Uint8List rgba, {
    required int width,
    required int height,
  }) async {
    calls.add((rgba.length, width, height));
    return result;
  }
}

/// [image] 하나를 실은 한 쪽짜리 문서.
Future<Uint8List> _documentWith(
  CapturedWidget image, {
  required ReportJpegEncoder encode,
  ReportFrameYield yieldFrame = _noYield,
}) async {
  final pw.Document document = pw.Document();
  final pw.ImageProvider provider = await embedReportImage(
    document.document,
    image,
    encode: encode,
    yieldFrame: yieldFrame,
  );
  document.addPage(
    pw.Page(build: (_) => pw.Image(provider, width: 100, height: 50)),
  );
  return document.save();
}

Future<void> _noYield() async {}

Future<Uint8List?> _noJpeg(
  Uint8List rgba, {
  required int width,
  required int height,
}) async => null;

void main() {
  group('rgbOfRgba', () {
    test('투명도를 빼고 RGB 순서를 그대로 둔다', () async {
      final Uint8List rgba = Uint8List.fromList(<int>[
        1, 2, 3, 4, //
        5, 6, 7, 8,
        9, 10, 11, 12,
      ]);

      final Uint8List rgb = await rgbOfRgba(rgba, yieldFrame: _noYield);

      expect(rgb, <int>[1, 2, 3, 5, 6, 7, 9, 10, 11]);
    });

    test('빈 그림은 빈 결과다', () async {
      expect(await rgbOfRgba(Uint8List(0), yieldFrame: _noYield), isEmpty);
    });

    test('작은 그림은 양보 없이 한 번에 옮긴다', () async {
      final _YieldCounter counter = _YieldCounter();

      await rgbOfRgba(solidRgba(64, 64), yieldFrame: counter.call);

      expect(counter.count, 0);
    });

    test('큰 그림은 묶음마다 양보해 UI 스레드를 붙잡지 않는다 (#2484)', () async {
      final _YieldCounter counter = _YieldCounter();
      // 카드 한 장 크기(1,488 × 1,200) — 묶음 여러 개로 나뉜다.
      final Uint8List rgba = solidRgba(1488, 1200, value: 0x7f);

      final Uint8List rgb = await rgbOfRgba(rgba, yieldFrame: counter.call);

      expect(counter.count, greaterThan(3));
      expect(rgb.length, 1488 * 1200 * 3);
      // 묶음 경계에서도 빠진 픽셀이 없다.
      expect(rgb.every((int v) => v == 0x7f), isTrue);
    });
  });

  group('embedReportImage', () {
    final CapturedWidget card = CapturedWidget(
      rgba: solidRgba(40, 20),
      width: 40,
      height: 20,
    );

    test('인코더에 구운 픽셀과 크기를 그대로 넘긴다', () async {
      final _SpyEncoder encoder = _SpyEncoder(tinyJpeg);

      await _documentWith(card, encode: encoder.call);

      expect(encoder.calls, <(int, int, int)>[(40 * 20 * 4, 40, 20)]);
    });

    test('JPEG 를 받으면 다시 압축하지 않고 DCTDecode 로 싣는다', () async {
      final Uint8List bytes = await _documentWith(
        card,
        encode: _SpyEncoder(tinyJpeg).call,
      );
      final String source = pdfSource(bytes);

      expect(source, contains('/DCTDecode'));
      // 날 RGB 그림은 실리지 않는다 — 크기 40 짜리 이미지 사전이 없다.
      expect(RegExp(r'/Width\s+40\b').hasMatch(source), isFalse);
    });

    test('JPEG 를 받지 못하면 날 RGB 그림으로 물러선다', () async {
      final Uint8List bytes = await _documentWith(card, encode: _noJpeg);
      final String source = pdfSource(bytes);

      expect(source, isNot(contains('/DCTDecode')));
      expect(RegExp(r'/Width\s+40\b').hasMatch(source), isTrue);
      expect(RegExp(r'/Height\s+20\b').hasMatch(source), isTrue);
      // 카드는 불투명하다 — 투명도 가면을 따로 싣지 않는다.
      expect(source, isNot(contains('/SMask')));
    });

    test('날 RGB 로 물러설 때는 싣기 전에 양보한다', () async {
      final _YieldCounter counter = _YieldCounter();

      await _documentWith(card, encode: _noJpeg, yieldFrame: counter.call);

      expect(counter.count, greaterThanOrEqualTo(1));
    });

    test('JPEG 로 실을 때는 픽셀 변환을 하지 않는다', () async {
      final _YieldCounter counter = _YieldCounter();

      await _documentWith(
        CapturedWidget(rgba: solidRgba(1488, 1200), width: 1488, height: 1200),
        encode: _SpyEncoder(tinyJpeg).call,
        yieldFrame: counter.call,
      );

      expect(counter.count, 0);
    });
  });

  test('네이티브·테스트 플랫폼에는 기본 JPEG 인코더가 없다', () async {
    expect(
      await encodeReportJpeg(solidRgba(2, 2), width: 2, height: 2),
      isNull,
    );
    expect(
      await platformReportJpegEncoder(solidRgba(2, 2), width: 2, height: 2),
      isNull,
    );
  });

  test('양보는 다음 이벤트 차례로 미룬다', () async {
    final List<String> order = <String>[];
    final Future<void> pending = yieldToFrame().then((_) => order.add('yield'));
    order.add('sync');

    await pending;

    expect(order, <String>['sync', 'yield']);
  });

  test('실은 그림은 문서의 한 쪽에 한 번만 실린다', () async {
    final Uint8List bytes = await _documentWith(
      CapturedWidget(rgba: solidRgba(4, 4), width: 4, height: 4),
      encode: _noJpeg,
    );

    final String source = pdfSource(bytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(source).length, 1);
    expect(RegExp(r'/Subtype\s*/Image\b').allMatches(source).length, 1);
  });
}
