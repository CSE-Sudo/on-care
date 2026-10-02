/// 알림이 서버 상태를 따라가는지 — #636.
///
/// 예전에는 컨트롤러가 생성될 때 한 번만 조회했다. `refresh()` 는 있었지만 부르는
/// 곳이 없어, 트레이너가 무언가 해도 회원 앱을 **재시작해야** 알림을 볼 수 있었다.
///
/// 여기서 고정하는 성질.
///
///  * 다시 조회하면 서버 목록으로 갈아 끼운다(중복이 남지 않는다).
///  * 조회가 겹쳐도 요청은 한 번만 나간다.
///  * 실패해도 **받아 둔 목록을 지우지 않고** 재시도를 제안한다.
///  * 목 모드는 네트워크를 타지 않는다 — 데모 화면이 서버를 찌르면 안 된다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';

const AppConfig _realConfig = AppConfig(
  environment: Environment.prod,
  apiBaseUrl: 'https://api.test/v1',
  useMockApi: false,
);

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

AlertItem _alert(String id, {bool read = false}) => AlertItem(
  id: id,
  title: '알림 $id',
  body: '본문',
  timeAgo: '방금',
  category: AlertCategory.system,
  read: read,
);

/// 조회 횟수를 세고, 결과와 실패를 시나리오별로 바꿀 수 있는 대역.
class _ScriptedRepo implements NotificationRepository {
  _ScriptedRepo(this._items);

  List<AlertItem> _items;
  int fetchCalls = 0;
  int unreadCalls = 0;
  bool fetchThrows = false;

  /// 조회를 붙잡아 두었다가 테스트가 풀어 주게 한다(겹침 검증용).
  Completer<void>? gate;

  /// 읽음 쓰기를 붙잡아 둔다. 쓰기가 끝나기 전에 미읽음을 다시 세면 서버가 옛 수를
  /// 답하므로, 그 순서를 검증하는 데 쓴다.
  Completer<void>? writeGate;

  void serve(List<AlertItem> items) => _items = items;

  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async {
    fetchCalls++;
    if (gate != null) await gate!.future;
    if (fetchThrows) throw StateError('네트워크 없음');
    return _items;
  }

  @override
  Future<void> markRead(String id) async {
    if (writeGate != null) await writeGate!.future;
    _items = _items
        .map((AlertItem i) => i.id == id ? i.copyWith(read: true) : i)
        .toList();
  }

  @override
  Future<void> markAllRead() async {
    _items = _items.map((AlertItem i) => i.copyWith(read: true)).toList();
  }

  @override
  Future<int> unreadCount() async {
    unreadCalls++;
    return _items.where((AlertItem i) => !i.read).length;
  }
}

ProviderContainer _container(_ScriptedRepo repo, {AppConfig? config}) {
  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(config ?? _realConfig),
      notificationRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  // 미읽음 배지는 `activePollingStream` 을 쓰고, 그 스트림이 앱 생명주기를 읽는다.
  // 바인딩이 없으면 스트림이 시작조차 못 해 배지 검증이 조용히 통과한다.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('다시 조회하면 서버 목록으로 갈아 끼운다', () async {
    final repo = _ScriptedRepo(<AlertItem>[_alert('a')]);
    final container = _container(repo);

    final notifier = container.read(notificationControllerProvider.notifier);
    await _settle();
    expect(container.read(notificationControllerProvider).items, hasLength(1));

    // 트레이너가 무언가 해서 서버에 알림이 하나 더 생긴 상황.
    repo.serve(<AlertItem>[_alert('b'), _alert('a')]);
    await notifier.refresh();

    final List<AlertItem> items = container
        .read(notificationControllerProvider)
        .items;
    // 통째로 갈아 끼우므로 같은 알림이 두 번 보이지 않는다.
    expect(items.map((AlertItem i) => i.id), <String>['b', 'a']);
  });

  test('조회가 겹쳐도 요청은 한 번만 나간다', () async {
    final repo = _ScriptedRepo(<AlertItem>[_alert('a')])
      ..gate = Completer<void>();
    final container = _container(repo);

    final notifier = container.read(notificationControllerProvider.notifier);
    // 생성자 조회가 아직 붙잡혀 있는 사이 진입 재조회가 겹친다.
    final Future<void> second = notifier.refresh();
    repo.gate!.complete();
    await second;

    // 화면 진입과 포그라운드 복귀가 겹치는 상황이라 실제로 자주 일어난다.
    expect(repo.fetchCalls, 1);
  });

  test('조회에 실패해도 받아 둔 목록을 지우지 않는다', () async {
    final repo = _ScriptedRepo(<AlertItem>[_alert('a'), _alert('b')]);
    final container = _container(repo);

    final notifier = container.read(notificationControllerProvider.notifier);
    await _settle();
    expect(container.read(notificationControllerProvider).items, hasLength(2));

    repo.fetchThrows = true;
    await notifier.refresh();

    final NotificationState state = container.read(
      notificationControllerProvider,
    );
    // 목록이 사라지면 읽지 않은 알림이 있었는지조차 알 수 없다.
    expect(state.items, hasLength(2));
    expect(state.failedToLoad, isTrue);
  });

  test('실패 뒤 다시 성공하면 실패 표시가 사라진다', () async {
    final repo = _ScriptedRepo(<AlertItem>[_alert('a')])..fetchThrows = true;
    final container = _container(repo);

    final notifier = container.read(notificationControllerProvider.notifier);
    await _settle();
    expect(container.read(notificationControllerProvider).failedToLoad, isTrue);

    repo.fetchThrows = false;
    await notifier.refresh();

    expect(
      container.read(notificationControllerProvider).failedToLoad,
      isFalse,
    );
  });

  test('읽음 처리하면 미읽음 배지를 즉시 다시 센다', () async {
    final repo = _ScriptedRepo(<AlertItem>[_alert('a'), _alert('b')]);
    final container = _container(repo);

    // 헤더가 배지를 보고 있는 상황을 만든다. 아무도 구독하지 않으면 무효화해도
    // 다시 조회되지 않는다(Riverpod 의 정상 동작) — 실제로는 탭 헤더가 늘 본다.
    container.listen<AsyncValue<int>>(
      notificationUnreadProvider,
      (AsyncValue<int>? _, AsyncValue<int> _) {},
      fireImmediately: true,
    );
    await container.read(notificationControllerProvider.notifier).refresh();
    await _settle();
    final int before = repo.unreadCalls;

    await container.read(notificationControllerProvider.notifier).markRead('a');
    await _settle();

    // 다음 폴링을 기다리면 목록과 배지가 잠시 어긋나 보인다.
    expect(repo.unreadCalls, greaterThan(before));
  });

  test('쓰기가 끝나기 전에는 미읽음을 다시 세지 않는다', () async {
    final repo = _ScriptedRepo(<AlertItem>[_alert('a'), _alert('b')])
      ..writeGate = Completer<void>();
    final container = _container(repo);

    container.listen<AsyncValue<int>>(
      notificationUnreadProvider,
      (AsyncValue<int>? _, AsyncValue<int> _) {},
      fireImmediately: true,
    );
    await container.read(notificationControllerProvider.notifier).refresh();
    await _settle();
    final int before = repo.unreadCalls;

    final Future<void> pending = container
        .read(notificationControllerProvider.notifier)
        .markRead('a');
    await _settle();
    // 아직 서버에 반영되지 않았다. 여기서 다시 세면 옛 수를 받아 배지가 다음
    // 폴링까지 틀린 채로 남는다(리뷰).
    expect(repo.unreadCalls, before);

    repo.writeGate!.complete();
    await pending;
    await _settle();
    expect(repo.unreadCalls, greaterThan(before));
  });

  // 데모도 새로고침이 저장소를 다시 부른다 — 로컬 인터셉터가 drift 로 답한다(#2660).
  // 그래야 챌린지 결과처럼 데모 중에 생긴 알림이 목록에 올라온다.
  test('목 모드도 새로고침하면 다시 불러온다', () async {
    final repo = _ScriptedRepo(<AlertItem>[_alert('a')]);
    final container = _container(repo, config: _mockConfig);

    final notifier = container.read(notificationControllerProvider.notifier);
    await _settle();
    final int before = repo.fetchCalls;
    await notifier.refresh();
    await _settle();

    expect(repo.fetchCalls, greaterThan(before));
    expect(container.read(notificationControllerProvider).items, isNotEmpty);
  });
}
