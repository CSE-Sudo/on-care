import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 날짜 내비게이션 행 — `◀ 8월 17일 – 8월 23일 ▶ 오늘` 그리고 오른쪽
/// 끝(일요일 칸 위)의 `+ 새 일정`. (#882, #1009)
///
/// 화살표·날짜 묶음은 [AppPeriodNav] 다 — 두 앱이 같은 이전/다음 이동 모양을
/// 쓴다(#1706). 날짜는 두 화살표 사이에 대칭 여백으로 서므로 늘 그 한가운데다.
///
/// `새 일정` 은 이 묶음과 떨어져 행의 맨 오른쪽에 선다 — 시간표의 일요일
/// 칸과 같은 자리라, 일정을 어느 주에 더할지가 시선으로 이어진다.
///
/// **`오늘` 이 나타나도 화살표가 움직이지 않는다.** `오늘` 은 오른쪽 화살표
/// 뒤의 **고정 폭 자리**에 앉고, 보이지 않을 때도 자리를 비워 둔다. 자리가
/// 흔들리면 같은 버튼을 누르려고 매번 다른 자리를 겨눠야 한다.
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
  });

  /// 보이는 창의 첫날.
  final DateTime start;

  /// 보이는 창의 마지막 날.
  final DateTime end;

  /// -1 = 이전 주, +1 = 다음 주.
  final ValueChanged<int> onShift;

  /// 오른쪽 화살표 뒤에 서는 컨트롤(`오늘`). 비어 있어도 자리는 남는다.
  final Widget trailing;

  /// 화살표·날짜 묶음과 떨어져 이 행의 맨 오른쪽(일요일 칸 위)에 서는 동작
  /// (`+ 새 일정`). 없으면 그 자리를 비운다.
  final Widget? newSession;

  /// `오늘` 이 앉는 자리의 폭. 버튼이 없을 때도 비워 두어야 묶음 폭이 변하지
  /// 않는다 — 폭이 변하면 좁은 화면의 축소 비율이 달라져 화살표가 움직인다.
  /// 자리가 고정이므로 **버튼이 그 안에서 줄어든다**.
  static const double _todaySlot = 96;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final group = AppPeriodNav(
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
      trailing: SizedBox(
        width: _todaySlot,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
        ),
      ),
    );

    // 화살표·날짜 묶음은 왼쪽 정렬, `새 일정` 은 오른쪽 끝(일요일 칸 위)이다.
    // 폭이 모자라면 묶음은 그 안에서 줄어들고, 새 일정은 다음 줄로 내린다 —
    // 둘을 한 줄에 우겨넣으면 좁은 화면에서 그대로 넘친다.
    final left = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: group,
    );
    if (newSession == null) {
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
              Align(alignment: Alignment.centerRight, child: newSession),
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: left),
            newSession!,
          ],
        );
      },
    );
  }
}
