import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';

/// 반복 일정 `시작 - 종료일` 칸의 종료일 표기. 반 칸 폭에 두 날짜를 모두
/// 연도까지 적으면 종료일이 잘린다 — 같은 해면 연도를 뺀다.
void main() {
  group('ymdRangeEnd', () {
    test('같은 해면 연도를 빼고 MM-DD 로 적는다', () {
      expect(
        ymdRangeEnd(DateTime(2026, 9, 29), DateTime(2026, 11, 10)),
        '11-10',
      );
    });

    test('한 자리 월·일은 0 을 채운다', () {
      expect(ymdRangeEnd(DateTime(2026, 1, 5), DateTime(2026, 3, 7)), '03-07');
    });

    test('해를 넘기면 연도를 남긴다', () {
      expect(
        ymdRangeEnd(DateTime(2026, 12, 2), DateTime(2027, 1, 31)),
        '2027-01-31',
      );
    });

    test('시작과 끝이 같은 날이어도 같은 해 규칙을 따른다', () {
      expect(
        ymdRangeEnd(DateTime(2026, 9, 29), DateTime(2026, 9, 29)),
        '09-29',
      );
    });

    test('시간이 붙어 있어도 날짜만 본다', () {
      expect(
        ymdRangeEnd(
          DateTime(2026, 9, 29, 23, 59),
          DateTime(2026, 11, 10, 0, 1),
        ),
        '11-10',
      );
    });
  });
}
