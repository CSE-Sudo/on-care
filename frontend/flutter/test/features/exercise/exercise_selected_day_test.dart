import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

/// 요일마다 [minutes] 분씩 채운 주. 0 을 주면 기록이 없는 주가 된다.
ExerciseWeek _week(double minutes) {
  final List<double> daily = List<double>.filled(7, minutes);
  return ExerciseWeek(
    sessions: <ExerciseSession>[
      if (minutes > 0)
        for (final String d in _dayLabels)
          ExerciseSession(
            id: 'x-$d',
            dayLabel: d,
            type: ExerciseType.cardio,
            minutes: minutes.round(),
            calories: minutes.round() * 7,
          ),
    ],
    dailyMinutes: daily,
    dailyCalories: List<double>.filled(7, minutes * 7),
    cardioMinutes: daily,
    strengthMinutes: List<double>.filled(7, 0),
    stretchingMinutes: List<double>.filled(7, 0),
    dayLabels: _dayLabels,
    totalMinutes: (minutes * 7).round(),
    totalCalories: (minutes * 49).round(),
    streakDays: minutes > 0 ? 7 : 0,
    aiCoachMessage: '',
  );
}

/// 모든 주가 같은 값인 저장소. 어느 날짜를 골라도 기록이 있다.
class _FixedWeekRepository implements ExerciseRepository {
  _FixedWeekRepository(this.minutes);
  final double minutes;

  @override
  Future<String> fetchAdvice(String period) async => '조언';

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _week(minutes);

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async => _week(minutes);

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

/// 이번 주와 지난 주가 서로 다른 값인 저장소. 지난 주 조회 경로(`fetchWeek`)를
/// 실제로 지났는지 수치로 구분하기 위한 대역.
class _TwoWeekRepository extends _FixedWeekRepository {
  _TwoWeekRepository({
    required double thisWeek,
    required this.pastWeekMinutes,
    this.failPastWeek = false,
  }) : super(thisWeek);

  final double pastWeekMinutes;
  final bool failPastWeek;

  /// 지난 주를 실제로 받아 갔는지. 이번 주 값이 재활용되면 false 로 남는다.
  bool fetchedPastWeek = false;

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async {
    fetchedPastWeek = true;
    if (failPastWeek) throw StateError('past week lookup failed');
    return _week(pastWeekMinutes);
  }
}

Widget _app(ExerciseRepository repo) {
  return ProviderScope(
    overrides: <Override>[
      // 데모 설정 — _PtLogCard 등 하위 카드가 실서버 provider 를 타지 않는다.
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'https://example.test',
          useMockApi: true,
        ),
      ),
      exerciseRepositoryProvider.overrideWithValue(repo),
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

/// 오늘이 아니면서 **이번 주 안에** 있고 주간 스트립(오늘 ±3일)에 보이는 날짜.
DateTime _otherDayThisWeek() {
  final DateTime now = nowKst();
  final DateTime today = DateTime(now.year, now.month, now.day);
  // 월요일이면 어제가 지난 주로 넘어가므로 내일을 고른다. 그 밖에는 어제.
  return today.weekday == DateTime.monday
      ? today.add(const Duration(days: 1))
      : today.subtract(const Duration(days: 1));
}

void main() {
  testWidgets('오늘이 아닌 날에 기록이 있으면 빈 문구 대신 그날 요약을 그린다 (#671)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(_FixedWeekRepository(40)));
    await tester.pumpAndSettle();

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExercisePage)),
    );
    final DateTime target = _otherDayThisWeek();

    await tester.tap(find.text('${target.day}').first);
    await tester.pumpAndSettle();

    expect(
      find.text(l.otherDateEmpty(l.pageExerciseTitle)),
      findsNothing,
      reason: '기록이 있는 날인데 빈 문구가 나오면 안 된다',
    );
    expect(
      find.text('${target.month}월 ${target.day}일 ${l.pageExerciseTitle}'),
      findsOneWidget,
    );
    // 유형별 값은 `운동 현황 > 오늘` 과 같은 카드로 그린다(#682). 소모
    // 칼로리는 도넛 안에서 말하므로(#1127) 카드 자체로 가른다.
    expect(find.byType(ExerciseDayLoadCard), findsWidgets);
    expect(find.text(l.exTypeCardio), findsWidgets);
    expect(find.text(l.unitMinutesValue(40)), findsWidgets);
  });

  testWidgets('정말 기록이 없는 날에는 빈 문구가 그대로 나온다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(_FixedWeekRepository(0)));
    await tester.pumpAndSettle();

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExercisePage)),
    );
    final DateTime target = _otherDayThisWeek();

    await tester.tap(find.text('${target.day}').first);
    await tester.pumpAndSettle();

    expect(find.text(l.otherDateEmpty(l.pageExerciseTitle)), findsOneWidget);
  });

  testWidgets('지난 주로 넘겨 고른 날은 그 주를 따로 받아 그린다 (#671)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 이번 주 40분 / 지난 주 12분 — 이번 주 값이 재사용되면 12분이 안 나온다.
    final _TwoWeekRepository repo = _TwoWeekRepository(
      thisWeek: 40,
      pastWeekMinutes: 12,
    );
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExercisePage)),
    );

    // 주간 스트립의 왼쪽 화살표로 한 주 뒤로 간다.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded).first);
    await tester.pumpAndSettle();

    // 지난 주로 옮긴 스트립의 가운데 날짜(= 오늘 -7일)를 고른다.
    final DateTime now = nowKst();
    final DateTime target = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 7));
    await tester.tap(find.text('${target.day}').first);
    await tester.pumpAndSettle();

    expect(
      repo.fetchedPastWeek,
      isTrue,
      reason: '지난 주는 fetchWeek 으로 따로 받아야 한다',
    );
    expect(
      find.text('${target.month}월 ${target.day}일 ${l.pageExerciseTitle}'),
      findsOneWidget,
    );
    expect(find.text('12${l.unitMinutes}'), findsWidgets);
    expect(find.text(l.otherDateEmpty(l.pageExerciseTitle)), findsNothing);
  });

  testWidgets('지난 주 조회가 실패하면 빈 문구로 내려앉는다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final _TwoWeekRepository repo = _TwoWeekRepository(
      thisWeek: 40,
      pastWeekMinutes: 12,
      failPastWeek: true,
    );
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExercisePage)),
    );

    await tester.tap(find.byIcon(Icons.chevron_left_rounded).first);
    await tester.pumpAndSettle();
    final DateTime now = nowKst();
    final DateTime target = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 7));
    await tester.tap(find.text('${target.day}').first);
    await tester.pumpAndSettle();

    expect(find.text(l.otherDateEmpty(l.pageExerciseTitle)), findsOneWidget);
  });
}
