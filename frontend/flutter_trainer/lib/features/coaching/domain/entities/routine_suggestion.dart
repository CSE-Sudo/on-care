/// An AI personal-exercise suggestion waiting for the trainer's judgement.
///
/// 배정 루틴([AssignedRoutine])과 같은 서버 모양(`RoutineOut`)에서 오지만 뜻이
/// 다르다 — 배정은 **이미 회원이 보고 있는 것**이고, 제안은 아직 아무에게도
/// 닿지 않은 후보다. 트레이너가 승인하는 순간 같은 행이 배정으로 바뀐다(#790).
/// 그래서 두 타입을 나눠 둔다: 한 목록에 섞이면 어느 쪽이 회원에게 갔는지 화면이
/// 구분할 수 없다.
class RoutineSuggestion {
  /// Creates a pending suggestion.
  const RoutineSuggestion({
    required this.id,
    required this.name,
    required this.minutes,
    required this.type,
    required this.reason,
    this.sets,
    this.reps,
    this.holdSeconds,
    this.weight,
    this.evidence = const <String>[],
  });

  /// Server id — the id the approve/dismiss calls address.
  final String id;

  /// Exercise name (e.g. "어깨 관절 보호 스트레칭").
  final String name;

  /// Recommended duration in minutes.
  final int minutes;

  /// Contract value — 걷기 | 유산소 | 근력 | 요가 | 스트레칭 | 기타.
  final String type;

  /// Why this exercise. **회원에게 그대로 전달되는 문구다** — 승인하면 회원 앱의
  /// 추천 카드에 이 글이 뜬다.
  final String reason;

  /// 근력 제안의 세트 수·한 세트당 횟수·중량(kg). 다른 유형은 null 이다.
  ///
  /// 승인하면 이 행이 그대로 배정이 된다 — 여기 값이 없으면 회원이 그 운동을
  /// 완료할 때 서버가 남길 세트가 없고, 그래프가 분에서 세트를 되짚어 아무도
  /// 적은 적 없는 수를 그린다. (#1321)
  final int? sets;
  final int? reps;

  /// 버티는 제안이면 한 세트를 버티는 시간(초). [reps] 와 한 자리를 나눠
  /// 쓴다 — 있으면 횟수가 비고, 없으면 반대다. (#1969)
  final int? holdSeconds;
  final double? weight;

  /// 이 제안이 무엇을 보고 만들어졌나(`최근 PT 피드백 반영` 등). 트레이너의
  /// 판단 재료이고 회원에게는 가지 않는다. 서버가 만든 문구이므로 번역하지 않고
  /// 그대로 보여 준다.
  final List<String> evidence;

  /// 수정 후 승인에 쓰는 사본. 보내지 않을 필드는 그대로 둔다.
  RoutineSuggestion copyWith({
    String? name,
    int? minutes,
    String? type,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
    String? reason,
  }) {
    return RoutineSuggestion(
      id: id,
      name: name ?? this.name,
      minutes: minutes ?? this.minutes,
      type: type ?? this.type,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      holdSeconds: holdSeconds ?? this.holdSeconds,
      weight: weight ?? this.weight,
      reason: reason ?? this.reason,
      evidence: evidence,
    );
  }
}
