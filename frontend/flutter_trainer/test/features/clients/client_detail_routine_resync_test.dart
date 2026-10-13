/// 회원 상세의 30초 재동기화가 개인운동 이행도 다시 읽는다. (#3233)
///
/// 날짜별 개인운동(`clientRoutineDaysProvider`)과 지금 걸린 개인운동
/// (`assignedRoutinesProvider`)은 계정 동안 살아 있고 실서버에서는 한 번만
/// 읽는다. 재동기화가 이 둘을 비우지 않아, 회원이 개인운동을 체크해도 오늘 줄이
/// 자정까지 `아직` 으로 남았다 — 같은 카드의 운동 행·총 소모 kcal 은 늘어나는데.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/clients/data/repositories/routine_days_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_days.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';

import '../../helpers/pump_app.dart';

/// 부를 때마다 센다. 응답은 비어 있어도 된다 — 다시 읽었는지만 본다.
class _CountingRoutineDays implements RoutineDaysRepository {
  final List<String> calls = <String>[];

  @override
  Future<RoutineDays> fetch(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    calls.add(memberId);
    return RoutineDays.empty;
  }
}

const String _client1 = 'seed-client-1';
const String _client2 = 'seed-client-2';
const Duration _cycle = Duration(seconds: 31);

Future<void> _wait(WidgetTester tester, Duration d) async {
  await tester.pump(d);
  await settle(tester);
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('30초마다 날짜별 개인운동과 걸린 개인운동을 다시 읽는다', (tester) async {
    final _CountingRoutineDays days = _CountingRoutineDays();
    final List<String> assignedBuilds = <String>[];
    final ProviderContainer container = await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail(_client1, section: 'workout'),
      extraOverrides: <Override>[
        routineDaysRepositoryProvider.overrideWithValue(days),
        assignedRoutinesProvider.overrideWith((ref, memberId) {
          assignedBuilds.add(memberId);
          return Stream<List<AssignedRoutine>>.value(const <AssignedRoutine>[]);
        }),
      ],
    );
    // 어느 카드가 보이든(걸린 개인운동이 있는 날만 오늘 상자가 선다) 화면이
    // 듣고 있는 상태를 만든다.
    final ProviderSubscription<AsyncValue<RoutineDays>> daysSub = container
        .listen(
          clientRoutineDaysProvider(routineDaysKeyNow(_client1)),
          (_, _) {},
        );
    final ProviderSubscription<AsyncValue<List<AssignedRoutine>>> assignedSub =
        container.listen(assignedRoutinesProvider(_client1), (_, _) {});
    addTearDown(daysSub.close);
    addTearDown(assignedSub.close);
    await settle(tester);
    final int daysBefore = days.calls.length;
    final int assignedBefore = assignedBuilds.length;
    expect(daysBefore, greaterThan(0));
    expect(assignedBefore, greaterThan(0));

    await _wait(tester, _cycle);

    expect(days.calls.length, daysBefore + 1);
    expect(days.calls.last, _client1);
    expect(assignedBuilds.length, assignedBefore + 1);
    expect(assignedBuilds.last, _client1);
  });

  testWidgets('회원을 바꾸면 새 회원의 걸린 개인운동을 다시 읽는다', (tester) async {
    final List<String> assignedBuilds = <String>[];
    final ProviderContainer container = await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail(_client1, section: 'workout'),
      extraOverrides: <Override>[
        routineDaysRepositoryProvider.overrideWithValue(_CountingRoutineDays()),
        assignedRoutinesProvider.overrideWith((ref, memberId) {
          assignedBuilds.add(memberId);
          return Stream<List<AssignedRoutine>>.value(const <AssignedRoutine>[]);
        }),
      ],
    );
    await goTo(tester, AppRoutes.clientDetail(_client2, section: 'workout'));
    final ProviderSubscription<AsyncValue<List<AssignedRoutine>>> sub =
        container.listen(assignedRoutinesProvider(_client2), (_, _) {});
    addTearDown(sub.close);
    await settle(tester);
    final int before = assignedBuilds
        .where((String id) => id == _client2)
        .length;

    await _wait(tester, _cycle);

    expect(
      assignedBuilds.where((String id) => id == _client2).length,
      before + 1,
    );
  });
}
