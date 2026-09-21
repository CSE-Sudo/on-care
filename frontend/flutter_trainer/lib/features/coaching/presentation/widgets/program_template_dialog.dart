import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 템플릿을 만들고 고치는 다이얼로그. (#920)
///
/// [template] 이 없으면 새로 만들고, 있으면 그 값으로 열린다. **시작 구성을
/// 열었을 때도 저장은 '새로 만들기'** 다 — 시작 구성은 저장된 행이 아니라
/// 고칠 대상이 없고, 손을 대는 순간 그 트레이너의 첫 템플릿이 된다.
///
/// 운동 줄은 회원 앱·프로그램 편집기와 같은 스펙이다 — 근력이면 세트·횟수·
/// 중량, 그 외 유형이면 시간. 템플릿은 프로그램이 아니라 **블록**이라 여기 적은
/// 값은 시작점이고, 회원마다 달라지는 값은 적용한 뒤 편집기에서 고친다.
class ProgramTemplateDialog extends ConsumerStatefulWidget {
  const ProgramTemplateDialog({super.key, this.template});

  /// 고칠 템플릿. 시작 구성이면 저장 시 새 템플릿이 만들어진다.
  final ProgramTemplate? template;

  @override
  ConsumerState<ProgramTemplateDialog> createState() =>
      _ProgramTemplateDialogState();
}

class _ProgramTemplateDialogState extends ConsumerState<ProgramTemplateDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.template?.name ?? '',
  );
  late final TextEditingController _goal = TextEditingController(
    text: widget.template?.goal ?? '',
  );
  late final List<_ExerciseDraft> _exercises = <_ExerciseDraft>[
    for (final exercise
        in widget.template?.exercises ?? const <TemplateExercise>[])
      _ExerciseDraft.from(exercise),
    if ((widget.template?.exercises ?? const <TemplateExercise>[]).isEmpty)
      _ExerciseDraft.empty(),
  ];

  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    for (final draft in _exercises) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l.coachTemplateNameRequired);
      return;
    }
    final exercises = <TemplateExercise>[
      for (final draft in _exercises)
        if (draft.toExercise() case final TemplateExercise exercise) exercise,
    ];
    if (exercises.isEmpty) {
      setState(() => _error = l.coachTemplateExerciseRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(trainerProgramTemplateRepositoryProvider);
      final existing = widget.template;
      // 시작 구성은 고칠 행이 없다 — 손을 댄 순간 내 첫 템플릿으로 저장된다.
      if (existing == null || existing.isStarter) {
        await repository.create(
          name: name,
          goal: _goal.text.trim(),
          exercises: exercises,
        );
      } else {
        await repository.update(
          existing.id,
          name: name,
          goal: _goal.text.trim(),
          exercises: exercises,
        );
      }
      ref.invalidate(programTemplatesProvider);
      if (!mounted) return;
      navigator.pop();
    } on AppError catch (error) {
      if (!mounted) return;
      setState(
        () => _error = serverDetailOr(
          l,
          error.message,
          l.coachTemplateSaveFailed,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);

    // 시작 구성이든 직접 만든 템플릿이든 편집 창은 똑같이 생겼다 — 저장 시
    // 시작 구성만 조용히 새 템플릿으로 만들어지는 차이는 데이터 계층
    // (`_save`)에만 있고, 화면엔 드러내지 않는다.
    return AppDialog(
      title: widget.template == null ? l.coachTemplateNew : l.coachTemplateEdit,
      size: AppDialogSize.medium,
      // 하단 [취소, 저장] 으로만 닫는다 — 예전 창에도 닫기 X 는 없었다.
      showClose: false,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: _saving ? null : () => Navigator.of(context).pop(),
        confirmKey: const ValueKey<String>('template-save'),
        confirmLabel: l.coachTemplateSave,
        onConfirm: _saving ? null : _save,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            key: const ValueKey<String>('template-name'),
            controller: _name,
            label: l.coachTemplateNameLabel,
            errorText: _error,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('template-goal'),
            controller: _goal,
            label: l.coachTemplateGoalLabel,
          ),
          const SizedBox(height: OnCareSpacing.s16),
          for (var index = 0; index < _exercises.length; index++)
            _ExerciseRow(
              key: ValueKey<int>(_exercises[index].key),
              draft: _exercises[index],
              onChanged: () => setState(() {}),
              onRemove: _exercises.length == 1
                  ? null
                  : () => setState(() {
                      _exercises.removeAt(index).dispose();
                    }),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: l.coachTemplateAddExercise,
              onPressed: () =>
                  setState(() => _exercises.add(_ExerciseDraft.empty())),
              variant: AppButtonVariant.text,
              size: OnCareButtonSize.small,
              leadingIcon: Icons.add_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

/// 편집 중인 운동 한 줄. 컨트롤러를 들고 있어 다이얼로그가 닫힐 때 정리한다.
///
/// `sets`/`reps`/`weight` 는 근력일 때만 쓴다(#1029, #1310) — 그 외 유형은
/// [minutes] 만 쓴다. 유형을 근력으로 바꾼 뒤 시간 칸은 화면에서 숨지만 값은
/// 그대로 남아 있다(기본 10분) — 백엔드 계약
/// (`ProgramTemplateExercise.minutes`)이 여전히 1 이상을 요구하기 때문이다.
class _ExerciseDraft {
  _ExerciseDraft({
    required this.name,
    required this.minutes,
    required this.sets,
    required this.reps,
    required this.holdSeconds,
    required this.weight,
    required this.type,
    required this.isHold,
  }) : key = _nextKey++;

  factory _ExerciseDraft.empty() => _ExerciseDraft(
    name: TextEditingController(),
    minutes: TextEditingController(text: '10'),
    sets: TextEditingController(text: '3'),
    reps: TextEditingController(text: '10'),
    holdSeconds: TextEditingController(text: '60'),
    weight: TextEditingController(text: '20'),
    type: kRoutineTypes.first,
    // 새 줄은 회로 연다 — 버티는 운동은 트레이너가 `초` 칩으로 바꾼다(#1969).
    isHold: false,
  );

  factory _ExerciseDraft.from(TemplateExercise exercise) => _ExerciseDraft(
    name: TextEditingController(text: exercise.name),
    minutes: TextEditingController(text: '${exercise.minutes}'),
    sets: TextEditingController(
      text: exercise.sets > 0 ? '${exercise.sets}' : '3',
    ),
    reps: TextEditingController(
      text: exercise.reps > 0 ? '${exercise.reps}' : '10',
    ),
    holdSeconds: TextEditingController(
      text: exercise.holdSeconds > 0 ? '${exercise.holdSeconds}' : '60',
    ),
    // 저장된 줄이 든 칸이 곧 이 운동을 재는 단위다. (#1969)
    isHold: exercise.holdSeconds > 0,
    // 중량만 0 을 그대로 연다 — 중량 칸은 비울 수 없어(최솟값 0) 저장된 0 은
    // 트레이너가 적은 맨몸이다. 세트·횟수는 최솟값이 1 이라 0 이 나올 수 없고,
    // 그 0 은 칸이 생기기 전에 저장된 템플릿의 빈자리다.
    weight: TextEditingController(text: '${exercise.weight}'),
    type: kRoutineTypes.contains(exercise.type)
        ? exercise.type
        : kRoutineTypes.first,
  );

  static int _nextKey = 0;

  final int key;
  final TextEditingController name;
  final TextEditingController minutes;
  final TextEditingController sets;
  final TextEditingController reps;

  /// 버티는 운동이면 한 세트를 버티는 시간(초). [reps] 와 한 자리를 나눠
  /// 쓰지만 컨트롤러는 따로 둔다 — 회↔초를 오갈 때 각자의 값이 남아야
  /// 한다. (#1969)
  final TextEditingController holdSeconds;

  final TextEditingController weight;
  String type;

  /// 지금 이 줄을 초로 재는가.
  bool isHold;

  /// 이름이 비었거나 시간이 0 이하면 저장 대상이 아니다 — 빈 줄을 남긴 채
  /// 저장을 눌러도 그 줄만 조용히 빠진다.
  TemplateExercise? toExercise() {
    final label = name.text.trim();
    final duration = int.tryParse(minutes.text.trim()) ?? 0;
    if (label.isEmpty || duration <= 0) return null;
    final isStrength = type == '근력';
    return TemplateExercise(
      name: label,
      minutes: duration,
      type: type,
      // 비근력은 저장하지 않는다 — 화면에서 숨긴 값이 조용히 실리면
      // 안 쓰는 필드가 남아 있는 것처럼 보인다.
      sets: isStrength ? (int.tryParse(sets.text.trim()) ?? 0) : 0,
      // 한 세트는 회로든 초로든 한 번만 잰다 — 고르지 않은 쪽은 0 이다(#1969).
      reps: isStrength && !isHold ? (int.tryParse(reps.text.trim()) ?? 0) : 0,
      holdSeconds: isStrength && isHold
          ? (int.tryParse(holdSeconds.text.trim()) ?? 0)
          : 0,
      weight: isStrength ? (double.tryParse(weight.text.trim()) ?? 0) : 0,
    );
  }

  void dispose() {
    name.dispose();
    minutes.dispose();
    sets.dispose();
    reps.dispose();
    holdSeconds.dispose();
    weight.dispose();
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.draft,
    required this.onChanged,
    this.onRemove,
    super.key,
  });

  final _ExerciseDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final isStrength = draft.type == '근력';
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  controller: draft.name,
                  label: l.coachTemplateExerciseName,
                  hint: l.aiExerciseNameExample,
                ),
              ),
              AppIconButton(
                tooltip: l.a11yRemoveExercise,
                onPressed: onRemove,
                icon: Icons.remove_circle_outline_rounded,
                color: OnCareColors.textSecondary,
              ),
            ],
          ),
          if (isStrength) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: RoutineMeasureToggle(
                keyPrefix: 'template-measure-${draft.key}',
                isHold: draft.isHold,
                onChanged: (bool hold) {
                  draft.isHold = hold;
                  onChanged();
                },
              ),
            ),
          ],
          const SizedBox(height: OnCareSpacing.s4),
          // 근력은 세트·횟수·중량으로, 그 외 유형은 시간으로 잰다
          // (#1029, #1310). 숫자 칸은 이름 아래 제 줄에 둔다 — 한 줄에 넷을
          // 밀어 넣으면 라벨이 잘려 무슨 칸인지 읽히지 않는다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (isStrength) ...<Widget>[
                Expanded(
                  child: AppTextField(
                    controller: draft.sets,
                    label: l.programEditorSets,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                // 버티는 운동은 `횟수` 자리를 `버티는 시간` 이 대신한다 —
                // 칸을 하나 더 두지 않고 바꿔 가며 쓴다(#1969).
                Expanded(
                  child: AppTextField(
                    controller: draft.isHold ? draft.holdSeconds : draft.reps,
                    label: draft.isHold
                        ? l.routineFieldHold
                        : l.programEditorReps,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: AppTextField(
                    controller: draft.weight,
                    label: l.programEditorWeight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                ),
              ] else
                Expanded(
                  child: AppTextField(
                    controller: draft.minutes,
                    label: l.coachTemplateExerciseMinutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s4),
          RoutineCategoryChips(
            value: draft.type,
            onChanged: (value) {
              draft.type = value;
              onChanged();
            },
            keyPrefix: 'template-category-${draft.key}',
          ),
        ],
      ),
    );
  }
}
