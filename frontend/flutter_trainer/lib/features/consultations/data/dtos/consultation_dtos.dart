import 'package:oncare_trainer/features/consultations/domain/entities/consultation_request.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// Maps the `TrainerConsultationOut` JSON into [ConsultationRequest].
///
/// Kept out of the Dio repository so the mapping is unit-testable on its
/// own — the enum→한국어 tables below are the part most likely to drift
/// from the backend's `Literal` types.

/// 운동 목표 코드 → 화면 문구. The backend stores the code so the label can
/// change without a migration; the mapping has to live on one side and the
/// trainer console is the only place it is read.
///
/// 여덟 목표는 회원이 온보딩에서 고르는 건강 목표와 같은 값이라 `healthFocus*`
/// 문구를 그대로 쓴다(#1992) — 따로 든 표에서 `fitness` 하나가 `체력 증진` 으로
/// 남아, 회원 화면의 `체력 강화` 와 같은 것인지 트레이너가 알 수 없었다.
/// `health`·`other` 는 건강 목표에 대응이 없어 이 화면만 부르는 이름이다.
Map<String, String> exerciseGoalLabels(AppLocalizations l) => <String, String>{
  'weight_loss': l.healthFocusWeightLoss,
  'strength': l.healthFocusStrength,
  'fitness': l.healthFocusFitness,
  'posture': l.healthFocusPosture,
  'rehab': l.healthFocusRehab,
  'eating': l.healthFocusEating,
  'exercise_habit': l.healthFocusExerciseHabit,
  'blood_pressure': l.healthFocusBloodPressure,
  'other': l.goalOther,
  // 없앤 선택지지만 이미 접수된 요청에 남아 있다 — 저장된 그대로 보여준다.
  'health': l.goalHealth,
};

Map<String, String> healthPurposeLabels(AppLocalizations l) => <String, String>{
  'weight': l.goalWeightLoss,
  'chronic': l.memberHealthConditions,
  'rehab': l.healthFocusRehab,
  'general': l.goalHealth,
  'none': '-',
  'other': l.goalOther,
};

/// 희망 시각 코드 → 화면 문구. `flexible` 이거나 `HH:MM` 정확한 시각이다(#1256).
///
/// 예전 morning/afternoon/evening 값이 이미 접수된 요청에 남아 있을 수 있어, 그
/// 값을 포함해 패턴에 맞지 않는 코드는 전부 "시간 협의"로 떨어뜨린다 — 원문
/// 코드를 그대로 보여주면 트레이너 화면에 `morning` 이 노출된다.
final RegExp _kPreferredTimePattern = RegExp(
  r'^([01]\d|2[0-3]):([0-5]\d)(?:-([01]\d|2[0-3]):([0-5]\d))?$',
);

/// The fixed start time encoded in [code] as `HH:mm`, or `null` for
/// `flexible` or a legacy morning/afternoon/evening bucket — those carry no
/// exact time to seed a session with. A range (`HH:mm-HH:mm`) yields its
/// start.
String? preferredStartTime(String code) {
  final RegExpMatch? match = _kPreferredTimePattern.firstMatch(code);
  if (match == null) return null;
  return '${match.group(1)}:${match.group(2)}';
}

// 사용자 앱의 희망 시간 표시가 24시간 형식(`17:00–18:00`)이라 여기도 맞춘다
// — 같은 데이터를 두 화면이 다른 형식(오전/오후 대 24시간)으로 보여주면
// 트레이너가 회원과 통화·메시지로 시간을 맞출 때 헷갈린다.
String preferredTimeLabel(AppLocalizations l, String code) {
  final RegExpMatch? match = _kPreferredTimePattern.firstMatch(code);
  if (match == null) return l.slotFlexible;
  final String start = '${match.group(1)}:${match.group(2)}';
  if (match.group(3) == null) return start;
  return '$start–${match.group(3)}:${match.group(4)}';
}

/// `GET /v1/trainer/consultations` element → [ConsultationRequest].
///
/// Unknown enum codes fall back to the raw code rather than an empty
/// string: a backend that adds `sports_rehab` should show something the
/// trainer can act on, not a blank line.
ConsultationRequest consultationRequestFromJson(Map<String, Object?> json) {
  return ConsultationRequest(
    id: _str(json['id']),
    memberId: _str(json['member_id']),
    memberName: _nullable(json['member_name']) ?? '',
    goalCode: _str(json['exercise_goal']),
    purposeCode: _str(json['health_purpose_type']),
    purposeDetail: _nullable(json['health_purpose_detail']),
    preferredDate: _date(json['preferred_date']),
    preferredTimeCode: _str(json['preferred_time_slot']),
    slotStartsAt: DateTime.tryParse(_str(json['slot_starts_at']))?.toLocal(),
    slotDurationMinutes: (json['slot_duration_minutes'] as num?)?.toInt(),
    message: _nullable(json['message']),
    status: _str(json['status']),
    decisionNote: _nullable(json['decision_note']),
    createdAt: DateTime.tryParse(_str(json['created_at'])),
  );
}

String _str(Object? value) => value is String ? value : '';

/// Trims and collapses empty strings to null — the API sends `null` for an
/// omitted note, but a whitespace-only note would otherwise render an
/// empty bubble.
String? _nullable(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// 코드 → 라벨. 모르는 코드는 원문 그대로 — 백엔드가 새 값을 추가해도
/// 빈 줄이 아니라 트레이너가 읽을 무언가가 남는다.
String label(Map<String, String> table, Object? code) {
  final raw = _str(code);
  return table[raw] ?? (raw.isEmpty ? '-' : raw);
}

/// `YYYY-MM-DD` → [DateTime]. An unparseable value yields the epoch rather
/// than throwing: one malformed row must not blank the whole inbox.
DateTime _date(Object? value) =>
    DateTime.tryParse(_str(value)) ?? DateTime.fromMillisecondsSinceEpoch(0);
