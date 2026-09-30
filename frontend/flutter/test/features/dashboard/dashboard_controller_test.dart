import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';

import '../../helpers/fake_dashboard_repository.dart';
import '../../helpers/fake_diet_repository.dart';

class _FailingDashboardRepository implements DashboardRepository {
  const _FailingDashboardRepository();

  @override
  Future<DashboardSummary> fetchSummary() async {
    throw StateError('boom');
  }
}

void main() {
  test('dashboardSummaryProvider returns the repository summary', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        // 기본 구현은 DioDashboardRepository 다(데모도 같다, #2645). 이
        // 단위 테스트는 provider 가 저장소 결과를 그대로 내는지만 본다.
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(FakeDietRepository()),
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
