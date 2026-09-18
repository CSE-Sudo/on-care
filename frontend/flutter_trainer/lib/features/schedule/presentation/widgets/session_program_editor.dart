import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/presentation/models/program_draft.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 세션 하나의 프로그램을 그 자리에서 고치는 편집기.
///
/// 운동 행을 [ProgramDraft] 로 들고 있다가 저장할 때 한 번에 반영한다.
///
/// 틀(테두리·반경·안쪽 여백)과 제목은 이 위젯을 감싸는 `AppDialog` 가 그린다 —
/// 제목은 `noteOnly ? schedEditNote : progEditTitle` 이다. 여기서는 내용과
/// 하단 [취소]·[저장] 두 버튼만 세운다.
class SessionProgramEditor extends ConsumerStatefulWidget {
  const SessionProgramEditor({
    required this.session,
    required this.onSaved,
    required this.onCancel,
    this.noteOnly = false,
    super.key,
  });

  final ScheduleSession session;

  /// 운동 목록 없이 **메모만** 고친다(상담). 저장할 때 기존 프로그램은 건드리지
  /// 않는다 — 편집기가 보여 주지 않은 값을 지우면 안 된다(#988).
  final bool noteOnly;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  ConsumerState<SessionProgramEditor> createState() =>
      _SessionProgramEditorState();
}

class _SessionProgramEditorState extends ConsumerState<SessionProgramEditor> {
  late final TextEditingController _note;
  late final List<ProgramDraft> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.session.note);
    _items = widget.session.program.map(ProgramDraft.fromItem).toList();
  }

  @override
  void dispose() {
    _note.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    setState(
      () => _items.add(
        ProgramDraft.empty(date: DateTime.parse(widget.session.date)),
      ),
    );
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index).dispose());
  }

  Future<void> _save() async {
    if (_saving) return;
    // await 전에 잡아 둔다 — 실패 경로가 await 뒤에도 있다.
    final AppLocalizations l = AppLocalizations.of(context);
    final program = <ProgramItem>[];
    for (final item in widget.noteOnly ? const <ProgramDraft>[] : _items) {
      // 숫자 칸은 스테퍼가 이미 범위 안으로 묶어 둔다 — 여기서 막을 것은
      // 비워 둔 이름뿐이다.
      if (item.name.text.trim().isEmpty) {
        showAppToast(context, l.progInvalid);
        return;
      }
      program.add(item.toItem());
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .updateProgram(
            widget.session.id,
            program: widget.noteOnly ? widget.session.program : program,
            // 편집기가 보여 주지 않은 값은 그대로 둔다(#1011).
            note: widget.noteOnly ? _note.text.trim() : widget.session.note,
          );
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      if (!mounted) return;
      showAppToast(context, l.progSaveFailed, type: AppToastType.error);
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!widget.noteOnly) ...<Widget>[
          for (var index = 0; index < _items.length; index++) ...<Widget>[
            _ProgramDraftFields(
              index: index,
              draft: _items[index],
              onRemove: () => _removeItem(index),
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: OnCareSpacing.s8),
          ],
          AppButton(
            label: l.progAddExercise,
            leadingIcon: Icons.add_rounded,
            variant: AppButtonVariant.secondary,
            size: OnCareButtonSize.small,
            fullWidth: true,
            onPressed: _saving ? null : _addItem,
          ),
          const SizedBox(height: OnCareSpacing.s16),
        ],
        // 메모는 **메모 자리에서만** 고친다. 프로그램 편집기 안쪽, 운동 목록을
        // 다 지나야 나오는 자리에도 두면 같은 값을 고치는 곳이 둘이 되어
        // 어느 쪽이 최신인지 읽는 사람이 알 수 없다(#1011).
        if (widget.noteOnly) ...<Widget>[
          AppTextField(
            key: const ValueKey<String>('program-trainer-note'),
            controller: _note,
            label: l.schedNote,
            hint: l.progNoteHint,
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: OnCareSpacing.s24),
        ],
        AppButtonPair(
          cancelLabel: l.actionCancel,
          onCancel: _saving ? null : widget.onCancel,
          confirmKey: const ValueKey<String>('save-program'),
          confirmLabel: _saving
              ? l.progSaving
              : widget.noteOnly
              ? l.progSaveNoteAction
              : l.progSaveAction,
          confirmLoading: _saving,
          onConfirm: _saving ? null : _save,
        ),
      ],
    );
  }
}

class _ProgramDraftFields extends StatelessWidget {
  const _ProgramDraftFields({
    required this.index,
    required this.draft,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final ProgramDraft draft;
  final VoidCallback onRemove;

  /// 어느 칸이든 바뀌면 부른다 — 편집기가 setState 해서 유형 전환·칼로리
  /// 미리보기가 함께 다시 그려진다.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(color: OnCareColors.lineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 회원 앱의 운동 추가 시트와 같은 순서다 (#1276) — 종류 → 이름 →
          // 시간(또는 세트·중량) → 강도 → 예상 칼로리. 날짜는 없다(#1489
          // 후속) — 이 운동은 세션 날짜(위 카드의 실제 일정)에 속해 있고,
          // 여기서 따로 고르게 하면 세션 날짜와 어긋나는 두 번째 입력이
          // 생긴다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: RoutineCategoryChips(
                  keyPrefix: 'program-type-$index',
                  value: normaliseRoutineType(draft.type),
                  onChanged: (String value) {
                    draft.type = value;
                    onChanged();
                  },
                ),
              ),
              AppIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: l.progDeleteExercise,
                color: OnCareColors.textTertiary,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          RoutineNameField(
            keyPrefix: 'program-name-$index',
            controller: draft.name,
            label: l.progExerciseName,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          // 근력은 세트·횟수·중량을 한 줄에, 나머지는 시간 한 칸으로 묻는다.
          // 라벨이 테두리에 얹히는 compact 입력이라 세 칸이 나란히 들어가도
          // 세로 폭이 늘어나지 않는다. (#1489)
          if (draft.isStrength)
            Row(
              children: <Widget>[
                Expanded(
                  child: RoutineSetsField(
                    keyPrefix: 'program-sets-$index',
                    sets: draft.sets,
                    compact: true,
                    onChanged: (int value) {
                      draft.sets = value;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: RoutineRepsField(
                    keyPrefix: 'program-reps-$index',
                    reps: draft.reps,
                    compact: true,
                    onChanged: (int value) {
                      draft.reps = value;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: RoutineWeightField(
                    keyPrefix: 'program-weight-$index',
                    weight: draft.weight,
                    compact: true,
                    onChanged: (double value) {
                      draft.weight = value;
                      onChanged();
                    },
                  ),
                ),
              ],
            )
          else
            RoutineMinutesField(
              keyPrefix: 'program-duration-$index',
              minutes: draft.minutes,
              compact: true,
              onChanged: (int value) {
                draft.minutes = value;
                onChanged();
              },
            ),
          const SizedBox(height: OnCareSpacing.s8),
          RoutineIntensityChips(
            keyPrefix: 'program-intensity-$index',
            value: draft.intensity,
            onChanged: (String value) {
              draft.intensity = value;
              onChanged();
            },
          ),
          const SizedBox(height: OnCareSpacing.s8),
          // 이름 칸은 `onChanged` 없이 컨트롤러만 들고 있다 — 글자를 적는 동안
          // 이 줄이 따라 그려지려면 컨트롤러를 직접 들어야 한다(#1312).
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: draft.name,
            builder: (BuildContext context, TextEditingValue _, _) =>
                RoutineCaloriesLine(estimate: draft.calories),
          ),
        ],
      ),
    );
  }
}
