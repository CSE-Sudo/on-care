/// 활동 포인트 적립 규칙 — 앱이 아는 단 하나의 원본. (#1786)
///
/// 백엔드 `points_service` 의 규칙과 같은 값이다. 앱 안에서는 목업 원장
/// (`DemoPointsLedger`)의 적립·한도와 포인트 적립 안내창의 문구가 모두 여기서
/// 숫자를 읽는다 — 안내창에 숫자를 따로 적으면 규칙을 바꿀 때 문구만 옛 값으로
/// 남는다. 서버 규칙을 바꾸면 이 값도 함께 바꾼다.
///
/// 하루 한도는 KST 달력 날짜로 센다.
enum PointsRule {
  /// 사진 분석으로 끼니가 새로 저장될 때.
  dietEntry(sourceType: 'diet_entry', points: 50, dailyCap: 3),

  /// 회원이 직접 추가한 운동.
  exerciseManual(sourceType: 'exercise_session', points: 20, dailyCap: 3),

  /// 추천·배정 운동 완료 — AI 가 추천한 루틴이든 트레이너가 배정한 루틴이든
  /// 완료해 생긴 운동 기록. 두 출처가 하루 한도를 함께 쓴다.
  routineComplete(sourceType: 'exercise_session', points: 50, dailyCap: 1);

  const PointsRule({
    required this.sourceType,
    required this.points,
    required this.dailyCap,
  });

  /// 적립의 근거가 된 기록 종류. 회수할 때 이 값과 기록 id 로 찾는다.
  final String sourceType;

  /// 한 번 적립하는 포인트.
  final int points;

  /// 하루에 적립받을 수 있는 횟수.
  final int dailyCap;
}
