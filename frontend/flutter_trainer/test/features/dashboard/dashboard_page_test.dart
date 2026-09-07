import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/attention_card.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/stat_card.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// The 대시보드 against the seeded roster.
///
/// Seed: 3 clients (김민수 3428mg and 박성호 2400mg are over the 2000mg
/// target, 이지수 1800mg is not; 이지수 is 휴면), all three have unread
/// replies (4 in total), and today has 4 booked sessions (6 slots − 2
/// gaps).
void main() {
  Future<void> openDashboard(
    WidgetTester tester, {
    List<Override> extraOverrides = const <Override>[],
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.dashboard,
      extraOverrides: extraOverrides,
    );
  }

  /// The location the router is currently showing.
  String currentLocation(WidgetTester tester) {
    final ctx = tester.element(find.byType(Navigator).first);
    return GoRouter.of(ctx).routerDelegate.currentConfiguration.uri.toString();
  }

  /// 오늘 할 일은 상담·건강 신호·프로그램 미등록·리포트 대상을 한 리스트로
  /// 섞어 보여준다 — 행 key(`dashboard-mission-<prefix>-...`) 접두사로 찾는다.
  Finder findMissionRow(String prefix) => find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('dashboard-mission-$prefix-');
  });

  /// 오늘 할 일은 카테고리별 아코디언이다 — 기본은 접혀 있어, 그 안의 미션
  /// 행을 보거나 누르기 전에 헤더를 한 번 펼쳐야 한다.
  Future<void> expandTaskCategory(WidgetTester tester, String title) async {
    final toggle = find.byKey(
      ValueKey<String>('dashboard-category-toggle-$title'),
    );
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }

  /// 주의 회원 검증이 쓰는 고정 로스터. (#907)
  ///
  /// 건강 신호 여덟(나트륨 5 · 당류 1 · 이행률 2)과 답장 대기 둘. 기대값을
  /// 데이터 바로 옆에 두어, 숫자가 어디서 왔는지 읽는 사람이 세어 볼 수 있게 한다.
  ///
  /// 이행률 경고는 `weekCompletion` 을 직접 준다 — 시드처럼 오늘 요일에 따라
  /// 잘리는 값을 쓰면 판정이 요일을 탄다.
  List<Override> attentionRosterOverrides() {
    const List<int> lowWeek = <int>[40, 40, 0, 0, 0, 0, 0];
    final List<TrainerClient> roster = <TrainerClient>[
      for (var i = 0; i < 5; i++)
        makeClient(id: 'sodium-$i', name: '나트륨 회원 $i', sodiumMg: 2500),
      makeClient(id: 'sugar-0', name: '당류 회원', sugarG: 80),
      for (var i = 0; i < 2; i++)
        makeClient(
          id: 'completion-$i',
          name: '이행률 회원 $i',
          weekCompletion: lowWeek,
        ),
      makeClient(id: 'reply-0', name: '답장 회원 0'),
      makeClient(id: 'reply-1', name: '답장 회원 1'),
    ];
    return <Override>[
      clientsProvider.overrideWith(
        (ref) => Stream<List<TrainerClient>>.value(roster),
      ),
      unreadCountsProvider.overrideWith(
        (ref) => Stream<Map<String, int>>.value(const <String, int>{
          'reply-0': 1,
          'reply-1': 2,
        }),
      ),
    ];
  }

  testWidgets('is the landing page after a restored session', (tester) async {
    await openDashboard(tester);
    expect(find.text('대시보드'), findsWidgets);
  });

  testWidgets('a failed summary retries once and renders fresh data', (
    tester,
  ) async {
    final retryGate = Completer<List<TrainerClient>>();
    int attempts = 0;
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.dashboard,
      extraOverrides: <Override>[
        clientsProvider.overrideWith((ref) {
          attempts++;
          if (attempts == 1) {
            return Stream<List<TrainerClient>>.error(
              StateError('internal transport detail'),
            );
          }
          return Stream<List<TrainerClient>>.fromFuture(retryGate.future);
        }),
      ],
    );

    expect(find.text('대시보드를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('internal transport detail'), findsNothing);

    final retry = find.byKey(const ValueKey<String>('dashboard-retry'));
    await tester.tap(retry);
    await tester.pump();
    await tester.tap(retry, warnIfMissed: false);
    await tester.pump();
    expect(attempts, 2, reason: '재시도 중 중복 요청이 시작됐어요');

    retryGate.complete(<TrainerClient>[
      makeClient(name: '복구 회원', sodiumMg: 2500),
    ]);
    await settle(tester);

    // 복구된 회원의 이름은 오늘 할 일 리스트를 스크롤해야 보인다 — 새로
    // 고쳐 그렸다는 사실은 KPI 로 확인한다.
    final myClients = tester.widget<StatCard>(
      find.ancestor(of: find.text('담당 회원'), matching: find.byType(StatCard)),
    );
    expect(myClients.value, '1');
    expect(find.text('대시보드를 불러오지 못했어요'), findsNothing);
  });

  testWidgets('the KPI row reports the seeded numbers', (tester) async {
    await openDashboard(tester);

    expect(find.text('담당 회원'), findsOneWidget);
    // '메시지' 는 사이드바 내비게이션 항목명과도 겹친다 — KPI 카드 안에서만 찾는다.
    expect(
      find.descendant(of: find.byType(StatCard), matching: find.text('메시지')),
      findsOneWidget,
    );
    expect(find.text('주의 회원'), findsOneWidget);
    expect(find.text('이탈 위험'), findsOneWidget);

    // 13 of the 15 seeded clients are active; 박성호 and 문가영 are the
    // two 휴면 fixtures. 답장 대기는 **회원이 마지막으로 말한** 스레드다 —
    // 시드에서는 넷(오세라 · 배준혁 · 문가영 · 노태강)이 그렇다.
    expect(find.text('휴면 2명'), findsOneWidget);
    expect(find.text('회원 4명 대기 중'), findsOneWidget);
  });

  testWidgets('주의 회원 counts health signals, not the reply backlog', (
    tester,
  ) async {
    // 로스터를 이 테스트가 직접 만든다(#907). 데모 시드는 주간 이행률을 **오늘
    // 요일까지만** 채우므로(`_upToToday`), 기록이 있는 날의 평균으로 판정하는
    // 이행률 경고가 요일마다 붙었다 떨어졌다 한다 — 시드에 기대면 이 숫자가
    // 수요일에 하나 늘고 화요일에 하나 줄어, 어느 요일에 CI 가 도느냐로
    // 통과·실패가 갈렸다.
    await openDashboard(tester, extraOverrides: attentionRosterOverrides());

    // 답장을 기다리는 스레드가 둘이지만 주의는 건강 신호만 센다 — 나트륨 5 ·
    // 당류 1 · 이행률 2 로 여덟이다. 답장 대기는 목록에는 남되 주의가 아니다.
    // 둘이 다시 합쳐지면 이 카드가 더 큰 수를 말하며 뜻을 잃는다.
    final attention = tester.widget<StatCard>(
      find.ancestor(of: find.text('주의 회원'), matching: find.byType(StatCard)),
    );
    expect(attention.value, '8');
    expect(find.text('식단·이행률 확인'), findsOneWidget);
  });

  testWidgets('a KPI deep-links into the pre-filtered roster', (tester) async {
    await openDashboard(tester);

    await tester.tap(
      find.descendant(of: find.byType(StatCard), matching: find.text('메시지')),
    );
    await settle(tester);
    // The number and the list it opens have to be the same claim.
    expect(currentLocation(tester), contains('f=unread'));
  });

  testWidgets('오늘의 일정 lists today’s sessions and their status', (tester) async {
    await openDashboard(tester);

    expect(find.text('오늘의 일정'), findsOneWidget);
    // ClientIdentity 가 이름과 성별·나이(회색)를 별도 Text 로 그린다.
    expect(find.text('김민수'), findsWidgets);
    expect(find.text('남성 · 35세'), findsWidgets);
    expect(find.text('1:1 PT'), findsWidgets);
    expect(find.text('완료'), findsWidgets);
    // 스케줄 화면과 같은 시작–종료 범위를 쓰며, 각 일정의 실제 소요
    // 시간이 끝 시각에 반영된다.
    expect(find.text('18:00–18:50'), findsOneWidget);
    expect(find.text('12:00–12:50'), findsOneWidget);
    expect(find.text('16:00–16:45'), findsOneWidget);
    expect(find.text('17:00–18:00'), findsWidgets);
    // 빈 시간(공백 슬롯)은 이제 아예 그리지 않는다 — 예약된 것만 보여준다.
    expect(find.textContaining('빈 시간'), findsNothing);
  });

  testWidgets('오늘의 일정 행은 자신이 가리키는 세션을 선택해 연다', (tester) async {
    await openDashboard(tester);

    final rows = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'dashboard-schedule-',
          ),
    );
    expect(rows, findsWidgets);
    final target = rows.at(1);
    final targetKey = tester.widget(target).key! as ValueKey<String>;
    final sessionId = targetKey.value.substring('dashboard-schedule-'.length);

    await tester.ensureVisible(target);
    await tester.tap(target);
    await settle(tester);

    expect(currentLocation(tester), contains('session=$sessionId'));
    expect(
      find.byKey(ValueKey<String>('schedule-session-$sessionId')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ScheduleWeekTimetable>(find.byType(ScheduleWeekTimetable))
          .selectedSessionId,
      sessionId,
    );
  });

  testWidgets('오늘 할 일은 건강 신호가 있는 회원을 미션으로 보여주고 그 섹션으로 연결한다', (tester) async {
    await openDashboard(tester, extraOverrides: attentionRosterOverrides());
    await expandTaskCategory(tester, '식단');

    // 건강 신호 여덟(나트륨 5 · 당류 1 · 이행률 2) 전부가 미션이 된다.
    // 답장 대기 둘은 건강 신호가 아니라서 오늘 할 일에 없다(#907).
    expect(findMissionRow('feedback-sodiumOver'), findsNWidgets(5));
    expect(find.text('답장 대기'), findsNothing);

    final mission = findMissionRow('feedback-sodiumOver').first;
    await tester.ensureVisible(mission);
    await tester.tap(mission);
    await settle(tester);
    expect(currentLocation(tester), contains('/diet'));
  });

  testWidgets('활동 피드백 spells out the three activity-feedback signals', (
    tester,
  ) async {
    await openDashboard(tester);

    expect(find.text('활동 피드백'), findsOneWidget);
    expect(find.text('이행률 저조·이탈 위험 감지'), findsOneWidget);
    expect(find.text('7일 이상 활동 저조'), findsOneWidget);
    expect(find.text('식단 피드백 미완료'), findsOneWidget);
    expect(find.textContaining('난이도를 낮추고'), findsOneWidget);
  });

  for (final scenario in <({String kind, String route})>[
    (kind: 'difficultyReview', route: '/coaching'),
    (kind: 'inactiveSevenDays', route: '/messages'),
    (kind: 'dietFeedbackPending', route: '/diet'),
  ]) {
    testWidgets('활동 피드백의 ${scenario.kind} 버튼이 그 활동에 맞는 화면으로 이동한다', (
      tester,
    ) async {
      await openDashboard(tester);

      final button = find.byKey(
        ValueKey<String>('ai-summary-cta-${scenario.kind}'),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await settle(tester);
      expect(currentLocation(tester), contains(scenario.route));
    });
  }

  testWidgets('the dashboard renders derived tasks without fake completion', (
    tester,
  ) async {
    await openDashboard(tester);

    expect(find.text('오늘 할 일'), findsOneWidget);
    expect(find.textContaining('확인 필요'), findsWidgets);
    expect(find.textContaining('/ 5 완료'), findsNothing);
  });

  testWidgets('wide dashboard follows the 4-KPI + 2-column body layout', (
    tester,
  ) async {
    await openDashboard(tester);

    expect(find.byType(StatCard), findsNWidgets(4));
    final actionRow = tester.widget<Row>(
      find.byKey(const ValueKey<String>('dashboard-action-row')),
    );
    expect(actionRow.children.whereType<Expanded>(), hasLength(2));
    expect(find.text('활동 피드백'), findsOneWidget);
  });

  testWidgets('오늘 할 일은 각 미션에 맞는 회원만 보여준다', (tester) async {
    final feedbackClient = makeClient(
      id: 'feedback-client',
      name: '식단 회원',
      sodiumMg: 2500,
    );
    final programClient = makeClient(
      id: 'program-client',
      name: '운동 회원',
      lastRoutine: '-',
    );
    await openDashboard(
      tester,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            feedbackClient,
            programClient,
          ]),
        ),
        unreadCountsProvider.overrideWith(
          (ref) => Stream<Map<String, int>>.value(const <String, int>{}),
        ),
      ],
    );
    await expandTaskCategory(tester, '식단');
    await expandTaskCategory(tester, '프로그램');

    expect(
      find.descendant(
        of: findMissionRow('feedback'),
        matching: find.textContaining('식단 회원'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: findMissionRow('program'),
        matching: find.textContaining('운동 회원'),
      ),
      findsOneWidget,
    );
    // 운동 회원은 프로그램 미등록 미션에만 있고, 식단 미션에는 없다.
    expect(
      find.descendant(
        of: findMissionRow('feedback'),
        matching: find.textContaining('운동 회원'),
      ),
      findsNothing,
    );
  });

  for (final scenario in <({String prefix, String category, String route})>[
    (prefix: 'feedback-sodiumOver', category: '식단', route: '/diet'),
    (prefix: 'program', category: '프로그램', route: '/coaching'),
    (prefix: 'report', category: '리포트', route: '/reports'),
  ]) {
    testWidgets('${scenario.prefix} 미션을 누르면 해당 화면으로 이동한다', (tester) async {
      final client = makeClient(
        id: 'nav-client',
        name: '이동 회원',
        sodiumMg: 2500,
        lastRoutine: '-',
      );
      await openDashboard(
        tester,
        extraOverrides: <Override>[
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[client]),
          ),
          unreadCountsProvider.overrideWith(
            (ref) => Stream<Map<String, int>>.value(const <String, int>{}),
          ),
        ],
      );
      await expandTaskCategory(tester, scenario.category);

      final mission = findMissionRow(scenario.prefix);
      await tester.ensureVisible(mission);
      await tester.tap(mission);
      await settle(tester);

      expect(currentLocation(tester), contains(scenario.route));
    });
  }

  testWidgets('상담 요청 미션을 누르면 대시보드 위에 상담 모달을 띄운다', (tester) async {
    await openDashboard(tester);
    await expandTaskCategory(tester, '상담');

    final mission = findMissionRow('consultation').first;
    await tester.ensureVisible(mission);
    await tester.tap(mission);
    await settle(tester);

    expect(currentLocation(tester), AppRoutes.dashboard);
    expect(
      find.byKey(const ValueKey<String>('consultations-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('consultations-back-to-schedule')),
      findsNothing,
    );
  });

  group('AttentionCard.sectionFor', () {
    test('each alert opens the sub-tab that actually addresses it', () {
      // The row is a shortcut to the fix, not just to the client.
      expect(AttentionCard.sectionFor(ClientAlert.unanswered), 'chat');
      expect(AttentionCard.sectionFor(ClientAlert.sodiumOver), 'diet');
      expect(AttentionCard.sectionFor(ClientAlert.lowCompletion), 'workout');
    });

    test('every alert has a destination', () {
      for (final alert in ClientAlert.values) {
        expect(
          AppRoutes.clientSections,
          contains(AttentionCard.sectionFor(alert)),
          reason: '${alert.label}의 이동 대상이 없는 섹션이에요',
        );
      }
    });
  });
}
