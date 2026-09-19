/// 건강 목표 숫자의 허용 범위 — 두 앱이 서버와 같은 기준을 쓴다. (#1888)
///
/// 목표는 **한 벌의 컬럼**(`health_profiles`)이고, 회원 앱과 트레이너 웹이
/// 각자의 문으로 그것을 고친다. 서버는 `backend/app/schemas/health_goal_ranges.py`
/// 한 곳에서 범위를 보고, 화면은 여기서 본다 — 보내기 전에 어느 칸이 문제인지
/// 말해 줄 수 있는 것은 화면뿐이다. 서버까지 가면 "저장에 실패했어요" 토스트만
/// 남는다.
///
/// **두 벌로 적어 두면 갈라진다.** 전에는 트레이너 웹이 숫자를 직접 적어 두고
/// 회원 앱에는 아무 기준이 없어, 회원이 넣은 값을 트레이너가 고칠 수 없는
/// 자리가 생겼다. 값을 바꿀 때는 서버 모듈과 여기를 **함께** 고친다.
library;

/// 한 칸이 받는 정수 범위.
class AppGoalRange {
  const AppGoalRange(this.min, this.max);

  final int min;
  final int max;

  /// 범위 안인가. 빈 칸은 여기서 보지 않는다 — 목표를 세우지 않는 것은
  /// 할 수 있는 일이라, 비어 있는지는 부르는 쪽이 판단한다.
  bool contains(int value) => value >= min && value <= max;

  /// 적힌 값이 범위를 벗어났는가. 빈 칸과 숫자가 아닌 값은 `false` 다 —
  /// 숫자만 받는 칸이라 화면에서 이미 걸러진다.
  bool rejects(String text) {
    final int? value = int.tryParse(text.trim());
    return value != null && !contains(value);
  }
}

/// 서버 `health_goal_ranges` 와 같은 값. 위 설명대로 함께 고친다.
abstract final class AppGoalRanges {
  /// 한 주의 분. 주간 시간 목표의 상한이다.
  static const int minutesPerWeek = 7 * 24 * 60;

  /// 하루 섭취 칼로리. 하한이 0 이 아닌 이유는 굶는 목표를 세울 수 없기
  /// 때문이다 — 0kcal 목표는 달성률을 셀 수 없다.
  static const AppGoalRange dailyCalories = AppGoalRange(500, 10000);
  static const AppGoalRange dailySodiumMg = AppGoalRange(0, 50000);
  static const AppGoalRange dailySugarG = AppGoalRange(0, 1000);
  static const AppGoalRange dailyCarbsG = AppGoalRange(0, 2000);
  static const AppGoalRange dailyProteinG = AppGoalRange(0, 1000);
  static const AppGoalRange dailyFatG = AppGoalRange(0, 1000);

  /// 운동 목표는 운동 탭이 견주는 축과 같다 (#1139) — 소모는 하루, 유형별은
  /// 한 주다.
  static const AppGoalRange dailyBurnKcal = AppGoalRange(0, 20000);
  static const AppGoalRange weeklyCardioMinutes =
      AppGoalRange(0, minutesPerWeek);
  static const AppGoalRange weeklyStrengthSets = AppGoalRange(0, 1000);
  static const AppGoalRange weeklyFlexibilityMinutes =
      AppGoalRange(0, minutesPerWeek);

  /// 키·몸무게도 같은 자리에서 본다 — 트레이너 웹이 이미 같은 폼에서 함께
  /// 검사하던 값이고, 서버 스키마(`height_cm`·`weight_kg`)도 한 벌이다.
  static const AppGoalRange heightCm = AppGoalRange(50, 300);
  static const AppGoalRange weightKg = AppGoalRange(20, 500);

  /// 글로 적는 목표의 길이 상한.
  static const int conditionsMaxLength = 1000;
  static const int goalsMaxLength = 500;
}
