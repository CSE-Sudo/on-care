/// 알림함 이어 불러오기 화면. (#2293)
///
/// 첫 쪽(100건)보다 오래된 알림을 목록 끝에서 이어 받는다 — 끝에 닿으면
/// 알아서, 또는 "지난 알림 더 보기" 로. 받는 중·실패·끝 상태를 보이고, 읽음
/// 처리는 이어 받은 쪽에도 그대로 비친다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

const ValueKey<String> _loadMoreKey = ValueKey<String>(
  'notifications-load-more',
);
const ValueKey<String> _retryKey = ValueKey<String>(
  'notifications-load-more-retry',
);
const ValueKey<String> _loadingKey = ValueKey<String>(
  'notifications-loading-more',
);
const ValueKey<String> _endKey = ValueKey<String>('notifications-end');

TrainerNotification _n(String id, {bool read = false}) => TrainerNotification(
  id: id,
  title: '알림 $id',
  body: '',
  kind: TrainerNotificationKind.other,
  read: read,
  createdAt: DateTime.utc(2026, 9, 1, 9),
  timeAgo: '',
);

TrainerNotificationCursor _c(String id) => TrainerNotificationCursor(
  before: '2026-09-01T09:00:00+00:00',
  beforeId: id,
);

/// 서버처럼 쪽을 나눠 주는 저장소. 읽음 처리는 모든 쪽에 반영된다.
class _PagedRepo implements TrainerNotificationRepository {
  _PagedRepo(this._pages);

  /// 쪽 목록 — 각 쪽의 마지막 알림 id 가 다음 쪽 커서다.
  final List<List<String>> _pages;
  final Set<String> _read = <String>{};
  final List<TrainerNotificationCursor?> calls = <TrainerNotificationCursor?>[];
  final List<String> readCalls = <String>[];
  int readAllCalls = 0;
  int failuresLeft = 0;
  Completer<void>? gate;

  int get _total => _pages.fold<int>(0, (n, p) => n + p.length);

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async {
    calls.add(before);
    if (before != null) {
      if (gate != null) await gate!.future;
      if (failuresLeft > 0) {
        failuresLeft--;
        throw StateError('network down');
      }
    }
    final int index = before == null
        ? 0
        : _pages.indexWhere((p) => p.last == before.beforeId) + 1;
    if (index >= _pages.length) return TrainerNotificationPage.empty;
    final List<String> ids = _pages[index];
    return TrainerNotificationPage(
      items: <TrainerNotification>[
        for (final String id in ids) _n(id, read: _read.contains(id)),
      ],
      next: index + 1 < _pages.length ? _c(ids.last) : null,
    );
  }

  @override
  Stream<TrainerNotificationPage> watch() =>
      Stream<TrainerNotificationPage>.fromFuture(fetch());

  /// 서버 배지처럼 쪽과 무관하게 전체를 센다.
  @override
  Future<int> unreadCount() async => _total - _read.length;

  @override
  Stream<int> watchUnreadCount() => Stream<int>.fromFuture(unreadCount());

  @override
  Future<void> markRead(String id) async {
    readCalls.add(id);
    _read.add(id);
  }

  @override
  Future<int> markAllRead() async {
    readAllCalls++;
    final int before = _read.length;
    for (final List<String> p in _pages) {
      _read.addAll(p);
    }
    return _read.length - before;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _PagedRepo repo, {
  Locale locale = const Locale('ko'),
}) async {
  await pumpTrainerApp(
    tester,
    token: 'demo-token',
    at: AppRoutes.notifications,
    locale: locale,
    extraOverrides: <Override>[
      trainerNotificationRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

bool _unread(WidgetTester tester, String id) => tester
    .widget<AppListRow>(find.byKey(ValueKey<String>('notification-$id')))
    .unread;

void main() {
  testWidgets('한 쪽으로 끝나는 알림함에는 아래에 아무것도 붙지 않는다', (tester) async {
    final repo = _PagedRepo(<List<String>>[
      <String>['a', 'b'],
    ]);
    await _pump(tester, repo);

    expect(find.text('알림 a'), findsOneWidget);
    expect(find.byKey(_loadMoreKey), findsNothing);
    expect(find.byKey(_endKey), findsNothing);
    expect(find.byKey(_retryKey), findsNothing);
  });

  testWidgets('더 있으면 "지난 알림 더 보기" 가 보인다', (tester) async {
    final repo = _PagedRepo(<List<String>>[
      <String>['a', 'b'],
      <String>['c'],
    ]);
    await _pump(tester, repo);

    expect(find.byKey(_loadMoreKey), findsOneWidget);
    expect(find.text(_ko.notifLoadMore), findsOneWidget);
    expect(find.text('알림 c'), findsNothing);
  });

  testWidgets('누르면 다음 쪽을 이어 붙이고 끝에 닿으면 끝을 알린다', (tester) async {
    final repo = _PagedRepo(<List<String>>[
      <String>['a', 'b'],
      <String>['c', 'd'],
      <String>['e'],
    ]);
    await _pump(tester, repo);

    await tester.tap(find.byKey(_loadMoreKey));
    await settle(tester);

    expect(find.text('알림 c'), findsOneWidget);
    expect(find.text('알림 d'), findsOneWidget);
    expect(repo.calls.last, _c('b'));
    expect(find.byKey(_loadMoreKey), findsOneWidget);

    await tester.tap(find.byKey(_loadMoreKey));
    await settle(tester);

    expect(find.text('알림 e'), findsOneWidget);
    expect(repo.calls.last, _c('d'));
    expect(find.byKey(_loadMoreKey), findsNothing);
    expect(find.byKey(_endKey), findsOneWidget);
    expect(find.text(_ko.notifNoEarlier), findsOneWidget);
    // 같은 알림이 두 줄로 그려지지 않는다.
    expect(find.text('알림 a'), findsOneWidget);
    expect(find.text('알림 b'), findsOneWidget);
  });

  testWidgets('받는 중에는 버튼 대신 로딩을 보인다', (tester) async {
    final repo = _PagedRepo(<List<String>>[
      <String>['a'],
      <String>['b'],
    ])..gate = Completer<void>();
    await _pump(tester, repo);

    await tester.tap(find.byKey(_loadMoreKey));
    await tester.pump();

    expect(find.byKey(_loadingKey), findsOneWidget);
    expect(find.byKey(_loadMoreKey), findsNothing);

    repo.gate!.complete();
    await settle(tester);

    expect(find.byKey(_loadingKey), findsNothing);
    expect(find.text('알림 b'), findsOneWidget);
  });

  testWidgets('실패하면 목록은 그대로 두고 재시도를 보인다', (tester) async {
    final repo = _PagedRepo(<List<String>>[
      <String>['a'],
      <String>['b'],
    ])..failuresLeft = 1;
    await _pump(tester, repo);

    await tester.tap(find.byKey(_loadMoreKey));
    await settle(tester);

    expect(find.text('알림 a'), findsOneWidget);
    expect(find.text(_ko.notifLoadMoreFailed), findsOneWidget);
    expect(find.byKey(_retryKey), findsOneWidget);
    expect(find.text('network down'), findsNothing);

    await tester.tap(find.byKey(_retryKey));
    await settle(tester);

    expect(find.text('알림 b'), findsOneWidget);
    expect(find.byKey(_retryKey), findsNothing);
    expect(find.byKey(_endKey), findsOneWidget);
  });

  testWidgets('목록 끝으로 스크롤하면 알아서 이어 받는다', (tester) async {
    final List<String> firstPage = <String>[
      for (var i = 0; i < 40; i++) 'p1-$i',
    ];
    final repo = _PagedRepo(<List<String>>[
      firstPage,
      <String>['p2-0'],
    ]);
    await _pump(tester, repo);
    expect(repo.calls, <TrainerNotificationCursor?>[null]);

    await tester.dragUntilVisible(
      find.text('알림 p1-39'),
      find.byType(ListView),
      const Offset(0, -400),
    );
    await settle(tester);

    expect(repo.calls, contains(_c('p1-39')));
    await tester.dragUntilVisible(
      find.text('알림 p2-0'),
      find.byType(ListView),
      const Offset(0, -400),
    );
    expect(find.text('알림 p2-0'), findsOneWidget);
  });

  testWidgets('실패한 뒤에는 스크롤로 되풀이하지 않는다', (tester) async {
    final List<String> firstPage = <String>[
      for (var i = 0; i < 40; i++) 'p1-$i',
    ];
    final repo = _PagedRepo(<List<String>>[
      firstPage,
      <String>['p2-0'],
    ])..failuresLeft = 5;
    await _pump(tester, repo);

    await tester.dragUntilVisible(
      find.byKey(_retryKey),
      find.byType(ListView),
      const Offset(0, -400),
    );
    await settle(tester);
    final int afterFailure = repo.calls.length;
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await settle(tester);

    expect(repo.calls.length, afterFailure);
    expect(repo.calls.where((c) => c != null), hasLength(1));
  });

  testWidgets('배지 수는 첫 쪽이 아니라 전체를 센다', (tester) async {
    final repo = _PagedRepo(<List<String>>[
      <String>['a', 'b'],
      <String>['c', 'd', 'e'],
    ]);
    await _pump(tester, repo);

    expect(find.text(_ko.notifUnreadCount(5)), findsOneWidget);
  });

  testWidgets('이어 받은 알림을 누르면 읽음 처리되고 미읽음 표시가 빠진다', (tester) async {
    final repo = _PagedRepo(<List<String>>[
      <String>['a'],
      <String>['old'],
    ]);
    await _pump(tester, repo);
    await tester.tap(find.byKey(_loadMoreKey));
    await settle(tester);
    expect(_unread(tester, 'old'), isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('notification-old')));
    await settle(tester);

    expect(repo.readCalls, <String>['old']);
    expect(_unread(tester, 'old'), isFalse);
    expect(find.text(_ko.notifUnreadCount(1)), findsOneWidget);
  });

  testWidgets('모두 읽음은 이어 받은 쪽까지 읽음으로 보인다', (tester) async {
    final repo = _PagedRepo(<List<String>>[
      <String>['a', 'b'],
      <String>['c', 'd'],
    ]);
    await _pump(tester, repo);
    await tester.tap(find.byKey(_loadMoreKey));
    await settle(tester);

    await tester.tap(find.text(_ko.notifReadAll));
    await settle(tester);

    expect(repo.readAllCalls, 1);
    for (final String id in <String>['a', 'b', 'c', 'd']) {
      expect(_unread(tester, id), isFalse, reason: id);
    }
    expect(find.text(_ko.notifAllRead), findsOneWidget);
    // 이어 받은 쪽이 비워지지 않는다 — 다시 스크롤할 필요가 없다.
    expect(find.text('알림 d'), findsOneWidget);
  });

  testWidgets('영어 화면은 이어 받기 문구도 영어다', (tester) async {
    final repo = _PagedRepo(<List<String>>[
      <String>['a'],
      <String>['b'],
      <String>['c'],
    ])..failuresLeft = 1;
    await _pump(tester, repo, locale: const Locale('en'));

    expect(find.text(_en.notifLoadMore), findsOneWidget);
    expect(find.text(_ko.notifLoadMore), findsNothing);

    await tester.tap(find.byKey(_loadMoreKey));
    await settle(tester);
    expect(find.text(_en.notifLoadMoreFailed), findsOneWidget);
    expect(find.text(_en.actionRetry), findsWidgets);

    await tester.tap(find.byKey(_retryKey));
    await settle(tester);
    await tester.tap(find.byKey(_loadMoreKey));
    await settle(tester);

    expect(find.text(_en.notifNoEarlier), findsOneWidget);
    expect(find.text(_ko.notifNoEarlier), findsNothing);
  });

  test('영어 문구가 비어 있거나 한국어로 남지 않았다', () {
    final RegExp hangul = RegExp('[가-힣]');
    for (final String text in <String>[
      _en.notifLoadMore,
      _en.notifLoadMoreFailed,
      _en.notifNoEarlier,
    ]) {
      expect(text, isNotEmpty);
      expect(hangul.hasMatch(text), isFalse, reason: text);
    }
    for (final String text in <String>[
      _ko.notifLoadMore,
      _ko.notifLoadMoreFailed,
      _ko.notifNoEarlier,
    ]) {
      expect(hangul.hasMatch(text), isTrue, reason: text);
    }
  });
}
