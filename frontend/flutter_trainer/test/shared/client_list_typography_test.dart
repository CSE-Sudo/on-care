import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/client_picker_card.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../helpers/client_factory.dart';
import '../helpers/pump_app.dart';

/// 프로그램 탭과 리포트 탭의 회원 목록은 같은 타이포·아바타 크기를 쓴다. (#1423)
///
/// 두 탭은 같은 구조(왼쪽 회원 목록 → 오른쪽 작업 영역)에 카드 제목·아이콘도
/// 같은데, 이름 글씨는 13.5 와 15, 아바타는 32 와 38 로 갈려 있었다. 탭을
/// 오갈 때 같은 목록이 다른 밀도로 보인다.
///
/// #1705·#1706 에서 공용 `oncare_ui` 규격(역할 글자·[AppAvatar])으로 옮겼고,
/// 지금은 두 탭이 같은 [ClientPickerCard] 한 줄을 쓴다.
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

  /// [rowKey] 행이 쓰는 테마의 규격 토큰.
  OnCareTokens tokensOf(WidgetTester tester, String rowKey) => Theme.of(
    tester.element(find.byKey(ValueKey<String>(rowKey))),
  ).extension<OnCareTokens>()!;

  /// [rowKey] 행 안 [AppAvatar] 의 지름.
  double appAvatarSizeIn(WidgetTester tester, String rowKey) {
    final Finder row = find.byKey(ValueKey<String>(rowKey));
    return tester
        .widget<AppAvatar>(
          find.descendant(of: row, matching: find.byType(AppAvatar)),
        )
        .size
        .dimension;
  }

  /// 아바타가 보이는 카드 면(바닥 간격 제외)의 세로 가운데에 있다.
  void expectAvatarCentered(WidgetTester tester, String rowKey) {
    final Finder row = find.byKey(ValueKey<String>(rowKey));
    final Finder avatar = find.descendant(
      of: row,
      matching: find.byType(AppAvatar),
    );
    final Finder surface = find
        .descendant(of: row, matching: find.byType(Material))
        .first;
    expect(
      tester.getCenter(avatar).dy,
      closeTo(tester.getCenter(surface).dy, 0.1),
    );
  }

  testWidgets('프로그램 탭 회원명은 공용 규격 크기·굵기를 쓴다 (#1705)', (tester) async {
    await openTab(tester, AppRoutes.coaching);

    // 첫 회원이 기본으로 선택된다 — 고른 쪽은 600 강조, 나머지는 기본 굵기.
    // 글씨 크기는 같다(고를 때 행 높이가 흔들리지 않는다).
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

    final OnCareTokens tokens = tokensOf(tester, 'program-client-type-a');
    final TextStyle nameRole = tokens.text(OnCareTypography.bodySmall);
    final TextStyle goalRole = tokens.text(OnCareTypography.caption);

    expect(selected.fontSize, nameRole.fontSize);
    expect(unselected.fontSize, nameRole.fontSize);
    expect(selected.fontWeight, FontWeight.w600);
    expect(unselected.fontWeight, nameRole.fontWeight);
    expect(unselected.fontWeight, isNot(FontWeight.w600));
    expect(selected.color, OnCareColors.textPrimary);
    expect(unselected.color, OnCareColors.textPrimary);
    // 목표 줄은 이름보다 한 단계 작고 흐리다.
    expect(goalSizeIn(tester, 'program-client-type-a'), goalRole.fontSize);
    expect(goalRole.fontSize!, lessThan(nameRole.fontSize!));
    expect(
      appAvatarSizeIn(tester, 'program-client-type-a'),
      OnCareSize.avatarMedium,
    );
    expectAvatarCentered(tester, 'program-client-type-a');
  });

  // 리포트 탭도 프로그램 탭과 같은 회원 카드 한 줄([ClientPickerCard])을 쓴다.
  testWidgets('리포트 탭 회원 목록은 프로그램 탭과 같은 카드를 쓴다 (#1706)', (tester) async {
    await openTab(tester, AppRoutes.reports);

    ClientPickerCard rowOf(String key) =>
        tester.widget<ClientPickerCard>(find.byKey(ValueKey<String>(key)));
    // 첫 회원이 기본으로 선택된다.
    expect(rowOf('report-client-type-a').selected, isTrue);
    expect(rowOf('report-client-type-b').selected, isFalse);

    // 고를 때 이름 크기가 달라져 행 높이가 흔들리지 않는다.
    expect(
      nameStyleIn(tester, 'report-client-type-a', '가회원').fontSize,
      nameStyleIn(tester, 'report-client-type-b', '나회원').fontSize,
    );
    final Finder row = find.byKey(
      const ValueKey<String>('report-client-type-a'),
    );
    expect(find.descendant(of: row, matching: find.text(goal)), findsOneWidget);
    final Finder avatar = find.descendant(
      of: row,
      matching: find.byType(AppAvatar),
    );
    expect(tester.widget<AppAvatar>(avatar).size, AppAvatarSize.medium);
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
