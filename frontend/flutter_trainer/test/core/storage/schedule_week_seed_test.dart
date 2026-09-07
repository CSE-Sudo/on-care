/// 데모 스케줄이 한 주(월~일)를 채우는지. (#1210)
///
/// 예전에는 시드가 오늘 하루치뿐이어서, 주간 시간표를 열면 오늘 열만 차 있고
/// 나머지 여섯 열이 비어 있었다. 시연하는 요일은 매번 다르므로 상태(완료·예정)를
/// 데이터에 박을 수 없다 — 지난 요일과 남은 요일을 시딩이 갈라야 한다.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

/// 2026-08-17(월) ~ 2026-08-23(일). 요일별로 오늘을 고정해 두 방향(지난 요일·남은
/// 요일)을 모두 본다.
final DateTime _monday = DateTime(2026, 8, 17, 9);

DateTime _dayOfWeek(int weekday) => DateTime(
  _monday.year,
  _monday.month,
  _monday.day + weekday - 1,
  9,
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  for (int today = 1; today <= 7; today++) {
    test('$today요일에 시연해도 월~일 모든 열에 일정이 있다', () async {
      await seedIfEmpty(db, clock: _dayOfWeek(today));

      final rows = await db.select(db.trainerScheduleEntries).get();
      final Set<String> dates = rows.map((r) => r.date).toSet();
      for (int weekday = 1; weekday <= 7; weekday++) {
        expect(
          dates,
          contains(ymd(_dayOfWeek(weekday))),
          reason: '오늘=$today요일 · 빈 열=$weekday요일',
        );
      }
    });
  }

  test('지난 요일은 완료, 남은 요일은 예정으로 놓인다', () async {
    // 목요일에 고정 — 앞뒤로 요일이 남아 두 규칙을 한 번에 본다.
    final DateTime thursday = _dayOfWeek(4);
    await seedIfEmpty(db, clock: thursday);

    final rows = await db.select(db.trainerScheduleEntries).get();
    for (final row in rows) {
      if (row.date == ymd(thursday)) continue; // 오늘 몫은 목록이 정한 상태다.
      final bool past = row.date.compareTo(ymd(thursday)) < 0;
      expect(
        row.status,
        past ? ScheduleStatus.done : ScheduleStatus.upcoming,
        reason: '${row.date} ${row.time} ${row.clientName}',
      );
    }
  });

  test('오늘 열은 완료·예정·공백이 섞인 원래 하루 그대로다', () async {
    final DateTime wednesday = _dayOfWeek(3);
    await seedIfEmpty(db, clock: wednesday);

    final today = await (db.select(
      db.trainerScheduleEntries,
    )..where((t) => t.date.equals(ymd(wednesday)))).get();

    expect(
      today.map((r) => r.status).toSet(),
      containsAll(<String>[
        ScheduleStatus.done,
        ScheduleStatus.upcoming,
        ScheduleStatus.gap,
      ]),
    );
    // 오늘 슬롯과 요일 슬롯이 같은 날에 겹치면 오늘 화면에 없던 수업이 끼어든다.
    expect(today.every((r) => !r.id.startsWith('seed-schedule-w')), isTrue);
  });

  test('PT와 상담은 규칙적인 시작 시간에 다양한 길이로 배치된다', () async {
    await seedIfEmpty(db, clock: _dayOfWeek(4));

    final rows = await db.select(db.trainerScheduleEntries).get();
    final consultations = rows
        .where((r) => r.type == SessionType.consultation)
        .toList();
    final training = rows
        .where((r) => r.type == SessionType.personalTraining)
        .toList();

    expect(
      consultations.map((r) => r.date).toSet().length,
      greaterThanOrEqualTo(2),
      reason: '상담이 하루에만 있으면 상담 흐름을 다른 요일에서 시연할 수 없다',
    );
    expect(training.map((r) => r.date).toSet().length, greaterThanOrEqualTo(5));
    final scheduled = rows.where((r) => r.durationMinutes > 0);
    for (final row in scheduled) {
      final parts = row.time.split(':');
      final hour = int.parse(parts.first);
      final minute = int.parse(parts.last);
      expect(hour, inInclusiveRange(9, 22), reason: '${row.date} ${row.time}');

      // 하루의 첫 수업만 9:00·9:30 으로 앞당길 수 있다 — 모든 요일이
      // 나란히 10:00에 시작하지 않도록 하는 예외다(#1319). 그 시간대는
      // 짝수·홀수 정시 규칙에서 벗어난다.
      if (hour == 9) {
        expect(<int>{0, 30}, contains(minute), reason: '${row.date} ${row.time}');
      } else {
        expect(minute, 0, reason: '${row.date} ${row.time}');
        if (row.type == SessionType.personalTraining) {
          expect(hour.isEven, isTrue, reason: '${row.date} ${row.time}');
        } else if (row.type == SessionType.consultation) {
          expect(hour.isOdd, isTrue, reason: '${row.date} ${row.time}');
        }
      }

      if (row.type == SessionType.personalTraining) {
        expect(
          <int>{30, 45, 50, 60, 90},
          contains(row.durationMinutes),
          reason: '${row.date} ${row.time}',
        );
      } else if (row.type == SessionType.consultation) {
        expect(
          <int>{30, 45, 60},
          contains(row.durationMinutes),
          reason: '${row.date} ${row.time}',
        );
      }
    }

    expect(
      training.map((r) => r.durationMinutes).toSet(),
      containsAll(<int>{30, 45, 50, 60, 90}),
    );
    expect(
      consultations.map((r) => r.durationMinutes).toSet(),
      containsAll(<int>{30, 45, 60}),
    );

    for (final date in rows.map((r) => r.date).toSet()) {
      final day = scheduled.where((r) => r.date == date).toList()
        ..sort((a, b) => a.time.compareTo(b.time));
      for (var index = 1; index < day.length; index++) {
        final previous = day[index - 1];
        final current = day[index];
        final previousParts = previous.time.split(':').map(int.parse).toList();
        final currentParts = current.time.split(':').map(int.parse).toList();
        final previousEnd =
            previousParts[0] * 60 +
            previousParts[1] +
            previous.durationMinutes;
        final currentStart = currentParts[0] * 60 + currentParts[1];
        expect(
          previousEnd,
          lessThanOrEqualTo(currentStart),
          reason: '$date ${previous.time}와 ${current.time} 일정이 겹친다',
        );
      }
    }
  });

  test('명단에 있는 이름은 회원 id 로, 미등록 상담자는 이름만 남는다', () async {
    await seedIfEmpty(db, clock: _dayOfWeek(4));

    final rows = await db.select(db.trainerScheduleEntries).get();
    final clients = await db.select(db.trainerClients).get();
    final Map<String, String> idByName = <String, String>{
      for (final c in clients) c.name: c.id,
    };

    for (final row in rows) {
      final String name = row.clientName;
      if (idByName.containsKey(name)) {
        expect(row.clientId, idByName[name], reason: name);
      }
    }
    // 상담 데모에는 명단에 없는 사람이 하나는 있어야 한다 — 신규 상담이 그렇다.
    expect(
      rows.any(
        (r) =>
            r.clientName.isNotEmpty &&
            !idByName.containsKey(r.clientName) &&
            r.clientId == null,
      ),
      isTrue,
    );
  });
}
