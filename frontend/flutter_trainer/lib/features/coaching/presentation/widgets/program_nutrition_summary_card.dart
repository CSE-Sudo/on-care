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
/// 영양 목표값 상수(`carbsTargetG` 등)와 카드 기준 높이만은
/// [NutritionSummaryCard] 쪽 정의를 그대로 가져다 쓴다 — 같은 하루의 같은
/// 목표를 두 탭이 서로 다른 숫자로 보이면 안 되기 때문이다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:oncare_trainer/core/utils/number_format.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/nutrition_summary_card.dart'
    show carbsTargetG, proteinTargetG, fatTargetG, kClientNutritionCardHeight;
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

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

/// 오늘 섭취 칼로리 + 탄단지 + 나트륨·당류. 카드는 **한 장**이다.
class ProgramNutritionSummaryCard extends StatelessWidget {
  /// Creates the summary for [client].
  const ProgramNutritionSummaryCard({super.key, required this.client});

  /// 오늘 합계를 들고 있는 고객.
  final TrainerClient client;

  /// 이 폭보다 좁으면 나트륨·당류 두 칸을 세로로 쌓는다.
  static const double _mineralStackBelowWidth =
      OnCareLayout.sidebarWidth + OnCareSpacing.s48;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;

    final _Item calories = _Item(
      label: l.metricCalories,
      value: formatNumber(client.calories),
      goal: formatNumber(calorieTargetKcal),
      unit: 'kcal',
      current: client.calories,
      target: calorieTargetKcal,
    );
    final List<_Item> macros = <_Item>[
      _Item(
        label: l.metricCarbs,
        value: formatNumber(client.carbsG),
        goal: formatNumber(carbsTargetG),
        unit: 'g',
        current: client.carbsG,
        target: carbsTargetG,
      ),
      _Item(
        label: l.metricProtein,
        value: formatNumber(client.proteinG),
        goal: formatNumber(proteinTargetG),
        unit: 'g',
        current: client.proteinG,
        target: proteinTargetG,
      ),
      _Item(
        label: l.metricFat,
        value: formatNumber(client.fatG),
        goal: formatNumber(fatTargetG),
        unit: 'g',
        current: client.fatG,
        target: fatTargetG,
      ),
    ];
    final List<_Item> minerals = <_Item>[
      _Item(
        label: l.metricSodium,
        value: formatNumber(client.sodiumMg),
        goal: formatNumber(sodiumTargetMg),
        unit: 'mg',
        current: client.sodiumMg,
        target: sodiumTargetMg,
      ),
      _Item(
        label: l.metricSugar,
        value: formatNumber(client.sugarG),
        goal: formatNumber(sugarTargetG),
        unit: 'g',
        current: client.sugarG,
        target: sugarTargetG,
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
                                text: ' / ${calories.goal} ${calories.unit}',
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
                      // 탄단지는 칼로리 숫자와 도넛 사이에 놓는다 — 칼로리가
                      // 무엇으로 채워졌는지가 그 숫자 바로 아래에서 읽혀야 한다.
                      // 바는 두지 않는다: 옆의 도넛이 이미 달성률을 그리고 있어,
                      // 좁은 왼쪽 칸에 바까지 넣으면 읽을 것만 는다. (회원 앱 #1120)
                      const SizedBox(height: OnCareSpacing.s8),
                      for (final _Item m in macros) ...<Widget>[
                        _MacroTextLine(item: m),
                        if (m != macros.last)
                          const SizedBox(height: OnCareSpacing.s4),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s12),
                _CalorieDonut(calories: calories, color: calorieColor),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s16),
            const AppDivider(),
            const SizedBox(height: OnCareSpacing.s12),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                if (c.maxWidth < _mineralStackBelowWidth) {
                  return Column(
                    children: <Widget>[
                      for (final _Item m in minerals) ...<Widget>[
                        _MineralItem(item: m),
                        if (m != minerals.last)
                          const SizedBox(height: OnCareSpacing.s12),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int i = 0; i < minerals.length; i++) ...<Widget>[
                      Expanded(child: _MineralItem(item: minerals[i])),
                      if (i < minerals.length - 1)
                        const SizedBox(width: OnCareSpacing.s8),
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

/// 칼로리 달성률 도넛. 링은 한 바퀴에서 멈추지만 숫자는 자르지 않는다.
class _CalorieDonut extends StatelessWidget {
  const _CalorieDonut({required this.calories, required this.color});

  final _Item calories;
  final Color color;

  /// 도넛 지름.
  static const double _diameter = OnCareSpacing.s48 + OnCareSpacing.s48;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return SizedBox.square(
      dimension: _diameter,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            key: const Key('client-nutrition-calorie-progress'),
            size: const Size.square(_diameter),
            painter: ProgramCalorieRingPainter(
              progress: calories.gaugeValue,
              color: color,
            ),
          ),
          // 링은 지름이 고정이라 글자 배율이 커지면 안쪽 두 줄이 원을 넘어선다.
          // 원 안에 들어가도록 함께 줄인다.
          Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s20),
            child: FittedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${(calories.ratio * 100).round()}%',
                    style: OnCareTypography.numeric(
                      tokens.text(OnCareTypography.titleMedium),
                    ).copyWith(color: color),
                  ),
                  const SizedBox(height: OnCareSpacing.s4),
                  Text(
                    l.dietAchieveRate,
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.caption))
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 칼로리 달성률 링. 바닥 원 위에 [progress](0~1) 만큼 12시 방향부터 시계
/// 방향으로 둥근 끝 호를 그린다.
///
/// 테스트가 회원을 바꿨을 때 링 값이 바뀌는지 [progress] 로 읽는다.
class ProgramCalorieRingPainter extends CustomPainter {
  /// Creates a ring filled to [progress] in [color].
  const ProgramCalorieRingPainter({
    required this.progress,
    required this.color,
  });

  /// 0~1 로 자른 달성률.
  final double progress;

  /// 호 색.
  final Color color;

  /// 링 선 굵기.
  static const double strokeWidth = OnCareSpacing.s8;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = (size.shortestSide - strokeWidth) / 2;
    final Offset center = size.center(Offset.zero);
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = OnCareColors.surfaceInput,
    );
    final double sweep = progress.clamp(0.0, 1.0) * 2 * math.pi;
    if (sweep <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(ProgramCalorieRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// 카드 머리의 탄단지 한 줄 — `탄수화물 204 /275g`. 바 없이 글자만 쓴다.
class _MacroTextLine extends StatelessWidget {
  const _MacroTextLine({required this.item});

  final _Item item;

  /// 라벨이 차지하는 폭. `탄수화물`(네 글자)이 들어갈 만큼만 잡는다 — 값이
  /// 라벨 바로 옆에서 시작하면서도 세 줄의 숫자가 세로로 가지런하다. 글자
  /// 배율을 따라가야 큰 글씨에서 라벨이 잘리지 않는다. (회원 앱 #1149)
  static const double _labelWidth = OnCareSpacing.s48 + OnCareSpacing.s8;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      key: Key('client-nutrition-macro-${item.label}'),
      children: <Widget>[
        SizedBox(
          width: MediaQuery.textScalerOf(context).scale(_labelWidth),
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ),
        const SizedBox(width: OnCareSpacing.s4),
        // 값은 라벨 바로 옆에서 시작한다. 글자 배율이 커지면 값부터 줄인다 —
        // 이 줄이 넘치면 카드 오른쪽의 도넛을 밀어낸다.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: item.value,
                    // 초과면 빨강 — 바가 없으니 색이 그 말을 대신한다.
                    // 세 항목이 각자 판단하므로 지방만 넘긴 날은 지방 줄만
                    // 빨개진다. (회원 앱 #890)
                    // 목표 안쪽은 목표 안 색(statusWithinGoal)을 흰 바탕에
                    // 65% 로 옅게 깐 색이다 — 브랜드 토큰에서 그 색이
                    // `macroProtein` 이다(#1070 #1239).
                    style:
                        OnCareTypography.numeric(
                          tokens.text(
                            OnCareTypography.strong(OnCareTypography.bodySmall),
                          ),
                        ).copyWith(
                          color: item.isOverGoal
                              ? OnCareColors.danger
                              : tokens.brand.macroProtein,
                        ),
                  ),
                  TextSpan(
                    text: ' / ${item.goal}${item.unit}',
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.caption))
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ],
              ),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }
}

/// 아래 줄의 나트륨·당류 한 칸 — 라벨(+초과분) · 값/목표 · 진행 바.
///
/// 나트륨·당류는 탄단지와 달리 그 자체가 경고 지표라, 목표 안쪽일 때도 색이
/// 또렷하다(옅게 두지 않는다).
class _MineralItem extends StatelessWidget {
  const _MineralItem({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color color = _statusColor(context, item);
    final TextStyle captionStrong = tokens.text(
      OnCareTypography.strong(OnCareTypography.caption),
    );
    return Column(
      key: Key('client-nutrition-mineral-${item.label}'),
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
                  text: ' +${item.difference}${item.unit}',
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
                  text: ' / ${item.goal}${item.unit}',
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
          key: Key('client-nutrition-mineral-progress-${item.label}'),
          value: item.gaugeValue,
          color: color,
        ),
      ],
    );
  }
}
