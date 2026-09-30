/// 데모 회원마다 매주 PT 가 1~2회 잡혀 있는지. (#2452)
///
/// 예전 시드는 이번 주 한 주만 심고, 그마저 오늘 요일에 해당하는 요일 슬롯은
/// 버렸다. 그래서 리포트를 열면 많은 회원이 `PT 세션 0회` 로 섰고, 지난 주로
/// 옮기면 전원이 0회였다. 실제 PT 회원은 주 1회(가끔 2회) 수업을 받는다.
///
/// 시연하는 요일마다 오늘 목록과 옮겨 간 수업이 달라지므로 일곱 요일을 모두
/// 고정해 본다.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_history.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

/// 2026-08-17(월) ~ 2026-08-23(일).
final DateTime _monday = DateTime(2026, 8, 17);

DateTime _dayOfWeek(int weekday) =>
    DateTime(_monday.year, _monday.month, _monday.day + weekday - 1, 9);

const List<String> _weekdayNames = <String>['월', '화', '수', '목', '금', '토', '일'];

/// 그 주 월요일 [back] 주 전의 [월, 일] 날짜 문자열.
(String, String) _weekRange(int back) {
  final DateTime start = DateTime(
    _monday.year,
    _monday.month,
    _monday.day - 7 * back,
  );
  final DateTime end = DateTime(start.year, start.month, start.day + 6);
  return (ymd(start), ymd(end));
}

int _minutes(String hhmm) {
  final List<int> parts = hhmm.split(':').map(int.parse).toList();
  return parts[0] * 60 + parts[1];
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<TrainerScheduleRow>> seededRows(DateTime clock) async {
    await seedIfEmpty(db, clock: clock);
    return db.select(db.trainerScheduleEntries).get();
  }

  for (int today = 1; today <= 7; today++) {
    final String label = '${_weekdayNames[today - 1]}요일';

    test('$label 시연: 회원마다 붙은 뒤의 모든 주에 수업이 1~2회다', () async {
      final List<TrainerScheduleRow> rows = await seededRows(_dayOfWeek(today));

      for (int id = 1; id <= 15; id++) {
        final String clientId = 'seed-client-$id';
        final int joined =
            demoMemberJoinedWeeksAgo[clientId] ?? demoReportHistoryWeeks;
        for (int back = 0; back < demoReportHistoryWeeks; back++) {
          final (String from, String to) = _weekRange(back);
          final int count = rows
              .where(
                (r) =>
                    r.clientId == clientId &&
                    r.status != ScheduleStatus.gap &&
                    r.date.compareTo(from) >= 0 &&
                    r.date.compareTo(to) <= 0,
              )
              .length;
          if (back <= joined) {
            expect(
              count,
              inInclusiveRange(1, 2),
              reason: '$clientId · $back주 전 · 오늘=$label',
            );
          } else {
            expect(
              count,
              0,
              reason: '$clientId 는 $joined주 전에 붙었다 — $back주 전 수업은 없어야 한다',
            );
          }
        }
      }
    });

    test('$label 시연: 한 주에 PT 를 1회 넘게 받는 회원은 몇 명뿐이다', () async {
      final List<TrainerScheduleRow> rows = await seededRows(_dayOfWeek(today));
      final (String from, String to) = _weekRange(1);
      final Map<String, int> perClient = <String, int>{};
      for (final TrainerScheduleRow r in rows) {
        if (r.clientId == null || r.type != SessionType.personalTraining) {
          continue;
        }
        if (r.date.compareTo(from) < 0 || r.date.compareTo(to) > 0) continue;
        perClient.update(r.clientId!, (n) => n + 1, ifAbsent: () => 1);
      }
      final int twice = perClient.values.where((n) => n == 2).length;
      expect(twice, inInclusiveRange(1, 5), reason: '$perClient');
      expect(perClient.values.every((n) => n <= 2), isTrue);
    });

    test('$label 시연: 트레이너의 어느 날도 수업이 겹치지 않는다', () async {
      final List<TrainerScheduleRow> rows = await seededRows(_dayOfWeek(today));
      final Map<String, List<TrainerScheduleRow>> byDate =
          <String, List<TrainerScheduleRow>>{};
      for (final TrainerScheduleRow r in rows) {
        if (r.durationMinutes <= 0) continue;
        byDate.putIfAbsent(r.date, () => <TrainerScheduleRow>[]).add(r);
      }
      for (final MapEntry<String, List<TrainerScheduleRow>> day
          in byDate.entries) {
        final List<TrainerScheduleRow> sorted = day.value
          ..sort((a, b) => a.time.compareTo(b.time));
        for (int i = 1; i < sorted.length; i++) {
          final TrainerScheduleRow prev = sorted[i - 1];
          final TrainerScheduleRow cur = sorted[i];
          expect(
            _minutes(prev.time) + prev.durationMinutes,
            lessThanOrEqualTo(_minutes(cur.time)),
            reason:
                '${day.key} ${prev.time} ${prev.clientName} 와 '
                '${cur.time} ${cur.clientName} 가 겹친다',
          );
        }
      }
    });

    test('$label 시연: 오늘 열은 원래 하루 목록 그대로다', () async {
      final DateTime clock = _dayOfWeek(today);
      final List<TrainerScheduleRow> rows = await seededRows(clock);
      final List<TrainerScheduleRow> todayRows = rows
          .where((r) => r.date == ymd(clock))
          .toList();
      expect(todayRows, hasLength(6));
      expect(
        todayRows.every((r) => RegExp(r'^seed-schedule-\d+$').hasMatch(r.id)),
        isTrue,
        reason: todayRows.map((r) => r.id).join(', '),
      );
    });
  }

  test('지난 주 수업은 완료이되 3주 전에 노쇼·취소가 한 건씩 있고, 이번 주는 '
      '요일에 따라 완료·예정으로 갈린다', () async {
    final DateTime thursday = _dayOfWeek(4);
    final List<TrainerScheduleRow> rows = await seededRows(thursday);
    final String monday = ymd(_monday);
    final String missFrom = ymd(
      DateTime(
        _monday.year,
        _monday.month,
        _monday.day - 7 * seedPastMissWeeksAgo,
      ),
    );
    final String missTo = ymd(
      DateTime(
        _monday.year,
        _monday.month,
        _monday.day - 7 * seedPastMissWeeksAgo + 6,
      ),
    );

    // 지난 상담(`seed-schedule-c`, #2667)은 되풀이한 수업이 아니다.
    final List<TrainerScheduleRow> past = rows
        .where(
          (r) =>
              r.date.compareTo(monday) < 0 &&
              !r.id.startsWith('seed-schedule-c'),
        )
        .toList();
    expect(past, isNotEmpty);
    // 끝내 하지 못한 수업은 3주 전의 배준혁 노쇼·강서연 회원 취소뿐이다(#2669).
    final List<TrainerScheduleRow> missed = past
        .where((r) => r.status != ScheduleStatus.done)
        .toList();
    expect(
      <(String, String)>{for (final r in missed) (r.clientName, r.status)},
      <(String, String)>{
        ('배준혁', ScheduleStatus.noShow),
        ('강서연', ScheduleStatus.cancelled),
      },
    );
    for (final TrainerScheduleRow r in missed) {
      expect(r.date.compareTo(missFrom) >= 0, isTrue, reason: r.date);
      expect(r.date.compareTo(missTo) <= 0, isTrue, reason: r.date);
    }
    final TrainerScheduleRow cancelled = missed.firstWhere(
      (r) => r.status == ScheduleStatus.cancelled,
    );
    expect(cancelled.cancellationSource, CancellationSource.member);
    expect(cancelled.cancellationReason, isNotEmpty);
    expect(cancelled.cancelledAt, isNotNull);
    expect(
      missed.firstWhere((r) => r.status == ScheduleStatus.noShow).noShowAt,
      isNotNull,
    );
    for (final TrainerScheduleRow r in past) {
      expect(r.type, SessionType.personalTraining);
      expect(r.clientId, isNotNull, reason: '지난 주에는 회원 PT 만 되풀이한다');
    }
  });

  test('지난 주 수업은 이번 주와 같은 요일·시각에 되풀이된다', () async {
    final List<TrainerScheduleRow> rows = await seededRows(_dayOfWeek(2));
    final (String from, String to) = _weekRange(0);
    final (String lastFrom, String lastTo) = _weekRange(1);

    Set<String> slotsOf(String from, String to) => <String>{
      for (final TrainerScheduleRow r in rows)
        if (r.clientId != null &&
            r.type == SessionType.personalTraining &&
            r.date.compareTo(from) >= 0 &&
            r.date.compareTo(to) <= 0)
          '${DateTime.parse(r.date).weekday} ${r.time} ${r.clientId}',
    };

    final Set<String> thisWeek = slotsOf(from, to)
      // 이번 주에 붙은 회원은 지난 주에 수업이 없다.
      ..removeWhere((s) => s.endsWith(' seed-client-7'));
    expect(slotsOf(lastFrom, lastTo), thisWeek);
  });

  test('같은 날 두 번 심어도 같은 스케줄이 나온다', () async {
    final DateTime clock = _dayOfWeek(5);
    String key(TrainerScheduleRow r) =>
        '${r.id}|${r.date}|${r.time}|${r.clientId}|${r.status}';

    final List<String> first = (await seededRows(clock)).map(key).toList()
      ..sort();

    final AppDatabase other = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(other.close);
    await seedIfEmpty(other, clock: clock);
    final List<String> second =
        (await other.select(other.trainerScheduleEntries).get())
            .map(key)
            .toList()
          ..sort();

    expect(second, first);
  });

  test('지난 주 수업은 다시 심을 때 지워지고 새로 깔린다 — seed- 행이다', () async {
    final List<TrainerScheduleRow> rows = await seededRows(_dayOfWeek(3));
    final (String from, _) = _weekRange(0);
    expect(
      rows
          .where((r) => r.date.compareTo(from) < 0)
          .every(
            (r) =>
                r.id.startsWith('seed-schedule-p') ||
                r.id.startsWith('seed-schedule-c'),
          ),
      isTrue,
    );
  });
}
