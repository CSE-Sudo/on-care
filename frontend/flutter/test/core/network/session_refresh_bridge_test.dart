/// 갱신을 한 번에 하나만 돌리는 다리. (#1546)
///
/// 갱신 토큰은 일회용이라, 동시 401 이 각자 갱신하면 두 번째부터 거부되어 멀쩡한
/// 세션이 끝난다. 이 다리가 진행 중인 갱신을 함께 기다리게 하는지 고정한다.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/network/session_refresh.dart';

class _GatedRefresher implements SessionTokenRefresher {
  final List<String> calls = <String>[];
  Completer<TokenRefreshResult> gate = Completer<TokenRefreshResult>();

  @override
  Future<TokenRefreshResult> refreshAfterUnauthorized(String staleToken) {
    calls.add(staleToken);
    return gate.future;
  }
}

class _ThrowingRefresher implements SessionTokenRefresher {
  @override
  Future<TokenRefreshResult> refreshAfterUnauthorized(String staleToken) =>
      Future<TokenRefreshResult>.error(StateError('storage'));
}

void main() {
  late SessionRefreshBridge bridge;
  late _GatedRefresher refresher;

  setUp(() {
    bridge = SessionRefreshBridge();
    refresher = _GatedRefresher();
    bridge.attach(refresher);
  });

  test('진행 중인 갱신이 있으면 새로 시작하지 않고 같은 결과를 받는다', () async {
    final Future<TokenRefreshResult> a = bridge.refresh('t');
    final Future<TokenRefreshResult> b = bridge.refresh('t');
    final Future<TokenRefreshResult> c = bridge.refresh('t');
    expect(bridge.isRefreshing, isTrue);

    refresher.gate.complete(const TokenRefreshResult.refreshed('n'));
    final List<TokenRefreshResult> results = await Future.wait(
      <Future<TokenRefreshResult>>[a, b, c],
    );

    expect(refresher.calls, <String>['t']);
    expect(results.map((TokenRefreshResult r) => r.accessToken), <String?>[
      'n',
      'n',
      'n',
    ]);
  });

  test('갱신이 끝나면 다음 만료에서 다시 갱신할 수 있다', () async {
    final Future<TokenRefreshResult> first = bridge.refresh('t1');
    refresher.gate.complete(const TokenRefreshResult.refreshed('t2'));
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(bridge.isRefreshing, isFalse);

    refresher.gate = Completer<TokenRefreshResult>();
    final Future<TokenRefreshResult> second = bridge.refresh('t2');
    refresher.gate.complete(const TokenRefreshResult.refreshed('t3'));
    expect((await second).accessToken, 't3');
    expect(refresher.calls, <String>['t1', 't2']);
  });

  test('거부·실패 결과도 기다리던 모두에게 그대로 간다', () async {
    final Future<TokenRefreshResult> a = bridge.refresh('t');
    final Future<TokenRefreshResult> b = bridge.refresh('t');
    refresher.gate.complete(const TokenRefreshResult.rejected());

    expect((await a).status, TokenRefreshStatus.rejected);
    expect((await b).status, TokenRefreshStatus.rejected);
    expect(refresher.calls, hasLength(1));
  });

  test('갱신기가 없으면 갱신할 수 없다고 답한다', () async {
    bridge.detach(refresher);
    final TokenRefreshResult result = await bridge.refresh('t');
    expect(result.status, TokenRefreshStatus.unavailable);
    expect(result.accessToken, isNull);
    expect(refresher.calls, isEmpty);
  });

  test('다른 갱신기를 떼려는 요청은 지금 것을 떼지 않는다', () async {
    bridge.detach(_GatedRefresher());
    final Future<TokenRefreshResult> pending = bridge.refresh('t');
    refresher.gate.complete(const TokenRefreshResult.refreshed('n'));
    expect((await pending).status, TokenRefreshStatus.refreshed);
  });

  test('갱신기가 던지면 세션의 끝이 아니라 갱신 불가로 본다', () async {
    bridge.attach(_ThrowingRefresher());
    final TokenRefreshResult result = await bridge.refresh('t');
    expect(result.status, TokenRefreshStatus.unavailable);
    expect(bridge.isRefreshing, isFalse);
  });
}
