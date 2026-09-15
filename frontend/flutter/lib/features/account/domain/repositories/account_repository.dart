import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';

abstract class AccountRepository {
  Future<UserProfile> fetchProfile();

  /// DELETE /users/me — withdraw the account. The server cascade-deletes
  /// the profile, diet/exercise, schedule, notifications and linked
  /// social accounts.
  Future<void> deleteAccount();

  /// PUT /users/me/health-goals — 건강 목표(식단 일일 6종 + 주간 운동 3종).
  ///
  /// 인자를 주지 않으면 그 목표는 손대지 않는다. [GoalUpdate.clear] 를 주면
  /// 목표를 해제한다 — 서버가 그 둘을 구분하므로 여기서도 구분해 보낸다.
  Future<UserProfile> updateHealthGoals({
    /// 건강 목표(`체중 감량, 혈압 관리`)과 자유 입력 운동 목표. 온보딩이
    /// 저장하던 두 값을 MY `건강 목표` 도 같은 열로 고친다(#1471).
    String? conditions,
    String? goals,
    GoalUpdate? dailyCalories,
    GoalUpdate? dailySodiumMg,
    GoalUpdate? dailySugarG,
    GoalUpdate? dailyCarbsG,
    GoalUpdate? dailyProteinG,
    GoalUpdate? dailyFatG,
    GoalUpdate? weeklyWorkoutGoal,
    GoalUpdate? weeklyExerciseMinutesGoal,
    GoalUpdate? weeklyBurnGoal,
    GoalUpdate? dailyBurnKcal,
    GoalUpdate? weeklyCardioMinutes,
    GoalUpdate? weeklyStrengthSets,
    GoalUpdate? weeklyFlexibilityMinutes,
  });

  /// POST /users/me/onboarding — first-run setup. All fields optional
  /// (partial save allowed); the backend marks the profile onboarded.
  ///
  /// 목표 열 칸은 [updateHealthGoals] 와 **같은 열**이다 — 온보딩이 채운
  /// 값을 MY 건강 목표가 그대로 이어 고친다. 여기서는 `GoalUpdate` 를 쓰지
  /// 않는다: 첫 저장이라 '해제할 목표' 가 없고, 비운 칸은 보내지 않는다.
  Future<UserProfile> submitOnboarding({
    String? birthDate,
    String? gender,
    num? heightCm,
    num? weightKg,
    String? conditions,
    String? goals,
    int? dailyCalories,
    int? dailySodiumMg,
    int? dailySugarG,
    int? dailyCarbsG,
    int? dailyProteinG,
    int? dailyFatG,
    int? dailyBurnKcal,
    int? weeklyCardioMinutes,
    int? weeklyStrengthSets,
    int? weeklyFlexibilityMinutes,
  });

  /// PUT /users/me — update basic profile (name/email/phone/birth).
  Future<UserProfile> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? birthDate,
    String? gender,
    num? heightCm,
    num? weightKg,
    String? goals,
  });
}
