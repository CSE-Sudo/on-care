import 'dart:async';

import 'package:flutter/material.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/ai_routine_item.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/time_range_picker_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Rich local draft editor matching the Figma program workspace.
///
/// Multi-session persistence remains unsupported. A one-session draft can be
/// handed to the existing flat routine boundary through the supplied actions.
///
/// **이 편집기는 회원에게 직접 API 를 부르지 않는다.** 실제 확인창·배정·PT
/// 등록은 전부 [onSend] 콜백을 통해 호출부(`CoachingPage`)가 한다 — 이
/// 위젯은 트리거(버튼)와 보낼 값(초안·등록일·등록시각)만 쥐고 있다. 그래서
/// 이 파일에는 repository 호출이 하나도 없다.
/// 세션 유형을 모를 때 쓰는 운동 기본 유형.
const String _kDefaultExerciseType = '근력';

class ProgramEditorWorkspace extends StatefulWidget {
  const ProgramEditorWorkspace({
    super.key,
    required this.clientGoal,
    required this.aiSuggestions,
    required this.onSend,
    required this.registerDate,
    required this.onRegisterDateChanged,
    required this.registerStartTime,
    required this.registerEndTime,
    required this.onRegisterTimeRangeChanged,
    this.template,
    this.templateRevision = 0,
    this.initialDraft,
    this.onSave,
    this.saving = false,
    this.sending = false,
  });

  final String clientGoal;
  final List<AiRoutineItem> aiSuggestions;
  final ProgramTemplate? template;
  final int templateRevision;

  /// 지금 구성을 실제로 보낸다 — 확인 다이얼로그를 띄우고, 확인되면 배정과
  /// PT 일정 등록까지 호출부가 순서대로 처리한다. 이 위젯은 트리거만 한다.
  final ValueChanged<ProgramEditorState> onSend;

  /// PT 스케줄에 등록할 날짜 — `일정 추가` 로 고른다. 기본값(오늘)은
  /// 호출부가 들고 있다.
  final DateTime registerDate;
  final ValueChanged<DateTime> onRegisterDateChanged;

  /// PT 스케줄에 등록할 시작·종료 시각. 기본값은 호출부가 들고
  /// 있고, 범위 선택기에서 두 값을 함께 바꾼다.
  final TimeOfDay registerStartTime;
  final TimeOfDay registerEndTime;
  final ValueChanged<TimeRangeValue> onRegisterTimeRangeChanged;

  /// A saved draft to open instead of starting from the client's goal.
  ///
  /// AI suggestions are **not** appended on top of it — the saved draft is
  /// what the trainer decided on, and re-adding proposals they already
  /// accepted or dropped would quietly change their work (#708).
  final ProgramEditorState? initialDraft;

  /// Saves the current draft. Null when saving isn't wired up.
  ///
  /// Resolves to whether the save actually succeeded — the header's bookmark
  /// button uses this (and only this) to flip from outline to filled.
  final Future<bool> Function(ProgramEditorState draft)? onSave;

  /// A save is in flight — the button locks so a second click can't create
  /// a duplicate draft.
  final bool saving;

  /// 전송(배정+PT 등록)이 진행 중이거나 막 끝났다 — `일정 추가` 버튼이
  /// 잠겨 두 번째 클릭이 두 번째 전송을 만들지 않는다.
  final bool sending;

  @override
  State<ProgramEditorWorkspace> createState() => _ProgramEditorWorkspaceState();
}

class _ProgramEditorWorkspaceState extends State<ProgramEditorWorkspace> {
  late ProgramEditorState _draft;
  var _initialized = false;
  var _editingProgramInfo = false;

  /// 이번 편집기 세션에서 템플릿 저장을 한 번이라도 성공했는가 — 북마크
  /// 아이콘을 outline↔filled 로 바꾸는 데만 쓴다. 저장은 누를 때마다 새
  /// 템플릿을 만드는 동작이라(#1028) "저장 취소"는 없고, 한 번 채워지면
  /// 이 편집기가 다시 열리기 전까지는 그대로 둔다.
  var _templateSaved = false;
  final TextEditingController _programName = TextEditingController();
  String? _addingToSession;
  final TextEditingController _exerciseName = TextEditingController();
  String _newExerciseType = _kDefaultExerciseType;

  /// 세션을 만들 때 고른 유형. **서버에 저장하지 않는다**(#2222) — 유형은
  /// 지금처럼 운동별(`ProgramDraftExercise.type`)로만 저장되고, 이 값은 그
  /// 세션에서 운동을 새로 넣을 때 쓰는 화면 기본값일 뿐이다. 그래서 불러온
  /// 프로그램에는 비어 있고, 그때는 [_kDefaultExerciseType] 로 떨어진다.
  final Map<String, String> _sessionType = <String, String>{};

  /// `세션 추가` 메뉴를 띄울 자리를 잡기 위한 앵커.
  final GlobalKey _addSessionKey = GlobalKey();
  // [ProgramExerciseDraft] 의 기본값과 맞춘다. 세트·중량은 근력일 때만,
  // 시간은 그 외 유형일 때만 보인다(#1029, #1276) — 유형이 무엇을 재는
  // 운동인지가 다르기 때문이다.
  //
  // 운동별 날짜 입력은 없다(#1483) — 트레이너가 등록할 실제 일정 날짜는
  // 이 아래 [widget.registerDate] 하나뿐이고, 새 운동은 그 값을 그대로
  // 물려받는다. 두 군데서 날짜를 고르게 하면 서로 어긋날 수 있다.
  int _newExerciseSets = 3;
  int _newExerciseReps = 10;
  double _newExerciseWeight = 20;
  int _newExerciseMinutes = 30;
  String _newExerciseIntensity = 'moderate';
  var _nextId = 2;

  bool get _hasValidRegisterTimeRange =>
      _minutes(widget.registerEndTime) > _minutes(widget.registerStartTime);

  int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;

  /// 고른 등록 날짜가 이미 지났는가 — 화면을 연 채 자정을 넘긴 경우다(#1582).
  /// 누르는 순간의 재검증은 호출부가 한 번 더 한다.
  bool get _registerDateIsPast => widget.registerDate.isBefore(_todayDate());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final l = AppLocalizations.of(context);
    final saved = widget.initialDraft;
    if (saved != null) {
      _draft = saved;
      _nextId =
          saved.sessions.fold<int>(
            0,
            (count, session) => count + session.exercises.length,
          ) +
          2;
    } else {
      // AI 루틴을 생성하기 전에는 임의의 추천 내용으로 채우지 않는다 — 프로그램
      // 정보 박스는 빈 상태로 시작하고, 이후 "템플릿에 반영"(AI 루틴 생성
      // 플로우) 또는 아래 AI 힌트 배너의 "편집기에 반영"을 눌러야만 채워진다.
      _draft = ProgramEditorState.initial(
        clientGoal: widget.clientGoal,
        programName: l.programEditorDefaultName(widget.clientGoal),
        sessionName: l.programEditorDefaultSession,
      );
    }
    _initialized = true;
  }

  @override
  void dispose() {
    _programName.dispose();
    _exerciseName.dispose();
    super.dispose();
  }

  /// 프로그램 이름 편집 UI — 카드 제목 자리에서 직접 뜬다. 깃허브 이슈/PR
  /// 제목처럼: 평소엔 이름 옆에 연필 아이콘만 있고, 누르면 그 자리가 입력칸
  /// 으로 바뀐다. 저장/취소 버튼은 옆의 카드 헤더 오른쪽(평소 `저장`/`검토
  /// 하기` 버튼이 있는 자리)으로 옮겨 보여준다(`_headerActions`) — 입력칸
  /// 아래에 따로 두면 카드 폭이 좁을 때 버튼이 다음 줄로 밀렸다. 목표·기간·
  /// 메모까지 담던 예전 `_ProgramInfo` 는 실제 배정·PT 등록 payload 가
  /// 읽지 않아 뺐고(#1029), 이름만 남았다.
  Widget _programNameTitle(AppLocalizations l) {
    if (!_editingProgramInfo) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(
              _draft.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.oncare
                  .text(OnCareTypography.titleSmall)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          AppIconButton(
            key: const ValueKey<String>('program-info-edit'),
            tooltip: l.actionEdit,
            onPressed: () => setState(() {
              _programName.text = _draft.name;
              _editingProgramInfo = true;
            }),
            icon: Icons.edit_rounded,
            color: OnCareColors.textTertiary,
          ),
        ],
      );
    }

    return AppTextField(
      key: const ValueKey<String>('program-name-inline-field'),
      controller: _programName,
      autofocus: true,
      onSubmitted: (_) => _saveProgramName(),
    );
  }

  void _saveProgramName() {
    final value = _programName.text.trim();
    setState(() {
      if (value.isNotEmpty) {
        _update(_draft.copyWith(name: value));
      }
      _editingProgramInfo = false;
    });
  }

  /// 카드 헤더 오른쪽 자리 — 평소엔 저장(북마크), 이름을 고치는 동안에는
  /// 그 자리를 그대로 `취소`/`저장`으로 바꿔 쓴다. `일정 추가`는 여기
  /// 없다 — 박스 하단으로 옮겼다(`build`).
  Widget _headerActions(AppLocalizations l) {
    if (_editingProgramInfo) {
      return Wrap(
        spacing: OnCareSpacing.buttonGap,
        children: <Widget>[
          AppButton(
            key: const ValueKey<String>('program-info-cancel'),
            label: l.actionCancel,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
            onPressed: () => setState(() => _editingProgramInfo = false),
          ),
          AppButton(
            key: const ValueKey<String>('program-info-save'),
            label: l.actionSave,
            size: OnCareButtonSize.small,
            onPressed: _saveProgramName,
          ),
        ],
      );
    }
    final canSave = widget.onSave != null && _draft.name.trim().isNotEmpty;
    // `보내기`는 이제 헤더가 아니라 박스 하단(footer)에 있다 — 여기 남는
    // 것은 저장(북마크) 하나뿐이다.
    //
    // 텍스트 버튼이던 `저장`을 북마크 아이콘 하나로 줄였다 — 저장 함수·API
    // 호출·중복 저장 방지(`widget.saving`)는 그대로, 채워진 아이콘
    // (`_templateSaved`)만 이 저장이 실제로 성공했음을 보여준다. 저장은
    // 여전히 누를 때마다 새 템플릿을 만드는 동작이라 "저장 취소"에 대응하는
    // outline 복귀는 없다.
    return AppIconButton(
      key: const ValueKey<String>('program-editor-save'),
      tooltip: !canSave
          ? l.programEditorSaveUnsupported
          : widget.saving
          ? l.progSaving
          : l.programEditorSaveTemplate,
      onPressed: canSave && !widget.saving ? _handleSaveTemplate : null,
      icon: _templateSaved
          ? Icons.bookmark_rounded
          : Icons.bookmark_border_rounded,
      color: _templateSaved
          ? context.oncare.brand.primary
          : OnCareColors.textTertiary,
    );
  }

  /// 기존 저장 함수(`widget.onSave`)를 그대로 부르고, 성공했을 때만 북마크
  /// 아이콘을 채운다 — 새 저장 로직이 아니라 반환값(성공 여부)을 아이콘
  /// 상태에 반영하는 얇은 래퍼다.
  Future<void> _handleSaveTemplate() async {
    final saved = await widget.onSave!(_draft);
    if (!mounted || !saved) return;
    setState(() => _templateSaved = true);
  }

  @override
  void didUpdateWidget(ProgramEditorWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_initialized) return;
    // A reopened draft is not topped up with proposals — see [initialDraft].
    if (widget.initialDraft == null &&
        widget.aiSuggestions != oldWidget.aiSuggestions) {
      _appendAiSuggestions(widget.aiSuggestions);
    }
    if (widget.templateRevision == oldWidget.templateRevision) {
      return;
    }
    final template = widget.template;
    if (template == null) return;
    // `showDialog` 는 다음 프레임(세션 목록이 이미 그려진 뒤)까지 미룬다 —
    // `didUpdateWidget` 은 build 도중이라 그 자리에서 바로 다이얼로그를 열
    // 수 없다. `didUpdateWidget` 자체는 동기 함수라 여기서 기다리지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 프레임이 끝난 뒤에야 불린다 — 그 사이 고객 전환 등으로 이 State 가
      // 트리에서 빠졌다면 dispose 된 State 에서 context/setState 를 건드리게
      // 된다.
      if (!mounted) return;
      unawaited(_applyTemplateToSession(template));
    });
  }

  /// 템플릿을 세션에 덧붙인다(#1029) — 세션이 둘 이상이면 어느 세션에
  /// 넣을지 먼저 고르게 한다. 하나뿐이면 고를 것이 없으니 곧장 그 세션에
  /// 붙인다. 기존 운동은 지우지 않고 그 세션의 목록 뒤에 이어 붙인다.
  Future<void> _applyTemplateToSession(ProgramTemplate template) async {
    var targetIndex = 0;
    if (_draft.sessions.length > 1) {
      final chosen = await _pickTemplateTargetSession(template);
      if (chosen == null || !mounted) return;
      targetIndex = chosen;
    }
    // 다이얼로그를 기다리는 동안 세션이 지워졌을 수 있다 — 인덱스를 다시
    // 확인한다.
    if (targetIndex >= _draft.sessions.length) return;
    final target = _draft.sessions[targetIndex];
    final additions = <ProgramExerciseDraft>[
      for (final exercise in template.exercises)
        ProgramExerciseDraft(
          id: 'exercise-${_nextId++}',
          name: exercise.name,
          type: exercise.type,
          minutes: exercise.minutes > 0 ? exercise.minutes : 30,
          sets: exercise.sets > 0 ? exercise.sets : 3,
          reps: exercise.reps > 0 ? exercise.reps : 10,
          weight: exercise.weight > 0 ? exercise.weight : 20,
          // `source` 는 그대로 서버 계약값(`trainer`)으로 남긴다 — 출처
          // 배지만 이 값을 우선해서 `<템플릿명> 템플릿 추가` 를 보여 준다.
          templateName: template.name,
        ),
    ];
    _replaceSession(
      targetIndex,
      target.copyWith(
        exercises: <ProgramExerciseDraft>[...target.exercises, ...additions],
      ),
    );
  }

  Future<int?> _pickTemplateTargetSession(ProgramTemplate template) {
    final l = AppLocalizations.of(context);
    return _pickSession(
      keyPrefix: 'template-session-picker',
      title: l.programTemplateSessionPickerTitle,
      body: l.programTemplateSessionPickerBody(template.name),
    );
  }

  /// 세션 하나를 고르게 한다. 템플릿을 붙일 세션(#1029)과 운동을 옮길
  /// 세션(#2222)이 같은 물음이라 한 다이얼로그를 쓴다 — [skipIndex] 는
  /// 지금 그 운동이 들어 있는 세션이라 고를 수 없게 뺀다.
  Future<int?> _pickSession({
    required String keyPrefix,
    required String title,
    required String body,
    int? skipIndex,
  }) {
    final l = AppLocalizations.of(context);
    return showAppDialog<int>(
      context: context,
      builder: (dialogContext) => AppDialog(
        key: ValueKey<String>(keyPrefix),
        title: title,
        showClose: false,
        footer: AppButton(
          key: ValueKey<String>('$keyPrefix-cancel'),
          label: l.actionCancel,
          variant: AppButtonVariant.secondary,
          fullWidth: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              body,
              style: dialogContext.oncare
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
            const SizedBox(height: OnCareSpacing.s12),
            for (var i = 0; i < _draft.sessions.length; i++)
              if (i != skipIndex) ...<Widget>[
                const SizedBox(height: OnCareSpacing.s8),
                AppButton(
                  key: ValueKey<String>(
                    '$keyPrefix-${_draft.sessions[i].id}',
                  ),
                  label: _draft.sessions[i].name,
                  variant: AppButtonVariant.secondary,
                  fullWidth: true,
                  onPressed: () => Navigator.of(dialogContext).pop(i),
                ),
              ],
          ],
        ),
      ),
    );
  }

  /// 운동을 다른 세션으로 옮긴다(#2222) — 세션 안 위/아래 이동만으로는
  /// 잘못 들어간 운동을 지우고 다시 만드는 수밖에 없었다.
  Future<void> _moveExerciseToSession(
    int sessionIndex,
    int exerciseIndex,
  ) async {
    final l = AppLocalizations.of(context);
    final ProgramExerciseDraft moving =
        _draft.sessions[sessionIndex].exercises[exerciseIndex];
    final int? target = await _pickSession(
      keyPrefix: 'move-exercise-session-picker',
      title: l.programEditorExerciseMoveTitle,
      body: l.programEditorExerciseMoveBody(moving.name),
      skipIndex: sessionIndex,
    );
    if (target == null || !mounted) return;
    // 다이얼로그를 기다리는 동안 세션이 지워지거나 운동이 움직였을 수 있다 —
    // 자리를 다시 찾는다.
    if (sessionIndex >= _draft.sessions.length ||
        target >= _draft.sessions.length) {
      return;
    }
    final ProgramSessionDraft source = _draft.sessions[sessionIndex];
    final int from = source.exercises.indexWhere(
      (exercise) => exercise.id == moving.id,
    );
    if (from < 0) return;
    final sessions = <ProgramSessionDraft>[..._draft.sessions];
    sessions[sessionIndex] = source.copyWith(
      exercises: <ProgramExerciseDraft>[...source.exercises]..removeAt(from),
    );
    final ProgramSessionDraft destination = sessions[target];
    sessions[target] = destination.copyWith(
      exercises: <ProgramExerciseDraft>[
        ...destination.exercises,
        source.exercises[from],
      ],
    );
    _update(_draft.copyWith(sessions: sessions));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 카드 헤더 — 제목(프로그램 이름) 왼쪽, 저장·편집 동작 오른쪽.
          Row(
            children: <Widget>[
              Expanded(child: _programNameTitle(l)),
              const SizedBox(width: OnCareSpacing.s8),
              _headerActions(l),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // `프로그램 정보`(목표·기간·메모 입력)는 뺐다(#1029) — 실제 배정·
          // PT 등록 payload(`programAssignToJson`/`_draftProgram`)는 이름과
          // 세션만 쓰고 이 값들을 읽지 않는다. `goal` 은 여전히 템플릿 저장
          // (`_saveTemplate`)에 쓰이므로 필드 자체([ProgramEditorState.goal])
          // 는 남기고, 고객의 목표로 자동 채워진 값을 그대로 쓴다 — 안내
          // 배너 없이도 AI 흐름의 `템플릿에 반영`이 그 값을 그대로 세션
          // 1에 병합한다(didUpdateWidget).
          //
          // 이름만은 계속 고칠 수 있어야 한다 — 카드 제목(`_programNameTitle`)
          // 이자 템플릿 저장 이름이라, 자동 생성된 문구(`OOO님을 위한
          // 프로그램`) 그대로 저장되는 유일한 경로가 되면 안 된다. 편집
          // UI는 이제 카드 제목 자리에서 바로 뜬다(`_programNameTitle`,
          // 깃허브 이슈/PR 제목 수정과 같은 자리 전환 방식).
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l.programEditorExerciseConfig,
                  style: context.oncare
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              // 박스형 버튼이던 `세션 추가`를 작은 텍스트 액션으로 줄였다 —
              // 시각 형태만 낮은 우선순위다. 누르면 이제 빈 세션이 바로
              // 붙지 않고 유형 네 가지가 펼쳐진다(#2222).
              Tooltip(
                key: _addSessionKey,
                message: _draft.canAddSession
                    ? ''
                    : l.programEditorSessionLimitReached(kProgramMaxSessions),
                child: AppButton(
                  key: const ValueKey<String>('program-editor-add-session'),
                  onPressed: _draft.canAddSession
                      ? () => unawaited(_pickSessionType())
                      : null,
                  leadingIcon: Icons.add_rounded,
                  label: l.programEditorAddSession,
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          for (
            var index = 0;
            index < _draft.sessions.length;
            index++
          ) ...<Widget>[
            _SessionEditor(
              key: ValueKey<String>(_draft.sessions[index].id),
              session: _draft.sessions[index],
              canMoveUp: index > 0,
              canMoveDown: index < _draft.sessions.length - 1,
              canDelete: _draft.sessions.length > 1,
              canAddExercise: _draft.canAddExercise,
              addingExercise: _addingToSession == _draft.sessions[index].id,
              exerciseNameController: _exerciseName,
              exerciseType: _newExerciseType,
              exerciseSets: _newExerciseSets,
              exerciseReps: _newExerciseReps,
              exerciseWeight: _newExerciseWeight,
              exerciseMinutes: _newExerciseMinutes,
              exerciseIntensity: _newExerciseIntensity,
              onNameChanged: (value) => _replaceSession(
                index,
                _draft.sessions[index].copyWith(name: value),
              ),
              onMoveUp: () => _moveSession(index, -1),
              onMoveDown: () => _moveSession(index, 1),
              onDelete: () => _deleteSession(index),
              onReset: () => _resetSession(index),
              onStartAdd: () => setState(() {
                _addingToSession = _draft.sessions[index].id;
                _exerciseName.clear();
                // 세션을 만들 때 고른 유형이 그 세션의 기본값이다(#2222).
                _newExerciseType =
                    _sessionType[_draft.sessions[index].id] ??
                    _kDefaultExerciseType;
              }),
              onCancelAdd: _cancelExerciseAdd,
              onExerciseTypeChanged: (type) =>
                  setState(() => _newExerciseType = type),
              onExerciseSetsChanged: (value) =>
                  setState(() => _newExerciseSets = value),
              onExerciseRepsChanged: (value) =>
                  setState(() => _newExerciseReps = value),
              onExerciseWeightChanged: (value) =>
                  setState(() => _newExerciseWeight = value),
              onExerciseMinutesChanged: (value) =>
                  setState(() => _newExerciseMinutes = value),
              onExerciseIntensityChanged: (value) =>
                  setState(() => _newExerciseIntensity = value),
              onConfirmAdd: () => _addExercise(index),
              onExerciseChanged: (exerciseIndex, exercise) =>
                  _replaceExercise(index, exerciseIndex, exercise),
              onMoveExercise: (exerciseIndex, direction) =>
                  _moveExercise(index, exerciseIndex, direction),
              // 세션이 하나뿐이면 옮길 곳이 없다 — 메뉴에 죽은 항목을 두지
              // 않는다.
              onMoveExerciseToSession: _draft.sessions.length > 1
                  ? (exerciseIndex) => unawaited(
                      _moveExerciseToSession(index, exerciseIndex),
                    )
                  : null,
              onDeleteExercise: (exerciseIndex) =>
                  _deleteExercise(index, exerciseIndex),
            ),
            const SizedBox(height: OnCareSpacing.s8),
          ],
          // 박스 하단 — PT 등록 날짜·시간 범위·일정 추가를 순서대로
          // 오른쪽 정렬로 둔다. 날짜·시간은 예약 슬롯(`reservation_slots_
          // sheet.dart`)과 같은 라벨+테두리 박스 UI다 — 트레이너 웹의 날짜·
          // 시간 선택 자리가 화면마다 다른 모양이면 안 된다. 넓으면 한 줄,
          // 좁거나 글자가 커지면 오른쪽 기준을 유지한 채 줄바꿈된다.
          // `일정 추가`(예전 `보내기`)가 확인창을 거쳐 실제로 배정+PT
          // 등록까지 한다. 실제 전송·등록 API 호출은 전부 호출부(`onSend`)
          // 가 한다 — 여기는 트리거와 등록일·시각 값만 쥔다.
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s4,
            children: <Widget>[
              _RegisterFieldBox(
                key: const ValueKey<String>('program-register-date'),
                icon: Icons.calendar_today_rounded,
                value: ymd(widget.registerDate),
                onTap: () => unawaited(_pickRegisterDate(context)),
              ),
              _RegisterFieldBox(
                key: const ValueKey<String>('program-register-time'),
                icon: Icons.schedule_rounded,
                value:
                    '${widget.registerStartTime.format(context)} – '
                    '${widget.registerEndTime.format(context)}',
                onTap: () => unawaited(_pickRegisterTimeRange(context)),
              ),
              Tooltip(
                // 버튼을 막는 조건과 같은 순서로 이유를 말한다(#1582).
                message: switch (_draft.assignmentBlocker) {
                  ProgramAssignmentBlocker.sizeExceeded => _sizeExceededMessage(
                    l,
                  ),
                  ProgramAssignmentBlocker.noExercises =>
                    l.programEditorNoExercises,
                  ProgramAssignmentBlocker.invalidExerciseName =>
                    l.programEditorExerciseNameInvalid,
                  null =>
                    !_hasValidRegisterTimeRange
                        ? l.schedEndBeforeStart
                        : _registerDateIsPast
                        ? l.programEditorRegisterDatePast
                        : '',
                },
                child: AppButton(
                  key: const ValueKey<String>('program-editor-send'),
                  label: l.programEditorAddSchedule,
                  onPressed:
                      _draft.supportsAssignment &&
                          _hasValidRegisterTimeRange &&
                          !_registerDateIsPast &&
                          !widget.sending
                      ? () => widget.onSend(_draft)
                      : null,
                ),
              ),
            ],
          ),
          if (_draft.exceedsSizeLimit) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              _sizeExceededMessage(l),
              key: const ValueKey<String>('program-size-exceeded'),
              style: context.oncare
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: OnCareColors.danger),
            ),
          ],
          if (!_hasValidRegisterTimeRange) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              l.schedEndBeforeStart,
              key: const ValueKey<String>('program-register-time-invalid'),
              style: context.oncare
                  .text(OnCareTypography.strong(OnCareTypography.caption))
                  .copyWith(color: OnCareColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  /// 한도를 넘었을 때 무엇을 얼마나 줄여야 하는지 알려 주는 안내(#1583).
  String _sizeExceededMessage(AppLocalizations l) =>
      l.programEditorSizeExceeded(
        _draft.sessions.length,
        kProgramMaxSessions,
        _draft.exerciseCount,
        kProgramMaxExercises,
      );

  /// 등록할 날짜를 고른다 — 기본값은 오늘, 과거 날짜는 고를 수 없다.
  Future<void> _pickRegisterDate(BuildContext context) async {
    final today = _todayDate();
    // 다른 탭의 날짜 입력과 같은 세로형 달력이다(#1425) — 트레이너 웹은 늘
    // 넓은 창이라 기본 `showDatePicker` 는 좌우로 퍼진 달력을 띄운다.
    final picked = await showAppDatePicker(
      context: context,
      // 자정을 넘긴 채로 다이얼로그가 열려 있으면 `registerDate`(연 상태)가
      // `today`(지금 다시 계산한 값)보다 이전일 수 있다 — 달력은 initialDate
      // 가 firstDate 보다 빠르면 assertion 으로 죽는다.
      initialDate: widget.registerDate.isBefore(today)
          ? today
          : widget.registerDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    widget.onRegisterDateChanged(
      DateTime(picked.year, picked.month, picked.day),
    );
  }

  /// 등록할 시작·종료 시각을 스케줄 탭과 같은 범위 선택기로 고른다.
  Future<void> _pickRegisterTimeRange(BuildContext context) async {
    final picked = await showScheduleTimeRangePicker(
      context: context,
      start: widget.registerStartTime,
      end: widget.registerEndTime,
    );
    if (picked == null) return;
    widget.onRegisterTimeRangeChanged(picked);
  }

  void _update(ProgramEditorState next) => setState(() => _draft = next);

  void _replaceSession(int index, ProgramSessionDraft session) {
    final sessions = [..._draft.sessions]..[index] = session;
    _update(_draft.copyWith(sessions: sessions));
  }

  /// `세션 추가` 를 누르면 유형부터 고른다 — 트레이너는 세션을 유산소·근력
  /// 처럼 성격별로 짜므로, 빈 세션을 먼저 만들고 이름과 운동 유형을 따로
  /// 고치게 두지 않는다(#2222).
  Future<void> _pickSessionType() async {
    final RenderBox? anchor =
        _addSessionKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null) return;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        anchor.localToGlobal(Offset.zero, ancestor: overlay),
        anchor.localToGlobal(
          anchor.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    final String? type = await showMenu<String>(
      context: context,
      position: position,
      items: <PopupMenuEntry<String>>[
        for (final String value in kRoutineTypes)
          PopupMenuItem<String>(
            key: ValueKey<String>('program-editor-session-type-$value'),
            value: value,
            child: Text(value),
          ),
      ],
    );
    // 메뉴가 떠 있는 동안 한도에 닿았을 수도 있다 — [_addSession] 이 다시 본다.
    if (type == null || !mounted) return;
    _addSession(type);
  }

  void _addSession(String type) {
    if (!_draft.canAddSession) return;
    final l = AppLocalizations.of(context);
    final id = 'session-${_nextId++}';
    final Set<String> taken = <String>{
      for (final ProgramSessionDraft session in _draft.sessions) session.name,
    };
    // 같은 유형이 또 있으면 2번부터 번호를 붙인다. 지워도 다시 매기지
    // 않는다 — 트레이너가 이미 고쳐 둔 이름 옆에서 번호가 저절로 움직이면
    // 어느 세션을 말하는지 알 수 없게 된다.
    var name = l.programEditorSessionNameTyped(type);
    for (var n = 2; taken.contains(name); n++) {
      name = l.programEditorSessionNameNumbered(type, n);
    }
    _update(
      _draft.copyWith(
        sessions: <ProgramSessionDraft>[
          ..._draft.sessions,
          ProgramSessionDraft(
            id: id,
            name: name,
            exercises: const <ProgramExerciseDraft>[],
          ),
        ],
      ),
    );
    _sessionType[id] = type;
  }

  void _moveSession(int index, int direction) {
    final target = index + direction;
    if (target < 0 || target >= _draft.sessions.length) return;
    final sessions = [..._draft.sessions];
    final moving = sessions.removeAt(index);
    sessions.insert(target, moving);
    _update(_draft.copyWith(sessions: sessions));
  }

  void _deleteSession(int index) {
    if (_draft.sessions.length == 1) return;
    _sessionType.remove(_draft.sessions[index].id);
    final sessions = [..._draft.sessions]..removeAt(index);
    _update(_draft.copyWith(sessions: sessions));
  }

  /// 이 세션의 운동만 비운다(#1029) — 세션 자체와 다른 세션은 그대로 둔다.
  void _resetSession(int index) {
    _replaceSession(
      index,
      _draft.sessions[index].copyWith(
        exercises: const <ProgramExerciseDraft>[],
      ),
    );
  }

  void _addExercise(int sessionIndex) {
    final name = _exerciseName.text.trim();
    if (name.isEmpty || !_draft.canAddExercise) return;
    final session = _draft.sessions[sessionIndex];
    _replaceSession(
      sessionIndex,
      session.copyWith(
        exercises: <ProgramExerciseDraft>[
          ...session.exercises,
          ProgramExerciseDraft(
            id: 'exercise-${_nextId++}',
            name: name,
            type: _newExerciseType,
            // 이 운동의 날짜는 편집기 하단에서 고르는 실제 등록 날짜를
            // 그대로 물려받는다(#1483) — 폼 안에 따로 날짜 선택은 없다.
            date: widget.registerDate,
            // 근력은 세트·횟수·중량으로, 그 외 유형은 시간으로 잰다 — 쓰지
            // 않는 쪽도 값을 들고 있어야 유형을 오갈 때 각자의 값이 남는다.
            sets: _newExerciseSets,
            reps: _newExerciseReps,
            weight: _newExerciseWeight,
            minutes: _newExerciseMinutes,
            intensity: _newExerciseIntensity,
          ),
        ],
      ),
    );
    _cancelExerciseAdd();
  }

  void _cancelExerciseAdd() {
    setState(() {
      _addingToSession = null;
      _exerciseName.clear();
      _newExerciseType = _kDefaultExerciseType;
      _newExerciseSets = 3;
      _newExerciseReps = 10;
      _newExerciseWeight = 20;
      _newExerciseMinutes = 30;
      _newExerciseIntensity = 'moderate';
    });
  }

  void _replaceExercise(
    int sessionIndex,
    int exerciseIndex,
    ProgramExerciseDraft exercise,
  ) {
    final session = _draft.sessions[sessionIndex];
    final exercises = [...session.exercises]..[exerciseIndex] = exercise;
    _replaceSession(sessionIndex, session.copyWith(exercises: exercises));
  }

  void _moveExercise(int sessionIndex, int exerciseIndex, int direction) {
    final session = _draft.sessions[sessionIndex];
    final target = exerciseIndex + direction;
    if (target < 0 || target >= session.exercises.length) return;
    final exercises = [...session.exercises];
    final moving = exercises.removeAt(exerciseIndex);
    exercises.insert(target, moving);
    _replaceSession(sessionIndex, session.copyWith(exercises: exercises));
  }

  void _deleteExercise(int sessionIndex, int exerciseIndex) {
    final session = _draft.sessions[sessionIndex];
    final exercises = [...session.exercises]..removeAt(exerciseIndex);
    _replaceSession(sessionIndex, session.copyWith(exercises: exercises));
  }

  /// AI 후보를 편집기에 붙인다 — **유형별로 세션을 나눈다**(#2222).
  ///
  /// AI 가 준 배열 순서는 서버 계약이 정하지 않는다(생성 프롬프트에 순서
  /// 지시가 없다). 트레이너는 세션을 성격별로 짜므로, 유형이 처음 나온
  /// 순서로 세션을 늘어놓고 한 유형 안에서만 AI 순서를 지킨다. 같은 유형이
  /// 떨어져 두 번 나와도 한 세션으로 모은다 — 세션이 잘게 쪼개지는 쪽이
  /// 트레이너에게 더 성가시다.
  void _appendAiSuggestions(List<AiRoutineItem> suggestions) {
    final l = AppLocalizations.of(context);
    final existingNames = <String>{
      for (final ProgramSessionDraft session in _draft.sessions)
        for (final ProgramExerciseDraft exercise in session.exercises)
          exercise.name,
    };
    final grouped = <String, List<ProgramExerciseDraft>>{};
    for (final AiRoutineItem item in suggestions) {
      if (!existingNames.add(item.name)) continue;
      // 옛 계약값(`걷기`·`요가`)도 네 가지 표준 유형으로 접는다 — 세션 유형과
      // 운동 유형이 어긋나면 그 세션의 새 운동 기본값이 엉뚱해진다.
      final String type = normaliseRoutineType(item.type);
      (grouped[type] ??= <ProgramExerciseDraft>[]).add(
        ProgramExerciseDraft(
          id: 'exercise-${_nextId++}',
          name: item.name,
          minutes: item.minutes > 0 ? item.minutes : 30,
          memo: item.reason,
          type: type,
          source: 'ai',
          // 2단계에서 직접 채운 세트·횟수·중량이 있으면 그대로 옮긴다 —
          // 없으면 [ProgramExerciseDraft] 기본값을 그대로 둔다. 셋 중
          // 하나라도 흘리면 트레이너가 방금 적은 값을 편집기에서 다시
          // 물어야 한다 (#1310).
          sets: item.sets > 0 ? item.sets : 3,
          reps: item.reps > 0 ? item.reps : 10,
          weight: item.weight > 0 ? item.weight : 20,
        ),
      );
    }
    if (grouped.isEmpty) return;

    final sessions = <ProgramSessionDraft>[..._draft.sessions];
    // 비어 있는 첫 세션은 새로 만들지 않고 첫 유형에 내준다 — 그대로 두면
    // 아무것도 없는 `세션 A` 가 맨 위에 남는다.
    var reuseFirst = sessions.length == 1 && sessions.first.exercises.isEmpty;
    for (final MapEntry<String, List<ProgramExerciseDraft>> group
        in grouped.entries) {
      final Set<String> taken = <String>{
        for (final ProgramSessionDraft session in sessions) session.name,
      };
      var name = l.programEditorSessionNameTyped(group.key);
      for (var n = 2; taken.contains(name); n++) {
        name = l.programEditorSessionNameNumbered(group.key, n);
      }
      if (reuseFirst) {
        sessions[0] = sessions.first.copyWith(
          name: name,
          exercises: group.value,
        );
        _sessionType[sessions.first.id] = group.key;
        reuseFirst = false;
      } else if (sessions.length < kProgramMaxSessions) {
        final id = 'session-${_nextId++}';
        sessions.add(
          ProgramSessionDraft(id: id, name: name, exercises: group.value),
        );
        _sessionType[id] = group.key;
      } else {
        // 세션 상한에 닿으면 남은 유형은 마지막 세션에 이어 붙인다 — 상한
        // 때문에 AI 가 준 운동을 말없이 흘리지는 않는다.
        sessions[sessions.length - 1] = sessions.last.copyWith(
          exercises: <ProgramExerciseDraft>[
            ...sessions.last.exercises,
            ...group.value,
          ],
        );
      }
    }
    if (_initialized) {
      _update(_draft.copyWith(sessions: sessions));
      return;
    }
    _draft = _draft.copyWith(sessions: sessions);
  }
}

class _SessionEditor extends StatefulWidget {
  const _SessionEditor({
    super.key,
    required this.session,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canDelete,
    required this.canAddExercise,
    required this.addingExercise,
    required this.exerciseNameController,
    required this.exerciseType,
    required this.exerciseSets,
    required this.exerciseReps,
    required this.exerciseWeight,
    required this.exerciseMinutes,
    required this.exerciseIntensity,
    required this.onNameChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onReset,
    required this.onStartAdd,
    required this.onCancelAdd,
    required this.onExerciseTypeChanged,
    required this.onExerciseSetsChanged,
    required this.onExerciseRepsChanged,
    required this.onExerciseWeightChanged,
    required this.onExerciseMinutesChanged,
    required this.onExerciseIntensityChanged,
    required this.onConfirmAdd,
    required this.onExerciseChanged,
    required this.onMoveExercise,
    required this.onMoveExerciseToSession,
    required this.onDeleteExercise,
  });

  final ProgramSessionDraft session;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canDelete;

  /// 프로그램 전체 운동 수가 상한 아래인가 — 아니면 추가 버튼이 잠긴다(#1583).
  final bool canAddExercise;
  final bool addingExercise;
  final TextEditingController exerciseNameController;
  final String exerciseType;
  final int exerciseSets;
  final int exerciseReps;
  final double exerciseWeight;
  final int exerciseMinutes;
  final String exerciseIntensity;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  /// 이 세션의 운동만 비운다 — 세션 자체는 남는다(#1029).
  final VoidCallback onReset;
  final VoidCallback onStartAdd;
  final VoidCallback onCancelAdd;
  final ValueChanged<String> onExerciseTypeChanged;
  final ValueChanged<int> onExerciseSetsChanged;
  final ValueChanged<int> onExerciseRepsChanged;
  final ValueChanged<double> onExerciseWeightChanged;
  final ValueChanged<int> onExerciseMinutesChanged;
  final ValueChanged<String> onExerciseIntensityChanged;
  final VoidCallback onConfirmAdd;
  final void Function(int, ProgramExerciseDraft) onExerciseChanged;
  final void Function(int, int) onMoveExercise;
  /// 이 운동을 다른 세션으로 옮긴다. 세션이 하나뿐이면 null.
  final ValueChanged<int>? onMoveExerciseToSession;

  final ValueChanged<int> onDeleteExercise;

  @override
  State<_SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<_SessionEditor> {
  var _editingName = false;

  /// 세션 이름 입력칸 — 편집을 시작할 때 지금 이름으로 채운다.
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.drag_indicator_rounded,
                size: OnCareSize.iconMedium,
                color: context.oncare.brand.primary,
              ),
              const SizedBox(width: OnCareSpacing.s4),
              Expanded(child: _buildSessionName()),
              if (_editingName)
                AppIconButton(
                  tooltip: l.actionClose,
                  onPressed: () => setState(() => _editingName = false),
                  icon: Icons.check_rounded,
                  color: context.oncare.brand.primary,
                )
              else ...<Widget>[
                // 더보기 메뉴 안에 묻으면 잘 안 보인다 — 초기화만 따로 아이콘
                // 버튼으로 더보기 왼쪽에 둔다.
                AppIconButton(
                  key: ValueKey<String>('session-reset-${widget.session.id}'),
                  tooltip: l.programEditorSessionReset,
                  onPressed: widget.session.exercises.isEmpty
                      ? null
                      : () => unawaited(_confirmReset()),
                  icon: Icons.refresh_rounded,
                  color: OnCareColors.textTertiary,
                ),
                AppMenu(
                  items: <AppMenuItem>[
                    AppMenuItem(
                      icon: Icons.edit_rounded,
                      label: l.actionEdit,
                      onSelected: () => _handleSessionAction('edit'),
                    ),
                    AppMenuItem(
                      icon: Icons.keyboard_arrow_up_rounded,
                      label: l.programEditorSessionUp,
                      onSelected: widget.canMoveUp
                          ? () => _handleSessionAction('up')
                          : null,
                    ),
                    AppMenuItem(
                      icon: Icons.keyboard_arrow_down_rounded,
                      label: l.programEditorSessionDown,
                      onSelected: widget.canMoveDown
                          ? () => _handleSessionAction('down')
                          : null,
                    ),
                    AppMenuItem(
                      icon: Icons.delete_outline_rounded,
                      label: l.actionDelete,
                      destructive: true,
                      onSelected: widget.canDelete
                          ? () => _handleSessionAction('delete')
                          : null,
                    ),
                  ],
                  triggerBuilder: (context, toggle) => AppIconButton(
                    key: ValueKey<String>(
                      'session-actions-${widget.session.id}',
                    ),
                    tooltip: l.actionEdit,
                    icon: Icons.more_horiz_rounded,
                    color: OnCareColors.textTertiary,
                    onPressed: toggle,
                  ),
                ),
              ],
            ],
          ),
          if (widget.session.exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
              child: Text(
                l.programEditorSessionEmpty,
                textAlign: TextAlign.center,
                style: context.oncare
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ),
          for (
            var index = 0;
            index < widget.session.exercises.length;
            index++
          ) ...<Widget>[
            _ExerciseEditor(
              key: ValueKey<String>(widget.session.exercises[index].id),
              exercise: widget.session.exercises[index],
              canMoveUp: index > 0,
              canMoveDown: index < widget.session.exercises.length - 1,
              onChanged: (value) => widget.onExerciseChanged(index, value),
              onMoveUp: () => widget.onMoveExercise(index, -1),
              onMoveDown: () => widget.onMoveExercise(index, 1),
              onMoveToSession: widget.onMoveExerciseToSession == null
                  ? null
                  : () => widget.onMoveExerciseToSession!(index),
              onDelete: () => widget.onDeleteExercise(index),
            ),
            const SizedBox(height: OnCareSpacing.s8),
          ],
          if (widget.addingExercise)
            // 새로 추가 중인 한 줄도 이미 있는 운동 카드와 같은 틀(카드 배경·
            // 테두리·반경)을 쓴다 — 그래야 목록에 자연스럽게 이어 붙는 한 줄로
            // 보이고, 입력 글자 크기도 [_DraftField] 와 맞춘다.
            Container(
              padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
              decoration: BoxDecoration(
                color: OnCareColors.surfaceCard,
                borderRadius: OnCareRadius.mdAll,
                border: Border.all(color: OnCareColors.lineStrong),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // 회원 앱의 운동 추가 시트와 같은 순서·같은 위젯이다
                  // (#1276, #1483) — 유형 → 이름 → 세부 운동량(시간 또는
                  // 세트·횟수·중량) → 강도 → 예상 칼로리. 날짜는 없다 —
                  // 트레이너 프로그램은 편집기 하단의 등록 날짜 하나만 쓴다.
                  // 유형을 먼저 골라야 이름 placeholder 와 아래 입력칸이
                  // 무엇을 재는지(세트·횟수·중량 또는 시간) 정해진다.
                  RoutineCategoryChips(
                    keyPrefix: 'custom-exercise-category',
                    value: widget.exerciseType,
                    onChanged: widget.onExerciseTypeChanged,
                  ),
                  const SizedBox(height: OnCareSpacing.s8),
                  RoutineNameField(
                    keyPrefix: 'custom-exercise-name',
                    controller: widget.exerciseNameController,
                    autofocus: true,
                    hint: routineTypeNameHint(l, widget.exerciseType),
                    onSubmitted: (_) => widget.onConfirmAdd(),
                  ),
                  const SizedBox(height: OnCareSpacing.s8),
                  // 근력은 세트·횟수·중량을 한 줄에, 그 외 유형은 시간
                  // 한 칸으로 잰다(#1029, #1310, #1489) — 스케줄 탭·AI
                  // 루틴 2단계와 같은 compact 입력이다.
                  if (widget.exerciseType == '근력')
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: RoutineSetsField(
                            keyPrefix: 'custom-exercise-sets',
                            sets: widget.exerciseSets,
                            compact: true,
                            onChanged: widget.onExerciseSetsChanged,
                          ),
                        ),
                        const SizedBox(width: OnCareSpacing.s8),
                        Expanded(
                          child: RoutineRepsField(
                            keyPrefix: 'custom-exercise-reps',
                            reps: widget.exerciseReps,
                            compact: true,
                            onChanged: widget.onExerciseRepsChanged,
                          ),
                        ),
                        const SizedBox(width: OnCareSpacing.s8),
                        Expanded(
                          child: RoutineWeightField(
                            keyPrefix: 'custom-exercise-weight',
                            weight: widget.exerciseWeight,
                            compact: true,
                            onChanged: widget.onExerciseWeightChanged,
                          ),
                        ),
                      ],
                    )
                  else
                    RoutineMinutesField(
                      keyPrefix: 'custom-exercise-duration',
                      minutes: widget.exerciseMinutes,
                      compact: true,
                      onChanged: widget.onExerciseMinutesChanged,
                    ),
                  const SizedBox(height: OnCareSpacing.s8),
                  RoutineIntensityChips(
                    keyPrefix: 'custom-exercise-intensity',
                    value: widget.exerciseIntensity,
                    onChanged: widget.onExerciseIntensityChanged,
                  ),
                  const SizedBox(height: OnCareSpacing.s8),
                  // 이름은 컨트롤러 안에서만 바뀐다 — 글자를 적는 동안 이 줄이
                  // 따라 그려지려면 컨트롤러를 직접 들어야 한다(#1312).
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.exerciseNameController,
                    builder: (BuildContext context, TextEditingValue name, _) =>
                        RoutineCaloriesLine(
                          estimate: estimateRoutineCalories(
                            name: name.text,
                            type: widget.exerciseType,
                            minutes: widget.exerciseType == '근력'
                                ? minutesFromSets(widget.exerciseSets)
                                : widget.exerciseMinutes,
                            intensity: widget.exerciseIntensity,
                          ),
                        ),
                  ),
                  const SizedBox(height: OnCareSpacing.s8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      AppButton(
                        label: l.actionCancel,
                        variant: AppButtonVariant.secondary,
                        size: OnCareButtonSize.small,
                        onPressed: widget.onCancelAdd,
                      ),
                      const SizedBox(width: OnCareSpacing.buttonGap),
                      AppButton(
                        label: l.programEditorAdd,
                        size: OnCareButtonSize.small,
                        onPressed: widget.canAddExercise
                            ? widget.onConfirmAdd
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Tooltip(
              message: widget.canAddExercise
                  ? ''
                  : l.programEditorExerciseLimitReached(kProgramMaxExercises),
              child: AppButton(
                label: l.programEditorAddExercise,
                variant: AppButtonVariant.secondary,
                leadingIcon: Icons.add_rounded,
                onPressed: widget.canAddExercise ? widget.onStartAdd : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionName() {
    if (!_editingName) {
      return Text(
        widget.session.name,
        style: context.oncare
            .text(OnCareTypography.titleSmall)
            .copyWith(color: OnCareColors.textPrimary),
      );
    }
    return AppTextField(
      key: ValueKey<String>('session-name-${widget.session.id}'),
      controller: _nameController,
      onChanged: widget.onNameChanged,
      autofocus: true,
    );
  }

  void _handleSessionAction(String action) {
    switch (action) {
      case 'edit':
        _nameController.text = widget.session.name;
        setState(() => _editingName = true);
        return;
      case 'up':
        widget.onMoveUp();
        return;
      case 'down':
        widget.onMoveDown();
        return;
      case 'delete':
        widget.onDelete();
        return;
    }
  }

  /// 운동이 있을 때만 묻는다 — 초기화 아이콘 자체가 그때만 활성화되니, 이
  /// 액션이 불릴 때는 지울 것이 있다는 뜻이다.
  Future<void> _confirmReset() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        key: const ValueKey<String>('session-reset-confirm'),
        title: l.programEditorSessionResetTitle,
        showClose: false,
        // 초기화는 되돌릴 수 없는 동작이라 확정 버튼을 빨간 채움으로 둔다.
        footer: AppButtonPair(
          cancelKey: const ValueKey<String>('session-reset-cancel'),
          cancelLabel: l.actionCancel,
          onCancel: () => Navigator.of(dialogContext).pop(false),
          confirmKey: const ValueKey<String>('session-reset-submit'),
          confirmLabel: l.programEditorSessionReset,
          destructive: true,
          onConfirm: () => Navigator.of(dialogContext).pop(true),
        ),
        child: Text(
          l.programEditorSessionResetBody(widget.session.name),
          style: dialogContext.oncare
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textSecondary),
        ),
      ),
    );
    if (confirmed == true) widget.onReset();
  }
}

class _ExerciseEditor extends StatefulWidget {
  const _ExerciseEditor({
    super.key,
    required this.exercise,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onMoveToSession,
    required this.onDelete,
  });

  final ProgramExerciseDraft exercise;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<ProgramExerciseDraft> onChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  /// 다른 세션으로 옮기기. 세션이 하나뿐이면 null 이라 메뉴에서 빠진다.
  final VoidCallback? onMoveToSession;
  final VoidCallback onDelete;

  @override
  State<_ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends State<_ExerciseEditor> {
  var _editing = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final exercise = widget.exercise;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s12,
        vertical: OnCareSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(color: OnCareColors.lineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.drag_indicator_rounded,
                size: OnCareSize.iconSmall,
                color: OnCareColors.textTertiary,
              ),
              const SizedBox(width: OnCareSpacing.s4),
              Expanded(child: _ExerciseSummary(exercise: exercise)),
              // 템플릿에서 끌어온 운동은 `<템플릿명> 템플릿 추가` 로, 그 외
              // 직접 추가는 `트레이너 추가` 로 — `source` 는 그대로 서버
              // 계약값(`trainer`)이라 [templateName] 이 있을 때만 우선한다
              // (#1029).
              if (exercise.templateName != null ||
                  exercise.source == 'trainer') ...<Widget>[
                const SizedBox(width: OnCareSpacing.s4),
                AppTag(
                  label: exercise.templateName != null
                      ? l.coachTemplateAdded(exercise.templateName!)
                      : l.coachTrainerAdded,
                ),
              ],
              if (_editing)
                AppIconButton(
                  key: ValueKey<String>('exercise-edit-${exercise.id}'),
                  tooltip: l.actionClose,
                  onPressed: () => setState(() => _editing = false),
                  icon: Icons.check_rounded,
                  color: context.oncare.brand.primary,
                )
              else
                AppMenu(
                  items: <AppMenuItem>[
                    AppMenuItem(
                      icon: Icons.edit_rounded,
                      label: l.actionEdit,
                      onSelected: () => _handleExerciseAction('edit'),
                    ),
                    AppMenuItem(
                      icon: Icons.keyboard_arrow_up_rounded,
                      label: l.programEditorExerciseUp,
                      onSelected: widget.canMoveUp
                          ? () => _handleExerciseAction('up')
                          : null,
                    ),
                    AppMenuItem(
                      icon: Icons.keyboard_arrow_down_rounded,
                      label: l.programEditorExerciseDown,
                      onSelected: widget.canMoveDown
                          ? () => _handleExerciseAction('down')
                          : null,
                    ),
                    if (widget.onMoveToSession != null)
                      AppMenuItem(
                        icon: Icons.drive_file_move_outline,
                        label: l.programEditorExerciseMoveSession,
                        onSelected: () => _handleExerciseAction('move'),
                      ),
                    AppMenuItem(
                      icon: Icons.delete_outline_rounded,
                      label: l.actionDelete,
                      destructive: true,
                      onSelected: () => _handleExerciseAction('delete'),
                    ),
                  ],
                  triggerBuilder: (context, toggle) => AppIconButton(
                    key: ValueKey<String>('exercise-edit-${exercise.id}'),
                    tooltip: l.actionEdit,
                    icon: Icons.more_horiz_rounded,
                    color: OnCareColors.textTertiary,
                    onPressed: toggle,
                  ),
                ),
            ],
          ),
          if (_editing) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            const AppDivider(),
            const SizedBox(height: OnCareSpacing.s8),
            _DraftField(
              fieldId: '${exercise.id}-name',
              label: l.programEditorExercise,
              value: exercise.name,
              onChanged: (value) =>
                  widget.onChanged(exercise.copyWith(name: value)),
            ),
            const SizedBox(height: OnCareSpacing.s8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 회원 앱의 운동 추가 시트와 같은 칸이다 (#1276, #1483) —
                // 종류 → 시간(또는 세트·횟수·중량) → 강도 → 예상 칼로리.
                // 날짜는 없다 — 트레이너 프로그램은 편집기 하단의 등록
                // 날짜 하나만 쓴다.
                RoutineCategoryChips(
                  keyPrefix: '${exercise.id}-type',
                  value: exercise.type,
                  onChanged: (value) =>
                      widget.onChanged(exercise.copyWith(type: value)),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                if (exercise.isStrength)
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: RoutineSetsField(
                          keyPrefix: '${exercise.id}-sets',
                          sets: exercise.sets,
                          compact: true,
                          onChanged: (value) =>
                              widget.onChanged(exercise.copyWith(sets: value)),
                        ),
                      ),
                      const SizedBox(width: OnCareSpacing.s8),
                      Expanded(
                        child: RoutineRepsField(
                          keyPrefix: '${exercise.id}-reps',
                          reps: exercise.reps,
                          compact: true,
                          onChanged: (value) =>
                              widget.onChanged(exercise.copyWith(reps: value)),
                        ),
                      ),
                      const SizedBox(width: OnCareSpacing.s8),
                      Expanded(
                        child: RoutineWeightField(
                          keyPrefix: '${exercise.id}-weight',
                          weight: exercise.weight,
                          compact: true,
                          onChanged: (value) => widget.onChanged(
                            exercise.copyWith(weight: value),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  RoutineMinutesField(
                    keyPrefix: '${exercise.id}-duration',
                    minutes: exercise.minutes,
                    compact: true,
                    onChanged: (value) =>
                        widget.onChanged(exercise.copyWith(minutes: value)),
                  ),
                const SizedBox(height: OnCareSpacing.s8),
                RoutineIntensityChips(
                  keyPrefix: '${exercise.id}-intensity',
                  value: exercise.intensity,
                  onChanged: (value) =>
                      widget.onChanged(exercise.copyWith(intensity: value)),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                RoutineCaloriesLine(estimate: exercise.calories),
                const SizedBox(height: OnCareSpacing.s4),
                _DraftField(
                  fieldId: '${exercise.id}-memo',
                  label: l.programEditorExerciseMemo,
                  value: exercise.memo,
                  onChanged: (value) =>
                      widget.onChanged(exercise.copyWith(memo: value)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _handleExerciseAction(String action) {
    switch (action) {
      case 'edit':
        setState(() => _editing = true);
        return;
      case 'up':
        widget.onMoveUp();
        return;
      case 'down':
        widget.onMoveDown();
        return;
      case 'move':
        widget.onMoveToSession?.call();
        return;
      case 'delete':
        widget.onDelete();
        return;
    }
  }
}

/// 테두리 박스(아이콘·값·펼침 화살표) — 날짜·시간처럼 눌러서 다이얼로그를
/// 여는 자리에 쓴다. 값 자체(날짜·시간)가 무엇을 고르는 칸인지 이미
/// 말해 주므로 위에 별도 라벨을 얹지 않는다(#1536) — 라벨이 있던 예약
/// 슬롯 시트(`reservation_slots_sheet.dart`의 `_tappableFieldColumn`)와는
/// 박스 자체의 생김새만 같다.
class _RegisterFieldBox extends StatelessWidget {
  const _RegisterFieldBox({
    required this.icon,
    required this.value,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.oncare;
    return Material(
      color: Colors.transparent,
      borderRadius: OnCareRadius.mdAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: OnCareRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
          decoration: BoxDecoration(
            color: OnCareColors.surfaceCard,
            borderRadius: OnCareRadius.mdAll,
            border: Border.all(color: OnCareColors.lineStrong),
          ),
          // 바로 옆 `일정 추가`([AppButton] medium)의 높이와 맞춘다 — 세로
          // 패딩만으로는 폰트 지표에 따라 미세하게 어긋날 수 있어, 높이를
          // 직접 고정한다(#1536). `Container.height`+`alignment`는 쓰지
          // 않는다 — 그 조합은 내부적으로 `Align`이 되어 `Wrap`이 주는
          // 만큼 가로로 늘어나 버린다(각 칩이 한 줄씩 차지하게 됨).
          // `SizedBox`는 세로만 고정하고 가로는 그대로 내용 크기를 따른다.
          child: SizedBox(
            height: tokens.density.buttonHeight(OnCareButtonSize.medium),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: OnCareSize.iconSmall,
                  color: tokens.brand.primary,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Text(
                  value,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: OnCareSize.iconMedium,
                  color: OnCareColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseSummary extends StatelessWidget {
  const _ExerciseSummary({required this.exercise});

  final ProgramExerciseDraft exercise;

  @override
  Widget build(BuildContext context) {
    final korean = Localizations.localeOf(context).languageCode == 'ko';
    final metrics = programExerciseMetrics(exercise, korean: korean);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          exercise.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.oncare
              .text(OnCareTypography.strong(OnCareTypography.bodySmall))
              .copyWith(color: OnCareColors.textPrimary),
        ),
        if (metrics.isNotEmpty) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            metrics.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ],
        if (exercise.memo.isNotEmpty) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            exercise.memo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// 운동 한 줄의 지표 요약 — 근력은 세트·횟수·중량, 그 외 유형은 시간. 유형마다
/// 재는 단위가 다르다는 규칙은 회원 앱·서버와도 같다 (#1276).
List<String> programExerciseMetrics(
  ProgramExerciseDraft exercise, {
  required bool korean,
}) {
  final metrics = <String>[];
  if (exercise.isStrength) {
    metrics.add(korean ? '${exercise.sets}세트' : '${exercise.sets} sets');
    if (exercise.reps > 0) {
      metrics.add(korean ? '${exercise.reps}회' : '${exercise.reps} reps');
    }
    // 맨몸 운동은 `0kg` 이다 — 중량 칸을 비울 수 없으므로 0 도 트레이너가 적은
    // 값이다.
    final double w = exercise.weight;
    metrics.add('${w == w.roundToDouble() ? w.round() : w}kg');
  } else {
    metrics.add(korean ? '${exercise.minutes}분' : '${exercise.minutes} min');
  }
  return metrics;
}

/// 운동 이름·메모 입력칸 — 필드 위 라벨과 규격 입력창.
///
/// 예전 `TextFormField(initialValue:)` 처럼 처음 값으로만 채우고, 이후에는
/// 입력한 글자를 [onChanged] 로 올려 보낼 뿐 바깥 값으로 다시 덮지 않는다
/// (다시 덮으면 입력 중 커서가 튄다).
class _DraftField extends StatefulWidget {
  const _DraftField({
    required this.fieldId,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String fieldId;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_DraftField> createState() => _DraftFieldState();
}

class _DraftFieldState extends State<_DraftField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      key: ValueKey<String>(widget.fieldId),
      controller: _controller,
      label: widget.label,
      onChanged: widget.onChanged,
    );
  }
}

/// 자정으로 자른 오늘 — 새 운동 행의 기본 날짜.
DateTime _todayDate() {
  final DateTime now = nowKst();
  return DateTime(now.year, now.month, now.day);
}
