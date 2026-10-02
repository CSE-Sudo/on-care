/// 알림함이 실패·갈 곳 없음에서 사실과 다른 상태를 보이거나 말없이 멈추지 않는다
/// — #2877.
///
/// 여기서 고정하는 성질.
///
///  * 받아 본 적 없이 첫 조회가 실패하면 실패 안내와 재시도만 그린다.
///  * 재시도를 시작하면 실패 표시를 내리고 첫 로딩 표시로 돌아간다.
///  * 받은 쪽을 모두 읽었어도 서버 미읽음이 남아 있으면 모두 읽음을 누를 수 있다.
///  * 모두 읽음 쓰기가 실패하면 읽음 표시를 되돌리고 오류 안내를 띄운다.
///  * 한 건 읽음 쓰기가 실패하면 그 알림만 안 읽음으로 되돌린다.
///  * 갈 곳이 없는 알림 줄은 눌리는 모양(물결·버튼 읽기)이 없다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare/features/notification/presentation/alert_navigation.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/features/notification/presentation/pages/notification_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const AppConfig _realConfig = AppConfig(
  environment: Environment.prod,
  apiBaseUrl: 'https://api.test/v1',
  useMockApi: false,
);

const Key _firstLoading = Key('notificationFirstLoading');
const Key _firstLoadFailed = Key('notificationFirstLoadFailed');
const Key _firstLoadRetry = Key('notificationFirstLoadRetry');
const Key _retryBanner = Key('notificationRetryBanner');

AlertItem _alert(String id, {bool read = false, AlertAction? action}) =>
    AlertItem(
      id: id,
      title: '알림 $id',
      body: '본문',
      timeAgo: '방금',
      category: AlertCategory.system,
      read: read,
      action: action,
    );

const AlertAction _toDashboard = AlertAction(
  label: '보기',
  target: AlertTarget.dashboard,
);

/// 조회·읽음 쓰기의 성패와 완료 시점을 테스트가 정하는 대역.
class _ScriptedRepo implements NotificationRepository {
  _ScriptedRepo(this.items);

  List<AlertItem> items;
  bool fetchThrows = false;
  bool markReadThrows = false;
  bool markAllReadThrows = false;
  int serverUnread = 0;
  int fetchCalls = 0;

  /// 채워 두면 조회가 이것이 끝날 때까지 기다린다.
  Completer<void>? gate;

  /// 채워 두면 읽음 쓰기가 이것이 끝날 때까지 기다린다.
  Completer<void>? writeGate;

  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async {
    fetchCalls++;
    if (gate != null) await gate!.future;
    if (fetchThrows) throw StateError('네트워크 없음');
    return items;
  }

  @override
  Future<void> markRead(String id) async {
    if (writeGate != null) await writeGate!.future;
    if (markReadThrows) throw StateError('쓰기 실패');
  }

  @override
  Future<void> markAllRead() async {
    if (writeGate != null) await writeGate!.future;
    if (markAllReadThrows) throw StateError('쓰기 실패');
  }

  @override
  Future<int> unreadCount() async => serverUnread;
}

ProviderContainer _container(_ScriptedRepo repo) {
  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_realConfig),
      notificationRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

bool _readOf(ProviderContainer c, String id) => c
    .read(notificationControllerProvider)
    .items
    .firstWhere((AlertItem i) => i.id == id)
    .read;

Future<void> _pumpPage(WidgetTester tester, _ScriptedRepo repo) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_realConfig),
        notificationRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NotificationPage(),
      ),
    ),
  );
}

/// 띄운 토스트가 스스로 내려갈 때까지 시간을 흘린다 — 남은 타이머가 없어야 한다.
Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

AppButton _markAllButton(WidgetTester tester) => tester.widget<AppButton>(
  find.ancestor(of: find.text('모두 읽음'), matching: find.byType(AppButton)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationState.failedFirstLoad', () {
    test('받은 적 없이 실패하고 비어 있으면 첫 조회 실패다', () {
      const state = NotificationState(items: <AlertItem>[], failedToLoad: true);
      expect(state.failedFirstLoad, isTrue);
    });

    test('한 번 받은 뒤의 실패는 첫 조회 실패가 아니다', () {
      const state = NotificationState(
        items: <AlertItem>[],
        loaded: true,
        failedToLoad: true,
      );
      expect(state.failedFirstLoad, isFalse);
    });

    test('들고 있는 목록이 있으면 첫 조회 실패가 아니다', () {
      final state = NotificationState(
        items: <AlertItem>[_alert('a')],
        failedToLoad: true,
      );
      expect(state.failedFirstLoad, isFalse);
    });

    test('실패하지 않았으면 첫 조회 실패가 아니다', () {
      const state = NotificationState(items: <AlertItem>[]);
      expect(state.failedFirstLoad, isFalse);
    });
  });

  group('NotificationController — 재시도', () {
    test('다시 받기 시작하면 실패 표시를 내리고 첫 조회 대기로 돌아간다', () async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a')])..fetchThrows = true;
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();
      expect(
        container.read(notificationControllerProvider).failedFirstLoad,
        isTrue,
      );

      repo
        ..fetchThrows = false
        ..gate = Completer<void>();
      final Future<void> retrying = notifier.refresh();
      final NotificationState during = container.read(
        notificationControllerProvider,
      );
      expect(during.failedToLoad, isFalse);
      expect(during.failedFirstLoad, isFalse);
      expect(during.awaitingFirstLoad, isTrue);

      repo.gate!.complete();
      await retrying;
      expect(
        container.read(notificationControllerProvider).items,
        hasLength(1),
      );
    });

    test('재시도도 실패하면 다시 첫 조회 실패가 된다', () async {
      final repo = _ScriptedRepo(<AlertItem>[])..fetchThrows = true;
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      await notifier.refresh();

      final NotificationState state = container.read(
        notificationControllerProvider,
      );
      expect(state.failedFirstLoad, isTrue);
      expect(state.loading, isFalse);
    });
  });

  group('NotificationController — 읽음 쓰기 실패', () {
    test('모두 읽음이 성공하면 true 를 돌려주고 모두 읽음으로 남는다', () async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a'), _alert('b')]);
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      expect(await notifier.markAllRead(), isTrue);
      expect(container.read(notificationControllerProvider).unreadCount, 0);
    });

    test('모두 읽음이 실패하면 읽음 표시를 되돌리고 false 를 돌려준다', () async {
      final repo = _ScriptedRepo(<AlertItem>[
        _alert('a'),
        _alert('b', read: true),
        _alert('c'),
      ])..markAllReadThrows = true;
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      expect(await notifier.markAllRead(), isFalse);

      // 원래 안 읽었던 것만 안 읽음으로 돌아가고, 이미 읽은 것은 그대로다.
      expect(_readOf(container, 'a'), isFalse);
      expect(_readOf(container, 'b'), isTrue);
      expect(_readOf(container, 'c'), isFalse);
    });

    test('모두 읽음 쓰기 중에는 읽음으로 보인다', () async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a')])
        ..markAllReadThrows = true
        ..writeGate = Completer<void>();
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      final Future<bool> writing = notifier.markAllRead();
      expect(_readOf(container, 'a'), isTrue);

      repo.writeGate!.complete();
      expect(await writing, isFalse);
      expect(_readOf(container, 'a'), isFalse);
    });

    test('되돌리는 사이 목록이 바뀌었으면 지금 목록에 있는 것만 되돌린다', () async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a'), _alert('b')])
        ..markAllReadThrows = true
        ..writeGate = Completer<void>();
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      final Future<bool> writing = notifier.markAllRead();
      // 쓰기가 끝나기 전에 새로고침으로 목록이 바뀐다 — 'b' 는 사라졌다.
      repo.items = <AlertItem>[_alert('a'), _alert('n', read: true)];
      await notifier.refresh();

      repo.writeGate!.complete();
      await writing;

      final List<AlertItem> items = container
          .read(notificationControllerProvider)
          .items;
      expect(items.map((AlertItem i) => i.id), <String>['a', 'n']);
      expect(_readOf(container, 'a'), isFalse);
      // 쓰기 전에 없던 알림은 건드리지 않는다.
      expect(_readOf(container, 'n'), isTrue);
    });

    test('한 건 읽음이 실패하면 그 알림만 안 읽음으로 되돌린다', () async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a'), _alert('b')])
        ..markReadThrows = true;
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      await notifier.markRead('a');

      expect(_readOf(container, 'a'), isFalse);
      expect(_readOf(container, 'b'), isFalse);
    });

    test('이미 읽은 알림의 읽음 쓰기가 실패해도 안 읽음으로 바꾸지 않는다', () async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a', read: true)])
        ..markReadThrows = true;
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      await notifier.markRead('a');

      expect(_readOf(container, 'a'), isTrue);
    });

    test('한 건 읽음이 성공하면 읽음으로 남는다', () async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a')]);
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      await notifier.markRead('a');

      expect(_readOf(container, 'a'), isTrue);
    });
  });

  group('isAlertNavigable', () {
    test('아는 목적지가 있으면 갈 곳이 있다', () {
      expect(isAlertNavigable(_alert('a', action: _toDashboard)), isTrue);
    });

    test('action 이 없으면 갈 곳이 없다', () {
      expect(isAlertNavigable(_alert('a')), isFalse);
    });

    test('모르는 목적지면 갈 곳이 없다', () {
      expect(
        isAlertNavigable(
          _alert(
            'a',
            action: const AlertAction(label: '?', target: AlertTarget.unknown),
          ),
        ),
        isFalse,
      );
    });

    test('코치 초대 알림은 초대 ID 가 있으면 갈 곳이 있다', () {
      const AlertItem invite = AlertItem(
        id: 'i',
        title: '초대',
        body: '',
        timeAgo: '방금',
        category: AlertCategory.trainerLink,
        wireCategory: 'coach_invite',
        inviteId: 'inv-1',
      );
      expect(isAlertNavigable(invite), isTrue);
    });

    test('코치 초대 알림이라도 초대 ID 가 없으면 action 으로 판단한다', () {
      const AlertItem invite = AlertItem(
        id: 'i',
        title: '초대',
        body: '',
        timeAgo: '방금',
        category: AlertCategory.trainerLink,
        wireCategory: 'coach_invite',
      );
      expect(isAlertNavigable(invite), isFalse);
    });
  });

  group('NotificationPage — 첫 조회 실패', () {
    testWidgets('실패 안내와 재시도만 그리고 "알림이 없습니다" 는 그리지 않는다', (
      WidgetTester tester,
    ) async {
      final repo = _ScriptedRepo(<AlertItem>[])..fetchThrows = true;
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();

      expect(find.byKey(_firstLoadFailed), findsOneWidget);
      expect(find.text('최신 알림을 불러오지 못했어요'), findsOneWidget);
      expect(find.byKey(_firstLoadRetry), findsOneWidget);
      expect(find.text('알림이 없습니다'), findsNothing);
      expect(find.byKey(_retryBanner), findsNothing);
    });

    testWidgets('재시도를 누르면 실패 안내 대신 로딩 표시가 보인다', (WidgetTester tester) async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a')])..fetchThrows = true;
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();
      expect(find.byKey(_firstLoadFailed), findsOneWidget);

      repo
        ..fetchThrows = false
        ..gate = Completer<void>();
      await tester.tap(find.byKey(_firstLoadRetry));
      await tester.pump();

      expect(find.byKey(_firstLoading), findsOneWidget);
      expect(find.byKey(_firstLoadFailed), findsNothing);
      expect(find.byKey(_retryBanner), findsNothing);

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('알림 a'), findsOneWidget);
      expect(find.byKey(_firstLoading), findsNothing);
    });

    testWidgets('받아 둔 목록이 있는 채로 실패하면 목록 위에 배너를 얹는다', (
      WidgetTester tester,
    ) async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a')]);
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();

      repo.fetchThrows = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byKey(_retryBanner), findsOneWidget);
      expect(find.byKey(_firstLoadFailed), findsNothing);
      expect(find.text('알림 a'), findsOneWidget);
    });
  });

  group('NotificationPage — 모두 읽음', () {
    testWidgets('받은 쪽을 모두 읽었어도 서버 미읽음이 있으면 누를 수 있다', (
      WidgetTester tester,
    ) async {
      // 첫 쪽은 다 읽었지만 오래된 미읽음이 서버에 남아 벨에 점이 있다.
      final repo = _ScriptedRepo(<AlertItem>[_alert('a', read: true)])
        ..serverUnread = 3;
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();

      expect(_markAllButton(tester).onPressed, isNotNull);
    });

    testWidgets('받은 쪽과 서버 모두 미읽음이 없으면 누를 수 없다', (WidgetTester tester) async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a', read: true)]);
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();

      expect(_markAllButton(tester).onPressed, isNull);
    });

    testWidgets('받은 쪽에 미읽음이 있으면 서버 수를 받기 전에도 누를 수 있다', (
      WidgetTester tester,
    ) async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a')]);
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();

      expect(_markAllButton(tester).onPressed, isNotNull);
    });

    testWidgets('모두 읽음이 실패하면 읽음 표시가 되돌아가고 오류 안내가 뜬다', (
      WidgetTester tester,
    ) async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a'), _alert('b')])
        ..serverUnread = 2
        ..markAllReadThrows = true;
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();

      await tester.tap(find.text('모두 읽음'));
      await tester.pump();
      await tester.pump();

      expect(find.text('모두 읽음 처리에 실패했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('notificationPage'))),
      );
      expect(container.read(notificationControllerProvider).unreadCount, 2);
      await _drainToasts(tester);
    });

    testWidgets('모두 읽음이 성공하면 오류 안내가 없다', (WidgetTester tester) async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('a')])..serverUnread = 1;
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();

      repo.serverUnread = 0;
      await tester.tap(find.text('모두 읽음'));
      await tester.pumpAndSettle();

      expect(find.text('모두 읽음 처리에 실패했어요. 잠시 후 다시 시도해 주세요'), findsNothing);
      expect(_markAllButton(tester).onPressed, isNull);
    });
  });

  group('NotificationPage — 갈 곳 없는 알림 줄', () {
    Finder rowOf(String id) =>
        find.byKey(ValueKey<String>('notification-row-$id'));

    testWidgets('갈 곳이 있는 줄만 눌림 물결을 갖는다', (WidgetTester tester) async {
      final repo = _ScriptedRepo(<AlertItem>[
        _alert('go', action: _toDashboard),
        _alert('stay'),
      ]);
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: rowOf('go'), matching: find.byType(InkWell)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rowOf('stay'), matching: find.byType(InkWell)),
        findsNothing,
      );
    });

    testWidgets('갈 곳이 없는 줄은 버튼으로 읽히지 않는다', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final repo = _ScriptedRepo(<AlertItem>[
        _alert('go', action: _toDashboard),
        _alert('stay'),
      ]);
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();

      expect(tester.widget<Semantics>(rowOf('go')).properties.button, isTrue);
      expect(
        tester.widget<Semantics>(rowOf('stay')).properties.button,
        isFalse,
      );
      semantics.dispose();
    });

    testWidgets('갈 곳이 없는 안 읽은 줄을 누르면 읽음으로만 바뀐다', (WidgetTester tester) async {
      final repo = _ScriptedRepo(<AlertItem>[_alert('stay')]);
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('notificationPage'))),
      );

      await tester.tap(find.text('알림 stay'));
      await tester.pumpAndSettle();

      expect(_readOf(container, 'stay'), isTrue);
      expect(find.byKey(const Key('notificationPage')), findsOneWidget);
    });
  });
}
