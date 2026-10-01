import 'dart:async';
import 'dart:convert';

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
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_diet_period_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_exercise_status_card.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_period_section.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/diet_view.dart'
    show ClientDietAnalysisPanel;
import 'package:oncare_trainer/features/coaching/data/dtos/program_draft_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/ai_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/ai_routine_item.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/sent_delivery.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/features/coaching/presentation/pages/ai_routine_options_flow.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/personal_routine_box.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_editor_workspace.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_final_review_card.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_nutrition_summary_card.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_template_dialog.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show elapsedWeekdays, weekdayCount, weekdayLabels;
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_personal_routines.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_program_section.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_duration.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/member_health_profile_provider.dart';
// 예외 둘: 탭 이동 시 스크롤 초기화(UI 위젯 아님), 그리고 요일별 막대그래프
// — 패키지에 대응 차트가 없고 리포트 탭·테스트가 같은 위젯 타입을 쓴다.
import 'package:oncare_trainer/shared/widgets/client_picker_card.dart';
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
  const CoachingPage({
    super.key,
    this.clientId,
    this.attachSessionId,
    this.attachDate,
    this.attachRequest,
  });

  /// Client to preselect, from the `client` query parameter.
  final String? clientId;

  /// 개인운동을 붙일 스케줄의 PT(`attach`)와 그 날(`d`). (#2280)
  ///
  /// 일정 상세의 `개인운동 없음` 에서 온다 — 둘 다 있으면 위저드가 그 PT 에
  /// 붙일 개인운동 단계로 열린다([AppRoutes.coachingAttach]).
  final String? attachSessionId;
  final String? attachDate;

  /// 붙이기를 누른 한 번(`r`) — 같은 PT 를 다시 눌러도 흐름이 새로 열린다.
  final String? attachRequest;

  @override
  ConsumerState<CoachingPage> createState() => _CoachingPageState();
}

class _CoachingPageState extends ConsumerState<CoachingPage> {
  /// Selected client; null until clients load (defaults to the first).
  ///
  /// 명단이 오면 화면이 그리는 회원으로 확정한다(#2874) — `null` 로 남으면
  /// 이 값을 키로 쓰는 정리(템플릿 적용 때 개인운동 비우기 등)가 아무것도
  /// 지우지 못한다.
  late String? _clientId = widget.clientId;

  /// 주소의 `client` 가 명단에 없어 첫 회원으로 대신 연 그 값(#2874).
  ///
  /// 주소가 그대로인 다시 그리기마다 그 값으로 회원을 바꾸려 들지 않게
  /// [didUpdateWidget] 이 건너뛴다.
  String? _unresolvedClientId;
  final Map<String, String> _typeEdits = <String, String>{};
  final Map<String, List<AiRoutineItem>> _generatedRecommendations =
      <String, List<AiRoutineItem>>{};

  /// 위저드의 개인운동 단계에서 정한, 이 PT 와 함께 보낼 개인운동. (#2223)
  ///
  /// 편집기는 PT 구성만 다루므로 여기서 들고 있다가 `일정 추가` 에 함께 실어
  /// 보낸다 — 서버가 그 PT 일정에 붙여 두고, 회원에게는 PT 완료 때 간다(#2224).
  final Map<String, List<RoutineExercise>> _personalRoutines =
      <String, List<RoutineExercise>>{};

  /// 위저드에서 `개인운동만 짜기` 로 온 회원들. 이 회원의 편집기
  /// 자리에는 프로그램 박스 대신 개인운동 박스만 서고, 보내기도 거기서 한다.
  final Set<String> _routineOnlyClients = <String>{};

  /// 편집기에서 짜고 있는 PT 에 붙일 개인운동을 개인운동 단계에서 짜는 회원.
  /// (#2280)
  ///
  /// `직접 만들기`·저장한 프로그램 적용은 위저드를 지나지 않아 개인운동 단계가
  /// 없었다. 편집기는 숨겨 두고(상태는 그대로) 위저드의 개인운동 단계(AI
  /// 제안)만 연다 — 반영하면 편집기로 돌아와 `일정 추가` 가 함께 싣는다.
  String? _draftAttachFor;

  /// 붙일 수 있는 PT 후보 — 그 회원의 아직 보내지 않은 PT 전체. (#2280)
  ///
  /// 개인운동만 따로 짜는 입구는 하나다. 트레이너는 어디로 보낼지 고르지 않고
  /// 시작일만 고른다 — 그날 이 중 PT 가 있으면 그 PT 에 붙이고, 없으면 바로
  /// 보낸다([_routineOnlyTargetFor]). 아직 읽지 않은 회원은 여기 없다.
  final Map<String, List<ScheduleSession>> _routineOnlyCandidates =
      <String, List<ScheduleSession>>{};

  /// 스케줄의 `개인운동 추가` 에서 왔다 — 그 PT 에 반영하면 그 일정으로 돌아간다.
  ({String clientId, String sessionId, String date})? _returnToSchedule;

  /// `개인운동만 짜기` 를 고른 채로 열 위저드의 판번호([_wizardRevision]).
  /// 스케줄의 `개인운동 추가` 에서 왔을 때다. (#2280)
  ///
  /// 판번호로 가리킨다 — 참·거짓으로 들고 있으면 언제 거둘지가 문제다. 위저드는
  /// AI 추천을 읽은 뒤에야 서므로 다음 프레임에 거두면 위저드가 서기 전에
  /// 지워지고, 남겨 두면 PT 프로그램을 보낸 뒤 새로 서는 위저드까지 `개인운동만`
  /// 으로 열린다. 판번호가 바뀌면 저절로 끝난다.
  int? _routineOnlyWizardRevision;

  /// 이미 받은 붙이기 요청(`r`). 탭을 옮겨 다녀도 코칭 탭 주소에는 그 요청이
  /// 남아 있어, 돌아올 때마다 위저드가 다시 세워지지 않게 한다. 같은 PT 라도
  /// 스케줄에서 다시 누르면 새 요청이라 다시 열린다.
  final Set<String> _consumedAttachRequests = <String>{};

  /// `개인운동만` 이 회원 목록에 걸리기 시작할 날. 기본은 오늘이다.
  final Map<String, DateTime> _routineOnlyStart = <String, DateTime>{};

  /// 지금 `개인운동만` 을 보내고 있는 회원들.
  final Set<String> _sendingRoutineOnly = <String>{};
  ProgramTemplate? _appliedTemplate;
  int _templateRevision = 0;
  int _editorRevision = 0;

  /// AI 1~3단계와 프로그램 편집기 중 어느 쪽을 표시할지 정한다.
  bool _aiWizardVisible = true;

  /// 위저드를 새로 세우기 위한 번호. 전송이 끝나면 하나 올려 위저드가 1 단계
  /// 부터 다시 서게 한다 — 그러지 않으면 `AI 추천으로 돌아가기` 가 **방금
  /// 보낸 구성을 그대로** 펼쳐, 보냈다는 표시도 없이 다시 반영할 수 있다.
  int _wizardRevision = 0;

  /// 위저드의 단계 진행 줄. 위저드는 편집기 열의 스크롤 안에 있어서, 진행
  /// 줄을 여기로 넘겨받아 그 스크롤 **바로 아래**에 둔다(#2476).
  final ValueNotifier<Widget?> _wizardNav = ValueNotifier<Widget?>(null);

  /// [_wizardNav] 를 마지막으로 넘긴 위저드 화면.
  Object? _wizardNavOwner;

  /// 위저드가 진행 줄을 넘기거나(`nav`) 사라지며 거둔다(`null`). 회원을 바꾸면
  /// 새 위저드가 먼저 제 줄을 넘기고 옛 위저드가 뒤이어 거두므로, 거두는 것은
  /// 지금 줄을 넘긴 그 화면일 때만 받는다.
  void _onWizardNav(Object owner, Widget? nav) {
    if (!mounted) return;
    if (nav == null && !identical(owner, _wizardNavOwner)) return;
    _wizardNavOwner = nav == null ? null : owner;
    _wizardNav.value = nav;
  }

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
    _resetNotifier?.removeListener(_resetScroll);
    _sentTimer?.cancel();
    _wizardNav.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _consumeAttachRoute();
  }

  @override
  void didUpdateWidget(CoachingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Following a second "AI 루틴 만들기" link (from another client's
    // 개요) must switch the workspace, not silently keep the old one.
    //
    // 주소가 선택 회원의 원천이다(#2872) — 지난 주소가 아니라 **지금 보이는
    // 회원**과 견준다. 주소가 그대로인 재진입(앞 주소와 같은 `client`)도
    // 화면이 다른 회원을 보고 있으면 그 회원으로 돌아온다.
    if (widget.clientId != null &&
        widget.clientId != _clientId &&
        widget.clientId != _unresolvedClientId) {
      _selectClient(widget.clientId!);
    }
    if (widget.attachSessionId != oldWidget.attachSessionId ||
        widget.attachRequest != oldWidget.attachRequest ||
        widget.clientId != oldWidget.clientId) {
      setState(_consumeAttachRoute);
    }
  }

  /// 스케줄의 `개인운동 추가` 에서 왔으면 `개인운동만 짜기` 를 고른 위저드를
  /// 새로 세우고, 시작일을 그 PT 날로 잡아 둔다. (#2280)
  ///
  /// 상태만 바꾼다 — 다시 그리는 것은 부르는 쪽 몫이다(`initState` 에서도
  /// 부른다).
  void _consumeAttachRoute() {
    final String? clientId = widget.clientId;
    final String? sessionId = widget.attachSessionId;
    final String? date = widget.attachDate;
    if (clientId == null || sessionId == null || date == null) return;
    if (!_consumedAttachRequests.add(widget.attachRequest ?? sessionId)) {
      return;
    }
    // 그 PT 날을 시작일로 잡아 둔다 — 그날 PT 가 있으니 그 PT 에 붙는다.
    final DateTime? day = DateTime.tryParse(date);
    if (day != null) _routineOnlyStart[clientId] = day;
    _returnToSchedule = (clientId: clientId, sessionId: sessionId, date: date);
    _personalRoutines.remove(clientId);
    _routineOnlyClients.remove(clientId);
    _draftAttachFor = null;
    _sent = false;
    _aiWizardVisible = true;
    _wizardRevision++;
    _routineOnlyWizardRevision = _wizardRevision;
  }

  void _selectClient(String id) {
    if (_clientId == id) return;
    setState(() {
      _clientId = id;
      _unresolvedClientId = null;
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
      _wizardRevision = 0;
      // 다른 회원으로 옮기면 붙이던 흐름은 거둔다 — 그 PT 는 앞 회원의 것이다.
      _draftAttachFor = null;
      _routineOnlyWizardRevision = null;
      // NOTE: _sendingClientIds is intentionally NOT cleared — writes for
      // other clients keep being tracked while the selection changes.
    });
    _sentTimer?.cancel();
  }

  /// 회원 카드를 눌렀다 — 상태가 아니라 **주소**를 바꾼다(#2872).
  ///
  /// 화면은 바뀐 주소를 [didUpdateWidget] 에서 받아 [_selectClient] 로
  /// 바뀐다. 그래야 새로고침·주소 공유·뒤로 가기가 모두 같은 회원을 연다.
  /// 리포트 화면의 회원 전환처럼 기록을 남기는 `go` 다. 붙이기 흐름 쿼리
  /// (`attach`·`d`·`r`)는 앞 회원의 PT 것이라 떼고 `client` 만 남긴다.
  Future<void> _requestClient(String id) async {
    if (id == _clientId) return;
    if (!mounted) return;
    context.go(AppRoutes.coachingFor(id));
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
              // 시·분·초로 적은 초를 그대로 담는다(#2521) — 분으로 접으면
              // `버피 45초` 가 `1분` 으로 남는다. 근력은 세트에서 환산한
              // 시간을 담는다 — 템플릿의 총 시간이 유형과 무관하게 한 축으로
              // 읽혀야 한다 (#1276).
              durationSeconds: exercise.isStrength
                  ? exercise.effectiveMinutes * 60
                  : exercise.durationSeconds,
              type: kRoutineTypes.contains(exercise.type)
                  ? exercise.type
                  : kRoutineTypes.first,
              // 근력이면 편집기에서 정한 세트·횟수·중량을 그대로 템플릿에
              // 담는다 — 비워 두면 다시 열었을 때 기본값으로 되돌아간 것처럼
              // 보인다. 한 세트는 회로든 초로든 한 번만 잰다(#1969) — 횟수와
              // 버티는 초 중 고른 쪽만 싣는다. 예전에는 횟수·초를 싣지 않아
              // `12회` 가 `10회` 로, 버티는 운동이 회로 돌아왔다. (#2521)
              sets: exercise.isStrength ? exercise.sets : 0,
              reps: exercise.isStrength && !exercise.isHold ? exercise.reps : 0,
              holdSeconds: exercise.isStrength && exercise.isHold
                  ? exercise.holdSeconds
                  : 0,
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

  /// 편집기의 `일정 추가` 가 부른다 — 확인창을 띄우고, 확인되면 회원 배정과
  /// `개인운동만` 을 회원에게 보낸다. (#2223)
  ///
  /// 붙일 PT 일정이 없으므로 배정만 한다 — 자리와 모양은 PT 모드의 `일정 추가`
  /// 와 같고, 이름만 `회원에게 보내기` 다. 운동 하나가 배정 한 건이 되고, 고른
  /// 시작일부터 한 주 동안 회원 목록에 걸린다.
  ///
  /// 시작일에 아직 보내지 않은 PT 가 있으면 보내지 않고 그 PT 에 붙인다(#2280,
  /// [_attachRoutineOnlyToPt]). 회원에게는 스케줄에서 그 PT 와 함께 간다.
  Future<void> _sendRoutineOnly(TrainerClient client) async {
    final routines = _personalRoutines[client.id] ?? const <RoutineExercise>[];
    if (_sent || _sendingRoutineOnly.contains(client.id) || routines.isEmpty) {
      return;
    }
    // 그날 PT 를 아직 읽지 못했으면 누르지 못한다 — 박스가 버튼을 잠근다.
    if (!_routineOnlyCandidates.containsKey(client.id)) return;
    final ScheduleSession? target = _routineOnlyTargetFor(client.id);
    if (target != null) {
      await _attachRoutineOnlyToPt(client, target.id, routines);
      return;
    }
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime start = _routineOnlyStart[client.id] ?? _todayKst();
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: l.aiRoutineOnlySend,
      message: l.programRoutineOnlyConfirmBody(
        client.name,
        ymd(start),
        ymd(start.add(const Duration(days: PersonalRoutineBox.activeDays - 1))),
      ),
      confirmLabel: l.actionSend,
      cancelLabel: l.actionCancel,
    );
    if (!confirmed || !mounted || !_isStillSelected(client.id)) return;

    final sentFor = client.id;
    // 실패 후 재시도는 **같은 내용이면 같은 키**여야 중복 배정이 막히고, 내용이
    // 달라졌으면 새 키여야 고친 것이 반영된다(#581) — 프로그램 전송과 같은
    // 지문 방식이다.
    final payload = routineOnlyAssignToJson(
      routines,
      // 저장 이름에는 기간을 넣지 않는다(#2581) — 보낸 날부터 7일이라 `이번 주`
      // 가 달력의 이번 주와 맞지 않는다. 회원 앱은 이 이름을 카드에 적지 않는다.
      programName: l.aiRoutineOnlyDeliveryName,
      startDate: ymd(start),
      activeDays: PersonalRoutineBox.activeDays,
    );
    final requestId = _requestIdFor(sentFor, payload);
    setState(() => _sendingRoutineOnly.add(sentFor));
    try {
      await ref.read(trainerRoutineRepositoryProvider).assignProgram(
        sentFor,
        <String, Object?>{...payload, 'client_request_id': requestId},
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _sendingRoutineOnly.remove(sentFor));
      if (_isStillSelected(sentFor)) {
        showAppToast(
          context,
          _sendFailureMessage(l, error),
          type: AppToastType.error,
        );
      }
      return;
    }
    _sendRequests.remove(sentFor);
    // 보낸 뒤에도 목록과 `개인운동만` 표시를 그대로 둔다 — 지우면 그 자리에
    // PT 편집기가 올라와, 방금 개인운동을 보낸 트레이너가 손댄 적 없는 PT
    // 프로그램 화면을 보게 된다. PT 모드가 보낸 뒤 프로그램 박스를 남기는
    // 것과 같아야 한다(#2223). 두 번째 전송은 `_sent` 가 막는다.
    if (!mounted) return;
    ref.invalidate(assignedRoutinesProvider(sentFor));
    // 전송 이력 카드는 직전 전송(`_latestDeliveryProvider`)을 따로 읽는다 —
    // 다시 읽게 하지 않으면 탭을 옮겨 다녀와야 방금 보낸 것이 보인다(#2280,
    // #2750).
    ref.invalidate(_latestDeliveryProvider(sentFor));
    // 보낸 개인운동을 채운 AI 제안은 서버가 이 전송으로 닫았다(#2747) — 다시
    // 읽게 해야 새로 선 위저드가 보낸 제안을 다시 채우지 않는다.
    ref.invalidate(routineSuggestionsProvider(sentFor));
    final stillSelected = _isStillSelected(sentFor);
    setState(() {
      _sendingRoutineOnly.remove(sentFor);
      if (stillSelected) {
        _sent = true;
        _wizardRevision++;
      }
    });
    if (!stillSelected) return;
    showAppToast(context, l.aiRoutineOnlySent, type: AppToastType.success);
  }

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
          type: AppToastType.error,
        );
      }
      return;
    }
    if (!mounted || !_isStillSelected(client.id)) return;
    final personalRoutines =
        _personalRoutines[client.id] ?? const <RoutineExercise>[];
    final confirmation = await showProgramAssignConfirmDialog(
      context,
      clientName: client.name,
      registerDate: _registerDate,
      registerStartTime: _registerStartTime,
      registerEndTime: _registerEndTime,
      candidates: candidates,
      // PT 와 함께 갈 개인운동을 저장 직전에 한 번 더 보여 준다 — 편집기에는
      // 개인운동 자리가 없어, 여기가 둘을 한 화면에서 확인하는 유일한 곳이다
      // (#2223).
      personalRoutines: personalRoutines,
    );
    if (confirmation == null || !mounted || !_isStillSelected(client.id)) {
      return;
    }
    final String? targetId = confirmation.sessionId;
    if (personalRoutines.isEmpty) {
      // 개인운동 없이 일정에 올리려 하면 한 번 붙잡는다(#2280). `직접 만들기`·
      // 저장한 프로그램 적용은 위저드의 개인운동 단계를 지나지 않는다. 막지는
      // 않는다 — 개인운동을 줄 수 없는 날도 있고, 스케줄의 일정 상세에서
      // 나중에 붙일 수도 있다.
      //
      // 어느 PT 에 올릴지 정한 **뒤에** 묻는다 — 개인운동이 이미 붙은 PT 의
      // 프로그램만 다시 올리면 서버가 붙어 있던 것을 그대로 두므로 "개인운동
      // 없이" 가 아니다. 붙어 있는지 읽지 못했으면 묻는 쪽으로 둔다.
      final List<RoutineExercise>? attached = targetId == null
          ? null
          : await _unsentRoutinesOn(targetId);
      if (!mounted || !_isStillSelected(client.id)) return;
      if (attached == null || attached.isEmpty) {
        final choice = await showNoPersonalRoutineDialog(
          context,
          title: l.progNoRoutinesRegisterTitle,
          body: l.progNoRoutinesRegisterBody,
          skipLabel: l.progNoRoutinesRegisterSkip,
        );
        if (choice == null || !mounted || !_isStillSelected(client.id)) {
          return;
        }
        // 붙이러 가면 일정에 올리지 않는다 — 개인운동 단계(AI 제안)에서 짜고
        // 편집기로 돌아와 다시 `일정 추가` 를 누른다.
        if (choice == NoPersonalRoutineChoice.add) {
          _startDraftAttach(client);
          return;
        }
      }
    } else if (targetId != null && !await _confirmReplaceIfAttached(targetId)) {
      // 이미 있는 PT 에 붙이는데 그 PT 에 개인운동이 붙어 있으면, 새로 짠
      // 것으로 바꾸는지 한 번 묻는다(#2280) — 서버는 붙어 있던 것을 새것으로
      // 갈아 끼운다.
      return;
    }
    if (!mounted || !_isStillSelected(client.id)) return;
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
      // 개인운동이 달라지면 다른 전송이다 — 같은 키를 쓰면 바뀐 개인운동이
      // 재시도에서 조용히 무시된다.
      personalRoutinesToJson(personalRoutines),
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
            personalRoutines: personalRoutines,
          );
    } catch (error) {
      if (!mounted) return;
      setState(() => _sendingClientIds.remove(sentFor));
      if (_isStillSelected(sentFor)) {
        showAppToast(
          context,
          _sendFailureMessage(l, error),
          type: AppToastType.error,
        );
      }
      return;
    }
    _sendRequests.remove(sentFor);
    // 보냈다 — 같은 개인운동이 다음 전송에 다시 딸려 가지 않게 비운다.
    _personalRoutines.remove(sentFor);
    if (!mounted) return;
    // 배정 목록(`assignedRoutinesProvider`)은 실 API 모드에서 1회성 fetch 라
    // 다시 읽으라고 말해 줘야 한다(#1029). 일정 쪽은 저장소가 스스로 다시
    // 읽는다.
    ref.invalidate(assignedRoutinesProvider(sentFor));
    // 3열 `전송 이력` 카드는 배정 목록이 아니라 직전 전송
    // (`_latestDeliveryProvider`, #2225)을 따로 읽는다 — 카드가 전송 동안에도
    // 떠 있어 autoDispose 로 버려지지 않으므로, 여기서 무효화하지 않으면
    // 화면을 떠났다 와야 갱신된다(#2750). 그 위 `아직 보내지 않은 개인운동`
    // 안내도 따로 읽는다 — 일정에 올린 PT 에 붙은 개인운동이 안내에 바로
    // 서야 한다(#2280).
    ref.invalidate(_latestDeliveryProvider(sentFor));
    ref.invalidate(_unsentRoutinesProvider(sentFor));
    // 함께 붙인 개인운동을 채운 AI 제안도 이 등록으로 닫혔다(#2747).
    ref.invalidate(routineSuggestionsProvider(sentFor));
    final stillSelected = _isStillSelected(sentFor);
    setState(() {
      _sendingClientIds.remove(sentFor);
      if (stillSelected) {
        _sent = true;
        _wizardRevision++;
      }
    });
    if (!stillSelected) return;
    // 등록 완료는 인라인 문구가 아니라 다른 성공 알림과 같은 상단
    // 토스트로 뜬다(#1536) — "스케줄로 이동" 액션으로 바로 그 날짜의
    // 스케줄 탭을 연다. `AppToastType`엔 경고 종류가 없어, 기존 세션에
    // 붙은 경우도 실패는 아니므로 `info`로 알린다.
    showAppToast(
      context,
      attachedToExisting
          ? l.coachRegisteredAttachedExisting(_dateChipLabel(l, registerDate))
          : l.coachRegisteredOn(_dateChipLabel(l, registerDate)),
      type: attachedToExisting ? AppToastType.info : AppToastType.success,
      actionLabel: l.coachGoToSchedule,
      onAction: () => context.go(AppRoutes.scheduleAt(date: date)),
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
      type: AppToastType.error,
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
        // 새로 잡을 자리가 다른 회원 일정과 겹친다(#2284) — 재시도해도 같으니
        // 시간을 바꾸게 한다.
        ScheduleOverlapError() => l.coachScheduleOverlap,
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
            // 초가 기준이다(#2521) — 분만 실으면 일정의 운동 목록이 분 × 60
            // 으로 되짚혀, 편집기의 45초가 스케줄·회원 앱에서 `1분` 이 된다.
            durationSeconds: exercise.isStrength
                ? null
                : exercise.durationSeconds,
            sets: exercise.isStrength ? exercise.sets : null,
            // 한 세트는 회로든 초로든 한 번만 잰다 — 고르지 않은 쪽은
            // 비운다(#1969).
            reps: exercise.isStrength && !exercise.isHold
                ? exercise.reps
                : null,
            holdSeconds: exercise.isStrength && exercise.isHold
                ? exercise.holdSeconds
                : null,
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
        headerCenter: const ClientSearchBar(),
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
                icon: AppIcons.clients,
              );
            }
            final selected = clients.firstWhere(
              (c) => c.id == _clientId,
              orElse: () => clients.first,
            );
            // 그리는 회원을 상태에도 확정한다(#2874). 회원 미지정(`/coaching`)
            // 이나 명단에 없는 `client` 로 들어오면 화면은 첫 회원을 그리는데
            // 상태는 `null`(또는 그 값)로 남아, 상태 키로 지우는 정리가 빗나갔다.
            // 그리는 결과는 같으므로 다시 그리지 않고 값만 맞춘다.
            if (_clientId != selected.id) {
              _unresolvedClientId = _clientId;
              _clientId = selected.id;
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= OnCareLayout.splitBreakpoint;
                // 3열의 고정 폭(왼쪽 목록 + 오른쪽 고객 데이터 열 + 간격 둘)을
                // 빼고도 편집기가 입력 폼 폭만큼은 가져야 한다.
                final fullWidth =
                    constraints.maxWidth >=
                    clientPickerColumnWidth +
                        OnCareLayout.splitListWidth +
                        OnCareLayout.splitGap +
                        OnCareLayout.splitGap +
                        OnCareLayout.dialogSmall;
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: ListView(
                          children: <Widget>[
                            // Single column: context, then the editor, then
                            // the library. The editor is the task — pushing it
                            // below the templates would bury it.
                            ..._contextChildren(l, clients, selected),
                            const SizedBox(height: OnCareSpacing.s16),
                            ..._editorChildren(selected),
                            const SizedBox(height: OnCareSpacing.s16),
                            ..._libraryChildren(selected),
                          ],
                        ),
                      ),
                      _wizardNavBar(),
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
                            // 회원을 고르는 열이라 분할 목록 폭의 3분의 2만
                            // 쓴다 — 리포트 탭 왼쪽 열과 같은 폭이다.
                            width: clientPickerColumnWidth,
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
                                    clientSidebarSplitMinHeight(context);
                                // 리포트 탭 회원 목록과 같은 위젯이다.
                                final list = ClientPickerList(
                                  clients: clients,
                                  selectedId: selected.id,
                                  onSelect: _requestClient,
                                  rowKeyPrefix: 'program-client',
                                  scrollKey: 'program-client-list-scroll',
                                );
                                final template = _TemplateCard(
                                  key: const ValueKey<String>(
                                    'program-template-sidebar',
                                  ),
                                  onApply: (template) =>
                                      _applyTemplate(selected, template),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                // 내용이 짧으면 진행 줄이 내용 바로 아래에
                                // 붙고, 열보다 길면 열 바닥에 머문다(#2476).
                                Flexible(
                                  child: SingleChildScrollView(
                                    key: const ValueKey<String>(
                                      'coaching-program-page-scroll',
                                    ),
                                    child: Column(
                                      key: const ValueKey<String>(
                                        'coaching-wide-main-column',
                                      ),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: <Widget>[
                                        // 오른쪽 열을 세울 만큼 넓지 않은
                                        // 창에서는 식단·운동이 가운데 열
                                        // **맨 위**에 온다 — 넓은 화면의
                                        // 오른쪽 열 맨 위와 같은 자리다(#1027).
                                        if (!fullWidth) ...<Widget>[
                                          _ClientDataSwitcher(
                                            key: const ValueKey<String>(
                                              'coaching-wide-client-overview',
                                            ),
                                            client: selected,
                                          ),
                                          const SizedBox(
                                            height: OnCareSpacing.s16,
                                          ),
                                        ],
                                        ..._editorChildren(selected),
                                        if (!fullWidth) ...<Widget>[
                                          const SizedBox(
                                            height: OnCareSpacing.s16,
                                          ),
                                          _SendHistoryCard(client: selected),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                _wizardNavBar(),
                              ],
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

  /// 위저드 단계 진행 줄(`이전` · 다음 단계). 편집기 열 스크롤 바로 아래에
  /// 둔다 — 내용이 짧으면 내용 바로 다음 줄에, 열보다 길면 열 바닥에 머물러
  /// 카드를 채우는 동안에도 어디서 넘어가는지 보인다(#2476). 위저드를 닫으면
  /// 걷는다.
  Widget _wizardNavBar() {
    // 붙이기 흐름의 위저드는 제 진행 줄을 내용 끝에 붙인다(#2280).
    if (!_aiWizardVisible || _draftAttachFor != null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<Widget?>(
      valueListenable: _wizardNav,
      builder: (context, nav, _) => nav == null
          ? const SizedBox.shrink()
          : Padding(
              // 위저드 카드 사이와 같은 간격이다.
              padding: const EdgeInsets.only(top: OnCareSpacing.s16),
              child: nav,
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
                child: ClientPickerCard(
                  client: c,
                  stacked: true,
                  selected: c.id == client.id,
                  onTap: () => _requestClient(c.id),
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
      _TemplateCard(onApply: (template) => _applyTemplate(client, template)),
      const SizedBox(height: OnCareSpacing.s16),
      _SendHistoryCard(client: client),
    ];
  }

  /// [client] 의 편집기에 [template] 을 적용한다.
  ///
  /// 대상 회원을 인자로 받는다(#2874) — 편집기가 그리는 회원의 개인운동을
  /// 지워야 한다. 상태 키(`_clientId`)로 지우면 화면 회원과 어긋났을 때
  /// 앞서 짠 개인운동이 템플릿 프로그램과 함께 전송된다.
  void _applyTemplate(TrainerClient client, ProgramTemplate template) =>
      setState(() {
        _appliedTemplate = template;
        _templateRevision++;
        _aiWizardVisible = false;
        _sent = false;
        // 템플릿은 편집기 내용을 갈아 끼운다 — 앞서 위저드에서 정한 개인운동은
        // 그 PT 구성에 맞춰 짠 것이라, 여기 남겨 두면 전혀 다른 PT 에 딸려 간다.
        _personalRoutines.remove(client.id);
        // `개인운동만` 으로 짜던 회원이어도 템플릿은 PT 프로그램이다 — 그대로
        // 두면 편집기가 숨은 채 빈 개인운동 박스만 남는다.
        _routineOnlyClients.remove(client.id);
      });

  /// 편집기 아래 개인운동 박스의 `개인운동 수정`. (#2280)
  ///
  /// 일정 상세의 `개인운동 수정` 과 **같은 창**을 쓴다 — 개인운동을 고치는 창이
  /// 자리마다 다르면 트레이너가 헷갈린다. 처음 짜는 것은 이 창이 아니라 개인운동
  /// 단계([_startDraftAttach])다. 저장했으면 참을 준다.
  Future<bool> _editPersonalRoutines(TrainerClient client) async {
    final edited = await showAppDialog<List<RoutineExercise>>(
      context: context,
      builder: (_) => SendPersonalRoutinesDialog(
        routines: _personalRoutines[client.id] ?? const <RoutineExercise>[],
        editOnly: true,
        goal: client.goal,
      ),
    );
    if (edited == null || !mounted || !_isStillSelected(client.id)) {
      return false;
    }
    setState(() => _personalRoutines[client.id] = edited);
    return true;
  }

  /// 편집기에서 짜고 있는 PT 에 붙일 개인운동을 위저드의 개인운동 단계에서
  /// 짠다. (#2280)
  ///
  /// `직접 만들기`·저장한 프로그램 적용은 위저드를 지나지 않아 개인운동 단계가
  /// 없었다. 편집기는 그대로 두고(숨겨 두고) 개인운동 단계만 연다 — AI 제안을
  /// 받아 짜야 한다. 프로그램도 AI 로 짜고, 고치는 것만 부분 창에서 한다.
  void _startDraftAttach(TrainerClient client) =>
      setState(() => _draftAttachFor = client.id);

  /// `개인운동만 짜기` 에서 짠 개인운동을 시작일의 PT 에 붙인다. (#2280)
  ///
  /// 회원에게 보내지 않는다 — 그 PT 의 프로그램을 보낼 때 함께 간다. 그 PT 에
  /// 개인운동이 이미 있으면 교체하는지 한 번 묻는다. 스케줄에서 왔으면 붙인 뒤
  /// 그 일정으로 돌아간다.
  Future<void> _attachRoutineOnlyToPt(
    TrainerClient client,
    String sessionId,
    List<RoutineExercise> routines,
  ) async {
    final l = AppLocalizations.of(context);
    final sentFor = client.id;
    setState(() => _sendingRoutineOnly.add(sentFor));
    final bool proceed = await _confirmReplaceIfAttached(sessionId);
    if (!mounted) return;
    if (!proceed) {
      setState(() => _sendingRoutineOnly.remove(sentFor));
      return;
    }
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .updateScheduledRoutines(sessionId, routines);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sendingRoutineOnly.remove(sentFor));
      showAppToast(
        context,
        l.schedRoutinesUpdateFailed,
        type: AppToastType.error,
      );
      return;
    }
    if (!mounted) return;
    // 스케줄 화면은 그동안 떠 있지 않았다 — 돌아가면 다시 읽게 한다.
    ref.read(scheduledRoutinesRevisionProvider.notifier).state++;
    // 전송 이력 위 `아직 보내지 않은 개인운동` 안내가 방금 붙인 것을 바로
    // 보이게 한다.
    ref.invalidate(_unsentRoutinesProvider(sentFor));
    // 붙인 개인운동을 채운 AI 제안은 이 요청으로 닫혔다(#2747) — 다시 읽어야
    // 다음 위저드가 그 제안을 다시 채우지 않는다.
    ref.invalidate(routineSuggestionsProvider(sentFor));
    final back = _returnToSchedule;
    final String? backDate =
        back != null && back.clientId == sentFor && back.sessionId == sessionId
        ? back.date
        : null;
    final bool goBack = backDate != null;
    final stillSelected = _isStillSelected(sentFor);
    // `개인운동만` 을 보낸 뒤와 같이 박스를 그대로 두고 두 번째 반영만 막는다.
    setState(() {
      _sendingRoutineOnly.remove(sentFor);
      if (goBack) _returnToSchedule = null;
      if (stillSelected) {
        _sent = true;
        _wizardRevision++;
      }
    });
    showAppToast(context, l.schedRoutinesAdded, type: AppToastType.success);
    if (goBack) {
      context.go(AppRoutes.scheduleAt(date: backDate, sessionId: sessionId));
    }
  }

  /// 붙일 수 있는 PT 후보를 읽는다 — 그 회원의 아직 보내지 않은 PT 전체.
  /// (#2280)
  ///
  /// 일정 상세가 처음 붙이게 하는 PT 와 같은 규칙이다
  /// ([acceptsFirstPersonalRoutines]). 개인운동이 이미 붙은 PT 도 후보다 —
  /// 고르면 교체할지 묻는다. 날짜·시각 순으로 늘어놓는다.
  Future<void> _loadRoutineOnlyCandidates(TrainerClient client) async {
    List<ScheduleSession> sessions;
    try {
      sessions = await ref.read(scheduleRepositoryProvider).watchClientSessions(
        (id: client.id, name: client.name),
      ).first;
    } catch (_) {
      // 읽지 못한 채로 두면 버튼이 잠긴다 — 빈 목록으로 두면 PT 가 있는 날인데도
      // 바로 보내 버린다.
      if (!mounted) return;
      showAppToast(
        context,
        AppLocalizations.of(context).schedLoadFailed,
        type: AppToastType.error,
      );
      return;
    }
    if (!mounted) return;
    final candidates = sessions.where(acceptsFirstPersonalRoutines).toList()
      ..sort((a, b) => '${a.date} ${a.time}'.compareTo('${b.date} ${b.time}'));
    setState(() => _routineOnlyCandidates[client.id] = candidates);
  }

  /// `개인운동만` 을 붙일 PT — 시작일에 있는 아직 보내지 않은 PT. (#2280)
  ///
  /// 같은 날 둘이면 먼저 시작하는 PT 다. 한 회원이 하루에 PT 를 두 번 받는 일은
  /// 드물어 고르게 하지 않고, 박스가 어느 PT 인지 시각까지 적는다. null 이면
  /// 그날 PT 가 없다 — 바로 보낸다.
  ScheduleSession? _routineOnlyTargetFor(String clientId) {
    final String day = ymd(_routineOnlyStart[clientId] ?? _todayKst());
    for (final ScheduleSession s
        in _routineOnlyCandidates[clientId] ?? const <ScheduleSession>[]) {
      if (s.date == day) return s;
    }
    return null;
  }

  /// 시작일에 PT 가 없을 때 알려 줄 아직 보내지 않은 PT. (#2280)
  ///
  /// 지나간 PT 가 먼저다 — 완료했지만 아직 보내지 않은 PT 는 곧 스케줄에서
  /// 보낼 것이라, 거기 붙이지 않고 바로 보내면 그 PT 를 보낼 때 개인운동이
  /// 없다고 한 번 더 붙잡힌다. 그다음이 오늘 이후 첫 PT 다. 후보는 날짜·시각
  /// 순이라 첫 줄이 곧 그 PT 다.
  ScheduleSession? _nearestRoutineOnlyPt(String clientId) {
    final List<ScheduleSession> candidates =
        _routineOnlyCandidates[clientId] ?? const <ScheduleSession>[];
    return candidates.isEmpty ? null : candidates.first;
  }

  /// [sessionId] PT 에 아직 보내지 않은 개인운동이 붙어 있으면 새로 짠 것으로
  /// 바꾸는지 묻는다. 바꿔도 되면(붙은 것이 없어도) 참이다. (#2280)
  ///
  /// 붙어 있는지 읽지 못했으면 거짓이다 — 모르는 채로 바꾸면 스케줄에서 손봐
  /// 둔 개인운동이 말없이 사라질 수 있다.
  Future<bool> _confirmReplaceIfAttached(String sessionId) async {
    final l = AppLocalizations.of(context);
    final List<RoutineExercise>? attached = await _unsentRoutinesOn(sessionId);
    if (!mounted) return false;
    if (attached == null) {
      showAppToast(
        context,
        l.schedRoutinesUpdateFailed,
        type: AppToastType.error,
      );
      return false;
    }
    if (attached.isEmpty) return true;
    return showAppConfirmDialog(
      context: context,
      title: l.aiReplaceRoutinesTitle,
      message: l.aiReplaceRoutinesBody(
        attached.length,
        attached.map((e) => e.name).join(' · '),
      ),
      confirmLabel: l.aiReplaceRoutinesConfirm,
    );
  }

  /// [sessionId] PT 에 붙어 있는 아직 보내지 않은 개인운동. 읽지 못했으면
  /// null 이다. (#2280)
  Future<List<RoutineExercise>?> _unsentRoutinesOn(String sessionId) async {
    try {
      return <RoutineExercise>[
        for (final SessionRoutine r
            in await ref
                .read(scheduleRepositoryProvider)
                .fetchScheduledRoutines(sessionId))
          if (!r.sent) r.exercise,
      ];
    } catch (_) {
      return null;
    }
  }

  void _startManualProgram(String clientId) => setState(() {
    _generatedRecommendations.remove(clientId);
    // 빈 편집기로 새로 시작한다 — 앞서 위저드에서 정한 개인운동도 함께 버린다.
    _personalRoutines.remove(clientId);
    _appliedTemplate = null;
    _templateRevision = 0;
    _editorRevision++;
    _aiWizardVisible = false;
    _sent = false;
  });

  /// The routine editor column (right column on wide).
  ///
  /// `AI에게 맞춤 루틴 요청하기` 는 `프로그램 정보` 박스([ProgramEditorWorkspace])
  /// 바로 위에 항상 붙인다. 실제 전송은 편집기의 `보내기` 가 [_sendProgram] 을
  /// 통해 호출부에서만 한다.
  List<Widget> _editorChildren(TrainerClient client) {
    final AppLocalizations l = AppLocalizations.of(context);
    final routineArgs = (id: client.id, name: client.name);
    final routineAsync = ref.watch(aiRoutineProvider(routineArgs));

    final List<Widget> children = <Widget>[
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
                key: ValueKey<String>(
                  'routine-options-${client.id}-$_wizardRevision',
                ),
                client: client,
                embedded: true,
                onStepNav: _onWizardNav,
                recommendedExercises: items
                    .map(
                      (item) => RoutineExercise(
                        name: item.name,
                        minutes: item.minutes,
                        durationSeconds: item.durationSeconds,
                        type: _typeEdits[item.id] ?? item.type,
                      ),
                    )
                    .toList(growable: false),
                recommendedReason: items.isEmpty
                    ? ''
                    : items.map((item) => item.reason).join(' · '),
                // 스케줄의 `개인운동 추가` 에서 왔으면 `개인운동만 짜기` 를
                // 고른 채로 연다(#2280).
                startRoutineOnly: _routineOnlyWizardRevision == _wizardRevision,
                onReviewCompleted: (exercises, personalRoutines, kind) {
                  final bool routineOnly = kind == ProgramKind.routineOnly;
                  if (routineOnly) {
                    // 새로 읽는다 — 그사이 스케줄에서 보낸 PT 가 남지 않게.
                    _routineOnlyCandidates.remove(client.id);
                    unawaited(_loadRoutineOnlyCandidates(client));
                  }
                  // 새 구성을 반영하면 새 전송이다 — 템플릿 적용·직접 만들기와
                  // 같은 규칙이다(#2752). 풀지 않으면 `개인운동만` 을 보낸 뒤
                  // 위저드로 짠 PT 의 `일정 추가` 가 이유 없이 잠기고 개인운동
                  // 박스가 `보냄` 으로 남는다. 같은 구성을 곧바로 두 번 보내는
                  // 것은 위저드를 다시 지나야 하므로 여전히 막힌다.
                  //
                  // PT 전송 뒤 3초 타이머가 아직 돌고 있으면 그 일(보낸 구성을
                  // 담은 편집기를 새로 세우기)을 지금 하고 거둔다 — 늦게 울리면
                  // 방금 반영한 구성까지 지우고, 거두기만 하면 보낸 구성 뒤에
                  // 새 구성이 덧붙는다.
                  final bool rebuildEditor = _sentTimer?.isActive ?? false;
                  _sentTimer?.cancel();
                  setState(() {
                    _sent = false;
                    if (rebuildEditor) _editorRevision++;
                    _personalRoutines[client.id] = personalRoutines;
                    if (routineOnly) {
                      _routineOnlyClients.add(client.id);
                      // 스케줄에서 왔으면 그 PT 날이 이미 잡혀 있다 — 지난
                      // PT 라도 그대로 둔다. 그 밖에 지난 날이 남아 있으면
                      // 오늘로 되돌린다 — 지난 날로는 걸지 않는다.
                      final DateTime today = _todayKst();
                      final DateTime? kept = _routineOnlyStart[client.id];
                      if (kept == null ||
                          (kept.isBefore(today) &&
                              _returnToSchedule?.clientId != client.id)) {
                        _routineOnlyStart[client.id] = today;
                      }
                    } else {
                      _routineOnlyClients.remove(client.id);
                    }
                    _generatedRecommendations[client.id] = <AiRoutineItem>[
                      for (var index = 0; index < exercises.length; index++)
                        AiRoutineItem(
                          id: 'generated-${client.id}-$index',
                          name: exercises[index].name,
                          minutes: exercises[index].minutes,
                          // 위저드에서 시·분·초로 고친 초를 함께 넘긴다(#2521).
                          durationSeconds: exercises[index].durationSeconds,
                          type: exercises[index].type,
                          reason: '',
                          sets: exercises[index].sets,
                          reps: exercises[index].reps,
                          holdSeconds: exercises[index].holdSeconds,
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
                  alignment: AlignmentDirectional.centerStart,
                  child: AppBackLink(
                    key: const ValueKey<String>('return-to-ai-flow'),
                    label: l.aiReturnToWizard,
                    // 위저드로 되돌아가면 거기서 다시 반영할 때까지 개인운동을
                    // 들고 있지 않는다 — 되돌아가 그만두면 앞서 정한 것이
                    // 다음 전송에 조용히 딸려 간다.
                    onPressed: () => setState(() {
                      _aiWizardVisible = true;
                      _personalRoutines.remove(client.id);
                    }),
                  ),
                ),
              )
            else
              // 위저드가 떠 있을 때 이 아래(편집기)는 숨어 있다 — 여기 간격을
              // 두면 위저드 진행 줄과 내용 사이만 벌어진다(#2476). 자리는
              // 지킨다: 빠지면 아래 편집기의 자리가 밀려 State 가 새로 선다.
              const SizedBox.shrink(),
            Offstage(
              offstage:
                  _aiWizardVisible || _routineOnlyClients.contains(client.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ProgramEditorWorkspace(
                    key: ValueKey<String>(
                      'program-editor-${client.id}-$_editorRevision',
                    ),
                    clientGoal: client.goal,
                    aiSuggestions:
                        _generatedRecommendations[client.id] ?? items,
                    template: _appliedTemplate,
                    templateRevision: _templateRevision,
                    onSend: (draft) => unawaited(_sendProgram(client, draft)),
                    onSave: _saveTemplate,
                    saving: _savingTemplate,
                    sending: _sendingClientIds.contains(client.id) || _sent,
                    sent: _sent && !_sendingClientIds.contains(client.id),
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
                  // 편집기는 PT 구성만 다룬다 — 함께 갈 개인운동은 그 **안쪽**
                  // 아래에 붙인다. 바깥 목록에 끼워 넣으면 개인운동이 생기는
                  // 순간 편집기의 자리가 흔들려 그 State 가 새로 만들어지고,
                  // 위저드가 반영한 구성이 사라진다.
                  //
                  // 비어 있어도 선다(#2280) — `직접 만들기`·저장한 프로그램
                  // 적용에서 개인운동을 붙일 자리가 여기다. 보낸 뒤 비워진
                  // 목록에는 붙일 것이 없으니 세우지 않는다.
                  if ((_personalRoutines[client.id]?.isNotEmpty ?? false) ||
                      !_sent) ...<Widget>[
                    const SizedBox(height: OnCareSpacing.s16),
                    PersonalRoutineBox(
                      key: ValueKey<String>(
                        'personal-routine-with-pt-${client.id}',
                      ),
                      routines:
                          _personalRoutines[client.id] ??
                          const <RoutineExercise>[],
                      routineOnly: false,
                      // 없으면 개인운동 단계(AI 제안)에서 짜고, 있으면 부분
                      // 창에서 고친다 — 프로그램과 같다.
                      onEdit: _sent || _sendingClientIds.contains(client.id)
                          ? null
                          : (_personalRoutines[client.id]?.isEmpty ?? true)
                          ? () => _startDraftAttach(client)
                          : () => unawaited(_editPersonalRoutines(client)),
                    ),
                  ],
                ],
              ),
            ),
            // PT 가 없는 주에는 프로그램 박스가 숨고 이 박스만 선다 — 고를
            // PT 도, 붙일 일정도 없다(#2223). 편집기 **뒤에** 둔다: 앞에
            // 끼우면 편집기의 자리가 밀려 그 State 가 새로 만들어지고, 위저드가
            // 반영한 구성이 사라진다.
            Offstage(
              offstage:
                  _aiWizardVisible || !_routineOnlyClients.contains(client.id),
              child: PersonalRoutineBox(
                key: ValueKey<String>('personal-routine-only-${client.id}'),
                routines:
                    _personalRoutines[client.id] ?? const <RoutineExercise>[],
                routineOnly: true,
                startDate: _routineOnlyStart[client.id] ?? _todayKst(),
                onStartDateChanged: _sent
                    ? null
                    : (DateTime date) =>
                          setState(() => _routineOnlyStart[client.id] = date),
                onSend: () => unawaited(_sendRoutineOnly(client)),
                sending: _sendingRoutineOnly.contains(client.id),
                sent: _sent,
                // 시작일에 PT 가 있으면 그 PT 에 붙고, 없으면 바로 보낸다(#2280).
                target: _routineOnlyTargetFor(client.id),
                nearestPt: _nearestRoutineOnlyPt(client.id),
                targetReady: _routineOnlyCandidates.containsKey(client.id),
              ),
            ),
          ],
        ),
      ),
    ];
    final bool attaching = _draftAttachFor == client.id;
    // 편집기의 PT 에 붙일 개인운동을 짜는 동안(#2280)은 위저드·편집기를
    // 숨겨 두고(상태는 그대로) 개인운동 단계만 세운다. 늘 같은 자리에 두어,
    // 흐름을 여닫아도 편집기의 State 가 새로 서지 않게 한다 — 짜던 PT 구성이
    // 사라진다.
    return <Widget>[
      Offstage(
        offstage: attaching,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
      if (attaching)
        AiRoutineOptionsFlow(
          key: ValueKey<String>('routine-attach-${client.id}'),
          client: client,
          embedded: true,
          attachTarget: l.aiAttachTargetPt,
          onAttach: (routines) {
            setState(() {
              _personalRoutines[client.id] = routines;
              _draftAttachFor = null;
            });
            showAppToast(
              context,
              l.schedRoutinesAdded,
              type: AppToastType.success,
            );
          },
          onAttachCancel: () => setState(() => _draftAttachFor = null),
        ),
    ];
  }
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
          AppSectionHeader(title: title, icon: icon, trailing: trailing),
          const SizedBox(height: OnCareSpacing.s12),
          if (expand) Expanded(child: child) else child,
        ],
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
      icon: AppIcons.calendar,
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
              // 이식 전 식단·운동 스트립 모양(옅은 띠 + 흰 엄지)이다(#1024,
              // #1777). 기간 토글은 기본 채움 알약 그대로 둔다.
              child: AppSegmentedToggle<_ClientDataView>(
                key: const ValueKey<String>('program-client-data-tabs'),
                expand: true,
                style: AppSegmentedToggleStyle.thumb,
                selected: _view,
                onChanged: (view) => setState(() => _view = view),
                segments: <AppSegment<_ClientDataView>>[
                  AppSegment<_ClientDataView>(
                    value: _ClientDataView.diet,
                    label: l.clientTabDiet,
                    icon: AppIcons.diet,
                  ),
                  AppSegment<_ClientDataView>(
                    value: _ClientDataView.workout,
                    label: l.clientTabWorkout,
                    icon: AppIcons.exercise,
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
                child: AppSegmentedToggle<ClientPeriod>(
                  key: const ValueKey<String>('client-period-toggle'),
                  segments: clientPeriodSegments(AppLocalizations.of(context)),
                  selected: _period,
                  onChanged: (ClientPeriod p) => setState(() => _period = p),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        // 전환에 애니메이션을 두지 않는다(#1027).
        if (_view == _ClientDataView.diet) ...<Widget>[
          if (_period == ClientPeriod.today)
            ProgramNutritionSummaryCard(
              key: ValueKey<String>('program-diet-${widget.client.id}'),
              client: widget.client,
              // 목표는 회원 프로필에서 읽는다(#2189). 읽는 중·실패면 기본값.
              profile: ref
                  .watch(memberHealthProfileProvider(widget.client.id))
                  .valueOrNull,
            )
          else
            ClientDietPeriodCard(
              // 키에 기간을 넣지 않는다 — 넣으면 주 ↔ 달을 옮길 때마다 카드가
              // 새로 만들어져 고른 지표가 초기화된다.
              key: ValueKey<String>('program-diet-period-${widget.client.id}'),
              clientId: widget.client.id,
              period: _period,
            ),
          // 회원 상세 식단 탭과 같은 `식단 분석` 카드 — 오늘은 추천까지 묻는다.
          // 트레이너는 회원 상세보다 이 탭에 오래 머물러, 추천을 여기서도
          // 답할 수 있어야 회원 앱 `추천 식단` 이 비지 않는다. 넓은 화면에서는
          // 곧 전송 이력 바로 위다.
          ClientDietAnalysisPanel(
            key: ValueKey<String>('program-diet-analysis-${widget.client.id}'),
            client: widget.client,
            period: _period,
            topGap: OnCareSpacing.s12,
          ),
        ] else ...<Widget>[
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
    // 편집할 수 없는 빌드면 만들기·고치기를 내밀지 않는다(#920). 데모도
    // 저장한 템플릿을 로컬 저장소에 남겨 편집할 수 있다(#1028, #2669).
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
        icon: AppIcons.template,
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
                child: _PointerUnfocus(
                  child: AppTile(
                    key: ValueKey<String>('template-card-${template.id}'),
                    // 중립 회색이다. 옅은 네이비로 두면 화면의 다른 네이비
                    // 강조와 섞여 **이미 고른 템플릿처럼** 보인다 — 고르기
                    // 전인데 고른 것으로 읽힌다(#2220).
                    tone: AppTileTone.neutral,
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
                                onEdit: () =>
                                    _edit(context, template: template),
                                onDelete: template.isStarter
                                    ? null
                                    : () => _delete(context, ref, template),
                              )
                            else
                              AppIcon(
                                AppIcons.addCircle,
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
                            formatExerciseDuration(l, template.totalSeconds),
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
              ),
          ],
        );
      },
    );
    return _SectionCard(
      title: l.coachTemplates,
      icon: AppIcons.template,
      expand: fixedBox,
      // 아이콘만 쓴다(#1028) — 좁은 사이드바에서 영어·큰 글자 배율이면
      // "새 템플릿" 글자가 제목과 함께 넘친다.
      trailing: canEdit
          ? AppIconButton(
              key: const ValueKey<String>('template-new'),
              icon: AppIcons.add,
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

/// 마우스로 누른 뒤 남는 포커스 강조를 거둔다. (#2220)
///
/// Flutter 웹에서 누를 수 있는 구획은 클릭으로 포커스를 받고, 포커스 강조는
/// **누른 뒤에도 계속 칠해진다.** 옅은 네이비일 때는 묻혔지만 회색 바탕에서는
/// 또렷해, 방금 누른 템플릿이 **골라 둔 것처럼** 남는다 — 이 이슈가 없애려던
/// 바로 그 오해다.
///
/// 포커스 자체를 막지는 않는다. Tab 으로 옮겨온 포커스는 키보드로 쓰는
/// 사람에게 "지금 여기" 를 알리는 유일한 길잡이라 그대로 둬야 한다. 그래서
/// **포인터로 누른 경우에만** 거둔다.
class _PointerUnfocus extends StatefulWidget {
  const _PointerUnfocus({required this.child});

  final Widget child;

  @override
  State<_PointerUnfocus> createState() => _PointerUnfocusState();
}

class _PointerUnfocusState extends State<_PointerUnfocus> {
  /// 직전 눌림이 포인터에서 왔는가. 키보드로 누른 것과 가르는 값이다.
  bool _fromPointer = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _fromPointer = true,
      // 눌렀다가 손가락을 끌어내 취소하면 눌림이 없던 일이 된다. 표시를
      // 남겨 두면 그다음 **키보드** 누름에서 한 번 잘못 거둔다.
      onPointerCancel: (_) => _fromPointer = false,
      child: Focus(
        onFocusChange: (bool hasFocus) {
          if (!hasFocus || !_fromPointer) return;
          _fromPointer = false;
          // 이 자리에서 곧장 거두면 포커스를 옮기는 도중이라 다시 돌아온다.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) FocusScope.of(context).unfocus();
          });
        },
        child: widget.child,
      ),
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
          icon: AppIcons.edit,
          onSelected: onEdit,
        ),
        // 지울 수 없으면 내린다(#2220). 회색으로 남겨 "못 하는 동작" 을
        // 알리려 했지만, `AppMenu` 는 위험 항목 글자색을 모든 상태에 같은
        // 빨강으로 줘 **비활성이 비활성으로 보이지 않는다** — 멀쩡한 빨간
        // `삭제` 를 눌러 보고 아무 일도 없는 것을 겪게 된다.
        //
        // 기본 템플릿은 저장된 행이 아니라 읽을 때 만들어지는 값이라 지울
        // 것이 없고, 자기 템플릿을 하나라도 저장하면 저절로 사라진다. 할 수
        // 없는 일을 굳이 내밀 이유가 없다.
        if (onDelete case final VoidCallback delete)
          AppMenuItem(
            label: l.coachTemplateDelete,
            icon: AppIcons.delete,
            destructive: true,
            onSelected: delete,
          ),
      ],
      triggerBuilder: (context, toggle) => AppIconButton(
        key: ValueKey<String>('template-menu-${template.id}'),
        icon: AppIcons.more,
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
/// from [_latestDeliveryProvider] (직전 전송 한 묶음, #2225) — 전송 성공
/// 분기가 이 provider 를 무효화해야 카드가 곧바로 바뀐다(#2750).
class _SendHistoryCard extends ConsumerWidget {
  const _SendHistoryCard({required this.client});

  final TrainerClient client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final latest = ref.watch(_latestDeliveryProvider(client.id));
    return _SectionCard(
      title: l.coachSentHistory,
      icon: AppIcons.history,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 아직 보내지 않은 것이 있으면 맨 위에서 알린다(#2225) — 지금은 그
          // 사실이 스케줄 탭의 그 일정을 열어야만 보인다. 보내는 일 자체는
          // 여기서 하지 않는다. 무엇을 보내는지는 일정 상세에서 고치고 확인한
          // 뒤에 보내야 하고, 그 화면이 이미 그 일을 맡고 있다(#2224).
          _UnsentRoutinesNotice(client: client),
          latest.when(
            loading: () => const AppLoading(placement: AppStatePlacement.card),
            error: (_, _) => AppErrorState(
              title: l.coachHistoryFailed,
              retryLabel: l.actionRetry,
              onRetry: () => ref.invalidate(_latestDeliveryProvider(client.id)),
              placement: AppStatePlacement.card,
            ),
            data: (delivery) => delivery == null
                ? AppEmptyState(
                    title: l.coachHistoryEmpty,
                    icon: AppIcons.sent,
                    placement: AppStatePlacement.card,
                  )
                : _LastDeliveryBox(delivery: delivery),
          ),
        ],
      ),
    );
  }
}

/// 끝난 PT 에 남아 있는 개인운동 — 보낼 수 있는데 아직 안 보낸 것. (#2225)
///
/// 위젯이 아니라 provider 가 들고 있다. 보낸 뒤 이 자리를 다시 읽어야 하는데,
/// 위젯이 제 상태에 들고 있으면 그 사이 다시 그려져 상태가 버려질 때 읽기가
/// 조용히 사라진다 — 보냈는데 알림이 그대로 남는다.
final _unsentRoutinesProvider = FutureProvider.autoDispose
    .family<List<UnsentRoutine>, String>(
      (ref, clientId) => ref
          .watch(scheduleRepositoryProvider)
          .fetchUnsentRoutinesFor(clientId),
    );

/// 가장 최근에 보낸 것 한 묶음. (#2225)
final _latestDeliveryProvider = FutureProvider.autoDispose
    .family<SentDelivery?, String>(
      (ref, clientId) => ref
          .watch(trainerRoutineRepositoryProvider)
          .fetchLatestDelivery(clientId),
    );

/// 아직 보내지 않은 개인운동이 있다고 알리고, 그 일정으로 데려다준다. (#2225)
///
/// 붙여만 둔 개인운동은 그 PT 를 완료하고 보낼 때 함께 간다(#2224). 그 사실이
/// 스케줄 탭의 그 일정을 열어야만 보여, 프로그램 탭만 보는 트레이너는 보낼
/// 것이 남은 줄 몰랐다.
///
/// **여기서 보내지는 않는다.** 무엇을 보내는지 고치고 확인한 뒤에 보내야 하고,
/// 그 일은 일정 상세가 이미 맡고 있다. 여기서 바로 보내면 트레이너는 무엇이
/// 나갔는지 못 본 채 보내게 된다.
class _UnsentRoutinesNotice extends ConsumerWidget {
  const _UnsentRoutinesNotice({required this.client});

  final TrainerClient client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows =
        ref.watch(_unsentRoutinesProvider(client.id)).valueOrNull ??
        const <UnsentRoutine>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final tokens = context.oncare;
    // 여러 일정에 남아 있으면 가장 오래된 것부터 — 오래 묵은 것이 먼저
    // 잊히고, 트레이너가 찾아야 할 것도 그쪽이다.
    final target = rows.reduce(
      (a, b) => a.scheduleDate.compareTo(b.scheduleDate) <= 0 ? a : b,
    );
    return Padding(
      key: const ValueKey<String>('coach-unsent-routines'),
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s12),
      child: Container(
        padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
        decoration: const BoxDecoration(
          color: OnCareColors.surfaceInput,
          borderRadius: OnCareRadius.mdAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l.coachUnsentRoutines(rows.length),
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                  .copyWith(color: OnCareColors.textPrimary),
            ),
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              l.coachUnsentRoutinesBody,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
            const SizedBox(height: OnCareSpacing.s8),
            AppButton(
              key: const ValueKey<String>('coach-open-unsent-schedule'),
              label: l.coachSendUnsentRoutines,
              leadingIcon: AppIcons.calendar,
              variant: AppButtonVariant.secondary,
              size: OnCareButtonSize.small,
              shrinkLabel: true,
              onPressed: () => context.go(
                AppRoutes.scheduleAt(
                  // 날짜가 비면 그 주를 못 찾는다. 옛 응답이 그럴 수 있어
                  // 빈 값은 실어 보내지 않는다 — 일정 id 만으로도 이번 주
                  // 안이면 열린다.
                  date: target.scheduleDate.isEmpty
                      ? null
                      : target.scheduleDate,
                  sessionId: target.scheduleId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 직전 전송 한 묶음 — 언제 보냈는지, 프로그램과 개인운동으로 갈라서. (#2225)
///
/// 전송 이력은 **직전 한 번만** 보여 준다. 여러 번을 나열하면 트레이너가
/// 찾는 것("방금 무엇이 나갔나")이 목록에 묻힌다. PT 와 그때 함께 간
/// 개인운동이 한 번의 전송이었다는 사실도 여기서만 드러난다(#2224).
class _LastDeliveryBox extends StatelessWidget {
  const _LastDeliveryBox({required this.delivery});

  final SentDelivery delivery;

  String _kindLabel(AppLocalizations l, String kind) => switch (kind) {
    DeliveryKinds.ptWithRoutine => l.coachDeliveryPtWithRoutine,
    DeliveryKinds.cancelledRoutineOnly => l.coachDeliveryCancelledRoutineOnly,
    _ => l.coachDeliveryRoutineOnly,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.oncare;
    // 짜 둔 프로그램이 아니라 **간 프로그램**이다. PT 를 취소하면 프로그램은
    // 나가지 않으므로 여기도 비어야 한다 — 아니면 스케줄 탭은 안 갔다고 하고
    // 전송 이력은 갔다고 하는 두 말이 선다.
    final program = delivery.program;
    // 전송 이력 카드 위에 그대로 적는다. 상자 안에 또 상자를 두면 이 카드가
    // 무엇을 말하는 카드인지 흐려진다.
    return Column(
      key: const ValueKey<String>('coach-last-delivery'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            AppTag(label: _kindLabel(l, delivery.kind), tone: AppTagTone.brand),
            const SizedBox(width: OnCareSpacing.s8),
            Expanded(
              child: Text(
                delivery.sentOn == null
                    ? l.coachLastDelivery
                    : l.coachDeliveryOn(ymd(delivery.sentOn!)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ),
          ],
        ),
        // 이름만으로는 무엇을 보냈는지 알 수 없다 — 몇 세트 몇 회 몇 kg 로
        // 보냈는지 보려고 다시 일정을 열어야 했다. 일정 상세와 **같은
        // 표기**를 쓴다(#2225).
        _DeliverySection(
          title: l.coachDeliveryProgramSection,
          lines: <String>[
            for (final item in program)
              switch (programItemAmount(l, item)) {
                '' => item.name,
                final String amount => '${item.name} · $amount',
              },
          ],
        ),
        _DeliverySection(
          title: l.coachDeliveryRoutineSection,
          lines: <String>[
            for (final r in delivery.routines) assignedRoutineLabel(l, r),
          ],
        ),
      ],
    );
  }
}

/// 직전 전송의 한 갈래 — 프로그램이든 개인운동이든 같은 모양으로 적는다.
///
/// 비어 있어도 자리를 남긴다. 한 갈래가 통째로 사라지면 트레이너는 그것이
/// **안 간 것인지 원래 없는 것인지** 알 수 없다.
class _DeliverySection extends StatelessWidget {
  const _DeliverySection({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = context.oncare;
    return Padding(
      key: ValueKey<String>('coach-delivery-section-$title'),
      padding: const EdgeInsets.only(top: OnCareSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.textSecondary),
          ),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: OnCareSpacing.s4),
              child: Text(
                l.coachDeliveryNothing,
                style: tokens
                    .text(OnCareTypography.bodySmall)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            )
          else
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: OnCareSpacing.s4),
                child: Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
        ],
      ),
    );
  }
}
