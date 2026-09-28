import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 첫 시작 구성 카드. 화면을 넓게 띄워 사이드바까지 그린 뒤 찾는다.
Future<Finder> _openTemplateCard(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: AppRoutes.coaching,
    seedClock: kMidWeekKst,
  );

  final String id = MockTrainerProgramTemplateRepository.starters.first.id;
  final Finder card = find.byKey(ValueKey<String>('template-card-$id')).first;
  expect(card, findsOneWidget);
  return card;
}

void main() {
  // 템플릿 카드가 옅은 네이비면 화면의 다른 네이비 강조와 섞여 **이미 고른
  // 템플릿처럼** 보인다 — 고르기 전인데 고른 것으로 읽힌다. (#2220)
  testWidgets('프로그램 템플릿 카드는 중립 회색을 쓴다', (tester) async {
    final Finder card = await _openTemplateCard(tester);

    final AppTile tile = tester.widget<AppTile>(card);
    expect(tile.tone, AppTileTone.neutral);

    // 채움이 실제로 회색으로 그려지는지까지 본다 — 톤 이름만 맞고 그 톤이
    // 브랜드 색을 내면 화면은 그대로다.
    final Material fill = tester.widget<Material>(
      find.descendant(of: card, matching: find.byType(Material)).first,
    );
    expect(fill.color, OnCareColors.surfaceInput);
  });

  // 마우스로 누른 뒤 포커스 강조가 남지 않는 것은 여기서 재지 못한다 —
  // `tester.tap` 은 실제 브라우저 클릭과 달리 포커스를 주지 않아, 고치기
  // 전에도 이 테스트는 통과한다. 그래서 그 쪽은 테스트를 두지 않고 브라우저로
  // 확인한다. 여기서는 **고치면서 망가지기 쉬운 것**만 지킨다.
  //
  // 포커스 자체를 막으면 키보드로 쓰는 사람이 "지금 어디" 를 알 길이 없어진다.
  // 누른 뒤에만 거두고, 옮겨온 포커스는 그대로 둔다. (#2220)
  testWidgets('키보드로 옮겨온 포커스는 그대로 남는다', (tester) async {
    final Finder card = await _openTemplateCard(tester);

    final FocusNode? node = Focus.maybeOf(tester.element(card));
    expect(node, isNotNull);
    node!.requestFocus();
    await tester.pumpAndSettle();

    expect(node.hasFocus, isTrue);
  });
}
