/// `전체` 그래프의 선택·보이는 구간 상태 (#1018, #1984).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  group('PeriodChartSelection', () {
    test('평균은 보이는 구간만 세고, 기록이 없는 날(0)은 뺀다', () {
      final PeriodChartSelection s = PeriodChartSelection();
      addTearDown(s.dispose);
      const List<double> values = <double>[100, 0, 200, 900];

      expect(s.averageOf(values), 400); // 구간을 모르면 전체
      s.setVisible(0, 2);
      expect(s.averageOf(values), 150);
    });

    test('reset() 은 고른 날만 푼다 — 보이는 구간은 그대로다', () {
      final PeriodChartSelection s = PeriodChartSelection();
      addTearDown(s.dispose);
      s.select(2);
      s.setVisible(0, 1);

      s.reset();

      expect(s.selected, isNull);
      expect(s.visible, (0, 1));
    });

    test('reset(includeVisible: true) 는 보이는 구간까지 비운다 (#1984)', () {
      final PeriodChartSelection s = PeriodChartSelection();
      addTearDown(s.dispose);
      int notified = 0;
      s.addListener(() => notified += 1);
      s.select(2);
      s.setVisible(0, 1);
      notified = 0;

      s.reset(includeVisible: true);

      expect(s.selected, isNull);
      expect(s.visible, isNull);
      expect(notified, 1);
      // 구간이 비었으므로 평균은 다시 배열 전체를 센다 — 앞 기간의 창이 새
      // 배열에 그대로 쓰이지 않는다.
      expect(s.averageOf(const <double>[100, 200, 300]), 200);
    });

    test('풀 것이 없으면 알리지 않는다', () {
      final PeriodChartSelection s = PeriodChartSelection();
      addTearDown(s.dispose);
      int notified = 0;
      s.addListener(() => notified += 1);

      s.reset();
      s.reset(includeVisible: true);

      expect(notified, 0);

      // 구간만 남은 상태에서는 includeVisible 만 한 번 알린다.
      s.setVisible(0, 3);
      notified = 0;
      s.reset();
      expect(notified, 0);
      s.reset(includeVisible: true);
      expect(notified, 1);
    });
  });
}
