/// 오늘 할 일 — 미션 원천이 늦게 와도 저장된 체크를 잃지 않는다. (#2763)
///
/// 상담 미션은 상담 목록을 따로 읽어 만든다. 이력이 상담 목록보다 먼저 오면
/// 그 순간 화면에 없는 상담 키의 체크·이월이 버려졌고, 그 상태로 아무 항목이나
/// 체크하면 그날 전체를 덮어써 서버의 상담 체크까지 사라졌다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/consultations/domain/entities/consultation_request.dart';
import 'package:oncare_trainer/features/dashboard/data/daily_task_progress_store.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/today_tasks_card.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// [kMidWeekKst] 기준 오늘·어제.
const String _today = '2026-08-20';
const String _yesterday = '2026-08-19';

ConsultationRequest _request(String id, String name) => ConsultationRequest(
  id: id,
  memberId: 'user-$id',
  memberName: name,
  goalCode: 'weight_loss',
  purposeCode: 'chronic',
  preferredDate: DateTime(2026, 8, 25),
  preferredTimeCode: 'evening',
  status: 'pending',
);

/// 상담 목록 읽기를 붙잡아 둘 수 있는 페이크 — 이력보다 늦게 오는 응답.
class _SlowConsultations implements ConsultationRepository {
  _SlowConsultations(this.requests);

  final List<ConsultationRequest> requests;

  /// 대시보드 카드가 기다리는 읽기 — 화면에 들어올 때마다 새로 붙잡힌다.
  final List<Completer<List<ConsultationRequest>>> _waiting =
      <Completer<List<ConsultationRequest>>>[];

  /// 붙잡아 둔 읽기를 모두 [requests] 로 답한다.
  void release() {
    for (final Completer<List<ConsultationRequest>> c in _waiting) {
      if (!c.isCompleted) c.complete(requests);
    }
  }

  /// 붙잡아 둔 읽기를 모두 실패시킨다.
  void fail() {
    for (final Completer<List<ConsultationRequest>> c in _waiting) {
      if (!c.isCompleted) c.completeError(StateError('consultations failed'));
    }
  }

  @override
  bool get supportsInbox => true;

  @override
  Future<List<ConsultationRequest>> fetch({
    String status = 'pending',
    int limit = consultationPageSize,
    DateTime? before,
    String? beforeId,
  }) {
    final Completer<List<ConsultationRequest>> c =
        Completer<List<ConsultationRequest>>();
    _waiting.add(c);
    return c.future;
  }

  @override
  Stream<List<ConsultationRequest>> watch({
    String status = 'pending',
    int limit = consultationPageSize,
  }) => Stream<List<ConsultationRequest>>.value(requests);

  @override
  Future<int> pendingCount() async => requests.length;

  @override
  Stream<int> watchPendingCount() => Stream<int>.value(requests.length);

  @override
  Future<ConsultationAcceptResult> accept(String id) =>
      throw UnimplementedError();

  @override
  Future<void> reject(String id, {String? note}) => throw UnimplementedError();
}

/// 저장 요청을 기록하는 이력 저장소.
class _RecordingStore implements DailyTaskProgressStore {
  _RecordingStore(this.history);

  final DailyTaskHistory history;
  final List<DailyTaskSnapshot> saves = <DailyTaskSnapshot>[];

  @override
  Future<DailyTaskHistory> load() async => history;

  @override
  Future<void> save(String date, DailyTaskSnapshot snapshot) async {
    expect(date, _today);
    saves.add(snapshot);
  }
}

void main() {
  final TrainerClient client = makeClient(id: 'm1', name: '리포트 회원');

  /// 다른 기기에서 오늘 상담 c1 을 체크해 두었고, 어제는 상담 c2 를 끝내지
  /// 못했다.
  DailyTaskHistory savedHistory() => const DailyTaskHistory(
    days: <String, DailyTaskSnapshot>{
      _today: DailyTaskSnapshot(
        total: 3,
        completedToday: 1,
        completedCarriedOver: 0,
        pendingKeys: <String>{'consultation-c2', 'report-m1'},
        completedKeys: <String>{'consultation-c1'},
      ),
      _yesterday: DailyTaskSnapshot(
        total: 1,
        completedToday: 0,
        completedCarriedOver: 0,
        pendingKeys: <String>{'consultation-c2'},
        completedKeys: <String>{},
      ),
    },
    firstSavedDate: _yesterday,
  );

  Future<void> openDashboard(
    WidgetTester tester, {
    required ConsultationRepository consultations,
    required DailyTaskProgressStore store,
  }) async {
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
        consultationRepositoryProvider.overrideWithValue(consultations),
        dailyTaskProgressStoreProvider.overrideWithValue(store),
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[client]),
        ),
      ],
    );
    await settle(tester);
  }

  Finder toggle(String title) =>
      find.byKey(ValueKey<String>('dashboard-category-toggle-$title'));

  Future<void> expand(WidgetTester tester, String title) async {
    await tester.ensureVisible(toggle(title));
    await tester.tap(toggle(title));
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

  testWidgets('상담 목록이 이력보다 늦게 와도 상담 체크와 이월이 살아 있다', (tester) async {
    final _SlowConsultations consultations = _SlowConsultations(
      <ConsultationRequest>[
        _request('c1', '상담 회원 1'),
        _request('c2', '상담 회원 2'),
      ],
    );
    final _RecordingStore store = _RecordingStore(savedHistory());
    await openDashboard(tester, consultations: consultations, store: store);

    // 상담 목록이 오기 전에는 체크를 받지 않는다 — 받으면 상담 체크가 빠진
    // 상태로 그날을 덮어쓴다.
    await expand(tester, '리포트');
    await tapCheckbox(tester, 'report-m1');
    expect(store.saves, isEmpty);
    expect(checkedOf(tester, 'report-m1'), isFalse);

    consultations.release();
    await settle(tester);

    await expand(tester, '상담');
    expect(checkedOf(tester, 'consultation-c1'), isTrue);
    // 어제 끝내지 못한 상담은 자기 카테고리가 아니라 `지난 할 일` 로 넘어온다.
    expect(toggle('지난 할 일'), findsOneWidget);
    await expand(tester, '지난 할 일');
    expect(checkedOf(tester, 'consultation-c2'), isFalse);

    // 이제 다른 항목을 체크해도 상담 체크는 저장에 남는다.
    await tapCheckbox(tester, 'report-m1');
    expect(store.saves, hasLength(1));
    final DailyTaskSnapshot saved = store.saves.single;
    expect(saved.completedKeys, <String>{'consultation-c1', 'report-m1'});
    expect(saved.pendingKeys, contains('consultation-c2'));
    // 진행률 그래프의 오늘 완료 수가 줄지 않는다(전에 1 → 이제 2).
    expect(saved.completed, 2);
  });

  testWidgets('상담 목록을 못 읽어도 저장된 상담 체크를 덮어쓰지 않는다', (tester) async {
    final _SlowConsultations consultations = _SlowConsultations(
      const <ConsultationRequest>[],
    );
    final _RecordingStore store = _RecordingStore(savedHistory());
    await openDashboard(tester, consultations: consultations, store: store);

    consultations.fail();
    await settle(tester);

    await expand(tester, '리포트');
    await tapCheckbox(tester, 'report-m1');

    expect(store.saves, hasLength(1));
    final DailyTaskSnapshot saved = store.saves.single;
    // 화면이 모르는 상담 미션의 저장 상태는 그대로 옮긴다.
    expect(saved.completedKeys, containsAll(<String>['consultation-c1']));
    expect(saved.pendingKeys, contains('consultation-c2'));
    expect(saved.completed, 2);
    expect(saved.total, 3);
  });

  testWidgets('다른 탭에 다녀와도 체크한 상담이 그대로다', (tester) async {
    final _SlowConsultations consultations = _SlowConsultations(
      <ConsultationRequest>[_request('c1', '상담 회원 1')],
    );
    final _RecordingStore store = _RecordingStore(savedHistory());
    await openDashboard(tester, consultations: consultations, store: store);
    consultations.release();
    await settle(tester);
    await expand(tester, '상담');
    expect(checkedOf(tester, 'consultation-c1'), isTrue);

    // 다른 탭에 갔다 돌아온다 — 이력은 다시 읽히고, 상담 목록은 또 늦게 온다.
    final BuildContext ctx = tester.element(find.byType(Navigator).first);
    GoRouter.of(ctx).go(AppRoutes.clients);
    await settle(tester);
    expect(find.byType(TodayTasksCard), findsNothing);
    GoRouter.of(ctx).go(AppRoutes.dashboard);
    await settle(tester);
    consultations.release();
    await settle(tester);

    // 펼침 상태는 탭을 오가도 남아 있을 수 있다 — 접혀 있을 때만 편다.
    if (checkboxOf('consultation-c1').evaluate().isEmpty) {
      await expand(tester, '상담');
    }
    expect(checkedOf(tester, 'consultation-c1'), isTrue);

    if (checkboxOf('report-m1').evaluate().isEmpty) {
      await expand(tester, '리포트');
    }
    await tapCheckbox(tester, 'report-m1');
    expect(store.saves.last.completedKeys, <String>{
      'consultation-c1',
      'report-m1',
    });
  });
}
