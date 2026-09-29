import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/member_report_history_provider.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/data/repositories/calorie_baseline.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/client_report_view.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/member_report_history_view.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_send_preview.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_nav.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/sent_report_view.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_file_name.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_printer.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트 편집기 단계 원 사이 간격 — 공용 기본의 두 배(#2449).
const double reportStepperGap = AppStepIndicator.numberedGap * 2;

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
  const ReportsPage({
    super.key,
    this.clientId,
    this.weekStart,
    this.historyClientId,
  });

  /// Client focused via the `client` query parameter.
  final String? clientId;

  /// 지난 리포트를 여는 회원 — `history` 쿼리(#2394). [clientId] 가 함께
  /// 오면 편집기가 먼저다.
  final String? historyClientId;

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

  /// Monday of the week being reported.
  ///
  /// URL 의 `week` 가 원본이다(#2289). 리포트 탭은 다른 탭에 다녀와도 살아
  /// 있어서, 여기서 한 번 정하고 끝내면 채팅의 리포트 카드가 다른 주를
  /// 가리켜도 보던 주가 그대로 열린다 — [didUpdateWidget] 이 URL 을 다시
  /// 읽고, 주를 옮기는 쪽은 URL 을 먼저 바꾼다.
  late DateTime _weekStart = _weekFromUrl(widget.weekStart);

  /// URL 이 가리키는 주의 월요일. 없으면 이번 주다.
  ///
  /// 아직 오지 않은 주는 이번 주로 당긴다 — 화면의 `다음 주` 화살표도 이번
  /// 주에서 멈추니, 손으로 고친 URL 이 그 너머의 빈 리포트를 열 이유가 없다.
  static DateTime _weekFromUrl(DateTime? requested) {
    final DateTime current = weekStartOf(nowKst());
    if (requested == null) return current;
    final DateTime monday = weekStartOf(requested);
    return monday.isAfter(current) ? current : monday;
  }

  /// URL 에 실을 주. 이번 주는 싣지 않는다 — 주소가 짧게 남고, 다음 주에
  /// 다시 열었을 때도 `이번 주` 로 열린다.
  DateTime? get _weekParam =>
      _weekStart == weekStartOf(nowKst()) ? null : _weekStart;

  /// 지금 보고 있는 주를 그대로 둔 채 [clientId] 의 편집기(null 이면
  /// 작업대)로 가는 주소.
  String _locationFor(String? clientId) =>
      AppRoutes.reportFor(clientId, weekStart: _weekParam);

  /// Clients whose report was sent this session — keeps the button from
  /// being pressed twice in a row by accident.
  final Set<String> _sent = <String>{};

  /// 작업대의 정렬. 기본은 손이 필요한 회원부터다(#2232).
  ReportQueueSort _sort = ReportQueueSort.priority;
  ReportSentSort _sentSort = ReportSentSort.unreadFirst;

  /// 편집기에서 지금 서 있는 단계.
  int _stage = 0;

  /// 지금까지 가 본 가장 먼 단계 — 여기까지만 눌러서 돌아갈 수 있다.
  int _maxStage = 0;

  /// `보낸 리포트` 를 열어 둔 회원. null 이면 작업대나 편집기다.
  String? _sentViewFor;

  /// 지난 리포트를 보고 있는 회원(#2394). URL 의 `history` 가 원본이다.
  late String? _historyFor = widget.historyClientId;

  /// 지난 리포트에서 `보기` 로 연 주. 그 화면의 돌아가기는 지난 리포트로
  /// 간다 — 작업대에서 바로 연 [_sentViewFor] 와 돌아가는 곳이 다르다.
  ///
  /// 작업대의 주([_weekStart])는 옮기지 않는다. 지난 리포트를 훑다 `회원 목록`
  /// 으로 돌아가면 보던 주의 작업대가 그대로 서야 한다.
  DateTime? _historyWeek;

  /// A send is in flight for this client.
  String? _sending;

  /// 다시 보낼지 묻는 창이 떠 있다 — 두 번 눌러 창이 둘 뜨지 않게 한다.
  bool _confirming = false;

  /// 인쇄 창이 떠 있다 — 두 번 눌러 창이 둘 뜨지 않게 한다(#2451).
  bool _printing = false;

  /// 피드백 입력창의 현재 내용. 입력창과 하단 전송 버튼이 서로 다른 위젯에
  /// 있어, 그 사이를 잇는 값이다.
  ///
  /// `setState` 를 부르지 않는다 — 전송 버튼은 누를 때 이 값을 읽으므로, 글자
  /// 하나마다 리포트 화면 전체를 다시 그릴 이유가 없다.
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

  /// 피드백 초안을 서버에 저장하는 중이다. (#821)
  bool _savingFeedback = false;

  /// ③ 전송 미리보기로 만든 PDF 한 부(#2402). 전송도 이 한 부를 그대로
  /// 보낸다 — 미리보기와 회원이 받는 파일이 서로 다를 수 없다.
  Future<Uint8List>? _preview;

  /// [_preview] 의 재료(`회원|주|언어|리포트 내용|문구`). ② 에서 글을 고치고
  /// 돌아오면 문구가 달라져 새로 만든다.
  ///
  /// 리포트는 객체가 아니라 내용으로 가른다(#2484). 스트림이 내용이 같은
  /// 리포트를 새 객체로 다시 보낼 때마다 PDF 를 처음부터 다시 만들면, 무거운
  /// 생성이 겹쳐 ③ 이 멈춘다. 수치가 실제로 바뀌면 열쇠가 달라져 새로 만든다.
  String? _previewKey;

  static String _previewKeyOf(
    AppLocalizations l,
    WeeklyReport report,
    String message,
  ) => '${_feedbackKey(report)}|${l.localeName}|${report.contentKey}|$message';

  /// [report] 를 [message] 로 만든 미리보기가 지금 있는가.
  bool _previewMatches(
    AppLocalizations l,
    WeeklyReport report,
    String message,
  ) => _preview != null && _previewKey == _previewKeyOf(l, report, message);

  /// ③ 에 띄울 PDF. 재료가 같으면 있던 것을 쓰고, 다르면 전송과 같은
  /// [_generateReportPdf] 로 새로 만든다. build 안에서 부른다.
  Future<Uint8List> _previewFor(
    AppLocalizations l,
    WeeklyReport report,
    String message,
  ) {
    if (_previewMatches(l, report, message)) return _preview!;
    _previewKey = _previewKeyOf(l, report, message);
    return _preview = _generateReportPdf(l, report, message);
  }

  /// 미리보기를 버린다 — 다음에 ③ 을 그릴 때 새로 만든다.
  void _dropPreview() {
    _preview = null;
    _previewKey = null;
  }

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
      _dropPreview();
    }
    if (widget.historyClientId != oldWidget.historyClientId) {
      _historyFor = widget.historyClientId;
      _historyWeek = null;
      _sentViewFor = null;
    }
    // 살아 있는 탭에 다른 주를 가리키는 링크가 들어왔다(#2289). 화면이 주를
    // 옮길 때는 URL 보다 상태를 먼저 바꾸므로 여기서 같은 값이 되어 다시
    // 비우지 않는다.
    final DateTime urlWeek = _weekFromUrl(widget.weekStart);
    if (urlWeek != _weekStart) _enterWeek(urlWeek);
  }

  /// [week] 로 옮기고 앞 주에 매인 것을 비운다. `setState` 안이나
  /// [didUpdateWidget] 에서 부른다.
  void _enterWeek(DateTime week) {
    _weekStart = week;
    // A different week is a different report — allow sending again.
    _sent.clear();
    _stage = 0;
    _maxStage = 0;
    _sentViewFor = null;
    _feedbackDraft = null;
    _feedbackFor = null;
    _feedbackBlank = false;
    _dropPreview();
  }

  /// 주를 옮기고 URL 에 싣는다.
  ///
  /// 화살표를 누를 때마다 방문 기록이 쌓이면 뒤로 가기가 지나온 주를 하나씩
  /// 되짚는다 — 기록은 남기지 않고 주소만 바꾼다([Router.neglect]).
  /// 새로고침·주소 공유는 그 주로 열린다(#2289).
  void _moveToWeek(DateTime week) {
    if (week == _weekStart) return;
    setState(() => _enterWeek(week));
    Router.neglect(context, () => context.go(_locationFor(_clientId)));
  }

  void _selectClient(String id) {
    if (_clientId == id) return;
    // 회원을 바꿔도 보던 주는 그대로다 — 작업대에서 고른 주의 리포트를 쓰러
    // 들어가는 것이다(#2289).
    context.go(_locationFor(id));
  }

  /// [clientId] 의 지난 리포트를 연다(#2394). 보던 주는 URL 에 남긴다 —
  /// `회원 목록` 으로 돌아가면 그 주 작업대다.
  void _openHistory(String clientId) {
    setState(() {
      _sentViewFor = null;
      _historyWeek = null;
    });
    context.go(AppRoutes.reportHistoryFor(clientId, weekStart: _weekParam));
  }

  /// [clientId] 의 [week] 주 편집기를 연다 — 지난 리포트의 `열기` 와 다시
  /// 쓰기가 부른다. 이번 주는 URL 에 싣지 않는다([_weekParam] 과 같은 규칙).
  void _openEditor(String clientId, DateTime week) {
    final DateTime monday = weekStartOf(week);
    context.go(
      AppRoutes.reportFor(
        clientId,
        weekStart: monday == weekStartOf(nowKst()) ? null : monday,
      ),
    );
  }

  /// 달력 날짜로 한 주씩 옮긴다. `Duration(days: 7)` 을 더하면 서머타임이
  /// 있는 곳에서 자정이 한 시간 밀려 주가 어긋난다.
  void _shiftWeek(int direction) => _moveToWeek(
    DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 7 * direction),
  );

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
    final DateTime weekEnd = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + 6,
    );
    return l.dateRange(
      l.dateMonthDay(weekStart.month, weekStart.day),
      l.dateMonthDay(weekEnd.month, weekEnd.day),
    );
  }

  void _goToCurrentWeek() => _moveToWeek(weekStartOf(nowKst()));

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

  /// 하단 `전송` 버튼의 전송. 화면에 떠 있는 리포트와 입력창의 현재 문구를 함께
  /// 보낸다 — 입력창과 전송 버튼이 서로 다른 위젯이 되면서 필요해진 연결이다.
  Future<void> _sendSelected(WeeklyReport report) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _send(report, _messageFor(l, report, _savedDraftOf(report)));
  }

  /// 리포트 PDF binary. 회원이 채팅으로 받는 문서가 이것이다.
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

  /// 리포트 전송 — PDF로 만들어 회원 채팅에 보낸다(#1378). 예전에는 순수
  /// 텍스트만 갔는데, 회원 채팅에서 PDF를 열람하는 길(#778, #921)이 이미 있어
  /// 굳이 글만 보낼 이유가 없었다. 따로 저장·인쇄하던 `PDF 내보내기` 는 헤더
  /// 공유 메뉴와 함께 물러났다(#2389) — 회원에게 가는 길은 이 하나뿐이다.
  Future<void> _send(WeeklyReport report, String message) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final id = report.client.id;
    if (_sending != null || _confirming || _sent.contains(id)) return;
    // 이미 보낸 주면 한 번 더 묻는다(#2288). 기록은 서버에서 오므로 새로고침한
    // 뒤에도 이 확인이 선다 — 전에는 세션 메모리만 봐서 새로고침하면 같은
    // 리포트가 아무 확인 없이 두 번 나갔다.
    _confirming = true;
    final bool proceed;
    try {
      proceed = await _confirmResend(l, report);
    } finally {
      _confirming = false;
    }
    if (!proceed || !mounted) return;
    setState(() => _sending = id);
    try {
      final bytes = await _pdfForSend(l, report, message);
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
    if (!mounted) return;
    ref
        .read(reportSendLogProvider.notifier)
        .record(clientId: id, weekStart: report.weekStart, message: message);
    // 서버 기록을 다시 읽는다 — 방금 보낸 것이 새로고침 뒤에도 남는 근거다.
    ref.invalidate(reportSendHistoryProvider(weekStartOf(report.weekStart)));
    ref.invalidate(memberReportHistoryProvider(id));
    setState(() {
      _sending = null;
      _sent.add(id);
      // 보내고 나면 작업대로 돌아간다 — 다음 회원이 그 자리에 있다.
      _stage = 0;
      _maxStage = 0;
      _dropPreview();
    });
    context.go(_locationFor(null));
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

  /// ③ 의 `인쇄` — 미리보기에 떠 있는 그 한 부를 인쇄 창에 넘긴다(#2451).
  ///
  /// 새로 만들지 않는다. 화면에서 본 것, 회원에게 가는 것, 종이에 찍히는 것이
  /// 모두 같은 파일이어야 한다. 파일 이름도 전송과 같다.
  Future<void> _print(WeeklyReport report, Uint8List bytes) async {
    if (_printing) return;
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() => _printing = true);
    try {
      await ref.read(reportPdfPrinterProvider)(
        bytes,
        name: reportPdfFileName(l, report),
      );
    } catch (_) {
      if (mounted) {
        showAppToast(context, l.reportsPrintFailed, type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// 보낼 PDF — ③ 에 떠 있는 미리보기 한 부다(#2402).
  ///
  /// 미리보기가 없거나(문구가 바뀌었거나) 만들다 실패했으면 새로 만들고, 그
  /// 한 부를 미리보기에도 건다 — 보낸 것과 화면에 떠 있는 것이 같게.
  Future<Uint8List> _pdfForSend(
    AppLocalizations l,
    WeeklyReport report,
    String message,
  ) async {
    final Future<Uint8List>? shown = _previewMatches(l, report, message)
        ? _preview
        : null;
    if (shown != null) {
      try {
        return await shown;
      } catch (_) {
        // 미리보기가 실패했다 — 아래에서 새로 만든다.
      }
    }
    final Future<Uint8List> fresh = _generateReportPdf(l, report, message);
    if (mounted) {
      setState(() {
        _preview = fresh;
        _previewKey = _previewKeyOf(l, report, message);
      });
    }
    return fresh;
  }

  /// [report] 의 회원에게 그 주 리포트가 이미 나갔으면 다시 보낼지 묻는다.
  ///
  /// 보낸 적이 없으면 묻지 않고 true 다. 서버 기록을 읽지 못했으면 아는
  /// 만큼(세션 기록·데모 기록)으로 판단한다 — 그때 작업대에는 이력을 읽지
  /// 못했다는 경고가 이미 서 있다.
  Future<bool> _confirmResend(AppLocalizations l, WeeklyReport report) async {
    final DateTime week = weekStartOf(report.weekStart);
    Map<String, ReportSendRecord> history = const <String, ReportSendRecord>{};
    try {
      history = await ref.read(reportSendHistoryProvider(week).future);
    } catch (_) {
      // 위 주석대로 아는 만큼으로 판단한다.
    }
    if (!mounted) return false;
    final List<TrainerClient> roster =
        ref.read(clientsProvider).valueOrNull ?? const <TrainerClient>[];
    final ReportSendRecord? previous = sendRecordFor(
      withDemoSends(
        mergeSendLogs(history, ref.read(reportSendLogProvider)),
        <String>{for (final TrainerClient c in roster) c.id},
        week,
      ),
      report.client.id,
      week,
    );
    if (previous == null) return true;
    final DateTime at = previous.sentAt;
    return showAppConfirmDialog(
      context: context,
      title: l.reportsResendTitle,
      message: l.reportsResendBody(
        report.client.name,
        dateLabel(l, at),
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}',
      ),
      confirmLabel: l.reportsResendConfirm,
      cancelLabel: l.actionCancel,
    );
  }

  /// 리포트를 읽는 중이거나 못 읽은 주의 카드. 주 이동은 편집기 위쪽 줄에
  /// 늘 있으니, 여기서는 제목만 두고 실패한 주에서 나갈 길은 그쪽이 맡는다.
  static Widget _weeklyStateCard(AppLocalizations l, Widget child) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(
          title: l.reportsWeekly,
          icon: AppIcons.document,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        child,
      ],
    ),
  );

  /// 지난 리포트에서 `보기` 로 연 [week] 주의 보낸 리포트.
  ///
  /// 작업대와 같은 기록(그 주 서버 기록 + 세션 기록 + 데모 기록)과 같은
  /// 화면([SentReportView])을 쓴다 — 두 길로 연 같은 주가 다르게 보이지
  /// 않는다. 기록이나 수치를 끝내 못 찾으면 지난 리포트로 되돌린다.
  Widget _historySentView(
    AppLocalizations l,
    List<TrainerClient> clients,
    TrainerClient client,
    DateTime week,
  ) {
    final AsyncValue<Map<String, ReportSendRecord>> weekHistory = ref.watch(
      reportSendHistoryProvider(week),
    );
    final Map<String, ReportSendRecord> log = withDemoSends(
      mergeSendLogs(
        weekHistory.valueOrNull ?? const <String, ReportSendRecord>{},
        ref.watch(reportSendLogProvider),
      ),
      <String>{for (final TrainerClient c in clients) c.id},
      week,
    );
    final ReportSendRecord? record = sendRecordFor(log, client.id, week);
    final AsyncValue<WeeklyReport> reportAsync = ref.watch(
      weeklyReportProvider((client: client, weekStart: week)),
    );
    final WeeklyReport? report = reportAsync.valueOrNull;
    if (record != null && report != null) {
      return SentReportView(
        key: ValueKey<String>('reports-history-sent-${ymd(week)}'),
        report: report,
        record: record,
        // 편집기 ① 과 같은 칼로리 `평소` 를 견준다(#2425).
        calorieBaseline: ref.watch(
          calorieBaselineProvider((client: client, weekStart: week)),
        ),
        backLabel: l.reportsHistoryBack,
        onBack: () => setState(() => _historyWeek = null),
        onRewrite: () {
          setState(() => _historyWeek = null);
          _openEditor(client.id, week);
        },
      );
    }
    if (weekHistory.isLoading || reportAsync.isLoading) {
      return const AppLoading();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _historyWeek = null);
    });
    return const AppLoading();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final clientsAsync = ref.watch(clientsProvider);
    final range = (
      from: ymd(_weekStart),
      to: ymd(DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 6)),
    );
    final weekSessions = ref.watch(scheduleRangeProvider(range));
    // 초안 구독은 본문(LayoutBuilder)보다 위에서 해야 해 본문이 고른 고객을
    // 볼 수 없다. 본문과 **같은 규칙**으로 여기서 한 번 더 고른다.
    final roster = clientsAsync.valueOrNull ?? const <TrainerClient>[];
    final TrainerClient? openClient = roster.isEmpty
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
    // 같은 [openClient] 이다.
    if (openClient != null) {
      ref.listen<AsyncValue<ReportFeedbackDraft>>(
        reportFeedbackDraftProvider((
          client: openClient,
          weekStart: _weekStart,
        )),
        (previous, next) {
          if (next.valueOrNull == null) return;
          if (_feedbackFor == _feedbackKeyOf(openClient.id, _weekStart)) {
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
              icon: AppIcons.reports,
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
          //
          // 기록의 원본은 서버다(#2288) — 세션 기록은 보낸 직후 서버 기록을
          // 다시 읽어 오는 사이를 잇는다. 새로고침해도 보낸 회원이 미전송으로
          // 돌아가지 않는다.
          final AsyncValue<Map<String, ReportSendRecord>> history = ref.watch(
            reportSendHistoryProvider(_weekStart),
          );
          if (history.isLoading) anyLoading = true;
          final Map<String, ReportSendRecord> sendLog = withDemoSends(
            mergeSendLogs(
              history.valueOrNull ?? const <String, ReportSendRecord>{},
              ref.watch(reportSendLogProvider),
            ),
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

          // ── 지난 리포트 ───────────────────────────────────────────────
          // 편집기(`client`)가 함께 열려 있으면 편집기가 먼저다.
          final String? historyFor = _clientId == null ? _historyFor : null;
          final TrainerClient? historyClient = historyFor == null
              ? null
              : clients.where((c) => c.id == historyFor).firstOrNull;
          if (historyClient != null) {
            final DateTime? week = _historyWeek;
            if (week != null) {
              return _historySentView(l, clients, historyClient, week);
            }
            return MemberReportHistoryView(
              client: historyClient,
              onBack: () => context.go(_locationFor(null)),
              onView: (DateTime week) => setState(() => _historyWeek = week),
              onOpenThisWeek: () =>
                  _openEditor(historyClient.id, weekStartOf(nowKst())),
            );
          }

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
                calorieBaseline: ref.watch(
                  calorieBaselineProvider((
                    client: sentReport.client,
                    weekStart: sentReport.weekStart,
                  )),
                ),
                onBack: () => setState(() => _sentViewFor = null),
                onHistory: () => _openHistory(sentFor),
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
              historyFailed: history.hasError && !history.isLoading,
              weekNav: weekNav,
              onSortChanged: (value) => setState(() => _sort = value),
              sentSort: _sentSort,
              onSentSortChanged: (value) => setState(() => _sentSort = value),
              onOpen: (entry) => _selectClient(entry.client.id),
              onOpenSent: (entry) =>
                  setState(() => _sentViewFor = entry.client.id),
              onHistory: (entry) => _openHistory(entry.client.id),
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
              // 머리 한 줄 — 목록으로 · 누구의 리포트 · (맨 오른쪽) 지난 리포트.
              // `지난 리포트` 는 스케줄 탭 `예약 슬롯` 과 같은 네이비 외곽선
              // 버튼이다(#2449). 글자 버튼이면 머리 줄에서 버튼으로 읽히지
              // 않았다. 초안 없이 바로 쓰기는 ② 에서 초안을 지우면 되므로 두지
              // 않는다.
              Row(
                children: <Widget>[
                  AppBackLink(
                    key: const ValueKey<String>('reports-back-to-list'),
                    label: l.reportsBackToWorkbench,
                    onPressed: () => context.go(_locationFor(null)),
                  ),
                  const SizedBox(width: OnCareSpacing.s8),
                  // 누구의 리포트인지는 편집기 머리에 한 번만 선다. 카드마다
                  // 이름을 적으면 네 카드가 같은 말을 네 번 하고, 정작 카드
                  // 제목이 말해야 할 `무엇을 보는 칸인가` 가 밀린다.
                  Expanded(
                    child: Text(
                      l.reportsClientWeekly(selected.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.oncare.text(
                        OnCareTypography.strong(OnCareTypography.titleSmall),
                      ),
                    ),
                  ),
                  const SizedBox(width: OnCareSpacing.s8),
                  // 이 회원에게 그동안 보낸 리포트 — 쓰기 전에 지난 주에
                  // 무엇을 말했는지 되짚는 길이다(#2394).
                  AppButton(
                    key: const ValueKey<String>('reports-editor-history'),
                    label: l.reportsHistoryButton,
                    variant: AppButtonVariant.strongOutline,
                    leadingIcon: AppIcons.history,
                    onPressed: () => _openHistory(selected.id),
                  ),
                ],
              ),
              const SizedBox(height: OnCareSpacing.s12),
              // 단계 표시는 AI 코칭의 추천안 만들기와 같은 것을 쓴다 — 같은
              // 일(여러 단계를 거쳐 회원에게 보낼 것을 만든다)이라 형태가
              // 달라야 할 이유가 없다.
              // 원 사이를 기본의 두 배로 벌린다(#2449) — 편집기 폭에서 세 단계가
              // 한데 붙어 보였다. 표시줄은 스스로 가운데에 서고, 모자란 폭에서는
              // 스스로 좁힌다.
              AppStepIndicator.numbered(
                keyPrefix: 'report-stage',
                labels: <String>[
                  l.reportsStepReview,
                  l.reportsStepWrite,
                  l.reportsStepSend,
                ],
                semanticsLabel: l.reportsStepperLabel,
                current: _stage,
                maxReached: _maxStage,
                onStepTap: (value) => setState(() => _stage = value),
                gap: reportStepperGap,
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
                        // ③ 전송은 회원이 받을 PDF 를 그대로 보여 준다(#2402).
                        // 글을 고치려면 `이전` 으로 ② 에 돌아간다.
                        if (_stage == ReportEditorStage.send.index)
                          ReportSendPreview(
                            report: data,
                            pdf: _previewFor(
                              l,
                              data,
                              _messageFor(l, data, savedDraft),
                            ),
                            onRetry: () => setState(_dropPreview),
                          )
                        else
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
                // ③ 에서는 미리보기 한 부가 다 만들어져야 인쇄할 수 있다.
                pdf: _stage == ReportEditorStage.send.index ? _preview : null,
                printing: _printing,
                onPrint: reportAsync.valueOrNull == null
                    ? null
                    : (bytes) => _print(reportAsync.value!, bytes),
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

/// 편집기 아래 줄 — 이전 / 다음, 마지막 단계에서는 인쇄 · 전송.
class _StepFooter extends StatelessWidget {
  const _StepFooter({
    required this.stage,
    required this.sending,
    required this.canSend,
    required this.pdf,
    required this.printing,
    required this.onPrint,
    required this.onPrev,
    required this.onNext,
    required this.onSend,
  });

  final int stage;
  final bool sending;

  /// 보낼 글이 있는가. 빈 피드백은 보내지 않는다.
  final bool canSend;

  /// ③ 에 떠 있는 PDF. 다 만들어지기 전이나 만들다 실패했으면 인쇄를 잠근다.
  final Future<Uint8List>? pdf;

  /// 인쇄 창이 떠 있다.
  final bool printing;

  /// [pdf] 로 만든 한 부를 인쇄한다.
  final ValueChanged<Uint8List>? onPrint;

  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool last = stage == 2;
    // 단계 흐름이라 `이전` 은 왼쪽 끝에 떼어 둔다 — 오른쪽 `다음` 과 한 쌍의
    // 선택이 아니라 되돌아가기다(#2465).
    return AppActionRow(
      leading: onPrev == null
          ? null
          : AppButton(
              key: const ValueKey<String>('report-step-prev'),
              label: l.reportsStepPrev,
              variant: AppButtonVariant.text,
              leadingIcon: AppIcons.chevronLeft,
              onPressed: onPrev,
            ),
      actions: <Widget>[
        if (last) ...<Widget>[
          // 인쇄는 전송 왼쪽이다(#2451). 보내기 전에 종이로 한 번 더 보는
          // 자리라 보조 버튼으로 둔다.
          FutureBuilder<Uint8List>(
            future: pdf,
            builder: (context, snapshot) {
              final Uint8List? bytes = snapshot.data;
              final bool ready = bytes != null && onPrint != null;
              return Tooltip(
                message: ready ? '' : l.reportsPrintNeedsPdf,
                child: AppButton(
                  key: const ValueKey<String>('report-step-print'),
                  label: l.reportsStepPrint,
                  variant: AppButtonVariant.secondary,
                  leadingIcon: AppIcons.print,
                  loading: printing,
                  onPressed: bytes == null || !ready || printing || sending
                      ? null
                      : () => onPrint!(bytes),
                ),
              );
            },
          ),
          // 빈 피드백으로 잠긴 버튼은 이유를 말하지 않으면 고장으로 읽힌다.
          Tooltip(
            message: canSend ? '' : l.reportsSendNeedsFeedback,
            child: AppButton(
              key: const ValueKey<String>('report-step-send'),
              label: l.reportsStepSend,
              // 전송 중에는 버튼 자리에서 진행을 보여 준다 — 같은 리포트가 두 번
              // 나가지 않게 잠그는 것도 이 자리다.
              loading: sending,
              onPressed: sending || !canSend ? null : onSend,
            ),
          ),
        ] else
          AppButton(
            key: const ValueKey<String>('report-step-next'),
            label: l.reportsStepNext,
            trailingIcon: AppIcons.chevronRight,
            onPressed: onNext,
          ),
      ],
    );
  }
}
