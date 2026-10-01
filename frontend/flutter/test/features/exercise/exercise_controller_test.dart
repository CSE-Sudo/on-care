import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';

import '../../helpers/demo_exercise.dart';
import '../../helpers/fixed_clock.dart';

void main() {
  test('exerciseWeekProvider provides 7 days, sane totals', () async {
    // 앱의 데모와 같은 경로 — 픽스처로 시드한 메모리 drift 위의 로컬 목업 API 를
    // 부르는 Dio 저장소다(#2724). 고정 금요일을 오늘로 두어 날짜에 상대적인
    // 시드를 결정적으로 만든다. 값이 픽스처와 맞는지는 demo_exercise_week_test
    // 가 본다 — 여기에 숫자를 또 적으면 픽스처와 세 벌이 된다.
    useFixedKstDate(DateTime(2024, 1, 5));
    final container = ProviderContainer(
      overrides: <Override>[
        exerciseRepositoryProvider.overrideWithValue(
          demoExerciseBackend(await seededDemoDatabase()).repository,
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
