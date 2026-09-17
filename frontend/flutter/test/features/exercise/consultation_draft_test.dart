import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';

ConsultationDraft _draft({
  String trainerId = 'trainer-1',
  HealthPurposeType purpose = HealthPurposeType.general,
  String? detail,
  bool consent = true,
  PreferredTime preferredTime = const PreferredTime.at(
    TimeOfDay(hour: 9, minute: 30),
  ),
}) => ConsultationDraft(
  trainerId: trainerId,
  exerciseGoal: ExerciseGoal.fitness,
  healthPurposeType: purpose,
  healthPurposeDetail: detail,
  preferredDate: DateTime(2026, 8, 20),
  preferredTimeSlot: preferredTime,
  message: null,
  // 동의 없이는 보낼 수 없다(#1022) — 기본 대역은 동의한 상태로 둔다.
  dataSharingConsent: consent,
);

void main() {
  test('wire 값이 백엔드 Literal 과 같다', () {
    final json = _draft().toJson();
    expect(json['trainer_id'], 'trainer-1');
    expect(json['exercise_goal'], 'fitness');
    expect(json['health_purpose_type'], 'general');
    expect(json['preferred_time_slot'], '09:30');
    // 서버 계약이 date 라 날짜만 보낸다.
    expect(json['preferred_date'], '2026-08-20');
  });

  test('시작–종료 범위는 HH:MM-HH:MM 으로 나간다 (#1256)', () {
    final json = _draft(
      preferredTime: const PreferredTime.range(
        TimeOfDay(hour: 9, minute: 30),
        TimeOfDay(hour: 10, minute: 30),
      ),
    ).toJson();
    expect(json['preferred_time_slot'], '09:30-10:30');
  });

  test('시각 없는 요청은 직렬화 전에 막는다 (#1587)', () {
    // 서버도 422 로 막지만, 여기서 먼저 막지 않으면 원인을 찾기 어려운 422 로
    // 돌아온다. 시각 없는 상담은 승인해도 일정을 잡을 수 없다.
    expect(
      () => _draft(preferredTime: const PreferredTime.flexible()).toJson(),
      throwsArgumentError,
    );
  });

  test('폐지된 헬스장 대상 필드는 아예 싣지 않는다', () {
    // target_type 은 서버 기본값(trainer)에 맡기고, gym_id 는 보내지 않는다 —
    // 보내면 서버가 422 로 막는다.
    final json = _draft().toJson();
    expect(json.containsKey('gym_id'), isFalse);
    expect(json.containsKey('target_type'), isFalse);
  });

  test('대상 트레이너가 비면 직렬화 전에 막는다', () {
    // 그대로 나가면 원인을 찾기 어려운 422 로 돌아온다.
    expect(() => _draft(trainerId: '').toJson(), throwsArgumentError);
    expect(() => _draft(trainerId: '   ').toJson(), throwsArgumentError);
  });

  test('기타 목적인데 상세가 비면 막는다', () {
    expect(
      () => _draft(purpose: HealthPurposeType.other, detail: '  ').toJson(),
      throwsArgumentError,
    );
    expect(
      _draft(
        purpose: HealthPurposeType.other,
        detail: '허리 통증',
      ).toJson()['health_purpose_detail'],
      '허리 통증',
    );
  });

  test('동의하지 않으면 보내지 못한다 (#1022)', () {
    // 서버도 400 으로 막지만, 동의 없이 만든 요청이 트레이너 인박스에 남았다가
    // 수락되면 회원이 동의한 적 없는 기록이 넘어간다.
    expect(
      () => _draft(consent: false).toJson(),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('동의 여부를 함께 보낸다 (#1022)', () {
    expect(_draft().toJson()['data_sharing_consent'], isTrue);
  });

  group('운동 목표를 건강 목표 8종으로 통일 (#1992)', () {
    test('여덟 건강 목표가 빠짐없이 운동 목표로 이어진다', () {
      // 상담 폼이 `kHealthFocusOptions` 를 그대로 선택지로 쓴다. 한 값이라도
      // 빠지면 폼이 그 칩을 그리다 null 로 죽는다.
      expect(kHealthFocusExerciseGoals.keys, containsAll(kHealthFocusOptions));
      expect(kHealthFocusExerciseGoals.length, kHealthFocusOptions.length);
    });

    test('여덟 목표의 wire 값이 백엔드 Literal 과 같다', () {
      expect(
        <String>[
          for (final String focus in kHealthFocusOptions)
            exerciseGoalToWire(kHealthFocusExerciseGoals[focus]!),
        ],
        <String>[
          'weight_loss',
          'strength',
          'fitness',
          'posture',
          'rehab',
          'eating',
          'exercise_habit',
          'blood_pressure',
        ],
      );
    });

    test('wire 값을 되읽으면 같은 목표가 나온다', () {
      for (final ExerciseGoal goal in ExerciseGoal.values) {
        expect(exerciseGoalFromWire(exerciseGoalToWire(goal)), goal);
      }
    });

    test('기타는 건강 목표로 잇지 않는다', () {
      // 여덟 중 무엇인지 알려주는 바가 없다 — 서버 `EXERCISE_GOAL_FOCUS` 도 같다.
      expect(exerciseGoalHealthFocus(ExerciseGoal.other), isNull);
      expect(exerciseGoalHealthFocus(ExerciseGoal.health), isNull);
    });

    test('이미 저장된 요청의 복원이 깨지지 않는다', () {
      // 백필하지 않는다 — 조회·복원만 되면 된다.
      // `fitness` 는 이름만 `체력 강화` 로 바뀌었고 뜻은 같아 그대로 읽는다.
      expect(exerciseGoalFromWire('fitness'), ExerciseGoal.fitness);
      expect(
        exerciseGoalHealthFocus(ExerciseGoal.fitness),
        kHealthFocusFitness,
      );
      // 없앤 선택지지만 저장된 값은 그 값대로 읽는다 — `other` 로 뭉개면
      // 트레이너 화면에서 `건강 관리` 가 `기타` 로 바뀐다.
      expect(exerciseGoalFromWire('health'), ExerciseGoal.health);
      // 서버가 값을 더해도 앱이 예외로 죽지 않는다.
      expect(exerciseGoalFromWire('sports_rehab'), ExerciseGoal.other);
      expect(exerciseGoalFromWire(null), ExerciseGoal.other);
    });

    test('혈압 관리는 건강관리 목적 chronic 으로 나간다', () {
      // 트레이너 카드가 이 값을 `건강상태·주의사항` 으로 읽어, 주의해서 볼
      // 회원임이 드러난다.
      expect(
        healthPurposeFromExerciseGoal(ExerciseGoal.bloodPressure),
        HealthPurposeType.chronic,
      );
      expect(
        healthPurposeFromExerciseGoal(ExerciseGoal.rehab),
        HealthPurposeType.rehab,
      );
      // 여덟 목표는 상세를 강제하지 않는다 — `other` 만 상세가 필요하다.
      for (final String focus in kHealthFocusOptions) {
        expect(
          healthPurposeFromExerciseGoal(kHealthFocusExerciseGoals[focus]!),
          isNot(HealthPurposeType.other),
        );
      }
    });
  });
}
