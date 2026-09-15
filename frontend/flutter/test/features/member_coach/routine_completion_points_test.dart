/// 데모 루틴 완료·운동 추가의 포인트 적립과 응답 파싱. (#1786)
///
/// 적립 규칙의 `AI 추천 운동 완료` 는 AI 가 추천한 루틴(`source: ai`)만이다.
/// 트레이너가 직접 배정한 루틴은 0 이다. 목업은 식단(목업 API)과 같은 원장을
/// 써서 하루 한도와 MY 잔액이 하나로 움직인다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

void main() {
  late DemoPointsLedger ledger;
  late MockExerciseRepository exercise;
  late MockMemberCoachRepository coach;

  setUp(() {
    ledger = DemoPointsLedger();
    exercise = MockExerciseRepository(points: ledger);
    coach = MockMemberCoachRepository(exercise: exercise, points: ledger);
  });

  group('데모 루틴 완료', () {
    test('AI 추천 루틴 완료는 +50P 하루 1회, 되돌리면 회수한다', () async {
      final List<CoachRoutine> ai = (await coach.fetchRoutines())
          .where((CoachRoutine r) => r.isAiRecommended)
          .toList();
      expect(ai.length, greaterThanOrEqualTo(2));

      final CoachRoutine first = await coach.completeRoutine(
        ai[0].id,
        minutes: 10,
      );
      expect(first.pointsAward?.awarded, 50);
      expect(ledger.balance, kDemoOpeningPoints + 50);

      final CoachRoutine second = await coach.completeRoutine(
        ai[1].id,
        minutes: 10,
      );
      expect(second.pointsAward?.awarded, 0);

      // 재전송은 처음 받은 값을 돌려줄 뿐 새로 쌓지 않는다.
      final CoachRoutine again = await coach.completeRoutine(
        ai[0].id,
        minutes: 10,
      );
      expect(again.pointsAward?.awarded, 50);
      expect(ledger.balance, kDemoOpeningPoints + 50);

      await coach.uncompleteRoutine(ai[0].id);
      expect(ledger.balance, kDemoOpeningPoints);

      // 되돌린 몫은 한도에서 빠져, 다시 완료하면 새 기록으로 적립된다.
      final CoachRoutine redone = await coach.completeRoutine(
        ai[0].id,
        minutes: 10,
      );
      expect(redone.pointsAward?.awarded, 50);
    });

    test('트레이너가 직접 배정한 루틴 완료는 적립하지 않는다', () async {
      final CoachRoutine trainer = (await coach.fetchRoutines()).firstWhere(
        (CoachRoutine r) => r.isTrainerRecommended,
      );

      final CoachRoutine done = await coach.completeRoutine(
        trainer.id,
        minutes: 10,
      );

      expect(done.completed, isTrue);
      expect(done.pointsAward?.awarded, 0);
      expect(ledger.balance, kDemoOpeningPoints);
    });

    test('목록의 루틴에는 적립 결과가 따라가지 않는다', () async {
      final CoachRoutine ai = (await coach.fetchRoutines()).firstWhere(
        (CoachRoutine r) => r.isAiRecommended,
      );
      await coach.completeRoutine(ai.id, minutes: 10);

      final CoachRoutine listed = (await coach.fetchRoutines()).firstWhere(
        (CoachRoutine r) => r.id == ai.id,
      );
      expect(listed.completed, isTrue);
      expect(listed.pointsAward, isNull);
    });
  });

  group('데모 운동 직접 추가', () {
    test('+20P 를 받고, 지우면 회수한다', () async {
      final ExerciseSession added = await exercise.addSession(
        type: ExerciseType.cardio,
        minutes: 20,
        calories: 100,
        date: nowKst(),
        name: '걷기',
      );
      expect(added.pointsAward?.awarded, 20);
      expect(ledger.balance, kDemoOpeningPoints + 20);

      await exercise.deleteSession(added.id!);
      expect(ledger.balance, kDemoOpeningPoints);
    });

    test('원장이 없으면 적립 없이 기록만 남는다', () async {
      final ExerciseSession added = await MockExerciseRepository().addSession(
        type: ExerciseType.cardio,
        minutes: 20,
        calories: 100,
        date: nowKst(),
      );
      expect(added.pointsAward, isNull);
    });
  });

  group('생성 응답의 points 파싱', () {
    const Map<String, Object?> points = <String, Object?>{
      'awarded': 50,
      'balance': 1290,
    };

    test('루틴 완료 응답', () {
      final CoachRoutine routine = coachRoutineFromJson(<String, Object?>{
        'id': 'r1',
        'name': '걷기',
        'minutes': 20,
        'type': '유산소',
        'reason': '',
        'source': 'ai',
        'completed': true,
        'points': points,
      });
      expect(routine.pointsAward?.awarded, 50);
      expect(routine.pointsAward?.balance, 1290);
      expect(
        coachRoutineFromJson(<String, Object?>{
          'id': 'r1',
          'source': 'ai',
        }).pointsAward,
        isNull,
      );
    });

    test('운동 추가 응답', () {
      final ExerciseSession session = ExerciseSession.fromJson(
        <String, Object?>{
          'id': 'ex-1',
          'day_label': '월',
          'type': 'cardio',
          'minutes': 20,
          'calories': 100,
          'points': <String, Object?>{'awarded': 20, 'balance': 1260},
        },
      );
      expect(session.pointsAward?.awarded, 20);
    });

    test('식단 분석 응답', () {
      final DietAnalysisResult result = DietAnalysisResult.fromResponse(
        <String, Object?>{
          'entry_id': 'diet-1',
          'analysis': <String, Object?>{},
          'points': points,
        },
      );
      expect(result.points?.awarded, 50);
      expect(
        DietAnalysisResult.fromResponse(<String, Object?>{
          'entry_id': 'diet-1',
        }).points,
        isNull,
      );
    });
  });
}
