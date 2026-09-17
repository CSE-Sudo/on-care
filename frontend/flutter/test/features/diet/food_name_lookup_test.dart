/// 음식 이름을 고치면 공공 영양 DB 값을 **제안**한다 — 덮어쓰지는 않는다. (#1896)
///
/// 이름 변경은 "다른 음식이다" 일 수도 "오타를 고쳤다" 일 수도 있어 앱이 둘을
/// 구분할 수 없다. 자동으로 갈아 끼우면 회원이 개별 칸에서 손으로 바로잡아 둔
/// 값이 소리 없이 사라진다 — 그 칸이 있는 이유가 분석 오류 보정이다.
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

/// 시드의 짜장면 1인분 — 650g 에 700kcal.
const FoodNutritionSuggestion _jjajang = FoodNutritionSuggestion(
  matchedName: '짜장면',
  food: FoodItem(
    name: '짜장면',
    calories: 700,
    amountG: 650,
    sodiumMg: 2400,
    sugarG: 12,
    carbsG: 104,
    proteinG: 16,
    fatG: 20,
  ),
);

Finder get _anyMealCard => find
    .byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('mealCard-'),
    )
    .first;

Finder _field(String key) => find.byKey(ValueKey<String>(key));

String _textOf(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: _field(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

/// 이름 칸을 벗어난다 — 조회는 포커스를 잃을 때만 걸린다.
Future<void> _blurName(WidgetTester tester, int index) async {
  await tester.tap(_field('diet-food-amount-$index'));
  await tester.pumpAndSettle();
}

Future<void> _openEdit(WidgetTester tester, FakeDietRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(900, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

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
  await tester.tap(_anyMealCard);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('mealDetailEditButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('이름을 고쳐 칸을 벗어나면 공공 DB 값을 제안한다 — 값은 아직 그대로다', (
    WidgetTester tester,
  ) async {
    final FakeDietRepository repo = FakeDietRepository()
      ..nutritionByName['짜장면'] = _jjajang;
    await _openEdit(tester, repo);

    // 딸기(2번)는 섭취량을 모르는 음식이다 — 제안이 1회 섭취량을 들고 온다.
    await tester.enterText(_field('diet-food-name-2'), '짜장면');
    await tester.pumpAndSettle();
    // 아직 칸을 벗어나지 않았다 — 타이핑 중간값으로 부르지 않는다.
    expect(_field('diet-food-db-apply-2'), findsNothing);
    expect(repo.nutritionLookups, isEmpty);

    await _blurName(tester, 2);

    expect(find.text('공공 DB · 짜장면'), findsOneWidget);
    expect(repo.nutritionLookups, <String>['짜장면']);
    // 제안일 뿐이다 — 누르기 전에는 아무 값도 바뀌지 않는다.
    expect(_textOf(tester, 'diet-food-kcal-2'), '32');
    expect(_textOf(tester, 'diet-food-carbs-2'), '8');
    expect(_textOf(tester, 'diet-food-amount-2'), '');
  });

  testWidgets('값 채우기를 누르면 여섯 값과 내용량이 함께 채워진다', (WidgetTester tester) async {
    final FakeDietRepository repo = FakeDietRepository()
      ..nutritionByName['짜장면'] = _jjajang;
    await _openEdit(tester, repo);

    await tester.enterText(_field('diet-food-name-2'), '짜장면');
    await tester.pumpAndSettle();
    await _blurName(tester, 2);
    await tester.tap(_field('diet-food-db-apply-2'));
    await tester.pumpAndSettle();

    // 양을 몰랐으므로 그 음식의 1회 섭취량이 기준이 된다.
    expect(_textOf(tester, 'diet-food-amount-2'), '650');
    expect(_textOf(tester, 'diet-food-kcal-2'), '700');
    expect(_textOf(tester, 'diet-food-carbs-2'), '104');
    expect(_textOf(tester, 'diet-food-sugar-2'), '12');
    expect(_textOf(tester, 'diet-food-protein-2'), '16');
    expect(_textOf(tester, 'diet-food-fat-2'), '20');
    expect(_textOf(tester, 'diet-food-sodium-2'), '2400');
    // 채운 뒤에는 더 제안할 것이 없다.
    expect(_field('diet-food-db-apply-2'), findsNothing);

    // 채운 값이 곧 새 기준이다 — 이어서 양을 반으로 줄이면 비례로 따라온다(#1876).
    await tester.enterText(_field('diet-food-amount-2'), '325');
    await tester.pumpAndSettle();
    expect(_textOf(tester, 'diet-food-kcal-2'), '350');
    expect(_textOf(tester, 'diet-food-carbs-2'), '52');
  });

  testWidgets('이미 적어 둔 내용량이 있으면 그 양의 값으로 채운다', (WidgetTester tester) async {
    final FakeDietRepository repo = FakeDietRepository()
      ..nutritionByName['짜장면'] = _jjajang;
    await _openEdit(tester, repo);

    // 스크램블 에그(1번)는 100g 으로 적혀 있다 — 제안을 받았다고 내가 적은
    // 양이 뒤집히면 안 된다.
    await tester.enterText(_field('diet-food-name-1'), '짜장면');
    await tester.pumpAndSettle();
    await _blurName(tester, 1);
    await tester.tap(_field('diet-food-db-apply-1'));
    await tester.pumpAndSettle();

    expect(
      _textOf(tester, 'diet-food-amount-1'),
      '100',
      reason: '내가 적은 양이 이긴다',
    );
    expect(_textOf(tester, 'diet-food-kcal-1'), '108', reason: '700 × 100/650');
    expect(_textOf(tester, 'diet-food-carbs-1'), '16', reason: '104 × 100/650');
  });

  testWidgets('공공 DB 에 없는 이름이면 조용하다', (WidgetTester tester) async {
    final FakeDietRepository repo = FakeDietRepository();
    await _openEdit(tester, repo);

    await tester.enterText(_field('diet-food-name-2'), '할머니표 비법 반찬');
    await tester.pumpAndSettle();
    await _blurName(tester, 2);

    expect(_field('diet-food-db-apply-2'), findsNothing);
    expect(_textOf(tester, 'diet-food-kcal-2'), '32', reason: '값은 그대로다');
  });

  testWidgets('값이 이미 제안과 같으면 제안하지 않는다', (WidgetTester tester) async {
    // 분석이 이미 공공 DB 값을 채워 둔 음식이다. 이름을 읽으려고 칸을 스쳐도
    // `값 채우기` 가 서 있으면 누를 이유를 찾게 된다.
    final FakeDietRepository repo = FakeDietRepository()
      ..nutritionByName['스크램블 에그'] = const FoodNutritionSuggestion(
        matchedName: '스크램블 에그',
        food: FoodItem(
          name: '스크램블 에그',
          calories: 185,
          amountG: 100,
          sodiumMg: 220,
          sugarG: 0.8,
          carbsG: 2,
          proteinG: 13,
          fatG: 14,
        ),
      );
    await _openEdit(tester, repo);

    await tester.tap(_field('diet-food-name-1'));
    await tester.pumpAndSettle();
    await _blurName(tester, 1);

    expect(repo.nutritionLookups, <String>['스크램블 에그'], reason: '조회는 걸린다');
    expect(_field('diet-food-db-apply-1'), findsNothing, reason: '바뀔 것이 없다');
  });

  testWidgets('조회가 실패해도 수정과 저장은 막히지 않는다', (WidgetTester tester) async {
    final FakeDietRepository repo = FakeDietRepository()
      ..nutritionLookupFails = true;
    await _openEdit(tester, repo);

    await tester.enterText(_field('diet-food-name-2'), '짜장면');
    await tester.pumpAndSettle();
    await _blurName(tester, 2);

    expect(_field('diet-food-db-apply-2'), findsNothing);

    // 고치고 저장하는 길은 그대로다 — 제안은 거들 뿐이다.
    await tester.enterText(_field('diet-food-kcal-2'), '400');
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final DietEntry saved = (await tester.runAsync(
      () => repo.fetchToday(),
    ))!.entries.firstWhere((DietEntry e) => e.id == 'mock-breakfast');
    expect(saved.foods[1].name, '짜장면');
    expect(saved.foods[1].calories, 400);
  });

  testWidgets('이름을 지우면 제안도 사라진다', (WidgetTester tester) async {
    final FakeDietRepository repo = FakeDietRepository()
      ..nutritionByName['짜장면'] = _jjajang;
    await _openEdit(tester, repo);

    await tester.enterText(_field('diet-food-name-2'), '짜장면');
    await tester.pumpAndSettle();
    await _blurName(tester, 2);
    expect(_field('diet-food-db-apply-2'), findsOneWidget);

    await tester.enterText(_field('diet-food-name-2'), '');
    await tester.pumpAndSettle();
    await _blurName(tester, 2);

    // 무엇의 제안인지 알 수 없는 줄이 남아 있으면 안 된다.
    expect(_field('diet-food-db-apply-2'), findsNothing);
  });
}
