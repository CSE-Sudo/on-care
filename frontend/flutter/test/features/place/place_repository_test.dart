import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/place/data/repositories/dio_place_repository.dart';
import 'package:oncare/features/place/presentation/controllers/place_controller.dart';

void main() {
  // 장소 계층은 '주변 장소' 화면이 사라진 뒤에도 남는다 — 운동 탭의 헬스장 찾기가
  // 카카오 Local 결과를 이 repository 로 받는다(`gymFinderResultsProvider`).
  //
  // 예전에는 쓰이지 않는 목업 구현(`MockPlaceRepository`)이 있었고 이 테스트가
  // 그것만 확인했다. 앱은 데모에서도 Dio 구현을 쓰므로(#2646) 목업을 지우고,
  // provider 가 모드와 무관하게 Dio 구현을 내는지를 본다.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  for (final bool useMockApi in <bool>[true, false]) {
    test('USE_MOCK_API=$useMockApi 여도 장소 저장소는 Dio 구현이다', () {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'https://dev.api.test/v1',
              useMockApi: useMockApi,
            ),
          ),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(placeRepositoryProvider),
        isA<DioPlaceRepository>(),
      );
    });
  }
}
