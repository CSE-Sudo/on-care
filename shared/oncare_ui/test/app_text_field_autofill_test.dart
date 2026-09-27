import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// [AppTextField] 가 자동완성 힌트를 안쪽 [TextField] 까지 그대로 건네는지(#2295).
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

  testWidgets('힌트를 주지 않으면 TextField 기본값(빈 목록)과 같다', (tester) async {
    await _pump(tester, const AppTextField(key: fieldKey, hint: '입력'));

    // null 이 아니라 빈 목록이어야 한다 — null 은 자동완성을 아예 끈다.
    final Iterable<String>? hints = _inner(tester, fieldKey).autofillHints;
    expect(hints, isNotNull);
    expect(hints, isEmpty);
    expect(hints, const TextField().autofillHints);
  });

  testWidgets('준 힌트를 순서 그대로 안쪽 TextField 에 건넨다', (tester) async {
    await _pump(
      tester,
      const AppTextField(
        key: fieldKey,
        autofillHints: <String>[AutofillHints.username, AutofillHints.email],
      ),
    );

    expect(_inner(tester, fieldKey).autofillHints, <String>[
      AutofillHints.username,
      AutofillHints.email,
    ]);
  });

  testWidgets('비밀번호 칸도 가림 처리와 함께 힌트를 건넨다', (tester) async {
    await _pump(
      tester,
      const AppTextField(
        key: fieldKey,
        obscureText: true,
        autofillHints: <String>[AutofillHints.newPassword],
      ),
    );

    final TextField inner = _inner(tester, fieldKey);
    expect(inner.obscureText, isTrue);
    expect(inner.autofillHints, <String>[AutofillHints.newPassword]);
  });

  testWidgets('null 을 주면 자동완성을 끈다', (tester) async {
    await _pump(tester, const AppTextField(key: fieldKey, autofillHints: null));

    expect(_inner(tester, fieldKey).autofillHints, isNull);
  });

  testWidgets('AutofillGroup 안의 칸은 그 묶음에 등록된다', (tester) async {
    const Key emailKey = ValueKey<String>('email');
    const Key passwordKey = ValueKey<String>('password');
    await _pump(
      tester,
      const AutofillGroup(
        child: Column(
          children: <Widget>[
            AppTextField(
              key: emailKey,
              autofillHints: <String>[AutofillHints.email],
            ),
            AppTextField(
              key: passwordKey,
              obscureText: true,
              autofillHints: <String>[AutofillHints.password],
            ),
          ],
        ),
      ),
    );

    final AutofillGroupState group = tester.state<AutofillGroupState>(
      find.byType(AutofillGroup),
    );
    // 칸에 포커스가 가면 묶음이 모든 칸의 설정을 한 번에 플랫폼에 넘긴다.
    await tester.tap(
      find.descendant(
        of: find.byKey(emailKey),
        matching: find.byType(TextField),
      ),
    );
    await tester.pump();
    expect(group.autofillClients.length, 2);
    final List<String> registered = <String>[
      for (final AutofillClient c in group.autofillClients)
        ...c.textInputConfiguration.autofillConfiguration.autofillHints,
    ];
    expect(
      registered,
      containsAll(<String>[AutofillHints.email, AutofillHints.password]),
    );
  });
}
