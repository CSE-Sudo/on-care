import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/shared/exercise_limits.dart';

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
