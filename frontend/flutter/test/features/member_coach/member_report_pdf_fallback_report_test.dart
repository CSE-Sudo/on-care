/// 리포트 결과지를 굽지 못해 글자 문서로 물러서면 처리된 오류로 알린다(#3051).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/observability/error_reporter.dart';
import 'package:oncare/core/observability/handled_error.dart';
import 'package:oncare/features/member_coach/services/member_report_pdf_generator.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_report/oncare_report.dart';

ReportSheetInputs _inputs() => ReportSheetInputs(
  week: ReportSheetWeekData(
    memberName: '김민수',
    weekStart: DateTime(2026, 8, 17),
    sessionsBooked: 2,
    sessionsDone: 1,
    completionAvg: 82,
    sodiumAvg: 2100,
    isCurrentWeek: false,
    caloriesWeek: const <int>[1800, 1850, 1900, 1950, 2000, 2050, 0],
    sugarWeek: const <double>[24.5, 24.5, 24.5, 24.5, 24.5, 24.5, 0],
    sodiumWeek: const <int>[2100, 2100, 2100, 2100, 2100, 2100, 0],
    weekCompletion: const <int>[80, 0, 90, 0, 75, 0, 0],
  ),
);

Future<CapturedWidget> _fakeCapture(
  Widget child, {
  required double width,
  required double pixelRatio,
}) async => CapturedWidget(
  rgba: Uint8List.fromList(List<int>.filled(4 * 4, 255)),
  width: 2,
  height: 2,
);

Future<CapturedWidget> _brokenCapture(
  Widget child, {
  required double width,
  required double pixelRatio,
}) async => throw StateError('renderer unavailable');

Future<void> _noYield() async {}

class _FakeReporter extends ErrorReporter {
  final List<(Object, String, Map<String, String>)> reports =
      <(Object, String, Map<String, String>)>[];

  @override
  bool get isEnabled => true;

  @override
  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    Map<String, String> tags = const <String, String>{},
  }) async {
    reports.add((error, source, tags));
  }
}

void main() {
  Future<AppLocalizations> localizations(WidgetTester tester) async {
    late AppLocalizations l;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            l = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return l;
  }

  testWidgets('굽지 못하면 글자 PDF 를 주고 onFallback 을 한 번 부른다', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l = await localizations(tester);
    final List<Object> fallbacks = <Object>[];
    late Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await MemberReportPdfGenerator(
        capture: _brokenCapture,
        yieldFrame: _noYield,
        onFallback: (Object error, StackTrace _) => fallbacks.add(error),
      ).generate(l: l, inputs: _inputs(), feedback: trainerReportFeedback('글'));
    });

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(fallbacks, hasLength(1));
    expect(fallbacks.single, isA<StateError>());
  });

  testWidgets('구워지면 onFallback 을 부르지 않는다', (WidgetTester tester) async {
    final AppLocalizations l = await localizations(tester);
    final List<Object> fallbacks = <Object>[];
    await tester.runAsync(() async {
      await MemberReportPdfGenerator(
        capture: _fakeCapture,
        yieldFrame: _noYield,
        onFallback: (Object error, StackTrace _) => fallbacks.add(error),
      ).generate(l: l, inputs: _inputs(), feedback: trainerReportFeedback('글'));
    });

    expect(fallbacks, isEmpty);
  });

  testWidgets('onFallback 이 던져도 글자 PDF 는 열린다', (WidgetTester tester) async {
    final AppLocalizations l = await localizations(tester);
    late Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await MemberReportPdfGenerator(
        capture: _brokenCapture,
        yieldFrame: _noYield,
        onFallback: (Object error, StackTrace _) =>
            throw StateError('report failed'),
      ).generate(l: l, inputs: _inputs(), feedback: trainerReportFeedback('글'));
    });

    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('앱 provider 는 폴백을 처리된 오류 창구로 보낸다', () async {
    final _FakeReporter reporter = _FakeReporter();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[errorReporterProvider.overrideWithValue(reporter)],
    );
    addTearDown(container.dispose);

    final MemberReportPdfGenerator generator = container.read(
      memberReportPdfGeneratorProvider,
    );
    generator.onFallback!(StateError('sheet'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);

    expect(reporter.reports, hasLength(1));
    expect(reporter.reports.single.$2, HandledErrorReporter.source);
    expect(
      reporter.reports.single.$3['handled_context'],
      'report.memberPdfSheet',
    );
  });
}
