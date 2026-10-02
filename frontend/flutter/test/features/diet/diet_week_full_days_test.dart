/// `이번 주` 그래프는 오늘이 무슨 요일이든 월~일 일곱 칸이다 (#2462).
///
/// 서버 `GET /diet/days` 는 `to` 가 오늘보다 뒤면 오늘로 당긴다 — `전체`
/// 그래프에서는 아직 오지 않은 날이 칸이 아니다. 그 응답을 그대로 그리면
/// 월요일에는 칸이 하나뿐이라 점 하나가 가운데 뜨고, 요일 라벨 `월` 은 왼쪽에
/// 붙고, 날짜 기간은 `9. 28. ~ 9. 28.` 이 됐다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/metric_trend_chart.dart';
import 'package:oncare_core/clock.dart';

import '../../helpers/diet_period_tabs.dart';
import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/record_span.dart';

/// 월요일 — 이번 주에 지나간 날이 오늘 하루뿐이다.
final DateTime _monday = DateTime(2026, 9, 28, 9);

/// 서버처럼 `to` 를 오늘로 당겨 주는 저장소.
class _ClampingDietRepository extends FakeDietRepository {
  @override
  Future<DietPeriod> fetchPeriod({DateTime? from, DateTime? to}) {
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime last = to == null || to.isAfter(today) ? today : to;
    return super.fetchPeriod(from: from, to: last);
  }
}

void main() {
  setUp(() => useFixedKstDate(_monday));

  test('오늘까지만 온 응답을 요청한 월~일로 채운다', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        testRecordSpanOverride(),
        dietRepositoryProvider.overrideWithValue(_ClampingDietRepository()),
      ],
    );
    addTearDown(container.dispose);

    final DietDateRange week = dietRangeForTab(DietPeriodTab.week, _monday);
    final DietPeriod period = await container.read(
      dietPeriodProvider(week).future,
    );

    expect(period.days.map((DietPeriodDay d) => d.date), <DateTime>[
      for (int i = 0; i < 7; i++) DateTime(2026, 9, 28 + i),
    ]);
    // 오늘 기록은 그대로, 아직 오지 않은 날은 빈 날이다.
    expect(period.days.first.hasRecord, isTrue);
    expect(period.days.skip(1).any((DietPeriodDay d) => d.hasRecord), isFalse);
    // 빈 칸이 늘어도 평균은 기록 있는 날만으로 낸다.
    expect(period.loggedDays, 1);
    expect(period.avgCalories, period.days.first.calories);
  });

  testWidgets('월요일에도 이번 주 그래프는 월~일 일곱 칸이다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          testRecordSpanOverride(),
          dietRepositoryProvider.overrideWithValue(_ClampingDietRepository()),
          accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DietRecordPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(dietPeriodTab(DietPeriodTab.week));
    await tester.pumpAndSettle();

    final MetricTrendChart chart = tester.widget<MetricTrendChart>(
      find.byType(MetricTrendChart),
    );
    expect(chart.dayLabels, <String>['월', '화', '수', '목', '금', '토', '일']);
    expect(chart.values, hasLength(7));
    // 선은 오늘(월)까지만 잇는다.
    expect(chart.todayIndex, 0);

    final String range = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('diet-period-range')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(range, '9. 28. ~ 10. 4.');
  });
}
