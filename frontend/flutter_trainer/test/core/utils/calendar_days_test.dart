/// 날짜 계산은 24시간이 아니라 달력의 하루로 한다. (#2890)
///
/// 서머타임이 있는 기기 시간대에서는 `add(Duration(days: 7))` 가 시계가 바뀌는
/// 주를 건너며 전날 23:00 이나 같은 날 01:00 으로 떨어진다. 그 값을 `ymd()` 로
/// 자르면 주 이동이 엉뚱한 주로 가거나 같은 주를 맴돈다. Dart 에는 테스트 안에서
/// 프로세스 시간대를 바꿀 수단이 없어서, 어느 시간대에서든 성립해야 하는
/// **달력 불변식**(늘 자정·요일 유지·하루씩 빠짐없이)을 확인한다.
library;

import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_recurrence.dart';
import 'package:oncare_ui/oncare_ui.dart';

bool _isMidnight(DateTime d) =>
    d.hour == 0 && d.minute == 0 && d.second == 0 && d.millisecond == 0;

void main() {
  group('addCalendarDays', () {
    test('달·해를 넘어도 달력의 날짜다', () {
      expect(addCalendarDays(DateTime(2026, 1, 31), 1), DateTime(2026, 2));
      expect(addCalendarDays(DateTime(2026, 12, 28), 7), DateTime(2027, 1, 4));
      expect(addCalendarDays(DateTime(2027), -1), DateTime(2026, 12, 31));
    });

    test('윤년 2월 29일을 지난다', () {
      expect(addCalendarDays(DateTime(2028, 2, 28), 1), DateTime(2028, 2, 29));
      expect(addCalendarDays(DateTime(2028, 2, 29), 1), DateTime(2028, 3));
      expect(addCalendarDays(DateTime(2026, 2, 28), 1), DateTime(2026, 3));
    });

    test('시각은 버리고 자정으로 맞춘다', () {
      expect(
        addCalendarDays(DateTime(2026, 8, 20, 23, 30), 1),
        DateTime(2026, 8, 21),
      );
    });

    test('1년 내내 하루씩 넘겨도 날짜가 빠지거나 겹치지 않는다', () {
      // 기기 시간대에 서머타임이 있다면 이 안에 전환일이 두 번 들어 있다.
      var day = DateTime(2026);
      final seen = <String>{};
      for (var i = 0; i < 366; i++) {
        expect(_isMidnight(day), isTrue, reason: '${ymd(day)} 가 자정이 아니다');
        expect(seen.add(ymd(day)), isTrue, reason: '${ymd(day)} 가 두 번 나왔다');
        final next = addCalendarDays(day, 1);
        expect(next.weekday, day.weekday % 7 + 1);
        day = next;
      }
      expect(ymd(day), '2027-01-02');
    });

    test('주 단위로 넘기면 요일이 그대로다', () {
      final thursday = DateTime(2026, 3, 5);
      for (var week = -60; week <= 60; week++) {
        final d = addCalendarDays(thursday, 7 * week);
        expect(d.weekday, DateTime.thursday);
        expect(_isMidnight(d), isTrue);
      }
    });
  });

  group('mondayOf', () {
    test('월요일은 그대로, 일요일은 6일 전 월요일이다', () {
      expect(mondayOf(DateTime(2026, 8, 17)), DateTime(2026, 8, 17));
      expect(mondayOf(DateTime(2026, 8, 20, 13)), DateTime(2026, 8, 17));
      expect(mondayOf(DateTime(2026, 8, 23)), DateTime(2026, 8, 17));
    });

    test('달·해 경계의 주는 앞 달·앞 해의 월요일이다', () {
      expect(mondayOf(DateTime(2026, 10)), DateTime(2026, 9, 28));
      expect(mondayOf(DateTime(2027, 1, 2)), DateTime(2026, 12, 28));
    });

    test('1년 내내 주 이동을 되풀이해도 늘 월요일 자정이다', () {
      var monday = mondayOf(DateTime(2026));
      for (var i = 0; i < 60; i++) {
        expect(monday.weekday, DateTime.monday, reason: ymd(monday));
        expect(_isMidnight(monday), isTrue, reason: ymd(monday));
        // 다음 주의 아무 날이나 다시 월요일로 접어도 같은 주다.
        final next = addCalendarDays(monday, 7);
        expect(mondayOf(addCalendarDays(next, 3)), next);
        monday = next;
      }
    });
  });

  group('반복 회차', () {
    test('1년치 매일 회차에 같은 날짜가 두 번 나오지 않는다', () {
      final dates = seriesOccurrences(
        DateTime(2026),
        WeeklyRecurrence(
          weekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
          until: DateTime(2026, 12, 31),
        ),
      );
      final keys = dates.map(ymd).toList();
      expect(keys.toSet().length, keys.length);
      expect(dates.every(_isMidnight), isTrue);
    });

    test('주 1회 회차는 정확히 7일 간격의 같은 요일이다', () {
      final dates = seriesOccurrences(
        DateTime(2026, 3, 2),
        const WeeklyRecurrence(weekdays: <int>{1}, count: 12),
      );
      expect(dates, <DateTime>[
        for (var i = 0; i < 12; i++)
          addCalendarDays(DateTime(2026, 3, 2), 7 * i),
      ]);
    });
  });

  test('주 이동·주간 칸 계산에 24시간 더하기가 다시 들어오지 않는다', () {
    // 주 이동(#2890)이 깨졌던 자리들 — 날짜를 하루·한 주 단위로 옮기는 곳이다.
    const List<String> files = <String>[
      'lib/features/schedule/presentation/pages/schedule_page.dart',
      'lib/features/schedule/presentation/widgets/schedule_week_timetable.dart',
      'lib/features/dashboard/presentation/pages/dashboard_page.dart',
    ];
    final pattern = RegExp(r'\.(add|subtract)\(\s*(const\s+)?Duration\(days:');
    final leftovers = <String>[];
    for (final path in files) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: path);
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (pattern.hasMatch(lines[i])) {
          leftovers.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      leftovers,
      isEmpty,
      reason:
          '날짜 이동은 addCalendarDays()/mondayOf() 를 쓰세요:\n'
          '${leftovers.join('\n')}',
    );
  });
}
