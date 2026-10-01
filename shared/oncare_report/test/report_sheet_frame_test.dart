import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';
import 'package:oncare_ui/oncare_ui.dart';

const List<LocalizationsDelegate<dynamic>> _delegates =
    <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

ReportSheetWeekData _week() => ReportSheetWeekData(
  memberName: '김민수',
  weekStart: DateTime(2026, 9, 14),
  sessionsBooked: 1,
  sessionsDone: 1,
  completionAvg: 80,
  sodiumAvg: 1800,
  isCurrentWeek: false,
);

void main() {
  test('the sheet theme is the trainer web theme', () {
    final ThemeData theme = reportSheetTheme();
    final OnCareTokens tokens = theme.extension<OnCareTokens>()!;
    final OnCareTokens trainer = OnCareTheme.light(
      brand: OnCareBrand.trainer,
      density: OnCareDensity.web,
    ).extension<OnCareTokens>()!;
    expect(tokens.brand.primary, trainer.brand.primary);
    expect(tokens.brand.strong, trainer.brand.strong);
    expect(tokens.brand.surface, trainer.brand.surface);
  });

  test('the sheet theme is not the member brand', () {
    final OnCareTokens tokens = reportSheetTheme().extension<OnCareTokens>()!;
    final OnCareTokens member = OnCareTheme.light(
      brand: OnCareBrand.member,
      density: OnCareDensity.mobile,
    ).extension<OnCareTokens>()!;
    expect(tokens.brand.primary, isNot(member.brand.primary));
  });

  testWidgets('the frame renders a sheet without an app around it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(
      ReportSheetDocument.width,
      ReportSheetDocument.height,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: reportSheetFrame(
          locale: const Locale('ko'),
          delegates: _delegates,
          sheet: ReportSheetDocument(report: _week(), feedback: '잘하셨어요'),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('잘하셨어요'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sheet-header')), findsOneWidget);
  });

  testWidgets('the frame ignores the device text scale', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: reportSheetFrame(
            locale: const Locale('en'),
            delegates: _delegates,
            sheet: Builder(
              builder: (BuildContext context) => Text(
                '${MediaQuery.textScalerOf(context).scale(10)}',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('10.0'), findsOneWidget);
  });

  testWidgets('the frame passes the locale down', (WidgetTester tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: reportSheetFrame(
          locale: const Locale('en'),
          delegates: _delegates,
          sheet: Builder(
            builder: (BuildContext context) =>
                Text(Localizations.localeOf(context).languageCode),
          ),
        ),
      ),
    );
    expect(find.text('en'), findsOneWidget);
  });
}
