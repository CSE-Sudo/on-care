import 'package:flutter/material.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/week_range_nav.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트의 주 이동 — `‹  9월 28일 ~ 10월 4일  [오늘]  ›`.
///
/// 스케줄 탭과 같은 [WeekRangeNav] 다 — `오늘` 은 두 화살표 **안쪽**, 날짜
/// 오른쪽의 고정 자리에 앉는다. 날짜 길이나 버튼 표시 여부와 무관하게
/// 화살표가 움직이지 않는다(#2536).
///
/// 버튼은 스케줄 탭의 `오늘` 과 같은 부품이다 — 같은 뜻의 조작이 탭마다 다른
/// 모양이면 익힌 것이 소용없다. 칠하지 않는 네이비 외곽선이라 회색 페이지
/// 배경이 그대로 비친다(#2180).
///
/// 이번 주를 보고 있으면 버튼을 아예 그리지 않는다 — 눌러도 달라질 것이 없다.
class ReportWeekNav extends StatelessWidget {
  /// Creates the week nav.
  const ReportWeekNav({
    super.key,
    required this.rangeLabel,
    required this.onPrev,
    required this.onNext,
    required this.onThisWeek,
  });

  /// 보고 있는 주(`9월 28일 ~ 10월 4일`).
  final String rangeLabel;

  final VoidCallback onPrev;

  /// 다음 주로. 가장 최근 주를 보고 있으면 null — 화살표가 비활성이 된다.
  final VoidCallback? onNext;

  /// 이번 주로 돌아간다. 이미 이번 주면 null — 버튼을 그리지 않는다.
  final VoidCallback? onThisWeek;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return WeekRangeNav(
      label: rangeLabel,
      previousTooltip: l.a11yPrevWeek,
      nextTooltip: l.a11yNextWeek,
      onPrevious: onPrev,
      onNext: onNext,
      today: onThisWeek == null
          ? null
          : AppButton(
              key: const ValueKey<String>('reports-go-this-week'),
              label: l.labelToday,
              variant: AppButtonVariant.strongOutline,
              leadingIcon: AppIcons.calendar,
              onPressed: onThisWeek,
            ),
    );
  }
}
