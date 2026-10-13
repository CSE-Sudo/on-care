/// 다시 읽은 배열이 짧아져도 고른 칸이 범위를 벗어나지 않는다. (#3249)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/shared/widgets/period_chart_selection_bounds.dart';
import 'package:oncare_ui/oncare_ui.dart' show PeriodChartSelection;

void main() {
  test('범위 안의 칸은 그대로, 밖이면 고르지 않은 것이다', () {
    final PeriodChartSelection selection = PeriodChartSelection();
    addTearDown(selection.dispose);

    expect(selection.selectedWithin(5), isNull);

    selection.select(4);
    expect(selection.selectedWithin(5), 4);
    // 30초 뒤 다시 읽은 배열이 세 칸으로 줄었다.
    expect(selection.selectedWithin(3), isNull);
    expect(selection.selectedWithin(0), isNull);
  });
}
