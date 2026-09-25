import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';

RoutineHistoryEntry _entry(String id, DateTime? completedAt) =>
    RoutineHistoryEntry(
      id: id,
      dateLabel: id,
      label: 'PT 세션 · 트레이너 지도',
      completionRate: 100,
      exercises: <ClientExerciseItem>[],
      clientFeedback: '',
      trainerNote: '',
      completedAt: completedAt,
    );

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
}
