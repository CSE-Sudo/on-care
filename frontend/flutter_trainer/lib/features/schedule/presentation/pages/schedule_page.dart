import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/request_id.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/consultations/presentation/pages/consultations_page.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/cancel_session_dialog.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/consultation_inbox_action.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/reservation_slots_sheet.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_date_nav_bar.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_card.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_personal_routines.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_program_editor.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_sheet.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 스케줄 tab — 트레이너의 주간 시간표. (#988)
///
/// 왼쪽 시간축과 월~일 일곱 열의 격자 위에 세션 블록이 앉는다. 블록의 위치는
/// 시작 시각, 높이는 소요 시간이라 **빈 시간이 빈 칸으로 남는다** — 트레이너가
/// 달력을 여는 이유가 대개 "어디에 넣을 수 있나" 라서다.
///
/// 블록을 고르면 오른쪽(좁은 화면에서는 아래) 상세 패널이 그 세션을 연다.
/// 완료는 끝난 프로그램을 보여 주고 회원에게 보낼 수 있고, 예정은 계획(없으면
/// 힌트)과 채팅 동선을 연다. 추가·수정(15분 단위)·삭제·완료·취소·노쇼 처리가
/// 모두 그 패널에 있다.
///
/// 예전에는 `일`·`주` 두 보기가 있었다. `일` 은 하루치 목록이라 빈 시간을
/// 말하지 못했고, `주` 는 칩을 위에서부터 쌓아 같은 문제를 안고 있었다. 하나로
/// 모으면서 라우트의 `v=` 파라미터도 없앴다 — 고를 것이 없다.
///
/// 보고 있는 날은 URL(`?d=…`)에서 온다. 대시보드가 특정 날짜로 링크할 수 있고
/// 새로고침해도 그 자리에 남는다.
class SchedulePage extends ConsumerStatefulWidget {
  /// Creates the schedule tab.
  const SchedulePage({
    super.key,
    this.date,
    this.sessionId,
    this.openInbox = false,
  });

  /// Browsed day as `YYYY-MM-DD`; invalid or absent means today.
  final String? date;

  /// Session selected by a deep link from the dashboard.
  final String? sessionId;

  /// 들어오자마자 상담 요청함 창을 연다 — 알림·옛 주소가 상담함으로 보낼 때
  /// ([AppRoutes.consultations]). 연 뒤에는 주소에서 쿼리를 지운다(#2717).
  final bool openInbox;

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  /// The calendar day being browsed (defaults to today).
  late DateTime _selectedDay = _resolveDay(widget.date);

  /// 보이는 주의 월요일. `오늘 − 3일` 로 잡던 때에는 매일 다른 요일에서 주가
  /// 시작해, 화면이 말하는 "주" 와 사람이 말하는 "이번 주" 가 어긋났다(#988).
  ///
  /// 고른 날에서 **파생한다** — 따로 들고 있으면 둘이 어긋날 수 있다. "주만
  /// 넘기고 고른 날은 유지" 같은 요구가 생기면 그때 상태로 승격한다.
  DateTime get _weekStart => _mondayOf(_selectedDay);

  /// Session shown in the detail panel.
  late String? _selectedSessionId = widget.sessionId;

  /// 프로그램 전송이 진행 중인 세션. 두 번 눌러 두 번 보내지 않는다.
  String? _sendingProgramId;

  /// 세션별 **아직 보내지 않은** 개인운동. 카드 아래 전송 버튼이 무엇을 보낼지
  /// 이 값으로 정한다(#2224).
  final Map<String, List<RoutineExercise>> _unsentRoutines =
      <String, List<RoutineExercise>>{};

  /// 보내거나 보내지 않기로 한 뒤 목록을 다시 읽게 하는 판번호 — 키가 바뀌면
  /// 덩어리가 새로 서면서 서버에서 다시 읽는다(#2224).
  final Map<String, int> _routinesRevision = <String, int>{};

  /// 세션별 전송 멱등키. 실패한 시도의 키를 그대로 다시 써야 재시도가 중복
  /// 배정을 만들지 않는다(#581 과 같은 규약).
  final Map<String, String> _sendRequestIds = <String, String>{};

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// [d] 가 속한 주의 월요일.
  static DateTime _mondayOf(DateTime d) =>
      _dateOnly(d).subtract(Duration(days: d.weekday - DateTime.monday));

  /// Parses a `YYYY-MM-DD` route parameter, falling back to today. A
  /// malformed date in the URL should land the trainer on today rather
  /// than an error page.
  static DateTime _resolveDay(String? raw) {
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return _dateOnly(parsed ?? nowKst());
  }

  @override
  void initState() {
    super.initState();
    if (widget.openInbox) _openInboxFromLink();
  }

  /// 주소가 부른 상담 요청함 창을 연다. 쿼리를 먼저 지워, 창을 닫은 뒤
  /// 새로고침이나 뒤로 가기로 창이 다시 뜨지 않게 한다.
  void _openInboxFromLink() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(
        AppRoutes.scheduleAt(date: widget.date, sessionId: widget.sessionId),
      );
      showConsultationsDialog(context);
    });
  }

  @override
  void didUpdateWidget(SchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openInbox && !oldWidget.openInbox) _openInboxFromLink();
    // The URL is the source of truth: a link from the dashboard, or
    // back/forward, must move the calendar.
    if (widget.date != oldWidget.date) {
      setState(() => _selectedDay = _resolveDay(widget.date));
    }
    if (widget.sessionId != oldWidget.sessionId) {
      setState(() => _selectedSessionId = widget.sessionId);
    }
  }

  /// Moves to [day], keeping the URL in step so the view is shareable.
  ///
  /// 고른 날이 다른 주면 시간표도 그 주로 넘어간다 — 보고 있는 날이 화면 밖에
  /// 있는 상태를 만들지 않는다.
  void _selectDay(DateTime day) {
    final next = _dateOnly(day);
    setState(() {
      _selectedDay = next;
      _selectedSessionId = null;
    });
    context.go(AppRoutes.scheduleAt(date: ymd(next)));
  }

  /// `-1` = 지난 주, `+1` = 다음 주. 고른 날을 함께 옮긴다.
  void _shiftWeek(int direction) =>
      _selectDay(_selectedDay.add(Duration(days: 7 * direction)));

  /// 입력 폼 크기(560)의 가운데 모달로 [child] 를 연다(#1250, #1706).
  ///
  /// 예약 슬롯이 이 틀을 쓴다. 최대 높이(화면의 85%)까지는 내용만큼만 커지고,
  /// 넘치면 그 안에서만 스크롤한다 — 틀은 [AppDialog] 가 정한다. 내용 위젯은
  /// 제목을 그리지 않으므로 [title] 은 틀의 헤더에 한 번만 선다.
  ///
  /// 일정·프로그램·메모 편집은 같은 크기의 [AppDialog] 를 폼 위젯이 직접
  /// 짓는다 — 저장 버튼을 창 아래에 고정하려면 저장 중 상태를 쥔 쪽이 틀을
  /// 그려야 한다(#2465).
  Future<void> _openFormDialog(
    String title,
    Widget Function(BuildContext) builder,
  ) {
    return showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: title,
        size: AppDialogSize.medium,
        child: builder(dialogContext),
      ),
    );
  }

  /// 프로그램(또는 메모)을 가운데 모달로 연다.
  Future<void> _openProgramEditor(
    ScheduleSession session, {
    required bool noteOnly,
  }) {
    final AppLocalizations l = AppLocalizations.of(context);
    return showAppDialog<void>(
      context: context,
      builder: (dialogContext) => SessionProgramEditor(
        title: !noteOnly
            ? l.progEditTitle
            : session.type == SessionType.consultation
            ? l.schedEditConsultNote
            : l.schedEditNote,
        key: ValueKey<String>(
          noteOnly
              ? 'note-editor-${session.id}'
              : 'program-editor-${session.id}',
        ),
        session: session,
        noteOnly: noteOnly,
        onSaved: () => Navigator.of(dialogContext).pop(),
        onCancel: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  /// 일정을 가운데 모달로 연다 — [existing] 이 없으면 `새 일정 추가`,
  /// 있으면 `일정 수정`이다.
  Future<void> _openScheduleDialog({ScheduleSession? existing}) {
    final clients = ref.read(clientsProvider).valueOrNull ?? const [];
    if (existing == null && clients.isEmpty) return Future<void>.value();
    final AppLocalizations l = AppLocalizations.of(context);
    return showAppDialog<void>(
      context: context,
      builder: (dialogContext) {
        return SessionSheet(
          title: existing == null ? l.schedAddTitle : l.schedEditTitle,
          key: ValueKey<String>(
            existing == null
                ? 'new-session-editor'
                : 'schedule-editor-${existing.id}',
          ),
          clients: <ScheduleClientKey>[
            for (final c in clients) (id: c.id, name: c.name),
          ],
          date: existing?.date ?? _selectedYmd,
          existing: existing,
          inline: true,
          onSaved: () => Navigator.of(dialogContext).pop(),
          onCancel: () => Navigator.of(dialogContext).pop(),
        );
      },
    );
  }

  /// 예약 슬롯도 새 일정·일정 수정과 같은 가운데 모달로 연다 — 아래에서
  /// 올라오는 바텀시트만 여기서 유독 다른 모양이었다.
  Future<void> _openReservationSlotsSheet() {
    return _openFormDialog(
      AppLocalizations.of(context).slotManageTitle,
      (dialogContext) => ReservationSlotsSheet(selectedDay: _selectedDay),
    );
  }

  /// 확인창 — 제목·본문·반반 버튼. 확정하면 `true` 다.
  ///
  /// [showAppConfirmDialog] 와 같은 모양이지만 직접 짓는다. 테스트가 확정
  /// 버튼을 키([confirmKey])로 누르고, 삭제 확인은 본문이 두 문단이라 한
  /// 문자열로 합치면 문장 단위로 찾을 수 없다.
  Future<bool> _confirm({
    required String title,
    required List<Widget> body,
    required String confirmLabel,
    Key? confirmKey,
    bool destructive = false,
  }) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool? ok = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: title,
        showClose: false,
        footer: AppButtonPair(
          cancelLabel: l.actionCancel,
          onCancel: () => Navigator.of(dialogContext).pop(false),
          confirmKey: confirmKey,
          confirmLabel: confirmLabel,
          destructive: destructive,
          onConfirm: () => Navigator.of(dialogContext).pop(true),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: body,
        ),
      ),
    );
    return ok ?? false;
  }

  Future<void> _confirmDelete(ScheduleSession s) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ok = await _confirm(
      title: l.schedDeleteTitle,
      confirmLabel: l.actionDelete,
      destructive: true,
      body: <Widget>[
        Text(l.schedDeleteConfirm(timeRangeLabel(l, s), s.clientName)),
        const SizedBox(height: OnCareSpacing.s8),
        // 삭제와 취소를 가르는 문장이다(#871). 실제 PT 가 진행되지 않은
        // 경우까지 삭제로 처리하면 그 사실이 어디에도 남지 않는다.
        // 취소·노쇼 제안은 예정 세션에만 맞는 말이다 — 완료·취소·노쇼로
        // 이미 끝난 세션(전이는 예정에서만 갈린다)에는 그 조치 자체가
        // 불가능해, 다른 문구로 갈아 끼운다(#1226).
        Text(
          s.isFinished
              ? l.schedDeleteMeansRemoveFinished
              : l.schedDeleteMeansRemove,
          style: tokens
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textTertiary),
        ),
      ],
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(scheduleRepositoryProvider).deleteSession(s.id);
    } catch (error) {
      if (!mounted) return;
      // 서버 사유(회원 예약 일정은 지울 수 없다는 409 등)를 보인다(#2756).
      showAppToast(
        context,
        error is AppError
            ? serverDetailOr(l, error.message, l.schedDeleteFailed)
            : l.schedDeleteFailed,
        type: AppToastType.error,
      );
    }
  }

  /// 완료 처리 — flips the session to 완료 and logs it to the client's
  /// 운동기록. 확인 다이얼로그를 거친다 — 완료는 예정에서만 갈리는 종료
  /// 상태라 취소·노쇼처럼 되돌릴 UI가 없고, 잘못 눌러도 물릴 방법이
  /// 없다(#1227). 메모는 이 다이얼로그가 아니라 완료 뒤 상세 패널에서
  /// 언제든 남길 수 있어, 여기서는 빈 메모란을 보여주지 않는다.
  Future<void> _confirmComplete(ScheduleSession s) async {
    final AppLocalizations l = AppLocalizations.of(context);
    // 완료는 기록만 남긴다. 개인운동은 `PT 프로그램 전송` 에 함께 실린다
    // (#2224) — 회원이 "오늘 한 것" 과 "혼자 할 것" 을 한 번에 받는다.
    final ok = await _confirm(
      title: l.schedCompleteTitle,
      confirmLabel: l.legendDone,
      confirmKey: const ValueKey<String>('session-complete-confirm'),
      body: <Widget>[Text(l.schedCompleteConfirm(s.time, s.clientName))],
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .completeSession(s.id, note: '');
    } catch (error) {
      // A DB or programJson-decode failure must not escape to the UI —
      // the session stays 예정 and the trainer is told (review PR 237).
      // 서버가 사유를 주면(시작 전이라 완료할 수 없다는 400 등) 그것을 보인다.
      if (!mounted) return;
      showAppToast(
        context,
        error is AppError
            ? serverDetailOr(l, error.message, l.schedCompleteFailed)
            : l.schedCompleteFailed,
        type: AppToastType.error,
      );
    }
  }

  /// 이 일정 회원의 건강 목표 — 개인운동 효과 칸의 자동 문구를 정한다(#2570).
  /// 로스터에 없으면 빈 값이고, 그때는 유형별 기본 문구가 간다.
  String _clientGoal(ScheduleSession session) {
    final clients = ref.read(clientsProvider).valueOrNull ?? const [];
    for (final client in clients) {
      if (client.id == session.clientId) return client.goal;
    }
    return '';
  }

  /// 취소·노쇼로 끝난 PT 의 개인운동을 고쳐서 보낸다. (#2224)
  ///
  /// PT 가 열리지 않아 "그 PT 다음에 할 것" 이라는 전제가 깨졌으므로, 보내기
  /// 전에 구성을 볼 수 있어야 한다. 취소된 PT 에는 프로그램 만들기로 다시
  /// 붙일 수 없어(`예정` 세션만 찾는다) 고치는 자리가 이 창뿐이다.
  Future<void> _sendRoutinesOnly(ScheduleSession session) async {
    final l = AppLocalizations.of(context);
    final rows = _unsentRoutines[session.id] ?? const <RoutineExercise>[];
    if (rows.isEmpty) return;
    final edited = await showAppDialog<List<RoutineExercise>>(
      context: context,
      builder: (_) => SendPersonalRoutinesDialog(
        routines: rows,
        goal: _clientGoal(session),
      ),
    );
    if (edited == null || !mounted) return;
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .sendScheduledRoutines(session.id, items: edited);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        l.schedRoutinesSendFailed,
        type: AppToastType.error,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _unsentRoutines[session.id] = const <RoutineExercise>[];
      _routinesRevision[session.id] = (_routinesRevision[session.id] ?? 0) + 1;
    });
    showAppToast(context, l.schedRoutinesSent, type: AppToastType.success);
  }

  /// 상세 일정에서 개인운동을 바로 고친다 — 보내지는 않는다. (#2224)
  ///
  /// PT 직전에 회원 상태를 보고 운동 하나를 빼거나 시간을 줄이려고 프로그램
  /// 만들기까지 돌아갈 일은 아니다. 이미 보낸 것은 이 길로 오지 않는다 —
  /// 연필 메뉴가 그때는 이 항목을 세우지 않는다.
  Future<void> _editRoutines(ScheduleSession session) async {
    final l = AppLocalizations.of(context);
    final rows = _unsentRoutines[session.id] ?? const <RoutineExercise>[];
    if (rows.isEmpty) return;
    final edited = await showAppDialog<List<RoutineExercise>>(
      context: context,
      builder: (_) => SendPersonalRoutinesDialog(
        routines: rows,
        editOnly: true,
        goal: _clientGoal(session),
      ),
    );
    if (edited == null || !mounted) return;
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .updateScheduledRoutines(session.id, edited);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        l.schedRoutinesUpdateFailed,
        type: AppToastType.error,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _unsentRoutines[session.id] = edited;
      _routinesRevision[session.id] = (_routinesRevision[session.id] ?? 0) + 1;
    });
    showAppToast(context, l.schedRoutinesUpdated, type: AppToastType.success);
  }

  /// 보내지 않기로 정리한다 — 무엇을 짰다가 안 보냈는지는 남는다. (#2224)
  Future<void> _skipRoutines(ScheduleSession session) async {
    final l = AppLocalizations.of(context);
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .dismissScheduledRoutines(session.id);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        l.schedRoutinesSendFailed,
        type: AppToastType.error,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _unsentRoutines[session.id] = const <RoutineExercise>[];
      _routinesRevision[session.id] = (_routinesRevision[session.id] ?? 0) + 1;
    });
    showAppToast(context, l.schedRoutinesSkipped);
  }

  /// 취소 처리 — 취소 주체와 (선택) 사유를 받고 세션을 `취소` 로 남긴다. (#871)
  ///
  /// 삭제와 달리 일정 행이 남는다. 다이얼로그가 주체를 **고르게** 하는 까닭은
  /// 지표 때문이다 — 트레이너 사정의 취소와 고객 취소를 구분하지 않으면 나중에
  /// 회원의 낮은 이행률을 잘못 읽는다.
  ///
  /// 같은 창에서 `노쇼` 도 고른다(#2175). [allowNoShow] 는 시작 시각이 지난
  /// PT 에서만 참이다 — 오지 않았다는 사실은 그 시간이 지나야 안다(#2760).
  Future<void> _confirmCancel(
    ScheduleSession s, {
    required bool allowNoShow,
  }) async {
    final result = await showAppDialog<CancelSessionChoice>(
      context: context,
      builder: (context) =>
          CancelSessionDialog(session: s, allowNoShow: allowNoShow),
    );
    if (result == null || !mounted) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final repo = ref.read(scheduleRepositoryProvider);
    try {
      if (result.noShow) {
        await repo.markNoShow(s.id);
      } else {
        await repo.cancelSession(
          s.id,
          source: result.source,
          reason: result.reason,
        );
      }
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        result.noShow ? l.schedNoShowFailed : l.schedCancelFailed,
        type: AppToastType.error,
      );
    }
  }

  /// 완료한 세션의 프로그램을 그 회원에게 보낸다. (#822)
  ///
  /// 멱등키를 실어 보내므로 실패 후 다시 눌러도 회원의 루틴이 두 벌 생기지
  /// 않는다. 성공하면 세션 행에 남아, 화면이 '전송됨' 을 사실대로 말한다.
  ///
  /// 개인운동이 하나도 없으면 보내기 직전에 한 번 붙잡는다(#2280) — 보낸 뒤에는
  /// 이 PT 에 개인운동을 붙일 수 없어, "나중에 보내야지" 하고 PT 만 보내면 그
  /// 기회가 사라진다. 막지는 않는다: 개인운동을 줄 수 없는 날도 있다.
  Future<void> _sendProgram(ScheduleSession s) async {
    if (_sendingProgramId != null) return;
    final AppLocalizations l = AppLocalizations.of(context);
    // 읽어 온 뒤 하나도 없다는 것을 알 때만 묻는다 — 읽지 못한 PT 에 없다고
    // 말하지 않는다.
    if ((_unsentRoutines[s.id]?.isEmpty ?? false) &&
        acceptsFirstPersonalRoutines(s)) {
      final choice = await showNoPersonalRoutineDialog(
        context,
        title: l.schedNoRoutinesSendTitle,
        body: l.schedNoRoutinesSendBody,
        skipLabel: l.schedNoRoutinesSendSkip,
      );
      if (choice == null || !mounted) return;
      // 붙이러 가면 보내지 않는다 — 붙인 뒤 돌아와 트레이너가 다시 보낸다.
      // 코칭 탭에서 `PT에 반영` 을 누른 것이 회원 전송까지 되면, 누른
      // 버튼과 일어난 일이 달라진다.
      if (choice == NoPersonalRoutineChoice.add) {
        _goAddRoutines(s);
        return;
      }
      if (_sendingProgramId != null) return;
    }
    setState(() => _sendingProgramId = s.id);
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .sendProgram(
            s.id,
            clientRequestId: _sendRequestIds[s.id] ??= newClientRequestId(),
          );
      if (!mounted) return;
      _sendRequestIds.remove(s.id); // 다음 전송은 새 시도다.
      // 개인운동도 이 전송에 함께 실려 갔다(#2224). 갈래를 다시 읽지 않으면
      // 이미 보낸 것에 `아직 회원에게 가지 않았어요` 가 그대로 남는다.
      setState(() {
        _unsentRoutines[s.id] = const <RoutineExercise>[];
        _routinesRevision[s.id] = (_routinesRevision[s.id] ?? 0) + 1;
      });
      showAppToast(
        context,
        l.schedSentTo(s.clientName),
        type: AppToastType.success,
      );
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, l.coachSendFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _sendingProgramId = null);
    }
  }

  /// 개인운동이 없는 PT 의 `개인운동 추가` — 그 회원의 코칭 탭 개인운동
  /// 단계로 간다. (#2280)
  ///
  /// 개인운동은 AI 제안을 받아 짜는 것이라 스케줄에서 빈 창으로 짜지 않는다.
  /// 프로그램도 AI 로 한 번 짜고, 고치는 것만 이 카드의 부분 창에서 한다.
  /// 붙이면 코칭 탭이 이 일정으로 돌려보낸다.
  void _goAddRoutines(ScheduleSession s) {
    final String? clientId = s.clientId ?? _rosterIdByName(s.clientName);
    if (clientId == null) {
      context.go(AppRoutes.clients);
      return;
    }
    context.go(
      AppRoutes.coachingAttach(
        clientId,
        sessionId: s.id,
        date: s.date,
        requestId: newClientRequestId(),
      ),
    );
  }

  /// 일정에 회원 id 가 없을 때(예전에 이름으로만 잡은 일정) 로스터에서 이름으로
  /// 찾는다 — [_openProgram] 과 같은 방식이다.
  String? _rosterIdByName(String name) {
    final clients = ref.read(clientsProvider).valueOrNull ?? const [];
    for (final c in clients) {
      if (c.name == name) return c.id;
    }
    return null;
  }

  /// 계획 없는 세션의 `프로그램 추가` — 이 카드 안이 아니라 그 고객의 코칭
  /// 탭으로 이동한다. 프로그램은 AI 코칭 탭에서 짓고 보내는 것이라, 스케줄
  /// 카드에는 편집기를 두지 않는다(#1247).
  void _openProgram(ScheduleSession s) {
    final clients = ref.read(clientsProvider).valueOrNull ?? const [];
    final match = clients.where((c) => c.name == s.clientName);
    if (match.isEmpty) {
      context.go(AppRoutes.clients);
      return;
    }
    context.go(AppRoutes.coachingFor(match.first.id));
  }

  String get _selectedYmd => ymd(_selectedDay);

  /// 날짜 행 오른쪽에 붙는 `오늘`. (#882, #988)
  ///
  /// 예전에는 페이지 헤더 오른쪽 끝에서 `예약 슬롯`·`새 일정` 같은 문서 액션과
  /// 섞여 있었다. 날짜를 바꾸는 컨트롤인데 조작 대상(날짜 행)과 100px 넘게
  /// 떨어져 있었다. 함께 있던 `일|주` 는 보기가 하나로 모이면서 사라졌다.
  ///
  /// 이번 주 오늘을 보고 있으면 아무것도 그리지 않는다 — 눌러도 달라질 것이
  /// 없는 버튼이다.
  ///
  /// 흰 채움이던 동안에는 회색 페이지 위에서 버튼만 떠 보였다. 칠하지 않는
  /// 네이비 외곽선이라 페이지 배경이 그대로 비친다(#2180).
  Widget _todayControl() {
    final AppLocalizations l = AppLocalizations.of(context);
    final today = _dateOnly(nowKst());
    if (_selectedDay == today) return const SizedBox.shrink();
    return AppButton(
      label: l.labelToday,
      variant: AppButtonVariant.strongOutline,
      leadingIcon: AppIcons.calendar,
      onPressed: () => _selectDay(today),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // Keep the client stream live so the booking sheet and the chat
    // shortcut have data even when this tab is the first one opened.
    ref.watch(clientsProvider);
    // 오늘 버튼 계산은 [_todayControl] 안에 있다 — 그 버튼이 헤더가 아니라
    // 날짜 행에 살기 때문이다(#882).

    return AppWebPage(
      title: l.schedTitle,
      subtitle: dateLabel(l, _selectedDay),
      // 검색 바는 헤더 가운데 자리다 — 다른 탭과 같은 가로 위치에 서고, 자리가
      // 모자라면 스스로 아이콘으로 접힌다.
      headerCenter: const ClientSearchBar(),
      // 날짜 행은 async `when()` **바깥**에 있다: 주를 넘길 때마다 새 provider
      // 가 `loading` 으로 시작하는데, 그때 페이지 전체를 스피너로 비우면 날짜
      // 행이 깜빡인다. 격자만 async 상태를 따른다(review PR 245).
      body: _buildTimetable(),
    );
  }

  /// 주간 시간표와 그 오른쪽(좁은 화면에서는 아래)의 상세 패널. (#988)
  ///
  /// 한 번의 범위 질의가 주 전체를 받친다 — 요일마다 스트림을 하나씩 열면 주를
  /// 넘길 때마다 일곱 개가 함께 흔들린다.
  Widget _buildTimetable() {
    final AppLocalizations l = AppLocalizations.of(context);
    final consultationInbox = ref.watch(consultationInboxEnabledProvider);
    final pendingConsultations = consultationInbox
        ? ref.watch(consultationPendingCountProvider).valueOrNull
        : null;
    final start = _weekStart;
    final end = start.add(const Duration(days: 6));
    final range = (from: ymd(start), to: ymd(end));
    final week = ref.watch(scheduleRangeProvider(range));

    // 날짜 행은 **시간표 쪽 열 안**에 있다. 페이지 폭 전체에 걸쳐 두면 `오늘`
    // 이 상세 패널 위에 떠, 무엇을 조작하는 버튼인지 자리로 말하지 못한다.
    // 시간표 안에 두면 오른쪽 끝이 일요일 칸 위로 온다(#988).
    // 예약 슬롯·상담 요청 — 화면 머리 오른쪽 끝은 모든 탭이 알림 종 하나만
    // 두는 자리라 머리에서 내렸다(#2628). 넓은 화면에서는 상세 패널 칸의 머리에,
    // 좁은 화면에서는 날짜 행의 `새 일정` 왼쪽에 선다.
    final List<Widget> intakeActions = <Widget>[
      AppButton(
        key: const ValueKey<String>('schedule-open-slots'),
        label: l.schedSlots,
        // `오늘` 과 같은 네이비 외곽선이다 — 둘 다 페이지 배경 위에 선다(#2180).
        variant: AppButtonVariant.strongOutline,
        leadingIcon: AppIcons.eventAvailable,
        onPressed: () => _openReservationSlotsSheet(),
      ),
      if (consultationInbox)
        ConsultationInboxAction(
          pending: pendingConsultations,
          onTap: () => showConsultationsDialog(context),
        ),
    ];
    Widget navBar({required bool withIntake}) => Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
      child: ScheduleDateNavBar(
        start: start,
        end: end,
        onShift: _shiftWeek,
        trailing: _todayControl(),
        actions: withIntake ? intakeActions : const <Widget>[],
        // `새 일정` 은 이 행의 오른쪽 끝, 일요일 칸 위에 선다. 예전에는 페이지
        // 헤더의 다른 문서 액션과 섞여 있어, 무엇을 조작하는 버튼인지 시간표와
        // 자리로 이어지지 않았다(#882 와 같은 이유).
        newSession: AppButton(
          label: l.schedNewSession,
          leadingIcon: AppIcons.add,
          onPressed: () => _openScheduleDialog(),
        ),
      ),
    );

    return Builder(
      builder: (context) {
        final sessions = week.valueOrNull ?? const <ScheduleSession>[];
        // 요일 머리글은 async 상태와 상관없이 남는다 — 주를 넘길 때마다
        // 날짜 줄이 스피너로 사라지면 고를 자리가 잠깐 없어진다.
        final Widget? bodyOverride = switch (week) {
          // 다시 시도할 동작이 없어(스트림이 스스로 다시 붙는다) 버튼 없는
          // 빈 화면 틀에 오류 아이콘을 얹는다.
          AsyncError() => AppEmptyState(
            title: l.schedLoadFailed,
            icon: AppIcons.offline,
          ),
          AsyncValue(hasValue: false) => const AppLoading(),
          _ => null,
        };

        // 상세 패널이 무엇을 열지 — 고른 세션이 우선이고, 없으면 고른
        // 날의 첫 세션이다. 빈 패널로 두면 시간표만 보고 아무것도 다룰
        // 수 없는 화면이 된다.
        ScheduleSession? selected;
        for (final session in sessions) {
          if (session.id == _selectedSessionId &&
              session.date == _selectedYmd) {
            selected = session;
            break;
          }
        }
        if (selected == null) {
          for (final session in sessions) {
            if (session.date == _selectedYmd && !session.isGap) {
              selected = session;
              break;
            }
          }
        }

        final grid = ScheduleWeekTimetable(
          weekStart: start,
          sessions: sessions,
          selectedDay: _selectedDay,
          selectedSessionId: selected?.id,
          bodyOverride: bodyOverride,
          onPickDay: _selectDay,
          onPickSession: (session) {
            final day = DateTime.tryParse(session.date);
            if (day == null) return;
            setState(() {
              _selectedDay = _dateOnly(day);
              _selectedSessionId = session.id;
            });
            context.go(
              AppRoutes.scheduleAt(date: session.date, sessionId: session.id),
            );
          },
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final stacked = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                navBar(withIntake: true),
                Expanded(child: grid),
              ],
            );
            // 시간표와 상세 패널은 분할 기준 폭에서 나란히 선다. 두 열 기준 폭
            // (1080)으로 두면 사이드바를 편 1280 창에서도 패널이 아래로 밀린다.
            if (constraints.maxWidth < OnCareLayout.splitBreakpoint) {
              // 좁은 화면에는 오른쪽에 패널을 둘 폭이 없다. 예전에는
              // 패널을 통째로 버렸는데, 탭 핸들러는 그대로 살아 있어서
              // 누르면 선택만 바뀌고 화면은 그대로였다 — 트레이너에게는
              // 버튼이 고장 난 것으로 보인다(#881).
              //
              // 같은 패널을 시간표 아래로 쌓는다. 표현을 바꾸지 않으므로
              // 넓은 화면에서 익힌 것이 좁은 화면에서도 그대로 통한다.
              if (selected == null) return stacked;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(flex: 3, child: stacked),
                  Container(
                    height: OnCareSize.hairline,
                    color: OnCareColors.lineSubtle,
                  ),
                  Expanded(flex: 2, child: _buildWeekDetail(selected)),
                ],
              );
            }
            // 머리(날짜 행 · 패널 칸 머리)를 **한 줄에** 세우고 몸(격자 · 카드)을
            // 그 아래 한 줄에 세운다 — 같은 `Row` 라 높이가 저절로 맞는다(#1008).
            //
            // 패널 칸의 머리에는 예약 슬롯·상담 요청이 서고, `상세 일정` 제목은
            // 그 아래 카드 위로 내려간다(#2628). 둘 다 시간표에 일정을 들이는
            // 동작이라 `새 일정` 과 같은 높이에 선다.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          right: OnCareLayout.splitGap,
                        ),
                        child: navBar(withIntake: false),
                      ),
                    ),
                    const SizedBox(width: OnCareSize.hairline),
                    SizedBox(
                      width: _panelWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: OnCareSpacing.s16,
                          bottom: OnCareSpacing.s8,
                        ),
                        child: Row(
                          key: const ValueKey<String>(
                            'schedule-intake-actions',
                          ),
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            for (
                              int i = 0;
                              i < intakeActions.length;
                              i++
                            ) ...<Widget>[
                              if (i > 0)
                                const SizedBox(width: OnCareSpacing.s8),
                              intakeActions[i],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            right: OnCareLayout.splitGap,
                          ),
                          child: grid,
                        ),
                      ),
                      Container(
                        width: OnCareSize.hairline,
                        color: OnCareColors.lineSubtle,
                      ),
                      SizedBox(
                        width: _panelWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _panelHeader(),
                            Expanded(
                              child: _buildWeekDetail(
                                selected,
                                withTitle: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 상세 패널의 폭.
  static const double _panelWidth = OnCareLayout.splitListWidth;

  /// 넓은 화면의 패널 머리글 — 시간표 머리와 같은 높이에서 시작한다(#1008,
  /// #2628). 선택한 일정이 없어도 자리를 말한다.
  ///
  /// 문구가 `스케줄` 이던 때에는 페이지 제목과 같은 말이라 그 자리가 무엇인지
  /// 말하지 못했다 — 왼쪽 격자도 스케줄이고 오른쪽 카드도 스케줄이다.
  Widget _panelHeader() {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OnCareSpacing.s16,
        0,
        0,
        OnCareSpacing.s8,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(l.schedDetailTitle, style: _panelTitleStyle()),
      ),
    );
  }

  TextStyle _panelTitleStyle() => context.oncare
      .text(OnCareTypography.titleSmall)
      .copyWith(color: OnCareColors.textPrimary);

  Widget _buildWeekDetail(ScheduleSession? session, {bool withTitle = true}) {
    final l = AppLocalizations.of(context);
    if (session == null) {
      return AppEmptyState(title: l.schedEmptyDay, icon: AppIcons.eventBusy);
    }

    final day = DateTime.tryParse(session.date) ?? _selectedDay;
    final DateTime now = nowKst();
    final today = _dateOnly(now);
    // 날짜가 아니라 시작 시각으로 가른다(#2760) — 오늘 저녁 PT 를 오전에
    // 완료·노쇼로 처리하면 하지 않은 운동이 기록되거나 오지 않았다고 적힌다.
    final bool started = sessionHasStarted(session, now);
    final dateText = day == today
        ? l.labelToday
        : l.dateMonthDay(day.month, day.day);
    return ListView(
      key: const Key('week-detail'),
      padding: const EdgeInsets.all(OnCareSpacing.s16),
      children: <Widget>[
        // 넓은 화면에서는 패널 머리글([_panelHeader])이 따로 서므로 빼둔다.
        if (withTitle) ...<Widget>[
          Text(l.schedDetailTitle, style: _panelTitleStyle()),
          const SizedBox(height: OnCareSpacing.s12),
        ],
        SessionCard(
          session: session,
          onEditSchedule: () => _openScheduleDialog(existing: session),
          onEditProgram: () => _openProgramEditor(session, noteOnly: false),
          onGoToProgram: () => _openProgram(session),
          onEditNote: () => _openProgramEditor(session, noteOnly: true),
          onDelete: () => _confirmDelete(session),
          // 담당이 끊긴 회원의 일정은 완료할 수 없다 — 회원 운동 기록에 적히는
          // 일이라 서버가 막는다(#2281, #2589).
          onComplete: (session.isUpcoming && started && !session.memberDetached)
              ? () => _confirmComplete(session)
              : null,
          // 취소는 앞으로의 약속에도 열려 있다 — 거두는 것이 취소다. 노쇼는
          // 같은 창의 선택지로, 시작 시각이 지난 약속에만 선다: 오지 않았다는
          // 사실은 그 시간이 지나야 안다(#871, #2175, #2760).
          onCancel: session.isUpcoming
              ? () => _confirmCancel(session, allowNoShow: started)
              : null,
          programDateLabel: dateText,
          sendingProgram: _sendingProgramId == session.id,
          onSendProgram: () => _sendProgram(session),
          // PT 에서 할 것과 회원이 혼자 할 것을 한 카드에서 갈라 보여 준다
          // (#2224). 마무리된 PT 라면 여기서 보낼지도 정한다.
          // 해제 회원의 일정은 개인운동을 읽지 않는다 — 회원 코칭 기록이다(#2589).
          personalRoutines: session.memberDetached
              ? null
              : SessionPersonalRoutines(
                  // 코칭 탭에서 붙이고 돌아오면(#2280) 이 화면은 그동안 떠
                  // 있지 않아 바뀐 것을 모른다 — 붙인 쪽이 올린 판번호로 다시
                  // 읽는다.
                  key: ValueKey<String>(
                    'personal-routines-${session.id}'
                    '-${_routinesRevision[session.id] ?? 0}'
                    '-${ref.watch(scheduledRoutinesRevisionProvider)}',
                  ),
                  sessionId: session.id,
                  finished: !session.isUpcoming,
                  showEmpty: acceptsFirstPersonalRoutines(session),
                  onAdd: () => _goAddRoutines(session),
                  // 읽지 못했으면 null — 있는지 없는지 모르는 채로 둔다.
                  onChanged: (rows) => setState(() {
                    if (rows == null) {
                      _unsentRoutines.remove(session.id);
                    } else {
                      _unsentRoutines[session.id] = rows;
                    }
                  }),
                ),
          hasUnsentRoutines:
              (_unsentRoutines[session.id] ?? const <RoutineExercise>[])
                  .isNotEmpty,
          onSendRoutines: () => unawaited(_sendRoutinesOnly(session)),
          onSkipRoutines: () => unawaited(_skipRoutines(session)),
          onEditRoutines: () => unawaited(_editRoutines(session)),
        ),
      ],
    );
  }
}
