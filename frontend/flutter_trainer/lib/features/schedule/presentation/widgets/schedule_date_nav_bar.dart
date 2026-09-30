import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/week_range_nav.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 날짜 내비게이션 행 — `‹ 8월 31일 – 9월 6일 [오늘] ›` 그리고 오른쪽
/// 끝(일요일 칸 위)의 `+ 새 일정`. (#882, #1009)
///
/// 화살표·날짜·`오늘` 묶음은 [WeekRangeNav] 다 — 리포트 탭과 같은 부품이다.
/// 두 화살표 사이가 고정 폭이고 `오늘` 은 그 안쪽 고정 자리에 앉으므로, 날짜
/// 길이나 `오늘` 표시 여부와 무관하게 화살표가 움직이지 않는다(#2536).
///
/// `새 일정` 은 이 묶음과 떨어져 행의 맨 오른쪽에 선다 — 시간표의 일요일
/// 칸과 같은 자리라, 일정을 어느 주에 더할지가 시선으로 이어진다.
///
/// 좁은 폭에서는 줄을 가르지 않고 묶음째 작게 그린다 — 줄이 갈리면 화살표가
/// 자리를 지킨다는 규칙이 그 순간 깨진다.
class ScheduleDateNavBar extends StatelessWidget {
  const ScheduleDateNavBar({
    super.key,
    required this.start,
    required this.end,
    required this.onShift,
    required this.trailing,
    this.newSession,
    this.actions = const <Widget>[],
  });

  /// 보이는 창의 첫날.
  final DateTime start;

  /// 보이는 창의 마지막 날.
  final DateTime end;

  /// -1 = 이전 주, +1 = 다음 주.
  final ValueChanged<int> onShift;

  /// 두 화살표 안쪽, 날짜 오른쪽에 서는 컨트롤(`오늘`). 비어 있어도 자리는 남는다.
  final Widget trailing;

  /// 화살표·날짜 묶음과 떨어져 이 행의 맨 오른쪽(일요일 칸 위)에 서는 동작
  /// (`+ 새 일정`). 없으면 그 자리를 비운다.
  final Widget? newSession;

  /// [newSession] 왼쪽에 함께 서는 동작(`예약 슬롯`·`상담 요청`). 화면 머리
  /// 오른쪽 끝은 모든 탭이 알림 종 하나만 두는 자리라 이 줄로 내렸다(#2628).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final group = WeekRangeNav(
      label: l.dateRange(
        l.dateMonthDay(start.month, start.day),
        l.dateMonthDay(end.month, end.day),
      ),
      previousTooltip: l.a11yPrevWeek,
      nextTooltip: l.a11yNextWeek,
      // 주 이동에는 제한이 없다 — 앞뒤 어느 쪽으로든 갈 수 있어야 하므로 비활성
      // 상태를 만들지 않는다.
      onPrevious: () => onShift(-1),
      onNext: () => onShift(1),
      today: trailing,
    );

    // 화살표·날짜 묶음은 왼쪽 정렬, `새 일정` 은 오른쪽 끝(일요일 칸 위)이다.
    // 폭이 모자라면 묶음은 그 안에서 줄어들고, 새 일정은 다음 줄로 내린다 —
    // 둘을 한 줄에 우겨넣으면 좁은 화면에서 그대로 넘친다.
    final left = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: group,
    );
    final Widget? right = newSession == null && actions.isEmpty
        ? null
        // 좁은 폭·큰 글자에서는 다음 줄로 내린다 — 한 줄에 우겨넣으면 넘친다.
        : Wrap(
            alignment: WrapAlignment.end,
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[...actions, ?newSession],
          );
    if (right == null) {
      return Align(alignment: Alignment.centerLeft, child: left);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // `새 일정` 을 한 줄에 함께 담는 최소 폭 — 태블릿 기준 폭 아래로는
        // 다음 줄로 내린다.
        if (constraints.maxWidth < OnCareLayout.tabletBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              left,
              const SizedBox(height: OnCareSpacing.s8),
              Align(alignment: Alignment.centerRight, child: right),
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: left),
            right,
          ],
        );
      },
    );
  }
}
