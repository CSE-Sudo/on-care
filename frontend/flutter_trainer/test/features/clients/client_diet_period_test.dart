import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/design_system/tokens/colors.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/diet_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/metric_trend_chart.dart';

import '../../helpers/pump_app.dart';

/// 트레이너도 회원 식단을 `오늘 / 이번 주 / 이번 달` 로 본다. (#914)
///
/// 회원은 자기 앱에서 이미 세 기간을 골라 보는데, 정작 코칭하는 트레이너는
/// 오늘 하루밖에 못 봤다 — 회원이 "이번 주는 좀 과했어요" 라고 말해도 견줄
/// 화면이 없었다.
void main() {
  group('ClientDietPeriod', () {
    ClientDietPeriod periodOf(List<ClientDietDay> days) => ClientDietPeriod(
      range: (from: days.first.date, to: days.last.date),
      days: days,
    );

    test('평균은 기록이 있는 날만으로 나눈다', () {
      final period = periodOf(<ClientDietDay>[
        ClientDietDay(
          date: DateTime(2026, 8, 17),
          calories: 2000,
          sodiumMg: 1800,
          sugarG: 20,
        ),
        // 아직 오지 않은 날 / 적지 않은 날. 이 0 까지 나누면 달 초에는 평균이
        // 늘 실제보다 낮게 나온다.
        ClientDietDay(date: DateTime(2026, 8, 18)),
        ClientDietDay(
          date: DateTime(2026, 8, 19),
          calories: 2400,
          sodiumMg: 2200,
          sugarG: 30,
        ),
      ]);

      expect(period.loggedDays, 2);
      expect(period.avgCalories, 2200);
      expect(period.avgSodiumMg, 2000);
      expect(period.avgSugarG, 25);
      expect(period.isEmpty, isFalse);
    });

    test('기록이 하나도 없으면 비어 있다고 보고 0 으로 나누지 않는다', () {
      final period = periodOf(<ClientDietDay>[
        ClientDietDay(date: DateTime(2026, 8, 17)),
        ClientDietDay(date: DateTime(2026, 8, 18)),
      ]);

      expect(period.isEmpty, isTrue);
      expect(period.loggedDays, 0);
      expect(period.avgCalories, 0);
    });
  });

  group('기간 그래프가 회원 앱과 같은 그림이다 (#944)', () {
    Future<void> openDiet(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('이번 주는 꺾은선, 이번 달은 막대다', (tester) async {
      await openDiet(tester);

      await tester.tap(find.byKey(const Key('client-period-week')));
      await tester.pumpAndSettle();
      // 회원 앱과 같이 주는 꺾은선이다 — 7칸은 점과 값이 겹치지 않는다.
      expect(find.byType(MetricTrendChart), findsOneWidget);
      expect(find.byKey(const Key('client-diet-bar-0')), findsNothing);

      await tester.tap(find.byKey(const Key('client-period-month')));
      await tester.pumpAndSettle();
      // 30칸을 꺾은선으로 그리면 점과 값 라벨이 서로 겹친다.
      expect(find.byType(MetricTrendChart), findsNothing);
      expect(find.byKey(const Key('client-diet-bar-0')), findsOneWidget);
    });

    testWidgets('이번 달 칼로리 막대가 탄단지 3색으로 쌓인다', (tester) async {
      await openDiet(tester);
      await tester.tap(find.byKey(const Key('client-period-month')));
      await tester.pumpAndSettle();

      // 시드가 채운 날 중 하나를 고른다 — 기록이 없는 날은 쌓지 않는다.
      final Finder stacked = find.byWidgetPredicate(
        (Widget w) => w is ColoredBox && w.color == AppColors.macroCarbs,
      );
      expect(stacked, findsWidgets);

      // 색만 확인하면 폭 0 을 통과시킨다(회원 앱 #947 에서 밟은 함정).
      final RenderBox box = stacked.evaluate().first.renderObject! as RenderBox;
      expect(box.size.width, greaterThan(0));
      expect(box.size.height, greaterThan(0));

      // 어느 색이 무엇인지는 카드 **머리**의 탄단지 줄이 말한다 — 그래프
      // 아래 범례는 뺐다(#1167). 한 카드가 같은 말을 두 번 하지 않는다.
      expect(
        find.byKey(const ValueKey<String>('client-diet-period-macros')),
        findsOneWidget,
      );
    });

    testWidgets('나트륨으로 바꾸면 쌓지 않는다', (tester) async {
      await openDiet(tester);
      await tester.tap(find.byKey(const Key('client-period-month')));
      await tester.pumpAndSettle();

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(DietView)),
      );
      await tester.tap(find.text(l.metricSodium));
      await tester.pumpAndSettle();

      // 나트륨에는 쌓을 성분이 없다 — 한 색 막대로 돌아가고 머리의 탄단지
      // 줄도 사라진다. 카드 안으로 범위를 좁힌다 — `AppColors.macroCarbs`
      // 와 `AppColors.primary` 가 같은 색이라, 넓은 화면에서 옆에 함께
      // 뜨는 회원 목록의 정렬 툴바(선택 회원 주간 이행률 바)까지 훑으면
      // 이 카드와 무관한 primary색 막대까지 걸린다.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('client-diet-period-card')),
          matching: find.byWidgetPredicate(
            (Widget w) => w is ColoredBox && w.color == AppColors.macroCarbs,
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('client-diet-period-macros')),
        findsNothing,
      );
    });

    testWidgets('이름과 아이콘은 섹션 헤더가 들고, 카드는 그림만 그린다', (tester) async {
      await openDiet(tester);

      final Finder header = find.byKey(
        const ValueKey<String>('client-period-section-header'),
      );
      expect(header, findsOneWidget);
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(DietView)),
      );
      expect(
        find.descendant(
          of: header,
          matching: find.text(l.clientNutritionSummary),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: header,
          matching: find.byIcon(Icons.restaurant_outlined),
        ),
        findsOneWidget,
      );

      // 기간을 바꿔도 제목·아이콘이 나타났다 사라지지 않는다.
      final Rect atToday = tester.getRect(header);
      await tester.tap(find.byKey(const Key('client-period-month')));
      await tester.pumpAndSettle();
      expect(tester.getRect(header), atToday);
      expect(
        find.descendant(
          of: header,
          matching: find.text(l.clientNutritionSummary),
        ),
        findsOneWidget,
      );
    });
  });

  group('DietView 기간 토글', () {
    testWidgets('오늘로 열리고, 이번 주를 고르면 영양 추이로 바뀐다', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
      );
      await tester.pumpAndSettle();

      // 기본은 오늘 — 지금까지 보던 화면이 그대로 첫 화면이다.
      expect(
        find.byKey(const Key('client-nutrition-summary-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('client-period-toggle')),
        findsOneWidget,
      );

      // 배포 화면에서 사용하는 기간 토글 규격을 유지한다.
      final Container periodToggle = tester.widget<Container>(
        find.byKey(const ValueKey<String>('client-period-toggle')),
      );
      expect(periodToggle.padding, const EdgeInsets.all(3));

      final Finder todayButton = find.byKey(const Key('client-period-today'));
      final Padding todayPadding = tester.widget<Padding>(
        find.descendant(of: todayButton, matching: find.byType(Padding)).first,
      );
      expect(
        todayPadding.padding,
        const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      );
      final Text todayLabel = tester.widget<Text>(
        find.descendant(of: todayButton, matching: find.text('오늘')),
      );
      expect(todayLabel.style?.fontSize, 12.5);
      expect(
        find.byKey(const ValueKey<String>('client-diet-period-card')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('client-period-week')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('client-diet-period-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('client-nutrition-summary-card')),
        findsNothing,
      );
      // 토글은 카드 제목 줄에 그대로 남아, 되돌아갈 길이 사라지지 않는다.
      expect(
        find.byKey(const ValueKey<String>('client-period-toggle')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('client-period-month')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('client-diet-period-card')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('client-period-today')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('client-nutrition-summary-card')),
        findsOneWidget,
      );
    });
  });
}
