/// 데모·새 계정의 지난 할 일 이력. (#1203)
///
/// 실제 기록이 없을 때만, 그것도 **지난 날들만** 채운다. 오늘의 실제 목록과
/// 섞이면 방금 들어온 항목이 `어제부터 밀린 일` 로 분류된다(#1147).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/dashboard/data/daily_task_progress_store.dart';
import 'package:oncare_trainer/features/dashboard/data/demo_task_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final DateTime today = DateTime(2026, 8, 20); // 목요일
  DateTime daysBefore(int n) => today.subtract(Duration(days: n));

  test('오늘과 앞날은 지어내지 않는다', () {
    final DemoTaskHistory demo = DemoTaskHistory(today: DateTime(2026, 8, 20));

    expect(demo.snapshotFor(today), isNull);
    expect(demo.snapshotFor(today.add(const Duration(days: 1))), isNull);
    expect(demo.snapshotFor(daysBefore(1)), isNotNull);
  });

  test('어제 요약만 미완료 한 건을 남긴다 — 그 한 건이 오늘의 지난 할 일이다', () {
    final DemoTaskHistory demo = DemoTaskHistory(today: DateTime(2026, 8, 20));

    final DailyTaskSnapshot yesterday = demo.snapshotFor(daysBefore(1))!;
    expect(yesterday.pendingKeys, <String>{DemoTaskHistory.kDemoCarryOverKey});
    expect(yesterday.total - yesterday.completed, 1);
    expect(demo.snapshotFor(daysBefore(2))!.pendingKeys, isEmpty);
  });

  test('데모 이월 키는 실제 미션 키와 겹칠 수 없다', () {
    // 실제 키는 `consultation-`·`feedback-`·`program-`·`report-` 로 시작한다
    // (today_tasks_card 의 _buildMissions).
    for (final String prefix in <String>[
      'consultation-',
      'feedback-',
      'program-',
      'report-',
    ]) {
      expect(DemoTaskHistory.kDemoCarryOverKey.startsWith(prefix), isFalse);
    }
  });

  test('덮는 기간 밖은 비워 둔다', () {
    final DemoTaskHistory demo = DemoTaskHistory(today: DateTime(2026, 8, 20));

    expect(demo.snapshotFor(daysBefore(DemoTaskHistory.windowDays)), isNotNull);
    expect(
      demo.snapshotFor(daysBefore(DemoTaskHistory.windowDays + 1)),
      isNull,
    );
  });

  test('실제 기록이 시작된 날부터는 물러난다', () {
    final DemoTaskHistory demo = DemoTaskHistory(
      today: DateTime(2026, 8, 20),
      firstSavedDate: '2026-08-18',
    );

    expect(demo.snapshotFor(DateTime(2026, 8, 17)), isNotNull);
    expect(demo.snapshotFor(DateTime(2026, 8, 18)), isNull);
    // 그 뒤로는 저장된 날이 없어도 지어내지 않는다 — 쓰기 시작한 계정의
    // 기록에 데모가 덧그려지면 어느 쪽이 진짜인지 알 수 없다.
    expect(demo.snapshotFor(DateTime(2026, 8, 19)), isNull);
  });

  test('막대는 날짜에서 정해진다 — 다시 그려도 흔들리지 않고 합이 맞는다', () {
    final DemoTaskHistory demo = DemoTaskHistory(today: DateTime(2026, 8, 20));

    for (int i = 1; i <= DemoTaskHistory.windowDays; i++) {
      final DailyTaskSnapshot first = demo.snapshotFor(daysBefore(i))!;
      final DailyTaskSnapshot again = demo.snapshotFor(daysBefore(i))!;
      expect(first.total, again.total);
      expect(first.completed, again.completed);
      expect(first.completed, lessThanOrEqualTo(first.total));
      expect(first.total, greaterThan(0));
    }
  });

  test('가장 이른 저장일이 데모의 경계다', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final LocalDailyTaskProgressStore store = LocalDailyTaskProgressStore(
      prefs,
    );

    expect((await store.load()).firstSavedDate, isNull);

    const DailyTaskSnapshot snapshot = DailyTaskSnapshot(
      total: 3,
      completedToday: 1,
      completedCarriedOver: 0,
      pendingKeys: <String>{'report-c1'},
      dismissedKeys: <String>{'program-c2'},
    );
    await store.save('2026-08-19', snapshot);
    await store.save('2026-08-17', snapshot);
    await store.save('2026-08-20', snapshot);

    final DailyTaskHistory history = await store.load();
    expect(history.firstSavedDate, '2026-08-17');
    // 삭제한 항목도 함께 남는다(#1633).
    expect(history.read('2026-08-20')!.dismissedKeys, <String>{'program-c2'});
  });
}
