import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/meal_emoji.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_diet_repository.dart';

Finder _field(String key) => find.byKey(ValueKey<String>(key));

/// 식단 추가 시트를 열고, 시트가 끝난 결과(저장했나)를 [saved] 에 남긴다.
Future<List<bool>> _openAddSheet(
  WidgetTester tester,
  FakeDietRepository repository,
) async {
  final List<bool> saved = <bool>[];
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        dietRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // 저장 알림은 페이지가 닫힌 뒤 내비게이터 위 오버레이에 뜬다 — 앱과
        // 같은 자리를 둔다.
        builder: (BuildContext context, Widget? child) => Overlay(
          initialEntries: <OverlayEntry>[
            OverlayEntry(builder: (_) => child ?? const SizedBox.shrink()),
          ],
        ),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async =>
                    saved.add(await showDietAddSheet(context)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return saved;
}

void main() {
  group('식단 추가 시트 머리 (#2151)', () {
    testWidgets('닫기 X 대신 `+ 직접 추가` 가 있다', (WidgetTester tester) async {
      await _openAddSheet(tester, FakeDietRepository());

      expect(find.byKey(const Key('dietAddSheet')), findsOneWidget);
      expect(find.byIcon(AppIcons.close), findsNothing);
      final Finder button = find.byKey(const Key('dietManualAddButton'));
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.text('직접 추가')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: button, matching: find.byIcon(AppIcons.add)),
        findsOneWidget,
      );
    });

    testWidgets('바깥을 누르면 닫힌다', (WidgetTester tester) async {
      final List<bool> saved = await _openAddSheet(
        tester,
        FakeDietRepository(),
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dietAddSheet')), findsNothing);
      expect(saved, <bool>[false]);
    });
  });

  group('직접 추가 화면 (#2151)', () {
    testWidgets('`+ 직접 추가` 는 사진 없이 적는 화면을 연다', (WidgetTester tester) async {
      await _openAddSheet(tester, FakeDietRepository());

      await tester.tap(find.byKey(const Key('dietManualAddButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dietAddSheet')), findsNothing);
      expect(find.byKey(const Key('mealCreatePage')), findsOneWidget);
      expect(find.text('식단 직접 추가'), findsOneWidget);
      // 빈 음식 줄 하나로 연다.
      expect(_field('diet-food-name-1'), findsOneWidget);
      expect(_field('diet-food-name-2'), findsNothing);
      // 날짜는 오늘, 삭제 버튼은 없다 — 아직 없는 기록이다.
      expect(find.byKey(const Key('meal-create-date')), findsOneWidget);
      expect(find.text('식단 삭제'), findsNothing);
    });

    testWidgets('적은 음식으로 끼니를 저장하고 닫힌다', (WidgetTester tester) async {
      final FakeDietRepository repository = FakeDietRepository();
      final List<bool> saved = await _openAddSheet(tester, repository);
      await tester.tap(find.byKey(const Key('dietManualAddButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppChoiceChip, '저녁'));
      await tester.enterText(_field('diet-food-name-1'), '김밥');
      await tester.enterText(_field('diet-food-kcal-1'), '420');
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('meal-total'))).data,
        startsWith('420'),
      );

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(repository.created, hasLength(1));
      final created = repository.created.single;
      expect(created.mealType, 'dinner');
      expect(created.foods.single.name, '김밥');
      expect(created.foods.single.calories, 420);
      expect(find.byKey(const Key('mealCreatePage')), findsNothing);
      expect(saved, <bool>[true]);
    });

    testWidgets('이름 적힌 음식이 없으면 저장하지 않고 이유를 보인다', (WidgetTester tester) async {
      final FakeDietRepository repository = FakeDietRepository();
      await _openAddSheet(tester, repository);
      await tester.tap(find.byKey(const Key('dietManualAddButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(repository.created, isEmpty);
      expect(find.text('음식을 하나 이상 적어 주세요'), findsOneWidget);
      expect(find.byKey(const Key('mealCreatePage')), findsOneWidget);
    });

    testWidgets('취소는 저장하지 않고 닫는다', (WidgetTester tester) async {
      final FakeDietRepository repository = FakeDietRepository();
      final List<bool> saved = await _openAddSheet(tester, repository);
      await tester.tap(find.byKey(const Key('dietManualAddButton')));
      await tester.pumpAndSettle();
      await tester.enterText(_field('diet-food-name-1'), '김밥');

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(repository.created, isEmpty);
      expect(find.byKey(const Key('mealCreatePage')), findsNothing);
      expect(saved, <bool>[false]);
    });
  });

  group('사진 없는 끼니의 이모지 (#2151)', () {
    test('음식 이름으로 고른다', () {
      expect(foodEmoji('김치 라면'), '🍜');
      expect(foodEmoji('참치김밥'), '🍙');
      expect(foodEmoji('김치찌개'), '🍲');
      expect(foodEmoji('탕수육'), '🍖');
      expect(foodEmoji('치즈 버거'), '🍔');
      expect(foodEmoji('현미밥'), '🍚');
      expect(foodEmoji('할머니표 비법 반찬'), isNull);
      expect(foodEmoji('  '), isNull);
    });

    test('첫 음식부터 보고, 모르면 끼니 이모지다', () {
      expect(
        mealThumbEmoji(MealType.lunch, <String>['비법 반찬', '떡볶이', '김밥']),
        '🍢',
      );
      expect(mealThumbEmoji(MealType.breakfast, <String>['비법 반찬']), '🥣');
      expect(mealThumbEmoji(MealType.lateNight, <String>[]), '🌙');
    });
  });
}
