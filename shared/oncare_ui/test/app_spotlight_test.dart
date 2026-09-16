import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 스포트라이트 안내(#1857) — 구멍 위치에 따라 설명이 자리를 옮기고, 덮개는
/// 아래 화면의 탭을 삼킨다.
void main() {
  const Key caption = Key('caption');

  Future<void> pump(WidgetTester tester, {required Rect? hole}) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.member,
          density: OnCareDensity.mobile,
        ),
        home: Stack(
          children: <Widget>[
            Positioned.fill(
              child: AppSpotlight(
                hole: hole,
                caption: const SizedBox(key: caption, width: 300, height: 160),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('구멍이 위에 있으면 설명이 그 아래에 붙는다', (WidgetTester tester) async {
    const Rect hole = Rect.fromLTWH(16, 80, 368, 120);
    await pump(tester, hole: hole);

    final Rect card = tester.getRect(find.byKey(caption));
    expect(card.top, greaterThan(hole.bottom));
    expect(card.bottom, lessThanOrEqualTo(800));
  });

  testWidgets('구멍이 화면 아래 끝이면 설명이 위로 올라간다', (WidgetTester tester) async {
    // 하단 내비를 짚는 경우다 — 아래에는 카드가 들어갈 자리가 없다.
    const Rect hole = Rect.fromLTWH(16, 700, 90, 80);
    await pump(tester, hole: hole);

    final Rect card = tester.getRect(find.byKey(caption));
    expect(card.bottom, lessThan(hole.top));
    expect(card.top, greaterThanOrEqualTo(0));
  });

  testWidgets('짚을 자리를 아직 못 찾았으면 구멍 없이 덮기만 한다', (WidgetTester tester) async {
    await pump(tester, hole: null);

    // 안내가 사라지지는 않는다 — 설명은 화면 가운데 남는다.
    final Rect card = tester.getRect(find.byKey(caption));
    expect(card.top, greaterThan(0));
    expect(card.bottom, lessThan(800));
  });

  testWidgets('덮개 아래 화면은 눌리지 않는다', (WidgetTester tester) async {
    int taps = 0;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.member,
          density: OnCareDensity.mobile,
        ),
        home: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                key: const Key('below'),
                behavior: HitTestBehavior.opaque,
                onTap: () => taps += 1,
              ),
            ),
            const Positioned.fill(
              child: AppSpotlight(
                hole: Rect.fromLTWH(16, 80, 368, 120),
                caption: SizedBox(key: caption, width: 300, height: 160),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(200, 600));
    await tester.pumpAndSettle();

    // 안내 도중 화면이 바뀌면 방금 짚은 자리가 사라진다.
    expect(taps, 0);
  });
}
