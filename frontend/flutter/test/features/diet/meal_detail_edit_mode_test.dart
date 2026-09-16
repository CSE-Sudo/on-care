/// 식단 상세는 보기로 열리고, 머리의 연필을 눌러야 고칠 수 있다 (#1856).
///
/// 대부분은 무엇을 먹었는지 다시 보려고 들어오지 고치려고 들어오지 않는다.
/// 수정 모드에서는 음식마다 그 음식의 영양까지 한자리에서 고친다 — 끼니 단위
/// 탄단지는 음식별 값의 합계라 영양 정보 카드에서는 고칠 자리가 없다.
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

Finder get _editButton => find.byKey(const Key('mealDetailEditButton'));
Finder get _firstFoodName =>
    find.byKey(const ValueKey<String>('diet-food-name-1'));
Finder get _firstFoodCarbs =>
    find.byKey(const ValueKey<String>('diet-food-carbs-1'));
Finder _foodSugar(int index) =>
    find.byKey(ValueKey<String>('diet-food-sugar-$index'));
Finder _sugarError(int index) =>
    find.byKey(ValueKey<String>('diet-food-sugar-$index-error'));

/// `mock-breakfast` 의 첫 음식(스크램블 에그)을 지금 저장된 대로 읽는다.
Future<FoodItem> _savedFirstFood(
  WidgetTester tester,
  FakeDietRepository repo,
) async => (await tester.runAsync(
  () => repo.fetchToday(),
))!.entries.firstWhere((DietEntry e) => e.id == 'mock-breakfast').foods.first;

Future<void> _openDetail(WidgetTester tester, FakeDietRepository repo) async {
  // 수정 모드에서는 음식마다 영양 칸이 여섯 줄씩 붙어 화면이 길어진다.
  // 영양 정보 카드까지 `ListView` 가 실제로 짓도록 넉넉히 잡는다.
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
        // 저장 성공 토스트가 내비게이터보다 위에 있는 오버레이를 찾는다.
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

void main() {
  testWidgets('상세는 보기로 열린다 — 입력 칸도 저장 버튼도 없다', (WidgetTester tester) async {
    await _openDetail(tester, FakeDietRepository());

    expect(_editButton, findsOneWidget);
    expect(_firstFoodName, findsNothing);
    expect(_firstFoodCarbs, findsNothing);
    expect(find.text('저장'), findsNothing);
    // 먹은 내용 자체는 보인다.
    expect(find.text('스크램블 에그'), findsOneWidget);
  });

  testWidgets('연필을 누르면 이름·칼로리와 음식별 영양 칸이 나온다', (WidgetTester tester) async {
    await _openDetail(tester, FakeDietRepository());

    await tester.tap(_editButton);
    await tester.pumpAndSettle();

    expect(_editButton, findsNothing, reason: '수정 중에는 연필이 사라진다');
    expect(_firstFoodName, findsOneWidget);
    expect(_firstFoodCarbs, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('diet-food-sodium-1')),
      findsOneWidget,
    );
    expect(find.text('저장'), findsOneWidget);
  });

  testWidgets('음식의 탄수화물을 고치면 합계가 따라오고 저장 뒤에도 남는다', (WidgetTester tester) async {
    final FakeDietRepository repo = FakeDietRepository();
    await _openDetail(tester, repo);

    await tester.tap(_editButton);
    await tester.pumpAndSettle();

    // 둘째 음식(딸기)이 8g 이라 합계가 99 가 되는 값을 넣는다 — 화면의 다른
    // 숫자와 겹치지 않아 합계를 글자로 집어낼 수 있다.
    await tester.enterText(_firstFoodCarbs, '91');
    await tester.pumpAndSettle();

    // 저장하기 전에 이미 영양 정보 카드의 합계가 따라와 있다.
    expect(find.text('99'), findsOneWidget);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final DietEntry saved = (await tester.runAsync(
      () => repo.fetchToday(),
    ))!.entries.firstWhere((DietEntry e) => e.id == 'mock-breakfast');
    expect(saved.foods.first.carbsG, 91);
    expect(saved.carbsG, 99);
  });

  testWidgets('취소하면 보기로 돌아가고 고치던 값이 되돌아간다', (WidgetTester tester) async {
    await _openDetail(tester, FakeDietRepository());

    await tester.tap(_editButton);
    await tester.pumpAndSettle();

    await tester.enterText(_firstFoodCarbs, '91');
    await tester.pumpAndSettle();
    expect(find.text('99'), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    // 화면을 나가지 않고 보기 모드로만 돌아간다.
    expect(find.byKey(const Key('mealDetailPage')), findsOneWidget);
    expect(_editButton, findsOneWidget);
    expect(_firstFoodCarbs, findsNothing);
    expect(find.text('99'), findsNothing);
    expect(find.text('10'), findsWidgets, reason: '원래 합계 2 + 8');
  });

  testWidgets('저장하면 화면에 남아 보기 모드로 돌아가고 고친 값이 그대로 보인다', (
    WidgetTester tester,
  ) async {
    await _openDetail(tester, FakeDietRepository());

    await tester.tap(_editButton);
    await tester.pumpAndSettle();
    await tester.enterText(_firstFoodCarbs, '91');
    await tester.pumpAndSettle();

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    // 목록으로 나가 버리면 방금 고친 값이 어떻게 됐는지 확인할 자리가 없다.
    expect(find.byKey(const Key('mealDetailPage')), findsOneWidget);
    expect(_editButton, findsOneWidget, reason: '보기 모드로 돌아온다');
    expect(_firstFoodCarbs, findsNothing);
    expect(find.text('99'), findsOneWidget, reason: '고친 합계가 그대로 보인다');
  });

  testWidgets('음식 칼로리를 고치면 총 칼로리가 곧바로 따라온다', (WidgetTester tester) async {
    await _openDetail(tester, FakeDietRepository());

    await tester.tap(_editButton);
    await tester.pumpAndSettle();
    expect(find.text('217 kcal'), findsOneWidget, reason: '185 + 32');

    // 스크램블 에그 185 → 900. 딸기 32 와 합쳐 932 가 되어야 한다.
    await tester.enterText(
      find.byKey(const ValueKey<String>('diet-food-kcal-1')),
      '900',
    );
    await tester.pumpAndSettle();

    expect(find.text('932 kcal'), findsOneWidget);
    expect(find.text('217 kcal'), findsNothing);
  });

  testWidgets('음식별 나트륨·당류를 고치면 끼니 합계도 따라 저장된다', (WidgetTester tester) async {
    final FakeDietRepository repo = FakeDietRepository();
    await _openDetail(tester, repo);

    await tester.tap(_editButton);
    await tester.pumpAndSettle();
    // 스크램블 에그 당류 0.8 → 2. 딸기 5.5 와 합쳐 7.5 가 되어야 한다.
    // 그 음식의 탄수화물(2g)을 넘는 값은 이제 저장이 막히므로(#1869), 합계가
    // 따라오는지 보는 이 검사는 넘지 않는 값으로 확인한다.
    await tester.enterText(_foodSugar(1), '2');
    await tester.pumpAndSettle();

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final DietEntry saved = (await tester.runAsync(
      () => repo.fetchToday(),
    ))!.entries.firstWhere((DietEntry e) => e.id == 'mock-breakfast');
    expect(saved.foods.first.sugarG, 2);
    expect(saved.sugarG, 7.5, reason: '끼니 행에도 따로 저장되므로 음식에서 다시 합쳐 보내야 한다');
  });

  testWidgets('음식을 모두 지우고 저장하면 식단을 지울지 묻는다', (WidgetTester tester) async {
    await _openDetail(tester, FakeDietRepository());

    await tester.tap(_editButton);
    await tester.pumpAndSettle();

    // 뒤에서부터 지운다 — 앞에서 지우면 남은 줄의 번호가 밀린다.
    await tester.tap(find.byKey(const ValueKey<String>('diet-food-remove-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('diet-food-remove-1')));
    await tester.pumpAndSettle();

    // 지우는 도중에는 아무것도 묻지 않는다.
    expect(find.text('음식이 하나도 남지 않았어요. 이 식단 기록을 삭제할까요?'), findsNothing);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('음식이 하나도 남지 않았어요. 이 식단 기록을 삭제할까요?'), findsOneWidget);
  });

  // 당류는 탄수화물의 일부라 그보다 클 수 없다. 서버도 같은 값을 422 로
  // 거절하므로(#1863), 앱이 먼저 막지 않으면 다 적고 저장을 누른 뒤에야
  // 어느 칸이 문제인지 모르는 실패 토스트만 뜬다 (#1869).
  group('당류는 탄수화물보다 클 수 없다', () {
    testWidgets('저장을 누르기 전에는 오류가 뜨지 않는다', (WidgetTester tester) async {
      await _openDetail(tester, FakeDietRepository());

      await tester.tap(_editButton);
      await tester.pumpAndSettle();

      // 스크램블 에그는 탄수화물 2g 이다 — 9 는 이미 어긋난 값이다.
      await tester.enterText(_foodSugar(1), '9');
      await tester.pumpAndSettle();

      // 치는 도중에 빨간 글씨가 먼저 뜨면 틀린 것처럼 보인다(#1784).
      expect(_sugarError(1), findsNothing);
    });

    testWidgets('저장을 누르면 그 음식의 당류 칸 아래에 이유가 뜨고 저장이 나가지 않는다', (
      WidgetTester tester,
    ) async {
      final FakeDietRepository repo = FakeDietRepository();
      await _openDetail(tester, repo);

      await tester.tap(_editButton);
      await tester.pumpAndSettle();
      await tester.enterText(_foodSugar(1), '9');
      await tester.pumpAndSettle();

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(_sugarError(1), findsOneWidget);
      expect(find.text('당류는 탄수화물보다 클 수 없어요'), findsOneWidget);
      expect(find.text('저장'), findsOneWidget, reason: '수정 모드에 머문다');
      expect(
        (await _savedFirstFood(tester, repo)).sugarG,
        0.8,
        reason: '요청이 나가지 않았으므로 저장된 값은 그대로다',
      );
    });

    testWidgets('오류는 틀린 음식에만 붙는다', (WidgetTester tester) async {
      await _openDetail(tester, FakeDietRepository());

      await tester.tap(_editButton);
      await tester.pumpAndSettle();
      // 딸기는 탄수화물 8g 이다.
      await tester.enterText(_foodSugar(2), '9');
      await tester.pumpAndSettle();

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(_sugarError(2), findsOneWidget);
      expect(_sugarError(1), findsNothing, reason: '스크램블 에그는 멀쩡하다');
    });

    testWidgets('고치면 문구가 사라지고 저장이 나간다', (WidgetTester tester) async {
      final FakeDietRepository repo = FakeDietRepository();
      await _openDetail(tester, repo);

      await tester.tap(_editButton);
      await tester.pumpAndSettle();
      await tester.enterText(_foodSugar(1), '9');
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(_sugarError(1), findsOneWidget);

      // 한 번 보인 칸은 그 뒤로 고치는 대로 다시 검사한다 — 저장을 다시
      // 누르지 않아도 문구가 사라져야 고친 것이 맞는지 알 수 있다.
      await tester.enterText(_foodSugar(1), '1.5');
      await tester.pumpAndSettle();
      expect(_sugarError(1), findsNothing);

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect((await _savedFirstFood(tester, repo)).sugarG, 1.5);
    });

    testWidgets('당류를 그대로 두고 탄수화물을 올려도 문구가 사라진다', (WidgetTester tester) async {
      await _openDetail(tester, FakeDietRepository());

      await tester.tap(_editButton);
      await tester.pumpAndSettle();
      await tester.enterText(_foodSugar(1), '9');
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(_sugarError(1), findsOneWidget);

      // 고칠 칸이 당류라고 정해져 있지 않다 — 탄수화물을 덜 적었을 수도 있다.
      await tester.enterText(_firstFoodCarbs, '20');
      await tester.pumpAndSettle();

      expect(_sugarError(1), findsNothing);
    });

    testWidgets('당류와 탄수화물이 같으면 통과한다', (WidgetTester tester) async {
      final FakeDietRepository repo = FakeDietRepository();
      await _openDetail(tester, repo);

      await tester.tap(_editButton);
      await tester.pumpAndSettle();
      // 전부 당인 음식이 있다 — 같은 값은 막지 않는다.
      await tester.enterText(_foodSugar(1), '2');
      await tester.pumpAndSettle();

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(_sugarError(1), findsNothing);
      expect((await _savedFirstFood(tester, repo)).sugarG, 2);
    });

    testWidgets('탄수화물이 0 이면 막지 않는다 — 서버와 같은 판단', (WidgetTester tester) async {
      final FakeDietRepository repo = FakeDietRepository();
      await _openDetail(tester, repo);

      await tester.tap(_editButton);
      await tester.pumpAndSettle();
      // 탄수화물 없이 저장된 옛 기록이 있다. 앱만 막으면 서버가 받아 주는
      // 기록을 고칠 길이 없다(#1877).
      await tester.enterText(_firstFoodCarbs, '');
      await tester.enterText(_foodSugar(1), '9');
      await tester.pumpAndSettle();

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(_sugarError(1), findsNothing);
      expect((await _savedFirstFood(tester, repo)).sugarG, 9);
    });

    testWidgets('취소하고 다시 펴면 빨간 글씨가 남아 있지 않다', (WidgetTester tester) async {
      await _openDetail(tester, FakeDietRepository());

      await tester.tap(_editButton);
      await tester.pumpAndSettle();
      await tester.enterText(_foodSugar(1), '9');
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(_sugarError(1), findsOneWidget);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      await tester.tap(_editButton);
      await tester.pumpAndSettle();

      // 저장을 누른 적 없는 화면에 오류가 먼저 서 있으면 안 된다.
      expect(_sugarError(1), findsNothing);
    });
  });
}
