import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/client_report_view.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_pdf_export_dialog.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_nav.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_actions.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/mini_charts.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 요약 생성만 실패한다 — 리포트 본문은 정상이라 카드 하나만 폴백으로 간다.
class _SummaryFailsRepository implements ReportRepository {
  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) => Stream<WeeklyReport>.value(
    buildWeeklyReport(client: client, sessions: const [], weekStart: weekStart),
  );

  @override
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
    required AppLocalizations l,
  }) async => throw StateError('summary provider down');

  @override
  Future<void> send({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) async {}

  @override
  Future<void> sendPdf({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async {}

  @override
  Future<ReportFeedbackDraft> feedbackDraft({
    required TrainerClient client,
    required DateTime weekStart,
  }) async => const ReportFeedbackDraft.none();

  @override
  Future<ReportFeedbackDraft> saveFeedbackDraft({
    required String clientId,
    required DateTime weekStart,
    required String body,
  }) async => ReportFeedbackDraft(body: body, saved: true);

  @override
  Future<void> saveNextWeekGoals({
    required String clientId,
    required DateTime weekStart,
    required List<String> goals,
  }) async {}
}

class _ReportFailsOncePerKeyRepository implements ReportRepository {
  final Map<String, int> _attempts = <String, int>{};
  final List<ReportKey> calls = <ReportKey>[];

  @override
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
    required AppLocalizations l,
  }) async => ruleReportSummary(
    l,
    buildWeeklyReport(client: client, sessions: const [], weekStart: weekStart),
    client,
  );

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) {
    final key = '${client.id}/${weekStart.toIso8601String()}';
    calls.add((client: client, weekStart: weekStart));
    final attempt = (_attempts[key] ?? 0) + 1;
    _attempts[key] = attempt;
    if (attempt == 1) {
      return Stream<WeeklyReport>.error(StateError('report transport detail'));
    }
    return Stream<WeeklyReport>.value(
      buildWeeklyReport(
        client: client,
        sessions: const [],
        weekStart: weekStart,
      ),
    );
  }

  @override
  Future<void> send({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) async {}

  @override
  Future<void> sendPdf({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async {}

  @override
  Future<ReportFeedbackDraft> feedbackDraft({
    required TrainerClient client,
    required DateTime weekStart,
  }) async => const ReportFeedbackDraft.none();

  @override
  Future<ReportFeedbackDraft> saveFeedbackDraft({
    required String clientId,
    required DateTime weekStart,
    required String body,
  }) async => ReportFeedbackDraft(body: body, saved: true);

  @override
  Future<void> saveNextWeekGoals({
    required String clientId,
    required DateTime weekStart,
    required List<String> goals,
  }) async {}
}

/// 리포트 against the seeded roster — the trainer's own week plus one
/// client's report, and sending it into their chat thread.
void main() {
  /// 헤더의 공유 메뉴를 연다 — 전송은 이제 이 메뉴 안에 있다(#735).
  Future<void> openShareMenu(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('reports-share-action')),
    );
    await settle(tester);
  }

  /// 리포트 본문의 피드백 입력창.
  final Finder feedbackField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == '회원에게 전달할 코칭 피드백을 작성하세요.',
  );

  /// 피드백 카드 제목 줄의 되돌리기·다시 실행 화살표(#2187).
  final Finder undoFeedback = find.byKey(
    const ValueKey<String>('report-feedback-undo'),
  );
  final Finder redoFeedback = find.byKey(
    const ValueKey<String>('report-feedback-redo'),
  );

  /// 리포트 카드 제목 줄의 주 이동 화살표. 헤더가 아니라 카드 안에 있다(#1177).
  /// 공용 `AppPeriodNav` 의 화살표라 키 대신 주 이동 안의 아이콘 버튼으로 찾는다.
  final Finder prevWeek = find.descendant(
    of: find.byType(ReportWeekNav),
    matching: find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
  );
  final Finder nextWeek = find.descendant(
    of: find.byType(ReportWeekNav),
    matching: find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
  );

  /// 공유 메뉴 항목. 공용 `AppMenu` 항목에는 키가 없어 문구로 찾는다.
  Finder shareItem(String label) => find.widgetWithText(MenuItemButton, label);

  /// 리포트 탭을 연다.
  ///
  /// 탭의 첫 화면은 **작업대**다(#2232). 리포트 본문을 보는 테스트가 대부분
  /// 이라, 따로 말하지 않으면 한 회원의 편집기로 바로 들어간다 — 작업대
  /// 자체를 보는 테스트만 [workbench] 를 켠다. [stage] 는 편집기의 단계
  /// (0 이번 주 확인 · 1 다음 주 목표 · 2 전송)다.
  Future<ProviderContainer> openReports(
    WidgetTester tester, {
    String? clientId,
    bool workbench = false,
    DateTime? weekStart,
    int stage = 0,
    Size size = const Size(1600, 1200),
    List<Override> extraOverrides = const <Override>[],
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProviderContainer container = await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: workbench
          ? AppRoutes.reports
          : AppRoutes.reportFor(
              clientId ?? 'seed-client-1',
              weekStart: weekStart,
            ),
      extraOverrides: extraOverrides,
    );
    if (!workbench && stage > 0) {
      await tester.pumpAndSettle();
      for (int i = 0; i < stage; i++) {
        await tester.tap(
          find.byKey(const ValueKey<String>('report-step-next')),
        );
        await tester.pumpAndSettle();
      }
    }
    return container;
  }

  testWidgets('shows the trainer week alongside a client report', (
    tester,
  ) async {
    await openReports(tester);

    expect(find.text('리포트'), findsWidgets);
    // ① 은 지표를 나란히 세우던 비교 표가 아니라 요일 격자다(#2232).
    expect(find.text('PT 세션'), findsOneWidget);
    // 피드백 입력창은 ③ 전송 단계로 내려갔다 — ① 이번 주 확인은 읽기만
    // 하는 단계라 입력이 없다(#2232).
    expect(find.text('트레이너 피드백'), findsNothing);
    expect(find.text('다음 주'), findsNothing);
    // 칼로리·나트륨·당류를 돌려 보던 알약 줄은 물러났다 — ① 이 답하는 것은
    // `무엇을 했나` 이고, 지표를 고르는 일은 트레이너의 몫이 아니다(#2232).
    for (final metric in <String>['calories', 'sodium', 'sugar']) {
      expect(
        find.byKey(ValueKey<String>('compare-diet-$metric')),
        findsNothing,
      );
    }
    // Defaults to the first client rather than an empty right pane.
    expect(find.text('김민수님 주간 리포트'), findsOneWidget);
    // 카드 안에 회원 신상을 다시 적지 않는다 — 왼쪽 목록에서 방금 고른
    // 회원이고, 카드 제목이 이미 누구의 리포트인지 말한다(#1177).
    expect(
      find.descendant(
        of: find.byType(ClientReportView),
        matching: find.text('남성 · 35세'),
      ),
      findsNothing,
    );
  });

  testWidgets('공유는 상단에서 전송과 PDF 내보내기를 함께 보여 준다 (#735)', (tester) async {
    await openReports(tester);

    final shareAction = find.byKey(
      const ValueKey<String>('reports-share-action'),
    );
    expect(shareAction, findsOneWidget);
    expect(tester.getCenter(shareAction).dy, lessThan(88));
    // 메뉴를 열기 전에는 항목이 보이지 않는다.
    expect(find.text('PDF 내보내기'), findsNothing);

    await openShareMenu(tester);
    expect(find.text('김민수님에게 전송'), findsOneWidget);
    expect(find.text('PDF 내보내기'), findsOneWidget);
    // PDF 는 현재 리포트로 실제 binary를 만드는 경로와 연결된다.
    expect(
      tester.widget<MenuItemButton>(shareItem('PDF 내보내기')).onPressed,
      isNotNull,
    );
  });

  testWidgets('PDF 대화상자의 저장과 인쇄는 각각 플랫폼 경계를 호출한다', (tester) async {
    final actions = _RecordingPdfActions();
    final container = await openReports(
      tester,
      extraOverrides: <Override>[
        reportPdfActionsProvider.overrideWithValue(actions),
      ],
    );
    final client = (await container.read(clientsProvider.future)).first;
    final report = buildWeeklyReport(
      client: client,
      sessions: const [],
      weekStart: DateTime(2026, 8, 10),
    );
    final bytes = Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);

    showDialog<void>(
      context: tester.element(find.byType(Scaffold).last),
      builder: (_) => ReportPdfExportDialog(report: report, bytes: bytes),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('report-pdf-save')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('report-pdf-print')));
    await tester.pump();

    expect(actions.savedBytes, same(bytes));
    expect(actions.printedBytes, same(bytes));
    expect(actions.savedName, '${client.name}_2026-08-10_주간리포트.pdf');
    expect(actions.printedName, actions.savedName);
  });

  testWidgets('PDF 생성 중에는 중복을 막고 실패 후 재시도한다', (tester) async {
    final first = Completer<Uint8List>();
    final generator = _QueuedPdfGenerator(<Future<Uint8List>>[
      first.future,
      Future<Uint8List>.value(
        Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
      ),
    ]);
    await openReports(
      tester,
      extraOverrides: <Override>[
        reportPdfGeneratorProvider.overrideWithValue(generator),
      ],
    );

    await openShareMenu(tester);
    await tester.tap(shareItem('PDF 내보내기'));
    await settle(tester);
    expect(generator.calls, 1);

    await openShareMenu(tester);
    expect(
      tester.widget<MenuItemButton>(shareItem('PDF 생성 중…')).onPressed,
      isNull,
    );
    await openShareMenu(tester); // 열려 있는 메뉴를 닫는다. 재시도는 아래에서 연다.
    first.completeError(StateError('render failed'));
    await settle(tester);
    expect(find.text('PDF를 생성하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);

    // 실패가 현재 리포트를 없애지 않고, 재시도는 액션 대화상자로 이어진다.
    await openShareMenu(tester);
    await tester.tap(shareItem('PDF 내보내기'));
    await settle(tester);
    expect(generator.calls, 2);
    expect(
      find.byKey(const ValueKey<String>('report-pdf-send')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('report-pdf-save')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('report-pdf-print')),
      findsOneWidget,
    );
  });

  // ---- 요약 카드 자리와 주 이동 라벨 (#897) ----

  testWidgets('요약 카드는 ② 작성 단계에만 선다 (#2232)', (tester) async {
    await openReports(tester);
    final Finder summaryTitle = find.text('이번 주 요약');
    // ① 확인에는 없다. AI 가 내린 결론을 먼저 읽으면 자료를 보는 일이 그
    // 결론이 맞는지 확인하는 일로 바뀌어, 요약이 짚지 않은 것은 트레이너도
    // 짚지 않게 된다.
    expect(summaryTitle, findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
    await settle(tester);
    // 쓰는 자리의 출발점이라 여기에 선다. 하나뿐이다 — 둘이 서면 어느 쪽이
    // 최신인지 알 수 없다.
    expect(summaryTitle, findsOneWidget);
  });

  testWidgets('짧은 창에서도 단계 내용이 넘치지 않는다 (#1177, #2232)', (tester) async {
    await openReports(tester, size: const Size(1600, 480), stage: 1);

    expect(tester.takeException(), isNull);
    expect(find.text('이번 주 요약'), findsOneWidget);
  });

  testWidgets('좁은 화면에서도 작업대가 먼저 뜬다 (#2232)', (tester) async {
    await openReports(tester, workbench: true, size: const Size(700, 1000));

    expect(find.byType(ReportWorkbench), findsOneWidget);
    // 아직 아무도 고르지 않았으니 요약을 만들지 않는다.
    expect(find.text('피드백으로 가져오기'), findsNothing);
  });

  testWidgets('주 이동은 목록 화면에서 하고, 보고 있는 주를 적는다 (#1177, #2232)', (tester) async {
    await openReports(tester, workbench: true);

    String rangeOf(DateTime start) {
      final DateTime end = start.add(const Duration(days: 6));
      return '${start.month}월 ${start.day}일 – ${end.month}월 ${end.day}일';
    }

    final DateTime thisWeek = weekStartOf(nowKst());
    expect(find.text(rangeOf(thisWeek)), findsOneWidget);

    await tester.tap(prevWeek);
    await settle(tester);

    final DateTime lastWeek = thisWeek.subtract(const Duration(days: 7));
    expect(find.text(rangeOf(lastWeek)), findsOneWidget);
    expect(find.text(rangeOf(thisWeek)), findsNothing);

    // 오른쪽 화살표로 되돌아온다.
    await tester.tap(nextWeek);
    await settle(tester);
    expect(find.text(rangeOf(thisWeek)), findsOneWidget);
  });

  testWidgets('가장 최근 주에서는 다음 주 화살표가 죽어 있다 (#1177)', (tester) async {
    await openReports(tester, workbench: true);

    IconButton arrow(Finder finder) => tester.widget<IconButton>(finder);
    expect(arrow(nextWeek).onPressed, isNull, reason: '앞으로 갈 주가 없다');
    expect(arrow(prevWeek).onPressed, isNotNull);

    await tester.tap(prevWeek);
    await settle(tester);
    expect(arrow(nextWeek).onPressed, isNotNull);
  });

  testWidgets('`오늘` 버튼은 주 이동 줄 안에 있고 이번 주에서는 아예 감춘다 (#1177, #1245, #2232)', (
    tester,
  ) async {
    await openReports(tester, workbench: true);

    final Finder currentWeek = find.byKey(
      const ValueKey<String>('reports-go-this-week'),
    );
    // 헤더에는 더 이상 없다.
    expect(
      find.descendant(
        of: find.byType(AppWebPage),
        matching: find.widgetWithText(AppButton, '이번 주로'),
      ),
      findsNothing,
    );
    // 스케줄 탭의 `오늘` 처럼 이번 주에는 버튼 자체를 그리지 않는다 — 회색
    // 비활성이 아니라 미표시다.
    expect(currentWeek, findsNothing);

    await tester.tap(prevWeek);
    await settle(tester);

    // 스케줄 탭의 `오늘` 처럼 옮기는 대상과 같은 줄에 선다.
    expect(
      find.descendant(of: find.byType(ReportWeekNav), matching: currentWeek),
      findsOneWidget,
    );
    expect(tester.widget<AppButton>(currentWeek).onPressed, isNotNull);
    await tester.tap(currentWeek);
    await settle(tester);

    expect(currentWeek, findsNothing);
  });

  testWidgets('채팅의 리포트 카드가 가리킨 주로 열린다 (#1421)', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.reset);

    // 카드는 지나간 주를 가리킨다 — 이번 주로 열리면 트레이너가 어느 주였는지
    // 다시 찾아야 한다.
    final DateTime lastWeek = weekStartOf(
      nowKst(),
    ).subtract(const Duration(days: 7));
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.reportFor('seed-client-1', weekStart: lastWeek),
    );
    await settle(tester);

    // 편집기에는 주 표시가 없다 — 목록으로 돌아가면 그 주에 머물러 있다.
    await tester.tap(
      find.byKey(const ValueKey<String>('reports-back-to-list')),
    );
    await settle(tester);

    final DateTime weekEnd = lastWeek.add(const Duration(days: 6));
    expect(
      find.text(
        '${lastWeek.month}월 ${lastWeek.day}일 – ${weekEnd.month}월 ${weekEnd.day}일',
      ),
      findsWidgets,
    );
    // 이번 주가 아니라는 증거 — 이번 주에는 이 버튼을 아예 그리지 않는다.
    expect(
      find.byKey(const ValueKey<String>('reports-go-this-week')),
      findsOneWidget,
    );
  });

  testWidgets('`오늘` 은 날짜·화살표 뒤에 선다 (#2232)', (WidgetTester tester) async {
    await openReports(tester, workbench: true);

    await tester.tap(prevWeek);
    await settle(tester);

    final Finder currentWeek = find.byKey(
      const ValueKey<String>('reports-go-this-week'),
    );
    expect(currentWeek, findsOneWidget);
    // 읽는 순서대로 — 어느 주인지를 먼저 읽고, 돌아갈지는 그 다음이다.
    expect(
      tester.getTopLeft(currentWeek).dx,
      greaterThanOrEqualTo(tester.getTopRight(nextWeek).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('편집기에는 주 이동이 없다 — 고른 한 주를 쓰는 자리다 (#2232)', (
    WidgetTester tester,
  ) async {
    await openReports(tester);

    expect(find.byType(ReportWeekNav), findsNothing);
    expect(find.textContaining(' – '), findsNothing);
  });

  testWidgets('헤더 검색 바가 다른 탭과 같은 인라인 모양이다 (#1177)', (tester) async {
    await openReports(tester);

    // 날짜 버튼이 헤더 폭을 먹던 때에는 가운데 검색 바가 아이콘으로 접혀,
    // 리포트 탭만 다른 탭과 다른 모양이었다.
    expect(find.byKey(clientSearchFieldKey), findsOneWidget);
    expect(find.byKey(clientSearchIconKey), findsNothing);
    // 대시보드에서 보는 것과 같은 폭·같은 안내 문구다.
    final double reportsWidth = tester
        .getSize(find.byKey(clientSearchFieldKey))
        .width;
    expect(find.text('회원·목표·최근 메시지·마지막 프로그램 전송일 검색'), findsOneWidget);

    await goTo(tester, AppRoutes.dashboard);
    expect(
      tester.getSize(find.byKey(clientSearchFieldKey)).width,
      closeTo(reportsWidth, 0.5),
    );
  });

  testWidgets('좁은 화면에서도 작업대 ↔ 편집기를 오간다 (#2232)', (tester) async {
    await openReports(
      tester,
      workbench: true,
      size: const Size(700, 1000),
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            makeClient(id: 'mobile-client', name: '모바일 회원'),
          ]),
        ),
      ],
    );

    expect(find.text('모바일 회원님 주간 리포트'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('reports-back-to-list')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('reports-queue-mobile-client')),
    );
    await settle(tester);

    final back = find.byKey(const ValueKey<String>('reports-back-to-list'));
    expect(back, findsOneWidget);
    expect(find.text('모바일 회원님 주간 리포트'), findsOneWidget);
    expect(tester.getTopLeft(back).dy, lessThan(220));

    await tester.tap(back);
    await settle(tester);

    expect(back, findsNothing);
    expect(find.text('모바일 회원님 주간 리포트'), findsNothing);
    expect(find.byType(ReportWorkbench), findsOneWidget);
  });

  testWidgets('the client query parameter focuses that client', (tester) async {
    await openReports(tester, clientId: 'seed-client-3');
    expect(find.text('박성호님 주간 리포트'), findsOneWidget);
  });

  testWidgets('a failed client roster retries independently', (tester) async {
    int attempts = 0;
    await openReports(
      tester,
      clientId: 'seed-client-3',
      extraOverrides: <Override>[
        clientsProvider.overrideWith((ref) {
          attempts++;
          return attempts == 1
              ? Stream<List<TrainerClient>>.error(
                  StateError('client transport detail'),
                )
              : Stream<List<TrainerClient>>.value(<TrainerClient>[
                  makeClient(id: 'seed-client-1', name: '첫 회원'),
                  makeClient(id: 'seed-client-3', name: '복구 회원'),
                ]);
        }),
      ],
    );

    expect(find.text('리포트를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('client transport detail'), findsNothing);
    // 재시도 버튼은 공용 오류 상태 안에 있다 — 키는 그 묶음에 있다.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reports-clients-retry')),
        matching: find.byType(AppButton),
      ),
    );
    await settle(tester);

    expect(attempts, 2);
    expect(find.text('복구 회원님 주간 리포트'), findsOneWidget);
  });

  testWidgets('weekly report retry keeps the selected client and week', (
    tester,
  ) async {
    final repository = _ReportFailsOncePerKeyRepository();
    await openReports(
      tester,
      clientId: 'seed-client-3',
      weekStart: weekStartOf(nowKst()).subtract(const Duration(days: 7)),
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(repository),
      ],
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reports-weekly-retry')),
        matching: find.byType(AppButton),
      ),
    );
    await settle(tester);

    final selectedWeek = weekStartOf(
      nowKst(),
    ).subtract(const Duration(days: 7));
    final selectedCalls = repository.calls
        .where(
          (call) =>
              call.client.id == 'seed-client-3' &&
              call.weekStart == selectedWeek,
        )
        .toList();
    // Comparison/trend cards legitimately request adjacent weeks too. The
    // failed selected week itself must still be retried without losing scope.
    expect(selectedCalls.length, greaterThanOrEqualTo(2));
    expect(find.text('박성호님 주간 리포트'), findsOneWidget);
    expect(find.text('report transport detail'), findsNothing);
  });

  testWidgets('작업대에서 회원 줄을 누르면 그 회원의 편집기로 들어간다 (#2232)', (tester) async {
    await openReports(tester, workbench: true);

    // The API does not expose saved feedback status. Session-local send state
    // must not be presented as a persistent member-list status.
    expect(find.text('피드백 미작성'), findsNothing);
    expect(find.text('피드백 완료'), findsNothing);
    // 작업대는 이번 주 전 회원을 한 줄씩 세운다.
    expect(find.byType(ReportWorkbench), findsOneWidget);

    // 이미 리포트가 나간 회원(데모 기록)은 큐에 서지 않으므로, 미전송 줄
    // 하나를 고른다.
    await tester.tap(
      find.byKey(const ValueKey<String>('reports-queue-seed-client-3')),
    );
    await settle(tester);
    expect(find.text('박성호님 주간 리포트'), findsOneWidget);
  });

  testWidgets('작업대 줄은 이름과 고를 이유만 적고 이행률 막대는 두지 않는다 (#1177, #2232)', (
    tester,
  ) async {
    await openReports(
      tester,
      workbench: true,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            makeClient(
              id: 'measured',
              name: '기록회원',
              goal: '혈압 관리',
              weekCompletion: const <int>[80, 0, 60, 0, 0, 0, 0],
            ),
          ]),
        ),
      ],
    );

    // 같은 값을 편집기가 훨씬 자세히 말한다 — 고르는 자리에는 이름과 왜
    // 이 회원이 위에 있는지만 둔다.
    expect(
      find.descendant(
        of: find.byType(ReportWorkbench),
        matching: find.byType(InlineBarValue),
      ),
      findsNothing,
    );
    expect(find.text('기록회원'), findsWidgets);
  });

  testWidgets('좁은 창의 작업대 줄도 넘치지 않는다 (#2232)', (tester) async {
    await openReports(
      tester,
      workbench: true,
      size: const Size(700, 760),
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            makeClient(
              id: 'narrow',
              name: '매우긴이름의회원',
              goal: '체중 감량과 근력 향상을 함께 관리하는 목표',
              weekCompletion: const <int>[100, 100, 100, 100, 100, 100, 100],
            ),
          ]),
        ),
      ],
    );

    expect(
      find.byKey(const ValueKey<String>('reports-queue-narrow')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report previews exactly what the member will receive', (
    tester,
  ) async {
    await openReports(tester, stage: 2);

    // The preview box is the message body itself, so the trainer can
    // read it before sending rather than discovering it in the thread.
    expect(find.textContaining('주간 리포트'), findsWidgets);
    // PT 진행 횟수는 초안에서 뺐다 — 회원에게 보낼 글이 아니다(#1177).
    expect(find.textContaining('PT 세션'), findsNothing);
    // 전송 경로는 화면에 하나뿐이다 — 본문에는 더 이상 전송 버튼이 없다.
    await openShareMenu(tester);
    expect(find.text('김민수님에게 전송'), findsOneWidget);
  });

  testWidgets('empty feedback cannot be sent', (tester) async {
    await openReports(tester, stage: 2);

    await tester.enterText(feedbackField, '   ');
    await settle(tester);

    await openShareMenu(tester);
    expect(
      tester.widget<MenuItemButton>(shareItem('김민수님에게 전송')).onPressed,
      isNull,
    );
  });

  testWidgets('전송 delivers the report into the client chat thread', (
    tester,
  ) async {
    // 전송 기본 흐름이 PDF를 만들어 보낸다(#1378) — 실 `ReportPdfGenerator`는
    // dart:ui 래스터를 거쳐 fake pump 로는 settle 되지 않으니, 다른
    // PDF 관련 테스트처럼 즉시 끝나는 가짜로 바꾼다. 이 테스트가 보는 것은
    // "채팅에 도착하는가"이지 PDF 렌더링 자체가 아니다.
    final container = await openReports(
      tester,
      stage: 2,
      extraOverrides: <Override>[
        reportPdfGeneratorProvider.overrideWithValue(
          _QueuedPdfGenerator(<Future<Uint8List>>[
            Future<Uint8List>.value(
              Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
            ),
          ]),
        ),
      ],
    );
    await openShareMenu(tester);

    await tester.tap(find.text('김민수님에게 전송'));
    await settle(tester);

    // 메뉴 항목이 잠겨 두 번 보내지지 않는다.
    await openShareMenu(tester);
    expect(find.text('전송됨'), findsOneWidget);

    final messages = await tester.runAsync(
      () => container
          .read(chatRepositoryProvider)
          .watchThread('seed-client-1')
          .first,
    );
    expect(
      messages!.map((m) => m.body).where((t) => t.contains('주간 리포트')),
      isNotEmpty,
    );
  });

  testWidgets('a failed send keeps the button actionable and warns', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.reportFor('seed-client-1'),
      extraOverrides: <Override>[
        chatRepositoryProvider.overrideWith(
          (ref) => _FailingChatRepository(ref.watch(appDatabaseProvider)),
        ),
        // PDF 생성 자체는 성공해야 이 테스트가 노리는 실패(채팅 전송)만
        // 남는다 — 실 생성기는 fake pump 로 settle 되지 않는다(위 테스트와
        // 같은 이유).
        reportPdfGeneratorProvider.overrideWithValue(
          _QueuedPdfGenerator(<Future<Uint8List>>[
            Future<Uint8List>.value(
              Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
            ),
          ]),
        ),
      ],
    );
    await settle(tester);
    // 피드백 입력창은 ③ 전송 단계에 있다(#2232).
    await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
    await settle(tester);
    await openShareMenu(tester);

    await tester.tap(find.text('김민수님에게 전송'));
    await settle(tester);

    // No false "전송됨" — the trainer would otherwise believe the member
    // got a report that never arrived.
    expect(find.text('전송됨'), findsNothing);
    expect(find.text('리포트 전송에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
    // 실패해도 작성한 피드백이 남고 다시 보낼 수 있다.
    expect(
      tester.widget<TextField>(feedbackField).controller!.text,
      contains('주간 리포트'),
    );
    await openShareMenu(tester);
    expect(
      tester.widget<MenuItemButton>(shareItem('김민수님에게 전송')).onPressed,
      isNotNull,
    );
  });

  testWidgets('주를 가리키는 말은 이번 주·지난 주·선택 주 셋뿐이다', (tester) async {
    await openReports(tester, workbench: true);

    // 주 이동 줄은 주 이름 대신 **보고 있는 주의 날짜 범위**를 적는다.
    // '이전 주' 라고 쓰면 비교 카드의 '지난 주' 열과 같은 말이 되어 어느 주를
    // 보고 있는지 헷갈린다.
    expect(prevWeek, findsOneWidget);
    expect(find.textContaining(' – '), findsWidgets);
    expect(find.text('이전 주'), findsNothing);

    await tester.tap(prevWeek);
    await settle(tester);

    // 과거 주로 옮겨도 마찬가지다 — 옮긴 주를 가리키는 말은 날짜 범위뿐이다.
    expect(find.textContaining(' – '), findsWidgets);
    expect(find.text('이전 주'), findsNothing);
  });

  testWidgets('요약 카드가 안내문 대신 이번 주 요약을 말한다 (#755)', (tester) async {
    await openReports(tester, stage: 1);

    // 예전에는 이 자리에 "API 연결 후 사용할 수 있어요" 만 있었다.
    expect(
      find.text('실제 리포트 요약 API 연결 후 사용할 수 있어요. 현재 문구는 자동 생성하지 않습니다.'),
      findsNothing,
    );
    // 데모에는 모델이 없어 수치에서 조립한 문장이 온다 — 그래서 'AI 생성'
    // 배지는 달리지 않는다. 트레이너가 이 문장을 어디까지 믿을지 알아야 한다.
    expect(find.text('AI 생성'), findsNothing);
    expect(find.textContaining('운동 이행률'), findsWidgets);
  });

  testWidgets('요약 카드가 다음 주 할 일까지 적어 아래를 채운다 (#1177)', (tester) async {
    await openReports(tester, stage: 1);

    // PT 세션 수는 옆 카드 제목 줄이 이미 말한다 — 요약에서 되풀이하지 않는다.
    expect(find.textContaining('PT 세션 1/1회 완료'), findsNothing);
    // 그 자리를 수치에서 곧바로 나오는 다음 주 할 일이 가져간다. 어떤 제안이
    // 뜨는지는 그 주 수치에 달렸으므로 줄이 있다는 것만 본다 — 문구는
    // `summaryCoachingActions` 테스트가 규칙으로 확인한다.
    expect(find.text('다음 주 코칭 제안'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reports-summary-action-0')),
      findsOneWidget,
    );
  });

  testWidgets('요약을 피드백 초안으로 가져온다 (#755)', (tester) async {
    await openReports(tester, stage: 2);

    // 헤더의 통합 검색창도 TextField 다 — 피드백 입력창만 집는다.
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.minLines == 4,
    );
    final before = tester.widget<TextField>(field).controller!.text;

    await tester.ensureVisible(find.text('피드백으로 가져오기'));
    await tester.pump();
    await tester.tap(find.text('피드백으로 가져오기'));
    await settle(tester);

    final after = tester.widget<TextField>(field).controller!.text;
    expect(after, isNot(before), reason: '입력창이 요약으로 바뀌지 않았다');
    // 제목 줄과 근거가 함께 들어가야 트레이너가 손볼 재료가 된다.
    expect(after, contains('회원은'));
    expect(after, contains('· '));
  });

  testWidgets('초안이 자동으로 채워졌다고 입력창이 말해 준다 (#755)', (tester) async {
    await openReports(tester, stage: 2);

    // 회원에게 그대로 나가는 글이라, 확인하고 보내라는 신호가 그 자리에
    // 있어야 한다. 'AI' 라고 하지 않는다 — 이 초안은 수치에서 조립한
    // 템플릿이지 생성된 문장이 아니다.
    expect(
      find.text('수치에서 자동으로 채운 초안이에요. 보내기 전에 확인하고 고쳐 주세요.'),
      findsOneWidget,
    );
  });

  testWidgets('가져온 요약은 되돌리기로 가져오기 전 글로 돌아간다 (#755, #2187)', (tester) async {
    await openReports(tester, stage: 2);

    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.minLines == 4,
    );
    final draft = tester.widget<TextField>(field).controller!.text;

    // 되돌릴 것이 없으면 버튼은 꺼져 있다.
    expect(tester.widget<AppIconButton>(undoFeedback).onPressed, isNull);

    // 커서를 넣어야 편집 기록이 지금 글을 첫 단계로 잡는다.
    await tester.tap(field);
    await settle(tester);

    await tester.ensureVisible(find.text('피드백으로 가져오기'));
    await tester.pump();
    await tester.tap(find.text('피드백으로 가져오기'));
    await settle(tester);
    expect(tester.widget<TextField>(field).controller!.text, isNot(draft));

    await tester.ensureVisible(undoFeedback);
    await tester.pump();
    await tester.tap(undoFeedback);
    await settle(tester);

    expect(tester.widget<TextField>(field).controller!.text, draft);
  });

  testWidgets('요약 생성이 실패해도 카드가 안내문으로 돌아간다 (#755)', (tester) async {
    await openReports(
      stage: 1,
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(_SummaryFailsRepository()),
      ],
    );

    expect(
      find.text('실제 리포트 요약 API 연결 후 사용할 수 있어요. 현재 문구는 자동 생성하지 않습니다.'),
      findsOneWidget,
    );
  });

  // ---- 피드백 초안 저장 (#821) ----

  final Finder saveFeedback = find.byKey(
    const ValueKey<String>('report-feedback-save'),
  );

  testWidgets('피드백 저장 버튼이 켜져 있고 입력창의 현재 문구를 저장한다 (#821)', (tester) async {
    final drafts = _DraftStore();
    await openReports(
      stage: 2,
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(drafts),
      ],
    );

    expect(tester.widget<AppButton>(saveFeedback).onPressed, isNotNull);

    await tester.enterText(feedbackField, '어깨 안정화 위주로 한 주 더 갑니다.');
    await settle(tester);
    await tester.ensureVisible(saveFeedback);
    await tester.pump();
    await tester.tap(saveFeedback);
    await settle(tester);

    expect(drafts.saved, <String>['어깨 안정화 위주로 한 주 더 갑니다.']);
    expect(find.text('피드백 초안을 저장했어요.'), findsOneWidget);
  });

  testWidgets('이번 주 리포트에는 저장·되돌리기가 있다 (#1177)', (tester) async {
    await openReports(tester, stage: 2);

    expect(saveFeedback, findsOneWidget);
    expect(undoFeedback, findsOneWidget);
    expect(redoFeedback, findsOneWidget);
  });

  testWidgets('지난 주 리포트에는 저장·되돌리기가 없다 (#1177)', (tester) async {
    await openReports(
      tester,
      weekStart: weekStartOf(nowKst()).subtract(const Duration(days: 7)),
      stage: 2,
    );

    // 트레이너가 손볼 것은 이번 주에 보낼 글이다. 이미 지나간 주의 초안을
    // 저장해 둘 자리는 없다.
    expect(saveFeedback, findsNothing);
    expect(undoFeedback, findsNothing);
    expect(redoFeedback, findsNothing);
    // 글은 그대로 읽을 수 있다 — 숨긴 것은 버튼뿐이다.
    expect(feedbackField, findsOneWidget);
  });

  testWidgets('부제는 리포트를 쓰라고 하지 않고 확인해 전달하라고 말한다 (#1177)', (tester) async {
    await openReports(tester);

    expect(find.text('주간 변화를 확인하고 회원에게 전달하세요'), findsOneWidget);
  });

  testWidgets('저장에 실패해도 쓰던 문구는 입력창에 남는다 (#821)', (tester) async {
    await openReports(
      stage: 2,
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(_DraftStore(failSave: true)),
      ],
    );

    await tester.enterText(feedbackField, '저장은 실패해도 이 문구는 남아야 한다');
    await settle(tester);
    await tester.ensureVisible(saveFeedback);
    await tester.pump();
    await tester.tap(saveFeedback);
    await settle(tester);

    expect(find.text('초안을 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    // 저장하려다 잃는 것이 이 기능이 없애려던 문제다.
    expect(
      tester.widget<TextField>(feedbackField).controller!.text,
      '저장은 실패해도 이 문구는 남아야 한다',
    );
  });

  testWidgets('저장해 둔 초안이 있으면 입력창이 그 문구로 열린다 (#821)', (tester) async {
    await openReports(
      stage: 2,
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(
          _DraftStore(stored: '지난번에 쓰다 만 문구'),
        ),
      ],
    );

    expect(
      tester.widget<TextField>(feedbackField).controller!.text,
      '지난번에 쓰다 만 문구',
    );
  });

  testWidgets('되돌리기는 자동 생성본이 아니라 저장된 초안으로 돌아간다 (#821)', (tester) async {
    await openReports(
      stage: 2,
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(
          _DraftStore(stored: '저장해 둔 초안'),
        ),
      ],
    );

    // 커서를 넣어야 편집 기록이 지금 글을 첫 단계로 잡는다.
    await tester.tap(feedbackField);
    await settle(tester);
    await tester.enterText(feedbackField, '고치는 중인 문구');
    await settle(tester);

    await tester.ensureVisible(undoFeedback);
    await tester.pump();
    await tester.tap(undoFeedback);
    await settle(tester);

    expect(
      tester.widget<TextField>(feedbackField).controller!.text,
      '저장해 둔 초안',
    );
    // 처음 열린 글보다 앞은 없다.
    expect(tester.widget<AppIconButton>(undoFeedback).onPressed, isNull);
  });

  testWidgets('되돌리기·다시 실행은 편집을 한 단계씩 오간다 (#2187)', (tester) async {
    final drafts = _DraftStore(stored: '처음 문구');
    await openReports(
      stage: 2,
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(drafts),
      ],
    );

    String text() => tester.widget<TextField>(feedbackField).controller!.text;
    AppIconButton undo() => tester.widget<AppIconButton>(undoFeedback);
    AppIconButton redo() => tester.widget<AppIconButton>(redoFeedback);

    // 한 번에 전부 버리는 `초안으로 되돌리기` 는 없다.
    expect(find.text('초안으로 되돌리기'), findsNothing);
    expect(undo().tooltip, '되돌리기');
    expect(redo().tooltip, '다시 실행');
    expect(undo().onPressed, isNull);
    expect(redo().onPressed, isNull);

    // 편집 기록은 잠깐 멈출 때마다 한 단계로 쌓인다.
    // 커서를 넣어야 편집 기록이 지금 글을 첫 단계로 잡는다.
    await tester.tap(feedbackField);
    await settle(tester);
    await tester.enterText(feedbackField, '처음 문구 하나');
    await settle(tester);
    await tester.enterText(feedbackField, '처음 문구 하나 둘');
    await settle(tester);
    expect(undo().onPressed, isNotNull);
    expect(redo().onPressed, isNull);

    await tester.ensureVisible(undoFeedback);
    await tester.pump();
    await tester.tap(undoFeedback);
    await settle(tester);
    expect(text(), '처음 문구 하나');
    expect(redo().onPressed, isNotNull);

    await tester.ensureVisible(undoFeedback);
    await tester.pump();
    await tester.tap(undoFeedback);
    await settle(tester);
    expect(text(), '처음 문구');
    expect(undo().onPressed, isNull);

    await tester.ensureVisible(redoFeedback);
    await tester.pump();
    await tester.tap(redoFeedback);
    await settle(tester);
    expect(text(), '처음 문구 하나');

    // 저장은 되돌린 뒤 화면에 보이는 글을 쓴다 — 손으로 친 글자만 따라가면
    // 되돌리기 전 문구가 저장된다.
    await tester.ensureVisible(saveFeedback);
    await tester.pump();
    await tester.tap(saveFeedback);
    await settle(tester);
    expect(drafts.saved, <String>['처음 문구 하나']);
  });

  // ---- 직접 작성하기와 목표 남기기 (#2232) ----

  /// 편집기의 `직접 작성하기`.
  final Finder writeFromScratch = find.byKey(
    const ValueKey<String>('report-feedback-scratch'),
  );

  /// ② 에서 목표 하나를 직접 적어 고른다.
  Future<void> pickOwnGoal(WidgetTester tester, String goal) async {
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('report-goals-own')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('report-goals-own')),
      goal,
    );
    await tester.tap(find.byKey(const ValueKey<String>('report-goals-add')));
    await settle(tester);
  }

  testWidgets('직접 작성하기는 자동 초안을 비워 빈 화면에서 시작하게 한다 (#2232)', (tester) async {
    await openReports(tester, stage: 2);

    expect(
      tester.widget<TextField>(feedbackField).controller!.text,
      isNotEmpty,
    );

    await tester.ensureVisible(writeFromScratch);
    await tester.pump();
    await tester.tap(writeFromScratch);
    await settle(tester);

    expect(tester.widget<TextField>(feedbackField).controller!.text, isEmpty);
  });

  testWidgets('비운 초안은 되돌리기 한 번으로 돌아온다 — 잘못 누른 것을 되돌릴 수 있다 (#2232)', (
    tester,
  ) async {
    await openReports(tester, stage: 2);

    // 커서를 넣어야 편집 기록이 지금 글을 첫 단계로 잡는다.
    await tester.tap(feedbackField);
    await settle(tester);
    final String draft = tester
        .widget<TextField>(feedbackField)
        .controller!
        .text;

    await tester.ensureVisible(writeFromScratch);
    await tester.pump();
    await tester.tap(writeFromScratch);
    await settle(tester);

    await tester.ensureVisible(undoFeedback);
    await tester.pump();
    await tester.tap(undoFeedback);
    await settle(tester);

    expect(tester.widget<TextField>(feedbackField).controller!.text, draft);
  });

  testWidgets('비운 채로는 보낼 수 없다 — 빈 리포트가 회원에게 가지 않게 (#2232)', (tester) async {
    await openReports(tester, stage: 2);

    await tester.ensureVisible(writeFromScratch);
    await tester.pump();
    await tester.tap(writeFromScratch);
    await settle(tester);

    await openShareMenu(tester);
    expect(
      tester.widget<MenuItemButton>(shareItem('김민수님에게 전송')).onPressed,
      isNull,
    );
  });

  testWidgets('직접 작성하기는 피드백 카드 안, 입력창 바로 위에 선다 (#2232)', (tester) async {
    await openReports(tester, stage: 2);

    expect(writeFromScratch, findsOneWidget);
    // 초안을 정하는 다른 길(요약 가져오기)도 같은 화면에 남아 있다.
    expect(find.text('피드백으로 가져오기'), findsOneWidget);

    final Rect field = tester.getRect(feedbackField);
    final Offset scratch = tester.getCenter(writeFromScratch);
    // 고칠 글이 있는 칸의 머리에 붙어 있어야, 누르면 무엇이 비는지 보인다.
    expect(scratch.dy, lessThan(field.top));
    expect(scratch.dx, greaterThan(field.left));
    expect(scratch.dx, lessThan(field.right));
  });

  testWidgets('②에서 고른 목표는 전송과 함께 남는다 (#2232)', (tester) async {
    final _DraftStore drafts = _DraftStore();
    await openReports(
      tester,
      stage: 1,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(drafts),
        reportPdfGeneratorProvider.overrideWithValue(
          _QueuedPdfGenerator(<Future<Uint8List>>[
            Future<Uint8List>.value(
              Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
            ),
          ]),
        ),
      ],
    );

    await pickOwnGoal(tester, '화요일 저녁 15분 루틴');
    // 고르기만 해서는 아직 남지 않는다 — 보내지 않고 떠난 주의 목표까지
    // 다음 주가 회수하면, 회원이 받지도 않은 목표를 못 지켰다고 적힌다.
    expect(drafts.savedGoals, isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
    await settle(tester);
    await openShareMenu(tester);
    await tester.tap(find.text('김민수님에게 전송'));
    await settle(tester);

    expect(drafts.savedGoals, <List<String>>[
      <String>['화요일 저녁 15분 루틴'],
    ]);
  });

  testWidgets('목표를 고르지 않고 보내면 빈 목록이 남는다 — 지난 주 목표를 물려받지 않게 (#2232)', (
    tester,
  ) async {
    final _DraftStore drafts = _DraftStore();
    await openReports(
      tester,
      stage: 2,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(drafts),
        reportPdfGeneratorProvider.overrideWithValue(
          _QueuedPdfGenerator(<Future<Uint8List>>[
            Future<Uint8List>.value(
              Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
            ),
          ]),
        ),
      ],
    );

    await openShareMenu(tester);
    await tester.tap(find.text('김민수님에게 전송'));
    await settle(tester);

    expect(drafts.savedGoals, <List<String>>[<String>[]]);
  });

  testWidgets('목표 남기기가 실패해도 전송은 성공으로 남는다 (#2232)', (tester) async {
    // 회원은 이미 리포트를 받았다. 여기서 실패를 알리면 보낸 사실이 실패로
    // 읽히고, 트레이너는 같은 리포트를 한 번 더 보낸다.
    final _DraftStore drafts = _DraftStore(failGoals: true);
    await openReports(
      tester,
      stage: 2,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(drafts),
        reportPdfGeneratorProvider.overrideWithValue(
          _QueuedPdfGenerator(<Future<Uint8List>>[
            Future<Uint8List>.value(
              Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
            ),
          ]),
        ),
      ],
    );

    await openShareMenu(tester);
    await tester.tap(find.text('김민수님에게 전송'));
    await settle(tester);

    expect(find.text('리포트 전송에 실패했어요. 다시 시도해 주세요'), findsNothing);
    await openShareMenu(tester);
    expect(find.text('전송됨'), findsOneWidget);
  });
}

/// 저장한 초안을 기억하는 리포트 저장소. 리포트 본문·요약은 데모 계산을 그대로
/// 쓰고, 초안만 이 double 이 들고 있다.
class _DraftStore implements ReportRepository {
  _DraftStore({this.stored, this.failSave = false, this.failGoals = false});

  /// 화면을 열 때 이미 저장돼 있는 초안. null 이면 저장한 적 없는 주다.
  final String? stored;
  final bool failSave;

  /// 목표 남기기가 실패하는 주 — 전송은 이미 끝난 뒤다.
  final bool failGoals;
  final List<String> saved = <String>[];

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) => Stream<WeeklyReport>.value(
    buildWeeklyReport(client: client, sessions: const [], weekStart: weekStart),
  );

  @override
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
    required AppLocalizations l,
  }) async => ruleReportSummary(
    l,
    buildWeeklyReport(client: client, sessions: const [], weekStart: weekStart),
    client,
  );

  @override
  Future<void> send({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) async {}

  @override
  Future<void> sendPdf({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async {}

  @override
  Future<ReportFeedbackDraft> feedbackDraft({
    required TrainerClient client,
    required DateTime weekStart,
  }) async {
    final String? body = saved.isNotEmpty ? saved.last : stored;
    if (body == null) return const ReportFeedbackDraft.none();
    return ReportFeedbackDraft(body: body, saved: true);
  }

  @override
  Future<ReportFeedbackDraft> saveFeedbackDraft({
    required String clientId,
    required DateTime weekStart,
    required String body,
  }) async {
    if (failSave) throw StateError('draft save failed');
    saved.add(body);
    return ReportFeedbackDraft(body: body, saved: true);
  }

  /// ② 에서 고른 목표가 전송과 함께 남는지 보는 자리.
  final List<List<String>> savedGoals = <List<String>>[];

  @override
  Future<void> saveNextWeekGoals({
    required String clientId,
    required DateTime weekStart,
    required List<String> goals,
  }) async {
    if (failGoals) throw StateError('goal save failed');
    savedGoals.add(List<String>.of(goals));
  }
}

class _RecordingPdfActions implements ReportPdfActions {
  Uint8List? savedBytes;
  Uint8List? printedBytes;
  String? savedName;
  String? printedName;

  @override
  Future<void> save(Uint8List bytes, String fileName) async {
    savedBytes = bytes;
    savedName = fileName;
  }

  @override
  Future<void> print(Uint8List bytes, String fileName) async {
    printedBytes = bytes;
    printedName = fileName;
  }
}

class _QueuedPdfGenerator extends ReportPdfGenerator {
  _QueuedPdfGenerator(this._results);

  final List<Future<Uint8List>> _results;
  int calls = 0;

  @override
  Future<Uint8List> generate({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) {
    final result = _results[calls];
    calls++;
    return result;
  }
}

/// Chat repository whose sends always fail.
class _FailingChatRepository extends DriftChatRepository {
  const _FailingChatRepository(super.db);

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
    String? emoteId,
  }) async {
    throw StateError('send failed');
  }
}
