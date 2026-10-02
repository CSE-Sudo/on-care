import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/web/leave_guard.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 코칭 화면의 보내지 않은 작성 내용 지킴 (#2873).
///
/// 새로 고침·탭 닫기는 브라우저가 묻는다 — 여기서는 그 순간 읽는 조건
/// ([leaveGuards])과 회원 전환 확인창을 본다.
void main() {
  const String a = 'seed-client-1';
  const String b = 'seed-client-2';

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.coachingFor(a),
      seedClock: kMidWeekKst,
    );
  }

  Future<void> tapCentered(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> generate(WidgetTester tester) => tapCentered(
    tester,
    find.byKey(const ValueKey<String>('generate-routine-options')),
  );

  Finder card(String id) => find.byKey(ValueKey<String>('program-client-$id'));

  String? clientQuery(WidgetTester tester) =>
      Uri.parse(currentLocation(tester)).queryParameters['client'];

  testWidgets('작성 내용이 없으면 막지 않고, 후보를 받으면 막는다', (tester) async {
    await open(tester);
    expect(leaveGuards.shouldBlock(), isFalse);

    await generate(tester);

    expect(leaveGuards.shouldBlock(), isTrue);
  });

  testWidgets('작성 중 회원을 바꾸면 앱 안에서 먼저 묻는다', (tester) async {
    await open(tester);
    await generate(tester);

    await tapCentered(tester, card(b));
    expect(find.text('다른 회원으로 바꿀까요?'), findsOneWidget);

    // 취소하면 그 회원, 그 작성 내용 그대로다.
    await tester.tap(find.text('취소').last);
    await tester.pumpAndSettle();
    expect(clientQuery(tester), a);
    expect(leaveGuards.shouldBlock(), isTrue);

    // 바꾸면 새 회원의 빈 작업 공간이 열리고 지킴이 풀린다.
    await tapCentered(tester, card(b));
    await tester.tap(find.text('바꾸기').last);
    await settle(tester);
    expect(clientQuery(tester), b);
    expect(leaveGuards.shouldBlock(), isFalse);
  });

  testWidgets('작성 내용이 없으면 묻지 않고 바로 바꾼다', (tester) async {
    await open(tester);

    await tapCentered(tester, card(b));

    expect(find.text('다른 회원으로 바꿀까요?'), findsNothing);
    expect(clientQuery(tester), b);
  });

  testWidgets('편집기 구성을 템플릿으로 저장하면 지킴이 풀린다', (tester) async {
    await open(tester);
    final String id = MockTrainerProgramTemplateRepository.starters.first.id;
    await tapCentered(
      tester,
      find.byKey(ValueKey<String>('template-card-$id')).first,
    );
    // 템플릿이 편집기를 채웠다 — 보내지 않은 구성이다.
    expect(leaveGuards.shouldBlock(), isTrue);

    await tapCentered(
      tester,
      find.byKey(const ValueKey<String>('program-editor-save')),
    );
    await settle(tester);

    expect(leaveGuards.shouldBlock(), isFalse);
  });
}
