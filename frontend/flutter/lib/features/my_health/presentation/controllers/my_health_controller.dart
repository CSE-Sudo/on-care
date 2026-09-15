import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/features/my_health/data/repositories/dio_my_health_repository.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/domain/repositories/my_health_repository.dart';

final myHealthRepositoryProvider = Provider<MyHealthRepository>((ref) {
  // 실모드(USE_MOCK_API=false)에서는 백엔드 /users/me/health 로 실제 프로필·활동점수·
  // 위험도를 읽는다(health_profile 있으면 실데이터, 없으면 백엔드가 데모 기본값 반환).
  // 데모/로컬 모드에서만 인메모리 mock 을 사용한다. diet/exercise 와 동일한 분기.
  if (ref.watch(appConfigProvider).useMockApi) {
    // 잔액은 목업 식단·운동·코치 경로와 같은 원장에서 읽는다(#1786).
    return MockMyHealthRepository(points: ref.watch(demoPointsLedgerProvider));
  }
  return DioMyHealthRepository(ref.watch(dioProvider));
}, name: 'myHealthRepository');

/// 프로필·위험도·포인트·설정.
///
/// 식단·운동을 저장하거나 지우면 포인트가 움직이므로, 그 흐름이 이 provider 를
/// 다시 읽는다(`refreshPointsBalance`, #1786). 예전에는 세션 초기화 때만 읽었다.
final myHealthStateProvider = FutureProvider<MyHealthState>((ref) {
  return ref.watch(myHealthRepositoryProvider).fetchState();
}, name: 'myHealthState');
