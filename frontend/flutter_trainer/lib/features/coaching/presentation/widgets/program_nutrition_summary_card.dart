/// 프로그램 탭의 `식단 - 오늘` 카드. (#1531)
///
/// 예전에는 고객 탭 `영양 요약` 카드([NutritionSummaryCard])를 프로그램 탭도
/// 그대로 가져다 썼다 — 한 클래스를 두 탭이 같이 그려서, 고객 탭을 위한
/// 레이아웃 수정이 프로그램 탭에도 그대로 번졌다(예: 고객 탭 전용 폭 실험을
/// 하려면 프로그램 탭 테스트까지 함께 고쳐야 했다).
///
/// 이 위젯은 그 인스턴스를 프로그램 탭 전용으로 떼어낸 것이다. 디자인·표시
/// 규칙은 [NutritionSummaryCard] 와 지금 이 시점 기준으로 동일하다 — 둘 다
/// 회원 앱 식단 탭 `오늘` 카드(`diet_record_page.dart` 의
/// `_NutritionSummaryCard`)를 따른다. 앞으로 둘 중 한쪽만 바꾸라는 요구가
/// 없는 한, 한쪽을 고쳐도 다른 쪽은 그대로여야 한다.
///
/// 영양 목표([clientDietGoalsOf])와 카드 기준 높이만은 [NutritionSummaryCard]
/// 쪽 정의를 그대로 가져다 쓴다 — 같은 하루의 같은 목표를 두 탭이 서로 다른
/// 숫자로 보이면 안 되기 때문이다.
///
/// 구분선 아래는 탄·단·지 진행 바 세 칸이다(#2189). 회원 앱이 나트륨·당류를
/// 카드에서 내렸고(회원 앱 #1986) 같은 탭의 `이번 주`·`전체` 도 칼로리만 본다
/// (#2156) — 이 카드만 나트륨·당류를 그리면 기간을 옮길 때마다 지표가 바뀐다.
/// 이 칸은 회원 상세보다 좁아서 회원 상세의 가로 3열이 아니라 회원 앱 `오늘`
/// 카드의 배치(위 칼로리+도넛, 아래 탄단지 가로 세 칸)를 그대로 쓴다.
library;

import 'package:flutter/material.dart';

import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart'
    show ClientDietGoals, clientDietGoalsOf, kClientNutritionCardHeight;
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/widgets/nutrition_calorie_donut.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 달성률 도넛의 지름·선 굵기 — 좁은 옆 칸이라 회원 상세(136·12)보다 작다.
const double _donutDiameter = OnCareSpacing.s48 + OnCareSpacing.s48;
const double _donutStroke = OnCareSpacing.s8;

/// 한 지표의 표시값 한 벌.
class _Item {
  const _Item({
    required this.label,
    required this.value,
    required this.goal,
    required this.unit,
    required this.current,
    required this.target,
  });

  final String label;
  final String value;
  final String goal;
  final String unit;
  final num current;
  final num target;

  /// 목표 대비 실제 비율. **자르지 않는다** — 목표를 넘기면 1.0 을 넘는다.
  /// 달성률 라벨이 이 값을 적는다. 여기서 잘라 두면 목표를 260kcal 넘긴 날에도
  /// '100%' 라고 말해 바로 아래 문구와 어긋난다(#820).
  double get ratio => target <= 0 ? 0 : current / target;

  /// 게이지에 넣을 값. 링과 막대는 1.0 을 넘으면 눈금이 깨지므로 그릴 때만
  /// 자른다.
  double get gaugeValue => ratio.clamp(0.0, 1.0).toDouble();

  bool get isOverGoal => current > target;

  /// 목표까지 남은/넘은 양.
  String get difference => formatNumber((current - target).abs());
}

/// 오늘 섭취 칼로리 + 탄단지. 카드는 **한 장**이다.
class ProgramNutritionSummaryCard extends StatelessWidget {
  /// Creates the summary for [client] against the goals in [profile].
  const ProgramNutritionSummaryCard({
    super.key,
    required this.client,
    this.profile,
  });

  /// 오늘 합계를 들고 있는 고객.
  final TrainerClient client;

  /// 목표를 읽을 건강 프로필. 아직 못 읽었으면 null 이고 기본값으로 그린다.
  final MemberHealthProfile? profile;

  /// 이 폭보다 좁으면 탄단지 세 칸을 위아래로 쌓는다 — 회원 앱 `오늘` 카드와
  /// 같은 값이다.
  static const double _macroStackBelowWidth = 280;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ClientDietGoals goals = clientDietGoalsOf(profile);

    final _Item calories = _Item(
      label: l.metricCalories,
      value: formatNumber(client.calories),
      goal: formatNumber(goals.calories),
      unit: 'kcal',
      current: client.calories,
      target: goals.calories,
    );
    final List<_Item> macros = <_Item>[
      _Item(
        label: l.metricCarbs,
        value: formatNumber(client.carbsG),
        goal: formatNumber(goals.carbsG),
        unit: 'g',
        current: client.carbsG,
        target: goals.carbsG,
      ),
      _Item(
        label: l.metricProtein,
        value: formatNumber(client.proteinG),
        goal: formatNumber(goals.proteinG),
        unit: 'g',
        current: client.proteinG,
        target: goals.proteinG,
      ),
      _Item(
        label: l.metricFat,
        value: formatNumber(client.fatG),
        goal: formatNumber(goals.fatG),
        unit: 'g',
        current: client.fatG,
        target: goals.fatG,
      ),
    ];
    final Color calorieColor = _statusColor(context, calories);
    // 오늘·이번 주·전체가 같은 크기여야 토글을 눌러도 화면이 튀지 않는다.
    // 글자 배율이 커지면 셋 다 함께 커진다 — 최소 높이라 넘치지 않는다.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kClientNutritionCardHeight),
      child: AppCard(
        key: const Key('client-nutrition-summary-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l.dietCalorieIntake,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens
                            .text(
                              OnCareTypography.strong(OnCareTypography.caption),
                            )
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                      const SizedBox(height: OnCareSpacing.s4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: calories.value,
                                style: OnCareTypography.numeric(
                                  tokens.text(OnCareTypography.display),
                                ).copyWith(color: calorieColor),
                              ),
                              TextSpan(
                                // ko `/ 2,000kcal` · en `/ 2,000 kcal`(#3120).
                                text:
                                    ' / ${calories.goal}'
                                    '${unitGap(Localizations.localeOf(context).toString())}'
                                    '${calories.unit}',
                                style: tokens
                                    .text(
                                      OnCareTypography.strong(
                                        OnCareTypography.bodySmall,
                                      ),
                                    )
                                    .copyWith(
                                      color: OnCareColors.textSecondary,
                                    ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s12),
                // 회원 상세 식단 탭과 같은 도넛이다 — 자리가 좁아 지름·선·글자만
                // 작다(#2469).
                NutritionCalorieDonut(
                  ratio: calories.ratio,
                  color: calorieColor,
                  diameter: _donutDiameter,
                  stroke: _donutStroke,
                  percentRole: OnCareTypography.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s16),
            const AppDivider(),
            const SizedBox(height: OnCareSpacing.s12),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                // 구분선 아래는 탄·단·지 진행 바 세 칸이다(#2189).
                if (c.maxWidth < _macroStackBelowWidth) {
                  return Column(
                    children: <Widget>[
                      for (final _Item m in macros) ...<Widget>[
                        _MacroProgressItem(item: m),
                        if (m != macros.last)
                          const SizedBox(height: OnCareSpacing.s12),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int i = 0; i < macros.length; i++) ...<Widget>[
                      Expanded(child: _MacroProgressItem(item: macros[i])),
                      if (i < macros.length - 1)
                        const SizedBox(width: OnCareSpacing.s12),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 목표 안쪽이면 메인 색, 넘겼으면 빨강. 카드 전체가 이 한 규칙을 쓴다.
Color _statusColor(BuildContext context, _Item item) => item.isOverGoal
    ? OnCareColors.danger
    : context.oncare.brand.statusWithinGoal;

/// 아래 줄의 탄·단·지 한 칸 — 라벨(+초과분) · 값/목표 · 진행 바. 회원 앱
/// `오늘` 카드의 `_MacroProgressItem` 과 같은 구성이다(#2189).
class _MacroProgressItem extends StatelessWidget {
  const _MacroProgressItem({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color color = _statusColor(context, item);
    final TextStyle captionStrong = tokens.text(
      OnCareTypography.strong(OnCareTypography.caption),
    );
    return Column(
      key: Key('client-nutrition-macro-${item.label}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: item.label),
              // 초과분은 라벨 오른쪽에 빨간 글씨로. 초과가 아닐 때는 아무것도
              // 붙이지 않는다 — 체크 표시를 두면 목표에 한참 못 미친 날도
              // "정상" 이라고 말한다. (회원 앱 #1070)
              if (item.isOverGoal)
                TextSpan(
                  text:
                      ' +${item.difference}${unitGap(Localizations.localeOf(context).toString())}${item.unit}',
                  style: captionStrong.copyWith(color: OnCareColors.danger),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: captionStrong.copyWith(color: OnCareColors.textPrimary),
        ),
        const SizedBox(height: OnCareSpacing.s4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: item.value,
                  style: OnCareTypography.numeric(
                    tokens.text(
                      OnCareTypography.strong(OnCareTypography.bodySmall),
                    ),
                  ).copyWith(color: OnCareColors.textPrimary),
                ),
                TextSpan(
                  text:
                      ' / ${item.goal}${unitGap(Localizations.localeOf(context).toString())}${item.unit}',
                  style: captionStrong.copyWith(
                    color: OnCareColors.textSecondary,
                  ),
                ),
              ],
            ),
            maxLines: 1,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        AppProgressBar(
          key: Key('client-nutrition-macro-progress-${item.label}'),
          value: item.gaugeValue,
          color: color,
        ),
      ],
    );
  }
}
