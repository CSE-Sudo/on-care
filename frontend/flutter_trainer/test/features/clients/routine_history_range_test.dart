import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';

RoutineHistoryEntry _entry(
  String id,
  DateTime? completedAt, {
  DateTime? date,
}) => RoutineHistoryEntry(
  id: id,
  dateLabel: id,
  label: 'PT 세션 · 트레이너 지도',
  completionRate: 100,
  exercises: <ClientExerciseItem>[],
  clientFeedback: '',
  trainerNote: '',
  completedAt: completedAt,
  date: date,
);

/// KST 벽시계 [kst] 와 같은 순간의 UTC 시각 — 실 API 가 `completed_at` 으로 준다.
DateTime _utcOfKst(DateTime kst) => DateTime.utc(
  kst.year,
  kst.month,
  kst.day,
  kst.hour,
  kst.minute,
).subtract(const Duration(hours: 9));

List<String> _ids(List<RoutineHistoryEntry> entries) =>
    entries.map((RoutineHistoryEntry e) => e.id).toList();

void main() {
  // 목요일. 주 범위(월~일)의 양 끝이 이 날 앞뒤로 갈라져야 경계를 볼 수 있다.
  final DateTime today = DateTime(2026, 8, 20);

  test('오늘 은 그날 하루만 남긴다 — 시각은 보지 않는다', () {
    final List<RoutineHistoryEntry> entries = <RoutineHistoryEntry>[
      // 서버가 주는 완료 시각은 하루 중 아무 때나다. 마지막 날 0시와 견주면
      // 저녁 운동이 통째로 빠진다(#1114).
      _entry('오늘-저녁', DateTime(2026, 8, 20, 22, 45)),
      _entry('오늘-새벽', DateTime(2026, 8, 20, 0, 1)),
      _entry('어제', DateTime(2026, 8, 19, 23, 59)),
      _entry('내일', DateTime(2026, 8, 21)),
    ];

    expect(
      _ids(historyInRange(entries, clientRangeFor(ClientPeriod.today, today))),
      <String>['오늘-저녁', '오늘-새벽'],
    );
  });

  test('이번 주 는 월요일 0시부터 일요일까지 — 양 끝을 포함한다', () {
    final List<RoutineHistoryEntry> entries = <RoutineHistoryEntry>[
      _entry('지난-일요일', DateTime(2026, 8, 16, 20)),
      _entry('월요일', DateTime(2026, 8, 17)),
      _entry('일요일', DateTime(2026, 8, 23, 21, 30)),
      _entry('다음-월요일', DateTime(2026, 8, 24)),
    ];

    expect(
      _ids(historyInRange(entries, clientRangeFor(ClientPeriod.week, today))),
      <String>['월요일', '일요일'],
    );
  });

  test('전체 는 첫 기록일까지 거슬러 오른다 (#2079)', () {
    // 예전에는 12주 고정 창이라 그보다 오래된 이력이 사라졌다.
    final List<RoutineHistoryEntry> entries = <RoutineHistoryEntry>[
      _entry('막차', today.subtract(const Duration(days: 83))),
      _entry('그-앞', today.subtract(const Duration(days: 200))),
    ];

    expect(
      _ids(
        historyInRange(
          entries,
          clientRangeFor(
            ClientPeriod.month,
            today,
            firstRecord: today.subtract(const Duration(days: 300)),
          ),
        ),
      ),
      <String>['막차', '그-앞'],
    );
  });

  test('첫 기록일이 없으면 전체 도 오늘 하루다', () {
    final List<RoutineHistoryEntry> entries = <RoutineHistoryEntry>[
      _entry('오늘', today),
      _entry('어제', today.subtract(const Duration(days: 1))),
    ];

    expect(
      _ids(historyInRange(entries, clientRangeFor(ClientPeriod.month, today))),
      <String>['오늘'],
    );
  });

  test('완료 날짜가 없는 기록은 어느 기간에서도 사라지지 않는다', () {
    // 날짜를 모르는 것과 그 기간이 아닌 것은 다른 말이다. 마이그레이션 이전
    // 행이나 실 API 가 드물게 못 채운 값이 화면에서 사라지면, 트레이너는
    // 기록이 지워진 줄 안다(#1114).
    final List<RoutineHistoryEntry> entries = <RoutineHistoryEntry>[
      _entry('날짜-없음', null),
      _entry('먼-과거', DateTime(2020, 3, 4)),
    ];

    for (final ClientPeriod period in ClientPeriod.values) {
      expect(
        _ids(historyInRange(entries, clientRangeFor(period, today))),
        <String>['날짜-없음'],
        reason: period.name,
      );
    }
  });

  test('걸러도 원래 차례(최신순)는 흐트러지지 않는다', () {
    final List<RoutineHistoryEntry> entries = <RoutineHistoryEntry>[
      _entry('1', DateTime(2026, 8, 20)),
      _entry('2', DateTime(2026, 8, 3)),
      _entry('3', DateTime(2026, 8, 19)),
      _entry('4', DateTime(2026, 8, 17)),
    ];

    expect(
      _ids(historyInRange(entries, clientRangeFor(ClientPeriod.week, today))),
      <String>['1', '3', '4'],
    );
  });

  group('historyDayOf — 기록이 붙는 날 (#2748)', () {
    test('서버가 준 운동일이 완료 시각보다 먼저다', () {
      // 어제 운동을 오늘 오후에 소급 체크했다(#2506).
      final RoutineHistoryEntry backfilled = _entry(
        '소급',
        _utcOfKst(DateTime(2026, 8, 20, 15)),
        date: DateTime(2026, 8, 19),
      );
      expect(historyDayOf(backfilled), DateTime(2026, 8, 19));
    });

    test('KST 07:30 완료는 UTC 로는 전날이어도 그날이다', () {
      final DateTime at = _utcOfKst(DateTime(2026, 8, 20, 7, 30));
      expect(at.isUtc, isTrue);
      expect(at.day, 19); // UTC 로 자르면 전날이 된다
      expect(historyDayOf(_entry('이른-아침', at)), DateTime(2026, 8, 20));
    });

    test('KST 자정 직전·직후 완료가 각자 그날에 붙는다', () {
      expect(
        historyDayOf(_entry('a', _utcOfKst(DateTime(2026, 8, 19, 23, 59)))),
        DateTime(2026, 8, 19),
      );
      expect(
        historyDayOf(_entry('b', _utcOfKst(DateTime(2026, 8, 20, 0, 1)))),
        DateTime(2026, 8, 20),
      );
    });

    test('UTC 가 아닌 시각(데모 벽시계)은 그대로 자른다', () {
      expect(
        historyDayOf(_entry('demo', DateTime(2026, 8, 20, 7, 30))),
        DateTime(2026, 8, 20),
      );
    });

    test('운동일의 시각은 버린다', () {
      expect(
        historyDayOf(_entry('d', null, date: DateTime(2026, 8, 20, 18))),
        DateTime(2026, 8, 20),
      );
    });

    test('둘 다 없으면 날짜를 모른다', () {
      expect(historyDayOf(_entry('none', null)), isNull);
    });
  });

  group('historyInRange 도 같은 날짜 규칙을 쓴다 (#2748)', () {
    test('KST 이른 아침 완료는 오늘 범위에 든다', () {
      final List<RoutineHistoryEntry> entries = <RoutineHistoryEntry>[
        _entry('오늘-0730', _utcOfKst(DateTime(2026, 8, 20, 7, 30))),
        _entry('어제-2330', _utcOfKst(DateTime(2026, 8, 19, 23, 30))),
      ];
      expect(
        _ids(
          historyInRange(entries, clientRangeFor(ClientPeriod.today, today)),
        ),
        <String>['오늘-0730'],
      );
    });

    test('소급 체크한 기록은 체크한 날이 아니라 운동일로 거른다', () {
      final List<RoutineHistoryEntry> entries = <RoutineHistoryEntry>[
        // 지난 일요일 운동을 이번 주 목요일에 체크했다.
        _entry(
          '지난주-운동',
          _utcOfKst(DateTime(2026, 8, 20, 10)),
          date: DateTime(2026, 8, 16),
        ),
        _entry('오늘-운동', _utcOfKst(DateTime(2026, 8, 20, 10))),
      ];
      expect(
        _ids(historyInRange(entries, clientRangeFor(ClientPeriod.week, today))),
        <String>['오늘-운동'],
      );
      expect(
        _ids(
          historyInRange(entries, clientRangeFor(ClientPeriod.today, today)),
        ),
        <String>['오늘-운동'],
      );
    });

    test('주 경계 — 월요일 KST 08:00 완료는 이번 주다', () {
      final List<RoutineHistoryEntry> entries = <RoutineHistoryEntry>[
        _entry('월-0800', _utcOfKst(DateTime(2026, 8, 17, 8))),
      ];
      expect(
        _ids(historyInRange(entries, clientRangeFor(ClientPeriod.week, today))),
        <String>['월-0800'],
      );
    });
  });
}
