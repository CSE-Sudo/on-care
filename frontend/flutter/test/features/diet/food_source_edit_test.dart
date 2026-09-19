/// 식단을 고쳐 저장해도 음식마다 영양 출처가 맞게 남는다. (#2105)
///
/// 예전에는 수정 저장 한 번에 모든 음식이 `estimate` 가 됐다 — 앱이 출처를 읽을
/// 때 버리고 보낼 때도 싣지 않아, 서버가 빠진 값을 인식기 기본값으로 채웠다.
/// 출처는 "지금 칸의 숫자가 어디서 왔나" 다. 손대지 않았거나 양만 바꾼 음식은
/// 원래 출처, 공공 DB 값으로 채운 음식은 `db`, 회원이 영양 칸을 고친 음식은
/// `member` 다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/food_nutrition_suggestion.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';

/// 아침 끼니: 공공 DB × 양(`db`) · 인식기 추정(`estimate`) · DB 에 탄단지가 비어
/// 인식기 값을 남긴 것(`mixed`).
const List<FoodItem> _breakfast = <FoodItem>[
  FoodItem(
    name: '스크램블 에그',
    calories: 185,
    amountG: 100,
    sodiumMg: 220,
    sugarG: 0.8,
    carbsG: 2,
    proteinG: 13,
    fatG: 14,
    source: FoodSource.db,
  ),
  FoodItem(
    name: '딸기',
    calories: 32,
    sodiumMg: 1,
    sugarG: 5.5,
    carbsG: 8,
    proteinG: 0.5,
    fatG: 0.5,
  ),
  FoodItem(
    name: '그래놀라 토핑',
    calories: 90,
    amountG: 20,
    sodiumMg: 30,
    carbsG: 13,
    proteinG: 2,
    fatG: 3,
    source: FoodSource.mixed,
  ),
];

/// 비슷한 음식(이름 끝말로 붙음) — 제안만 한다.
const FoodNutritionSuggestion _bananaLike = FoodNutritionSuggestion(
  matchedName: '바나나',
  food: FoodItem(
    name: '바나나',
    calories: 93,
    amountG: 100,
    sugarG: 12,
    carbsG: 23,
    proteinG: 1,
    fatG: 0.2,
    source: FoodSource.db,
  ),
);

Finder _field(String key) => find.byKey(ValueKey<String>(key));

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(_field(key), text);
  await tester.pumpAndSettle();
}

Future<FakeDietRepository> _openEdit(
  WidgetTester tester, {
  FakeDietRepository? repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final FakeDietRepository repo = repository ?? FakeDietRepository();
  await tester.runAsync(
    () => repo.updateEntry(id: 'mock-breakfast', foods: _breakfast),
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

Future<List<FoodSource>> _savedSources(
  WidgetTester tester,
  FakeDietRepository repo,
) async {
  await tester.tap(find.text('저장'));
  await tester.pumpAndSettle();
  return (await tester.runAsync(() => repo.fetchToday()))!.entries
      .firstWhere((DietEntry e) => e.id == 'mock-breakfast')
      .foods
      .map((FoodItem f) => f.source)
      .toList();
}

void main() {
  testWidgets('손대지 않은 음식은 원래 출처로 저장된다 — 고친 음식만 member', (
    WidgetTester tester,
  ) async {
    final FakeDietRepository repo = await _openEdit(tester);

    await _type(tester, 'diet-food-sodium-2', '10');

    expect(await _savedSources(tester, repo), <FoodSource>[
      FoodSource.db,
      FoodSource.member,
      FoodSource.mixed,
    ]);
  });

  testWidgets('섭취량만 바꾼 음식은 출처가 그대로다 — 여전히 DB × 양이다', (
    WidgetTester tester,
  ) async {
    final FakeDietRepository repo = await _openEdit(tester);

    await _type(tester, 'diet-food-amount-1', '150');
    await _type(tester, 'diet-food-amount-3', '30');
    // 양을 모르던 음식에 양만 적었다 — 값은 그대로라 추정은 추정이다.
    await _type(tester, 'diet-food-amount-2', '150');

    expect(await _savedSources(tester, repo), <FoodSource>[
      FoodSource.db,
      FoodSource.estimate,
      FoodSource.mixed,
    ]);
  });

  testWidgets('열량·탄단지를 고친 음식은 member 다 — 따라온 열량도 회원 입력이다', (
    WidgetTester tester,
  ) async {
    final FakeDietRepository repo = await _openEdit(tester);

    await _type(tester, 'diet-food-kcal-1', '200');
    await _type(tester, 'diet-food-fat-3', '5');

    expect(await _savedSources(tester, repo), <FoodSource>[
      FoodSource.member,
      FoodSource.estimate,
      FoodSource.member,
    ]);
  });

  testWidgets('공공 DB 값으로 채운 음식은 db 다', (WidgetTester tester) async {
    final FakeDietRepository repo = FakeDietRepository()
      ..nutritionByName['바나나'] = _bananaLike;
    await _openEdit(tester, repository: repo);

    await _type(tester, 'diet-food-name-2', '바나나');
    await tester.tap(_field('diet-food-amount-2'));
    await tester.pumpAndSettle();
    await tester.tap(_field('diet-food-db-apply-2'));
    await tester.pumpAndSettle();

    expect((await _savedSources(tester, repo))[1], FoodSource.db);
  });

  testWidgets('새로 추가한 음식은 member 다', (WidgetTester tester) async {
    final FakeDietRepository repo = await _openEdit(tester);
    await tester.tap(find.text('음식 추가'));
    await tester.pumpAndSettle();

    await _type(tester, 'diet-food-name-4', '직접 만든 샐러드');
    await _type(tester, 'diet-food-kcal-4', '150');

    expect((await _savedSources(tester, repo))[3], FoodSource.member);
  });
}
