import 'package:oncare/features/account/domain/entities/account_deletion_preview.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/measure_update.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';

abstract class AccountRepository {
  Future<UserProfile> fetchProfile();

  /// DELETE /users/me — withdraw the account. The server cascade-deletes
  /// the profile, diet/exercise, schedule, notifications and linked
  /// social accounts.
  /// 고른 탈퇴 사유를 함께 보낸다(#2019). 사유는 탈퇴를 막는 조건이 아니라
  /// 물어보는 자리라, 비어 있어도 탈퇴는 그대로 진행된다.
  Future<void> deleteAccount({List<String> reasons = const <String>[]});

  /// GET /users/me/deletion-preview — 탈퇴하면 사라지는 포인트·쿠폰과 취소되는
  /// 예약·상담 요청의 건수(#3006). 탈퇴 확인창이 이 숫자로 무엇을 잃는지 말한다.
  Future<AccountDeletionPreview> fetchDeletionPreview();

  /// PUT /users/me/health-goals — 건강 목표(식단 일일 6종 + 주간 운동 3종).
  ///
  /// 인자를 주지 않으면 그 목표는 손대지 않는다. [GoalUpdate.clear] 를 주면
  /// 목표를 해제한다 — 서버가 그 둘을 구분하므로 여기서도 구분해 보낸다.
  Future<UserProfile> updateHealthGoals({
    /// 건강 목표(`체중 감량, 혈압 관리`)과 자유 입력 운동 목표. 온보딩이
    /// 저장하던 두 값을 MY `건강 목표` 도 같은 열로 고친다(#1471).
    String? conditions,
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

  /// POST /users/me/onboarding/skip — 첫 설정 건너뛰기를 계정에 남긴다(#2855).
  ///
  /// 값은 아무것도 저장하지 않는다. 응답 프로필의 [UserProfile.onboardingSkipped]
  /// 가 참이 되고, 다음 로그인·세션 복구에서 첫 설정으로 다시 보내지 않는다.
  Future<UserProfile> skipOnboarding();

  /// PUT /users/me — update basic profile (name/email/phone/birth).
  ///
  /// 키·몸무게는 [MeasureUpdate] 로 받는다 — 인자를 주지 않으면 손대지 않고,
  /// [MeasureUpdate.clear] 는 값을 지운다. `num?` 하나로는 그 둘을 표현할 수
  /// 없어 비운 칸이 "손대지 않음"으로 나갔다(#1941).
  Future<UserProfile> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? birthDate,
    String? gender,
    MeasureUpdate? heightCm,
    MeasureUpdate? weightKg,
  });
}
