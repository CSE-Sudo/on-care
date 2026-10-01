/// 알림 목록 폴링의 수명 — 목록을 보는 동안만 돈다. (#2767)
///
/// 전에는 목록 provider 를 계정 동안 붙잡아 두어, 알림 종을 한 번 열었다
/// 닫으면 세션이 끝날 때까지 `GET /trainer/notifications` 가 20초마다 나갔다.
/// 배지(미읽음 수)는 따로 폴링하므로 그대로 돌아야 한다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/utils/active_polling_stream.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';

class _MockDio extends Mock implements Dio {}

const String _listPath = '/trainer/notifications';
const String _unreadPath = '/trainer/notifications/unread-count';

Response<T> _ok<T>(T body, String path) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: body,
);

/// 계정마다 다른 알림 하나를 주는 페이크 — 계정 경계 검증용.
class _AccountRepo implements TrainerNotificationRepository {
  const _AccountRepo(this.account);

  final String account;

  @override
  bool get supportsInbox => true;

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async => TrainerNotificationPage(
    items: <TrainerNotification>[
      TrainerNotification(
        id: 'noti-$account',
        title: '$account 의 알림',
        body: '',
        kind: TrainerNotificationKind.other,
        read: false,
        createdAt: DateTime.utc(2026, 8, 9, 10),
        timeAgo: '방금 전',
      ),
    ],
  );

  @override
  Stream<TrainerNotificationPage> watch() =>
      Stream<TrainerNotificationPage>.fromFuture(fetch());

  @override
  Future<int> unreadCount() async => 1;

  @override
  Stream<int> watchUnreadCount() => Stream<int>.value(1);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;
}

void main() {
  late _MockDio dio;
  late int listCalls;
  late int unreadCalls;
  late ProviderContainer container;

  setUp(() {
    dio = _MockDio();
    listCalls = 0;
    unreadCalls = 0;
    when(() => dio.get<List<dynamic>>(_listPath)).thenAnswer((_) async {
      listCalls++;
      return _ok<List<dynamic>>(<dynamic>[], _listPath);
    });
    when(() => dio.get<Map<String, Object?>>(_unreadPath)).thenAnswer((
      _,
    ) async {
      unreadCalls++;
      return _ok<Map<String, Object?>>(<String, Object?>{
        'unread': 0,
      }, _unreadPath);
    });
    container = ProviderContainer(
      overrides: <Override>[
        trainerNotificationRepositoryProvider.overrideWithValue(
          DioNotificationRepository(dio),
        ),
      ],
    );
  });

  testWidgets('보는 동안에는 20초마다 다시 읽는다', (tester) async {
    final ProviderSubscription<Object?> list = container.listen(
      trainerNotificationsProvider,
      (_, _) {},
    );
    await tester.pump();
    expect(listCalls, 1);

    await tester.pump(badgePollInterval);
    await tester.pump();
    expect(listCalls, 2);

    list.close();
    await tester.pump();
    container.dispose();
  });

  testWidgets('목록을 닫으면 폴링이 멈추고 provider 도 버려진다', (tester) async {
    final ProviderSubscription<Object?> list = container.listen(
      trainerNotificationsProvider,
      (_, _) {},
    );
    await tester.pump();
    expect(listCalls, 1);

    list.close();
    await tester.pump();
    expect(container.exists(trainerNotificationsProvider), isFalse);

    // 몇 주기가 지나도 더 부르지 않는다.
    await tester.pump(badgePollInterval * 3);
    expect(listCalls, 1);
    container.dispose();
  });

  testWidgets('다시 열면 첫 쪽을 새로 받고 폴링을 다시 시작한다', (tester) async {
    ProviderSubscription<Object?> list = container.listen(
      trainerNotificationsProvider,
      (_, _) {},
    );
    await tester.pump();
    list.close();
    await tester.pump();
    await tester.pump(badgePollInterval * 2);
    expect(listCalls, 1);

    list = container.listen(trainerNotificationsProvider, (_, _) {});
    await tester.pump();
    expect(listCalls, 2);
    expect(container.read(trainerNotificationsProvider).hasValue, isTrue);

    await tester.pump(badgePollInterval);
    await tester.pump();
    expect(listCalls, 3);

    list.close();
    await tester.pump();
    container.dispose();
  });

  testWidgets('목록을 닫아도 배지 폴링은 그대로 돈다', (tester) async {
    final ProviderSubscription<Object?> badge = container.listen(
      trainerUnreadNotificationsProvider,
      (_, _) {},
    );
    final ProviderSubscription<Object?> list = container.listen(
      trainerNotificationsProvider,
      (_, _) {},
    );
    await tester.pump();
    list.close();
    await tester.pump();

    final int before = unreadCalls;
    await tester.pump(badgePollInterval);
    await tester.pump();
    expect(unreadCalls, before + 1);
    expect(listCalls, 1);

    badge.close();
    await tester.pump();
    container.dispose();
  });

  test('계정이 바뀐 뒤 다시 열면 이전 계정의 알림이 보이지 않는다', () async {
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        trainerNotificationRepositoryProvider.overrideWith((ref) {
          final int scope = ref.watch(accountScopeProvider);
          return _AccountRepo(scope == 0 ? 'A' : 'B');
        }),
      ],
    );
    addTearDown(c.dispose);

    final ProviderSubscription<AsyncValue<TrainerNotificationPage>> a = c
        .listen(trainerNotificationsProvider, (_, _) {});
    await c.read(trainerNotificationsProvider.future);
    expect(a.read().requireValue.items.single.id, 'noti-A');
    a.close();
    await Future<void>.delayed(Duration.zero);

    c.read(accountScopeProvider.notifier).state++;

    final List<AsyncValue<TrainerNotificationPage>> seen =
        <AsyncValue<TrainerNotificationPage>>[];
    final ProviderSubscription<AsyncValue<TrainerNotificationPage>> b = c
        .listen(
          trainerNotificationsProvider,
          (_, AsyncValue<TrainerNotificationPage> next) => seen.add(next),
          fireImmediately: true,
        );
    addTearDown(b.close);
    await c.read(trainerNotificationsProvider.future);

    for (final AsyncValue<TrainerNotificationPage> state in seen) {
      final List<TrainerNotification> items =
          state.valueOrNull?.items ?? const <TrainerNotification>[];
      expect(items.map((n) => n.id), isNot(contains('noti-A')));
    }
    expect(b.read().requireValue.items.single.id, 'noti-B');
  });
}
