/// 운동 그래프가 쓰는 **지표 정의**. 회원 앱
/// `features/exercise/domain/entities/exercise_load.dart` 와 같은 규칙을 여기에도
/// 적어 둔다 — 두 앱은 패키지가 갈라져 있어 코드를 공유할 수 없다
/// (`activity_charts`·`metric_trend_chart` 와 같은 방식이다).
///
/// 한쪽만 고치면 같은 회원의 같은 주가 회원 화면과 트레이너 화면에서 다른
/// 이야기를 한다. 값을 바꿀 일이 생기면 **양쪽을 함께** 고친다.
library;

import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';

/// 유형별로 재는 단위가 다르다.
///
///   * 유산소  → **분**
///   * 근력    → **세트**
///   * 스트레칭 → **분**
///
/// 서로 더할 수 없는 값이라, 높이를 비교해야 하는 자리(도넛·막대)에서는 셋이
/// 함께 만든 결과인 **소모 칼로리**를 쓴다.
enum ExerciseKind { cardio, strength, stretching }

/// 근력 1세트가 차지하는 **벽시계 시간**(세트 + 휴식). 세트 수를 따로 기록하지
/// 않는 응답(분만 있는 기록)을 세트로 되돌릴 때 쓰는 다리다.
const double kStrengthMinutesPerSet = 3;

/// 분만 남은 근력 기록 → 세트 수(대략). 45분 ≈ 15세트.
int setsFromStrengthMinutes(num minutes) =>
    (minutes / kStrengthMinutesPerSet).round();

/// 하루 소모 칼로리 목표 — 회원이 MY 에서 정하지 않았을 때의 **기본값**.
///
/// 회원 앱 `kDefaultExerciseLoadGoals` 와 같은 값이다. 회원이 **매일** 닿을 수
/// 있는 선으로 잡는다 — 하루 한 시간 넘게 움직여야 나오는 500kcal 로 두면
/// 꾸준히 한 주에도 목표선을 한 번도 못 넘어, 회원과 트레이너가 같이 보는
/// 그래프가 늘 '실패' 로만 읽혔다.
///
/// 실제 그래프는 이 상수가 아니라 회원 프로필에서 읽은 [ExerciseBurnGoals] 를
/// 쓴다(#2157).
const double kDailyBurnKcal = 300;

/// 주간 소모 칼로리 목표의 기본값 — 하루 목표 × 7.
const double kWeeklyBurnKcal = kDailyBurnKcal * 7;

/// 주간 유산소 목표(분)의 기본값. WHO 의 주 150분 중강도 권고.
const double kWeeklyCardioMinutes = 150;

/// 주간 근력 목표(세트)의 기본값. 하루 3세트 × 7일.
const double kWeeklyStrengthSets = 21;

/// 주간 스트레칭 목표(분)의 기본값.
const double kWeeklyStretchingMinutes = 60;

/// 운동 그래프가 견주는 **회원의 목표** 한 벌 (#2157).
///
/// 회원 앱은 이 값을 MY 건강 목표(프로필 `daily_burn_kcal`·
/// `weekly_cardio_minutes`·`weekly_strength_sets`·`weekly_flexibility_minutes`)
/// 에서 읽는다(회원 앱 #1139, `exerciseLoadGoalsProvider`). 트레이너 화면만 코드
/// 상수를 쓰면 회원이 하루 목표를 400kcal 로 올려도 트레이너는 300kcal 선을
/// 보고, 회원 폰에서 모자란 날이 트레이너 화면에서는 넘친 날로 읽힌다.
class ExerciseBurnGoals {
  /// Creates a goal set. 주지 않은 값은 회원 앱과 같은 기본값이다.
  const ExerciseBurnGoals({
    this.dailyBurnKcal = kDailyBurnKcal,
    this.weeklyCardioMinutes = kWeeklyCardioMinutes,
    this.weeklyStrengthSets = kWeeklyStrengthSets,
    this.weeklyStretchingMinutes = kWeeklyStretchingMinutes,
  });

  /// 회원 건강 프로필에서 읽는다. 프로필이 없거나(읽는 중·실패) 칸이 비어
  /// 있으면 그 칸만 기본값이다 — 회원 앱과 같은 규칙이다.
  factory ExerciseBurnGoals.fromProfile(MemberHealthProfile? profile) {
    if (profile == null) return kDefaultExerciseBurnGoals;
    return ExerciseBurnGoals(
      dailyBurnKcal: profile.dailyBurnKcal?.toDouble() ?? kDailyBurnKcal,
      weeklyCardioMinutes:
          profile.weeklyCardioMinutes?.toDouble() ?? kWeeklyCardioMinutes,
      weeklyStrengthSets:
          profile.weeklyStrengthSets?.toDouble() ?? kWeeklyStrengthSets,
      weeklyStretchingMinutes:
          profile.weeklyFlexibilityMinutes?.toDouble() ??
          kWeeklyStretchingMinutes,
    );
  }

  /// 하루 소모 칼로리 목표. `오늘` 도넛이 이 값을 채운다.
  final double dailyBurnKcal;

  final double weeklyCardioMinutes;
  final double weeklyStrengthSets;
  final double weeklyStretchingMinutes;

  /// 주간 소모 칼로리 목표 — 하루 목표 × 7. 회원 앱과 같은 규칙이다.
  double get weeklyBurnKcal => dailyBurnKcal * 7;

  /// 유형의 주간 목표를 **그 유형의 단위**로.
  double weeklyGoalOf(ExerciseKind kind) => switch (kind) {
    ExerciseKind.cardio => weeklyCardioMinutes,
    ExerciseKind.strength => weeklyStrengthSets,
    ExerciseKind.stretching => weeklyStretchingMinutes,
  };
}

/// 회원이 목표를 정하지 않았을 때의 목표 한 벌.
const ExerciseBurnGoals kDefaultExerciseBurnGoals = ExerciseBurnGoals();
