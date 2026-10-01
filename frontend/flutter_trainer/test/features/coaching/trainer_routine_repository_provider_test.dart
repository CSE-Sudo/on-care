import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';

ProviderContainer _containerFor({required bool useMockApi}) {
  // 데모 저장소는 데모 DB 를 받는다(#2668) — 실제 DB 를 열지 않게 메모리로.
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(
    overrides: <Override>[
      appDatabaseProvider.overrideWithValue(db),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'http://localhost/v1',
          useMockApi: useMockApi,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('resolves the mock routine repository when USE_MOCK_API=true', () {
    expect(
      _containerFor(useMockApi: true).read(trainerRoutineRepositoryProvider),
      isA<MockTrainerRoutineRepository>(),
    );
  });

  test('resolves the Dio routine repository when USE_MOCK_API=false', () {
    expect(
      _containerFor(useMockApi: false).read(trainerRoutineRepositoryProvider),
      isA<DioTrainerRoutineRepository>(),
    );
  });
}
