import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';

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
  test('resolves the demo suggestion repository when USE_MOCK_API=true', () {
    expect(
      _containerFor(
        useMockApi: true,
      ).read(trainerRoutineSuggestionRepositoryProvider),
      isA<MockTrainerRoutineSuggestionRepository>(),
    );
  });

  test('resolves the Dio suggestion repository when USE_MOCK_API=false', () {
    expect(
      _containerFor(
        useMockApi: false,
      ).read(trainerRoutineSuggestionRepositoryProvider),
      isA<DioTrainerRoutineSuggestionRepository>(),
    );
  });

  test('the demo repository drops a suggestion once it is reviewed', () async {
    final repo = MockTrainerRoutineSuggestionRepository();

    final before = await repo.pending('m1');
    expect(before, isNotEmpty);

    await repo.approve(before.first.id);
    final after = await repo.pending('m1');

    expect(after.length, before.length - 1);
    // 두 번째 검토는 실서버의 409 와 같은 예외 — 데모에서도 같은 문구가 나온다.
    await expectLater(
      repo.approve(before.first.id),
      throwsA(isA<RoutineSuggestionAlreadyReviewed>()),
    );
  });

  test('the demo repository keeps each member\'s list separate', () async {
    final repo = MockTrainerRoutineSuggestionRepository();

    final first = await repo.pending('m1');
    await repo.dismiss(first.first.id);

    // 한 회원의 판단이 다른 회원의 목록을 줄이면 안 된다.
    expect((await repo.pending('m2')).length, first.length);
  });
}
