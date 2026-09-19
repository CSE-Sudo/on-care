/// 식단 화면의 시각 표시 제거와 끼니 순서 고정. (#1989)
///
/// 시각이 사라지면 카드를 줄 세우는 기준도 사라진다. 서버는 저장 순서
/// (`created_at`)로 내려주므로, 어제 저녁 사진을 오늘 아침에 올리면 아침 카드
/// 아래에 저녁 카드가 붙는다 — 시각이 보이던 동안에는 그 순서가 읽혔지만
/// 이제는 읽을 것이 없다.
///
/// `time_label` 은 계속 저장되고 서버 계약도 그대로다. 화면에서 내리는 것과
/// 값을 버리는 것은 다르다 — 대역도 시각을 계속 들고 있으므로, 아래 검사는
/// "값이 없어서 안 보인다" 가 아니라 "화면이 그리지 않는다" 를 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';

DietEntry _entry(String id, MealType meal, String time) => DietEntry(
  id: id,
  mealType: meal,
  timeLabel: time,
  totalCalories: 100,
  foods: const <FoodItem>[FoodItem(name: '음식', calories: 100)],
);

List<String> _ids(List<DietEntry> entries) => <String>[
  for (final DietEntry e in entries) e.id!,
];

void main() {
  group('끼니 순서 고정', () {
    test('저장 순서와 상관없이 아침·점심·저녁·간식·야식 순으로 선다', () {
      // 서버가 준 순서는 저장 순서다 — 어제 저녁을 오늘 아침에 올린 모양.
      final List<DietEntry> saved = <DietEntry>[
        _entry('dinner', MealType.dinner, '19:00'),
        _entry('late', MealType.lateNight, '23:10'),
        _entry('breakfast', MealType.breakfast, '08:20'),
        _entry('snack', MealType.snack, '15:30'),
        _entry('lunch', MealType.lunch, '12:40'),
      ];

      expect(_ids(sortedByMealType(saved)), <String>[
        'breakfast',
        'lunch',
        'dinner',
        'snack',
        'late',
      ]);
    });

    test('같은 끼니가 둘 이상이면 그 안에서는 저장 순서를 따른다', () {
      final List<DietEntry> saved = <DietEntry>[
        _entry('snack-2', MealType.snack, '16:00'),
        _entry('breakfast', MealType.breakfast, '08:20'),
        _entry('snack-1', MealType.snack, '10:30'),
      ];

      // 간식 둘은 서로 자리를 바꾸지 않는다 — `List.sort` 는 안정 정렬이
      // 아니므로 순번을 함께 비교해야 이 순서가 지켜진다.
      expect(_ids(sortedByMealType(saved)), <String>[
        'breakfast',
        'snack-2',
        'snack-1',
      ]);
    });

    test('끼니가 하나뿐이거나 비어 있어도 죽지 않는다', () {
      expect(sortedByMealType(<DietEntry>[]), isEmpty);
      expect(
        _ids(sortedByMealType(<DietEntry>[_entry('a', MealType.dinner, '')])),
        <String>['a'],
      );
    });

    test('원본 목록을 뒤집지 않는다', () {
      // 서버 응답을 그대로 들고 있는 상태를 정렬이 건드리면, 같은 목록을 읽는
      // 다른 화면이 영향을 받는다.
      final List<DietEntry> saved = <DietEntry>[
        _entry('dinner', MealType.dinner, '19:00'),
        _entry('breakfast', MealType.breakfast, '08:20'),
      ];

      sortedByMealType(saved);

      expect(_ids(saved), <String>['dinner', 'breakfast']);
    });
  });

  group('시각 표시 제거', () {
    Future<void> pumpDiet(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
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
    }

    testWidgets('끼니 카드 어디에도 시각이 없다', (WidgetTester tester) async {
      await pumpDiet(tester);

      // 대역은 이 세 시각을 `time_label` 로 계속 준다.
      for (final String time in <String>['08:20', '12:40', '15:30']) {
        expect(find.text(time), findsNothing, reason: '$time 이 아직 화면에 그려진다');
      }
    });

    testWidgets('끼니 배지는 그대로 남는다', (WidgetTester tester) async {
      await pumpDiet(tester);

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(DietRecordPage)),
      );
      // 시각만 내린 것이지 카드 머리를 통째로 지운 것이 아니다.
      expect(find.text(l.dietMealBreakfast), findsWidgets);
      expect(find.text(l.dietMealLunch), findsWidgets);
    });
  });
}
