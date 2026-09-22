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
      DateTime? initialDate,
      DateTime? firstDate,
      DateTime? lastDate,
      Size viewSize = const Size(800, 1400),
    }) async {
      tester.view.physicalSize = viewSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
                    initialDate: initialDate ?? DateTime(2026, 8, 24),
                    firstDate: firstDate ?? DateTime(2026),
                    lastDate: lastDate ?? DateTime(2027),
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

    /// 창 안의 달력과 그 안의 [text].
    Finder calendar() => find.byType(AppCalendarDatePicker);
    Finder inCalendar(String text) =>
        find.descendant(of: calendar(), matching: find.text(text));

    /// 달력 머리 라벨을 눌러 달 보기 ↔ 날짜 보기를 오간다.
    Future<void> tapHeader(WidgetTester tester) async {
      await tester.tap(find.byKey(AppCalendarDatePicker.headerKey));
      await tester.pumpAndSettle();
    }

    /// 달 보기 칸 [text] 의 채움.
    BoxDecoration monthFill(WidgetTester tester, String text) =>
        tester
                .widget<Ink>(
                  find.ancestor(
                    of: inCalendar(text),
                    matching: find.byType(Ink),
                  ),
                )
                .decoration!
            as BoxDecoration;

    Color? textColor(WidgetTester tester, String text) =>
        tester.widget<Text>(inCalendar(text)).style!.color;

    IconButton arrow(WidgetTester tester, IconData icon) =>
        tester.widget<IconButton>(
          find.descendant(
            of: calendar(),
            matching: find.widgetWithIcon(IconButton, icon),
          ),
        );

    TextField input(WidgetTester tester) => tester.widget<TextField>(
      find.descendant(
        of: find.byKey(AppDatePickerDialog.inputKey),
        matching: find.byType(TextField),
      ),
    );

    const List<String> monthNames = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

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
        expect(find.byType(AppCalendarDatePicker), findsOneWidget);
        expect(find.byKey(AppDatePickerDialog.calendarKey), findsOneWidget);
        // Material 기본 달력(연도 목록으로만 바뀌는 머리)은 쓰지 않는다.
        expect(find.byType(CalendarDatePicker), findsNothing);

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
          of: find.byType(AppCalendarDatePicker),
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
      final AppCalendarDatePicker picker = tester.widget(calendar());
      expect(picker.selectedDate, DateTime(2026, 9, 30));
      expect(inCalendar('September 2026'), findsOneWidget);

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

    testWidgets('머리 달 라벨을 누르면 열두 달 격자로 바뀌고 보던 달이 브랜드 채움이다', (
      WidgetTester tester,
    ) async {
      await openPicker(tester);
      expect(inCalendar('August 2026'), findsOneWidget);

      await tapHeader(tester);

      for (final String month in monthNames) {
        expect(inCalendar(month), findsOneWidget, reason: month);
      }
      expect(inCalendar('2026'), findsOneWidget);
      // 날짜 격자는 사라진다(Material 연도 목록도 아니다).
      expect(inCalendar('24'), findsNothing);
      expect(find.byType(YearPicker), findsNothing);
      // 보던 달(8월)은 날짜 원과 같은 브랜드 채움 알약에 흰 글자다.
      expect(monthFill(tester, 'August').color, OnCareBrand.member.primary);
      expect(monthFill(tester, 'August').borderRadius, OnCareRadius.pillAll);
      expect(textColor(tester, 'August'), OnCareColors.textOnFill);
      expect(monthFill(tester, 'July').color, isNull);
      expect(textColor(tester, 'July'), OnCareColors.textPrimary);

      // 가운데 연도를 다시 누르면 보던 달의 날짜 보기로 돌아간다.
      await tapHeader(tester);
      expect(inCalendar('August 2026'), findsOneWidget);
      expect(inCalendar('24'), findsOneWidget);
    });

    testWidgets('달 보기의 꺾쇠는 해를 넘기고 고를 수 없는 해로는 가지 않는다', (
      WidgetTester tester,
    ) async {
      // 2026-01-01 ~ 2027-01-01.
      await openPicker(tester);
      await tapHeader(tester);

      expect(arrow(tester, Icons.chevron_left_rounded).onPressed, isNull);
      await tester.tap(
        find.descendant(
          of: calendar(),
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
      );
      await tester.pumpAndSettle();

      expect(inCalendar('2027'), findsOneWidget);
      expect(arrow(tester, Icons.chevron_right_rounded).onPressed, isNull);
      // 보던 달(2026년 8월)은 다른 해에서는 칠하지 않는다.
      expect(monthFill(tester, 'August').color, isNull);
      // 2027-01-01 까지만 고를 수 있어 1월만 열리고 2월부터는 흐리다.
      expect(textColor(tester, 'January'), OnCareColors.textPrimary);
      expect(textColor(tester, 'February'), OnCareColors.textDisabled);

      await tester.tap(
        find.descendant(
          of: calendar(),
          matching: find.byIcon(Icons.chevron_left_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(inCalendar('2026'), findsOneWidget);
      expect(monthFill(tester, 'August').color, OnCareBrand.member.primary);
    });

    testWidgets('달을 누르면 그 달 날짜로 돌아가고 고른 날은 날을 누를 때까지 그대로다', (
      WidgetTester tester,
    ) async {
      final List<DateTime?> results = await openPicker(tester);
      await tapHeader(tester);

      await tester.tap(inCalendar('November'));
      await tester.pumpAndSettle();

      expect(inCalendar('November 2026'), findsOneWidget);
      expect(
        tester.widget<AppCalendarDatePicker>(calendar()).selectedDate,
        DateTime(2026, 8, 24),
      );
      expect(input(tester).controller!.text, '08/24/2026');
      // 11월에는 고른 날이 없으니 채운 날짜 원도 없다.
      expect(
        find.descendant(
          of: calendar(),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Ink &&
                w.decoration is ShapeDecoration &&
                (w.decoration! as ShapeDecoration).color ==
                    OnCareBrand.member.primary,
          ),
        ),
        findsNothing,
      );

      await tester.tap(inCalendar('5'));
      await tester.pumpAndSettle();
      expect(input(tester).controller!.text, '11/05/2026');

      await tester.tap(find.byKey(AppDatePickerDialog.confirmKey));
      await tester.pumpAndSettle();
      expect(results, <DateTime?>[DateTime(2026, 11, 5)]);
    });

    testWidgets('기간과 하루도 겹치지 않는 달은 흐리고 눌러도 넘어가지 않는다(#1765)', (
      WidgetTester tester,
    ) async {
      await openPicker(
        tester,
        initialDate: DateTime(2026, 8, 24),
        firstDate: DateTime(2026, 3, 10),
        // 미래 막기: 오늘까지만 고른다.
        lastDate: DateTime(2026, 9, 15),
      );
      await tapHeader(tester);

      for (final String month in <String>[
        'January',
        'February',
        'October',
        'November',
        'December',
      ]) {
        expect(
          textColor(tester, month),
          OnCareColors.textDisabled,
          reason: month,
        );
      }
      // 일부라도 겹치는 3월·9월은 고를 수 있다.
      expect(textColor(tester, 'March'), OnCareColors.textPrimary);
      expect(textColor(tester, 'September'), OnCareColors.textPrimary);
      // 한 해 안의 기간이라 해 꺾쇠도 둘 다 막힌다.
      expect(arrow(tester, Icons.chevron_left_rounded).onPressed, isNull);
      expect(arrow(tester, Icons.chevron_right_rounded).onPressed, isNull);

      await tester.tap(inCalendar('October'));
      await tester.pumpAndSettle();
      expect(inCalendar('2026'), findsOneWidget);
      expect(inCalendar('October 2026'), findsNothing);

      await tester.tap(inCalendar('September'));
      await tester.pumpAndSettle();
      expect(inCalendar('September 2026'), findsOneWidget);
      // 9월 15일 뒤는 흐리고, 다음 달로도 가지 않는다.
      expect(textColor(tester, '20'), OnCareColors.textDisabled);
      expect(arrow(tester, Icons.chevron_right_rounded).onPressed, isNull);
    });

    testWidgets('달 보기에서 날짜를 타이핑하면 그 달의 날짜 보기로 돌아간다', (
      WidgetTester tester,
    ) async {
      await openPicker(tester);
      await tapHeader(tester);

      await tester.enterText(
        find.byKey(AppDatePickerDialog.inputKey),
        '10/3/2026',
      );
      await tester.pumpAndSettle();

      expect(inCalendar('October 2026'), findsOneWidget);
      expect(
        tester.widget<AppCalendarDatePicker>(calendar()).selectedDate,
        DateTime(2026, 10, 3),
      );
    });

    testWidgets('날짜 보기의 꺾쇠·좌우 밀기로 달을 넘기고 고른 날은 그대로다', (
      WidgetTester tester,
    ) async {
      await openPicker(tester);

      await tester.tap(
        find.descendant(
          of: calendar(),
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(inCalendar('September 2026'), findsOneWidget);

      // 오른쪽에서 왼쪽으로 쓸면 다음 달, 반대면 이전 달이다.
      await tester.fling(inCalendar('16'), const Offset(-200, 0), 1000);
      await tester.pumpAndSettle();
      expect(inCalendar('October 2026'), findsOneWidget);
      await tester.fling(inCalendar('16'), const Offset(200, 0), 1000);
      await tester.pumpAndSettle();
      expect(inCalendar('September 2026'), findsOneWidget);

      expect(
        tester.widget<AppCalendarDatePicker>(calendar()).selectedDate,
        DateTime(2026, 8, 24),
      );
    });

    testWidgets('달력 줄 높이는 Material 달력처럼 세로 화면 48·가로 화면 42 다', (
      WidgetTester tester,
    ) async {
      // 세로 화면(회원앱).
      await openPicker(tester);
      expect(
        tester.getSize(calendar()).height,
        OnCareCalendar.pickerHeaderHeight +
            OnCareCalendar.pickerRowHeightPortrait *
                (OnCareCalendar.pickerMaxWeeks + 1),
      );
      await tester.tap(find.byKey(AppDatePickerDialog.cancelKey));
      await tester.pumpAndSettle();

      // 가로 화면(데스크톱 트레이너웹) — 줄을 42 로 줄여 창이 커지지 않는다.
      await openPicker(
        tester,
        brand: OnCareBrand.trainer,
        density: OnCareDensity.web,
        viewSize: const Size(800, 600),
      );
      expect(
        tester.getSize(calendar()).height,
        OnCareCalendar.pickerHeaderHeight +
            OnCareCalendar.pickerRowHeightLandscape *
                (OnCareCalendar.pickerMaxWeeks + 1),
      );
      // 넷째 주 날짜가 하단 버튼 뒤로 가려지지 않고 바로 눌린다.
      expect(inCalendar('20').hitTestable(), findsOneWidget);
      await tester.tap(inCalendar('20'));
      await tester.pumpAndSettle();
      expect(input(tester).controller!.text, '08/20/2026');
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

    /// 창 안에서 [color] 로 칠한 [shape] 모양 DecoratedBox.
    Finder painted(Color color, BoxShape shape) => find.descendant(
      of: find.byKey(AppDateRangePickerDialog.dialogKey),
      matching: find.byWidgetPredicate(
        (Widget w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == color &&
            (w.decoration as BoxDecoration).shape == shape,
      ),
    );

    /// 시작·종료일 원(브랜드 채움).
    Finder circleCells() =>
        painted(OnCareBrand.trainer.primary, BoxShape.circle);

    /// 사이 날 띠(브랜드 강조 채움, #2183). 시작·종료일 칸의 안쪽 절반 조각도
    /// 포함한다.
    Finder bandCells() => painted(
      OnCareColors.onWhite(OnCareBrand.trainer.primary, OnCareAlpha.medium),
      BoxShape.rectangle,
    );

    /// [day] 숫자를 그린 글자.
    Text dayText(WidgetTester tester, String day) => tester.widget<Text>(
      find.descendant(
        of: find.byKey(AppDateRangePickerDialog.dialogKey),
        matching: find.text(day),
      ),
    );

    TextField field(WidgetTester tester, Key key) => tester.widget<TextField>(
      find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
    );

    testWidgets('한 달 격자·시작/종료 입력칸·2열 버튼을 그리고 기간을 원과 옅은 띠로 잇는다', (
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

      // 시작(7)·종료(10)는 브랜드 원에 흰 굵은 숫자.
      expect(circleCells(), findsNWidgets(2));
      for (final String cap in <String>['7', '10']) {
        expect(dayText(tester, cap).style!.color, OnCareColors.textOnFill);
        expect(dayText(tester, cap).style!.fontWeight, FontWeight.w700);
      }
      final Rect startCircle = tester.getRect(circleCells().first);
      expect(startCircle.center, tester.getCenter(find.text('7')));

      // 사이 날(8·9)은 칸 폭 전체의 옅은 띠에 짙은 브랜드 보통 굵기 숫자.
      for (final String mid in <String>['8', '9']) {
        expect(dayText(tester, mid).style!.color, OnCareBrand.trainer.strong);
        expect(dayText(tester, mid).style!.fontWeight, FontWeight.w500);
      }
      // 띠 조각 = 8·9 온칸 둘 + 7 의 오른쪽 절반 + 10 의 왼쪽 절반.
      expect(bandCells(), findsNWidgets(4));
      final List<Rect> bands = <Rect>[
        for (int i = 0; i < 4; i++) tester.getRect(bandCells().at(i)),
      ];
      final double cellWidth = bands[1].width;
      expect(bands[2].width, cellWidth);
      expect(bands[0].width, closeTo(cellWidth / 2, 0.01));
      expect(bands[3].width, closeTo(cellWidth / 2, 0.01));
      // 시작일은 원 가운데에서 오른쪽으로, 종료일은 원 가운데까지 띠가 붙는다.
      expect(bands[0].left, closeTo(startCircle.center.dx, 0.01));
      expect(
        bands[3].right,
        closeTo(tester.getRect(circleCells().last).center.dx, 0.01),
      );
      // 띠 높이는 원 지름과 같다.
      expect(bands[1].height, startCircle.height);
      // 범위 밖 숫자는 본문 색 그대로다.
      expect(dayText(tester, '15').style!.color, OnCareColors.textPrimary);
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

      // 종료일을 고르기 전에는 시작일 원 하나뿐이고 띠가 없다.
      expect(circleCells(), findsOneWidget);
      expect(bandCells(), findsNothing);

      await tester.tap(find.text('20'));
      await tester.pump();
      // 16~19 온칸 넷 + 15·20 의 안쪽 절반 둘.
      expect(circleCells(), findsNWidgets(2));
      expect(bandCells(), findsNWidgets(6));

      await tester.tap(find.byKey(AppDateRangePickerDialog.confirmKey));
      await tester.pumpAndSettle();
      expect(results, hasLength(1));
      expect(results.single!.start, DateTime(2026, 9, 15));
      expect(results.single!.end, DateTime(2026, 9, 20));
    });

    testWidgets('같은 날을 두 번 누르면 원 하나만 그리고 그 하루를 돌려준다', (
      WidgetTester tester,
    ) async {
      final List<DateTimeRange?> results = await openRangePicker(
        tester,
        initialRange: september,
      );

      await tester.tap(find.text('15'));
      await tester.pump();
      await tester.tap(find.text('15'));
      await tester.pump();

      expect(circleCells(), findsOneWidget);
      expect(bandCells(), findsNothing);
      expect(dayText(tester, '15').style!.color, OnCareColors.textOnFill);

      await tester.tap(find.byKey(AppDateRangePickerDialog.confirmKey));
      await tester.pumpAndSettle();
      expect(results.single!.start, DateTime(2026, 9, 15));
      expect(results.single!.end, DateTime(2026, 9, 15));
    });

    testWidgets('기간이 주를 넘기면 줄 끝에서 띠가 각진 채로 이어진다', (WidgetTester tester) async {
      // 2026-09-12 는 토요일(줄 끝), 13 은 일요일(다음 줄 처음) — en_US 는 일요일 시작.
      await openRangePicker(
        tester,
        initialRange: DateTimeRange(
          start: DateTime(2026, 9, 11),
          end: DateTime(2026, 9, 14),
        ),
      );

      // 12·13 온칸 둘 + 11·14 절반 둘. 모서리를 둥글리지 않는다.
      expect(bandCells(), findsNWidgets(4));
      for (final Element e in bandCells().evaluate()) {
        final BoxDecoration d =
            (e.widget as DecoratedBox).decoration as BoxDecoration;
        expect(d.borderRadius, isNull);
      }
      expect(dayText(tester, '12').style!.color, OnCareBrand.trainer.strong);
      expect(dayText(tester, '13').style!.color, OnCareBrand.trainer.strong);
      expect(
        tester.getRect(find.text('13')).top,
        greaterThan(tester.getRect(find.text('12')).bottom),
      );
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
