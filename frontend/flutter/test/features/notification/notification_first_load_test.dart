/// 알림함 첫 조회 중에는 "알림이 없습니다" 를 그리지 않는다 — #2638.
///
/// 예전에는 컨트롤러가 첫 조회를 시작하며 `loading` 을 세웠지만 화면이 그 값을
/// 읽지 않아, 응답이 오기 전까지 빈 상태가 먼저 보였다가 목록으로 바뀌었다.
///
/// 여기서 고정하는 성질.
///
///  * 첫 조회가 끝나기 전, 목록이 비어 있으면 로딩 표시를 그린다.
///  * 서버가 빈 목록을 주면 그때 빈 상태를 그린다.
///  * 첫 조회가 실패하면 로딩 표시를 내리고 실패 안내와 재시도만 그린다 —
///    빈 상태("알림이 없습니다")는 그리지 않는다(#2877).
///  * 한 번 받은 뒤의 새로고침은 빈 상태를 로딩 표시로 바꾸지 않는다.
///  * 목/데모 시드는 처음부터 받은 목록이다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/features/notification/presentation/pages/notification_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

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

const Key _firstLoading = Key('notificationFirstLoading');
const Key _retryBanner = Key('notificationRetryBanner');
const Key _firstLoadFailed = Key('notificationFirstLoadFailed');

AlertItem _alert(String id) => AlertItem(
  id: id,
  title: '알림 $id',
  body: '본문',
  timeAgo: '방금',
  category: AlertCategory.system,
);

/// 조회를 붙잡아 두었다가 테스트가 풀어 주는 대역.
class _GatedRepo implements NotificationRepository {
  _GatedRepo(this.items);

  List<AlertItem> items;
  bool fetchThrows = false;
  int fetchCalls = 0;

  /// 채워 두면 조회가 이것이 끝날 때까지 기다린다.
  Completer<void>? gate;

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
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}

  @override
  Future<int> unreadCount() async => 0;
}

ProviderContainer _container(_GatedRepo repo, {AppConfig? config}) {
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

Future<void> _pumpPage(
  WidgetTester tester,
  _GatedRepo repo, {
  AppConfig config = _realConfig,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationState — 첫 조회 대기', () {
    test('받은 적 없이 조회 중이고 비어 있으면 첫 조회 대기다', () {
      const state = NotificationState(items: <AlertItem>[], loading: true);
      expect(state.awaitingFirstLoad, isTrue);
    });

    test('한 번 받은 뒤의 새로고침은 첫 조회 대기가 아니다', () {
      const state = NotificationState(
        items: <AlertItem>[],
        loading: true,
        loaded: true,
      );
      expect(state.awaitingFirstLoad, isFalse);
    });

    test('조회 중이 아니면 첫 조회 대기가 아니다', () {
      const state = NotificationState(items: <AlertItem>[]);
      expect(state.awaitingFirstLoad, isFalse);
    });

    test('목록이 있으면 첫 조회 대기가 아니다', () {
      final state = NotificationState(
        items: <AlertItem>[_alert('a')],
        loading: true,
      );
      expect(state.awaitingFirstLoad, isFalse);
    });

    test('copyWith 는 받은 적 있음을 지키고, 넘기면 바꾼다', () {
      const state = NotificationState(items: <AlertItem>[], loaded: true);
      expect(state.copyWith(loading: true).loaded, isTrue);
      expect(state.copyWith(loaded: false).loaded, isFalse);
    });
  });

  group('NotificationController — 받은 적 있음', () {
    test('실모드는 첫 조회가 끝나기 전까지 받은 적이 없다', () async {
      final repo = _GatedRepo(<AlertItem>[_alert('a')])
        ..gate = Completer<void>();
      final container = _container(repo);

      final NotificationState before = container.read(
        notificationControllerProvider,
      );
      expect(before.loading, isTrue);
      expect(before.loaded, isFalse);
      expect(before.awaitingFirstLoad, isTrue);

      repo.gate!.complete();
      await _settle();

      final NotificationState after = container.read(
        notificationControllerProvider,
      );
      expect(after.loading, isFalse);
      expect(after.loaded, isTrue);
      expect(after.items, hasLength(1));
      expect(after.awaitingFirstLoad, isFalse);
    });

    test('서버가 빈 목록을 줘도 받은 것이다', () async {
      final repo = _GatedRepo(<AlertItem>[]);
      final container = _container(repo);
      container.read(notificationControllerProvider);
      await _settle();

      final NotificationState state = container.read(
        notificationControllerProvider,
      );
      expect(state.loaded, isTrue);
      expect(state.items, isEmpty);
      expect(state.awaitingFirstLoad, isFalse);
    });

    test('첫 조회가 실패하면 받은 적은 없지만 대기도 끝난다', () async {
      final repo = _GatedRepo(<AlertItem>[])..fetchThrows = true;
      final container = _container(repo);
      container.read(notificationControllerProvider);
      await _settle();

      final NotificationState state = container.read(
        notificationControllerProvider,
      );
      expect(state.loaded, isFalse);
      expect(state.loading, isFalse);
      expect(state.failedToLoad, isTrue);
      expect(state.awaitingFirstLoad, isFalse);
    });

    test('실패 뒤 다시 조회해 성공하면 받은 것이 된다', () async {
      final repo = _GatedRepo(<AlertItem>[_alert('a')])..fetchThrows = true;
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();
      expect(container.read(notificationControllerProvider).loaded, isFalse);

      repo.fetchThrows = false;
      await notifier.refresh();

      final NotificationState state = container.read(
        notificationControllerProvider,
      );
      expect(state.loaded, isTrue);
      expect(state.failedToLoad, isFalse);
      expect(state.items, hasLength(1));
    });

    test('받은 뒤 새로고침 중에도 받은 적 있음이 유지된다', () async {
      final repo = _GatedRepo(<AlertItem>[]);
      final container = _container(repo);
      final notifier = container.read(notificationControllerProvider.notifier);
      await _settle();

      repo.gate = Completer<void>();
      final Future<void> refreshing = notifier.refresh();
      final NotificationState during = container.read(
        notificationControllerProvider,
      );
      expect(during.loading, isTrue);
      expect(during.loaded, isTrue);
      expect(during.awaitingFirstLoad, isFalse);

      repo.gate!.complete();
      await refreshing;
    });

    // 데모도 실서버와 같은 경로다 — 로컬 인터셉터가 답할 뿐 조회는 똑같이 한다(#2660).
    test('목/데모 모드도 첫 조회로 받는다', () async {
      final repo = _GatedRepo(<AlertItem>[_alert('a')])
        ..gate = Completer<void>();
      final container = _container(repo, config: _mockConfig);

      final NotificationState before = container.read(
        notificationControllerProvider,
      );
      expect(before.loaded, isFalse);
      expect(before.awaitingFirstLoad, isTrue);

      repo.gate!.complete();
      await _settle();

      final NotificationState after = container.read(
        notificationControllerProvider,
      );
      expect(after.loaded, isTrue);
      expect(after.items, hasLength(1));
      expect(repo.fetchCalls, 1);
    });
  });

  group('NotificationPage — 첫 로딩 표시', () {
    testWidgets('첫 조회 중에는 빈 상태 대신 로딩 표시를 그린다', (WidgetTester tester) async {
      final repo = _GatedRepo(<AlertItem>[_alert('a')])
        ..gate = Completer<void>();
      await _pumpPage(tester, repo);
      await tester.pump();

      expect(find.byKey(_firstLoading), findsOneWidget);
      expect(find.byType(AppEmptyState), findsNothing);
      expect(find.text('알림이 없습니다'), findsNothing);

      repo.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(_firstLoading), findsNothing);
      expect(find.text('알림 a'), findsOneWidget);
      expect(find.byType(AppEmptyState), findsNothing);
    });

    testWidgets('서버가 빈 목록을 주면 그때 빈 상태를 그린다', (WidgetTester tester) async {
      final repo = _GatedRepo(<AlertItem>[])..gate = Completer<void>();
      await _pumpPage(tester, repo);
      await tester.pump();
      expect(find.byKey(_firstLoading), findsOneWidget);

      repo.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(_firstLoading), findsNothing);
      expect(find.byType(AppEmptyState), findsOneWidget);
    });

    testWidgets('첫 조회가 실패하면 로딩 표시를 내리고 실패 안내와 재시도만 그린다', (
      WidgetTester tester,
    ) async {
      final repo = _GatedRepo(<AlertItem>[])
        ..fetchThrows = true
        ..gate = Completer<void>();
      await _pumpPage(tester, repo);
      await tester.pump();
      expect(find.byKey(_firstLoading), findsOneWidget);

      repo.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(_firstLoading), findsNothing);
      expect(find.byKey(_firstLoadFailed), findsOneWidget);
      // 받아 본 적이 없는데 "없다" 고 말하지 않는다(#2877).
      expect(find.text('알림이 없습니다'), findsNothing);
      // 같은 안내를 배너로 한 번 더 얹지 않는다.
      expect(find.byKey(_retryBanner), findsNothing);
    });

    testWidgets('받은 뒤 다시 조회하는 동안에는 빈 상태를 그대로 둔다', (WidgetTester tester) async {
      final repo = _GatedRepo(<AlertItem>[]);
      await _pumpPage(tester, repo);
      await tester.pumpAndSettle();
      expect(find.byType(AppEmptyState), findsOneWidget);

      // 앱이 앞으로 돌아오면 다시 조회한다. 그 사이에도 빈 상태가 유지되어야 한다.
      repo.gate = Completer<void>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.byKey(_firstLoading), findsNothing);
      expect(find.byType(AppEmptyState), findsOneWidget);

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AppEmptyState), findsOneWidget);
    });

    testWidgets('데모 모드도 첫 조회 중에는 로딩 표시를 그린다', (WidgetTester tester) async {
      final repo = _GatedRepo(<AlertItem>[_alert('a')])
        ..gate = Completer<void>();
      await _pumpPage(tester, repo, config: _mockConfig);
      await tester.pump();

      expect(find.byKey(_firstLoading), findsOneWidget);
      expect(find.byType(AppEmptyState), findsNothing);

      repo.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(_firstLoading), findsNothing);
      expect(find.text('알림 a'), findsOneWidget);
    });
  });
}
