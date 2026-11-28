/// 배정 근력 운동의 완료 기록. (#3364)
///
/// 근력 배정에는 분이 없고 세트·횟수·중량이 있다. 예전 완료 요청은 분과 강도만
/// 보내면서 분이 0 이면 1 로 채워, 근력 배정이 모두 1분짜리 기록이 됐고 회원이
/// 실제로 한 세트와 중량을 남길 수 없었다. 이제 완료 시트가 배정 값을 채워
/// 묻고, 분은 서버가 세트 수에서 환산한다 — 운동 직접 입력과 같은 규칙이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/features/exercise/data/repositories/dio_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/demo_exercise.dart';

const Trainer _assignedTrainer = Trainer(
  id: 'trainer-assigned',
  gymId: 'trainer-gym',
  name: '김트레이너',
);

/// 분 없이 세트·횟수·중량만 정한 근력 배정.
const CoachRoutine _squat = CoachRoutine(
  id: 'r-squat',
  name: '스쿼트',
  minutes: 0,
  type: '근력',
  reason: '',
  source: 'trainer',
  sets: 4,
  reps: 12,
  weight: 40,
);

/// 버티는 근력 배정 — 횟수 대신 초다.
const CoachRoutine _plank = CoachRoutine(
  id: 'r-plank',
  name: '플랭크',
  minutes: 0,
  type: '근력',
  reason: '',
  source: 'trainer',
  sets: 3,
  holdSeconds: 60,
);

const CoachRoutine _walk = CoachRoutine(
  id: 'r-walk',
  name: '걷기',
  minutes: 30,
  type: '유산소',
  reason: '',
  source: 'trainer',
);

/// 운동 여럿짜리 세션 — 행이 세트를 들지 않는다.
const CoachRoutine _session = CoachRoutine(
  id: 'r-session',
  name: '하체 A',
  minutes: 40,
  type: '근력',
  reason: '',
  source: 'trainer',
  sessionName: '하체 A',
  exercises: <CoachRoutineExercise>[
    CoachRoutineExercise(name: '스쿼트', sets: 3, reps: 10, weight: 40),
    CoachRoutineExercise(name: '런지', sets: 3, reps: 12),
  ],
);

/// 루틴 하나를 내주고, 완료 요청에 실린 값을 남긴다.
class _RecordingRepository extends MockMemberCoachRepository {
  _RecordingRepository(this.routine);

  final CoachRoutine routine;

  int calls = 0;
  int? sentMinutes;
  int? sentSets;
  int? sentReps;
  int? sentHoldSeconds;
  double? sentWeight;

  @override
  Future<List<CoachRoutine>> fetchRoutines() async => <CoachRoutine>[routine];

  @override
  Future<CoachRoutine> completeRoutine(
    String routineId, {
    int? minutes,
    int? durationSeconds,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
    String intensity = 'moderate',
    DateTime? day,
  }) async {
    calls += 1;
    sentMinutes = minutes;
    sentSets = sets;
    sentReps = reps;
    sentHoldSeconds = holdSeconds;
    sentWeight = weight;
    return routine.copyWith(completed: true, completedIntensity: intensity);
  }
}

Future<void> _pump(WidgetTester tester, MockMemberCoachRepository repo) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachRepositoryProvider.overrideWithValue(repo),
        myTrainerProvider.overrideWith((ref) async => _assignedTrainer),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AiCoachingCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester, CoachRoutine routine) async {
  await tester.tap(find.byKey(Key('completeRoutine-${routine.id}')));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('confirmRoutineCompletion')));
  await tester.pumpAndSettle();
}

void main() {
  group('완료 시트', () {
    testWidgets('근력 배정은 배정된 세트·횟수·중량을 채워 묻고, 확인만 눌러도 그 값이 간다', (
      WidgetTester tester,
    ) async {
      final _RecordingRepository repo = _RecordingRepository(_squat);
      await _pump(tester, repo);

      await _openSheet(tester, _squat);

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(AppNumberWheel)),
      );
      expect(find.text(l.exExerciseStrengthAmount), findsOneWidget);
      expect(
        find.byKey(const Key('routineCompletionSetsWheel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('routineCompletionRepsWheel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('routineCompletionWeightWheel')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('routineCompletionHoldWheel')), findsNothing);
      // 강도 선택은 그대로 있다.
      expect(
        find.byKey(const Key('routineCompletionIntensity')),
        findsOneWidget,
      );

      await _confirm(tester);

      expect(repo.calls, 1);
      expect(repo.sentSets, 4);
      expect(repo.sentReps, 12);
      expect(repo.sentWeight, 40);
      expect(repo.sentHoldSeconds, isNull);
      // 분은 앱이 지어내지 않는다 — 서버가 세트 수에서 환산한다.
      expect(repo.sentMinutes, isNull);
    });

    testWidgets('버티는 근력 배정은 횟수 자리에 초를 묻고 초를 보낸다', (WidgetTester tester) async {
      final _RecordingRepository repo = _RecordingRepository(_plank);
      await _pump(tester, repo);

      await _openSheet(tester, _plank);

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(AppNumberWheel)),
      );
      expect(find.text(l.exExerciseStrengthAmountHold), findsOneWidget);
      expect(
        find.byKey(const Key('routineCompletionHoldWheel')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('routineCompletionRepsWheel')), findsNothing);

      await _confirm(tester);

      expect(repo.sentSets, 3);
      expect(repo.sentHoldSeconds, 60);
      expect(repo.sentReps, isNull);
      // 중량을 정하지 않은 배정은 맨몸(0kg)이 기본이다.
      expect(repo.sentWeight, 0);
      expect(repo.sentMinutes, isNull);
    });

    testWidgets('유산소 배정의 완료는 지금과 같다 — 강도만 묻고 배정된 분이 간다', (
      WidgetTester tester,
    ) async {
      final _RecordingRepository repo = _RecordingRepository(_walk);
      await _pump(tester, repo);

      await _openSheet(tester, _walk);

      expect(find.byType(AppNumberWheel), findsNothing);
      expect(
        find.byKey(const Key('routineCompletionIntensity')),
        findsOneWidget,
      );

      await _confirm(tester);

      expect(repo.sentMinutes, 30);
      expect(repo.sentSets, isNull);
      expect(repo.sentReps, isNull);
      expect(repo.sentHoldSeconds, isNull);
      expect(repo.sentWeight, isNull);
    });

    testWidgets('운동 여럿짜리 근력 세션은 세트를 묻지 않고 배정된 분이 간다', (
      WidgetTester tester,
    ) async {
      final _RecordingRepository repo = _RecordingRepository(_session);
      await _pump(tester, repo);

      await _openSheet(tester, _session);

      expect(find.byType(AppNumberWheel), findsNothing);

      await _confirm(tester);

      expect(repo.sentMinutes, 40);
      expect(repo.sentSets, isNull);
    });

    testWidgets('취소하면 완료 요청이 가지 않는다', (WidgetTester tester) async {
      final _RecordingRepository repo = _RecordingRepository(_squat);
      await _pump(tester, repo);

      await _openSheet(tester, _squat);
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(AppNumberWheel)),
      );
      await tester.tap(find.text(l.actionCancel));
      await tester.pumpAndSettle();

      expect(repo.calls, 0);
    });

    testWidgets('완료한 근력 줄은 배정 값이 아니라 실제로 한 값을 적는다', (
      WidgetTester tester,
    ) async {
      final CoachRoutine done = _squat.copyWith(
        completed: true,
        completedMinutes: 15,
        completedSets: 5,
        completedReps: 8,
        completedWeight: 45,
      );
      await _pump(tester, _RecordingRepository(done));

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(AiCoachingCard)),
      );
      expect(find.textContaining(l.exSetsCount(5)), findsOneWidget);
      expect(find.textContaining(l.exRepsCount(8)), findsOneWidget);
      expect(find.textContaining(l.exSetsCount(4)), findsNothing);
    });
  });

  group('데모 저장소', () {
    late DemoPointsLedger ledger;
    late DioExerciseRepository exercise;
    late LocalApiInterceptor api;
    late MockMemberCoachRepository coach;

    setUp(() {
      ledger = DemoPointsLedger();
      final backend = demoExerciseBackend(emptyDemoDatabase(), points: ledger);
      exercise = backend.repository;
      api = backend.api;
      coach = MockMemberCoachRepository(exercise: api, points: ledger);
    });

    Future<CoachRoutine> strengthRoutine() async =>
        (await coach.fetchRoutines()).firstWhere(
          (CoachRoutine r) => r.type == '근력' && r.sets != null,
        );

    Future<ExerciseSession?> loggedFor(String routineId) async =>
        (await exercise.fetchThisWeek()).sessions
            .where((ExerciseSession s) => s.assignedRoutineId == routineId)
            .firstOrNull;

    test('분 없이 완료한 근력 배정은 세트 수에서 시간을 얻고 배정 값을 기록한다', () async {
      final CoachRoutine routine = await strengthRoutine();
      final int sets = routine.sets!;

      final CoachRoutine done = await coach.completeRoutine(routine.id);

      // 세트당 3분 — 운동 직접 입력과 같은 환산이다. 1분이 아니다.
      expect(done.completedMinutes, sets * 3);
      expect(done.completedSets, sets);
      expect(done.completedReps, routine.reps);
      expect(done.completedWeight, routine.weight);
      final ExerciseSession? logged = await loggedFor(routine.id);
      expect(logged, isNotNull);
      expect(logged!.minutes, sets * 3);
      expect(logged.sets, sets);
      expect(logged.reps, routine.reps);
      expect(logged.weight, routine.weight);
    });

    test('회원이 고쳐 적은 세트·횟수·중량이 기록에 남는다', () async {
      final CoachRoutine routine = await strengthRoutine();

      final CoachRoutine done = await coach.completeRoutine(
        routine.id,
        sets: 5,
        reps: 8,
        weight: 27.5,
        intensity: 'high',
      );

      expect(done.completedSets, 5);
      expect(done.completedReps, 8);
      expect(done.completedWeight, 27.5);
      expect(done.completedMinutes, 15);
      // 배정 값은 흔들리지 않는다.
      expect(done.sets, routine.sets);
      final ExerciseSession? logged = await loggedFor(routine.id);
      expect(logged!.sets, 5);
      expect(logged.reps, 8);
      expect(logged.weight, 27.5);
      expect(logged.minutes, 15);
    });

    test('초로 버틴 완료는 횟수를 비운다', () async {
      final CoachRoutine routine = await strengthRoutine();

      final CoachRoutine done = await coach.completeRoutine(
        routine.id,
        sets: 3,
        holdSeconds: 45,
      );

      expect(done.completedHoldSeconds, 45);
      expect(done.completedReps, isNull);
      final ExerciseSession? logged = await loggedFor(routine.id);
      expect(logged!.holdSeconds, 45);
      expect(logged.reps, isNull);
    });

    test('근력이 아닌 배정은 세트·중량을 남기지 않는다', () async {
      final CoachRoutine routine = (await coach.fetchRoutines()).firstWhere(
        (CoachRoutine r) => r.type != '근력',
      );

      final CoachRoutine done = await coach.completeRoutine(
        routine.id,
        minutes: routine.minutes,
        sets: 3,
        reps: 10,
        weight: 20,
      );

      expect(done.completedMinutes, routine.minutes);
      expect(done.completedSets, isNull);
      expect(done.completedWeight, isNull);
      final ExerciseSession? logged = await loggedFor(routine.id);
      expect(logged!.sets, isNull);
      expect(logged.weight, isNull);
    });

    test('완료를 되돌리면 기록과 포인트가 함께 되돌아간다', () async {
      final CoachRoutine routine = await strengthRoutine();
      final int before = ledger.balance;

      final CoachRoutine done = await coach.completeRoutine(
        routine.id,
        sets: 5,
        reps: 8,
        weight: 27.5,
      );
      expect(ledger.balance, before + (done.pointsAward?.awarded ?? 0));
      expect(done.pointsAward?.awarded, greaterThan(0));

      final CoachRoutine undone = await coach.uncompleteRoutine(routine.id);

      expect(undone.completed, isFalse);
      expect(undone.completedSets, isNull);
      expect(undone.completedMinutes, isNull);
      expect(await loggedFor(routine.id), isNull);
      expect(ledger.balance, before);
      // 목록도 미완료로 돌아가고 완료 값이 남지 않는다.
      final CoachRoutine listed = (await coach.fetchRoutines()).firstWhere(
        (CoachRoutine r) => r.id == routine.id,
      );
      expect(listed.completed, isFalse);
      expect(listed.completedSets, isNull);
    });

    test('새로고침한 뒤에도 완료한 세트·중량이 기록에서 되살아난다', () async {
      final CoachRoutine routine = await strengthRoutine();
      await coach.completeRoutine(routine.id, sets: 5, reps: 8, weight: 27.5);

      // 새로고침 — 코치 저장소만 새로 만들어진다. 기록은 drift 에 남아 있다.
      final MockMemberCoachRepository refreshed = MockMemberCoachRepository(
        exercise: api,
        points: ledger,
      );
      final CoachRoutine restored = (await refreshed.fetchRoutines())
          .firstWhere((CoachRoutine r) => r.id == routine.id);

      expect(restored.completed, isTrue);
      expect(restored.completedSets, 5);
      expect(restored.completedReps, 8);
      expect(restored.completedWeight, 27.5);
    });
  });

  group('응답 파싱', () {
    test('완료 응답의 세트·횟수·버틴 시간·중량을 읽는다', () {
      final CoachRoutine routine = coachRoutineFromJson(<String, Object?>{
        'id': 'r1',
        'name': '스쿼트',
        'minutes': 0,
        'type': '근력',
        'reason': '',
        'source': 'trainer',
        'sets': 3,
        'reps': 10,
        'weight': 20,
        'completed': true,
        'completed_minutes': 15,
        'completed_sets': 5,
        'completed_reps': 8,
        'completed_hold_seconds': null,
        'completed_weight': 27.5,
      });

      expect(routine.sets, 3);
      expect(routine.completedSets, 5);
      expect(routine.completedReps, 8);
      expect(routine.completedHoldSeconds, isNull);
      expect(routine.completedWeight, 27.5);
    });

    test('완료 값을 모르는 옛 응답은 비어 있다', () {
      final CoachRoutine routine = coachRoutineFromJson(<String, Object?>{
        'id': 'r1',
        'name': '스쿼트',
        'minutes': 0,
        'type': '근력',
        'reason': '',
        'source': 'trainer',
        'sets': 3,
        'completed': true,
      });

      expect(routine.completedSets, isNull);
      expect(routine.completedWeight, isNull);
    });
  });
}
