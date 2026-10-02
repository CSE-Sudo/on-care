import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/features/my_health/data/repositories/dio_my_health_repository.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';

void main() {
  group('MyHealthState.fromJson (#2903)', () {
    test('서버 응답은 프로필과 포인트 잔액뿐이다', () {
      final state = MyHealthState.fromJson(<String, Object?>{
        'profile': <String, Object?>{
          'id': 'user-7d4e9a2c5f18',
          'name': '김민수',
          'email': 'minsu@oncare.com',
        },
        'activity_points': 1240,
      });
      expect(state.profile.id, 'user-7d4e9a2c5f18');
      expect(state.profile.name, '김민수');
      expect(state.profile.email, 'minsu@oncare.com');
      expect(state.activityPoints, 1240);
    });

    test('옛 서버가 위험 문구·순위·설정 메뉴를 실어 보내도 파싱된다', () {
      // 배포 순서에 따라 앱이 먼저 바뀌면 빠진 필드가 아직 온다 — 무시한다.
      final state = MyHealthState.fromJson(<String, Object?>{
        'profile': <String, Object?>{
          'name': '김민수',
          'email': 'minsu@oncare.com',
        },
        'risk': <String, Object?>{
          'title': '주의',
          'body': '관리 필요',
          'level': 'medium',
        },
        'activity_points': 50,
        'activity_rank': 14,
        'settings': <Object?>[],
      });
      expect(state.activityPoints, 50);
      expect(state.profile.id, '');
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
