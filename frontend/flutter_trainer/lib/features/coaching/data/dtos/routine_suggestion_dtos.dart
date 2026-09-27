import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_limits.dart';

/// 서버가 보내는 AI 개인운동 근거 코드(`routine_suggestion_service.EV_*`). (#2301)
///
/// 서버는 문장 대신 이 코드를 보내고, 화면 문구는 [routineEvidenceLabel] 이
/// 화면 언어로 고른다. 문장으로 보내면 한 번 준비한 후보의 근거가 영어 화면에서도
/// 한국어로 남는다.
abstract final class RoutineEvidence {
  /// 최근 PT 뒤 트레이너 피드백(PT 노트·루틴 피드백)이 있다.
  static const String recentPtFeedback = 'recent_pt_feedback';

  /// 최근 운동 시간이 근력에 몰려 있다.
  static const String strengthHeavy = 'strength_heavy';

  /// 혈압 관리가 필요한 회원이다.
  static const String bloodPressureGoal = 'blood_pressure_goal';

  /// 최근 유산소 기록이 없다.
  static const String lowCardio = 'low_cardio';

  /// 최근 운동 기록을 보고 만들었다.
  static const String recentRecord = 'recent_record';
}

/// 근거 코드 → 화면 문구. (#2301)
///
/// 모르는 값은 원문 그대로다 — 서버가 새 코드를 더했거나, 트레이너·다른 경로가
/// 직접 적은 근거 문장이다. 근거 하나를 못 읽는다고 칩을 숨기면 판단 재료가
/// 사라진다.
String routineEvidenceLabel(AppLocalizations l, String code) => switch (code) {
  RoutineEvidence.recentPtFeedback => l.routineEvidenceRecentPtFeedback,
  RoutineEvidence.strengthHeavy => l.routineEvidenceStrengthHeavy,
  RoutineEvidence.bloodPressureGoal => l.routineEvidenceBloodPressureGoal,
  RoutineEvidence.lowCardio => l.routineEvidenceLowCardio,
  RoutineEvidence.recentRecord => l.routineEvidenceRecentRecord,
  _ => code,
};

/// `RoutineOut` JSON → [RoutineSuggestion].
///
/// 모르는 필드는 무시하고, 빠진 필드는 빈 값으로 둔다 — 제안 하나의 모양이
/// 예상과 달라서 검토 목록 전체가 안 뜨면 트레이너는 검토할 것이 있는지조차
/// 알 수 없다.
RoutineSuggestion routineSuggestionFromJson(Map<String, Object?> json) {
  return RoutineSuggestion(
    id: _str(json['id']),
    name: _str(json['name']),
    minutes: json['minutes'] is num ? (json['minutes']! as num).toInt() : 0,
    type: _str(json['type']),
    sets: (json['sets'] as num?)?.toInt(),
    reps: (json['reps'] as num?)?.toInt(),
    holdSeconds: (json['hold_seconds'] as num?)?.toInt(),
    weight: (json['weight'] as num?)?.toDouble(),
    reason: _str(json['reason']),
    evidence: _strings(json['evidence']),
  );
}

/// [RoutineSuggestionApproveRequest] JSON — 보낼 필드만 담는다.
///
/// 서버의 부분 수정 규약(#495)에서 **명시적 null 은 422** 다. 그래서 "그대로
/// 승인"은 빈 객체를 보내고, 수정 후 승인은 바뀐 필드만 싣는다. 값 범위는
/// 배정(`assignRoutineToJson`)과 같은 규칙으로 미리 맞춰 422 왕복을 막는다.
Map<String, Object?> routineSuggestionApproveToJson({
  String? name,
  int? minutes,
  String? type,
  int? sets,
  int? reps,
  int? holdSeconds,
  double? weight,
  String? reason,
}) {
  final trimmedName = name?.trim();
  // 세트·횟수·중량은 **근력으로 승인할 때만** 싣는다. 서버도 다른 유형에서는
  // 버리지만, 보내지 않는 편이 화면이 무엇을 정했는지와 payload 가 어긋날
  // 자리를 아예 없앤다. (#1321)
  final bool strength = type == '근력';
  return <String, Object?>{
    // 빈 이름은 서버가 400 으로 거른다. 보내지 않는 것이 곧 '이름은 그대로'다.
    if (trimmedName != null && trimmedName.isNotEmpty)
      'name': _truncate(trimmedName, 100),
    if (minutes != null) 'minutes': minutes.clamp(0, 600),
    if (type != null && kRoutineTypes.contains(type)) 'type': type,
    if (strength && sets != null) 'sets': sets.clamp(1, 99),
    // 한 세트는 회로든 초로든 한 번만 잰다. 초로 승인하면 횟수를 보내지
    // 않고, 서버가 제안 행의 옛 횟수를 지운다(#1969).
    if (strength && holdSeconds == null && reps != null)
      'reps': reps.clamp(1, 999),
    if (strength && holdSeconds != null)
      'hold_seconds': holdSeconds.clamp(1, kMaxExerciseHoldSeconds),
    if (strength && weight != null) 'weight': weight.clamp(0, 1000),
    if (reason != null) 'reason': _truncate(reason.trim(), 200),
  };
}

List<String> _strings(Object? v) {
  if (v is! List) return const <String>[];
  return <String>[
    for (final item in v)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

String _str(Object? v) => v is String ? v : '';

String _truncate(String s, int max) =>
    s.length <= max ? s : s.substring(0, max);
