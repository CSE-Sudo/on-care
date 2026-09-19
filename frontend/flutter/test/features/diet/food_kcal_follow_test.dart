/// 탄수화물·단백질·지방을 고치면 열량이 **바뀐 만큼만** 따라온다. (#2106)
///
/// 4·4·9 로 새로 계산해 덮지 않는다. 공공 DB 열량은 식품마다 다른 에너지
/// 환산계수를 써서, 새로 계산하면 지방만 줄였는데도 성분표가 알던 몫이 함께
/// 사라진다(삼겹살 구운것 100g 484kcal, 4·4·9 로는 462kcal).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';

/// 삼겹살 구운것 200g — 성분표 값(100g 484kcal·단백질 22.78g·지방 41.2g)의 두 배.
const FoodItem _pork = FoodItem(
  name: '삼겹살',
  calories: 968,
  amountG: 200,
  sodiumMg: 160,
  proteinG: 45.6,
  fatG: 82.4,
  source: FoodSource.db,
);

/// 인식기가 탄단지를 주지 않은 옛 기록(#1877) — 열량만 있다.
const FoodItem _oldNoodles = FoodItem(
  name: '짜장면',
  calories: 700,
  sodiumMg: 2400,
);

/// 4·4·9 보다 열량이 낮은 음식(38.7 > 20). 버섯처럼 식이섬유가 많으면 그렇다.
const FoodItem _mushroom = FoodItem(
  name: '버섯볶음',
  calories: 20,
  amountG: 100,
  carbsG: 6,
  proteinG: 3,
  fatG: 0.3,
);

Finder _field(String key) => find.byKey(ValueKey<String>(key));

String _textOf(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: _field(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(_field(key), text);
  await tester.pumpAndSettle();
}

/// 아침 끼니를 [foods] 로 깔고 수정 모드로 연다.
Future<FakeDietRepository> _openEdit(
  WidgetTester tester,
  List<FoodItem> foods,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final FakeDietRepository repo = FakeDietRepository();
  await tester.runAsync(
    () => repo.updateEntry(id: 'mock-breakfast', foods: foods),
  );

  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const DietRecordPage()),
      GoRoute(
        path: '/diet/entries/:entryId',
        builder: (BuildContext context, GoRouterState state) =>
            DietMealDetailPage(
              entryId: state.pathParameters['entryId']!,
              initialMeal: state.extra as DietMeal?,
            ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[dietRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (BuildContext context, Widget? child) => Overlay(
          initialEntries: <OverlayEntry>[
            OverlayEntry(builder: (_) => child ?? const SizedBox.shrink()),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('mealCard-mock-breakfast')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('mealDetailEditButton')));
  await tester.pumpAndSettle();
  return repo;
}

Future<List<FoodItem>> _save(
  WidgetTester tester,
  FakeDietRepository repo,
) async {
  await tester.tap(find.text('저장'));
  await tester.pumpAndSettle();
  return (await tester.runAsync(
    () => repo.fetchToday(),
  ))!.entries.firstWhere((DietEntry e) => e.id == 'mock-breakfast').foods;
}

void main() {
  testWidgets('지방을 줄이면 열량이 바뀐 만큼만 준다 — 4·4·9 로 새로 계산하지 않는다', (
    WidgetTester tester,
  ) async {
    final FakeDietRepository repo = await _openEdit(tester, <FoodItem>[_pork]);

    // 한 글자씩 들어온다. 기준이 글자마다 다시 서면 반올림이 쌓인다.
    await _type(tester, 'diet-food-fat-1', '6');
    await _type(tester, 'diet-food-fat-1', '60');

    // 968 − 9 × 22.4 = 766.4. 새로 계산하면 45.6×4 + 60×9 = 722 다.
    expect(_textOf(tester, 'diet-food-kcal-1'), '766');

    final List<FoodItem> saved = await _save(tester, repo);
    expect(saved.single.calories, 766);
    expect(saved.single.fatG, 60);
  });

  testWidgets('열량을 먼저 적으면 그 뒤 탄단지를 적어도 열량이 남는다', (WidgetTester tester) async {
    await _openEdit(tester, <FoodItem>[_pork]);

    // 영양 표시 라벨을 옮겨 적는 중이다.
    await _type(tester, 'diet-food-kcal-1', '900');
    await _type(tester, 'diet-food-fat-1', '70');
    await _type(tester, 'diet-food-protein-1', '50');

    expect(_textOf(tester, 'diet-food-kcal-1'), '900');
  });

  testWidgets('탄단지를 먼저 적고 열량을 적어도 열량이 남는다', (WidgetTester tester) async {
    await _openEdit(tester, <FoodItem>[_pork]);

    await _type(tester, 'diet-food-fat-1', '70');
    expect(
      _textOf(tester, 'diet-food-kcal-1'),
      '856',
      reason: '968 − 9 × 12.4',
    );

    await _type(tester, 'diet-food-kcal-1', '900');
    await _type(tester, 'diet-food-protein-1', '50');

    expect(_textOf(tester, 'diet-food-kcal-1'), '900', reason: '적은 순서와 상관없다');
  });

  testWidgets('열량을 직접 고쳐도 탄단지는 그대로다 — 한 방향만 잇는다', (WidgetTester tester) async {
    await _openEdit(tester, <FoodItem>[_pork]);

    await _type(tester, 'diet-food-kcal-1', '500');

    expect(_textOf(tester, 'diet-food-protein-1'), '45.6');
    expect(_textOf(tester, 'diet-food-fat-1'), '82.4');
  });

  testWidgets('탄단지 없던 옛 기록(#1877)은 채워 넣어도 열량이 그대로다', (
    WidgetTester tester,
  ) async {
    await _openEdit(tester, <FoodItem>[_oldNoodles]);

    // 한 글자씩 — `1` 을 친 뒤에도 "채우기" 로 남아야 한다.
    await _type(tester, 'diet-food-carbs-1', '1');
    await _type(tester, 'diet-food-carbs-1', '12');
    await _type(tester, 'diet-food-carbs-1', '128');
    await _type(tester, 'diet-food-protein-1', '18');

    // 반영하면 700 + 4 × 128 + 4 × 18 = 1,284kcal 로 두 번 센다.
    expect(_textOf(tester, 'diet-food-kcal-1'), '700');
  });

  testWidgets('새로 추가한 음식은 0 에서 4·4·9 로 채워진다', (WidgetTester tester) async {
    await _openEdit(tester, <FoodItem>[_pork]);
    await tester.tap(find.text('음식 추가'));
    await tester.pumpAndSettle();

    await _type(tester, 'diet-food-carbs-2', '30');
    await _type(tester, 'diet-food-protein-2', '20');
    await _type(tester, 'diet-food-fat-2', '10');

    expect(_textOf(tester, 'diet-food-kcal-2'), '290');
  });

  testWidgets('당류·나트륨은 열량에 들어가지 않는다', (WidgetTester tester) async {
    await _openEdit(tester, <FoodItem>[_mushroom]);

    await _type(tester, 'diet-food-sugar-1', '2');
    await _type(tester, 'diet-food-sodium-1', '300');

    expect(_textOf(tester, 'diet-food-kcal-1'), '20');
  });

  testWidgets('열량은 0 아래로 내려가지 않는다', (WidgetTester tester) async {
    await _openEdit(tester, <FoodItem>[_mushroom]);

    // 20 − 4 × 6 = −4.
    await _type(tester, 'diet-food-carbs-1', '0');

    expect(_textOf(tester, 'diet-food-kcal-1'), '', reason: '0 은 빈 칸으로 보인다');
  });

  testWidgets('섭취량을 바꾼 뒤에는 그 양의 값에서 바뀐 만큼 움직인다', (WidgetTester tester) async {
    await _openEdit(tester, <FoodItem>[_pork]);

    await _type(tester, 'diet-food-fat-1', '60');
    expect(_textOf(tester, 'diet-food-kcal-1'), '766');

    // 양이 반이면 여섯 값이 함께 반이 된다(#1876) — 고친 지방에서 비례한다.
    await _type(tester, 'diet-food-amount-1', '100');
    expect(_textOf(tester, 'diet-food-kcal-1'), '383');
    expect(_textOf(tester, 'diet-food-fat-1'), '30');
    expect(_textOf(tester, 'diet-food-protein-1'), '22.8');

    // 이제 기준은 100g 의 한 벌이다. 383 + 4 × 7.2 = 411.8.
    await _type(tester, 'diet-food-protein-1', '30');
    expect(_textOf(tester, 'diet-food-kcal-1'), '412');
  });
}
