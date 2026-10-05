/// 추천 운동 완료·되돌리기가 실패하면 토스트와 함께 처리된 오류로 보고한다(#3051).
///
/// 예전에는 `debugPrint` 로 개발 콘솔에만 남아, 같은 실패가 반복돼도 운영 쪽에서
/// 알 수 없었다. 이미 지워진 배정(404)처럼 화면이 정상 흐름으로 처리하는 실패는
/// 보고하지 않는다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/observability/error_reporter.dart';
import 'package:oncare/core/observability/handled_error.dart';
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

class _FakeReporter extends ErrorReporter {
  final List<(Object, String, Map<String, String>)> reports =
      <(Object, String, Map<String, String>)>[];

  @override
  bool get isEnabled => true;

  @override
  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    Map<String, String> tags = const <String, String>{},
  }) async {
    reports.add((error, source, tags));
  }
}

/// 완료는 [completeFailure], 되돌리기는 [undoFailure] 로 실패시키는 데모 저장소.
class _FailingCoachRepository extends MockMemberCoachRepository {
  _FailingCoachRepository({required super.exercise, this.completeFailure});

  Object? completeFailure;
  Object? undoFailure;

  @override
  Future<CoachRoutine> completeRoutine(
    String routineId, {
    required int minutes,
    int? durationSeconds,
    String intensity = 'moderate',
    DateTime? day,
  }) async {
    final Object? failure = completeFailure;
    if (failure != null) throw failure;
    return super.completeRoutine(
      routineId,
      minutes: minutes,
      durationSeconds: durationSeconds,
      intensity: intensity,
      day: day,
    );
  }

  @override
  Future<CoachRoutine> uncompleteRoutine(
    String routineId, {
    DateTime? day,
  }) async {
    final Object? failure = undoFailure;
    if (failure != null) throw failure;
    return super.uncompleteRoutine(routineId, day: day);
  }
}

/// 데모 저장소 그대로 — 목록을 다시 읽은 횟수만 센다. 담당이 끊기면 배정
/// 루틴이 목록에서 사라진다(`linked`).
class _CountingCoachRepository extends MockMemberCoachRepository {
  _CountingCoachRepository({required super.exercise, required super.linked});

  int fetches = 0;

  @override
  Future<List<CoachRoutine>> fetchRoutines() {
    fetches += 1;
    return super.fetchRoutines();
  }
}

void main() {
  late _FakeReporter reporter;

  setUp(() => reporter = _FakeReporter());

  Future<void> pumpCard(
    WidgetTester tester,
    MockMemberCoachRepository coach,
  ) async {
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
          errorReporterProvider.overrideWithValue(reporter),
          memberCoachRepositoryProvider.overrideWithValue(coach),
          activityCalendarProvider.overrideWith(
            (ref) => Completer<ActivityCalendar>().future,
          ),
          myStreakShieldsProvider.overrideWith(
            (ref) => Completer<StreakShields>().future,
          ),
          weeklyChallengeProvider.overrideWith(
            (ref) => Completer<WeeklyChallenge>().future,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: AiCoachingCard(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<CoachRoutine> firstOpenRoutine(
    WidgetTester tester,
    MockMemberCoachRepository coach,
  ) async => (await tester.runAsync(
    () => coach.fetchRoutines(),
  ))!.firstWhere((CoachRoutine r) => !r.completed);

  Future<void> complete(WidgetTester tester, CoachRoutine target) async {
    await tester.tap(find.byKey(Key('completeRoutine-${target.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRoutineCompletion')));
    await tester.pumpAndSettle();
  }

  /// 실패 토스트가 머무는 시간을 흘려 남은 타이머를 비운다.
  Future<void> drainToasts(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(AiCoachingCard)));

  testWidgets('완료가 예상 밖 오류로 실패하면 토스트와 함께 한 번 보고한다', (
    WidgetTester tester,
  ) async {
    final _FailingCoachRepository coach = _FailingCoachRepository(
      exercise: demoExerciseBackend(emptyDemoDatabase()).api,
      completeFailure: StateError('server shape changed'),
    );
    await pumpCard(tester, coach);

    await complete(tester, await firstOpenRoutine(tester, coach));

    expect(find.text(l10n(tester).coachRoutineLogFailed), findsOneWidget);
    expect(reporter.reports, hasLength(1));
    expect(reporter.reports.single.$2, HandledErrorReporter.source);
    expect(
      reporter.reports.single.$3['handled_context'],
      'coach.completeRoutine',
    );
    await drainToasts(tester);
  });

  testWidgets('이미 지워진 배정(404)은 안내만 하고 보고하지 않는다', (WidgetTester tester) async {
    final _FailingCoachRepository coach = _FailingCoachRepository(
      exercise: demoExerciseBackend(emptyDemoDatabase()).api,
      completeFailure: const NotFoundError(),
    );
    await pumpCard(tester, coach);

    await complete(tester, await firstOpenRoutine(tester, coach));

    expect(find.text(l10n(tester).coachRoutineGone), findsOneWidget);
    expect(reporter.reports, isEmpty);
    await drainToasts(tester);
  });

  // 데모 저장소가 사라진 루틴을 실서버처럼 404([NotFoundError])로 알린다 —
  // 화면은 실서버 경로와 같은 안내를 하고 목록을 다시 읽는다(#3099).
  testWidgets('데모에서 사라진 루틴을 완료하면 실서버와 같은 안내 뒤 목록을 다시 읽는다', (
    WidgetTester tester,
  ) async {
    bool linked = true;
    final _CountingCoachRepository coach = _CountingCoachRepository(
      exercise: demoExerciseBackend(emptyDemoDatabase()).api,
      linked: () => linked,
    );
    await pumpCard(tester, coach);
    final CoachRoutine target = await firstOpenRoutine(tester, coach);
    final int before = coach.fetches;

    // 화면에 떠 있는 동안 담당이 끊겨 배정 루틴이 사라졌다.
    linked = false;
    await complete(tester, target);

    expect(find.text(l10n(tester).coachRoutineGone), findsOneWidget);
    expect(find.text(l10n(tester).coachRoutineLogFailed), findsNothing);
    expect(coach.fetches, greaterThan(before), reason: '목록을 다시 읽어야 한다');
    expect(reporter.reports, isEmpty);
    await drainToasts(tester);
  });

  testWidgets('연결이 끊긴 실패는 안내만 하고 보고하지 않는다', (WidgetTester tester) async {
    final _FailingCoachRepository coach = _FailingCoachRepository(
      exercise: demoExerciseBackend(emptyDemoDatabase()).api,
      completeFailure: const NetworkError(),
    );
    await pumpCard(tester, coach);

    await complete(tester, await firstOpenRoutine(tester, coach));

    expect(find.text(l10n(tester).coachRoutineNetworkError), findsOneWidget);
    expect(reporter.reports, isEmpty);
    await drainToasts(tester);
  });

  testWidgets('되돌리기가 실패하면 토스트와 함께 보고한다', (WidgetTester tester) async {
    final _FailingCoachRepository coach = _FailingCoachRepository(
      exercise: demoExerciseBackend(emptyDemoDatabase()).api,
    );
    await pumpCard(tester, coach);
    final CoachRoutine target = await firstOpenRoutine(tester, coach);
    await complete(tester, target);
    expect(reporter.reports, isEmpty);

    coach.undoFailure = StateError('undo broke');
    await tester.tap(find.byKey(Key('completeRoutine-${target.id}')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(AppButton, l10n(tester).coachRoutineUndo),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n(tester).coachRoutineUndoFailed), findsOneWidget);
    expect(reporter.reports, hasLength(1));
    expect(
      reporter.reports.single.$3['handled_context'],
      'coach.uncompleteRoutine',
    );
    await drainToasts(tester);
  });
}
