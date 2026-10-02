import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이메일 칸의 자동 대문자·자동 고침(#2816).
///
/// 서버는 이메일을 소문자로 맞춰 비교하므로 첫 글자가 대문자로 바뀌어도 같은
/// 계정이지만, 자동 고침이 주소를 다른 단어로 바꾸면 서버가 되돌릴 수 없다.
/// 그래서 [TextInputType.emailAddress] 칸은 둘 다 끈다. 다른 칸은 그대로다.
Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: OnCareTheme.light(
        brand: OnCareBrand.member,
        density: OnCareDensity.mobile,
      ),
      home: Scaffold(body: child),
    ),
  );
}

TextField _inner(WidgetTester tester, Key key) => tester.widget<TextField>(
  find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
);

void main() {
  const Key fieldKey = ValueKey<String>('field');

  testWidgets('이메일 칸은 자동 대문자·자동 고침·추천을 끈다', (tester) async {
    await _pump(
      tester,
      const AppTextField(
        key: fieldKey,
        keyboardType: TextInputType.emailAddress,
      ),
    );

    final TextField field = _inner(tester, fieldKey);
    expect(field.textCapitalization, TextCapitalization.none);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.keyboardType, TextInputType.emailAddress);
  });

  testWidgets('이메일이 아닌 칸은 TextField 기본값 그대로다', (tester) async {
    await _pump(tester, const AppTextField(key: fieldKey, hint: '이름'));

    final TextField field = _inner(tester, fieldKey);
    const TextField defaults = TextField();
    expect(field.textCapitalization, defaults.textCapitalization);
    expect(field.autocorrect, defaults.autocorrect);
    expect(field.enableSuggestions, defaults.enableSuggestions);
  });

  testWidgets('전화번호 칸도 자동 고침을 끄지 않는다', (tester) async {
    await _pump(
      tester,
      const AppTextField(key: fieldKey, keyboardType: TextInputType.phone),
    );

    // 끄지 않고 TextField 기본값(null — 플랫폼·autofillHints 로 정함)에 맡긴다.
    expect(_inner(tester, fieldKey).autocorrect, isNot(isFalse));
    expect(
      _inner(tester, fieldKey).autocorrect,
      const TextField().autocorrect,
    );
  });

  testWidgets('이메일 칸에 대문자로 친 값은 그대로 보인다 — 바꾸는 것은 서버다', (
    tester,
  ) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      AppTextField(
        key: fieldKey,
        controller: controller,
        keyboardType: TextInputType.emailAddress,
      ),
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(fieldKey),
        matching: find.byType(TextField),
      ),
      'Member@OnCare.com',
    );
    expect(controller.text, 'Member@OnCare.com');
  });
}
