import 'package:flutter/material.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 스케줄·리포트 탭의 주 이동 — `‹  [   ]  8월 31일 – 9월 6일  [오늘]  ›` (#2536).
///
/// **두 화살표가 자리를 지킨다.** 날짜는 고정 폭 자리([dateSlot])에 서고,
/// `오늘` 은 두 화살표 **안쪽**, 날짜 오른쪽의 고정 폭 자리([todaySlot])에
/// 앉는다. 주를 넘겨 날짜 문구가 길어지거나(`12월 28일 – 1월 3일`) `오늘` 이
/// 나타나고 사라져도 화살표는 움직이지 않는다 — 날짜 폭만큼 사이가 벌어지던
/// 때에는 같은 버튼을 누르려고 매번 다른 자리를 겨눠야 했다(#1009, #1295).
///
/// 날짜 왼쪽에도 `오늘` 자리와 같은 폭을 거울처럼 비워 두어, 날짜가 두
/// 화살표 사이 한가운데에 선다.
///
/// 화살표는 대시보드 할 일 진행률의 주 이동과 같은 **배경 없는 브랜드색**
/// 아이콘이다 — 같은 뜻의 조작이 탭마다 다른 모양이면 익힌 것이 소용없다.
class WeekRangeNav extends StatelessWidget {
  const WeekRangeNav({
    super.key,
    required this.label,
    required this.previousTooltip,
    required this.nextTooltip,
    required this.onPrevious,
    required this.onNext,
    this.today,
    this.previousKey,
    this.nextKey,
  });

  /// 보고 있는 주(`8월 31일 – 9월 6일`).
  final String label;
  final String previousTooltip;
  final String nextTooltip;

  /// `null` 이면 그 방향으로 갈 수 없다(비활성 회색).
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// 날짜 오른쪽 고정 자리에 서는 `오늘` 버튼. 없어도 자리는 남는다.
  final Widget? today;

  final Key? previousKey;
  final Key? nextKey;

  /// 날짜 자리의 폭 — 가장 긴 형식(`12월 28일 – 1월 3일`)이 들어가는 폭이다.
  /// 큰 글자 배율에서는 글자가 이 안에서 줄어든다.
  static const double dateSlot = 150;

  /// `오늘` 자리의 폭. 버튼이 없을 때도 비워 두어야 화살표가 밀리지 않는다.
  /// 자리가 고정이므로 **버튼이 그 안에서 줄어든다**.
  static const double todaySlot = 112;

  static const double _gap = OnCareSpacing.s8;

  @override
  Widget build(BuildContext context) {
    final OnCareBrand brand = context.oncare.brand;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppIconButton(
          key: previousKey,
          icon: AppIcons.chevronLeft,
          tooltip: previousTooltip,
          color: brand.primary,
          onPressed: onPrevious,
        ),
        const SizedBox(width: _gap),
        // `오늘` 자리의 거울 — 아무것도 그리지 않지만 날짜를 두 화살표 사이
        // 한가운데에 세우는 것은 이 빈 자리다.
        const SizedBox(width: todaySlot),
        SizedBox(
          width: dateSlot,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: OnCareTypography.numeric(
                  context.oncare.text(OnCareTypography.label),
                ).copyWith(color: OnCareColors.textPrimary),
              ),
            ),
          ),
        ),
        SizedBox(
          width: todaySlot,
          child: today == null
              ? null
              : Center(
                  child: FittedBox(fit: BoxFit.scaleDown, child: today),
                ),
        ),
        const SizedBox(width: _gap),
        AppIconButton(
          key: nextKey,
          icon: AppIcons.chevronRight,
          tooltip: nextTooltip,
          color: brand.primary,
          onPressed: onNext,
        ),
      ],
    );
  }
}
