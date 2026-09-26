/// 글씨를 키운 뒤 문구가 잘리던 자리들 (#1004).
///
/// 세로로 넘치는 것은 예외로 드러나지만 **가로로 줄임표가 되거나 상자에 눌려
/// 잘리는 것은 조용하다.** 화면 이름·서비스 이름·그래프 목표 라벨은 잘리면
/// 그 자리가 무엇인지가 사라지는 곳이라, 여기서 못 박아 둔다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';

import '../helpers/pump_app.dart';

/// [text] 를 그리는 문단이 잘렸는가 — 줄임표가 걸렸거나 상자보다 큰가.
bool _isClipped(WidgetTester tester, String contains) {
  bool clipped = false;
  bool found = false;
  void visit(Element el) {
    final RenderObject? ro = el.renderObject;
    if (ro is RenderParagraph && ro.hasSize) {
      final String text = ro.text.toPlainText();
      if (text.contains(contains)) {
        found = true;
        if (ro.didExceedMaxLines ||
            ro.getMinIntrinsicHeight(ro.size.width) > ro.size.height + 0.5) {
          clipped = true;
        }
      }
    }
    el.visitChildren(visit);
  }

  visit(tester.binding.rootElement!);
  expect(found, isTrue, reason: '"$contains" 를 그리는 문단을 못 찾았다');
  return clipped;
}

void main() {
  testWidgets('사이드바 서비스 이름이 줄임표로 잘리지 않는다', (WidgetTester tester) async {
    // 사이드바가 라벨을 펴는 폭.
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.dashboard,
    );
    await settle(tester);

    expect(_isClipped(tester, 'On-Care'), isFalse);
  });

  testWidgets('화면 이름이 줄임표로 잘리지 않는다 — 액션이 많은 내 정보', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.my,
      locale: const Locale('en'),
    );
    await settle(tester);

    expect(_isClipped(tester, 'My profile'), isFalse);
  });
}
