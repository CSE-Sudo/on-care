import 'dart:async';

import 'package:flutter/widgets.dart';

/// 배지 숫자(안읽음 메시지·알림·상담 요청)를 다시 읽는 주기.
///
/// 한 자리에 모아 두는 이유는 세 배지가 같은 사이드바에 나란히 서 있어서다 —
/// 주기가 제각각이면 같은 순간에 본 세 숫자의 기준 시각이 달라진다. 열려 있는
/// 채팅 스레드(3초)·스케줄(5초)보다 느슨한 것은 의도다. 배지는 지금 보고 있는
/// 내용이 아니라 **다른 곳에서 일어난 변화**를 알리는 자리라, 몇 초의 지연보다
/// 콘솔을 종일 띄워 두는 트레이너에게 걸리는 요청 수가 더 중요하다. (#917)
const Duration badgePollInterval = Duration(seconds: 20);

/// Polls [load] while the stream has a listener and the console is
/// **visible** on screen.
///
/// "보이는가" 가 기준이다(#2869). `resumed` 와 `inactive` 는 폴링을 이어 가고,
/// `hidden`·`paused`·`detached` 에서만 멈춘다. Flutter 웹은 브라우저 창이
/// 포커스만 잃어도(blur — 듀얼 모니터에서 다른 창을 누른 경우) `inactive` 를
/// 보내는데, 그때도 트레이너 웹은 화면에 그대로 떠 있다. 예전처럼 `resumed`
/// 만 전경으로 보면 "켜 두고 곁눈질하는" 콘솔에서 채팅·배지·명단·일정이
/// 창을 다시 누를 때까지 멈췄다. 탭이 가려지거나 창이 최소화되면 웹은
/// `hidden` 을 보내므로 그때 멈춘다. 모바일의 `inactive` 는 짧은 과도
/// 상태라 이어 가도 비용이 거의 없다.
///
/// `resumed`↔`inactive` 오가기는 같은 '보임' 상태 안의 이동이라 아무것도
/// 하지 않는다 — 타이머를 다시 걸거나 즉시 한 번 더 읽지 않으므로 창을
/// 오가며 눌러도 요청이 겹치지 않는다. 가려졌다가 다시 보이면(`hidden` →
/// `inactive`/`resumed`) 그때 즉시 한 번 읽는다.
///
/// The first failure is surfaced so an initial loading error can be shown.
/// Once a value has been emitted, transient failures are kept out of the
/// stream: consumers continue showing the last good value while the next
/// poll retries. Cancelling the subscription or hiding the console stops
/// the timer immediately.
Stream<T> activePollingStream<T>({
  required Future<T> Function() load,
  required Duration? interval,
  Stream<void>? refreshes,
}) {
  late final StreamController<T> controller;
  late final _LifecycleObserver lifecycleObserver;
  Timer? timer;
  StreamSubscription<void>? refreshSubscription;
  bool cancelled = false;
  bool loading = false;
  bool refreshPending = false;
  bool hasValue = false;
  int lifecycleGeneration = 0;
  bool foreground = _isForeground(WidgetsBinding.instance.lifecycleState);

  late void Function() scheduleNext;

  Future<void> poll() async {
    if (cancelled || loading || !foreground) return;
    loading = true;
    final int requestGeneration = lifecycleGeneration;
    try {
      final T value = await load();
      if (!cancelled &&
          foreground &&
          requestGeneration == lifecycleGeneration) {
        hasValue = true;
        controller.add(value);
      }
    } catch (error, stackTrace) {
      if (!cancelled &&
          foreground &&
          requestGeneration == lifecycleGeneration &&
          !hasValue) {
        controller.addError(error, stackTrace);
      }
    } finally {
      loading = false;
      if (refreshPending && !cancelled && foreground) {
        refreshPending = false;
        unawaited(poll());
      } else {
        scheduleNext();
      }
    }
  }

  scheduleNext = () {
    timer?.cancel();
    timer = null;
    final Duration? delay = interval;
    if (cancelled || !foreground || delay == null) return;
    timer = Timer(delay, () => unawaited(poll()));
  };

  void handleLifecycle(AppLifecycleState state) {
    final bool nextForeground = _isForeground(state);
    if (foreground == nextForeground) return;
    foreground = nextForeground;
    timer?.cancel();
    timer = null;
    if (!foreground) {
      lifecycleGeneration += 1;
      refreshPending = false;
    } else if (loading) {
      refreshPending = true;
    } else {
      unawaited(poll());
    }
  }

  void refreshNow() {
    if (cancelled || !foreground) return;
    timer?.cancel();
    timer = null;
    if (loading) {
      refreshPending = true;
    } else {
      unawaited(poll());
    }
  }

  lifecycleObserver = _LifecycleObserver(handleLifecycle);
  controller = StreamController<T>(
    onListen: () {
      foreground = _isForeground(WidgetsBinding.instance.lifecycleState);
      WidgetsBinding.instance.addObserver(lifecycleObserver);
      refreshSubscription = refreshes?.listen((_) => refreshNow());
      if (foreground) unawaited(poll());
    },
    onCancel: () {
      cancelled = true;
      timer?.cancel();
      timer = null;
      unawaited(refreshSubscription?.cancel());
      refreshSubscription = null;
      WidgetsBinding.instance.removeObserver(lifecycleObserver);
      unawaited(controller.close());
    },
  );
  return controller.stream;
}

/// 폴링을 이어 갈 상태인가 — 화면에 보이는가. (#2869)
///
/// `null` 은 바인딩이 아직 상태를 받기 전(첫 프레임 전·테스트)이다.
bool _isForeground(AppLifecycleState? state) => switch (state) {
  null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
  AppLifecycleState.hidden ||
  AppLifecycleState.paused ||
  AppLifecycleState.detached => false,
};

/// [_isForeground] 를 테스트에서 상태별로 확인하는 창.
@visibleForTesting
bool pollsWhileIn(AppLifecycleState? state) => _isForeground(state);

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this.onChanged);

  final void Function(AppLifecycleState state) onChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChanged(state);
}
