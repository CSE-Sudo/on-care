import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 날짜·기간 선택창 복원(#1778).
///
/// 날짜 선택창 부분은 두 앱에 있던 옛 `portrait_date_picker_test.dart`
/// (`2db5b04`)의 뜻을 공용 컴포넌트로 옮긴 것이다.
void main() {
  const List<(OnCareBrand, OnCareDensity)> themes =
      <(OnCareBrand, OnCareDensity)>[
        (OnCareBrand.member, OnCareDensity.mobile),
        (OnCareBrand.trainer, OnCareDensity.web),
      ];

  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host({
    required OnCareBrand brand,
    required OnCareDensity density,
    required Widget child,
  }) {
    return MaterialApp(
      theme: OnCareTheme.light(brand: brand, density: density),
      home: Scaffold(body: child),
    );
  }

  group('날짜 선택창', () {
    /// 열기 버튼 하나짜리 화면을 띄우고 창을 연다. 닫힌 뒤 돌려받은 값은
    /// 돌려준 목록에 쌓인다 — 한 번도 닫히지 않았으면 비어 있다.
    Future<List<DateTime?>> openPicker(
      WidgetTester tester, {
      OnCareBrand brand = OnCareBrand.member,
      OnCareDensity density = OnCareDensity.mobile,
      String? helpText,
    }) async {
      useTallView(tester);
      final List<DateTime?> results = <DateTime?>[];
      await tester.pumpWidget(
        host(
          brand: brand,
          density: density,
          child: Builder(
            builder: (BuildContext context) => AppButton(
              label: '달력 열기',
              onPressed: () async {
                results.add(
                  await showAppDatePicker(
                    context: context,
                    initialDate: DateTime(2026, 8, 24),
                    firstDate: DateTime(2026),
                    lastDate: DateTime(2027),
                    helpText: helpText,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('달력 열기'));
      await tester.pumpAndSettle();
      return results;
    }

    for (final (OnCareBrand brand, OnCareDensity density) in themes) {
      testWidgets('$brand · 흰 창에 닫기 X·입력창·달력·2열 취소/확인이 모두 보인다', (
        WidgetTester tester,
      ) async {
        await openPicker(tester, brand: brand, density: density);

        final Finder dialog = find.byKey(AppDatePickerDialog.dialogKey);
        expect(dialog, findsOneWidget);
        // 창 표면(Dialog 안 Material)이 흰 카드 색이고 폭은 400 을 넘지 않는다.
        final Finder surface = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first;
        expect(
          tester.widget<Material>(surface).color,
          OnCareColors.surfaceCard,
        );
        expect(
          tester.getSize(surface).width,
          lessThanOrEqualTo(OnCareLayout.dialogSmall),
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.byIcon(Icons.close_rounded),
          ),
          findsOneWidget,
        );
        // 전환 없이 입력창과 달력이 항상 같이 보인다.
        expect(find.byKey(AppDatePickerDialog.inputKey), findsOneWidget);
        expect(find.byType(CalendarDatePicker), findsOneWidget);

        // 아래 버튼은 창 안 2열 둥근 네모 — 왼쪽 취소, 오른쪽 확인, 폭이 같다.
        final Rect cancel = tester.getRect(
          find.byKey(AppDatePickerDialog.cancelKey),
        );
        final Rect confirm = tester.getRect(
          find.byKey(AppDatePickerDialog.confirmKey),
        );
        expect(cancel.width, confirm.width);
        expect(cancel.top, confirm.top);
        expect(cancel.right, lessThan(confirm.left));
        expect(find.byType(AppButtonPair), findsOneWidget);
      });
    }

    testWidgets('제목은 플랫폼 문구이고 helpText 로 바꿀 수 있다', (WidgetTester tester) async {
      await openPicker(tester, helpText: '기록 날짜');
      expect(find.text('기록 날짜'), findsOneWidget);
    });

    testWidgets('달력에서 날짜를 고르면 입력창 글자도 같이 바뀐다', (WidgetTester tester) async {
      await openPicker(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text('30'),
        ),
      );
      await tester.pumpAndSettle();

      final TextField field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(AppDatePickerDialog.inputKey),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, contains('30'));
    });

    testWidgets('입력창에 유효한 날짜를 타이핑하면 달력도 그 날짜로 움직인다', (
      WidgetTester tester,
    ) async {
      final List<DateTime?> results = await openPicker(tester);

      await tester.enterText(
        find.byKey(AppDatePickerDialog.inputKey),
        '9/30/2026',
      );
      await tester.pumpAndSettle();

      // 달력이 9월로 넘어가 30일을 고른 상태다.
      final CalendarDatePicker calendar = tester.widget(
        find.byType(CalendarDatePicker),
      );
      expect(calendar.initialDate, DateTime(2026, 9, 30));

      await tester.tap(find.byKey(AppDatePickerDialog.confirmKey));
      await tester.pumpAndSettle();
      expect(results, <DateTime?>[DateTime(2026, 9, 30)]);
    });

    testWidgets('입력창에 범위 밖 날짜를 타이핑하면 오류를 보여주고 확인을 막는다', (
      WidgetTester tester,
    ) async {
      final List<DateTime?> results = await openPicker(tester);

      await tester.enterText(
        find.byKey(AppDatePickerDialog.inputKey),
        '1/1/2020',
      );
      await tester.pumpAndSettle();

      final MaterialLocalizations l = MaterialLocalizations.of(
        tester.element(find.byKey(AppDatePickerDialog.dialogKey)),
      );
      expect(find.text(l.dateOutOfRangeLabel), findsOneWidget);

      await tester.tap(find.byKey(AppDatePickerDialog.confirmKey));
      await tester.pumpAndSettle();

      // 창이 열려 있어야 한다 — 확인이 막혔다.
      expect(find.byKey(AppDatePickerDialog.dialogKey), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('형식이 틀린 입력은 형식 오류를 보여준다', (WidgetTester tester) async {
      await openPicker(tester);

      await tester.enterText(find.byKey(AppDatePickerDialog.inputKey), 'abc');
      await tester.pumpAndSettle();

      final MaterialLocalizations l = MaterialLocalizations.of(
        tester.element(find.byKey(AppDatePickerDialog.dialogKey)),
      );
      expect(find.text(l.invalidDateFormatLabel), findsOneWidget);
    });

    testWidgets('오른쪽 위 X 를 누르면 아무 값 없이 닫힌다', (WidgetTester tester) async {
      final List<DateTime?> results = await openPicker(tester);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byKey(AppDatePickerDialog.dialogKey), findsNothing);
      expect(results, <DateTime?>[null]);
    });

    testWidgets('취소를 누르면 아무 값 없이 닫힌다', (WidgetTester tester) async {
      final List<DateTime?> results = await openPicker(tester);

      await tester.tap(find.byKey(AppDatePickerDialog.cancelKey));
      await tester.pumpAndSettle();

      expect(results, <DateTime?>[null]);
    });

    testWidgets('확인을 누르면 고른 날짜를 돌려준다', (WidgetTester tester) async {
      final List<DateTime?> results = await openPicker(tester);

      await tester.tap(find.byKey(AppDatePickerDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(results, <DateTime?>[DateTime(2026, 8, 24)]);
    });
  });

  group('기간 선택창', () {
    Future<List<DateTimeRange?>> openRangePicker(
      WidgetTester tester, {
      DateTimeRange? initialRange,
    }) async {
      useTallView(tester);
      final List<DateTimeRange?> results = <DateTimeRange?>[];
      await tester.pumpWidget(
        host(
          brand: OnCareBrand.trainer,
          density: OnCareDensity.web,
          child: Builder(
            builder: (BuildContext context) => AppButton(
              label: '기간 열기',
              onPressed: () async {
                results.add(
                  await showAppDateRangePicker(
                    context: context,
                    firstDate: DateTime(2026),
                    lastDate: DateTime(2026, 12, 31),
                    initialRange: initialRange,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('기간 열기'));
      await tester.pumpAndSettle();
      return results;
    }

    final DateTimeRange september = DateTimeRange(
      start: DateTime(2026, 9, 7),
      end: DateTime(2026, 9, 10),
    );

    /// 기간 띠(브랜드 채움) 칸.
    Finder bandCells() => find.descendant(
      of: find.byKey(AppDateRangePickerDialog.dialogKey),
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color ==
                OnCareBrand.trainer.primary,
      ),
    );

    TextField field(WidgetTester tester, Key key) => tester.widget<TextField>(
      find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
    );

    testWidgets('한 달 격자·시작/종료 입력칸·2열 버튼을 그리고 기간을 브랜드 띠로 잇는다', (
      WidgetTester tester,
    ) async {
      await openRangePicker(tester, initialRange: september);

      expect(find.byKey(AppDateRangePickerDialog.dialogKey), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);
      // 옛 앱에서 보이던 크기(옛 16 × 1.1 → 18, 옛 12 × 1.1 → 13).
      expect(
        tester.widget<Text>(find.text('September 2026')).style!.fontSize,
        18,
      );
      expect(tester.widget<Text>(find.text('15')).style!.fontSize, 18);
      expect(
        tester.widget<Text>(find.text('7')).style!.fontWeight,
        FontWeight.w700,
      );
      final MaterialLocalizations ml = MaterialLocalizations.of(
        tester.element(find.byKey(AppDateRangePickerDialog.dialogKey)),
      );
      expect(
        tester
            .widget<Text>(find.text(ml.narrowWeekdays[1]).first)
            .style!
            .fontSize,
        13,
      );
      expect(
        field(tester, AppDateRangePickerDialog.startInputKey).controller!.text,
        '09/07/2026',
      );
      expect(
        field(tester, AppDateRangePickerDialog.endInputKey).controller!.text,
        '09/10/2026',
      );
      expect(find.byKey(AppDateRangePickerDialog.cancelKey), findsOneWidget);
      expect(find.byKey(AppDateRangePickerDialog.confirmKey), findsOneWidget);

      // 7·8·9·10 네 칸이 한 띠다. 양 끝만 둥글다.
      expect(bandCells(), findsNWidgets(4));
      final List<BorderRadius> radii = <BorderRadius>[
        for (final Element e in bandCells().evaluate())
          ((e.widget as DecoratedBox).decoration as BoxDecoration).borderRadius!
              as BorderRadius,
      ];
      expect(radii.first.topLeft, OnCareRadius.pill);
      expect(radii.first.topRight, Radius.zero);
      expect(radii.last.topRight, OnCareRadius.pill);
      expect(radii.last.topLeft, Radius.zero);
    });

    testWidgets('두 번 탭해 새 기간을 고르고 확인하면 그 기간을 돌려준다', (
      WidgetTester tester,
    ) async {
      final List<DateTimeRange?> results = await openRangePicker(
        tester,
        initialRange: september,
      );

      await tester.tap(find.text('15'));
      await tester.pump();
      // 종료일이 비어 있는 동안 확인은 닫지 않는다.
      await tester.tap(find.byKey(AppDateRangePickerDialog.confirmKey));
      await tester.pumpAndSettle();
      expect(find.byKey(AppDateRangePickerDialog.dialogKey), findsOneWidget);
      expect(
        field(tester, AppDateRangePickerDialog.endInputKey).controller!.text,
        isEmpty,
      );

      await tester.tap(find.text('20'));
      await tester.pump();
      expect(bandCells(), findsNWidgets(6));

      await tester.tap(find.byKey(AppDateRangePickerDialog.confirmKey));
      await tester.pumpAndSettle();
      expect(results, hasLength(1));
      expect(results.single!.start, DateTime(2026, 9, 15));
      expect(results.single!.end, DateTime(2026, 9, 20));
    });

    testWidgets('시작일을 종료일 뒤로 타이핑하면 종료일을 비운다', (WidgetTester tester) async {
      await openRangePicker(tester, initialRange: september);

      await tester.enterText(
        find.byKey(AppDateRangePickerDialog.startInputKey),
        '9/12/2026',
      );
      await tester.pump();

      expect(
        field(tester, AppDateRangePickerDialog.endInputKey).controller!.text,
        isEmpty,
      );
      expect(bandCells(), findsNothing);
    });

    testWidgets('첫 달에서는 이전 달로 못 가고, 다음 달로는 한 달씩 넘긴다', (
      WidgetTester tester,
    ) async {
      await openRangePicker(
        tester,
        initialRange: DateTimeRange(
          start: DateTime(2026, 1, 5),
          end: DateTime(2026, 1, 6),
        ),
      );

      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();
      expect(find.text('February 2026'), findsOneWidget);
    });

    testWidgets('처음 기간이 없으면 두 칸이 비고 취소하면 null 이다', (WidgetTester tester) async {
      final List<DateTimeRange?> results = await openRangePicker(tester);

      expect(
        field(tester, AppDateRangePickerDialog.startInputKey).controller!.text,
        isEmpty,
      );
      await tester.tap(find.byKey(AppDateRangePickerDialog.cancelKey));
      await tester.pumpAndSettle();
      expect(results, <DateTimeRange?>[null]);
    });
  });
}
