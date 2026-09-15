import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 주간·월간 달력 복원(#1778) — `2db5b04` 시점 모양.
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

  group('월간 달력 격자', () {
    const List<String> labels = <String>['일', '월', '화', '수', '목', '금', '토'];

    Future<void> pumpGrid(
      WidgetTester tester, {
      required double height,
      Widget? Function(BuildContext, DateTime)? dayBuilder,
    }) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            height: height,
            child: AppMonthGrid(
              // 2026-09: 1일 화요일 → 선행 2칸 + 30일 = 5주.
              month: DateTime(2026, 9),
              weekdayLabels: labels,
              firstWeekday: DateTime.sunday,
              showWeekdayHeader: false,
              today: DateTime(2026, 9, 15),
              onSelected: (_) {},
              dayKey: (DateTime d) => Key('day-${d.day}'),
              dayBuilder: dayBuilder,
            ),
          ),
        ),
      );
    }

    testWidgets('높이가 넉넉하면 주 줄이 남은 높이를 나눠 갖는다', (WidgetTester tester) async {
      await pumpGrid(tester, height: 600);

      expect(tester.getSize(find.byKey(const Key('day-1'))).height, 120);
      expect(find.byKey(const Key('day-30')).hitTestable(), findsOneWidget);
    });

    testWidgets('높이가 모자라면 줄을 최소 높이로 두고 격자만 스크롤한다', (WidgetTester tester) async {
      await pumpGrid(tester, height: 200);

      expect(
        tester.getSize(find.byKey(const Key('day-1'))).height,
        OnCareCalendar.monthMinRowHeight,
      );
      final ScrollableState scrollable = tester.state(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('오늘 칸은 옅은 브랜드 바탕이고 넘치는 일정 칩은 잘린다', (WidgetTester tester) async {
      await pumpGrid(
        tester,
        height: 300,
        dayBuilder: (BuildContext _, DateTime day) => day.day == 15
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < 8; i++)
                    AppCalendarEventChip(
                      color: OnCareColors.success,
                      label: '0$i:00 일정 $i',
                    ),
                ],
              )
            : null,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('day-15')),
          matching: find.byType(AppCalendarEventChip),
        ),
        findsNWidgets(8),
      );
      final Container cell = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const Key('day-15')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (cell.decoration! as BoxDecoration).color,
        OnCareBrand.member.primary.withValues(
          alpha: OnCareCalendar.todayCellAlpha,
        ),
      );
    });
  });

  group('월간 달력 시트 조각', () {
    testWidgets('제목 옆 닫기는 옅은 브랜드(accent) 원이고 누르면 닫힌다', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (BuildContext context) => AppButton(
              label: '열기',
              onPressed: () => showAppSheet<void>(
                context: context,
                builder: (_) => AppCalendarSheetFrame(
                  header: <Widget>[
                    AppMonthCalendarHeader(
                      title: '일정',
                      monthLabel: '2026년 9월',
                      previousTooltip: '이전 달',
                      nextTooltip: '다음 달',
                      onPrevious: () {},
                      onNext: () {},
                      actionLabel: '일정 추가',
                      onAction: () {},
                    ),
                    const AppMonthWeekdayHeader(
                      labels: <String>['일', '월', '화', '수', '목', '금', '토'],
                    ),
                  ],
                  body: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      final Finder close = find
          .ancestor(
            of: find.byIcon(Icons.close_rounded),
            matching: find.byType(Material),
          )
          .first;
      expect(
        tester.getSize(close),
        const Size.square(OnCareCalendar.circleClose),
      );
      expect(
        tester.widget<Material>(close).color,
        OnCareBrand.member.surfaceAccent,
      );
      expect(find.widgetWithText(AppButton, '일정 추가'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('2026년 9월'), findsNothing);
    });
  });
}
