/// 이미 보낸 리포트를 다시 보는 화면. (#2232)
///
/// 이 화면이 답해야 하는 질문은 하나다 — **회원이 무엇을 받았나.** 그래서
/// 편집기가 아니다. 보낸 글을 고칠 수 있게 생긴 자리에 두면 고친 뒤에야
/// 못 보낸다는 걸 알게 되고, 그건 화면이 거짓말을 한 것이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_trend_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/client_report_view.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/member_feedback_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_exercise_trend.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_feedback_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_macro_bars.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_review_cards.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_grid.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/sent_report_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();

final DateTime _week = DateTime(2026, 9, 14);

WeeklyReport _report({
  String name = '김민수',
  int? completionAvg = 86,
  List<int> weekCompletion = const <int>[100, 50, 0, 67, 100, 100, 100],
  MemberWeeklyFeedback? memberFeedback,
}) => WeeklyReport(
  client: makeClient(name: name),
  weekStart: _week,
  sessionsBooked: 2,
  sessionsDone: 2,
  completionAvg: completionAvg,
  sodiumOverDays: 1,
  sodiumAvg: 1900,
  isCurrentWeek: false,
  weekCompletion: weekCompletion,
  // 보낸 리포트도 ① 격자와 합계 줄을 그린다 — 그때 트레이너가 본 것과 같은
  // 그림이라야 "이걸 보고 이렇게 썼다" 를 되짚을 수 있다(#2232).
  caloriesWeek: const <int>[1850, 2100, 0, 1990, 2400, 1700, 1880],
  carbsWeek: const <double>[230, 260, 0, 240, 300, 210, 235],
  proteinWeek: const <double>[104, 118, 0, 96, 130, 88, 101],
  fatWeek: const <double>[52, 61, 0, 55, 70, 48, 53],
  calorieTarget: 2000,
  carbsTarget: 250,
  proteinTarget: 120,
  fatTarget: 60,
  mealCounts: const <int>[3, 3, 0, 2, 3, 2, 3],
  memberFeedback: memberFeedback,
  days: const <ReportDay>[
    ReportDay(completion: 100, exercises: <String>['스쿼트', '런지'], assigned: 2),
    ReportDay(completion: 50, exercises: <String>['벤치프레스'], assigned: 2),
    ReportDay(completion: 0, assigned: 3),
    ReportDay(completion: 67, exercises: <String>['플랭크', '레그프레스'], assigned: 3),
    ReportDay(completion: 100, exercises: <String>['데드리프트'], assigned: 1),
    ReportDay(completion: 100, exercises: <String>['사이클'], assigned: 1),
    ReportDay(completion: 100, exercises: <String>['스트레칭'], assigned: 1),
  ],
);

/// ③ 운동 추세가 읽는 여덟 주. 보낸 리포트도 편집기와 같은 추세 카드를
/// 그린다(#2425) — 이번 주 한 칸이면 도넛이 선다.
final ReportTrend _trend = ReportTrend(
  weeks: <ReportTrendWeek>[
    ReportTrendWeek(
      weekStart: _week,
      cardioMinutes: 90,
      strengthSets: 12,
      stretchingMinutes: 30,
      cardioCalories: 520,
      strengthCalories: 310,
      stretchingCalories: 80,
    ),
  ],
  goals: const ExerciseBurnGoals(),
);

/// 편집기·보낸 리포트가 함께 쓰는 앱 틀. 추세 카드가 provider 를 읽어
/// [ProviderScope] 가 필요하다.
Widget _app(Widget child, {String locale = 'ko'}) => ProviderScope(
  overrides: <Override>[
    reportTrendProvider.overrideWith((ref, key) async => _trend),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: Locale(locale),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

ReportSendRecord _record({
  String message = '',
  bool read = true,
  DateTime? sentAt,
}) => ReportSendRecord(
  clientId: 'seed-client-1',
  weekStart: _week,
  sentAt: sentAt ?? DateTime(2026, 9, 19, 21, 5),
  message: message,
  read: read,
);

Future<({int back, int rewrite})> _pump(
  WidgetTester tester, {
  WeeklyReport? report,
  ReportSendRecord? record,
  String locale = 'ko',
  Size size = const Size(900, 1600),
}) async {
  int back = 0;
  int rewrite = 0;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _app(
      Padding(
        padding: const EdgeInsets.all(OnCareSpacing.s16),
        child: SentReportView(
          report: report ?? _report(),
          record: record ?? _record(),
          onBack: () => back++,
          onRewrite: () => rewrite++,
        ),
      ),
      locale: locale,
    ),
  );
  // 추세는 비동기 provider 다 — 한 번 더 그려야 도넛이 선다.
  await tester.pump();
  await tester.pump();
  return (back: back, rewrite: rewrite);
}

/// 화면에 보이는 모든 글월.
List<String> _texts(WidgetTester tester) => <String>[
  for (final Element e in find.byType(Text).evaluate())
    if ((e.widget as Text).data != null) (e.widget as Text).data!,
];

void main() {
  testWidgets('누구에게 언제 보냈는지를 먼저 말한다', (tester) async {
    await _pump(tester);

    expect(find.text('김민수님에게 보낸 리포트'), findsOneWidget);
    // 시각은 분까지만 — 초를 보여 줄 이유가 없다.
    expect(
      _texts(tester).any((String t) => t.contains('21:05')),
      isTrue,
      reason: '보낸 시각이 화면에 없다',
    );
  });

  testWidgets('보낸 시각의 분은 한 자리여도 0 을 채운다', (tester) async {
    await _pump(tester, record: _record(sentAt: DateTime(2026, 9, 19, 9, 5)));

    expect(_texts(tester).any((String t) => t.contains('09:05')), isTrue);
  });

  testWidgets('보낸 본문이 있으면 그대로 보여 준다 — 뒤에 고친 초안이 아니다', (tester) async {
    await _pump(tester, record: _record(message: '그때 보낸 글입니다'));

    expect(find.text('그때 보낸 글입니다'), findsOneWidget);
  });

  testWidgets('데모 기록처럼 본문이 비어 있으면 그 주 수치에서 만든 글이 선다', (tester) async {
    await _pump(tester);

    // 빈 카드 대신, 회원이 받았을 글과 같은 규칙으로 만든 글을 세운다.
    final String generated = reportMessage(_ko, _report());
    expect(generated, isNotEmpty);
    expect(find.text(generated), findsOneWidget);
  });

  testWidgets('본문 카드가 비어 있는 채로 서지 않는다', (tester) async {
    await _pump(tester);

    expect(find.text(''), findsNothing);
  });

  testWidgets('보낸 글은 입력창에 담기지 않는다 — 고칠 수 없는 글이다', (tester) async {
    await _pump(tester, record: _record(message: '그때 보낸 글입니다'));

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('작업대로 돌아가는 길이 있다', (tester) async {
    await _pump(tester);

    expect(
      find.byKey(const ValueKey<String>('reports-sent-back')),
      findsOneWidget,
    );
    expect(find.text('이번 주 리포트'), findsOneWidget);
  });

  testWidgets('돌아가기를 누르면 작업대로 간다', (tester) async {
    // 콜백 호출 횟수는 닫힌 레코드라 누른 뒤 다시 읽을 수 없다 — 대신 누르고
    // 나서 예외가 없고 버튼이 살아 있는지를 본다.
    int back = 0;
    await tester.pumpWidget(
      _app(
        SentReportView(
          report: _report(),
          record: _record(),
          onBack: () => back++,
          onRewrite: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('reports-sent-back')));
    await tester.pump();

    expect(back, 1);
  });

  testWidgets('이 내용으로 다시 쓰는 길이 있다', (tester) async {
    int rewrite = 0;
    await tester.pumpWidget(
      _app(
        SentReportView(
          report: _report(),
          record: _record(),
          onBack: () {},
          onRewrite: () => rewrite++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('reports-sent-rewrite')),
    );
    await tester.pump();

    expect(rewrite, 1);
  });

  testWidgets('편집기 ① 확인의 카드를 그대로 세운다 — 그래프까지 같은 위젯이다', (tester) async {
    await _pump(tester);

    // 따로 그린 요약 카드가 아니라 편집기와 같은 묶음이다(#2425).
    expect(find.byType(ReportReviewCards), findsOneWidget);
    expect(find.byType(MemberFeedbackCard), findsOneWidget);
    expect(find.byType(ReportWeekGrid), findsOneWidget);
    expect(find.byType(ReportMacroBars), findsOneWidget);
    expect(find.byType(ReportExerciseTrend), findsOneWidget);
    // 카드 제목도 편집기의 번호·제목 그대로다.
    expect(find.text(_ko.reportsCardWeekTitle), findsOneWidget);
    expect(find.text(_ko.reportsExerciseTrend), findsOneWidget);
    // 추세 카드는 비어 있지 않고 도넛을 그린다.
    expect(
      find.byKey(const ValueKey<String>('report-trend-empty')),
      findsNothing,
    );
    // 예전의 따로 그린 `그때 보낸 수치` 카드는 없다.
    expect(find.text('그때 보낸 수치'), findsNothing);
  });

  testWidgets('편집기 ② 작성의 피드백 카드에 보낸 글이 선다', (tester) async {
    await _pump(tester, record: _record(message: '그때 보낸 글입니다'));

    final Finder card = find.byType(ReportFeedbackCard);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text(_ko.reportsFeedbackTitle)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('그때 보낸 글입니다')),
      findsOneWidget,
    );
  });

  testWidgets('① 확인 카드가 ② 작성 피드백보다 먼저 선다 — 편집기 차례 그대로', (tester) async {
    await _pump(tester);

    final double review = tester.getTopLeft(find.byType(ReportReviewCards)).dy;
    final double feedback = tester
        .getTopLeft(find.byType(ReportFeedbackCard))
        .dy;
    expect(review, lessThan(feedback));
  });

  testWidgets('회원이 낸 답도 편집기와 같은 카드로 보인다', (tester) async {
    await _pump(
      tester,
      report: _report(
        memberFeedback: MemberWeeklyFeedback(
          weekStart: _week,
          condition: WeekCondition.tired,
          intensity: WeekIntensity.hard,
          note: '무릎이 좀 뻐근했어요',
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(MemberFeedbackCard),
        matching: find.byKey(const ValueKey<String>('report-feedback-note')),
      ),
      findsOneWidget,
    );
    expect(find.text('무릎이 좀 뻐근했어요'), findsOneWidget);
  });

  testWidgets('편집기 ① 확인도 같은 카드 묶음을 쓴다', (tester) async {
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: ClientReportView(
            stage: ReportEditorStage.review,
            report: _report(),
            showSummary: true,
            draftEpoch: 0,
            summaryEpoch: 0,
            initialFeedback: '',
            onUseSummaryAsDraft: (_) {},
            onFeedbackChanged: (_) {},
            savingFeedback: false,
            onSaveFeedback: () {},
            weekNav: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(ReportReviewCards), findsOneWidget);
    // ① 에는 쓰는 자리가 없다.
    expect(find.byType(ReportFeedbackCard), findsNothing);
  });

  testWidgets('편집기 ② 작성도 같은 피드백 카드 틀에 입력창을 담는다', (tester) async {
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: ClientReportView(
            stage: ReportEditorStage.write,
            report: _report(),
            showSummary: true,
            draftEpoch: 0,
            summaryEpoch: 0,
            initialFeedback: '초안',
            onUseSummaryAsDraft: (_) {},
            onFeedbackChanged: (_) {},
            savingFeedback: false,
            onSaveFeedback: () {},
            weekNav: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();

    final Finder card = find.byType(ReportFeedbackCard);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(TextField)),
      findsOneWidget,
    );
    expect(find.byType(ReportReviewCards), findsNothing);
  });

  testWidgets('읽기 전용 피드백이 비어 있으면 `피드백 없음` 을 적는다', (tester) async {
    await tester.pumpWidget(
      _app(const ReportFeedbackCard(child: ReportFeedbackText(text: '  '))),
    );

    expect(find.text(_ko.reportsPdfNoFeedback), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('이름이 바뀌면 제목도 그 회원을 가리킨다', (tester) async {
    await _pump(tester, report: _report(name: '박성호'));

    expect(find.text('박성호님에게 보낸 리포트'), findsOneWidget);
    expect(find.text('김민수님에게 보낸 리포트'), findsNothing);
  });

  testWidgets('이행률이 없는 주에도 화면이 선다', (tester) async {
    await _pump(
      tester,
      report: _report(completionAvg: null, weekCompletion: const <int>[]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(_ko.reportsFeedbackTitle), findsOneWidget);
  });

  testWidgets('영어에서 모든 자리가 번역되어 있다', (tester) async {
    await _pump(tester, locale: 'en');

    expect(find.text('Report sent to 김민수'), findsOneWidget);
    expect(find.text('Trainer feedback'), findsOneWidget);
    expect(find.text('Rewrite from this'), findsOneWidget);
    expect(find.text("This week's reports"), findsOneWidget);
  });

  testWidgets('영어 화면에 한글이 남아 있지 않다', (tester) async {
    await _pump(tester, locale: 'en');

    final RegExp hangul = RegExp(r'[가-힣]');
    // 운동 이름은 트레이너가 적은 사용자 데이터라 번역하지 않는다 — ① 격자가
    // 그대로 옮겨 적는다.
    final Set<String> exercises = <String>{
      for (final ReportDay day in _report().days) ...day.exercises,
    };
    for (final String t in _texts(tester)) {
      // 회원 이름은 사람 이름이라 번역하지 않는다.
      if (t.contains('김민수')) continue;
      if (exercises.any(t.contains)) continue;
      expect(hangul.hasMatch(t), isFalse, reason: '영어 화면에 번역되지 않은 글이 있다: $t');
    }
  });

  testWidgets('좁은 폭에서도 넘치지 않는다', (tester) async {
    await _pump(tester, size: const Size(420, 1600));

    expect(tester.takeException(), isNull);
  });
}
