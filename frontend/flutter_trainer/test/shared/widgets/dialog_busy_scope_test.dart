/// 열람형 창은 평소엔 바로 닫히고, 요청이 도는 동안만 닫히지 않는다.
///
/// 바깥 누름·뒤로 가기·X 셋 모두 `Navigator.maybePop` 을 거치므로 범위 하나가
/// 셋을 함께 막는다. 공용 `showAppDialog` 의 기본값(바깥 닫힘 허용)은 그대로다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/shared/widgets/dialog_busy_scope.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 누르면 [gate] 가 풀릴 때까지 창을 붙잡는 버튼.
class _HoldButton extends StatelessWidget {
  const _HoldButton({required this.id, required this.gate});

  final String id;
  final Completer<void> gate;

  @override
  Widget build(BuildContext context) => TextButton(
    key: ValueKey<String>('hold-$id'),
    onPressed: () async {
      try {
        await DialogBusyScope.guard(context, () => gate.future);
      } on StateError {
        // 실패한 요청 — 화면은 토스트를 띄우고 넘어간다.
      }
    },
    child: Text('hold $id'),
  );
}

final Finder _dialog = find.byType(AppDialog);

Future<void> _open(
  WidgetTester tester, {
  required Completer<void> first,
  Completer<void>? second,
  bool scoped = true,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            key: const ValueKey<String>('open'),
            onPressed: () => showAppDialog<void>(
              context: context,
              builder: (_) {
                final Widget dialog = AppDialog(
                  title: '창',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _HoldButton(id: 'a', gate: first),
                      if (second != null) _HoldButton(id: 'b', gate: second),
                    ],
                  ),
                );
                return scoped ? DialogBusyScope(child: dialog) : dialog;
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey<String>('open')));
  await tester.pumpAndSettle();
  expect(_dialog, findsOneWidget);
}

/// 창 바깥(배경 막)을 누른다.
Future<void> _tapOutside(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await tester.pumpAndSettle();
}

/// 시스템 뒤로 가기(웹의 브라우저 뒤로 가기·Esc 와 같은 길).
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('요청이 없으면 바깥을 눌러 바로 닫힌다', (tester) async {
    await _open(tester, first: Completer<void>());

    await _tapOutside(tester);

    expect(_dialog, findsNothing);
  });

  testWidgets('요청이 없으면 뒤로 가기로 바로 닫힌다', (tester) async {
    await _open(tester, first: Completer<void>());

    await _back(tester);

    expect(_dialog, findsNothing);
  });

  testWidgets('요청 중에는 바깥 누름·뒤로 가기·X 로 닫히지 않는다', (tester) async {
    final Completer<void> gate = Completer<void>();
    await _open(tester, first: gate);
    await tester.tap(find.byKey(const ValueKey<String>('hold-a')));
    await tester.pump();

    await _tapOutside(tester);
    expect(_dialog, findsOneWidget);
    await _back(tester);
    expect(_dialog, findsOneWidget);
    await tester.tap(find.byType(AppCloseButton));
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    await _tapOutside(tester);
    expect(_dialog, findsNothing);
  });

  testWidgets('요청이 실패해도 끝나면 다시 닫힌다', (tester) async {
    final Completer<void> gate = Completer<void>();
    await _open(tester, first: gate);
    await tester.tap(find.byKey(const ValueKey<String>('hold-a')));
    await tester.pump();

    gate.completeError(StateError('실패'));
    await tester.pumpAndSettle();

    await _tapOutside(tester);
    expect(_dialog, findsNothing);
  });

  testWidgets('창 안 여러 위젯의 요청을 모아 모두 끝나야 닫힌다', (tester) async {
    final Completer<void> a = Completer<void>();
    final Completer<void> b = Completer<void>();
    await _open(tester, first: a, second: b);
    await tester.tap(find.byKey(const ValueKey<String>('hold-a')));
    await tester.tap(find.byKey(const ValueKey<String>('hold-b')));
    await tester.pump();

    a.complete();
    await tester.pumpAndSettle();
    await _tapOutside(tester);
    expect(_dialog, findsOneWidget, reason: 'b 가 아직 돈다');

    b.complete();
    await tester.pumpAndSettle();
    await _tapOutside(tester);
    expect(_dialog, findsNothing);
  });

  testWidgets('범위 밖에서는 아무것도 막지 않는다 — 공용 기본값 그대로', (tester) async {
    final Completer<void> gate = Completer<void>();
    await _open(tester, first: gate, scoped: false);
    await tester.tap(find.byKey(const ValueKey<String>('hold-a')));
    await tester.pump();

    await _tapOutside(tester);

    expect(_dialog, findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
  });
}
