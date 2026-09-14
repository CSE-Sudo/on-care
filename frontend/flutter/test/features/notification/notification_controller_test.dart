import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';

// 목 모드 설정 — 컨트롤러가 데모 시드(demoAlerts)를 즉시 사용하고
// 네트워크 없이 세션 변이만 검증한다.
const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

// 실모드 설정 — 컨트롤러가 리포에서 로드하고 읽음을 리포로 영속화한다.
const AppConfig _realConfig = AppConfig(
  environment: Environment.prod,
  apiBaseUrl: 'https://api.test/v1',
  useMockApi: false,
);

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: <Override>[appConfigProvider.overrideWithValue(_mockConfig)],
  );
  return container;
}

/// 실모드 검증용 리포 — fetchPage 결과를 돌려주고 읽음 호출을 기록한다.
class _RecordingRepo implements NotificationRepository {
  _RecordingRepo(this._items);

  final List<AlertItem> _items;
  final List<String> markReadCalls = <String>[];
  int markAllReadCalls = 0;

  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async => _items;

  @override
  Future<void> markRead(String id) async => markReadCalls.add(id);

  @override
  Future<void> markAllRead() async => markAllReadCalls++;

  @override
  Future<int> unreadCount() async =>
      _items.where((AlertItem a) => !a.read).length;
}

void main() {
  test('seed state has unread items', () {
    final container = _container();
    addTearDown(container.dispose);
    final state = container.read(notificationControllerProvider);
    expect(state.items, isNotEmpty);
    expect(state.unreadCount, greaterThan(0));
  });

  test('데모 알림도 갈 곳을 갖는다', () {
    // 목적지가 없으면 데모에서는 눌러도 읽음 처리만 된다 — 구현돼 있는 이동
    // 기능이 데모에서만 없는 것처럼 보인다. (#667)
    final container = _container();
    addTearDown(container.dispose);
    final List<AlertItem> items = container
        .read(notificationControllerProvider)
        .items;

    expect(
      items.where((AlertItem i) => i.action?.isNavigable ?? false),
      isNotEmpty,
    );
    // 갈 곳 없는 알림도 목록에는 남는다 — 사라지거나 엉뚱한 곳으로 가지 않는다.
    expect(items.where((AlertItem i) => i.action == null), isNotEmpty);
  });

  test('읽어도 갈 곳은 남는다', () {
    // `copyWith` 가 action 을 흘리면, 한 번 읽은 알림은 다시 눌러도 이동하지
    // 않는다 — 목록에는 그대로 있으니 원인을 찾기 어렵다.
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(notificationControllerProvider.notifier);
    final AlertItem target = container
        .read(notificationControllerProvider)
        .items
        .firstWhere((AlertItem i) => i.action != null);

    notifier.markRead(target.id);

    final AlertItem after = container
        .read(notificationControllerProvider)
        .items
        .firstWhere((AlertItem i) => i.id == target.id);
    expect(after.read, isTrue);
    expect(after.action?.target, target.action?.target);
  });

  test('markRead toggles a single item', () {
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(notificationControllerProvider.notifier);
    final firstId = container
        .read(notificationControllerProvider)
        .items
        .first
        .id;

    notifier.markRead(firstId);

    final updated = container
        .read(notificationControllerProvider)
        .items
        .firstWhere((i) => i.id == firstId);
    expect(updated.read, isTrue);
  });

  test('markAllRead drops unread count to zero', () {
    final container = _container();
    addTearDown(container.dispose);
    container.read(notificationControllerProvider.notifier).markAllRead();
    expect(container.read(notificationControllerProvider).unreadCount, 0);
  });

  test('real mode loads from repo and persists read/all-read', () async {
    final repo = _RecordingRepo(const <AlertItem>[
      AlertItem(
        id: 'n1',
        title: '알림1',
        body: 'b1',
        timeAgo: '방금',
        category: AlertCategory.reminder,
      ),
      AlertItem(
        id: 'n2',
        title: '알림2',
        body: 'b2',
        timeAgo: '1시간 전',
        category: AlertCategory.achievement,
      ),
    ]);
    final container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_realConfig),
        notificationRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(notificationControllerProvider.notifier);
    await notifier.refresh(); // deterministically await the backend load
    expect(container.read(notificationControllerProvider).items.length, 2);

    await notifier.markRead('n1');
    expect(repo.markReadCalls, <String>['n1']);
    expect(
      container
          .read(notificationControllerProvider)
          .items
          .firstWhere((AlertItem i) => i.id == 'n1')
          .read,
      isTrue,
    );

    await notifier.markAllRead();
    expect(repo.markAllReadCalls, 1);
    expect(container.read(notificationControllerProvider).unreadCount, 0);
  });
}
