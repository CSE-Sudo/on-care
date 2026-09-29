import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 여러 칸 숫자 휠 (#2545).
///
/// 근력의 세트·횟수·중량을 스테퍼 세 줄로 받으면 유산소(시간 휠)와 모양이
/// 달라졌다 — 같은 띠·같은 높이의 휠 한 줄로 받는다.
void main() {
  /// 휠 하나를 [steps] 칸만큼 굴린다(양수가 아래로). `duration_wheel_test`
  /// 의 같은 헬퍼와 같다 — 다투는 스크롤이 없어 슬롭을 소진하지 않는다.
  Future<void> roll(WidgetTester tester, int column, int steps) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListWheelScrollView).at(column)),
    );
    await gesture.moveBy(Offset(0, -40.0 * steps));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// 세트(1~100)·중량(0~1000, 0.5) 두 칸을 띄운다. 지금 값을 돌려준다.
  Future<List<double>> pump(
    WidgetTester tester, {
    double sets = 3,
    double weight = 20,
  }) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final List<double> values = <double>[sets, weight];
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.member,
          density: OnCareDensity.mobile,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) =>
                AppNumberWheel(
                  columns: <AppNumberWheelColumn>[
                    AppNumberWheelColumn(
                      value: values[0],
                      min: 1,
                      max: 100,
                      unit: '세트',
                      onChanged: (double v) => setState(() => values[0] = v),
                    ),
                    AppNumberWheelColumn(
                      value: values[1],
                      min: 0,
                      max: 1000,
                      step: 0.5,
                      unit: 'kg',
                      onChanged: (double v) => setState(() => values[1] = v),
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return values;
  }

  testWidgets('지금 값에 맞춰 열린다', (WidgetTester tester) async {
    await pump(tester, sets: 12, weight: 40.5);

    expect(find.text('12 세트', findRichText: true), findsOneWidget);
    expect(find.text('40.5 kg', findRichText: true), findsOneWidget);
  });

  testWidgets('칸마다 굴린 값을 따로 올려보낸다', (WidgetTester tester) async {
    final List<double> values = await pump(tester);

    await roll(tester, 0, 2);
    expect(values, <double>[5, 20]);

    await roll(tester, 1, 5);
    expect(values, <double>[5, 22.5]);
  });

  testWidgets('중량은 0.5 걸음이고 딱 떨어지면 소수점을 뺀다', (WidgetTester tester) async {
    await pump(tester);

    // 가운데 칸 위아래로 19.5 · 20.5 가 보이고, 20 은 `20.0` 이 아니다.
    expect(find.text('19.5 kg', findRichText: true), findsOneWidget);
    expect(find.text('20 kg', findRichText: true), findsOneWidget);
    expect(find.text('20.5 kg', findRichText: true), findsOneWidget);
  });

  testWidgets('범위 끝을 넘겨 굴려도 끝 칸에 선다', (WidgetTester tester) async {
    final List<double> values = await pump(tester, sets: 99);

    await roll(tester, 0, 5);
    expect(values[0], 100);

    await roll(tester, 0, -200);
    expect(values[0], 1);
  });

  testWidgets('밖에서 값이 바뀌면 휠이 따라간다', (WidgetTester tester) async {
    double sets = 3;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.member,
          density: OnCareDensity.mobile,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              update = setState;
              return AppNumberWheel(
                columns: <AppNumberWheelColumn>[
                  AppNumberWheelColumn(
                    value: sets,
                    min: 1,
                    max: 100,
                    unit: '세트',
                    onChanged: (double v) => setState(() => sets = v),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    update(() => sets = 40);
    await tester.pumpAndSettle();

    // 가운데 칸이 40 이고 위아래로 39 · 41 이 보인다.
    expect(find.text('40 세트', findRichText: true), findsOneWidget);
    expect(find.text('39 세트', findRichText: true), findsOneWidget);
    expect(sets, 40, reason: '따라가며 다른 값을 올려보내지 않는다');
  });
}
