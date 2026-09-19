/// MY 포인트 카드의 적립 모션 — 숫자가 올라가고 별이 톡 튄다. (#1786)
///
/// 처음 읽을 때는 움직이지 않고, 잔액이 이전에 보인 값보다 오를 때만 움직인다.
/// 줄면 그대로 바꾸고, 움직임 줄이기에서는 새 숫자로 바로 바꾼다. 가려진 탭에서
/// 받은 값은 탭이 보일 때 움직인다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

void main() {
  late DemoPointsLedger ledger;

  // 시작 잔액을 못 박아 둔다 — 아래 숫자는 이 값에서 움직인다.
  setUp(() => ledger = DemoPointsLedger(openingBalance: 1240));

  Future<void> pumpPage(
    WidgetTester tester, {
    bool disableAnimations = false,
    ValueNotifier<bool>? visible,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ValueNotifier<bool> tabVisible = visible ?? ValueNotifier<bool>(true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          gymRepositoryProvider.overrideWithValue(MockGymRepository()),
          myHealthRepositoryProvider.overrideWithValue(
            MockMyHealthRepository(points: ledger),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          // 하단 탭이 가려진 탭에 하듯 TickerMode 로 보임을 흉내 낸다.
          home: ValueListenableBuilder<bool>(
            valueListenable: tabVisible,
            builder: (BuildContext context, bool on, Widget? child) =>
                TickerMode(enabled: on, child: child!),
            child: const MyHealthPage(),
          ),
        ),
      ),
    );
  }

  Finder banner() => find.byKey(const Key('pointsBanner'));

  String pointsText(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: banner(), matching: find.byType(Text)))
      .data!;

  double starScale(WidgetTester tester) => tester
      .widget<ScaleTransition>(find.byKey(const Key('pointsStar')))
      .scale
      .value;

  /// [frames] 동안 보인 숫자와 별의 가장 큰 배율.
  Future<(Set<String>, double)> watch(
    WidgetTester tester, {
    int frames = 70,
  }) async {
    final Set<String> seen = <String>{};
    double peak = 1;
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (banner().evaluate().isEmpty) continue;
      seen.add(pointsText(tester));
      final double scale = starScale(tester);
      if (scale > peak) peak = scale;
    }
    return (seen, peak);
  }

  Future<void> refetch(WidgetTester tester) async {
    ProviderScope.containerOf(
      tester.element(find.byType(MyHealthPage)),
    ).invalidate(myHealthStateProvider);
  }

  testWidgets('처음 읽을 때는 숫자도 별도 움직이지 않는다', (WidgetTester tester) async {
    await pumpPage(tester);

    final (Set<String> seen, double peak) = await watch(tester);

    expect(seen.difference(<String>{'—P', '1240P'}), isEmpty);
    expect(peak, 1);
    await tester.pumpAndSettle();
    expect(pointsText(tester), '1240P');
  });

  testWidgets('잔액이 오르면 이전 값에서 숫자가 올라가고 별이 톡 튄다', (
    WidgetTester tester,
  ) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(pointsText(tester), '1240P');

    ledger.award(PointsRule.dietEntry, 'diet-1');
    await refetch(tester);
    final (Set<String> seen, double peak) = await watch(tester);

    // 1240 과 1290 사이의 숫자를 거쳐 간다.
    expect(
      seen.where((String s) => s != '1240P' && s != '1290P'),
      isNotEmpty,
    );
    expect(peak, greaterThan(1.1));
    await tester.pumpAndSettle();
    expect(pointsText(tester), '1290P');
    expect(starScale(tester), 1);
  });

  testWidgets('잔액이 줄면(회수) 움직이지 않고 바로 바꾼다', (WidgetTester tester) async {
    ledger.award(PointsRule.dietEntry, 'diet-1');
    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(pointsText(tester), '1290P');

    ledger.revoke(PointsRule.dietEntry.sourceType, 'diet-1');
    await refetch(tester);
    final (Set<String> seen, double peak) = await watch(tester);

    expect(seen.difference(<String>{'1290P', '1240P'}), isEmpty);
    expect(peak, 1);
    expect(pointsText(tester), '1240P');
  });

  testWidgets('움직임 줄이기에서는 새 숫자로 바로 바꾼다', (WidgetTester tester) async {
    await pumpPage(tester, disableAnimations: true);
    await tester.pumpAndSettle();

    ledger.award(PointsRule.exerciseManual, 'ex-1');
    await refetch(tester);
    final (Set<String> seen, double peak) = await watch(tester);

    expect(seen.difference(<String>{'1240P', '1260P'}), isEmpty);
    expect(peak, 1);
    expect(pointsText(tester), '1260P');
  });

  testWidgets('가려진 탭에서 받은 적립은 탭이 보일 때 움직인다', (WidgetTester tester) async {
    final ValueNotifier<bool> visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);
    await pumpPage(tester, visible: visible);
    await tester.pumpAndSettle();

    visible.value = false;
    await tester.pump();
    ledger.award(PointsRule.exerciseManual, 'ex-1');
    await refetch(tester);
    await tester.pump(const Duration(seconds: 2));
    // 회원이 보지 못하는 동안에는 이전 숫자에 머문다.
    expect(pointsText(tester), '1240P');

    visible.value = true;
    final (Set<String> seen, double peak) = await watch(tester);

    expect(
      seen.where((String s) => s != '1240P' && s != '1260P'),
      isNotEmpty,
    );
    expect(peak, greaterThan(1.1));
    await tester.pumpAndSettle();
    expect(pointsText(tester), '1260P');
  });
}
