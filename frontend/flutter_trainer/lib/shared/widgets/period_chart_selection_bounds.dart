import 'package:oncare_ui/oncare_ui.dart' show PeriodChartSelection;

/// 고른 칸을 지금 그리는 배열 안에서만 읽는다(#3249).
///
/// 회원 상세는 30초마다 기간 집계를 다시 읽는다. 다시 읽은 배열이 짧아지면
/// (기록이 지워져 `전체` 의 첫날이 늦어지는 등) 앞서 고른 칸이 범위를 벗어나,
/// 머리 숫자가 `values[picked]` 에서 RangeError 를 냈다. 범위 밖이면 고르지
/// 않은 것으로 본다 — 평균으로 돌아간다.
extension PeriodChartSelectionBounds on PeriodChartSelection {
  /// 길이 [length] 인 배열에서 쓸 수 있는 고른 칸. 없거나 범위 밖이면 null.
  int? selectedWithin(int length) {
    final int? index = selected;
    return index != null && index >= 0 && index < length ? index : null;
  }
}
