import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

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
  final ValueChanged<List<RoutineExercise>>? onReviewCompleted;

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

  @override
  void dispose() {
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
      _edited.add(
        RoutineExercise(
          name: name,
          minutes: _newExerciseMinutes,
          type: _newExerciseType,
          sets: isStrength ? _newExerciseSets : 0,
          reps: isStrength ? _newExerciseReps : 0,
          weight: isStrength ? _newExerciseWeight : 0,
        ),
      );
      _newExerciseName.clear();
      _newExerciseType = '근력';
      _newExerciseMinutes = 30;
      _newExerciseSets = 3;
      _newExerciseReps = 10;
      _newExerciseWeight = 20;
      _showAddExercise = false;
    });
  }

  void _completeReview() {
    if (_edited.isEmpty) {
      final AppLocalizations l = AppLocalizations.of(context);
      showAppToast(context, l.aiKeepOneExercise);
      return;
    }
    setState(() {
      _stage = 2;
      _maxReachedStage = 2;
      _showAddExercise = false;
    });
    _scrollToTop();
  }

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
    widget.onReviewCompleted?.call(List<RoutineExercise>.unmodifiable(_edited));
    showAppToast(context, l.aiAppliedToTemplate, type: AppToastType.success);
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
          onStageTap: _goToStage,
        ),
      ),
      const SizedBox(height: OnCareSpacing.s16),
      if (_stage == 0) ...<Widget>[
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
          onTap: _generate,
        ),
      ] else if (_stage == 1) ...<Widget>[
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
          onTap: _completeReview,
        ),
      ] else ...<Widget>[
        _reviewedRoutineList(),
        const SizedBox(height: OnCareSpacing.s16),
        _reviewActions(),
      ],
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

  /// 후보 카드를 나란히 둘 때 한 장의 최소 폭.
  static const double _minOptionCardWidth = OnCareLayout.sidebarWidth;

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
        for (final String exercise in entry.exercises)
          if (exercise.trim().endsWith('✓'))
            exercise.trim().substring(0, exercise.trim().length - 1).trim(),
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

  Widget _exerciseEditor(int index) {
    final AppLocalizations l = AppLocalizations.of(context);
    final exercise = _edited[index];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: RoutineCategoryChips(
                  keyPrefix: 'routine-category-$_selectedKey-$index',
                  value: exercise.type,
                  onChanged: (type) => setState(() {
                    _edited[index] = exercise.copyWith(type: type);
                  }),
                ),
              ),
              AppIconButton(
                icon: Icons.close_rounded,
                tooltip: l.progDeleteExercise,
                color: OnCareColors.textTertiary,
                onPressed: () => setState(() => _edited.removeAt(index)),
              ),
            ],
          ),
          SizedBox(
            key: ValueKey<String>('routine-category-name-gap-$index'),
            height: OnCareSpacing.s12,
          ),
          _ExerciseNameField(
            key: ValueKey<String>(
              'routine-name-$_selectedKey-$index-${exercise.name}',
            ),
            initialValue: exercise.name,
            hint: l.progExerciseName,
            onChanged: (name) {
              _edited[index] = _edited[index].copyWith(name: name);
            },
          ),
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
                    key: ValueKey<String>('routine-sets-$_selectedKey-$index'),
                    keyPrefix: 'routine-sets-$_selectedKey-$index',
                    sets: exercise.sets > 0 ? exercise.sets : 3,
                    compact: true,
                    onChanged: (sets) => setState(() {
                      _edited[index] = _edited[index].copyWith(sets: sets);
                    }),
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: RoutineRepsField(
                    key: ValueKey<String>('routine-reps-$_selectedKey-$index'),
                    keyPrefix: 'routine-reps-$_selectedKey-$index',
                    reps: exercise.reps > 0 ? exercise.reps : 10,
                    compact: true,
                    onChanged: (reps) => setState(() {
                      _edited[index] = _edited[index].copyWith(reps: reps);
                    }),
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: RoutineWeightField(
                    key: ValueKey<String>(
                      'routine-weight-$_selectedKey-$index',
                    ),
                    keyPrefix: 'routine-weight-$_selectedKey-$index',
                    weight: exercise.weight,
                    compact: true,
                    onChanged: (weight) => setState(() {
                      _edited[index] = _edited[index].copyWith(weight: weight);
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
                _edited[index] = _edited[index].copyWith(minutes: minutes);
              }),
            ),
        ],
      ),
    );
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
          ),
          const SizedBox(height: OnCareSpacing.s12),
          RoutineCategoryChips(
            keyPrefix: 'new-exercise-category',
            value: _newExerciseType,
            onChanged: (type) => setState(() => _newExerciseType = type),
          ),
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
                  child: RoutineRepsField(
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
          // 취소 버튼에 테스트가 찾는 Key 가 있어 AppButtonPair 대신 같은 모양을
          // Row 로 만든다.
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  key: const ValueKey<String>('hide-add-exercise-form'),
                  label: l.actionCancel,
                  onPressed: () => setState(() => _showAddExercise = false),
                  variant: AppButtonVariant.secondary,
                  fullWidth: true,
                ),
              ),
              const SizedBox(width: OnCareSpacing.buttonGap),
              Expanded(
                child: AppButton(
                  label: l.aiRegister,
                  onPressed: _addExercise,
                  fullWidth: true,
                ),
              ),
            ],
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

  /// 3단계의 유일한 동작 — **고객에게 바로 전송하지 않는다**. 확정한 구성을
  /// 2열의 `프로그램 정보` 박스에 반영만 하고, 실제 전송은 그 박스를 확인·
  /// 수정한 뒤 프로그램 탭의 단일 `보내기`(최종 검토)에서 이뤄진다.
  Widget _reviewActions() {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppButton(
      key: const ValueKey<String>('apply-routine-to-template'),
      label: l.aiApplyToTemplate,
      onPressed: _applyToTemplate,
      size: OnCareButtonSize.large,
      leadingIcon: Icons.playlist_add_check_rounded,
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
    required VoidCallback onTap,
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
String _strengthSummary(AppLocalizations l, RoutineExercise exercise) {
  final double w = exercise.weight;
  final String weight = w == w.roundToDouble() ? '${w.round()}' : '$w';
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

/// 진행 단계 — [AppStepIndicator] 막대 + 단계마다 이름.
///
/// 세 이름을 모두 보여 주고(어느 단계로 되돌아갈 수 있는지 읽히게), 이미 지난
/// 단계의 이름·막대를 누르면 그 단계로 간다. 이름 칸에 단계별 Key 를 둔다.
class _ProgressStepper extends StatelessWidget {
  const _ProgressStepper({
    required this.stage,
    required this.maxReachedStage,
    required this.onStageTap,
  });

  final int stage;
  final int maxReachedStage;
  final ValueChanged<int> onStageTap;

  /// 단계 이름. 로케일을 따르므로 const 로 둘 수 없다. (#501)
  static List<String> _steps(AppLocalizations l) => <String>[
    l.aiStepConditions,
    l.aiStepReview,
    l.aiStepDone,
  ];

  void _tap(int index) {
    if (index <= maxReachedStage) onStageTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final List<String> steps = _steps(l);
    return Semantics(
      label: l.aiStepperLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppStepIndicator(
            count: steps.length,
            current: stage,
            onStepTap: _tap,
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Row(
            children: <Widget>[
              for (int index = 0; index < steps.length; index++) ...<Widget>[
                if (index > 0) const SizedBox(width: OnCareSpacing.s4),
                Expanded(
                  child: InkWell(
                    key: ValueKey<String>('routine-stage-$index'),
                    borderRadius: OnCareRadius.smAll,
                    onTap: index <= maxReachedStage ? () => _tap(index) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: OnCareSpacing.s4,
                      ),
                      child: Text(
                        steps[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens
                            .text(
                              index == stage
                                  ? OnCareTypography.strong(
                                      OnCareTypography.caption,
                                    )
                                  : OnCareTypography.caption,
                            )
                            .copyWith(
                              color: index == stage
                                  ? tokens.brand.primary
                                  : index <= maxReachedStage
                                  ? OnCareColors.textPrimary
                                  : OnCareColors.textTertiary,
                            ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
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
