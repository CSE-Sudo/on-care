import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/measure_update.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/domain/repositories/account_repository.dart';

/// Not wired by default (the app uses [DioAccountRepository] → the drift-backed
/// LocalApiInterceptor). Kept for unit tests / offline overrides.
class MockAccountRepository implements AccountRepository {
  MockAccountRepository({UserProfile profile = _demo}) : _profile = profile;

  static const UserProfile _demo = UserProfile(
    id: 'user-7d4e9a2c5f18',
    name: '김민수',
    email: 'minsu@oncare.com',
    phone: '010-1234-5678',
    birthDate: '1990-01-15',
    // 트레이너 앱의 김민수와 같은 사람이다 — 성별과 목표가 두 앱에서 같아야
    // 한다 (#1140).
    gender: 'male',
    goals: '혈압 관리 · 체중 감량',
    dailyCalories: 2000,
    dailySodiumMg: 2000,
    dailySugarG: 50,
    dailyCarbsG: 275,
    dailyProteinG: 100,
    dailyFatG: 55,
    // 데모 회원의 운동 목표는 권장값 그대로 둔다 — 화면은 이 값을 쓰지 않고
    // (#1139) 트레이너 앱이 읽는 자리라, 비워 두면 로스터에서 목표가 없다고
    // 읽힌다.
    //
    // 주간 소모는 **하루 목표 × 7** 이다(300 × 7). 500 은 하루 목표가
    // 500kcal 이던 시절에 주간 칸으로 옮겨 적힌 값이라, 운동 탭 도넛이 재는
    // 2,100kcal 과도 트레이너 화면의 회원 정보와도 어긋났다. (#1170)
    weeklyWorkoutGoal: 3,
    weeklyExerciseMinutesGoal: 150,
    weeklyBurnGoal: 2100,
  );

  UserProfile _profile;

  @override
  Future<UserProfile> fetchProfile() async => _profile;

  @override
  Future<void> deleteAccount() async {}

  @override
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
  }) async {
    _profile = _replaceProfile(
      birthDate: birthDate,
      gender: gender,
      // 온보딩은 첫 저장이라 '지움'이 없다 — 비운 칸은 손대지 않는다.
      heightCm: heightCm == null ? null : MeasureUpdate(heightCm),
      weightKg: weightKg == null ? null : MeasureUpdate(weightKg),
      goals: goals,
      dailyCalories: dailyCalories,
      dailySodiumMg: dailySodiumMg,
      dailySugarG: dailySugarG,
      dailyCarbsG: dailyCarbsG,
      dailyProteinG: dailyProteinG,
      dailyFatG: dailyFatG,
      dailyBurnKcal: dailyBurnKcal,
      weeklyCardioMinutes: weeklyCardioMinutes,
      weeklyStrengthSets: weeklyStrengthSets,
      weeklyFlexibilityMinutes: weeklyFlexibilityMinutes,
    );
    return _profile;
  }

  @override
  Future<UserProfile> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? birthDate,
    String? gender,
    MeasureUpdate? heightCm,
    MeasureUpdate? weightKg,
    String? goals,
  }) async {
    _profile = _replaceProfile(
      name: name,
      email: email,
      phone: phone,
      birthDate: birthDate,
      gender: gender,
      heightCm: heightCm,
      weightKg: weightKg,
      goals: goals,
    );
    return _profile;
  }

  /// 준 값만 갈아 끼우고 나머지는 그대로 둔다.
  ///
  /// **열 목표 칸을 하나도 빠뜨리지 않는다** — 예전에는 운동 유형별 목표
  /// 넷이 빠져 있어, 내 프로필을 저장하기만 해도 온보딩·MY 에서 정한 운동
  /// 목표가 조용히 사라졌다.
  UserProfile _replaceProfile({
    String? name,
    String? email,
    String? phone,
    String? birthDate,
    String? gender,
    MeasureUpdate? heightCm,
    MeasureUpdate? weightKg,
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
  }) => UserProfile(
    id: _profile.id,
    name: name ?? _profile.name,
    email: email ?? _profile.email,
    phone: phone ?? _profile.phone,
    birthDate: birthDate ?? _profile.birthDate,
    gender: gender ?? _profile.gender,
    // 인자를 주지 않으면 손대지 않고, 값이 null 이면 지운다(#1941).
    heightCm: heightCm == null
        ? _profile.heightCm
        : heightCm.value?.toDouble(),
    weightKg: weightKg == null
        ? _profile.weightKg
        : weightKg.value?.toDouble(),
    goals: goals ?? _profile.goals,
    dailyCalories: dailyCalories ?? _profile.dailyCalories,
    dailySodiumMg: dailySodiumMg ?? _profile.dailySodiumMg,
    dailySugarG: dailySugarG ?? _profile.dailySugarG,
    dailyCarbsG: dailyCarbsG ?? _profile.dailyCarbsG,
    dailyProteinG: dailyProteinG ?? _profile.dailyProteinG,
    dailyFatG: dailyFatG ?? _profile.dailyFatG,
    weeklyWorkoutGoal: _profile.weeklyWorkoutGoal,
    weeklyExerciseMinutesGoal: _profile.weeklyExerciseMinutesGoal,
    weeklyBurnGoal: _profile.weeklyBurnGoal,
    dailyBurnKcal: dailyBurnKcal ?? _profile.dailyBurnKcal,
    weeklyCardioMinutes: weeklyCardioMinutes ?? _profile.weeklyCardioMinutes,
    weeklyStrengthSets: weeklyStrengthSets ?? _profile.weeklyStrengthSets,
    weeklyFlexibilityMinutes:
        weeklyFlexibilityMinutes ?? _profile.weeklyFlexibilityMinutes,
  );

  @override
  Future<UserProfile> updateHealthGoals({
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
  }) async {
    _profile = UserProfile(
      id: _profile.id,
      name: _profile.name,
      email: _profile.email,
      phone: _profile.phone,
      birthDate: _profile.birthDate,
      gender: _profile.gender,
      heightCm: _profile.heightCm,
      weightKg: _profile.weightKg,
      // 관리 초점과 자유 입력 운동 목표도 이 화면에서 고친다(#1471).
      conditions: conditions ?? _profile.conditions,
      goals: goals ?? _profile.goals,
      dailyCalories: dailyCalories == null
          ? _profile.dailyCalories
          : dailyCalories.value,
      dailySodiumMg: dailySodiumMg == null
          ? _profile.dailySodiumMg
          : dailySodiumMg.value,
      dailySugarG: dailySugarG == null
          ? _profile.dailySugarG
          : dailySugarG.value,
      dailyCarbsG: dailyCarbsG == null
          ? _profile.dailyCarbsG
          : dailyCarbsG.value,
      dailyProteinG: dailyProteinG == null
          ? _profile.dailyProteinG
          : dailyProteinG.value,
      dailyFatG: dailyFatG == null ? _profile.dailyFatG : dailyFatG.value,
      weeklyWorkoutGoal: weeklyWorkoutGoal == null
          ? _profile.weeklyWorkoutGoal
          : weeklyWorkoutGoal.value,
      weeklyExerciseMinutesGoal: weeklyExerciseMinutesGoal == null
          ? _profile.weeklyExerciseMinutesGoal
          : weeklyExerciseMinutesGoal.value,
      weeklyBurnGoal: weeklyBurnGoal == null
          ? _profile.weeklyBurnGoal
          : weeklyBurnGoal.value,
      dailyBurnKcal: dailyBurnKcal == null
          ? _profile.dailyBurnKcal
          : dailyBurnKcal.value,
      weeklyCardioMinutes: weeklyCardioMinutes == null
          ? _profile.weeklyCardioMinutes
          : weeklyCardioMinutes.value,
      weeklyStrengthSets: weeklyStrengthSets == null
          ? _profile.weeklyStrengthSets
          : weeklyStrengthSets.value,
      weeklyFlexibilityMinutes: weeklyFlexibilityMinutes == null
          ? _profile.weeklyFlexibilityMinutes
          : weeklyFlexibilityMinutes.value,
    );
    return _profile;
  }
}
