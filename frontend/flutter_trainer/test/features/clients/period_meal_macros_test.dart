/// `이번 주`·`전체` 에서 펼친 끼니에도 탄·단·지가 보인다. (#1439)
///
/// 데이터가 없어서가 아니라 그리지 않아서였다 — 날짜별 조회는 끼니마다
/// `carbs_g`·`protein_g`·`fat_g` 를 이미 준다. 트레이너가 과거 식단을 볼 때만
/// 정보가 얕아지면 코칭 근거가 달라진다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/pump_app.dart';

/// 펼친 날의 끼니. 하나는 탄단지가 있고 하나는 아예 없다 — 두 표기를 한
/// 화면에서 함께 본다.
const List<ClientDietEntry> _meals = <ClientDietEntry>[
  ClientDietEntry(
    id: 'meal-with-macros',
    meal: '점심',
    items: '비빔밥',
    calories: 615,
    sodiumMg: 1200,
    sugarG: 9,
    carbsG: 92.5,
    proteinG: 21,
    fatG: 14,
  ),
  // 먹었는데 영양이 비어 있는 옛 기록 — 0g 으로 적으면 아무것도 안 먹은
  // 끼니로 읽힌다.
  ClientDietEntry(
    id: 'meal-without-macros',
    meal: '간식',
    items: '아메리카노',
    calories: 120,
    sodiumMg: 5,
  ),
];

void main() {
  Future<void> openDiet(WidgetTester tester, {bool stubMeals = false}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 2400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      // 시드 로스터의 첫 회원(김민수) — 데모 식단이 가장 두툼하다.
      at: AppRoutes.clientDetail('seed-client-1', section: 'diet'),
      extraOverrides: <Override>[
        if (stubMeals)
          // 어느 날을 펼쳐도 같은 끼니가 온다 — 데모 픽스처가 끼니를 들고 있는
          // 날이 며칠뿐이라, 실행한 날짜에 따라 검사가 비어 버린다.
          clientDietOnProvider.overrideWith((ref, key) async => _meals),
      ],
    );
    await tester.pumpAndSettle();
  }

  /// 끼니가 보일 때까지 날짜 줄을 펼친다.
  ///
  /// `이번 주` 의 오늘 줄은 토글이 아니라 늘 펼쳐져 있고, 지난 날 줄은 눌러야
  /// 열린다 — 어느 쪽이든 끼니가 화면에 오면 그만둔다.
  Future<void> expandUntilMeals(WidgetTester tester) async {
    Finder lines() => find.byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('client-diet-macros-'),
    );
    if (lines().evaluate().isNotEmpty) return;
    final Finder tiles = find.byWidgetPredicate(
      (Widget w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('client-day-tile-'),
    );
    for (int i = 0; i < tiles.evaluate().length; i++) {
      final Finder tile = tiles.at(i);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      if (lines().evaluate().isNotEmpty) return;
    }
  }

  /// 펼친 끼니의 탄단지 줄. 키에 끼니 id 가 들어 있다.
  Finder macroLines() => find.byWidgetPredicate(
    (Widget w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('client-diet-macros-'),
  );

  testWidgets('오늘 끼니 카드에는 지금처럼 탄단지가 보인다', (tester) async {
    await openDiet(tester);

    expect(macroLines(), findsWidgets);
    expect(find.textContaining('탄수화물'), findsWidgets);
  });

  testWidgets('이번 주에서 날짜를 펼치면 그 끼니의 탄단지가 보인다', (tester) async {
    await openDiet(tester, stubMeals: true);

    await tester.tap(find.byKey(const Key('client-period-week')));
    await tester.pumpAndSettle();
    await expandUntilMeals(tester);

    expect(
      find.byKey(const ValueKey<String>('client-diet-macros-meal-with-macros')),
      findsOneWidget,
    );
    final Text withMacros = tester.widget<Text>(
      find.byKey(const ValueKey<String>('client-diet-macros-meal-with-macros')),
    );
    // `오늘` 카드와 같은 순서·단위·서식이다.
    expect(withMacros.data, '탄수화물 92.5g · 단백질 21g · 지방 14g');

    // 영양이 아예 없는 옛 기록은 0g 이 아니라 `기록 없음` 이라고 말한다.
    final Text missing = tester.widget<Text>(
      find.byKey(
        const ValueKey<String>('client-diet-macros-meal-without-macros'),
      ),
    );
    expect(missing.data, '탄·단·지 기록 없음');
  });

  testWidgets('전체도 같은 컴포넌트를 쓴다', (tester) async {
    await openDiet(tester, stubMeals: true);

    await tester.tap(find.byKey(const Key('client-period-month')));
    await tester.pumpAndSettle();
    await expandUntilMeals(tester);

    final Text withMacros = tester.widget<Text>(
      find.byKey(const ValueKey<String>('client-diet-macros-meal-with-macros')),
    );
    expect(withMacros.data, '탄수화물 92.5g · 단백질 21g · 지방 14g');
  });
}
