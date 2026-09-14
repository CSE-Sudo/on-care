/// 운동 추가 시트 — 통일 스펙 (#1262, #1276, #1310).
///
/// 근력은 세트·횟수·중량으로, 나머지는 시간으로 묻는다. 화면 여러 곳(홈 운동 카드·
/// 운동 현황 링·주간 목표)이 근력을 이미 세트로 읽는데 시트만 분으로 물어,
/// 회원이 적지 않은 수(분 ÷ 3)가 화면에 떴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 저장 요청을 그대로 받아 두는 대역. 무엇이 실려 갔는지만 본다.
class _CapturingRepository implements ExerciseRepository {
  ExerciseType? type;
  int? minutes;
  int? sets;
  int? reps;
  double? weight;
  String? name;
  DateTime? date;
  String? updatedId;

  @override
  Future<String> fetchAdvice(String period) async => '조언';

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _emptyWeek;

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async => _emptyWeek;

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
  }) async {
    _capture(type, minutes, sets, reps, weight, name, date);
    return _echo(
      'new',
      type,
      minutes,
      calories,
      sets,
      reps,
      weight,
      name,
      date,
    );
  }

  /// 시트가 여는 순간 부르지 않는다 — 이름이 찬 뒤에만 온다(#1312). 여기서는
  /// 앱이 아는 유형 평균을 그대로 돌려준다.
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
    double? weight,
  }) async {
    updatedId = id;
    _capture(type, minutes, sets, reps, weight, name, date);
    return _echo(id, type, minutes, calories, sets, reps, weight, name, date);
  }

  void _capture(
    ExerciseType type,
    int minutes,
    int? sets,
    int? reps,
    double? weight,
    String name,
    DateTime date,
  ) {
    this.type = type;
    this.minutes = minutes;
    this.sets = sets;
    this.reps = reps;
    this.weight = weight;
    this.name = name;
    this.date = date;
  }

  ExerciseSession _echo(
    String id,
    ExerciseType type,
    int minutes,
    int calories,
    int? sets,
    int? reps,
    double? weight,
    String name,
    DateTime date,
  ) => ExerciseSession(
    id: id,
    dayLabel: <String>['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1],
    type: type,
    minutes: minutes,
    calories: calories,
    sets: sets,
    reps: reps,
    weight: weight,
    name: name,
    date: date,
  );
}

const ExerciseWeek _emptyWeek = ExerciseWeek(
  sessions: <ExerciseSession>[],
  dailyMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  dailyCalories: <double>[0, 0, 0, 0, 0, 0, 0],
  cardioMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  strengthMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  stretchingMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
  totalMinutes: 0,
  totalCalories: 0,
  streakDays: 0,
  aiCoachMessage: '',
);

/// 시트를 연 화면. [session] 을 주면 수정 모드로 열린다.
Future<void> _openSheet(
  WidgetTester tester,
  _CapturingRepository repo, {
  ExerciseSession? session,
}) async {
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[exerciseRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showExerciseAddSheet(context, session: session),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

/// 이름을 적는다 — 저장에 필요한 유일한 필수 입력이다.
Future<void> _typeName(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('exerciseNameField')), name);
  await tester.pumpAndSettle();
}

/// [key] 스테퍼가 지금 들고 있는 숫자.
String _stepperValue(WidgetTester tester, Key key) => tester
    .widget<TextField>(
      find.descendant(
        of: find.descendant(
          of: find.byKey(key),
          matching: find.byKey(const Key('numberStepperField')),
        ),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('저장'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('근력을 고르면 시간 대신 세트·횟수·중량으로 묻는다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    // 기본값은 유산소 — 분으로 묻는다.
    expect(find.text('운동 시간'), findsOneWidget);
    expect(find.text('세트 수'), findsNothing);
    expect(find.byKey(const Key('exerciseMinutesStepper')), findsOneWidget);

    await tester.tap(find.text('근력'));
    await tester.pumpAndSettle();

    expect(find.text('세트 수'), findsOneWidget);
    expect(find.text('횟수'), findsOneWidget);
    expect(find.text('중량'), findsOneWidget);
    expect(find.text('운동 시간'), findsNothing);
    expect(find.byKey(const Key('exerciseSetsStepper')), findsOneWidget);
    expect(find.byKey(const Key('exerciseRepsStepper')), findsOneWidget);
    expect(find.byKey(const Key('exerciseMinutesStepper')), findsNothing);
    expect(_stepperValue(tester, const Key('exerciseSetsStepper')), '12');
    expect(_stepperValue(tester, const Key('exerciseRepsStepper')), '10');
  });

  testWidgets('근력 기록은 세트·횟수·중량을 실어 저장한다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await tester.tap(find.text('근력'));
    await tester.pumpAndSettle();
    await _typeName(tester, '스쿼트');
    await _save(tester);

    expect(repo.type, ExerciseType.strength);
    expect(repo.name, '스쿼트');
    expect(repo.sets, 12);
    expect(repo.reps, 10);
    expect(repo.weight, 20.0);
    // 서버는 분(>0)도 받는다 — 세트당 벽시계 3분으로 환산한 값이다.
    expect(repo.minutes, 36);
  });

  testWidgets('근력이 아닌 기록에는 세트·횟수·중량이 실리지 않는다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await _typeName(tester, '러닝머신');
    await _save(tester);

    expect(repo.type, ExerciseType.cardio);
    expect(repo.sets, isNull);
    expect(repo.reps, isNull);
    expect(repo.weight, isNull);
    expect(repo.minutes, 30);
  });

  testWidgets('이름을 비워 두면 저장하지 않는다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await _save(tester);

    expect(repo.name, isNull, reason: '저장 요청 자체가 나가지 않아야 한다');
  });

  testWidgets('−/+ 버튼은 값을 한 칸씩 옮긴다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    final Finder plus = find.descendant(
      of: find.byKey(const Key('exerciseMinutesStepper')),
      matching: find.byKey(const Key('numberStepperIncrement')),
    );
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(_stepperValue(tester, const Key('exerciseMinutesStepper')), '31');

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('exerciseMinutesStepper')),
        matching: find.byKey(const Key('numberStepperDecrement')),
      ),
    );
    await tester.pumpAndSettle();
    expect(_stepperValue(tester, const Key('exerciseMinutesStepper')), '30');
  });

  testWidgets('시간은 직접 적어 넣을 수 있다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await _typeName(tester, '러닝머신');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('exerciseMinutesStepper')),
        matching: find.byKey(const Key('numberStepperField')),
      ),
      '47',
    );
    await tester.pumpAndSettle();
    await _save(tester);

    expect(repo.minutes, 47);
  });

  testWidgets('중량은 소수점 한 자리까지 받는다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await tester.tap(find.text('근력'));
    await tester.pumpAndSettle();
    await _typeName(tester, '데드리프트');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('exerciseWeightStepper')),
        matching: find.byKey(const Key('numberStepperField')),
      ),
      '62.5',
    );
    await tester.pumpAndSettle();
    await _save(tester);

    expect(repo.weight, 62.5);
  });

  testWidgets('수정 시트는 저장된 값으로 열린다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(
      tester,
      repo,
      session: ExerciseSession(
        id: 'ex-1',
        dayLabel: '월',
        type: ExerciseType.strength,
        minutes: 45,
        calories: 270,
        sets: 15,
        reps: 8,
        weight: 40.5,
        name: '벤치프레스',
        date: DateTime(2026, 8, 17),
      ),
    );

    expect(find.text('세트 수'), findsOneWidget);
    expect(_stepperValue(tester, const Key('exerciseSetsStepper')), '15');
    expect(_stepperValue(tester, const Key('exerciseRepsStepper')), '8');
    expect(_stepperValue(tester, const Key('exerciseWeightStepper')), '40.5');

    await _save(tester);

    expect(repo.updatedId, 'ex-1');
    expect(repo.sets, 15);
    expect(repo.reps, 8);
    expect(repo.weight, 40.5);
    expect(repo.name, '벤치프레스');
    // 지난 기록을 고쳐도 그 날짜에 그대로 남는다 — 오늘로 끌어오지 않는다.
    expect(repo.date, DateTime(2026, 8, 17));
  });

  testWidgets('세트를 모르는 옛 근력 기록은 분에서 환산해 연다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(
      tester,
      repo,
      session: const ExerciseSession(
        id: 'ex-old',
        dayLabel: '월',
        type: ExerciseType.strength,
        minutes: 30,
        calories: 180,
      ),
    );

    // 30분 ÷ 3분
    expect(_stepperValue(tester, const Key('exerciseSetsStepper')), '10');
  });

  testWidgets('근력이던 기록을 유산소로 고치면 세트·횟수·중량이 지워진다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(
      tester,
      repo,
      session: const ExerciseSession(
        id: 'ex-2',
        dayLabel: '월',
        type: ExerciseType.strength,
        minutes: 36,
        calories: 216,
        sets: 12,
        reps: 10,
        weight: 30,
        name: '스쿼트',
      ),
    );

    await tester.tap(find.text('유산소'));
    await tester.pumpAndSettle();
    await _save(tester);

    expect(repo.type, ExerciseType.cardio);
    expect(repo.sets, isNull);
    expect(repo.reps, isNull);
    expect(repo.weight, isNull);
  });
}
