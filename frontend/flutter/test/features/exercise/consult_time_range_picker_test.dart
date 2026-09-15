import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/presentation/widgets/consult_time_range_picker.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 상담 신청 전용 시간 선택창(#1779 — `2db5b04` 모양 복원).
///
/// 창 자체의 동작은 `oncare_ui` 의 `time_picker_test.dart` 가 다룬다. 여기서는
/// 회원앱이 넣는 문구·키(`consult-time-range-…`)와 이 함수가 지키는 약속을 본다.
void main() {
  late TimeRangeValue? result;
  late bool completed;

  Future<void> openPicker(WidgetTester tester) async {
    result = null;
    completed = false;
    // 실제 폰 크기 — 시계판(280)과 아래 두 버튼이 한 화면에 들어간다.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              result = await showConsultTimeRangePicker(
                context: context,
                start: const TimeOfDay(hour: 10, minute: 0),
                end: const TimeOfDay(hour: 11, minute: 0),
              );
              completed = true;
            },
            child: const Text('시간 선택 열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('시간 선택 열기'));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) => AppLocalizations.of(
    tester.element(find.byType(AppTimeRangePickerDialog)),
  );

  Finder byKey(String value) => find.byKey(ValueKey<String>(value));

  Finder confirmButton() => find
      .descendant(
        of: find.byType(AppTimeRangePickerDialog),
        matching: find.byType(AppButton),
      )
      .last;

  testWidgets('한 창에 제목·닫기·시작/종료 칸·단계 라벨·오전/오후·시계판이 있고 '
      '키보드 전환 버튼은 없다', (WidgetTester tester) async {
    await openPicker(tester);
    final AppLocalizations l = l10n(tester);

    // Material 시계를 두 번 여는 방식이 아니다.
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.text(l.exTimeRangeTitle), findsOneWidget);
    expect(find.byType(AppCloseButton), findsOneWidget);
    expect(find.text(l.exTimeRangeStartTime), findsOneWidget);
    expect(find.text(l.exTimeRangeEndTime), findsOneWidget);
    expect(find.text(l.exTimeRangeStartHourStep), findsOneWidget);
    expect(find.text(l.exSlotAm), findsOneWidget);
    expect(find.text(l.exSlotPm), findsOneWidget);
    expect(find.byType(AppClockDial), findsOneWidget);
    // 아이콘 버튼은 닫기 X 하나뿐이다 — 키보드 전환 버튼이 없다.
    expect(
      find.descendant(
        of: find.byType(AppTimeRangePickerDialog),
        matching: find.byType(IconButton),
      ),
      findsOneWidget,
    );
    // 아래는 2열 취소 / 확인이다.
    expect(find.byType(AppButtonPair), findsOneWidget);
    expect(find.text(l.actionCancel), findsOneWidget);
    expect(find.text(l.actionConfirm), findsOneWidget);
  });

  testWidgets('시작 시간 입력에 24시간 기준 값을 직접 타이핑할 수 있다', (WidgetTester tester) async {
    await openPicker(tester);

    await tester.enterText(byKey('consult-time-range-start-input'), '23:30');
    await tester.pump();

    expect(
      tester
          .widget<TextField>(byKey('consult-time-range-start-input'))
          .controller!
          .text,
      '23:30',
    );
  });

  testWidgets('종료 시간이 시작 시간보다 빠르면 확인을 막고 안내한다', (WidgetTester tester) async {
    await openPicker(tester);

    // 시작 시(10) → 시작 분(0) → 종료 시(9)까지 시계판으로 고른다.
    await tester.tap(byKey('consult-time-range-clock-value-10'));
    await tester.pump();
    await tester.tap(byKey('consult-time-range-clock-value-0'));
    await tester.pump();
    await tester.tap(byKey('consult-time-range-clock-value-9'));
    await tester.pump();

    expect(byKey('consult-time-range-invalid-end'), findsOneWidget);
    expect(find.text(l10n(tester).exTimeRangeInvalidEnd), findsOneWidget);
    expect(tester.widget<AppButton>(confirmButton()).onPressed, isNull);
  });

  testWidgets('확인을 누르면 고른 시작·종료 시각을 돌려준다', (WidgetTester tester) async {
    await openPicker(tester);

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(find.byType(AppTimeRangePickerDialog), findsNothing);
    expect(completed, isTrue);
    expect(result, (
      start: const TimeOfDay(hour: 10, minute: 0),
      end: const TimeOfDay(hour: 11, minute: 0),
    ));
  });

  testWidgets('닫기 X 로 닫으면 null 이다', (WidgetTester tester) async {
    await openPicker(tester);

    await tester.tap(find.byType(AppCloseButton));
    await tester.pumpAndSettle();

    expect(find.byType(AppTimeRangePickerDialog), findsNothing);
    expect(completed, isTrue);
    expect(result, isNull);
  });
}
