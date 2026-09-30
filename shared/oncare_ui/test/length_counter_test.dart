import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 여러 줄 입력칸 아래의 `현재/최대` 글자 수(#2618).
void main() {
  Future<TextEditingController> pump(
    WidgetTester tester, {
    String text = '',
    int maxLength = 10,
    bool showCounter = true,
    String? helper,
  }) async {
    final TextEditingController controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.trainer,
          density: OnCareDensity.web,
        ),
        home: Scaffold(
          body: AppTextField(
            controller: controller,
            helper: helper,
            maxLines: 3,
            maxLength: maxLength,
            showCounter: showCounter,
          ),
        ),
      ),
    );
    return controller;
  }

  Color? colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  testWidgets('적는 대로 글자 수가 바뀐다', (WidgetTester tester) async {
    await pump(tester);
    expect(find.text('0/10'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '가나다');
    await tester.pump();

    expect(find.text('3/10'), findsOneWidget);
    expect(colorOf(tester, '3/10'), OnCareColors.textTertiary);
  });

  testWidgets('켜지 않으면 상한이 있어도 글자 수를 감춘다', (WidgetTester tester) async {
    await pump(tester, showCounter: false);
    expect(find.text('0/10'), findsNothing);
  });

  testWidgets('도움말과 글자 수는 같은 줄 양 끝에 선다', (WidgetTester tester) async {
    await pump(tester, helper: '회원에게 보여요');

    final Rect helper = tester.getRect(find.text('회원에게 보여요'));
    final Rect counter = tester.getRect(find.text('0/10'));
    expect(counter.center.dy, moreOrLessEquals(helper.center.dy, epsilon: 1));
    expect(counter.left, greaterThan(helper.right));
  });

  testWidgets('이모지 한 글자는 한 글자로 센다', (WidgetTester tester) async {
    await pump(tester, text: '👍🏻👍🏻');
    expect(find.text('2/10'), findsOneWidget);
  });

  testWidgets('상한에 닿으면 위험 색이다', (WidgetTester tester) async {
    await pump(tester, text: '가' * 10);
    expect(colorOf(tester, '10/10'), OnCareColors.danger);
  });

  testWidgets('상한을 줄이기 전에 저장된 긴 글도 그대로 세어 알린다', (
    WidgetTester tester,
  ) async {
    await pump(tester, text: '가' * 12);
    expect(colorOf(tester, '12/10'), OnCareColors.danger);
  });

  test('등급 값은 서버 text_limits 와 같다', () {
    expect(AppTextLimits.name, 100);
    expect(AppTextLimits.line, 200);
    expect(AppTextLimits.entry, 500);
    expect(AppTextLimits.long, 1000);
  });
}
