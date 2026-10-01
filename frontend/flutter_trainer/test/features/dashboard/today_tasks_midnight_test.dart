/// 오늘 할 일 — 자정을 넘긴 뒤의 첫 체크·삭제. (#2866)
///
/// 대시보드를 켜 둔 채 자정을 넘기면 카드는 어제 상태를 들고 있었다. 그때 처음
/// 누른 체크가 어제 체크 전체를 오늘 완료로 저장했다. 이제 화면을 연 날과
/// 오늘이 다르면 그 탭은 받지 않고 오늘 기준으로 다시 그린 뒤 알린다. 저장은
/// 화면을 연 날에만 한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/dashboard/data/daily_task_progress_store.dart';
import 'package:oncare_trainer/features/dashboard/data/demo_task_history.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

const String _yesterday = '2026-08-20';
const String _today = '2026-08-21';

final DateTime _beforeMidnight = DateTime(2026, 8, 20, 23, 58);
final DateTime _afterMidnight = DateTime(2026, 8, 21, 0, 1);

/// 그날 기록을 들고 있는 저장소. 받은 변경을 날짜와 함께 남긴다.
class _DayStore implements DailyTaskProgressStore {
  DailyTaskHistory history = const DailyTaskHistory();
  final List<(String, TaskKeyChange)> changes = <(String, TaskKeyChange)>[];

  @override
  Future<DailyTaskHistory> load() async => history;

  @override
  Future<void> save(String date, DailyTaskSnapshot snapshot) =>
      throw StateError('화면은 그날 전체를 덮어쓰지 않는다');

  @override
  Future<DailyTaskSnapshot> applyKey(String date, TaskKeyChange change) async {
    changes.add((date, change));
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

  late StreamController<DateTime> clock;
  late DateTime now;

  setUp(() {
    clock = StreamController<DateTime>.broadcast();
    now = _beforeMidnight;
    debugNowKstOverride = () => now;
    addTearDown(() => debugNowKstOverride = null);
    addTearDown(clock.close);
  });

  Future<void> openDashboard(WidgetTester tester, _DayStore store) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.dashboard,
      kstClock: clock.stream,
      extraOverrides: <Override>[
        dailyTaskProgressStoreProvider.overrideWithValue(store),
        // 목업 모드의 데모 이월 항목(#1203)은 실제 이력이 시작되기 전 날짜를
        // 지어 채운다. 그대로 두면 자정 전에도 `지난 할 일` 이 데모 한 건으로
        // 서, 자정을 넘겨 생기는 실제 이월(어제 못 한 m2)과 구분되지 않는다.
        demoTaskHistoryProvider.overrideWith((ref) => null),
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(clients),
        ),
      ],
    );
    await settle(tester);
  }

  Finder toggle(String title) =>
      find.byKey(ValueKey<String>('dashboard-category-toggle-$title'));

  Finder missionOf(String key) =>
      find.byKey(ValueKey<String>('dashboard-mission-$key'));

  Future<void> expand(WidgetTester tester, String title) async {
    await tester.ensureVisible(toggle(title));
    await tester.tap(toggle(title));
    await settle(tester);
  }

  Finder checkboxOf(String key) =>
      find.descendant(of: missionOf(key), matching: find.byType(Checkbox));

  bool? checkedOf(WidgetTester tester, String key) =>
      tester.widget<Checkbox>(checkboxOf(key)).value;

  Future<void> tapCheckbox(WidgetTester tester, String key) async {
    await tester.ensureVisible(checkboxOf(key));
    await tester.tap(checkboxOf(key));
    await settle(tester);
  }

  /// 어제 밤 m1 만 체크해 둔 대시보드.
  Future<_DayStore> checkedLastNight(WidgetTester tester) async {
    final _DayStore store = _DayStore();
    await openDashboard(tester, store);
    clock.add(_beforeMidnight);
    await settle(tester);
    await expand(tester, '리포트');
    await tapCheckbox(tester, 'report-m1');
    expect(store.changes.single.$1, _yesterday);
    return store;
  }

  testWidgets('자정 뒤 첫 체크는 받지 않고 오늘 기준으로 다시 불러온다', (tester) async {
    final _DayStore store = await checkedLastNight(tester);

    // 시계가 아직 다시 그리기 전에 자정을 넘겨 m2 를 누른다.
    now = _afterMidnight;
    await tapCheckbox(tester, 'report-m2');

    expect(store.changes, hasLength(1), reason: '어제 목록을 보고 누른 탭은 보내지 않는다');
    expect(store.history.read(_today), isNull);
    expect(find.textContaining('날짜가 바뀌어 오늘 할 일로 새로 불러왔어요'), findsOneWidget);

    // 어제 체크한 m1 은 오늘 체크로 넘어오지 않는다. 어제 못 한 m2 는
    // `지난 할 일` 로 넘어온다.
    if (checkboxOf('report-m1').evaluate().isEmpty) {
      await expand(tester, '리포트');
    }
    expect(checkedOf(tester, 'report-m1'), isFalse);
    if (checkboxOf('report-m2').evaluate().isEmpty) {
      await expand(tester, '지난 할 일');
    }
    expect(checkedOf(tester, 'report-m2'), isFalse);

    // 다시 누르면 오늘 날짜에 그 키만 저장된다.
    await tapCheckbox(tester, 'report-m2');
    expect(store.changes.last.$1, _today);
    expect(store.changes.last.$2.key, 'report-m2');
    final DailyTaskSnapshot saved = store.history.read(_today)!;
    expect(saved.completedKeys, <String>{'report-m2'});
    expect(saved.completedCarriedOver, 1);
    expect(saved.completedToday, 0);
    // 어제 기록은 그대로다.
    expect(store.history.read(_yesterday)?.completedKeys, <String>{
      'report-m1',
    });
  });

  testWidgets('자정이 되면 누르지 않아도 오늘 기준으로 다시 그린다', (tester) async {
    await checkedLastNight(tester);
    expect(checkedOf(tester, 'report-m1'), isTrue);
    expect(toggle('지난 할 일'), findsNothing);

    now = _afterMidnight;
    clock.add(_afterMidnight);
    await settle(tester);

    expect(toggle('지난 할 일'), findsOneWidget);
    if (checkboxOf('report-m1').evaluate().isEmpty) {
      await expand(tester, '리포트');
    }
    expect(checkedOf(tester, 'report-m1'), isFalse);
    expect(find.textContaining('날짜가 바뀌어'), findsNothing);
  });

  testWidgets('자정 뒤 첫 삭제도 받지 않는다', (tester) async {
    final _DayStore store = await checkedLastNight(tester);

    now = _afterMidnight;
    final Finder delete = find.descendant(
      of: missionOf('report-m2'),
      matching: find.byTooltip('삭제'),
    );
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await settle(tester);

    // 확인창도 띄우지 않고 알린다.
    expect(find.text('이 항목을 삭제할까요?'), findsNothing);
    expect(find.textContaining('날짜가 바뀌어 오늘 할 일로 새로 불러왔어요'), findsOneWidget);
    expect(store.changes, hasLength(1));
    expect(store.history.read(_today), isNull);
  });
}
