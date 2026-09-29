import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// "오늘 식단" 카드의 칼로리 달성률 도넛 — 회원 상세 식단 탭과 프로그램 탭이
/// 이 하나를 쓴다(#2469).
///
/// 두 카드는 자리가 달라 지름·선 굵기·% 글씨 역할만 다르게 받는다(회원 상세
/// 136·12·display, 프로그램 탭 96·8·titleMedium). 링은 한 바퀴에서 멈추고
/// (회색 트랙의 [AppRingGaugeStyle.plain]), 넘긴 양은 가운데 숫자(`113%`)가
/// 자르지 않고 말한다.
class NutritionCalorieDonut extends StatelessWidget {
  const NutritionCalorieDonut({
    super.key,
    required this.ratio,
    required this.color,
    required this.diameter,
    required this.stroke,
    this.percentRole = OnCareTypography.display,
  });

  /// 목표 대비 섭취 비율 — 1 을 넘을 수 있다.
  final double ratio;

  /// 채운 호와 % 글자의 색.
  final Color color;
  final double diameter;
  final double stroke;

  /// 가운데 % 글자의 역할.
  final TextStyle percentRole;

  /// 링의 Key — 테스트가 채운 값을 읽는다.
  static const Key ringKey = Key('client-nutrition-calorie-progress');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return SizedBox.square(
      dimension: diameter,
      child: AppRingGauge(
        key: ringKey,
        // 링은 한 바퀴에서 멈춘다 — 넘긴 양은 링이 그릴 수 없다.
        value: ratio.clamp(0.0, 1.0),
        color: color,
        stroke: stroke,
        // 링은 지름이 고정이라 글자 배율이 커지면 안쪽 두 줄이 원을 넘어선다.
        // 원 안에 들어가도록 함께 줄인다 — 키우지는 않는다(느슨한 칸).
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(OnCareSpacing.s20),
            child: FittedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${(ratio * 100).round()}%',
                    style: OnCareTypography.numeric(
                      tokens.text(percentRole),
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
        ),
      ),
    );
  }
}
