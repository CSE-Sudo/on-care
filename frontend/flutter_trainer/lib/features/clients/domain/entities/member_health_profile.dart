import 'package:oncare_trainer/features/clients/domain/diet_analysis_rules.dart'
    show pyRound;

class MemberHealthProfile {
  /// [focusChangedBy] 값 — 건강 목표를 마지막으로 바꾼 사람(#1832).
  static const String focusChangedByMember = 'member';
  static const String focusChangedByTrainer = 'trainer';

  const MemberHealthProfile({
    required this.memberId,
    required this.memberName,
    this.heightCm,
    this.weightKg,
    this.gender = '',
    this.conditions = '',
    this.dailyCalories,
    this.dailySodiumMg,
    this.dailySugarG,
    this.dailyCarbsG,
    this.dailyProteinG,
    this.dailyFatG,
    this.serverEffectiveDailyProteinG,
    this.dailyBurnKcal,
    this.weeklyCardioMinutes,
    this.weeklyStrengthSets,
    this.weeklyFlexibilityMinutes,
    this.weeklyWorkoutGoal,
    this.weeklyExerciseMinutesGoal,
    this.weeklyBurnGoal,
    this.focusChangedBy,
    this.focusChangedAt,
    this.notesChangedBy,
    this.notesChangedAt,
  });

  final String memberId;
  final String memberName;
  final double? heightCm;
  final double? weightKg;
  final String gender;
  final String conditions;
  final int? dailyCalories;
  final int? dailySodiumMg;

  /// 회원 앱 마이페이지가 관리하는 일일 식단 목표. 트레이너 화면도 같은 값을
  /// 읽고 저장한다 — 한쪽에서 고친 목표가 다른 쪽에서 옛 값으로 남지 않게
  /// (#1449).
  final int? dailySugarG;
  final int? dailyCarbsG;
  final int? dailyProteinG;
  final int? dailyFatG;

  /// 서버가 계산한 실효 단백질 목표(`effective_daily_protein_g`, #2898). 옛
  /// 응답·데모면 null 이고, 그때는 [effectiveDailyProteinG] 가 같은 규칙을 계산한다.
  final int? serverEffectiveDailyProteinG;

  /// 단백질 목표 — 개인 목표 → 서버 실효값 → 체중 × 1.2g → 60g. 회원 식단
  /// 분석·조언과 같은 분모다(#2898). 회원 앱 `UserProfile.effectiveDailyProteinG`
  /// 와 같은 규칙이다.
  int get effectiveDailyProteinG =>
      dailyProteinG ??
      serverEffectiveDailyProteinG ??
      proteinTargetFromWeight(weightKg) ??
      defaultDailyProteinG;

  /// 체중도 개인 목표도 없을 때의 단백질 목표 — 서버 `DEFAULT_PROTEIN_G`.
  static const int defaultDailyProteinG = 60;

  /// 체중 1kg 당 단백질 목표(g) — 서버 `PROTEIN_G_PER_KG`.
  static const double proteinGPerKg = 1.2;

  /// 체중 기반 단백질 목표. 체중이 없으면 null.
  static int? proteinTargetFromWeight(double? weightKg) =>
      weightKg != null && weightKg > 0
      ? pyRound(weightKg * proteinGPerKg)
      : null;

  /// 운동 탭이 실제로 견주는 목표(#1139). 아래 `weekly*Goal` 셋은 그 이전
  /// 세대의 값이라 트레이너 편집 폼에서는 다루지 않는다.
  final int? dailyBurnKcal;
  final int? weeklyCardioMinutes;
  final int? weeklyStrengthSets;
  final int? weeklyFlexibilityMinutes;

  final int? weeklyWorkoutGoal;
  final int? weeklyExerciseMinutesGoal;
  final int? weeklyBurnGoal;

  /// 건강 목표를 마지막으로 바꾼 사람 — 회원(`member`)인지 트레이너(`trainer`)인지.
  /// 회원과 트레이너가 같은 칸을 고치므로 승인 대신 기록을 보여 준다(#1832).
  final String? focusChangedBy;

  /// 건강 목표를 마지막으로 바꾼 시각(로컬 시각).
  final DateTime? focusChangedAt;

  /// 건강상태·주의사항을 마지막으로 바꾼 사람 — `member` 또는 `trainer`(#2942).
  /// 목표 칩 기록과 따로다. 바꾼 적이 없으면 null.
  final String? notesChangedBy;

  /// 건강상태·주의사항을 마지막으로 바꾼 시각(로컬 시각).
  final DateTime? notesChangedAt;

  factory MemberHealthProfile.fromJson(Map<String, Object?> json) =>
      MemberHealthProfile(
        memberId: json['member_id'] as String? ?? '',
        memberName: json['member_name'] as String? ?? '',
        heightCm: (json['height_cm'] as num?)?.toDouble(),
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        gender: json['gender'] as String? ?? '',
        conditions: json['conditions'] as String? ?? '',
        dailyCalories: (json['daily_calories'] as num?)?.toInt(),
        dailySodiumMg: (json['daily_sodium_mg'] as num?)?.toInt(),
        dailySugarG: (json['daily_sugar_g'] as num?)?.toInt(),
        dailyCarbsG: (json['daily_carbs_g'] as num?)?.toInt(),
        dailyProteinG: (json['daily_protein_g'] as num?)?.toInt(),
        dailyFatG: (json['daily_fat_g'] as num?)?.toInt(),
        serverEffectiveDailyProteinG:
            switch (json['effective_daily_protein_g']) {
              final num v when v > 0 => v.toInt(),
              _ => null,
            },
        dailyBurnKcal: (json['daily_burn_kcal'] as num?)?.toInt(),
        weeklyCardioMinutes: (json['weekly_cardio_minutes'] as num?)?.toInt(),
        weeklyStrengthSets: (json['weekly_strength_sets'] as num?)?.toInt(),
        weeklyFlexibilityMinutes: (json['weekly_flexibility_minutes'] as num?)
            ?.toInt(),
        weeklyWorkoutGoal: (json['weekly_workout_goal'] as num?)?.toInt(),
        weeklyExerciseMinutesGoal:
            (json['weekly_exercise_minutes_goal'] as num?)?.toInt(),
        weeklyBurnGoal: (json['weekly_burn_goal'] as num?)?.toInt(),
        focusChangedBy: switch (json['focus_changed_by']) {
          final String by when by.isNotEmpty => by,
          _ => null,
        },
        focusChangedAt: switch (json['focus_changed_at']) {
          // UTC 순간 그대로 — 표시할 때 KST 날짜로 바꾼다(#2893).
          final String at => DateTime.tryParse(at),
          _ => null,
        },
        notesChangedBy: switch (json['notes_changed_by']) {
          final String by when by.isNotEmpty => by,
          _ => null,
        },
        notesChangedAt: switch (json['notes_changed_at']) {
          final String at => DateTime.tryParse(at)?.toLocal(),
          _ => null,
        },
      );
}
