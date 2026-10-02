/// 주 단위 날짜 계산은 24시간이 아니라 달력의 하루로 한다. (#2890)
///
/// 서머타임이 있는 기기 시간대에서 `subtract(Duration(days: n))` 로 월요일을
/// 구하면 시계가 바뀌는 주에 전날 23:00 이 나와, 홈 운동 주간 그래프와 운동
/// 기간 집계의 주 키가 하루 어긋난다. Dart 에는 테스트 안에서 프로세스 시간대를
/// 바꿀 수단이 없어서, 어느 시간대에서든 성립해야 하는 달력 불변식을 본다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare_ui/oncare_ui.dart';

bool _isMidnight(DateTime d) =>
    d.hour == 0 && d.minute == 0 && d.second == 0 && d.millisecond == 0;

void main() {
  test('addCalendarDays 는 달·해·윤년을 넘어도 달력의 날짜다', () {
    expect(addCalendarDays(DateTime(2026, 1, 31), 1), DateTime(2026, 2));
    expect(addCalendarDays(DateTime(2027), -1), DateTime(2026, 12, 31));
    expect(addCalendarDays(DateTime(2028, 2, 28), 1), DateTime(2028, 2, 29));
    expect(
      addCalendarDays(DateTime(2026, 8, 20, 23, 30), 1),
      DateTime(2026, 8, 21),
    );
  });

  test('mondayOf 는 그 주의 월요일 자정이다', () {
    expect(mondayOf(DateTime(2026, 8, 17)), DateTime(2026, 8, 17));
    expect(mondayOf(DateTime(2026, 8, 20, 13)), DateTime(2026, 8, 17));
    expect(mondayOf(DateTime(2026, 8, 23)), DateTime(2026, 8, 17));
    expect(mondayOf(DateTime(2027, 1, 2)), DateTime(2026, 12, 28));
  });

  test('1년 내내 날마다 접어도 늘 월요일 자정이고 주가 7일씩 바뀐다', () {
    // 기기 시간대에 서머타임이 있다면 이 안에 전환일이 두 번 들어 있다.
    var day = DateTime(2026);
    DateTime? previous;
    for (var i = 0; i < 366; i++) {
      final monday = mondayOf(day);
      expect(monday.weekday, DateTime.monday, reason: '$day');
      expect(_isMidnight(monday), isTrue, reason: '$day');
      if (previous != null && monday != previous) {
        expect(monday, addCalendarDays(previous, 7));
      }
      previous = monday;
      day = addCalendarDays(day, 1);
    }
  });

  test('운동 기간 집계의 주 키도 같은 월요일이다', () {
    for (var i = 0; i < 14; i++) {
      final d = addCalendarDays(DateTime(2026, 3), i);
      expect(mondayOfWeek(d), mondayOf(d));
    }
  });
}
