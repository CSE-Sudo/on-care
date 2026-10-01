import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/shared/widgets/client_picker_card.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 코칭 화면의 회원 전환이 주소에 실린다 (#2872).
///
/// 주소가 선택 회원의 원천이다 — 새로고침·주소 공유·재진입이 모두 마지막으로
/// 고른 회원을 연다.
void main() {
  const String a = 'seed-client-1';
  const String b = 'seed-client-2';

  Future<void> open(WidgetTester tester, String at) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: at,
      seedClock: kMidWeekKst,
    );
  }

  Finder card(String id) => find.byKey(ValueKey<String>('program-client-$id'));

  bool isSelected(WidgetTester tester, String id) =>
      tester.widget<ClientPickerCard>(card(id)).selected;

  Future<void> tapCard(WidgetTester tester, String id) async {
    await tester.ensureVisible(card(id));
    await tester.tap(card(id));
    await settle(tester);
  }

  String? clientQuery(WidgetTester tester) =>
      Uri.parse(currentLocation(tester)).queryParameters['client'];

  testWidgets('회원 카드를 누르면 주소의 client 가 바뀐다', (tester) async {
    await open(tester, AppRoutes.coachingFor(a));
    expect(isSelected(tester, a), isTrue);

    await tapCard(tester, b);

    expect(clientQuery(tester), b);
    expect(isSelected(tester, b), isTrue);
    expect(isSelected(tester, a), isFalse);
  });

  testWidgets('그 주소로 다시 열면(새로고침) 마지막으로 고른 회원이 열린다', (tester) async {
    await open(tester, AppRoutes.coachingFor(b));

    expect(isSelected(tester, b), isTrue);
    expect(isSelected(tester, a), isFalse);
  });

  testWidgets('A 에서 B 로 바꾼 뒤 A 링크로 오면 A 로 돌아온다', (tester) async {
    await open(tester, AppRoutes.coachingFor(a));
    await tapCard(tester, b);
    expect(isSelected(tester, b), isTrue);

    // 다른 화면의 `AI 루틴 만들기` 처럼 A 로 오는 링크.
    await goTo(tester, AppRoutes.dashboard);
    await goTo(tester, AppRoutes.coachingFor(a));

    expect(clientQuery(tester), a);
    expect(isSelected(tester, a), isTrue);
    expect(isSelected(tester, b), isFalse);
  });

  testWidgets('회원을 바꾸면 붙이기 흐름 쿼리가 떨어진다', (tester) async {
    await open(
      tester,
      AppRoutes.coachingAttach(
        a,
        sessionId: 'session-1',
        date: '2026-08-21',
        requestId: 'r-1',
      ),
    );

    await tapCard(tester, b);

    final Uri uri = Uri.parse(currentLocation(tester));
    expect(uri.path, AppRoutes.coaching);
    expect(uri.queryParameters, <String, String>{'client': b});
  });

  testWidgets('같은 회원 카드를 다시 눌러도 주소는 그대로다', (tester) async {
    await open(tester, AppRoutes.coachingFor(a));
    final String before = currentLocation(tester);

    await tapCard(tester, a);

    expect(currentLocation(tester), before);
    expect(isSelected(tester, a), isTrue);
  });
}
