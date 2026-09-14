import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/request_id.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/design_system/tokens/colors.dart';
import 'package:oncare_trainer/design_system/tokens/layout.dart';
import 'package:oncare_trainer/design_system/tokens/radius.dart';
import 'package:oncare_trainer/design_system/tokens/spacing.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_diet_period_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_exercise_status_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_period_section.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/program_draft_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/ai_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/ai_routine_item.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/features/coaching/presentation/pages/ai_routine_options_flow.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_editor_workspace.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_final_review_card.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_nutrition_summary_card.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_template_dialog.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_suggestion_review_card.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show elapsedWeekdays, weekdayCount, weekdayLabels;
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/app_toast.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';
import 'package:oncare_trainer/shared/widgets/icon_label.dart';
import 'package:oncare_trainer/shared/widgets/mini_charts.dart';
import 'package:oncare_trainer/shared/widgets/page_scaffold.dart';
import 'package:oncare_trainer/shared/widgets/section_card.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppSegmentedToggle;

/// AI 코칭 — the workspace where a client's data becomes a routine.
///
/// Pick a client, read the AI's take on their diet and its reasoning,
/// tweak names/minutes, drop suggestions, add your own exercises, then
/// send it two ways: as homework to the member's app, or as the program
/// attached to a PT session on the schedule.
///
/// This is a top-level destination rather than an action buried in the
/// client detail because it is the product's differentiator, and because
/// the trainer plans several clients in one sitting. Arriving from a
/// client (`?client=<id>`) preselects them.
class CoachingPage extends ConsumerStatefulWidget {
  /// Creates the AI coaching workspace.
  const CoachingPage({super.key, this.clientId});

  /// Client to preselect, from the `client` query parameter.
  final String? clientId;

  @override
  ConsumerState<CoachingPage> createState() => _CoachingPageState();
}

class _CoachingPageState extends ConsumerState<CoachingPage> {
  /// Selected client; null until clients load (defaults to the first).
  late String? _clientId = widget.clientId;
  final Map<String, String> _typeEdits = <String, String>{};
  final Map<String, List<AiRoutineItem>> _generatedRecommendations =
      <String, List<AiRoutineItem>>{};
  ProgramTemplate? _appliedTemplate;
  int _templateRevision = 0;
  int _editorRevision = 0;

  /// AI 1~3단계와 프로그램 편집기 중 어느 쪽을 표시할지 정한다.
  bool _aiWizardVisible = true;
  /// `일정 추가` 가 방금 성공했다 — 성공 토스트가 떠 있는 동안 같은 구성을
  /// 다시 보내지 못하게 잠그고, 잠시 뒤 편집기를 새로 세운다.
  bool _sent = false;
  Timer? _sentTimer;

  /// `일정 추가` 가 진행 중인 회원들. 여러 회원을 동시에 보낼 수 있지만 한
  /// 회원에게는 한 번에 하나만 나간다 — 회원을 바꿔도 앞 요청은 계속 돈다.
  final Set<String> _sendingClientIds = <String>{};

  /// 회원별 미완료 전송의 멱등키와, 그 키를 만든 구성(초안·날짜·시간)의 지문.
  /// 실패 후 같은 구성으로 다시 보내면 같은 키를 쓰고(응답 유실 뒤 중복 방지,
  /// #581·#1580), 구성이 바뀌었거나 성공하면 새로 잡는다.
  final Map<String, ({String fingerprint, String id})> _sendRequests =
      <String, ({String fingerprint, String id})>{};

  /// PT 스케줄에 등록할 날. 기본값은 오늘.
  DateTime _registerDate = _todayKst();

  /// PT 스케줄에 등록할 시작·종료 시각. 기존 기본 시작은 오전 10시,
  /// 기본 종료는 한 시간 뒤이며 둘 다 사용자가 바꿀 수 있다.
  TimeOfDay _registerStartTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _registerEndTime = const TimeOfDay(hour: 11, minute: 0);

  int get _registerDurationMinutes =>
      _registerEndTime.hour * 60 +
      _registerEndTime.minute -
      (_registerStartTime.hour * 60 + _registerStartTime.minute);

  /// A template save is in flight — blocks re-entry so one click is one
  /// template (#1028).
  bool _savingTemplate = false;

  @override
  void dispose() {
    _sentTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(CoachingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Following a second "AI 루틴 만들기" link (from another client's
    // 개요) must switch the workspace, not silently keep the old one.
    if (widget.clientId != null && widget.clientId != oldWidget.clientId) {
      _selectClient(widget.clientId!);
    }
  }

  void _selectClient(String id) {
    if (_clientId == id) return;
    setState(() {
      _clientId = id;
      // A different client gets a clean slate, like the mock.
      _typeEdits.clear();
      _sent = false;
      _registerDate = _todayKst();
      _registerStartTime = const TimeOfDay(hour: 10, minute: 0);
      _registerEndTime = const TimeOfDay(hour: 11, minute: 0);
      _appliedTemplate = null;
      _templateRevision = 0;
      _editorRevision = 0;
      _aiWizardVisible = true;
      // NOTE: _sendingClientIds is intentionally NOT cleared — writes for
      // other clients keep being tracked while the selection changes.
    });
    _sentTimer?.cancel();
  }

  bool _isStillSelected(String clientId) =>
      _clientId == null || _clientId == clientId;

  /// 지금 편집기 구성을 프로그램 템플릿으로 저장한다 (#1028).
  ///
  /// 저장 대상은 항상 "고객 리스트 아래 프로그램 템플릿" 목록이다 — 눌렀던
  /// 자리가 곧 저장된 위치라 별도의 "저장한 프로그램" 보관함을 따로 두지
  /// 않는다. 템플릿은 세션 없이 운동 이름·시간·종류만 담는 가벼운 블록이라
  /// (`program_template_dialog.dart` 참고), 세트·횟수·중량 같은 값은 여기서
  /// 저장되지 않는다 — 회원마다 달라지는 값은 템플릿을 적용한 뒤 편집기에서
  /// 다시 정한다는 기존 템플릿 개념을 그대로 따른다.
  ///
  /// 누를 때마다 새 템플릿을 만든다 — "수정 저장" 같은 덮어쓰기 개념을 따로
  /// 두지 않아, 버튼은 항상 `저장`으로 남는다.
  ///
  /// 반환값(성공 여부)은 호출부(편집기의 북마크 버튼)가 저장 전/후 아이콘
  /// 상태(outline↔filled)를 구분하는 데만 쓴다 — 저장 자체의 동작·API 호출·
  /// 스낵바 안내는 그대로다.
  Future<bool> _saveTemplate(ProgramEditorState draft) async {
    if (_savingTemplate) return false;
    final l = AppLocalizations.of(context);
    final exercises = <TemplateExercise>[
      for (final session in draft.sessions)
        for (final exercise in session.exercises)
          if (exercise.name.trim().isNotEmpty)
            TemplateExercise(
              name: exercise.name.trim(),
              // 근력은 세트에서 환산한 분을 담는다 — 템플릿의 총 시간이
              // 유형과 무관하게 한 축으로 읽혀야 한다 (#1276).
              minutes: exercise.effectiveMinutes,
              type: kRoutineTypes.contains(exercise.type)
                  ? exercise.type
                  : kRoutineTypes.first,
              // 근력이면 편집기에서 정한 세트·중량을 그대로 템플릿에 담는다
              // — 비워 두면 다시 열었을 때 기본값으로 되돌아간 것처럼 보인다.
              sets: exercise.isStrength ? exercise.sets : 0,
              weight: exercise.isStrength ? exercise.weight : 0,
            ),
    ];
    if (exercises.isEmpty) {
      showAppToast(context, l.coachTemplateExerciseRequired);
      return false;
    }
    setState(() => _savingTemplate = true);
    try {
      await ref
          .read(trainerProgramTemplateRepositoryProvider)
          .create(
            name: draft.name.trim(),
            goal: draft.goal.trim(),
            exercises: exercises,
          );
      ref.invalidate(programTemplatesProvider);
      if (!mounted) return false;
      setState(() => _savingTemplate = false);
      showAppToast(context, l.programDraftSaved, kind: AppToastKind.success);
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      setState(() => _savingTemplate = false);
      showAppToast(
        context,
        error is AppError
            ? serverDetailOr(l, error.message, l.coachTemplateSaveFailed)
            : l.coachTemplateSaveFailed,
        kind: AppToastKind.error,
      );
      return false;
    }
  }

  /// 편집기의 `일정 추가` 가 부른다 — 확인창을 띄우고, 확인되면 회원 배정과
  /// PT 일정 등록을 **한 명령으로** 보낸다(#1580). 예전에는 두 API 를 차례로
  /// 불러 배정만 되고 일정은 빠진 반쪽 상태가 남을 수 있었다.
  ///
  /// 확인한 순간의 대상 회원·날짜·시간·구성을 붙잡아 보낸다 — 요청이 도는
  /// 동안 회원을 바꿔도 그 회원의 작업은 확인한 값 그대로 끝난다. 실패하면
  /// 편집기·날짜·시간을 그대로 두어 같은 멱등키로 다시 보낼 수 있고, 성공
  /// 표시는 명령이 끝난 뒤에만 뜬다.
  Future<void> _sendProgram(
    TrainerClient client,
    ProgramEditorState draft,
  ) async {
    if (_sent ||
        _sendingClientIds.contains(client.id) ||
        !draft.supportsAssignment ||
        _registerDurationMinutes <= 0 ||
        !_registerDateStillValid()) {
      return;
    }
    final l = AppLocalizations.of(context);
    final List<ScheduleSession> candidates;
    try {
      candidates = await _attachCandidates(client);
    } catch (error) {
      if (mounted && _isStillSelected(client.id)) {
        showAppToast(
          context,
          _sendFailureMessage(l, error),
          kind: AppToastKind.error,
        );
      }
      return;
    }
    if (!mounted || !_isStillSelected(client.id)) return;
    final confirmation = await showProgramAssignConfirmDialog(
      context,
      clientName: client.name,
      registerDate: _registerDate,
      registerStartTime: _registerStartTime,
      registerEndTime: _registerEndTime,
      candidates: candidates,
    );
    if (confirmation == null || !mounted || !_isStillSelected(client.id)) {
      return;
    }
    // 확인창을 띄워 둔 사이에도 자정이 지날 수 있다 — 보내기 직전에 한 번 더.
    if (!_registerDateStillValid()) return;
    final sentFor = client.id;
    final registerDate = _registerDate;
    final date = ymd(registerDate);
    final time = _registerStartHhmm;
    final durationMinutes = _registerDurationMinutes;
    final requestId = _requestIdFor(sentFor, <Object?>[
      programAssignToJson(draft),
      date,
      time,
      durationMinutes,
      confirmation.sessionId,
    ]);
    setState(() => _sendingClientIds.add(sentFor));
    final bool attachedToExisting;
    try {
      attachedToExisting = await ref
          .read(scheduleRepositoryProvider)
          .registerProgramSchedule(
            date: date,
            clientId: sentFor,
            clientName: client.name,
            time: time,
            durationMinutes: durationMinutes,
            assignment: programAssignToJson(draft, clientRequestId: requestId),
            program: _draftProgram(draft),
            sessionId: confirmation.sessionId,
          );
    } catch (error) {
      if (!mounted) return;
      setState(() => _sendingClientIds.remove(sentFor));
      if (_isStillSelected(sentFor)) {
        showAppToast(
          context,
          _sendFailureMessage(l, error),
          kind: AppToastKind.error,
        );
      }
      return;
    }
    _sendRequests.remove(sentFor);
    if (!mounted) return;
    // 3열 `전송 이력`(`assignedRoutinesProvider`)은 실 API 모드에서 1회성
    // fetch 라 다시 읽으라고 말해 줘야 한다(#1029). 일정 쪽은 저장소가
    // 스스로 다시 읽는다.
    ref.invalidate(assignedRoutinesProvider(sentFor));
    final stillSelected = _isStillSelected(sentFor);
    setState(() {
      _sendingClientIds.remove(sentFor);
      if (stillSelected) _sent = true;
    });
    if (!stillSelected) return;
    // 등록 완료는 인라인 문구가 아니라 다른 성공 알림과 같은 상단
    // 토스트로 뜬다(#1536) — "스케줄로 이동" 액션으로 바로 그 날짜의
    // 스케줄 탭을 연다. `AppToastKind`엔 경고 종류가 없어, 기존 세션에
    // 붙은 경우도 실패는 아니므로 `info`로 알린다.
    showAppToast(
      context,
      attachedToExisting
          ? l.coachRegisteredAttachedExisting(_dateChipLabel(l, registerDate))
          : l.coachRegisteredOn(_dateChipLabel(l, registerDate)),
      kind: attachedToExisting ? AppToastKind.info : AppToastKind.success,
      action: AppToastAction(
        label: l.coachGoToSchedule,
        onTap: () => context.go(AppRoutes.scheduleAt(date: date)),
      ),
    );
    _sentTimer?.cancel();
    _sentTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _sent = false;
        // 보낸 뒤에는 편집기를 새로 세운다 — 이미 나간 구성이 그대로
        // 남아 있으면 한 번 더 보낼 수 있는 것처럼 읽힌다.
        _editorRevision++;
      });
    });
  }

  /// 등록할 시작 시각 `HH:mm`.
  String get _registerStartHhmm =>
      '${_registerStartTime.hour.toString().padLeft(2, '0')}:'
      '${_registerStartTime.minute.toString().padLeft(2, '0')}';

  /// 고른 날짜·시간대와 겹치는 이 회원의 예정 세션(시작 시각 순). 확인창이
  /// 새 일정인지 기존 일정 연결인지를 저장 전에 보여 주려고 읽는다(#1581).
  /// 서버가 같은 규칙으로 다시 고르므로, 그 사이 일정이 바뀌어 여기서 본 것과
  /// 어긋나면 저장이 409 로 멈춘다.
  Future<List<ScheduleSession>> _attachCandidates(TrainerClient client) async {
    final date = ymd(_registerDate);
    final time = _registerStartHhmm;
    final duration = _registerDurationMinutes;
    final sessions = await ref
        .read(scheduleRepositoryProvider)
        .fetchClientSessionsOn((id: client.id, name: client.name), date);
    return sessions
        .where(
          (session) =>
              session.isUpcoming &&
              session.date == date &&
              timeRangesOverlap(
                session.time,
                session.durationMinutes,
                time,
                duration,
              ),
        )
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  /// 등록 날짜가 아직 오늘 이후인가. 화면을 연 채 자정을 넘겨 전날이 됐으면
  /// 오늘로 되돌리고 알린 뒤 false — 전날 날짜로는 보내지 않는다(#1582).
  bool _registerDateStillValid() {
    final today = _todayKst();
    if (!_registerDate.isBefore(today)) return true;
    setState(() => _registerDate = today);
    showAppToast(
      context,
      AppLocalizations.of(context).programEditorRegisterDatePast,
      kind: AppToastKind.error,
    );
    return false;
  }

  /// 실패 원인별 안내(#1582). 다시 눌러 풀리는 실패만 재시도를 권한다 — 담당
  /// 관계가 없거나(404) 서버가 입력을 거절한(400·422) 경우는 같은 요청을
  /// 반복해도 결과가 같다. 응답 형식이 어긋나면 서버에는 반영됐을 수 있어
  /// 먼저 확인하게 한다.
  String _sendFailureMessage(AppLocalizations l, Object error) =>
      switch (error) {
        ProgramAttachConflictError() => l.coachAttachTargetChanged,
        NetworkError() => l.coachSendNetworkFailed,
        NotFoundError() => l.coachSendClientNotFound,
        ValidationError() => l.coachSendInvalid,
        FormatException() => l.coachSendUnverified,
        _ => l.coachSendFailed,
      };

  /// [clientId] 의 이번 전송에 쓸 멱등키. [payload] 가 지난 실패 때와 같으면
  /// 그 키를 다시 쓴다 — 응답만 잃은 요청을 재시도해도 서버가 두 번 만들지
  /// 않는다. 구성을 고쳤으면 다른 요청이므로 새 키를 만든다.
  String _requestIdFor(String clientId, Object payload) {
    final fingerprint = jsonEncode(payload, toEncodable: (value) => '$value');
    final pending = _sendRequests[clientId];
    if (pending != null && pending.fingerprint == fingerprint) {
      return pending.id;
    }
    final id = newClientRequestId();
    _sendRequests[clientId] = (fingerprint: fingerprint, id: id);
    return id;
  }

  /// The draft flattened into schedule items, each tagged with its session.
  ///
  /// 세션 이름은 항목마다 붙는다(#709) — 일정은 평면 목록이지만 이 값으로 다시
  /// 세션별로 묶어 보여 줄 수 있고, 세션이 하나뿐이면 빈 문자열이라 예전 일정과
  /// 같은 모양이다.
  List<ProgramItem> _draftProgram(ProgramEditorState draft) {
    final multi = draft.sessions.length > 1;
    return <ProgramItem>[
      for (final session in draft.sessions)
        for (final exercise in session.exercises)
          ProgramItem(
            name: exercise.name.trim(),
            type: exercise.type,
            date: exercise.date,
            // 근력은 세트·횟수·중량으로만 재고 시간을 싣지 않는다 — 두
            // 편집기와 회원 기록이 같은 규칙을 쓴다 (#1276). 횟수는 예전에
            // 여기서만 빠져 있었다: 편집기에서 채운 `12회` 가 일정에 등록하는
            // 순간 사라져, 같은 프로그램이 코칭 탭과 스케줄 탭에서 다르게
            // 읽혔다.
            duration: exercise.isStrength ? null : exercise.minutes,
            sets: exercise.isStrength ? exercise.sets : null,
            reps: exercise.isStrength ? exercise.reps : null,
            weight: exercise.isStrength ? exercise.weight : null,
            intensity: exercise.intensity,
            session: multi ? capSessionName(session.name) : '',
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final clientsAsync = ref.watch(clientsProvider);

    return PageScaffold(
      title: l.coachTitle,
      subtitle: l.coachSubtitle,
      headerCenter: const ClientSearchBar(),
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      child: clientsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            l.clientsLoadFailed,
            style: const TextStyle(color: AppColors.mutedForeground),
          ),
        ),
        data: (clients) {
          if (clients.isEmpty) {
            return Center(
              child: Text(
                l.coachNoClients,
                style: const TextStyle(color: AppColors.mutedForeground),
              ),
            );
          }
          final selected = clients.firstWhere(
            (c) => c.id == _clientId,
            orElse: () => clients.first,
          );
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= AppLayout.splitBreakpoint;
              // 3열의 고정 폭(목록 260 + 우측 360 + 간격 48)과 페이지 여백을
              // 빼고도 편집기가 최소 600px을 가져야 한다.
              final fullWidth = constraints.maxWidth >= 1320;
              if (!wide) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppLayout.pagePadding,
                    AppLayout.pagePadding,
                    AppLayout.pagePadding,
                    AppLayout.pagePadding,
                  ),
                  children: <Widget>[
                    // Single column: context, then the editor, then the
                    // library. The editor is the task — pushing it below
                    // the templates would bury it.
                    ..._contextChildren(l, clients, selected),
                    const SizedBox(height: AppSpacing.lg),
                    ..._suggestionChildren(selected),
                    ..._editorChildren(selected),
                    const SizedBox(height: AppSpacing.lg),
                    ..._libraryChildren(selected),
                  ],
                );
              }
              // 넓은 화면은 **세 열이 각자 스크롤한다.** 왼쪽(고객 · 템플릿)은
              // #958 이후로 이미 그랬고, 이번에는 오른쪽 고객 데이터 열도
              // 가운데 편집기 스크롤에서 떼어 냈다(#1027) — 편집기를 아래로
              // 읽는 동안 지금 고른 고객의 식단·운동이 함께 밀려 올라가면,
              // 정작 그 데이터를 근거로 짜야 할 프로그램을 쓰면서 근거를 볼
              // 수 없다. 열을 나누면 오른쪽 열은 제자리에 머무른다.
              return Padding(
                padding: const EdgeInsets.all(AppLayout.pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: 260,
                            // 고객 목록(5줄 고정)은 그 자리·높이 그대로 두고,
                            // 템플릿 카드가 늘어나는 만큼만 그 아래 남는
                            // 공간 안에서 따로 스크롤한다 — 예전처럼 열
                            // 전체를 한 스크롤로 묶으면 템플릿을 보려고
                            // 내릴 때 고객 목록까지 함께 밀려 올라갔다.
                            //
                            // 다만 이 열에 실제로 주어진 높이가 고객 목록
                            // 하나만으로도 빠듯할 만큼 짧으면(작은 창) 그대로
                            // 나누지 않는다 — 템플릿 카드는 헤더 한 줄 만큼의
                            // 최소 높이도 없이는 그릴 수 없어 RenderFlex
                            // 오버플로우가 난다. 그런 창에서는 예전처럼 열
                            // 전체를 한 스크롤로 묶어 오버플로우 대신
                            // 스크롤로 흡수한다.
                            child: LayoutBuilder(
                              builder: (context, sidebarConstraints) {
                                final canSplit =
                                    sidebarConstraints.maxHeight >=
                                    _sidebarSplitMinHeight(context);
                                final list = _MemberProgramList(
                                  clients: clients,
                                  selectedId: selected.id,
                                  onSelect: _selectClient,
                                );
                                final template = _TemplateCard(
                                  key: const ValueKey<String>(
                                    'program-template-sidebar',
                                  ),
                                  onApply: _applyTemplate,
                                  fixedBox: canSplit,
                                );
                                if (!canSplit) {
                                  return SingleChildScrollView(
                                    key: const ValueKey<String>(
                                      'coaching-sidebar-scroll',
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        list,
                                        const SizedBox(height: AppSpacing.lg),
                                        template,
                                      ],
                                    ),
                                  );
                                }
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    list,
                                    const SizedBox(height: AppSpacing.lg),
                                    // 남는 세로 공간은 전부 템플릿 카드가
                                    // 갖는다 — 카드 박스 자체가 이 높이로
                                    // 고정되고, 카드 내부가 그 안에서만
                                    // 스크롤한다.
                                    Expanded(child: template),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: SingleChildScrollView(
                              key: const ValueKey<String>(
                                'coaching-program-page-scroll',
                              ),
                              child: Column(
                                key: const ValueKey<String>(
                                  'coaching-wide-main-column',
                                ),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  // 오른쪽 열을 세울 만큼 넓지 않은 창에서는 식단·운동이 가운데
                                  // 열 **맨 위**에 온다 — 넓은 화면의 오른쪽 열 맨 위와 같은
                                  // 자리다(#1027). 좁은 화면(`_contextChildren`)도 이미 이
                                  // 순서다.
                                  if (!fullWidth) ...<Widget>[
                                    _ClientDataSwitcher(
                                      key: const ValueKey<String>(
                                        'coaching-wide-client-overview',
                                      ),
                                      client: selected,
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    // 3열이 따로 생기지 않는 너비에서도 AI 개인운동 제안은
                                    // 고객 데이터 바로 아래, 작은 카드로 유지한다.
                                    _suggestionColumn(selected),
                                    const SizedBox(height: AppSpacing.lg),
                                  ],
                                  // `AI에게 맞춤 루틴 요청하기` 는 더 이상 클릭해야 나타나지
                                  // 않는다 — `_editorChildren` 이 프로그램 정보 박스 위에 늘
                                  // 붙여 둔다(#1028).
                                  ..._editorChildren(selected),
                                  if (!fullWidth) ...<Widget>[
                                    const SizedBox(height: AppSpacing.lg),
                                    _SendHistoryCard(client: selected),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (fullWidth) ...<Widget>[
                            const SizedBox(width: AppSpacing.lg),
                            SizedBox(
                              key: const ValueKey<String>(
                                'coaching-wide-client-overview',
                              ),
                              width: 360,
                              // 가운데 열과 **다른 스크롤**이다 — 편집기를 아래로
                              // 읽어도 이 열은 제자리에 머문다. 열 자체가 화면보다
                              // 길어질 때만 이 안에서 따로 움직인다.
                              child: SingleChildScrollView(
                                key: const ValueKey<String>(
                                  'coaching-client-rail-scroll',
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    // 식단·운동이 열의 맨 위다. 고객을 고른 뒤
                                    // 가장 자주 보는 값이 가장 먼저 온다.
                                    _ClientDataSwitcher(client: selected),
                                    const SizedBox(height: AppSpacing.lg),
                                    // AI 개인운동 제안은 식단·운동 바로
                                    // 아래, 전송 이력 위에 둔다 — 고객
                                    // 데이터를 본 직후 판단하는 흐름이다.
                                    _suggestionColumn(selected),
                                    const SizedBox(height: AppSpacing.lg),
                                    _SendHistoryCard(client: selected),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Who the routine is for, and what their day looks like — the
  /// context the editor is read against.
  List<Widget> _contextChildren(
    AppLocalizations l,
    List<TrainerClient> clients,
    TrainerClient client,
  ) {
    return <Widget>[
      _sectionLabel(l.reportsPickClient),
      const SizedBox(height: AppSpacing.sm),
      // Horizontal scroll instead of one cramped Row — stays usable as
      // the roster grows past the seeded three (codex review).
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final c in clients) ...<Widget>[
              SizedBox(
                width: 104,
                child: _ClientChip(
                  client: c,
                  selected: c.id == client.id,
                  onTap: () => _selectClient(c.id),
                ),
              ),
              if (c != clients.last) const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      // 좁은 화면도 넓은 화면과 같은 것을 본다 — 오늘의 영양 카드 하나만
      // 붙여 두면 이 폭에서는 운동 데이터를 볼 길이 아예 없었다.
      _ClientDataSwitcher(client: client),
    ];
  }

  /// Reusable blocks and what this client already received — reference
  /// material, secondary to the editor.
  ///
  /// 저장한 프로그램을 위한 별도 보관함은 없다 — `저장` 이 곧장 `_TemplateCard`
  /// 목록에 쓰기 때문에, 방금 저장한 결과도 이 카드에서 바로 보인다 (#1028).
  List<Widget> _libraryChildren(TrainerClient client) {
    return <Widget>[
      _TemplateCard(onApply: _applyTemplate),
      const SizedBox(height: AppSpacing.lg),
      _SendHistoryCard(client: client),
    ];
  }

  void _applyTemplate(ProgramTemplate template) => setState(() {
    _appliedTemplate = template;
    _templateRevision++;
    _aiWizardVisible = false;
    _sent = false;
  });

  void _startManualProgram(String clientId) => setState(() {
    _generatedRecommendations.remove(clientId);
    _appliedTemplate = null;
    _templateRevision = 0;
    _editorRevision++;
    _aiWizardVisible = false;
    _sent = false;
  });

  /// AI 가 준비한 개인운동 제안. (#790)
  ///
  /// 개인운동은 PT 사이를 메우는 짧은 운동이고 정규 프로그램은 기간 전체의
  /// 계획이라, 같은 프로그램 탭 안에 두더라도 편집기에 섞지 않는다 — 여기서
  /// 하는 일은 편집이 아니라 판단(추천/수정 후 추천/추천 안 함)이다. 넓은
  /// 화면에서는 오른쪽 고객 데이터 열의 식단·운동 바로 아래, 전송 이력 위에
  /// 작은 카드로 두고(호출부 참고), 열을 나눌 폭이 없는 화면에서만 이
  /// 목록으로 편집기 위에 쌓인다.
  List<Widget> _suggestionChildren(TrainerClient client) {
    return <Widget>[
      _suggestionColumn(client),
      const SizedBox(height: AppSpacing.lg),
    ];
  }

  Widget _suggestionColumn(TrainerClient client) => RoutineSuggestionReviewCard(
    key: ValueKey<String>('routine-suggestions-${client.id}'),
    clientId: client.id,
    clientName: client.name,
  );

  /// The routine editor column (right column on wide).
  ///
  /// `AI에게 맞춤 루틴 요청하기` 는 더 이상 클릭해야 나타나지 않는다 —
  /// `프로그램 정보` 박스([ProgramEditorWorkspace]) 바로 위에 항상 붙인다.
  /// AI 요청 흐름의 `템플릿에 반영` 이 그 결과를 [ProgramEditorWorkspace]
  /// 의 `aiSuggestions` 로 넘기면 편집기가 세션 1에 병합할 뿐, 이 흐름도
  /// 편집기도 여기서 회원에게 직접 API 를 부르지 않는다 — 실제 전송은
  /// 편집기의 `보내기` 가 [_sendProgram] 을 통해 호출부에서만 한다.
  List<Widget> _editorChildren(TrainerClient client) {
    final AppLocalizations l = AppLocalizations.of(context);
    final routineAsync = ref.watch(
      aiRoutineProvider((id: client.id, name: client.name)),
    );

    return <Widget>[
      routineAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text(
          l.routinesLoadFailed,
          style: const TextStyle(color: AppColors.mutedForeground),
        ),
        data: (items) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Offstage(
              offstage: !_aiWizardVisible,
              child: AiRoutineOptionsFlow(
                key: ValueKey<String>('routine-options-${client.id}'),
                client: client,
                embedded: true,
                recommendedExercises: items
                    .map(
                      (item) => RoutineExercise(
                        name: item.name,
                        minutes: item.minutes,
                        type: _typeEdits[item.id] ?? item.type,
                      ),
                    )
                    .toList(growable: false),
                recommendedReason: items.isEmpty
                    ? ''
                    : items.map((item) => item.reason).join(' · '),
                onReviewCompleted: (exercises) {
                  setState(() {
                    _generatedRecommendations[client.id] = <AiRoutineItem>[
                      for (var index = 0; index < exercises.length; index++)
                        AiRoutineItem(
                          id: 'generated-${client.id}-$index',
                          name: exercises[index].name,
                          minutes: exercises[index].minutes,
                          type: exercises[index].type,
                          reason: l.coachReviewed,
                          sets: exercises[index].sets,
                          reps: exercises[index].reps,
                          weight: exercises[index].weight,
                        ),
                    ];
                    _aiWizardVisible = false;
                  });
                },
                onManualCreate: () => _startManualProgram(client.id),
              ),
            ),
            if (!_aiWizardVisible)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey<String>('return-to-ai-flow'),
                    onPressed: () => setState(() => _aiWizardVisible = true),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.chevron_left, size: 18),
                    label: Text(l.aiReturnToWizard),
                  ),
                ),
              )
            else
              const SizedBox(height: AppSpacing.lg),
            Offstage(
              offstage: _aiWizardVisible,
              child: ProgramEditorWorkspace(
                key: ValueKey<String>(
                  'program-editor-${client.id}-$_editorRevision',
                ),
                clientGoal: client.goal,
                aiSuggestions: _generatedRecommendations[client.id] ?? items,
                template: _appliedTemplate,
                templateRevision: _templateRevision,
                onSend: (draft) => unawaited(_sendProgram(client, draft)),
                onSave: _saveTemplate,
                saving: _savingTemplate,
                sending: _sendingClientIds.contains(client.id) || _sent,
                registerDate: _registerDate,
                onRegisterDateChanged: (date) =>
                    setState(() => _registerDate = date),
                registerStartTime: _registerStartTime,
                registerEndTime: _registerEndTime,
                onRegisterTimeRangeChanged: (range) => setState(() {
                  _registerStartTime = range.start;
                  _registerEndTime = range.end;
                }),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.subtleForeground,
      ),
    );
  }
}

/// 1열이 "고객 목록 고정 + 템플릿 카드만 스크롤"로 나뉘려면 필요한 최소
/// 높이 — 고객 목록 5줄([_MemberProgramList], 글자 배율 반영) + 그 아래
/// 간격 + 템플릿 카드가 최소한 헤더 한 줄을 그릴 수 있는 높이를 더한
/// 값이다. 실제 주어진 높이가 이보다 작으면 나누지 않는다(호출부 참고).
double _sidebarSplitMinHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  final extraScale = (scale - 1).clamp(0.0, 2.0);
  final rowHeight = 64 + 56 * extraScale;
  // 두 카드 모두 dense 패딩(AppSpacing.md 상하) + 헤더 아래 간격
  // (AppSpacing.sm)을 쓴다. 헤더 줄 높이는 카드마다 다르다 — 고객 목록
  // 헤더는 아이콘 16 + 글자뿐이지만, 템플릿 카드 헤더는 편집 가능할 때
  // `template-new` IconButton(28×28, `_TemplateCard` 참고)을 달아 그
  // 28px 가 기준이 된다. 더 큰 쪽으로 어림해야 경계에서 카드가 헤더
  // 한 줄도 못 그리는 채로 `canSplit`이 켜지지 않는다.
  const listChrome = AppSpacing.md * 2 + 22 + AppSpacing.sm;
  const templateChrome = AppSpacing.md * 2 + 28 + AppSpacing.sm;
  return rowHeight * 5 + listChrome + AppSpacing.lg + templateChrome;
}

class _MemberProgramList extends StatefulWidget {
  const _MemberProgramList({
    required this.clients,
    required this.selectedId,
    required this.onSelect,
  });

  final List<TrainerClient> clients;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<_MemberProgramList> createState() => _MemberProgramListState();
}

class _MemberProgramListState extends State<_MemberProgramList> {
  /// 한 줄 높이. 이름 · 목표 두 줄이 들어간다.
  ///
  /// 이행률 막대는 뺐다(#1029) — 이 목록은 회원을 고르는 자리고, 이행률
  /// 비교는 리포트 탭의 몫이다. 예전에는 `오늘`/`5일 전` 같은 마지막 루틴
  /// 시각도 있었는데 그것도 지운 채였다(#1027).
  ///
  /// 웹에서는 줄 안의 글이 브라우저 기본 글꼴로 몇 px 넘쳐 줄무늬가 뜬 적이
  /// 있다(#958) — 테스트 글꼴보다 줄 높이가 살짝 크다. 그만큼 여유를 둔다.
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  @override
  void didUpdateWidget(_MemberProgramList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.clients.length != widget.clients.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealSelected() {
    if (!_scroll.hasClients) return;
    final rowHeight = clientListRowHeight(context);
    final index = widget.clients.indexWhere(
      (client) => client.id == widget.selectedId,
    );
    if (index < 0) return;
    final top = index * rowHeight;
    final bottom = top + rowHeight;
    final viewportTop = _scroll.offset;
    final viewportBottom = viewportTop + _scroll.position.viewportDimension;
    final target = top < viewportTop
        ? top
        : bottom > viewportBottom
        ? bottom - _scroll.position.viewportDimension
        : viewportTop;
    if (target == viewportTop) return;
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rowHeight = clientListRowHeight(context);
    return SectionCard(
      // 리포트 탭 좌측 고객 카드와 같은 제목·아이콘을 쓴다 — 두 탭이 같은
      // `왼쪽 고객 열 + 오른쪽 작업 영역` 구조라, 카드가 서로 다른 이름을
      // 달고 있으면 같은 목록인지 매번 다시 읽어야 한다. (#958)
      title: l.navClients,
      icon: Icons.people_outline,
      dense: true,
      child: SizedBox(
        height: rowHeight * clientListVisibleRows,
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: widget.clients.length > clientListVisibleRows,
          child: ListView.builder(
            key: const ValueKey<String>('program-client-list-scroll'),
            controller: _scroll,
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            itemCount: widget.clients.length,
            itemExtent: rowHeight,
            itemBuilder: (context, index) {
              final client = widget.clients[index];
              final selected = client.id == widget.selectedId;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Material(
                  key: ValueKey<String>('program-client-${client.id}'),
                  color: selected
                      ? AppColors.accentSurface
                      : Colors.transparent,
                  borderRadius: const BorderRadius.all(AppRadius.md),
                  child: InkWell(
                    onTap: () => widget.onSelect(client.id),
                    borderRadius: const BorderRadius.all(AppRadius.md),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Row(
                        children: <Widget>[
                          // 아바타 크기는 리포트 탭 고객 목록과 같은
                          // 기준을 쓴다(#1423).
                          ClientAvatar(
                            label: client.avatar,
                            size: clientListAvatarSize,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                // 이름 타이포는 리포트 탭 고객 목록과 같은
                                // 기준을 쓴다(#1423) — 같은 목록이 탭마다
                                // 다른 크기로 보이지 않게.
                                ClientIdentity(
                                  client: client,
                                  nameStyle: clientListNameStyle(
                                    selected: selected,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // 목표는 늘 보인다. 전에는 `lastRoutine` 이
                                // 비었을 때만 그 자리를 빌려 써서, 루틴을 한
                                // 번이라도 보낸 고객은 목표가 사라졌다(#898).
                                ClientGoalLabel(
                                  client: client,
                                  fontSize: clientListGoalFontSize,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

}

/// 요일별 운동 이행률(월→일). (#899)
///
/// 프로그램을 짜는 화면인데 이 회원의 한 주가 어떻게 흘렀는지가 없었다 —
/// 어느 요일이 비었는지가 다음 주 프로그램을 정하는 자료다.
///
/// 리포트 탭이 쓰는 [BarSeriesChart] 를 그대로 쓴다. 두 탭이 같은 그림으로
/// 말해야 트레이너가 같은 값을 두 번 읽지 않는다.
///
/// 요약 카드가 사라진 뒤로는 `운동` 쪽 아래에 선다(#1027). 제목은 카드가
/// 들므로 그래프 위에 같은 문구를 한 번 더 적지 않는다.
class _WeekCompletionBars extends StatelessWidget {
  const _WeekCompletionBars({required this.client});

  final TrainerClient client;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final week = client.weekCompletion;
    return SectionCard(
      title: l.reportsCompletionByDay,
      icon: Icons.calendar_view_week_outlined,
      dense: true,
      child: week.length != weekdayCount
          ? EmptyHint(message: l.reportsNoWorkoutsThisWeek)
          : BarSeriesChart(
              key: const ValueKey<String>('program-week-completion-chart'),
              title: l.reportsCompletionByDay,
              values: week,
              labels: weekdayLabels(l),
              maxValue: 100,
              height: 72,
              showValues: true,
              valueSuffix: '%',
              // 로스터의 계열은 늘 이번 주다 — 아직 오지 않은 요일을 0% 로
              // 그리면 `0% 수행` 이라는 다른 뜻이 된다.
              pendingFromIndex: elapsedWeekdays(nowKst()),
              // 지난 날인데 기록이 없는 요일도 0% 가 아니다.
              missingIndices: <int>{
                for (var i = 0; i < elapsedWeekdays(nowKst()); i++)
                  if (i < week.length && week[i] == 0) i,
              },
            ),
    );
  }
}

enum _ClientDataView { diet, workout }

/// 고른 고객의 식단 · 운동 — 프로그램 탭에서 가장 자주 보는 값이다.
///
/// 넓은 화면에서는 오른쪽 열의 맨 위, 좁은 화면에서는 페이지 맨 위에 온다.
/// 예전에는 고객 요약 카드가 그 자리를 차지하고 이 영역이 그 아래(또는
/// 옆)였다 — 요약 카드가 말하던 것(이름 · 목표 · 최근 세션 · 초과 배지)은
/// 왼쪽 고객 목록과 아래 카드들이 이미 하고 있어, 카드를 지우고 자리를
/// 넘겼다(#1027).
class _ClientDataSwitcher extends ConsumerStatefulWidget {
  const _ClientDataSwitcher({super.key, required this.client});

  final TrainerClient client;

  @override
  ConsumerState<_ClientDataSwitcher> createState() =>
      _ClientDataSwitcherState();
}

class _ClientDataSwitcherState extends ConsumerState<_ClientDataSwitcher> {
  _ClientDataView _view = _ClientDataView.diet;

  /// 프로그램 탭에서도 `오늘 / 이번 주 / 이번 달` 을 고를 수 있다(#914).
  /// 다음 주 프로그램을 짜는 화면인데 오늘 하루만 보이면, 무엇을 근거로 짜야
  /// 하는지가 화면 밖에 있다.
  ClientPeriod _period = ClientPeriod.today;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      key: const ValueKey<String>('program-client-data-switcher'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 기간 토글은 전환 스트립과 **한 줄**에 둔다(#943).
        //
        // 회원 앱처럼 카드 위에 `제목 + 토글` 한 줄을 따로 두면 고객 데이터 열이
        // 그만큼 길어져, 폭 1552px·높이 900px 에서 당류 카드가 화면 밖으로 7.8px
        // 밀렸다. 스트립이 이미 `식단`/`운동` 이라는 제목 노릇을 하고 있으므로
        // 그 줄의 오른쪽 끝을 빌려 쓴다 — 세로 자리를 한 픽셀도 더 쓰지 않고,
        // 기간을 바꿔도 토글이 움직이지 않는다.
        Row(
          children: <Widget>[
            Expanded(child: _dataTabs(l)),
            const SizedBox(width: AppSpacing.sm),
            // 토글은 줄어들되 잘리지는 않는다. 영어 `Today / This week /
            // This month` 는 배율 1.3 · 폭 1024 에서 줄을 115px 넘겼다 —
            // FittedBox 가 세 칸을 다 보여 준 채 통째로 작게 그린다.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: AppSegmentedToggle<ClientPeriod>(
                  key: const ValueKey<String>('client-period-toggle'),
                  segments: clientPeriodSegments(l),
                  selected: _period,
                  onChanged: (ClientPeriod p) => setState(() => _period = p),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // 전환에 애니메이션을 두지 않는다(#1027). 식단 그래프는 움직이지 않는
        // 그림이어야 한다는 것이 이번 결정이고, 카드를 페이드로 바꾸면 기간을
        // 옮길 때마다 그 그래프가 다시 떠오른다.
        if (_view == _ClientDataView.diet)
          if (_period == ClientPeriod.today)
            ProgramNutritionSummaryCard(
              key: ValueKey<String>('program-diet-${widget.client.id}'),
              client: widget.client,
            )
          else
            ClientDietPeriodCard(
              // 키에 기간을 넣지 않는다. 넣으면 주 ↔ 달을 옮길 때마다 카드가
              // 새로 만들어져, 나트륨을 보다 기간만 넓힌 트레이너가 지표를
              // 다시 골라야 했다.
              key: ValueKey<String>('program-diet-period-${widget.client.id}'),
              clientId: widget.client.id,
              period: _period,
            )
        else ...<Widget>[
          ClientExerciseStatusCard(
            key: ValueKey<String>('program-workout-${widget.client.id}'),
            clientId: widget.client.id,
            period: _period,
            // 운동 그래프 아래에 세트 · 횟수 · 시간을 붙인다. 그래프는 "얼마나
            // 오래" 만 말해서, 다음 프로그램을 짤 때 정작 필요한 "무엇을 몇
            // 세트" 가 화면 밖에 있었다.
            clientName: widget.client.name,
          ),
          const SizedBox(height: AppSpacing.md),
          // 요약 카드가 들고 있던 그림이다. 카드는 지웠지만 이 그래프는
          // 운동 데이터라 운동 쪽으로 옮겼다 — 어느 요일이 비었는지가 다음
          // 주 프로그램을 정하는 자료다.
          _WeekCompletionBars(client: widget.client),
        ],
      ],
    );
  }

  /// 식단 ↔ 운동 전환 스트립.
  Widget _dataTabs(AppLocalizations l) => Container(
    key: const ValueKey<String>('program-client-data-tabs'),
    height: 44,
    padding: EdgeInsets.zero,
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.1),
      borderRadius: const BorderRadius.all(AppRadius.pill),
    ),
    foregroundDecoration: BoxDecoration(
      borderRadius: const BorderRadius.all(AppRadius.pill),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: _ClientDataTab(
            label: l.clientTabDiet,
            icon: Icons.restaurant_outlined,
            selected: _view == _ClientDataView.diet,
            onTap: () => setState(() {
              _view = _ClientDataView.diet;
            }),
          ),
        ),
        Expanded(
          child: _ClientDataTab(
            label: l.clientTabWorkout,
            icon: Icons.fitness_center_outlined,
            selected: _view == _ClientDataView.workout,
            onTap: () => setState(() {
              _view = _ClientDataView.workout;
            }),
          ),
        ),
      ],
    ),
  );
}

class _ClientDataTab extends StatelessWidget {
  const _ClientDataTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.primary : AppColors.mutedForeground;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? AppColors.card : const Color(0x00000000),
          borderRadius: const BorderRadius.all(AppRadius.pill),
          border: selected ? Border.all(color: AppColors.card) : null,
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: const Color(0x00000000),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientChip extends StatelessWidget {
  const _ClientChip({
    required this.client,
    required this.selected,
    required this.onTap,
  });

  final TrainerClient client;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.card,
      borderRadius: const BorderRadius.all(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(AppRadius.card),
            border: selected ? null : Border.all(color: AppColors.borderStrong),
          ),
          child: Column(
            children: <Widget>[
              selected
                  ? Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryForeground.withValues(
                          alpha: 0.25,
                        ),
                      ),
                      child: Text(
                        client.avatar,
                        style: const TextStyle(
                          color: AppColors.primaryForeground,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ClientAvatar(label: client.avatar, size: 32),
              const SizedBox(height: AppSpacing.xs),
              ClientIdentity(
                client: client,
                stacked: true,
                nameStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.primaryForeground
                      : AppColors.foreground,
                ),
                demographicsStyle: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? AppColors.primaryForeground.withValues(alpha: 0.8)
                      : AppColors.subtleForeground,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 운동 한 줄을 템플릿에 담을 때 쓸 시간(분). `duration` 이 비어 있거나
/// 0 이하면(세트·중량 위주 운동) 새 운동 줄의 기본값(10분, 다이얼로그와 동일)을
/// 대신 쓴다 — 값이 없다고 그 운동째로 템플릿에서 빠지지 않게 한다.
/// 오늘 자정(KST) — PT 등록 날짜의 기본값이자 고를 수 있는 가장 이른 날.
DateTime _todayKst() {
  final now = nowKst();
  return DateTime(now.year, now.month, now.day);
}

/// [date] 를 사람이 읽는 짧은 라벨로 — 오늘/내일은 그렇게, 그 뒤는 `M/D`.
String _dateChipLabel(AppLocalizations l, DateTime date) {
  final today = _todayKst();
  if (ymd(date) == ymd(today)) return l.labelToday;
  if (ymd(date) == ymd(today.add(const Duration(days: 1)))) {
    return l.labelTomorrow;
  }
  return '${date.month}/${date.day}';
}

/// One selectable register-day chip.
class _TemplateCard extends ConsumerWidget {
  const _TemplateCard({
    super.key,
    required this.onApply,
    this.fixedBox = false,
  });

  final ValueChanged<ProgramTemplate> onApply;

  /// 넓은 화면 사이드바(`Expanded`로 높이가 이미 정해진 자리)에서만 켠다 —
  /// 카드 박스를 그 높이로 고정하고 목록만 안에서 스크롤한다. 좁은 화면의
  /// `_libraryChildren`는 페이지 자체가 스크롤하는 `ListView` 안이라 높이가
  /// 정해져 있지 않다(unbounded) — 여기서 켜면 `Expanded`/내부 스크롤이
  /// 레이아웃 예외를 던진다.
  final bool fixedBox;

  /// 만들기·편집 다이얼로그. 시작 구성을 열면 저장이 '새로 만들기' 가 된다.
  Future<void> _edit(BuildContext context, {ProgramTemplate? template}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ProgramTemplateDialog(template: template),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ProgramTemplate template,
  ) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(l.coachTemplateDeleteConfirm(template.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.coachTemplateDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(trainerProgramTemplateRepositoryProvider)
          .delete(template.id);
      ref.invalidate(programTemplatesProvider);
    } on AppError {
      if (!context.mounted) return;
      showAppToast(
        context,
        l.coachTemplateDeleteFailed,
        kind: AppToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final templatesAsync = ref.watch(programTemplatesProvider);
    // 데모는 읽기 전용이다 — 저장할 백엔드가 없어, 만든 것이 새로고침 한 번에
    // 사라지면 만들 수 있다고 말한 화면이 거짓이 된다. (#920)
    final canEdit = ref.watch(programTemplateEditingEnabledProvider);
    final templates = templatesAsync.valueOrNull ?? const <ProgramTemplate>[];
    if (templatesAsync.hasError && templates.isEmpty) {
      return SectionCard(
        title: l.coachTemplates,
        icon: Icons.dashboard_customize_outlined,
        dense: true,
        // 정상 경로와 같은 규칙이다 — `fixedBox`(넓은 사이드바)일 때는
        // 오류 상태도 부모가 준 고정 높이를 그대로 받아야 한다. 여기서
        // 빠뜨리면 오류가 난 그 순간에만 카드가 제 높이를 못 지켜
        // RenderFlex 오버플로우가 난다(코드리뷰).
        expandChild: fixedBox,
        child: Text(
          l.coachTemplateLoadFailed,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.mutedForeground,
          ),
        ),
      );
    }
    // 넓은 사이드바(`fixedBox`)에서만 카드 박스를 고정 높이로 만들고, 그
    // 안에서 목록만 스크롤한다. 좁은 화면(페이지 자체가 스크롤하는
    // `ListView` 안, 높이 unbounded)에서는 예전처럼 자연스러운 높이로
    // 그린다 — 거기서 고정 높이를 쓰면 `Expanded`가 레이아웃 예외를 던진다.
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 3 : 1;
        final width =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final template in templates)
              SizedBox(
                width: width,
                child: Material(
                  color: AppColors.inputBackground,
                  borderRadius: const BorderRadius.all(AppRadius.md),
                  child: InkWell(
                    onTap: () => onApply(template),
                    borderRadius: const BorderRadius.all(AppRadius.md),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  template.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.foreground,
                                  ),
                                ),
                              ),
                              if (canEdit)
                                _TemplateMenu(
                                  template: template,
                                  onEdit: () =>
                                      _edit(context, template: template),
                                  onDelete: template.isStarter
                                      ? null
                                      : () => _delete(context, ref, template),
                                )
                              else
                                const Icon(
                                  Icons.add_circle_outline,
                                  size: 17,
                                  color: AppColors.primary,
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            l.coachTemplateSummaryWithGoal(
                              template.goal,
                              template.exercises.length,
                              template.totalMinutes,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: AppColors.subtleForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
    return SectionCard(
      title: l.coachTemplates,
      icon: Icons.dashboard_customize_outlined,
      dense: true,
      expandChild: fixedBox,
      // 아이콘만 쓴다(#1028) — 이 카드는 260px 고정 폭 사이드바에 있어,
      // 영어·큰 글자 배율에서 "새 템플릿" 글자가 제목과 함께 넘친다.
      trailing: canEdit
          ? IconButton(
              key: const ValueKey<String>('template-new'),
              onPressed: () => _edit(context),
              icon: const Icon(Icons.add, size: 18),
              tooltip: l.coachTemplateNew,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            )
          : null,
      child: fixedBox
          ? SingleChildScrollView(
              key: const ValueKey<String>('coaching-template-scroll'),
              child: body,
            )
          : body,
    );
  }
}

/// 템플릿 한 장의 편집·삭제 메뉴 — 기본 템플릿(시작 구성)도 사용자 템플릿과
/// 같은 두 항목을 보여 준다(#1029).
///
/// 시작 구성은 삭제만 항목 자체가 아니라 **비활성**으로 남긴다 — 서버 행이
/// 아예 없어(합성 `starter:` id) 지울 것이 없다. 항목을 통째로 숨기면 두
/// 템플릿 종류가 다른 기능을 가진 것처럼 보이지만, 회색으로 남기면 "이건 못
/// 하는 동작" 이라는 뜻이 그대로 전해진다 — 지운 것처럼 보였다가 다음 조회에
/// 되돌아오는 거짓말은 여전히 만들지 않는다(#920).
///
/// 고친다는 동작 자체는 같지만 결과가 다르다 — 시작 구성은 고치면 내 첫
/// 템플릿으로 **새로 저장**되고, 내 템플릿은 그 행을 그대로 고친다. 그래서
/// 라벨도 다르게 남긴다 — 같은 말로 두면 실제로 무슨 일이 일어나는지 감춘다.
class _TemplateMenu extends StatelessWidget {
  const _TemplateMenu({
    required this.template,
    required this.onEdit,
    this.onDelete,
  });

  final ProgramTemplate template;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: ValueKey<String>('template-menu-${template.id}'),
      tooltip: '',
      padding: EdgeInsets.zero,
      iconSize: 17,
      icon: const Icon(Icons.more_vert, color: AppColors.subtleForeground),
      color: AppColors.card,
      elevation: 4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadius.md),
        side: BorderSide(color: AppColors.borderStrong),
      ),
      onSelected: (value) => value == 'edit' ? onEdit() : onDelete?.call(),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'edit',
          child: _TemplateMenuLabel(
            icon: Icons.edit_outlined,
            label: l.coachTemplateEdit,
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          enabled: onDelete != null,
          child: _TemplateMenuLabel(
            icon: Icons.delete_outline,
            label: l.coachTemplateDelete,
            destructive: true,
          ),
        ),
      ],
    );
  }
}

/// 팝업 메뉴 한 줄 — 아이콘 + 글자. 프로그램 편집기의 세션·운동 메뉴
/// (`_MenuLabel`)와 같은 모양을 쓴다.
class _TemplateMenuLabel extends StatelessWidget {
  const _TemplateMenuLabel({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.destructive : AppColors.foreground;
    return Row(
      children: <Widget>[
        Icon(icon, size: 17, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: TextStyle(color: color, fontSize: 12.5)),
      ],
    );
  }
}

/// 전송 이력 — what this client has already been given.
///
/// Without it the workspace has no memory: the trainer can't tell
/// whether they already sent today's routine, and repeats it. Sourced
/// from the schedule (PT 프로그램) and, on the real API, the member's
/// assigned routines.
class _SendHistoryCard extends ConsumerWidget {
  const _SendHistoryCard({required this.client});

  final TrainerClient client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final sessions = ref.watch(
      clientSessionsProvider((id: client.id, name: client.name)),
    );
    // Homework goes out via `assignRoutine`, which writes no schedule row.
    // Watching only the schedule left this card empty right after a send,
    // so the trainer could send the same routine again believing nothing
    // had gone out.
    final assigned = ref.watch(assignedRoutinesProvider(client.id));
    return SectionCard(
      title: l.coachSentHistory,
      icon: Icons.history,
      dense: true,
      child: sessions.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => EmptyHint(message: l.coachHistoryFailed),
        data: (list) {
          final withProgram = list
              .where((s) => s.program.isNotEmpty)
              .take(4)
              .toList();
          final routines = assigned.valueOrNull ?? const <AssignedRoutine>[];
          if (withProgram.isEmpty && routines.isEmpty) {
            return EmptyHint(
              message: l.coachHistoryEmpty,
              icon: Icons.outbox_outlined,
            );
          }
          return Column(
            children: <Widget>[
              for (final routine in routines.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      _SendHistoryTypeBadge(label: l.coachHomework),
                      Expanded(
                        child: Text(
                          l.coachRoutineSummary(routine.name, routine.minutes),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.foreground,
                          ),
                        ),
                      ),
                      routine.source == 'ai'
                          ? const IconLabel(
                              icon: Icons.auto_awesome,
                              label: 'AI',
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            )
                          : IconLabel(
                              icon: Icons.badge_outlined,
                              label: l.coachTrainer,
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                      // 보낸 뒤 물리는 자리. 여기 목록이 배정된 개인운동을
                      // 보여 주는 유일한 곳인데 취소가 없어서, 잘못 보냈을 때
                      // 고객 탭까지 옮겨 가야 지울 수 있었다. (#1020)
                      _CancelRoutineButton(
                        clientId: client.id,
                        routine: routine,
                      ),
                    ],
                  ),
                ),
              for (final s in withProgram)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      _SendHistoryTypeBadge(label: l.coachPersonalTraining),
                      Expanded(
                        child: Text(
                          s.program.length == 1
                              ? s.program.first.name
                              : l.coachSessionProgramSummary(
                                  s.program.first.name,
                                  s.program.length - 1,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.foreground,
                          ),
                        ),
                      ),
                      Text(
                        scheduleStatusLabel(l, s.status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: s.isDone
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 전송 이력의 프로그램 종류 — 개인운동과 PT를 같은 디자인 언어로 구분한다.
class _SendHistoryTypeBadge extends StatelessWidget {
  const _SendHistoryTypeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: ValueKey<String>('send-history-type-$label'),
          width: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: const BoxDecoration(
            color: AppColors.accentSurface,
            borderRadius: BorderRadius.all(AppRadius.pill),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 배정한 개인운동을 물리는 버튼. (#1020)
///
/// 지운다고 회원이 이미 수행한 기록까지 사라지지는 않는다 — 지우는 것은
/// **배정**이지 한 일이 아니다.
class _CancelRoutineButton extends ConsumerStatefulWidget {
  const _CancelRoutineButton({required this.clientId, required this.routine});

  final String clientId;
  final AssignedRoutine routine;

  @override
  ConsumerState<_CancelRoutineButton> createState() =>
      _CancelRoutineButtonState();
}

class _CancelRoutineButtonState extends ConsumerState<_CancelRoutineButton> {
  bool _busy = false;

  Future<void> _cancel() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l.routineDeleteTitle),
        content: Text(l.routineDeleteBody(widget.routine.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.actionCancel),
          ),
          TextButton(
            key: const ValueKey<String>('confirm-cancel-routine'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l.actionDelete,
              style: const TextStyle(color: AppColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(trainerRoutineRepositoryProvider)
          .deleteRoutine(widget.clientId, widget.routine.id);
      if (!mounted) return;
      showAppToast(context, l.routineDeleted, kind: AppToastKind.success);
    } on StateError {
      // 404 — 이미 없는 것을 지우려 했다. 목적은 이뤄진 셈이라 목록만 다시 읽고
      // 그 줄을 화면에서 걷어낸다.
      if (!mounted) return;
      showAppToast(context, l.routineAlreadyGone);
    } on Object {
      if (!mounted) return;
      showAppToast(context, l.routineDeleteFailed, kind: AppToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
      ref.invalidate(assignedRoutinesProvider(widget.clientId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.only(left: AppSpacing.sm),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      key: ValueKey<String>('history-cancel-routine-${widget.routine.id}'),
      onPressed: _cancel,
      icon: const Icon(Icons.close_rounded, size: 15),
      color: AppColors.mutedForeground,
      tooltip: AppLocalizations.of(context).routineDelete,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
    );
  }
}
