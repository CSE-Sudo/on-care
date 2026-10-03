/// 리포트 탭의 작업대·단계 편집기·보낸 리포트 (#2232).
///
/// 리포트 탭은 회원 하나를 골라 그 주를 읽는 화면이 아니라, 이번 주 여러 장을
/// 내보내는 라인이다. 그래서 이 파일이 보는 것은 그래프의 내용이 아니라
/// **일의 흐름** 이다 — 누가 남았나, 어디까지 왔나, 보낸 건 무엇이었나.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_send_preview.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_nav.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/sent_report_view.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

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
    List<Override> extraOverrides = const <Override>[],
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
        ...extraOverrides,
      ],
    );
    await settle(tester);
    return container;
  }

  /// 줄의 리포트 수치가 붙을 때까지 기다린다.
  ///
  /// PT 관리 신호는 로스터에서 바로 오지만, 이행률·주 후반 하락 같은 리포트
  /// 배지는 데모 DB(drift)를 **실제 시간**으로 읽은 뒤에 붙는다. 전체 스위트처럼
  /// 머신이 바쁠 때는 [settle] 의 가짜 시간 2초 안에 끝나지 않는다.
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 250));
    }
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

    await tester.tap(find.byKey(const ValueKey<String>('reports-sort-button')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('reports-sort-name')));
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

  testWidgets('전송 완료 줄의 보기를 누르면 회원이 받은 리포트를 그대로 본다 (#2232)', (tester) async {
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

    await tester.tap(find.byKey(const ValueKey<String>('reports-view-a')));
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
    await tester.tap(find.byKey(const ValueKey<String>('reports-view-a')));
    await settle(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('reports-sent-rewrite')),
    );
    await settle(tester);

    expect(find.text('가회원님 주간 리포트'), findsOneWidget);
  });

  testWidgets('단계는 ① 확인 → ② 작성 → ③ 전송 으로 오간다 (#2232)', (tester) async {
    await openWorkbench(
      tester,
      clients: _roster,
      at: AppRoutes.reportFor('a'),
      // ③ 은 들어서자마자 PDF 를 만든다(#2402) — 실 생성기와 쪽 굽기는
      // 테스트에서 끝나지 않아 곧바로 끝나는 가짜를 둔다.
      extraOverrides: <Override>[
        reportPdfGeneratorProvider.overrideWithValue(_InstantPdfGenerator()),
        reportPdfRasterizerProvider.overrideWithValue(
          (Uint8List pdf) async => <Uint8List>[pdf],
        ),
      ],
    );

    final Finder next = find.byKey(const ValueKey<String>('report-step-next'));
    final Finder prev = find.byKey(const ValueKey<String>('report-step-prev'));
    // 첫 단계에서는 뒤로 갈 곳이 없어 버튼도 없다.
    expect(prev, findsNothing);
    // ① 은 읽는 단계다 — 요일 격자가 서고, 쓰는 자리는 없다.
    expect(find.text('PT'), findsOneWidget);
    expect(find.text('트레이너 피드백'), findsNothing);

    // ② 작성 — 요약과 입력창이 같은 화면에 선다. 단계 이름이 `작성` 인데
    // 글 쓰는 자리가 다음 단계에 있으면 이름이 거짓말을 한다.
    await tester.tap(next);
    await settle(tester);
    expect(find.text('이번 주 요약'), findsOneWidget);
    expect(find.text('트레이너 피드백'), findsOneWidget);
    expect(find.text('PT'), findsNothing);

    await tester.tap(next);
    await settle(tester);
    // ③ 전송은 회원이 받을 PDF 를 보여 준다 — 입력창은 ② 에만 있다(#2402).
    expect(find.text('트레이너 피드백'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('report-send-preview')),
      findsOneWidget,
    );
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
    expect(find.text('PT'), findsOneWidget);
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
          // 서버가 식단 신호를 실어 보내도 작업대에는 오지 않는다.
          signals: const <ClientSignal>[
            ClientSignal(ClientSignalKind.calorieOff, percent: 22, over: true),
            ClientSignal(ClientSignalKind.proteinLow, percent: 64),
          ],
        ),
      ],
    );

    // 운동 이행률 0 인 날을 따로 세어 `N일 무기록` 이라 말하지 않는다 — 기록
    // 끊김은 PT 관리 신호가 말한다(#2344).
    await waitFor(tester, find.text('이행 75%'));
    expect(find.textContaining('무기록'), findsNothing);
    expect(find.text('이행 75%'), findsOneWidget);
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

  testWidgets('작업대 줄은 회원 상세와 같은 PT 관리 신호 배지를 단다 (#2344)', (tester) async {
    await openWorkbench(
      tester,
      clients: <TrainerClient>[
        makeClient(
          id: 's',
          name: '신호회원',
          weekCompletion: const <int>[80, 80, 80, 80, 80, 80, 80],
          signals: const <ClientSignal>[
            ClientSignal(ClientSignalKind.noShow, count: 2),
            ClientSignal(ClientSignalKind.recordGap, days: 4),
          ],
        ),
      ],
    );

    // 문구는 회원 상세 헤더의 `detailLabel` 그대로, 급한 순서 그대로.
    final Finder gap = find.byKey(
      const ValueKey<String>('reports-queue-alert-s-record_gap'),
    );
    final Finder noShow = find.byKey(
      const ValueKey<String>('reports-queue-alert-s-no_show'),
    );
    expect(
      find.descendant(of: gap, matching: find.text('4일째 기록 없음')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: noShow, matching: find.text('노쇼·취소 2회')),
      findsOneWidget,
    );
    expect(tester.getTopLeft(gap).dx, lessThan(tester.getTopLeft(noShow).dx));
    // 모양도 같다 — 빨강 톤에 ⓘ 아이콘.
    final AppTag tag = tester.widget<AppTag>(
      find.descendant(of: gap, matching: find.byType(AppTag)),
    );
    expect(tag.tone, AppTagTone.danger);
    expect(tag.icon, AppIcons.error);
    // 리포트 고유 배지는 그 뒤에 남는다.
    await waitFor(tester, find.text('이행 80%'));
    expect(find.text('이행 80%'), findsOneWidget);
    // 예전의 앱 로컬 노쇼 문구는 없다.
    expect(find.text('노쇼 1회'), findsNothing);
  });

  testWidgets('PT 관리 신호가 여럿이어도 리포트 고유 배지는 남는다 (#2344)', (tester) async {
    await openWorkbench(
      tester,
      clients: <TrainerClient>[
        makeClient(
          id: 'm',
          name: '많은회원',
          weekCompletion: const <int>[100, 90, 100, 60, 40, 30, 40],
          signals: const <ClientSignal>[
            ClientSignal(ClientSignalKind.discomfort),
            ClientSignal(ClientSignalKind.noShow, count: 2),
            ClientSignal(ClientSignalKind.exerciseGoalLow, percent: 28),
          ],
        ),
      ],
    );

    expect(find.text('통증·불편'), findsOneWidget);
    expect(find.text('노쇼·취소 2회'), findsOneWidget);
    expect(find.text('운동 목표 28%'), findsOneWidget);
    await waitFor(tester, find.textContaining('하락'));
    expect(find.textContaining('하락'), findsOneWidget);
  });

  group('전송 진행 줄 (#2395)', () {
    Finder progress() => find.byKey(const ValueKey<String>('reports-progress'));
    Finder percent() =>
        find.byKey(const ValueKey<String>('reports-progress-percent'));
    Finder queueBox() =>
        find.byKey(const ValueKey<String>('reports-workbench-queue'));
    Finder sentBox() =>
        find.byKey(const ValueKey<String>('reports-workbench-sent'));

    testWidgets('막대 오른쪽 끝에 전송 비율을 적는다', (tester) async {
      final ProviderContainer container = await openWorkbench(
        tester,
        clients: _roster,
      );

      expect(find.text('0 / 2 전송'), findsOneWidget);
      expect(tester.widget<Text>(percent()).data, '0%');

      container
          .read(reportSendLogProvider.notifier)
          .record(
            clientId: 'a',
            weekStart: weekStartOf(nowKst()),
            message: '가회원님 이번 주 리포트예요.',
          );
      await settle(tester);

      expect(tester.widget<Text>(percent()).data, '50%');
      // 비율은 막대 오른쪽, 줄의 끝에 선다.
      final Rect bar = tester.getRect(
        find.descendant(of: progress(), matching: find.byType(AppProgressBar)),
      );
      expect(tester.getRect(percent()).left, greaterThan(bar.right));
    });

    testWidgets('막대가 두껍고 빈 구간이 배경과 구분되는 색이다 (#2446)', (tester) async {
      await openWorkbench(tester, clients: _roster);

      final Finder bar = find.byKey(
        const ValueKey<String>('reports-progress-bar'),
      );
      expect(bar, findsOneWidget);
      final AppProgressBar widget = tester.widget<AppProgressBar>(bar);
      expect(widget.height, OnCareSize.progressBarThick);
      expect(widget.height, greaterThan(OnCareSize.progressBar));
      // 빈 구간은 페이지 배경(입력 채움과 거의 같은 색)과 다른 선 색이다.
      expect(widget.trackColor, OnCareColors.lineStrong);
      expect(widget.trackColor, isNot(OnCareColors.surfaceInput));
      expect(tester.getSize(bar).height, OnCareSize.progressBarThick);
    });

    testWidgets('아무도 안 보낸 주에도 막대 전체 길이가 트랙으로 그려진다 (#2446)', (tester) async {
      await openWorkbench(tester, clients: _roster);

      final LinearProgressIndicator indicator = tester
          .widget<LinearProgressIndicator>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('reports-progress-bar')),
              matching: find.byType(LinearProgressIndicator),
            ),
          );
      expect(indicator.value, 0);
      expect(indicator.backgroundColor, OnCareColors.lineStrong);
      expect(indicator.minHeight, OnCareSize.progressBarThick);
    });

    testWidgets('넓은 화면에서 진행 줄이 두 상자를 가로지른다', (tester) async {
      await openWorkbench(tester, clients: _roster);

      final Rect row = tester.getRect(progress());
      final Rect queue = tester.getRect(queueBox());
      final Rect sent = tester.getRect(sentBox());
      // 미전송 상자의 왼쪽 끝에서 전송 완료 상자의 오른쪽 끝까지.
      expect(row.left, closeTo(queue.left, 1));
      expect(row.right, closeTo(sent.right, 1));
      // 두 상자보다 위에 선다 — 한쪽 상자의 머리가 아니다.
      expect(row.bottom, lessThanOrEqualTo(queue.top));
      expect(row.bottom, lessThanOrEqualTo(sent.top));
      // 두 상자의 윗변이 같은 높이에서 시작한다.
      expect(queue.top, closeTo(sent.top, 1));
    });

    testWidgets('좁은 화면에서도 진행 줄이 맨 위에 선다', (tester) async {
      await openWorkbench(
        tester,
        clients: _roster,
        size: const Size(700, 1400),
      );

      final Rect row = tester.getRect(progress());
      expect(row.bottom, lessThanOrEqualTo(tester.getRect(queueBox()).top));
      expect(percent(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('영어에서는 sent 와 비율을 함께 적는다', (tester) async {
      await openWorkbench(tester, clients: _roster, locale: const Locale('en'));

      expect(find.text('0 / 2 sent'), findsOneWidget);
      expect(tester.widget<Text>(percent()).data, '0%');
    });

    test('비율은 반올림한 정수다', () {
      expect(reportSendPercent(0, 15), 0);
      expect(reportSendPercent(1, 15), 7);
      expect(reportSendPercent(6, 15), 40);
      expect(reportSendPercent(2, 3), 67);
      expect(reportSendPercent(15, 15), 100);
    });

    test('회원이 없으면 0% — 0으로 나누지 않는다', () {
      expect(reportSendPercent(0, 0), 0);
    });

    test('범위를 벗어난 수는 0~100 으로 묶는다', () {
      expect(reportSendPercent(20, 15), 100);
      expect(reportSendPercent(-1, 15), 0);
    });
  });

  group('두 상자 높이 고정·안쪽 스크롤 (#2396)', () {
    final List<TrainerClient> many = <TrainerClient>[
      for (int i = 0; i < 20; i++)
        makeClient(
          id: 'm$i',
          name: '회원${i.toString().padLeft(2, '0')}',
          weekCompletion: const <int>[50, 50, 50, 50, 50, 50, 50],
        ),
    ];
    Finder queueBox() =>
        find.byKey(const ValueKey<String>('reports-workbench-queue'));
    Finder sentBox() =>
        find.byKey(const ValueKey<String>('reports-workbench-sent'));
    Finder queueList() =>
        find.byKey(const ValueKey<String>('reports-workbench-queue-list'));

    testWidgets('넓은 화면에서 두 상자가 같은 높이로 화면 아래까지 선다', (tester) async {
      await openWorkbench(tester, clients: _roster);

      final Rect queue = tester.getRect(queueBox());
      final Rect sent = tester.getRect(sentBox());
      expect(queue.top, closeTo(sent.top, 1));
      expect(queue.height, closeTo(sent.height, 1));
      // 줄 수만큼만 서지 않는다 — 두 줄뿐이어도 상자는 창 아래쪽까지 간다.
      expect(sent.bottom, greaterThan(1200 * 0.8));
      expect(sent.bottom, lessThanOrEqualTo(1200));
      // 페이지째 내리는 스크롤이 없다.
      expect(
        find.byKey(const ValueKey<String>('reports-workbench-page-scroll')),
        findsNothing,
      );
    });

    testWidgets('목록을 내려도 상자 머리와 전송 완료 상자는 제자리다', (tester) async {
      await openWorkbench(tester, clients: many, size: const Size(1600, 700));

      final Finder firstRow = find.text('회원00');
      final Finder sortToggle = find.byKey(
        const ValueKey<String>('reports-sort-button'),
      );
      expect(firstRow, findsOneWidget);
      final Offset toggleBefore = tester.getTopLeft(sortToggle);
      final Rect sentBefore = tester.getRect(sentBox());
      final Rect queueBefore = tester.getRect(queueBox());

      await tester.drag(queueList(), const Offset(0, -2000));
      await settle(tester);

      // 목록은 상자 안에서 내려가 첫 줄이 밀려나고 마지막 줄이 보인다.
      expect(find.text('회원00').hitTestable(), findsNothing);
      expect(find.text('회원19').hitTestable(), findsOneWidget);
      // 정렬 버튼·두 상자는 움직이지 않는다.
      expect(tester.getTopLeft(sortToggle), toggleBefore);
      expect(tester.getRect(sentBox()), sentBefore);
      expect(tester.getRect(queueBox()), queueBefore);
      // 마지막 줄도 상자 안에서 끝난다 — 상자 밖으로 새지 않는다.
      expect(
        tester.getRect(find.text('회원19')).bottom,
        lessThanOrEqualTo(queueBefore.bottom),
      );
    });

    testWidgets('창이 낮으면 상자를 최소 높이로 세우고 페이지를 내린다', (tester) async {
      await openWorkbench(tester, clients: many, size: const Size(1600, 360));

      expect(
        find.byKey(const ValueKey<String>('reports-workbench-page-scroll')),
        findsOneWidget,
      );
      final Rect queue = tester.getRect(queueBox());
      final Rect sent = tester.getRect(sentBox());
      expect(queue.height, closeTo(sent.height, 1));
      // 창(360)보다 큰 최소 높이가 지켜진다 — 머리만 남은 상자가 되지 않는다.
      expect(queue.bottom, greaterThan(360));
      expect(tester.takeException(), isNull);
    });

    testWidgets('한쪽이 비어도 상자 크기는 그대로, 빈 문구는 가운데', (tester) async {
      await openWorkbench(tester, clients: _roster);

      // 아직 아무도 보내지 않았다 — 전송 완료 상자가 빈 채로 선다.
      final Rect sent = tester.getRect(sentBox());
      final Rect queue = tester.getRect(queueBox());
      expect(sent.height, closeTo(queue.height, 1));
      final Finder empty = find.byKey(
        const ValueKey<String>('reports-sent-empty'),
      );
      expect(empty, findsOneWidget);
      final double emptyCenter = tester.getCenter(empty).dy;
      // 상자 위쪽에 붙지 않고 세로 가운데 언저리에 선다.
      expect(emptyCenter, greaterThan(sent.top + sent.height * 0.35));
      expect(emptyCenter, lessThan(sent.top + sent.height * 0.65));
    });

    testWidgets('좁은 화면은 높이를 고정하지 않고 페이지째 내린다', (tester) async {
      await openWorkbench(
        tester,
        clients: _roster,
        size: const Size(700, 1400),
      );

      final Rect queue = tester.getRect(queueBox());
      final Rect sent = tester.getRect(sentBox());
      // 위아래로 쌓인다.
      expect(sent.top, greaterThan(queue.bottom));
      // 줄 수만큼만 선다 — 창 높이를 채우려고 늘어나지 않는다.
      expect(queue.height, lessThan(1400 / 2));
      expect(queueList(), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('전송 완료 상자 모양 미전송 기준 (#2397)', () {
    AppTagTone countTone(WidgetTester tester, String boxKey) {
      final Finder tag = find
          .descendant(
            of: find.byKey(ValueKey<String>(boxKey)),
            matching: find.byType(AppTag),
          )
          .first;
      return tester.widget<AppTag>(tag).tone;
    }

    testWidgets('두 인원 배지는 같은 브랜드 톤이다', (tester) async {
      final ProviderContainer container = await openWorkbench(
        tester,
        clients: _roster,
      );

      // 전송 완료 0명.
      expect(countTone(tester, 'reports-workbench-queue'), AppTagTone.brand);
      expect(countTone(tester, 'reports-workbench-sent'), AppTagTone.brand);

      for (final String id in <String>['a', 'h']) {
        container
            .read(reportSendLogProvider.notifier)
            .record(
              clientId: id,
              weekStart: weekStartOf(nowKst()),
              message: '이번 주 리포트예요.',
            );
      }
      await settle(tester);

      // 미전송 0명 — 초록으로 바뀌지 않는다.
      expect(
        find.byKey(const ValueKey<String>('reports-queue-empty')),
        findsOneWidget,
      );
      expect(countTone(tester, 'reports-workbench-queue'), AppTagTone.brand);
      expect(countTone(tester, 'reports-workbench-sent'), AppTagTone.brand);
    });

    testWidgets('전송 완료 줄은 미전송 줄과 같은 흰 카드다', (tester) async {
      final ProviderContainer container = await openWorkbench(
        tester,
        clients: _roster,
      );
      container
          .read(reportSendLogProvider.notifier)
          .record(
            clientId: 'a',
            weekStart: weekStartOf(nowKst()),
            message: '가회원님 이번 주 리포트예요.',
          );
      await settle(tester);

      final Widget sentRow = tester.widget(
        find.byKey(const ValueKey<String>('reports-sent-a')),
      );
      final Widget queueRow = tester.widget(
        find.byKey(const ValueKey<String>('reports-queue-h')),
      );
      expect(sentRow, isA<AppCard>());
      expect(queueRow, isA<AppCard>());
      final AppCard sent = sentRow as AppCard;
      final AppCard queue = queueRow as AppCard;
      // 색을 따로 칠하지 않은 기본 흰 카드, 같은 안쪽 여백.
      expect(sent.backgroundColor, isNull);
      expect(sent.selected, isFalse);
      expect(sent.padding, queue.padding);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('reports-workbench-sent')),
          matching: find.byType(AppTile),
        ),
        findsNothing,
      );
      // 이름·전송일 문구는 카드 안에 그대로 선다.
      final Finder inCard = find.descendant(
        of: find.byKey(const ValueKey<String>('reports-sent-a')),
        matching: find.byType(Text),
      );
      // 이름 줄은 성별·나이를 이어 붙인 Text.rich 라 span 까지 읽는다(#2447).
      final List<String> texts = <String>[
        for (final Element e in inCard.evaluate())
          (e.widget as Text).data ??
              (e.widget as Text).textSpan?.toPlainText() ??
              '',
      ];
      expect(texts.any((t) => t.startsWith('가회원')), isTrue);
      expect(texts.any((t) => t.contains('전송')), isTrue);
    });
  });

  group('정렬 드롭다운 (#2398)', () {
    final List<TrainerClient> trio = <TrainerClient>[
      makeClient(
        id: 'b',
        name: '나회원',
        weekCompletion: const <int>[100, 100, 100, 100, 100, 100, 100],
      ),
      makeClient(
        id: 'c',
        name: '다회원',
        weekCompletion: const <int>[0, 0, 0, 0, 0, 0, 0],
      ),
      makeClient(
        id: 'a',
        name: '가회원',
        weekCompletion: const <int>[60, 60, 60, 60, 60, 60, 60],
      ),
    ];
    Finder sortButton() =>
        find.byKey(const ValueKey<String>('reports-sort-button'));
    Finder item(ReportQueueSort sort) =>
        find.byKey(ValueKey<String>('reports-sort-${sort.name}'));
    List<String> order(WidgetTester tester) {
      final List<MapEntry<String, double>> rows = <MapEntry<String, double>>[
        for (final String id in <String>['a', 'b', 'c'])
          MapEntry<String, double>(
            id,
            tester
                .getTopLeft(find.byKey(ValueKey<String>('reports-queue-$id')))
                .dy,
          ),
      ]..sort((x, y) => x.value.compareTo(y.value));
      return <String>[for (final MapEntry<String, double> e in rows) e.key];
    }

    Future<void> choose(WidgetTester tester, ReportQueueSort sort) async {
      await tester.tap(sortButton());
      await settle(tester);
      await tester.tap(item(sort));
      await settle(tester);
    }

    testWidgets('버튼은 `정렬: 우선 확인 순` 으로 시작하고 토글은 없다', (tester) async {
      await openWorkbench(tester, clients: trio);

      expect(
        find.descendant(of: sortButton(), matching: find.text('정렬: 우선 확인 순')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sortButton(),
          matching: find.byIcon(AppIcons.expandMore),
        ),
        findsOneWidget,
      );
      expect(find.byType(AppSegmentedToggle<ReportQueueSort>), findsNothing);
      // 기본값은 우선 확인 순 — 이행률이 가장 낮은 회원이 맨 위.
      expect(order(tester).first, 'c');
    });

    testWidgets('메뉴는 세 방식을 보이고 고른 항목에 체크를 단다', (tester) async {
      await openWorkbench(tester, clients: trio);

      await tester.tap(sortButton());
      await settle(tester);
      for (final ReportQueueSort sort in ReportQueueSort.values) {
        expect(item(sort), findsOneWidget);
      }
      expect(find.text('이름 오름차순'), findsOneWidget);
      expect(find.text('이름 내림차순'), findsOneWidget);
      // 체크는 지금 고른 우선 확인 순에만 선다.
      MenuItemButton menuItem(ReportQueueSort sort) =>
          tester.widget<MenuItemButton>(item(sort));
      expect(menuItem(ReportQueueSort.priority).leadingIcon, isA<AppIcon>());
      expect(menuItem(ReportQueueSort.name).leadingIcon, isNull);
      expect(menuItem(ReportQueueSort.nameDescending).leadingIcon, isNull);

      await tester.tap(item(ReportQueueSort.nameDescending));
      await settle(tester);
      await tester.tap(sortButton());
      await settle(tester);
      expect(menuItem(ReportQueueSort.priority).leadingIcon, isNull);
      expect(
        menuItem(ReportQueueSort.nameDescending).leadingIcon,
        isA<AppIcon>(),
      );
    });

    testWidgets('이름 오름차순·내림차순을 고르면 줄 순서와 버튼 문구가 바뀐다', (tester) async {
      await openWorkbench(tester, clients: trio);

      await choose(tester, ReportQueueSort.name);
      expect(order(tester), <String>['a', 'b', 'c']);
      expect(find.text('정렬: 이름 오름차순'), findsOneWidget);

      await choose(tester, ReportQueueSort.nameDescending);
      expect(order(tester), <String>['c', 'b', 'a']);
      expect(find.text('정렬: 이름 내림차순'), findsOneWidget);

      await choose(tester, ReportQueueSort.priority);
      expect(order(tester).first, 'c');
      expect(find.text('정렬: 우선 확인 순'), findsOneWidget);
    });

    testWidgets('주를 옮겨도 고른 정렬이 남는다', (tester) async {
      await openWorkbench(tester, clients: trio);
      await choose(tester, ReportQueueSort.nameDescending);

      await tester.tap(
        find.descendant(
          of: find.byType(ReportWeekNav),
          matching: find.widgetWithIcon(IconButton, AppIcons.chevronLeft),
        ),
      );
      await settle(tester);

      expect(find.text('정렬: 이름 내림차순'), findsOneWidget);
    });

    testWidgets('영어 문구', (tester) async {
      await openWorkbench(tester, clients: trio, locale: const Locale('en'));

      expect(find.text('Sort: Needs attention'), findsOneWidget);
      await tester.tap(sortButton());
      await settle(tester);
      expect(find.text('Name A–Z'), findsOneWidget);
      expect(find.text('Name Z–A'), findsOneWidget);
    });

    test('정렬 도메인 — 우선 확인·이름 오름·내림', () {
      List<String> ids(ReportQueueSort sort) => <String>[
        for (final ReportQueueEntry e in buildReportQueue(
          clients: trio,
          reports: const <String, WeeklyReport>{},
          sentIds: const <String>{},
          sort: sort,
        ))
          e.client.id,
      ];
      expect(ids(ReportQueueSort.name), <String>['a', 'b', 'c']);
      expect(ids(ReportQueueSort.nameDescending), <String>['c', 'b', 'a']);
      // 수치를 못 읽은 줄끼리는 점수가 같아 이름 순으로 선다.
      expect(ids(ReportQueueSort.priority), <String>['a', 'b', 'c']);
      expect(ReportQueueSort.values, hasLength(3));
    });
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

    test('예약 − 완료 를 노쇼로 말하지 않는다 — 남은 예정 세션일 수 있다 (#2343)', () {
      // 실서버의 `sessions_booked` 는 예정 + 완료다. 수요일에 금요일 PT 가
      // 남아 있는 주도 이렇게 보인다.
      final List<ReportSignal> signals = reportSignals(
        report(
          week: const <int>[90, 80, 90, 80, 90, 80, 90],
          completion: 85,
          booked: 2,
          done: 1,
        ),
      );
      expect(signals, const <ReportSignal>[
        ReportSignal(ReportSignalKind.completion, 85),
        ReportSignal(ReportSignalKind.fullLog),
      ]);
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

  group('ReportQueueEntry.priority', () {
    WeeklyReport report({
      required int completion,
      int booked = 0,
      int done = 0,
    }) => WeeklyReport(
      client: makeClient(),
      weekStart: weekStartOf(nowKst()),
      sessionsBooked: booked,
      sessionsDone: done,
      completionAvg: completion,
      sodiumOverDays: 0,
      sodiumAvg: 0,
      isCurrentWeek: false,
      weekCompletion: List<int>.filled(7, completion),
    );

    ReportQueueEntry entry(
      int completion, {
      int booked = 0,
      int done = 0,
      List<ClientSignal> signals = const <ClientSignal>[],
    }) => ReportQueueEntry(
      client: makeClient(signals: signals),
      report: report(completion: completion, booked: booked, done: done),
      sent: false,
    );

    test('아직 하지 않은 예정 세션은 순서를 끌어올리지 않는다 (#2343)', () {
      expect(entry(90, booked: 3).priority, greaterThan(entry(80).priority));
    });

    test('PT 관리 신호가 걸린 회원이 위로 온다 (#2344)', () {
      expect(
        entry(
          85,
          signals: const <ClientSignal>[
            ClientSignal(ClientSignalKind.noShow, count: 2),
          ],
        ).priority,
        lessThan(entry(60).priority),
      );
    });

    test('식단 신호·답장 대기는 순서에 들지 않는다 (#2232)', () {
      final ReportQueueEntry diet = entry(
        80,
        signals: const <ClientSignal>[
          ClientSignal(ClientSignalKind.calorieOff, percent: 30, over: true),
          ClientSignal(ClientSignalKind.proteinLow, percent: 50),
          ClientSignal(ClientSignalKind.unanswered),
        ],
      );
      expect(diet.attention, isEmpty);
      expect(diet.priority, entry(80).priority);
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

/// 곧바로 끝나는 PDF 생성기.
class _InstantPdfGenerator extends ReportPdfGenerator {
  @override
  Future<Uint8List> generate({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) async => Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);
}
