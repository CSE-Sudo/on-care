import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';

void main() {
  test('exerciseWeekProvider provides 7 days, sane totals', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        // Production repo is DioExerciseRepository (needs dio + db);
        // unit test only needs the React-shaped in-memory mock.
        // 고정 금요일을 주입해 날짜에 상대적인 시드를 결정적으로 만든다.
        // 값이 픽스처와 맞는지는 mock_exercise_repository_test 가 본다 —
        // 여기에 숫자를 또 적으면 픽스처와 세 벌이 된다.
        exerciseRepositoryProvider.overrideWithValue(
          MockExerciseRepository(today: DateTime(2024, 1, 5)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final week = await container.read(exerciseWeekProvider.future);
    expect(week.dailyMinutes.length, 7);
    expect(week.dayLabels.length, 7);
    expect(week.totalMinutes, greaterThan(0));
    expect(week.totalCalories, greaterThan(0));
    expect(week.streakDays, greaterThan(0));
    expect(week.aiCoachMessage, isNotEmpty);
    expect(week.sessions, isNotEmpty);
    // Stacked-chart series should line up with the bar chart x-axis.
    expect(week.cardioMinutes.length, week.dailyMinutes.length);
    expect(week.strengthMinutes.length, week.dailyMinutes.length);
    expect(week.stretchingMinutes.length, week.dailyMinutes.length);
  });
}
