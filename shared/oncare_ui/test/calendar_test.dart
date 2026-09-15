import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 주간 달력 복원(#1778) — `2db5b04` 시점 모양.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: OnCareTheme.light(
        brand: OnCareBrand.member,
        density: OnCareDensity.mobile,
      ),
      home: Scaffold(body: child),
    );
  }

  group('주간 달력', () {
    final List<DateTime> week = List<DateTime>.generate(
      7,
      (int i) => DateTime(2026, 9, 14 + i),
    );
    const List<String> labels = <String>['월', '화', '수', '목', '금', '토', '일'];

    Future<void> pumpStrip(
      WidgetTester tester, {
      required DateTime selected,
      ValueChanged<DateTime>? onSelected,
      VoidCallback? onNext,
      VoidCallback? onToday,
    }) async {
      await tester.pumpWidget(
        host(
          AppWeekStrip(
            label: '9월 3주차',
            todayLabel: '오늘',
            onToday: onToday,
            todayKey: const Key('today-pill'),
            days: week,
            weekdayLabels: labels,
            selected: selected,
            today: DateTime(2026, 9, 16),
            onSelected: onSelected ?? (_) {},
            lastSelectableDay: DateTime(2026, 9, 16),
            previousTooltip: '지난 주',
            nextTooltip: '다음 주',
            onPrevious: () {},
            onNext: onNext,
          ),
        ),
      );
    }

    testWidgets('양옆 원형 꺾쇠 — 갈 수 없는 쪽은 흐리다', (WidgetTester tester) async {
      await pumpStrip(tester, selected: DateTime(2026, 9, 16));

      Opacity opacityOf(IconData icon) => tester.widget<Opacity>(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(Opacity)),
      );
      expect(opacityOf(Icons.chevron_left_rounded).opacity, 1);
      expect(
        opacityOf(Icons.chevron_right_rounded).opacity,
        OnCareCalendar.disabledArrowOpacity,
      );
      final Finder arrow = find
          .ancestor(
            of: find.byIcon(Icons.chevron_left_rounded),
            matching: find.byType(Material),
          )
          .first;
      expect(
        tester.getSize(arrow),
        const Size.square(OnCareCalendar.weekArrow),
      );
      expect(
        tester.widget<Material>(arrow).color,
        OnCareBrand.member.surfaceSoft,
      );
    });

    testWidgets('글자·날짜 칸은 옛 앱에서 보이던 크기(× 1.1)다', (WidgetTester tester) async {
      await pumpStrip(tester, selected: DateTime(2026, 9, 15), onToday: () {});

      double sizeOf(String text) =>
          tester.widget<Text>(find.text(text)).style!.fontSize!;
      expect(sizeOf('9월 3주차'), 15); // 옛 13.5
      expect(sizeOf('월'), 13); // 옛 12
      expect(sizeOf('15'), 15); // 옛 13.5
      expect(sizeOf('오늘'), 13); // 옛 12
      final Finder box = find
          .ancestor(of: find.text('15'), matching: find.byType(Container))
          .first;
      expect(tester.getSize(box), const Size.square(33)); // 옛 30
    });

    testWidgets('좁은 화면·큰 글자 배율에서도 넘치거나 잘리지 않는다', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (BuildContext context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  child: AppWeekStrip(
                    label: 'September, week 3 of the month',
                    todayLabel: 'Today',
                    onToday: () {},
                    days: week,
                    weekdayLabels: const <String>[
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat',
                      'Sun',
                    ],
                    selected: DateTime(2026, 9, 20),
                    today: DateTime(2026, 9, 20),
                    onSelected: (_) {},
                    previousTooltip: '지난 주',
                    nextTooltip: '다음 주',
                    onPrevious: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // 칸은 한 칸 폭(양옆 화살표를 뺀 폭의 1/7)을 넘지 않는다.
      const double cellWidth = (320 - 2 * OnCareCalendar.weekArrow) / 7;
      final Finder box = find
          .ancestor(of: find.text('20'), matching: find.byType(Container))
          .first;
      expect(tester.getSize(box).width, lessThanOrEqualTo(cellWidth));
      // 날짜 숫자는 칸 안에 온전히 들어간다.
      final Rect number = tester.getRect(find.text('20'));
      final Rect boxRect = tester.getRect(box);
      expect(number.left, greaterThanOrEqualTo(boxRect.left));
      expect(number.right, lessThanOrEqualTo(boxRect.right));
    });

    testWidgets('선택한 날은 브랜드 채움 칸에 카드 그림자다', (WidgetTester tester) async {
      await pumpStrip(tester, selected: DateTime(2026, 9, 15));

      final Container box = tester.widget<Container>(
        find
            .ancestor(of: find.text('15'), matching: find.byType(Container))
            .first,
      );
      final BoxDecoration decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, OnCareBrand.member.primary);
      expect(decoration.boxShadow, OnCareShadows.card);
    });

    testWidgets('오늘 뒤의 날은 눌러도 고르지 않는다(#1765)', (WidgetTester tester) async {
      final List<DateTime> picked = <DateTime>[];
      await pumpStrip(
        tester,
        selected: DateTime(2026, 9, 16),
        onSelected: picked.add,
      );

      await tester.tap(find.text('18'));
      await tester.tap(find.text('15'));
      expect(picked, <DateTime>[DateTime(2026, 9, 15)]);
    });

    testWidgets('`오늘` 알약은 동작이 있을 때만 보이고 누르면 오늘로 돌아간다', (
      WidgetTester tester,
    ) async {
      await pumpStrip(tester, selected: DateTime(2026, 9, 16));
      expect(find.byKey(const Key('today-pill')), findsNothing);
      expect(find.text('9월 3주차'), findsOneWidget);

      int taps = 0;
      await pumpStrip(
        tester,
        selected: DateTime(2026, 9, 15),
        onToday: () => taps++,
      );
      await tester.tap(find.byKey(const Key('today-pill')));
      expect(taps, 1);
    });
  });
}
