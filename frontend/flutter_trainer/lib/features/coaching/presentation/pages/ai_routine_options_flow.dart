import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/utils/korean_josa_l10n.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/data/routine_context_source_store.dart';
import 'package:oncare_trainer/features/coaching/domain/coaching_workspace_draft.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_context_source.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';
import 'package:oncare_trainer/features/coaching/domain/program_direction.dart';
import 'package:oncare_trainer/features/coaching/domain/routine_effects.dart';
import 'package:oncare_trainer/features/coaching/domain/routine_generate_limits.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_duration.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_trainer/shared/utils/exercise_weight_label.dart';
import 'package:oncare_trainer/shared/utils/health_focus_labels.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이번에 짜는 프로그램이 어떤 것인가. (#2223)
///
/// **트레이너가 고르는 값이 아니다** — 조건 설정에서 `개인운동만 짜기`
/// 로 PT 프로그램 짜기를 건너뛰면 [routineOnly] 가 된다. 시작할 때 종류부터
/// 묻지 않는 것은, 대부분의 주가 PT 가 있는 주라 그 물음이 늘 같은 답을 받는
/// 절차가 되기 때문이다. 건너뛴 결과가 단계 수(4 / 3)를 정한다.
enum ProgramKind {
  /// PT 프로그램 + 그 PT 에 붙는 개인운동.
  ptWithRoutine,

  /// 개인운동만 — 이번엔 PT 가 없다.
  routineOnly,
}

/// 위저드의 한 단계. 종류마다 놓이는 자리와 개수가 다르므로, 화면은 번호가
/// 아니라 이 값으로 무엇을 그릴지 정한다. (#2223)
enum _Step {
  /// 조건 설정.
  conditions,

  /// PT 프로그램 선택(개인운동만 모드에는 없다).
  program,

  /// 개인운동 짜기.
  personal,

  /// 프로그램 검토 — 확정 전 마지막 확인이다. 그 뒤에도 개인운동 단계와
  /// 편집기의 `일정 추가` 가 남아 있어 "최종" 이라 부르지 않는다. (#2372)
  review,
}

/// Conversation-style AI routine builder.
///
/// The assistant stays inside the AI routine tab when [embedded] is true.
/// After generation, plans A/B/C are presented in a horizontal rail; selecting
/// a card updates the common editor below it. C is the next PT program in the
/// member's recent rotation, adjusted to the latest analysis (#3282).
class AiRoutineOptionsFlow extends ConsumerStatefulWidget {
  const AiRoutineOptionsFlow({
    required this.client,
    this.embedded = false,
    this.onReviewCompleted,
    this.onManualCreate,
    this.onGenerated,
    this.onStepNav,
    this.attachTarget,
    this.onAttach,
    this.onAttachCancel,
    this.startRoutineOnly = false,
    this.initialSnapshot,
    this.onSnapshot,
    super.key,
  });

  final TrainerClient client;
  final bool embedded;

  /// 위저드를 빠져나가는 유일한 출구 — 확정한 PT 구성과 그 PT 에 붙일
  /// 개인운동을 함께 넘긴다(#2223). `개인운동만` 모드는 위저드가 직접 보내므로
  /// 이 콜백을 부르지 않는다.
  final void Function(
    List<RoutineExercise> program,
    List<RoutineExercise> personalRoutines,
    ProgramKind kind,
  )?
  onReviewCompleted;

  /// AI 단계를 종료하고 빈 프로그램 편집기로 전환한다.
  final VoidCallback? onManualCreate;

  /// 후보를 받았다 — 바깥 화면이 "보내지 않은 작성 내용" 으로 센다(#2873).
  /// 다시 그리게 하지 않는 가벼운 알림이다.
  final VoidCallback? onGenerated;

  /// [embedded] 일 때 단계 진행 줄(`이전` · 다음 단계 버튼)을 바깥에 넘긴다.
  ///
  /// 이 화면을 담은 바깥 열이 자기 스크롤 **아래**에 그려 고정한다 — 리포트
  /// 편집기 단계 하단과 같은 자리다(#2476). [owner] 는 넘긴 화면이고, 화면이
  /// 사라질 때 `nav: null` 로 한 번 더 불러 거두게 한다. 비우면 진행 줄은
  /// 내용 끝에 붙는다.
  final void Function(Object owner, Widget? nav)? onStepNav;

  /// 편집기에서 짜고 있는 PT 에 **개인운동만 붙이는** 흐름이면 그 PT 를 한 줄로
  /// 적은 값. (#2280)
  ///
  /// `직접 만들기`·저장한 프로그램 적용으로 짠 PT 는 개인운동 단계를 지나지
  /// 않는다. 이 값을 주면 위저드가 개인운동 단계로 열린다 — PT 구성은 이미
  /// 편집기에 있으니 프로그램 선택·검토는 건너뛴다. AI 제안은 여느 때처럼
  /// 채워진다: 개인운동을 빈 줄에서 짜게 두면 그 제안을 못 본다.
  final String? attachTarget;

  /// [attachTarget] 흐름의 출구 — 정한 개인운동을 넘긴다.
  final ValueChanged<List<RoutineExercise>>? onAttach;

  /// [attachTarget] 흐름을 그만둔다.
  final VoidCallback? onAttachCancel;

  /// `개인운동만 짜기` 를 고른 채로 연다. (#2280)
  ///
  /// 스케줄의 `개인운동 추가` 에서 왔다 — 그 PT 에 붙일 개인운동을 짜러 왔으니
  /// 조건 설정에서 같은 버튼을 한 번 더 누르게 하지 않는다. 시작일이 그 PT
  /// 날로 잡혀 있어, 반영한 뒤 개인운동 박스가 그 PT 에 붙인다.
  final bool startRoutineOnly;

  /// 자동 보관해 둔 작성 상태로 연다 — 새로 고침 뒤 `이어서 쓰기`(#2873).
  ///
  /// 같은 단계·같은 후보·같은 입력으로 선다. 후보를 다시 만들지 않는다.
  /// 붙이기 흐름([attachTarget])에서는 쓰지 않는다.
  final AiRoutineWizardSnapshot? initialSnapshot;

  /// 작성 상태가 바뀌었다 — 바깥 화면이 자동 보관에 싣는다(#2873).
  ///
  /// 그리는 도중에도 불리므로, 받는 쪽은 다시 그리게 하지 말고 값만 적어 둔다
  /// ([onGenerated] 와 같다).
  final ValueChanged<AiRoutineWizardSnapshot>? onSnapshot;

  bool get _attachMode => attachTarget != null;

  @override
  ConsumerState<AiRoutineOptionsFlow> createState() =>
      _AiRoutineOptionsFlowState();
}

class _AiRoutineOptionsFlowState extends ConsumerState<AiRoutineOptionsFlow> {
  /// 조건 설정 단계의 자연어 요청. 그대로 `trainer_note` 로 나간다 (#1028).
  ///
  /// 고객에게 함께 보낼 메모([_trainerMemo])와 **다른 칸**이다 — 하나로 묶여
  /// 있던 동안에는 "하체 부담 적은 40분으로 만들어줘" 같은 AI 지시문이 그대로
  /// 회원이 읽는 루틴 사유로 나갔다.
  final TextEditingController _prompt = TextEditingController();
  final TextEditingController _trainerMemo = TextEditingController();
  final TextEditingController _newExerciseName = TextEditingController();

  /// 이 화면의 맨 위(진행 단계 표시줄) 를 가리킨다 — [_scrollToTop] 이 이
  /// 위젯을 뷰포트 위쪽으로 끌어올릴 때 기준으로 쓴다.
  final GlobalKey _topKey = GlobalKey();

  /// 마지막으로 [AiRoutineOptionsFlow.onStepNav] 에 넘긴 진행 줄.
  Widget? _publishedNav;

  /// `RoutineOptionsRequest.trainer_note` 의 서버 상한(#1028). 여기서 막으면
  /// 긴 요청이 422 왕복 없이 그 자리에서 잘린다.
  static const int _promptMaxLength = 500;

  /// AI 가 참고할 자료(#2587). 트레이너가 고른 적이 없으면 기본값이고, 고른
  /// 값은 브라우저에 계정별로 남아 다음에 위저드를 열 때 그대로 돌아온다.
  Set<RoutineContextSource> _sources = RoutineContextSource.defaults;

  @override
  void initState() {
    super.initState();
    final RoutineContextSourceStore? store = _sourceStore();
    if (store != null) _sources = store.read(_sourceAccount());
    // 글자를 칠 때는 이 화면이 다시 그려지지 않는다 — 요청·메모 칸의 변경도
    // 자동 보관에 실리게 따로 듣는다(#2873).
    _prompt.addListener(_emitSnapshot);
    _trainerMemo.addListener(_emitSnapshot);
    final AiRoutineWizardSnapshot? saved = widget.initialSnapshot;
    if (saved != null && !widget._attachMode) {
      _restoreSnapshot(saved);
      return;
    }
    // 붙이기 흐름은 개인운동 단계에서 바로 시작한다(#2280). 제안이 아직
    // 오지 않았으면 개인운동 칸이 그릴 때 채운다.
    if (widget._attachMode || widget.startRoutineOnly) {
      if (widget.startRoutineOnly) _kind = ProgramKind.routineOnly;
      _stage = _steps.indexOf(_Step.personal);
      _maxReachedStage = _stage;
      _seedPersonalFromSuggestions();
      // 좁은 화면에서는 위저드가 회원 데이터 카드 아래에 선다 — 열리자마자
      // 보이게 끌어올린다.
      _scrollToTop();
    }
  }

  /// 자동 보관해 둔 작성 상태를 그대로 놓는다(#2873). 상태만 바꾼다 —
  /// `initState` 에서 부른다.
  void _restoreSnapshot(AiRoutineWizardSnapshot saved) {
    _kind = saved.routineOnly
        ? ProgramKind.routineOnly
        : ProgramKind.ptWithRoutine;
    _stage = saved.stage.clamp(0, _steps.length - 1);
    _maxReachedStage = saved.maxReachedStage.clamp(_stage, _steps.length - 1);
    _options = saved.options;
    _selectedKey = saved.selectedKey;
    _edited = List<RoutineExercise>.of(saved.edited);
    _measureChosen.addAll(saved.measureChosen);
    _personal = List<RoutineExercise>.of(saved.personal);
    _personalMeasureChosen.addAll(saved.personalMeasureChosen);
    _personalSeeded = saved.personalSeeded;
    // 줄마다 채운 AI 제안 id 가 따라온다 — 근거 표시·거절이 다시 그 제안을
    // 가리킨다.
    _personalOrigins
      ..clear()
      ..addAll(<_PersonalOrigin?>[
        for (final RoutineExercise e in _personal)
          if (e.suggestionId case final String id when id.isNotEmpty)
            _PersonalOrigin(id: id)
          else
            null,
      ]);
    _prompt.text = saved.prompt;
    _trainerMemo.text = saved.trainerMemo;
    _minutes = saved.minutes;
    _intensity = saved.intensity;
    _minutesTouched = saved.minutesTouched;
    _intensityTouched = saved.intensityTouched;
  }

  /// 지금 작성 상태(#2873).
  AiRoutineWizardSnapshot _snapshot() => AiRoutineWizardSnapshot(
    stage: _stage,
    maxReachedStage: _maxReachedStage,
    routineOnly: _kind == ProgramKind.routineOnly,
    selectedKey: _selectedKey,
    edited: List<RoutineExercise>.unmodifiable(_edited),
    personal: List<RoutineExercise>.unmodifiable(_personal),
    personalSeeded: _personalSeeded,
    options: _options,
    prompt: _prompt.text,
    trainerMemo: _trainerMemo.text,
    minutes: _minutes,
    intensity: _intensity,
    minutesTouched: _minutesTouched,
    intensityTouched: _intensityTouched,
    measureChosen: Set<int>.unmodifiable(_measureChosen),
    personalMeasureChosen: Set<int>.unmodifiable(_personalMeasureChosen),
  );

  /// 바깥에 작성 상태를 알린다. 붙이기 흐름은 편집기의 PT 에 딸린 짧은 단계라
  /// 따로 보관하지 않는다.
  void _emitSnapshot() {
    if (!mounted || widget._attachMode) return;
    widget.onSnapshot?.call(_snapshot());
  }

  /// 선택을 남길 저장소. 브라우저 저장소를 못 읽는 자리(저장소를 붙이지 않은
  /// 위젯 테스트 등)에서는 `null` 이다 — 기억만 못 할 뿐 선택과 생성은 된다.
  RoutineContextSourceStore? _sourceStore() {
    try {
      return ref.read(routineContextSourceStoreProvider);
    } on Object {
      return null;
    }
  }

  /// 저장 키의 계정. 데모에는 계정이 없어 `demo` 로 모은다.
  String _sourceAccount() => ref.read(accountEmailProvider) ?? 'demo';

  void _toggleSource(RoutineContextSource source, bool on) {
    final Set<RoutineContextSource> next = <RoutineContextSource>{..._sources};
    on ? next.add(source) : next.remove(source);
    setState(() => _sources = next);
    // 저장이 실패해도 이번 생성에는 화면의 선택이 그대로 쓰인다.
    unawaited(_sourceStore()?.write(_sourceAccount(), next));
  }

  int _minutes = 30;
  String _intensity = 'moderate';
  String _newExerciseType = '근력';
  int _newExerciseSeconds = 30 * 60;
  // 근력만 세트·횟수·중량을 받는다(#1029, #1310) — 그 외 유형은
  // [_newExerciseSeconds] 를 그대로 쓴다.
  int _newExerciseSets = 3;
  int _newExerciseReps = 10;
  int _newExerciseHoldSeconds = 60;

  /// 새 운동 줄을 초로 재는가 — 위 목록의 항목과 같은 규칙이다. (#1969)
  bool _newExerciseIsHold = false;

  /// 트레이너가 새 운동 줄의 회↔초를 직접 골랐는가.
  bool _newExerciseMeasureChosen = false;
  double _newExerciseWeight = 20;

  /// Whether the trainer has touched minutes/intensity directly (#776),
  /// tracked separately — touching one must not silently pin the other to
  /// its stale display value. Until touched, [_minutes]/[_intensity] only
  /// hold pre-fill display values and generation sends no explicit condition
  /// for that field — the server derives it from history (or a fixed
  /// default) instead. Once touched, whatever the trainer set always wins.
  bool _minutesTouched = false;
  bool _intensityTouched = false;

  bool _generating = false;
  bool _showAddExercise = false;
  RoutineOptions? _options;
  int _stage = 0;
  int _maxReachedStage = 0;
  String _selectedKey = 'A';
  List<RoutineExercise> _edited = <RoutineExercise>[];

  /// 트레이너가 회↔초를 직접 고른 항목의 자리. 고른 뒤에는 이름이 바뀌어도
  /// 종목표가 그 선택을 덮지 않는다 — 종목표는 기본값일 뿐이다. (#1969)
  final Set<int> _measureChosen = <int>{};

  /// 이번 프로그램의 종류 — 첫 단계 맨 위에서 고른다. (#2223)
  ProgramKind _kind = ProgramKind.ptWithRoutine;

  /// 이 PT 사이에(또는 PT 없이 한 주 동안) 회원이 혼자 할 개인운동.
  ///
  /// 프로그램 후보([_edited])와 **다른 목록**이다 — 개인운동은 PT 구성을 고르는
  /// 일과 엮이지 않는 별개의 단계이고, 저장도 따로 된다.
  List<RoutineExercise> _personal = <RoutineExercise>[];

  /// 개인운동 목록에서 회↔초를 직접 고른 자리. [_measureChosen] 과 나눠 둔다 —
  /// 두 목록의 같은 번째 줄이 서로의 선택을 물려받으면 안 된다.
  final Set<int> _personalMeasureChosen = <int>{};

  /// AI 제안을 개인운동 목록에 한 번 채웠는가. 다시 채우면 트레이너가 지운
  /// 제안이 되살아난다.
  bool _personalSeeded = false;

  /// 지금 펼쳐서 고치고 있는 개인운동 줄. 없으면 null. (#2223)
  ///
  /// 목록은 기본적으로 **읽는 자리**다 — 줄마다 편집 칸을 펼쳐 두면 무엇을
  /// 추천받았는지 한눈에 훑을 수가 없다. 한 번에 하나만 연다: 여러 줄을
  /// 동시에 펼치면 다시 긴 폼 더미가 된다.
  int? _editingPersonal;

  /// 개인운동 줄이 어느 AI 제안에서 왔나 — 줄 번호 → 제안 id·근거.
  ///
  /// [RoutineExercise] 는 프로그램 후보와 함께 쓰는 값이라 제안 id 나 근거를
  /// 담지 않는다. 그 둘은 이 화면에서만 필요하므로(근거 표시·거절 호출) 목록
  /// 옆에 따로 들고 있는다. 줄을 지우면 뒤 번호가 당겨지므로 함께 옮긴다.
  final List<_PersonalOrigin?> _personalOrigins = <_PersonalOrigin?>[];

  /// 단계 표시줄의 칸들. **어느 모드든 언제나 이 넷이다** — 흐름이 줄어드는
  /// 것처럼 보이지 않게, 밟지 않는 칸도 자리를 지키고 `건너뜀` 으로 남는다.
  /// (#2223)
  static const List<_Step> _steps = <_Step>[
    _Step.conditions,
    _Step.program,
    _Step.review,
    _Step.personal,
  ];

  /// 이번 흐름에서 밟지 않는 칸. `개인운동만` 은 고를 PT 프로그램도, 검토할
  /// PT 프로그램도 없으므로 가운데 둘을 지나친다 — 그래서 마지막 칸(개인운동)이
  /// 짜는 자리이자 보내는 자리가 된다.
  ///
  /// 이미 있는 PT 에 붙이는 흐름(#2280)도 같은 두 칸을 지나친다 — PT 구성은
  /// 이미 있다. 모양은 `개인운동만` 과 같지만 끝에서 그 PT 에 붙는다.
  Set<_Step> get _skipped =>
      _kind == ProgramKind.routineOnly || widget._attachMode
      ? const <_Step>{_Step.program, _Step.review}
      : const <_Step>{};

  _Step get _currentStep => _steps[_stage];

  /// [from] 다음으로 실제로 밟을 칸의 번호. 건너뛰는 칸은 지나친다.
  int _nextStageAfter(int from) {
    var next = from + 1;
    while (next < _steps.length && _skipped.contains(_steps[next])) {
      next += 1;
    }
    return next;
  }

  /// 지금 단계가 편집하는 목록. 운동 줄 편집기와 추가 폼이 이 하나를 본다 —
  /// 단계마다 같은 편집기를 쓰되 대상만 다르다.
  List<RoutineExercise> get _activeList =>
      _currentStep == _Step.personal ? _personal : _edited;

  /// 위 목록의 위젯 키 앞자리. 두 목록의 줄이 같은 키를 쓰면 한쪽을 고칠 때
  /// 다른 쪽의 입력 상태가 딸려 온다.
  String get _activeKeyPrefix =>
      _currentStep == _Step.personal ? 'personal' : _selectedKey;

  Set<int> get _activeMeasureChosen =>
      _currentStep == _Step.personal ? _personalMeasureChosen : _measureChosen;

  @override
  void dispose() {
    // 회원을 바꾸거나 위저드를 새로 열면 이 화면이 사라진다. 바깥에 남긴 진행
    // 줄은 사라진 화면을 부르므로 거두게 한다 — 새 화면이 이미 제 줄을
    // 넘겼는지는 [owner] 로 바깥이 가린다.
    final onStepNav = widget.onStepNav;
    if (onStepNav != null && _publishedNav != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => onStepNav(this, null),
      );
    }
    _prompt.dispose();
    _trainerMemo.dispose();
    _newExerciseName.dispose();
    super.dispose();
  }

  /// 역할 글자에 색을 입힌다.
  TextStyle _text(TextStyle role, Color color) =>
      context.oncare.text(role).copyWith(color: color);

  String _analysisSuggestion(AppLocalizations l) {
    final client = widget.client;
    final sodium = client.sodiumOverBudget
        ? l.aiReasonSodium
        : l.aiReasonBalanced;
    // 보낸 적이 없으면 예전처럼 저장된 `-` 를 그대로 둔다.
    final last = lastRoutineLabel(l, client);
    // 목표는 저장 값(한국어)이 아니라 화면 언어로 적는다(#2467).
    final goal = healthFocusGoalLabel(l, client.goal);
    return '${l.aiReasonGoal(goal, last.isEmpty ? client.lastRoutine : last)} '
        '$sodium';
  }

  List<_RoutineChoice> _choicesOf(AppLocalizations l) {
    final options = _options;
    if (options == null) return const <_RoutineChoice>[];
    return <_RoutineChoice>[
      _RoutineChoice.fromPlan(options.planA),
      _RoutineChoice.fromPlan(options.planB),
      // C안 — 지난 PT 흐름상 이번 차례(#3282). 예전 세 번째 카드(`기존 AI
      // 추천`)는 배정된 **개인운동**이라 PT 프로그램 단계에 맞지 않았고, 생성
      // 조건도 거치지 않았다. 개인운동은 개인운동 단계에서만 다룬다.
      if (options.planC case final RoutinePlan c) _RoutineChoice.fromPlan(c),
    ];
  }

  String _optionDisplayName(AppLocalizations l, String key) => switch (key) {
    'A' => l.aiOptionRecovery,
    'B' => l.aiOptionPush,
    _ => l.aiOptionNext,
  };

  Future<void> _generate() async {
    if (_generating) return;
    // 칸이 범위 밖 값을 받지 않지만, 범위 밖 요청은 서버가 422 로 거절하므로
    // 보내기 전에 한 번 더 막는다(#2871).
    if (_minutesTouched && !isRoutineGenerateMinutesInRange(_minutes)) {
      _showGenerateRangeError();
      return;
    }
    setState(() => _generating = true);
    try {
      final options = await ref
          .read(trainerRoutineOptionsRepositoryProvider)
          .generate(
            widget.client.id,
            availableMinutes: _minutesTouched ? _minutes : null,
            intensityPreference: _intensityTouched ? _intensity : null,
            // 자연어 요청은 백엔드가 실제로 읽는 유일한 자유 텍스트 필드로
            // 나간다 — 새 필드를 지어내지 않는다(#1028).
            trainerNote: _prompt.text.trim(),
            // 고른 자료만 AI 와 규칙 폴백에 들어간다(#2587). 모두 끈 선택도
            // 빈 목록으로 보낸다 — 서버 기본값으로 되돌리지 않는다.
            sources: _sources,
          );
      if (!mounted) return;
      final analysis = options.analysis;
      setState(() {
        _options = options;
        _selectedKey = 'A';
        _edited = options.planA.exercises.map(_withStrengthDefaults).toList();
        _showAddExercise = false;
        // 후보를 만들었다는 것은 곧 **PT 프로그램을 짜겠다**는 뜻이다. 앞서
        // `개인운동만 짜기` 로 건너뛰었다가 조건 설정으로 되돌아와
        // 생성한 경우라도 여기서 되돌린다 — 그러지 않으면 `건너뜀` 으로 그린
        // 칸에 선 채 프로그램을 고르게 되고, 마지막 버튼이 `회원에게 보내기`
        // 라 방금 고른 PT 구성이 조용히 버려진다.
        _kind = ProgramKind.ptWithRoutine;
        _stage = _nextStageAfter(0);
        _maxReachedStage = _stage;
        // 트레이너가 아직 건드리지 않은 조건만 서버가 실제로 쓴 값(또는
        // 기본값)으로 채운다 — 트레이너가 시간만 고쳤다면 강도는 그대로
        // 서버가 계산하도록 둬야 하고, 그 반대도 마찬가지다(#776).
        if (!_minutesTouched) {
          // 칸이 받는 범위로 당겨 채운다 — 범위 밖 값이 다음 요청에 실리면
          // 서버가 거절한다(#2871).
          _minutes = clampRoutineGenerateMinutes(
            analysis.suggestedAvailableMinutes ?? _minutes,
          );
        }
        if (!_intensityTouched) {
          _intensity = analysis.suggestedIntensity ?? _intensity;
        }
      });
      widget.onGenerated?.call();
      _scrollToTop();
    } catch (e) {
      if (!mounted) return;
      final AppLocalizations l = AppLocalizations.of(context);
      // 서버가 입력을 거절했다(422) — 같은 값으로 다시 눌러도 결과가 같으니
      // 일시 장애처럼 안내하지 않고 조건을 고치게 한다. 서버 상세는 그대로
      // 내보이지 않는다(#2871).
      if (e is ValidationError) {
        _showGenerateRangeError();
        return;
      }
      // 한도 초과는 고장이 아니라 잠시 뒤 되는 상태다. 다른 오류와 같은 문구를
      // 쓰면 트레이너가 기능이 깨진 것으로 읽는다(#582). 하루 상한은 "잠시 후"
      // 가 아니라 내일이라 문구를 따로 둔다(#3032).
      showAppToast(
        context,
        switch (e) {
          RateLimitedError(isDailyLimit: true) => l.aiGenerateDailyLimit,
          RateLimitedError() => l.aiGenerateRateLimited,
          _ => l.aiGenerateFailed,
        },
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 생성 조건이 서버 범위를 벗어났다는 안내(#2871).
  void _showGenerateRangeError() {
    final AppLocalizations l = AppLocalizations.of(context);
    showAppToast(
      context,
      l.aiGenerateInvalidConditions(
        kRoutineGenerateMinMinutes,
        kRoutineGenerateMaxMinutes,
      ),
      type: AppToastType.error,
    );
  }

  void _selectChoice(_RoutineChoice choice) {
    setState(() {
      _selectedKey = choice.key;
      _edited = choice.exercises.map(_withStrengthDefaults).toList();
      _showAddExercise = false;
    });
  }

  void _addExercise() {
    final name = _newExerciseName.text.trim();
    if (name.isEmpty) {
      final AppLocalizations l = AppLocalizations.of(context);
      showAppToast(context, l.aiExerciseNameRequired);
      return;
    }
    final isStrength = _newExerciseType == '근력';
    setState(() {
      _activeList.add(
        RoutineExercise(
          name: name,
          minutes: minutesFromSeconds(_newExerciseSeconds),
          type: _newExerciseType,
          // 시·분·초로 적은 시간을 그대로 싣는다(#2221).
          durationSeconds: isStrength ? null : _newExerciseSeconds,
          sets: isStrength ? _newExerciseSets : 0,
          // 한 세트는 회로든 초로든 한 번만 잰다 — 고르지 않은 쪽은 0 이다.
          // (#1969)
          reps: isStrength && !_newExerciseIsHold ? _newExerciseReps : 0,
          holdSeconds: isStrength && _newExerciseIsHold
              ? _newExerciseHoldSeconds
              : 0,
          isHold: isStrength && _newExerciseIsHold,
          weight: isStrength ? _newExerciseWeight : 0,
        ),
      );
      // 직접 넣은 줄의 출처는 트레이너다 — AI 제안을 그대로 둔 줄과 구분해
      // 보낸다(#2223).
      _newExerciseName.clear();
      _newExerciseType = '근력';
      _newExerciseSeconds = 30 * 60;
      _newExerciseSets = 3;
      _newExerciseReps = 10;
      _newExerciseHoldSeconds = 60;
      _newExerciseIsHold = false;
      _newExerciseMeasureChosen = false;
      _newExerciseWeight = 20;
      _showAddExercise = false;
      // 직접 넣은 줄은 제안에서 온 것이 아니다 — 자리만 맞춰 비워 둔다.
      if (_currentStep == _Step.personal) {
        _personalOrigins.add(null);
        // 방금 폼에서 다 정하고 넣은 줄이라 접힌 채로 둔다.
        _editingPersonal = null;
      }
    });
  }

  /// 한 단계 앞으로 — 건너뛰는 칸은 지나친다. 되돌아온 뒤 다시 나아갈 때도
  /// 같은 자리를 쓴다.
  void _advance() {
    setState(() {
      _stage = _nextStageAfter(_stage);
      if (_stage > _maxReachedStage) _maxReachedStage = _stage;
      _showAddExercise = false;
    });
    _scrollToTop();
  }

  /// 지금 단계의 `다음` 이 하는 일. 단계마다 조건과 동작이 다르다. (#2223)
  ///
  /// 개인운동 단계는 **최소 한 개**를 정해야 넘어간다 — PT 프로그램만 보내고
  /// 개인운동이 빠지는 경우를 막는 것이 이 단계를 필수로 둔 이유다.
  void _next() {
    final AppLocalizations l = AppLocalizations.of(context);
    switch (_currentStep) {
      case _Step.conditions:
        unawaited(_generate());
      case _Step.program:
        if (_edited.isEmpty) {
          showAppToast(context, l.aiKeepOneExercise);
          return;
        }
        _advance();
      case _Step.review:
        // 프로그램 검토 다음은 개인운동 단계다.
        _seedPersonalFromSuggestions();
        _advance();
      case _Step.personal:
        if (_personal.isEmpty) {
          showAppToast(context, l.aiKeepOnePersonalRoutine);
          return;
        }
        // 이미 있는 PT 에 붙이는 흐름이면 편집기로 가지 않고 넘긴다(#2280).
        final onAttach = widget.onAttach;
        if (widget._attachMode && onAttach != null) {
          onAttach(List<RoutineExercise>.unmodifiable(_personal));
          return;
        }
        // 마지막 칸이다. 두 모드 모두 편집기 화면으로 넘어가고, 보내는 것은
        // 거기서 한다.
        _applyToTemplate();
    }
  }

  /// PT 프로그램 짜기를 건너뛰고 개인운동만 짠다. (#2223)
  ///
  /// 회원이 미리 "이번 주는 PT 를 못 한다"고 말한 주다. `프로그램 선택`·
  /// `프로그램 검토` 를 `건너뜀` 으로 지나 마지막 칸(개인운동)에서 짜고 끝낸다.
  /// 후보 생성은 부르지 않는다 — 쓰지 않을 PT 프로그램을
  /// 만드느라 기다릴 이유가 없다.
  void _skipPtProgram() {
    if (_generating) return;
    setState(() {
      _kind = ProgramKind.routineOnly;
      _stage = 0;
      _maxReachedStage = 0;
      _showAddExercise = false;
    });
    // 제안이 이미 와 있으면 지금 채우고, 아직이면 개인운동 칸이 그릴 때
    // 채운다. 어느 쪽이든 다시 그리는 것은 `_advance` 가 한다.
    _seedPersonalFromSuggestions();
    // 가운데 두 칸을 지나 마지막 칸(개인운동)으로 간다.
    _advance();
  }

  /// AI 개인운동 제안(대기 중)을 개인운동 목록의 출발점으로 삼는다. (#2223)
  ///
  /// 없애는 `AI 개인운동 제안` 카드가 보여 주던 바로 그 목록이다 — 개인운동을
  /// 보내는 입구를 이 단계 하나로 모으면서, 카드에 걸려 있던 제안도 여기로
  /// 들어온다. 한 번만 채운다: 다시 채우면 트레이너가 지운 제안이 되살아난다.
  /// **상태만 바꾼다** — 다시 그리는 것은 부르는 쪽의 몫이다. 화면을 짓는
  /// 도중(`build`)에도 불리므로 여기서 `setState` 를 하면 겹친다.
  void _seedPersonalFromSuggestions() {
    if (_personalSeeded) return;
    final AsyncValue<List<RoutineSuggestion>> async = ref.read(
      routineSuggestionsProvider(widget.client.id),
    );
    // 다시 읽는 중이면 들고 있는 값은 **전송 전의** 목록이다(#2747) — 보낸
    // 직후 새로 선 위저드가 그 값으로 채우면 방금 보낸 제안이 되살아난다.
    if (async.isLoading) return;
    final suggestions = async.valueOrNull;
    // 아직 도착하지 않았다. **채웠다고 표시하지 않는다** — 표시해 버리면
    // 뒤늦게 온 제안이 영영 목록에 들어오지 못하고, 트레이너는 제안이 있는
    // 날에도 빈 목록을 본다.
    if (suggestions == null) return;
    _personalSeeded = true;
    if (suggestions.isEmpty) return;
    _personal = <RoutineExercise>[
      for (final s in suggestions) _exerciseOfSuggestion(s),
    ];
    _personalOrigins
      ..clear()
      ..addAll(<_PersonalOrigin?>[
        for (final s in suggestions) _PersonalOrigin(id: s.id),
      ]);
  }

  /// 지금 단계의 목록에서 한 줄을 뺀다.
  ///
  /// 개인운동 단계에서 AI 제안을 빼는 것은 없앤 카드의 `추천 안 함` 과 같은
  /// 일이라, 서버의 대기 중 제안도 거절 처리한다 — 그러지 않으면 뺀 제안이
  /// 다음 날 다시 올라와 트레이너가 같은 것을 또 뺀다. 서버 호출이 실패해도
  /// 화면에서는 빼 둔다: 이번 전송에 넣지 않겠다는 뜻은 이미 분명하다.
  ///
  /// 되돌릴 수 없는 일이라 **한 번 묻는다** — 거절한 제안은 다시 올라오지
  /// 않는다(다른 화면의 루틴 철회와 같은 확인창이다).
  Future<void> _confirmRemoveExerciseAt(int index) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final String name = _activeList[index].name;
    final bool personal = _currentStep == _Step.personal;
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.aiPersonalDismissTitle,
      // PT 후보에서 빼는 것은 이번 구성에서 지우는 일이고, 개인운동에서 빼는
      // 것은 서버의 AI 제안까지 거절하는 일이다 — 되돌릴 수 있는 범위가 달라
      // 문구도 나눈다.
      // 이름은 조사를 붙여 넘긴다 — `을(를)` 은 사람이 쓴 문장으로 읽히지
      // 않는다. 영어 화면에는 조사를 붙이지 않는다(#2895).
      message: personal
          ? l.aiPersonalDismissBody(withObjectJosaFor(l, name))
          : l.aiProgramExerciseRemoveBody(withObjectJosaFor(l, name)),
      confirmLabel: l.actionDelete,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    _removeExerciseAt(index);
  }

  void _removeExerciseAt(int index) {
    final bool personal = _currentStep == _Step.personal;
    final _PersonalOrigin? origin = personal && index < _personalOrigins.length
        ? _personalOrigins[index]
        : null;
    final String name = _activeList[index].name;
    setState(() {
      _activeList.removeAt(index);
      if (personal && index < _personalOrigins.length) {
        _personalOrigins.removeAt(index);
      }
      // 뒤 줄의 번호가 하나씩 당겨진다 — 비워 버리면 남은 줄의 회↔초 선택까지
      // 잃고, 다음에 이름을 고칠 때 종목표 기본값이 도로 덮어쓴다.
      _shiftMeasureChosen(index);
      // 뒤 줄의 번호가 당겨지므로 열어 둔 자리를 그대로 두면 엉뚱한 줄이
      // 펼쳐진다 — 닫는다.
      if (personal) _editingPersonal = null;
    });
    if (origin == null) return;
    unawaited(_dismissSuggestion(origin.id, name));
  }

  /// 한 줄이 빠져 번호가 당겨질 때 회↔초 선택 자리를 함께 옮긴다.
  void _shiftMeasureChosen(int removed) {
    final Set<int> moved = <int>{
      for (final int i in _activeMeasureChosen)
        if (i < removed) i else if (i > removed) i - 1,
    };
    _activeMeasureChosen
      ..clear()
      ..addAll(moved);
  }

  Future<void> _dismissSuggestion(String id, String name) async {
    final AppLocalizations l = AppLocalizations.of(context);
    try {
      await ref.read(trainerRoutineSuggestionRepositoryProvider).dismiss(id);
    } on RoutineSuggestionAlreadyReviewed {
      // 다른 자리에서 이미 정리된 제안이다 — 화면에서 뺀 것으로 충분하다.
      return;
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        l.aiPersonalDismissFailed,
        type: AppToastType.error,
      );
      return;
    }
    if (!mounted) return;
    ref.invalidate(routineSuggestionsProvider(widget.client.id));
    showAppToast(context, l.aiPersonalDismissed(withTopicJosaFor(l, name)));
  }

  RoutineExercise _exerciseOfSuggestion(RoutineSuggestion s) =>
      _withStrengthDefaults(_rawExerciseOfSuggestion(s));

  RoutineExercise _rawExerciseOfSuggestion(RoutineSuggestion s) =>
      RoutineExercise(
        name: s.name,
        minutes: s.minutes,
        type: s.type,
        sets: s.sets ?? 0,
        reps: s.reps ?? 0,
        holdSeconds: s.holdSeconds ?? 0,
        // 한 세트를 초로 잰 제안이면 그 칸을 그대로 이어받는다(#1969).
        isHold: (s.holdSeconds ?? 0) > 0,
        weight: s.weight ?? 0,
        reason: s.reason,
        source: 'ai',
        // 보낼 때 이 제안을 닫는 데 쓴다(#2747).
        suggestionId: s.id,
      );

  void _goToStage(int stage) {
    if (stage > _maxReachedStage || stage == _stage) return;
    // 건너뛴 칸은 밟을 자리가 아니다 — 눌러도 아무 일이 없다.
    if (_skipped.contains(_steps[stage])) return;
    setState(() => _stage = stage);
    _scrollToTop();
  }

  /// 1·2·3단계를 넘나들 때마다 이 화면을 담고 있는 스크롤을 맨 위로 되돌린다
  /// — 이전 단계에서 아래로 많이 내려가 있었어도, 다음 단계는 늘 위에서부터
  /// 보인다.
  ///
  /// 편집기 안에 넣을 때(embedded)는 자기 `Scrollable` 이 없어 코칭 페이지
  /// 전체를 담은 바깥 스크롤을 그대로 쓰는데, 그 스크롤은 이 화면 위로도
  /// (회원 요약 등) 카드가 더 있는 좁은 화면에서는 `ListView` 로 지연 빌드된다
  /// — `position.animateTo(0)` 처럼 절대 위치 0으로 보내면 이 화면이 뷰포트
  /// 밖으로 밀려나 통째로 언빌드된다. [_topKey] 를 이 화면 맨 위(진행 단계
  /// 표시줄)에 붙여 두고 `Scrollable.ensureVisible` 로 "그 카드가 이미 있는
  /// 스크롤에서, 그 카드의 맨 위가 뷰포트 맨 위에 오도록" 만큼만 옮긴다.
  void _scrollToTop() {
    // 다음 프레임(새 단계가 이미 빌드된 뒤)까지 미룬다 — 이 호출은 늘
    // `setState` 직후라, 그 자리에서 바로 스크롤을 건드리면 아직 끝나지
    // 않은 빌드/레이아웃 도중에 스크롤 위치를 바꾸는 셈이 된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final topContext = _topKey.currentContext;
      if (topContext == null) return;
      Scrollable.ensureVisible(
        topContext,
        duration: OnCareMotion.slow,
        curve: OnCareMotion.curve,
      );
    });
  }

  /// 프로그램 검토에서 확정한 구성을 **바로 고객에게 보내지 않고**, 2열의
  /// (지금은 비어 있는) `프로그램 정보` 박스로만 반영한다.
  ///
  /// 실제 전송은 프로그램 탭 편집기의 단일 `보내기` 버튼에서만 일어난다 —
  /// 여기서는 서버를 호출하지 않는다. 반영은
  /// [CoachingPage]가 넘겨준 [AiRoutineOptionsFlow.onReviewCompleted] 콜백을
  /// 통해 편집기의 `aiSuggestions` 로 흘러가고, 편집기가 그 값이 바뀔 때마다
  /// 세션 1에 병합한다(`ProgramEditorWorkspace.didUpdateWidget`).
  void _applyToTemplate() {
    final AppLocalizations l = AppLocalizations.of(context);
    // `개인운동만` 은 고른 PT 구성이 없다 — 개인운동만 넘긴다.
    if (_kind == ProgramKind.ptWithRoutine && _edited.isEmpty) {
      showAppToast(context, l.aiKeepOneExercise);
      return;
    }
    widget.onReviewCompleted?.call(
      List<RoutineExercise>.unmodifiable(_edited),
      List<RoutineExercise>.unmodifiable(_personal),
      _kind,
    );
    showAppToast(context, l.aiAppliedToTemplate, type: AppToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final content = <Widget>[
      if (!widget._attachMode && widget.onManualCreate != null) ...<Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            key: const ValueKey<String>('ai-manual-create'),
            label: l.aiManualCreate,
            onPressed: widget.onManualCreate,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
            leadingIcon: AppIcons.write,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
      ],
      KeyedSubtree(
        key: _topKey,
        child: AppStepIndicator.numbered(
          keyPrefix: 'routine-stage',
          semanticsLabel: l.aiStepperLabel,
          current: _stage,
          maxReached: _maxReachedStage,
          labels: _stepLabels(l),
          skipped: <int>{
            for (int i = 0; i < _steps.length; i++)
              if (_skipped.contains(_steps[i])) i,
          },
          skippedLabel: l.aiStepSkipped,
          // 붙이기 흐름은 개인운동 칸에서 끝난다 — 조건 설정으로 돌아가도 거기엔
          // PT 후보 생성뿐이라 할 일이 없다(#2280).
          onStepTap: widget._attachMode ? (_) {} : _goToStage,
        ),
      ),
      const SizedBox(height: OnCareSpacing.s16),
      // 편집기의 PT 에 붙이는 흐름(#2280) — 어느 PT 에 붙는지를 단계 표시줄
      // 바로 아래에 적는다.
      if (widget._attachMode) ...<Widget>[
        AppTile(
          key: const ValueKey<String>('routine-attach-target'),
          tone: AppTileTone.neutral,
          child: Row(
            children: <Widget>[
              const AppIcon(
                AppIcons.calendar,
                size: OnCareSize.iconSmall,
                color: OnCareColors.textSecondary,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Text(
                  widget.attachTarget!,
                  style: _text(
                    OnCareTypography.bodySmall,
                    OnCareColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: OnCareSpacing.s16),
      ],
      ...switch (_currentStep) {
        _Step.conditions => <Widget>[
          _assistantAnalysis(),
          const SizedBox(height: OnCareSpacing.s16),
          _sourcesCard(),
          const SizedBox(height: OnCareSpacing.s16),
          _promptField(),
          const SizedBox(height: OnCareSpacing.s16),
          _directionControls(),
        ],
        _Step.program => <Widget>[
          _generatedOptions(),
          const SizedBox(height: OnCareSpacing.sectionGap),
          _routineEditor(),
          const SizedBox(height: OnCareSpacing.s16),
          _trainerMemoField(),
        ],
        _Step.personal => <Widget>[_personalRoutineEditor()],
        _Step.review => <Widget>[_reviewedRoutineList()],
      },
    ];
    final Widget nav = _stepNav();
    // 단계·후보·목록이 바뀌면 다시 그려진다 — 그때마다 알린다. 같은 내용이면
    // 받는 쪽이 거른다(#2873).
    _emitSnapshot();

    if (widget.embedded) {
      final onStepNav = widget.onStepNav;
      if (onStepNav != null) {
        // 진행 줄은 바깥 열의 스크롤 아래에 고정된다 — 이 화면은 그 스크롤
        // 안에 있어 제 손으로 스크롤 밖에 그릴 수 없다. 빌드가 끝난 뒤에
        // 넘긴다: 빌드 도중에 알리면 바깥이 같은 프레임에 다시 그려진다.
        _publishedNav = nav;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(_publishedNav, nav)) onStepNav(this, nav);
        });
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ...content,
          if (onStepNav == null) ...<Widget>[
            const SizedBox(height: OnCareSpacing.sectionGap),
            nav,
            const SizedBox(height: OnCareSpacing.s32),
          ],
        ],
      );
    }

    final double pad = context.oncare.density.pagePadding;
    return Scaffold(
      backgroundColor: OnCareColors.surfacePage,
      appBar: AppTopBar(
        title: l.aiRoutineFor(widget.client.name),
        // 옛 AppBar 의 자동 뒤로가기와 같게 — 돌아갈 경로가 있을 때만 단다.
        showBack: Navigator.canPop(context),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ListView(padding: EdgeInsets.all(pad), children: content),
            ),
            Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, pad), child: nav),
          ],
        ),
      ),
    );
  }

  /// 단계 진행 줄 — `이전` 은 왼쪽 끝, 이 단계를 끝내는 주 버튼은 오른쪽 끝.
  /// (#2476)
  ///
  /// 카드 여러 장을 채운 뒤 넘어가는 단계라, 버튼이 내용 끝에만 붙어 있으면
  /// 스크롤을 다 내려야 보인다. 리포트 편집기 단계 하단처럼 열 스크롤 바로
  /// 아래에 둔다 — 내용이 짧으면 내용 바로 다음 줄에, 길면 열 바닥에
  /// 머문다([AiRoutineOptionsFlow.onStepNav]).
  ///
  /// 조건 설정에는 되돌아갈 칸이 없다. 그 자리 대신 주 버튼 왼쪽에 `PT 없이
  /// 개인운동만 짜기` 를 보조 버튼으로 둔다 — `이전` 처럼 되돌아가는 것이 아니라
  /// 후보 생성과 나란히 **앞으로** 가는 다른 갈래다(#2223: 이번 주는 PT 가 없는
  /// 회원 — 후보 생성을 거치지 않고 개인운동만 짜서 보낸다).
  Widget _stepNav() {
    final AppLocalizations l = AppLocalizations.of(context);
    // 편집기의 PT 에 붙이는 흐름은 개인운동 칸에서 시작하고 끝난다 — 되돌아갈
    // 칸이 없으니 `이전` 자리(왼쪽 끝)를 쓰지 않고, [취소][확정] 을 오른쪽에
    // 붙여 둔다(#2280). 확정은 위저드 마지막 칸과 같은 `프로그램에 반영` 이다 —
    // 반영하면 편집기로 돌아간다.
    if (widget._attachMode) {
      return AppButtonPair(
        cancelKey: const ValueKey<String>('routine-attach-cancel'),
        cancelLabel: l.actionCancel,
        onCancel: widget.onAttachCancel,
        confirmKey: const ValueKey<String>('routine-attach-confirm'),
        confirmLabel: l.aiApplyToTemplate,
        onConfirm: _next,
      );
    }
    final int? prev = _previousStage();
    final Widget primary = switch (_currentStep) {
      _Step.conditions => AppButton(
        key: const ValueKey<String>('generate-routine-options'),
        label: _generating ? l.aiAnalysing : _generateButtonLabel(l),
        onPressed: _next,
        leadingIcon: AppIcons.ai,
        // 처리 중이면 스피너를 두고 탭을 막는다([_generate] 도 중복 호출을 막는다).
        loading: _generating,
      ),
      // 이 단계는 후보를 고르고 고치는 자리다 — 검토는 다음 칸이 한다.
      _Step.program => AppButton(
        key: const ValueKey<String>('complete-routine-review'),
        label: l.aiStepNext,
        onPressed: _next,
        trailingIcon: AppIcons.chevronRight,
      ),
      // 검토를 끝내고 개인운동 단계로 간다. **아직 아무것도 반영하지 않는다** —
      // 위저드를 빠져나가는 출구는 개인운동 단계의 `프로그램에 반영` 하나뿐이고,
      // 그때 PT 구성과 개인운동이 함께 편집기로 간다(#2223).
      _Step.review => AppButton(
        key: const ValueKey<String>('apply-routine-to-template'),
        label: l.aiReviewDone,
        onPressed: _next,
        leadingIcon: AppIcons.review,
      ),
      // 두 모드 모두 여기서 편집기 화면으로 넘어간다 — 보내는 것은 거기서
      // 한다. PT 가 있든 없든 끝내는 과정이 같아야 한다(#2223).
      _Step.personal => AppButton(
        key: const ValueKey<String>('complete-personal-routines'),
        label: l.aiApplyToTemplate,
        onPressed: _next,
        leadingIcon: AppIcons.applyToTemplate,
      ),
    };
    return AppActionRow(
      leading: prev == null
          ? null
          : AppButton(
              key: const ValueKey<String>('routine-step-prev'),
              label: l.aiStepPrev,
              variant: AppButtonVariant.text,
              leadingIcon: AppIcons.chevronLeft,
              onPressed: () => _goToStage(prev),
            ),
      actions: <Widget>[
        if (_currentStep == _Step.conditions)
          AppButton(
            key: const ValueKey<String>('skip-pt-program'),
            label: l.aiSkipPtProgram,
            onPressed: _generating ? null : _skipPtProgram,
            variant: AppButtonVariant.secondary,
            leadingIcon: AppIcons.personalRoutine,
          ),
        primary,
      ],
    );
  }

  /// `이전` 이 갈 칸 — 건너뛴 칸은 지나친다. 첫 칸이면 없다.
  int? _previousStage() {
    var prev = _stage - 1;
    while (prev >= 0 && _skipped.contains(_steps[prev])) {
      prev -= 1;
    }
    return prev < 0 ? null : prev;
  }

  /// 분석 박스 오른쪽 칸(최근 감지 메모)의 **고정 높이**(#1655).
  ///
  /// 메모가 늘어도 카드가 아래로 자라면 안 된다 — 프로그램 탭은 이 박스 아래에
  /// 생성 조건과 버튼을 두고 있어, 박스가 자랄 때마다 트레이너가 누르던 자리가
  /// 밀린다. 넘치는 메모는 칸 안에서 스크롤한다.
  ///
  /// 두 칸을 위아래로 쌓을 때의 높이다. 나란히 둘 때는 왼쪽 다섯 줄(사실 넷 +
  /// 권장 방향, #2373)과 키를 맞춰 [_analysisPanelSideHeight] 를 쓴다 — 쌓을
  /// 때까지 그 키를 쓰면 빈 칸만 커진다.
  static const double _analysisPanelHeight =
      OnCareSpacing.s48 + OnCareSpacing.s48;

  /// 두 칸을 나란히 둘 때 오른쪽 칸의 고정 높이 — 왼쪽 다섯 줄의 키.
  static const double _analysisPanelSideHeight =
      _analysisPanelHeight + OnCareSpacing.s24;

  /// 이 폭 아래에서는 두 칸을 위아래로 쌓는다.
  static const double _analysisSplitWidth = OnCareLayout.dialogMedium;

  /// 분석 줄 왼쪽 라벨 칸의 폭.
  static const double _analysisLabelWidth =
      OnCareSpacing.s48 + OnCareSpacing.s40;

  /// 후보 카드를 나란히 둘 때 한 장의 최소 폭(160).
  ///
  /// 세 후보는 **나란히 세 열**로 비교한다. 프로그램 탭의 가운데 편집기 열은
  /// 넓은 창에서도 600 안팎이라, 한 장에 232 를 요구하면 늘 세로로 쌓였다.
  /// 이 폭보다도 좁을 때만 세로로 쌓는다.
  static const double _minOptionCardWidth = OnCareSpacing.s40 * 4;

  Widget _assistantAnalysis() {
    final AppLocalizations l = AppLocalizations.of(context);
    final client = widget.client;
    // 주의 배지·주간 리포트와 같은 정의([recordedCompletionMean]) — 이 박스만
    // 다른 계산으로 "완료율"을 말하면 트레이너가 같은 값을 두 번 다르게 읽는다.
    final completionMean = recordedCompletionMean(client);
    final Widget facts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _analysisRow(l.aiGoal, healthFocusGoalLabel(l, client.goal)),
        // "오늘"·"어제" 같은 날짜가 아니라 **무엇을 했는지**를 적는다 —
        // 프로그램을 짜는 자리에서 알아야 하는 것은 마지막 기록이 언제였나가
        // 아니라 어떤 운동을 마쳤나다 (#1655).
        _analysisRow(l.aiRecentRoutine, _recentRoutineLabel(l)),
        _analysisRow(
          l.aiRecentCompletion,
          completionMean == null
              ? l.aiNoCompletionData
              : '${completionMean.round()}%'
                    '${completionMean < lowCompletionThreshold ? l.aiCompletionLow : ''}',
          warn:
              completionMean != null && completionMean < lowCompletionThreshold,
        ),
        // 목표를 넘겼을 때만 꼬리표를 붙인다. 넘기지 않았다고 "적정" 이라
        // 말하면, 목표에 한참 못 미친 값까지 적정이 된다(#1070).
        //
        // 오늘 나트륨 하나만으로는 "오늘 우연히 튄 값"인지 "평소 패턴"인지
        // 구분이 안 된다 — 최근 7일 초과일수([sodiumOverDays])와 당류
        // 초과 여부([sugarOverBudget])를 같은 줄에 더해 식단 신호를 한
        // 번에 보여준다.
        _analysisRow(
          l.aiDietSignal,
          '${client.sodiumMg}${unitGap(l.localeName)}mg'
          '${client.sodiumOverBudget ? l.aiOverTarget : ''}'
          '${client.sodiumOverDays > 0 ? l.aiSodiumOverDaysSuffix(client.sodiumOverDays) : ''}'
          '${client.sugarOverBudget ? l.aiSugarAlsoOver : ''}',
          warn: client.sodiumOverBudget || client.sugarOverBudget,
        ),
        // 위 네 줄을 어떻게 읽을지 — 규칙으로 정한 한 줄이다(#2373). 같은
        // 회원 데이터에는 언제나 같은 말이 나온다.
        _analysisRow(
          l.aiDirectionLabel,
          _directionLabel(l, programDirectionFor(client)),
          key: const ValueKey<String>('ai-analysis-direction'),
        ),
      ],
    );
    // 회원 데이터를 규칙으로 계산한 값만 담는다 — AI 를 부르지 않으므로 AI
    // 아이콘·브랜드 강조 카드를 쓰지 않는다. 눈에 띄어야 하는 것은 카드가 아니라
    // 경고 줄(빨강)과 오른쪽 확인 필요 칸이다. (#2372)
    return AppCard(
      key: const ValueKey<String>('ai-analysis-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSectionHeader(title: l.aiAnalysedData, icon: AppIcons.review),
          const SizedBox(height: OnCareSpacing.s12),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool stacked = constraints.maxWidth < _analysisSplitWidth;
              final Widget memos = _chatInsightMemoPanel(
                height: stacked
                    ? _analysisPanelHeight
                    : _analysisPanelSideHeight,
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    facts,
                    const SizedBox(height: OnCareSpacing.s12),
                    memos,
                  ],
                );
              }
              // 왼쪽이 넓다. 반씩 나눴더니 식단 주의 한 줄이 두 줄로 접히면서
              // 카드 전체가 아래로 자랐다 — 이 카드는 크기가 고정이라야 한다.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 5, child: facts),
                  const SizedBox(width: OnCareSpacing.s16),
                  Expanded(flex: 3, child: memos),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 분석 박스 오른쪽 — 오늘을 포함한 최근 7일(KST)의 채팅 감지 메모.
  ///
  /// 채팅 배너와 같은 붉은 계열을 쓴다. 같은 감지가 채팅에서는 붉고 여기서는
  /// 회색이면, 트레이너가 두 화면에서 같은 신호를 같은 것으로 알아보지 못한다.
  /// 손으로 쓴 트레이너 메모(`source=trainer`)는 여기 넣지 않는다 — 이 칸은
  /// AI 가 대화에서 집어낸 것만 모으는 자리다.
  ///
  /// 모양은 채팅 감지 경고와 같은 [AppBanner] `danger`·[AppBannerDensity.compact]
  /// 다. 고정 높이 안에서 메모 목록을 스크롤한다(#1655, `expandChild`).
  Widget _chatInsightMemoPanel({required double height}) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<List<TrainerMemo>> memos = ref.watch(
      trainerMemosProvider(widget.client.id),
    );
    return SizedBox(
      key: const ValueKey<String>('ai-chat-insight-memos'),
      height: height,
      child: AppBanner(
        tone: AppBannerTone.danger,
        density: AppBannerDensity.compact,
        icon: AppIcons.warning,
        title: l.aiInsightMemoTitle,
        expandChild: true,
        // 메모를 못 읽어도 이 칸만 조용히 비운다 — 생성 버튼까지 막으면
        // 참고 자료 하나 때문에 프로그램을 못 만든다 (#1655).
        child: memos.when(
          loading: () => const AppLoading(placement: AppStatePlacement.card),
          error: (Object _, StackTrace _) =>
              _insightMemoNote(l.aiInsightMemoFailed),
          data: (List<TrainerMemo> list) {
            final List<TrainerMemo> recent = _recentChatInsights(list);
            if (recent.isEmpty) {
              return _insightMemoNote(l.aiInsightMemoEmpty);
            }
            return ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: recent.length,
              itemBuilder: (BuildContext context, int index) =>
                  _insightMemoLine(recent[index]),
            );
          },
        ),
      ),
    );
  }

  Widget _insightMemoNote(String text) => Text(
    text,
    style: _text(OnCareTypography.caption, OnCareColors.textSecondary),
  );

  /// `8/31  무릎 불편감이 …` — 날짜와 요약을 한 줄에 둔다. 날짜는 트레이너 웹의
  /// 짧은 날짜 꼴(`M/d`, 0 을 채우지 않음)이다(#3120).
  Widget _insightMemoLine(TrainerMemo memo) {
    final DateTime date = _kstDateOf(memo.createdAt);
    final String day = '${date.month}/${date.day}';
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            day,
            style: _text(
              OnCareTypography.strong(OnCareTypography.caption),
              OnCareColors.danger,
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(
            child: Text(
              memo.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(OnCareTypography.caption, OnCareColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// 오늘을 포함한 최근 7일(KST)의 채팅 감지 메모, 최신순.
  /// 같은 날짜 안에서는 목록 계약과 같게 `created_at DESC, id DESC` 다.
  List<TrainerMemo> _recentChatInsights(List<TrainerMemo> memos) {
    final DateTime today = nowKst();
    final DateTime from = DateTime(today.year, today.month, today.day - 6);
    final List<TrainerMemo> recent = <TrainerMemo>[
      for (final TrainerMemo memo in memos)
        if (memo.source == TrainerMemoSource.chatInsight &&
            !_kstDateOf(memo.createdAt).isBefore(from))
          memo,
    ];
    recent.sort((TrainerMemo a, TrainerMemo b) {
      final int byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return recent;
  }

  /// 저장 시각을 **KST 달력일**로 옮긴다. 기기 타임존이 KST 가 아니면 자정
  /// 언저리의 메모가 하루씩 밀린다 — `nowKst` 와 같은 기준을 쓴다.
  static DateTime _kstDateOf(DateTime at) {
    final DateTime kst = at.toUtc().add(kstOffset);
    return DateTime(kst.year, kst.month, kst.day);
  }

  /// 최근 기록에서 **마친 운동 이름**을 만든다.
  ///
  /// 이력은 최신순이고 항목 이름은 `스쿼트 ✓` / `레그프레스 ✗` 꼴이라
  /// (`FixtureExercise.label`), 마친 것(✓)만 남겨 이름을 읽는다. 마친 운동이
  /// 하나도 없는 날은 건너뛴다 — "최근 운동" 자리에 하지 않은 운동을 적을 수는
  /// 없다.
  String _recentRoutineLabel(AppLocalizations l) {
    final List<RoutineHistoryEntry> history =
        ref.watch(clientHistoryProvider(widget.client.id)).valueOrNull ??
        const <RoutineHistoryEntry>[];
    for (final RoutineHistoryEntry entry in history) {
      final List<String> done = <String>[
        for (final ClientExerciseItem exercise in entry.exercises)
          if (exercise.done) exercise.name,
      ];
      if (done.isEmpty) continue;
      return done.length == 1
          ? done.first
          : l.aiRecentRoutineMore(done.first, done.length - 1);
    }
    return l.aiNoRecentRoutine;
  }

  /// 조건 설정 단계의 `AI가 참고할 자료` 체크 목록 (#2587).
  ///
  /// 트레이너만 보는 글(상담 메모 등)을 AI 에 넣을지는 트레이너가 고른다.
  /// 줄마다 서버가 실제로 읽는 범위를 적는다 — 켜 두면 무엇이 들어가는지
  /// 트레이너가 짐작하지 않아도 되게.
  ///
  /// 넓으면 세 칸, 좁으면 두 칸·한 칸으로 줄을 바꾼다.
  Widget _sourcesCard() {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      key: const ValueKey<String>('ai-sources-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSectionHeader(
            title: l.aiSourcesTitle,
            subtitle: l.aiSourcesBlurb,
            subtitleMaxLines: 2,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final int columns = constraints.maxWidth >= 720
                  ? 3
                  : constraints.maxWidth >= 440
                  ? 2
                  : 1;
              const double gap = OnCareSpacing.s8;
              final double width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: <Widget>[
                  for (final RoutineContextSource source
                      in RoutineContextSource.values)
                    SizedBox(width: width, child: _sourceTile(l, source)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sourceTile(AppLocalizations l, RoutineContextSource source) {
    final bool on = _sources.contains(source);
    // 선택 칩(`AppChoiceChip`)과 같은 선택 색 — 켜진 자료가 한눈에 갈린다.
    final OnCareTokens tokens = context.oncare;
    final (String label, String range) = switch (source) {
      // 서버 `_recent_chat_lines` 와 같은 범위다(#2794).
      RoutineContextSource.recentChat => (
        l.aiSourceRecentChat,
        l.aiSourceRangeDays(14, 10),
      ),
      RoutineContextSource.ptFeedback => (
        l.aiSourcePtFeedback,
        l.aiSourceRangeDays(14, 5),
      ),
      RoutineContextSource.consultMemo => (
        l.aiSourceConsultMemo,
        l.aiSourceRangeDays(30, 3),
      ),
      RoutineContextSource.trainerMemo => (
        l.aiSourceTrainerMemo,
        l.aiSourceRangeDays(14, 5),
      ),
      RoutineContextSource.chatInsight => (
        l.aiSourceChatInsight,
        l.aiSourceRangeDays(7, 10),
      ),
      RoutineContextSource.weeklyFeedback => (
        l.aiSourceWeeklyFeedback,
        l.aiSourceRangeWeeks,
      ),
    };
    return Material(
      color: on ? tokens.brand.surface : OnCareColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: OnCareRadius.mdAll,
        side: BorderSide(
          color: on ? tokens.brand.border : OnCareColors.lineSubtle,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('ai-source-${source.wire}'),
        onTap: () => _toggleSource(source, !on),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OnCareSpacing.s4,
            vertical: OnCareSpacing.s4,
          ),
          child: Row(
            children: <Widget>[
              Checkbox(
                value: on,
                onChanged: (bool? value) =>
                    _toggleSource(source, value ?? false),
              ),
              const SizedBox(width: OnCareSpacing.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        OnCareTypography.bodySmall,
                        OnCareColors.textPrimary,
                      ),
                    ),
                    Text(
                      range,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        OnCareTypography.caption,
                        OnCareColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 조건 설정 단계의 자연어 요청 칸 (#1028).
  ///
  /// 슬라이더·칩으로는 표현할 수 없는 요구("무릎 부담 적게", "유산소 비중 높게")를
  /// 트레이너가 쓰던 말 그대로 적는 자리다. 이 값은 지어낸 새 필드가 아니라
  /// 백엔드 `RoutineOptionsRequest.trainer_note` 로 그대로 나간다 — 서버가
  /// 실제로 읽는 유일한 자유 텍스트라 화면이 거짓말을 하지 않는다.
  Widget _promptField() {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      key: const ValueKey<String>('ai-prompt-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSectionHeader(
            title: l.aiPromptTitle,
            subtitle: l.aiPromptBlurb,
            subtitleMaxLines: 1,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('ai-natural-language-prompt'),
            controller: _prompt,
            label: l.aiPromptLabel,
            hint: l.aiPromptHint,
            minLines: 3,
            maxLines: 5,
            maxLength: _promptMaxLength,
          ),
          const SizedBox(height: OnCareSpacing.s4),
          // AppTextField 는 기본 글자 수 표시를 숨긴다 — 서버 상한을 트레이너가
          // 미리 보도록 필드 오른쪽 아래에 직접 둔다.
          Align(
            alignment: Alignment.centerRight,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _prompt,
              builder: (BuildContext context, TextEditingValue value, _) =>
                  Text(
                    '${value.text.characters.length}/$_promptMaxLength',
                    key: const ValueKey<String>('ai-prompt-counter'),
                    style: _text(
                      OnCareTypography.caption,
                      OnCareColors.textTertiary,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _directionControls() {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSectionHeader(
            title: l.aiGenerateConditions,
            subtitle: l.aiConditionsAutoHint,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 다른 시간 칸(`RoutineDurationField`)과 같은 시·분 칸이다. 서버가
          // 분으로 받으므로 초 칸은 숨긴다.
          AppDurationField(
            key: const ValueKey<String>('generation-minutes'),
            keyPrefix: 'generation-minutes',
            duration: Duration(minutes: _minutes),
            label: l.routineFieldTotalMinutes,
            labels: AppDurationWheelLabels(
              hours: l.routineUnitHours,
              minutes: l.routineUnitMinutes,
              seconds: l.routineUnitSeconds,
            ),
            showSeconds: false,
            // 서버가 받는 범위만 받는다(#2871) — 개별 운동 시간 칸과 다르다.
            minSeconds: kRoutineGenerateMinMinutes * 60,
            maxSeconds: kRoutineGenerateMaxMinutes * 60,
            onChanged: (Duration value) => setState(() {
              _minutes = value.inMinutes;
              _minutesTouched = true;
            }),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            l.aiGenerateMinutesHelper(
              kRoutineGenerateMinMinutes,
              kRoutineGenerateMaxMinutes,
            ),
            key: const ValueKey<String>('generation-minutes-helper'),
            style: _text(OnCareTypography.caption, OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s16),
          RoutineIntensityChips(
            value: _intensity,
            onChanged: (intensity) => setState(() {
              _intensity = intensity;
              _intensityTouched = true;
            }),
          ),
        ],
      ),
    );
  }

  /// Only known after the first generation — before that we haven't seen
  /// the member's analysis yet, so the button stays generic (#776).
  ///
  /// 데모와 실서버가 같다(#2674). 예전에는 데모에서 기록 부족(템플릿) 상태를
  /// 숨겼다(#1028) — 데모 회원에게 기록이 없어 생성기가 늘 템플릿을 돌려줘,
  /// 데이터 기반 흐름이 한 번도 보이지 않았기 때문이다. 이제 데모도 시드한
  /// 운동 기록으로 서버와 같은 규칙의 추천 상태를 계산하므로, 기록이 쌓인 회원은
  /// 학습 중·맞춤 흐름을, 기록이 적은 회원은 그 사실을 그대로 본다.
  String _generateButtonLabel(AppLocalizations l) {
    final status = _options?.analysis.recommendationStatus;
    return status == RecommendationStatus.template
        ? l.aiGenerateGoalBased
        : l.aiGenerateCandidates;
  }

  Widget _generatedOptions() {
    final AppLocalizations l = AppLocalizations.of(context);
    final options = _options!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppSectionHeader(title: l.aiCompareCandidates, icon: AppIcons.ai),
        const SizedBox(height: OnCareSpacing.s8),
        // 기록이 적은 회원에게도 그 사실을 말한다 — 데모·실서버 같다(#2674).
        // 참고한 대화 링크도 이 배너 안에 둔다 — 무엇을 근거로 만들었는지가
        // 한 상자에 모인다.
        // 목표·완료율·생성 방식·트레이너 요청도 배너 안 표로 모은다 — 예전에는
        // 배너 밖 한 줄 캡션이라 근거가 두 군데로 갈렸다.
        _RecommendationStatusBanner(
          analysis: options.analysis,
          generatedBy: options.generatedBy,
          trainerRequest: _prompt.text.trim(),
          minutes: _minutes,
          intensity: _intensity,
          minutesSetByTrainer: _minutesTouched,
          intensitySetByTrainer: _intensityTouched,
          findings: options.findings,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        // 세 안은 하나만 고르는 묶음이다 — 카드마다 선 라디오가 이 묶음을 본다.
        RadioGroup<String>(
          groupValue: _selectedKey,
          onChanged: (String? key) {
            for (final choice in _choicesOf(l)) {
              if (choice.key == key) _selectChoice(choice);
            }
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Side by side whenever they fit: this is a COMPARISON, and a
              // comparison you have to scroll through isn't one. The console
              // splits the workspace into two columns, so the editor column
              // is narrower than the full-width page this flow was built
              // for.
              final choices = _choicesOf(l);
              final needed =
                  choices.length * _minOptionCardWidth +
                  (choices.length - 1) * OnCareSpacing.cardGap;
              if (constraints.maxWidth >= needed) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: OnCareSpacing.s12),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final choice in choices) ...<Widget>[
                          Expanded(child: _optionCard(choice)),
                          if (choice != choices.last)
                            const SizedBox(width: OnCareSpacing.cardGap),
                        ],
                      ],
                    ),
                  ),
                );
              }
              // 폭이 부족하면 가로 스크롤 대신 세로로 쌓는다 — 옆으로 밀어야
              // 보이는 후보는 "비교"가 아니다. 각 카드는 폭 전체를 쓰고,
              // 내용만큼 세로로 자연스럽게 늘어난다(카드 내부 재스크롤 없음).
              return Padding(
                padding: const EdgeInsets.only(bottom: OnCareSpacing.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final choice in choices) ...<Widget>[
                      _optionCard(choice),
                      if (choice != choices.last)
                        const SizedBox(height: OnCareSpacing.cardGap),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _optionCard(_RoutineChoice choice) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Color brand = context.oncare.brand.primary;
    final selected = choice.key == _selectedKey;
    final total = choice.exercises.fold<int>(
      0,
      (sum, exercise) => sum + exercise.minutes,
    );
    final optionName = _optionDisplayName(l, choice.key);
    return AppCard(
      key: ValueKey<String>('routine-option-${choice.key}'),
      selected: selected,
      onTap: () => _selectChoice(choice),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // 빈 동그라미 글리프 대신 라디오 조작 요소다(#2466) — 아이콘은
              // 늘 채움이라 `안 고름` 을 그릴 모양이 없다. 카드 전체가 눌리는
              // 자리라 라디오는 고른 안을 보이는 일만 맡는다.
              SizedBox.square(
                dimension: OnCareSize.iconMedium,
                child: Radio<String>(value: choice.key),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Text(
                  '$optionName · ${choice.label}',
                  style: _text(
                    OnCareTypography.titleSmall,
                    OnCareColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            l.aiTotalAndIntensity(
              total,
              routinePlanIntensityLabel(l, choice.intensity),
            ),
            style: _text(OnCareTypography.label, brand),
          ),
          // C안 — 왜 이번 차례인지와 지난 PT 에서 무엇을 바꿨는지(#3282).
          if (choice.basis.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              choice.basis,
              key: ValueKey<String>('routine-option-${choice.key}-basis'),
              style: _text(OnCareTypography.bodySmall, OnCareColors.textSecondary),
            ),
          ],
          if (choice.changes.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            for (final String change in choice.changes)
              Text(
                l.aiFindingAction(change),
                style: _text(OnCareTypography.bodySmall, brand),
              ),
          ],
          const SizedBox(height: OnCareSpacing.s8),
          for (final exercise in choice.exercises)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s2),
              child: Text(
                '${l.aiBulletExercise(exercise.name, exercise.minutes)}'
                '(${routineTypeLabel(l, exercise.type)})',
                style: _text(
                  OnCareTypography.bodySmall,
                  OnCareColors.textPrimary,
                ),
              ),
            ),
          const SizedBox(height: OnCareSpacing.s8),
          // 카드가 세로로 늘어날 수 있게 된 만큼, 이유를 3줄로 잘라내지
          // 않고 전부 보여준다 — 잘린 추천 이유는 비교에 쓸 수 없다.
          Text(
            choice.reason,
            style: _text(OnCareTypography.caption, OnCareColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _routineEditor() {
    final AppLocalizations l = AppLocalizations.of(context);
    final optionName = _optionDisplayName(l, _selectedKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(
          title: l.aiEditOption(optionName),
          subtitle: l.aiEditBlurb,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        for (int index = 0; index < _edited.length; index++) ...<Widget>[
          _exerciseEditor(index),
          const SizedBox(height: OnCareSpacing.s8),
        ],
        if (_showAddExercise)
          _addExerciseForm()
        else
          _addExerciseButton(
            key: const ValueKey<String>('show-add-exercise-form'),
            onPressed: () => setState(() => _showAddExercise = true),
          ),
      ],
    );
  }

  /// 목록 끝 가운데의 `+ 운동 추가`. (#2476)
  ///
  /// 줄을 하나 더 붙이는 자리라 목록 바로 아래에 둔다 — 넣은 줄이 그 자리에
  /// 생긴다. 모양은 편집기의 `+ 세션 추가`·`+ 운동 추가` 와 같은 작은 글자
  /// 버튼이다. 열 폭을 채우는 보조 버튼이면 아래 진행 줄의 주 버튼과 무게가
  /// 겨루고, 오른쪽 끝이면 그 주 버튼과 한 줄기로 읽힌다.
  Widget _addExerciseButton({required Key key, VoidCallback? onPressed}) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Align(
      child: AppButton(
        key: key,
        label: l.programEditorAddExercise,
        onPressed: onPressed,
        variant: AppButtonVariant.text,
        size: OnCareButtonSize.small,
        leadingIcon: AppIcons.add,
      ),
    );
  }

  /// 트레이너가 내용을 고친 줄은 출처가 트레이너가 된다(#2223).
  ///
  /// 트레이너 웹의 `AI`/`트레이너` 태그가 이 값으로 갈린다. 이름·유형·시간·
  /// 세트를 다 바꿔 놓고도 `AI` 로 남으면 태그가 사실과 달라진다(회원 앱은 줄마다
  /// 출처를 보여 주지 않는다, #2566). `AI 추천 사유` 는 그대로 남는다 —
  /// 그건 트레이너만 보는 칸이고, 왜 이 운동이 올라왔는지는 고친 뒤에도
  /// 알아야 한다.
  RoutineExercise _asTrainerEdit(RoutineExercise exercise) =>
      exercise.source == 'ai' ? exercise.copyWith(source: 'trainer') : exercise;

  /// 운동 한 줄 편집기. 프로그램 후보와 개인운동이 **같은 편집기**를 쓴다 —
  /// 대상 목록만 단계에 따라 다르다([_activeList], #2223).
  Widget _exerciseEditor(int index) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<RoutineExercise> list = _activeList;
    final exercise = list[index];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: RoutineCategoryChips(
                  keyPrefix: 'routine-category-$_activeKeyPrefix-$index',
                  value: exercise.type,
                  // 근력으로 바꾸면 화면이 보여 주는 3세트·10회를 값으로도
                  // 채운다(#3247) — 0 으로 두면 저장이 세트·횟수를 빼고 보낸다.
                  onChanged: (type) => setState(() {
                    list[index] = _asTrainerEdit(
                      _withStrengthDefaults(exercise.copyWith(type: type)),
                    );
                  }),
                ),
              ),
              // 개인운동을 펼쳐서 고치는 중이면 이 자리는 **닫기**다 — 프로그램
              // 편집기의 이름 수정과 같은 체크 아이콘을 쓴다(#2223). 닫는 길이
              // 없으면 한번 연 줄은 다른 줄을 열기 전까지 펼쳐진 채로 남는다.
              if (_currentStep == _Step.personal && _editingPersonal == index)
                AppIconButton(
                  key: ValueKey<String>('personal-routine-done-$index'),
                  icon: AppIcons.check,
                  tooltip: l.aiPersonalEditDone,
                  color: context.oncare.brand.primary,
                  onPressed: () => setState(() => _editingPersonal = null),
                )
              else
                AppIconButton(
                  key: ValueKey<String>(
                    'routine-remove-$_activeKeyPrefix-$index',
                  ),
                  icon: AppIcons.delete,
                  // 개인운동 단계에서 AI 제안을 빼는 것은 없앤 카드의
                  // `추천 안 함`(휴지통)과 같은 일이다 — 서버의 대기 중 제안도
                  // 함께 거절해, 뺀 제안이 내일 다시 올라오지 않게 한다(#2223).
                  tooltip: _currentStep == _Step.personal
                      ? l.aiPersonalDismissTooltip
                      : l.progDeleteExercise,
                  color: OnCareColors.textTertiary,
                  onPressed: () => unawaited(_confirmRemoveExerciseAt(index)),
                ),
            ],
          ),
          SizedBox(
            key: ValueKey<String>('routine-category-name-gap-$index'),
            height: OnCareSpacing.s12,
          ),
          _ExerciseNameField(
            key: ValueKey<String>(
              'routine-name-$_activeKeyPrefix-$index-${exercise.name}',
            ),
            initialValue: exercise.name,
            hint: l.progExerciseName,
            onChanged: (name) {
              // 이름이 버티는 운동이면 `횟수` 칸이 `버티는 시간` 으로
              // 바뀐다(#1969). 트레이너가 직접 고른 뒤에는 덮지 않는다 —
              // 그 선택은 `_measureChosen` 이 기억한다.
              list[index] = _asTrainerEdit(
                _withStrengthDefaults(
                  list[index].copyWith(
                    name: name,
                    isHold: _activeMeasureChosen.contains(index)
                        ? null
                        : isIsometricExerciseName(name),
                  ),
                ),
              );
            },
          ),
          // 고치는 동안에도 AI 가 왜 이 운동을 골랐는지는 이름 바로 아래
          // 그대로 보인다 — 판단하면서 읽는 글이라 편집 칸이 아니다.
          if (_currentStep == _Step.personal) _aiRationale(index),
          if (exercise.type == '근력') ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            // 한 세트를 회로 잴지 초로 잴지. 이름 해석이 기본값을 주고,
            // 고르는 것은 트레이너다(#1969).
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: RoutineMeasureToggle(
                keyPrefix: 'routine-measure-$_activeKeyPrefix-$index',
                isHold: exercise.isHold,
                onChanged: (bool hold) => setState(() {
                  _activeMeasureChosen.add(index);
                  // 회↔초를 바꾸면 새 칸의 기본값(10회·60초)도 값으로 채운다
                  // (#3247).
                  list[index] = _asTrainerEdit(
                    _withStrengthDefaults(list[index].copyWith(isHold: hold)),
                  );
                }),
              ),
            ),
          ],
          const SizedBox(height: OnCareSpacing.s8),
          // 근력은 세트·횟수·중량을 한 줄에, 그 외 유형은 시간 한 칸으로
          // 잰다(#1029, #1310, #1489). 다른 편집 화면과 같은 compact 입력을
          // 쓴다 — 같은 운동을 화면마다 다른 칸으로 받으면 나가는 값도
          // 화면마다 달라진다.
          if (exercise.type == '근력')
            Row(
              children: <Widget>[
                Expanded(
                  child: RoutineSetsField(
                    key: ValueKey<String>(
                      'routine-sets-$_activeKeyPrefix-$index',
                    ),
                    keyPrefix: 'routine-sets-$_activeKeyPrefix-$index',
                    sets: exercise.sets > 0 ? exercise.sets : 3,
                    compact: true,
                    onChanged: (sets) => setState(() {
                      list[index] = _asTrainerEdit(
                        list[index].copyWith(sets: sets),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                // 버티는 운동은 `횟수` 자리를 `버티는 시간` 이 대신한다 —
                // 칸을 하나 더 두지 않고 바꿔 가며 쓴다(#1969).
                Expanded(
                  child: exercise.isHold
                      ? RoutineHoldSecondsField(
                          key: ValueKey<String>(
                            'routine-hold-$_activeKeyPrefix-$index',
                          ),
                          keyPrefix: 'routine-hold-$_activeKeyPrefix-$index',
                          holdSeconds: exercise.holdSeconds > 0
                              ? exercise.holdSeconds
                              : 60,
                          compact: true,
                          onChanged: (seconds) => setState(() {
                            list[index] = _asTrainerEdit(
                              list[index].copyWith(holdSeconds: seconds),
                            );
                          }),
                        )
                      : RoutineRepsField(
                          key: ValueKey<String>(
                            'routine-reps-$_activeKeyPrefix-$index',
                          ),
                          keyPrefix: 'routine-reps-$_activeKeyPrefix-$index',
                          reps: exercise.reps > 0 ? exercise.reps : 10,
                          compact: true,
                          onChanged: (reps) => setState(() {
                            list[index] = _asTrainerEdit(
                              list[index].copyWith(reps: reps),
                            );
                          }),
                        ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: RoutineWeightField(
                    key: ValueKey<String>(
                      'routine-weight-$_activeKeyPrefix-$index',
                    ),
                    keyPrefix: 'routine-weight-$_activeKeyPrefix-$index',
                    weight: exercise.weight,
                    compact: true,
                    onChanged: (weight) => setState(() {
                      list[index] = _asTrainerEdit(
                        list[index].copyWith(weight: weight),
                      );
                    }),
                  ),
                ),
              ],
            )
          else
            RoutineDurationField(
              key: ValueKey<String>('routine-duration-$index'),
              keyPrefix: 'routine-duration-$index',
              seconds: exercise.seconds,
              onChanged: (seconds) => setState(() {
                list[index] = _asTrainerEdit(
                  list[index].copyWith(durationSeconds: seconds),
                );
              }),
            ),
          if (_currentStep == _Step.personal) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            _personalEffectField(index),
          ],
        ],
      ),
    );
  }

  /// AI 가 이 운동을 고른 이유 — **트레이너만 보는 글이다.** (#2223, #2579)
  ///
  /// 운동 이름 바로 아래 부제처럼 문장만 둔다. 서버가 회원 기록 숫자(최근 2주
  /// 운동 시간·근력 비중·PT 뒤 며칠)로 쓴 판단 재료라, 근거 태그를 따로 달면
  /// 같은 말을 두 번 한다. `AI 추천 사유` 라벨도 두지 않는다 — 단계 머리의
  /// `AI 제안 N` 이 이 줄들이 AI 가 낸 것임을 말한다. 회원에게는 가지 않는다
  /// (회원 응답이 비운다, 회원 카드에는 효과 한 줄이 선다).
  Widget _aiRationale(int index) {
    final RoutineExercise exercise = _personal[index];
    if (exercise.reason.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: OnCareSpacing.s4),
      child: Text(
        exercise.reason,
        key: ValueKey<String>('personal-rationale-$index'),
        style: _text(OnCareTypography.bodySmall, OnCareColors.textSecondary),
      ),
    );
  }

  /// 한 번에 정할 수 있는 개인운동 수. 운동 하나가 배정 한 건(=프로그램 세션
  /// 하나)이 되므로 서버의 세션 상한과 같은 값이다.
  static const int _maxPersonalRoutines = 12;

  /// 단계 표시줄에 적을 이름들. 고른 종류에 따라 3칸·4칸이 된다. (#2223)
  List<String> _stepLabels(AppLocalizations l) => <String>[
    for (final step in _steps)
      switch (step) {
        _Step.conditions => l.aiStepConditions,
        _Step.program => l.aiStepReview,
        _Step.personal => l.aiStepPersonal,
        _Step.review => l.aiStepDone,
      },
  ];

  /// 개인운동 단계 — AI 제안을 받아 고치고, 빼고, 직접 더한다. (#2223)
  ///
  /// 없앤 `AI 개인운동 제안` 카드가 하던 일을 그대로 한다. 카드가 보여 주던
  /// 것(제안 개수·소개문·회원에게 갈 메모·근거 태그·빈 상태·오류)을 모두 여기서
  /// 보여 주고, 카드에는 없던 인라인 편집과 직접 추가가 더해진다. 카드에서
  /// `추천 안 함`(휴지통)이던 자리는 이 목록에서 빼는 일이고, 서버의 대기 중
  /// 제안도 함께 거절 처리한다 — 뺀 제안이 내일 다시 올라오지 않게.
  ///
  /// `개인운동만` 이면 이 칸이 마지막이라, 보낼 시작일·한마디까지 여기 붙는다.
  Widget _personalRoutineEditor() {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<List<RoutineSuggestion>> suggestions = ref.watch(
      routineSuggestionsProvider(widget.client.id),
    );
    // 제안이 늦게 도착하면 그때 한 번 채운다 — 트레이너가 이미 손댔으면
    // (_personalSeeded) 그대로 둔다.
    if (suggestions.hasValue && !suggestions.isLoading && !_personalSeeded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_seedPersonalFromSuggestions);
      });
    }
    // AI 제안에서 **온** 줄을 센다 — `source` 로 세면 트레이너가 한 줄만
    // 고쳐도(그때 출처가 트레이너가 된다) 지우지 않은 줄의 숫자가 줄고,
    // 세 줄을 다 고치면 배지와 안내 문장이 통째로 사라진다. 지운 줄은
    // [_personalOrigins] 에서도 함께 빠지므로 그때는 제대로 줄어든다.
    final int aiCount = _personalOrigins
        .take(_personal.length)
        .whereType<_PersonalOrigin>()
        .length;
    return Column(
      key: const ValueKey<String>('personal-routine-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(
          // `개인운동만` 은 붙을 PT 가 없다 — "PT 사이에 할" 이라고 하면
          // 방금 PT 를 건너뛴 트레이너에게 어긋난 말이 된다.
          title: _kind == ProgramKind.routineOnly
              ? l.aiPersonalStepTitleRoutineOnly
              : l.aiPersonalStepTitle,
          icon: AppIcons.ai,
          subtitle: _kind == ProgramKind.routineOnly
              ? l.aiPersonalStepBlurbRoutineOnly
              : l.aiPersonalStepBlurb,
          trailing: aiCount > 0
              ? AppTag(
                  key: const ValueKey<String>('personal-routine-badge'),
                  label: l.aiPersonalStepBadge(aiCount),
                  tone: AppTagTone.brand,
                )
              : null,
        ),
        if (aiCount > 0) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            l.aiPersonalStepIntro(widget.client.name),
            key: const ValueKey<String>('personal-routine-intro'),
            style: _text(OnCareTypography.caption, OnCareColors.textTertiary),
          ),
        ],
        const SizedBox(height: OnCareSpacing.s12),
        if (suggestions.isLoading && _personal.isEmpty)
          const AppLoading(placement: AppStatePlacement.card)
        else ...<Widget>[
          // 제안을 못 읽었다고 이 단계가 막히지는 않는다 — 직접 넣을 수 있다.
          if (suggestions.hasError && _personal.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
              child: Text(
                l.aiPersonalStepLoadFailed,
                key: const ValueKey<String>('personal-routine-error'),
                style: _text(
                  OnCareTypography.bodySmall,
                  OnCareColors.textSecondary,
                ),
              ),
            ),
          for (int index = 0; index < _personal.length; index++) ...<Widget>[
            if (_editingPersonal == index)
              _exerciseEditor(index)
            else
              _personalSummaryRow(index),
            const SizedBox(height: OnCareSpacing.s8),
          ],
          if (_personal.isEmpty && !suggestions.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
              child: Text(
                suggestions.hasValue
                    ? l.aiPersonalStepNoSuggestion
                    : l.aiPersonalStepEmpty,
                key: const ValueKey<String>('personal-routine-empty'),
                style: _text(
                  OnCareTypography.bodySmall,
                  OnCareColors.textSecondary,
                ),
              ),
            ),
        ],
        if (_showAddExercise)
          _addExerciseForm()
        else
          _addExerciseButton(
            key: const ValueKey<String>('show-add-personal-exercise-form'),
            // 운동 하나가 배정 한 건이 되므로 서버의 세션 상한을 넘길 수
            // 없다. 넘기기 전에 여기서 막는다 — 다 적은 뒤 422 로 되돌려
            // 받는 것보다 낫다.
            onPressed: _personal.length >= _maxPersonalRoutines
                ? null
                : () => setState(() => _showAddExercise = true),
          ),
        if (_personal.length >= _maxPersonalRoutines) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            l.aiPersonalStepFull(_maxPersonalRoutines),
            key: const ValueKey<String>('personal-routine-full'),
            style: _text(OnCareTypography.caption, OnCareColors.textSecondary),
          ),
        ],
      ],
    );
  }

  /// 접혀 있는 개인운동 한 줄 — 무엇을, 얼마나, 왜. (#2223)
  ///
  /// 없앤 `AI 개인운동 제안` 카드의 한 장과 같은 모양이다: 이름·유형·양을 한
  /// 줄에 두고 그 아래 회원에게 갈 메모와 근거를 붙인다. 고칠 때만 연필로
  /// 펼친다 — 줄마다 편집 칸이 늘 열려 있으면 목록을 훑을 수가 없다.
  Widget _personalSummaryRow(int index) {
    final AppLocalizations l = AppLocalizations.of(context);
    final RoutineExercise exercise = _personal[index];
    final TextStyle metaStyle = _text(
      OnCareTypography.strong(OnCareTypography.caption),
      OnCareColors.textTertiary,
    );
    return AppCard(
      key: ValueKey<String>('personal-routine-row-$index'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                // 이름 · 유형 · 양을 한 줄에 둔다 — 줄을 나누면 셋을 훑는 데
                // 시선이 세 번 움직인다.
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: exercise.name,
                        style: _text(
                          OnCareTypography.strong(OnCareTypography.bodySmall),
                          OnCareColors.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: ' · ',
                        style: _text(
                          OnCareTypography.caption,
                          OnCareColors.textTertiary,
                        ),
                      ),
                      TextSpan(
                        text: routineTypeLabel(l, exercise.type),
                        style: metaStyle,
                      ),
                      TextSpan(
                        text: ' · ',
                        style: _text(
                          OnCareTypography.caption,
                          OnCareColors.textTertiary,
                        ),
                      ),
                      TextSpan(
                        text: exercise.type == '근력'
                            ? _strengthSummary(l, exercise)
                            : formatExerciseDuration(l, exercise.seconds),
                        style: metaStyle,
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...<Widget>[
                const SizedBox(width: OnCareSpacing.s4),
                AppIconButton(
                  key: ValueKey<String>('personal-routine-edit-$index'),
                  icon: AppIcons.edit,
                  tooltip: l.actionEdit,
                  // 옆 삭제와 같은 회색이다 — 편집기 운동 줄의 연필도 회색이라
                  // 이 카드에서만 파랗게 튀지 않게 한다.
                  color: OnCareColors.textSecondary,
                  onPressed: () => setState(() => _editingPersonal = index),
                ),
                AppIconButton(
                  key: ValueKey<String>('personal-routine-remove-$index'),
                  icon: AppIcons.delete,
                  tooltip: l.aiPersonalDismissTooltip,
                  color: OnCareColors.textSecondary,
                  onPressed: () => unawaited(_confirmRemoveExerciseAt(index)),
                ),
              ],
            ],
          ),
          _aiRationale(index),
          const SizedBox(height: OnCareSpacing.s12),
          _personalEffectField(index),
        ],
      ),
    );
  }

  /// 회원에게 보일 효과 한 줄(#2570). 접힌 줄에서도 바로 고친다 — 자동
  /// 문구가 placeholder 로 보여 무엇이 갈지 알 수 있고, 바꾸고 싶을 때만
  /// 친다. 효과만 바꾼 것은 운동을 고친 것이 아니라 출처는 그대로 둔다.
  Widget _personalEffectField(int index) {
    final RoutineExercise exercise = _personal[index];
    return RoutineEffectField(
      keyPrefix: 'personal-routine-effect-$index',
      value: exercise.effect,
      autoEffect: autoRoutineEffect(exercise.type, widget.client.goal),
      onChanged: (String effect) => setState(() {
        _personal[index] = _personal[index].copyWith(effect: effect);
      }),
    );
  }

  Widget _addExerciseForm() {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSectionHeader(title: l.aiAddExerciseManually),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('new-exercise-name'),
            controller: _newExerciseName,
            label: l.progExerciseName,
            hint: l.aiExerciseNameExample,
            // 이름이 버티는 운동이면 `횟수` 칸이 `버티는 시간` 으로 바뀐다 —
            // 트레이너가 직접 고른 뒤에는 덮지 않는다(#1969).
            onChanged: (String name) {
              if (_newExerciseMeasureChosen) return;
              setState(
                () => _newExerciseIsHold = isIsometricExerciseName(name),
              );
            },
          ),
          const SizedBox(height: OnCareSpacing.s12),
          RoutineCategoryChips(
            keyPrefix: 'new-exercise-category',
            value: _newExerciseType,
            onChanged: (type) => setState(() => _newExerciseType = type),
          ),
          if (_newExerciseType == '근력') ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: RoutineMeasureToggle(
                keyPrefix: 'new-exercise-measure',
                isHold: _newExerciseIsHold,
                onChanged: (bool hold) => setState(() {
                  _newExerciseMeasureChosen = true;
                  _newExerciseIsHold = hold;
                }),
              ),
            ),
          ],
          const SizedBox(height: OnCareSpacing.s8),
          // 근력은 세트·횟수·중량을 한 줄에, 그 외 유형은 시간 한 칸으로
          // 잰다(#1029, #1310, #1489).
          if (_newExerciseType == '근력')
            Row(
              children: <Widget>[
                Expanded(
                  child: RoutineSetsField(
                    key: const ValueKey<String>('new-exercise-sets'),
                    keyPrefix: 'new-exercise-sets',
                    sets: _newExerciseSets,
                    compact: true,
                    onChanged: (sets) =>
                        setState(() => _newExerciseSets = sets),
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: _newExerciseIsHold
                      ? RoutineHoldSecondsField(
                          key: const ValueKey<String>('new-exercise-hold'),
                          keyPrefix: 'new-exercise-hold',
                          holdSeconds: _newExerciseHoldSeconds,
                          compact: true,
                          onChanged: (seconds) =>
                              setState(() => _newExerciseHoldSeconds = seconds),
                        )
                      : RoutineRepsField(
                          key: const ValueKey<String>('new-exercise-reps'),
                          keyPrefix: 'new-exercise-reps',
                          reps: _newExerciseReps,
                          compact: true,
                          onChanged: (reps) =>
                              setState(() => _newExerciseReps = reps),
                        ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: RoutineWeightField(
                    key: const ValueKey<String>('new-exercise-weight'),
                    keyPrefix: 'new-exercise-weight',
                    weight: _newExerciseWeight,
                    compact: true,
                    onChanged: (weight) =>
                        setState(() => _newExerciseWeight = weight),
                  ),
                ),
              ],
            )
          else
            RoutineDurationField(
              key: const ValueKey<String>('new-exercise-duration'),
              keyPrefix: 'new-exercise-duration',
              seconds: _newExerciseSeconds,
              onChanged: (seconds) => setState(() {
                _newExerciseSeconds = seconds;
              }),
            ),
          const SizedBox(height: OnCareSpacing.s12),
          AppButtonPair(
            cancelKey: const ValueKey<String>('hide-add-exercise-form'),
            cancelLabel: l.actionCancel,
            onCancel: () => setState(() => _showAddExercise = false),
            confirmKey: const ValueKey<String>('add-exercise-submit'),
            confirmLabel: l.aiRegister,
            onConfirm: _addExercise,
          ),
        ],
      ),
    );
  }

  Widget _trainerMemoField() {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppSectionHeader(title: l.schedNote),
          const SizedBox(height: OnCareSpacing.s8),
          AppTextField(
            key: const ValueKey<String>('final-trainer-memo'),
            controller: _trainerMemo,
            label: l.aiNoteForClient,
            hint: _analysisSuggestion(l),
            helper: l.schedNoteVisibleToMember,
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            l.aiNotePlaceholderHint,
            style: _text(OnCareTypography.caption, OnCareColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _reviewedRoutineList() {
    final AppLocalizations l = AppLocalizations.of(context);
    final Color brand = context.oncare.brand.primary;
    final optionName = _optionDisplayName(l, _selectedKey);
    final memo = _trainerMemo.text.trim();
    return Column(
      key: const ValueKey<String>('reviewed-routine-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(
          title: l.aiReviewedSuggestion(optionName),
          icon: AppIcons.checkCircle,
          subtitle: l.aiEditsApplied,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        // 줄 **사이**에만 간격을 둔다 — 끝에 남는 간격은 아래 진행 줄과의
        // 거리를 다른 단계보다 벌린다(#2476).
        for (final (int index, RoutineExercise exercise)
            in _edited.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: OnCareSpacing.s8),
          AppCard(
            child: Row(
              children: <Widget>[
                AppTag(
                  label: routineTypeLabel(l, exercise.type),
                  tone: AppTagTone.brand,
                ),
                const SizedBox(width: OnCareSpacing.s12),
                Expanded(
                  child: Text(
                    exercise.name,
                    style: _text(
                      OnCareTypography.strong(OnCareTypography.bodySmall),
                      OnCareColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  // 근력은 트레이너가 세트·횟수·중량으로 정했다 —
                  // 시간(minutes)은 그 경우 편집 화면에 아예 없어 값이 바뀌지
                  // 않으니, 요약도 같은 칸으로 보여줘야 방금 고친 값과
                  // 어긋나지 않는다.
                  exercise.type == '근력'
                      ? _strengthSummary(l, exercise)
                      : formatExerciseDuration(l, exercise.seconds),
                  style: _text(
                    OnCareTypography.strong(OnCareTypography.bodySmall),
                    brand,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (memo.isNotEmpty) const SizedBox(height: OnCareSpacing.s8),
        if (memo.isNotEmpty)
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const AppIcon(
                  AppIcons.note,
                  size: OnCareSize.iconMedium,
                  // 메모다. 주의가 아니므로 빨강으로 올리지 않는다(#690).
                  color: OnCareColors.cautionFill,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l.schedNote,
                        style: _text(
                          OnCareTypography.strong(OnCareTypography.caption),
                          OnCareColors.cautionFill,
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.s4),
                      Text(
                        memo,
                        style: _text(
                          OnCareTypography.bodySmall,
                          OnCareColors.textPrimary,
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
  }

  String _directionLabel(AppLocalizations l, ProgramDirection direction) =>
      switch (direction) {
        ProgramDirection.lowerIntensity => l.aiDirectionLower,
        ProgramDirection.moreCardio => l.aiDirectionCardio,
        ProgramDirection.lowerIntensityMoreCardio =>
          l.aiDirectionLowerAndCardio,
        ProgramDirection.keep => l.aiDirectionKeep,
        ProgramDirection.noData => l.aiDirectionNoData,
      };

  Widget _analysisRow(
    String label,
    String value, {
    bool warn = false,
    Key? key,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: _analysisLabelWidth,
            child: Text(
              label,
              style: _text(OnCareTypography.label, OnCareColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              // 네 줄짜리 카드다. 한 줄이 접히면 아래 생성 조건·버튼이 통째로
              // 밀리므로, 좁아지면 줄을 늘리는 대신 말줄임한다 (#1655).
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(
                OnCareTypography.strong(OnCareTypography.bodySmall),
                warn ? OnCareColors.danger : OnCareColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 근력 한 줄에 빠진 세트·횟수를 채운다.
///
/// AI 는 근력 운동을 분으로만 주기도 한다. 그때 편집기의 숫자 칸은 `3`·`10`
/// 을 보여 주면서 값은 0 으로 두었다 — 프로그램 검토가 `0세트 · 0회` 를 그리고,
/// 편집기로 넘어갈 때 또 다른 기본값이 붙어 **한 운동이 세 화면에서 다른
/// 숫자로 보였다**. 보이는 값을 그대로 저장해 셋을 하나로 맞춘다.
///
/// **중량은 채우지 않는다.** 맨몸이 기본이고, 들지도 않을 무게를 회원에게
/// 지시하게 된다 — `0kg` 은 트레이너가 적은 값이다(#1310).
RoutineExercise _withStrengthDefaults(RoutineExercise exercise) {
  if (exercise.type != '근력') return exercise;
  return exercise.copyWith(
    sets: exercise.sets > 0 ? exercise.sets : 3,
    reps: exercise.isHold || exercise.reps > 0 ? exercise.reps : 10,
    holdSeconds: exercise.isHold && exercise.holdSeconds <= 0
        ? 60
        : exercise.holdSeconds,
  );
}

/// 근력 한 줄의 요약 문구 — 세트 · 횟수 · 중량. (#1310)
///
/// 맨몸 운동(0kg)은 중량을 적지 않는다 — `3세트 · 15회`. (#2533)
///
/// 버티는 운동은 횟수 자리에 초가 선다 — `3세트 · 60초`. 한 세트를 두
/// 단위로 적지 않으므로 둘이 한 줄에 함께 서지 않는다. (#1969)
String _strengthSummary(AppLocalizations l, RoutineExercise exercise) =>
    <String>[
      l.progSetsValue(exercise.sets),
      if (exercise.isHold)
        l.progHoldValue(exercise.holdSeconds)
      else
        l.progRepsValue(exercise.reps),
      ?strengthWeightLabel(l, exercise.weight),
    ].join(' · ');

/// 후보 편집기의 운동 이름 칸.
///
/// 옛 `TextFormField(initialValue:)` 처럼 처음 값만 받아 자기 컨트롤러를 둔다 —
/// 입력마다 부모를 다시 그리지 않고 [onChanged] 로 값만 넘긴다. 부모가 이름이
/// 바뀐 뒤 다시 그려지면 Key 가 바뀌어 새 값으로 다시 만들어진다.
class _ExerciseNameField extends StatefulWidget {
  const _ExerciseNameField({
    required this.initialValue,
    required this.hint,
    required this.onChanged,
    super.key,
  });

  final String initialValue;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_ExerciseNameField> createState() => _ExerciseNameFieldState();
}

class _ExerciseNameFieldState extends State<_ExerciseNameField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: _controller,
      hint: widget.hint,
      onChanged: widget.onChanged,
    );
  }
}

class _RoutineChoice {
  const _RoutineChoice({
    required this.key,
    required this.label,
    required this.intensity,
    required this.exercises,
    required this.reason,
    this.basis = '',
    this.changes = const <String>[],
  });

  factory _RoutineChoice.fromPlan(RoutinePlan plan) {
    return _RoutineChoice(
      key: plan.key,
      label: plan.label,
      intensity: plan.intensity,
      exercises: plan.exercises,
      reason: plan.rationale,
      basis: plan.basis,
      changes: plan.changes,
    );
  }

  final String key;
  final String label;
  final String intensity;
  final List<RoutineExercise> exercises;
  final String reason;

  /// C안의 차례 근거와 바꾼 점(#3282). A·B안은 비어 있다.
  final String basis;
  final List<String> changes;
}

/// 진행 단계 — 번호 원 세 개를 옅은 회색 선이 잇고, 원 아래에 단계 이름.
///
/// 지금 단계의 원만 트레이너 남색으로 채우고 흰 굵은 번호를 쓴다. 나머지는
/// 옅은 회색 채움·얇은 테두리·회색 번호다. 첫 단계는 왼쪽 끝, 가운데 단계는
/// 가운데, 마지막 단계는 오른쪽 끝에 서고 이름도 같은 쪽으로 정렬한다.
/// 이미 지난 단계(원·이름)를 누르면 그 단계로 간다. 단계마다 Key 를 둔다.
/// 개인운동 줄이 어디서 왔나 — 그 AI 제안의 id. (#2223)
///
/// 뺄 때 서버에 거절을 알리는 데 쓴다. 직접 넣은 줄은 이 값이 없다. 근거
/// 코드는 사유 문장이 기록 숫자로 말하므로 따로 들고 있지 않는다(#2579).
class _PersonalOrigin {
  const _PersonalOrigin({required this.id});

  final String id;
}

/// The trainer↔member chat lines the generation was grounded on (#580).
///
/// Shown because the trainer is the one who has to trust the routine: if the
/// AI quietly ignored "무릎이 아파요", the only way to notice is to see which
/// utterances it was given. Lines arrive speaker-labelled from the server, so
/// this widget only handles layout.
///
/// 줄이 많으면 후보 비교가 아래로 밀려나므로 화면에는 `참고한 대화 N줄` 링크
/// 한 줄만 두고, 누르면 채팅처럼 말풍선 창으로 연다.
class _ChatEvidence extends StatelessWidget {
  const _ChatEvidence({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(
        key: const ValueKey<String>('ai-chat-evidence-open'),
        borderRadius: OnCareRadius.smAll,
        onTap: () => showAppDialog<void>(
          context: context,
          builder: (BuildContext context) => _ChatEvidenceDialog(lines: lines),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppIcon(AppIcons.chat, size: 16, color: tokens.brand.primary),
              const SizedBox(width: OnCareSpacing.s4),
              Text(
                l.aiChatEvidenceLink(lines.length),
                style: tokens
                    .text(OnCareTypography.label)
                    .copyWith(color: tokens.brand.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 참고한 대화를 채팅처럼 보여 주는 창 — 회원은 왼쪽, 트레이너는 오른쪽.
///
/// 서버가 줄마다 `트레이너: ` · `회원: ` 처럼 말한 사람을 붙여 보낸다. 그
/// 머리로 좌우를 가르고, 말풍선에는 머리를 뗀 본문만 적는다.
class _ChatEvidenceDialog extends StatelessWidget {
  const _ChatEvidenceDialog({required this.lines});

  final List<String> lines;

  static const List<String> _trainerPrefixes = <String>['트레이너', 'Trainer'];

  static (bool trainer, String text) _split(String line) {
    final int colon = line.indexOf(':');
    if (colon <= 0) return (false, line.trim());
    final String speaker = line.substring(0, colon).trim();
    return (
      _trainerPrefixes.contains(speaker),
      line.substring(colon + 1).trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppDialog(
      key: const ValueKey<String>('ai-chat-evidence-dialog'),
      title: l.aiChatEvidenceTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final String line in lines)
            Builder(
              builder: (BuildContext context) {
                final (bool trainer, String text) = _split(line);
                return Padding(
                  padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
                  child: Align(
                    alignment: trainer
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: trainer
                              ? tokens.brand.surface
                              : OnCareColors.surfaceInput,
                          borderRadius: OnCareRadius.mdAll,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: OnCareSpacing.s12,
                            vertical: OnCareSpacing.s8,
                          ),
                          child: Text(
                            text,
                            style: tokens
                                .text(OnCareTypography.bodySmall)
                                .copyWith(color: OnCareColors.textPrimary),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// States how much this generation actually reflects the member's own
/// history (#776) — so a thin-history member never reads as "personalized"
/// when the AI had nothing personal to go on, and a settled member sees
/// what pattern the candidates are grounded in.
class _RecommendationStatusBanner extends StatelessWidget {
  const _RecommendationStatusBanner({
    required this.analysis,
    required this.generatedBy,
    required this.trainerRequest,
    required this.minutes,
    required this.intensity,
    required this.minutesSetByTrainer,
    required this.intensitySetByTrainer,
    required this.findings,
  });

  final MemberAnalysis analysis;

  /// 서버가 알려 준 생성 방식(`rule` 이면 규칙 기반).
  final String generatedBy;

  /// 1단계에서 트레이너가 적은 요청. 비어 있으면 줄을 그리지 않는다.
  final String trainerRequest;

  /// 이번 생성의 총 시간·강도(`low`/`moderate`/`high`). 트레이너가 건드리지
  /// 않은 값은 서버가 기록에서 정한 값으로 채워져 있다(#776).
  final int minutes;
  final String intensity;

  /// 각 조건을 트레이너가 직접 정했는지 — 아니면 기록 기반 자동이다.
  final bool minutesSetByTrainer;
  final bool intensitySetByTrainer;

  /// 서버가 찾은 것과 반영 방향(#3280). 비어 있으면(옛 서버) 입력값 표만 둔다.
  final List<RoutineFinding> findings;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final (String title, String body) = switch (analysis.recommendationStatus) {
      RecommendationStatus.template => (
        l.aiStatusTemplateTitle,
        l.aiStatusTemplateBody,
      ),
      RecommendationStatus.learning => (
        l.aiStatusLearningTitle,
        l.aiStatusLearningBody,
      ),
      RecommendationStatus.personalized => (
        l.aiStatusPersonalizedTitle,
        l.aiStatusPersonalizedBody(
          analysis.historySessionCount,
          analysis.analysisPeriodDays,
        ),
      ),
    };
    final bool hasChat = analysis.recentMessages.isNotEmpty;
    final List<(String, String)> rows = <(String, String)>[
      (l.aiBasisGoalLabel, healthFocusGoalLabel(l, analysis.goal)),
      // 판단 결과가 있으면 완료율·반복 운동은 그 안(`평균 완료율` · `반복한
      // 운동`)에 근거와 함께 나온다 — 1단계 회원 현황과 세 번 겹치지 않게 뺀다.
      if (findings.isEmpty) ...<(String, String)>[
        (
          l.aiBasisCompletionLabel,
          l.aiBasisCompletionValue(analysis.avgCompletionRate),
        ),
        if (analysis.frequentExercises.isNotEmpty)
          (l.aiFrequentExercisesLabel, analysis.frequentExercises.join(', ')),
      ],
      // 후보의 총 시간·강도를 직접 정하는 값이라 1단계와 겹쳐도 근거로 둔다.
      (
        l.aiBasisConditionLabel,
        l.aiBasisConditionValue(
          // 총 시간은 후보가 넘지 않는 **상한**이다 — A안은 일부러 더 짧게
          // 짠다(#776). `총 30분` 이라 적으면 22분 후보가 조건을 어긴 듯 읽힌다.
          l.aiBasisConditionMax(minutes, switch (intensity) {
            'low' => l.intensityLight,
            'high' => l.intensityHigh,
            _ => l.intensityModerate,
          }),
          switch ((minutesSetByTrainer, intensitySetByTrainer)) {
            (true, true) => l.aiBasisConditionByTrainer,
            (false, false) => l.aiBasisConditionAuto,
            _ => l.aiBasisConditionMixed,
          },
        ),
      ),
      (
        l.aiBasisMethodLabel,
        generatedBy == 'rule' ? l.aiBasisMethodRule : l.aiBasisMethodAi,
      ),
      if (trainerRequest.isNotEmpty)
        (l.aiBasisRequestLabel, l.aiBasisRequestValue(trainerRequest)),
    ];
    // AI 가 이번 후보를 무엇에 기대 만들었는지 알리는 안내다 — 회색 상자로
    // 두면 입력 칸처럼 읽혔다(#2468).
    return SizedBox(
      width: double.infinity,
      child: AppBanner(
        title: title,
        message: body,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 찾은 것 → 반영 방향(#3280). 분석 박스가 회원 현황을 되풀이하지
            // 않고 **이번 판단**을 말하는 자리다.
            if (findings.isNotEmpty) ...<Widget>[
              Text(
                l.aiFindingsTitle,
                style: tokens
                    .text(OnCareTypography.label)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
              const SizedBox(height: OnCareSpacing.s4),
              for (final RoutineFinding f in findings)
                Padding(
                  key: ValueKey<String>('ai-finding-${f.kind}'),
                  padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: f.finding,
                              style: tokens
                                  .text(
                                    OnCareTypography.strong(
                                      OnCareTypography.bodySmall,
                                    ),
                                  )
                                  .copyWith(color: OnCareColors.textPrimary),
                            ),
                            TextSpan(
                              text: l.aiFindingSource(f.source),
                              style: tokens
                                  .text(OnCareTypography.bodySmall)
                                  .copyWith(color: OnCareColors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        l.aiFindingAction(f.action),
                        style: tokens
                            .text(OnCareTypography.bodySmall)
                            .copyWith(color: tokens.brand.primary),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: OnCareSpacing.s4),
            ],
            // 라벨 칸은 가장 긴 라벨에 맞춘다 — 숫자 너비를 박지 않는다.
            Table(
              columnWidths: const <int, TableColumnWidth>{
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
              },
              children: <TableRow>[
                for (final (String label, String value) in rows)
                  TableRow(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: OnCareSpacing.s12,
                          bottom: OnCareSpacing.s2,
                        ),
                        child: Text(
                          label,
                          style: tokens
                              .text(OnCareTypography.bodySmall)
                              .copyWith(color: OnCareColors.textSecondary),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: OnCareSpacing.s2,
                        ),
                        child: Text(
                          value,
                          style: tokens
                              .text(
                                OnCareTypography.strong(
                                  OnCareTypography.bodySmall,
                                ),
                              )
                              .copyWith(color: OnCareColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            // 규칙형도 최근 대화를 읽는다(#1440) — 통증 부위를 찾아 그 부위에
            // 부담이 큰 동작을 빼므로, 대화를 참고했다고 말하는 것이 사실이다
            // (#2674).
            if (hasChat) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s4),
              _ChatEvidence(lines: analysis.recentMessages),
            ],
          ],
        ),
      ),
    );
  }
}
