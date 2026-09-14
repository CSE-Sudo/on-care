import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/features/my_health/data/repositories/dio_my_health_repository.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';

/// 최소 유효 페이로드(indicators·settings 는 빈 배열). activity_rank 만 파라미터화.
Map<String, Object?> _payload({
  required Object? activityRank,
}) => <String, Object?>{
  'profile': <String, Object?>{'name': '김민수', 'email': 'minsu@oncare.com'},
  'risk': <String, Object?>{'title': '주의', 'body': '관리 필요', 'level': 'medium'},
  'indicators': <Object?>[],
  'activity_points': 1240,
  'activity_rank': activityRank,
  'settings': <Object?>[],
};

void main() {
  group('MyHealthState.fromJson activity_rank nullable (리뷰 #313)', () {
    test('activity_rank: null 이어도 파싱 오류 없이 null 로 수용된다', () {
      // 온보딩만 마친 일반 사용자는 백엔드가 activity_rank: null 을 반환한다.
      final state = MyHealthState.fromJson(_payload(activityRank: null));
      expect(state.activityRank, isNull);
      expect(state.activityPoints, 1240);
      expect(state.profile.name, '김민수');
    });

    test('activity_rank 값이 있으면 그대로 파싱된다', () {
      final state = MyHealthState.fromJson(_payload(activityRank: 14));
      expect(state.activityRank, 14);
    });
  });

  group('myHealthRepositoryProvider 모드 분기', () {
    ProviderContainer makeContainer({required bool useMockApi}) {
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'https://dev.api.test/v1',
              useMockApi: useMockApi,
            ),
          ),
          // Dio 저장소 경로는 dioProvider → appLogger 를 타므로 조용한 로거로 오버라이드.
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('USE_MOCK_API=false 면 Dio 저장소를 쓴다', () {
      final container = makeContainer(useMockApi: false);
      expect(
        container.read(myHealthRepositoryProvider),
        isA<DioMyHealthRepository>(),
      );
    });

    test('USE_MOCK_API=true 면 Mock 저장소를 쓴다', () {
      final container = makeContainer(useMockApi: true);
      expect(
        container.read(myHealthRepositoryProvider),
        isA<MockMyHealthRepository>(),
      );
    });
  });
}
