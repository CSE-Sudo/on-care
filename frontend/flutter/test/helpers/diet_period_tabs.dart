import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';

/// 식단 탭 기간 토글의 [tab] 칸.
///
/// 토글은 패키지 `AppSegmentedToggle` 이라 칸마다 키가 없다(#1700). 칸은
/// [DietPeriodTab] 순서대로 놓이므로 순서로 집는다 — 로케일과 무관하다.
Finder dietPeriodTab(DietPeriodTab tab) => find
    .descendant(
      of: find.byKey(const ValueKey<String>('diet-period-toggle')),
      matching: find.byType(GestureDetector),
    )
    .at(tab.index);
