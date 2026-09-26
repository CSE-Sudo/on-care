import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/data/repositories/calorie_baseline.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/client_report_view.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_goal_picker.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_pdf_export_dialog.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_share_menu.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_nav.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/sent_report_view.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_file_name.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/progress_stepper.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트 — the week, from two angles.
///
/// **운영 지표** answers "how did my week go?" (sessions, completion,
/// programs prepared). **고객 주간 리포트** turns one client's week into
/// something the trainer can send them — the retention loop of an O2O
/// coaching product, since a member renews when they can see progress.
///
/// Sending delivers into the member's existing chat thread rather than a
/// separate report inbox: it arrives where they already read, and it
/// works identically in demo and against the real API.
class ReportsPage extends ConsumerStatefulWidget {
  /// Creates the reports page. [clientId] preselects a client.
  const ReportsPage({super.key, this.clientId, this.weekStart});

  /// Client focused via the `client` query parameter.
  final String? clientId;

  /// Week focused via the `week` query parameter. 채팅의 리포트 카드가
  /// 가리키는 주로 열기 위한 값이라 월요일이 아닌 날짜가 와도 그 주의
  /// 월요일로 맞춘다(#1421).
  final DateTime? weekStart;

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  /// Selected client id; null falls back to the first in the roster.
  late String? _clientId = widget.clientId;

  /// Monday of the week being reported. Starts on the week the caller
  /// asked for, otherwise this week.
  late DateTime _weekStart = weekStartOf(widget.weekStart ?? nowKst());

  /// Clients whose report was sent this session — keeps the button from
  /// being pressed twice in a row by accident.
  final Set<String> _sent = <String>{};

  /// 작업대의 정렬. 기본은 손이 필요한 회원부터다(#2232).
  ReportQueueSort _sort = ReportQueueSort.priority;

  /// 편집기에서 지금 서 있는 단계.
  int _stage = 0;

  /// 지금까지 가 본 가장 먼 단계 — 여기까지만 눌러서 돌아갈 수 있다.
  int _maxStage = 0;

  /// `보낸 리포트` 를 열어 둔 회원. null 이면 작업대나 편집기다.
  String? _sentViewFor;

  /// A send is in flight for this client.
  String? _sending;

  /// PDF binary를 만드는 동안 내보내기 중복 요청을 막는다.
  bool _generatingPdf = false;

  /// 피드백 입력창의 현재 내용. 전송 버튼이 헤더의 공유 메뉴로 올라가면서
  /// 입력창과 전송이 서로 다른 위젯에 있게 되어, 그 사이를 잇는 값이다.
  ///
  /// `setState` 를 부르지 않는다 — 메뉴는 열릴 때 `itemBuilder` 가 이 값을 다시
  /// 읽으므로, 글자 하나마다 리포트 화면 전체를 다시 그릴 이유가 없다.
  String? _feedbackDraft;

  /// [_feedbackDraft] 가 어느 리포트의 것인가(`고객|주`). 고객이나 주가 바뀌면
  /// 남의 리포트에 쓰던 문구가 따라가지 않게 버린다.
  String? _feedbackFor;

  /// 입력창을 새 문구로 다시 만들 때 올린다.
  ///
  /// `TextEditingController` 는 한 번 만들어지면 initialText 를 다시 읽지
  /// 않는다. 저장해 둔 초안이 늦게 도착하는 건 드문 일이라, 컨트롤러를 밖으로
  /// 끌어내는 대신 위젯 키를 바꿔 다시 만든다. 요약 가져오기는 되돌릴 수
  /// 있어야 해서 [_summaryEpoch] 가 따로 맡는다(#2187).
  int _draftEpoch = 0;

  /// 요약을 초안으로 가져올 때 올린다. 입력창을 다시 만들면 편집 기록이
  /// 사라져, 가져오기 전 글로 되돌릴 수 없다 — 이 값은 입력창 안의 글만
  /// 바꾼다(#2187).
  int _summaryEpoch = 0;

  /// 입력창이 비었는가. 메뉴의 전송 항목을 잠그는 유일한 이유라, 이 값이
  /// 바뀔 때만 다시 그린다 — 글자마다 화면 전체를 다시 그리지 않는다.
  bool _feedbackBlank = false;

  /// 회원·주마다 고른 다음 주 목표. (#2232)
  ///
  /// 서버에 목표를 두는 자리가 아직 없어 이번 세션에만 남는다 — 보낸 글에는
  /// 그대로 실려 나가므로 회원이 받은 것은 남는다.
  final Map<String, List<String>> _goals = <String, List<String>>{};

  /// 피드백 초안을 서버에 저장하는 중이다. (#821)
  bool _savingFeedback = false;

  /// 입력창의 출발점 — 저장해 둔 초안이 있으면 그것, 없으면 수치에서 만든
  /// 자동 문구다. (#821)
  ///
  /// 빈 본문을 저장한 주는 빈 문자열이 출발점이다. 트레이너가 일부러 지운
  /// 것이라, "저장한 적 없음" 으로 보고 자동 문구를 되살리면 지운 일이
  /// 무의미해진다.
  String _baseFor(
    AppLocalizations l,
    WeeklyReport report,
    ReportFeedbackDraft? saved,
  ) => saved != null && saved.saved ? saved.body : reportMessage(l, report);

  /// 이 리포트에 대해 실제로 보낼 문구 — 트레이너가 고친 게 있으면 그것,
  /// 없으면 화면에 채워져 있는 기본 문구다.
  String _messageFor(
    AppLocalizations l,
    WeeklyReport report,
    ReportFeedbackDraft? saved,
  ) => _feedbackFor == _feedbackKey(report)
      ? (_feedbackDraft ?? _baseFor(l, report, saved))
      : _baseFor(l, report, saved);

  /// 이 주에 고른 다음 주 목표.
  List<String> _goalsFor(WeeklyReport report) =>
      _goals[_feedbackKey(report)] ?? const <String>[];

  /// 회원이 실제로 받는 글 — 피드백 아래에 고른 목표를 붙인다.
  ///
  /// 입력창에 목표를 미리 적어 두지 않는다. 트레이너가 ②에서 고른 것을
  /// 지웠다 되살렸다 하면 글이 따라 흔들리고, 되돌리기 기록도 그만큼
  /// 어지러워진다 — 붙이는 일은 보낼 때 한 번만 한다.
  String _outgoingMessage(
    AppLocalizations l,
    WeeklyReport report,
    String feedback,
  ) {
    final List<String> goals = _goalsFor(report);
    if (goals.isEmpty) return feedback;
    return <String>[
      feedback,
      '',
      l.reportsGoalsTitle,
      for (final String goal in goals) '· $goal',
    ].join('\n');
  }

  static String _feedbackKey(WeeklyReport report) =>
      '${report.client.id}|${report.weekStart.toIso8601String()}';

  static String _feedbackKeyOf(String clientId, DateTime weekStart) =>
      '$clientId|${weekStart.toIso8601String()}';

  /// 입력창의 현재 문구를 그 주의 초안으로 저장한다. (#821)
  ///
  /// 실패해도 입력 내용을 건드리지 않는다 — 저장하려다 잃는 것이 이 기능이
  /// 없애려던 바로 그 문제다.
  Future<void> _saveFeedback(WeeklyReport report, String body) async {
    if (_savingFeedback) return;
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() => _savingFeedback = true);
    try {
      await ref
          .read(reportRepositoryProvider)
          .saveFeedbackDraft(
            clientId: report.client.id,
            weekStart: report.weekStart,
            body: body,
          );
      ref.invalidate(
        reportFeedbackDraftProvider((
          client: report.client,
          weekStart: report.weekStart,
        )),
      );
      if (!mounted) return;
      showAppToast(context, l.reportsFeedbackSaved, type: AppToastType.success);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        l.reportsFeedbackSaveFailed,
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _savingFeedback = false);
    }
  }

  @override
  void didUpdateWidget(ReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clientId != oldWidget.clientId) {
      _clientId = widget.clientId;
      // 다른 회원의 리포트는 처음부터 읽는다 — 앞 회원에서 ③까지 갔다고
      // 이 회원의 수치를 건너뛸 이유가 없다.
      _stage = 0;
      _maxStage = 0;
    }
  }

  void _selectClient(String id) {
    if (_clientId == id) return;
    context.go(AppRoutes.reportFor(id));
  }

  void _shiftWeek(int direction) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * direction));
      // A different week is a different report — allow sending again.
      _sent.clear();
      _stage = 0;
      _maxStage = 0;
      _sentViewFor = null;
      _feedbackDraft = null;
      _feedbackFor = null;
      _feedbackBlank = false;
    });
  }

  /// 다음 주 목표 하나를 고르거나 뺀다.
  void _toggleGoal(WeeklyReport report, String goal) {
    final String key = _feedbackKey(report);
    final List<String> next = <String>[..._goals[key] ?? const <String>[]];
    next.contains(goal) ? next.remove(goal) : next.add(goal);
    setState(() => _goals[key] = next);
  }

  /// 트레이너가 직접 적은 목표를 더한다 — 적자마자 고른 것으로 친다.
  void _addGoal(WeeklyReport report, String goal) {
    final String key = _feedbackKey(report);
    final List<String> next = <String>[..._goals[key] ?? const <String>[]];
    if (next.contains(goal)) return;
    next.add(goal);
    setState(() => _goals[key] = next);
  }

  /// 요약을 피드백 입력창으로 옮긴다.
  ///
  /// 요약 카드는 넓은 화면에서 왼쪽 열로, 좁은 화면에서는 리포트 흐름 안으로
  /// 자리를 옮겨 다녀 부르는 곳이 둘이다 — 옮기는 규칙은 한 곳에 둔다.
  void _useSummaryAsDraft(WeeklyReport report, String draft) {
    setState(() {
      _feedbackDraft = draft;
      _feedbackFor = _feedbackKey(report);
      _feedbackBlank = draft.trim().isEmpty;
      _summaryEpoch++;
    });
  }

  /// `8월 3일 – 8월 9일` — 카드 제목 줄에 적는 지금 보고 있는 주.
  static String _weekRangeLabel(AppLocalizations l, DateTime weekStart) {
    final DateTime weekEnd = weekStart.add(const Duration(days: 6));
    return l.dateRange(
      l.dateMonthDay(weekStart.month, weekStart.day),
      l.dateMonthDay(weekEnd.month, weekEnd.day),
    );
  }

  void _goToCurrentWeek() {
    final currentWeek = weekStartOf(nowKst());
    if (_weekStart == currentWeek) return;
    setState(() {
      _weekStart = currentWeek;
      _sent.clear();
      _stage = 0;
      _maxStage = 0;
      _sentViewFor = null;
      _feedbackDraft = null;
      _feedbackFor = null;
      _feedbackBlank = false;
    });
  }

  /// 그 주에 저장된 초안. 아직 안 읽혔으면 null 이다 — 전송·PDF 처럼 지금
  /// 당장 값이 필요한 자리에서 쓴다. (#821)
  ReportFeedbackDraft? _savedDraftOf(WeeklyReport report) => ref
      .read(
        reportFeedbackDraftProvider((
          client: report.client,
          weekStart: report.weekStart,
        )),
      )
      .valueOrNull;

  /// 헤더 공유 메뉴의 전송. 화면에 떠 있는 리포트와 입력창의 현재 문구를 함께
  /// 보낸다 — 입력창과 전송 버튼이 서로 다른 위젯이 되면서 필요해진 연결이다.
  Future<void> _sendSelected(WeeklyReport report) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _send(
      report,
      _outgoingMessage(
        l,
        report,
        _messageFor(l, report, _savedDraftOf(report)),
      ),
    );
  }

  /// 리포트 PDF binary. [_send]의 기본 전송과 [_openPdfExport]의 내보내기가
  /// 같은 문서를 만든다 — 전송이 실제로 받는 것과 내보내기 미리보기가 다른
  /// 문서면 안 된다.
  Future<Uint8List> _generateReportPdf(
    AppLocalizations l,
    WeeklyReport report,
    String feedback,
  ) async {
    WeeklyReport? previous;
    try {
      previous = await ref.read(
        weeklyReportProvider((
          client: report.client,
          weekStart: report.weekStart.subtract(const Duration(days: 7)),
        )).future,
      );
    } catch (_) {
      // 전주 집계가 없어도 현재 주차 PDF는 생성할 수 있다.
    }
    return ref
        .read(reportPdfGeneratorProvider)
        .generate(
          l: l,
          report: report,
          feedback: feedback,
          previousReport: previous,
        );
  }

  /// 헤더 공유 메뉴의 기본 전송 — PDF로 만들어 보낸다(#1378). 예전에는 순수
  /// 텍스트만 갔는데, 회원 채팅에서 PDF를 열람하는 길(#778, #921)이 이미 있어
  /// 굳이 글만 보낼 이유가 없었다. "PDF 내보내기"(별도 저장·인쇄용, [_openPdfExport])는
  /// 그대로 둔다.
  Future<void> _send(WeeklyReport report, String message) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final id = report.client.id;
    if (_sending != null || _sent.contains(id)) return;
    setState(() => _sending = id);
    try {
      final bytes = await _generateReportPdf(l, report, message);
      await ref
          .read(reportRepositoryProvider)
          .sendPdf(
            clientId: id,
            weekStart: report.weekStart,
            bytes: bytes,
            fileName: reportPdfFileName(l, report),
            message: message,
          );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = null);
      showAppToast(context, l.reportsSendFailed, type: AppToastType.error);
      return;
    }
    // ② 에서 고른 목표는 **보낼 때** 남긴다. 고르는 족족 저장하면 보내지 않고
    // 화면을 떠난 주의 목표까지 다음 주 리포트가 회수해, 회원이 받지도 않은
    // 목표를 못 지켰다고 적힌다(#2232).
    //
    // 전송이 이미 끝난 뒤라 여기서 실패해도 되돌리지 않는다 — 회원은 리포트를
    // 받았고, 목표 회수는 다음 주에야 필요한 일이다.
    try {
      await ref
          .read(reportRepositoryProvider)
          .saveNextWeekGoals(
            clientId: id,
            weekStart: report.weekStart,
            goals: _goalsFor(report),
          );
    } catch (_) {
      // 조용히 넘어간다. 여기서 토스트를 띄우면 방금 뜬 `전송 완료` 를 덮어,
      // 보냈다는 사실이 실패로 읽힌다.
    }
    if (!mounted) return;
    ref
        .read(reportSendLogProvider.notifier)
        .record(clientId: id, weekStart: report.weekStart, message: message);
    setState(() {
      _sending = null;
      _sent.add(id);
      // 보내고 나면 작업대로 돌아간다 — 다음 회원이 그 자리에 있다.
      _stage = 0;
      _maxStage = 0;
    });
    context.go(AppRoutes.reports);
    // 전송 확인은 하단 SnackBar가 아니라 상단 토스트로 뜬다 — 채팅으로
    // 바로 넘어갈 수 있는 동작 버튼을 붙이기 위해서다(#1378).
    showAppToast(
      context,
      l.reportsSent(report.client.name),
      type: AppToastType.success,
      actionLabel: l.reportsGoToChat,
      onAction: () => context.go(AppRoutes.messagesFor(id)),
    );
  }

  Future<void> _openPdfExport(WeeklyReport report) async {
    if (_generatingPdf) return;
    // PDF 문구도 화면과 같은 로케일이어야 한다 (#964).
    final AppLocalizations l = AppLocalizations.of(context);
    // 내보낸 PDF 와 전송한 글이 달라서는 안 된다 — 목표도 같이 싣는다.
    final feedback = _outgoingMessage(
      l,
      report,
      _messageFor(l, report, _savedDraftOf(report)),
    );
    setState(() => _generatingPdf = true);
    try {
      final bytes = await _generateReportPdf(l, report, feedback);
      if (!mounted) return;
      await showAppDialog<void>(
        context: context,
        builder: (_) => ReportPdfExportDialog(report: report, bytes: bytes),
      );
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          l.reportsPdfGenerationFailed,
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  /// 리포트를 읽는 중이거나 못 읽은 주의 카드. 주 이동은 편집기 위쪽 줄에
  /// 늘 있으니, 여기서는 제목만 두고 실패한 주에서 나갈 길은 그쪽이 맡는다.
  static Widget _weeklyStateCard(AppLocalizations l, Widget child) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(
          title: l.reportsWeekly,
          icon: Icons.description_rounded,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        child,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final clientsAsync = ref.watch(clientsProvider);
    final range = (
      from: ymd(_weekStart),
      to: ymd(_weekStart.add(const Duration(days: 6))),
    );
    final weekSessions = ref.watch(scheduleRangeProvider(range));
    // 헤더는 본문(LayoutBuilder)보다 위에 있어 본문이 고른 고객을 볼 수 없다.
    // 본문과 **같은 규칙**으로 여기서 한 번 더 고른다 — 메뉴 항목에 이름을
    // 함께 보여 주므로 누구에게 가는 리포트인지 화면에서 드러난다.
    final roster = clientsAsync.valueOrNull ?? const <TrainerClient>[];
    final TrainerClient? shareTarget = roster.isEmpty
        ? null
        : roster.firstWhere(
            (c) => c.id == _clientId,
            orElse: () => roster.first,
          );
    // 저장해 둔 초안이 도착하면 입력창을 그 문구로 다시 만든다. 이미 이 리포트를
    // 고치고 있었다면 건드리지 않는다 — 읽어 온 값이 트레이너가 방금 친 글을
    // 덮으면 안 된다. (#821)
    //
    // `ref.listen` 은 build 안에서만 부를 수 있어 본문(LayoutBuilder 콜백은
    // layout 단계에 돈다)이 아니라 여기에 둔다. 고객을 고르는 규칙은 본문과
    // 같은 [shareTarget] 이다.
    if (shareTarget != null) {
      ref.listen<AsyncValue<ReportFeedbackDraft>>(
        reportFeedbackDraftProvider((
          client: shareTarget,
          weekStart: _weekStart,
        )),
        (previous, next) {
          if (next.valueOrNull == null) return;
          if (_feedbackFor == _feedbackKeyOf(shareTarget.id, _weekStart)) {
            return;
          }
          setState(() => _draftEpoch++);
        },
      );
    }

    return AppWebPage(
      key: ValueKey<String>('reports-${_clientId ?? 'list'}'),
      title: l.reportsTitle,
      subtitle: l.reportsSubtitle,
      // 헤더 검색은 가운데 자리다 — 다른 탭과 같은 가로 위치에 서고, 자리가
      // 모자라면 검색 바가 스스로 아이콘으로 접힌다.
      headerCenter: const ClientSearchBar(),
      actions: <Widget>[
        // 주 이동은 통째로 리포트 카드 제목 줄에 있다 — 화살표도, 이번 주로
        // 돌아가는 버튼도. 헤더에 두면 옮기는 대상과 버튼이 다른 줄에 서고,
        // 날짜 버튼이 가운데 고객 검색 바의 폭을 먹어 다른 탭과 다른 모양으로
        // 접혔다(#1177).
        ReportShareMenu(
          client: shareTarget,
          weekStart: _weekStart,
          sent: shareTarget != null && _sent.contains(shareTarget.id),
          sending: shareTarget != null && _sending == shareTarget.id,
          feedbackBlank: _feedbackBlank,
          onSend: _sendSelected,
          generatingPdf: _generatingPdf,
          onPdf: _openPdfExport,
        ),
      ],
      body: clientsAsync.when(
        loading: () => const AppLoading(),
        // 재시도 버튼은 상태 위젯 안에 있어 키를 줄 수 없다 — 묶음에 키를 둔다.
        error: (e, _) => KeyedSubtree(
          key: const ValueKey<String>('reports-clients-retry'),
          child: AppErrorState(
            title: l.reportsLoadFailed,
            retryLabel: l.actionRetry,
            onRetry: clientsAsync.isLoading
                ? null
                : () => ref.invalidate(clientsProvider),
          ),
        ),
        data: (clients) {
          if (clients.isEmpty) {
            return AppEmptyState(
              title: l.reportsNoClients,
              icon: Icons.insights_rounded,
            );
          }
          // 이번 주 큐를 세우려면 회원별 리포트가 필요하다. 한 명이 실패해도
          // 나머지 줄은 그대로 선다 — 작업대의 답은 "누가 남았나" 이고, 그
          // 답은 수치 없이도 낼 수 있다.
          final reports = <String, WeeklyReport>{};
          bool anyLoading = false;
          for (final TrainerClient c in clients) {
            final AsyncValue<WeeklyReport> value = ref.watch(
              weeklyReportProvider((client: c, weekStart: _weekStart)),
            );
            final WeeklyReport? data = value.valueOrNull;
            if (data != null) reports[c.id] = data;
            if (value.isLoading) anyLoading = true;
          }
          // 기록 자체를 본다 — notifier 를 보면 상태가 바뀌어도 다시 그리지
          // 않아 전송한 회원이 큐에 남는다.
          // 데모 기록을 얹는다 — 작업대의 두 열이 다 차 있어야 이 화면이
          // 무엇인지 읽힌다. 트레이너가 이번 세션에 실제로 보낸 것이 언제나
          // 먼저다(#2232).
          final Map<String, ReportSendRecord> sendLog = withDemoSends(
            ref.watch(reportSendLogProvider),
            <String>{for (final TrainerClient c in clients) c.id},
            _weekStart,
          );
          final Set<String> sentIds = <String>{
            ..._sent,
            ...sentClientsIn(sendLog, _weekStart),
          };

          final bool isThisWeek = _weekStart == weekStartOf(nowKst());
          final Widget weekNav = ReportWeekNav(
            rangeLabel: _weekRangeLabel(l, _weekStart),
            onPrev: () => _shiftWeek(-1),
            // 앞으로는 이번 주까지만 간다 — 아직 오지 않은 주의 리포트는 빈
            // 화면이다.
            onNext: isThisWeek ? null : () => _shiftWeek(1),
            onThisWeek: isThisWeek ? null : _goToCurrentWeek,
          );

          // ── 보낸 리포트 ───────────────────────────────────────────────
          final String? sentFor = _sentViewFor;
          if (sentFor != null) {
            final ReportSendRecord? record = sendRecordFor(
              sendLog,
              sentFor,
              _weekStart,
            );
            final WeeklyReport? sentReport = reports[sentFor];
            if (record != null && sentReport != null) {
              return SentReportView(
                report: sentReport,
                record: record,
                onBack: () => setState(() => _sentViewFor = null),
                onRewrite: () {
                  setState(() => _sentViewFor = null);
                  _selectClient(sentFor);
                },
              );
            }
            // 기록이나 수치가 사라졌으면 작업대로 되돌린다 — 빈 화면에
            // 가두지 않는다.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _sentViewFor = null);
            });
          }

          // ── 작업대 ──────────────────────────────────────────────────
          if (_clientId == null) {
            return ReportWorkbench(
              entries: buildReportQueue(
                clients: clients,
                reports: reports,
                sentIds: sentIds,
                sort: _sort,
              ),
              records: <String, ReportSendRecord>{
                for (final ReportSendRecord r in sendLog.values)
                  if (ymd(r.weekStart) == ymd(_weekStart)) r.clientId: r,
              },
              sort: _sort,
              loading: anyLoading,
              weekNav: weekNav,
              onSortChanged: (value) => setState(() => _sort = value),
              onOpen: (entry) => _selectClient(entry.client.id),
              onOpenSent: (entry) =>
                  setState(() => _sentViewFor = entry.client.id),
            );
          }

          // ── 편집기 ──────────────────────────────────────────────────
          final selected = clients.firstWhere(
            (c) => c.id == _clientId,
            orElse: () => clients.first,
          );
          final reportKey = (client: selected, weekStart: _weekStart);
          final reportAsync = ref.watch(weeklyReportProvider(reportKey));
          // 저장해 둔 초안. 리포트와 따로 읽는다 — 초안은 트레이너가 쓰던
          // 글이고, 리포트가 다시 계산돼도 사라지면 안 된다.
          final savedDraft = ref
              .watch(reportFeedbackDraftProvider(reportKey))
              .valueOrNull;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 좁은 창에서는 머리줄을 둘로 접는다. 한 줄에 목록·이름·주
              // 이동·바로 쓰기를 모두 세우면 노트북보다 좁은 창에서 넘친다.
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide =
                      constraints.maxWidth >= OnCareLayout.splitBreakpoint;
                  final Widget skip = AppButton(
                    key: const ValueKey<String>('report-skip-to-write'),
                    label: l.reportsSkipToWrite,
                    leadingIcon: Icons.edit_note_rounded,
                    variant: AppButtonVariant.text,
                    size: OnCareButtonSize.small,
                    onPressed: () {
                      final WeeklyReport? data = reportAsync.valueOrNull;
                      if (data != null) _useSummaryAsDraft(data, '');
                      setState(() {
                        _stage = ReportEditorStage.values.length - 1;
                        _maxStage = _stage;
                      });
                    },
                  );
                  final Widget head = Row(
                    children: <Widget>[
                      AppButton(
                        key: const ValueKey<String>('reports-back-to-list'),
                        label: l.reportsBackToWorkbench,
                        variant: AppButtonVariant.text,
                        leadingIcon: Icons.chevron_left_rounded,
                        onPressed: () => context.go(AppRoutes.reports),
                      ),
                      const SizedBox(width: OnCareSpacing.s8),
                      // 누구의 리포트인지는 편집기 머리에 한 번만 선다. 카드마다
                      // 이름을 적으면 네 카드가 같은 말을 네 번 하고, 정작 카드
                      // 제목이 말해야 할 `무엇을 보는 칸인가` 가 밀린다.
                      Flexible(
                        child: Text(
                          l.reportsClientWeekly(selected.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.oncare.text(
                            OnCareTypography.strong(
                              OnCareTypography.titleSmall,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      // 주 이동은 목록 화면에서만 한다 — 편집기는 이미 고른
                      // 한 주를 쓰는 자리라, 여기서 주가 바뀌면 쓰던 글이 다른
                      // 주의 수치 옆에 선다.
                      if (wide) skip,
                    ],
                  );
                  if (wide) return head;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      head,
                      const SizedBox(height: OnCareSpacing.s8),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: skip,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: OnCareSpacing.s12),
              // 단계 표시는 AI 코칭의 추천안 만들기와 같은 것을 쓴다 — 같은
              // 일(여러 단계를 거쳐 회원에게 보낼 것을 만든다)이라 형태가
              // 달라야 할 이유가 없다.
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: ProgressStepper(
                    keyPrefix: 'report-stage',
                    labels: <String>[
                      l.reportsStepReview,
                      l.reportsStepGoals,
                      l.reportsStepSend,
                    ],
                    semanticsLabel: l.reportsStepperLabel,
                    stage: _stage,
                    maxReachedStage: _maxStage,
                    onStageTap: (value) => setState(() => _stage = value),
                  ),
                ),
              ),
              const SizedBox(height: OnCareSpacing.s16),
              Expanded(
                child: reportAsync.when(
                  loading: () => _weeklyStateCard(
                    l,
                    const AppLoading(placement: AppStatePlacement.card),
                  ),
                  error: (e, _) => _weeklyStateCard(
                    l,
                    KeyedSubtree(
                      key: const ValueKey<String>('reports-weekly-retry'),
                      child: AppErrorState(
                        title: l.reportsLoadFailed,
                        retryLabel: l.actionRetry,
                        placement: AppStatePlacement.card,
                        onRetry: reportAsync.isLoading
                            ? null
                            : () => ref.invalidate(
                                weeklyReportProvider(reportKey),
                              ),
                      ),
                    ),
                  ),
                  data: (data) => SingleChildScrollView(
                    key: const ValueKey<String>('reports-report-scroll'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        ClientReportView(
                          stage: ReportEditorStage.values[_stage],
                          report: data,
                          showSummary: true,
                          draftEpoch: _draftEpoch,
                          summaryEpoch: _summaryEpoch,
                          initialFeedback: _messageFor(l, data, savedDraft),
                          savingFeedback: _savingFeedback,
                          onSaveFeedback: () => _saveFeedback(
                            data,
                            _messageFor(l, data, savedDraft),
                          ),
                          weekNav: const SizedBox.shrink(),
                          // 평소와 견주려면 지난 주들을 읽어야 한다. 같은
                          // family 를 다시 읽는 것이라 새 API 가 없고, 오간
                          // 주는 캐시에 남는다.
                          calorieBaseline: ref.watch(
                            calorieBaselineProvider((
                              client: selected,
                              weekStart: _weekStart,
                            )),
                          ),
                          onUseSummaryAsDraft: (draft) =>
                              _useSummaryAsDraft(data, draft),
                          onFeedbackChanged: (text) {
                            _feedbackDraft = text;
                            _feedbackFor = _feedbackKey(data);
                            // 비었는지가 바뀔 때만 다시 그린다 — 전송 항목을
                            // 가르는 값이다.
                            final blank = text.trim().isEmpty;
                            if (blank != _feedbackBlank) {
                              setState(() => _feedbackBlank = blank);
                            }
                          },
                        ),
                        // ② 는 다음 주에 함께 챙길 것을 고르는 단계다 — 요약
                        // 카드가 재료를 내놓고, 이 카드가 고른 것을 남긴다.
                        if (_stage == 1) ...<Widget>[
                          const SizedBox(height: OnCareSpacing.s16),
                          ReportGoalPicker(
                            suggestions: summaryCoachingActionsAll(l, data),
                            selected: _goalsFor(data),
                            onToggle: (goal) => _toggleGoal(data, goal),
                            onAdd: (goal) => _addGoal(data, goal),
                          ),
                        ],
                        // ③ 에서는 고른 목표를 다시 고르게 하지 않는다. 보낼
                        // 글 아래에 그대로 붙어 나가는 것을 보여 줄 뿐이다.
                        if (_stage == 2 &&
                            _goalsFor(data).isNotEmpty) ...<Widget>[
                          const SizedBox(height: OnCareSpacing.s16),
                          _GoalRecap(goals: _goalsFor(data)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: OnCareSpacing.s12),
              _StepFooter(
                stage: _stage,
                sending: _sending == selected.id,
                canSend: !_feedbackBlank,
                onPrev: _stage == 0 ? null : () => setState(() => _stage--),
                onNext: _stage == 2
                    ? null
                    : () => setState(() {
                        _stage++;
                        if (_stage > _maxStage) _maxStage = _stage;
                      }),
                onSend: reportAsync.valueOrNull == null
                    ? null
                    : () => _sendSelected(reportAsync.value!),
              ),

              if (weekSessions.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: OnCareSpacing.s12),
                  child: Text(
                    l.reportsScheduleWarning,
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.caption))
                        .copyWith(color: OnCareColors.caution),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 편집기 아래 줄 — 이전 / 다음, 마지막 단계에서는 전송.
class _StepFooter extends StatelessWidget {
  const _StepFooter({
    required this.stage,
    required this.sending,
    required this.canSend,
    required this.onPrev,
    required this.onNext,
    required this.onSend,
  });

  final int stage;
  final bool sending;

  /// 보낼 글이 있는가. 빈 피드백은 보내지 않는다.
  final bool canSend;

  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool last = stage == 2;
    return Row(
      children: <Widget>[
        if (onPrev != null)
          AppButton(
            key: const ValueKey<String>('report-step-prev'),
            label: l.reportsStepPrev,
            variant: AppButtonVariant.text,
            leadingIcon: Icons.chevron_left_rounded,
            onPressed: onPrev,
          ),
        const Spacer(),
        if (last)
          AppButton(
            key: const ValueKey<String>('report-step-send'),
            label: l.reportsStepSend,
            onPressed: sending || !canSend ? null : onSend,
          )
        else
          AppButton(
            key: const ValueKey<String>('report-step-next'),
            label: l.reportsStepNext,
            trailingIcon: Icons.chevron_right_rounded,
            onPressed: onNext,
          ),
      ],
    );
  }
}

/// ③ 전송 단계에서, 보낼 글 아래에 함께 나갈 다음 주 목표를 보여 주는 카드.
class _GoalRecap extends StatelessWidget {
  const _GoalRecap({required this.goals});

  final List<String> goals;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      key: const ValueKey<String>('report-goals-recap'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSectionHeader(
            title: l.reportsGoalsTitle,
            icon: Icons.flag_rounded,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          for (final String goal in goals) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppIcon(
                  Icons.check_circle_rounded,
                  size: OnCareSize.iconSmall,
                  color: tokens.brand.primary,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: Text(
                    goal,
                    style: tokens.text(OnCareTypography.bodySmall),
                  ),
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s8),
          ],
        ],
      ),
    );
  }
}
