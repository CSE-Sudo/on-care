/// 운동 집계가 회원 앱과 **같은 값**을 쓰는지 (#2195).
///
/// #2157 이 목표·기간·기타 이중 계산을 맞춘 뒤 남아 있던 두 가지다.
///
///  * 유형 분해가 실려 왔는지를 **응답이 말한 대로** 본다. 값으로 되짚으면
///    네 유형이 모두 0 인 날이 분해 없는 날로 읽혀 분이 통째로 유산소로 간다.
///  * 연속 일수는 **서버가 센 값**(`streak_days`)이다. 앱에서 다시 세면 분이
///    0 이고 칼로리만 있는 날에서 두 앱이 다른 일수를 말한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';

final DateTime _d = DateTime(2026, 9, 21);

void main() {
  group('유형 분해 여부는 응답이 말한다', () {
    test('분해가 실려 온 주의 쉰 날은 분해가 있는 날이다', () {
      final ClientExerciseDay rested = ClientExerciseDay(
        date: _d,
        typeSplitFromPayload: true,
      );
      expect(rested.hasTypeSplit, isTrue);
    });

    test('분해가 없는 옛 응답의 날은 전부 유산소로 본다', () {
      final ClientExerciseDay old = ClientExerciseDay(
        date: _d,
        minutes: 40,
        calories: 200,
        typeSplitFromPayload: false,
      );
      expect(old.hasTypeSplit, isFalse);
    });

    test('응답이 말해 주지 않은 날만 값으로 되짚는다', () {
      // 직접 만든 값(테스트·목)에서는 예전 규칙 그대로다.
      expect(
        ClientExerciseDay(date: _d, otherMinutes: 30).hasTypeSplit,
        isTrue,
      );
      expect(ClientExerciseDay(date: _d, minutes: 30).hasTypeSplit, isFalse);
    });

    test('주간 응답의 분해 판정은 회원 앱과 같은 길이 기준이다', () {
      // 회원 앱 `dayLoadsOfWeek` — 세 배열의 길이가 일별 배열과 같을 때만 쓴다.
      const ClientExerciseWeek short = ClientExerciseWeek(
        dayLabels: <String>['월', '화'],
        dailyMinutes: <int>[30, 20],
        dailyCalories: <int>[180, 120],
        cardioMinutes: <int>[30],
        totalMinutes: 50,
        totalCalories: 300,
      );
      expect(short.hasTypeSplit, isFalse);
    });
  });

  group('연속 일수는 서버가 센 값이다', () {
    test('주간 응답의 streak_days 를 읽는다', () {
      final ClientExerciseWeek week = ClientExerciseWeek.fromJson(
        <String, Object?>{
          'day_labels': <String>['월', '화', '수', '목', '금', '토', '일'],
          'daily_minutes': <int>[30, 30, 0, 0, 0, 0, 0],
          'daily_calories': <int>[200, 200, 0, 0, 0, 0, 0],
          'streak_days': 2,
        },
      );
      expect(week.streakDays, 2);
    });

    test('옛 응답에 그 칸이 없으면 0 이다', () {
      final ClientExerciseWeek week = ClientExerciseWeek.fromJson(
        <String, Object?>{
          'day_labels': <String>['월'],
          'daily_minutes': <int>[30],
          'daily_calories': <int>[200],
        },
      );
      expect(week.streakDays, 0);
    });
  });
}
