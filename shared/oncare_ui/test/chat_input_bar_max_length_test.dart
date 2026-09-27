import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 채팅 입력줄의 최대 글자 수(#1549).
///
/// 서버가 받는 길이를 넘는 글은 입력되지 않고, 한도에 가까워졌을 때만 입력줄
/// 위에 글자 수가 보인다. 평소에는 입력줄 모양(높이·버튼 자리)이 예전 그대로다.
void main() {
  final Finder counter = find.byKey(
    const ValueKey<String>('chat-input-length-counter'),
  );

  Future<TextEditingController> pump(
    WidgetTester tester, {
    int? maxLength,
    String text = '',
    OnCareDensity density = OnCareDensity.mobile,
  }) async {
    final TextEditingController controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(brand: OnCareBrand.member, density: density),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 800,
              child: AppChatInputBar(
                controller: controller,
                hint: '메시지',
                sendTooltip: '보내기',
                onSend: () {},
                maxLength: maxLength,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('한도를 넘는 글자는 입력되지 않는다', (WidgetTester tester) async {
    final TextEditingController controller = await pump(tester, maxLength: 10);

    await tester.enterText(find.byType(TextField), '가' * 15);
    await tester.pump();

    expect(controller.text, '가' * 10);
  });

  testWidgets('정확히 한도만큼은 그대로 입력된다', (WidgetTester tester) async {
    final TextEditingController controller = await pump(tester, maxLength: 10);

    await tester.enterText(find.byType(TextField), 'a' * 10);
    await tester.pump();

    expect(controller.text, 'a' * 10);
  });

  testWidgets('한도를 주지 않으면 제한이 없다(기존 동작)', (WidgetTester tester) async {
    final TextEditingController controller = await pump(tester);

    await tester.enterText(find.byType(TextField), 'a' * 5000);
    await tester.pump();

    expect(controller.text.length, 5000);
    expect(counter, findsNothing);
  });

  testWidgets('한도에 멀면 글자 수를 보이지 않는다', (WidgetTester tester) async {
    await pump(tester, maxLength: 100);

    await tester.enterText(find.byType(TextField), 'a' * 89);
    await tester.pump();

    expect(counter, findsNothing);
  });

  testWidgets('한도의 90% 부터 입력줄 위에 현재/최대 를 보인다', (WidgetTester tester) async {
    await pump(tester, maxLength: 100);

    await tester.enterText(find.byType(TextField), 'a' * 90);
    await tester.pump();

    expect(find.text('90/100'), findsOneWidget);
    final Text text = tester.widget<Text>(counter);
    expect(text.style?.color, OnCareColors.textTertiary);
    // 입력칸 위에 선다 — 아래에 붙은 전송 버튼과 높이가 어긋나지 않게.
    expect(
      tester.getRect(counter).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(TextField)).top),
    );
  });

  testWidgets('한도에 닿으면 위험 색으로 바뀐다', (WidgetTester tester) async {
    await pump(tester, maxLength: 100);

    await tester.enterText(find.byType(TextField), 'a' * 120);
    await tester.pump();

    expect(find.text('100/100'), findsOneWidget);
    expect(tester.widget<Text>(counter).style?.color, OnCareColors.danger);
  });

  testWidgets('글을 지우면 글자 수가 다시 사라진다', (WidgetTester tester) async {
    final TextEditingController controller = await pump(tester, maxLength: 100);
    await tester.enterText(find.byType(TextField), 'a' * 95);
    await tester.pump();
    expect(counter, findsOneWidget);

    controller.clear();
    await tester.pump();

    expect(counter, findsNothing);
  });

  testWidgets('입력칸 기본 카운터 줄은 그리지 않는다', (WidgetTester tester) async {
    await pump(tester, maxLength: 100);

    await tester.enterText(find.byType(TextField), 'a' * 95);
    await tester.pump();

    // 기본 카운터였다면 입력칸 아래에 '95/100' 이 하나 더 있다.
    expect(find.text('95/100'), findsOneWidget);
  });

  for (final OnCareDensity density in <OnCareDensity>[
    OnCareDensity.mobile,
    OnCareDensity.web,
  ]) {
    testWidgets('한도가 있어도 평소 입력줄 높이는 같다 (${density.name})', (
      WidgetTester tester,
    ) async {
      await pump(tester, density: density);
      final double plain = tester.getSize(find.byType(AppChatInputBar)).height;

      await pump(tester, maxLength: 1000, density: density);
      final double limited = tester
          .getSize(find.byType(AppChatInputBar))
          .height;

      expect(limited, plain);
    });
  }
}
