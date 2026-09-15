import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/features/exercise/data/repositories/dio_streak_shield_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_streak_shield_repository.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/domain/repositories/streak_shield_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';

/// 연속 기록 보호권 저장소. (#1788)
///
/// 데모 모드는 목업 운동 저장소와 같은 기록·같은 보호권 원장을 본다 — 운동
/// 현황에서 쓴 보호권이 연속 일수와 내 혜택에 한 번에 보인다.
final streakShieldRepositoryProvider = Provider<StreakShieldRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return MockStreakShieldRepository(
      book: ref.watch(demoStreakShieldBookProvider),
      exercise: ref.watch(exerciseRepositoryProvider),
    );
  }
  return DioStreakShieldRepository(ref.watch(dioProvider));
}, name: 'streakShieldRepository');

/// 내 혜택의 보호권 구역 — 보유 수와 보호한 날. 교환·사용 뒤 다시 읽는다.
final myStreakShieldsProvider = FutureProvider.autoDispose<StreakShields>(
  (ref) => ref.watch(streakShieldRepositoryProvider).fetch(),
  name: 'myStreakShields',
);
