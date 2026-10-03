import 'dart:async';

import 'package:flutter/widgets.dart';

/// Polls [load] while the stream has a listener and the application is in
/// the foreground.
///
/// The first failure is surfaced so an initial loading error can be shown.
/// Once a value has been emitted, transient failures are kept out of the
/// stream: consumers continue showing the last good value while the next
/// poll retries. Cancelling the subscription or backgrounding the app stops
/// the timer immediately.
///
/// 회원 앱과 트레이너 웹이 이 함수 하나를 함께 쓴다(#2907). 주기는 각 앱이
/// 상수로 넘긴다(예: 트레이너 웹 배지의 `badgePollInterval`).
///
/// [interval] 이 null 이면 주기 폴링 없이 구독할 때·다시 보일 때·[refreshes] 가
/// 올 때만 읽는다.
///
/// [refreshes] 에 이벤트가 오면 주기를 기다리지 않고 바로 다시 읽는다(읽는
/// 중이면 끝난 뒤 한 번 더).
///
/// [surfaceError] 가 참인 오류는 값을 받은 뒤에도 흘려보낸다 — 잠깐의 실패가
/// 아니라 상태가 바뀌었다는 신호(예: 담당 해제로 대화가 404, #2843)라 마지막
/// 값을 붙들고 있으면 안 되는 경우다.
///
/// [keepPollingWhileInactive] 는 "전경" 의 기준을 고른다(#2869).
///
///  * 거짓(기본, 회원 앱): `resumed` 일 때만 폴링한다.
///  * 참(트레이너 웹): "화면에 보이는가" 가 기준이다. `resumed` 와 `inactive` 는
///    폴링을 이어 가고, `hidden`·`paused`·`detached` 에서만 멈춘다. Flutter 웹은
///    브라우저 창이 포커스만 잃어도(blur — 듀얼 모니터에서 다른 창을 누른 경우)
///    `inactive` 를 보내는데, 그때도 콘솔은 화면에 그대로 떠 있다. `resumed` 만
///    전경으로 보면 "켜 두고 곁눈질하는" 콘솔에서 채팅·배지·명단·일정이 창을
///    다시 누를 때까지 멈췄다. 탭이 가려지거나 창이 최소화되면 웹은 `hidden` 을
///    보내므로 그때 멈춘다. `resumed`↔`inactive` 오가기는 같은 '보임' 상태 안의
///    이동이라 아무것도 하지 않는다 — 타이머를 다시 걸거나 즉시 한 번 더 읽지
///    않으므로 창을 오가며 눌러도 요청이 겹치지 않는다. 가려졌다가 다시
///    보이면(`hidden` → `inactive`/`resumed`) 그때 즉시 한 번 읽는다.
Stream<T> activePollingStream<T>({
  required Future<T> Function() load,
  required Duration? interval,
  Stream<void>? refreshes,
  bool Function(Object error)? surfaceError,
  bool keepPollingWhileInactive = false,
}) {
  bool isForeground(AppLifecycleState? state) => pollsWhileIn(
    state,
    keepPollingWhileInactive: keepPollingWhileInactive,
  );

  late final StreamController<T> controller;
  late final _LifecycleObserver lifecycleObserver;
  Timer? timer;
  StreamSubscription<void>? refreshSubscription;
  bool cancelled = false;
  bool loading = false;
  bool refreshPending = false;
  bool hasValue = false;
  int lifecycleGeneration = 0;
  bool foreground = isForeground(WidgetsBinding.instance.lifecycleState);

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
          (!hasValue || (surfaceError?.call(error) ?? false))) {
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
    final bool nextForeground = isForeground(state);
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
      foreground = isForeground(WidgetsBinding.instance.lifecycleState);
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

/// 폴링을 이어 갈 상태인가. [activePollingStream] 의 `keepPollingWhileInactive`
/// 와 같은 기준이다.
///
/// `null` 은 바인딩이 아직 상태를 받기 전(첫 프레임 전·테스트)이다.
///
/// 스트림이 아닌 주기 작업도 같은 기준을 써야 한다 — `VisiblePeriodicTimer`
/// 가 이 함수로 멈추고 다시 건다(#3013).
bool pollsWhileIn(
  AppLifecycleState? state, {
  bool keepPollingWhileInactive = false,
}) => switch (state) {
  null || AppLifecycleState.resumed => true,
  AppLifecycleState.inactive => keepPollingWhileInactive,
  AppLifecycleState.hidden ||
  AppLifecycleState.paused ||
  AppLifecycleState.detached => false,
};

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this.onChanged);

  final void Function(AppLifecycleState state) onChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChanged(state);
}
