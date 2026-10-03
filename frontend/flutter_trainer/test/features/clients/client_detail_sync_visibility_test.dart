import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/clients/domain/repositories/client_data_refresher.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/pump_app.dart';

/// 회원 상세의 30초 동기화는 탭이 가려진 동안 멈춘다 (#3013).
///
/// 저장소 스트림(`activePollingStream`)과 같은 보임 기준이다: 창 포커스만 잃은
/// `inactive` 는 이어 가고, `hidden`·`paused` 에서 멈추며, 다시 보이면 곧바로 한
/// 번 맞춘다. 상세가 다시 읽는 것은 [ClientDataRefresher.refreshClientData] 로
/// 센다 — 주기 한 번마다 한 번 부른다.
class _RecordingRefreshClientRepository extends DriftClientRepository
    implements ClientDataRefresher {
  _RecordingRefreshClientRepository(super.db);

  final List<String> clientRefreshes = <String>[];

  @override
  void refreshAllClientData() {}

  @override
  void refreshClientData(String clientId) => clientRefreshes.add(clientId);
}

const String _client1 = 'seed-client-1';
const String _client2 = 'seed-client-2';

Future<_RecordingRefreshClientRepository> _pumpDetail(
  WidgetTester tester, {
  String clientId = _client1,
}) async {
  late _RecordingRefreshClientRepository repository;
  await pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: AppRoutes.clientDetail(clientId, section: 'diet'),
    extraOverrides: <Override>[
      clientRepositoryProvider.overrideWith((ref) {
        repository = _RecordingRefreshClientRepository(
          ref.watch(appDatabaseProvider),
        );
        return repository;
      }),
    ],
  );
  return repository;
}

void _lifecycle(WidgetTester tester, AppLifecycleState state) =>
    tester.binding.handleAppLifecycleStateChanged(state);

Future<void> _wait(WidgetTester tester, Duration d) async {
  await tester.pump(d);
  await settle(tester);
}

const Duration _cycle = Duration(seconds: 31);

void main() {
  setUp(() {
    // 다른 테스트가 남긴 상태와 무관하게 '보이는 콘솔' 에서 시작한다.
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('탭이 가려지면(hidden) 30초가 지나도 다시 읽지 않는다', (tester) async {
    final repository = await _pumpDetail(tester);
    expect(repository.clientRefreshes, <String>[_client1]);

    _lifecycle(tester, AppLifecycleState.inactive);
    _lifecycle(tester, AppLifecycleState.hidden);
    await _wait(tester, _cycle);
    await _wait(tester, _cycle);

    expect(repository.clientRefreshes, <String>[_client1]);
  });

  testWidgets('최소화(paused)에서도 멈춘다', (tester) async {
    final repository = await _pumpDetail(tester);

    _lifecycle(tester, AppLifecycleState.inactive);
    _lifecycle(tester, AppLifecycleState.hidden);
    _lifecycle(tester, AppLifecycleState.paused);
    await _wait(tester, _cycle);

    expect(repository.clientRefreshes, <String>[_client1]);
  });

  testWidgets('다시 보이면 곧바로 한 번 읽고 주기를 다시 건다', (tester) async {
    final repository = await _pumpDetail(tester);
    _lifecycle(tester, AppLifecycleState.inactive);
    _lifecycle(tester, AppLifecycleState.hidden);
    await _wait(tester, _cycle);
    expect(repository.clientRefreshes, hasLength(1));

    // 웹이 가려졌다 돌아올 때의 차례: hidden → inactive → resumed.
    _lifecycle(tester, AppLifecycleState.inactive);
    await settle(tester);
    expect(repository.clientRefreshes, hasLength(2));
    // inactive → resumed 는 같은 '보임' 안의 이동 — 다시 읽지 않는다.
    _lifecycle(tester, AppLifecycleState.resumed);
    await settle(tester);
    expect(repository.clientRefreshes, hasLength(2));

    await _wait(tester, _cycle);
    expect(repository.clientRefreshes, hasLength(3));
  });

  testWidgets('창 포커스만 잃은 동안(inactive)에는 30초마다 계속 읽는다', (tester) async {
    final repository = await _pumpDetail(tester);

    _lifecycle(tester, AppLifecycleState.inactive);
    await _wait(tester, _cycle);
    expect(repository.clientRefreshes, hasLength(2));
    await _wait(tester, _cycle);
    expect(repository.clientRefreshes, hasLength(3));
  });

  testWidgets('창을 오가며 눌러도(resumed↔inactive) 요청이 겹치지 않는다', (tester) async {
    final repository = await _pumpDetail(tester);

    for (var i = 0; i < 3; i++) {
      _lifecycle(tester, AppLifecycleState.inactive);
      _lifecycle(tester, AppLifecycleState.resumed);
    }
    await settle(tester);

    expect(repository.clientRefreshes, <String>[_client1]);
  });

  testWidgets('회원을 바꾸면 새 회원 하나만 주기에 남는다', (tester) async {
    final repository = await _pumpDetail(tester);

    await goTo(tester, AppRoutes.clientDetail(_client2, section: 'diet'));
    final int afterSwitch = repository.clientRefreshes.length;
    expect(repository.clientRefreshes.last, _client2);

    await _wait(tester, _cycle);
    final List<String> tick = repository.clientRefreshes.sublist(afterSwitch);
    expect(tick, <String>[_client2]);
  });

  testWidgets('상세를 닫으면 주기가 남지 않는다', (tester) async {
    final repository = await _pumpDetail(tester);

    await goTo(tester, AppRoutes.dashboard);
    final int afterClose = repository.clientRefreshes.length;
    await _wait(tester, _cycle);

    expect(repository.clientRefreshes, hasLength(afterClose));
  });
}
