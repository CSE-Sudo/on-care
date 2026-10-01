import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/gen/l10n/report_sheet_localizations_en.dart';
import 'package:oncare_report/gen/l10n/report_sheet_localizations_ko.dart';
import 'package:oncare_report/oncare_report.dart';
import 'package:oncare_ui/oncare_ui.dart';

final ReportSheetLocalizationsKo _ko = ReportSheetLocalizationsKo();
final ReportSheetLocalizationsEn _en = ReportSheetLocalizationsEn();

/// 결과지의 모든 칸 — 트레이너 웹 결과지와 같은 칸이다.
const List<String> _sections = <String>[
  'sheet-header',
  'sheet-diet',
  'sheet-exercise',
  'sheet-daily',
  'sheet-trend',
  'sheet-score',
  'sheet-eval',
  'sheet-average',
  'sheet-member',
  'sheet-feedback',
];

ReportSheetWeekData _report({ReportSheetAnswers? answers}) =>
    ReportSheetWeekData(
      memberName: '김회원',
      weekStart: DateTime(2026, 8, 10),
      sessionsBooked: 2,
      sessionsDone: 1,
      completionAvg: 72,
      sodiumAvg: 1890,
      isCurrentWeek: false,
      weekCompletion: const <int>[80, 0, 70, 90, 60, 0, 0],
      sodiumWeek: const <int>[1800, 0, 2100, 1700, 1950, 0, 0],
      caloriesWeek: const <int>[1800, 0, 1900, 1750, 2600, 0, 0],
      sugarWeek: const <double>[20, 0, 24.5, 19, 22, 0, 0],
      carbsWeek: const <double>[250, 0, 240, 260, 300, 0, 0],
      proteinWeek: const <double>[60, 0, 70, 65, 80, 0, 0],
      fatWeek: const <double>[50, 0, 55, 45, 70, 0, 0],
      calorieTarget: 2000,
      days: const <ReportSheetDay>[
        ReportSheetDayData(
          completion: 80,
          exercises: <String>['스쿼트', '런지'],
          assigned: 3,
        ),
        ReportSheetDayData(completion: 0),
        ReportSheetDayData(completion: 70, exercises: <String>['벤치프레스']),
      ],
      mealCounts: const <int>[3, 0, 2, 3, 3, 0, 0],
      answers: answers,
    );

ReportSheetTrendData _trend() => ReportSheetTrendData(
  goals: const ReportSheetGoals(),
  weeks: <ReportSheetTrendWeek>[
    for (int i = 7; i >= 0; i--)
      ReportSheetTrendWeekData(
        weekStart: DateTime(2026, 8, 10 - 7 * i),
        cardioMinutes: 60 + i * 10,
        strengthSets: 6 + i,
        stretchingMinutes: 30,
      ),
  ],
);

final ReportSheetAnswersData _answer = ReportSheetAnswersData(
  conditionWire: 'tired',
  intensityWire: 'hard',
  painArea: '오른 무릎',
  painOn: DateTime(2026, 8, 12),
  note: '무릎이 조금 불편했어요',
);

Future<void> _pump(
  WidgetTester tester,
  ReportSheetDocument sheet, {
  Locale locale = const Locale('ko'),
  OnCareBrand brand = OnCareBrand.member,
}) async {
  tester.view.physicalSize = const Size(
    ReportSheetDocument.width,
    ReportSheetDocument.height,
  );
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Localizations(
      locale: locale,
      delegates: const <LocalizationsDelegate<Object>>[
        DefaultWidgetsLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
      ],
      child: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.noScaling),
        child: Theme(
          data: OnCareTheme.light(
            brand: brand,
            density: identical(brand, OnCareBrand.member)
                ? OnCareDensity.mobile
                : OnCareDensity.web,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(alignment: Alignment.topLeft, child: sheet),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('ReportSheetDocument (#2652)', () {
    for (final (String name, OnCareBrand brand) in <(String, OnCareBrand)>[
      ('회원 앱', OnCareBrand.member),
      ('트레이너 웹', OnCareBrand.trainer),
    ]) {
      testWidgets('$name 테마에서도 한 장에 모든 칸이 실린다', (tester) async {
        await _pump(
          tester,
          ReportSheetDocument(
            report: _report(answers: _answer),
            feedback: '이번 주 잘했어요',
            trend: _trend(),
          ),
          brand: brand,
        );
        for (final String key in _sections) {
          expect(
            find.byKey(ValueKey<String>(key)),
            findsOneWidget,
            reason: key,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('크기는 A4 비율로 고정이다', (tester) async {
      await _pump(
        tester,
        ReportSheetDocument(report: _report(), feedback: 'x'),
      );
      expect(
        tester.getSize(find.byType(ReportSheetDocument)),
        const Size(ReportSheetDocument.width, ReportSheetDocument.height),
      );
      expect(
        ReportSheetDocument.height / ReportSheetDocument.width,
        closeTo(1.4142, 0.001),
      );
    });

    testWidgets('머리 띠에 제목·회원 이름·기간·PT·끼니 기록일이 선다', (tester) async {
      await _pump(
        tester,
        ReportSheetDocument(report: _report(), feedback: 'x'),
      );
      expect(find.text(_ko.reportsPdfDocTitle), findsOneWidget);
      expect(find.text('김회원'), findsOneWidget);
      expect(
        find.text(_ko.reportsSheetPeriodValue('2026-08-10', '2026-08-16')),
        findsOneWidget,
      );
      expect(
        find.text(_ko.reportsPdfAttendance('1', '2', '50')),
        findsOneWidget,
      );
      expect(find.text(_ko.reportsSheetDaysOf('4', '7')), findsOneWidget);
    });

    testWidgets('회원 답이 없으면 네 줄 모두 `아직 받지 못함`', (tester) async {
      await _pump(
        tester,
        ReportSheetDocument(report: _report(), feedback: 'x'),
      );
      final Finder member = find.byKey(const ValueKey<String>('sheet-member'));
      expect(
        find.descendant(
          of: member,
          matching: find.text(_ko.reportsMemberFeedbackUnanswered),
        ),
        findsNWidgets(4),
      );
    });

    testWidgets('회원 답은 서버 값을 로케일 이름으로 옮겨 적는다', (tester) async {
      await _pump(
        tester,
        ReportSheetDocument(
          report: _report(answers: _answer),
          feedback: 'x',
        ),
      );
      final Finder member = find.byKey(const ValueKey<String>('sheet-member'));
      expect(
        find.descendant(
          of: member,
          matching: find.text(_ko.reportsMemberFeedbackConditionTired),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: member,
          matching: find.text(_ko.reportsMemberFeedbackIntensityHard),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: member,
          matching: find.text(
            _ko.reportsMemberFeedbackPainOn('오른 무릎', _ko.dateMonthDay(8, 12)),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: member, matching: find.text('무릎이 조금 불편했어요')),
        findsOneWidget,
      );
    });

    testWidgets('영어 로케일이면 결과지 문구가 영어다', (tester) async {
      await _pump(
        tester,
        ReportSheetDocument(report: _report(), feedback: 'x', trend: _trend()),
        locale: const Locale('en'),
      );
      expect(find.text(_en.reportsPdfDocTitle), findsOneWidget);
      expect(find.text(_en.reportsSheetDietTitle), findsOneWidget);
      expect(find.text(_ko.reportsSheetDietTitle), findsNothing);
    });

    testWidgets('결과지가 모르는 언어면 한국어로 그린다', (tester) async {
      await _pump(
        tester,
        ReportSheetDocument(report: _report(), feedback: 'x'),
        locale: const Locale('ja'),
      );
      expect(find.text(_ko.reportsPdfDocTitle), findsOneWidget);
    });

    testWidgets('아래 칸 제목은 기본이 트레이너 코칭이고 바꿀 수 있다', (tester) async {
      await _pump(
        tester,
        ReportSheetDocument(report: _report(), feedback: 'x'),
      );
      expect(find.text(_ko.reportsFeedbackTitle), findsOneWidget);

      await _pump(
        tester,
        ReportSheetDocument(
          report: _report(),
          feedback: 'x',
          feedbackTitle: '이번 주 인사이트',
        ),
      );
      expect(find.text('이번 주 인사이트'), findsOneWidget);
      expect(find.text(_ko.reportsFeedbackTitle), findsNothing);
    });

    testWidgets('빈 피드백이면 `남긴 코칭 없음` 을 적는다', (tester) async {
      await _pump(
        tester,
        ReportSheetDocument(report: _report(), feedback: '   '),
      );
      expect(find.text(_ko.reportsPdfNoFeedback), findsOneWidget);
    });

    testWidgets('긴 피드백은 말줄임으로 끝나고 한 장을 넘지 않는다', (tester) async {
      final String long = List<String>.filled(
        600,
        '한글 피드백을 PDF에 정확히 반영합니다.',
      ).join(' ');
      await _pump(
        tester,
        ReportSheetDocument(report: _report(), feedback: long),
      );
      final Finder text = find.byKey(
        const ValueKey<String>('sheet-feedback-text'),
      );
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(
        tester.getBottomLeft(text).dy,
        lessThanOrEqualTo(ReportSheetDocument.height),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('기록이 하나도 없는 주도 칸마다 `미집계` 로 선다', (tester) async {
      await _pump(
        tester,
        ReportSheetDocument(
          report: ReportSheetWeekData(
            memberName: '무기록',
            weekStart: DateTime(2026, 8, 10),
            sessionsBooked: 0,
            sessionsDone: 0,
            completionAvg: null,
            sodiumAvg: null,
            isCurrentWeek: false,
          ),
          feedback: '',
        ),
      );
      expect(find.text(_ko.reportsPdfNoData), findsWidgets);
      expect(find.text(_ko.reportsSheetScoreNone), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
