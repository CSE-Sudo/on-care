import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/ai_routine_item.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_editor_workspace.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 프로그램 직접 만들기의 PT 등록 날짜·시각 선택 UI. (#1425)
///
/// 앱의 다른 입력 화면과 같은 세로형 달력(`showPortraitDatePicker`)과 스케줄
/// 탭의 시계 선택기(`showScheduleTimePicker`)를 쓴다 — 같은 앱에서 날짜·시각을
/// 고르는 방법이 탭마다 다르면 공통 검증·접근성 개선도 함께 가지 않는다.
void main() {
  DateTime today() {
    final now = nowKst();
    return DateTime(now.year, now.month, now.day);
  }

  /// 워크스페이스만 띄운다 — 등록 날짜·시각은 이 위젯이 쥔다.
  Future<({DateTime date, TimeOfDay start, TimeOfDay end}) Function()>
  pumpWorkspace(
    WidgetTester tester, {
    Size size = const Size(1400, 1000),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    DateTime date = today();
    TimeOfDay start = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 11, minute: 0);

    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.trainer,
          density: OnCareDensity.web,
        ),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: ProgramEditorWorkspace(
                clientGoal: '체지방 감량',
                aiSuggestions: const <AiRoutineItem>[],
                registerDate: date,
                registerStartTime: start,
                registerEndTime: end,
                onRegisterDateChanged: (value) => setState(() => date = value),
                onRegisterTimeRangeChanged: (value) => setState(() {
                  start = value.start;
                  end = value.end;
                }),
                onSend: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => (date: date, start: start, end: end);
  }

  Future<void> tapChip(WidgetTester tester, String key) async {
    final chip = find.byKey(ValueKey<String>(key));
    await tester.scrollUntilVisible(
      chip,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  testWidgets('기본값은 오늘·오전 10시–11시이고 칩에 그대로 보인다', (tester) async {
    final read = await pumpWorkspace(tester);

    expect(read().date, today());
    expect(read().start, const TimeOfDay(hour: 10, minute: 0));
    expect(read().end, const TimeOfDay(hour: 11, minute: 0));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('program-register-date')),
        matching: find.text(ymd(today())),
      ),
      findsOneWidget,
    );
  });

  testWidgets('날짜 선택은 넓은 창에서도 세로형 달력이다', (tester) async {
    await pumpWorkspace(tester);
    await tapChip(tester, 'program-register-date');

    // `showPortraitDatePicker` 는 Material 기본 `DatePickerDialog` 대신
    // `CalendarDatePicker` 를 직접 감싸 그린다 — 그 자체가 화면 가로·세로에
    // 상관없이 늘 세로 배치라 트레이너 웹처럼 늘 넓은 창에서도 좌우로
    // 갈라지지 않는다.
    final Finder dialog = find.byKey(const Key('portraitDatePicker'));
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(CalendarDatePicker)),
      findsOneWidget,
    );
  });

  testWidgets('과거 날짜는 고를 수 없고 한 해 앞까지 고른다', (tester) async {
    await pumpWorkspace(tester);
    await tapChip(tester, 'program-register-date');

    final CalendarDatePicker picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(picker.firstDate, today());
    expect(picker.lastDate, today().add(const Duration(days: 365)));
    expect(picker.initialDate, today());
  });

  testWidgets('시각 선택은 스케줄 탭과 같은 범위 선택기다', (tester) async {
    final read = await pumpWorkspace(tester);
    await tapChip(tester, 'program-register-time');

    // Material 기본 시간 선택기가 아니라 스케줄 탭의 시계다.
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('session-time-range-start-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('session-time-range-confirm')),
      findsOneWidget,
    );

    // 시작을 9시 30분으로 고르고 확인한다.
    await tester.tap(find.byKey(const ValueKey<String>('clock-value-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('clock-value-30')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('session-time-range-confirm')),
    );
    await tester.pumpAndSettle();

    expect(read().start, const TimeOfDay(hour: 9, minute: 30));
    expect(read().end, const TimeOfDay(hour: 11, minute: 0));
  });

  testWidgets('시각 선택을 닫으면 값이 그대로다', (tester) async {
    final read = await pumpWorkspace(tester);
    await tapChip(tester, 'program-register-time');

    await tester.tap(find.text('취소').last);
    await tester.pumpAndSettle();

    expect(read().start, const TimeOfDay(hour: 10, minute: 0));
    expect(read().end, const TimeOfDay(hour: 11, minute: 0));
  });
}
