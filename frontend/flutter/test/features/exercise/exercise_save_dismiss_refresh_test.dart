/// 저장 중에 시트를 내려도 저장 뒤 갱신이 빠지지 않는다. (#2879)
///
/// 예전에는 시트가 저장 성공 뒤 `mounted` 를 먼저 보고 빠져나가, 저장 중에
/// 시트를 내리면 서버에는 기록이 있는데 주간 그래프·AI 조언·주간 챌린지가 옛
/// 값이었다. 이제 비우기는 시트가 아니라 [ExerciseChangeRunner] 가 한다.
library;

import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_session_draft.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_refresh.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
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

/// 저장 요청을 [gate] 가 풀릴 때까지 붙잡는 대역. 이번 주 조회 수를 센다.
class _GatedRepository implements ExerciseRepository {
  Completer<void>? gate;

  /// 저장이 던질 예외. null 이면 성공한다.
  Object? saveError;
  int weekCalls = 0;
  int adviceCalls = 0;
  int saves = 0;

  Future<void> _wait() async {
    final Completer<void>? g = gate;
    if (g != null) await g.future;
    saves++;
    final Object? error = saveError;
    if (error != null) throw error;
  }

  @override
  Future<ExerciseAdvice> fetchAdvice(String period) async {
    adviceCalls++;
    return const ExerciseAdvice(message: '조언');
  }

  @override
  Future<ExerciseWeek> fetchThisWeek() async {
    weekCalls++;
    return _emptyWeek;
  }

  @override
  Future<List<ExercisePeriodWeek>> fetchPeriod({
    DateTime? from,
    DateTime? to,
  }) async => const <ExercisePeriodWeek>[];

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
  Future<ExerciseSessionsAdded> addSessions(
    List<ExerciseSessionDraft> drafts,
  ) async {
    await _wait();
    final ExerciseSessionDraft d = drafts.last;
    return ExerciseSessionsAdded(
      sessions: <ExerciseSession>[
        ExerciseSession(
          id: 'added',
          dayLabel: _dayLabels[d.date.weekday - 1],
          type: d.type,
          minutes: d.minutes,
          calories: d.calories,
          name: d.name,
          date: d.date,
        ),
      ],
      points: const PointsAward(awarded: 20, balance: 1260),
    );
  }

  @override
  Future<void> deleteSession(String id) async {}

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
    await _wait();
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

/// KST 고정 날짜의 기존 기록.
final ExerciseSession _existing = ExerciseSession(
  id: 'ex-1',
  dayLabel: '월',
  type: ExerciseType.cardio,
  minutes: 30,
  calories: 120,
  name: '걷기',
  date: DateTime(2026, 9, 28),
);

/// 시·분·초 휠의 [column] 번째 칸을 [steps] 칸만큼 굴린다. (#2071)
Future<void> _rollDurationWheel(
  WidgetTester tester,
  int column,
  int steps,
) async {
  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(find.byType(ListWheelScrollView).at(column)),
  );
  await gesture.moveBy(const Offset(0, -kTouchSlop - 1));
  await gesture.moveBy(Offset(0, -40.0 * steps));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('ExerciseChangeRunner', () {
    ProviderContainer container(_GatedRepository repo) {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          exerciseRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('성공하면 이번 주를 다시 읽게 한다', () async {
      final _GatedRepository repo = _GatedRepository();
      final ProviderContainer c = container(repo);
      final ProviderSubscription<AsyncValue<ExerciseWeek>> sub = c.listen(
        exerciseWeekProvider,
        (_, _) {},
      );
      addTearDown(sub.close);
      await c.read(exerciseWeekProvider.future);
      expect(repo.weekCalls, 1);

      await c
          .read(exerciseChangeRunnerProvider)
          .run((ExerciseRepository r) => r.deleteSession('ex-1'));
      await c.read(exerciseWeekProvider.future);

      expect(repo.weekCalls, 2);
    });

    test('결과를 그대로 돌려준다', () async {
      final _GatedRepository repo = _GatedRepository();
      final ProviderContainer c = container(repo);

      final ExerciseSessionsAdded added = await c
          .read(exerciseChangeRunnerProvider)
          .run(
            (ExerciseRepository r) => r.addSessions(<ExerciseSessionDraft>[
              ExerciseSessionDraft(
                type: ExerciseType.cardio,
                minutes: 30,
                calories: 120,
                date: DateTime(2026, 9, 28),
                name: '걷기',
              ),
            ]),
          );

      expect(added.sessions.single.id, 'added');
      expect(added.points?.awarded, 20);
    });

    test('실패하면 비우지 않고 예외를 올린다', () async {
      final _GatedRepository repo = _GatedRepository()
        ..saveError = StateError('offline');
      final ProviderContainer c = container(repo);
      final ProviderSubscription<AsyncValue<ExerciseWeek>> sub = c.listen(
        exerciseWeekProvider,
        (_, _) {},
      );
      addTearDown(sub.close);
      await c.read(exerciseWeekProvider.future);

      await expectLater(
        c
            .read(exerciseChangeRunnerProvider)
            .run((ExerciseRepository r) => r.addSessions(const [])),
        throwsA(isA<StateError>()),
      );
      await c.read(exerciseWeekProvider.future);

      expect(repo.weekCalls, 1);
    });
  });

  group('기록 시트', () {
    late _GatedRepository repo;

    Future<void> pump(WidgetTester tester, {ExerciseSession? session}) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo = _GatedRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            exerciseRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (BuildContext context, WidgetRef ref, Widget? _) {
                  // 운동 탭의 주간 그래프가 이번 주를 보고 있는 상태.
                  ref.watch(exerciseWeekProvider);
                  return TextButton(
                    onPressed: () =>
                        showExerciseAddSheet(context, session: session),
                    child: const Text('열기'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// 저장을 누른 뒤, 요청이 끝나기 전에 시트를 내린다.
    Future<void> saveThenDismiss(WidgetTester tester) async {
      repo.gate = Completer<void>();
      await tester.tap(find.byKey(const Key('exerciseSaveButton')));
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exerciseAddSheet')), findsNothing);
    }

    Future<void> finishSave(WidgetTester tester) async {
      repo.gate!.complete();
      await tester.pump();
      await tester.pump(OnCareMotion.toastEnter);
    }

    Future<void> drainToast(WidgetTester tester) async {
      await tester.pump(OnCareMotion.toastVisible);
      await tester.pumpAndSettle();
    }

    testWidgets('새 기록 저장 중에 시트를 내려도 이번 주를 다시 읽고 알림이 뜬다', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      expect(repo.weekCalls, 1);

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('exerciseNameField')), '걷기');
      await tester.pumpAndSettle();
      await _rollDurationWheel(tester, 1, 30);
      await saveThenDismiss(tester);

      await finishSave(tester);
      expect(repo.saves, 1);
      // 포인트 적립 알림도 시트 없이 뜬다.
      expect(find.text('운동이 기록됐어요'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(repo.weekCalls, 2);
      // 아래 화면은 닫히지 않는다.
      expect(find.text('열기'), findsOneWidget);

      await drainToast(tester);
    });

    testWidgets('수정 중에 시트를 내려도 이번 주를 다시 읽는다', (WidgetTester tester) async {
      await pump(tester, session: _existing);

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await saveThenDismiss(tester);

      await finishSave(tester);
      expect(find.text('운동 기록이 수정됐어요'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(repo.weekCalls, 2);
      expect(find.text('열기'), findsOneWidget);

      await drainToast(tester);
    });

    testWidgets('시트를 내리지 않으면 지금처럼 닫히고 다시 읽는다', (WidgetTester tester) async {
      await pump(tester, session: _existing);

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exerciseSaveButton')));
      await tester.pump();
      await tester.pump(OnCareMotion.toastEnter);

      expect(find.text('운동 기록이 수정됐어요'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exerciseAddSheet')), findsNothing);
      expect(repo.weekCalls, 2);

      await drainToast(tester);
    });
  });
}
