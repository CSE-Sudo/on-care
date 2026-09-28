import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<void> _pump(WidgetTester tester, Widget bar) => tester.pumpWidget(
  MaterialApp(
    theme: OnCareTheme.light(
      brand: OnCareBrand.trainer,
      density: OnCareDensity.web,
    ),
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Scaffold(
        body: Center(child: SizedBox(width: 200, child: bar)),
      ),
    ),
  ),
);

LinearProgressIndicator _indicator(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));

void main() {
  testWidgets('기본값은 높이 8·입력 채움 트랙이다', (tester) async {
    await _pump(tester, const AppProgressBar(value: 0.5));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(AppProgressBar)).height,
      OnCareSize.progressBar,
    );
    expect(_indicator(tester).minHeight, OnCareSize.progressBar);
    expect(_indicator(tester).backgroundColor, OnCareColors.surfaceInput);
  });

  testWidgets('두께·트랙 색을 바꿀 수 있다', (tester) async {
    await _pump(
      tester,
      const AppProgressBar(
        value: 0,
        height: OnCareSize.progressBarThick,
        trackColor: OnCareColors.lineStrong,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(AppProgressBar)).height,
      OnCareSize.progressBarThick,
    );
    expect(_indicator(tester).minHeight, OnCareSize.progressBarThick);
    expect(_indicator(tester).backgroundColor, OnCareColors.lineStrong);
  });

  testWidgets('값이 1 을 넘으면 1 로, 0 보다 작으면 0 으로 그린다', (tester) async {
    await _pump(tester, const AppProgressBar(value: 1.7));
    await tester.pumpAndSettle();
    expect(_indicator(tester).value, 1);

    await _pump(tester, const AppProgressBar(value: -0.3));
    await tester.pumpAndSettle();
    expect(_indicator(tester).value, 0);
  });

  test('두꺼운 막대는 기본 막대보다 두껍다', () {
    expect(OnCareSize.progressBarThick, greaterThan(OnCareSize.progressBar));
  });
}
