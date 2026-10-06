/// 운동 기록을 고치거나 지우면 함께 달라지는 화면을 모두 다시 읽는다.
/// (#2629, #2631, #2634)
///
/// 수정·삭제 흐름을 실제로 거친 뒤, 지난 주 하루·AI 조언·MY 기록 달력·보호권·
/// 포인트·주간 챌린지·첫 기록일이 각각 다시 만들어졌는지 센다. 예전에는 삭제가
/// 달력·보호권을 빠뜨렸고, 수정이 주간 챌린지를 빠뜨렸고, 둘 다 지난 주와 조언을
/// 비우지 않았다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_session_draft.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/services/record_span_provider.dart';
import 'package:oncare_ui/oncare_ui.dart';

const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

const ExerciseWeek _emptyWeek = ExerciseWeek(
  sessions: <ExerciseSession>[],
  dailyMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  dayLabels: _dayLabels,
  totalMinutes: 0,
  totalCalories: 0,
  streakDays: 0,
  aiCoachMessage: '',
);

/// 지난 주 월요일로 쓰는 키. 값 자체는 중요하지 않다 — 같은 키를 보고 있다는
/// 것이 중요하다.
final DateTime _pastMonday = DateTime(2026, 9, 7);

/// 요청 수만 세는 운동 저장소.
class _CountingRepository implements ExerciseRepository {
  int adviceCalls = 0;
  int pastWeekCalls = 0;
  int updated = 0;
  int deleted = 0;

  @override
  Future<ExerciseAdvice> fetchAdvice(String period) async {
    adviceCalls++;
    return const ExerciseAdvice(message: '조언');
  }

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _emptyWeek;

  @override
  Future<List<ExercisePeriodWeek>> fetchPeriod({
    DateTime? from,
    DateTime? to,
  }) async => const <ExercisePeriodWeek>[];

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async {
    pastWeekCalls++;
    return _emptyWeek;
  }

  @override
  Future<ExerciseCalorieEstimate> previewCalories({
    required ExerciseType type,
    required String name,
    required int minutes,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
  }) async => ExerciseCalorieEstimate(
    calories: estimateExerciseCalories(type, minutes, intensity: intensity),
  );

  @override
  Future<ExerciseSessionsAdded> addSessions(
    List<ExerciseSessionDraft> drafts,
  ) async => const ExerciseSessionsAdded(sessions: <ExerciseSession>[]);

  @override
  Future<void> deleteSession(String id) async {
    deleted++;
  }

  @override
  Future<ExerciseSession> updateSession({
    required String id,
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    String name = '',
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? sets,
    int? reps,
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
  }) async {
    updated++;
    return ExerciseSession(
      id: id,
      dayLabel: _dayLabels[date.weekday - 1],
      type: type,
      minutes: minutes,
      calories: calories,
      name: name,
      date: date,
    );
  }
}

/// provider 가 몇 번 만들어졌는지. 값은 끝나지 않는 Future 로 둔다 — 여기서는
/// 다시 만들어졌는지만 본다.
class _Builds {
  int calendar = 0;
  int shields = 0;
  int health = 0;
  int challenge = 0;
  int span = 0;
}

final ExerciseSession _session = ExerciseSession(
  id: 'ex-1',
  dayLabel: '목',
  type: ExerciseType.cardio,
  minutes: 30,
  calories: 120,
  name: '걷기',
  date: DateTime(2026, 9, 10),
);

void main() {
  late _CountingRepository repo;
  late _Builds builds;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo = _CountingRepository();
    builds = _Builds();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          exerciseRepositoryProvider.overrideWithValue(repo),
          activityCalendarProvider.overrideWith((ref) {
            builds.calendar++;
            return Completer<ActivityCalendar>().future;
          }),
          myStreakShieldsProvider.overrideWith((ref) {
            builds.shields++;
            return Completer<StreakShields>().future;
          }),
          myHealthStateProvider.overrideWith((ref) {
            builds.health++;
            return Completer<MyHealthState>().future;
          }),
          weeklyChallengeProvider.overrideWith((ref) {
            builds.challenge++;
            return Completer<WeeklyChallenge>().future;
          }),
          recordSpanProvider.overrideWith((ref) {
            builds.span++;
            return Completer<RecordSpan>().future;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) {
                // 운동 탭(지난 주 하루·조언)과 MY 탭(달력·보호권·잔액·챌린지)을
                // 보고 있는 상태 — 무효화되면 다시 만든다.
                ref
                  ..watch(exercisePastWeekProvider(_pastMonday))
                  ..watch(exerciseAdviceProvider('week'))
                  ..watch(activityCalendarProvider)
                  ..watch(myStreakShieldsProvider)
                  ..watch(myHealthStateProvider)
                  ..watch(weeklyChallengeProvider)
                  ..watch(recordSpanProvider);
                return TextButton(
                  onPressed: () =>
                      confirmDeleteExerciseSession(context, ref, _session),
                  child: const Text('지우기'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dismissToast(WidgetTester tester) async {
    await tester.pump(OnCareMotion.toastVisible);
    await tester.pumpAndSettle();
  }

  void expectEverythingRebuiltOnce() {
    expect(repo.pastWeekCalls, 2, reason: '지난 주 하루 (#2629)');
    expect(repo.adviceCalls, 2, reason: 'AI 맞춤 조언 (#2631)');
    expect(builds.calendar, 2, reason: 'MY 기록 달력 (#2634)');
    expect(builds.shields, 2, reason: '보호권 (#2634)');
    expect(builds.health, 2, reason: '포인트 잔액');
    expect(builds.challenge, 2, reason: '주간 챌린지 (#2634)');
    expect(builds.span, 2, reason: '첫 기록일');
  }

  testWidgets('처음에는 한 번씩만 읽는다', (WidgetTester tester) async {
    await pump(tester);

    expect(repo.pastWeekCalls, 1);
    expect(repo.adviceCalls, 1);
    expect(builds.calendar, 1);
    expect(builds.shields, 1);
    expect(builds.health, 1);
    expect(builds.challenge, 1);
    expect(builds.span, 1);
  });

  testWidgets('기록을 지우면 저장과 같은 것들을 다시 읽는다', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제').last);
    await tester.pumpAndSettle();

    expect(repo.deleted, 1);
    expectEverythingRebuiltOnce();
    await dismissToast(tester);
  });

  testWidgets('삭제를 확인창에서 물리면 아무것도 다시 읽지 않는다', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소').last);
    await tester.pumpAndSettle();

    expect(repo.deleted, 0);
    expect(repo.pastWeekCalls, 1);
    expect(repo.adviceCalls, 1);
    expect(builds.calendar, 1);
    expect(builds.challenge, 1);
  });
}
