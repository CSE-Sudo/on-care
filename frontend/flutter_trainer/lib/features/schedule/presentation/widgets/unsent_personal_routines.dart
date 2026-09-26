import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/personal_routine_box.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/routine_form_fields.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 마무리된 PT 에 남은 개인운동을 알리고, 거기서 보내게 한다. (#2224)
///
/// 취소·노쇼로 끝난 PT 의 개인운동은 **저절로 가지 않는다** — 아파서 쉬는
/// 회원에게 운동이 자동으로 가면 안 된다. 그래서 취소하는 순간에 묻지 않고,
/// 트레이너가 차분할 때 이 자리에서 판단한다. 취소는 경황이 없을 때 하는
/// 일이라, 그 순간에 운동 구성을 고치라고 들이미는 것은 무리다.
class UnsentPersonalRoutines extends ConsumerStatefulWidget {
  const UnsentPersonalRoutines({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<UnsentPersonalRoutines> createState() =>
      _UnsentPersonalRoutinesState();
}

class _UnsentPersonalRoutinesState
    extends ConsumerState<UnsentPersonalRoutines> {
  List<RoutineExercise> _routines = const <RoutineExercise>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(UnsentPersonalRoutines oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final rows = await ref
          .read(scheduleRepositoryProvider)
          .fetchScheduledRoutines(widget.sessionId);
      if (mounted) setState(() => _routines = rows);
    } catch (_) {
      // 읽지 못하면 조용히 숨긴다 — 없는 것을 있다고 말하지 않는다.
      if (mounted) setState(() => _routines = const <RoutineExercise>[]);
    }
  }

  Future<void> _send(List<RoutineExercise>? edited) async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .sendScheduledRoutines(widget.sessionId, items: edited);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, l.schedRoutinesSendFailed, type: AppToastType.error);
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _routines = const <RoutineExercise>[];
    });
    showAppToast(context, l.schedRoutinesSent, type: AppToastType.success);
  }

  Future<void> _dismiss() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .dismissScheduledRoutines(widget.sessionId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, l.schedRoutinesSendFailed, type: AppToastType.error);
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _routines = const <RoutineExercise>[];
    });
    showAppToast(context, l.schedRoutinesSkipped);
  }

  Future<void> _openSendDialog() async {
    final edited = await showAppDialog<List<RoutineExercise>>(
      context: context,
      builder: (_) => _SendPersonalRoutinesDialog(routines: _routines),
    );
    if (edited == null || !mounted) return;
    await _send(edited);
  }

  @override
  Widget build(BuildContext context) {
    if (_routines.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: OnCareSpacing.s12),
      child: AppCard(
        key: const ValueKey<String>('session-unsent-routines'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.directions_run_rounded,
                  size: OnCareSize.iconMedium,
                  color: OnCareColors.textSecondary,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: Text(
                    l.schedRoutinesUnsent,
                    style: context.oncare
                        .text(OnCareTypography.titleSmall)
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                ),
                AppTag(
                  label: '${_routines.length}',
                  tone: AppTagTone.brand,
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s8),
            for (final RoutineExercise routine in _routines)
              Padding(
                padding: const EdgeInsets.only(top: OnCareSpacing.s2),
                child: Text(
                  '· ${personalRoutineLabel(l, routine)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.oncare
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ),
            const SizedBox(height: OnCareSpacing.s12),
            AppButtonPair(
              cancelKey: const ValueKey<String>('session-routines-skip'),
              cancelLabel: l.schedRoutinesSkip,
              onCancel: _busy ? null : () => unawaited(_dismiss()),
              confirmKey: const ValueKey<String>('session-routines-send'),
              confirmLabel: l.schedRoutinesSend,
              onConfirm: _busy ? null : () => unawaited(_openSendDialog()),
            ),
          ],
        ),
      ),
    );
  }
}

/// 보내기 전에 구성을 고치는 창. (#2224)
///
/// 개인운동은 "이 PT 다음에 할 것" 으로 짜였다. PT 가 열리지 않았으면 전제가
/// 깨지므로 그대로 보내기 어렵다. 취소된 PT 에는 프로그램 만들기로 다시 붙일
/// 수 없어(`예정` 세션만 찾는다) 고치는 자리가 여기뿐이다.
class _SendPersonalRoutinesDialog extends StatefulWidget {
  const _SendPersonalRoutinesDialog({required this.routines});

  final List<RoutineExercise> routines;

  @override
  State<_SendPersonalRoutinesDialog> createState() =>
      _SendPersonalRoutinesDialogState();
}

class _SendPersonalRoutinesDialogState
    extends State<_SendPersonalRoutinesDialog> {
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
