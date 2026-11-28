/// 입력칸 밖을 누르면 키보드가 내려간다(#3489).
///
/// iOS 숫자 키패드에는 완료 키가 없다. 온보딩에서 키·몸무게를 넣은 뒤 빈 곳을
/// 눌러도 키패드가 남아 아래 칸과 버튼을 가렸다. 앱 루트([OncareApp])가 빈 곳
/// 탭을 받아 포커스를 내린다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app.dart';
import 'package:oncare/app/router/app_router.dart';

const Key _height = Key('height');
const Key _weight = Key('weight');
const Key _button = Key('button');
const Key _blank = Key('blank');

void main() {
  late int pressed;

  Future<void> pumpApp(WidgetTester tester) async {
    pressed = 0;
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            body: Column(
              children: <Widget>[
                const TextField(
                  key: _height,
                  keyboardType: TextInputType.number,
                ),
                const TextField(
                  key: _weight,
                  keyboardType: TextInputType.number,
                ),
                ElevatedButton(
                  key: _button,
                  onPressed: () => pressed++,
                  child: const Text('다음'),
                ),
                const Expanded(child: SizedBox(key: _blank)),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[appRouterProvider.overrideWithValue(router)],
        child: const OncareApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool focused(WidgetTester tester, Key key) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode
      .hasFocus;

  testWidgets('숫자 칸에 입력한 뒤 빈 곳을 누르면 포커스가 풀리고 키보드가 닫힌다', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(_height));
    await tester.enterText(find.byKey(_height), '170');
    await tester.pump();
    expect(focused(tester, _height), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tapAt(tester.getCenter(find.byKey(_blank)));
    await tester.pumpAndSettle();

    expect(focused(tester, _height), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('170'), findsOneWidget, reason: '입력한 값은 남는다');
  });

  testWidgets('다른 입력칸을 누르면 포커스가 그 칸으로 옮겨 간다', (WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(_height));
    await tester.pump();

    await tester.tap(find.byKey(_weight));
    await tester.pumpAndSettle();

    expect(focused(tester, _height), isFalse);
    expect(focused(tester, _weight), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('버튼은 루트의 빈 곳 탭에 가로채이지 않고 그대로 눌린다', (WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(_button));
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('포커스가 없을 때 빈 곳을 눌러도 아무 일도 없다', (WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tapAt(tester.getCenter(find.byKey(_blank)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(focused(tester, _height), isFalse);
  });
}
