import 'package:dio/dio.dart';

import 'package:oncare/features/account/domain/entities/account_deletion_preview.dart';
import 'package:oncare/features/account/domain/entities/account_reauth.dart';
import 'package:oncare/features/account/domain/entities/goal_update.dart';
import 'package:oncare/features/account/domain/entities/measure_update.dart';
import 'package:oncare/features/account/domain/entities/profile_update_rejected.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/domain/repositories/account_repository.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart'
    show ReissuedTokens;

class DioAccountRepository implements AccountRepository {
  DioAccountRepository(this._dio);
  final Dio _dio;

  @override
  Future<UserProfile> fetchProfile() async {
    final res = await _dio.get<Map<String, Object?>>('/users/me/profile');
    return UserProfile.fromJson(res.data!);
  }

  @override
  Future<void> deleteAccount({
    List<String> reasons = const <String>[],
    AccountReauth? reauth,
  }) async {
    try {
      await _dio.delete<Map<String, Object?>>(
        '/users/me',
        data: <String, Object?>{'reasons': reasons, ...?reauth?.toJson()},
      );
    } on DioException catch (e) {
      // 본인 확인 거절(400)은 이유를 실어 올린다(#3039) — 화면이 창 안에서 다시
      // 입력하게 한다. 401 이 아니므로 세션은 그대로다.
      final AccountReauthRejected? rejected =
          AccountReauthRejected.fromResponse(
            e.response?.statusCode,
            e.response?.data,
          );
      if (rejected != null) throw rejected;
      rethrow;
    }
  }

  @override
  Future<AccountDeletionPreview> fetchDeletionPreview() async {
    final res = await _dio.get<Map<String, Object?>>(
      '/users/me/deletion-preview',
    );
    return AccountDeletionPreview.fromJson(res.data!);
  }

  @override
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
  Future<UserProfile> skipOnboarding() async {
    final res = await _dio.post<Map<String, Object?>>(
      '/users/me/onboarding/skip',
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
    AccountReauth? reauth,
    void Function(ReissuedTokens tokens)? onTokensReissued,
  }) async {
    final Response<Map<String, Object?>> res;
    try {
      res = await _dio.put<Map<String, Object?>>(
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
          // 이메일을 바꿀 때의 본인 확인(#3039).
          ...?reauth?.toJson(),
        },
      );
    } on DioException catch (e) {
      final AccountReauthRejected? reauthRejected =
          AccountReauthRejected.fromResponse(
            e.response?.statusCode,
            e.response?.data,
          );
      if (reauthRejected != null) throw reauthRejected;
      // 이메일 중복(409)·연락처 비움(422)은 이유를 실어 올린다(#2639). 데모의
      // 로컬 목업 API 도 오류를 같은 예외로 돌려준다(#2743).
      final ProfileUpdateRejected? rejected =
          ProfileUpdateRejected.fromResponse(
            e.response?.statusCode,
            e.response?.data,
          );
      if (rejected != null) throw rejected;
      rethrow;
    }
    // 이메일을 바꾸면 서버가 새 토큰 한 쌍을 싣는다(#3039). 다른 저장은 null 이다.
    final ReissuedTokens? tokens = ReissuedTokens.fromJson(res.data);
    if (tokens != null) onTokensReissued?.call(tokens);
    return UserProfile.fromJson(res.data!);
  }

  @override
  Future<UserProfile> updateHealthGoals({
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
  }) async {
    final res = await _dio.put<Map<String, Object?>>(
      '/users/me/health-goals',
      // 키를 **넣되 값이 null** 이면 서버가 목표를 해제한다. `?value` 로
      // 통째로 빼면 해제가 '손대지 않음'이 되어 지운 목표가 되살아난다.
      data: <String, Object?>{
        // 문자열 둘은 비워서 저장할 수 있다 — 빈 문자열이 '적지 않음' 이다.
        'conditions': ?conditions,
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
