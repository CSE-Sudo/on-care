/// A routine assigned to a member (the `RoutineOut` shape shared with the
/// member app's `/me/coach/routines`). Sending one from the trainer app is
/// how a member receives a routine.
class AssignedRoutine {
  const AssignedRoutine({
    required this.id,
    required this.name,
    required this.minutes,
    required this.type,
    required this.reason,
    required this.source,
    this.completed = false,
    this.date,
    this.intensity = 'moderate',
    this.sets,
    this.reps,
    this.holdSeconds,
    this.weight,
  });

  /// Server id (empty before assignment).
  final String id;

  /// Routine label (e.g. "AI 맞춤 루틴").
  final String name;

  /// Total minutes.
  final int minutes;

  /// One of 유산소 | 근력 | 스트레칭 | 기타.
  final String type;

  /// 언제 하라고 보내는 배정인가. 날짜를 정하지 않았으면 null. (#1276)
  final DateTime? date;

  /// 운동 강도 계약값('light'|'moderate'|'high'). 예상 칼로리의 근거이고,
  /// 회원이 완료할 때의 기본값이 된다 — 예전에는 배정에 강도를 실을 자리가
  /// 없어 늘 '보통'으로 계산됐다. (#1276)
  final String intensity;

  /// 근력 루틴의 세트 수·한 세트당 횟수·중량(kg). 다른 유형은 null 이다.
  /// (#1276, #1310)
  final int? sets;
  final int? reps;

  /// 버티는 루틴이면 한 세트를 버티는 시간(초). [reps] 와 한 자리를 나눠
  /// 쓴다 — 있으면 횟수가 비고, 없으면 반대다. (#1969)
  final int? holdSeconds;
  final double? weight;

  /// Why this routine — surfaced to the member.
  final String reason;

  /// `ai` (AI-suggested) or `trainer` (hand-assigned).
  final String source;

  /// 회원이 이 배정을 이미 수행했는가. 서버가 `completed` 로 함께 내려준다.
  ///
  /// 취소는 **아직 하지 않은** 것만 물릴 수 있다 — 이미 한 운동을 배정 목록에서
  /// 지운다고 그 기록이 없던 일이 되지는 않으므로, 취소 버튼을 걸어 두면
  /// 트레이너가 기록까지 지운다고 오해한다(#1020).
  final bool completed;
}
