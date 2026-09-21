import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/exercise_limits.dart';

/// Valid routine types accepted by the backend (`RoutineType` literal).
///
/// **번역하지 않는다.** 이 값은 화면 문구가 아니라 서버로 나가는 계약값이다 —
/// 영어 로케일에서 `type: 'Strength'` 를 보내면 백엔드 Literal 검증에 걸려 422 가
/// 난다. 화면에 보일 문구는 [routineTypeLabel] 로 따로 가져온다. (#501)
/// 유산소 / 근력 / 스트레칭 / 기타 네 가지다 (#996, #1276). 걷기는 유산소로,
/// 요가·유연성은 스트레칭으로 접혔다 — 없어진 정보는 **운동 이름**에 남는다
/// ("저강도 걷기"는 이름이 걷기이고 유형이 유산소다).
const List<String> kRoutineTypes = <String>['유산소', '근력', '스트레칭', '기타'];

/// 옛 유형 값 → 표준 유형. 화면이나 캐시에 남은 옛 값을 서버로 그대로 보내면
/// 유형 하나 때문에 배정이 실패하거나 '근력'으로 뭉개진다. (#996)
const Map<String, String> kLegacyRoutineTypes = <String, String>{
  '걷기': '유산소',
  '요가': '스트레칭',
  '유연성': '스트레칭',
};

/// 운동 강도 계약값 — 회원 앱의 가벼움/보통/높음과 같다. (#1276)
const List<String> kRoutineIntensities = <String>['light', 'moderate', 'high'];

/// 서버로 보낼 강도 하나. 모르는 값은 '보통'이다.
String normaliseRoutineIntensity(String? intensity) =>
    kRoutineIntensities.contains(intensity) ? intensity! : 'moderate';

/// 서버로 보낼 유형 하나. 모르는 값은 '근력'으로 떨어뜨린다 — 서버 Literal 이
/// 거절하면 배정 자체가 실패하기 때문이다.
String normaliseRoutineType(String type) {
  final String folded = kLegacyRoutineTypes[type] ?? type;
  return kRoutineTypes.contains(folded) ? folded : '근력';
}

/// `RoutineOut` JSON → [AssignedRoutine].
/// 저장된 계약값 → 화면 문구.
String routineTypeLabel(AppLocalizations l, String type) => switch (type) {
  '유산소' => l.routineTypeCardio,
  '근력' => l.routineTypeStrength,
  '스트레칭' => l.routineTypeFlexibility,
  '기타' => l.routineTypeOther,
  // 옛 값이 남아 있는 화면도 읽어야 한다 — 서버는 이미 접었지만 오래 열어 둔
  // 화면이나 캐시에는 그대로 있을 수 있다. (#996)
  '걷기' => l.routineTypeCardio,
  '요가' || '유연성' => l.routineTypeFlexibility,
  // 서버가 새 유형을 추가했는데 앱이 모르는 경우 — 원문을 그대로 보여 준다.
  _ => type,
};

/// 운동 이름 입력칸의 유형별 예시. 회원 앱 운동 추가(#1460)와 같은 문구를
/// 쓴다 — 두 앱이 서로 다른 예시를 보여주면 트레이너가 회원 기록과 다른
/// 이름 관습을 쓰게 된다.
String routineTypeNameHint(AppLocalizations l, String type) => switch (type) {
  '유산소' => l.routineFieldExerciseNameHintCardio,
  '근력' => l.routineFieldExerciseNameHintStrength,
  '스트레칭' => l.routineFieldExerciseNameHintFlexibility,
  '기타' => l.routineFieldExerciseNameHintOther,
  '걷기' => l.routineFieldExerciseNameHintCardio,
  '요가' || '유연성' => l.routineFieldExerciseNameHintFlexibility,
  _ => l.routineFieldExerciseNameHint,
};

/// 저장된 강도 계약값 → 화면 문구.
String routineIntensityLabel(AppLocalizations l, String intensity) =>
    switch (intensity) {
      'light' => l.intensityLight,
      'high' => l.intensityHigh,
      _ => l.intensityModerate,
    };

AssignedRoutine assignedRoutineFromJson(Map<String, Object?> json) {
  return AssignedRoutine(
    id: _str(json['id']),
    name: _str(json['name']),
    minutes: json['minutes'] is num ? (json['minutes']! as num).toInt() : 0,
    type: _str(json['type']),
    reason: _str(json['reason']),
    source: _str(json['source']),
    completed: json['completed'] == true,
    date: DateTime.tryParse(_str(json['exercise_date'])),
    intensity: normaliseRoutineIntensity(json['intensity'] as String?),
    sets: (json['sets'] as num?)?.toInt(),
    reps: (json['reps'] as num?)?.toInt(),
    holdSeconds: (json['hold_seconds'] as num?)?.toInt(),
    weight: (json['weight'] as num?)?.toDouble(),
  );
}

/// [AssignedRoutine] → `RoutineAssignRequest` JSON. Clamps/normalises so the
/// backend's validators (minutes 0–600, type literal, lengths) never 422.
///
/// [clientRequestId] 는 전송 시도의 멱등키다. 넣어 보내면 같은 키의 재요청이
/// 새 배정을 만들지 않는다(#581). 생략하면 서버는 기존처럼 매번 새로 배정한다.
Map<String, Object?> assignRoutineToJson(
  AssignedRoutine r, {
  String? clientRequestId,
}) {
  final String type = normaliseRoutineType(r.type);
  final bool strength = type == '근력';
  return <String, Object?>{
    'name': r.name.trim().isEmpty ? 'AI 맞춤 추천안' : _truncate(r.name.trim(), 100),
    'minutes': r.minutes.clamp(0, 600),
    'type': type,
    'exercise_date': r.date == null ? null : _ymd(r.date!),
    'intensity': normaliseRoutineIntensity(r.intensity),
    // 세트·횟수·중량은 근력에만 싣는다 — 서버도 다른 유형에서는 버린다.
    // (#1276, #1310)
    'sets': strength ? r.sets?.clamp(1, 99) : null,
    // 한 세트는 회로든 초로든 한 번만 잰다 — 초가 있으면 횟수를 비운다.
    // (#1969)
    'reps': strength && r.holdSeconds == null ? r.reps?.clamp(1, 999) : null,
    'hold_seconds': strength
        ? r.holdSeconds?.clamp(1, kMaxExerciseHoldSeconds)
        : null,
    'weight': strength ? r.weight?.clamp(0, 1000) : null,
    'reason': _truncate(r.reason, 200),
    'source': r.source == 'trainer' ? 'trainer' : 'ai',
    'client_request_id': ?clientRequestId,
  };
}

/// `YYYY-MM-DD` — 서버가 `date` 로 받는 형식.
String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _str(Object? v) => v is String ? v : '';

String _truncate(String s, int max) =>
    s.length <= max ? s : s.substring(0, max);

/// Picks the dominant exercise type and the routine `source` for a
/// composed send (AI-suggested items still on screen + trainer-added
/// custom exercises). Pure so the "all-custom falls back to 근력/ai" class
/// of bug is directly unit-testable (review), matching the [assignRoutine]
/// summary the trainer sees before sending.
///
///  * `type` — the most frequent type across both lists (ties keep the
///    first-seen type via a strict `>` comparison), defaulting to '근력'
///    when there are no exercises at all.
///  * `source` — `'trainer'` when every AI suggestion was removed (an
///    all-custom routine is trainer-authored, not AI-generated), `'ai'`
///    otherwise.
({String type, String source}) summaryTypeAndSource({
  required List<String> aiItemTypes,
  required List<String> customItemTypes,
}) {
  final counts = <String, int>{};
  for (final t in <String>[...aiItemTypes, ...customItemTypes]) {
    counts[t] = (counts[t] ?? 0) + 1;
  }
  var type = '근력';
  var best = 0;
  counts.forEach((t, c) {
    if (c > best) {
      best = c;
      type = t;
    }
  });
  return (type: type, source: aiItemTypes.isEmpty ? 'trainer' : 'ai');
}
