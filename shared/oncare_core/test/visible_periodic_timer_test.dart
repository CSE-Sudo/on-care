import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_core/visible_periodic_timer.dart';

/// 보임 기준 주기 타이머(#3013). `activePollingStream` 과 같은 기준([pollsWhileIn])
/// 으로 멈추고 다시 건다.
///
/// `active_polling_visibility_test.dart` 처럼 `testWidgets` 가 아니라 `test` 로
/// 돈다 — 수명 관찰자를 `testWidgets` 안에서 붙였다 떼면 마무리가 끝나지 않는다.
/// "멈춘다" 는 몇 주기를 기다려도 늘지 않는 것으로, "계속 부른다" 는 기대한
/// 횟수에 닿을 때까지 기다리는 것으로 본다.
void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  const Duration interval = Duration(milliseconds: 30);
  const Duration never = Duration(days: 1);

  void setState(AppLifecycleState state) =>
      binding.handleAppLifecycleStateChanged(state);

  Future<void> reach(int Function() calls, int count) async {
    final Stopwatch watch = Stopwatch()..start();
    while (calls() < count) {
      if (watch.elapsed > const Duration(seconds: 5)) {
        fail('$count 번에 닿지 않았다(${calls()}번)');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  ({VisiblePeriodicTimer timer, int Function() calls}) make(
    Duration every, {
    bool keepPollingWhileInactive = true,
  }) {
    var calls = 0;
    final VisiblePeriodicTimer timer = VisiblePeriodicTimer(
      interval: every,
      keepPollingWhileInactive: keepPollingWhileInactive,
      onTick: () => calls++,
    );
    addTearDown(timer.dispose);
    return (timer: timer, calls: () => calls);
  }

  setUp(() => setState(AppLifecycleState.resumed));
  tearDown(() => setState(AppLifecycleState.resumed));

  test('start 는 즉시 부르지 않고, 보이는 동안 주기마다 부른다', () async {
    final probe = make(interval);
    probe.timer.start();
    expect(probe.calls(), 0);
    expect(probe.timer.isRunning, isTrue);

    await reach(probe.calls, 3);
  });

  test('가려지면(hidden) 멈춘다', () async {
    final probe = make(interval);
    probe.timer.start();

    setState(AppLifecycleState.inactive);
    setState(AppLifecycleState.hidden);
    final int before = probe.calls();
    expect(probe.timer.isRunning, isFalse);
    await Future<void>.delayed(interval * 5);

    expect(probe.calls(), before);
  });

  test('paused·detached 에서도 멈춘다', () async {
    final probe = make(interval);
    probe.timer.start();

    setState(AppLifecycleState.inactive);
    setState(AppLifecycleState.hidden);
    setState(AppLifecycleState.paused);
    final int before = probe.calls();
    await Future<void>.delayed(interval * 5);
    expect(probe.calls(), before);

    setState(AppLifecycleState.detached);
    await Future<void>.delayed(interval * 3);
    expect(probe.calls(), before);
  });

  test('다시 보이면 즉시 한 번 부르고, inactive→resumed 는 더 부르지 않는다', () {
    final probe = make(never);
    probe.timer.start();
    setState(AppLifecycleState.inactive);
    setState(AppLifecycleState.hidden);
    expect(probe.calls(), 0);

    setState(AppLifecycleState.inactive);
    expect(probe.calls(), 1);
    expect(probe.timer.isRunning, isTrue);
    setState(AppLifecycleState.resumed);
    expect(probe.calls(), 1);
  });

  test('resumed↔inactive 를 오가도 부르지 않는다(트레이너 웹 기준)', () {
    final probe = make(never);
    probe.timer.start();
    for (var i = 0; i < 5; i++) {
      setState(AppLifecycleState.inactive);
      setState(AppLifecycleState.resumed);
    }

    expect(probe.calls(), 0);
  });

  test('회원 앱 기준(기본값)은 inactive 에서 멈추고 resumed 에서 다시 부른다', () {
    final probe = make(never, keepPollingWhileInactive: false);
    probe.timer.start();

    setState(AppLifecycleState.inactive);
    expect(probe.timer.isRunning, isFalse);
    setState(AppLifecycleState.resumed);
    expect(probe.calls(), 1);
    expect(probe.timer.isRunning, isTrue);
  });

  test('가려진 채로 시작하면 주기를 걸지 않고, 보이면 그때 건다', () {
    setState(AppLifecycleState.inactive);
    setState(AppLifecycleState.hidden);
    final probe = make(never);
    probe.timer.start();
    expect(probe.timer.isRunning, isFalse);

    setState(AppLifecycleState.inactive);
    expect(probe.calls(), 1);
    expect(probe.timer.isRunning, isTrue);
  });

  test('dispose 뒤에는 부르지 않고 수명 변화에도 반응하지 않는다', () async {
    final probe = make(interval);
    probe.timer
      ..start()
      ..dispose();
    expect(probe.timer.isRunning, isFalse);

    setState(AppLifecycleState.hidden);
    setState(AppLifecycleState.inactive);
    await Future<void>.delayed(interval * 3);

    expect(probe.calls(), 0);
  });

  test('start 를 두 번 불러도 주기는 하나다', () async {
    final probe = make(interval);
    probe.timer
      ..start()
      ..start();
    setState(AppLifecycleState.inactive);
    setState(AppLifecycleState.hidden);
    // 관찰자가 둘이면 다시 보일 때 두 번 부른다.
    setState(AppLifecycleState.inactive);

    expect(probe.calls(), 1);
  });

  test('dispose 뒤 start 는 아무것도 하지 않는다', () {
    final probe = make(never);
    probe.timer
      ..dispose()
      ..start();

    expect(probe.timer.isRunning, isFalse);
  });
}
