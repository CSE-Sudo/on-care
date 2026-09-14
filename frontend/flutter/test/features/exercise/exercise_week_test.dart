import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

void main() {
  test('longestActiveStreak counts the longest run, not the active days', () {
    // 월·수·금 — 활성 일수는 3이지만 '연속'은 1.
    expect(longestActiveStreak(<double>[30, 0, 45, 0, 60, 0, 0]), 1);
    // 수·목·금 연속 3일 (앞뒤 휴식일 포함).
    expect(longestActiveStreak(<double>[0, 0, 40, 40, 50, 0, 0]), 3);
    // 가장 긴 구간을 고른다: 1일 구간과 3일 구간이 섞이면 3.
    expect(longestActiveStreak(<double>[30, 0, 20, 20, 20, 0, 0]), 3);
    expect(longestActiveStreak(<double>[0, 0, 0, 0, 0, 0, 0]), 0);
    expect(longestActiveStreak(<double>[]), 0);
  });

  test('ExerciseWeek exposes workoutCount and stays const-constructible', () {
    const week = ExerciseWeek(
      sessions: <ExerciseSession>[],
      dailyMinutes: <double>[10, 0, 30],
      dayLabels: <String>['a', 'b', 'c'],
      totalMinutes: 40,
      totalCalories: 400,
      streakDays: 2,
      aiCoachMessage: 'hi',
    );
    expect(week.totalMinutes, 40);
    expect(week.totalCalories, 400);
    expect(week.streakDays, 2);
    // 활성 일수 = dailyMinutes 가 0보다 큰 날. 세션 목록에 없는 분(체크한 AI
    // 추천 운동)이 더해져도 같은 규칙으로 세어진다.
    expect(week.workoutCount, 2);
  });

  test('workoutCount falls back to session day labels without a series', () {
    const week = ExerciseWeek(
      sessions: <ExerciseSession>[
        ExerciseSession(
          dayLabel: '월',
          type: ExerciseType.cardio,
          minutes: 30,
          calories: 200,
        ),
        ExerciseSession(
          dayLabel: '월',
          type: ExerciseType.strength,
          minutes: 20,
          calories: 150,
        ),
      ],
      dailyMinutes: <double>[],
      dayLabels: <String>[],
      totalMinutes: 50,
      totalCalories: 350,
      streakDays: 1,
      aiCoachMessage: 'hi',
    );
    expect(week.workoutCount, 1); // 같은 날 두 세션은 1일로 합쳐진다.
  });

  test('fromJson derives daily_calories from sessions when absent', () {
    // 백엔드/LocalApi 응답이 daily_calories 를 아직 내려주지 않는 경우에도 홈
    // '주간 추이' 차트가 실제 데이터를 그리도록 세션에서 요일별로 합산한다.
    final week = ExerciseWeek.fromJson(<String, Object?>{
      'sessions': <Object?>[
        <String, Object?>{
          'id': 's-1',
          'day_label': '월',
          'type': 'cardio',
          'minutes': 30,
          'calories': 250,
        },
        <String, Object?>{
          'id': 's-2',
          'day_label': '월',
          'type': 'strength',
          'minutes': 20,
          'calories': 150,
        },
        <String, Object?>{
          'id': 's-3',
          'day_label': '수',
          'type': 'cardio',
          'minutes': 45,
          'calories': 300,
        },
      ],
      'daily_minutes': <Object?>[50, 0, 45, 0, 0, 0, 0],
      'day_labels': <Object?>['월', '화', '수', '목', '금', '토', '일'],
      'total_minutes': 95,
      'total_calories': 700,
      'streak_days': 2,
      'ai_coach_message': 'hi',
    });
    expect(week.dailyCalories, <double>[400, 0, 300, 0, 0, 0, 0]);
  });

  test('fromJson keeps daily_calories when the payload carries it', () {
    final week = ExerciseWeek.fromJson(<String, Object?>{
      'sessions': <Object?>[],
      'daily_minutes': <Object?>[0, 0, 0, 0, 0, 0, 0],
      'daily_calories': <Object?>[10, 20, 30, 0, 0, 0, 0],
      'day_labels': <Object?>['월', '화', '수', '목', '금', '토', '일'],
      'total_minutes': 0,
      'total_calories': 60,
      'streak_days': 0,
      'ai_coach_message': 'hi',
    });
    expect(week.dailyCalories, <double>[10, 20, 30, 0, 0, 0, 0]);
  });

  test('ExerciseWeek.fromJson parses the LocalApi shape', () {
    final week = ExerciseWeek.fromJson(<String, Object?>{
      'sessions': <Object?>[
        <String, Object?>{
          'id': 's-1',
          'day_label': '월',
          'type': 'cardio',
          'minutes': 30,
          'calories': 250,
        },
      ],
      'daily_minutes': <Object?>[30, 0, 45, 0, 60, 0, 0],
      'day_labels': <Object?>['월', '화', '수', '목', '금', '토', '일'],
      'total_minutes': 135,
      'total_calories': 1050,
      'streak_days': 3,
      'ai_coach_message': 'hi',
    });
    expect(week.sessions.length, 1);
    expect(week.sessions.first.id, 's-1');
    expect(week.sessions.first.type, ExerciseType.cardio);
    // Absent intensity defaults to moderate (legacy payloads).
    expect(week.sessions.first.intensity, ExerciseIntensity.moderate);
    expect(week.dailyMinutes, <double>[30, 0, 45, 0, 60, 0, 0]);
    expect(week.streakDays, 3);
  });

  test('ExerciseSession.fromJson parses a persisted intensity', () {
    final week = ExerciseWeek.fromJson(<String, Object?>{
      'sessions': <Object?>[
        <String, Object?>{
          'id': 's-1',
          'day_label': '월',
          'type': 'strength',
          'minutes': 40,
          'calories': 300,
          'intensity': 'high',
        },
      ],
      'daily_minutes': <Object?>[40, 0, 0, 0, 0, 0, 0],
      'day_labels': <Object?>['월', '화', '수', '목', '금', '토', '일'],
      'total_minutes': 40,
      'total_calories': 300,
      'streak_days': 1,
      'ai_coach_message': 'hi',
    });
    expect(week.sessions.first.intensity, ExerciseIntensity.high);
  });

  group('ExerciseSession.source (#499)', () {
    ExerciseSession parse(Map<String, Object?> extra) =>
        ExerciseSession.fromJson(<String, Object?>{
          'id': 'ex-1',
          'day_label': '월',
          'type': 'strength',
          'minutes': 60,
          'calories': 360,
          ...extra,
        });

    test('trainer_pt 기록은 회원이 고칠 수 없다', () {
      final s = parse(<String, Object?>{'source': 'trainer_pt'});
      expect(s.source, ExerciseSource.trainerPt);
      expect(s.isEditable, isFalse);
    });

    test('회원이 남긴 기록은 그대로 편집 가능하다', () {
      final s = parse(<String, Object?>{'source': 'member'});
      expect(s.source, ExerciseSource.member);
      expect(s.isEditable, isTrue);
    });

    test('필드가 없거나 모르는 값이면 회원 기록으로 본다', () {
      // 이 필드를 모르는 예전 응답과 데모/목 경로에서 기록이 통째로
      // 잠기면 안 된다 — 안전한 쪽은 '편집 가능'이다.
      expect(parse(<String, Object?>{}).isEditable, isTrue);
      expect(
        parse(<String, Object?>{'source': 'something-new'}).isEditable,
        isTrue,
      );
    });
  });
}
