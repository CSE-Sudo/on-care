/// 리포트 URL 의 `week` 계약 (#2289).
///
/// 주는 URL 이 원본이라, 만드는 쪽(`reportFor`)과 읽는 쪽(`parseReportWeek`)이
/// 같은 모양을 말해야 새로고침·링크 공유가 같은 주로 돌아온다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

void main() {
  group('AppRoutes.reportFor', () {
    test('회원만 주면 주 없이 회원만 싣는다', () {
      expect(AppRoutes.reportFor('c1'), '/reports?client=c1');
    });

    test('회원과 주를 함께 싣는다', () {
      expect(
        AppRoutes.reportFor('c1', weekStart: DateTime(2026, 8, 3)),
        '/reports?client=c1&week=2026-08-03',
      );
    });

    test('회원이 없으면 작업대 주소다 — 주만 싣는다', () {
      expect(
        AppRoutes.reportFor(null, weekStart: DateTime(2026, 8, 10)),
        '/reports?week=2026-08-10',
      );
    });

    test('회원도 주도 없으면 물음표 없는 탭 주소다', () {
      expect(AppRoutes.reportFor(null), AppRoutes.reports);
    });

    test('주의 시각은 버리고 날짜만 싣는다', () {
      expect(
        AppRoutes.reportFor('c1', weekStart: DateTime(2026, 8, 3, 23, 30)),
        '/reports?client=c1&week=2026-08-03',
      );
    });

    test('회원 id 의 특수문자는 인코딩된다', () {
      final Uri uri = Uri.parse(
        AppRoutes.reportFor('a b&c', weekStart: DateTime(2026, 8, 3)),
      );
      expect(uri.queryParameters['client'], 'a b&c');
      expect(uri.queryParameters['week'], '2026-08-03');
    });
  });

  group('AppRoutes.parseReportWeek', () {
    test('yyyy-MM-dd 를 그 날짜로 읽는다', () {
      expect(AppRoutes.parseReportWeek('2026-08-03'), DateTime(2026, 8, 3));
    });

    test('앞뒤 공백은 무시한다', () {
      expect(AppRoutes.parseReportWeek(' 2026-08-03 '), DateTime(2026, 8, 3));
    });

    test('윤년 2월 29일은 받는다', () {
      expect(AppRoutes.parseReportWeek('2028-02-29'), DateTime(2028, 2, 29));
    });

    for (final String? raw in <String?>[
      null,
      '',
      'garbage',
      '2026-8-3',
      '20260803',
      '2026/08/03',
      '2026-08-03T10:00:00',
      '2026-02-30',
      '2027-02-29',
      '2026-13-01',
      '2026-00-10',
      '2026-08-00',
      '2026-08-32',
    ]) {
      test('잘못된 값 `$raw` 는 null', () {
        expect(AppRoutes.parseReportWeek(raw), isNull);
      });
    }

    for (final DateTime monday in <DateTime>[
      DateTime(2026, 1, 5),
      DateTime(2026, 3, 30),
      DateTime(2026, 8, 17),
      DateTime(2026, 12, 28),
    ]) {
      test('reportFor 가 실은 주를 그대로 되읽는다 (${monday.toIso8601String()})', () {
        final String location = AppRoutes.reportFor('c1', weekStart: monday);
        final String? raw = Uri.parse(location).queryParameters['week'];
        expect(AppRoutes.parseReportWeek(raw), monday);
      });
    }
  });

  group('weekStartOf', () {
    test('월요일은 그대로다', () {
      expect(weekStartOf(DateTime(2026, 8, 17)), DateTime(2026, 8, 17));
    });

    test('일요일 밤은 그 주 월요일로 간다', () {
      expect(weekStartOf(DateTime(2026, 8, 23, 23, 59)), DateTime(2026, 8, 17));
    });

    test('시각을 버린다', () {
      final DateTime monday = weekStartOf(DateTime(2026, 8, 20, 13, 5));
      expect(monday, DateTime(2026, 8, 17));
      expect(monday.hour, 0);
    });

    test('달을 넘는다', () {
      expect(weekStartOf(DateTime(2026, 9, 2)), DateTime(2026, 8, 31));
    });

    test('해를 넘는다', () {
      expect(weekStartOf(DateTime(2027, 1, 3)), DateTime(2026, 12, 28));
    });

    test('윤일이 낀 주', () {
      expect(weekStartOf(DateTime(2028, 3, 2)), DateTime(2028, 2, 28));
    });

    test('1년 동안 언제나 월요일 0시다', () {
      for (int i = 0; i < 366; i++) {
        final DateTime day = DateTime(2026, 1, 1 + i, 12);
        final DateTime monday = weekStartOf(day);
        expect(monday.weekday, DateTime.monday, reason: '$day');
        expect(monday.hour, 0, reason: '$day');
        expect(day.difference(monday).inDays, lessThan(7), reason: '$day');
      }
    });
  });
}
