// 회원 상세의 활성/휴면 배지가 서버 상태를 따르는지. (#707)
//
// 배지는 로스터를 그대로 그린다 — 탭한 순간이 아니라 **소스가 확인해 준 뒤에만**
// 바뀐다. 그래야 실패한 저장이 화면에 확정값처럼 남지 않는다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

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

Finder get _badge =>
    find.byKey(const ValueKey<String>('client-status-toggle'));

void main() {
  testWidgets('탭하면 배지가 휴면으로 바뀌고 회원 목록에도 반영된다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1'),
    );

    expect(find.text('활성'), findsWidgets);
    await tester.tap(_badge);
    await settle(tester);

    // 상세의 배지와 목록 요약이 같은 값을 쓴다.
    expect(find.text('휴면'), findsWidgets);

    await tester.tap(_badge);
    await settle(tester);
    expect(find.text('활성'), findsWidgets);
  });

  testWidgets('휴면으로 바꾸면 필터·대시보드가 읽는 로스터 값이 함께 바뀐다', (tester) async {
    await withWideSurface(tester, () async {
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1'),
      );

      final before = await container.read(clientsProvider.future);
      expect(before.firstWhere((c) => c.id == 'seed-client-1').active, isTrue);

      await tester.tap(_badge);
      await settle(tester);

      // 필터·대시보드가 읽는 바로 그 값이 바뀐다(둘 다 roster 의 active 파생).
      final after = await container.read(clientsProvider.future);
      expect(after.firstWhere((c) => c.id == 'seed-client-1').active, isFalse);
    });
  });

  testWidgets('저장이 실패하면 배지는 그대로 남고 다시 시도할 수 있다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1'),
      extraOverrides: <Override>[
        clientRepositoryProvider.overrideWith(
          (ref) => _FailingStatusRepository(ref.watch(appDatabaseProvider)),
        ),
      ],
    );

    expect(find.text('활성'), findsWidgets);
    await tester.tap(_badge);
    await settle(tester);

    expect(find.textContaining('상태를 바꾸지 못했어요'), findsOneWidget);
    // 서버가 받지 않은 값이 화면에 확정처럼 남지 않는다.
    expect(find.text('휴면'), findsNothing);

    // 배지는 다시 눌리는 상태다(잠긴 채로 남지 않는다).
    expect(
      tester.widget<InkWell>(find.byKey(_badgeInkWellKey)).onTap,
      isNotNull,
    );
  });

  testWidgets('저장 중 다시 탭해도 요청은 한 번만 나간다', (tester) async {
    final gate = Completer<void>();
    late _GatedStatusRepository repository;
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1'),
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
    expect(find.text('휴면'), findsWidgets);
  });
}

const ValueKey<String> _badgeInkWellKey = ValueKey<String>(
  'client-status-toggle',
);
