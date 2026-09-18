/// 음식 수정 칸 맨 위의 `내용량(g)` 과 그 값에 따른 영양 비례 환산 (#1876).
///
/// 공공 영양 DB 는 100g 기준이고 서버 보정이 그 양으로 환산해 둔 값이 칸에
/// 적혀 있다. 그러니 "이거 300g 먹었어" 에 필요한 것은 DB 재조회가 아니라
/// 곱셈 한 번이다 — 섭취량과 그때의 영양을 함께 들고 있으면 된다.
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

Finder get _anyMealCard => find
    .byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('mealCard-'),
    )
    .first;

Finder _field(String key) => find.byKey(ValueKey<String>(key));

/// 보기 모드 음식 줄의 내용량 (#1964).
Finder _viewAmount(int index) =>
    find.byKey(ValueKey<String>('diet-food-view-amount-$index'));

/// 칸에 실제로 적혀 있는 글자. 비례 환산이 값을 다시 적으므로, `_foods` 가
/// 아니라 회원이 보는 칸을 확인해야 한다.
String _textOf(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: _field(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

/// 끼니 하나를 **보기 모드**로 연다 — 연필은 누르지 않는다.
Future<void> _openView(WidgetTester tester, FakeDietRepository repo) async {
  // 음식마다 영양 칸이 일곱 줄씩 붙어 화면이 길어진다 — `ListView` 가 영양
  // 정보 카드까지 실제로 짓도록 넉넉히 잡는다.
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
}

Future<void> _openEdit(WidgetTester tester, FakeDietRepository repo) async {
  await _openView(tester, repo);
  await tester.tap(find.byKey(const Key('mealDetailEditButton')));
  await tester.pumpAndSettle();
}

Future<DietEntry> _savedBreakfast(
  WidgetTester tester,
  FakeDietRepository repo,
) async => (await tester.runAsync(
  () => repo.fetchToday(),
))!.entries.firstWhere((DietEntry e) => e.id == 'mock-breakfast');

void main() {
  testWidgets('내용량 칸이 칼로리보다 먼저 온다 — 양을 아는 음식만 값이 차 있다', (
    WidgetTester tester,
  ) async {
    await _openEdit(tester, FakeDietRepository());

    expect(_field('diet-food-amount-1'), findsOneWidget);
    expect(find.text('내용량'), findsWidgets);
    // 아래 여섯 값의 기준이므로 그 값들보다 위에 있어야 한다.
    expect(
      tester.getTopLeft(_field('diet-food-amount-1')).dy,
      lessThan(tester.getTopLeft(_field('diet-food-kcal-1')).dy),
    );

    expect(_textOf(tester, 'diet-food-amount-1'), '100');
    // 딸기는 서버가 양을 얻지 못한 음식이다 — 빈 칸으로 열린다.
    expect(_textOf(tester, 'diet-food-amount-2'), '');
  });

  testWidgets('내용량을 두 배로 고치면 여섯 값이 모두 두 배가 된다', (WidgetTester tester) async {
    await _openEdit(tester, FakeDietRepository());

    await tester.enterText(_field('diet-food-amount-1'), '200');
    await tester.pumpAndSettle();

    expect(_textOf(tester, 'diet-food-kcal-1'), '370', reason: '185 × 2');
    expect(_textOf(tester, 'diet-food-carbs-1'), '4');
    expect(_textOf(tester, 'diet-food-sugar-1'), '1.6');
    expect(_textOf(tester, 'diet-food-protein-1'), '26');
    expect(_textOf(tester, 'diet-food-fat-1'), '28');
    expect(_textOf(tester, 'diet-food-sodium-1'), '440');

    // 영양 정보 카드의 합계도 저장 전에 이미 따라와 있다(딸기 몫을 더한 값).
    expect(find.text('402 kcal'), findsOneWidget, reason: '총 칼로리 370 + 32');
    expect(find.text('441'), findsOneWidget, reason: '나트륨 440 + 1');
    expect(find.text('7.1'), findsOneWidget, reason: '당류 1.6 + 5.5');
  });

  testWidgets('고친 내용량과 비례한 영양이 저장 뒤에도 남는다', (WidgetTester tester) async {
    final FakeDietRepository repo = FakeDietRepository();
    await _openEdit(tester, repo);

    await tester.enterText(_field('diet-food-amount-1'), '200');
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final DietEntry saved = await _savedBreakfast(tester, repo);
    final FoodItem egg = saved.foods.first;
    expect(egg.amountG, 200, reason: '양을 흘리면 다음에 열었을 때 기준이 사라진다');
    expect(egg.calories, 370);
    expect(egg.carbsG, 4);
    expect(egg.sugarG, closeTo(1.6, 0.001));
    expect(egg.proteinG, 26);
    expect(egg.fatG, 28);
    expect(egg.sodiumMg, 440);
    // 끼니 합계도 음식에서 다시 합쳐 보낸 값이어야 한다.
    expect(saved.totalCalories, 402);
    expect(saved.carbsG, 12);
    expect(saved.sodiumMg, 441);

    // 양을 몰랐던 음식은 여전히 null 이다 — 없는 값을 0 으로 지어내지 않는다.
    expect(saved.foods[1].amountG, isNull);
  });

  testWidgets('한 자씩 치는 동안 반올림이 쌓이지 않는다', (WidgetTester tester) async {
    await _openEdit(tester, FakeDietRepository());

    // `300` 은 한 번에 들어오지 않는다. 칸의 값에서 곱해 나가면 정수 반올림이
    // 단계마다 쌓여 555 대신 600 이 남는다 — 곱셈은 늘 기준 한 벌에서 한 번만.
    for (final String typed in <String>['3', '30', '300']) {
      await tester.enterText(_field('diet-food-amount-1'), typed);
      await tester.pumpAndSettle();
    }

    expect(_textOf(tester, 'diet-food-kcal-1'), '555', reason: '185 × 3');
    expect(_textOf(tester, 'diet-food-sodium-1'), '660', reason: '220 × 3');
    expect(_textOf(tester, 'diet-food-sugar-1'), '2.4', reason: '0.8 × 3');
  });

  testWidgets('양을 모르던 음식에 양을 적어도 영양은 그대로다 — 그때부터 기준이 된다', (
    WidgetTester tester,
  ) async {
    await _openEdit(tester, FakeDietRepository());

    // 딸기(32kcal)는 기준이 없다. 적어 넣었다고 값이 튀면 적기가 무서워진다.
    await tester.enterText(_field('diet-food-amount-2'), '150');
    await tester.pumpAndSettle();
    expect(_textOf(tester, 'diet-food-kcal-2'), '32');
    expect(_textOf(tester, 'diet-food-carbs-2'), '8');

    // 이제 기준이 섰으므로 두 배는 두 배다.
    await tester.enterText(_field('diet-food-amount-2'), '300');
    await tester.pumpAndSettle();
    expect(_textOf(tester, 'diet-food-kcal-2'), '64');
    expect(_textOf(tester, 'diet-food-carbs-2'), '16');
  });

  testWidgets('영양을 손으로 고친 뒤 양을 바꾸면 고친 값에서 비례한다', (WidgetTester tester) async {
    await _openEdit(tester, FakeDietRepository());

    // 분석이 틀렸을 때 쓰는 수동 보정 — 개별 칸은 그대로 남아 있다.
    await tester.enterText(_field('diet-food-kcal-1'), '200');
    await tester.pumpAndSettle();

    await tester.enterText(_field('diet-food-amount-1'), '200');
    await tester.pumpAndSettle();

    expect(
      _textOf(tester, 'diet-food-kcal-1'),
      '400',
      reason: '분석이 준 185 가 아니라 회원이 고친 200 에서 비례해야 한다',
    );
  });

  testWidgets('내용량 칸을 비워도 영양은 그대로 남고 기준도 살아 있다', (WidgetTester tester) async {
    await _openEdit(tester, FakeDietRepository());

    await tester.enterText(_field('diet-food-amount-1'), '');
    await tester.pumpAndSettle();
    // 양을 적지 않겠다는 뜻이지 아무것도 안 먹었다는 뜻이 아니다.
    expect(_textOf(tester, 'diet-food-kcal-1'), '185');

    await tester.enterText(_field('diet-food-amount-1'), '200');
    await tester.pumpAndSettle();
    expect(_textOf(tester, 'diet-food-kcal-1'), '370');
  });

  // 고칠 자리를 열어야만 기준이 드러나면 순서가 뒤집힌 것이다 — 옆의 칼로리가
  // 그 양을 재고 나온 값이라, 보기만 해도 함께 읽혀야 한다 (#1964).
  group('보기 모드에서도 내용량이 보인다', () {
    testWidgets('양을 아는 음식은 이름 옆에 적히고, 모르는 음식은 아무것도 적지 않는다', (
      WidgetTester tester,
    ) async {
      await _openView(tester, FakeDietRepository());

      expect(_viewAmount(1), findsOneWidget);
      expect(find.text('100g'), findsOneWidget, reason: '스크램블 에그');
      // 딸기는 서버가 양을 얻지 못한 음식이다. `0g` 이 뜨면 안 먹었다로 읽힌다.
      expect(_viewAmount(2), findsNothing);
      expect(find.text('0g'), findsNothing);
    });

    testWidgets('수정 모드에서 고친 양이 저장 뒤 보기 모드에도 이어진다', (WidgetTester tester) async {
      await _openEdit(tester, FakeDietRepository());

      await tester.enterText(_field('diet-food-amount-1'), '200');
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mealDetailEditButton')), findsOneWidget);
      expect(find.text('200g'), findsOneWidget);
      expect(find.text('100g'), findsNothing);
    });
  });
}
