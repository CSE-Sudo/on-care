/// 데모에서도 대화를 읽으면 메시지·리포트 알림이 읽음이 된다 — #3343.
///
/// 데모의 대화는 목업 코치 저장소가, 알림은 로컬 목업 API(drift)가 들고 있다.
/// 저장소가 읽었다고 알리고, 목업 API 가 서버와 같은 갈래만 읽음으로 바꾼다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare_core/clock.dart';

const AppConfig _demoConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('목업 코치 저장소', () {
    test('대화를 읽으면 알림함에 알린다', () async {
      int calls = 0;
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        onChatRead: () async => calls += 1,
      );
      addTearDown(repo.dispose);

      await repo.markRead();

      expect(calls, 1);
      expect(await repo.unreadCount(), 0);
    });

    test('알릴 곳이 없어도 대화는 읽음이 된다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository();
      addTearDown(repo.dispose);

      await repo.markRead();

      expect(await repo.unreadCount(), 0);
    });

    test('알리다 실패하면 실패를 그대로 올린다 — 대화는 이미 읽음이다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        onChatRead: () async => throw StateError('알림 읽음 실패'),
      );
      addTearDown(repo.dispose);

      await expectLater(repo.markRead(), throwsStateError);
      expect(await repo.unreadCount(), 0);
    });
  });

  group('목업 모드 연결', () {
    late AppDatabase db;
    late Dio dio;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      final now = nowKst();
      await db.batch((b) {
        b.insertAll(db.notificationItems, <NotificationItemsCompanion>[
          NotificationItemsCompanion.insert(
            id: 'chat',
            createdAt: now.subtract(const Duration(minutes: 5)),
            title: '트레이너 피드백이 도착했어요',
            body: '스트레칭을 꼭 해 주세요.',
            category: 'coach_chat',
          ),
          NotificationItemsCompanion.insert(
            id: 'routine',
            createdAt: now.subtract(const Duration(minutes: 10)),
            title: '새 개인운동이 왔어요',
            body: '걷기 위주로 조정했어요.',
            category: 'routine',
          ),
        ]);
      });
    });

    tearDown(() async {
      await db.close();
      dio.close();
    });

    Future<Map<String, bool>> reads() async => <String, bool>{
      for (final r in await db.select(db.notificationItems).get()) r.id: r.read,
    };

    test('저장소의 대화 읽음이 로컬 목업 API 의 알림을 읽음으로 바꾼다', () async {
      dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_demoConfig),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(memberCoachRepositoryProvider).markRead();

      final r = await reads();
      expect(r['chat'], isTrue);
      expect(r['routine'], isFalse);
    });

    test('목업 API 가 없는 Dio 면 요청을 보내지 않는다', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_demoConfig),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(memberCoachRepositoryProvider).markRead();

      expect((await reads())['chat'], isFalse);
    });
  });
}
