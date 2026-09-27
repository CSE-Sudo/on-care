import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 회원이 담당을 끊으면 서버는 그 회원 데이터를 404 로 막고(#2281), 트레이너
/// 웹은 명단을 곧바로 다시 읽는다. 명단에서 빠진 회원의 상세는 원래의
/// '찾을 수 없음' 상태로 바뀌어야 한다 — 오류로 깨지거나 낡은 값을 들고
/// 있으면 안 된다.
void main() {
  const String memberId = 'seed-client-1';

  /// Opens the detail and returns how to push the next roster.
  Future<void Function(List<TrainerClient>)> openDetail(
    WidgetTester tester, {
    required Locale locale,
    String? section,
  }) async {
    final StreamController<List<TrainerClient>> roster =
        StreamController<List<TrainerClient>>.broadcast();
    addTearDown(roster.close);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      locale: locale,
      extraOverrides: <Override>[
        clientsProvider.overrideWith((ref) => roster.stream),
      ],
    );
    await goTo(tester, AppRoutes.clientDetail(memberId, section: section));
    roster.add(<TrainerClient>[
      makeClient(id: memberId, name: '김민수'),
      makeClient(id: 'seed-client-2', name: '이지수'),
    ]);
    await settle(tester);
    return roster.add;
  }

  for (final String section in <String>['diet', 'workout']) {
    testWidgets('open $section detail falls back to not-found (ko)', (
      tester,
    ) async {
      await withWideSurface(tester, () async {
        final pushRoster = await openDetail(
          tester,
          locale: const Locale('ko'),
          section: section,
        );
        expect(find.text('회원을 찾을 수 없어요'), findsNothing);
        expect(find.text('김민수'), findsWidgets);

        pushRoster(<TrainerClient>[makeClient(id: 'seed-client-2')]);
        await settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('회원을 찾을 수 없어요'), findsOneWidget);
        // 끊긴 회원의 이름·기록이 화면에 남아 있지 않다.
        expect(find.text('김민수'), findsNothing);
      });
    });
  }

  testWidgets('open detail falls back to not-found (en)', (tester) async {
    await withWideSurface(tester, () async {
      final pushRoster = await openDetail(tester, locale: const Locale('en'));
      expect(find.text('Member not found'), findsNothing);

      pushRoster(<TrainerClient>[makeClient(id: 'seed-client-2')]);
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Member not found'), findsOneWidget);
    });
  });

  testWidgets('narrow layout offers the way back to the list', (tester) async {
    final pushRoster = await openDetail(tester, locale: const Locale('ko'));
    pushRoster(<TrainerClient>[makeClient(id: 'seed-client-2')]);
    await settle(tester);

    expect(find.text('회원을 찾을 수 없어요'), findsOneWidget);
    await tester.tap(find.text('회원 목록으로'));
    await settle(tester);
    expect(currentLocation(tester), AppRoutes.clients);
  });

  testWidgets('a removed member stays away when the roster re-emits', (
    tester,
  ) async {
    await withWideSurface(tester, () async {
      final pushRoster = await openDetail(tester, locale: const Locale('ko'));
      pushRoster(<TrainerClient>[makeClient(id: 'seed-client-2')]);
      await settle(tester);
      // 다음 주기의 명단도 같다 — 한 번 바뀐 화면이 되돌아가지 않는다.
      pushRoster(<TrainerClient>[makeClient(id: 'seed-client-2')]);
      await settle(tester);

      expect(find.text('회원을 찾을 수 없어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
