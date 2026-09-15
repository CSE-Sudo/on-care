/// 연속 일수와 보호권 — 세 생산자(FastAPI·목업 API·앱)가 함께 쓰는 정의. (#1788)
///
/// 보호한 날은 연속 일수에만 운동한 날로 들어가고, 분·칼로리·운동 일수에는 들어가지
/// 않는다. 오늘 체크한 AI 루틴을 얹어도 보호권 상태가 사라지지 않는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';

const List<bool> _tuesday = <bool>[false, true, false, false, false, false, false];

void main() {
  test('보호한 날도 연속 일수에 들어간다', () {
    const List<double> daily = <double>[30, 0, 20, 0, 0, 0, 0];

    expect(longestActiveStreak(daily), 1);
    expect(longestActiveStreak(daily, protectedDays: _tuesday), 3);
    // 보호한 날만 이어져도 이어진 날이다.
    expect(
      longestActiveStreak(
        List<double>.filled(7, 0),
        protectedDays: <bool>[false, true, true, false, false, false, false],
      ),
      2,
    );
  });

  test('가장 긴 연속에 보호권으로만 이어진 날이 들었는지 가른다', () {
    // 월~수 3일(화 보호)과 금~일 3일이 같은 길이 — 보호한 구간이 있으면 참.
    expect(
      longestStreakKeptByShield(<double>[30, 0, 20, 0, 10, 10, 10], _tuesday),
      isTrue,
    );
    // 보호한 구간(월~화 2일)이 가장 긴 구간(금~일 3일)이 아니면 거짓.
    expect(
      longestStreakKeptByShield(<double>[30, 0, 0, 0, 10, 10, 10], _tuesday),
      isFalse,
    );
    // 보호한 뒤 그날 운동을 더했으면 운동한 날이다.
    expect(
      longestStreakKeptByShield(<double>[30, 20, 10, 0, 0, 0, 0], _tuesday),
      isFalse,
    );
  });

  test('주간 응답의 보호한 날과 보호권 상태를 읽는다', () {
    Map<String, Object?> payload({bool withShield = true}) => <String, Object?>{
      'sessions': <Object?>[],
      'daily_minutes': <int>[30, 0, 20, 0, 0, 0, 0],
      'day_labels': <String>['월', '화', '수', '목', '금', '토', '일'],
      'total_minutes': 50,
      'total_calories': 300,
      'streak_days': 3,
      'ai_coach_message': '',
      if (withShield) ...<String, Object?>{
        'protected_days': _tuesday,
        'streak_shield': <String, Object?>{
          'held': 1,
          'protectable_date': '2026-09-16',
        },
      },
    };

    final ExerciseWeek week = ExerciseWeek.fromJson(payload());
    expect(week.protectedDays, _tuesday);
    expect(week.isProtectedDay(1), isTrue);
    expect(week.isProtectedDay(9), isFalse);
    expect(week.streakShield?.held, 1);
    expect(week.streakShield?.protectableDate, DateTime(2026, 9, 16));
    expect(week.streakKeptByShield, isTrue);
    // 보호한 날은 운동 일수가 아니다.
    expect(week.workoutCount, 2);

    final ExerciseWeek old = ExerciseWeek.fromJson(payload(withShield: false));
    expect(old.protectedDays, isEmpty);
    expect(old.streakShield, isNull);
  });

  test('오늘 AI 루틴을 얹어도 보호한 날과 보호권 상태가 남는다', () {
    const StreakShieldWeekState shield = StreakShieldWeekState(held: 1);
    const ExerciseWeek week = ExerciseWeek(
      sessions: <ExerciseSession>[],
      dailyMinutes: <double>[30, 0, 20, 0, 0, 0, 0],
      cardioMinutes: <double>[30, 0, 20, 0, 0, 0, 0],
      strengthMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
      stretchingMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
      dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
      totalMinutes: 50,
      totalCalories: 300,
      streakDays: 3,
      aiCoachMessage: '',
      protectedDays: _tuesday,
      streakShield: shield,
    );

    final ExerciseWeek shown = applyTodayBonus(
      week,
      const ExerciseTodayBonus(cardioMinutes: 30, calories: 250),
      now: DateTime(2026, 9, 17, 10), // 목요일
    );

    expect(shown.protectedDays, _tuesday);
    expect(identical(shown.streakShield, shield), isTrue);
    // 월·화(보호)·수·목(루틴) 4일 연속. 분 합계에는 보호한 날이 없다.
    expect(shown.streakDays, 4);
    expect(shown.totalMinutes, 80);
  });
}
