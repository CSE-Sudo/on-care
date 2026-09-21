/// 운동 추가 시트 — 통일 스펙 (#1262, #1276, #1310).
///
/// 근력은 세트·횟수·중량으로, 나머지는 시간으로 묻는다. 화면 여러 곳(홈 운동 카드·
/// 운동 현황 링·주간 목표)이 근력을 이미 세트로 읽는데 시트만 분으로 물어,
/// 회원이 적지 않은 수(분 ÷ 3)가 화면에 떴다.
library;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/demo/exercise_catalog_demo.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_limits.dart';
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
  int? holdSeconds;
  int? durationSeconds;
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
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
  }) async {
    _capture(
      type,
      minutes,
      sets,
      reps,
      holdSeconds,
      durationSeconds,
      weight,
      name,
      date,
    );
    return _echo(
      'new',
      type,
      minutes,
      calories,
      sets,
      reps,
      holdSeconds,
      durationSeconds,
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
    // 실 서버는 종목 참조표의 `isometric` 표시를 내려 준다. 대역도 같은 표를
    // 보는 데모 종목표로 답해, 폼의 `회/초` 기본값이 같은 근거를 탄다(#1969).
    isometric: isIsometricExerciseName(name),
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
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
  }) async {
    updatedId = id;
    _capture(
      type,
      minutes,
      sets,
      reps,
      holdSeconds,
      durationSeconds,
      weight,
      name,
      date,
    );
    return _echo(
      id,
      type,
      minutes,
      calories,
      sets,
      reps,
      holdSeconds,
      durationSeconds,
      weight,
      name,
      date,
    );
  }

  void _capture(
    ExerciseType type,
    int minutes,
    int? sets,
    int? reps,
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
    String name,
    DateTime date,
  ) {
    this.type = type;
    this.minutes = minutes;
    this.sets = sets;
    this.reps = reps;
    this.holdSeconds = holdSeconds;
    this.durationSeconds = durationSeconds;
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
    int? holdSeconds,
    int? durationSeconds,
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
    holdSeconds: holdSeconds,
    durationSeconds: durationSeconds,
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
///
/// 디바운스(400ms)를 넘겨 이름 해석까지 돌린다. 그 응답이 `회/초` 기본값을
/// 정하므로(#1969), 넘기지 않으면 칸이 아직 바뀌지 않은 상태를 본다.
Future<void> _typeName(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('exerciseNameField')), name);
  await tester.pump(const Duration(milliseconds: 500));
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

/// 시·분·초 휠의 [column] 번째 칸을 [steps] 칸만큼 굴린다(양수가 아래로).
///
/// `FixedExtentScrollPhysics` 가 칸에 맞춰 세우므로, 칸 높이만큼 끌면 한 칸이다.
Future<void> _rollWheel(
  WidgetTester tester,
  int column,
  int steps, {
  double itemExtent = 40,
}) async {
  // 시트 안이라 부모 스크롤이 휠과 아레나를 다툰다. 슬롭(`kTouchSlop`, 18)을
  // **넘는** 첫 이동이 승부를 가르고 그 이동 자체는 버려지므로, 그 뒤의
  // 이동이 그대로 칸 수다. `tester.drag` 는 슬롭을 끈 거리에서 빼 한 칸이
  // 모자라게 서고, `touchSlopY: 0` 으로는 아레나가 갈리지 않아 휠이 멈춰 있다.
  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(find.byType(ListWheelScrollView).at(column)),
  );
  await gesture.moveBy(const Offset(0, -kTouchSlop - 1));
  await gesture.moveBy(Offset(0, -itemExtent * steps));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('저장'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('근력을 고르면 시간 대신 세트·횟수·중량으로 묻는다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    // 기본값은 유산소 — 시·분·초 휠로 묻는다(#2071).
    expect(find.text('운동 시간'), findsOneWidget);
    expect(find.text('세트 수'), findsNothing);
    expect(find.byKey(const Key('exerciseDurationWheel')), findsOneWidget);

    await tester.tap(find.text('근력'));
    await tester.pumpAndSettle();

    expect(find.text('세트 수'), findsOneWidget);
    expect(find.text('횟수'), findsOneWidget);
    expect(find.text('중량'), findsOneWidget);
    expect(find.text('운동 시간'), findsNothing);
    expect(find.byKey(const Key('exerciseSetsStepper')), findsOneWidget);
    expect(find.byKey(const Key('exerciseRepsStepper')), findsOneWidget);
    expect(find.byKey(const Key('exerciseDurationWheel')), findsNothing);
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

  testWidgets('버티는 운동을 적으면 횟수 칸이 버티는 시간으로 바뀐다 (#1969)', (
    WidgetTester tester,
  ) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await tester.tap(find.text('근력'));
    await tester.pumpAndSettle();
    // 이름을 적기 전에는 회로 묻는다 — 대부분의 근력이 그렇다.
    expect(find.byKey(const Key('exerciseRepsStepper')), findsOneWidget);
    expect(find.byKey(const Key('exerciseHoldStepper')), findsNothing);

    await _typeName(tester, '플랭크');

    // 종목표가 버티는 운동이라고 하면 같은 자리를 초가 대신한다 — 칸이
    // 늘어나지 않는다.
    expect(find.byKey(const Key('exerciseHoldStepper')), findsOneWidget);
    expect(find.byKey(const Key('exerciseRepsStepper')), findsNothing);
    expect(find.text('버티는 시간'), findsOneWidget);
    expect(find.text('횟수'), findsNothing);
  });

  testWidgets('버티는 운동은 초를 싣고 횟수를 비운다 (#1969)', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await tester.tap(find.text('근력'));
    await tester.pumpAndSettle();
    await _typeName(tester, '플랭크');
    await _save(tester);

    expect(repo.holdSeconds, 60);
    // 한 세트를 두 단위로 적지 않는다. 45초를 `reps: 3` 으로 적던 것이
    // 이 칸을 만든 이유다.
    expect(repo.reps, isNull);
    expect(repo.sets, 12);
  });

  testWidgets('회/초는 회원이 직접 고를 수 있고 그 선택이 이름을 이긴다 (#1969)', (
    WidgetTester tester,
  ) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await tester.tap(find.text('근력'));
    await tester.pumpAndSettle();
    await _typeName(tester, '플랭크');
    expect(find.byKey(const Key('exerciseHoldStepper')), findsOneWidget);

    // 종목표는 기본값일 뿐이다 — 고르는 것은 적는 사람이다.
    await tester.tap(find.byKey(const Key('exerciseMeasureReps')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exerciseRepsStepper')), findsOneWidget);

    // 고른 뒤에는 이름을 다시 적어도 덮지 않는다.
    await _typeName(tester, '사이드 플랭크');
    expect(find.byKey(const Key('exerciseRepsStepper')), findsOneWidget);

    await _save(tester);
    expect(repo.reps, 10);
    expect(repo.holdSeconds, isNull);
  });

  testWidgets('초로 적힌 기록을 열면 초 칸으로 열린다 (#1969)', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(
      tester,
      repo,
      session: ExerciseSession(
        id: 'ex-hold',
        dayLabel: '월',
        type: ExerciseType.strength,
        minutes: 9,
        calories: 54,
        name: '플랭크',
        sets: 3,
        holdSeconds: 45,
        weight: 0,
        date: DateTime(2026, 3, 2),
      ),
    );

    expect(find.byKey(const Key('exerciseHoldStepper')), findsOneWidget);
    expect(
      _stepperValue(tester, const Key('exerciseHoldStepper')),
      '45',
      reason: '적어 둔 초가 그대로 열려야 한다',
    );
  });

  testWidgets('근력이 아닌 기록에는 세트·횟수·중량이 실리지 않는다', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await _typeName(tester, '러닝머신');
    await _rollWheel(tester, 1, 30);
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

  testWidgets('취소는 저장하지 않고 시트를 닫는다 (#1782)', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);
    await _typeName(tester, '아침 러닝');

    await tester.tap(find.byKey(const Key('exerciseCancelButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exerciseAddSheet')), findsNothing);
    expect(repo.name, isNull, reason: '취소는 저장 요청을 보내지 않는다');
  });

  testWidgets('휠을 굴린 시간이 그대로 실려 간다 (#2071)', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await _typeName(tester, '러닝머신');
    // 0 에서 시작해 47칸 굴린다.
    await _rollWheel(tester, 1, 47);
    await _save(tester);

    expect(repo.durationSeconds, 47 * 60);
    // 서버는 여전히 분도 받는다 — 초에서 환산한 값이다.
    expect(repo.minutes, 47);
  });

  testWidgets('분으로는 적을 수 없던 초를 적는다 (#2071)', (WidgetTester tester) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await _typeName(tester, '계단 오르기');
    // 45초만 적는다 — 분 스테퍼로는 적을 수 없던 값이다.
    await _rollWheel(tester, 2, 45);
    await _save(tester);

    expect(repo.durationSeconds, 45);
    // 45초가 반올림으로 0분이 되어 거절되지 않는다 — 서버와 같은 환산이다.
    expect(repo.minutes, 1);
  });

  testWidgets('시 칸을 굴리면 한 시간이 넘는 운동도 적는다 (#2071)', (
    WidgetTester tester,
  ) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await _typeName(tester, '등산');
    // 예전에는 `90분` 처럼 분으로 환산해 올려야 했다.
    await _rollWheel(tester, 0, 1);
    await _rollWheel(tester, 1, 35);
    await _save(tester);

    expect(repo.durationSeconds, 3600 + 35 * 60);
    expect(repo.minutes, 95);
  });

  testWidgets('시트는 0시 0분 0초로 열리고 그대로는 저장되지 않는다 (#2071)', (
    WidgetTester tester,
  ) async {
    // 미리 채워 둔 시간은 회원이 한 번도 건드리지 않고 저장할 수 있는 값이다 —
    // 그러면 아무도 적은 적 없는 시간이 기록에 남는다. 0 에서 시작하면 저장이
    // 막히므로, 기록에 남는 시간은 반드시 적은 값이다.
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await _typeName(tester, '러닝머신');
    await _save(tester);

    expect(repo.name, isNull, reason: '저장 요청 자체가 나가지 않아야 한다');
  });

  testWidgets('수정 시트는 저장된 초로 휠이 맞춰져 열린다 (#2071)', (
    WidgetTester tester,
  ) async {
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(
      tester,
      repo,
      session: ExerciseSession(
        id: 'ex-secs',
        dayLabel: '월',
        type: ExerciseType.cardio,
        minutes: 2,
        durationSeconds: 95,
        calories: 18,
        name: '계단 오르기',
        date: DateTime(2026, 3, 2),
      ),
    );

    // 휠을 건드리지 않고 그대로 저장하면 적어 둔 초가 그대로 나간다.
    await _save(tester);
    expect(repo.durationSeconds, 95);
  });

  testWidgets('트레이너가 배정할 수 있는 세트·중량을 회원도 직접 적을 수 있다', (
    WidgetTester tester,
  ) async {
    // 예전에는 세트가 회원 앱 40·서버 100·트레이너 99 로 셋이 다 달랐고 중량은
    // 회원 앱만 500kg 이었다. 트레이너가 짠 프로그램이 화면에 보여도 회원이 그
    // 수를 옮겨 적을 수 없었다(#1904).
    final _CapturingRepository repo = _CapturingRepository();
    await _openSheet(tester, repo);

    await tester.tap(find.text('근력'));
    await tester.pumpAndSettle();
    await _typeName(tester, '레그프레스');

    for (final (Key key, num value) in <(Key, num)>[
      (const Key('exerciseSetsStepper'), kMaxExerciseSets),
      (const Key('exerciseRepsStepper'), kMaxExerciseReps),
      (const Key('exerciseWeightStepper'), kMaxExerciseWeightKg),
    ]) {
      await tester.enterText(
        find.descendant(
          of: find.byKey(key),
          matching: find.byKey(const Key('numberStepperField')),
        ),
        '${value.toInt()}',
      );
      await tester.pumpAndSettle();
      // 상한 안의 값이므로 잘리지 않는다 — 예전에는 40·500 으로 깎였다.
      expect(
        _stepperValue(tester, key),
        '${value.toInt()}',
        reason: '$key 가 상한 안의 값을 깎았다',
      );
    }

    await _save(tester);

    expect(repo.sets, kMaxExerciseSets);
    expect(repo.reps, kMaxExerciseReps);
    expect(repo.weight, kMaxExerciseWeightKg);
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
