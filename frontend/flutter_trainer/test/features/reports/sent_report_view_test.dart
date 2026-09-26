/// 이미 보낸 리포트를 다시 보는 화면. (#2232)
///
/// 이 화면이 답해야 하는 질문은 하나다 — **회원이 무엇을 받았나.** 그래서
/// 편집기가 아니다. 보낸 글을 고칠 수 있게 생긴 자리에 두면 고친 뒤에야
/// 못 보낸다는 걸 알게 되고, 그건 화면이 거짓말을 한 것이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/sent_report_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();

final DateTime _week = DateTime(2026, 9, 14);

WeeklyReport _report({
  String name = '김민수',
  int? completionAvg = 86,
  List<int> weekCompletion = const <int>[100, 50, 0, 67, 100, 100, 100],
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
    MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(OnCareSpacing.s16),
          child: SentReportView(
            report: report ?? _report(),
            record: record ?? _record(),
            onBack: () => back++,
            onRewrite: () => rewrite++,
          ),
        ),
      ),
    ),
  );
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
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: Scaffold(
          body: SentReportView(
            report: _report(),
            record: _record(),
            onBack: () => back++,
            onRewrite: () {},
          ),
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
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: Scaffold(
          body: SentReportView(
            report: _report(),
            record: _record(),
            onBack: () {},
            onRewrite: () => rewrite++,
          ),
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

  testWidgets('그때 보낸 수치도 함께 남는다 — 글만으로는 근거를 되짚을 수 없다', (tester) async {
    await _pump(tester);

    expect(find.text('그때 보낸 수치'), findsOneWidget);
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
    expect(find.text('보낸 피드백'), findsOneWidget);
  });

  testWidgets('영어에서 모든 자리가 번역되어 있다', (tester) async {
    await _pump(tester, locale: 'en');

    expect(find.text('Report sent to 김민수'), findsOneWidget);
    expect(find.text('Message sent'), findsOneWidget);
    expect(find.text('Figures sent'), findsOneWidget);
    expect(find.text('Rewrite from this'), findsOneWidget);
    expect(find.text("This week's reports"), findsOneWidget);
  });

  testWidgets('영어 화면에 한글이 남아 있지 않다', (tester) async {
    await _pump(tester, locale: 'en');

    final RegExp hangul = RegExp(r'[가-힣]');
    for (final String t in _texts(tester)) {
      // 회원 이름은 사람 이름이라 번역하지 않는다.
      if (t.contains('김민수')) continue;
      expect(hangul.hasMatch(t), isFalse, reason: '영어 화면에 번역되지 않은 글이 있다: $t');
    }
  });

  testWidgets('좁은 폭에서도 넘치지 않는다', (tester) async {
    await _pump(tester, size: const Size(420, 1600));

    expect(tester.takeException(), isNull);
  });
}
