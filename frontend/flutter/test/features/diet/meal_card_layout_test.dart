/// 식단 기록 카드를 사진·끼니·메뉴명·칼로리 한 줄로 재구성. (#1990)
///
/// 예전 카드는 두 층이었다 — 위층에 `[아침] ⋯ >`, 아래층에 `[사진] 메뉴명 ⋯
/// [217 kcal]`. 끼니 배지와 사진이 서로 다른 줄에 있어 카드를 훑을 때 눈이
/// 위아래로 한 번 꺾였고, 사진도 56dp 라 무엇을 먹었는지 알아보기 어려웠다.
///
/// 이제 사진을 왼쪽에 크게 두고, 그 오른쪽 위층에 `끼니 배지 ⋯ >`, 가운데 층에
/// `메뉴명 ⋯ 총 칼로리` 를 둔다. 칼로리는 메뉴명 블록의 세로 가운데, 화살표와
/// 같은 오른쪽 세로선에 선다 — 목록을 훑을 때 칼로리가 한 선에 모인다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/meal_photo_view.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_diet_repository.dart';

/// 오늘 끼니를 직접 정하는 대역 — 음식 수가 다른 끼니를 한 화면에 둔다.
class _MealsRepository extends FakeDietRepository {
  _MealsRepository(this._entries);

  final List<DietEntry> _entries;

  @override
  Future<DietDay> fetchToday() async => DietDay(
    entries: _entries,
    totalCalories: _entries.fold<int>(
      0,
      (int a, DietEntry e) => a + e.totalCalories,
    ),
    totalSodiumMg: 0,
    totalSugarG: 0,
    macros: const DietMacros.zero(),
    aiCoachMessage: '',
  );
}

DietEntry _meal(String id, MealType type, List<String> foods) => DietEntry(
  id: id,
  mealType: type,
  timeLabel: '12:00',
  totalCalories: 100 * foods.length,
  foods: <FoodItem>[
    for (final String f in foods) FoodItem(name: f, calories: 100),
  ],
);

Finder _card(String id) => find.byKey(Key('mealCard-$id'));

Finder _inCard(String id, Finder matching) =>
    find.descendant(of: _card(id), matching: matching);

Future<void> _pump(
  WidgetTester tester,
  FakeDietRepository repo, {
  Size size = const Size(400, 2400),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[dietRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const DietRecordPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('한 층으로 읽힌다', () {
    testWidgets('사진이 왼쪽, 그 오른쪽 위층에 끼니·가운데 층에 메뉴명과 칼로리다', (
      WidgetTester tester,
    ) async {
      await _pump(tester, FakeDietRepository());
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(DietRecordPage)),
      );

      final Rect photo = tester.getRect(
        _inCard('mock-breakfast', find.byType(MealPhotoView)),
      );
      final Rect badge = tester.getRect(
        _inCard('mock-breakfast', find.text(l.dietMealBreakfast)),
      );
      final Rect first = tester.getRect(
        _inCard('mock-breakfast', find.text('스크램블 에그')),
      );
      final Rect last = tester.getRect(
        _inCard('mock-breakfast', find.text('딸기')),
      );
      final Rect kcal = tester.getRect(
        _inCard(
          'mock-breakfast',
          find.textContaining('217 kcal', findRichText: true),
        ),
      );

      // 오른쪽은 모두 사진 오른쪽에서 시작한다.
      for (final Rect r in <Rect>[badge, first, kcal]) {
        expect(r.left, greaterThan(photo.right));
      }
      // 끼니가 위층, 메뉴명이 그 아래다.
      expect(badge.bottom, lessThanOrEqualTo(first.top));
      // 칼로리는 메뉴명과 한 층이다 — 이름 오른쪽, 이름 블록의 세로 가운데.
      // 메뉴명 아래 네 번째 줄로 내려가면 카드 오른쪽이 빈다.
      expect(kcal.left, greaterThan(first.right));
      expect(kcal.left, greaterThan(last.right));
      expect(
        kcal.center.dy,
        moreOrLessEquals((first.top + last.bottom) / 2, epsilon: 2),
      );
      // 끼니 배지가 사진과 같은 층이다 — 예전처럼 사진 위 별도 줄이 아니다.
      expect(badge.top, greaterThanOrEqualTo(photo.top - 0.5));
      expect(badge.top, lessThan(photo.bottom));
    });

    testWidgets('메뉴명이 한 줄이면 칼로리는 그 줄과 나란하다', (WidgetTester tester) async {
      await _pump(
        tester,
        _MealsRepository(<DietEntry>[
          _meal('one', MealType.lunch, <String>['짬뽕']),
        ]),
      );

      final Rect food = tester.getRect(_inCard('one', find.text('짬뽕')));
      final Rect kcal = tester.getRect(
        _inCard('one', find.textContaining('100 kcal', findRichText: true)),
      );
      expect(kcal.center.dy, moreOrLessEquals(food.center.dy, epsilon: 2));
    });

    testWidgets('사진은 정사각 88 이다', (WidgetTester tester) async {
      await _pump(tester, FakeDietRepository());

      final Size photo = tester.getSize(
        _inCard('mock-breakfast', find.byType(MealPhotoView)),
      );
      expect(photo, const Size(88, 88));
    });

    testWidgets('화살표는 끼니 배지 줄 오른쪽 끝, 칼로리는 그 바로 아래 같은 세로선이다', (
      WidgetTester tester,
    ) async {
      await _pump(tester, FakeDietRepository());
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(DietRecordPage)),
      );

      final Rect arrow = tester.getRect(
        _inCard('mock-breakfast', find.byIcon(AppIcons.chevronRight)),
      );
      final Rect badge = tester.getRect(
        _inCard('mock-breakfast', find.text(l.dietMealBreakfast)),
      );
      // 글자가 아니라 배지 테두리로 잰다 — 글자는 배지 안쪽 여백만큼 들어가 있다.
      final Rect kcalTag = tester.getRect(
        find.ancestor(
          of: _inCard(
            'mock-breakfast',
            find.textContaining('217 kcal', findRichText: true),
          ),
          matching: find.byType(AppTag),
        ),
      );

      expect(arrow.center.dy, moreOrLessEquals(badge.center.dy, epsilon: 4));
      // 두 오른쪽 끝이 한 세로선에 선다 — 목록을 훑을 때 칼로리가 한 선에 모인다.
      expect(kcalTag.right, moreOrLessEquals(arrow.right, epsilon: 0.5));
      expect(kcalTag.top, greaterThanOrEqualTo(arrow.bottom));
    });
  });

  group('메뉴명은 두 줄까지', () {
    testWidgets('음식이 넷이면 두 줄만 적고 마지막 줄에 남은 개수를 붙인다', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _MealsRepository(<DietEntry>[
          _meal('four', MealType.lunch, <String>['현미밥', '된장국', '제육볶음', '김치']),
        ]),
      );

      expect(_inCard('four', find.text('현미밥')), findsOneWidget);
      expect(
        _inCard('four', find.text('된장국 외 2')),
        findsOneWidget,
        reason: '숨긴 개수를 적지 않으면 회원이 덜 적었다고 읽는다',
      );
      expect(_inCard('four', find.text('제육볶음')), findsNothing);
      expect(_inCard('four', find.textContaining('김치')), findsNothing);
    });

    testWidgets('음식이 셋이면 `외 1` 이다', (WidgetTester tester) async {
      await _pump(
        tester,
        _MealsRepository(<DietEntry>[
          _meal('three', MealType.dinner, <String>['연어', '샐러드', '고구마']),
        ]),
      );

      expect(_inCard('three', find.text('샐러드 외 1')), findsOneWidget);
    });

    testWidgets('음식이 둘 이하면 전부 적고 `외` 가 붙지 않는다', (WidgetTester tester) async {
      await _pump(
        tester,
        _MealsRepository(<DietEntry>[
          _meal('two', MealType.breakfast, <String>['스크램블 에그', '딸기']),
          _meal('one', MealType.snack, <String>['바나나']),
        ]),
      );

      expect(_inCard('two', find.text('스크램블 에그')), findsOneWidget);
      expect(_inCard('two', find.text('딸기')), findsOneWidget);
      expect(_inCard('one', find.text('바나나')), findsOneWidget);
      expect(find.textContaining(' 외 '), findsNothing);
    });

    testWidgets('음식이 많아도 카드 높이는 두 줄짜리와 같다', (WidgetTester tester) async {
      await _pump(
        tester,
        _MealsRepository(<DietEntry>[
          _meal('two', MealType.breakfast, <String>['a', 'b']),
          _meal('six', MealType.lunch, <String>['a', 'b', 'c', 'd', 'e', 'f']),
        ]),
      );

      expect(
        tester.getSize(_card('six')).height,
        tester.getSize(_card('two')).height,
      );
    });
  });

  group('좁은 폭·큰 글자', () {
    testWidgets('320 폭 · 글자 1.3 배에서도 넘치지 않는다', (WidgetTester tester) async {
      await _pump(
        tester,
        _MealsRepository(<DietEntry>[
          _meal('long', MealType.lateNight, <String>[
            '매우 긴 이름의 치즈 돈가스 정식 세트',
            '콘샐러드와 단무지',
            '콜라',
          ]),
        ]),
        size: const Size(320, 2400),
        textScale: 1.3,
      );

      // 오버플로가 나면 위젯 테스트가 예외로 떨어진다.
      expect(tester.takeException(), isNull);
      expect(_card('long'), findsOneWidget);
    });

    testWidgets('칼로리는 말줄임 대신 배지를 줄인다', (WidgetTester tester) async {
      // 수치가 잘리면 다른 값으로 읽힌다(#743) — `1,2…` 는 1,200 인지 12 인지
      // 알 수 없다.
      await _pump(
        tester,
        _MealsRepository(<DietEntry>[
          const DietEntry(
            id: 'big',
            mealType: MealType.dinner,
            timeLabel: '',
            totalCalories: 12345,
            foods: <FoodItem>[FoodItem(name: '뷔페', calories: 12345)],
          ),
        ]),
        size: const Size(320, 2400),
        textScale: 1.3,
      );

      expect(tester.takeException(), isNull);
      expect(
        _inCard('big', find.textContaining('12,345', findRichText: true)),
        findsOneWidget,
      );
      expect(_inCard('big', find.textContaining('…')), findsNothing);
    });
  });

  testWidgets('사진이 없는 기록은 끼니 이모지로 접힌다', (WidgetTester tester) async {
    // 사진 → 번들 에셋 → 끼니 이모지 순서는 [MealPhotoView] 가 안다(#1053).
    await _pump(
      tester,
      _MealsRepository(<DietEntry>[
        _meal('nophoto', MealType.lateNight, <String>['라면']),
      ]),
    );

    expect(_inCard('nophoto', find.text('🌙')), findsOneWidget);
  });
}
