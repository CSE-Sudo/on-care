/// 운동 현황의 주간 챌린지 진행 줄. (#1789)
///
/// 이번 주 챌린지에 참가했을 때만 `주간 챌린지  2 / 3회` 가 선다. 참가 전이거나
/// 챌린지를 못 읽었으면 운동 현황은 예전 그대로다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/domain/repositories/challenge_repository.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../benefits/fake_challenge_repository.dart';

const ExerciseWeek _week = ExerciseWeek(
  sessions: <ExerciseSession>[],
  dailyMinutes: <double>[30, 20, 0, 0, 0, 0, 0],
  dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
  totalMinutes: 50,
  totalCalories: 400,
  streakDays: 2,
  aiCoachMessage: '',
);

class _FailingChallengeRepository extends FakeChallengeRepository {
  @override
  Future<WeeklyChallenge> fetchWeekly() => Future<WeeklyChallenge>.error(
    StateError('network'),
  );
}

void main() {
  Future<void> pump(WidgetTester tester, ChallengeRepository repo) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          exerciseActivityPeriodProvider.overrideWith((ref) => 0),
          exerciseWeekProvider.overrideWith((ref) async => _week),
          challengeRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ExerciseActivityStatus(week: _week),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final Finder line = find.byKey(const Key('exerciseChallengeProgress'));

  testWidgets('참가했으면 운동 현황 아래 진행을 보여 준다', (tester) async {
    await pump(
      tester,
      FakeChallengeRepository(
        weekly: weeklyWith(
          progress: 2,
          joinable: false,
          blockReason: ChallengeBlockReason.alreadyJoined,
          challenge: challengeOf(progress: 2),
        ),
      ),
    );

    expect(line, findsOneWidget);
    expect(
      find.descendant(of: line, matching: find.text('주간 챌린지')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: line, matching: find.text('2 / 3회')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(line).dy,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('exercise-section-header')),
            )
            .dy,
      ),
    );
  });

  testWidgets('참가 전에는 진행 줄이 없다', (tester) async {
    await pump(tester, FakeChallengeRepository());

    expect(line, findsNothing);
  });

  testWidgets('챌린지를 못 읽어도 운동 현황은 그대로다', (tester) async {
    await pump(tester, _FailingChallengeRepository());

    expect(line, findsNothing);
    expect(find.text('운동 현황'), findsOneWidget);
  });
}
