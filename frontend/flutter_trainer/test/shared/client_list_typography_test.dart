import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';

import '../helpers/client_factory.dart';
import '../helpers/pump_app.dart';

/// 프로그램 탭과 리포트 탭의 회원 목록은 같은 타이포·아바타 크기를 쓴다. (#1423)
///
/// 두 탭은 같은 구조(왼쪽 회원 목록 → 오른쪽 작업 영역)에 카드 제목·아이콘도
/// 같은데, 이름 글씨는 13.5 와 15, 아바타는 32 와 38 로 갈려 있었다. 탭을
/// 오갈 때 같은 목록이 다른 밀도로 보인다.
void main() {
  const String goal = '혈압 관리 · 체중 감량';

  final List<TrainerClient> roster = <TrainerClient>[
    makeClient(id: 'type-a', name: '가회원', goal: goal),
    makeClient(id: 'type-b', name: '나회원', goal: goal),
  ];

  Future<void> openTab(WidgetTester tester, String at) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: at,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(roster),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  /// [rowKey] 행 안에서 [name] 을 그리는 텍스트의 스타일.
  TextStyle nameStyleIn(WidgetTester tester, String rowKey, String name) {
    final Finder row = find.byKey(ValueKey<String>(rowKey));
    expect(row, findsOneWidget, reason: rowKey);
    return tester
        .widget<Text>(find.descendant(of: row, matching: find.text(name)))
        .style!;
  }

  /// [rowKey] 행의 목표 한 줄 글씨 크기.
  double goalSizeIn(WidgetTester tester, String rowKey) {
    final Finder row = find.byKey(ValueKey<String>(rowKey));
    return tester
        .widget<Text>(find.descendant(of: row, matching: find.text(goal)))
        .style!
        .fontSize!;
  }

  /// [rowKey] 행 안 [ClientAvatar] 의 지름.
  double avatarSizeIn(WidgetTester tester, String rowKey) {
    final Finder row = find.byKey(ValueKey<String>(rowKey));
    return tester
        .widget<ClientAvatar>(
          find.descendant(of: row, matching: find.byType(ClientAvatar)),
        )
        .size;
  }

  void expectAvatarCentered(WidgetTester tester, String rowKey) {
    final Finder row = find.byKey(ValueKey<String>(rowKey));
    final Finder avatar = find.descendant(
      of: row,
      matching: find.byType(ClientAvatar),
    );
    expect(tester.getCenter(avatar).dy, closeTo(tester.getCenter(row).dy, 0.1));
  }

  testWidgets('프로그램 탭 회원명은 공용 크기·굵기를 쓴다', (tester) async {
    await openTab(tester, AppRoutes.coaching);

    // 첫 회원이 기본으로 선택된다 — 고른 쪽은 굵게, 나머지는 한 단계 얇게.
    final TextStyle selected = nameStyleIn(
      tester,
      'program-client-type-a',
      '가회원',
    );
    final TextStyle unselected = nameStyleIn(
      tester,
      'program-client-type-b',
      '나회원',
    );

    expect(selected.fontSize, clientListNameFontSize);
    expect(unselected.fontSize, clientListNameFontSize);
    expect(selected.fontWeight, FontWeight.w800);
    expect(unselected.fontWeight, FontWeight.w600);
    expect(goalSizeIn(tester, 'program-client-type-a'), clientListGoalFontSize);
    expect(avatarSizeIn(tester, 'program-client-type-a'), clientListAvatarSize);
    expectAvatarCentered(tester, 'program-client-type-a');
  });

  testWidgets('리포트 탭 회원명이 프로그램 탭과 같은 크기·굵기다', (tester) async {
    await openTab(tester, AppRoutes.reports);

    final TextStyle selected = nameStyleIn(
      tester,
      'report-client-type-a',
      '가회원',
    );
    final TextStyle unselected = nameStyleIn(
      tester,
      'report-client-type-b',
      '나회원',
    );

    expect(selected.fontSize, clientListNameFontSize);
    expect(unselected.fontSize, clientListNameFontSize);
    expect(selected.fontWeight, FontWeight.w800);
    expect(unselected.fontWeight, FontWeight.w600);
    expect(goalSizeIn(tester, 'report-client-type-a'), clientListGoalFontSize);
    expect(avatarSizeIn(tester, 'report-client-type-a'), clientListAvatarSize);
    expectAvatarCentered(tester, 'report-client-type-a');
  });

  testWidgets('긴 이름과 큰 배율에서도 행이 넘치지 않는다', (tester) async {
    final List<TrainerClient> longNames = <TrainerClient>[
      makeClient(id: 'type-a', name: '아주아주긴이름의회원님입니다', goal: goal),
    ];
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 1200);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.reports,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(longNames),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
