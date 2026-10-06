/// 콘솔을 보지 않는 동안의 새 알림 — 탭 제목 숫자·화면 구석 알림. (#3285)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/poll_intervals.dart';
import 'package:oncare_trainer/features/desktop_alerts/data/browser_alerts.dart';
import 'package:oncare_trainer/features/desktop_alerts/data/desktop_alert_preference.dart';
import 'package:oncare_trainer/features/desktop_alerts/presentation/desktop_alerts_host.dart';
import 'package:oncare_trainer/features/desktop_alerts/presentation/tab_unread_title.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 띄운 알림을 모으고, 권한·포커스를 테스트가 정하는 브라우저.
class _FakeAlerts implements BrowserAlerts {
  BrowserAlertPermission granted = BrowserAlertPermission.granted;
  bool focused = false;
  final List<BrowserAlert> shown = <BrowserAlert>[];
  final List<bool> dots = <bool>[];

  @override
  BrowserAlertPermission get permission => granted;

  @override
  Future<BrowserAlertPermission> requestPermission() async => granted;

  @override
  void show(BrowserAlert alert, {required void Function() onClick}) =>
      shown.add(alert);

  @override
  bool get pageFocused => focused;

  @override
  void setIconDot({required bool on}) => dots.add(on);
}

/// 알림 목록과 미읽음 수를 테스트가 바꾸는 저장소.
class _FakeRepository implements TrainerNotificationRepository {
  final StreamController<int> unread = StreamController<int>.broadcast();
  List<TrainerNotification> items = <TrainerNotification>[];
  int fetches = 0;
  int unreadReads = 0;
  int hiddenUnread = 0;

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async {
    fetches++;
    return TrainerNotificationPage(items: items);
  }

  @override
  Stream<TrainerNotificationPage> watch() =>
      Stream<TrainerNotificationPage>.fromFuture(fetch());

  @override
  Future<int> unreadCount() async {
    unreadReads++;
    return hiddenUnread;
  }

  @override
  Stream<int> watchUnreadCount() => unread.stream;

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;
}

TrainerNotification _noti(
  String id, {
  TrainerNotificationKind kind = TrainerNotificationKind.reservation,
  String title = '새 예약이 들어왔어요',
  String body = '박성호 회원 · 10월 7일 (화) 16:00',
  bool read = false,
}) => TrainerNotification(
  id: id,
  title: title,
  body: body,
  kind: kind,
  read: read,
  createdAt: DateTime.utc(2026, 10, 7, 7),
  timeAgo: '방금 전',
);

void main() {
  late _FakeAlerts alerts;
  late _FakeRepository repository;
  late ProviderContainer container;

  setUp(() {
    alerts = _FakeAlerts();
    repository = _FakeRepository();
    container = ProviderContainer(
      overrides: <Override>[
        browserAlertsProvider.overrideWithValue(alerts),
        trainerNotificationRepositoryProvider.overrideWithValue(repository),
        desktopAlertPreferenceProvider.overrideWith(
          (ref) => DesktopAlertPreference(null),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await repository.unread.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  Future<void> pumpHost(WidgetTester tester, {bool enabled = true}) async {
    await container
        .read(desktopAlertPreferenceProvider.notifier)
        .set(enabled: enabled);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DesktopAlertsHost(child: SizedBox()),
        ),
      ),
    );
    await settle(tester);
  }

  /// 배지 폴링이 새 미읽음 수를 받은 것처럼.
  Future<void> unreadBecomes(WidgetTester tester, int count) async {
    repository.unread.add(count);
    await settle(tester);
  }

  testWidgets('다른 곳을 보는 중 새 알림이 오면 화면 구석에 띄운다', (tester) async {
    repository.items = <TrainerNotification>[_noti('old')];
    await pumpHost(tester);
    await unreadBecomes(tester, 1);

    repository.items = <TrainerNotification>[_noti('new'), _noti('old')];
    await unreadBecomes(tester, 2);

    // 켜 둘 때 이미 있던 알림은 띄우지 않는다.
    expect(alerts.shown.map((BrowserAlert a) => a.tag), <String>['oncare-new']);
    expect(alerts.shown.single.title, '새 예약이 들어왔어요');
    expect(alerts.shown.single.body, '박성호 회원 · 10월 7일 (화) 16:00');
  });

  testWidgets('메시지 알림에는 메시지 내용을 싣지 않는다', (tester) async {
    await pumpHost(tester);
    await unreadBecomes(tester, 0);

    repository.items = <TrainerNotification>[
      _noti(
        'msg',
        kind: TrainerNotificationKind.message,
        title: '김민수 회원의 메시지',
        body: '어제부터 무릎이 아파요',
      ),
    ];
    await unreadBecomes(tester, 1);

    expect(alerts.shown.single.title, '김민수 회원의 메시지');
    expect(alerts.shown.single.body, '새 메시지가 왔어요');
    expect(alerts.shown.single.body, isNot(contains('무릎')));
  });

  testWidgets('이 탭을 보고 있으면 띄우지 않는다 — 알림 종이 알린다', (tester) async {
    alerts.focused = true;
    await pumpHost(tester);
    await unreadBecomes(tester, 0);

    repository.items = <TrainerNotification>[_noti('new')];
    await unreadBecomes(tester, 1);
    expect(alerts.shown, isEmpty);

    // 본 알림은 나중에 다른 곳을 볼 때도 다시 띄우지 않는다.
    alerts.focused = false;
    repository.items = <TrainerNotification>[_noti('next'), _noti('new')];
    await unreadBecomes(tester, 2);
    expect(alerts.shown.map((BrowserAlert a) => a.tag), <String>[
      'oncare-next',
    ]);
  });

  testWidgets('이 브라우저 설정을 꺼 두면 띄우지도 목록을 받지도 않는다', (tester) async {
    await pumpHost(tester, enabled: false);
    await unreadBecomes(tester, 0);
    repository.items = <TrainerNotification>[_noti('new')];
    await unreadBecomes(tester, 1);

    expect(alerts.shown, isEmpty);
    expect(repository.fetches, 0);
  });

  testWidgets('권한이 없으면 띄우지 않는다', (tester) async {
    alerts.granted = BrowserAlertPermission.denied;
    await pumpHost(tester);
    await unreadBecomes(tester, 0);
    repository.items = <TrainerNotification>[_noti('new')];
    await unreadBecomes(tester, 1);

    expect(alerts.shown, isEmpty);
  });

  testWidgets('한 번에 넷 이상이면 하나로 묶는다', (tester) async {
    await pumpHost(tester);
    await unreadBecomes(tester, 0);

    repository.items = <TrainerNotification>[
      for (int i = 0; i < 5; i++) _noti('n$i'),
    ];
    await unreadBecomes(tester, 5);

    expect(alerts.shown.single.tag, 'oncare-summary');
    expect(alerts.shown.single.title, '새 알림 5건');
  });

  testWidgets('탭 제목 숫자와 아이콘 점은 설정과 상관없이 미읽음 수를 따른다', (tester) async {
    await pumpHost(tester, enabled: false);

    await unreadBecomes(tester, 3);
    expect(container.read(tabUnreadCountProvider), 3);
    expect(alerts.dots.last, isTrue);

    await unreadBecomes(tester, 0);
    expect(container.read(tabUnreadCountProvider), 0);
    expect(alerts.dots.last, isFalse);
  });

  testWidgets('탭이 가려진 동안에는 느리게 다시 읽어 새 알림을 띄운다', (tester) async {
    await pumpHost(tester);
    await unreadBecomes(tester, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await settle(tester);

    repository.items = <TrainerNotification>[_noti('new')];
    repository.hiddenUnread = 1;
    await tester.pump(hiddenAlertPollInterval);
    await settle(tester);

    expect(repository.unreadReads, 1);
    expect(container.read(tabUnreadCountProvider), 1);
    expect(alerts.shown.single.tag, 'oncare-new');

    // 다시 보이면 느린 읽기를 멈춘다 — 배지 폴링이 이어받는다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    await tester.pump(hiddenAlertPollInterval * 2);
    expect(repository.unreadReads, 1);
  });

  testWidgets('콘솔을 떠나면 탭 제목 숫자를 지운다', (tester) async {
    await pumpHost(tester, enabled: false);
    await unreadBecomes(tester, 2);
    expect(container.read(tabUnreadCountProvider), 2);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await settle(tester);

    expect(container.read(tabUnreadCountProvider), 0);
    expect(alerts.dots.last, isFalse);
  });

  group('탭 제목', () {
    test('안 읽은 수가 있으면 앞에 붙이고, 100건 이상은 99+', () {
      expect(TabUnreadTitle.titleFor('On-Care 트레이너', 0), 'On-Care 트레이너');
      expect(TabUnreadTitle.titleFor('On-Care 트레이너', 3), '(3) On-Care 트레이너');
      expect(
        TabUnreadTitle.titleFor('On-Care 트레이너', 120),
        '(99+) On-Care 트레이너',
      );
    });
  });

  group('알림 문장', () {
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));

    test('메시지가 아니면 알림함과 같은 문장이다', () {
      final BrowserAlert alert = desktopAlertFor(l, _noti('r1'));
      expect(alert.title, '새 예약이 들어왔어요');
      expect(alert.body, '박성호 회원 · 10월 7일 (화) 16:00');
      expect(alert.tag, 'oncare-r1');
    });
  });
}
