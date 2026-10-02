/// 사용 가이드 식단 단계의 예시 음식 이름이 화면 언어를 따르는지. (#2878)
///
/// 예시 하루의 음식 이름이 한국어로 박혀 있어, 영어 가이드에서도 끼니 카드에
/// 한국어 이름이 나왔다. 이제 ARB 문구로 싣고, 썸네일 이모지는 언어와 상관없이
/// 같게 정해 둔다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/app_guide/domain/guide_sample_data.dart';
import 'package:oncare/features/app_guide/presentation/pages/guide_tour_page.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/meal_emoji.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final RegExp _hangul = RegExp('[가-힣]');

/// 예전에 박혀 있던 한국어 이름 — 한국어 가이드는 지금도 이 이름이어야 한다.
const List<String> _koreanNames = <String>[
  '스크램블에그',
  '통밀 토스트',
  '닭가슴살 샐러드',
  '현미밥',
  '연어구이',
  '구운 채소',
];

Iterable<String> _foodNames(DietDay day) => <String>[
  for (final DietEntry e in day.entries)
    for (final FoodItem f in e.foods) f.name,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  group('예시 하루 자료', () {
    test('한국어는 예전과 같은 음식 이름이다', () {
      expect(_foodNames(guideSampleDietDay(ko)), _koreanNames);
    });

    test('영어는 음식 이름에 한글이 없다', () {
      for (final String name in _foodNames(guideSampleDietDay(en))) {
        expect(name, isNotEmpty);
        expect(name, isNot(matches(_hangul)), reason: name);
      }
    });

    test('끼니 썸네일 이모지가 두 언어에서 같다', () {
      final List<DietEntry> koEntries = guideSampleDietDay(ko).entries;
      final List<DietEntry> enEntries = guideSampleDietDay(en).entries;
      expect(enEntries, hasLength(koEntries.length));
      for (int i = 0; i < koEntries.length; i++) {
        expect(koEntries[i].thumbEmoji, isNotNull);
        expect(enEntries[i].thumbEmoji, koEntries[i].thumbEmoji);
      }
    });

    test('정해 둔 이모지는 한국어 이름으로 고르던 것과 같다', () {
      // 한국어 가이드의 모습이 바뀌지 않는다.
      for (final DietEntry e in guideSampleDietDay(ko).entries) {
        expect(
          e.thumbEmoji,
          mealThumbEmoji(e.mealType, e.foods.map((FoodItem f) => f.name)),
        );
      }
    });

    test('숫자는 언어와 무관하고 홈 요약과 같다', () {
      final DietDay koDay = guideSampleDietDay(ko);
      final DietDay enDay = guideSampleDietDay(en);
      expect(enDay.totalCalories, koDay.totalCalories);
      expect(enDay.totalSodiumMg, koDay.totalSodiumMg);
      expect(enDay.totalSugarG, koDay.totalSugarG);
      // 홈 요약(1,480kcal · 1,720mg · 32g)과 같은 하루다.
      expect(
        koDay.totalCalories,
        kGuideSampleSummary.indicators[0].current.round(),
      );
      expect(
        koDay.totalSodiumMg,
        kGuideSampleSummary.indicators[1].current.round(),
      );
      expect(
        koDay.totalSugarG.round(),
        kGuideSampleSummary.indicators[2].current.round(),
      );
      // 끼니 합이 하루 합과 맞는다.
      expect(
        koDay.entries.fold<int>(0, (int a, DietEntry e) => a + e.totalCalories),
        koDay.totalCalories,
      );
    });

    test('쓰이지 않던 한국어 끼니 코멘트를 싣지 않는다', () {
      for (final DietEntry e in guideSampleDietDay(en).entries) {
        expect(e.aiComment, isEmpty);
      }
    });
  });

  group('가이드 식단 단계 화면', () {
    Future<void> pumpDietStep(WidgetTester tester, Locale locale) async {
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final GoRouter router = GoRouter(
        initialLocation: AppRoutes.guideTour,
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.guideTour,
            builder: (_, _) => const GuideTourPage(),
          ),
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (_, _) => const Scaffold(body: Text('dashboard-route')),
          ),
        ],
      );
      addTearDown(router.dispose);

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'https://dev.api.test',
              useMockApi: true,
            ),
          ),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 홈 두 단계를 지나 식단 단계로.
      for (int i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('appGuideNext')));
        await tester.pumpAndSettle();
      }
      expect(find.byType(DietRecordPage), findsOneWidget);
    }

    testWidgets('영어 가이드의 끼니 카드에 영어 음식 이름이 나온다', (WidgetTester tester) async {
      await pumpDietStep(tester, const Locale('en'));

      expect(
        find.textContaining(en.guideSampleFoodScrambledEggs),
        findsWidgets,
      );
      for (final String name in _koreanNames) {
        expect(find.textContaining(name), findsNothing, reason: name);
      }
    });

    testWidgets('한국어 가이드는 예전 음식 이름을 그대로 보인다', (WidgetTester tester) async {
      await pumpDietStep(tester, const Locale('ko'));

      expect(find.textContaining('스크램블에그'), findsWidgets);
      expect(
        find.textContaining(en.guideSampleFoodScrambledEggs),
        findsNothing,
      );
    });
  });
}
