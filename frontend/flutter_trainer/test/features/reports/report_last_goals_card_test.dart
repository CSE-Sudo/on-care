/// ③ 지난 주 목표 달성 카드. (#2287)
///
/// 판정 로직은 `report_goal_check_test.dart` 가 본다. 이 파일은 그 판정이 카드에
/// 어떻게 서는지를 본다 — 목표 없음의 빈 상태, 달성·절반·미달·직접 확인 딱지와
/// 근거, 달성 수 딱지, 한·영 두 로케일, 좁은 화면과 큰 글자.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_last_goals_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';

List<double> _days(double v) => List<double>.filled(7, v);

/// 목표 넷이 서로 다른 판정을 받는 주 — 단백질 달성, 나트륨 절반, 운동 미달,
/// 수치로 볼 수 없는 목표 하나.
WeeklyReport _report({List<String>? goals}) => WeeklyReport(
  client: makeClient(name: '김민수'),
  weekStart: DateTime(2026, 9, 14),
  sessionsBooked: 2,
  sessionsDone: 1,
  completionAvg: 20,
  sodiumOverDays: 3,
  sodiumAvg: 2300,
  sodiumTarget: 2000,
  isCurrentWeek: false,
  proteinWeek: _days(110),
  proteinTarget: 120,
  weekGoals:
      goals ?? const <String>['저녁 단백질 챙기기', '나트륨 줄이기', '주 3회 운동', '물 2L 마시기'],
);

Future<void> _pump(
  WidgetTester tester, {
  required WeeklyReport report,
  String locale = 'ko',
  Size size = const Size(900, 700),
  double textScale = 1,
}) async {
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(OnCareSpacing.s16),
          child: ReportLastGoalsCard(report: report),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// [index] 번째 목표 줄 안의 글자들.
List<String> _row(WidgetTester tester, int index) => <String>[
  for (final Text t in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(ValueKey<String>('report-last-goal-$index')),
      matching: find.byType(Text),
    ),
  ))
    t.data ?? '',
];

AppTagTone _tone(WidgetTester tester, int index) => tester
    .widget<AppTag>(
      find.descendant(
        of: find.byKey(ValueKey<String>('report-last-goal-$index')),
        matching: find.byType(AppTag),
      ),
    )
    .tone;

void main() {
  group('목표가 없는 주', () {
    testWidgets('한국어 — 빈 상태와 어디서 고르는지를 말한다', (tester) async {
      await _pump(tester, report: _report(goals: const <String>[]));

      expect(find.text('지난 주 목표 달성'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('report-last-goals-empty')),
        findsOneWidget,
      );
      expect(find.text('지난 주에 고른 목표가 없어요'), findsOneWidget);
      expect(find.text('이번 주에 다음 주 목표를 고르면 다음 리포트에서 여기로 돌아와요'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('report-last-goals-count')),
        findsNothing,
      );
    });

    testWidgets('English — the empty state reads naturally', (tester) async {
      await _pump(
        tester,
        locale: 'en',
        report: _report(goals: const <String>[]),
      );

      expect(find.text("Last week's goals"), findsOneWidget);
      expect(find.text('No goals were picked last week'), findsOneWidget);
      expect(
        find.text(
          'Pick next week\'s goals now and they come back here in the next report',
        ),
        findsOneWidget,
      );
    });
  });

  group('목표가 있는 주 — 한국어', () {
    testWidgets('고른 순서대로 판정 · 목표 · 근거가 한 줄에 선다', (tester) async {
      await _pump(tester, report: _report());

      expect(_row(tester, 0), <String>['달성', '저녁 단백질 챙기기', '110 / 120g']);
      expect(_row(tester, 1), <String>['절반', '나트륨 줄이기', '2300 / 2000mg']);
      expect(_row(tester, 2), <String>['미달', '주 3회 운동', '20 / 80%']);
      // 수치로 볼 수 없는 목표에는 근거를 지어내지 않는다.
      expect(_row(tester, 3), <String>['직접 확인', '물 2L 마시기']);
    });

    testWidgets('판정마다 딱지 색이 다르다', (tester) async {
      await _pump(tester, report: _report());

      expect(_tone(tester, 0), AppTagTone.success);
      expect(_tone(tester, 1), AppTagTone.caution);
      expect(_tone(tester, 2), AppTagTone.danger);
      expect(_tone(tester, 3), AppTagTone.neutral);
    });

    testWidgets('제목 줄에 달성 수와 판정 기준을 적는다', (tester) async {
      await _pump(tester, report: _report());

      expect(find.text('1 / 4 달성'), findsOneWidget);
      expect(find.text('· 이번 주 기록으로 판정'), findsOneWidget);
      expect(
        tester
            .widget<AppTag>(
              find.byKey(const ValueKey<String>('report-last-goals-count')),
            )
            .tone,
        AppTagTone.neutral,
      );
    });

    testWidgets('전부 달성한 주는 달성 수 딱지가 초록이다', (tester) async {
      await _pump(tester, report: _report(goals: const <String>['저녁 단백질 챙기기']));

      expect(find.text('1 / 1 달성'), findsOneWidget);
      expect(
        tester
            .widget<AppTag>(
              find.byKey(const ValueKey<String>('report-last-goals-count')),
            )
            .tone,
        AppTagTone.success,
      );
    });

    testWidgets('카드 번호는 ③ 이다', (tester) async {
      await _pump(tester, report: _report());
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('목표가 있는 주 — English', () {
    testWidgets('verdicts, goals and evidence read in English', (tester) async {
      await _pump(tester, locale: 'en', report: _report());

      expect(_row(tester, 0), <String>['Met', '저녁 단백질 챙기기', '110 / 120g']);
      expect(_row(tester, 1), <String>['Partly', '나트륨 줄이기', '2300 / 2000mg']);
      expect(_row(tester, 2), <String>['Missed', '주 3회 운동', '20 / 80%']);
      expect(_row(tester, 3), <String>['Check yourself', '물 2L 마시기']);
      expect(find.text('1 / 4 met'), findsOneWidget);
      expect(find.text("· Judged from this week's records"), findsOneWidget);
    });

    testWidgets('goals picked in English are judged too', (tester) async {
      await _pump(
        tester,
        locale: 'en',
        report: _report(
          goals: const <String>['Protein at every dinner', 'Less sodium'],
        ),
      );

      expect(_row(tester, 0).first, 'Met');
      expect(_row(tester, 1).first, 'Partly');
      expect(find.text('1 / 2 met'), findsOneWidget);
    });
  });

  group('배치', () {
    testWidgets('좁은 화면에서도 넘치지 않는다', (tester) async {
      await _pump(
        tester,
        size: const Size(360, 800),
        report: _report(
          goals: const <String>[
            '저녁마다 단백질 30g 이상을 챙기고 간식은 두유로 바꾸기, 주말에도 같은 규칙 지키기',
            '나트륨 줄이기',
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(_row(tester, 0).first, '달성');
      // 좁은 칸에서는 근거가 목표 문장 아래로 내려갈 뿐 사라지지 않는다.
      expect(_row(tester, 1), <String>['절반', '나트륨 줄이기', '2300 / 2000mg']);
    });

    testWidgets('큰 글자에서도 넘치지 않는다', (tester) async {
      await _pump(
        tester,
        locale: 'en',
        size: const Size(480, 900),
        textScale: 1.6,
        report: _report(),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Check yourself'), findsOneWidget);
    });
  });
}
