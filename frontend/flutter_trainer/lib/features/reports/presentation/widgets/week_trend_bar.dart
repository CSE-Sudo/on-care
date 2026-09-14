import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 한 주 한 줄 — 라벨 · 가로 막대 · 값.
///
/// 이행률(%)과 영양 지표(kcal·mg·g)가 같은 줄 모양을 쓴다. 값의 뜻은 부르는
/// 쪽이 정하고, 여기서는 **길이와 색만** 그린다.
class WeekTrendBar extends StatelessWidget {
  const WeekTrendBar({
    super.key,
    required this.label,
    required this.fraction,
    required this.text,
    required this.loading,
    required this.current,
    this.warn = false,
    this.valueWidth = 40,
  });

  final String label;

  /// 막대 길이(0~1). 기록이 없으면 null — 막대를 그리지 않는다.
  final double? fraction;

  /// 오른쪽에 찍을 값. 기록이 없으면 부르는 쪽이 '-' 를 준다.
  final String text;

  final bool loading;

  /// 보고 있는 주. 앞선 주와 눈에 띄게 구분한다.
  final bool current;

  /// 목표를 벗어난 주(이행률이 낮거나, 영양 지표가 목표를 넘었거나).
  final bool warn;

  /// 값 칸 너비. 'kcal' 처럼 단위가 붙으면 넓혀 준다.
  final double valueWidth;

  /// 주 라벨 칸 너비 — `3주 전`·`이번 주` 가 한 줄에 들어가는 폭.
  static const double _labelWidth = 52;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    // 목표를 벗어난 주는 빨강, 그 밖은 목표 안쪽 색(브랜드). 보고 있는 주만 제
    // 색을 쓰고 앞선 주는 흐리게 깔아, 색으로 초과 여부를 읽으면서도 어느 줄이
    // 이번 주인지 헷갈리지 않게 한다.
    final Color base = warn
        ? OnCareColors.danger
        : tokens.brand.statusWithinGoal;
    // 목표를 넘긴 주는 지난 주라도 흐리게 깔지 않는다. 흐린 빨강은 분홍으로
    // 보여, 정작 초과를 알아보라고 넣은 색이 가장 약하게 그려졌다(#1177).
    final Color tone = current || warn
        ? base
        : OnCareColors.onWhite(base, OnCareAlpha.strong);
    final TextStyle caption = tokens.text(
      current
          ? OnCareTypography.strong(OnCareTypography.caption)
          : OnCareTypography.caption,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _labelWidth,
            child: Text(
              label,
              style: caption.copyWith(
                color: current
                    ? OnCareColors.textPrimary
                    : OnCareColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            // 눈금 위쪽 끝을 고정해 둔다 — 그 주의 최댓값에 맞춰 늘이면
            // 2,288 과 2,166 이 전혀 다른 길이로 보인다. 기록이 없으면 빈
            // 트랙만 남는다.
            child: AppProgressBar(value: fraction ?? 0, color: tone),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          SizedBox(
            width: valueWidth,
            child: Text(
              loading ? '…' : text,
              textAlign: TextAlign.right,
              maxLines: 1,
              style: OnCareTypography.numeric(caption).copyWith(
                color: current
                    ? OnCareColors.textPrimary
                    : OnCareColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
