/// 트레이너 웹 데모 회원 상세 시드(#2667) — 지난 끼니·운동 현황·성별·나이·
/// 식단 계획·후속 관리·메모·프로그램 초안.
///
/// 김민수(`seed-client-1`)는 공유 픽스처가 정하므로 여기서는 나머지 회원을 본다.
library;

import 'dart:ui' show Locale;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/storage/seed_menu_plans.dart';
import 'package:oncare_trainer/core/storage/seed_trainer_notes.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/follow_up_task.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_draft_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/follow_up_task_repository.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fixed_clock.dart';

/// 심긴 모든 고객의 미완료 후속 관리.
Future<List<FollowUpTask>> _pendingFollowUps(SharedPreferences prefs) async {
  const String prefix = 'trainer_follow_ups:';
  final LocalFollowUpTaskRepository repository = LocalFollowUpTaskRepository(
    prefs,
  );
  final List<FollowUpTask> tasks = <FollowUpTask>[];
  for (final String key in prefs.getKeys()) {
    if (!key.startsWith(prefix)) continue;
    tasks.addAll(await repository.fetchForClient(key.substring(prefix.length)));
  }
  return tasks;
}

void main() {
  late AppDatabase db;
  late DriftClientRepository repo;

  setUp(() async {
    useFixedKstDate(kMidWeekKst);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db, clock: kMidWeekKst);
    repo = DriftClientRepository(db);
  });
  tearDown(() => db.close());

  group('지난 끼니', () {
    test('지난 날짜를 열면 그날 합계와 같은 끼니 카드가 나온다', () async {
      final DateTime today = DateTime(2026, 8, 20);
      final List<ClientDailyMetricRow> metrics =
          await (db.select(db.clientDailyMetrics)..where(
                (t) =>
                    t.clientId.equals('seed-client-2') &
                    t.date.isBiggerOrEqualValue(
                      ymd(DateTime(2026, 8, 20 - 27)),
                    ) &
                    t.date.isSmallerThanValue(ymd(today)),
              ))
              .get();
      final List<ClientDailyMetricRow> eaten = metrics
          .where((ClientDailyMetricRow m) => m.calories > 0)
          .toList();
      expect(eaten.length, greaterThanOrEqualTo(14));
      for (final ClientDailyMetricRow m in eaten) {
        final List<ClientDietEntry> meals = await repo.fetchDietOn(
          'seed-client-2',
          DateTime.parse(m.date),
        );
        expect(meals, hasLength(m.mealCount), reason: m.date);
        expect(
          meals.fold<int>(0, (int a, ClientDietEntry e) => a + e.calories),
          m.calories,
          reason: m.date,
        );
        expect(
          meals.fold<int>(0, (int a, ClientDietEntry e) => a + e.sodiumMg),
          m.sodiumMg,
          reason: m.date,
        );
        // 끼니 카드의 음식 줄도 끼니 합계와 같다.
        for (final ClientDietEntry meal in meals) {
          expect(meal.foods, isNotEmpty, reason: m.date);
          expect(
            meal.foods.fold<int>(0, (int a, f) => a + f.calories),
            meal.calories,
            reason: '${m.date} ${meal.meal}',
          );
        }
      }
    });

    test('오늘 끼니는 시드 그대로다 — 지난 끼니가 오늘에 섞이지 않는다', () async {
      final List<ClientDietEntry> today = await repo.fetchDietOn(
        'seed-client-2',
        DateTime(2026, 8, 20),
      );
      final TrainerClientRow row = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-2'))).getSingle();
      expect(
        today.fold<int>(0, (int a, ClientDietEntry e) => a + e.calories),
        row.caloriesToday,
      );
    });

    test('4주보다 오래된 날도 끼니 카드가 합계와 같다 (#2732)', () async {
      // 기간 뷰는 리포트 이력 전체를 그린다 — 오래된 날을 펼쳐도 카드가 있어야 한다.
      final String old = ymd(DateTime(2026, 8, 20 - 60));
      final List<ClientDailyMetricRow> metrics =
          await (db.select(db.clientDailyMetrics)..where(
                (t) =>
                    t.clientId.equals('seed-client-2') &
                    t.date.isSmallerOrEqualValue(old),
              ))
              .get();
      final List<ClientDailyMetricRow> eaten = metrics
          .where((ClientDailyMetricRow m) => m.calories > 0)
          .toList();
      expect(eaten, isNotEmpty);
      for (final ClientDailyMetricRow m in eaten) {
        final List<ClientDietEntry> meals = await repo.fetchDietOn(
          'seed-client-2',
          DateTime.parse(m.date),
        );
        expect(meals, hasLength(m.mealCount), reason: m.date);
        expect(
          meals.fold<int>(0, (int a, ClientDietEntry e) => a + e.calories),
          m.calories,
          reason: m.date,
        );
      }
    });
  });

  group('운동 현황', () {
    test('연속 일수·주간 목표를 회원 목표에서 채운다', () async {
      // 최우진 — 7일 100%, 하루 소모 목표 400kcal.
      final ClientExerciseWeek week = await repo.fetchExerciseWeek(
        'seed-client-5',
      );
      expect(week.streakDays, greaterThan(0));
      expect(week.weeklyGoalMinutes, 150);
      expect(week.weeklyGoalCalories, 400 * 7);
    });

    test('유형별 분·칼로리는 그날 한 운동에서 세고, 합이 하루 총합과 같다', () async {
      final ClientExerciseWeek week = await repo.fetchExerciseWeek(
        'seed-client-5',
        weekStart: DateTime(2026, 8, 10),
      );
      expect(week.totalMinutes, greaterThan(0));
      for (var d = 0; d < 7; d++) {
        expect(
          week.cardioMinutes[d] +
              week.strengthMinutes[d] +
              week.stretchingMinutes[d],
          week.dailyMinutes[d],
          reason: 'day $d',
        );
        expect(
          week.cardioCalories[d] +
              week.strengthCalories[d] +
              week.stretchingCalories[d],
          week.dailyCalories[d],
          reason: 'day $d',
        );
      }
      expect(week.strengthSets.any((int s) => s > 0), isTrue);
    });

    test('김민수도 연속 일수와 목표를 싣는다', () async {
      final ClientExerciseWeek week = await repo.fetchExerciseWeek(
        'seed-client-1',
      );
      expect(week.weeklyGoalMinutes, 150);
      expect(week.weeklyGoalCalories, 350 * 7);
    });
  });

  test('성별·나이를 로스터에 심는다 — 김민수도 백엔드 시드와 같은 값이다 (#2744)', () async {
    final List<TrainerClientRow> rows = await db
        .select(db.trainerClients)
        .get();
    final TrainerClientRow yuna = rows.firstWhere(
      (TrainerClientRow r) => r.id == 'seed-client-10',
    );
    expect(yuna.gender, 'female');
    expect(yuna.age, 41);
    // 나이 폴백이 없어졌으므로 김민수도 비워 두면 데모 화면에 나이가 빠진다.
    final TrainerClientRow minsu = rows.firstWhere(
      (TrainerClientRow r) => r.id == 'seed-client-1',
    );
    expect(minsu.gender, 'male');
    expect(minsu.age, 36);
    for (final TrainerClientRow r in rows) {
      expect(r.gender, isNotNull, reason: r.name);
      expect(r.age, isNotNull, reason: r.name);
    }
  });

  test('지난 두 주의 PT 에 메모가 있고, 지난 상담이 있다', () async {
    final List<TrainerScheduleRow> rows = await db
        .select(db.trainerScheduleEntries)
        .get();
    final String twoWeeksAgo = ymd(DateTime(2026, 8, 20 - 14));
    final String monday = ymd(DateTime(2026, 8, 17));
    final List<TrainerScheduleRow> recentPast = rows
        .where(
          (TrainerScheduleRow r) =>
              r.id.startsWith('seed-schedule-p') &&
              r.date.compareTo(twoWeeksAgo) >= 0 &&
              r.date.compareTo(monday) < 0,
        )
        .toList();
    expect(
      recentPast.where((TrainerScheduleRow r) => r.note.isNotEmpty),
      isNotEmpty,
    );
    final List<TrainerScheduleRow> consults = rows
        .where((TrainerScheduleRow r) => r.id.startsWith('seed-schedule-c'))
        .toList();
    expect(consults, isNotEmpty);
    for (final TrainerScheduleRow c in consults) {
      expect(c.type, SessionType.consultation);
      expect(c.status, ScheduleStatus.done);
      expect(c.note, isNotEmpty);
      expect(c.clientId, startsWith('seed-client-'));
    }
  });

  group('식단 계획', () {
    List<String> names(List<DemoPlanMenu> plan) =>
        plan.map((DemoPlanMenu m) => m.name).toList();

    test('김민수는 공유 리스트, 다른 회원은 회원마다 다른 리스트다', () {
      expect(
        names(demoMenuPlanFor('seed-client-1', 'ko')),
        names(kDemoMenuPlan['ko']!),
      );
      final Set<String> plans = <String>{
        for (var n = 2; n <= 15; n++)
          names(demoMenuPlanFor('seed-client-$n', 'ko')).join('|'),
      };
      expect(plans, hasLength(14));
    });

    test('칸의 끼니·추천 이유는 공유 리스트와 같고, 영어 이름은 한국어와 다르다', () {
      final List<DemoPlanMenu> ko = demoMenuPlanFor('seed-client-4', 'ko');
      final List<DemoPlanMenu> en = demoMenuPlanFor('seed-client-4', 'en');
      final List<DemoPlanMenu> base = kDemoMenuPlan['ko']!;
      expect(ko, hasLength(base.length));
      for (var i = 0; i < base.length; i++) {
        expect(ko[i].slot, base[i].slot);
        expect(ko[i].tag, base[i].tag);
        expect(en[i].tag, base[i].tag);
        expect(en[i].name, isNot(ko[i].name));
        expect(ko[i].name.length, lessThanOrEqualTo(12));
        expect(en[i].name.length, lessThanOrEqualTo(28));
      }
    });

    test('AI 식단 추천 후보가 그 회원의 리스트에서 나오고, 근거 일수가 하루를 넘는다', () async {
      final r = await repo.fetchDietRecommendations(
        'seed-client-6',
        locale: const Locale('ko'),
      );
      expect(r.basisDays, greaterThan(7));
      final Set<String> plan = names(
        demoMenuPlanFor('seed-client-6', 'ko'),
      ).toSet();
      for (final c in r.candidates) {
        expect(plan, contains(c.name));
      }
    });
  });

  group('후속 관리·메모·프로그램 초안', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    test('후속 관리·메모·초안을 심고, 두 번 불러도 한 번만 심는다', () async {
      await seedDemoTrainerNotes(prefs, clock: kMidWeekKst);
      await seedDemoTrainerNotes(prefs, clock: kMidWeekKst);

      final LocalFollowUpTaskRepository followUps = LocalFollowUpTaskRepository(
        prefs,
      );
      final List<FollowUpTask> pending = await _pendingFollowUps(prefs);
      expect(pending, isNotEmpty);
      // 기한이 지난 할 일도 심는다.
      expect(
        pending.any(
          (FollowUpTask t) => t.dueDate.isBefore(DateTime(2026, 8, 20)),
        ),
        isTrue,
      );
      final List<FollowUpTask> jisu = await followUps.fetchForClient(
        'seed-client-2',
        includeCompleted: true,
      );
      expect(jisu.single.isCompleted, isTrue);

      final List<TrainerMemo> sera = await LocalTrainerMemoRepository(
        prefs,
      ).fetch('seed-client-8');
      expect(
        sera.where((TrainerMemo m) => m.source == TrainerMemoSource.trainer),
        hasLength(1),
      );

      final drafts = await LocalTrainerProgramDraftRepository(prefs).list();
      expect(drafts, hasLength(3));
      final draft = await LocalTrainerProgramDraftRepository(
        prefs,
      ).read(drafts.first.id);
      expect(draft.sessions, isNotEmpty);
    });

    test('채팅 감지 메모가 있으면 그 목록에 덧붙인다', () async {
      await prefs.setString(
        'trainer_memos:seed-client-8',
        '[{"id":"memo-seed-x","body":"허리 통증","source":"chat_insight",'
            '"created_at":"2026-08-19T10:00:00.000"}]',
      );
      await seedDemoTrainerNotes(prefs, clock: kMidWeekKst);
      final List<TrainerMemo> memos = await LocalTrainerMemoRepository(
        prefs,
      ).fetch('seed-client-8');
      expect(memos.map((TrainerMemo m) => m.id), contains('memo-seed-x'));
      expect(memos.length, 2);
    });

    test('영어 데모는 영어로 심는다', () async {
      await seedDemoTrainerNotes(
        prefs,
        language: DemoLanguage.en,
        clock: kMidWeekKst,
      );
      final List<FollowUpTask> pending = await _pendingFollowUps(prefs);
      expect(pending, isNotEmpty);
      for (final FollowUpTask t in pending) {
        expect(RegExp('[가-힣]').hasMatch(t.title), isFalse, reason: t.title);
      }
    });
  });
}
