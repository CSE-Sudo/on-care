/// 알림 읽음 표시와 미읽음 폴링의 경쟁 — #3097.
///
/// 여기서 고정하는 성질.
///
///  * 조회가 진행 중일 때 읽음·모두 읽음을 하고 쓰기가 먼저 끝나도, 쓰기 **전**
///    서버 상태를 담은 응답이 목록을 다시 안 읽음으로 돌리지 않는다. 응답에 새로 온
///    알림은 그대로 붙는다.
///  * 쓰기가 실패하면 그 응답으로 덮은 알림까지 안 읽음으로 되돌린다(#2877).
///  * 미읽음 배지를 듣는 곳이 모두 사라지면 폴링이 멈춘다.
///  * 로그아웃한 뒤에는 배지를 다시 세더라도 서버에 묻지 않는다.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';

const AppConfig _realConfig = AppConfig(
  environment: Environment.prod,
  apiBaseUrl: 'https://api.test/v1',
  useMockApi: false,
);

AlertItem _alert(String id, {bool read = false, String createdAt = ''}) =>
    AlertItem(
      id: id,
      title: '알림 $id',
      body: '본문',
      timeAgo: '방금',
      category: AlertCategory.system,
      read: read,
      createdAt: createdAt,
    );

/// 서버처럼 동작하는 대역. 조회는 **요청을 받은 시점의** 목록을 답한다 — 응답을
/// 붙잡아 둔 사이 쓰기가 끝나도 응답은 옛 상태다.
class _RacingRepo implements NotificationRepository {
  _RacingRepo(this.items);

  List<AlertItem> items;
  int unreadCalls = 0;

  /// 다음 조회 응답을 붙잡는다.
  Completer<void>? fetchGate;

  /// 읽음 쓰기를 실패로 답한다.
  bool writeThrows = false;

  /// 읽음 쓰기를 붙잡는다.
  Completer<void>? writeGate;

  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async {
    final List<AlertItem> snapshot = List<AlertItem>.of(items);
    final Completer<void>? gate = fetchGate;
    if (gate != null) await gate.future;
    return snapshot;
  }

  @override
  Future<void> markRead(String id) async {
    if (writeGate != null) await writeGate!.future;
    if (writeThrows) throw StateError('쓰기 실패');
    items = items
        .map((AlertItem i) => i.id == id ? i.copyWith(read: true) : i)
        .toList();
  }

  @override
  Future<void> markAllRead() async {
    if (writeGate != null) await writeGate!.future;
    if (writeThrows) throw StateError('쓰기 실패');
    items = items.map((AlertItem i) => i.copyWith(read: true)).toList();
  }

  @override
  Future<int> unreadCount() async {
    unreadCalls++;
    return items.where((AlertItem i) => !i.read).length;
  }
}

ProviderContainer _container(_RacingRepo repo) {
  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_realConfig),
      notificationRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, bool> _readById(ProviderContainer container) => <String, bool>{
  for (final AlertItem i
      in container.read(notificationControllerProvider).items)
    i.id: i.read,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('진행 중 조회와 읽음 처리 (#3097)', () {
    test('읽음 쓰기가 먼저 끝나도 옛 응답이 그 알림을 안 읽음으로 돌리지 않는다', () async {
      final repo = _RacingRepo(<AlertItem>[_alert('a'), _alert('b')]);
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      // 알림함 진입 — 조회가 나갔지만 응답은 아직이다.
      repo.fetchGate = Completer<void>();
      final Future<void> loading = notifier.refresh();
      await _settle();

      await notifier.markRead('a');
      expect(repo.items.firstWhere((AlertItem i) => i.id == 'a').read, isTrue);

      // 쓰기 전 서버 상태를 담은 응답이 도착한다.
      repo.fetchGate!.complete();
      await loading;

      expect(_readById(container), <String, bool>{'a': true, 'b': false});
    });

    test('옛 응답에 새로 온 알림은 그대로 붙는다', () async {
      final repo = _RacingRepo(<AlertItem>[_alert('a')]);
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      // 트레이너가 새 알림을 보낸 뒤 진입했다.
      repo.items = <AlertItem>[_alert('new'), _alert('a')];
      repo.fetchGate = Completer<void>();
      final Future<void> loading = notifier.refresh();
      await _settle();

      await notifier.markRead('a');
      repo.fetchGate!.complete();
      await loading;

      expect(_readById(container), <String, bool>{'new': false, 'a': true});
    });

    test('모두 읽음 뒤 도착한 옛 응답도 그때까지의 알림을 읽음으로 둔다', () async {
      final repo = _RacingRepo(<AlertItem>[
        _alert('b', createdAt: '2026-10-04T10:00:00Z'),
        _alert('a', createdAt: '2026-10-04T09:00:00Z'),
      ]);
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      // 응답에는 받아 두지 않았던 과거 알림(old)과, 모두 읽음 뒤에 온 새 알림이
      // 섞여 있다.
      repo.items = <AlertItem>[
        _alert('new', createdAt: '2026-10-04T11:00:00Z'),
        ...repo.items,
        _alert('old', createdAt: '2026-10-03T09:00:00Z'),
      ];
      repo.fetchGate = Completer<void>();
      final Future<void> loading = notifier.refresh();
      await _settle();

      expect(await notifier.markAllRead(), isTrue);
      // 서버는 쓰기 때 있던 알림을 모두 읽음으로 바꿨다. 새 알림은 그 뒤에 왔다고
      // 친다.
      repo.items = repo.items
          .map((AlertItem i) => i.id == 'new' ? i : i.copyWith(read: true))
          .toList();

      repo.fetchGate!.complete();
      await loading;

      expect(_readById(container), <String, bool>{
        'new': false,
        'b': true,
        'a': true,
        'old': true,
      });
    });

    test('쓰기가 실패하면 그 사이 응답으로 덮은 알림까지 안 읽음으로 되돌린다', () async {
      final repo = _RacingRepo(<AlertItem>[_alert('a'), _alert('b')])
        ..writeGate = Completer<void>()
        ..writeThrows = true;
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      final Future<void> writing = notifier.markRead('a');
      await _settle();
      // 쓰기가 진행 중일 때 응답이 먼저 온다 — 읽음 표시는 유지된다.
      await notifier.refresh();
      expect(_readById(container)['a'], isTrue);

      repo.writeGate!.complete();
      await writing;

      expect(_readById(container), <String, bool>{'a': false, 'b': false});
    });

    test('쓰기가 끝난 뒤 새로 나간 조회는 서버 답을 그대로 쓴다', () async {
      final repo = _RacingRepo(<AlertItem>[_alert('a')]);
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      await notifier.markRead('a');
      // 다른 기기에서 다시 안 읽음이 된 상황을 흉내 낸다 — 덧입힘이 남아 있으면
      // 서버 답을 덮어 버린다.
      repo.items = <AlertItem>[_alert('a')];
      await notifier.refresh();

      expect(_readById(container), <String, bool>{'a': false});
    });
  });

  group('미읽음 폴링 (#3097)', () {
    testWidgets('듣는 곳이 모두 사라지면 폴링이 멈춘다', (WidgetTester tester) async {
      final repo = _RacingRepo(<AlertItem>[_alert('a')]);
      final container = _container(repo);

      final ProviderSubscription<AsyncValue<int>> sub = container
          .listen<AsyncValue<int>>(
            notificationUnreadProvider,
            (AsyncValue<int>? _, AsyncValue<int> _) {},
            fireImmediately: true,
          );
      await tester.pump();
      await tester.pump(const Duration(seconds: 16));
      expect(repo.unreadCalls, greaterThanOrEqualTo(2));

      sub.close();
      await tester.pump(const Duration(seconds: 1));
      final int after = repo.unreadCalls;

      await tester.pump(const Duration(seconds: 60));
      expect(repo.unreadCalls, after);
    });

    test('로그아웃한 뒤에는 배지를 다시 세도 서버에 묻지 않는다', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'access_token': 'stored-access',
        'refresh_token': 'stored-refresh',
      });
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (RequestOptions o, RequestInterceptorHandler h) =>
                h.resolve(
                  Response<Map<String, Object?>>(
                    requestOptions: o,
                    statusCode: 200,
                    data: <String, Object?>{'id': 'u1'},
                  ),
                ),
          ),
        );
      final repo = _RacingRepo(<AlertItem>[_alert('a')]);
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_realConfig),
          dioProvider.overrideWithValue(dio),
          notificationRepositoryProvider.overrideWithValue(repo),
          sessionFeatureResetOverride(),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      for (var i = 0; i < 40; i++) {
        if (container.read(sessionControllerProvider).isAuthenticated) break;
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);

      // 셸이 벨 배지를 듣고 있다.
      final ProviderSubscription<AsyncValue<int>> shell = container
          .listen<AsyncValue<int>>(
            notificationUnreadProvider,
            (AsyncValue<int>? _, AsyncValue<int> _) {},
            fireImmediately: true,
          );
      await _settle();
      final int before = repo.unreadCalls;
      expect(before, greaterThan(0));

      // 로그아웃은 세션 초기화로 배지를 무효화한다 — 셸이 아직 듣고 있어 새로 선다.
      await container.read(sessionControllerProvider.notifier).signOut();
      await _settle();
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      expect(repo.unreadCalls, before);
      expect(container.read(notificationUnreadProvider).valueOrNull, 0);

      // 셸이 치워지면 폴링도 끝난다.
      shell.close();
      await _settle();
      expect(container.exists(notificationUnreadProvider), isFalse);
    });
  });
}
