import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 옅은 남색 그라디언트 카드 — 대시보드 "활동 피드백"처럼 규칙·요약 안내를
/// 흰 카드들 사이에서 한눈에 구분할 때 쓴다.
///
/// 규격 전환 전 활동 피드백 카드의 모양(옅은 남색 그라디언트 + 진한 하늘색
/// 테두리)을 트레이너 브랜드 토큰으로 옮겼다. 리포트 탭의 요약 카드도 같은
/// 모양을 쓰도록 여기서 한 곳에 둔다.
///
/// - 채움: 왼쪽 위 [OnCareBrand.surface] → 오른쪽 아래
///   [OnCareBrand.exerciseStretching] `LinearGradient`
/// - 테두리: [OnCareBrand.border] 1px
/// - 반경: [OnCareRadius.xlAll] (AppCard 와 같음), 그림자 [OnCareShadows.card]
/// - 안쪽 여백: [OnCareSpacing.cardPadding]
class SoftNavyCard extends StatelessWidget {
  /// Creates the card.
  const SoftNavyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(OnCareSpacing.cardPadding),
  });

  /// Card content.
  final Widget child;

  /// Inner padding.
  final EdgeInsetsGeometry padding;

  /// 카드 장식 — 카드 전체가 아니라 장식만 필요할 때(예: 다른 위젯 안에서
  /// 같은 바탕을 그릴 때) 쓴다.
  static BoxDecoration decoration(OnCareBrand brand) => BoxDecoration(
    borderRadius: OnCareRadius.xlAll,
    border: Border.all(color: brand.border),
    boxShadow: OnCareShadows.card,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[brand.surface, brand.exerciseStretching],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: decoration(context.oncare.brand),
      child: Padding(padding: padding, child: child),
    );
  }
}
