import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_core/active_polling_stream.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/poll_intervals.dart';
import 'package:oncare_trainer/features/desktop_alerts/data/browser_alerts.dart';
import 'package:oncare_trainer/features/desktop_alerts/data/desktop_alert_preference.dart';
import 'package:oncare_trainer/features/desktop_alerts/presentation/tab_unread_title.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/pages/notifications_page.dart';
import 'package:oncare_trainer/features/notifications/presentation/trainer_notification_text.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 콘솔을 보지 않는 동안 새 알림을 알린다(#3285).
///
/// * **탭 제목 숫자·아이콘 빨간 점** — 알림함(종)의 안 읽은 수. 권한이 필요 없어
///   늘 켜져 있다. 종류별 수신 설정(#2420)으로 끈 종류는 알림함에 생기지 않으므로
///   숫자에도 들어가지 않는다.
/// * **화면 구석 알림** — "이 브라우저에서 알림 받기"를 켜고 권한을 허용했을 때,
///   트레이너가 이 탭을 보고 있지 않으면(다른 탭·다른 프로그램) 새 알림을 띄운다.
///   보고 있으면 알림 종이 알리므로 띄우지 않는다.
///
/// 배지 폴링은 탭이 가려지면 멈춘다. 그래서 가려진 동안만
/// [hiddenAlertPollInterval] 마다 안 읽은 수를 다시 읽는다. 보이는 동안은 배지
/// 폴링([trainerUnreadBadgeProvider])을 그대로 따라가 요청을 더하지 않는다.
///
/// 숫자가 늘면 첫 쪽을 받아, 처음 본 안 읽은 알림만 띄운다. 켜는 순간 이미 있던
/// 알림은 '본 것' 으로 두어 한꺼번에 쏟아지지 않게 한다. 한 번에 넷 이상이면
/// "새 알림 N건" 하나로 묶는다.
///
/// **메시지 알림에는 내용을 싣지 않는다.** 센터 PC 화면 구석에 떠 옆 사람도 볼 수
/// 있고, 회원 메시지에는 몸 상태 이야기가 들어 있을 수 있다 — 건강 메모를 알림
/// 미리보기에 싣지 않는 규칙(#2619)과 같은 이유다. 누르면 그 대화가 열린다.
class DesktopAlertsHost extends ConsumerStatefulWidget {
  const DesktopAlertsHost({required this.child, super.key});

  final Widget child;

  /// 한 번에 따로 띄우는 최대 건수. 넘으면 하나로 묶는다.
  static const int maxSeparateAlerts = 3;

  @override
  ConsumerState<DesktopAlertsHost> createState() => _DesktopAlertsHostState();
}

class _DesktopAlertsHostState extends ConsumerState<DesktopAlertsHost>
    with WidgetsBindingObserver {
  late final StateController<int> _titleCount;
  late final BrowserAlerts _alerts;
  bool _visible = _isVisible(WidgetsBinding.instance.lifecycleState);
  Timer? _hiddenPoll;

  /// 마지막으로 본 안 읽은 수. 늘었는지 가르는 기준이다.
  int? _lastCount;

  /// 이미 본 알림 id. `null` 이면 아직 첫 쪽을 받아 두지 않았다.
  Set<String>? _seen;

  /// 첫 쪽 받기를 한 줄로 세운다 — 겹치면 같은 알림을 두 번 띄운다.
  Future<void> _queue = Future<void>.value();

  static bool _isVisible(AppLifecycleState? state) =>
      pollsWhileIn(state, keepPollingWhileInactive: true);

  @override
  void initState() {
    super.initState();
    _titleCount = ref.read(tabUnreadCountProvider.notifier);
    _alerts = ref.read(browserAlertsProvider);
    WidgetsBinding.instance.addObserver(this);
    ref
      ..listenManual<int?>(trainerUnreadBadgeProvider, (_, int? next) {
        if (next != null) _onCount(next);
      }, fireImmediately: true)
      ..listenManual<bool>(desktopAlertPreferenceProvider, (_, bool on) {
        if (on) _enqueue(_seed);
      }, fireImmediately: true)
      // 계정이 바뀌면 저장소가 새로 만들어진다 — 앞 계정의 기록을 버린다.
      ..listenManual<TrainerNotificationRepository>(
        trainerNotificationRepositoryProvider,
        (_, _) => _reset(),
      );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool visible = _isVisible(state);
    if (visible == _visible) return;
    _visible = visible;
    _hiddenPoll?.cancel();
    _hiddenPoll = null;
    if (!visible) {
      _hiddenPoll = Timer.periodic(
        hiddenAlertPollInterval,
        (_) => unawaited(_readHidden()),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hiddenPoll?.cancel();
    // 콘솔을 떠나면(로그아웃) 탭 제목·아이콘을 원래대로. 트리를 정리하는 중에
    // provider 를 바꾸지 않도록 한 박자 늦춘다.
    final StateController<int> titleCount = _titleCount;
    final BrowserAlerts alerts = _alerts;
    scheduleMicrotask(() {
      alerts.setIconDot(on: false);
      try {
        titleCount.state = 0;
      } on StateError {
        // 앱 전체가 함께 내려간 경우(테스트 끝 등) — 되돌릴 제목도 없다.
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _reset() {
    _lastCount = null;
    _seen = null;
    if (ref.read(desktopAlertPreferenceProvider)) _enqueue(_seed);
  }

  bool get _active =>
      ref.read(desktopAlertPreferenceProvider) &&
      _alerts.permission == BrowserAlertPermission.granted;

  TrainerNotificationRepository get _repository =>
      ref.read(trainerNotificationRepositoryProvider);

  void _enqueue(Future<void> Function() task) {
    _queue = _queue.then((_) async {
      if (!mounted) return;
      try {
        await task();
      } on Object {
        // 잠깐의 실패 — 다음 숫자 변화나 다음 주기에 다시 본다.
      }
    });
  }

  void _onCount(int count) {
    // 처음 그릴 때(listenManual 의 fireImmediately)도 지나므로 provider 는 한
    // 박자 늦게 바꾼다.
    scheduleMicrotask(() {
      if (!mounted) return;
      _titleCount.state = count;
      _alerts.setIconDot(on: count > 0);
    });
    final int? previous = _lastCount;
    _lastCount = count;
    if (previous != null && count > previous) _enqueue(_checkNew);
  }

  Future<void> _readHidden() async {
    if (!mounted || _visible) return;
    try {
      _onCount(await _repository.unreadCount());
    } on Object {
      // 다음 주기에 다시 읽는다.
    }
  }

  /// 지금 있는 알림을 '본 것' 으로 받아 둔다.
  Future<void> _seed() async {
    if (!_active || _seen != null) return;
    final TrainerNotificationPage page = await _repository.fetch();
    _seen = <String>{for (final TrainerNotification n in page.items) n.id};
  }

  Future<void> _checkNew() async {
    if (!_active) return;
    final Set<String>? seen = _seen;
    if (seen == null) {
      // 켠 뒤 처음 — 지금 있는 것은 '본 것' 이다.
      await _seed();
      return;
    }
    final TrainerNotificationPage page = await _repository.fetch();
    final List<TrainerNotification> fresh = <TrainerNotification>[
      for (final TrainerNotification n in page.items)
        if (!n.read && !seen.contains(n.id)) n,
    ];
    seen.addAll(page.items.map((TrainerNotification n) => n.id));
    if (fresh.isEmpty || !mounted || _alerts.pageFocused) return;
    _show(fresh);
  }

  void _show(List<TrainerNotification> fresh) {
    final AppLocalizations l = AppLocalizations.of(context);
    if (fresh.length > DesktopAlertsHost.maxSeparateAlerts) {
      _alerts.show(
        (
          title: l.desktopAlertSummaryTitle(fresh.length),
          body: l.desktopAlertSummaryBody,
          tag: 'oncare-summary',
        ),
        onClick: () {
          if (mounted) GoRouter.of(context).go(AppRoutes.notifications);
        },
      );
      return;
    }
    // 첫 쪽은 최신순이다. 오래된 것부터 띄워 가장 새 알림이 맨 위에 온다.
    for (final TrainerNotification n in fresh.reversed) {
      _alerts.show(
        desktopAlertFor(l, n),
        onClick: () {
          if (mounted) NotificationsPage.open(context, n);
        },
      );
    }
  }
}

/// 알림 한 건의 화면 구석 알림 문장. 알림함과 같은 문장을 쓰되, 메시지는 내용을
/// 싣지 않는다(#2619 와 같은 이유).
@visibleForTesting
BrowserAlert desktopAlertFor(AppLocalizations l, TrainerNotification n) {
  final TrainerNotificationText text = trainerNotificationText(l, n);
  return (
    title: text.title,
    body: n.kind == TrainerNotificationKind.message
        ? l.desktopAlertMessageBody
        : text.body,
    tag: 'oncare-${n.id}',
  );
}
