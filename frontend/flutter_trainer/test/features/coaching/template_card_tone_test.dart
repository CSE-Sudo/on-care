import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

void main() {
  // 템플릿 카드가 옅은 네이비면 화면의 다른 네이비 강조와 섞여 **이미 고른
  // 템플릿처럼** 보인다 — 고르기 전인데 고른 것으로 읽힌다. (#2220)
  testWidgets('프로그램 템플릿 카드는 중립 회색을 쓴다', (tester) async {
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
    final Finder card = find
        .byKey(ValueKey<String>('template-card-$id'))
        .first;
    expect(card, findsOneWidget);

    final AppTile tile = tester.widget<AppTile>(card);
    expect(tile.tone, AppTileTone.neutral);

    // 채움이 실제로 회색으로 그려지는지까지 본다 — 톤 이름만 맞고 그 톤이
    // 브랜드 색을 내면 화면은 그대로다.
    final Material fill = tester.widget<Material>(
      find.descendant(of: card, matching: find.byType(Material)).first,
    );
    expect(fill.color, OnCareColors.surfaceInput);
  });
}
