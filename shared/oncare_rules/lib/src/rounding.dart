/// 서버(Python)와 같은 반올림 — 두 앱이 서버와 같은 수를 내야 하는 자리는 모두
/// 이 파일의 함수를 쓴다. (#2860)
///
/// Python `round()` 는 정확히 절반(`x.5`)일 때 **짝수 쪽**으로 간다
/// (`round(2.5) == 2`, `round(3.5) == 4`). Dart `num.round()` 는 0 에서 먼 쪽이라
/// (`2.5.round() == 3`) 같은 기록이 앱 미리보기와 서버 저장값에서 1 씩 갈린다.
/// 서버 규칙은 바꾸지 않는다 — 이미 저장된 값과 집계를 지켜야 해서 앱이 맞춘다.
library;

/// Python `round(x)` 와 같은 정수 반올림(0.5 는 짝수 쪽).
///
/// 이진 실수 값 그대로 비교한다 — `x - floor(x)` 는 |x| < 2^52 에서 정확히
/// 계산되므로, Python 이 실제 이진수 값으로 반올림하는 것과 같은 답이 나온다.
int pyRound(num x) {
  final double v = x.toDouble();
  final double floor = v.floorToDouble();
  final double diff = v - floor;
  final int f = floor.toInt();
  if (diff > 0.5) return f + 1;
  if (diff < 0.5) return f;
  return f.isEven ? f : f + 1;
}

/// 초 → 분. 서버 `ExerciseSessionCreate._minutes_from_seconds`
/// (`max(1, round(seconds / 60))`)와 같다. (#2071, #2860)
///
/// 0 이하는 0 이다(기록 없음). 1초짜리 기록도 0분이 되지 않는다 — `minutes > 0`
/// 이 저장의 전제라, 반올림 때문에 회원 기록이 거절되면 안 된다.
/// 150초(2분 30초)는 2분, 270초(4분 30초)는 4분이다.
int minutesFromSeconds(int seconds) {
  if (seconds <= 0) return 0;
  final int minutes = pyRound(seconds / 60);
  return minutes < 1 ? 1 : minutes;
}
