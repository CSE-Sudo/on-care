import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/exercise/data/repositories/dio_trainer_report_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_trainer_report_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/trainer_report_repository.dart';

/// 트레이너 신고 저장소 (#3008). 데모는 목 헬스장 저장소처럼 메모리에서 받는다 —
/// 한 인스턴스를 provider 수명 동안 유지해 같은 트레이너 중복 신고가 실서버처럼
/// 거절된다.
final trainerReportRepositoryProvider = Provider<TrainerReportRepository>((
  ref,
) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return MockTrainerReportRepository();
  }
  return DioTrainerReportRepository(ref.watch(dioProvider));
}, name: 'trainerReportRepository');
