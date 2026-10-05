// 회원 상세의 휴면 배지가 서버 상태를 따르는지. (#707, #2330)
//
// `활성` 은 기본값이라 적지 않고, 휴면인 회원에만 배지가 선다. 배지를 누르면
// 활성으로 돌린다. 배지는 로스터를 그대로 그린다 — 탭한 순간이 아니라 **소스가
// 확인해 준 뒤에만** 바뀐다. 그래야 실패한 저장이 화면에 확정값처럼 남지 않는다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 저장이 항상 실패하는 소스 — 로스터는 건드리지 않는다(실패한 요청과 같다).
class _FailingStatusRepository extends DriftClientRepository {
  const _FailingStatusRepository(super.db);

  @override
  Future<void> setClientActive(String id, bool active) async {
    throw const NetworkError();
  }
}

/// 저장이 호출자가 열어 줄 때까지 끝나지 않는 소스 — 저장 중 재탭을 시험한다.
class _GatedStatusRepository extends DriftClientRepository {
  _GatedStatusRepository(super.db, this._gate);

  final Future<void> _gate;
  int calls = 0;

  @override
  Future<void> setClientActive(String id, bool active) async {
    calls++;
    await _gate;
    return super.setClientActive(id, active);
  }
}

Finder get _badge => find.byKey(const ValueKey<String>('client-status-toggle'));

/// 시드의 휴면 회원 — 박성호.
const String _dormantId = 'seed-client-3';

void main() {
  testWidgets('활성 회원에게는 상태 배지가 없다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1'),
    );

    expect(_badge, findsNothing);
    expect(find.text('활성'), findsNothing);
  });

  testWidgets('휴면 배지를 누르면 활성으로 돌아가고 배지가 사라진다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail(_dormantId),
    );

    expect(find.descendant(of: _badge, matching: find.text('휴면')), findsOne);
    await tester.tap(_badge);
    await settle(tester);

    expect(_badge, findsNothing);
  });

  testWidgets('활성으로 돌리면 필터·대시보드가 읽는 로스터 값이 함께 바뀐다', (tester) async {
    await withWideSurface(tester, () async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail(_dormantId),
      );

      final before = await container.read(clientsProvider.future);
      expect(before.firstWhere((c) => c.id == _dormantId).active, isFalse);

      await tester.tap(_badge);
      await settle(tester);

      // 필터·대시보드가 읽는 바로 그 값이 바뀐다(둘 다 roster 의 active 파생).
      final after = await container.read(clientsProvider.future);
      expect(after.firstWhere((c) => c.id == _dormantId).active, isTrue);
    });
  });

  testWidgets('저장이 실패하면 배지는 그대로 남고 다시 시도할 수 있다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail(_dormantId),
      extraOverrides: <Override>[
        clientRepositoryProvider.overrideWith(
          (ref) => _FailingStatusRepository(ref.watch(appDatabaseProvider)),
        ),
      ],
    );

    await tester.tap(_badge);
    await settle(tester);

    // 연결 오류는 원인별 안내다 — Dio 영어 원문이 아니다.
    expect(find.textContaining('연결이 불안정합니다'), findsOneWidget);
    // 서버가 받지 않은 값이 화면에 확정처럼 남지 않는다.
    expect(find.descendant(of: _badge, matching: find.text('휴면')), findsOne);

    // 배지는 다시 눌리는 상태다(잠긴 채로 남지 않는다).
    expect(tester.widget<AppTag>(_badge).onTap, isNotNull);
  });

  testWidgets('저장 중 다시 탭해도 요청은 한 번만 나간다', (tester) async {
    final gate = Completer<void>();
    late _GatedStatusRepository repository;
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail(_dormantId),
      extraOverrides: <Override>[
        clientRepositoryProvider.overrideWith((ref) {
          repository = _GatedStatusRepository(
            ref.watch(appDatabaseProvider),
            gate.future,
          );
          return repository;
        }),
      ],
    );

    await tester.tap(_badge);
    await tester.pump();
    // 저장이 끝나기 전의 두 번째·세 번째 탭.
    await tester.tap(_badge, warnIfMissed: false);
    await tester.tap(_badge, warnIfMissed: false);
    await tester.pump();
    expect(repository.calls, 1);

    gate.complete();
    await settle(tester);
    expect(_badge, findsNothing);
  });
}
