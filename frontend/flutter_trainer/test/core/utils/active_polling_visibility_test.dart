import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/utils/active_polling_stream.dart';

/// 폴링은 "화면에 보이는가" 로 멈춘다 — 창 포커스만 잃은(`inactive`) 동안은
/// 이어 가고, 가려지거나(`hidden`) 최소화·백그라운드(`paused`)에서만 멈춘다.
/// (#2869)
///
/// `testWidgets` 의 가짜 시계로 타이머를 돌린다 — `tester.pump(간격)` 이 한
/// 주기를 흘려보낸다.
void main() {
  const Duration interval = Duration(seconds: 5);

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

  /// [interval] 마다 호출 수를 세는 폴링 스트림을 듣는다.
  ///
  /// 테스트 끝에 [stop] 으로 구독을 끊는다 — 가짜 시계에 남은 타이머가 있으면
  /// `testWidgets` 가 실패로 본다.
  Future<
    ({List<int> emitted, int Function() calls, Future<void> Function() stop})
  >
  listen(WidgetTester tester) async {
    var calls = 0;
    final List<int> emitted = <int>[];
    final StreamSubscription<int> subscription = activePollingStream<int>(
      load: () async => ++calls,
      interval: interval,
    ).listen(emitted.add);
    await tester.pump(); // 첫 읽기
    return (emitted: emitted, calls: () => calls, stop: subscription.cancel);
  }

  void setState(WidgetTester tester, AppLifecycleState state) =>
      tester.binding.handleAppLifecycleStateChanged(state);

  tearDown(() {
    // 다음 테스트가 '보이는 콘솔' 에서 시작하게 되돌린다.
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('창 포커스만 잃은 동안(inactive)에도 주기마다 계속 읽는다', (tester) async {
    setState(tester, AppLifecycleState.resumed);
    final probe = await listen(tester);
    expect(probe.calls(), 1);

    setState(tester, AppLifecycleState.inactive);
    await tester.pump(interval);
    expect(probe.calls(), 2);
    await tester.pump(interval);
    expect(probe.calls(), 3);
    expect(probe.emitted, <int>[1, 2, 3]);
    await probe.stop();
  });

  testWidgets('탭이 가려지면(hidden) 멈춘다', (tester) async {
    setState(tester, AppLifecycleState.resumed);
    final probe = await listen(tester);

    setState(tester, AppLifecycleState.inactive);
    setState(tester, AppLifecycleState.hidden);
    await tester.pump(interval * 3);

    expect(probe.calls(), 1);
    await probe.stop();
  });

  testWidgets('최소화·백그라운드(paused)에서도 멈춘다', (tester) async {
    setState(tester, AppLifecycleState.resumed);
    final probe = await listen(tester);

    setState(tester, AppLifecycleState.inactive);
    setState(tester, AppLifecycleState.hidden);
    setState(tester, AppLifecycleState.paused);
    await tester.pump(interval * 3);

    expect(probe.calls(), 1);
    await probe.stop();
  });

  testWidgets('다시 보이면 즉시 한 번 읽고, 이어서 한 주기에 한 번씩만 읽는다', (tester) async {
    setState(tester, AppLifecycleState.resumed);
    final probe = await listen(tester);
    setState(tester, AppLifecycleState.hidden);
    await tester.pump(interval * 2);
    expect(probe.calls(), 1);

    // 웹이 가려졌다 돌아올 때의 차례: hidden → inactive → resumed.
    setState(tester, AppLifecycleState.inactive);
    await tester.pump();
    expect(probe.calls(), 2, reason: '보이게 된 순간 즉시 한 번');

    setState(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(probe.calls(), 2, reason: 'inactive→resumed 는 중복 요청이 없다');

    await tester.pump(interval);
    expect(probe.calls(), 3);
    await probe.stop();
  });

  testWidgets('resumed↔inactive 를 여러 번 오가도 요청이 늘지 않는다', (tester) async {
    setState(tester, AppLifecycleState.resumed);
    final probe = await listen(tester);

    for (var i = 0; i < 4; i++) {
      setState(tester, AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 100));
      setState(tester, AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(probe.calls(), 1, reason: '창을 오가는 것만으로는 다시 읽지 않는다');

    // 타이머도 다시 걸리지 않았다 — 처음 잡은 주기 그대로 다음 읽기가 온다.
    await tester.pump(interval - const Duration(milliseconds: 800));
    expect(probe.calls(), 2);
    await probe.stop();
  });

  testWidgets('inactive 상태에서 구독을 시작해도 바로 읽는다', (tester) async {
    setState(tester, AppLifecycleState.inactive);
    final probe = await listen(tester);

    expect(probe.calls(), 1);
    await tester.pump(interval);
    expect(probe.calls(), 2);
    await probe.stop();
  });

  testWidgets('hidden 상태에서 구독을 시작하면 보일 때까지 읽지 않는다', (tester) async {
    setState(tester, AppLifecycleState.hidden);
    final probe = await listen(tester);
    await tester.pump(interval * 2);
    expect(probe.calls(), 0);

    setState(tester, AppLifecycleState.inactive);
    await tester.pump();
    expect(probe.calls(), 1);
    await probe.stop();
  });
}
