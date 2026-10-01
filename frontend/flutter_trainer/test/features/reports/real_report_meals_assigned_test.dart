/// 실서버 리포트의 요일별 끼니 수·배정 개인운동 수. (#2772)
///
/// 실서버 디코더가 `meal_counts`·`days[].assigned` 를 읽지 않아, 데모에서는
/// 숫자가 서는 같은 화면이 실서버에서는 끼니 줄이 전부 `–`, 자동 문구에 끼니
/// 문장이 없고, 회원 PDF 끼니 칸도 `–` 였다. 개인운동 칸은 분모가 실제로 한
/// 운동 수로 되돌아가 늘 꽉 찬 것처럼 보였다.
///
/// 이 파일이 지키는 것:
///  * 디코더가 두 칸을 읽고, 없는 옛 응답은 지금처럼 빈 값으로 둔다.
///  * 실서버 응답으로 만든 리포트가 데모와 같은 규칙으로 끼니 문장·팁을 쓴다.
///  * 요일 표가 끼니 수와 `한 수 / 배정 수` 를 그린다.
///  * 결과지(공유 시트·PDF)가 같은 끼니 수를 읽는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart' show ReportSheet;
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_grid.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/fixed_clock.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();

/// 지난 주(고정한 오늘 2026-08-20 기준) 실서버 응답. 화요일·토·일은 끼니를
/// 적지 않았고, 월요일엔 배정 셋 중 둘을 했다.
Map<String, dynamic> _body({bool withMeals = true, bool withAssigned = true}) =>
    <String, dynamic>{
      'member_id': 'm1',
      'member_name': '김민수',
      'week_start': '2026-08-10',
      'week_end': '2026-08-16',
      'sessions_booked': 2,
      'sessions_done': 2,
      'completion_avg': 80,
      'sodium_over_days': 0,
      'sodium_avg': 1800,
      'week_completion': <int>[80, 0, 80, 80, 80, 0, 0],
      'sodium_week': <int>[1800, 0, 1800, 1800, 1800, 0, 0],
      'calories_week': <int>[1900, 0, 1800, 2000, 1850, 0, 0],
      'sugar_week': <double>[20, 0, 20, 20, 20, 0, 0],
      if (withMeals) 'meal_counts': <int>[3, 0, 2, 3, 3, 0, 0],
      'days': <Map<String, dynamic>>[
        <String, dynamic>{
          'completion': 80,
          'exercises': <String>['스쿼트', '런지'],
          if (withAssigned) 'assigned': 3,
        },
        <String, dynamic>{
          'completion': 0,
          'exercises': <String>[],
          if (withAssigned) 'assigned': null,
        },
        for (int i = 2; i < 7; i++)
          <String, dynamic>{
            'completion': 0,
            'exercises': <String>[],
            if (withAssigned) 'assigned': i == 2 ? 0 : null,
          },
      ],
      'message': '',
    };

WeeklyReport _decode(Map<String, dynamic> body) =>
    weeklyReportFromJson(body, makeClient(id: 'm1', name: '김민수'));

void main() {
  setUp(() => useFixedKstDate(kMidWeekKst));

  group('weeklyReportFromJson', () {
    test('meal_counts 를 요일별 끼니 수로 읽는다', () {
      expect(_decode(_body()).mealCounts, <int>[3, 0, 2, 3, 3, 0, 0]);
    });

    test('days[].assigned 를 그날 배정 수로 읽는다', () {
      final WeeklyReport report = _decode(_body());

      expect(report.days.first.assigned, 3);
      expect(report.days.first.total, 3);
      expect(report.days.first.done, 2);
    });

    test('assigned 가 null·0 인 날은 배정을 모르는 날이다 (#2232)', () {
      final WeeklyReport report = _decode(_body());

      // null 은 그대로, 0 은 쉬는 날과 구분되지 않아 null 로 읽는다.
      expect(report.days[1].assigned, isNull);
      expect(report.days[2].assigned, isNull);
      // 모르면 실제로 한 운동 수가 분모로 되돌아간다.
      expect(report.days[1].total, 0);
    });

    test('두 칸이 없는 옛 응답도 깨지지 않고 빈 값으로 둔다', () {
      final WeeklyReport report = _decode(
        _body(withMeals: false, withAssigned: false),
      );

      expect(report.mealCounts, isEmpty);
      expect(report.days, hasLength(7));
      expect(report.days.every((ReportDay d) => d.assigned == null), isTrue);
    });

    test('숫자가 아닌 값은 버린다', () {
      final Map<String, dynamic> body = _body()
        ..['meal_counts'] = <Object?>[3, 'x', null, 1, 1, 1, 1];
      (body['days'] as List<Map<String, dynamic>>).first['assigned'] = 'three';

      final WeeklyReport report = _decode(body);

      expect(report.days.first.assigned, isNull);
      // 7칸이 아니면 화면 규칙이 끼니 수를 모르는 자료로 본다.
      expect(report.mealCounts, hasLength(5));
    });
  });

  group('자동 문구 — 데모와 같은 규칙', () {
    test('실서버 응답에도 끼니 기록 문장이 들어간다', () {
      final String message = reportMessage(_ko, _decode(_body()));

      expect(message, contains(_ko.reportBodyMealDays(7, 4)));
    });

    test('빠진 날이 있으면 끼니 기록 팁이 들어간다', () {
      final String message = reportMessage(_ko, _decode(_body()));

      expect(message, contains(_ko.reportTipMeals));
    });

    test('끼니 수가 없는 옛 응답은 끼니 문장을 지어내지 않는다', () {
      final String message = reportMessage(
        _ko,
        _decode(_body(withMeals: false)),
      );

      expect(message, isNot(contains(_ko.reportBodyMealDays(7, 0))));
      expect(message, isNot(contains(_ko.reportTipMeals)));
    });

    test('같은 값의 데모 리포트와 같은 문구가 나온다', () {
      final WeeklyReport real = _decode(_body());
      final WeeklyReport demo = WeeklyReport(
        client: real.client,
        weekStart: real.weekStart,
        sessionsBooked: real.sessionsBooked,
        sessionsDone: real.sessionsDone,
        completionAvg: real.completionAvg,
        sodiumOverDays: real.sodiumOverDays,
        sodiumAvg: real.sodiumAvg,
        isCurrentWeek: real.isCurrentWeek,
        weekCompletion: real.weekCompletion,
        sodiumWeek: real.sodiumWeek,
        caloriesWeek: real.caloriesWeek,
        sugarWeek: real.sugarWeek,
        days: real.days,
        mealCounts: const <int>[3, 0, 2, 3, 3, 0, 0],
      );

      expect(reportMessage(_ko, real), reportMessage(_ko, demo));
    });
  });

  group('요일 표', () {
    Future<void> pump(WidgetTester tester, WeeklyReport report) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(OnCareSpacing.s16),
              child: ReportWeekGrid(report: report),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('실서버 리포트의 끼니 줄에 그날 끼니 수가 선다', (tester) async {
      await pump(tester, _decode(_body()));

      expect(find.text(_ko.reportsGridMealCount(3)), findsNWidgets(3));
      expect(find.text(_ko.reportsGridMealCount(2)), findsOneWidget);
      expect(find.text(_ko.reportsGridMealCount(0)), findsNWidgets(3));
    });

    testWidgets('배정을 아는 날은 개인운동 칸이 `한 수 / 배정 수` 다', (tester) async {
      await pump(tester, _decode(_body()));

      expect(find.text(_ko.reportsGridDoneOfAssigned(2, 3)), findsOneWidget);
      // 예전에는 분모가 한 운동 수로 돌아가 `2 / 2` 로 꽉 찬 날처럼 보였다.
      expect(find.text(_ko.reportsGridDoneOfAssigned(2, 2)), findsNothing);
    });

    testWidgets('끼니 수가 없는 옛 응답은 지금처럼 끼니 줄이 `–` 다', (tester) async {
      await pump(tester, _decode(_body(withMeals: false)));

      expect(find.text(_ko.reportsGridMealCount(3)), findsNothing);
    });
  });

  group('결과지(공유 시트·PDF)', () {
    test('실서버 리포트의 끼니 기록일이 실제 횟수로 선다', () {
      final ReportSheet sheet = ReportSheet.of(
        _decode(_body()),
        today: kMidWeekKst,
      );

      expect(sheet.mealDays, 4);
      expect(sheet.mealDaysDue, 7);
    });

    test('끼니 수가 없는 옛 응답은 끼니 기록일을 모른다', () {
      final ReportSheet sheet = ReportSheet.of(
        _decode(_body(withMeals: false)),
        today: kMidWeekKst,
      );

      expect(sheet.mealDaysDue, isNull);
    });
  });
}
