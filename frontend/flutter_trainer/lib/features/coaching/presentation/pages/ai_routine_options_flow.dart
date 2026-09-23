import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이번에 짜는 프로그램이 어떤 것인가. (#2223)
///
/// **트레이너가 고르는 값이 아니다** — 조건 설정에서 `PT 없이 개인운동만 짜기`
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

  /// 최종 검토.
  review,
}

/// Conversation-style AI routine builder.
///
/// The assistant stays inside the AI routine tab when [embedded] is true.
/// After generation, A/B and the existing recommendation are presented in a
/// horizontal rail; selecting a card updates the common editor below it.
class AiRoutineOptionsFlow extends ConsumerStatefulWidget {
  const AiRoutineOptionsFlow({
    required this.client,
    this.embedded = false,
    this.recommendedExercises = const <RoutineExercise>[],
    this.recommendedReason = '',
    this.onReviewCompleted,
    this.onManualCreate,
    super.key,
  });

  final TrainerClient client;
  final bool embedded;
  final List<RoutineExercise> recommendedExercises;
  final String recommendedReason;
  /// 위저드를 빠져나가는 유일한 출구 — 확정한 PT 구성과 그 PT 에 붙일
  /// 개인운동을 함께 넘긴다(#2223). `개인운동만` 모드는 위저드가 직접 보내므로
  /// 이 콜백을 부르지 않는다.
  final void Function(
    List<RoutineExercise> program,
    List<RoutineExercise> personalRoutines,
  )?
  onReviewCompleted;

  /// AI 단계를 종료하고 빈 프로그램 편집기로 전환한다.
  final VoidCallback? onManualCreate;

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

  /// `RoutineOptionsRequest.trainer_note` 의 서버 상한(#1028). 여기서 막으면
  /// 긴 요청이 422 왕복 없이 그 자리에서 잘린다.
  static const int _promptMaxLength = 500;

  int _minutes = 30;
  String _intensity = 'moderate';
  String _newExerciseType = '근력';
  int _newExerciseMinutes = 30;
  // 근력만 세트·횟수·중량을 받는다(#1029, #1310) — 그 외 유형은
  // [_newExerciseMinutes] 를 그대로 쓴다.
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

  /// `개인운동만` 전송의 시작일 — 기본은 오늘이다. (#2223)
  DateTime _startDate = todayKst();

  /// `개인운동만` 전송에 붙이는 회원에게 한마디(선택).
  final TextEditingController _memberMessage = TextEditingController();

  bool _sendingRoutineOnly = false;

  /// `개인운동만` 을 이미 보냈는가 — 두 번 눌러 같은 운동이 두 벌 가지 않게
  /// 버튼을 잠근다(프로그램 전송의 `_sent` 와 같은 규칙).
  bool _routineOnlySent = false;

  /// 이 전송 시도의 멱등키. 실패해 다시 누를 때 같은 키를 다시 보내야 중복
  /// 배정이 막힌다(#581) — 내용이 바뀌지 않는 한 새로 만들지 않는다.
  String? _routineOnlyRequestId;

  /// 고른 종류에서 실제로 밟는 단계들. 화면·표시줄·이동이 모두 이 목록을 본다.
  List<_Step> get _steps => _kind == ProgramKind.routineOnly
      ? const <_Step>[_Step.conditions, _Step.personal, _Step.review]
      : const <_Step>[
          _Step.conditions,
          _Step.program,
          _Step.review,
          _Step.personal,
        ];

  _Step get _currentStep => _steps[_stage];

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
    _prompt.dispose();
    _trainerMemo.dispose();
    _newExerciseName.dispose();
    _memberMessage.dispose();
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
    return '${l.aiReasonGoal(client.goal, client.lastRoutine)} '
        '$sodium';
  }

  List<_RoutineChoice> _choicesOf(AppLocalizations l) {
    final options = _options;
    if (options == null) return const <_RoutineChoice>[];
    return <_RoutineChoice>[
      _RoutineChoice.fromPlan(options.planA),
      _RoutineChoice.fromPlan(options.planB),
      if (widget.recommendedExercises.isNotEmpty)
        _RoutineChoice(
          // key 는 화면 문구가 아니라 선택 식별자다('A'/'B' 와 같은 층).
          // 번역하면 _selectedKey 비교가 로케일마다 달라져 선택이 깨진다. (#501)
          key: _recommendedKey,
          label: l.aiTagExisting,
          intensity: l.aiTagCustom,
          exercises: widget.recommendedExercises,
          reason: widget.recommendedReason.isEmpty
              ? l.aiExistingBlurb
              : widget.recommendedReason,
        ),
    ];
  }

  /// 기존 추천 후보의 선택 식별자. 'A'/'B' 와 같은 층의 값이라 번역하지 않는다.
  static const String _recommendedKey = 'recommended';

  String _optionDisplayName(AppLocalizations l, String key) => switch (key) {
    'A' => l.aiOptionRecovery,
    'B' => l.aiOptionPush,
    _ => l.aiOptionExisting,
  };

  Future<void> _generate() async {
    if (_generating) return;
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
          );
      if (!mounted) return;
      final analysis = options.analysis;
      setState(() {
        _options = options;
        _selectedKey = 'A';
        _edited = List<RoutineExercise>.of(options.planA.exercises);
        _showAddExercise = false;
        _stage = 1;
        _maxReachedStage = 1;
        // 후보가 새로 만들어졌다 — 멱등키를 무효로 만든다(내용이 달라졌다).
        _routineOnlyRequestId = null;
        // 트레이너가 아직 건드리지 않은 조건만 서버가 실제로 쓴 값(또는
        // 기본값)으로 채운다 — 트레이너가 시간만 고쳤다면 강도는 그대로
        // 서버가 계산하도록 둬야 하고, 그 반대도 마찬가지다(#776).
        if (!_minutesTouched) {
          _minutes = analysis.suggestedAvailableMinutes ?? _minutes;
        }
        if (!_intensityTouched) {
          _intensity = analysis.suggestedIntensity ?? _intensity;
        }
      });
      _scrollToTop();
    } catch (e) {
      if (!mounted) return;
      final AppLocalizations l = AppLocalizations.of(context);
      // 한도 초과는 고장이 아니라 잠시 뒤 되는 상태다. 다른 오류와 같은 문구를
      // 쓰면 트레이너가 기능이 깨진 것으로 읽는다(#582).
      showAppToast(
        context,
        e is RateLimitedError ? l.aiGenerateRateLimited : l.aiGenerateFailed,
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _selectChoice(_RoutineChoice choice) {
    setState(() {
      _selectedKey = choice.key;
      _edited = List<RoutineExercise>.of(choice.exercises);
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
          minutes: _newExerciseMinutes,
          type: _newExerciseType,
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
      _newExerciseMinutes = 30;
      _newExerciseSets = 3;
      _newExerciseReps = 10;
      _newExerciseHoldSeconds = 60;
      _newExerciseIsHold = false;
      _newExerciseMeasureChosen = false;
      _newExerciseWeight = 20;
      _showAddExercise = false;
    });
  }

  /// 한 단계 앞으로. 되돌아온 뒤 다시 나아갈 때도 같은 자리를 쓴다.
  void _advance() {
    setState(() {
      _stage += 1;
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
        if (_kind == ProgramKind.routineOnly) {
          unawaited(_sendRoutineOnly());
          return;
        }
        // PT 모드의 최종 검토 다음은 개인운동 단계다.
        _seedPersonalFromSuggestions();
        _advance();
      case _Step.personal:
        if (_personal.isEmpty) {
          showAppToast(context, l.aiKeepOnePersonalRoutine);
          return;
        }
        if (_kind == ProgramKind.routineOnly) {
          _advance();
          return;
        }
        _applyToTemplate();
    }
  }

  /// PT 프로그램 짜기를 건너뛰고 개인운동만 짠다. (#2223)
  ///
  /// 회원이 미리 "이번 주는 PT 를 못 한다"고 말한 주다. 단계가 3칸(조건 설정 →
  /// 개인운동 → 최종 검토)으로 줄고, 붙일 PT 일정이 없으므로 최종 검토에서
  /// 곧바로 회원에게 보낸다. 후보 생성은 부르지 않는다 — 쓰지 않을 PT 프로그램을
  /// 만드느라 기다릴 이유가 없다.
  void _skipPtProgram() {
    if (_generating) return;
    setState(() {
      _kind = ProgramKind.routineOnly;
      _stage = 0;
      _maxReachedStage = 0;
      _showAddExercise = false;
    });
    _seedPersonalFromSuggestions();
    _advance();
  }

  /// AI 개인운동 제안(대기 중)을 개인운동 목록의 출발점으로 삼는다. (#2223)
  ///
  /// 없애는 `AI 개인운동 제안` 카드가 보여 주던 바로 그 목록이다 — 개인운동을
  /// 보내는 입구를 이 단계 하나로 모으면서, 카드에 걸려 있던 제안도 여기로
  /// 들어온다. 한 번만 채운다: 다시 채우면 트레이너가 지운 제안이 되살아난다.
  void _seedPersonalFromSuggestions() {
    if (_personalSeeded) return;
    _personalSeeded = true;
    final suggestions = ref
        .read(routineSuggestionsProvider(widget.client.id))
        .valueOrNull;
    if (suggestions == null || suggestions.isEmpty) return;
    setState(() {
      _personal = <RoutineExercise>[
        for (final s in suggestions) _exerciseOfSuggestion(s),
      ];
    });
  }

  RoutineExercise _exerciseOfSuggestion(RoutineSuggestion s) => RoutineExercise(
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
  );

  void _goToStage(int stage) {
    if (stage > _maxReachedStage || stage == _stage) return;
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

  /// 최종 검토에서 확정한 구성을 **바로 고객에게 보내지 않고**, 2열의
  /// (지금은 비어 있는) `프로그램 정보` 박스로만 반영한다.
  ///
  /// 실제 전송은 프로그램 탭 편집기의 단일 `보내기` 버튼에서만 일어난다 —
  /// 여기서는 서버를 호출하지 않는다. 반영은
  /// [CoachingPage]가 넘겨준 [AiRoutineOptionsFlow.onReviewCompleted] 콜백을
  /// 통해 편집기의 `aiSuggestions` 로 흘러가고, 편집기가 그 값이 바뀔 때마다
  /// 세션 1에 병합한다(`ProgramEditorWorkspace.didUpdateWidget`).
  void _applyToTemplate() {
    final AppLocalizations l = AppLocalizations.of(context);
    if (_edited.isEmpty) {
      showAppToast(context, l.aiKeepOneExercise);
      return;
    }
    widget.onReviewCompleted?.call(
      List<RoutineExercise>.unmodifiable(_edited),
      List<RoutineExercise>.unmodifiable(_personal),
    );
    showAppToast(context, l.aiAppliedToTemplate, type: AppToastType.success);
  }

  /// `개인운동만` 을 회원에게 **바로** 보낸다. (#2223)
  ///
  /// PT 모드와 달리 붙일 일정이 없으므로 편집기를 거치지 않는다 — 이 위저드가
  /// 배정 API 를 직접 부르는 유일한 자리다. 한 묶음으로 배정해 이력이 "이번
  /// 전송"을 한 덩어리로 읽을 수 있게 하고(`delivery_kind: routine_only`),
  /// 고른 시작일과 회원에게 한마디를 함께 싣는다.
  Future<void> _sendRoutineOnly() async {
    if (_sendingRoutineOnly || _routineOnlySent) return;
    final AppLocalizations l = AppLocalizations.of(context);
    if (_personal.isEmpty) {
      showAppToast(context, l.aiKeepOnePersonalRoutine);
      return;
    }
    // 실패 후 재시도는 **같은 키**를 다시 보내야 중복 배정이 막힌다(#581).
    final requestId =
        _routineOnlyRequestId ??= 'routine-only-'
            '${widget.client.id}-'
            '${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _sendingRoutineOnly = true);
    try {
      await ref
          .read(trainerRoutineRepositoryProvider)
          .assignProgram(widget.client.id, <String, Object?>{
            'name': l.aiRoutineOnlyProgramName,
            'sessions': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'routine-only',
                'name': '',
                'exercises': <Map<String, Object?>>[
                  for (final e in _personal) _personalExerciseToJson(e),
                ],
              },
            ],
            'delivery_kind': 'routine_only',
            'trainer_message': _memberMessage.text.trim(),
            'start_date': _ymd(_startDate),
            'client_request_id': requestId,
          });
    } catch (error) {
      if (!mounted) return;
      setState(() => _sendingRoutineOnly = false);
      showAppToast(context, l.aiRoutineOnlySendFailed, type: AppToastType.error);
      return;
    }
    if (!mounted) return;
    setState(() {
      _sendingRoutineOnly = false;
      _routineOnlySent = true;
    });
    showAppToast(context, l.aiRoutineOnlySent, type: AppToastType.success);
  }

  /// 개인운동 한 줄 → 프로그램 세션의 운동 항목. 서버가 세션을 루틴으로 접을
  /// 때 쓰는 모양과 같다(`ProgramDraftExercise`).
  Map<String, Object?> _personalExerciseToJson(RoutineExercise e) {
    final bool strength = e.type == '근력';
    return <String, Object?>{
      'id': 'personal-${e.name.hashCode}',
      'name': e.name,
      'type': e.type,
      'duration': strength ? 0 : e.minutes,
      'sets': strength ? e.sets : 0,
      // 한 세트를 회로든 초로든 한 번만 잰다(#1969).
      'reps': strength && !e.isHold ? e.reps : 0,
      'hold_seconds': strength && e.isHold ? e.holdSeconds : 0,
      'weight': strength ? e.weight : 0,
      'source': e.source,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final content = <Widget>[
      if (widget.onManualCreate != null) ...<Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            key: const ValueKey<String>('ai-manual-create'),
            label: l.aiManualCreate,
            onPressed: widget.onManualCreate,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
            leadingIcon: Icons.edit_note_rounded,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
      ],
      KeyedSubtree(
        key: _topKey,
        child: _ProgressStepper(
          stage: _stage,
          maxReachedStage: _maxReachedStage,
          labels: _stepLabels(l),
          onStageTap: _goToStage,
        ),
      ),
      const SizedBox(height: OnCareSpacing.s16),
      ...switch (_currentStep) {
        _Step.conditions => <Widget>[
          _assistantAnalysis(),
          const SizedBox(height: OnCareSpacing.s16),
          _promptField(),
          const SizedBox(height: OnCareSpacing.s16),
          _directionControls(),
          const SizedBox(height: OnCareSpacing.s16),
          _primaryButton(
            key: const ValueKey<String>('generate-routine-options'),
            label: _generating ? l.aiAnalysing : _generateButtonLabel(l),
            icon: Icons.auto_awesome_rounded,
            busy: _generating,
            onTap: _next,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          // 이번 주는 PT 가 없는 회원 — PT 프로그램 짜기를 통째로 건너뛰고
          // 개인운동만 짜서 바로 보낸다(#2223). 후보 생성을 거치지 않으므로
          // 기다릴 일도, 쓰지 않을 후보를 만들 일도 없다.
          Align(
            child: AppButton(
              key: const ValueKey<String>('skip-pt-program'),
              label: l.aiSkipPtProgram,
              onPressed: _generating ? null : _skipPtProgram,
              variant: AppButtonVariant.text,
              size: OnCareButtonSize.small,
              leadingIcon: Icons.directions_run_rounded,
            ),
          ),
        ],
        _Step.program => <Widget>[
          _generatedOptions(),
          const SizedBox(height: OnCareSpacing.sectionGap),
          _routineEditor(),
          const SizedBox(height: OnCareSpacing.s16),
          _trainerMemoField(),
          const SizedBox(height: OnCareSpacing.sectionGap),
          _primaryButton(
            key: const ValueKey<String>('complete-routine-review'),
            label: l.aiReviewDone,
            icon: Icons.fact_check_rounded,
            onTap: _next,
          ),
        ],
        _Step.personal => <Widget>[
          _personalRoutineEditor(),
          const SizedBox(height: OnCareSpacing.sectionGap),
          _primaryButton(
            key: const ValueKey<String>('complete-personal-routines'),
            label: _kind == ProgramKind.routineOnly
                ? l.aiPersonalStepNext
                : l.aiApplyToTemplate,
            icon: _kind == ProgramKind.routineOnly
                ? Icons.fact_check_rounded
                : Icons.playlist_add_check_rounded,
            onTap: _next,
          ),
        ],
        _Step.review => <Widget>[
          if (_kind == ProgramKind.routineOnly) ...<Widget>[
            _routineOnlyReview(),
            const SizedBox(height: OnCareSpacing.s16),
            _primaryButton(
              key: const ValueKey<String>('send-routine-only'),
              label: _routineOnlySent
                  ? l.aiRoutineOnlySentLabel
                  : l.aiRoutineOnlySend,
              icon: Icons.send_rounded,
              busy: _sendingRoutineOnly,
              onTap: _routineOnlySent ? null : _next,
            ),
          ] else ...<Widget>[
            _reviewedRoutineList(),
            const SizedBox(height: OnCareSpacing.s16),
            _reviewActions(),
          ],
        ],
      },
      const SizedBox(height: OnCareSpacing.s32),
    ];

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: content,
      );
    }

    return Scaffold(
      backgroundColor: OnCareColors.surfacePage,
      appBar: AppTopBar(
        title: l.aiRoutineFor(widget.client.name),
        // 옛 AppBar 의 자동 뒤로가기와 같게 — 돌아갈 경로가 있을 때만 단다.
        showBack: Navigator.canPop(context),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(context.oncare.density.pagePadding),
          children: content,
        ),
      ),
    );
  }

  /// 분석 박스 오른쪽 칸(최근 감지 메모)의 **고정 높이**(#1655).
  ///
  /// 메모가 늘어도 카드가 아래로 자라면 안 된다 — 프로그램 탭은 이 박스 아래에
  /// 생성 조건과 버튼을 두고 있어, 박스가 자랄 때마다 트레이너가 누르던 자리가
  /// 밀린다. 왼쪽 네 줄과 같은 키를 못 박고, 넘치는 메모는 칸 안에서 스크롤한다.
  static const double _analysisPanelHeight =
      OnCareSpacing.s48 + OnCareSpacing.s48;

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
        _analysisRow(l.aiGoal, client.goal),
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
          '${client.sodiumMg}mg'
          '${client.sodiumOverBudget ? l.aiOverTarget : ''}'
          '${client.sodiumOverDays > 0 ? l.aiSodiumOverDaysSuffix(client.sodiumOverDays) : ''}'
          '${client.sugarOverBudget ? l.aiSugarAlsoOver : ''}',
          warn: client.sodiumOverBudget || client.sugarOverBudget,
        ),
      ],
    );
    // AI 가 읽은 자료 박스는 옅은 브랜드 채움·브랜드 테두리로 다른 카드와 구분한다.
    return AppCard(
      key: const ValueKey<String>('ai-analysis-card'),
      selected: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _AssistantLabel(text: l.aiAnalysedData),
          const SizedBox(height: OnCareSpacing.s12),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget memos = _chatInsightMemoPanel();
              if (constraints.maxWidth < _analysisSplitWidth) {
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
  /// 모양은 [AppBanner] 의 `danger` 톤(8% 채움·40% 테두리·반경 12·안쪽 12)과
  /// 같다. 다만 고정 높이 안에서 메모 목록을 스크롤해야 해(#1655) 제목·본문
  /// 두 칸뿐인 [AppBanner] 를 그대로 쓰지 못한다.
  Widget _chatInsightMemoPanel() {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<List<TrainerMemo>> memos = ref.watch(
      trainerMemosProvider(widget.client.id),
    );
    return Container(
      key: const ValueKey<String>('ai-chat-insight-memos'),
      height: _analysisPanelHeight,
      padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
      decoration: BoxDecoration(
        color: OnCareColors.onWhite(OnCareColors.danger, OnCareAlpha.subtle),
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(
          color: OnCareColors.onWhite(OnCareColors.danger, OnCareAlpha.strong),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.warning_amber_rounded,
                size: OnCareSize.iconSmall,
                color: OnCareColors.danger,
              ),
              const SizedBox(width: OnCareSpacing.s4),
              Expanded(
                child: Text(
                  l.aiInsightMemoTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    OnCareTypography.strong(OnCareTypography.caption),
                    OnCareColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s4),
          // 메모를 못 읽어도 이 칸만 조용히 비운다 — 생성 버튼까지 막으면
          // 참고 자료 하나 때문에 프로그램을 못 만든다 (#1655).
          Expanded(
            child: memos.when(
              loading: () =>
                  const AppLoading(placement: AppStatePlacement.card),
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
        ],
      ),
    );
  }

  Widget _insightMemoNote(String text) => Text(
    text,
    style: _text(OnCareTypography.caption, OnCareColors.textSecondary),
  );

  /// `08.31  무릎 불편감이 …` — 날짜와 요약을 한 줄에 둔다.
  Widget _insightMemoLine(TrainerMemo memo) {
    final DateTime date = _kstDateOf(memo.createdAt);
    final String day =
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.day.toString().padLeft(2, '0')}';
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
          Text(
            l.aiPromptTitle,
            style: _text(OnCareTypography.titleSmall, OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            l.aiPromptBlurb,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _text(OnCareTypography.caption, OnCareColors.textSecondary),
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
          Text(
            l.aiGenerateConditions,
            style: _text(OnCareTypography.titleSmall, OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            l.aiConditionsAutoHint,
            style: _text(OnCareTypography.caption, OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          RoutineMinutesField(
            key: const ValueKey<String>('generation-minutes'),
            keyPrefix: 'generation-minutes',
            minutes: _minutes,
            label: l.routineFieldTotalMinutes,
            onChanged: (minutes) => setState(() {
              _minutes = minutes;
              _minutesTouched = true;
            }),
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

  /// 데모(`USE_MOCK_API=true`)에서는 목표 기반 기본 추천 상태를 내보이지 않는다.
  /// (#1028)
  ///
  /// 데모 회원은 축적된 운동 기록이 아예 없어 생성기가 늘
  /// [RecommendationStatus.template] 을 돌려준다 — 그래서 데모를 열면 언제나
  /// `목표 기반 루틴 생성`·`목표 기반 기본 추천`만 보였고, 정작 보여 줘야 할
  /// **데이터 기반 맞춤 흐름**이 화면에 한 번도 나오지 않았다. 실 API 모드는
  /// 그대로다 — 기록이 적은 실제 회원에게는 그 사실을 계속 말해야 한다.
  bool get _hideTemplateState => ref.watch(appConfigProvider).useMockApi;

  /// Only known after the first generation — before that we haven't seen
  /// the member's analysis yet, so the button stays generic (#776).
  String _generateButtonLabel(AppLocalizations l) {
    final status = _options?.analysis.recommendationStatus;
    return status == RecommendationStatus.template && !_hideTemplateState
        ? l.aiGenerateGoalBased
        : l.aiGenerateCandidates;
  }

  Widget _generatedOptions() {
    final AppLocalizations l = AppLocalizations.of(context);
    final options = _options!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _AssistantLabel(text: l.aiCompareCandidates),
        const SizedBox(height: OnCareSpacing.s8),
        // 데모에서는 목표 기반 기본 추천 안내를 띄우지 않는다 —
        // [_hideTemplateState] 참고.
        if (!(_hideTemplateState &&
            options.analysis.recommendationStatus ==
                RecommendationStatus.template)) ...<Widget>[
          _RecommendationStatusBanner(analysis: options.analysis),
          const SizedBox(height: OnCareSpacing.s8),
        ],
        Text(
          l.aiBasisGoalCompletion(
                options.analysis.goal,
                options.analysis.avgCompletionRate,
              ) +
              (options.generatedBy == 'rule' ? l.aiBasisRuleBased : ''),
          style: _text(OnCareTypography.caption, OnCareColors.textSecondary),
        ),
        // 1단계에서 트레이너가 직접 적은 요청이 있으면 그대로 덧붙인다 —
        // 이 화면이 "무엇을 근거로" 만들어졌는지 트레이너 자신의 조건까지
        // 보여준다. 새 상태가 아니라 이미 있는 [_prompt] 를 그대로 읽는다.
        if (_prompt.text.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            l.aiBasisTrainerRequest(_prompt.text.trim()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _text(
              OnCareTypography.caption,
              OnCareColors.textSecondary,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
        ],
        // Only when the AI actually generated these plans. The rule-based
        // fallback ignores chat entirely, so showing "참고한 최근 대화" next to a
        // rule plan would claim an input that was never used — the trainer
        // would think a knee complaint was accounted for when it wasn't.
        if (options.generatedBy == 'ai' &&
            options.analysis.recentMessages.isNotEmpty) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s4),
          _ChatEvidence(lines: options.analysis.recentMessages),
        ],
        const SizedBox(height: OnCareSpacing.s12),
        LayoutBuilder(
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
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: OnCareSize.iconMedium,
                color: selected ? brand : OnCareColors.textSecondary,
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
            l.aiTotalAndIntensity(total, choice.intensity),
            style: _text(OnCareTypography.label, brand),
          ),
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
        Text(
          l.aiEditOption(optionName),
          style: _text(OnCareTypography.titleSmall, OnCareColors.textPrimary),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        Text(
          l.aiEditBlurb,
          style: _text(OnCareTypography.caption, OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        for (int index = 0; index < _edited.length; index++) ...<Widget>[
          _exerciseEditor(index),
          const SizedBox(height: OnCareSpacing.s8),
        ],
        if (_showAddExercise)
          _addExerciseForm()
        else
          AppButton(
            key: const ValueKey<String>('show-add-exercise-form'),
            label: l.aiAddExerciseManually,
            onPressed: () => setState(() => _showAddExercise = true),
            variant: AppButtonVariant.secondary,
            leadingIcon: Icons.add_rounded,
            fullWidth: true,
          ),
      ],
    );
  }

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
                  onChanged: (type) => setState(() {
                    list[index] = exercise.copyWith(type: type);
                  }),
                ),
              ),
              AppIconButton(
                icon: Icons.close_rounded,
                tooltip: l.progDeleteExercise,
                color: OnCareColors.textTertiary,
                onPressed: () => setState(() => list.removeAt(index)),
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
              list[index] = list[index].copyWith(
                name: name,
                isHold: _activeMeasureChosen.contains(index)
                    ? null
                    : isIsometricExerciseName(name),
              );
            },
          ),
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
                  list[index] = list[index].copyWith(isHold: hold);
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
                    key: ValueKey<String>('routine-sets-$_activeKeyPrefix-$index'),
                    keyPrefix: 'routine-sets-$_activeKeyPrefix-$index',
                    sets: exercise.sets > 0 ? exercise.sets : 3,
                    compact: true,
                    onChanged: (sets) => setState(() {
                      list[index] = list[index].copyWith(sets: sets);
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
                            list[index] = list[index].copyWith(
                              holdSeconds: seconds,
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
                            list[index] = list[index].copyWith(reps: reps);
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
                      list[index] = list[index].copyWith(weight: weight);
                    }),
                  ),
                ),
              ],
            )
          else
            RoutineMinutesField(
              key: ValueKey<String>('routine-minutes-$index'),
              keyPrefix: 'routine-minutes-$index',
              minutes: exercise.minutes,
              compact: true,
              onChanged: (minutes) => setState(() {
                list[index] = list[index].copyWith(minutes: minutes);
              }),
            ),
        ],
      ),
    );
  }

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

  /// 개인운동 단계 — AI 제안을 받아 고치고, 지우고, 직접 더한다. (#2223)
  ///
  /// 제안은 없애는 `AI 개인운동 제안` 카드가 읽던 그 목록이다. 아직 오지
  /// 않았거나 하나도 없으면 빈 채로 시작하고, 트레이너가 직접 넣는다 — 제안이
  /// 없다고 이 단계를 건너뛰지는 않는다.
  Widget _personalRoutineEditor() {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<List<RoutineSuggestion>> suggestions = ref.watch(
      routineSuggestionsProvider(widget.client.id),
    );
    // 제안이 늦게 도착하면 그때 한 번 채운다 — 트레이너가 이미 손댔으면
    // (_personalSeeded) 그대로 둔다.
    if (suggestions.hasValue && !_personalSeeded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_seedPersonalFromSuggestions);
      });
    }
    return Column(
      key: const ValueKey<String>('personal-routine-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _AssistantLabel(
          // `개인운동만` 은 붙을 PT 가 없다 — "PT 사이에 할" 이라고 말하면
          // 방금 "이번엔 PT 가 없어요" 를 고른 트레이너에게 어긋난 말이 된다.
          text: _kind == ProgramKind.routineOnly
              ? l.aiPersonalStepTitleRoutineOnly
              : l.aiPersonalStepTitle,
        ),
        const SizedBox(height: OnCareSpacing.s4),
        Text(
          _kind == ProgramKind.routineOnly
              ? l.aiPersonalStepBlurbRoutineOnly
              : l.aiPersonalStepBlurb,
          style: _text(OnCareTypography.caption, OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        if (suggestions.isLoading && _personal.isEmpty)
          const AppLoading(placement: AppStatePlacement.card)
        else ...<Widget>[
          for (int index = 0; index < _personal.length; index++) ...<Widget>[
            _exerciseEditor(index),
            const SizedBox(height: OnCareSpacing.s8),
          ],
          if (_personal.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
              child: Text(
                l.aiPersonalStepEmpty,
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
          AppButton(
            key: const ValueKey<String>('show-add-personal-exercise-form'),
            label: l.aiAddExerciseManually,
            onPressed: () => setState(() => _showAddExercise = true),
            variant: AppButtonVariant.secondary,
            leadingIcon: Icons.add_rounded,
            fullWidth: true,
          ),
      ],
    );
  }

  /// `개인운동만` 의 최종 검토 — 보낼 목록·시작일·회원에게 한마디. (#2223)
  ///
  /// 붙일 PT 일정이 없으므로 여기서 바로 회원에게 간다. 편집기를 거치는 PT
  /// 모드와 달리, 이 화면의 버튼이 곧 전송이다.
  Widget _routineOnlyReview() {
    final AppLocalizations l = AppLocalizations.of(context);
    final Color brand = context.oncare.brand.primary;
    return Column(
      key: const ValueKey<String>('routine-only-review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              Icons.check_circle_rounded,
              size: OnCareSize.iconMedium,
              color: OnCareColors.success,
            ),
            const SizedBox(width: OnCareSpacing.s8),
            Expanded(
              child: Text(
                l.aiRoutineOnlyReviewTitle,
                style: _text(
                  OnCareTypography.titleSmall,
                  OnCareColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        for (final exercise in _personal) ...<Widget>[
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
                  exercise.type == '근력'
                      ? _strengthSummary(l, exercise)
                      : l.minutesShort(exercise.minutes),
                  style: _text(
                    OnCareTypography.strong(OnCareTypography.bodySmall),
                    brand,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l.aiRoutineOnlyStartDate,
                style: _text(
                  OnCareTypography.titleSmall,
                  OnCareColors.textPrimary,
                ),
              ),
              const SizedBox(height: OnCareSpacing.s8),
              AppButton(
                key: const ValueKey<String>('routine-only-start-date'),
                label: _ymd(_startDate),
                onPressed: _pickStartDate,
                variant: AppButtonVariant.secondary,
                leadingIcon: Icons.event_rounded,
              ),
              const SizedBox(height: OnCareSpacing.s16),
              AppTextField(
                key: const ValueKey<String>('routine-only-member-message'),
                controller: _memberMessage,
                label: l.aiRoutineOnlyMessage,
                hint: l.aiRoutineOnlyMessageHint,
                minLines: 2,
                maxLines: 3,
                maxLength: _memberMessageMaxLength,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 날짜 한 줄(YYYY-MM-DD) — 서버가 받는 모양이고 화면에도 그대로 쓴다.
  String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// 서버 `trainer_message` 의 상한. 여기서 막으면 422 왕복이 없다.
  static const int _memberMessageMaxLength = 200;

  Future<void> _pickStartDate() async {
    final DateTime now = todayKst();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      // 지난 날로는 보내지 않는다 — 이미 지난 날의 운동을 새로 시키는 일은 없다.
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = picked;
      // 보낼 내용이 달라졌다 — 멱등키를 새로 만든다.
      _routineOnlyRequestId = null;
    });
  }

  Widget _addExerciseForm() {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l.aiAddExerciseManually,
            style: _text(OnCareTypography.titleSmall, OnCareColors.textPrimary),
          ),
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
              setState(() => _newExerciseIsHold = isIsometricExerciseName(name));
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
                          onChanged: (seconds) => setState(
                            () => _newExerciseHoldSeconds = seconds,
                          ),
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
            RoutineMinutesField(
              key: const ValueKey<String>('new-exercise-minutes'),
              minutes: _newExerciseMinutes,
              compact: true,
              onChanged: (minutes) => setState(() {
                _newExerciseMinutes = minutes;
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
          Text(
            l.schedNote,
            style: _text(OnCareTypography.titleSmall, OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          AppTextField(
            key: const ValueKey<String>('final-trainer-memo'),
            controller: _trainerMemo,
            label: l.aiNoteForClient,
            hint: _analysisSuggestion(l),
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
        Row(
          children: <Widget>[
            const Icon(
              Icons.check_circle_rounded,
              size: OnCareSize.iconMedium,
              color: OnCareColors.success,
            ),
            const SizedBox(width: OnCareSpacing.s8),
            Expanded(
              child: Text(
                l.aiReviewedSuggestion(optionName),
                style: _text(
                  OnCareTypography.titleSmall,
                  OnCareColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s4),
        Text(
          l.aiEditsApplied,
          style: _text(OnCareTypography.caption, OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        for (final exercise in _edited) ...<Widget>[
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
                      : l.minutesShort(exercise.minutes),
                  style: _text(
                    OnCareTypography.strong(OnCareTypography.bodySmall),
                    brand,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
        ],
        if (memo.isNotEmpty)
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.sticky_note_2_rounded,
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

  /// PT 모드 최종 검토의 유일한 동작 — 개인운동 단계로 넘어간다. (#2223)
  ///
  /// **여기서는 아직 아무것도 반영하지 않는다.** 위저드를 빠져나가는 출구는
  /// 다음 단계(개인운동)의 `프로그램에 반영` 하나뿐이고, 그때 PT 구성과
  /// 개인운동이 **함께** 편집기로 간다. 전송은 그 뒤 편집기의 `일정 추가` 다.
  Widget _reviewActions() {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppButton(
      key: const ValueKey<String>('apply-routine-to-template'),
      label: l.aiGoToPersonalStep,
      onPressed: _next,
      size: OnCareButtonSize.large,
      leadingIcon: Icons.directions_run_rounded,
      fullWidth: true,
    );
  }

  Widget _analysisRow(String label, String value, {bool warn = false}) {
    return Padding(
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

  Widget _primaryButton({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return AppButton(
      key: key,
      label: label,
      onPressed: onTap,
      size: OnCareButtonSize.large,
      leadingIcon: icon,
      // 처리 중이면 스피너를 두고 탭을 막는다([_generate] 도 중복 호출을 막는다).
      loading: busy,
      fullWidth: true,
    );
  }
}

/// 근력 한 줄의 요약 문구 — 세트 × 횟수 · 중량. (#1310)
///
/// 맨몸 운동은 `0kg` 이다 — 중량 칸을 비울 수 없으므로 0 도 트레이너가 적은
/// 값이다.
///
/// 버티는 운동은 횟수 자리에 초가 선다 — `3세트 · 60초 · 0kg`. 한 세트를 두
/// 단위로 적지 않으므로 둘이 한 줄에 함께 서지 않는다. (#1969)
String _strengthSummary(AppLocalizations l, RoutineExercise exercise) {
  final double w = exercise.weight;
  final String weight = w == w.roundToDouble() ? '${w.round()}' : '$w';
  if (exercise.isHold) {
    return l.aiHoldSummary(exercise.sets, exercise.holdSeconds, weight);
  }
  return l.aiStrengthSummary(exercise.sets, exercise.reps, weight);
}

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
  });

  factory _RoutineChoice.fromPlan(RoutinePlan plan) {
    return _RoutineChoice(
      key: plan.key,
      label: plan.label,
      intensity: plan.intensity,
      exercises: plan.exercises,
      reason: plan.rationale,
    );
  }

  final String key;
  final String label;
  final String intensity;
  final List<RoutineExercise> exercises;
  final String reason;
}

/// 진행 단계 — 번호 원 세 개를 옅은 회색 선이 잇고, 원 아래에 단계 이름.
///
/// 지금 단계의 원만 트레이너 남색으로 채우고 흰 굵은 번호를 쓴다. 나머지는
/// 옅은 회색 채움·얇은 테두리·회색 번호다. 첫 단계는 왼쪽 끝, 가운데 단계는
/// 가운데, 마지막 단계는 오른쪽 끝에 서고 이름도 같은 쪽으로 정렬한다.
/// 이미 지난 단계(원·이름)를 누르면 그 단계로 간다. 단계마다 Key 를 둔다.
class _ProgressStepper extends StatelessWidget {
  const _ProgressStepper({
    required this.stage,
    required this.maxReachedStage,
    required this.labels,
    required this.onStageTap,
  });

  final int stage;
  final int maxReachedStage;

  /// 밟는 단계의 이름들. 프로그램 종류에 따라 3칸·4칸이다(#2223) — 표시줄은
  /// 몇 칸인지 스스로 정하지 않고 받은 만큼만 그린다.
  final List<String> labels;

  final ValueChanged<int> onStageTap;

  /// 번호 원의 지름.
  static const double _circle = OnCareSize.avatarMedium;

  /// 원 하나가 차지하는 칸의 폭 — 원 지름 + 원 사이 간격. (#2219)
  ///
  /// 칸 폭이 곧 **원 중심 사이의 거리**다. 예전에는 [Expanded] 로 화면 폭을
  /// n등분해서, 창이 넓어질수록 원들이 좌우 끝으로 멀어졌다. 단계 표시는
  /// 화면을 채우는 물건이 아니라 "몇 걸음 중 몇 번째"를 읽는 작은 눈금이라,
  /// 폭과 무관하게 같은 간격으로 모여 가운데에 선다.
  ///
  /// 라벨도 이 폭 안에서 한 줄로 말줄임된다 — 칸이 겹치지 않으니 라벨끼리
  /// 겹칠 일도 없다. 간격 토큰의 최대값(48)만으로는 원들이 서로 붙어 보여,
  /// 두 칸(48 + 16)을 더해 눈에 띄게 띄운다.
  static const double _stepWidth =
      _circle + OnCareSpacing.s48 + OnCareSpacing.s16;

  void _tap(int index) {
    if (index <= maxReachedStage) onStageTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final List<String> steps = labels;
    return Semantics(
      label: l.aiStepperLabel,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 칸을 다 늘어놓을 폭이 없으면(아주 좁은 창) 그만큼 좁힌다 —
          // 고정 간격을 지키느라 표시줄이 화면 밖으로 넘치지는 않는다.
          final double available = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : _stepWidth * steps.length;
          final double stepWidth = math.min(
            _stepWidth,
            available / steps.length,
          );
          final double totalWidth = stepWidth * steps.length;
          return Center(
            child: SizedBox(
              width: totalWidth,
              child: Stack(
                children: <Widget>[
                  // 첫 원의 가운데에서 마지막 원의 가운데까지만 잇는 가는 선 —
                  // 원이 모인 만큼만 그려진다. 원이 불투명해 선은 원 사이에서만
                  // 보인다.
                  Positioned(
                    top: (_circle - OnCareSize.hairline) / 2,
                    left: stepWidth / 2,
                    right: stepWidth / 2,
                    child: const ColoredBox(
                      color: OnCareColors.lineSubtle,
                      child: SizedBox(height: OnCareSize.hairline),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (int index = 0; index < steps.length; index++)
                        SizedBox(
                          width: stepWidth,
                          child: _step(tokens, steps[index], index),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _step(OnCareTokens tokens, String label, int index) {
    final bool current = index == stage;
    // 칸마다 같은 폭을 쓰므로 원도 라벨도 그 칸 가운데에 선다(#2219) — 예전에는
    // 첫 칸을 왼쪽 끝, 마지막 칸을 오른쪽 끝에 붙여 화면 폭을 가로질렀다.
    return InkWell(
      key: ValueKey<String>('routine-stage-$index'),
      borderRadius: OnCareRadius.smAll,
      onTap: index <= maxReachedStage ? () => _tap(index) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: _circle,
            height: _circle,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: current ? tokens.brand.primary : OnCareColors.surfaceInput,
              border: current
                  ? null
                  : Border.all(color: OnCareColors.lineStrong),
            ),
            child: Text(
              '${index + 1}',
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.label))
                  .copyWith(
                    color: current
                        ? OnCareColors.textOnFill
                        : OnCareColors.textSecondary,
                  ),
            ),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: tokens
                .text(
                  current
                      ? OnCareTypography.strong(OnCareTypography.caption)
                      : OnCareTypography.caption,
                )
                .copyWith(
                  color: current
                      ? OnCareColors.textPrimary
                      : OnCareColors.textTertiary,
                ),
          ),
        ],
      ),
    );
  }
}

/// AI 가 말하는 구획의 제목 — AI 아이콘 + `titleSmall`.
class _AssistantLabel extends StatelessWidget {
  const _AssistantLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppSectionHeader(title: text, icon: Icons.auto_awesome_rounded);
  }
}

/// The trainer↔member chat lines the generation was grounded on (#580).
///
/// Shown because the trainer is the one who has to trust the routine: if the
/// AI quietly ignored "무릎이 아파요", the only way to notice is to see which
/// utterances it was given. Lines arrive speaker-labelled from the server, so
/// this widget only handles layout.
class _ChatEvidence extends StatelessWidget {
  const _ChatEvidence({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(OnCareSpacing.s8),
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceInput,
        borderRadius: OnCareRadius.smAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.aiChatEvidenceTitle,
            style: tokens
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          for (final String line in lines)
            Padding(
              padding: const EdgeInsets.only(top: OnCareSpacing.s2),
              child: Text(
                line,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
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
  const _RecommendationStatusBanner({required this.analysis});

  final MemberAnalysis analysis;

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(OnCareSpacing.s8),
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceInput,
        borderRadius: OnCareRadius.smAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: tokens
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s2),
          Text(
            body,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          if (analysis.frequentExercises.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              '${l.aiFrequentExercisesLabel}: '
              '${analysis.frequentExercises.join(', ')}',
              style: tokens
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}
