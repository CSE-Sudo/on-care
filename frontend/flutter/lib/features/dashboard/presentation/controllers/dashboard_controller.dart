import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/dashboard/data/repositories/dio_dashboard_repository.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';

/// 홈 요약 저장소. 데모와 실서버가 **같은 경로**다(#2645).
///
/// 데모(`USE_MOCK_API`)에서는 [dioProvider] 가 `LocalApiInterceptor` 를 달고
/// 있어 `GET /dashboard/summary` 를 로컬 DB 로 답한다 — 식단·운동 탭이 이미 이
/// 경로다. 예전에는 데모 홈만 별도 목업 저장소를 거쳐, 운동 45분·큐레이션 조언
/// 같은 고정값을 내고 요청 언어도 보지 않았다. 끼니를 다 지워도 홈 조언이
/// 그대로였던 까닭이다.
///
/// 식단 CRUD 뒤의 새로 고침은 홈 탭으로 돌아올 때 [dashboardSummaryProvider]
/// 를 무효화하는 셸이 맡는다(실서버와 같다).
final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DioDashboardRepository(ref.watch(dioProvider));
}, name: 'dashboardRepository');

final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((
  ref,
) {
  final repo = ref.watch(dashboardRepositoryProvider);
  return repo.fetchSummary();
}, name: 'dashboardSummary');
