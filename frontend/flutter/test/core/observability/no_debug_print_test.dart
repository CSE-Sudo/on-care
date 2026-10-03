import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib` 에 `debugPrint`·`debugPrintStack`·`print` 가 남지 않게 막는다(#3051).
///
/// `debugPrint` 는 릴리스 빌드에서도 기기 로그로 나가고, 오류 보고기의 개인정보
/// 처리를 거치지 않는다. 잡아서 처리한 오류는
/// `core/observability/handled_error.dart` 의 `handledErrorReporterProvider` 로
/// 남긴다.
void main() {
  test('lib 에 debugPrint·print 호출이 없다', () {
    final RegExp call = RegExp(
      r'(^|[^A-Za-z0-9_.])(debugPrint|debugPrintStack|print)\(',
    );
    final List<String> hits = <String>[];
    final Iterable<File> files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (File f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('.g.dart') &&
              !f.path.contains(
                '${Platform.pathSeparator}gen${Platform.pathSeparator}',
              ),
        );
    for (final File file in files) {
      final List<String> lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String code = lines[i].split('//').first;
        if (call.hasMatch(code)) hits.add('${file.path}:${i + 1}');
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          '처리한 오류는 handledErrorReporterProvider 로 남긴다 '
          '(lib/core/observability/handled_error.dart).',
    );
  });
}
