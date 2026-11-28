import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';

void main() {
  group('reportSheetLocalizations', () {
    test('문구는 한국어 하나다 (#3415)', () {
      final ReportSheetLocalizations l = reportSheetLocalizations();
      expect(l.localeName, 'ko');
      expect(l.reportsPdfDocTitle, isNotEmpty);
      expect(l.weekdayMon, isNotEmpty);
    });

    test('지원 로케일은 한국어뿐이다', () {
      expect(ReportSheetLocalizations.supportedLocales, const <Locale>[
        Locale('ko'),
      ]);
    });
  });

  group('reportFormatNumber', () {
    test('정수는 천 단위 쉼표만 붙인다', () {
      expect(reportFormatNumber(2058), '2,058');
      expect(reportFormatNumber(1234567), '1,234,567');
      expect(reportFormatNumber(12), '12');
    });

    test('소수는 한 자리까지, 정수 부분에도 쉼표', () {
      expect(reportFormatNumber(2058.46), '2,058.5');
      expect(reportFormatNumber(17.8), '17.8');
      expect(reportFormatNumber(3.0), '3');
    });

    test('음수도 같은 규칙이다', () {
      expect(reportFormatNumber(-1500), '-1,500');
    });
  });
}
