/// 키·몸무게 한 칸의 부분 수정에서 **"건드리지 않음"과 "지움"** 을 가르는 값.
///
/// `height_cm`·`weight_kg` 는 nullable 이고, 서버(`ProfileUpdate`)는 두 칸을
/// `nullable_fields` 로 둬 **키가 없으면 그대로 두고, 키가 `null` 로 오면
/// 값을 지운다.** 그런데 Dart 쪽 인자가 그냥 `num?` 이면 호출부가 그 구분을
/// 표현할 수 없어, 지금까지는 비운 칸이 "손대지 않음"으로 나갔다 — 저장은
/// 성공하고 화면을 다시 열면 지운 값이 돌아왔다(#1941).
///
/// - 인자를 주지 않으면(`null`) 그 값은 손대지 않는다.
/// - [MeasureUpdate.clear] 또는 `MeasureUpdate(null)` 은 값을 지운다.
/// - `MeasureUpdate(170)` 은 값을 세운다.
///
/// 목표 칸의 [GoalUpdate] 와 같은 구실을 한다. 따로 두는 것은 목표가 정수이고
/// 이 둘은 소수(`170.5`)이기 때문이다.
class MeasureUpdate {
  /// 이 값을 [value] 로 세운다. `null` 이면 지운다.
  const MeasureUpdate(this.value);

  /// 값을 지운다 — 서버로 JSON `null` 이 나간다.
  const MeasureUpdate.clear() : value = null;

  /// 세울 값. `null` 은 지움이다.
  final num? value;

  @override
  bool operator ==(Object other) =>
      other is MeasureUpdate && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MeasureUpdate($value)';
}
