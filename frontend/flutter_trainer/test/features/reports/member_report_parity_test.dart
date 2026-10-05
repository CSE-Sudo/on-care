/// 회원 앱 데모가 여는 김민수 리포트가 이 앱 데모의 김민수 리포트와 같은가. (#2652)
///
/// 회원 앱에는 이 앱의 drift 시드가 없어, 같은 픽스처에서 같은 규칙으로 결과지
/// 자료를 바로 만든다(`demoReportSheetInputs`). 이 테스트는 그 규칙이 이 앱의
/// 시드와 갈라지지 않았는지 — 요일별 수치·끼니 수·PT·회원 답·운동 목표 — 를
/// 심은 DB 와 견줘 확인한다. 한쪽만 고치면 여기서 깨진다.
library;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart'
    show
        DemoReportAnswer,
        ExerciseKind,
        ReportSheetAnswers,
        ReportSheetInputs,
        ReportSheetWeek,
        demoReportSheetInputs,
        kDemoReportAnswers,
        kDemoReportGoals,
        kDemoReportPtWeeks,
        kReportSheetHistoryWeeks,
        kReportSheetTrendWeeks;
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/storage/seed_health_profiles.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_history.dart';
import 'package:oncare_trainer/features/reports/data/repositories/calorie_baseline.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

/// 목요일 21시 — 이번 주 월~목이 채워지고 주말은 아직 오지 않은 날.
final DateTime _now = DateTime(2026, 9, 24, 21);
final DateTime _thisMonday = DateTime(2026, 9, 21);
const String _minsu = 'seed-client-1';

Future<AppDatabase> _seeded(DemoLanguage language) async {
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  await seedIfEmpty(db, clock: _now, language: language);
  return db;
}

DateTime _weeksAgo(int back) =>
    DateTime(_thisMonday.year, _thisMonday.month, _thisMonday.day - 7 * back);

ReportSheetInputs _member(DateTime weekStart, {String lang = 'ko'}) =>
    demoReportSheetInputs(
      fixture: DemoFixture.load(),
      weekStart: weekStart,
      now: _now,
      languageCode: lang,
    );

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('주 수·목표 상수가 이 앱과 같다', () {
    expect(kDemoReportPtWeeks, demoReportHistoryWeeks);
    expect(kReportSheetTrendWeeks, kReportTrendWeeks);
    expect(kReportSheetHistoryWeeks, kCalorieBaselineWeeks);
    final Map<String, num> profile = seedHealthProfiles[1]!;
    expect(
      kDemoReportGoals.of(ExerciseKind.cardio),
      profile['weekly_cardio_minutes'],
    );
    expect(
      kDemoReportGoals.of(ExerciseKind.strength),
      profile['weekly_strength_sets'],
    );
    expect(
      kDemoReportGoals.of(ExerciseKind.stretching),
      profile['weekly_flexibility_minutes'] ?? 60,
    );
  });

  test('요일별 수치·끼니 수·배정 수가 심은 일별 지표와 같다', () async {
    final AppDatabase db = await _seeded(DemoLanguage.ko);
    addTearDown(db.close);
    final List<ClientDailyMetricRow> rows = await (db.select(
      db.clientDailyMetrics,
    )..where((t) => t.clientId.equals(_minsu))).get();
    final Map<String, ClientDailyMetricRow> byDate =
        <String, ClientDailyMetricRow>{for (final r in rows) r.date: r};

    for (int back = 0; back < 6; back++) {
      final DateTime monday = _weeksAgo(back);
      final ReportSheetWeek week = _member(monday).week;
      for (int d = 0; d < 7; d++) {
        final ClientDailyMetricRow? row =
            byDate[ymd(DateTime(monday.year, monday.month, monday.day + d))];
        final String at = '$back주 전 ${d + 1}번째 날';
        if (row == null) {
          if (week.caloriesWeek.isNotEmpty) {
            expect(week.caloriesWeek[d], 0, reason: at);
            expect(week.mealCounts[d], 0, reason: at);
          }
          continue;
        }
        expect(week.caloriesWeek[d], row.calories, reason: at);
        expect(week.sodiumWeek[d], row.sodiumMg, reason: at);
        expect(week.sugarWeek[d], closeTo(row.sugarG, 1e-9), reason: at);
        expect(week.carbsWeek[d], closeTo(row.carbsG, 1e-9), reason: at);
        expect(week.proteinWeek[d], closeTo(row.proteinG, 1e-9), reason: at);
        expect(week.fatWeek[d], closeTo(row.fatG, 1e-9), reason: at);
        expect(week.weekCompletion[d], row.completion, reason: at);
        expect(week.mealCounts[d], row.mealCount, reason: at);
        expect(
          week.days[d].assigned,
          row.assignedCount > 0 ? row.assignedCount : null,
          reason: at,
        );
      }
    }
  });

  test('PT 는 이 앱 스케줄과 같이 주마다 한 번 진행했다', () async {
    final AppDatabase db = await _seeded(DemoLanguage.ko);
    addTearDown(db.close);
    final rows = await (db.select(
      db.trainerScheduleEntries,
    )..where((t) => t.clientId.equals(_minsu))).get();
    for (int back = 0; back <= kDemoReportPtWeeks; back++) {
      final DateTime monday = _weeksAgo(back);
      final DateTime sunday = DateTime(
        monday.year,
        monday.month,
        monday.day + 6,
      );
      final inWeek = rows.where((r) {
        final DateTime day = DateTime.parse(r.date);
        return !day.isBefore(monday) && !day.isAfter(sunday);
      }).toList();
      final ReportSheetWeek week = _member(monday).week;
      expect(week.sessionsBooked, inWeek.length, reason: '$back주 전');
      expect(
        week.sessionsDone,
        inWeek.where((r) => r.status == ScheduleStatus.done).length,
        reason: '$back주 전',
      );
    }
  });

  for (final (DemoLanguage language, String lang) in <(DemoLanguage, String)>[
    (DemoLanguage.ko, 'ko'),
    (DemoLanguage.en, 'en'),
  ]) {
    test('회원 답이 심은 주간 피드백과 같다 ($lang)', () async {
      final AppDatabase db = await _seeded(language);
      addTearDown(db.close);
      final rows = await (db.select(
        db.clientWeeklyFeedbacks,
      )..where((t) => t.clientId.equals(_minsu))).get();
      expect(rows, hasLength(kDemoReportAnswers.length));
      for (final DemoReportAnswer a in kDemoReportAnswers) {
        final DateTime monday = _weeksAgo(a.weeksAgo);
        final row = rows.singleWhere((r) => r.weekStart == ymd(monday));
        final ReportSheetAnswers answers = _member(
          monday,
          lang: lang,
        ).week.answers!;
        final String at = '${a.weeksAgo}주 전';
        expect(answers.conditionWire, row.condition, reason: at);
        expect(answers.intensityWire, row.intensity, reason: at);
        expect(answers.painArea, row.painArea, reason: at);
        expect(
          answers.painOn == null ? '' : ymd(answers.painOn!),
          row.painOn,
          reason: at,
        );
        expect(answers.note, row.note, reason: at);
      }
    });
  }
}
