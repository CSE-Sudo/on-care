import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_chat_repository.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

class _CountingChatRepository implements ChatRepository {
  int threadReads = 0;

  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) {
    threadReads++;
    return Stream<List<ClientChatMessage>>.value(const <ClientChatMessage>[]);
  }

  @override
  Future<void> markThreadRead(String clientId) async {}

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
    String? emoteId,
  }) async {}

  @override
  Stream<Map<String, int>> watchUnreadCounts() =>
      Stream<Map<String, int>>.value(const <String, int>{});
}

ProviderContainer _containerFor({required bool useMockApi}) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'http://localhost/v1',
          useMockApi: useMockApi,
        ),
      ),
      appDatabaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('resolves the drift chat repository when USE_MOCK_API=true', () {
    expect(
      _containerFor(useMockApi: true).read(chatRepositoryProvider),
      isA<DriftChatRepository>(),
    );
  });

  test('resolves the Dio chat repository when USE_MOCK_API=false', () {
    expect(
      _containerFor(useMockApi: false).read(chatRepositoryProvider),
      isA<DioChatRepository>(),
    );
  });

  test(
    'thread provider refetches after the view is left and re-entered',
    () async {
      final repo = _CountingChatRepository();
      final container = ProviderContainer(
        overrides: <Override>[chatRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      var subscription = container.listen(
        chatThreadProvider('m1'),
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(chatThreadProvider('m1').future);
      subscription.close();
      await container.pump();

      subscription = container.listen(
        chatThreadProvider('m1'),
        (_, _) {},
        fireImmediately: true,
      );
      await container.read(chatThreadProvider('m1').future);
      subscription.close();

      expect(repo.threadReads, 2);
    },
  );
}
