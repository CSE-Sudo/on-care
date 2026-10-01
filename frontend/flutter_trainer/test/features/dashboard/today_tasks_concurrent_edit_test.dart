/// 오늘 할 일 — 여러 탭·기기에서 동시에 체크해도 서로 지우지 않는다. (#2886)
///
/// 카드는 누른 키 하나만 보내고, 저장소가 돌려준 그날 기록(다른 기기의 체크
/// 포함)으로 화면을 바꾼다. 저장이 실패하면 그 키만 되돌리고 알린다. 다른
/// 탭에서 돌아오면(앱 재개) 기록을 다시 읽는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/dashboard/data/daily_task_progress_store.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// [kMidWeekKst] 기준 오늘.
const String _today = '2026-08-20';

/// 서버처럼 그날 기록을 들고 있는 저장소. [otherDevice] 로 다른 기기의 변경을
/// 흉내 내고, [failNext] 면 다음 요청을 실패시킨다.
class _SharedStore implements DailyTaskProgressStore {
  DailyTaskHistory history = const DailyTaskHistory();
  final List<TaskKeyChange> changes = <TaskKeyChange>[];
  bool failNext = false;
  int loads = 0;

  /// 다른 기기가 [key] 를 체크했다.
  void otherDevice(String key, Set<String> keys) {
    history = history.withDay(
      _today,
      applyTaskKeyChange(
        saved: history.read(_today),
        change: TaskKeyChange(
          key: key,
          action: TaskKeyAction.check,
          keys: keys,
          seen: keys,
        ),
      ),
    );
  }

  @override
  Future<DailyTaskHistory> load() async {
    loads += 1;
    return history;
  }

  @override
  Future<void> save(String date, DailyTaskSnapshot snapshot) =>
      throw StateError('화면은 그날 전체를 덮어쓰지 않는다');

  @override
  Future<DailyTaskSnapshot> applyKey(String date, TaskKeyChange change) async {
    changes.add(change);
    if (failNext) {
      failNext = false;
      throw const NetworkError();
    }
    final DailyTaskSnapshot next = applyTaskKeyChange(
      saved: history.read(date),
      change: change,
    );
    history = history.withDay(date, next);
    return next;
  }
}

void main() {
  final List<TrainerClient> clients = <TrainerClient>[
    makeClient(id: 'm1', name: '리포트 회원 1'),
    makeClient(id: 'm2', name: '리포트 회원 2'),
  ];
  const Set<String> reportKeys = <String>{'report-m1', 'report-m2'};

  Future<void> openDashboard(WidgetTester tester, _SharedStore store) async {
    useFixedKstDate();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.dashboard,
      extraOverrides: <Override>[
        dailyTaskProgressStoreProvider.overrideWithValue(store),
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(clients),
        ),
      ],
    );
    await settle(tester);
  }

  Finder toggle(String title) =>
      find.byKey(ValueKey<String>('dashboard-category-toggle-$title'));

  Future<void> expandReports(WidgetTester tester) async {
    if (find
        .byKey(const ValueKey<String>('dashboard-mission-report-m1'))
        .evaluate()
        .isNotEmpty) {
      return;
    }
    await tester.ensureVisible(toggle('리포트'));
    await tester.tap(toggle('리포트'));
    await settle(tester);
  }

  Finder checkboxOf(String key) => find.descendant(
    of: find.byKey(ValueKey<String>('dashboard-mission-$key')),
    matching: find.byType(Checkbox),
  );

  bool? checkedOf(WidgetTester tester, String key) =>
      tester.widget<Checkbox>(checkboxOf(key)).value;

  Future<void> tapCheckbox(WidgetTester tester, String key) async {
    await tester.ensureVisible(checkboxOf(key));
    await tester.tap(checkboxOf(key));
    await settle(tester);
  }

  testWidgets('다른 기기의 체크를 지우지 않고 응답으로 함께 보여 준다', (tester) async {
    final _SharedStore store = _SharedStore();
    await openDashboard(tester, store);
    await expandReports(tester);
    expect(checkedOf(tester, 'report-m1'), isFalse);

    // 이 화면을 연 뒤 다른 기기가 m1 을 체크했다.
    store.otherDevice('report-m1', reportKeys);
    await tapCheckbox(tester, 'report-m2');

    expect(store.changes.single.key, 'report-m2');
    expect(store.history.read(_today)?.completedKeys, reportKeys);
    expect(checkedOf(tester, 'report-m1'), isTrue);
    expect(checkedOf(tester, 'report-m2'), isTrue);
  });

  testWidgets('저장이 실패하면 그 체크만 되돌리고 알린다', (tester) async {
    final _SharedStore store = _SharedStore();
    await openDashboard(tester, store);
    await expandReports(tester);
    await tapCheckbox(tester, 'report-m1');
    expect(checkedOf(tester, 'report-m1'), isTrue);

    store.failNext = true;
    await tapCheckbox(tester, 'report-m2');

    expect(checkedOf(tester, 'report-m2'), isFalse);
    expect(checkedOf(tester, 'report-m1'), isTrue);
    expect(find.textContaining('할 일 상태를 저장하지 못했어요'), findsOneWidget);
    expect(store.history.read(_today)?.completedKeys, <String>{'report-m1'});
  });

  testWidgets('다른 탭에서 돌아오면 기록을 다시 읽어 다른 기기의 체크를 보여 준다', (tester) async {
    final _SharedStore store = _SharedStore();
    await openDashboard(tester, store);
    await expandReports(tester);
    final int loadsBefore = store.loads;

    store.otherDevice('report-m2', reportKeys);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(store.loads, greaterThan(loadsBefore));
    await expandReports(tester);
    expect(checkedOf(tester, 'report-m2'), isTrue);
    expect(checkedOf(tester, 'report-m1'), isFalse);
  });
}
