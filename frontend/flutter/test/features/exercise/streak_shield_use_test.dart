/// 운동 현황의 연속 기록 보호권 — `보호권 쓰기` 버튼, 파란 2열 확인창,
/// `보호권으로 이어짐` 표시. (#1788)
///
/// 오늘을 목요일(2026-08-20)로 고정한다. 월·화·목에 운동했고 어제(수)는 비어
/// 있어, 어제를 보호하면 월~목 4일 연속이 된다. 버튼을 띄울지는 서버가 주는
/// `streak_shield.protectable_date` 로만 정한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';
import 'fake_streak_shield_repository.dart';

const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];
final DateTime _yesterday = DateTime(2026, 8, 19);

const ValueKey<String> _useKey = ValueKey<String>('exercise-streak-shield-use');
const ValueKey<String> _protectedKey = ValueKey<String>(
  'exercise-streak-protected',
);

/// 월·화·목 운동. [protectedWed] 면 수요일을 보호권으로 이어 붙인 주다.
ExerciseWeek _week({bool protectedWed = false, StreakShieldWeekState? shield}) {
  const List<double> daily = <double>[30, 20, 0, 40, 0, 0, 0];
  final List<bool> protectedDays = <bool>[
    false,
    false,
    protectedWed,
    false,
    false,
    false,
    false,
  ];
  return ExerciseWeek(
    sessions: const <ExerciseSession>[],
    dailyMinutes: daily,
    dailyCalories: const <double>[200, 150, 0, 300, 0, 0, 0],
    cardioMinutes: daily,
    strengthMinutes: List<double>.filled(7, 0),
    stretchingMinutes: List<double>.filled(7, 0),
    dayLabels: _dayLabels,
    totalMinutes: 90,
    totalCalories: 650,
    streakDays: longestActiveStreak(daily, protectedDays: protectedDays),
    aiCoachMessage: '',
    protectedDays: protectedDays,
    streakShield: shield,
  );
}

/// 넣어 준 주를 돌려주는 운동 저장소. 몇 번 다시 읽었는지 센다.
class _WeekRepository implements ExerciseRepository {
  _WeekRepository(this.week);

  ExerciseWeek week;
  int fetchCalls = 0;

  @override
  Future<ExerciseWeek> fetchThisWeek() async {
    fetchCalls++;
    return week;
  }

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async => week;

  @override
  Future<String> fetchAdvice(String period) async => '조언';

  @override
  Future<ExerciseCalorieEstimate> previewCalories({
    required ExerciseType type,
    required String name,
    required int minutes,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
  }) async => throw UnimplementedError();

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
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteSession(String id) async => throw UnimplementedError();

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
  }) async => throw UnimplementedError();
}

Widget _app(ExerciseRepository exercise, FakeStreakShieldRepository shields) {
  return ProviderScope(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'https://example.test',
          useMockApi: true,
        ),
      ),
      exerciseRepositoryProvider.overrideWithValue(exercise),
      streakShieldRepositoryProvider.overrideWithValue(shields),
      accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
      memberCoachRepositoryProvider.overrideWithValue(
        MockMemberCoachRepository() as MemberCoachRepository,
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ExercisePage(),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  ExerciseRepository exercise,
  FakeStreakShieldRepository shields,
) async {
  useFixedKstDate();
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(exercise, shields));
  await tester.pumpAndSettle();
}

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AppButtonPair), matching: find.text(text));

void main() {
  testWidgets('어제 기록이 없고 보호권이 있으면 확인창을 거쳐 어제를 이어 붙인다', (tester) async {
    final _WeekRepository exercise = _WeekRepository(
      _week(shield: StreakShieldWeekState(held: 1, protectableDate: _yesterday)),
    );
    final FakeStreakShieldRepository shields = FakeStreakShieldRepository(
      shields: const StreakShields(held: 1, maxHeld: 2, cost: 300),
      onUse: (_) => exercise.week = _week(
        protectedWed: true,
        shield: const StreakShieldWeekState(held: 0),
      ),
    );
    await _pump(tester, exercise, shields);

    expect(find.text('2일 연속 운동 중이에요!'), findsOneWidget);
    expect(find.byKey(_protectedKey), findsNothing);

    await tester.tap(find.byKey(_useKey));
    await tester.pumpAndSettle();

    final AppButtonPair pair = tester.widget<AppButtonPair>(
      find.byType(AppButtonPair),
    );
    expect(pair.cancelLabel, '취소');
    expect(pair.confirmLabel, '보호권 쓰기');
    expect(pair.destructive, isFalse);
    expect(
      find.text('8월 19일에는 운동 기록이 없어요. 보호권 1개를 써서 연속 기록에 이어 붙여요. (보유 1개)'),
      findsOneWidget,
    );

    await tester.tap(_inDialog('보호권 쓰기'));
    await tester.pumpAndSettle();

    expect(shields.used, <DateTime>[_yesterday]);
    expect(exercise.fetchCalls, greaterThanOrEqualTo(2));
    expect(find.text('4일 연속 운동 중이에요!'), findsOneWidget);
    expect(find.byKey(_useKey), findsNothing);
    expect(find.byKey(_protectedKey), findsOneWidget);
    expect(find.text('어제를 연속 기록에 이어 붙였어요'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('확인창에서 취소하면 보호권을 쓰지 않는다', (tester) async {
    final _WeekRepository exercise = _WeekRepository(
      _week(shield: StreakShieldWeekState(held: 2, protectableDate: _yesterday)),
    );
    final FakeStreakShieldRepository shields = FakeStreakShieldRepository();
    await _pump(tester, exercise, shields);

    await tester.tap(find.byKey(_useKey));
    await tester.pumpAndSettle();
    await tester.tap(_inDialog('취소'));
    await tester.pumpAndSettle();

    expect(shields.used, isEmpty);
    expect(find.byType(AppButtonPair), findsNothing);
    expect(find.byKey(_useKey), findsOneWidget);
  });

  testWidgets('서버가 보호할 수 있는 날을 주지 않으면 버튼이 없다', (tester) async {
    // 보호권은 있지만 어제에 운동 기록이 있거나 이미 보호한 경우 — 서버가 null 을 준다.
    final _WeekRepository exercise = _WeekRepository(
      _week(shield: const StreakShieldWeekState(held: 2)),
    );
    await _pump(tester, exercise, FakeStreakShieldRepository());

    expect(find.text('2일 연속 운동 중이에요!'), findsOneWidget);
    expect(find.byKey(_useKey), findsNothing);
  });

  testWidgets('보호권 상태가 없는 응답(지난 주·옛 서버)에도 버튼이 없다', (tester) async {
    await _pump(tester, _WeekRepository(_week()), FakeStreakShieldRepository());

    expect(find.byKey(_useKey), findsNothing);
    expect(find.byKey(_protectedKey), findsNothing);
  });

  testWidgets('보호한 날은 연속 줄과 그날 상세에 보호권으로 이어짐으로 보인다', (tester) async {
    final _WeekRepository exercise = _WeekRepository(
      _week(
        protectedWed: true,
        shield: const StreakShieldWeekState(held: 0),
      ),
    );
    await _pump(tester, exercise, FakeStreakShieldRepository());

    // 오늘 카드 — 월~목 4일 연속에 보호한 수요일이 들었다.
    expect(find.text('4일 연속 운동 중이에요!'), findsOneWidget);
    expect(find.byKey(_protectedKey), findsOneWidget);
    expect(find.text('보호권으로 이어짐'), findsOneWidget);

    // 어제(수)를 고르면 기록이 없는 날 문구와 함께 보호한 날임을 적는다.
    await tester.tap(find.text('19').first);
    await tester.pumpAndSettle();

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExercisePage)),
    );
    expect(find.text(l.otherDateEmpty(l.pageExerciseTitle)), findsOneWidget);
    expect(find.byKey(_protectedKey), findsOneWidget);
  });
}
