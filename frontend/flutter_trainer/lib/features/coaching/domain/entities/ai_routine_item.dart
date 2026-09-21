/// One AI-suggested routine item for a client (AI 루틴 탭). Decoded from
/// the drift `ClientAiRoutines` row.
class AiRoutineItem {
  /// Creates a routine item.
  const AiRoutineItem({
    required this.id,
    required this.name,
    required this.minutes,
    required this.type,
    required this.reason,
    this.sets = 0,
    this.reps = 0,
    this.holdSeconds = 0,
    this.weight = 0,
  });

  /// Row id (used to key per-item edits).
  final String id;

  /// Exercise name (e.g. "저강도 유산소 (걷기)").
  final String name;

  /// Suggested duration in minutes.
  final int minutes;

  /// 유산소 | 근력 | 스트레칭.
  final String type;

  /// Why the AI suggests it (e.g. "혈압 안정에 효과적").
  final String reason;

  /// 근력 운동에서만 쓴다(#1029, #1310) — 2단계 프로그램 선택에서 트레이너가
  /// 채운 세트·횟수·중량을 그대로 옮긴다. drift `ClientAiRoutines` 행에는 이
  /// 값이 없어 0 으로 읽힌다.
  final int sets;
  final int reps;

  /// 버티는 운동이면 한 세트를 버티는 시간(초). [reps] 와 한 자리를 나눠
  /// 쓴다 — 있으면 횟수가 0 이고, 없으면 반대다. 0 이 "적지 않음" 이다.
  /// (#1969)
  final int holdSeconds;

  final double weight;
}
