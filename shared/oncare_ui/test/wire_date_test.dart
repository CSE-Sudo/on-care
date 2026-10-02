import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 두 앱이 함께 쓰는 날짜 키·주 시작 계산(#2908). 서버 `app/core/week.py` 의
/// `monday_of` 와 같은 날을 같은 주로 묶어야 한다.
void main() {
  group('wireDate', () {
    test('YYYY-MM-DD 로 자릿수를 채워 적는다', () {
      expect(wireDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(wireDate(DateTime(2026, 12, 31)), '2026-12-31');
      expect(wireDate(DateTime(987, 3, 9)), '0987-03-09');
    });

    test('시각 성분은 보지 않는다', () {
      expect(wireDate(DateTime(2026, 10, 3, 23, 59, 59)), '2026-10-03');
      expect(wireDate(DateTime(2026, 10, 3)), '2026-10-03');
    });
  });

  group('parseWireDate', () {
    test('wireDate 로 적은 값을 시각 없는 날짜로 되읽는다', () {
      final DateTime day = DateTime(2026, 2, 28);
      expect(parseWireDate(wireDate(day)), day);
    });

    test('형식이 다르거나 달력에 없는 날이면 null 이다', () {
      for (final String? value in <String?>[
        null,
        '',
        '2026-2-28',
        '2026/02/28',
        '2026-02-28T00:00:00',
        '2026-02-30',
        '2026-13-01',
      ]) {
        expect(parseWireDate(value), isNull, reason: value);
      }
    });
  });

  group('mondayOf', () {
    test('월요일은 그 날 그대로, 일요일은 엿새 앞 월요일이다', () {
      // 2026-09-28 은 월요일, 2026-10-04 는 일요일이다.
      expect(mondayOf(DateTime(2026, 9, 28)), DateTime(2026, 9, 28));
      expect(mondayOf(DateTime(2026, 10, 4)), DateTime(2026, 9, 28));
      expect(mondayOf(DateTime(2026, 10, 5)), DateTime(2026, 10, 5));
    });

    test('한 주의 이레가 모두 같은 월요일로 묶인다', () {
      for (int i = 0; i < 7; i++) {
        expect(
          mondayOf(DateTime(2026, 9, 28 + i)),
          DateTime(2026, 9, 28),
          reason: 'day +$i',
        );
      }
    });

    test('시각 성분을 버린다', () {
      final DateTime monday = mondayOf(DateTime(2026, 10, 3, 18, 30, 15));
      expect(monday, DateTime(2026, 9, 28));
      expect(monday.hour, 0);
      expect(monday.minute, 0);
    });

    test('연말·연초 주는 해를 넘겨 앞 해 월요일로 간다', () {
      // 2027-01-01 은 금요일, 그 주 월요일은 2026-12-28 이다.
      expect(mondayOf(DateTime(2027)), DateTime(2026, 12, 28));
      expect(mondayOf(DateTime(2027, 1, 3)), DateTime(2026, 12, 28));
      expect(mondayOf(DateTime(2027, 1, 4)), DateTime(2027, 1, 4));
    });

    test('달 경계와 윤년 2월을 넘는다', () {
      // 2028-03-01 은 수요일 — 윤년이라 앞 월요일은 2028-02-28 이다.
      expect(mondayOf(DateTime(2028, 3)), DateTime(2028, 2, 28));
      // 2026-03-01 은 일요일 — 평년이라 앞 월요일은 2026-02-23 이다.
      expect(mondayOf(DateTime(2026, 3)), DateTime(2026, 2, 23));
    });
  });
}
