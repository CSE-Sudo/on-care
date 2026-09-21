import 'package:flutter/material.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 색 고르기 시트가 돌려주는 선택. (#2076)
class GraphColorChoice {
  const GraphColorChoice(this.color, {required this.unlock});

  final String color;

  /// 아직 열지 않은 색이라 포인트를 내야 하는가. false 면 바로 바꾼다.
  final bool unlock;
}

/// 그래프 색 고르기 시트 — 계열마다 3단계를 그대로 보여 준다. (#2076)
///
/// 그래프 카드의 팔레트 버튼과 사용처의 `그래프 색 바꾸기` 교환이 같은 시트를 쓴다.
/// 색은 **하나씩** 열기 때문에 사용처 카드를 색마다 세우지 않고, 어느 색을 열지
/// 여기서 고른다.
///
/// - 이미 연 색은 눌러서 바로 바꾼다. 포인트가 들지 않는다.
/// - 열지 않은 색은 값(`150P로 열기`)을 달고, 누르면 교환 확인창으로 넘어간다.
/// - [lockedOnly] 는 사용처에서 들어온 길이다 — 살 수 있는 색만 보여 준다.
///
/// 고른 값은 [GraphColorChoice] 로 돌려주고, 실제 교환·저장은 화면이 한다(확인창과
/// 잔액 갱신이 사용처 화면의 다른 교환과 같은 자리에 있어야 한다).
class GraphColorSheet extends StatelessWidget {
  const GraphColorSheet({
    super.key,
    required this.state,
    this.lockedOnly = false,
  });

  final GraphColorState state;
  final bool lockedOnly;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<String> colors = lockedOnly ? state.locked : state.palette;
    return AppSheet(
      key: const Key('graphColorSheet'),
      title: lockedOnly ? l.myGraphColorPickTitle : l.myGraphColorTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final String color in colors) ...<Widget>[
            _ColorRow(
              color: color,
              unlocked: state.isUnlocked(color),
              selected: state.current == color,
              cost: state.cost,
              onTap: () => Navigator.of(context).pop(
                GraphColorChoice(color, unlock: !state.isUnlocked(color)),
              ),
            ),
            const SizedBox(height: OnCareSpacing.s8),
          ],
        ],
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.color,
    required this.unlocked,
    required this.selected,
    required this.cost,
    required this.onTap,
  });

  final String color;
  final bool unlocked;
  final bool selected;
  final int cost;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareRecordRamp ramp = OnCareRecordColors.rampOf(color);
    return InkWell(
      key: ValueKey<String>('graph-color-$color'),
      onTap: selected ? null : onTap,
      borderRadius: OnCareRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.all(OnCareSpacing.s8),
        child: Row(
          children: <Widget>[
            // 계열의 3단계를 그대로 보여 준다 — 그래프에 어떻게 보일지가 이름보다
            // 빠르다.
            for (final Color step in ramp.steps) ...<Widget>[
              Container(
                width: OnCareSpacing.s16,
                height: OnCareSpacing.s16,
                decoration: BoxDecoration(
                  color: step,
                  borderRadius: OnCareRadius.xsAll,
                ),
              ),
              const SizedBox(width: OnCareSpacing.s4),
            ],
            const SizedBox(width: OnCareSpacing.s8),
            Expanded(
              child: Text(
                graphColorName(l, color),
                style: tokens
                    .text(OnCareTypography.body)
                    .copyWith(color: OnCareColors.textPrimary),
              ),
            ),
            if (selected)
              AppIcon(
                AppIcons.checkCircle,
                size: OnCareSize.iconMedium,
                color: tokens.brand.primary,
              )
            else if (!unlocked)
              AppTag(label: l.myGraphColorLocked(l.myPointsCost(cost))),
          ],
        ),
      ),
    );
  }
}
