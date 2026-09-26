import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// ② 다음 주 목표 — 다음 주에 회원과 함께 챙길 것을 고르는 자리. (#2232)
///
/// 고를 거리는 [suggestions] 다. 수치에서 그대로 나온 말이라 모델이 없어도,
/// 요약 생성이 실패한 주에도 비지 않는다. 트레이너가 직접 적은 목표도 같은
/// 목록에 선다 — 회원이 받을 글에서는 둘을 구분할 이유가 없다.
class ReportGoalPicker extends StatefulWidget {
  /// Creates the picker.
  const ReportGoalPicker({
    super.key,
    required this.suggestions,
    required this.selected,
    required this.onToggle,
    required this.onAdd,
  });

  /// 이번 주 수치가 내놓은 다음 주 제안.
  final List<String> suggestions;

  /// 지금 고른 목표 — [suggestions] 에 없는 값(직접 적은 것)도 들어간다.
  final List<String> selected;

  /// 목표 하나를 고르거나 뺀다.
  final ValueChanged<String> onToggle;

  /// 직접 적은 목표를 더한다.
  final ValueChanged<String> onAdd;

  @override
  State<ReportGoalPicker> createState() => _ReportGoalPickerState();
}

class _ReportGoalPickerState extends State<ReportGoalPicker> {
  final TextEditingController _own = TextEditingController();

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  void _add() {
    final String text = _own.text.trim();
    if (text.isEmpty) return;
    widget.onAdd(text);
    _own.clear();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // 제안에 없는, 트레이너가 직접 적은 목표도 함께 세운다.
    final List<String> rows = <String>[
      ...widget.suggestions,
      for (final String goal in widget.selected)
        if (!widget.suggestions.contains(goal)) goal,
    ];

    return AppCard(
      key: const ValueKey<String>('report-goals-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: AppSectionHeader(
                  title: l.reportsGoalsTitle,
                  icon: Icons.flag_rounded,
                ),
              ),
              AppTag(
                label: l.reportsGoalsPicked(widget.selected.length),
                tone: widget.selected.isEmpty
                    ? AppTagTone.neutral
                    : AppTagTone.brand,
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            l.reportsGoalsHint,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          if (rows.isEmpty)
            Text(
              l.reportsGoalsNone,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textTertiary),
            )
          else
            for (final String goal in rows) ...<Widget>[
              _GoalRow(
                goal: goal,
                selected: widget.selected.contains(goal),
                onTap: () => widget.onToggle(goal),
              ),
              const SizedBox(height: OnCareSpacing.s8),
            ],
          const SizedBox(height: OnCareSpacing.s4),
          Row(
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  key: const ValueKey<String>('report-goals-own'),
                  controller: _own,
                  hint: l.reportsGoalsOwnHint,
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              AppButton(
                key: const ValueKey<String>('report-goals-add'),
                label: l.reportsGoalsAdd,
                variant: AppButtonVariant.secondary,
                size: OnCareButtonSize.small,
                leadingIcon: Icons.add_rounded,
                onPressed: _add,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 목표 한 줄 — 눌러서 고르고, 다시 눌러서 뺀다.
class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.goal,
    required this.selected,
    required this.onTap,
  });

  final String goal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return AppTile(
      key: ValueKey<String>('report-goal-$goal'),
      onTap: onTap,
      tone: selected ? AppTileTone.brand : AppTileTone.none,
      child: Row(
        children: <Widget>[
          AppIcon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: OnCareSize.iconSmall,
            color: selected ? tokens.brand.primary : OnCareColors.textTertiary,
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(
            child: Text(
              goal,
              style: tokens.text(
                selected
                    ? OnCareTypography.strong(OnCareTypography.bodySmall)
                    : OnCareTypography.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
