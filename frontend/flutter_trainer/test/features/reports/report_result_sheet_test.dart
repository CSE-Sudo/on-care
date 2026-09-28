import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_result_sheet.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';

import '../../helpers/client_factory.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

/// 결과지의 모든 칸. 한 장에 이것이 다 실려야 한다(#2485).
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

WeeklyReport _report({
  String name = '김회원',
  MemberWeeklyFeedback? memberFeedback,
}) => WeeklyReport(
  client: makeClient(id: 'sheet-client', name: name),
  weekStart: DateTime(2026, 8, 10),
  sessionsBooked: 2,
  sessionsDone: 1,
  completionAvg: 72,
  sodiumOverDays: 2,
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
  days: const <ReportDay>[
    ReportDay(completion: 80, exercises: <String>['스쿼트', '런지'], assigned: 3),
    ReportDay(completion: 0),
    ReportDay(completion: 70, exercises: <String>['벤치프레스']),
  ],
  mealCounts: const <int>[3, 0, 2, 3, 3, 0, 0],
  memberFeedback: memberFeedback,
);

WeeklyReport _empty() => WeeklyReport(
  client: makeClient(id: 'sheet-empty', name: '무기록'),
  weekStart: DateTime(2026, 8, 10),
  sessionsBooked: 0,
  sessionsDone: 0,
  completionAvg: null,
  sodiumOverDays: null,
  sodiumAvg: null,
  isCurrentWeek: false,
);

ReportTrend _trend() => ReportTrend(
  weeks: <ReportTrendWeek>[
    for (int i = 7; i >= 0; i--)
      ReportTrendWeek(
        weekStart: DateTime(2026, 8, 10 - 7 * i),
        cardioMinutes: 60 + i * 10,
        strengthSets: 6 + i,
        stretchingMinutes: 30,
        cardioCalories: 300,
        strengthCalories: 200,
        stretchingCalories: 60,
      ),
  ],
  goals: const ExerciseBurnGoals(),
);

MemberWeeklyFeedback _answer({String note = '무릎이 조금 불편했어요'}) =>
    MemberWeeklyFeedback(
      weekStart: DateTime(2026, 8, 10),
      condition: WeekCondition.tired,
      intensity: WeekIntensity.hard,
      painArea: '오른 무릎',
      painOn: DateTime(2026, 8, 12),
      note: note,
    );

/// 생성기가 두르는 것과 같은 틀 — 테마·로케일·글자 배율.
Future<void> _pump(
  WidgetTester tester,
  ReportResultSheet sheet, {
  AppLocalizations? l,
}) async {
  tester.view.physicalSize = const Size(
    ReportResultSheet.width,
    ReportResultSheet.height,
  );
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Localizations(
      locale: Locale((l ?? _ko).localeName),
      delegates: AppLocalizations.localizationsDelegates,
      child: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.noScaling),
        child: Theme(
          data: AppTheme.light(),
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

/// 그려진 글 전부.
List<String> _texts(WidgetTester tester) => <String>[
  for (final Text t in tester.widgetList<Text>(find.byType(Text)))
    if (t.data case final String s) s,
];

RenderParagraph _paragraph(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );

void main() {
  group('ReportResultSheet — A4 한 장 결과지 (#2485)', () {
    testWidgets('한 장에 모든 칸이 실린다', (tester) async {
      await _pump(
        tester,
        ReportResultSheet(
          report: _report(memberFeedback: _answer()),
          feedback: '이번 주 잘했어요',
          trend: _trend(),
        ),
      );

      for (final String key in _sections) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('크기는 언제나 A4 비율로 고정이다', (tester) async {
      await _pump(tester, ReportResultSheet(report: _report(), feedback: 'x'));

      expect(
        tester.getSize(find.byType(ReportResultSheet)),
        const Size(ReportResultSheet.width, ReportResultSheet.height),
      );
      // A4 는 1 : √2 다.
      expect(
        ReportResultSheet.height / ReportResultSheet.width,
        closeTo(1.4142, 0.001),
      );
    });

    testWidgets('머리 띠에 제목과 회원 정보 한 줄이 선다', (tester) async {
      await _pump(tester, ReportResultSheet(report: _report(), feedback: 'x'));

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

    testWidgets('식단·운동 분석은 부족·적정·초과 눈금 아래 막대로 선다', (tester) async {
      await _pump(
        tester,
        ReportResultSheet(report: _report(), feedback: 'x', trend: _trend()),
      );

      // 두 섹션마다 눈금 머리 한 줄씩.
      expect(find.text(_ko.reportsSheetBandUnder), findsWidgets);
      expect(find.text(_ko.reportsSheetBandNormal), findsWidgets);
      final Finder diet = find.byKey(const ValueKey<String>('sheet-diet'));
      for (final String label in <String>[
        _ko.metricCalories,
        _ko.metricCarbs,
        _ko.metricProtein,
        _ko.metricFat,
        _ko.metricSodium,
        _ko.metricSugar,
      ]) {
        expect(
          find.descendant(of: diet, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      // 여섯 항목 모두 기록이 있어 막대가 채워진다.
      expect(
        find.descendant(
          of: diet,
          matching: find.byKey(const ValueKey<String>('sheet-bar-fill')),
        ),
        findsNWidgets(6),
      );
      // 운동: 수행률·출석·유산소·근력·스트레칭.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('sheet-exercise')),
          matching: find.byKey(const ValueKey<String>('sheet-bar-fill')),
        ),
        findsNWidgets(5),
      );
    });

    testWidgets('긴 피드백은 넘치지 않고 말줄임으로 끝난다', (tester) async {
      final String long = List<String>.filled(
        600,
        '한글 피드백을 PDF에 정확히 반영합니다.',
      ).join(' ');
      await _pump(tester, ReportResultSheet(report: _report(), feedback: long));

      final Finder text = find.byKey(
        const ValueKey<String>('sheet-feedback-text'),
      );
      final Text widget = tester.widget<Text>(text);
      expect(widget.overflow, TextOverflow.ellipsis);
      expect(widget.maxLines, isNotNull);
      expect(_paragraph(tester, text).didExceedMaxLines, isTrue);
      // 글 칸이 제 자리 안에 머문다 — 결과지 아래로 삐져나가지 않는다.
      expect(
        tester.getBottomLeft(text).dy,
        lessThanOrEqualTo(ReportResultSheet.height),
      );
      expect(
        tester.getSize(find.byType(ReportResultSheet)),
        const Size(ReportResultSheet.width, ReportResultSheet.height),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('짧은 피드백은 줄이지 않고 그대로 싣는다', (tester) async {
      await _pump(
        tester,
        ReportResultSheet(report: _report(), feedback: '이번 주 잘했어요'),
      );

      final Finder text = find.byKey(
        const ValueKey<String>('sheet-feedback-text'),
      );
      expect(find.text('이번 주 잘했어요'), findsOneWidget);
      expect(_paragraph(tester, text).didExceedMaxLines, isFalse);
    });

    testWidgets('빈 피드백은 `피드백 없음` 으로 선다', (tester) async {
      await _pump(
        tester,
        ReportResultSheet(report: _report(), feedback: '   '),
      );

      expect(find.text(_ko.reportsPdfNoFeedback), findsOneWidget);
    });

    testWidgets('긴 회원 메모도 정해진 줄에서 말줄임으로 끝난다', (tester) async {
      final String note = List<String>.filled(80, '무릎이 불편했어요').join(' ');
      await _pump(
        tester,
        ReportResultSheet(
          report: _report(memberFeedback: _answer(note: note)),
          feedback: 'x',
        ),
      );

      final Finder text = find.text(note);
      expect(tester.widget<Text>(text).overflow, TextOverflow.ellipsis);
      expect(_paragraph(tester, text).didExceedMaxLines, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('회원 답은 컨디션·강도·통증·메모를 싣는다', (tester) async {
      await _pump(
        tester,
        ReportResultSheet(
          report: _report(memberFeedback: _answer()),
          feedback: 'x',
        ),
      );

      final Finder member = find.byKey(const ValueKey<String>('sheet-member'));
      Finder inMember(String s) =>
          find.descendant(of: member, matching: find.text(s));
      expect(inMember(_ko.reportsMemberFeedbackConditionTired), findsOneWidget);
      expect(inMember(_ko.reportsMemberFeedbackIntensityHard), findsOneWidget);
      expect(
        inMember(
          _ko.reportsMemberFeedbackPainOn('오른 무릎', _ko.dateMonthDay(8, 12)),
        ),
        findsOneWidget,
      );
      expect(inMember('무릎이 조금 불편했어요'), findsOneWidget);
    });

    testWidgets('빈 데이터도 한 장에 모든 칸이 서고 미집계로 채운다', (tester) async {
      await _pump(tester, ReportResultSheet(report: _empty(), feedback: ''));

      for (final String key in _sections) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
      expect(find.text(_ko.reportsSheetScoreNone), findsOneWidget);
      expect(find.text(_ko.reportsPdfNoData), findsWidgets);
      expect(find.text(_ko.reportsMemberFeedbackUnanswered), findsWidgets);
      // 기록이 없으면 막대를 채우지 않는다 — 0 으로 긋지 않는다.
      expect(
        find.byKey(const ValueKey<String>('sheet-bar-fill')),
        findsNothing,
      );
      // 추세를 읽지 못했다는 안내가 추이 칸에 선다.
      expect(find.text(_ko.reportsTrendUnavailable), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('점수는 산식과 항목 점수를 함께 싣는다', (tester) async {
      await _pump(tester, ReportResultSheet(report: _report(), feedback: 'x'));

      final Finder score = find.byKey(const ValueKey<String>('sheet-score'));
      expect(
        find.descendant(
          of: score,
          matching: find.text(_ko.reportsSheetScoreFormula),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: score,
          matching: find.text(_ko.reportsSheetScoreUnit),
        ),
        findsOneWidget,
      );
      // 수행률 72%·출석 50%·식단 기록 4/7·열량 적정일 3/4 의 평균.
      final int expected = ((72 + 50 + 400 / 7 + 75) / 4).round();
      expect(
        find.descendant(of: score, matching: find.text('$expected')),
        findsOneWidget,
      );
    });

    testWidgets('항목별 평가는 해당 칸 하나에 표시한다', (tester) async {
      await _pump(tester, ReportResultSheet(report: _report(), feedback: 'x'));

      final Finder eval = find.byKey(const ValueKey<String>('sheet-eval'));
      // 식단 여섯·수행률·출석 — 여덟 줄 모두 값이 있어 한 칸씩 표시된다.
      expect(
        find.descendant(
          of: eval,
          matching: find.byKey(const ValueKey<String>('sheet-eval-checked')),
        ),
        findsNWidgets(8),
      );
    });

    testWidgets('4주 평균 대비는 지난 주들이 있으면 변화를 싣는다', (tester) async {
      final WeeklyReport past = WeeklyReport(
        client: makeClient(id: 'sheet-client', name: '김회원'),
        weekStart: DateTime(2026, 8, 3),
        sessionsBooked: 2,
        sessionsDone: 2,
        completionAvg: 62,
        sodiumOverDays: 0,
        sodiumAvg: 1790,
        isCurrentWeek: false,
      );
      await _pump(
        tester,
        ReportResultSheet(
          report: _report(),
          feedback: 'x',
          history: <WeeklyReport>[past],
        ),
      );

      final Finder avg = find.byKey(const ValueKey<String>('sheet-average'));
      expect(
        find.descendant(
          of: avg,
          matching: find.text('▲ ${_ko.reportsPdfValuePercent('10')}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: avg,
          matching: find.text('▲ ${_ko.reportsPdfValueMg('100')}'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('추세가 있으면 주별 달성률과 요일별 열량 꺾은선이 선다', (tester) async {
      await _pump(
        tester,
        ReportResultSheet(report: _report(), feedback: 'x', trend: _trend()),
      );

      final Finder trend = find.byKey(const ValueKey<String>('sheet-trend'));
      expect(
        find.descendant(of: trend, matching: find.byType(CustomPaint)),
        findsAtLeastNWidgets(2),
      );
      expect(find.text(_ko.reportsTrendUnavailable), findsNothing);
      // 여덟 주의 월요일이 가로축에 선다.
      expect(
        find.descendant(of: trend, matching: find.text('8/10')),
        findsOneWidget,
      );
    });

    testWidgets('영어 로케일이면 결과지 문구가 모두 영어다', (tester) async {
      await _pump(
        tester,
        ReportResultSheet(
          report: _report(memberFeedback: _answer(note: 'Knee felt sore')),
          feedback: 'Nice week',
          trend: _trend(),
        ),
        l: _en,
      );

      expect(find.text(_en.reportsPdfDocTitle), findsOneWidget);
      expect(find.text(_en.reportsSheetDietTitle), findsOneWidget);
      expect(find.text(_en.reportsSheetScoreTitle), findsOneWidget);
      // 회원 이름·통증 부위는 사용자 데이터라 검사에서 뺀다.
      final List<String> leaked = _texts(tester)
          .where((String s) => !s.contains('김회원') && !s.contains('오른 무릎'))
          .where(RegExp(r'[가-힣]').hasMatch)
          .toList();
      expect(leaked, isEmpty, reason: '결과지에 한국어가 남아 있다: $leaked');
      expect(tester.takeException(), isNull);
    });

    testWidgets('영어·긴 피드백·빈 데이터가 겹쳐도 한 장에 머문다', (tester) async {
      await _pump(
        tester,
        ReportResultSheet(
          report: _empty(),
          feedback: List<String>.filled(400, 'Keep going strong.').join(' '),
        ),
        l: _en,
      );

      for (final String key in _sections) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
      expect(
        tester.getSize(find.byType(ReportResultSheet)),
        const Size(ReportResultSheet.width, ReportResultSheet.height),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
