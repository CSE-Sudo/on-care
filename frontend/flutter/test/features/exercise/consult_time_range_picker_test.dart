import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/exercise/presentation/widgets/consult_time_range_picker.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 공용 시간 선택기로 시작 → 종료를 차례로 고르는 흐름(#1701).
///
/// 선택기 자체(다이얼 조작)는 Flutter 기본 시간 선택기의 몫이라, 여기서는 이
/// 함수가 지키는 약속 — 고른 범위를 돌려준다, 취소하면 null, 종료가 시작보다
/// 이르면 null — 만 본다.
void main() {
  late TimeRangeValue? result;
  late bool completed;

  Future<void> openPicker(
    WidgetTester tester, {
    required TimeOfDay start,
    required TimeOfDay end,
  }) async {
    result = null;
    completed = false;
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
                start: start,
                end: end,
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

  MaterialLocalizations material(WidgetTester tester) =>
      MaterialLocalizations.of(tester.element(find.byType(TimePickerDialog)));

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(TimePickerDialog)));

  Future<void> confirmStep(WidgetTester tester) async {
    await tester.tap(find.text(material(tester).okButtonLabel));
    await tester.pumpAndSettle();
  }

  testWidgets('시작·종료를 차례로 확인하면 고른 범위를 돌려준다', (WidgetTester tester) async {
    await openPicker(
      tester,
      start: const TimeOfDay(hour: 10, minute: 0),
      end: const TimeOfDay(hour: 11, minute: 0),
    );

    // 첫 창은 시작 시간을 묻는다.
    expect(find.text(l10n(tester).exTimeRangeStartTime), findsOneWidget);
    await confirmStep(tester);

    // 이어서 종료 시간을 묻는다.
    expect(find.text(l10n(tester).exTimeRangeEndTime), findsOneWidget);
    await confirmStep(tester);

    expect(find.byType(TimePickerDialog), findsNothing);
    expect(completed, isTrue);
    expect(result, (
      start: const TimeOfDay(hour: 10, minute: 0),
      end: const TimeOfDay(hour: 11, minute: 0),
    ));
  });

  testWidgets('중간에 취소하면 null 이다', (WidgetTester tester) async {
    await openPicker(
      tester,
      start: const TimeOfDay(hour: 10, minute: 0),
      end: const TimeOfDay(hour: 11, minute: 0),
    );

    await confirmStep(tester);
    await tester.tap(find.text(material(tester).cancelButtonLabel));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsNothing);
    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('종료가 시작보다 이르면 범위로 받지 않는다(null)', (WidgetTester tester) async {
    await openPicker(
      tester,
      start: const TimeOfDay(hour: 11, minute: 0),
      end: const TimeOfDay(hour: 9, minute: 0),
    );

    await confirmStep(tester);
    await confirmStep(tester);

    expect(completed, isTrue);
    expect(result, isNull);
  });
}
