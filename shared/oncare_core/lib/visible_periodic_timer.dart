import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:oncare_core/active_polling_stream.dart';

/// 화면이 보이는 동안만 [interval] 마다 [onTick] 을 부르는 주기 타이머(#3013).
///
/// [activePollingStream] 과 **같은 보임 기준**([pollsWhileIn])을 쓴다. 스트림이
/// 아닌 주기 작업(예: 트레이너 웹 회원 상세가 FutureProvider 들을 다시 읽는 일)이
/// `Timer.periodic` 을 따로 걸면, 탭이 가려진 동안에도 혼자 요청을 보내 같은 앱
/// 안에서 폴링 기준이 둘로 갈린다.
///
///  * 가려지면(보임 → 안 보임) 타이머를 끊는다.
///  * 다시 보이면(안 보임 → 보임) 곧바로 [onTick] 을 한 번 부르고 주기를 다시
///    건다 — 가려진 동안 놓친 변화를 기다리지 않고 맞춘다.
///  * 같은 '보임' 안의 이동(`resumed`↔`inactive`, 트레이너 웹 기준)은 아무것도
///    하지 않는다 — 창을 오가며 눌러도 요청이 겹치지 않는다.
///
/// [start] 는 [onTick] 을 즉시 부르지 않는다 — 처음 한 번은 부르는 쪽이 정한다.
/// 다 쓰면 [dispose] 로 관찰자와 타이머를 함께 뗀다.
class VisiblePeriodicTimer with WidgetsBindingObserver {
  /// Creates a timer; nothing runs until [start].
  VisiblePeriodicTimer({
    required this.interval,
    required this.onTick,
    this.keepPollingWhileInactive = false,
  });

  /// 주기.
  final Duration interval;

  /// 주기마다·다시 보일 때 부르는 작업.
  final VoidCallback onTick;

  /// [pollsWhileIn] 의 같은 이름 인자 — 트레이너 웹은 참이다.
  final bool keepPollingWhileInactive;

  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  bool _visible = true;

  /// 지금 주기가 걸려 있는가(테스트·진단용).
  bool get isRunning => _timer?.isActive ?? false;

  /// 관찰을 시작하고, 지금 보이면 주기를 건다. 두 번 불러도 한 번만 붙는다.
  void start() {
    if (_disposed || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _visible = pollsWhileIn(
      WidgetsBinding.instance.lifecycleState,
      keepPollingWhileInactive: keepPollingWhileInactive,
    );
    if (_visible) _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      if (_disposed || !_visible) return;
      onTick();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    final bool next = pollsWhileIn(
      state,
      keepPollingWhileInactive: keepPollingWhileInactive,
    );
    if (next == _visible) return;
    _visible = next;
    if (!next) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    onTick();
    _arm();
  }

  /// 타이머와 관찰자를 뗀다. 이후 [start] 는 아무것도 하지 않는다.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }
}
