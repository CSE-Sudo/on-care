/// 토스트가 걷힐 때 자리(OverlayEntry)와 곡선 애니메이션을 놓는다. (#3250)
///
/// 걷기만 하고 놓지 않으면 토스트를 띄울 때마다 자리가 하나씩 남는다. 앞 토스트를
/// 새 토스트가 걷어 낸 뒤 앞 토스트의 타이머가 다시 걷으려 해도 두 번 걷지 않아야
/// 한다 — 두 번 걷으면 단언이 터진다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<BuildContext> _pump(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(
        brand: OnCareBrand.member,
        density: OnCareDensity.mobile,
      ),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            captured = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  testWidgets('새 토스트가 앞 토스트를 걷어도 앞 타이머가 다시 걷지 않는다', (tester) async {
    final BuildContext context = await _pump(tester);

    showAppToast(context, '첫 알림');
    await tester.pump();
    showAppToast(context, '둘째 알림');
    await tester.pump();

    expect(find.text('첫 알림'), findsNothing);
    expect(find.text('둘째 알림'), findsOneWidget);

    // 두 토스트의 머무는 시간이 모두 지나도 오류 없이 걷힌다.
    await tester.pump(OnCareMotion.toastVisible);
    await tester.pumpAndSettle();
    expect(find.text('둘째 알림'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('저절로 걷힌 뒤에도 다음 토스트가 뜬다', (tester) async {
    final BuildContext context = await _pump(tester);

    showAppToast(context, '첫 알림');
    await tester.pump();
    await tester.pump(OnCareMotion.toastVisible);
    await tester.pumpAndSettle();
    expect(find.text('첫 알림'), findsNothing);

    showAppToast(context, '다음 알림');
    await tester.pump();
    expect(find.text('다음 알림'), findsOneWidget);
    await tester.pump(OnCareMotion.toastVisible);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
