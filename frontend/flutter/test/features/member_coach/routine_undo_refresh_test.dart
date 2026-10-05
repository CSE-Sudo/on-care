/// 추천 개인운동 완료를 취소해도 MY 기록 달력·보호권·주간 챌린지를 다시 읽는다.
/// (#2634)
///
/// 완료는 운동 기록 한 건을 만들고, 완료 취소는 그 기록을 지운다. 예전에는 완료만
/// 달력·보호권을 다시 읽고 취소는 빠뜨려, 되돌린 날이 달력에 운동한 날로 남았다.
/// 지금은 둘 다 운동 기록 저장·삭제와 같은 갱신 함수를 부른다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/demo_exercise.dart';

/// 완료 요청을 [gate] 가 풀릴 때까지 붙잡는다. 추천 목록 조회 수를 센다.
class _GatedCoach extends MockMemberCoachRepository {
  _GatedCoach({super.exercise});

  Completer<void>? gate;
  int routineFetches = 0;

  @override
  Future<List<CoachRoutine>> fetchRoutines() {
    routineFetches++;
    return super.fetchRoutines();
  }

  @override
  Future<CoachRoutine> completeRoutine(
    String routineId, {
    required int minutes,
    int? durationSeconds,
    String intensity = 'moderate',
    DateTime? day,
  }) async {
    final Completer<void>? g = gate;
    if (g != null) await g.future;
    return super.completeRoutine(
      routineId,
      minutes: minutes,
      durationSeconds: durationSeconds,
      intensity: intensity,
      day: day,
    );
  }
}

/// 추천 카드를 화면에 둘지 — 요청 중에 줄을 치우는 데 쓴다.
final StateProvider<bool> _showCard = StateProvider<bool>((ref) => true);

void main() {
  late _GatedCoach coach;
  late int calendarBuilds;
  late int shieldBuilds;
  late int challengeBuilds;

  setUp(() {
    // 앱의 데모와 같은 경로 — 루틴 완료 기록이 로컬 목업 API(drift)에 남는다(#2724).
    coach = _GatedCoach(exercise: demoExerciseBackend(emptyDemoDatabase()).api);
    calendarBuilds = 0;
    shieldBuilds = 0;
    challengeBuilds = 0;
  });

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'http://localhost',
              useMockApi: true,
            ),
          ),
          memberCoachRepositoryProvider.overrideWithValue(coach),
          // 다시 만들어졌는지만 센다 — 값은 끝나지 않는 Future 다.
          activityCalendarProvider.overrideWith((ref) {
            calendarBuilds++;
            return Completer<ActivityCalendar>().future;
          }),
          myStreakShieldsProvider.overrideWith((ref) {
            shieldBuilds++;
            return Completer<StreakShields>().future;
          }),
          weeklyChallengeProvider.overrideWith((ref) {
            challengeBuilds++;
            return Completer<WeeklyChallenge>().future;
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
                // MY 탭의 기록 달력·보호권과 운동 탭의 주간 챌린지를 보고 있는
                // 상태다.
                ref
                  ..watch(activityCalendarProvider)
                  ..watch(myStreakShieldsProvider)
                  ..watch(weeklyChallengeProvider)
                  // 운동 탭의 다른 자리도 추천 목록을 보고 있다.
                  ..watch(coachRoutinesProvider);
                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ref.watch(_showCard)
                        ? const AiCoachingCard()
                        : const SizedBox.shrink(),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<CoachRoutine> firstOpenRoutine(WidgetTester tester) async =>
      (await tester.runAsync(
        () => coach.fetchRoutines(),
      ))!.firstWhere((CoachRoutine r) => !r.completed);

  Future<void> complete(WidgetTester tester, CoachRoutine target) async {
    await tester.tap(find.byKey(Key('completeRoutine-${target.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRoutineCompletion')));
    await tester.pumpAndSettle();
  }

  Future<void> undo(WidgetTester tester, CoachRoutine target) async {
    await tester.tap(find.byKey(Key('completeRoutine-${target.id}')));
    await tester.pumpAndSettle();
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(AiCoachingCard)),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(AppButton, l.coachRoutineUndo),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('완료하면 달력·보호권·주간 챌린지를 다시 읽는다', (WidgetTester tester) async {
    await pumpCard(tester);
    expect(calendarBuilds, 1);
    expect(shieldBuilds, 1);
    expect(challengeBuilds, 1);

    await complete(tester, await firstOpenRoutine(tester));

    expect(calendarBuilds, 2);
    expect(shieldBuilds, 2);
    expect(challengeBuilds, 2);
  });

  testWidgets('완료를 취소해도 달력·보호권·주간 챌린지를 다시 읽는다', (WidgetTester tester) async {
    await pumpCard(tester);
    final CoachRoutine target = await firstOpenRoutine(tester);
    await complete(tester, target);
    expect(calendarBuilds, 2);

    await undo(tester, target);

    expect(calendarBuilds, 3, reason: '되돌린 날이 달력에 운동한 날로 남는다');
    expect(shieldBuilds, 3);
    expect(challengeBuilds, 3, reason: '주간 챌린지 진행이 내려가지 않는다');
  });

  testWidgets('완료 취소를 물리면 다시 읽지 않는다', (WidgetTester tester) async {
    await pumpCard(tester);
    final CoachRoutine target = await firstOpenRoutine(tester);
    await complete(tester, target);

    await tester.tap(find.byKey(Key('completeRoutine-${target.id}')));
    await tester.pumpAndSettle();
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(AiCoachingCard)),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.text(l.coachRoutineKeep),
      ),
    );
    await tester.pumpAndSettle();

    expect(calendarBuilds, 2);
    expect(challengeBuilds, 2);
  });

  testWidgets('완료 요청 중에 그 줄이 치워져도 목록·달력·챌린지를 다시 읽는다 (#3096)', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester);
    final CoachRoutine target = await firstOpenRoutine(tester);
    final int fetchesBefore = coach.routineFetches;

    coach.gate = Completer<void>();
    await tester.tap(find.byKey(Key('completeRoutine-${target.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRoutineCompletion')));
    await tester.pump();

    // 요청이 가 있는 동안 카드가 치워진다(목록 갱신·탭 이동).
    ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    ).read(_showCard.notifier).state = false;
    await tester.pumpAndSettle();
    expect(find.byType(AiCoachingCard), findsNothing);

    coach.gate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(coach.routineFetches, greaterThan(fetchesBefore));
    expect(calendarBuilds, 2);
    expect(shieldBuilds, 2);
    expect(challengeBuilds, 2);
  });
}
