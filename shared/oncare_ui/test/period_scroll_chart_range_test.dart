/// 기간 그래프가 칸 수만 바뀌어도 보이는 구간을 다시 알린다. (#3250)
///
/// 칸 폭·화면 폭이 그대로면 예전에는 알림이 오지 않아, 머리의 기간 글자가 옛
/// 구간(없어진 칸 번호)을 말했다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  testWidgets('칸 수만 바뀌어도 보이는 구간을 다시 알린다', (WidgetTester tester) async {
    final List<(int, int)> ranges = <(int, int)>[];

    Widget chart(int count) => MaterialApp(
      theme: OnCareTheme.light(
        brand: OnCareBrand.member,
        density: OnCareDensity.mobile,
      ),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: PeriodScrollChart(
            count: count,
            height: 120,
            barBuilder: (BuildContext _, int i) => const SizedBox.shrink(),
            labelBuilder: (int i) => '$i',
            onVisibleRangeChanged: (int first, int last) =>
                ranges.add((first, last)),
          ),
        ),
      ),
    );

    await tester.pumpWidget(chart(10));
    await tester.pumpAndSettle();
    expect(ranges.last, (0, 9));

    await tester.pumpWidget(chart(5));
    await tester.pumpAndSettle();
    expect(ranges.last, (0, 4));
  });
}
