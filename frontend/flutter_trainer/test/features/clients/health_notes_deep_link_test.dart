/// 주의사항 알림에서 온 회원 상세는 신체·목표 창의 `건강 목표` 탭을 바로 연다.
/// (#2619)
///
/// 회원이 고친 건강상태·주의사항은 그 탭에만 보인다. 알림을 눌러 상세로만 가면
/// 트레이너가 창을 열고 탭을 한 번 더 골라야 글에 닿는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';

import '../../helpers/pump_app.dart';

void main() {
  Future<void> open(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(tester, token: 'demo-trainer-token', at: location);
    await settle(tester);
  }

  final Finder tabs = find.byKey(const ValueKey<String>('client-health-tabs'));

  testWidgets('알림에서 온 상세는 건강 목표 탭을 연다', (tester) async {
    await open(
      tester,
      AppRoutes.clientDetail('seed-client-1', openHealthNotes: true),
    );

    expect(tabs, findsOneWidget);
    // 건강상태·주의사항은 `건강 목표` 탭에만 있다.
    expect(find.text('건강상태·주의사항'), findsOneWidget);
  });

  testWidgets('그냥 들어온 상세는 창을 열지 않는다', (tester) async {
    await open(tester, AppRoutes.clientDetail('seed-client-1'));

    expect(tabs, findsNothing);
  });
}
