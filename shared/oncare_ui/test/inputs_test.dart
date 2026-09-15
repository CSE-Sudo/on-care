import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  OnCareBrand brand = OnCareBrand.member,
  OnCareDensity density = OnCareDensity.mobile,
}) {
  return tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(brand: brand, density: density),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('입력·선택 컴포넌트가 그려진다', (tester) async {
    await _pump(
      tester,
      SingleChildScrollView(
        child: Column(
          children: <Widget>[
            const AppTextField(label: '이름', hint: '입력', helper: '도움말'),
            const AppSearchField(hint: '검색', clearTooltip: '지우기'),
            AppSelectField<int>(
              label: '성별',
              value: 1,
              items: const <DropdownMenuItem<int>>[
                DropdownMenuItem<int>(value: 1, child: Text('남')),
                DropdownMenuItem<int>(value: 2, child: Text('여')),
              ],
              onChanged: (_) {},
            ),
            const Row(
              children: <Widget>[
                AppTag(label: '태그', tone: AppTagTone.brand),
                AppCountBadge(count: 120),
                AppStatusDot(),
              ],
            ),
            AppNumberStepper(
              value: 3,
              onChanged: (_) {},
              decreaseTooltip: '빼기',
              increaseTooltip: '더하기',
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('고르기 칩은 체크 없이 선택 상태를 바꾸고 높이가 밀도를 따른다', (tester) async {
    bool selected = false;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AppChoiceChip(
          label: '남성',
          selected: selected,
          onSelected: (v) => setState(() => selected = v),
        ),
      ),
      density: OnCareDensity.web,
    );
    expect(tester.getSize(find.byType(AppChoiceChip)).height, 32);
    await tester.tap(find.text('남성'));
    await tester.pump();
    expect(selected, isTrue);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('세그먼트 토글은 누른 값을 알린다', (tester) async {
    String value = 'day';
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AppSegmentedToggle<String>(
          segments: const <AppSegment<String>>[
            AppSegment<String>(value: 'day', label: '오늘'),
            AppSegment<String>(value: 'week', label: '주'),
          ],
          selected: value,
          onChanged: (v) => setState(() => value = v),
        ),
      ),
    );
    await tester.tap(find.text('주'));
    await tester.pumpAndSettle();
    expect(value, 'week');
  });

  group('세그먼트 토글은 이전 알약 모양이다(#1777)', () {
    const List<AppSegment<String>> segments = <AppSegment<String>>[
      AppSegment<String>(value: 'day', label: '오늘'),
      AppSegment<String>(value: 'week', label: '이번 주'),
    ];

    BoxDecoration segmentDecoration(WidgetTester tester, String label) =>
        tester
                .widget<AnimatedContainer>(
                  find.ancestor(
                    of: find.text(label),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration!
            as BoxDecoration;

    BoxDecoration trackDecoration(WidgetTester tester) =>
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byType(AppSegmentedToggle<String>),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;

    Color labelColor(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label)).style!.color!;

    for (final (OnCareBrand brand, OnCareDensity density)
        in <(OnCareBrand, OnCareDensity)>[
          (OnCareBrand.member, OnCareDensity.mobile),
          (OnCareBrand.trainer, OnCareDensity.web),
        ]) {
      testWidgets('${brand.name}: 트랙·선택 칸 모두 알약, 색은 브랜드를 따른다', (tester) async {
        await _pump(
          tester,
          AppSegmentedToggle<String>(
            segments: segments,
            selected: 'day',
            onChanged: (_) {},
          ),
          brand: brand,
          density: density,
        );

        final BoxDecoration track = trackDecoration(tester);
        expect(track.borderRadius, OnCareRadius.pillAll);
        expect(track.color, brand.segmentTrack);

        final BoxDecoration on = segmentDecoration(tester, '오늘');
        expect(on.borderRadius, OnCareRadius.pillAll);
        expect(on.color, brand.primary);
        expect(labelColor(tester, '오늘'), OnCareColors.textOnFill);

        final BoxDecoration off = segmentDecoration(tester, '이번 주');
        expect(off.color, Colors.transparent);
        expect(labelColor(tester, '이번 주'), brand.segmentLabel);
        expect(
          tester.widget<Text>(find.text('오늘')).style!.fontWeight,
          FontWeight.w700,
        );
      });
    }

    testWidgets('높이는 칩 높이로 고정하지 않고 글자에 맞춘다 — 두 밀도가 같다', (tester) async {
      final double line =
          OnCareTypography.segment.fontSize! * OnCareTypography.segment.height!;
      final double expected =
          line +
          OnCareSize.segmentPaddingVertical * 2 +
          OnCareSize.segmentTrackInset * 2;

      for (final OnCareDensity density in <OnCareDensity>[
        OnCareDensity.mobile,
        OnCareDensity.web,
      ]) {
        await _pump(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: AppSegmentedToggle<String>(
              segments: segments,
              selected: 'day',
              onChanged: (_) {},
            ),
          ),
          density: density,
        );
        expect(
          tester.getSize(find.byType(AppSegmentedToggle<String>)).height,
          closeTo(expected, 0.01),
          reason: density.name,
        );
      }
    });

    testWidgets('아이콘 칸과 부모 폭을 나누는 칸도 라벨이 온전하다', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 320,
          child: AppSegmentedToggle<String>(
            expand: true,
            selected: 'diet',
            onChanged: (_) {},
            segments: const <AppSegment<String>>[
              AppSegment<String>(
                value: 'diet',
                label: '식단',
                icon: Icons.restaurant_rounded,
              ),
              AppSegment<String>(
                value: 'workout',
                label: '운동',
                icon: Icons.fitness_center_rounded,
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(AppSegmentedToggle<String>)).width,
        320,
      );
      for (final String label in <String>['식단', '운동']) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(label))
              .didExceedMaxLines,
          isFalse,
          reason: label,
        );
      }
      expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
    });
  });

  testWidgets('입력창 기본 높이가 밀도를 따른다', (tester) async {
    await _pump(
      tester,
      const AppTextField(hint: '입력'),
      density: OnCareDensity.web,
    );
    expect(
      tester.getSize(find.byType(TextField)).height,
      greaterThanOrEqualTo(OnCareDensity.web.inputMedium),
    );
  });
}
