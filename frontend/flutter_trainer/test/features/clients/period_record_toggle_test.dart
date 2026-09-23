/// 기간 기록 토글과 세부 지표 표기. (#1465)
///
/// 접힌 줄의 요약과 펼친 줄의 상세가 같은 수치를 두 번 말해, 토글이 무엇을
/// 여는 장치인지 흐려졌다. 식단의 `탄단지` 는 따로 선 지표가 아니라 칼로리의
/// 구성이고, 운동의 `칼로리` 는 섭취 칼로리와 구분되어야 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';

import '../../helpers/pump_app.dart';

void main() {
  Future<void> openSection(WidgetTester tester, String section) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 2400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail('seed-client-1', section: section),
    );
    await tester.pumpAndSettle();
  }

  Finder dayTiles() => find.byWidgetPredicate(
    (Widget w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('client-day-tile-'),
  );

  testWidgets('식단 접힌 줄에는 요약 수치가 없다', (tester) async {
    await openSection(tester, 'diet');
    await tester.tap(_periodSegment('이번 주'));
    await tester.pumpAndSettle();

    // 접힌 줄에는 날짜와 화살표뿐이다 — `1,820 kcal · 나트륨 …` 같은 요약이
    // 붙지 않는다.
    final Finder collapsed = dayTiles().last;
    expect(
      find.descendant(of: collapsed, matching: find.textContaining('kcal')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: collapsed,
        matching: find.byIcon(Icons.expand_more_rounded),
      ),
      findsWidgets,
    );
  });

  testWidgets('식단 펼친 줄은 칼로리(탄단지) → 나트륨 → 당류 순이다', (tester) async {
    await openSection(tester, 'diet');
    await tester.tap(_periodSegment('이번 주'));
    await tester.pumpAndSettle();

    // 기록이 있는 날을 펼친다.
    for (int i = 0; i < dayTiles().evaluate().length; i++) {
      final Finder tile = dayTiles().at(i);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      // 카드 머리에도 탄단지 줄이 늘 있어 `탄수화물` 로는 펼쳤는지 알 수 없다.
      // `칼로리` 는 펼친 줄에만 있다 — 기간 그래프에 지표 칩이 없어졌다(#2156).
      if (find
          .textContaining('칼로리', findRichText: true)
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    // `탄단지` 라는 상위 용어는 없고, 각 영양소 이름만 남는다.
    expect(find.text('탄단지'), findsNothing);
    expect(find.textContaining('탄수화물'), findsWidgets);

    // 순서: 칼로리 → 나트륨 → 당류.
    final double calories = tester
        .getTopLeft(find.textContaining('칼로리', findRichText: true).first)
        .dx;
    expect(calories, isNotNull);
  });

  testWidgets('운동 상세는 소모 칼로리라고 부른다', (tester) async {
    await openSection(tester, 'workout');
    await tester.tap(_periodSegment('이번 주'));
    await tester.pumpAndSettle();

    for (int i = 0; i < dayTiles().evaluate().length; i++) {
      final Finder tile = dayTiles().at(i);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      if (find
          .textContaining('소모 칼로리', findRichText: true)
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    expect(find.textContaining('소모 칼로리', findRichText: true), findsWidgets);
  });
}

/// 기간 토글에서 [label] 칸. 세그먼트는 칸마다 키가 없어 토글 안의 글자로 찾는다.
Finder _periodSegment(String label) => find.descendant(
  of: find.byKey(const ValueKey<String>('client-period-toggle')),
  matching: find.text(label),
);
