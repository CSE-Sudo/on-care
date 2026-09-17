/// 기간 카드가 "지금 무엇을 보고 있는가" 를 적는 한 줄. (#2007 · #2009)
///
/// 운동 탭 `운동 현황` 과 식단 탭 `영양 요약` 은 같은 성격의 카드다 — 기간
/// 토글 아래에서 한 덩어리의 숫자를 보여 주고, 그 숫자가 **어느 기간의 것인지**
/// 를 카드 안에서 스스로 말해야 한다. 두 탭이 각자 형식을 정하면 같은 그림이
/// 서로 다른 말투로 읽힌다.
///
/// 그래서 형식을 한 곳에 둔다. 한쪽만 고치는 일이 생기지 않도록, 문자열을
/// 만드는 [periodRangeText] 와 그것을 그리는 [PeriodRangeLabel] 을 함께 둔다.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:oncare_ui/oncare_ui.dart';

/// `9. 14. ~ 9. 20.` — 카드가 집계한 기간.
///
/// 연도는 적지 않는다. 한 줄에 들어가야 하고, 카드가 보는 것은 길어야 열두
/// 주라 해가 바뀌어도 월·일만으로 갈리지 않는다.
String periodRangeText(String locale, DateTime from, DateTime to) =>
    '${DateFormat.Md(locale).format(from)}'
    ' ~ '
    '${DateFormat.Md(locale).format(to)}';

/// 카드 머리줄 오른쪽에 붙는 기간 한 줄.
///
/// 좁아지면 글자가 통째로 줄어든다 — 잘려서 `9. 14. ~ 9.…` 가 되면 기간의
/// 끝을 잃고, 그러면 이 줄이 하려던 말이 사라진다.
class PeriodRangeLabel extends StatelessWidget {
  const PeriodRangeLabel({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerRight,
    child: Text(
      text,
      maxLines: 1,
      style: context.oncare
          .text(OnCareTypography.strong(OnCareTypography.caption))
          .copyWith(color: OnCareColors.textSecondary),
    ),
  );
}
