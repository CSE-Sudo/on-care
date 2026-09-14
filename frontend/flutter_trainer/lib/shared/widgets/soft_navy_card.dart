import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 옅은 남색 카드 — 대시보드 "활동 피드백"처럼 규칙·요약 안내를 흰 카드들
/// 사이에서 한눈에 구분할 때 쓴다.
///
/// 채움은 대시보드 `오늘의 일정` 카드의 다음 일정 상자와 **같은 단색**
/// [OnCareBrand.surface] 다. 같은 화면에 옅은 남색이 두 가지로 보이지 않게,
/// 그라디언트 대신 한 색으로 칠한다. 리포트 탭의 요약 카드도 같은 모양을
/// 쓰도록 여기서 한 곳에 둔다.
///
/// - 채움: [OnCareBrand.surface] 단색
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
    color: brand.surface,
    borderRadius: OnCareRadius.xlAll,
    border: Border.all(color: brand.border),
    boxShadow: OnCareShadows.card,
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: decoration(context.oncare.brand),
      child: Padding(padding: padding, child: child),
    );
  }
}
