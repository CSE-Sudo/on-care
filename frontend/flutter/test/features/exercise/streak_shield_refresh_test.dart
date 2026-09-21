/// 운동을 저장하면 내 혜택의 보호권을 다시 읽는다. (#1788)
///
/// 보호권으로 이어 붙인 날에 운동을 기록하면 서버가 그 보호권을 되돌린다. 보유
/// 수가 바뀌었으므로 저장 뒤 보호권 구역을 다시 읽어야 한다.
library;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'fake_streak_shield_repository.dart';

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

/// 저장한 값을 그대로 돌려주는 운동 저장소.
class _SavingRepository implements ExerciseRepository {
  int added = 0;
  int updated = 0;

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
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
  }) async {
    added++;
    return ExerciseSession(
      id: 'added',
      dayLabel: _dayLabels[date.weekday - 1],
      type: type,
      minutes: minutes,
      calories: calories,
      name: name,
      date: date,
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

void main() {
  late _SavingRepository exercise;
  late FakeStreakShieldRepository shields;

  Future<void> pump(WidgetTester tester, {ExerciseSession? session}) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    exercise = _SavingRepository();
    shields = FakeStreakShieldRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          exerciseRepositoryProvider.overrideWithValue(exercise),
          streakShieldRepositoryProvider.overrideWithValue(shields),
          myHealthRepositoryProvider.overrideWithValue(
            const MockMyHealthRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) {
                // 내 혜택이 보호권 구역을 보고 있는 상태 — 무효화되면 다시 읽는다.
                ref.watch(myStreakShieldsProvider);
                return AppButton(
                  label: '열기',
                  onPressed: () =>
                      showExerciseAddSheet(context, session: session),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('exerciseSaveButton')));
    await tester.pumpAndSettle();
    await tester.pump(OnCareMotion.toastVisible);
    await tester.pumpAndSettle();
  }

  testWidgets('운동을 추가하면 보호권을 다시 읽는다', (WidgetTester tester) async {
    await pump(tester);
    expect(shields.fetchCalls, 1);

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exerciseNameField')), '걷기');
    await tester.pumpAndSettle();
    // 시트는 0시 0분 0초로 열린다 — 시간을 적지 않으면 저장이 막힌다(#2071).
    await rollDurationWheel(tester, 1, 30);
    await save(tester);

    expect(exercise.added, 1);
    expect(shields.fetchCalls, 2);
  });

  testWidgets('운동 기록을 고쳐도 보호권을 다시 읽는다', (WidgetTester tester) async {
    await pump(
      tester,
      session: ExerciseSession(
        id: 'ex-1',
        dayLabel: '월',
        type: ExerciseType.cardio,
        minutes: 30,
        calories: 120,
        name: '걷기',
        date: DateTime(2026, 9, 14),
      ),
    );
    expect(shields.fetchCalls, 1);

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(exercise.updated, 1);
    expect(shields.fetchCalls, 2);
  });
}

/// 시·분·초 휠의 [column] 번째 칸을 [steps] 칸만큼 굴린다. (#2071)
///
/// 시트 안이라 부모 스크롤이 휠과 아레나를 다툰다. 슬롭(`kTouchSlop`)을 **넘는**
/// 첫 이동이 승부를 가르고 그 이동 자체는 버려지므로, 그 뒤의 이동이 그대로
/// 칸 수다.
Future<void> rollDurationWheel(
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
