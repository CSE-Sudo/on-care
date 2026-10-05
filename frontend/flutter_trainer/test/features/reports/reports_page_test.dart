import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue_summary.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/pages/reports_page.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/client_report_view.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_send_preview.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_nav.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_printer.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/progress_bar_finder.dart';
import '../../helpers/pump_app.dart';

/// 요약 생성만 실패한다 — 리포트 본문은 정상이라 카드 하나만 폴백으로 간다.
class _SummaryFailsRepository implements ReportRepository {
  @override
  Future<List<ReportSendRecord>> sentReports({
    required DateTime weekStart,
  }) async => const <ReportSendRecord>[];

  @override
  Future<MemberReportHistoryPage> memberReportHistory({
    required String clientId,
    DateTime? before,
    int limit = memberReportHistoryPageSize,
  }) async => const MemberReportHistoryPage.empty();

  @override
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) => reportQueueFromReports(this, clients: clients, weekStart: weekStart);

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
}

class _ReportFailsOncePerKeyRepository implements ReportRepository {
  final Map<String, int> _attempts = <String, int>{};
  final List<ReportKey> calls = <ReportKey>[];

  @override
  Future<List<ReportSendRecord>> sentReports({
    required DateTime weekStart,
  }) async => const <ReportSendRecord>[];

  @override
  Future<MemberReportHistoryPage> memberReportHistory({
    required String clientId,
    DateTime? before,
    int limit = memberReportHistoryPageSize,
  }) async => const MemberReportHistoryPage.empty();

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
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) => reportQueueFromReports(this, clients: clients, weekStart: weekStart);

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) {
    final key = '${client.id}/${weekStart.toIso8601String()}';
    calls.add(ReportKey(client: client, weekStart: weekStart));
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
}

/// 리포트 against the seeded roster — the trainer's own week plus one
/// client's report, and sending it into their chat thread.
void main() {
  /// 편집기 하단의 `전송` 버튼. 헤더 공유 메뉴가 물러난 뒤(#2389) 회원에게
  /// 리포트를 보내는 길은 이것 하나뿐이다.
  final Finder sendButton = find.byKey(
    const ValueKey<String>('report-step-send'),
  );

  /// 하단 `전송` 버튼을 누른다.
  Future<void> tapSend(WidgetTester tester) async {
    await tester.ensureVisible(sendButton);
    await tester.pump();
    await tester.tap(sendButton);
    await settle(tester);
  }

  /// 하단 `전송` 버튼이 눌리는가.
  bool sendEnabled(WidgetTester tester) =>
      tester.widget<AppButton>(sendButton).onPressed != null;

  /// ③ 전송의 회원 수신 PDF 미리보기(#2402).
  final Finder preview = find.byKey(
    const ValueKey<String>('report-send-preview'),
  );
  final Finder previewLoading = find.byKey(
    const ValueKey<String>('report-send-preview-loading'),
  );
  final Finder previewFailed = find.byKey(
    const ValueKey<String>('report-send-preview-failed'),
  );

  /// 미리보기가 지금 보여 주는 쪽 — `1 / 3쪽`.
  String? pageLabel(WidgetTester tester) => tester
      .widget<Text>(
        find.byKey(const ValueKey<String>('report-send-preview-page-label')),
      )
      .data;

  /// 보낸 뒤 돌아온 작업대의 `전송 완료` 열에 [clientId] 가 섰는가.
  Finder sentRow(String clientId) =>
      find.byKey(ValueKey<String>('reports-sent-$clientId'));

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
  /// `WeekRangeNav` 의 화살표라 키 대신 주 이동 안의 아이콘 버튼으로 찾는다.
  final Finder prevWeek = find.descendant(
    of: find.byType(ReportWeekNav),
    matching: find.widgetWithIcon(IconButton, AppIcons.chevronLeft),
  );
  final Finder nextWeek = find.descendant(
    of: find.byType(ReportWeekNav),
    matching: find.widgetWithIcon(IconButton, AppIcons.chevronRight),
  );

  /// 리포트 탭을 연다.
  ///
  /// 탭의 첫 화면은 **작업대**다(#2232). 리포트 본문을 보는 테스트가 대부분
  /// 이라, 따로 말하지 않으면 한 회원의 편집기로 바로 들어간다 — 작업대
  /// 자체를 보는 테스트만 [workbench] 를 켠다. [stage] 는 편집기의 단계
  /// (0 확인 · 1 작성 · 2 전송)다.
  Future<ProviderContainer> openReports(
    WidgetTester tester, {
    String? clientId,
    bool workbench = false,
    DateTime? weekStart,
    int stage = 0,
    Size size = const Size(1600, 1200),
    ReportPdfGenerator? pdf,
    _FakeRasterizer? raster,
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
      // ③ 전송은 들어서자마자 PDF 를 만들어 보여 준다(#2402). 실 생성기는
      // dart:ui 래스터를 거쳐 fake pump 로는 끝나지 않고, 쪽 그림을 굽는
      // printing 플러그인은 테스트에 없어 둘 다 가짜로 둔다.
      extraOverrides: <Override>[
        reportPdfGeneratorProvider.overrideWithValue(
          pdf ?? _QueuedPdfGenerator(const <Future<Uint8List>>[]),
        ),
        reportPdfRasterizerProvider.overrideWithValue(
          (raster ?? _FakeRasterizer()).call,
        ),
        ...extraOverrides,
      ],
    );
    if (!workbench && stage > 0) {
      await settle(tester);
      for (int i = 0; i < stage; i++) {
        await tester.tap(
          find.byKey(const ValueKey<String>('report-step-next')),
        );
        // pumpAndSettle 은 쓰지 않는다 — 미리보기를 만드는 동안 도는
        // 스피너가 끝나지 않는다.
        await settle(tester);
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
    expect(find.text('PT'), findsOneWidget);
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
        matching: find.text('남성 · 36세'),
      ),
      findsNothing,
    );
  });

  testWidgets('헤더에는 공유 버튼이 없다 — 전송은 편집기 하단 하나뿐 (#2389)', (tester) async {
    await openReports(tester);

    expect(
      find.byKey(const ValueKey<String>('reports-share-action')),
      findsNothing,
    );
    expect(find.text('공유'), findsNothing);
    expect(find.text('PDF 내보내기'), findsNothing);
    // ① 확인에서는 아직 보낼 단계가 아니다.
    expect(sendButton, findsNothing);
  });

  testWidgets('작업대 헤더에도 공유 버튼이 없다 (#2389)', (tester) async {
    await openReports(tester, workbench: true);

    expect(
      find.byKey(const ValueKey<String>('reports-share-action')),
      findsNothing,
    );
    expect(find.text('공유'), findsNothing);
  });

  testWidgets('③ 전송 단계에서 하단 전송 버튼이 선다 (#2389)', (tester) async {
    await openReports(tester, stage: 2);

    expect(sendButton, findsOneWidget);
    expect(find.text('김민수님에게 전송'), findsNothing);
    expect(sendEnabled(tester), isTrue);
    // 하단 줄에 선다 — 헤더(위 88px 안)가 아니다.
    expect(tester.getCenter(sendButton).dy, greaterThan(88));
  });

  testWidgets('미리보기를 만들지 못한 채 전송하면 새로 만들어 보낸다 (#2389, #2402)', (tester) async {
    final Completer<Uint8List> first = Completer<Uint8List>();
    final _DraftStore drafts = _DraftStore();
    final _QueuedPdfGenerator generator = _QueuedPdfGenerator(
      <Future<Uint8List>>[first.future],
    );
    await openReports(
      tester,
      stage: 2,
      pdf: generator,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(drafts),
      ],
    );
    expect(generator.calls, 1);

    first.completeError(StateError('render failed'));
    await settle(tester);
    expect(previewFailed, findsOneWidget);
    // 미리보기가 실패해도 보내는 길은 막지 않는다 — 전송이 다시 만든다.
    expect(sendEnabled(tester), isTrue);

    await tapSend(tester);
    expect(generator.calls, 2);
    expect(drafts.sentBytes, <List<int>>[_pdfBytes]);
    expect(sentRow('seed-client-1'), findsOneWidget);
  });

  testWidgets('PDF 를 만드는 중에는 전송 버튼이 잠겨 두 번 나가지 않는다 (#2389, #2402)', (
    tester,
  ) async {
    final Completer<Uint8List> first = Completer<Uint8List>();
    final _QueuedPdfGenerator generator = _QueuedPdfGenerator(
      <Future<Uint8List>>[first.future],
    );
    await openReports(tester, stage: 2, pdf: generator);

    await tester.ensureVisible(sendButton);
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pump();
    // 미리보기로 만들고 있는 한 부를 기다린다 — 새로 만들지 않는다.
    expect(generator.calls, 1);
    expect(sendEnabled(tester), isFalse);

    first.complete(Uint8List.fromList(_pdfBytes));
    await settle(tester);
    expect(generator.calls, 1);
    expect(sentRow('seed-client-1'), findsOneWidget);
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

  testWidgets('`오늘` 은 날짜 뒤, 두 화살표 안쪽에 선다 (#2232, #2536)', (
    WidgetTester tester,
  ) async {
    await openReports(tester, workbench: true);
    final Rect prevBefore = tester.getRect(prevWeek);
    final Rect nextBefore = tester.getRect(nextWeek);

    await tester.tap(prevWeek);
    await settle(tester);

    final Finder currentWeek = find.byKey(
      const ValueKey<String>('reports-go-this-week'),
    );
    expect(currentWeek, findsOneWidget);
    final Finder dateLabel = find.descendant(
      of: find.byType(ReportWeekNav),
      matching: find.textContaining('월'),
    );
    // 읽는 순서대로 — 어느 주인지를 먼저 읽고, 돌아갈지는 그 다음이다.
    expect(
      tester.getTopLeft(currentWeek).dx,
      greaterThanOrEqualTo(tester.getTopRight(dateLabel).dx),
    );
    // 버튼은 두 화살표 사이의 고정 자리에 앉는다 — 나타나도 화살표가
    // 움직이지 않는다(#2536).
    expect(
      tester.getTopRight(currentWeek).dx,
      lessThanOrEqualTo(tester.getTopLeft(nextWeek).dx),
    );
    expect(tester.getRect(prevWeek), prevBefore);
    expect(tester.getRect(nextWeek), nextBefore);
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
      find.byKey(const ValueKey<String>('reports-open-mobile-client')),
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

  testWidgets('작업대에서 회원 줄의 열기를 누르면 그 회원의 편집기로 들어간다 (#2232)', (tester) async {
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
      find.byKey(const ValueKey<String>('reports-open-seed-client-3')),
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
    // 범위는 회원 줄이다 — 작업대 머리의 전송 진행 막대(#2395)는 회원이 아니라
    // 그 주의 일을 재므로 여기에 걸리지 않는다. 줄이 없어도 아래 `findsNothing`
    // 은 통과하므로 먼저 떠 있는지 본다.
    final Finder row = find.byKey(
      const ValueKey<String>('reports-queue-measured'),
    );
    expect(row, findsOneWidget);
    expect(findProgressBars(of: row), findsNothing);
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
    final _QueuedPdfGenerator pdf = _QueuedPdfGenerator(<Future<Uint8List>>[
      Future<Uint8List>.value(Uint8List.fromList(<int>[1, 2, 3])),
    ]);
    final _FakeRasterizer raster = _FakeRasterizer(pages: 3);
    await openReports(tester, stage: 1, pdf: pdf, raster: raster);
    final String draft = tester
        .widget<TextField>(feedbackField)
        .controller!
        .text;
    await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
    await settle(tester);

    // 받는 사람·대상 주·전달 방식을 먼저 적는다(#2402).
    expect(find.text('회원이 받는 리포트'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('report-send-preview-recipient')),
          )
          .data,
      '김민수',
    );
    final DateTime week = weekStartOf(nowKst());
    final DateTime weekEnd = week.add(const Duration(days: 6));
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('report-send-preview-week')),
          )
          .data,
      '${week.month}월 ${week.day}일 – ${weekEnd.month}월 ${weekEnd.day}일',
    );
    expect(find.text('김민수님 채팅으로 PDF 파일이 전송돼요'), findsOneWidget);
    // 보여 주는 것은 전송과 같은 생성기가 입력창의 글로 만든 PDF 다.
    expect(pdf.calls, 1);
    expect(pdf.feedbacks, <String>[draft]);
    expect(raster.inputs, <List<int>>[
      <int>[1, 2, 3],
    ]);
    expect(
      find.byKey(const ValueKey<String>('report-send-preview-page-0')),
      findsOneWidget,
    );
    expect(pageLabel(tester), '1 / 3쪽');
    // 전송 경로는 화면에 하나뿐이다 — 편집기 하단의 전송 버튼(#2389).
    expect(sendButton, findsOneWidget);
  });

  testWidgets('empty feedback cannot be sent', (tester) async {
    await openReports(tester, stage: 1);

    await tester.enterText(feedbackField, '   ');
    await settle(tester);
    // 글은 ② 에서 쓰고, 보내는 것은 ③ 이다(#2402).
    await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
    await settle(tester);

    expect(sendEnabled(tester), isFalse);
    // 잠긴 이유를 버튼이 말한다.
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == '피드백을 입력하면 전송할 수 있어요',
      ),
      findsOneWidget,
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
      pdf: _QueuedPdfGenerator(<Future<Uint8List>>[
        Future<Uint8List>.value(
          Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
        ),
      ]),
    );
    await tapSend(tester);

    // 보내고 나면 작업대로 돌아가고, 그 회원은 `전송 완료` 열에 선다.
    expect(sentRow('seed-client-1'), findsOneWidget);

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
        reportPdfRasterizerProvider.overrideWithValue(_FakeRasterizer().call),
      ],
    );
    await settle(tester);
    // 전송 버튼은 ③ 전송 단계에 있다(#2232).
    await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
    await settle(tester);
    await tapSend(tester);

    // No false "sent" — the trainer would otherwise believe the member
    // got a report that never arrived.
    expect(sentRow('seed-client-1'), findsNothing);
    expect(find.text('리포트 전송에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
    // 실패해도 ③ 에 머물러 다시 보낼 수 있고, 작성한 피드백도 남아 있다.
    expect(preview, findsOneWidget);
    expect(sendEnabled(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('report-step-prev')));
    await settle(tester);
    expect(
      tester.widget<TextField>(feedbackField).controller!.text,
      contains('주간 리포트'),
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
    // 데모는 모델 대신 미리 써 둔 고정본을 생성 요약으로 보여 준다(#2669) —
    // 실서버에서 늘 보이는 'AI 생성' 배지가 데모에서도 보인다.
    expect(find.text('AI 생성'), findsOneWidget);
    // 근거 줄은 규칙 요약의 것이고, 데모도 회원이 적어 둔 목표로 판정한다.
    expect(find.textContaining('개인 목표'), findsWidgets);
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
    await openReports(tester, stage: 1);

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
    // 제목 줄과 근거가 함께 들어가야 트레이너가 손볼 재료가 된다. 데모 제목
    // 줄은 회원 이름으로 시작하는 고정본이다(#2669).
    expect(after, contains('님'));
    expect(after, contains('· '));
  });

  testWidgets('초안이 자동으로 채워졌다고 입력창이 말해 준다 (#755)', (tester) async {
    await openReports(tester, stage: 1);

    // 회원에게 그대로 나가는 글이라, 확인하고 보내라는 신호가 그 자리에
    // 있어야 한다. 'AI' 라고 하지 않는다 — 이 초안은 수치에서 조립한
    // 템플릿이지 생성된 문장이 아니다.
    expect(
      find.text('수치에서 자동으로 채운 초안이에요. 보내기 전에 확인하고 고쳐 주세요.'),
      findsOneWidget,
    );
  });

  testWidgets('가져온 요약은 되돌리기로 가져오기 전 글로 돌아간다 (#755, #2187)', (tester) async {
    await openReports(tester, stage: 1);

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

  testWidgets('요약 생성이 실패해도 카드가 비지 않고 실패와 다시 시도를 띄운다 (#755, #2885)', (
    tester,
  ) async {
    await openReports(
      stage: 1,
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(_SummaryFailsRepository()),
      ],
    );

    expect(find.text('요약을 만들지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reports-ai-retry')),
      findsOneWidget,
    );
    // 예전 안내문으로 되돌아가지 않는다 — 그 문구는 실패를 말하지 않는다.
    expect(
      find.text('실제 리포트 요약 API 연결 후 사용할 수 있어요. 현재 문구는 자동 생성하지 않습니다.'),
      findsNothing,
    );
  });

  // ---- 피드백 초안 저장 (#821) ----

  final Finder saveFeedback = find.byKey(
    const ValueKey<String>('report-feedback-save'),
  );

  testWidgets('피드백 저장 버튼이 켜져 있고 입력창의 현재 문구를 저장한다 (#821)', (tester) async {
    final drafts = _DraftStore();
    await openReports(
      stage: 1,
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
    await openReports(tester, stage: 1);

    expect(saveFeedback, findsOneWidget);
    expect(undoFeedback, findsOneWidget);
    expect(redoFeedback, findsOneWidget);
  });

  testWidgets('지난 주 리포트에는 저장·되돌리기가 없다 (#1177)', (tester) async {
    await openReports(
      tester,
      weekStart: weekStartOf(nowKst()).subtract(const Duration(days: 7)),
      stage: 1,
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
      stage: 1,
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
      stage: 1,
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
      stage: 1,
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
      stage: 1,
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

  // ---- 직접 작성하기 (#2232) ----

  /// 편집기의 `직접 작성하기`.
  final Finder writeFromScratch = find.byKey(
    const ValueKey<String>('report-feedback-scratch'),
  );

  testWidgets('직접 작성하기는 자동 초안을 비워 빈 화면에서 시작하게 한다 (#2232)', (tester) async {
    await openReports(tester, stage: 1);

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
    await openReports(tester, stage: 1);

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
    await openReports(tester, stage: 1);

    await tester.ensureVisible(writeFromScratch);
    await tester.pump();
    await tester.tap(writeFromScratch);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
    await settle(tester);

    expect(sendEnabled(tester), isFalse);
  });

  testWidgets('직접 작성하기는 피드백 카드 안, 입력창 바로 위에 선다 (#2232)', (tester) async {
    await openReports(tester, stage: 1);

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

  // ---- 목표 고르기·지난 주 목표 달성 삭제 (#2400) ----

  /// 편집기에 서 있는 카드 번호들, 위에서부터.
  List<int?> cardNumbers(WidgetTester tester) => tester
      .widgetList<AppSectionHeader>(find.byType(AppSectionHeader))
      .map((AppSectionHeader h) => h.number)
      .where((int? n) => n != null)
      .toList();

  testWidgets('① 확인에는 지난 주 목표 달성 카드가 없고 번호가 1·2·3 으로 이어진다 (#2400)', (
    tester,
  ) async {
    await openReports(tester);

    expect(find.text('지난 주 목표 달성'), findsNothing);
    expect(find.text('지난 주에 고른 목표가 없어요'), findsNothing);
    // 회원의 답 · 이번 주 수치 · 운동 추세 — 빠진 자리 없이 이어진다.
    expect(find.text('PT'), findsOneWidget);
    expect(cardNumbers(tester), <int>[1, 2, 3]);
  });

  testWidgets('② 작성에는 요약과 입력창만 서고 다음 주 목표 고르기가 없다 (#2400)', (tester) async {
    await openReports(tester, stage: 1);

    expect(find.text('이번 주 요약'), findsOneWidget);
    expect(feedbackField, findsOneWidget);
    expect(find.text('다음 주 목표'), findsNothing);
    expect(find.text('직접 적기'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('report-goals-card')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('report-goals-own')),
      findsNothing,
    );
    // 번호 카드는 ① 의 것이라 여기에는 없다.
    expect(cardNumbers(tester), isEmpty);
  });

  testWidgets('③ 전송에는 고른 목표를 되짚는 카드가 없다 (#2400)', (tester) async {
    await openReports(tester, stage: 2);

    expect(preview, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('report-goals-recap')),
      findsNothing,
    );
    expect(find.text('다음 주 목표'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('report-step-send')),
      findsOneWidget,
    );
  });

  testWidgets('단계 이름은 확인 · 작성 · 보내기다 (#2400, #2479)', (tester) async {
    await openReports(tester);

    expect(find.text('확인'), findsWidgets);
    expect(find.text('작성'), findsWidgets);
    expect(find.text('보내기'), findsWidgets);
  });

  testWidgets('보낸 글과 PDF 에는 입력창의 문구만 실린다 — 목표 목록이 붙지 않는다 (#2400)', (
    tester,
  ) async {
    final _DraftStore drafts = _DraftStore();
    final _QueuedPdfGenerator pdf = _QueuedPdfGenerator(<Future<Uint8List>>[
      Future<Uint8List>.value(
        Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
      ),
    ]);
    await openReports(
      tester,
      stage: 1,
      pdf: pdf,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(drafts),
      ],
    );

    const String feedback = '이번 주 하체 루틴 잘 따라오셨어요.';
    await tester.enterText(feedbackField, feedback);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
    await settle(tester);
    await tapSend(tester);

    expect(drafts.sentMessages, <String>[feedback]);
    expect(pdf.feedbacks, <String>[feedback]);
    for (final String text in <String>[
      ...drafts.sentMessages,
      ...pdf.feedbacks,
    ]) {
      expect(text, isNot(contains('다음 주 목표')));
      expect(text, isNot(contains('· ')));
    }
  });

  testWidgets('자동 초안 그대로 보내도 목표 목록이 붙지 않는다 (#2400)', (tester) async {
    final _DraftStore drafts = _DraftStore();
    final _QueuedPdfGenerator pdf = _QueuedPdfGenerator(<Future<Uint8List>>[
      Future<Uint8List>.value(
        Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
      ),
    ]);
    await openReports(
      tester,
      stage: 1,
      pdf: pdf,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(drafts),
      ],
    );

    final String draft = tester
        .widget<TextField>(feedbackField)
        .controller!
        .text;
    await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
    await settle(tester);
    await tapSend(tester);

    // 입력창에 떠 있던 글이 한 글자도 더해지지 않고 그대로 나간다.
    expect(drafts.sentMessages, <String>[draft]);
    expect(pdf.feedbacks, <String>[draft]);
  });

  // ---- ③ 전송 — 회원이 받는 PDF 미리보기 (#2402) ----

  /// 편집기 하단의 `다음` / `이전`.
  Future<void> step(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>('report-step-$key')));
    await settle(tester);
  }

  testWidgets('③ 에는 요약 카드와 피드백 입력창이 없고 미리보기만 선다 (#2402)', (tester) async {
    await openReports(tester, stage: 2);

    expect(preview, findsOneWidget);
    expect(feedbackField, findsNothing);
    expect(find.text('이번 주 요약'), findsNothing);
    expect(find.text('피드백으로 가져오기'), findsNothing);
    expect(find.byType(ClientReportView), findsNothing);
    // 고치려면 ② 로 돌아가라고 그 자리에서 말한다.
    expect(find.text('글을 고치려면 이전을 눌러 작성 단계로 돌아가세요'), findsOneWidget);
  });

  testWidgets('② 에서 글을 고치고 돌아오면 미리보기를 새로 만든다 (#2402)', (tester) async {
    final _DraftStore drafts = _DraftStore();
    final _QueuedPdfGenerator pdf = _QueuedPdfGenerator(
      const <Future<Uint8List>>[],
    );
    final _FakeRasterizer raster = _FakeRasterizer();
    await openReports(
      tester,
      stage: 2,
      pdf: pdf,
      raster: raster,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(drafts),
      ],
    );
    expect(pdf.calls, 1);

    await step(tester, 'prev');
    const String edited = '다음 주는 상체 위주로 가 볼게요.';
    await tester.enterText(feedbackField, edited);
    await settle(tester);
    await step(tester, 'next');

    expect(pdf.calls, 2);
    expect(pdf.feedbacks.last, edited);
    expect(raster.inputs, hasLength(2));

    // 고친 것이 없으면 다시 만들지 않는다.
    await step(tester, 'prev');
    await step(tester, 'next');
    expect(pdf.calls, 2);

    // 보내는 것도 마지막 미리보기 그 한 부다.
    await tapSend(tester);
    expect(pdf.calls, 2);
    expect(drafts.sentMessages, <String>[edited]);
    expect(drafts.sentBytes, <List<int>>[_pdfBytes]);
  });

  group('같은 재료면 다시 만들지 않는다 (#2484)', () {
    Future<(_StreamedReports, _QueuedPdfGenerator, _FakeRasterizer)> openSend(
      WidgetTester tester,
    ) async {
      final _StreamedReports reports = _StreamedReports();
      addTearDown(reports.close);
      final _QueuedPdfGenerator pdf = _QueuedPdfGenerator(
        const <Future<Uint8List>>[],
      );
      final _FakeRasterizer raster = _FakeRasterizer();
      await openReports(
        tester,
        stage: 2,
        pdf: pdf,
        raster: raster,
        extraOverrides: <Override>[
          reportRepositoryProvider.overrideWithValue(reports),
        ],
      );
      return (reports, pdf, raster);
    }

    testWidgets('내용이 같은 리포트가 새 객체로 다시 와도 PDF 를 다시 만들지 않는다', (tester) async {
      final (reports, pdf, raster) = await openSend(tester);
      expect(pdf.calls, 1);
      expect(raster.inputs, hasLength(1));

      // 스트림이 같은 내용을 새 객체로 두 번 더 보낸다 — 데모의 drift 스트림이
      // 일정 표가 건드려질 때마다 그렇게 한다.
      reports.pushSame();
      await settle(tester);
      reports.pushSame();
      await settle(tester);

      expect(pdf.calls, 1);
      expect(raster.inputs, hasLength(1));
      expect(previewLoading, findsNothing);
      expect(preview, findsOneWidget);
    });

    testWidgets('수치가 바뀐 리포트가 오면 새로 만든다', (tester) async {
      final (reports, pdf, raster) = await openSend(tester);
      expect(pdf.calls, 1);

      reports.pushChanged();
      await settle(tester);

      expect(pdf.calls, 2);
      expect(raster.inputs, hasLength(2));
    });

    testWidgets('같은 내용이 다시 와도 전송은 떠 있는 한 부를 보낸다', (tester) async {
      final (reports, pdf, _) = await openSend(tester);

      reports.pushSame();
      await settle(tester);
      await tapSend(tester);

      expect(pdf.calls, 1);
      expect(reports.sentBytes, <List<int>>[_pdfBytes]);
    });
  });

  testWidgets('단계 표시로 ③ 에 다시 들어와도 고친 글로 새로 만든다 (#2402)', (tester) async {
    final _QueuedPdfGenerator pdf = _QueuedPdfGenerator(
      const <Future<Uint8List>>[],
    );
    await openReports(tester, stage: 2, pdf: pdf);

    await tester.tap(find.byKey(const ValueKey<String>('report-stage-1')));
    await settle(tester);
    await tester.enterText(feedbackField, '고친 문구');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('report-stage-2')));
    await settle(tester);

    expect(pdf.calls, 2);
    expect(pdf.feedbacks.last, '고친 문구');
  });

  testWidgets('미리보기를 만드는 동안과 실패했을 때를 보여 주고 다시 만들 수 있다 (#2402)', (tester) async {
    final Completer<Uint8List> first = Completer<Uint8List>();
    final Completer<Uint8List> second = Completer<Uint8List>();
    final _QueuedPdfGenerator pdf = _QueuedPdfGenerator(<Future<Uint8List>>[
      first.future,
      second.future,
    ]);
    await openReports(tester, stage: 2, pdf: pdf);

    expect(previewLoading, findsOneWidget);
    expect(find.text('미리보기를 만드는 중이에요'), findsOneWidget);
    expect(previewFailed, findsNothing);

    first.completeError(StateError('render failed'));
    await settle(tester);
    expect(previewLoading, findsNothing);
    expect(previewFailed, findsOneWidget);
    expect(find.text('미리보기를 만들지 못했어요'), findsOneWidget);

    await tester.tap(
      find.descendant(of: previewFailed, matching: find.text('다시 시도')),
    );
    await settle(tester);
    expect(pdf.calls, 2);
    // 다시 만드는 동안에는 지난 실패를 두지 않는다.
    expect(previewLoading, findsOneWidget);
    expect(previewFailed, findsNothing);

    second.complete(Uint8List.fromList(_pdfBytes));
    await settle(tester);
    expect(previewLoading, findsNothing);
    expect(
      find.byKey(const ValueKey<String>('report-send-preview-page-0')),
      findsOneWidget,
    );
  });

  testWidgets('쪽을 넘기고 확대·축소한다 (#2402)', (tester) async {
    await openReports(tester, stage: 2, raster: _FakeRasterizer());

    AppIconButton button(String key) => tester.widget<AppIconButton>(
      find.byKey(ValueKey<String>('report-send-preview-$key')),
    );
    double pageWidth() => tester
        .getSize(
          find.byKey(const ValueKey<String>('report-send-preview-page-0')),
        )
        .width;

    expect(pageLabel(tester), '1 / 2쪽');
    expect(button('prev').onPressed, isNull);
    expect(button('zoom-out').onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('report-send-preview-next')),
    );
    await settle(tester);
    expect(pageLabel(tester), '2 / 2쪽');
    expect(
      find.byKey(const ValueKey<String>('report-send-preview-page-1')),
      findsOneWidget,
    );
    expect(button('next').onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('report-send-preview-prev')),
    );
    await settle(tester);
    expect(pageLabel(tester), '1 / 2쪽');

    final double before = pageWidth();
    await tester.tap(
      find.byKey(const ValueKey<String>('report-send-preview-zoom-in')),
    );
    await settle(tester);
    expect(pageWidth(), greaterThan(before));
    expect(button('zoom-out').onPressed, isNotNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('report-send-preview-zoom-out')),
    );
    await settle(tester);
    expect(pageWidth(), before);
  });

  group('편집기 머리 (#2449)', () {
    Finder historyButton() =>
        find.byKey(const ValueKey<String>('reports-editor-history'));

    testWidgets('초안 없이 직접 쓰기 버튼이 없다', (tester) async {
      await openReports(tester);

      expect(
        find.byKey(const ValueKey<String>('report-skip-to-write')),
        findsNothing,
      );
      expect(find.text('초안 없이 직접 쓰기'), findsNothing);
    });

    testWidgets('지난 리포트는 예약 슬롯과 같은 네이비 외곽선 버튼이다', (tester) async {
      await openReports(tester);

      final AppButton button = tester.widget<AppButton>(historyButton());
      expect(button.variant, AppButtonVariant.strongOutline);
      expect(button.leadingIcon, isNotNull);
      expect(button.label, '지난 리포트');
    });

    testWidgets('지난 리포트는 머리 줄 맨 오른쪽에 선다', (tester) async {
      await openReports(tester);

      final Rect history = tester.getRect(historyButton());
      final Rect back = tester.getRect(
        find.byKey(const ValueKey<String>('reports-back-to-list')),
      );
      expect(history.left, greaterThan(back.right));
      // 같은 줄이다.
      expect((history.center.dy - back.center.dy).abs(), lessThan(8));
      // 편집기 오른쪽 끝에 붙는다 — 단계 표시줄의 마지막 원보다 오른쪽.
      final Rect lastStep = tester.getRect(
        find.byKey(const ValueKey<String>('report-stage-2')),
      );
      expect(history.right, greaterThan(lastStep.right));
    });

    testWidgets('단계 원 사이가 공용 기본 간격의 두 배다', (tester) async {
      await openReports(tester);

      final double centers =
          tester
              .getCenter(find.byKey(const ValueKey<String>('report-stage-1')))
              .dx -
          tester
              .getCenter(find.byKey(const ValueKey<String>('report-stage-0')))
              .dx;
      expect(
        centers - OnCareSize.avatarMedium,
        closeTo(AppStepIndicator.numberedGap * 2, 0.01),
      );
      expect(reportStepperGap, AppStepIndicator.numberedGap * 2);
    });

    testWidgets('좁은 창에서도 머리 줄이 넘치지 않는다', (tester) async {
      await openReports(tester, size: const Size(700, 1000));

      expect(tester.takeException(), isNull);
      expect(historyButton(), findsOneWidget);
    });
  });

  testWidgets('③ 의 전송 버튼은 글이 있을 때만 켜진다 — 미리보기 상태와 무관하다 (#2402)', (
    tester,
  ) async {
    final Completer<Uint8List> pending = Completer<Uint8List>();
    await openReports(
      tester,
      stage: 1,
      pdf: _QueuedPdfGenerator(<Future<Uint8List>>[pending.future]),
    );
    await tester.enterText(feedbackField, '이번 주도 수고하셨어요.');
    await settle(tester);
    await step(tester, 'next');
    // 미리보기를 만드는 중이어도 보낼 수 있다 — 전송은 그 한 부를 기다린다.
    expect(previewLoading, findsOneWidget);
    expect(sendEnabled(tester), isTrue);

    await step(tester, 'prev');
    await tester.enterText(feedbackField, '');
    await settle(tester);
    await step(tester, 'next');
    expect(sendEnabled(tester), isFalse);
    pending.complete(Uint8List.fromList(_pdfBytes));
    await settle(tester);
  });

  group('③ 인쇄 (#2451)', () {
    final Finder printButton = find.byKey(
      const ValueKey<String>('report-step-print'),
    );

    /// 하단 `인쇄` 버튼이 눌리는가.
    bool printEnabled(WidgetTester tester) =>
        tester.widget<AppButton>(printButton).onPressed != null;

    Future<void> tapPrint(WidgetTester tester) async {
      await tester.ensureVisible(printButton);
      await tester.pump();
      await tester.tap(printButton);
      await settle(tester);
    }

    testWidgets('인쇄 버튼은 ③ 에만 있고 전송 바로 왼쪽에 선다', (tester) async {
      await openReports(tester);
      expect(printButton, findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
      await settle(tester);
      expect(printButton, findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
      await settle(tester);
      expect(printButton, findsOneWidget);
      expect(sendButton, findsOneWidget);
      // 같은 줄, 전송의 왼쪽.
      expect(
        tester.getCenter(printButton).dy,
        moreOrLessEquals(tester.getCenter(sendButton).dy),
      );
      expect(
        tester.getTopRight(printButton).dx,
        lessThan(tester.getTopLeft(sendButton).dx),
      );
      expect(find.text('인쇄'), findsOneWidget);
    });

    testWidgets('인쇄는 미리보기와 같은 한 부를 전송과 같은 파일 이름으로 넘긴다', (tester) async {
      final _FakePrinter printer = _FakePrinter();
      final _FakeRasterizer raster = _FakeRasterizer();
      final _QueuedPdfGenerator pdf = _QueuedPdfGenerator(<Future<Uint8List>>[
        Future<Uint8List>.value(Uint8List.fromList(<int>[1, 2, 3, 4])),
      ]);
      await openReports(
        tester,
        stage: 2,
        pdf: pdf,
        raster: raster,
        extraOverrides: <Override>[
          reportPdfPrinterProvider.overrideWithValue(printer.call),
        ],
      );
      expect(printEnabled(tester), isTrue);

      await tapPrint(tester);

      expect(printer.inputs, <List<int>>[
        <int>[1, 2, 3, 4],
      ]);
      // 미리보기에 구운 것과 같은 바이트다.
      expect(printer.inputs.single, raster.inputs.single);
      // 인쇄한다고 PDF 를 새로 만들지 않는다.
      expect(pdf.calls, 1);
      expect(printer.names.single, endsWith('.pdf'));
      expect(printer.names.single, startsWith('김민수_'));
    });

    testWidgets('PDF 를 만드는 동안에는 인쇄가 잠겨 있다', (tester) async {
      final Completer<Uint8List> first = Completer<Uint8List>();
      final _FakePrinter printer = _FakePrinter();
      await openReports(
        tester,
        stage: 2,
        pdf: _QueuedPdfGenerator(<Future<Uint8List>>[first.future]),
        extraOverrides: <Override>[
          reportPdfPrinterProvider.overrideWithValue(printer.call),
        ],
      );
      expect(previewLoading, findsOneWidget);
      expect(printEnabled(tester), isFalse);
      // 잠긴 이유를 말해 준다.
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(of: printButton, matching: find.byType(Tooltip)),
            )
            .message,
        '미리보기 PDF가 준비되면 인쇄할 수 있어요',
      );

      first.complete(Uint8List.fromList(_pdfBytes));
      await settle(tester);
      expect(printEnabled(tester), isTrue);
      expect(printer.inputs, isEmpty);
    });

    testWidgets('PDF 를 만들지 못했으면 인쇄가 잠기고, 다시 만들면 풀린다', (tester) async {
      final Completer<Uint8List> first = Completer<Uint8List>();
      await openReports(
        tester,
        stage: 2,
        pdf: _QueuedPdfGenerator(<Future<Uint8List>>[first.future]),
        extraOverrides: <Override>[
          reportPdfPrinterProvider.overrideWithValue(_FakePrinter().call),
        ],
      );

      first.completeError(StateError('render failed'));
      await settle(tester);
      expect(previewFailed, findsOneWidget);
      expect(printEnabled(tester), isFalse);

      await tester.tap(
        find.descendant(of: previewFailed, matching: find.text('다시 시도')),
      );
      await settle(tester);
      expect(previewFailed, findsNothing);
      expect(printEnabled(tester), isTrue);
    });

    testWidgets('인쇄 창을 열지 못하면 알리고 다시 누를 수 있다', (tester) async {
      final _FakePrinter printer = _FakePrinter(fail: true);
      await openReports(
        tester,
        stage: 2,
        extraOverrides: <Override>[
          reportPdfPrinterProvider.overrideWithValue(printer.call),
        ],
      );

      await tapPrint(tester);

      expect(find.text('인쇄 창을 열지 못했어요. 다시 시도해 주세요'), findsOneWidget);
      expect(printEnabled(tester), isTrue);
      // 인쇄 실패는 전송과 상관없다 — ③ 에 그대로 머문다.
      expect(preview, findsOneWidget);
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('인쇄 창이 떠 있는 동안에는 한 번 더 눌리지 않는다', (tester) async {
      final Completer<bool> dialog = Completer<bool>();
      final _FakePrinter printer = _FakePrinter(result: dialog.future);
      await openReports(
        tester,
        stage: 2,
        extraOverrides: <Override>[
          reportPdfPrinterProvider.overrideWithValue(printer.call),
        ],
      );

      await tapPrint(tester);
      expect(printer.inputs, hasLength(1));
      expect(printEnabled(tester), isFalse);
      expect(tester.widget<AppButton>(printButton).loading, isTrue);

      dialog.complete(true);
      await settle(tester);
      expect(printEnabled(tester), isTrue);
      expect(tester.widget<AppButton>(printButton).loading, isFalse);
      expect(printer.inputs, hasLength(1));
    });

    testWidgets('인쇄는 피드백이 비어 있어도 할 수 있다 — 전송만 잠긴다', (tester) async {
      await openReports(
        tester,
        stage: 1,
        extraOverrides: <Override>[
          reportPdfPrinterProvider.overrideWithValue(_FakePrinter().call),
        ],
      );
      await tester.enterText(feedbackField, '');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
      await settle(tester);

      expect(sendEnabled(tester), isFalse);
      expect(printEnabled(tester), isTrue);
    });
  });
}

/// 저장한 초안을 기억하는 리포트 저장소. 리포트 본문·요약은 데모 계산을 그대로
/// 쓰고, 초안만 이 double 이 들고 있다.
class _DraftStore implements ReportRepository {
  _DraftStore({this.stored, this.failSave = false});

  /// 화면을 열 때 이미 저장돼 있는 초안. null 이면 저장한 적 없는 주다.
  final String? stored;
  final bool failSave;
  final List<String> saved = <String>[];

  @override
  Future<List<ReportSendRecord>> sentReports({
    required DateTime weekStart,
  }) async => const <ReportSendRecord>[];

  @override
  Future<MemberReportHistoryPage> memberReportHistory({
    required String clientId,
    DateTime? before,
    int limit = memberReportHistoryPageSize,
  }) async => const MemberReportHistoryPage.empty();

  @override
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) => reportQueueFromReports(this, clients: clients, weekStart: weekStart);

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

  /// PDF 와 함께 회원에게 나간 글.
  final List<String> sentMessages = <String>[];

  /// 보낸 PDF — 미리보기로 만든 한 부와 같은지 본다(#2402).
  final List<List<int>> sentBytes = <List<int>>[];

  @override
  Future<void> sendPdf({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async {
    sentMessages.add(message);
    sentBytes.add(bytes.toList());
  }

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
}

/// 리포트를 스트림으로 흘려 보내는 저장소. 데모의 drift 스트림처럼 같은 주를
/// 다시 보낼 수 있다(#2484).
class _StreamedReports extends _DraftStore {
  final StreamController<WeeklyReport> _pushed =
      StreamController<WeeklyReport>.broadcast();

  TrainerClient? _client;
  DateTime? _week;

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) async* {
    final DateTime week = weekStartOf(weekStart);
    // 편집기가 여는 주가 가장 늦은 주다 — 평소 칼로리를 내려고 읽는 지난
    // 주들보다 뒤다. 그 주를 흘려 보낼 주로 삼는다.
    if (_week == null || week.isAfter(_week!)) {
      _client = client;
      _week = week;
    }
    yield buildWeeklyReport(
      client: client,
      sessions: const [],
      weekStart: week,
    );
    yield* _pushed.stream.where((WeeklyReport r) => r.weekStart == week);
  }

  /// 처음과 내용이 같은 리포트를 새 객체로 보낸다.
  void pushSame() => _pushed.add(
    buildWeeklyReport(client: _client!, sessions: const [], weekStart: _week!),
  );

  /// PT 기록이 달라진 리포트를 보낸다.
  void pushChanged() => _pushed.add(
    WeeklyReport(
      client: _client!,
      weekStart: _week!,
      sessionsBooked: 3,
      sessionsDone: 2,
      completionAvg: 64,
      sodiumOverDays: 1,
      sodiumAvg: 2100,
      isCurrentWeek: true,
    ),
  );

  Future<void> close() => _pushed.close();
}

class _QueuedPdfGenerator extends ReportPdfGenerator {
  _QueuedPdfGenerator(this._results);

  final List<Future<Uint8List>> _results;
  int calls = 0;

  /// PDF 에 실린 피드백 문구 — 부를 때마다 하나씩 쌓인다.
  final List<String> feedbacks = <String>[];

  @override
  Future<Uint8List> generate({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) {
    feedbacks.add(feedback);
    // 준비한 결과를 다 쓰면 곧바로 끝나는 한 부를 낸다.
    final result = calls < _results.length
        ? _results[calls]
        : Future<Uint8List>.value(Uint8List.fromList(_pdfBytes));
    calls++;
    return result;
  }
}

/// 가짜 생성기가 기본으로 내는 PDF.
const List<int> _pdfBytes = <int>[0x25, 0x50, 0x44, 0x46];

/// 1×1 투명 PNG — 미리보기 쪽 그림 자리에 넣는다.
final Uint8List _pagePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

/// 미리보기의 쪽 굽기 자리. 넘겨받은 PDF 를 기억하고 [pages] 쪽을 낸다.
class _FakeRasterizer {
  _FakeRasterizer({this.pages = 2});

  final int pages;

  /// 구워 달라고 받은 PDF — 부를 때마다 하나씩 쌓인다.
  final List<List<int>> inputs = <List<int>>[];

  Future<List<Uint8List>> call(Uint8List pdf) async {
    inputs.add(pdf.toList());
    return List<Uint8List>.filled(pages, _pagePng);
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

/// 인쇄 창 대신 넘겨받은 PDF 와 이름을 적어 둔다.
class _FakePrinter {
  _FakePrinter({this.fail = false, this.result});

  /// 인쇄 창을 열지 못한 것처럼 던진다.
  final bool fail;

  /// 인쇄 창이 닫히는 때. 없으면 곧바로 닫힌다.
  final Future<bool>? result;

  final List<List<int>> inputs = <List<int>>[];
  final List<String> names = <String>[];

  Future<bool> call(Uint8List pdf, {required String name}) async {
    inputs.add(pdf.toList());
    names.add(name);
    if (fail) throw StateError('print dialog unavailable');
    return result ?? Future<bool>.value(true);
  }
}
