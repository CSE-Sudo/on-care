import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/time_range_picker_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  Future<void> openPicker(WidgetTester tester) async {
    // 대화상자가 시계 전체를 스크롤 없이 담는 창 크기.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.trainer,
          density: OnCareDensity.web,
        ),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showScheduleTimeRangePicker(
              context: context,
              start: const TimeOfDay(hour: 10, minute: 0),
              end: const TimeOfDay(hour: 9, minute: 30),
            ),
            child: const Text('시간 선택 열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('시간 선택 열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('종료 분 단계에서 시작보다 빠른 종료 시간을 안내한다 (#1293)', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);

    await tester.tap(find.byKey(const ValueKey<String>('clock-value-10')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('clock-value-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('clock-value-9')));
    await tester.pump();

    expect(find.text('종료 분'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('time-range-invalid-end')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey<String>('session-time-range-confirm')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey<String>('time-range-back')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('clock-value-11')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('time-range-invalid-end')),
      findsNothing,
    );
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey<String>('session-time-range-confirm')),
          )
          .onPressed,
      isNotNull,
    );
  });
}
