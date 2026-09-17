import 'package:dio/dio.dart';

import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/measure_update.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/domain/repositories/account_repository.dart';

class DioAccountRepository implements AccountRepository {
  DioAccountRepository(this._dio);
  final Dio _dio;

  @override
  Future<UserProfile> fetchProfile() async {
    final res = await _dio.get<Map<String, Object?>>('/users/me/profile');
    return UserProfile.fromJson(res.data!);
  }

  @override
  Future<void> deleteAccount() async {
    await _dio.delete<Map<String, Object?>>('/users/me');
  }

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
    final res = await _dio.post<Map<String, Object?>>(
      '/users/me/onboarding',
      // 여기서는 `?value` 로 빈 값을 통째로 뺀다 — 첫 저장이라 '목표 해제'
      // 라는 뜻이 없고, 비운 칸은 손대지 않은 칸이다.
      data: <String, Object?>{
        'birth_date': ?birthDate,
        'gender': ?gender,
        'height_cm': ?heightCm,
        'weight_kg': ?weightKg,
        'conditions': ?conditions,
        'goals': ?goals,
        'daily_calories': ?dailyCalories,
        'daily_sodium_mg': ?dailySodiumMg,
        'daily_sugar_g': ?dailySugarG,
        'daily_carbs_g': ?dailyCarbsG,
        'daily_protein_g': ?dailyProteinG,
        'daily_fat_g': ?dailyFatG,
        'daily_burn_kcal': ?dailyBurnKcal,
        'weekly_cardio_minutes': ?weeklyCardioMinutes,
        'weekly_strength_sets': ?weeklyStrengthSets,
        'weekly_flexibility_minutes': ?weeklyFlexibilityMinutes,
      },
    );
    return UserProfile.fromJson(res.data!);
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
    final res = await _dio.put<Map<String, Object?>>(
      '/users/me',
      data: <String, Object?>{
        'name': ?name,
        'email': ?email,
        'phone': ?phone,
        'birth_date': ?birthDate,
        'gender': ?gender,
        // 키를 **넣되 값이 null** 이면 서버가 값을 지운다. `?value` 로 통째로
        // 빼면 지움이 '손대지 않음'이 되어 비운 값이 되살아난다(#1941).
        if (heightCm != null) 'height_cm': heightCm.value,
        if (weightKg != null) 'weight_kg': weightKg.value,
        'goals': ?goals,
      },
    );
    return UserProfile.fromJson(res.data!);
  }

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
    final res = await _dio.put<Map<String, Object?>>(
      '/users/me/health-goals',
      // 키를 **넣되 값이 null** 이면 서버가 목표를 해제한다. `?value` 로
      // 통째로 빼면 해제가 '손대지 않음'이 되어 지운 목표가 되살아난다.
      data: <String, Object?>{
        // 문자열 둘은 비워서 저장할 수 있다 — 빈 문자열이 '적지 않음' 이다.
        'conditions': ?conditions,
        'goals': ?goals,
        if (dailyCalories != null) 'daily_calories': dailyCalories.value,
        if (dailySodiumMg != null) 'daily_sodium_mg': dailySodiumMg.value,
        if (dailySugarG != null) 'daily_sugar_g': dailySugarG.value,
        if (dailyCarbsG != null) 'daily_carbs_g': dailyCarbsG.value,
        if (dailyProteinG != null) 'daily_protein_g': dailyProteinG.value,
        if (dailyFatG != null) 'daily_fat_g': dailyFatG.value,
        if (weeklyWorkoutGoal != null)
          'weekly_workout_goal': weeklyWorkoutGoal.value,
        if (weeklyExerciseMinutesGoal != null)
          'weekly_exercise_minutes_goal': weeklyExerciseMinutesGoal.value,
        if (weeklyBurnGoal != null) 'weekly_burn_goal': weeklyBurnGoal.value,
        if (dailyBurnKcal != null) 'daily_burn_kcal': dailyBurnKcal.value,
        if (weeklyCardioMinutes != null)
          'weekly_cardio_minutes': weeklyCardioMinutes.value,
        if (weeklyStrengthSets != null)
          'weekly_strength_sets': weeklyStrengthSets.value,
        if (weeklyFlexibilityMinutes != null)
          'weekly_flexibility_minutes': weeklyFlexibilityMinutes.value,
      },
    );
    return UserProfile.fromJson(res.data!);
  }
}
