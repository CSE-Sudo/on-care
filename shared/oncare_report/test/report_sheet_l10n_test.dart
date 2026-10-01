import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';

void main() {
  group('reportSheetLocalizationsFor', () {
    test('한국어·영어는 그 언어로', () {
      expect(reportSheetLocalizationsFor(const Locale('ko')).localeName, 'ko');
      expect(reportSheetLocalizationsFor(const Locale('en')).localeName, 'en');
    });

    test('지역 코드가 붙어도 언어만 본다', () {
      expect(
        reportSheetLocalizationsFor(const Locale('en', 'US')).localeName,
        'en',
      );
    });

    test('모르는 언어면 한국어', () {
      expect(reportSheetLocalizationsFor(const Locale('ja')).localeName, 'ko');
    });

    testWidgets('로케일이 없는 트리에서도 한국어로 그린다', (tester) async {
      late ReportSheetLocalizations l;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            l = reportSheetLocalizationsOf(context);
            return const SizedBox();
          },
        ),
      );
      expect(l.localeName, 'ko');
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

  test('두 언어의 문구 키가 같다', () {
    final ReportSheetLocalizations ko = lookupReportSheetLocalizations(
      const Locale('ko'),
    );
    final ReportSheetLocalizations en = lookupReportSheetLocalizations(
      const Locale('en'),
    );
    expect(ko.reportsPdfDocTitle, isNot(en.reportsPdfDocTitle));
    expect(ko.weekdayMon, isNotEmpty);
    expect(en.weekdayMon, isNotEmpty);
  });
}
