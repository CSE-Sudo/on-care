/// 끼니 카드의 총량 배지 색과, 수정 화면 상단의 큰 사진 (#1053).
///
/// 배지 색은 같은 탭 안에서 뜻이 하나여야 한다. 기간 그래프와 나트륨·당류
/// 카드가 목표 안쪽을 브랜드 파랑으로 그리므로 끼니 카드도 같은 색을 쓴다
/// (#1070 에서 초록 → 파랑).
///
/// 수정 화면은 무엇을 고치는 끼니인지부터 보여 준다 — 사진을 먼저 확인하고
/// 숫자를 고치는 순서다.
///
/// 카드가 총 칼로리만 남긴 뒤로(#1848) 배지는 하나다. 색 규칙은 그대로다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/features/diet/presentation/widgets/meal_photo_view.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_diet_repository.dart';

/// 대역의 아침 — 사진 자산이 붙어 있는 끼니다.
const DietMeal _breakfast = DietMeal(
  id: 'entry-breakfast',
  mealType: MealType.breakfast,
  time: '08:20',
  total: 217,
  emoji: '🥣',
  thumbBg: Color(0xFFFFF3E0),
  photoAsset: 'assets/images/breakfast-scrambled-egg-strawberry.jpg',
  items: <DietFood>[DietFood('스크램블 에그', 185), DietFood('딸기', 32)],
  tags: <DietTag>[],
  sodium: 221,
  sugar: 6.3,
);

/// 끼니 카드 하나로 범위를 좁히는 검색자.
Finder get _anyMealCard => find
    .byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('mealCard-'),
    )
    .first;

void main() {
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

  /// 배지 안에서 **값** 에 칠해진 색. 라벨은 같은 색을 옅게 쓰므로 마지막으로
  /// 색이 지정된 조각이 값이다. `Text.rich` 가 스팬을 한 겹 감싸 두어 곧장
  /// `children.last` 를 보면 색이 없는 껍데기가 잡힌다.
  Color? badgeColorOf(WidgetTester tester, String text) {
    // 끼니 카드 안으로 범위를 좁힌다. 같은 화면 위쪽의 나트륨·당류 카드도
    // "나트륨 …" 으로 시작하는 리치 텍스트를 갖고 있어, 좁히지 않으면 그쪽이
    // 먼저 잡힌다.
    final RichText rich = tester
        .widgetList<RichText>(
          find.descendant(
            of: _anyMealCard,
            matching: find.byWidgetPredicate(
              (Widget w) =>
                  w is RichText && w.text.toPlainText().startsWith('$text '),
            ),
          ),
        )
        .first;
    Color? color;
    rich.text.visitChildren((InlineSpan span) {
      if (span.style?.color != null) color = span.style!.color;
      return true;
    });
    return color;
  }

  testWidgets('끼니 카드의 총량 배지는 기간 그래프와 같은 파랑이다', (WidgetTester tester) async {
    await pumpDiet(tester);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(DietRecordPage)),
    );
    // 대역의 아침은 217kcal — 목표 안쪽이다.
    expect(
      badgeColorOf(tester, l.dietCalories),
      OnCareBrand.member.statusWithinGoal,
    );
  });

  testWidgets('끼니 카드에 남는 수치는 총 칼로리뿐이다', (WidgetTester tester) async {
    await pumpDiet(tester);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(DietRecordPage)),
    );
    // 나트륨·당류 배지와 탄단지 줄은 상세 화면 몫으로 옮겼다(#1848).
    for (final String label in <String>[
      l.dietSodium,
      l.dietSugar,
      l.homeMacroCarbs,
    ]) {
      expect(
        find.descendant(
          of: _anyMealCard,
          matching: find.textContaining(label, findRichText: true),
        ),
        findsNothing,
        reason: '끼니 카드에 `$label` 이 남아 있다',
      );
    }
  });

  testWidgets('목록 썸네일은 정사각 56 이다', (WidgetTester tester) async {
    await pumpDiet(tester);

    final List<MealPhotoView> thumbs = tester
        .widgetList<MealPhotoView>(find.byType(MealPhotoView))
        .toList();
    expect(thumbs, isNotEmpty);
    expect(thumbs.every((MealPhotoView p) => p.height == 56), isTrue);
  });

  testWidgets('끼니를 열면 상단에 사진이 크게 뜬다', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 수정 화면은 탭 껍데기 위에 라우터로 열린다 — 여기서는 그 페이지만 띄운다.
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
          home: DietMealDetailPage(
            entryId: _breakfast.id!,
            initialMeal: _breakfast,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final MealPhotoView hero = tester.widget<MealPhotoView>(
      find.byType(MealPhotoView).first,
    );
    expect(hero.height, greaterThan(52));
    expect(hero.width, double.infinity);
    // 목록과 같은 사진을 고른다 — 두 화면이 각자 고르면 어긋난다.
    expect(hero.photoAsset, _breakfast.photoAsset);
  });
}
