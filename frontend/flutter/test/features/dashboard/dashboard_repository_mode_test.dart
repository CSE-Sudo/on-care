import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/dashboard/data/repositories/dio_dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';

/// 데모 홈은 예전에 별도 목업 저장소를 탔다. 그 분기가 두 번 유실되어 데모 홈이
/// "대시보드 정보를 불러오지 못했어요" 만 띄운 적이 있고, 분기가 살아 있을 때는
/// 고정 운동값·큐레이션 조언을 내 실제 기록과 어긋났다. 이제 두 모드 모두 Dio
/// 저장소이고, 데모는 `dioProvider` 에 달린 로컬 인터셉터가 답한다(#2645).
void main() {
  // 데모 Dio 는 로컬 인터셉터를 통해 drift 를 타므로 바인딩과 인메모리 DB 가
  // 필요하다. 파일 DB 를 열면 테스트가 기기 저장소에 의존하게 된다.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dashboardRepositoryProvider 모드 분기', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

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
          appDatabaseProvider.overrideWithValue(db),
          accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('USE_MOCK_API=false 면 Dio 저장소를 쓴다', () {
      final container = makeContainer(useMockApi: false);
      expect(
        container.read(dashboardRepositoryProvider),
        isA<DioDashboardRepository>(),
      );
    });

    test('USE_MOCK_API=true 도 같은 Dio 저장소다 — 목업 갈래가 없다', () {
      final container = makeContainer(useMockApi: true);
      expect(
        container.read(dashboardRepositoryProvider),
        isA<DioDashboardRepository>(),
      );
    });

    test('데모 기본값(USE_MOCK_API 미지정)도 Dio 저장소다', () {
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(AppConfig.fromEnvironment()),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          appDatabaseProvider.overrideWithValue(db),
          accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(dashboardRepositoryProvider),
        isA<DioDashboardRepository>(),
      );
    });
  });
}
