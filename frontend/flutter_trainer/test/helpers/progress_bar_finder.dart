import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/shared/widgets/mini_charts.dart';

/// [of] 안에서 값을 길이로 칠하는 막대를 찾는다.
///
/// 회원을 고르는 목록 줄에 이행률 막대를 다시 두지 않는다는 회귀 확인
/// (#1029, #1177, #2232)은 전에 막대 위젯 `InlineBarValue` 의 타입으로 찾았다.
/// 그 위젯은 쓰는 곳이 없어 지웠다(#2470). 타입 이름으로 찾으면 막대가 다른
/// 위젯으로 돌아와도 걸리지 않으므로, 막대를 **그리는 방식**으로 찾는다 —
/// 비율만큼 폭을 채우는 [FractionallySizedBox](지운 위젯이 쓰던 방식),
/// 공용 `AppProgressBar` 가 쓰는 [LinearProgressIndicator], 막대그래프
/// [BarSeriesChart].
Finder findProgressBars({required Finder of}) => find.descendant(
  of: of,
  matching: find.byWidgetPredicate(
    (Widget w) =>
        w is FractionallySizedBox ||
        w is LinearProgressIndicator ||
        w is BarSeriesChart,
  ),
);
