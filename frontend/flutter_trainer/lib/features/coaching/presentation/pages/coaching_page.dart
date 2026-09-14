import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/request_id.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_diet_period_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_exercise_status_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_period_toggle.dart';
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
// 예외 둘: 탭 이동 시 스크롤 초기화(UI 위젯 아님), 그리고 요일별 막대그래프
// — 패키지에 대응 차트가 없고 리포트 탭·테스트가 같은 위젯 타입을 쓴다.
import 'package:oncare_trainer/shared/widgets/mini_charts.dart';
import 'package:oncare_trainer/shared/widgets/page_scroll_reset.dart';
import 'package:oncare_ui/oncare_ui.dart';

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
  bool _sent = false;
  Timer? _sentTimer;

  /// A homework send is in flight (blocks re-entry, disables the button).
  bool _sending = false;

  /// 진행 중인 전송 시도의 멱등키와 그 대상 회원. 실패 후 재시도는 같은 키를
  /// 다시 쓰고(중복 배정 방지), 성공하거나 대상이 바뀌면 새로 잡는다(#581).
  String? _sendRequestId;
  String? _sendRequestFor;

  /// A schedule registration just succeeded — blocks re-registration for a
  /// few seconds while the success toast is still fresh.
  bool _registered = false;
  // Every client whose registration is in flight. Multiple clients may save
  // concurrently, but each client may have only one pending write.
  final Set<String> _registeringClientIds = <String>{};
  Timer? _registerTimer;

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
    _resetNotifier?.removeListener(_resetScroll);
    _sentTimer?.cancel();
    _registerTimer?.cancel();
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
      _sending = false;
      _registered = false;
      _registerDate = _todayKst();
      _registerStartTime = const TimeOfDay(hour: 10, minute: 0);
      _registerEndTime = const TimeOfDay(hour: 11, minute: 0);
      _appliedTemplate = null;
      _templateRevision = 0;
      _editorRevision = 0;
      _aiWizardVisible = true;
      // NOTE: _registeringClientIds is intentionally NOT cleared — writes
      // for other clients keep being tracked while the selection changes.
    });
    _sentTimer?.cancel();
    _registerTimer?.cancel();
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
      showAppToast(context, l.programDraftSaved, type: AppToastType.success);
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      setState(() => _savingTemplate = false);
      showAppToast(
        context,
        error is AppError
            ? serverDetailOr(l, error.message, l.coachTemplateSaveFailed)
            : l.coachTemplateSaveFailed,
        type: AppToastType.error,
      );
      return false;
    }
  }

  /// 편집기의 `보내기` 가 부른다 — 확인창을 띄우고, 확인되면 배정한다
  /// (#1028). 초안은 편집기가 그 자리에서 쥐고 있던 값을 그대로 인자로
  /// 받는다 — 예전에는 "최종 검토" 화면이 스냅샷을 붙잡아 두는 역할을
  /// 했지만, 이제 그 화면이 없어 호출 시점의 값을 곧장 쓴다.
  Future<void> _sendProgram(
    TrainerClient client,
    ProgramEditorState draft,
  ) async {
    if (_sent ||
        _sending ||
        !draft.supportsAssignment ||
        _registerDurationMinutes <= 0) {
      return;
    }
    final confirmed = await showProgramAssignConfirmDialog(
      context,
      clientName: client.name,
      registerDate: _registerDate,
      registerStartTime: _registerStartTime,
      registerEndTime: _registerEndTime,
    );
    if (confirmed != true || !mounted || !_isStillSelected(client.id)) return;
    final sentFor = client.id;
    if (_sendRequestId == null || _sendRequestFor != sentFor) {
      _sendRequestId = newClientRequestId();
      _sendRequestFor = sentFor;
    }
    setState(() => _sending = true);
    final l = AppLocalizations.of(context);
    try {
      // 세션이 몇 개든 프로그램 배정 한 번으로 보낸다 — 세션당 루틴 한 건이
      // 되고, 세션이 하나뿐이면 예전 단일 배정과 같은 결과다(#709).
      await ref
          .read(trainerRoutineRepositoryProvider)
          .assignProgram(
            client.id,
            programAssignToJson(draft, clientRequestId: _sendRequestId),
          );
    } catch (_) {
      if (!mounted || !_isStillSelected(sentFor)) return;
      setState(() => _sending = false);
      showAppToast(context, l.coachSendFailed, type: AppToastType.error);
      return;
    }
    // 배정은 여기서 이미 끝났다 — 3열 `전송 이력`(`assignedRoutinesProvider`)
    // 은 실 API 모드에서 1회성 fetch 라 다시 읽으라고 말해 줘야 한다(#1029).
    // 데모의 `assignedRoutinesProvider`/PT 등록이 읽는 `clientSessionsProvider`
    // 는 로컬 DB를 그대로 지켜보는 스트림이라 여기서 손대지 않아도 된다.
    ref.invalidate(assignedRoutinesProvider(client.id));
    if (!mounted || !_isStillSelected(sentFor)) return;
    setState(() {
      _sending = false;
      _sent = true;
      _sendRequestId = null;
      _sendRequestFor = null;
    });
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
    // `보내기` 하나가 배정과 PT 등록을 함께 한다(#1029) —
    // `assignProgram`/`registerProgram` 은 여전히 서로 다른 API 라 억지로
    // 합치지 않고 순서대로 부른다. 배정이 이미 됐으니 등록이 실패해도
    // 배정 자체를 취소하지 않는다 — [_registerProgram] 은 자기 몫의
    // 실패만 그 자리에서 따로 알린다(`coachScheduleFailed`), 방금 보인
    // 배정 성공을 덮어쓰지 않는다.
    await _registerProgram(client, draft);
  }

  /// [_sendProgram] 이 배정 성공 뒤에만 부른다(#1029) — 이 앱에 PT 등록
  /// 버튼은 따로 없다.
  Future<void> _registerProgram(
    TrainerClient client,
    ProgramEditorState draft,
  ) async {
    if (!draft.supportsAssignment ||
        _registered ||
        _registeringClientIds.contains(client.id)) {
      return;
    }
    final registeredFor = client.id;
    final date = ymd(_registerDate);
    final time =
        '${_registerStartTime.hour.toString().padLeft(2, '0')}:'
        '${_registerStartTime.minute.toString().padLeft(2, '0')}';
    final l = AppLocalizations.of(context);
    setState(() => _registeringClientIds.add(registeredFor));
    bool attachedToExisting;
    try {
      attachedToExisting = await ref
          .read(scheduleRepositoryProvider)
          .registerProgram(
            date: date,
            clientId: client.id,
            clientName: client.name,
            time: time,
            durationMinutes: _registerDurationMinutes,
            program: _draftProgram(draft),
          );
    } catch (_) {
      if (!mounted) return;
      setState(() => _registeringClientIds.remove(registeredFor));
      if (_isStillSelected(registeredFor)) {
        showAppToast(context, l.coachScheduleFailed, type: AppToastType.error);
      }
      return;
    }
    if (!mounted) return;
    final stillSelected = _isStillSelected(registeredFor);
    setState(() {
      _registeringClientIds.remove(registeredFor);
      if (stillSelected) _registered = true;
    });
    if (stillSelected) {
      // 등록 완료는 인라인 문구가 아니라 다른 성공 알림과 같은 상단
      // 토스트로 뜬다(#1536) — "스케줄로 이동" 액션으로 바로 그 날짜의
      // 스케줄 탭을 연다. `AppToastType`엔 경고 종류가 없어, 기존 세션에
      // 붙은 경우도 실패는 아니므로 `info`로 알린다.
      showAppToast(
        context,
        attachedToExisting
            ? l.coachRegisteredAttachedExisting(
                _dateChipLabel(l, _registerDate),
              )
            : l.coachRegisteredOn(_dateChipLabel(l, _registerDate)),
        type: attachedToExisting ? AppToastType.info : AppToastType.success,
        actionLabel: l.coachGoToSchedule,
        onAction: () => context.go(AppRoutes.scheduleAt(date: date)),
      );
    }
    _registerTimer?.cancel();
    _registerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _registered = false);
    });
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 탭을 다시 누르면 이 페이지의 세로 스크롤을 맨 위로 되돌린다 — 예전
    // `PageScaffold` 가 하던 일을 페이지 틀이 바뀐 뒤에도 그대로 한다.
    final next = PageScrollResetScope.maybeOf(context);
    if (identical(next, _resetNotifier)) return;
    _resetNotifier?.removeListener(_resetScroll);
    _resetNotifier = next;
    _resetNotifier?.addListener(_resetScroll);
  }

  final Set<ScrollableState> _topLevelScrollables = <ScrollableState>{};
  ValueNotifier<int>? _resetNotifier;

  void _resetScroll() {
    if (!TickerMode.valuesOf(context).enabled) return;
    _topLevelScrollables.removeWhere((scrollable) => !scrollable.mounted);
    for (final scrollable in _topLevelScrollables) {
      final position = scrollable.position;
      if (position.hasPixels && position.pixels != position.minScrollExtent) {
        position.jumpTo(position.minScrollExtent);
      }
    }
  }

  bool _rememberScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final notificationContext = notification.context;
    if (notificationContext != null) {
      final scrollable = Scrollable.maybeOf(notificationContext);
      if (scrollable != null) _topLevelScrollables.add(scrollable);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final clientsAsync = ref.watch(clientsProvider);

    return NotificationListener<ScrollNotification>(
      onNotification: _rememberScroll,
      child: AppWebPage(
        title: l.coachTitle,
        subtitle: l.coachSubtitle,
        actions: const <Widget>[
          SizedBox(
            width: OnCareLayout.headerCenterMinWidth,
            child: ClientSearchBar(),
          ),
        ],
        body: clientsAsync.when(
          loading: () => const AppLoading(),
          error: (e, _) => AppErrorState(
            title: l.clientsLoadFailed,
            retryLabel: l.actionRetry,
            onRetry: () => ref.invalidate(clientsProvider),
          ),
          data: (clients) {
            if (clients.isEmpty) {
              return AppEmptyState(
                title: l.coachNoClients,
                icon: Icons.people_outline_rounded,
              );
            }
            final selected = clients.firstWhere(
              (c) => c.id == _clientId,
              orElse: () => clients.first,
            );
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= OnCareLayout.splitBreakpoint;
                // 3열의 고정 폭(왼쪽 목록 + 오른쪽 고객 데이터 열 + 간격 둘)을
                // 빼고도 편집기가 입력 폼 폭만큼은 가져야 한다.
                final fullWidth =
                    constraints.maxWidth >=
                    OnCareLayout.splitListWidth +
                        OnCareLayout.splitListWidth +
                        OnCareLayout.splitGap +
                        OnCareLayout.splitGap +
                        OnCareLayout.dialogSmall;
                if (!wide) {
                  return ListView(
                    children: <Widget>[
                      // Single column: context, then the editor, then the
                      // library. The editor is the task — pushing it below
                      // the templates would bury it.
                      ..._contextChildren(l, clients, selected),
                      const SizedBox(height: OnCareSpacing.s16),
                      ..._suggestionChildren(selected),
                      ..._editorChildren(selected),
                      const SizedBox(height: OnCareSpacing.s16),
                      ..._libraryChildren(selected),
                    ],
                  );
                }
                // 넓은 화면은 **세 열이 각자 스크롤한다.** 왼쪽(고객 · 템플릿)은
                // #958 이후로 이미 그랬고, 오른쪽 고객 데이터 열도 가운데 편집기
                // 스크롤에서 떼어 냈다(#1027) — 편집기를 아래로 읽는 동안 지금
                // 고른 고객의 식단·운동이 함께 밀려 올라가면, 정작 그 데이터를
                // 근거로 짜야 할 프로그램을 쓰면서 근거를 볼 수 없다.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: OnCareLayout.splitListWidth,
                            // 고객 목록(5줄 고정)은 그 자리·높이 그대로 두고,
                            // 템플릿 카드가 늘어나는 만큼만 그 아래 남는 공간
                            // 안에서 따로 스크롤한다.
                            //
                            // 다만 이 열에 주어진 높이가 고객 목록 하나만으로도
                            // 빠듯할 만큼 짧으면(작은 창) 나누지 않고 열 전체를
                            // 한 스크롤로 묶어 오버플로우 대신 스크롤로 흡수한다.
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
                                        const SizedBox(
                                          height: OnCareSpacing.s16,
                                        ),
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
                                    const SizedBox(height: OnCareSpacing.s16),
                                    // 남는 세로 공간은 전부 템플릿 카드가
                                    // 갖는다 — 카드 내부가 그 안에서만
                                    // 스크롤한다.
                                    Expanded(child: template),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: OnCareLayout.splitGap),
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
                                  // 오른쪽 열을 세울 만큼 넓지 않은 창에서는
                                  // 식단·운동이 가운데 열 **맨 위**에 온다 —
                                  // 넓은 화면의 오른쪽 열 맨 위와 같은
                                  // 자리다(#1027).
                                  if (!fullWidth) ...<Widget>[
                                    _ClientDataSwitcher(
                                      key: const ValueKey<String>(
                                        'coaching-wide-client-overview',
                                      ),
                                      client: selected,
                                    ),
                                    const SizedBox(height: OnCareSpacing.s12),
                                    // 3열이 따로 생기지 않는 너비에서도 AI
                                    // 개인운동 제안은 고객 데이터 바로 아래,
                                    // 작은 카드로 유지한다.
                                    _suggestionColumn(selected),
                                    const SizedBox(height: OnCareSpacing.s16),
                                  ],
                                  ..._editorChildren(selected),
                                  if (!fullWidth) ...<Widget>[
                                    const SizedBox(height: OnCareSpacing.s16),
                                    _SendHistoryCard(client: selected),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (fullWidth) ...<Widget>[
                            const SizedBox(width: OnCareLayout.splitGap),
                            SizedBox(
                              key: const ValueKey<String>(
                                'coaching-wide-client-overview',
                              ),
                              width: OnCareLayout.splitListWidth,
                              // 가운데 열과 **다른 스크롤**이다 — 편집기를
                              // 아래로 읽어도 이 열은 제자리에 머문다.
                              child: SingleChildScrollView(
                                key: const ValueKey<String>(
                                  'coaching-client-rail-scroll',
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    _ClientDataSwitcher(client: selected),
                                    const SizedBox(height: OnCareSpacing.s16),
                                    _suggestionColumn(selected),
                                    const SizedBox(height: OnCareSpacing.s16),
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
                );
              },
            );
          },
        ),
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
    final TextStyle labelStyle = context.oncare
        .text(OnCareTypography.strong(OnCareTypography.caption))
        .copyWith(color: OnCareColors.textTertiary);
    return <Widget>[
      Text(l.reportsPickClient, style: labelStyle),
      const SizedBox(height: OnCareSpacing.s8),
      // Horizontal scroll instead of one cramped Row — stays usable as
      // the roster grows past the seeded three (codex review).
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final c in clients) ...<Widget>[
              SizedBox(
                width: OnCareLayout.sidebarWidth,
                // 이름 아래에 성별·나이를 쌓는다 — 이름이 같은 회원을
                // 가려내는 정보다.
                child: AppListRow(
                  title: c.name,
                  subtitle: _clientDemographics(l, c),
                  leading: AppAvatar(name: c.name),
                  selected: c.id == client.id,
                  onTap: () => _selectClient(c.id),
                ),
              ),
              if (c != clients.last) const SizedBox(width: OnCareSpacing.s8),
            ],
          ],
        ),
      ),
      const SizedBox(height: OnCareSpacing.s16),
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
      const SizedBox(height: OnCareSpacing.s16),
      _SendHistoryCard(client: client),
    ];
  }

  void _applyTemplate(ProgramTemplate template) => setState(() {
    _appliedTemplate = template;
    _templateRevision++;
    _aiWizardVisible = false;
    _registered = false;
    _sent = false;
  });

  void _startManualProgram(String clientId) => setState(() {
    _generatedRecommendations.remove(clientId);
    _appliedTemplate = null;
    _templateRevision = 0;
    _editorRevision++;
    _aiWizardVisible = false;
    _registered = false;
    _sent = false;
  });

  /// AI 가 준비한 개인운동 제안. (#790)
  ///
  /// 개인운동은 PT 사이를 메우는 짧은 운동이고 정규 프로그램은 기간 전체의
  /// 계획이라, 같은 프로그램 탭 안에 두더라도 편집기에 섞지 않는다. 넓은
  /// 화면에서는 오른쪽 고객 데이터 열의 식단·운동 바로 아래, 전송 이력 위에
  /// 작은 카드로 두고, 열을 나눌 폭이 없는 화면에서만 이 목록으로 편집기 위에
  /// 쌓인다.
  List<Widget> _suggestionChildren(TrainerClient client) {
    return <Widget>[
      _suggestionColumn(client),
      const SizedBox(height: OnCareSpacing.s16),
    ];
  }

  Widget _suggestionColumn(TrainerClient client) => RoutineSuggestionReviewCard(
    key: ValueKey<String>('routine-suggestions-${client.id}'),
    clientId: client.id,
    clientName: client.name,
  );

  /// The routine editor column (right column on wide).
  ///
  /// `AI에게 맞춤 루틴 요청하기` 는 `프로그램 정보` 박스([ProgramEditorWorkspace])
  /// 바로 위에 항상 붙인다. 실제 전송은 편집기의 `보내기` 가 [_sendProgram] 을
  /// 통해 호출부에서만 한다.
  List<Widget> _editorChildren(TrainerClient client) {
    final AppLocalizations l = AppLocalizations.of(context);
    final routineArgs = (id: client.id, name: client.name);
    final routineAsync = ref.watch(aiRoutineProvider(routineArgs));

    return <Widget>[
      routineAsync.when(
        loading: () => const AppLoading(placement: AppStatePlacement.card),
        error: (e, _) => AppErrorState(
          title: l.routinesLoadFailed,
          retryLabel: l.actionRetry,
          onRetry: () => ref.invalidate(aiRoutineProvider(routineArgs)),
          placement: AppStatePlacement.card,
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
                padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    key: const ValueKey<String>('return-to-ai-flow'),
                    label: l.aiReturnToWizard,
                    onPressed: () => setState(() => _aiWizardVisible = true),
                    variant: AppButtonVariant.text,
                    size: OnCareButtonSize.small,
                    leadingIcon: Icons.chevron_left_rounded,
                  ),
                ),
              )
            else
              const SizedBox(height: OnCareSpacing.s16),
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
                sending: _sending || _sent,
                registerDate: _registerDate,
                onRegisterDateChanged: (date) => setState(() {
                  _registerDate = date;
                  _registered = false;
                }),
                registerStartTime: _registerStartTime,
                registerEndTime: _registerEndTime,
                onRegisterTimeRangeChanged: (range) => setState(() {
                  _registerStartTime = range.start;
                  _registerEndTime = range.end;
                  _registered = false;
                }),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

/// 고객 목록에 보이는 행 수.
const int _visibleClientRows = 5;

/// 고객 목록 한 줄 높이 — 이름 · 목표 두 줄이 들어간다.
///
/// 기본은 밀도의 목록 행 최소 높이에 여유 16 을 더한 값이고, 접근성 글자
/// 배율이 올라가면 그만큼 함께 늘어난다(#995). 리포트 탭 고객 목록과 같은
/// 높이다.
double _clientRowHeight(BuildContext context) {
  final density = context.oncare.density;
  final double base = OnCareTypography.bodySmall.fontSize!;
  final scale = MediaQuery.textScalerOf(context).scale(base) / base;
  final extraScale = (scale - 1).clamp(0.0, 2.0);
  return density.listRowMin +
      OnCareSpacing.s16 +
      (density.listRowMin + OnCareSpacing.s8) * extraScale;
}

/// 1열이 "고객 목록 고정 + 템플릿 카드만 스크롤"로 나뉘려면 필요한 최소
/// 높이 — 고객 목록 5줄 + 두 카드의 안쪽 여백·헤더·헤더 아래 간격 + 카드
/// 사이 간격. 실제 주어진 높이가 이보다 작으면 나누지 않는다(호출부 참고).
///
/// 헤더 줄 높이는 카드마다 다르다 — 고객 목록 헤더는 아이콘 + 제목뿐이라
/// 큰 아이콘 한 칸이면 되지만, 템플릿 카드 헤더는 편집 가능할 때
/// `template-new` 아이콘 버튼(밀도의 아이콘 버튼 한 변)을 달아 그 높이가
/// 기준이 된다. 더 큰 쪽으로 어림해야 경계에서 카드가 헤더 한 줄도 못
/// 그리는 채로 `canSplit`이 켜지지 않는다.
double _sidebarSplitMinHeight(BuildContext context) {
  final density = context.oncare.density;
  const listChrome =
      OnCareSpacing.cardPadding +
      OnCareSpacing.cardPadding +
      OnCareSize.iconLarge +
      OnCareSpacing.s12;
  final templateChrome =
      OnCareSpacing.cardPadding +
      OnCareSpacing.cardPadding +
      density.iconButton +
      OnCareSpacing.s12;
  return _clientRowHeight(context) * _visibleClientRows +
      listChrome +
      OnCareSpacing.s16 +
      templateChrome;
}

/// 이름이 같은 회원을 가려내는 `성별 · 나이`.
String _clientDemographics(AppLocalizations l, TrainerClient client) {
  final gender = switch (client.rosterGender) {
    'female' => l.memberHealthGenderFemale,
    'male' => l.memberHealthGenderMale,
    _ => l.memberHealthGenderOther,
  };
  return l.coachClientDemographics(gender, client.rosterAge);
}

/// 카드 제목 줄 + 본문. [expand] 면 카드가 부모가 준 높이를 그대로 받고
/// 본문이 남는 높이를 모두 갖는다.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.expand = false,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: AppSectionHeader(title: title, icon: icon),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          if (expand) Expanded(child: child) else child,
        ],
      ),
    );
  }
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
  /// 이행률 막대는 뺐다(#1029) — 이 목록은 회원을 고르는 자리고, 이행률
  /// 비교는 리포트 탭의 몫이다. 마지막 루틴 시각도 지운 채다(#1027).
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
    if (!mounted || !_scroll.hasClients) return;
    final rowHeight = _clientRowHeight(context);
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
    final tokens = context.oncare;
    final rowHeight = _clientRowHeight(context);
    return _SectionCard(
      // 리포트 탭 좌측 고객 카드와 같은 제목·아이콘을 쓴다 (#958).
      title: l.navClients,
      icon: Icons.people_outline_rounded,
      child: SizedBox(
        height: rowHeight * _visibleClientRows,
        child: ListView.builder(
          key: const ValueKey<String>('program-client-list-scroll'),
          controller: _scroll,
          padding: EdgeInsets.zero,
          itemCount: widget.clients.length,
          itemExtent: rowHeight,
          itemBuilder: (context, index) {
            final client = widget.clients[index];
            final selected = client.id == widget.selectedId;
            final nameStyle = tokens
                .text(
                  selected
                      ? OnCareTypography.strong(OnCareTypography.bodySmall)
                      : OnCareTypography.bodySmall,
                )
                .copyWith(color: OnCareColors.textPrimary);
            final detailStyle = tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary);
            return Padding(
              padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
              child: Material(
                key: ValueKey<String>('program-client-${client.id}'),
                color: selected ? tokens.brand.surface : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: OnCareRadius.mdAll,
                  side: selected
                      ? BorderSide(color: tokens.brand.primary)
                      : BorderSide.none,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => widget.onSelect(client.id),
                  hoverColor: tokens.brand.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(OnCareSpacing.s8),
                    child: Row(
                      children: <Widget>[
                        AppAvatar(name: client.name),
                        const SizedBox(width: OnCareSpacing.s8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Flexible(
                                    child: Text(
                                      client.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: nameStyle,
                                    ),
                                  ),
                                  const SizedBox(width: OnCareSpacing.s4),
                                  Flexible(
                                    child: Text(
                                      _clientDemographics(l, client),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: detailStyle,
                                    ),
                                  ),
                                ],
                              ),
                              // 목표는 늘 보인다(#898). 비어 있으면 빈 줄을
                              // 만들지 않는다.
                              if (client.goal.trim().isNotEmpty)
                                Text(
                                  client.goal,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: detailStyle,
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
    );
  }
}

/// 요일별 운동 이행률(월→일). (#899)
///
/// 리포트 탭이 쓰는 [BarSeriesChart] 를 그대로 쓴다. 두 탭이 같은 그림으로
/// 말해야 트레이너가 같은 값을 두 번 읽지 않는다. 요약 카드가 사라진 뒤로는
/// `운동` 쪽 아래에 선다(#1027).
class _WeekCompletionBars extends StatelessWidget {
  const _WeekCompletionBars({required this.client});

  final TrainerClient client;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final week = client.weekCompletion;
    return _SectionCard(
      title: l.reportsCompletionByDay,
      icon: Icons.calendar_view_week_rounded,
      child: week.length != weekdayCount
          ? AppEmptyState(
              title: l.reportsNoWorkoutsThisWeek,
              placement: AppStatePlacement.card,
            )
          : BarSeriesChart(
              key: const ValueKey<String>('program-week-completion-chart'),
              title: l.reportsCompletionByDay,
              values: week,
              labels: weekdayLabels(l),
              maxValue: 100,
              height: OnCareSize.avatarXLarge + OnCareSpacing.s16,
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
/// 넓은 화면에서는 오른쪽 열의 맨 위, 좁은 화면에서는 페이지 맨 위에 온다
/// (#1027).
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
  ClientPeriod _period = ClientPeriod.today;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      key: const ValueKey<String>('program-client-data-switcher'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 기간 토글은 전환 토글과 **한 줄**에 둔다(#943) — 카드 위에 줄을
        // 따로 두면 고객 데이터 열이 그만큼 길어져 당류 카드가 화면 밖으로
        // 밀린다.
        Row(
          children: <Widget>[
            Expanded(
              child: AppSegmentedToggle<_ClientDataView>(
                key: const ValueKey<String>('program-client-data-tabs'),
                expand: true,
                selected: _view,
                onChanged: (view) => setState(() => _view = view),
                segments: <AppSegment<_ClientDataView>>[
                  AppSegment<_ClientDataView>(
                    value: _ClientDataView.diet,
                    label: l.clientTabDiet,
                    icon: Icons.restaurant_rounded,
                  ),
                  AppSegment<_ClientDataView>(
                    value: _ClientDataView.workout,
                    label: l.clientTabWorkout,
                    icon: Icons.fitness_center_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            // 토글은 줄어들되 잘리지는 않는다 — FittedBox 가 세 칸을 다 보여
            // 준 채 통째로 작게 그린다.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: ClientPeriodToggle(
                  active: _period,
                  onChanged: (ClientPeriod p) => setState(() => _period = p),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        // 전환에 애니메이션을 두지 않는다(#1027).
        if (_view == _ClientDataView.diet)
          if (_period == ClientPeriod.today)
            ProgramNutritionSummaryCard(
              key: ValueKey<String>('program-diet-${widget.client.id}'),
              client: widget.client,
            )
          else
            ClientDietPeriodCard(
              // 키에 기간을 넣지 않는다 — 넣으면 주 ↔ 달을 옮길 때마다 카드가
              // 새로 만들어져 고른 지표가 초기화된다.
              key: ValueKey<String>('program-diet-period-${widget.client.id}'),
              clientId: widget.client.id,
              period: _period,
            )
        else ...<Widget>[
          ClientExerciseStatusCard(
            key: ValueKey<String>('program-workout-${widget.client.id}'),
            clientId: widget.client.id,
            period: _period,
            clientName: widget.client.name,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          _WeekCompletionBars(client: widget.client),
        ],
      ],
    );
  }
}

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

/// 프로그램 템플릿 목록.
class _TemplateCard extends ConsumerWidget {
  const _TemplateCard({
    super.key,
    required this.onApply,
    this.fixedBox = false,
  });

  final ValueChanged<ProgramTemplate> onApply;

  /// 넓은 화면 사이드바(`Expanded`로 높이가 이미 정해진 자리)에서만 켠다 —
  /// 카드 박스를 그 높이로 고정하고 목록만 안에서 스크롤한다. 좁은 화면은
  /// 페이지 자체가 스크롤하는 `ListView` 안이라 높이가 정해져 있지 않다.
  final bool fixedBox;

  /// 만들기·편집 다이얼로그. 시작 구성을 열면 저장이 '새로 만들기' 가 된다.
  Future<void> _edit(BuildContext context, {ProgramTemplate? template}) {
    return showAppDialog<void>(
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
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: l.coachTemplateDeleteConfirm(template.name),
      confirmLabel: l.coachTemplateDelete,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!confirmed) return;
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
        type: AppToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final tokens = context.oncare;
    final templatesAsync = ref.watch(programTemplatesProvider);
    // 데모는 읽기 전용이다 — 저장할 백엔드가 없어, 만든 것이 새로고침 한 번에
    // 사라지면 만들 수 있다고 말한 화면이 거짓이 된다. (#920)
    final canEdit = ref.watch(programTemplateEditingEnabledProvider);
    final templates = templatesAsync.valueOrNull ?? const <ProgramTemplate>[];
    if (templatesAsync.hasError && templates.isEmpty) {
      final error = AppErrorState(
        title: l.coachTemplateLoadFailed,
        retryLabel: l.actionRetry,
        onRetry: () => ref.invalidate(programTemplatesProvider),
        placement: AppStatePlacement.card,
      );
      return _SectionCard(
        title: l.coachTemplates,
        icon: Icons.dashboard_customize_rounded,
        // 정상 경로와 같은 규칙이다 — `fixedBox`(넓은 사이드바)일 때는 오류
        // 상태도 부모가 준 고정 높이 안에서만 그린다(코드리뷰).
        expand: fixedBox,
        child: fixedBox ? SingleChildScrollView(child: error) : error,
      );
    }
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= OnCareLayout.dialogMedium
            ? 3
            : 1;
        final width =
            (constraints.maxWidth - OnCareSpacing.s8 * (columns - 1)) / columns;
        return Wrap(
          spacing: OnCareSpacing.s8,
          runSpacing: OnCareSpacing.s8,
          children: <Widget>[
            for (final template in templates)
              SizedBox(
                width: width,
                child: AppTile(
                  onTap: () => onApply(template),
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
                              style: tokens
                                  .text(
                                    OnCareTypography.strong(
                                      OnCareTypography.bodySmall,
                                    ),
                                  )
                                  .copyWith(color: OnCareColors.textPrimary),
                            ),
                          ),
                          if (canEdit)
                            _TemplateMenu(
                              template: template,
                              onEdit: () => _edit(context, template: template),
                              onDelete: template.isStarter
                                  ? null
                                  : () => _delete(context, ref, template),
                            )
                          else
                            Icon(
                              Icons.add_circle_outline_rounded,
                              size: OnCareSize.iconMedium,
                              color: tokens.brand.primary,
                            ),
                        ],
                      ),
                      const SizedBox(height: OnCareSpacing.s4),
                      Text(
                        l.coachTemplateSummaryWithGoal(
                          template.goal,
                          template.exercises.length,
                          template.totalMinutes,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tokens
                            .text(OnCareTypography.caption)
                            .copyWith(color: OnCareColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
    return _SectionCard(
      title: l.coachTemplates,
      icon: Icons.dashboard_customize_rounded,
      expand: fixedBox,
      // 아이콘만 쓴다(#1028) — 좁은 사이드바에서 영어·큰 글자 배율이면
      // "새 템플릿" 글자가 제목과 함께 넘친다.
      trailing: canEdit
          ? AppIconButton(
              key: const ValueKey<String>('template-new'),
              icon: Icons.add_rounded,
              tooltip: l.coachTemplateNew,
              onPressed: () => _edit(context),
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
/// 시작 구성은 삭제만 **비활성**으로 남긴다 — 서버 행이 아예 없어(합성
/// `starter:` id) 지울 것이 없다. 회색으로 남기면 "이건 못 하는 동작" 이라는
/// 뜻이 그대로 전해진다(#920).
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
    return AppMenu(
      items: <AppMenuItem>[
        AppMenuItem(
          label: l.coachTemplateEdit,
          icon: Icons.edit_rounded,
          onSelected: onEdit,
        ),
        AppMenuItem(
          label: l.coachTemplateDelete,
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: onDelete,
        ),
      ],
      triggerBuilder: (context, toggle) => AppIconButton(
        key: ValueKey<String>('template-menu-${template.id}'),
        icon: Icons.more_vert_rounded,
        tooltip: l.coachTemplateMenu,
        color: OnCareColors.textTertiary,
        onPressed: toggle,
      ),
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
    final tokens = context.oncare;
    final sessionArgs = (id: client.id, name: client.name);
    final sessions = ref.watch(clientSessionsProvider(sessionArgs));
    // Homework goes out via `assignRoutine`, which writes no schedule row.
    // Watching only the schedule left this card empty right after a send.
    final assigned = ref.watch(assignedRoutinesProvider(client.id));
    final rowStyle = tokens
        .text(OnCareTypography.strong(OnCareTypography.bodySmall))
        .copyWith(color: OnCareColors.textPrimary);
    return _SectionCard(
      title: l.coachSentHistory,
      icon: Icons.history_rounded,
      child: sessions.when(
        loading: () => const AppLoading(placement: AppStatePlacement.card),
        error: (e, _) => AppErrorState(
          title: l.coachHistoryFailed,
          retryLabel: l.actionRetry,
          onRetry: () => ref.invalidate(clientSessionsProvider(sessionArgs)),
          placement: AppStatePlacement.card,
        ),
        data: (list) {
          final withProgram = list
              .where((s) => s.program.isNotEmpty)
              .take(4)
              .toList();
          final routines = assigned.valueOrNull ?? const <AssignedRoutine>[];
          if (withProgram.isEmpty && routines.isEmpty) {
            return AppEmptyState(
              title: l.coachHistoryEmpty,
              icon: Icons.outbox_rounded,
              placement: AppStatePlacement.card,
            );
          }
          return Column(
            children: <Widget>[
              for (final routine in routines.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: OnCareSpacing.s4,
                  ),
                  child: Row(
                    children: <Widget>[
                      _SendHistoryTypeBadge(label: l.coachHomework),
                      Expanded(
                        child: Text(
                          l.coachRoutineSummary(routine.name, routine.minutes),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: rowStyle,
                        ),
                      ),
                      const SizedBox(width: OnCareSpacing.s4),
                      AppTag(
                        label: routine.source == 'ai' ? 'AI' : l.coachTrainer,
                        tone: AppTagTone.brand,
                        icon: routine.source == 'ai'
                            ? Icons.auto_awesome_rounded
                            : Icons.badge_rounded,
                      ),
                      // 보낸 뒤 물리는 자리. 여기 목록이 배정된 개인운동을
                      // 보여 주는 유일한 곳이다. (#1020)
                      _CancelRoutineButton(
                        clientId: client.id,
                        routine: routine,
                      ),
                    ],
                  ),
                ),
              for (final s in withProgram)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: OnCareSpacing.s4,
                  ),
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
                          style: rowStyle,
                        ),
                      ),
                      const SizedBox(width: OnCareSpacing.s4),
                      Text(
                        scheduleStatusLabel(l, s.status),
                        style: tokens
                            .text(
                              OnCareTypography.strong(OnCareTypography.caption),
                            )
                            .copyWith(
                              color: s.isDone
                                  ? OnCareColors.success
                                  : tokens.brand.primary,
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

/// 전송 이력의 프로그램 종류 — 개인운동과 PT를 같은 폭의 태그로 구분한다.
class _SendHistoryTypeBadge extends StatelessWidget {
  const _SendHistoryTypeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    // 종류마다 글자 수가 달라도 줄의 이름 칸이 같은 자리에서 시작하도록
    // 칸 폭을 고정한다.
    return Padding(
      padding: const EdgeInsets.only(right: OnCareSpacing.s8),
      child: SizedBox(
        key: ValueKey<String>('send-history-type-$label'),
        width: OnCareSpacing.s48,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AppTag(label: label, tone: AppTagTone.brand),
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
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.routineDeleteTitle,
      message: l.routineDeleteBody(widget.routine.name),
      confirmLabel: l.actionDelete,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(trainerRoutineRepositoryProvider)
          .deleteRoutine(widget.clientId, widget.routine.id);
      if (!mounted) return;
      showAppToast(context, l.routineDeleted, type: AppToastType.success);
    } on StateError {
      // 404 — 이미 없는 것을 지우려 했다. 목적은 이뤄진 셈이라 목록만 다시 읽고
      // 그 줄을 화면에서 걷어낸다.
      if (!mounted) return;
      showAppToast(context, l.routineAlreadyGone);
    } on Object {
      if (!mounted) return;
      showAppToast(context, l.routineDeleteFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
      ref.invalidate(assignedRoutinesProvider(widget.clientId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.only(left: OnCareSpacing.s8),
        child: AppLoading.inline(),
      );
    }
    return AppIconButton(
      key: ValueKey<String>('history-cancel-routine-${widget.routine.id}'),
      icon: Icons.close_rounded,
      tooltip: AppLocalizations.of(context).routineDelete,
      color: OnCareColors.textSecondary,
      onPressed: _cancel,
    );
  }
}
