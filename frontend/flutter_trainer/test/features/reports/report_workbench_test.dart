/// 리포트 탭의 작업대·단계 편집기·보낸 리포트 (#2232).
///
/// 리포트 탭은 회원 하나를 골라 그 주를 읽는 화면이 아니라, 이번 주 여러 장을
/// 내보내는 라인이다. 그래서 이 파일이 보는 것은 그래프의 내용이 아니라
/// **일의 흐름** 이다 — 누가 남았나, 어디까지 왔나, 보낸 건 무엇이었나.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/sent_report_view.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 이름순·주의순이 서로 다른 차례가 되도록 짠 로스터.
///
/// `하회원` 은 이름으로는 맨 뒤지만 이행률이 바닥이라 주의순에서는 맨 앞이다.
final List<TrainerClient> _roster = <TrainerClient>[
  makeClient(
    id: 'a',
    name: '가회원',
    weekCompletion: const <int>[100, 100, 100, 100, 100, 100, 100],
  ),
  makeClient(
    id: 'h',
    name: '하회원',
    goal: '근력 향상',
    weekCompletion: const <int>[10, 0, 0, 10, 0, 0, 0],
  ),
];

void main() {
  Future<ProviderContainer> openWorkbench(
    WidgetTester tester, {
    Size size = const Size(1600, 1200),
    List<TrainerClient> clients = const <TrainerClient>[],
    String at = AppRoutes.reports,
    Locale locale = const Locale('ko'),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProviderContainer container = await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: at,
      locale: locale,
      extraOverrides: <Override>[
        if (clients.isNotEmpty)
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(clients),
          ),
      ],
    );
    await settle(tester);
    return container;
  }

  /// 작업대에 선 미전송 줄의 회원 id — 화면에 보이는 차례 그대로.
  List<String> queueOrder(WidgetTester tester) => <String>[
    for (final Element e in find.byType(ReportWorkbench).evaluate())
      ...(() {
        final List<String> ids = <String>[];
        for (final Element row
            in find
                .descendant(
                  of: find.byWidget(e.widget),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w.key is ValueKey<String> &&
                        (w.key! as ValueKey<String>).value.startsWith(
                          'reports-queue-',
                        ),
                  ),
                )
                .evaluate()) {
          ids.add(
            (row.widget.key! as ValueKey<String>).value.replaceFirst(
              'reports-queue-',
              '',
            ),
          );
        }
        return ids;
      })(),
  ];

  testWidgets('작업대는 주의가 필요한 회원을 맨 위에 세운다 (#2232)', (tester) async {
    await openWorkbench(tester, clients: _roster);

    expect(queueOrder(tester), <String>['h', 'a']);
  });

  testWidgets('이름순으로 바꾸면 차례가 이름을 따른다 (#2232)', (tester) async {
    await openWorkbench(tester, clients: _roster);

    await tester.tap(find.text('이름 순'));
    await settle(tester);

    expect(queueOrder(tester), <String>['a', 'h']);
  });

  testWidgets('작업대는 이번 주 몇 장이 나갔는지 먼저 답한다 (#2232)', (tester) async {
    final ProviderContainer container = await openWorkbench(
      tester,
      clients: _roster,
    );

    expect(find.text('0 / 2 전송'), findsOneWidget);
    // 아직 아무도 안 보냈으니 전송 완료 열은 비어 있다고 말한다.
    expect(find.text('아직 보낸 리포트가 없어요'), findsOneWidget);

    container
        .read(reportSendLogProvider.notifier)
        .record(
          clientId: 'a',
          weekStart: weekStartOf(nowKst()),
          message: '가회원님 이번 주 리포트예요.',
        );
    await settle(tester);

    expect(find.text('1 / 2 전송'), findsOneWidget);
    // 보낸 회원은 큐에서 빠지고 전송 완료 열로 옮겨 간다.
    expect(queueOrder(tester), <String>['h']);
    expect(
      find.byKey(const ValueKey<String>('reports-sent-a')),
      findsOneWidget,
    );
  });

  testWidgets('전송 완료 줄을 누르면 회원이 받은 리포트를 그대로 본다 (#2232)', (tester) async {
    final ProviderContainer container = await openWorkbench(
      tester,
      clients: _roster,
    );
    container
        .read(reportSendLogProvider.notifier)
        .record(
          clientId: 'a',
          weekStart: weekStartOf(nowKst()),
          message: '가회원님 이번 주도 잘 지키셨어요.',
        );
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey<String>('reports-sent-a')));
    await settle(tester);

    expect(find.byType(SentReportView), findsOneWidget);
    // 보낸 글은 고칠 수 없는 글로 그대로 선다 — 회원이 읽은 것이 이 글이다.
    expect(find.text('가회원님 이번 주도 잘 지키셨어요.'), findsOneWidget);
    // 보낸 리포트는 읽는 화면이다 — 고칠 입력창을 두지 않는다.
    expect(
      find.descendant(
        of: find.byType(SentReportView),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey<String>('reports-sent-back')));
    await settle(tester);

    expect(find.byType(SentReportView), findsNothing);
    expect(find.byType(ReportWorkbench), findsOneWidget);
  });

  testWidgets('보낸 리포트에서 다시 쓰기를 누르면 그 회원의 편집기로 간다 (#2232)', (tester) async {
    final ProviderContainer container = await openWorkbench(
      tester,
      clients: _roster,
    );
    container
        .read(reportSendLogProvider.notifier)
        .record(
          clientId: 'a',
          weekStart: weekStartOf(nowKst()),
          message: '가회원님 이번 주도 잘 지키셨어요.',
        );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('reports-sent-a')));
    await settle(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('reports-sent-rewrite')),
    );
    await settle(tester);

    expect(find.text('가회원님 주간 리포트'), findsOneWidget);
  });

  testWidgets('단계는 ① 확인 → ② 작성 → ③ 전송 으로 오간다 (#2232)', (tester) async {
    await openWorkbench(tester, clients: _roster, at: AppRoutes.reportFor('a'));

    final Finder next = find.byKey(const ValueKey<String>('report-step-next'));
    final Finder prev = find.byKey(const ValueKey<String>('report-step-prev'));
    // 첫 단계에서는 뒤로 갈 곳이 없어 버튼도 없다.
    expect(prev, findsNothing);
    // ① 은 읽는 단계다 — 요일 격자가 서고, 쓰는 자리는 없다.
    expect(find.text('PT 세션'), findsOneWidget);
    expect(find.text('트레이너 피드백'), findsNothing);

    // ② 작성 — 요약과 입력창이 같은 화면에 선다. 단계 이름이 `작성` 인데
    // 글 쓰는 자리가 다음 단계에 있으면 이름이 거짓말을 한다.
    await tester.tap(next);
    await settle(tester);
    expect(find.text('이번 주 요약'), findsOneWidget);
    expect(find.text('트레이너 피드백'), findsOneWidget);
    expect(find.text('PT 세션'), findsNothing);

    await tester.tap(next);
    await settle(tester);
    expect(find.text('트레이너 피드백'), findsOneWidget);
    // 마지막 단계에는 `다음` 대신 `전송` 이 선다.
    expect(next, findsNothing);
    expect(
      find.byKey(const ValueKey<String>('report-step-send')),
      findsOneWidget,
    );

    await tester.tap(prev);
    await settle(tester);
    expect(find.text('이번 주 요약'), findsOneWidget);

    // ① 로 더 돌아가면 쓰는 자리가 사라진다.
    await tester.tap(prev);
    await settle(tester);
    expect(find.text('트레이너 피드백'), findsNothing);
    expect(find.text('PT 세션'), findsOneWidget);
  });

  testWidgets('② 에서 고른 다음 주 목표가 ③ 에 그대로 붙는다 (#2232)', (tester) async {
    await openWorkbench(tester, clients: _roster, at: AppRoutes.reportFor('h'));

    final Finder next = find.byKey(const ValueKey<String>('report-step-next'));
    await tester.tap(next);
    await settle(tester);

    // 고른 것이 없으면 ③ 에는 목표 카드가 서지 않는다.
    expect(find.text('0개 고름'), findsOneWidget);

    // 수치에서 나온 제안을 하나 고르고, 직접 적은 목표를 하나 더한다.
    final Finder firstGoal = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('report-goal-'),
        )
        .first;
    await tester.ensureVisible(firstGoal);
    await tester.pump();
    await tester.tap(firstGoal);
    await settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('report-goals-own')),
      '주 3회 스트레칭',
    );
    await tester.tap(find.byKey(const ValueKey<String>('report-goals-add')));
    await settle(tester);

    expect(find.text('2개 고름'), findsOneWidget);

    await tester.tap(next);
    await settle(tester);

    // ③ 에서는 다시 고르게 하지 않는다 — 함께 나갈 것을 보여 줄 뿐이다.
    expect(
      find.byKey(const ValueKey<String>('report-goals-recap')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('report-goals-card')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('report-goals-recap')),
        matching: find.text('주 3회 스트레칭'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('영어로 켜도 작업대에 한국어가 남지 않는다 (#501, #2232)', (tester) async {
    await openWorkbench(
      tester,
      locale: const Locale('en'),
      clients: <TrainerClient>[
        makeClient(
          id: 'a',
          name: 'Alex Kim',
          goal: 'Lose weight',
          lastMessage: 'hi',
          lastTime: 'now',
          lastRoutine: 'today',
          weekCompletion: const <int>[10, 0, 0, 10, 0, 0, 0],
        ),
      ],
    );

    final RegExp hangul = RegExp(r'[가-힣]');
    final List<String> leftovers = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ReportWorkbench),
            matching: find.byType(Text),
          ),
        )
        .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .where(hangul.hasMatch)
        .toList();

    expect(leftovers, isEmpty, reason: '영어 로케일인데 한국어가 그려졌어요: $leftovers');
  });

  testWidgets('작업대 줄은 훈련 쪽 사실만 적는다 — 칼로리·나트륨·당류는 없다 (#2232)', (tester) async {
    await openWorkbench(
      tester,
      clients: <TrainerClient>[
        makeClient(
          id: 'q',
          name: '큐회원',
          sodiumMg: 4200,
          calories: 3400,
          sugarG: 90,
          weekCompletion: const <int>[80, 0, 70, 0, 0, 60, 90],
        ),
      ],
    );

    // 기록이 끊긴 날은 요일 수로 말한다.
    expect(find.text('3일 무기록'), findsOneWidget);
    // 식단 지표는 작업대에 오지 않는다 — 그 답은 리포트 본문의 식단 카드다.
    for (final String banned in <String>['나트륨', '칼로리', '당류']) {
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').contains(banned),
        ),
        findsNothing,
        reason: '작업대 줄에 $banned 이(가) 남아 있다',
      );
    }
  });

  testWidgets('이번 주 리포트 칸이 전송 완료 칸의 두 배로 선다 (#2232)', (tester) async {
    await openWorkbench(tester, clients: _roster);

    final double sent = tester
        .getSize(find.byKey(const ValueKey<String>('reports-workbench-sent')))
        .width;
    final double queue = tester
        .getSize(find.byKey(const ValueKey<String>('reports-workbench-queue')))
        .width;
    // 이번 주에 **할 일**이 왼쪽 칸이고, 전송 완료는 이미 끝난 일이다.
    // 둘을 같은 폭으로 두면 끝난 일이 할 일만큼 자리를 차지한다.
    expect(queue / sent, closeTo(2, 0.05));
  });

  group('reportSignals', () {
    WeeklyReport report({
      List<int> week = const <int>[],
      int booked = 0,
      int done = 0,
      int? completion,
    }) => WeeklyReport(
      client: makeClient(),
      weekStart: weekStartOf(nowKst()),
      sessionsBooked: booked,
      sessionsDone: done,
      completionAvg: completion,
      sodiumOverDays: 5,
      sodiumAvg: 4200,
      isCurrentWeek: false,
      weekCompletion: week,
    );

    test('기록이 하나도 없으면 신규로 본다', () {
      expect(reportSignals(report()), <ReportSignal>[
        const ReportSignal(ReportSignalKind.onboarding),
      ]);
    });

    test('빠진 세션은 이행률 다음에 온다', () {
      final List<ReportSignal> signals = reportSignals(
        report(
          week: const <int>[90, 80, 90, 80, 90, 80, 90],
          completion: 85,
          booked: 2,
          done: 1,
        ),
      );
      expect(
        signals.first,
        const ReportSignal(ReportSignalKind.completion, 85),
      );
      expect(signals[1], const ReportSignal(ReportSignalKind.noShow, 1));
    });

    test('주 후반이 무너진 주는 하락으로 읽는다', () {
      final List<ReportSignal> signals = reportSignals(
        report(week: const <int>[100, 90, 100, 60, 40, 30, 40], completion: 66),
      );
      expect(
        signals.any((s) => s.kind == ReportSignalKind.slump),
        isTrue,
        reason: '$signals',
      );
    });

    test('식단 수치는 신호에도 점수에도 들어가지 않는다', () {
      // 나트륨이 닷새 넘친 주여도 신호는 운동 쪽 사실뿐이다.
      final List<ReportSignal> signals = reportSignals(
        report(
          week: const <int>[100, 100, 100, 100, 100, 100, 100],
          completion: 100,
        ),
      );
      expect(
        signals.map((s) => s.kind),
        everyElement(isNot(ReportSignalKind.onboarding)),
      );
      expect(
        signals.any((s) => s.kind == ReportSignalKind.fullLog),
        isTrue,
        reason: '$signals',
      );
    });
  });

  group('withDemoSends', () {
    test('데모 로스터의 몇 명은 이미 보낸 것으로 선다', () {
      final DateTime week = weekStartOf(nowKst());
      final Map<String, ReportSendRecord> merged = withDemoSends(
        const <String, ReportSendRecord>{},
        <String>{'seed-client-1', 'seed-client-2', 'seed-client-5'},
        week,
      );
      final Set<String> sent = sentClientsIn(merged, week);
      expect(sent, containsAll(<String>['seed-client-2', 'seed-client-5']));
      // 시연의 주인공은 미전송으로 남는다 — 그의 리포트는 화면에서 직접 쓴다.
      expect(sent, isNot(contains('seed-client-1')));
    });

    test('트레이너가 실제로 보낸 기록을 덮어쓰지 않는다', () {
      final DateTime week = weekStartOf(nowKst());
      final ReportSendRecord mine = ReportSendRecord(
        clientId: 'seed-client-2',
        weekStart: week,
        sentAt: nowKst(),
        message: '직접 쓴 글',
      );
      final Map<String, ReportSendRecord> merged = withDemoSends(
        <String, ReportSendRecord>{'seed-client-2|${ymd(week)}': mine},
        <String>{'seed-client-2'},
        week,
      );
      expect(sendRecordFor(merged, 'seed-client-2', week)!.message, '직접 쓴 글');
    });

    test('로스터 열다섯 명이 두 열로 갈린다 — 손볼 회원은 남는 쪽에 선다', () {
      final DateTime week = weekStartOf(nowKst());
      final Set<String> roster = <String>{
        for (int i = 1; i <= 15; i++) 'seed-client-$i',
      };
      final Set<String> sent = sentClientsIn(
        withDemoSends(const <String, ReportSendRecord>{}, roster, week),
        week,
      );
      // 두 열이 다 차 있어야 작업대가 무슨 화면인지 읽힌다.
      expect(sent, isNotEmpty);
      expect(roster.difference(sent), isNotEmpty);
      // 신호가 붙어야 할 회원은 작업대에 남는다: 김민수(시연 주인공),
      // 박성호·문가영(휴면), 오세라(악화), 배준혁(답장 대기), 임도현(신규),
      // 노은채(기록 하루).
      for (final String id in <String>[
        'seed-client-1',
        'seed-client-3',
        'seed-client-7',
        'seed-client-8',
        'seed-client-9',
        'seed-client-12',
        'seed-client-15',
      ]) {
        expect(sent, isNot(contains(id)), reason: '$id 은 미전송이어야 한다');
      }
    });

    test('안 읽은 회원이 섞여 있다 — 우선 확인 안내가 읽을 값이다', () {
      final DateTime week = weekStartOf(nowKst());
      final Map<String, ReportSendRecord> merged = withDemoSends(
        const <String, ReportSendRecord>{},
        <String>{for (int i = 1; i <= 15; i++) 'seed-client-$i'},
        week,
      );
      final Iterable<ReportSendRecord> demo = merged.values;
      expect(demo.where((ReportSendRecord r) => r.read), isNotEmpty);
      expect(demo.where((ReportSendRecord r) => !r.read), isNotEmpty);
    });

    test('지난 주에는 데모 기록을 얹지 않는다', () {
      final DateTime last = weekStartOf(
        nowKst().subtract(const Duration(days: 7)),
      );
      expect(
        withDemoSends(const <String, ReportSendRecord>{}, <String>{
          'seed-client-2',
        }, last),
        isEmpty,
      );
    });
  });
}
