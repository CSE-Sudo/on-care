import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare_ui/oncare_ui.dart'
    show
        kGoalDefaultDailyBurnKcal,
        kGoalDefaultWeeklyCardioMinutes,
        kGoalDefaultWeeklyFlexibilityMinutes,
        kGoalDefaultWeeklyStrengthSets;

/// 운동 유형마다 **재는 단위가 다르다**는 사실을 그대로 인정하는 모델.
///
/// 예전 `운동 현황` 그래프는 모든 유형을 `분` 으로 쌓았다. 유산소는 시간이
/// 곧 운동량이지만, 근력은 그렇지 않다 — 같은 40분이라도 12세트를 한 날과
/// 6세트를 하고 절반을 쉰 날이 같은 막대가 됐다. 그래서 여기서는
///
///   * 유산소  → **분**
///   * 근력    → **세트**
///   * 스트레칭  → **분**
///
/// 을 각자의 단위로 들고 다니고, 화면의 숫자·목표는 언제나 그 단위로 보여 준다.
/// 세 유형을 **한 축에서** 비교해야 할 때 쓰는 값은 [ExerciseDayLoad.calories]
/// 하나다 — 트레이너 앱도 같은 축을 쓰므로, 같은 회원의 같은 한 주가 두 앱에서
/// 같은 그림으로 읽힌다. (#1276)
enum ExerciseLoadKind { cardio, strength, flexibility }

/// 근력 1세트가 차지하는 **벽시계 시간**(세트 + 휴식). 세트 수를 따로 기록하지
/// 않는 옛 기록(분만 있는 기록)을 세트로 되돌릴 때만 쓰는 다리다.
const double kStrengthMinutesPerSetWithRest = 3.0;

/// 세트를 **모르는** 옛 기록에서만 쓰는 환산. 45분 ≈ 15세트.
///
/// 기록이 세트를 들고 있으면 언제나 그 값을 쓴다 — 분에서 되짚어 계산하면
/// 트레이너가 보낸 프로그램의 세트 수와 화면의 수가 어긋난다.
int setsFromStrengthMinutes(double minutes) =>
    (minutes / kStrengthMinutesPerSetWithRest).round();

/// 유형별 목표. **주간 목표가 원본**이고, 하루 목표는 그 유형을 주 몇 번 하는지로
/// 나눈 값이다 — 근력은 매일 하는 운동이 아니라서 주간 목표를 7 로 나누면
/// (2.3세트) 아무 뜻이 없는 숫자가 된다.
class ExerciseLoadGoals {
  const ExerciseLoadGoals({
    // PT 를 받는 회원이 수업이 없는 날에도 **매일** 닿을 수 있는 선으로 잡는다.
    // 500kcal(MY 기본값)은 하루 한 시간 넘게 움직여야 나오는 수라, 꾸준히 한
    // 주에도 목표선을 한 번도 못 넘어 그래프가 늘 '실패' 로만 읽혔다.
    //
    // 값은 공용 패키지 `oncare_ui` 의 `kGoalDefault…` 한 곳에 있다(#2906).
    this.dailyBurnKcal = kGoalDefaultDailyBurnKcal * 1.0,
    // WHO: 주 150분 중강도 유산소
    this.weeklyCardioMinutes = kGoalDefaultWeeklyCardioMinutes * 1.0,
    // 하루 3세트 × 7일
    this.weeklyStrengthSets = kGoalDefaultWeeklyStrengthSets * 1.0,
    this.weeklyFlexibilityMinutes = kGoalDefaultWeeklyFlexibilityMinutes * 1.0,
    this.cardioDaysPerWeek = 5,
    this.strengthDaysPerWeek = 7,
    this.flexibilityDaysPerWeek = 6,
  });

  /// 하루 소모 칼로리 목표. 오늘 도넛이 이 값을 채운다.
  final double dailyBurnKcal;

  /// 주간 소모 칼로리 목표 — 하루 목표 × 7.
  double get weeklyBurnKcal => dailyBurnKcal * 7;

  final double weeklyCardioMinutes;
  final double weeklyStrengthSets;
  final double weeklyFlexibilityMinutes;
  final int cardioDaysPerWeek;
  final int strengthDaysPerWeek;
  final int flexibilityDaysPerWeek;

  double get dailyCardioMinutes => weeklyCardioMinutes / cardioDaysPerWeek;
  double get dailyStrengthSets => weeklyStrengthSets / strengthDaysPerWeek;
  double get dailyFlexibilityMinutes =>
      weeklyFlexibilityMinutes / flexibilityDaysPerWeek;

  double goalOf(ExerciseLoadKind kind) => switch (kind) {
    ExerciseLoadKind.cardio => dailyCardioMinutes,
    ExerciseLoadKind.strength => dailyStrengthSets,
    ExerciseLoadKind.flexibility => dailyFlexibilityMinutes,
  };

  double weeklyGoalOf(ExerciseLoadKind kind) => switch (kind) {
    ExerciseLoadKind.cardio => weeklyCardioMinutes,
    ExerciseLoadKind.strength => weeklyStrengthSets,
    ExerciseLoadKind.flexibility => weeklyFlexibilityMinutes,
  };
}

const ExerciseLoadGoals kDefaultExerciseLoadGoals = ExerciseLoadGoals();

/// 하루치 운동을 **유형별 원래 단위**로 담는다.
class ExerciseDayLoad {
  const ExerciseDayLoad({
    required this.date,
    this.cardioMinutes = 0,
    this.strengthSets = 0,
    this.flexibilityMinutes = 0,
    this.otherMinutes = 0,
    this.calories = 0,
  });

  /// 유형별 `분` 만 있는 기록에서 만든다. 근력의 분은 세트로 되돌린다.
  factory ExerciseDayLoad.fromMinutes({
    required DateTime date,
    required double cardio,
    required double strength,
    required double flexibility,
    double other = 0,
    double calories = 0,
    double? sets,
  }) => ExerciseDayLoad(
    date: date,
    cardioMinutes: cardio,
    // 기록한 세트가 있으면 그 값이다. 없을 때만 분에서 환산한다.
    strengthSets: (sets ?? setsFromStrengthMinutes(strength)).round(),
    flexibilityMinutes: flexibility,
    otherMinutes: other,
    calories: calories,
  );

  final DateTime date;
  final double cardioMinutes;
  final int strengthSets;
  final double flexibilityMinutes;

  /// 목표가 없는 나머지 운동(기타). **활동량 점수에 넣지 않는다** — 그래프에
  /// 그리지 않기로 한 값이 숫자에만 섞여 들면 머리의 합계와 막대가 어긋난다.
  /// 화면에는 분 수만 따로 적는다.
  final double otherMinutes;

  /// 그날 태운 칼로리. 유형별 단위가 제각각인 운동을 **하나의 축**으로 보는
  /// 자리다 — 도넛과 막대는 이 값을 그린다.
  final double calories;

  bool get isActive =>
      cardioMinutes > 0 ||
      strengthSets > 0 ||
      flexibilityMinutes > 0 ||
      otherMinutes > 0 ||
      calories > 0;

  double valueOf(ExerciseLoadKind kind) => switch (kind) {
    ExerciseLoadKind.cardio => cardioMinutes,
    ExerciseLoadKind.strength => strengthSets.toDouble(),
    ExerciseLoadKind.flexibility => flexibilityMinutes,
  };
}

/// 주간 기록 → 요일별 [ExerciseDayLoad]. [monday] 는 그 주의 월요일.
///
/// 유형별 시리즈가 없는(옛) 페이로드는 전부 유산소로 본다 — 없는 근력 세트를
/// 지어내는 것보다 낫다.
List<ExerciseDayLoad> dayLoadsOfWeek(ExerciseWeek week, DateTime monday) {
  final int n = week.dailyMinutes.length;
  final bool hasBreakdown =
      n > 0 &&
      week.cardioMinutes.length == n &&
      week.strengthMinutes.length == n &&
      week.stretchingMinutes.length == n;
  return <ExerciseDayLoad>[
    for (int i = 0; i < n; i++)
      ExerciseDayLoad.fromMinutes(
        date: DateTime(monday.year, monday.month, monday.day + i),
        cardio: hasBreakdown ? week.cardioMinutes[i] : week.dailyMinutes[i],
        strength: hasBreakdown ? week.strengthMinutes[i] : 0,
        flexibility: hasBreakdown ? week.stretchingMinutes[i] : 0,
        other: i < week.otherMinutes.length ? week.otherMinutes[i] : 0,
        calories: i < week.dailyCalories.length ? week.dailyCalories[i] : 0,
        sets: i < week.strengthSets.length ? week.strengthSets[i] : null,
      ),
  ];
}
