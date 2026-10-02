import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/utils/active_polling_stream.dart';

/// 폴링은 "화면에 보이는가" 로 멈춘다 — 창 포커스만 잃은(`inactive`) 동안은
/// 이어 가고, 가려지거나(`hidden`) 최소화·백그라운드(`paused`)에서만 멈춘다.
/// (#2869)
///
/// 기존 폴링 테스트처럼 `testWidgets` 가 아니라 `test` 로 돈다 — 이 스트림의
/// 수명 관찰자를 `testWidgets` 안에서 붙였다 떼면 테스트 마무리가 끝나지 않는다.
/// 시간에 기대는 단정은 두 가지뿐이다: "멈춘다" 는 몇 주기를 기다려도 늘지
/// 않는 것으로, "계속 읽는다" 는 기대한 횟수에 닿을 때까지 기다리는 것으로
/// 본다. 즉시 읽기·중복 없음은 주기를 하루로 둬 타이머와 섞이지 않게 본다.
void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  /// 짧은 주기 — "계속 읽는다"·"멈춘다" 를 볼 때.
  const Duration interval = Duration(milliseconds: 30);

  /// 타이머가 끼어들지 않는 주기 — 즉시 읽기와 중복 요청을 셀 때.
  const Duration never = Duration(days: 1);

  group('pollsWhileIn', () {
    test('보이는 상태(resumed·inactive)와 상태 전(null)은 폴링한다', () {
      expect(pollsWhileIn(null), isTrue);
      expect(pollsWhileIn(AppLifecycleState.resumed), isTrue);
      expect(pollsWhileIn(AppLifecycleState.inactive), isTrue);
    });

    test('가려진 상태(hidden·paused·detached)는 멈춘다', () {
      expect(pollsWhileIn(AppLifecycleState.hidden), isFalse);
      expect(pollsWhileIn(AppLifecycleState.paused), isFalse);
      expect(pollsWhileIn(AppLifecycleState.detached), isFalse);
    });
  });

  /// 호출 수를 세는 폴링 스트림을 듣는다. 테스트 끝에 [stop] 으로 끊는다.
  ({List<int> emitted, int Function() calls, Future<void> Function() stop})
  listen(Duration every) {
    var calls = 0;
    final List<int> emitted = <int>[];
    final StreamSubscription<int> subscription = activePollingStream<int>(
      load: () async => ++calls,
      interval: every,
    ).listen(emitted.add);
    return (emitted: emitted, calls: () => calls, stop: subscription.cancel);
  }

  void setState(AppLifecycleState state) =>
      binding.handleAppLifecycleStateChanged(state);

  /// 읽기·내보내기 같은 비동기 꼬리를 흘려보낸다.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// [calls] 가 [count] 에 닿을 때까지 기다린다(넉넉한 상한).
  Future<void> reach(int Function() calls, int count) async {
    final Stopwatch watch = Stopwatch()..start();
    while (calls() < count) {
      if (watch.elapsed > const Duration(seconds: 5)) {
        fail('읽기가 $count 번에 닿지 않았다(${calls()}번)');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() => setState(AppLifecycleState.resumed));

  tearDown(() {
    // 다음 테스트가 '보이는 콘솔' 에서 시작하게 되돌린다.
    setState(AppLifecycleState.resumed);
  });

  test('창 포커스만 잃은 동안(inactive)에도 주기마다 계속 읽는다', () async {
    final probe = listen(interval);
    await settle();
    expect(probe.calls(), 1);

    setState(AppLifecycleState.inactive);
    // 읽기 수가 아니라 내보낸 값 수로 기다린다 — 값은 읽기가 끝난 뒤 한 박자
    // 늦게 들어오므로, 읽기 수로 기다리면 마지막 값을 보기 전에 단정한다.
    await reach(() => probe.emitted.length, 3);
    expect(probe.emitted.take(3), <int>[1, 2, 3]);
    await probe.stop();
  });

  test('탭이 가려지면(hidden) 멈춘다', () async {
    final probe = listen(interval);
    await settle();

    setState(AppLifecycleState.inactive);
    setState(AppLifecycleState.hidden);
    final int before = probe.calls();
    await Future<void>.delayed(interval * 5);

    expect(probe.calls(), before);
    await probe.stop();
  });

  test('최소화·백그라운드(paused)에서도 멈춘다', () async {
    final probe = listen(interval);
    await settle();

    setState(AppLifecycleState.inactive);
    setState(AppLifecycleState.hidden);
    setState(AppLifecycleState.paused);
    final int before = probe.calls();
    await Future<void>.delayed(interval * 5);

    expect(probe.calls(), before);
    await probe.stop();
  });

  test('다시 보이면 즉시 한 번 읽고, inactive→resumed 는 다시 읽지 않는다', () async {
    final probe = listen(never);
    await settle();
    setState(AppLifecycleState.hidden);
    await settle();
    expect(probe.calls(), 1);

    // 웹이 가려졌다 돌아올 때의 차례: hidden → inactive → resumed.
    setState(AppLifecycleState.inactive);
    await settle();
    expect(probe.calls(), 2, reason: '보이게 된 순간 즉시 한 번');

    setState(AppLifecycleState.resumed);
    await settle();
    expect(probe.calls(), 2, reason: 'inactive→resumed 는 중복 요청이 없다');
    await probe.stop();
  });

  test('resumed↔inactive 를 여러 번 오가도 요청이 늘지 않는다', () async {
    final probe = listen(never);
    await settle();

    for (var i = 0; i < 4; i++) {
      setState(AppLifecycleState.inactive);
      await settle();
      setState(AppLifecycleState.resumed);
      await settle();
    }
    expect(probe.calls(), 1, reason: '창을 오가는 것만으로는 다시 읽지 않는다');
    await probe.stop();
  });

  test('inactive 상태에서 구독을 시작해도 바로 읽고 주기를 이어 간다', () async {
    setState(AppLifecycleState.inactive);
    final probe = listen(interval);
    await settle();

    expect(probe.calls(), 1);
    await reach(probe.calls, 2);
    await probe.stop();
  });

  test('hidden 상태에서 구독을 시작하면 보일 때까지 읽지 않는다', () async {
    setState(AppLifecycleState.hidden);
    final probe = listen(interval);
    await Future<void>.delayed(interval * 3);
    expect(probe.calls(), 0);

    setState(AppLifecycleState.inactive);
    await settle();
    expect(probe.calls(), 1);
    await probe.stop();
  });
}
