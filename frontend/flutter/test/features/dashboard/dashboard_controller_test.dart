import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/dashboard/data/repositories/mock_dashboard_repository.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';

import '../../helpers/fake_diet_repository.dart';

class _FailingDashboardRepository implements DashboardRepository {
  const _FailingDashboardRepository();

  @override
  Future<DashboardSummary> fetchSummary() async {
    throw StateError('boom');
  }
}

void main() {
  test('dashboardSummaryProvider returns mock indicators + schedule', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        // Default impl is DioDashboardRepository (Stage 9.8). For
        // this unit test the React-shaped mock is enough.
        dashboardRepositoryProvider.overrideWithValue(
          MockDashboardRepository(FakeDietRepository()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final summary = await container.read(dashboardSummaryProvider.future);
    expect(summary, isA<DashboardSummary>());
    // 혈당 row was dropped from the home summary; expect 3 rows
    // (칼로리 / 나트륨 / 당류).
    expect(summary.indicators.length, 3);
    expect(summary.weekScore, 85);
    expect(summary.exerciseMinutes, 45);
    expect(summary.exerciseCalories, 520);
    expect(summary.exerciseCount, 4);
  });

  test('dashboardSummaryProvider propagates repository failures', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        dashboardRepositoryProvider.overrideWithValue(
          const _FailingDashboardRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(dashboardSummaryProvider.future),
      throwsA(isA<StateError>()),
    );
  });

  test('MockDashboardRepository marks sodium as over-budget', () async {
    final repo = MockDashboardRepository(FakeDietRepository());
    final s = await repo.fetchSummary();
    final sodium = s.indicators.firstWhere(
      (HealthIndicator h) => h.label == '나트륨',
    );
    expect(sodium.overBudget, isTrue);
    expect(sodium.progress, 1.0); // clamped
    // 매크로는 식단 저장소가 준 값 그대로다.
    expect(s.macros.carbsG, 120);
    expect(s.macros.proteinG, 45);
    expect(s.macros.fatG, 45);
  });

  test(
    'MockDashboardRepository uses the same personal goals as diet',
    () async {
      const UserProfile profile = UserProfile(
        id: 'member',
        name: '회원',
        email: 'member@example.com',
        dailyCalories: 1800,
        dailySodiumMg: 1500,
        dailySugarG: 35,
        dailyCarbsG: 220,
        dailyProteinG: 120,
        dailyFatG: 50,
      );
      final DashboardSummary summary = await MockDashboardRepository(
        FakeDietRepository(),
        fetchProfile: () async => profile,
      ).fetchSummary();
      final indicators = <String, HealthIndicator>{
        for (final indicator in summary.indicators) indicator.label: indicator,
      };

      expect(indicators['칼로리']!.max, profile.effectiveDailyCalories);
      expect(indicators['나트륨']!.max, profile.effectiveDailySodiumMg);
      expect(indicators['당류']!.max, profile.effectiveDailySugarG);
      for (final indicator in indicators.values) {
        expect(indicator.overBudget, indicator.current > indicator.max);
      }
    },
  );

  // 홈이 영양 수치를 따로 들고 있다가 식단 탭과 어긋났다 — 홈 2,329mg·4끼 vs
  // 식단 3,428mg·3끼. 식단이 기준이므로 두 화면이 같은 값을 보는지 못박는다.
  test('홈 요약의 영양 수치는 식단 하루치와 일치한다', () async {
    final FakeDietRepository diet = FakeDietRepository();
    final DietDay today = await diet.fetchToday();
    final DashboardSummary s = await MockDashboardRepository(
      diet,
    ).fetchSummary();

    num indicator(String label) => s.indicators
        .firstWhere((HealthIndicator h) => h.label == label)
        .current;

    expect(indicator('칼로리'), today.totalCalories);
    expect(indicator('나트륨'), today.totalSodiumMg);
    expect(indicator('당류'), today.totalSugarG);
    expect(s.dietEntries, today.entries.length);
    expect(s.macros.carbsG, today.macros.carbsG);
    expect(s.macros.proteinG, today.macros.proteinG);
    expect(s.macros.fatG, today.macros.fatG);
    final NutritionDay todayTrend = s.nutritionWeek[nowKst().weekday - 1];
    expect(todayTrend.calories, today.totalCalories);
    expect(todayTrend.sodiumMg, today.totalSodiumMg);
    expect(todayTrend.sugarG, today.totalSugarG);
  });

  // 저장소끼리 값이 맞아도, 홈 요약 provider 가 다시 읽지 않으면 화면은 옛
  // 수치를 계속 보여준다. 식단 CRUD 가 하는 일(dietTodayProvider 무효화)만으로
  // 홈 요약이 갱신되는지 본다(CodeRabbit 리뷰).
  test('식단 무효화가 홈 요약 provider 를 다시 읽게 한다', () async {
    const AppConfig config = AppConfig(
      environment: Environment.dev,
      apiBaseUrl: 'https://dev.api.test',
      useMockApi: true,
    );
    final FakeDietRepository diet = FakeDietRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
        dietRepositoryProvider.overrideWithValue(diet),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose 라 구독이 없으면 버려진다 — 화면이 떠 있는 상태를 흉내낸다.
    final ProviderSubscription<AsyncValue<DashboardSummary>> sub = container
        .listen(dashboardSummaryProvider, (_, _) {});
    addTearDown(sub.close);

    final DashboardSummary before = await container.read(
      dashboardSummaryProvider.future,
    );
    expect(before.dietEntries, 3);

    final DietDay day = await diet.fetchToday();
    await diet.deleteEntry(
      day.entries.firstWhere((DietEntry e) => e.mealType == MealType.lunch).id!,
    );
    // 식단 화면이 CRUD 후 하는 것과 같다.
    container.invalidate(dietTodayProvider);

    final DashboardSummary after = await container.read(
      dashboardSummaryProvider.future,
    );
    expect(after.dietEntries, 2);
  });

  // 데모 중 식단을 지우면 홈도 따라 줄어야 한다 — 같은 인스턴스를 공유하는지.
  test('식단 CRUD 가 홈 요약에 반영된다', () async {
    final FakeDietRepository diet = FakeDietRepository();
    final MockDashboardRepository dashboard = MockDashboardRepository(diet);

    final DashboardSummary before = await dashboard.fetchSummary();
    final DietDay day = await diet.fetchToday();
    final DietEntry lunch = day.entries.firstWhere(
      (DietEntry e) => e.mealType == MealType.lunch,
    );
    await diet.deleteEntry(lunch.id!);
    final DashboardSummary after = await dashboard.fetchSummary();

    num sodium(DashboardSummary s) => s.indicators
        .firstWhere((HealthIndicator h) => h.label == '나트륨')
        .current;

    expect(before.dietEntries, 3);
    expect(after.dietEntries, 2);
    // 짬뽕(3,200mg)이 빠지면 목표 아래로 내려온다.
    expect(sodium(after), lessThan(sodium(before)));
    expect(
      after.indicators
          .firstWhere((HealthIndicator h) => h.label == '나트륨')
          .overBudget,
      isFalse,
    );
  });

  test('DashboardSummary parses macros and supports older responses', () {
    Map<String, Object?> payload({Map<String, Object?>? macros}) {
      final result = <String, Object?>{
        'indicators': <Object?>[],
        'diet_entries': 0,
        'exercise_minutes': 0,
        'today_schedule': <Object?>[],
        'week_score': 50,
        'week_score_delta': 0,
        'sodium_warning': null,
        'exercise_feedback': null,
      };
      if (macros != null) result['macros'] = macros;
      return result;
    }

    final parsed = DashboardSummary.fromJson(
      payload(
        macros: <String, Object?>{
          'carbs_g': 203.6,
          'protein_g': 109.3,
          'fat_g': 66.5,
          'carbs_pct': 44,
          'protein_pct': 24,
          'fat_pct': 32,
        },
      ),
    );
    expect(parsed.macros.carbsG, 203.6);
    expect(parsed.macros.carbsPct, 44);
    expect(parsed.exerciseCalories, 0);
    expect(parsed.exerciseCount, 0);

    final legacy = DashboardSummary.fromJson(payload());
    expect(legacy.macros.carbsG, 0);
    expect(legacy.macros.carbsPct, 0);
    expect(legacy.isEmpty, isTrue);
  });

  test(
    'DashboardSummary parses nutrition_week + burn goal, defaults older',
    () {
      final parsed = DashboardSummary.fromJson(<String, Object?>{
        'indicators': <Object?>[],
        'diet_entries': 0,
        'exercise_minutes': 0,
        'exercise_burn_goal': 700,
        'nutrition_week': <Object?>[
          <String, Object?>{
            'label': '월',
            'calories': 1650,
            'sodium_mg': 1600,
            'sugar_g': 30,
          },
          <String, Object?>{
            'label': '화',
            'calories': 2100,
            'sodium_mg': 1900,
            'sugar_g': 48,
          },
        ],
        'nutrition_week_prev': <Object?>[
          <String, Object?>{
            'label': '월',
            'calories': 1820,
            'sodium_mg': 1900,
            'sugar_g': 35,
          },
        ],
        'today_schedule': <Object?>[],
        'week_score': 70,
        'week_score_delta': -5,
        'sodium_warning': null,
        'exercise_feedback': null,
      });
      expect(parsed.exerciseBurnGoal, 700);
      expect(parsed.nutritionWeek.length, 2);
      expect(parsed.nutritionWeek.first.label, '월');
      expect(parsed.nutritionWeek.first.calories, 1650);
      expect(parsed.nutritionWeek.first.sodiumMg, 1600);
      expect(parsed.nutritionWeekPrev.length, 1);
      expect(parsed.weekScoreDelta, -5);

      // 구버전 응답: 새 필드가 없으면 기본값(빈 주간·소모목표 500)으로 폴백.
      final legacy = DashboardSummary.fromJson(<String, Object?>{
        'indicators': <Object?>[],
        'diet_entries': 0,
        'exercise_minutes': 0,
        'today_schedule': <Object?>[],
        'week_score': 50,
        'week_score_delta': 0,
        'sodium_warning': null,
        'exercise_feedback': null,
      });
      expect(legacy.exerciseBurnGoal, 500);
      expect(legacy.nutritionWeek, isEmpty);
      expect(legacy.nutritionWeekPrev, isEmpty);
    },
  );

  test('isEmpty stays false when only past weekdays have diet records', () {
    Map<String, Object?> base(List<Object?> week) => <String, Object?>{
      'indicators': <Object?>[],
      'diet_entries': 0,
      'exercise_minutes': 0,
      'today_schedule': <Object?>[],
      'nutrition_week': week,
      'week_score': 50,
      'week_score_delta': 0,
      'sodium_warning': null,
      'exercise_feedback': null,
    };

    // 오늘 기록이 없어도(diet_entries=0, 칼로리 지표 0) 이번 주 과거 요일에
    // 실제 식단 기록이 있으면 홈은 비어 있지 않다 — 주간 추이 차트가 표시돼야 한다.
    final withPastWeek = DashboardSummary.fromJson(
      base(<Object?>[
        <String, Object?>{
          'label': '월',
          'calories': 1650,
          'sodium_mg': 1600,
          'sugar_g': 30,
        },
        <String, Object?>{
          'label': '화',
          'calories': 0,
          'sodium_mg': 0,
          'sugar_g': 0,
        },
      ]),
    );
    expect(withPastWeek.isEmpty, isFalse);

    // 주간에도 유효 기록이 하나도 없으면(모두 0) 여전히 비어 있다.
    final allZero = DashboardSummary.fromJson(
      base(<Object?>[
        <String, Object?>{
          'label': '월',
          'calories': 0,
          'sodium_mg': 0,
          'sugar_g': 0,
        },
      ]),
    );
    expect(allZero.isEmpty, isTrue);
  });
}
