/// GET /users/me/profile — the consolidated profile the settings modals
/// edit (내 프로필 + 건강 목표).
class UserProfile {
  static const int defaultDailyCalories = 2000;
  static const int defaultDailySodiumMg = 2000;
  static const int defaultDailySugarG = 50;
  static const int defaultDailyCarbsG = 275;
  static const int defaultDailyProteinG = 100;
  static const int defaultDailyFatG = 55;

  /// [focusChangedBy] 값 — 건강 목표를 마지막으로 바꾼 사람(#1832).
  static const String focusChangedByMember = 'member';
  static const String focusChangedByTrainer = 'trainer';

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    this.birthDate = '',
    this.gender = '',
    this.heightCm,
    this.weightKg,
    this.conditions = '',
    this.goals = '',
    this.dailyCalories,
    this.dailySodiumMg,
    this.dailySugarG,
    this.dailyCarbsG,
    this.dailyProteinG,
    this.dailyFatG,
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

  /// 자유 입력 운동 목표. 예전에는 내 프로필 수정에 있던 칸이다(#1471).
  final String goals;

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
  int get effectiveDailyProteinG => dailyProteinG ?? defaultDailyProteinG;
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
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
    phone: (json['phone'] as String?) ?? '',
    birthDate: (json['birth_date'] as String?) ?? '',
    gender: (json['gender'] as String?) ?? '',
    heightCm: (json['height_cm'] as num?)?.toDouble(),
    weightKg: (json['weight_kg'] as num?)?.toDouble(),
    conditions: (json['conditions'] as String?) ?? '',
    goals: (json['goals'] as String?) ?? '',
    dailyCalories: (json['daily_calories'] as num?)?.toInt(),
    dailySodiumMg: (json['daily_sodium_mg'] as num?)?.toInt(),
    dailySugarG: (json['daily_sugar_g'] as num?)?.toInt(),
    dailyCarbsG: (json['daily_carbs_g'] as num?)?.toInt(),
    dailyProteinG: (json['daily_protein_g'] as num?)?.toInt(),
    dailyFatG: (json['daily_fat_g'] as num?)?.toInt(),
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
