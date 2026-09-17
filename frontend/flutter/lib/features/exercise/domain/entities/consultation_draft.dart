/// `POST /consultations` 로 보내는 값. (#327)
///
/// 화면이 들고 있던 선택지는 현지화된 **라벨**이라 서버 계약(enum 코드)과 맞지 않았다.
/// 여기 enum 이 계약이고, 라벨은 화면이 이 enum 으로부터 만든다.
library;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:oncare/features/account/domain/entities/health_focus.dart';

/// 상담 신청의 운동 목표. 온보딩·MY 의 건강 목표 8종(`kHealthFocusOptions`)과 같은
/// 목록·같은 순서이고, 그 여덟 중 어디에도 넣기 어려운 경우를 위한
/// [ExerciseGoal.other] 하나가 더 있다. (#1992)
///
/// [ExerciseGoal.health] 는 **복원 전용**이다 — 예전 `건강 관리` 선택지로 이미
/// 저장된 요청을 화면에 그릴 때만 쓴다. 새 신청에서는 고를 수 없고, 서버도 더는
/// 받지 않는다.
enum ExerciseGoal {
  weightLoss,
  strength,
  fitness,
  posture,
  rehab,
  eating,
  exerciseHabit,
  bloodPressure,
  other,
  health,
}

/// 건강 목표 저장 값 → 운동 목표. 상담 폼은 선택지를 `kHealthFocusOptions` 에서
/// 그대로 읽고, 고른 값을 여기서 전송 enum 으로 바꾼다 — 두 화면이 목록을 따로
/// 들면 지금처럼 갈라진다(#1992).
const Map<String, ExerciseGoal> kHealthFocusExerciseGoals =
    <String, ExerciseGoal>{
      kHealthFocusWeightLoss: ExerciseGoal.weightLoss,
      kHealthFocusStrength: ExerciseGoal.strength,
      kHealthFocusFitness: ExerciseGoal.fitness,
      kHealthFocusPosture: ExerciseGoal.posture,
      kHealthFocusRehab: ExerciseGoal.rehab,
      kHealthFocusEating: ExerciseGoal.eating,
      kHealthFocusExerciseHabit: ExerciseGoal.exerciseHabit,
      kHealthFocusBloodPressure: ExerciseGoal.bloodPressure,
    };

/// 운동 목표 → 건강 목표 저장 값. 화면 문구를 `healthFocusLabel` 로 만들 때 쓴다.
/// 여덟 목표 밖인 [ExerciseGoal.other]·[ExerciseGoal.health] 는 `null` 이다 —
/// 이 둘은 부르는 이름을 화면이 따로 들고 있다.
String? exerciseGoalHealthFocus(ExerciseGoal goal) {
  for (final MapEntry<String, ExerciseGoal> entry
      in kHealthFocusExerciseGoals.entries) {
    if (entry.value == goal) return entry.key;
  }
  return null;
}

enum HealthPurposeType { weight, chronic, rehab, general, none, other }

/// 상담 희망 시각. 오전/오후/저녁 카테고리 대신 정확한 시각만 남긴다(#1256)
/// — 과거 `PreferredTimeSlot{morning,afternoon,evening,flexible}` enum을
/// 대체한다.
///
/// 신청 화면에서는 반드시 시작–종료가 채워진다(#1587). [PreferredTime.flexible]
/// 은 **복원 전용**이다 — 이미 저장된 `flexible`·레거시 값을 화면에 그릴 때만
/// 쓰고, 그 값으로 새 신청을 보내면 [ConsultationDraft.toJson] 이 막는다.
class PreferredTime {
  /// 시각을 알 수 없는 과거 요청. 새 신청에는 쓰지 않는다(#1587).
  const PreferredTime.flexible() : start = null, end = null;
  const PreferredTime.at(TimeOfDay time) : start = time, end = time;
  const PreferredTime.range(this.start, this.end);

  /// null 이면 시각을 알 수 없는 과거 요청("시간 협의")이다.
  final TimeOfDay? start;
  final TimeOfDay? end;
  TimeOfDay? get timeOfDay => start;

  bool get isFlexible => start == null;

  @override
  bool operator ==(Object other) =>
      other is PreferredTime && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// 백엔드 `ConsultationCreate` 의 Literal 값과 문자 그대로 같아야 한다.
String exerciseGoalToWire(ExerciseGoal g) => switch (g) {
  ExerciseGoal.weightLoss => 'weight_loss',
  ExerciseGoal.strength => 'strength',
  ExerciseGoal.fitness => 'fitness',
  ExerciseGoal.posture => 'posture',
  ExerciseGoal.rehab => 'rehab',
  ExerciseGoal.eating => 'eating',
  ExerciseGoal.exerciseHabit => 'exercise_habit',
  ExerciseGoal.bloodPressure => 'blood_pressure',
  ExerciseGoal.other => 'other',
  ExerciseGoal.health => 'health',
};

String healthPurposeToWire(HealthPurposeType p) => switch (p) {
  HealthPurposeType.weight => 'weight',
  HealthPurposeType.chronic => 'chronic',
  HealthPurposeType.rehab => 'rehab',
  HealthPurposeType.general => 'general',
  HealthPurposeType.none => 'none',
  HealthPurposeType.other => 'other',
};

/// 회원이 고르는 목표는 하나뿐이다("운동 목표") — 예전에는 건강관리 목적을
/// 따로 또 고르게 했는데, 둘이 왜 다른 선택이어야 하는지 회원 입장에서
/// 구분할 근거가 없었다(#1112). 서버 계약(`health_purpose_type`)은 그대로
/// 두고, 화면에서 고른 운동 목표로부터 이 값을 자동으로 채운다.
HealthPurposeType healthPurposeFromExerciseGoal(ExerciseGoal goal) =>
    switch (goal) {
      ExerciseGoal.weightLoss => HealthPurposeType.weight,
      ExerciseGoal.strength => HealthPurposeType.general,
      ExerciseGoal.fitness => HealthPurposeType.general,
      ExerciseGoal.posture => HealthPurposeType.rehab,
      ExerciseGoal.rehab => HealthPurposeType.rehab,
      ExerciseGoal.eating => HealthPurposeType.general,
      ExerciseGoal.exerciseHabit => HealthPurposeType.general,
      // 혈압은 꾸준히 관리하는 축이라 `chronic` 이다 — 트레이너 카드가 이 값을
      // `건강상태·주의사항` 으로 읽어, 주의해서 볼 회원임이 드러난다.
      ExerciseGoal.bloodPressure => HealthPurposeType.chronic,
      ExerciseGoal.other => HealthPurposeType.other,
      ExerciseGoal.health => HealthPurposeType.general,
    };

/// `HH:MM` 또는 `HH:MM-HH:MM`. 시각이 없는 값은 서버가 더는 받지 않으므로
/// (#1587) 여기까지 오기 전에 [ConsultationDraft.toJson] 이 막는다 — 남겨 둔
/// `flexible` 은 이미 저장된 요청을 다시 직렬화하는 경로를 위한 것이다.
String preferredTimeSlotToWire(PreferredTime t) {
  final TimeOfDay? start = t.start;
  if (start == null) return 'flexible';
  String hm(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
  final TimeOfDay end = t.end ?? start;
  return start == end ? hm(start) : '${hm(start)}-${hm(end)}';
}

/// 상담 신청 내용. 대상은 트레이너 한 사람이다 — 헬스장 전체로 보내는 갈래는
/// 없앴고, 서버도 `trainer_id` 없는 요청을 422 로 거절한다.
class ConsultationDraft {
  const ConsultationDraft({
    required this.trainerId,
    required this.exerciseGoal,
    required this.healthPurposeType,
    required this.healthPurposeDetail,
    required this.preferredDate,
    required this.preferredTimeSlot,
    required this.message,
    this.dataSharingConsent = false,
  });

  /// 상담을 받을 트레이너. 헬스장에서 시작해도 소속 트레이너 중 한 명을 고른 뒤에
  /// 요청이 만들어진다.
  final String trainerId;
  final ExerciseGoal exerciseGoal;
  final HealthPurposeType healthPurposeType;

  /// `healthPurposeType` 이 other 면 필수 — 서버가 422 로 강제한다.
  final String? healthPurposeDetail;
  final DateTime preferredDate;
  final PreferredTime preferredTimeSlot;
  final String? message;

  /// 식단·운동·신체 정보를 이 트레이너에게 보여 주는 데 동의했는가. (#1022)
  ///
  /// 신청은 회원이 하고 연결은 나중에 트레이너가 수락하며 만들어진다. 회원이
  /// 그 자리에 없으므로 동의는 **신청할 때** 받는다.
  final bool dataSharingConsent;

  Map<String, Object?> toJson() {
    // other 목적에는 상세가 있어야 한다(서버 422). 여기서 막지 않으면 원인을 찾기
    // 어려운 422 로 돌아온다.
    if (trainerId.trim().isEmpty) {
      throw ArgumentError('상담을 요청할 트레이너를 지정해야 합니다.');
    }
    if (healthPurposeType == HealthPurposeType.other &&
        (healthPurposeDetail == null || healthPurposeDetail!.trim().isEmpty)) {
      throw ArgumentError('기타 건강관리 목적에는 상세 내용이 필요합니다.');
    }
    if (preferredTimeSlot.isFlexible) {
      // 서버도 막지만(422) 여기서 먼저 막는다 — 시각 없는 요청은 트레이너가
      // 승인해도 잡을 시간이 없어, 승인만 되고 상담 일정은 만들어지지 않는다.
      // (#1587)
      throw ArgumentError('상담 희망 시각을 골라야 신청할 수 있습니다.');
    }
    if (!dataSharingConsent) {
      // 서버도 막지만(400) 여기서 먼저 막는다 — 동의 없이 보낸 요청이 트레이너
      // 인박스에 남았다가 수락되면, 회원이 동의한 적 없는 기록이 넘어간다.
      throw ArgumentError('식단·운동 기록 공유에 동의해야 상담을 신청할 수 있습니다.');
    }
    return _json();
  }

  Map<String, Object?> _json() => <String, Object?>{
    // `target_type` 은 서버 기본값(trainer)에 맡긴다 — 값이 하나뿐이다.
    'trainer_id': trainerId,
    'exercise_goal': exerciseGoalToWire(exerciseGoal),
    'health_purpose_type': healthPurposeToWire(healthPurposeType),
    'health_purpose_detail': healthPurposeDetail,
    // 날짜만 보낸다(YYYY-MM-DD) — 서버 계약이 date 다.
    'preferred_date':
        '${preferredDate.year.toString().padLeft(4, '0')}-'
        '${preferredDate.month.toString().padLeft(2, '0')}-'
        '${preferredDate.day.toString().padLeft(2, '0')}',
    'preferred_time_slot': preferredTimeSlotToWire(preferredTimeSlot),
    'message': message,
    'data_sharing_consent': dataSharingConsent,
  };
}

/// 서버 코드 → enum. 모르는 값은 `other`/`flexible` 로 떨어뜨려, 서버가 값을 추가해도
/// 앱이 예외로 죽지 않게 한다.
ExerciseGoal exerciseGoalFromWire(String? s) => switch (s) {
  'weight_loss' => ExerciseGoal.weightLoss,
  'strength' => ExerciseGoal.strength,
  // 예전 `체력 향상` 으로 저장된 값이다 — 이름만 `체력 강화` 로 바뀌었고 뜻은
  // 같아 그대로 읽는다(#1992).
  'fitness' => ExerciseGoal.fitness,
  'posture' => ExerciseGoal.posture,
  'rehab' => ExerciseGoal.rehab,
  'eating' => ExerciseGoal.eating,
  'exercise_habit' => ExerciseGoal.exerciseHabit,
  'blood_pressure' => ExerciseGoal.bloodPressure,
  // 없앤 선택지지만 이미 저장된 요청에 남아 있다. 건강 목표로는 잇지 않는다.
  'health' => ExerciseGoal.health,
  _ => ExerciseGoal.other,
};

HealthPurposeType healthPurposeFromWire(String? s) => switch (s) {
  'weight' => HealthPurposeType.weight,
  'chronic' => HealthPurposeType.chronic,
  'rehab' => HealthPurposeType.rehab,
  'general' => HealthPurposeType.general,
  'none' => HealthPurposeType.none,
  _ => HealthPurposeType.other,
};

/// `HH:MM` 이면 그 시각으로, 그 외(과거 `flexible`·`morning`/`afternoon`/
/// `evening` 값이나 알 수 없는 값 포함)는 전부 "시간 협의"로 떨어뜨린다(#1256).
///
/// 새 신청은 항상 정확한 시각을 담지만(#1587), 이미 저장된 요청은 그대로
/// 남아 있어 이 폴백이 계속 필요하다 — 걷어내면 그 행에서 화면이 깨진다.
final RegExp _kTimePattern = RegExp(
  r'^([01]\d|2[0-3]):([0-5]\d)(?:-([01]\d|2[0-3]):([0-5]\d))?$',
);

PreferredTime preferredTimeSlotFromWire(String? s) {
  final RegExpMatch? match = s == null ? null : _kTimePattern.firstMatch(s);
  if (match == null) return const PreferredTime.flexible();
  final start = TimeOfDay(
    hour: int.parse(match.group(1)!),
    minute: int.parse(match.group(2)!),
  );
  final end = match.group(3) == null
      ? start
      : TimeOfDay(
          hour: int.parse(match.group(3)!),
          minute: int.parse(match.group(4)!),
        );
  return PreferredTime.range(start, end);
}
