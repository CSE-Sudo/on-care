import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/schedule/domain/entities/schedule_event.dart';
import 'package:oncare/features/schedule/presentation/controllers/schedule_controller.dart';
import 'package:oncare/features/schedule/presentation/schedule_category_color.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/modals/add_event_dialog.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 하루치 일정을 펼쳐 수정·삭제할 수 있게 한다.
///
/// 캘린더 칸의 점을 직접 누르게 하지 않는 이유: 점은 칸 하나에 몇 개만 들어가는
/// 작은 표시라, 일정이 여럿인 날은 누를 수 없는 일정이 생긴다. 날짜를 눌러
/// 목록으로 펼치면 그 날의 모든 일정에 손이 닿는다.
///
/// 저장·삭제가 한 건이라도 일어났으면 `true` 로 닫힌다 — 부른 쪽이 달을 다시
/// 읽을지 판단한다.
Future<bool?> showDayEventsSheet(
  BuildContext context, {
  required DateTime date,
  required List<ScheduleEvent> events,
}) {
  return showAppSheet<bool>(
    // 캘린더 시트 위에 겹쳐 뜨므로 같은 규칙으로 루트 Navigator 에 올린다.
    context: Navigator.of(context, rootNavigator: true).context,
    builder: (BuildContext ctx) => _DayEventsBody(date: date, events: events),
  );
}

class _DayEventsBody extends ConsumerStatefulWidget {
  const _DayEventsBody({required this.date, required this.events});

  final DateTime date;
  final List<ScheduleEvent> events;

  @override
  ConsumerState<_DayEventsBody> createState() => _DayEventsBodyState();
}

class _DayEventsBodyState extends ConsumerState<_DayEventsBody> {
  /// 이 시트에서 무언가 바뀌었는지. 닫을 때 부른 쪽에 알려 준다.
  bool _changed = false;

  /// 삭제 요청이 오가는 일정 id. 두 번 눌러 두 번 지우는 것을 막는다.
  String? _deleting;

  /// 화면에 그리는 목록. 삭제·수정을 즉시 반영해야 시트를 닫았다 열지 않고도
  /// 결과가 보인다.
  late final List<ScheduleEvent> _events = <ScheduleEvent>[...widget.events]
    ..sort((ScheduleEvent a, ScheduleEvent b) => a.time.compareTo(b.time));

  void _markChanged() {
    _changed = true;
    // 달 그리드와 홈의 '오늘의 일정'이 같은 사실을 보도록 함께 무효화한다.
    ref
      ..invalidate(scheduleMonthProvider)
      ..invalidate(scheduleEventsProvider)
      ..invalidate(dashboardSummaryProvider);
  }

  Future<void> _edit(ScheduleEvent event) async {
    final bool? saved = await showEditEventDialog(context, event);
    if (saved != true || !mounted) return;
    _markChanged();
    // 고친 값을 서버에서 다시 읽는 대신, 이 시트는 닫히면서 부모가 새로 읽는다.
    // 여기서는 목록에서 빼 두어 옛 값이 남지 않게만 한다.
    setState(() => _events.removeWhere((ScheduleEvent e) => e.id == event.id));
    if (_events.isEmpty && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete(ScheduleEvent event) async {
    if (_deleting != null) return;
    final AppToastHost toast = AppToastHost.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    // 되돌릴 수 없으므로 확인을 한 번 받는다.
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.eventDeleteTitle,
      message: l.eventDeleteConfirm(event.title),
      confirmLabel: l.actionDelete,
      cancelLabel: l.actionCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _deleting = event.id);
    try {
      await ref.read(scheduleRepositoryProvider).deleteEvent(event.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = null);
      toast.show(l.eventDeleteFailed, type: AppToastType.error);
      return;
    }
    if (!mounted) return;
    _markChanged();
    setState(() {
      _deleting = null;
      _events.removeWhere((ScheduleEvent e) => e.id == event.id);
    });
    toast.show(l.eventDeleted, type: AppToastType.success);
  }

  Future<void> _add() async {
    final bool? saved = await showAddEventDialog(
      context,
      initialDate: widget.date,
    );
    if (saved != true || !mounted) return;
    _markChanged();
    // 새로 만든 일정은 이 목록이 모르므로 부모가 다시 읽게 하고 닫는다.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations m = MaterialLocalizations.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    // 헤더의 닫기 X·배경 탭은 경로를 그냥 닫으려 한다. 이 시트는 닫힐 때 무엇이
    // 바뀌었는지를 돌려줘야 하므로 그 닫기를 받아 결과를 실어 닫는다.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, bool? _) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: AppSheet(
        title: m.formatMediumDate(widget.date),
        footer: AppButton(
          key: const Key('dayEventsAdd'),
          label: l.eventAddForDay,
          variant: AppButtonVariant.secondary,
          leadingIcon: Icons.add_rounded,
          fullWidth: true,
          onPressed: _deleting != null ? null : _add,
        ),
        child: _events.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: OnCareSpacing.s16,
                ),
                child: Text(
                  l.eventsEmptyForDay,
                  textAlign: TextAlign.center,
                  style: context.oncare
                      .text(OnCareTypography.body)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < _events.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: OnCareSpacing.s8),
                    _EventRow(
                      event: _events[i],
                      deleting: _deleting == _events[i].id,
                      // 삭제가 오가는 동안에는 다른 줄도 잠근다.
                      disabled: _deleting != null,
                      onEdit: () => _edit(_events[i]),
                      onDelete: () => _delete(_events[i]),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.deleting,
    required this.disabled,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduleEvent event;
  final bool deleting;
  final bool disabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.only(
        left: OnCareSpacing.tilePadding,
        top: OnCareSpacing.s4,
        bottom: OnCareSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(color: OnCareColors.lineSubtle),
      ),
      child: Row(
        children: <Widget>[
          AppStatusDot(color: scheduleCategoryColor(event.category)),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(height: OnCareSpacing.s2),
                Text(
                  // 시간이 없는 일정도 있다 — 그 사실을 그대로 적는다.
                  <String>[
                    scheduleCategoryLabel(l, event.category),
                    if (event.time.isNotEmpty) event.time else l.eventTimeUnset,
                  ].join(' · '),
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ],
            ),
          ),
          if (deleting)
            SizedBox.square(
              dimension: tokens.density.iconButton,
              child: const Center(child: AppLoading.inline()),
            )
          else ...<Widget>[
            AppIconButton(
              key: Key('editEvent-${event.id}'),
              icon: Icons.edit_rounded,
              tooltip: l.actionEdit,
              onPressed: disabled ? null : onEdit,
            ),
            AppIconButton(
              key: Key('deleteEvent-${event.id}'),
              icon: Icons.delete_rounded,
              tooltip: l.actionDelete,
              color: OnCareColors.danger,
              onPressed: disabled ? null : onDelete,
            ),
          ],
        ],
      ),
    );
  }
}
