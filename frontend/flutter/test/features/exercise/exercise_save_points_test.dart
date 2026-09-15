/// 운동 저장 알림의 적립 표시와 MY 잔액 다시 읽기. (#1786)
///
/// 직접 추가한 운동이 포인트를 받으면 저장 알림에 ★ +20P 가 붙고, 한도를 넘어
/// 0 이면 저장 알림만 뜬다. 저장·삭제 뒤에는 MY 잔액을 다시 읽는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/domain/repositories/my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
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

/// 저장하면 정해 둔 적립 결과를 싣는 대역.
class _AwardingRepository implements ExerciseRepository {
  _AwardingRepository(this.award);

  final PointsAward award;
  int deleted = 0;

  @override
  Future<String> fetchAdvice(String period) async => '조언';

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _emptyWeek;

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async => _emptyWeek;

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
  Future<ExerciseSession> addSession({
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    String name = '',
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? sets,
    int? reps,
    double? weight,
  }) async => ExerciseSession(
    id: 'added',
    dayLabel: _dayLabels[date.weekday - 1],
    type: type,
    minutes: minutes,
    calories: calories,
    name: name,
    date: date,
    pointsAward: award,
  );

  @override
  Future<void> deleteSession(String id) async => deleted++;

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
    double? weight,
  }) async => ExerciseSession(
    id: id,
    dayLabel: _dayLabels[date.weekday - 1],
    type: type,
    minutes: minutes,
    calories: calories,
    name: name,
    date: date,
  );
}

/// MY 상태를 몇 번 읽었는지 센다.
class _CountingHealthRepository implements MyHealthRepository {
  int calls = 0;

  @override
  Future<MyHealthState> fetchState() {
    calls++;
    return const MockMyHealthRepository().fetchState();
  }
}

final Finder _badge = find.byKey(const ValueKey<String>('appToastReward'));

void main() {
  late _CountingHealthRepository health;

  Future<void> pump(
    WidgetTester tester,
    ExerciseRepository repo, {
    ExerciseSession? session,
  }) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    health = _CountingHealthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          exerciseRepositoryProvider.overrideWithValue(repo),
          myHealthRepositoryProvider.overrideWithValue(health),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) {
                // MY 탭이 잔액을 보고 있는 상태 — 무효화되면 다시 읽는다.
                ref.watch(myHealthStateProvider);
                return Column(
                  children: <Widget>[
                    TextButton(
                      onPressed: () =>
                          showExerciseAddSheet(context, session: session),
                      child: const Text('열기'),
                    ),
                    TextButton(
                      onPressed: () => confirmDeleteExerciseSession(
                        context,
                        ref,
                        session!,
                      ),
                      child: const Text('지우기'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addWorkout(WidgetTester tester) async {
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exerciseNameField')), '걷기');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseSaveButton')));
    await tester.pump();
    await tester.pump(OnCareMotion.toastEnter);
  }

  Future<void> dismissToast(WidgetTester tester) async {
    await tester.pump(OnCareMotion.toastVisible);
    await tester.pumpAndSettle();
  }

  testWidgets('적립을 받으면 저장 알림에 ★ +20P 가 붙고 MY 잔액을 다시 읽는다', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      _AwardingRepository(const PointsAward(awarded: 20, balance: 1260)),
    );
    expect(health.calls, 1);

    await addWorkout(tester);

    expect(find.text('운동이 기록됐어요'), findsOneWidget);
    expect(
      find.descendant(of: _badge, matching: find.text('+20P')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _badge, matching: find.byIcon(Icons.star_rounded)),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(health.calls, 2);

    await dismissToast(tester);
  });

  testWidgets('하루 한도를 넘어 0 이면 표시 없이 저장 알림만 뜬다', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      _AwardingRepository(const PointsAward(awarded: 0, balance: 1300)),
    );

    await addWorkout(tester);

    expect(find.text('운동이 기록됐어요'), findsOneWidget);
    expect(_badge, findsNothing);

    await dismissToast(tester);
  });

  testWidgets('기록을 고치면 적립 표시도 잔액 다시 읽기도 없다', (WidgetTester tester) async {
    final ExerciseSession existing = ExerciseSession(
      id: 'ex-1',
      dayLabel: '월',
      type: ExerciseType.cardio,
      minutes: 30,
      calories: 120,
      name: '걷기',
      date: DateTime(2026, 9, 14),
    );
    await pump(
      tester,
      _AwardingRepository(const PointsAward(awarded: 20, balance: 1260)),
      session: existing,
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exerciseSaveButton')));
    await tester.pump();
    await tester.pump(OnCareMotion.toastEnter);

    expect(find.text('운동 기록이 수정됐어요'), findsOneWidget);
    expect(_badge, findsNothing);
    await tester.pumpAndSettle();
    expect(health.calls, 1);

    await dismissToast(tester);
  });

  testWidgets('기록을 지우면 회수된 잔액을 다시 읽는다', (WidgetTester tester) async {
    final _AwardingRepository repo = _AwardingRepository(
      const PointsAward(awarded: 20, balance: 1260),
    );
    await pump(
      tester,
      repo,
      session: const ExerciseSession(
        id: 'ex-1',
        dayLabel: '월',
        type: ExerciseType.cardio,
        minutes: 30,
        calories: 120,
      ),
    );

    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제').last);
    await tester.pumpAndSettle();

    expect(repo.deleted, 1);
    expect(health.calls, 2);

    await dismissToast(tester);
  });
}
