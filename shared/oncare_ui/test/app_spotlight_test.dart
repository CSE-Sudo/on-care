import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 스포트라이트 안내(#1857) — 말풍선이 구멍 쪽에 붙고, 덮개는 아래 화면의 탭을
/// 삼킨다.
void main() {
  const Key caption = Key('caption');
  const Key skip = Key('skip');
  const Key next = Key('next');
  const Size screen = Size(400, 800);

  Future<void> pump(WidgetTester tester, {required Rect? hole}) async {
    await tester.binding.setSurfaceSize(screen);
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
                caption: const Text('여기를 보세요', key: caption),
                topBar: Row(
                  children: <Widget>[
                    const Spacer(),
                    AppSpotlightAction(
                      key: skip,
                      label: '건너뛰기',
                      onPressed: () {},
                    ),
                  ],
                ),
                bottomBar: Row(
                  children: <Widget>[
                    const Spacer(),
                    AppSpotlightAction(
                      key: next,
                      label: '다음',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('말풍선 자리', () {
    test('구멍 아래에 들어가면 아래, 좁으면 위, 둘 다 좁으면 가운데다', () {
      expect(
        AppSpotlight.placementFor(
          const Rect.fromLTWH(16, 80, 368, 120),
          screen,
        ),
        AppSpotlightPlacement.below,
      );
      expect(
        AppSpotlight.placementFor(const Rect.fromLTWH(16, 700, 90, 80), screen),
        AppSpotlightPlacement.above,
      );
      // 화면을 거의 다 덮는 자리 — 위아래 어디에도 들어가지 않는다.
      expect(
        AppSpotlight.placementFor(const Rect.fromLTWH(0, 20, 400, 760), screen),
        AppSpotlightPlacement.center,
      );
      expect(
        AppSpotlight.placementFor(null, screen),
        AppSpotlightPlacement.center,
      );
    });

    testWidgets('구멍이 위에 있으면 말풍선이 그 아래에 붙는다', (WidgetTester tester) async {
      const Rect hole = Rect.fromLTWH(16, 80, 368, 120);
      await pump(tester, hole: hole);

      final Rect bubble = tester.getRect(find.byType(AppSpotlightCallout));
      expect(bubble.top, greaterThan(hole.bottom));
      expect(bubble.bottom, lessThanOrEqualTo(screen.height));
      expect(find.byKey(caption), findsOneWidget);
    });

    testWidgets('구멍이 화면 아래 끝이면 말풍선이 위로 올라간다', (WidgetTester tester) async {
      // 하단 내비를 짚는 경우다 — 아래에는 말풍선이 들어갈 자리가 없다.
      const Rect hole = Rect.fromLTWH(16, 700, 90, 80);
      await pump(tester, hole: hole);

      final Rect bubble = tester.getRect(find.byType(AppSpotlightCallout));
      expect(bubble.bottom, lessThan(hole.top));
      expect(bubble.top, greaterThanOrEqualTo(0));
    });

    testWidgets('짚을 자리를 아직 못 찾았으면 구멍 없이 덮기만 한다', (WidgetTester tester) async {
      await pump(tester, hole: null);

      // 안내가 사라지지는 않는다 — 말풍선은 화면 가운데 남는다.
      final Rect bubble = tester.getRect(find.byType(AppSpotlightCallout));
      expect(bubble.top, greaterThan(0));
      expect(bubble.bottom, lessThan(screen.height));
    });
  });

  testWidgets('건너뛰기는 위, 다음은 아래에 선다', (WidgetTester tester) async {
    await pump(tester, hole: const Rect.fromLTWH(16, 300, 368, 120));

    final Rect skipRect = tester.getRect(find.byKey(skip));
    final Rect nextRect = tester.getRect(find.byKey(next));
    expect(skipRect.center.dy, lessThan(screen.height / 2));
    expect(nextRect.center.dy, greaterThan(screen.height / 2));
  });

  testWidgets('덮개 아래 화면은 눌리지 않는다', (WidgetTester tester) async {
    int taps = 0;
    await tester.binding.setSurfaceSize(screen);
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
                caption: Text('여기를 보세요', key: caption),
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
