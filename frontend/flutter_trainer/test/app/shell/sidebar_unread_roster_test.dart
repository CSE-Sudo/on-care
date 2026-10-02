import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 해제 회원 몫이 섞인 안읽음 맵에서 사이드바 배지·메시지 칩·대시보드가 같은
/// 수를 보인다. (#2868)
///
/// 명단은 `a`·`b` 둘이고, 안읽음 맵에는 명단에 없는 `released` 몫 5건이
/// 섞여 있다 — 서버가 해제 회원을 빼기 전 배포나 데모에서 생길 수 있는 모양.
void main() {
  List<Override> overrides() => <Override>[
    clientsProvider.overrideWith(
      (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
        makeClient(id: 'a', name: '가회원'),
        makeClient(id: 'b', name: '나회원'),
      ]),
    ),
    unreadCountsProvider.overrideWith(
      (ref) => Stream<Map<String, int>>.value(const <String, int>{
        'a': 2,
        'released': 5,
      }),
    ),
  ];

  Finder sidebarBadge() => find.descendant(
    of: find.byKey(const ValueKey<String>('sidebar-${AppRoutes.messages}')),
    matching: find.byKey(const ValueKey<String>('app-sidebar-item-badge')),
  );

  testWidgets('사이드바 메시지 배지는 명단 회원 몫만 센다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
        extraOverrides: overrides(),
        at: AppRoutes.messages,
      );

      expect(sidebarBadge(), findsOneWidget);
      expect(
        find.descendant(of: sidebarBadge(), matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sidebarBadge(), matching: find.text('7')),
        findsNothing,
      );
    });
  });

  testWidgets('메시지 읽지 않음 칩은 명단 회원 중 안읽음이 있는 수다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
        extraOverrides: overrides(),
        at: AppRoutes.messages,
      );

      expect(find.text('읽지 않음 1'), findsOneWidget);
      expect(find.text('읽지 않음 2'), findsNothing);
    });
  });

  testWidgets('대시보드 답장 대기도 같은 수다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
        extraOverrides: overrides(),
        at: AppRoutes.dashboard,
      );

      expect(find.text('회원 1명 대기 중'), findsOneWidget);
      expect(
        find.descendant(of: sidebarBadge(), matching: find.text('2')),
        findsOneWidget,
      );
    });
  });

  testWidgets('명단 밖 몫만 있으면 사이드바 배지가 없다', (tester) async {
    await withWideSurface(tester, () async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token-existing',
        extraOverrides: <Override>[
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
              makeClient(id: 'a', name: '가회원'),
            ]),
          ),
          unreadCountsProvider.overrideWith(
            (ref) => Stream<Map<String, int>>.value(const <String, int>{
              'released': 3,
            }),
          ),
        ],
        at: AppRoutes.messages,
      );

      expect(sidebarBadge(), findsNothing);
      expect(find.text('읽지 않음 0'), findsOneWidget);
    });
  });
}
