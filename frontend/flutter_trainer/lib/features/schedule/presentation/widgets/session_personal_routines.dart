import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/personal_routine_box.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 일정 상세 카드의 `개인운동` 갈래. (#2224)
///
/// PT 프로그램과 나란히 서서 "회원이 여기서 할 것" 과 "회원이 혼자 할 것" 을
/// 가른다. 예정인 PT 는 **무엇이 함께 갈지** 보여 주기만 한다 — 완료할 때
/// 나가므로 여기서 보낼 것이 없다.
///
/// 마무리된 PT([finished]) 라면 갈 곳을 잃은 개인운동이라 보낼지 정한다.
/// 취소·노쇼 때 **저절로 가지 않는다** — 아파서 쉬는 회원에게 운동이 자동으로
/// 가면 안 된다. 취소하는 순간에 묻지 않는 까닭은 그때가 경황이 없을 때라,
/// 그 순간에 운동 구성을 고치라고 들이미는 것이 무리이기 때문이다.
class SessionPersonalRoutines extends ConsumerStatefulWidget {
  const SessionPersonalRoutines({
    required this.sessionId,
    required this.finished,
    this.onChanged,
    super.key,
  });

  /// 목록이 바뀔 때마다 부른다 — 카드 아래 전송 버튼이 무엇을 보낼지
  /// 이 값으로 정한다(#2224).
  final ValueChanged<List<RoutineExercise>>? onChanged;

  final String sessionId;

  /// 완료·취소·노쇼로 끝난 PT 인가 — 그때만 보내기/보내지 않음이 선다.
  final bool finished;

  @override
  ConsumerState<SessionPersonalRoutines> createState() =>
      _SessionPersonalRoutinesState();
}

class _SessionPersonalRoutinesState
    extends ConsumerState<SessionPersonalRoutines> {
  List<RoutineExercise> _routines = const <RoutineExercise>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(SessionPersonalRoutines oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final rows = await ref
          .read(scheduleRepositoryProvider)
          .fetchScheduledRoutines(widget.sessionId);
      if (!mounted) return;
      setState(() => _routines = rows);
      widget.onChanged?.call(rows);
    } catch (_) {
      // 읽지 못하면 조용히 숨긴다 — 없는 것을 있다고 말하지 않는다.
      if (!mounted) return;
      setState(() => _routines = const <RoutineExercise>[]);
      widget.onChanged?.call(const <RoutineExercise>[]);
    }
  }




  @override
  Widget build(BuildContext context) {
    if (_routines.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final tokens = context.oncare;
    return Column(
      key: const ValueKey<String>('session-personal-routines'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // `미전송` 태그는 두지 않는다 — 마무리된 PT 에 개인운동이 아직
        // 남아 있다는 사실은 아래 `보내지 않음`·`개인운동 보내기` 가 이미
        // 말하고 있다. 같은 말을 두 번 적지 않는다.
        Text(
          l.schedGroupPersonal,
          style: tokens
              .text(OnCareTypography.strong(OnCareTypography.caption))
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        for (final RoutineExercise routine in _routines)
          Padding(
            padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
            child: Container(
              padding: const EdgeInsets.all(OnCareSpacing.tilePadding),
              decoration: const BoxDecoration(
                color: OnCareColors.surfaceInput,
                borderRadius: OnCareRadius.mdAll,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.directions_run_rounded,
                    size: OnCareSize.iconSmall,
                    color: OnCareColors.textTertiary,
                  ),
                  const SizedBox(width: OnCareSpacing.s8),
                  Expanded(
                    child: Text(
                      personalRoutineLabel(l, routine),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // 보내는 자리는 이 덩어리가 아니라 카드 아래 **전송 버튼 하나**다
        // (#2224) — 개인운동은 PT 프로그램과 함께 나가므로 버튼을 따로 두면
        // 같은 전송이 두 자리에 있는 것처럼 읽힌다. 취소·노쇼면 보낼
        // 프로그램이 없어 그 버튼이 `개인운동 보내기` 로 바뀐다.
        Text(
          widget.finished
              ? l.schedRoutinesNotSentYet
              : l.schedRoutinesGoesOnComplete,
          style: tokens
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textTertiary),
        ),
        const SizedBox(height: OnCareSpacing.s12),
      ],
    );
  }
}

/// 보내기 전에 구성을 고치는 창. (#2224)
///
/// 개인운동은 "이 PT 다음에 할 것" 으로 짜였다. PT 가 열리지 않았으면 전제가
/// 깨지므로 그대로 보내기 어렵다. 취소된 PT 에는 프로그램 만들기로 다시 붙일
/// 수 없어(`예정` 세션만 찾는다) 고치는 자리가 여기뿐이다.
class SendPersonalRoutinesDialog extends StatefulWidget {
  const SendPersonalRoutinesDialog({required this.routines, super.key});

  final List<RoutineExercise> routines;

  @override
  State<SendPersonalRoutinesDialog> createState() =>
      _SendPersonalRoutinesDialogState();
}

class _SendPersonalRoutinesDialogState
    extends State<SendPersonalRoutinesDialog> {
  late final List<RoutineExercise> _draft = <RoutineExercise>[
    ...widget.routines,
  ];
  late final List<TextEditingController> _names = <TextEditingController>[
    for (final RoutineExercise r in widget.routines)
      TextEditingController(text: r.name),
  ];

  @override
  void dispose() {
    for (final TextEditingController c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _removeAt(int index) {
    setState(() {
      _draft.removeAt(index);
      _names.removeAt(index).dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppDialog(
      key: const ValueKey<String>('session-routines-send-dialog'),
      title: l.schedRoutinesSendTitle,
      showClose: false,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: () => Navigator.of(context).pop(),
        confirmKey: const ValueKey<String>('session-routines-send-confirm'),
        confirmLabel: l.schedRoutinesSend,
        onConfirm: _draft.isEmpty
            ? null
            : () => Navigator.of(context).pop(_draft),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l.schedRoutinesSendBody,
            style: context.oncare
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          for (var index = 0; index < _draft.length; index++) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            _RoutineRow(
              key: ValueKey<String>('session-routine-edit-$index'),
              index: index,
              exercise: _draft[index],
              controller: _names[index],
              onChanged: (value) => setState(() => _draft[index] = value),
              onRemove: _draft.length > 1 ? () => _removeAt(index) : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({
    required this.index,
    required this.exercise,
    required this.controller,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final RoutineExercise exercise;
  final TextEditingController controller;
  final ValueChanged<RoutineExercise> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: RoutineCategoryChips(
                keyPrefix: 'session-routine-category-$index',
                value: exercise.type,
                onChanged: (type) => onChanged(exercise.copyWith(type: type)),
              ),
            ),
            if (onRemove != null)
              AppIconButton(
                key: ValueKey<String>('session-routine-remove-$index'),
                icon: Icons.close_rounded,
                tooltip: AppLocalizations.of(context).actionDelete,
                color: OnCareColors.textTertiary,
                onPressed: onRemove,
              ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        RoutineNameField(
          keyPrefix: 'session-routine-name-$index',
          controller: controller,
          onChanged: (name) => onChanged(exercise.copyWith(name: name)),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        // 근력은 세트·횟수로 재므로 분 칸을 쓰지 않는다(#1310) — 여기서는
        // 구성을 덜어내거나 이름·유형을 바꾸는 정도만 하고, 세트까지 다시
        // 짜려면 프로그램 만들기로 간다.
        if (exercise.type != '근력')
          RoutineMinutesField(
            keyPrefix: 'session-routine-minutes-$index',
            minutes: exercise.minutes > 0 ? exercise.minutes : 30,
            compact: true,
            onChanged: (minutes) =>
                onChanged(exercise.copyWith(minutes: minutes)),
          ),
      ],
    );
  }
}
