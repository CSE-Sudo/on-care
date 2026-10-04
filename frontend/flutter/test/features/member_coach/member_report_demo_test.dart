/// 데모가 실제로 지나는 길로 세운 리포트 결과지 (#1617, #2652).
///
/// 다른 리포트 테스트들은 손으로 만든 자료를 결과지로 옮기는 부분만 본다. 여기서는
/// **데모가 실제로 지나는 길**을 통째로 지난다 — drift 시드 → 데모 대화의 리포트
/// 안내 → 저장소 → 결과지 자료.
///
/// 지키는 것은 하나다: 회원 앱 데모가 여는 리포트가 트레이너 웹 데모가 김민수를
/// 두고 그리는 결과지와 **같은 값**이어야 한다. 두 앱을 나란히 놓고 시연하므로
/// 같은 주를 두 앱이 다른 점수로 말하면 바로 드러난다.
library;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_report_providers.dart';
import 'package:oncare/features/member_coach/services/member_report_pdf_generator.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_report/oncare_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  late ProviderContainer container;
  late CoachMessage notice;

  Future<void> setUpDemo(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() => seedIfEmpty(db));

    container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_config),
        appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    late List<CoachMessage> chat;
    await tester.runAsync(() async {
      chat = await container.read(memberCoachRepositoryProvider).fetchChat();
    });
    notice = chat.firstWhere(
      (CoachMessage m) => m.reportWeekStart != null,
      orElse: () => throw StateError('데모 대화에 리포트 안내가 없다'),
    );
  }

  Future<ReportSheetInputs> load(WidgetTester tester, String lang) async {
    late ReportSheetInputs inputs;
    await tester.runAsync(() async {
      inputs = await loadMemberReportSheet(
        container.read,
        weekStart: notice.reportWeekStart!,
        languageCode: lang,
      );
    });
    return inputs;
  }

  testWidgets('데모 리포트는 트레이너 웹 데모의 김민수 결과지와 같은 값이다', (
    WidgetTester tester,
  ) async {
    await setUpDemo(tester);
    final ReportSheetInputs mine = await load(tester, 'ko');
    final ReportSheetInputs trainer = demoReportSheetInputs(
      fixture: DemoFixture.load(),
      weekStart: reportWeekStartOf(notice.reportWeekStart!),
      now: nowKst(),
    );

    final ReportSheetWeek a = mine.week;
    final ReportSheetWeek b = trainer.week;
    expect(a.memberName, '김민수');
    expect(a.memberName, b.memberName);
    expect(a.weekStart, b.weekStart);
    expect(a.sessionsBooked, b.sessionsBooked);
    expect(a.sessionsDone, b.sessionsDone);
    expect(a.completionAvg, b.completionAvg);
    expect(a.sodiumAvg, b.sodiumAvg);
    expect(a.weekCompletion, b.weekCompletion);
    expect(a.caloriesWeek, b.caloriesWeek);
    expect(a.sodiumWeek, b.sodiumWeek);
    expect(a.sugarWeek, b.sugarWeek);
    expect(a.mealCounts, b.mealCounts);
    expect(
      a.days.map((ReportSheetDay d) => d.exercises).toList(),
      b.days.map((ReportSheetDay d) => d.exercises).toList(),
    );
    expect(a.answers?.conditionWire, b.answers?.conditionWire);
    expect(a.answers?.intensityWire, b.answers?.intensityWire);
    expect(a.answers?.note, b.answers?.note);

    expect(mine.history, hasLength(trainer.history.length));
    for (int i = 0; i < trainer.history.length; i++) {
      expect(mine.history[i].weekStart, trainer.history[i].weekStart);
      expect(mine.history[i].caloriesWeek, trainer.history[i].caloriesWeek);
      expect(mine.history[i].completionAvg, trainer.history[i].completionAvg);
    }
    expect(mine.trend!.weeks, hasLength(kReportSheetTrendWeeks));
    for (int i = 0; i < kReportSheetTrendWeeks; i++) {
      for (final ExerciseKind kind in ExerciseKind.values) {
        expect(
          mine.trend!.weeks[i].valueOf(kind),
          trainer.trend!.weeks[i].valueOf(kind),
          reason: '추이 ${i + 1}번째 주 ${kind.name}',
        );
      }
    }
  });

  testWidgets('데모 리포트의 점수가 트레이너 웹 데모와 같다', (WidgetTester tester) async {
    await setUpDemo(tester);
    final ReportSheetInputs mine = await load(tester, 'ko');
    final ReportSheetInputs trainer = demoReportSheetInputs(
      fixture: DemoFixture.load(),
      weekStart: reportWeekStartOf(notice.reportWeekStart!),
      now: nowKst(),
    );
    final DateTime today = nowKst();
    final ReportSheet a = ReportSheet.of(
      mine.week,
      trend: mine.trend,
      history: mine.history,
      today: today,
    );
    final ReportSheet b = ReportSheet.of(
      trainer.week,
      trend: trainer.trend,
      history: trainer.history,
      today: today,
    );
    // SheetScore 는 값 비교(==)를 두지 않는다 — 점수와 항목별 점수를 따로 본다.
    expect(a.score.value, b.score.value);
    expect(a.score.parts, b.score.parts);
    expect(a.mealDays, b.mealDays);
    expect(a.mealDaysDue, b.mealDaysDue);
    expect(a.weeklyRates, b.weeklyRates);
  });

  testWidgets('데모 리포트는 기록이 있는 주를 연다 — 빈 결과지가 아니다', (WidgetTester tester) async {
    await setUpDemo(tester);
    final ReportSheetInputs mine = await load(tester, 'ko');
    expect(
      mine.week.caloriesWeek.any((int v) => v > 0) ||
          mine.week.weekCompletion.any((int? v) => (v ?? 0) > 0),
      isTrue,
    );
    expect(mine.week.sessionsBooked, greaterThan(0));
  });

  testWidgets('데모 리포트를 글자 문서로 옮겨도 김민수와 트레이너 글이 실린다', (
    WidgetTester tester,
  ) async {
    await setUpDemo(tester);
    final ReportSheetInputs mine = await load(tester, 'ko');
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
    final List<String> lines = const MemberReportPdfGenerator().textContent(
      l: l,
      inputs: mine,
      feedback: trainerReportFeedback(notice.body),
    );
    expect(lines, contains('· 회원: 김민수'));
    if (notice.body.trim().isNotEmpty) {
      expect(lines, contains(notice.body.trim()));
    }
  });

  testWidgets('영어 화면이면 같은 수치에 영어 답이다', (WidgetTester tester) async {
    await setUpDemo(tester);
    final ReportSheetInputs ko = await load(tester, 'ko');
    final ReportSheetInputs en = await load(tester, 'en');
    expect(en.week.completionAvg, ko.week.completionAvg);
    expect(en.week.caloriesWeek, ko.week.caloriesWeek);
    expect(en.week.answers?.conditionWire, ko.week.answers?.conditionWire);
  });
}
