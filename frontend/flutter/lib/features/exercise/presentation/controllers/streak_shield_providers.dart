import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/data/repositories/dio_streak_shield_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_streak_shield_repository.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/domain/repositories/streak_shield_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';

/// 연속 기록 보호권 저장소. (#1788)
///
/// 데모 모드는 목업 운동 저장소·목업 식단과 같은 기록, 같은 보호권 원장을 본다 —
/// 교환한 보호권과 보호한 날이 내 혜택에 한 번에 보인다.
final streakShieldRepositoryProvider = Provider<StreakShieldRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return MockStreakShieldRepository(
      book: ref.watch(demoStreakShieldBookProvider),
      exercise: ref.watch(exerciseRepositoryProvider),
      // 기록 연속은 식단도 센다(#1788) — 데모의 식단은 로컬 목업 API 에 있다.
      diet: ref.watch(dietRepositoryProvider),
    );
  }
  return DioStreakShieldRepository(ref.watch(dioProvider));
}, name: 'streakShieldRepository');

/// 내 혜택의 보호권 구역 — 보유 수와 보호한 날. 교환·사용 뒤 다시 읽는다.
final myStreakShieldsProvider = FutureProvider.autoDispose<StreakShields>(
  (ref) => ref.watch(streakShieldRepositoryProvider).fetch(),
  name: 'myStreakShields',
);
