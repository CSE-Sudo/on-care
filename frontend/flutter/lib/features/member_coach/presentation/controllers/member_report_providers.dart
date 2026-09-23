import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/entities/member_weekly_report.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';

/// 트레이너가 보낸 리포트가 가리키는 주를, 회원 기록으로 다시 세운다. (#1600)
///
/// 새 엔드포인트를 두지 않는다 — 운동 탭·식단 탭·PT 일정이 이미 읽고 있는 값을
/// 모은다. 그래서 미리보기의 숫자가 회원이 앱에서 보는 숫자와 어긋나지 않는다.
///
/// 바로 앞 주도 함께 세운다(#1613). 트레이너 리포트 화면은 첫 카드가 `지난주
/// 대비` 비교라, 그 자리가 비면 같은 주를 두 앱이 다르게 말하게 된다.
final memberWeeklyReportProvider =
    FutureProvider.family<MemberWeeklyReport, DateTime>((
      ref,
      DateTime weekStart,
    ) async {
      final MemberWeeklyReport week = await ref.watch(
        _memberWeekProvider(mondayOfWeek(weekStart)).future,
      );
      final MemberWeeklyReport? last = await ref
          .watch(
            _memberWeekProvider(
              DateTime(
                week.weekStart.year,
                week.weekStart.month,
                week.weekStart.day - 7,
              ),
            ).future,
          )
          // 지난주를 못 읽는 것은 이번 주 문서를 막을 이유가 아니다 — 비교
          // 항목만 빠진다.
          .then<MemberWeeklyReport?>((MemberWeeklyReport r) => r)
          .catchError((Object _) => null);
      return week.copyWithPrevious(last);
    }, name: 'memberWeeklyReport');

/// 한 주치 집계. `지난주 대비` 를 위해 두 번 부르므로 따로 뗀다.
final _memberWeekProvider = FutureProvider.family<MemberWeeklyReport, DateTime>(
  (ref, DateTime weekStart) async {
    final DateTime monday = mondayOfWeek(weekStart);
    final DateTime today = DateTime(
      nowKst().year,
      nowKst().month,
      nowKst().day,
    );
    final bool isThisWeek = monday == mondayOfWeek(today);

    // watch 는 await 이전에 모두 건다 — 하나라도 바뀌면 문서도 다시 세워진다.
    final Future<ExerciseWeek> exercise = isThisWeek
        ? ref.watch(exerciseWeekProvider.future)
        : ref.watch(exercisePastWeekProvider(monday).future);
    final Future<DietPeriod> diet = ref.watch(
      dietPeriodProvider((
        from: monday,
        to: DateTime(monday.year, monday.month, monday.day + 6),
      )).future,
    );
    final Future<List<CoachSession>> sessions = ref.watch(
      coachSessionsProvider.future,
    );
    // 나트륨 초과 일수는 회원 자신의 목표로 센다 — MY 화면이 쓰는 값과 같다.
    final Future<UserProfile> profile = ref.watch(profileProvider.future);
    final ExerciseWeek week = await exercise;
    final DateTime sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final List<CoachSession> inWeek = (await sessions)
        .where((CoachSession s) {
          final DateTime? date = s.date;
          if (date == null) return false;
          final DateTime day = DateTime(date.year, date.month, date.day);
          return !day.isBefore(monday) && !day.isAfter(sunday);
        })
        .toList(growable: false);

    return MemberWeeklyReport(
      weekStart: monday,
      exercise: week,
      diet: await diet,
      // 취소된 PT 는 잡혀 있던 것으로 세지 않는다 — 진행되지 않은 일정을
      // 분모에 두면 출석률이 실제보다 낮게 읽힌다(#871 과 같은 규칙).
      sessionsBooked: inWeek.where((CoachSession s) => !s.isCancelled).length,
      // 잡힌 일정이 하나도 없어도 그 주에 **PT 로 기록된 운동**은 있을 수 있다
      // — 담당 트레이너의 일정 목록을 받지 못하는 경로(데모)가 그렇다. 그때는
      // 진행한 PT 를 운동 기록에서 센다. 둘 다 없을 때만 잡힌 일정이 없다고
      // 적는다(#1613).
      sessionsDone: inWeek.isEmpty
          ? week.sessions
                .where(
                  (ExerciseSession s) => s.source == ExerciseSource.trainerPt,
                )
                .length
          : inWeek.where((CoachSession s) => s.isDone).length,
      sodiumTarget: (await profile).effectiveDailySodiumMg,
      calorieTarget: (await profile).effectiveDailyCalories,
      sugarTarget: (await profile).effectiveDailySugarG,
      // 세운 날. 그 주에서 아직 오지 않은 요일을 가리는 데 쓴다(#1613) — 넘기지
      // 않으면 오지 않은 날이 다시 `기록 없음` 으로 적힌다.
      asOf: today,
    );
  },
  name: 'memberWeek',
);
