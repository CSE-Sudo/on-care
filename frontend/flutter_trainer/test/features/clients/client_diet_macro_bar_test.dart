import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/design_system/theme/app_theme.dart';
import 'package:oncare_trainer/design_system/tokens/colors.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_diet_period_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

/// 탄단지 누적 막대가 **어떤 데이터에도** 무너지지 않는지. (리뷰 #952)
///
/// 시드는 늘 셋이 다 있는 하루를 준다. 실서버는 그렇지 않다 — 탄수화물만 적힌
/// 날도, 하루 칼로리와 탄단지 합계가 어긋나는 날도 온다.
ClientDietPeriod _period(
  ClientPeriodKey key, {
  required List<ClientDietDay> Function(DateTime) dayAt,
}) {
  final ClientDateRange range = clientRangeFor(key.period, key.day);
  return ClientDietPeriod(
    range: range,
    days: <ClientDietDay>[
      for (final DateTime d in clientRangeDates(range)) ...dayAt(d),
    ],
  );
}

Widget _app(
  List<Override> overrides, {
  ClientPeriod period = ClientPeriod.month,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ClientDietPeriodCard(clientId: 'c1', period: period),
      ),
    ),
  ),
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    ClientDietDay Function(DateTime) build, {
    ClientPeriod period = ClientPeriod.month,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(<Override>[
        clientDietPeriodProvider.overrideWith(
          (ref, key) async =>
              _period(key, dayAt: (DateTime d) => <ClientDietDay>[build(d)]),
        ),
      ], period: period),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('이번 주 탄단지 라벨은 같은 보조 회색을 사용한다 (#1479)', (tester) async {
    await pump(
      tester,
      (DateTime d) => ClientDietDay(
        date: d,
        calories: 1560,
        sodiumMg: 900,
        carbsG: 200,
        proteinG: 100,
        fatG: 40,
      ),
      period: ClientPeriod.week,
    );

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ClientDietPeriodCard)),
    );
    for (final String label in <String>[
      l.metricCarbs,
      l.metricProtein,
      l.metricFat,
    ]) {
      expect(
        tester.widget<Text>(find.text(label).last).style!.color,
        AppColors.mutedForeground,
      );
    }
  });

  /// 첫 칸 구간들의 색과 그려진 높이.
  List<(Color, double)> segmentsOf(WidgetTester tester) => <(Color, double)>[
    for (final Element e
        in find
            .descendant(
              of: find.byKey(const Key('client-diet-bar-0')),
              matching: find.byType(ColoredBox),
            )
            .evaluate())
      (
        (e.widget as ColoredBox).color,
        (e.renderObject! as RenderBox).size.height,
      ),
  ];

  testWidgets('탄수화물만 있는 날도 막대가 그려진다', (tester) async {
    // `hasMacros` 는 셋 중 하나만 양수여도 true 다. 0 인 성분까지 구간을 만들면
    // 아무것도 안 보이는 칸이 섞인다.
    await pump(
      tester,
      (DateTime d) =>
          ClientDietDay(date: d, calories: 800, sodiumMg: 900, carbsG: 200),
    );

    final List<(Color, double)> segments = segmentsOf(tester);
    expect(segments, hasLength(1), reason: '0 인 성분은 구간을 만들지 않는다');
    expect(segments.single.$1, AppColors.macroCarbs);
    expect(segments.single.$2, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('아주 적게 먹은 성분도 실오라기로 남는다', (tester) async {
    // 반올림으로 셋이 모두 0 이 되면 높이만 있고 아무것도 그려지지 않은 막대가
    // 남는다 — #947 과 같은 종류의 사라짐이다.
    await pump(
      tester,
      (DateTime d) => ClientDietDay(
        date: d,
        calories: 2000,
        sodiumMg: 900,
        carbsG: 0.05,
        proteinG: 0.05,
        fatG: 0.05,
      ),
    );

    final List<(Color, double)> segments = segmentsOf(tester);
    for (final (Color _, double h) in segments) {
      expect(h, greaterThan(0));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('칼로리와 탄단지 합계가 어긋나면 나머지가 남는다 (리뷰 #952)', (tester) async {
    // 탄 100g(400) + 단 50g(200) + 지 20g(180) = 780kcal 인데 하루는 1,560kcal.
    // 막대 높이는 칼로리를 따르므로, 구간 비율까지 탄단지 합계로 잡으면 세 색이
    // 막대를 꽉 채워 없는 기여분을 지어내게 된다.
    await pump(
      tester,
      (DateTime d) => ClientDietDay(
        date: d,
        calories: 1560,
        sodiumMg: 900,
        carbsG: 100,
        proteinG: 50,
        fatG: 20,
      ),
    );

    final List<(Color, double)> segments = segmentsOf(tester);
    final double total = segments.fold<double>(
      0,
      (double a, (Color, double) s) => a + s.$2,
    );

    // 설명되지 않는 칼로리가 절반쯤이므로 `나머지` 구간이 있어야 한다.
    final Iterable<(Color, double)> rest = segments.where(
      // `나머지` 는 회원 앱과 같은 트랙 색이다 (#1400).
      ((Color, double) s) => s.$1 == AppColors.inputBackground,
    );
    expect(rest, hasLength(1), reason: '설명되지 않는 칼로리가 자리를 차지해야 한다');
    expect(rest.single.$2 / total, closeTo((1560 - 780) / 1560, 0.03));

    // 탄수화물은 400/1560 만큼만 차지한다 — 780 을 분모로 잡으면 0.51 이 된다.
    final (Color, double) carbs = segments.firstWhere(
      ((Color, double) s) => s.$1 == AppColors.macroCarbs,
    );
    expect(carbs.$2 / total, closeTo(400 / 1560, 0.03));
  });

  testWidgets('탄단지 합계가 칼로리를 넘으면 나머지 없이 꽉 찬다', (tester) async {
    // 서버가 준 하루 칼로리보다 영양소 합이 큰 날도 있다. 이때는 음수 나머지를
    // 그릴 수 없으므로 탄단지 합계에 맞춰 채운다.
    await pump(
      tester,
      (DateTime d) => ClientDietDay(
        date: d,
        calories: 500,
        sodiumMg: 900,
        carbsG: 200,
        proteinG: 100,
        fatG: 40,
      ),
    );

    final List<(Color, double)> segments = segmentsOf(tester);
    expect(
      segments.where(((Color, double) s) => s.$1 == AppColors.inputBackground),
      isEmpty,
    );
    expect(segments, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  test('오늘 기준 키는 KST 를 쓴다', () {
    expect(clientPeriodKeyNow('c1', ClientPeriod.month).day, todayKst());
  });
}
