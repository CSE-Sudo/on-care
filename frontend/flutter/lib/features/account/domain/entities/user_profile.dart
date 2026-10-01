/// GET /users/me/profile — the consolidated profile the settings modals
/// edit (내 프로필 + 건강 목표).
class UserProfile {
  static const int defaultDailyCalories = 2000;
  static const int defaultDailySodiumMg = 2000;
  static const int defaultDailySugarG = 50;
  static const int defaultDailyCarbsG = 275;

  /// 체중도 개인 목표도 없을 때의 단백질 목표 — 서버
  /// `diet_coach_inputs.DEFAULT_PROTEIN_G` 와 같다(#2898). 예전 100g 은 식단
  /// 분석 기준(60g)과 달라, 카드와 분석이 같은 날을 다르게 판단했다.
  static const int defaultDailyProteinG = 60;

  /// 체중 1kg 당 단백질 목표(g) — 서버 `PROTEIN_G_PER_KG` 와 같다(#2898).
  static const double proteinGPerKg = 1.2;
  static const int defaultDailyFatG = 55;

  /// [focusChangedBy] 값 — 건강 목표를 마지막으로 바꾼 사람(#1832).
  static const String focusChangedByMember = 'member';
  static const String focusChangedByTrainer = 'trainer';

  const UserProfile({
    required this.id,
    this.onboarded = false,
    required this.name,
    required this.email,
    this.phone = '',
    this.birthDate = '',
    this.gender = '',
    this.heightCm,
    this.weightKg,
    this.conditions = '',
    this.dailyCalories,
    this.dailySodiumMg,
    this.dailySugarG,
    this.dailyCarbsG,
    this.dailyProteinG,
    this.dailyFatG,
    this.serverEffectiveDailyProteinG,
    this.weeklyWorkoutGoal,
    this.weeklyExerciseMinutesGoal,
    this.weeklyBurnGoal,
    this.dailyBurnKcal,
    this.weeklyCardioMinutes,
    this.weeklyStrengthSets,
    this.weeklyFlexibilityMinutes,
    this.focusChangedBy,
    this.focusChangedAt,
  });

  final String id;

  /// 첫 설정(온보딩)을 끝냈는가. 서버가 첫 저장 때 참으로 표시한다(#1927).
  /// 기기가 아니라 계정에 붙는 값이라, 기기를 바꿔도 다시 묻지 않는다.
  final bool onboarded;

  final String name;
  final String email;
  final String phone;
  final String birthDate;
  final String gender;
  final double? heightCm;
  final double? weightKg;

  /// 건강 목표(`체중 감량, 혈압 관리`). 진단·치료 중인 질환을 단정하는
  /// 값이 아니라 **어디에 초점을 둘지**다(#1471). 온보딩과 MY `건강 목표` 가
  /// 같은 값을 읽고 고친다.
  final String conditions;

  // 식단 일일 목표 — 홈 영양 현황의 목표치와 같은 값을 공유한다.
  final int? dailyCalories;
  final int? dailySodiumMg;
  final int? dailySugarG;
  final int? dailyCarbsG;
  final int? dailyProteinG;
  final int? dailyFatG;

  int get effectiveDailyCalories => dailyCalories ?? defaultDailyCalories;
  int get effectiveDailySodiumMg => dailySodiumMg ?? defaultDailySodiumMg;
  int get effectiveDailySugarG => dailySugarG ?? defaultDailySugarG;
  int get effectiveDailyCarbsG => dailyCarbsG ?? defaultDailyCarbsG;

  /// 서버가 계산해 준 실효 단백질 목표(`effective_daily_protein_g`, #2898).
  /// 옛 응답·목업이면 null 이고, 그때는 [effectiveDailyProteinG] 가 같은 규칙을
  /// 앱에서 계산한다.
  final int? serverEffectiveDailyProteinG;

  /// 단백질 목표 — 개인 목표 → 서버 실효값 → 체중 × 1.2g → 60g. 식단 분석·조언과
  /// 같은 분모다(#2898).
  int get effectiveDailyProteinG =>
      dailyProteinG ??
      serverEffectiveDailyProteinG ??
      proteinTargetFromWeight(weightKg) ??
      defaultDailyProteinG;

  /// 체중 기반 단백질 목표. 체중이 없으면 null.
  static int? proteinTargetFromWeight(double? weightKg) =>
      weightKg != null && weightKg > 0
      ? _pyRound(weightKg * proteinGPerKg)
      : null;

  /// 파이썬 `round()` 와 같은 반올림(0.5 는 짝수 쪽) — 서버와 같은 수를 낸다.
  static int _pyRound(double x) {
    final int f = x.floor();
    final double diff = x - f;
    if (diff > 0.5) return f + 1;
    if (diff < 0.5) return f;
    return f.isEven ? f : f + 1;
  }

  int get effectiveDailyFatG => dailyFatG ?? defaultDailyFatG;

  // 주간 운동 목표 — 트레이너 앱이 고객 목표로 읽는 값이다. 회원 화면은 아래
  // 유형별 목표를 쓴다 (#1139).
  final int? weeklyWorkoutGoal; // 횟수
  final int? weeklyExerciseMinutesGoal; // 분
  final int? weeklyBurnGoal; // kcal

  // 기본값·`effective…` 는 두지 않는다 (#1139). 회원 화면이 견주는 목표는 아래
  // 유형별 값이고, 이 셋은 트레이너 앱이 읽는 값이라 회원 앱에서 기본값을
  // 씌우면 "회원이 정한 적 없는 목표" 가 있는 것처럼 보인다.

  // 운동 탭이 실제로 견주는 목표 (#1139). 소모는 **하루**, 유형별은 **한 주**다
  // — 근력을 7 로 나누면 "2.3세트" 라는 뜻 없는 수가 된다.
  final int? dailyBurnKcal;
  final int? weeklyCardioMinutes;
  final int? weeklyStrengthSets;
  final int? weeklyFlexibilityMinutes;

  /// 건강 목표를 마지막으로 바꾼 사람 — [focusChangedByMember] 또는
  /// [focusChangedByTrainer]. 회원과 담당 트레이너가 같은 칸을 고치므로, 승인 대신
  /// 누가 언제 바꿨는지를 보여 준다(#1832). 바꾼 적이 없으면 null.
  final String? focusChangedBy;

  /// 건강 목표를 마지막으로 바꾼 시각(로컬 시각). 바꾼 적이 없으면 null.
  final DateTime? focusChangedAt;

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
    onboarded: (json['onboarded'] as bool?) ?? false,
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    phone: (json['phone'] as String?) ?? '',
    birthDate: (json['birth_date'] as String?) ?? '',
    gender: (json['gender'] as String?) ?? '',
    heightCm: (json['height_cm'] as num?)?.toDouble(),
    weightKg: (json['weight_kg'] as num?)?.toDouble(),
    conditions: (json['conditions'] as String?) ?? '',
    dailyCalories: (json['daily_calories'] as num?)?.toInt(),
    dailySodiumMg: (json['daily_sodium_mg'] as num?)?.toInt(),
    dailySugarG: (json['daily_sugar_g'] as num?)?.toInt(),
    dailyCarbsG: (json['daily_carbs_g'] as num?)?.toInt(),
    dailyProteinG: (json['daily_protein_g'] as num?)?.toInt(),
    dailyFatG: (json['daily_fat_g'] as num?)?.toInt(),
    serverEffectiveDailyProteinG: switch (json['effective_daily_protein_g']) {
      final num v when v > 0 => v.toInt(),
      _ => null,
    },
    weeklyWorkoutGoal: (json['weekly_workout_goal'] as num?)?.toInt(),
    weeklyExerciseMinutesGoal: (json['weekly_exercise_minutes_goal'] as num?)
        ?.toInt(),
    weeklyBurnGoal: (json['weekly_burn_goal'] as num?)?.toInt(),
    dailyBurnKcal: (json['daily_burn_kcal'] as num?)?.toInt(),
    weeklyCardioMinutes: (json['weekly_cardio_minutes'] as num?)?.toInt(),
    weeklyStrengthSets: (json['weekly_strength_sets'] as num?)?.toInt(),
    weeklyFlexibilityMinutes: (json['weekly_flexibility_minutes'] as num?)
        ?.toInt(),
    focusChangedBy: switch (json['focus_changed_by']) {
      final String by when by.isNotEmpty => by,
      _ => null,
    },
    focusChangedAt: switch (json['focus_changed_at']) {
      final String at => DateTime.tryParse(at)?.toLocal(),
      _ => null,
    },
  );
}
