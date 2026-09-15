/// 기록을 저장해 받은 활동 포인트 — 생성 응답의 `points`. (#1786)
///
/// 식단 기록(`POST /diet/analyze`)·운동 직접 추가(`POST /exercise/sessions`)·배정
/// 루틴 완료(`POST /me/coach/routines/{id}/complete`) 응답에 실린다. 식단·운동·
/// 코치 세 기능이 함께 읽으므로 한 기능 아래가 아니라 여기에 둔다.
class PointsAward {
  const PointsAward({required this.awarded, required this.balance});

  /// 이번에 받은 포인트. 하루 한도를 넘었거나 적립 대상이 아니면 0 이다.
  final int awarded;

  /// 적립 뒤의 잔액.
  final int balance;

  /// 저장 알림에 적립 표시를 붙일지. 0 이면 표시 없이 저장 알림만 뜬다.
  bool get hasReward => awarded > 0;

  /// 응답의 `points` 를 읽는다. 없거나(이 필드를 모르는 서버) 모양이 다르면
  /// null 이다 — 적립을 못 읽었다고 저장 성공까지 실패로 만들 이유는 없다.
  static PointsAward? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? awarded = json['awarded'];
    final Object? balance = json['balance'];
    if (awarded is! num || balance is! num) return null;
    return PointsAward(awarded: awarded.toInt(), balance: balance.toInt());
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'awarded': awarded,
    'balance': balance,
  };
}
