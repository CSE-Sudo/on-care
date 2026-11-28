import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/demo_trainer_sync_repository.dart';
import 'package:oncare/features/my_health/data/repositories/dio_my_health_repository.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/data/repositories/trainer_sync_repository.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/domain/repositories/my_health_repository.dart';

final myHealthRepositoryProvider = Provider<MyHealthRepository>((ref) {
  // 실모드(USE_MOCK_API=false)에서는 백엔드 /users/me/health 로 실제 프로필·활동점수·
  // 위험도를 읽는다(health_profile 있으면 실데이터, 없으면 백엔드가 데모 기본값 반환).
  // 데모/로컬 모드에서만 인메모리 mock 을 사용한다. diet/exercise 와 동일한 분기.
  if (ref.watch(appConfigProvider).useMockApi) {
    // 잔액은 목업 식단·운동·코치 경로와 같은 원장에서 읽는다(#1786).
    // 이름·이메일은 목업 인터셉터가 저장한 프로필과 같은 DB 에서 읽는다(#2661).
    return MockMyHealthRepository(
      points: ref.watch(demoPointsLedgerProvider),
      db: ref.watch(appDatabaseProvider),
    );
  }
  return DioMyHealthRepository(ref.watch(dioProvider));
}, name: 'myHealthRepository');

/// 데모에서 연결 코드를 입력해 주는 트레이너. 데모 담당 요청을 보내는 사람과
/// 같다(`MockMemberCoachRepository`).
const String _demoPairingTrainerId = 'trainer-kim';

/// 동기화 코드 발급·취소. (#1634)
///
/// 실서비스와 데모가 같은 경로를 탄다. 데모에서는 코드를 띄워 두면 잠시 뒤
/// 트레이너가 입력한 것처럼 담당 연결을 잇는다 — 그래야 시트의 `연결됐어요` 가
/// 데모에서도 보인다(#3342). 연결 상태는 헬스장 저장소가 들고 있고, 담당 코치
/// 저장소도 그것을 읽는다(#1865).
final trainerSyncRepositoryProvider = Provider<TrainerSyncRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    final GymRepository gym = ref.watch(gymRepositoryProvider);
    final DemoTrainerSyncRepository demo = DemoTrainerSyncRepository(
      ref.watch(dioProvider),
      onCodeEntered: () {
        // 이미 담당이 있으면 그대로 둔다 — 코드는 담당이 없는 회원을 잇는 문이다.
        if (gym is MockGymRepository && !gym.hasTrainer) {
          gym.linkTrainer(_demoPairingTrainerId);
        }
      },
    );
    ref.onDispose(demo.dispose);
    return demo;
  }
  return TrainerSyncRepository(ref.watch(dioProvider));
}, name: 'trainerSyncRepository');

/// 프로필·위험도·포인트·설정.
///
/// 식단·운동을 저장하거나 지우면 포인트가 움직이므로, 그 흐름이 이 provider 를
/// 다시 읽는다(`refreshPointsBalance`, #1786). 예전에는 세션 초기화 때만 읽었다.
final myHealthStateProvider = FutureProvider<MyHealthState>((ref) {
  return ref.watch(myHealthRepositoryProvider).fetchState();
}, name: 'myHealthState');
