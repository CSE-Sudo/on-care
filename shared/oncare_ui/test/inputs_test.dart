import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

  group('세그먼트 토글 thumb 모양은 이전 식단·운동 스트립이다(#1777)', () {
    Widget strip({double width = 320}) => SizedBox(
      width: width,
      child: AppSegmentedToggle<String>(
        expand: true,
        style: AppSegmentedToggleStyle.thumb,
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
    );

    Finder segmentOf(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(AnimatedContainer),
    );

    testWidgets('옅은 띠 44 위 흰 엄지 + 브랜드 그림자, 선택 글자·아이콘은 메인 색', (tester) async {
      const OnCareBrand brand = OnCareBrand.trainer;
      await _pump(
        tester,
        Align(alignment: Alignment.topLeft, child: strip()),
        brand: brand,
        density: OnCareDensity.web,
      );
      final Finder toggle = find.byType(AppSegmentedToggle<String>);
      expect(
        tester.getSize(toggle),
        const Size(320, OnCareSize.segmentThumbTrackHeight),
      );

      final Container track = tester.widget<Container>(
        find.descendant(of: toggle, matching: find.byType(Container)).first,
      );
      final BoxDecoration trackDecoration = track.decoration! as BoxDecoration;
      expect(trackDecoration.color, brand.segmentThumbTrack);
      expect(trackDecoration.borderRadius, OnCareRadius.pillAll);
      final Border border =
          (track.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(border.top.color, brand.segmentThumbBorder);

      final BoxDecoration on =
          tester.widget<AnimatedContainer>(segmentOf('식단')).decoration!
              as BoxDecoration;
      expect(on.color, OnCareColors.surfaceCard);
      expect(on.borderRadius, OnCareRadius.pillAll);
      expect(on.boxShadow, OnCareShadows.segmentThumb(brand.primary));
      final BoxDecoration off =
          tester.widget<AnimatedContainer>(segmentOf('운동')).decoration!
              as BoxDecoration;
      expect(off.color, Colors.transparent);
      expect(off.boxShadow, isNull);

      expect(tester.widget<Text>(find.text('식단')).style!.color, brand.primary);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.restaurant_rounded)).color,
        brand.primary,
      );
      expect(
        tester.widget<Text>(find.text('운동')).style!.color,
        brand.segmentLabel,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.fitness_center_rounded)).color,
        brand.segmentLabel,
      );

      // 칸은 띠를 반씩 똑같이 나누고 위아래로 꽉 찬다.
      final Size diet = tester.getSize(segmentOf('식단'));
      expect(diet, tester.getSize(segmentOf('운동')));
      expect(diet.height, OnCareSize.segmentThumbTrackHeight);
    });

    testWidgets('폭을 반씩 나눠 받아도 아이콘 옆 라벨이 줄임표 없이 보인다', (tester) async {
      // 트레이너웹 오른쪽 열(380)에서 기간 토글과 한 줄을 나눠 받는 폭쯤이다.
      await _pump(
        tester,
        Align(alignment: Alignment.topLeft, child: strip(width: 180)),
        brand: OnCareBrand.trainer,
        density: OnCareDensity.web,
      );
      expect(tester.takeException(), isNull);
      for (final (String label, IconData icon) in <(String, IconData)>[
        ('식단', Icons.restaurant_rounded),
        ('운동', Icons.fitness_center_rounded),
      ]) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(label))
              .didExceedMaxLines,
          isFalse,
          reason: label,
        );
        expect(
          tester.getRect(find.byIcon(icon)).right,
          lessThan(tester.getRect(find.text(label)).left),
          reason: '$label 아이콘이 라벨 왼쪽에 있어야 한다',
        );
      }
    });
  });

  group('세그먼트 토글을 누르는 방식은 밀도를 따른다(#1820)', () {
    Widget toggle(
      ValueChanged<String> onChanged, {
      AppSegmentedToggleStyle style = AppSegmentedToggleStyle.fill,
    }) => AppSegmentedToggle<String>(
      style: style,
      selected: 'today',
      onChanged: onChanged,
      segments: const <AppSegment<String>>[
        AppSegment<String>(value: 'today', label: '오늘'),
        AppSegment<String>(value: 'week', label: '이번 주'),
      ],
    );

    Finder wells() => find.descendant(
      of: find.byType(AppSegmentedToggle<String>),
      matching: find.byType(InkWell),
    );

    for (final AppSegmentedToggleStyle style
        in AppSegmentedToggleStyle.values) {
      testWidgets(
        '${style.name}: 웹은 손가락 커서, Tab 포커스와 Enter 로 고른다',
        (tester) async {
          final List<String> picked = <String>[];
          await _pump(
            tester,
            Align(
              alignment: Alignment.topLeft,
              child: toggle(picked.add, style: style),
            ),
            brand: OnCareBrand.trainer,
            density: OnCareDensity.web,
          );
          expect(wells(), findsNWidgets(2));
          // 알약 전체가 누르는 자리다 — 물결 칸이 칸 크기와 같다.
          expect(
            tester.getSize(wells().last),
            tester.getSize(
              find.ancestor(
                of: find.text('이번 주'),
                matching: find.byType(AnimatedContainer),
              ),
            ),
          );

          final TestGesture mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
            pointer: 1,
          );
          addTearDown(mouse.removePointer);
          await mouse.addPointer(location: tester.getCenter(find.text('이번 주')));
          await tester.pump();
          expect(
            RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
            SystemMouseCursors.click,
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(picked, <String>['week']);
        },
      );
    }

    testWidgets('회원앱(모바일)은 이전처럼 탭만 받는다', (tester) async {
      final List<String> picked = <String>[];
      await _pump(
        tester,
        Align(alignment: Alignment.topLeft, child: toggle(picked.add)),
      );
      expect(wells(), findsNothing);
      await tester.tap(find.text('이번 주'));
      expect(picked, <String>['week']);
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

  testWidgets('활성 입력창은 흰 채움·진한 글자, 비활성은 회색 채움·흐린 글자다(#1776)', (tester) async {
    await _pump(
      tester,
      const Column(
        children: <Widget>[
          AppTextField(key: ValueKey<String>('on'), hint: '입력'),
          AppTextField(
            key: ValueKey<String>('off'),
            hint: '입력',
            enabled: false,
          ),
        ],
      ),
    );
    // 테마 기본값이 합쳐진 실제 장식을, 그 칸의 상태로 풀어 본다.
    (Color, Color?) look(String key) {
      final Finder field = find.byKey(ValueKey<String>(key));
      final InputDecoration decoration = tester
          .widget<InputDecorator>(
            find.descendant(of: field, matching: find.byType(InputDecorator)),
          )
          .decoration;
      final Color fill = WidgetStateProperty.resolveAs<Color>(
        decoration.fillColor!,
        <WidgetState>{if (!decoration.enabled) WidgetState.disabled},
      );
      final Color? text = tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .style
          .color;
      return (fill, text);
    }

    expect(look('on'), (OnCareColors.surfaceCard, OnCareColors.textPrimary));
    expect(look('off'), (OnCareColors.surfaceInput, OnCareColors.textDisabled));
  });
}
