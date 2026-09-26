import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';
import '../../helpers/fixed_clock.dart';

/// 지난 날짜의 PT 기록이 **제 제목 아래** 선다. (#1884)
///
/// 이 목록에는 제목이 없어, 바로 위 `직접 기록한 운동` 이 비었을 때 띄우는
/// `직접 추가한 운동이 없어요` 아래로 카드가 그대로 흘러나왔다 — 없다고 해 놓고
/// 보여 주는 꼴이라 저 카드가 무엇인지 알 수 없었다. 오늘 화면이 PT 일지를
/// `오늘 완료한 PT` 아래 두는 것과 같은 짜임 — 아이콘 달린 제목을 인 흰 카드 —
/// 으로 갈라 세운다.
///
/// PT 와 배정 개인운동은 **따로** 센다. 한 카드에 몰면 수업을 하지 않은 날의
/// 개인운동까지 `완료한 PT` 라고 적히는데, 그 카드에는 수업 시각도 피드백도
/// 없어 제목만 혼자 PT 라고 우긴다.
const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

String _labelOf(DateTime date) => _dayLabels[date.weekday - 1];

/// 어느 날을 골라도 그날의 요약이 그려지도록 한 주를 고르게 채운다 — 분이 0 인
/// 날은 `기록 없음` 화면으로 빠져 이 목록 자체가 없다.
ExerciseWeek _week(List<ExerciseSession> sessions) {
  final List<double> daily = List<double>.filled(7, 40);
  return ExerciseWeek(
    sessions: sessions,
    dailyMinutes: daily,
    dailyCalories: List<double>.filled(7, 280),
    cardioMinutes: daily,
    strengthMinutes: List<double>.filled(7, 0),
    stretchingMinutes: List<double>.filled(7, 0),
    dayLabels: _dayLabels,
    totalMinutes: 280,
    totalCalories: 1960,
    streakDays: 1,
    aiCoachMessage: '',
  );
}

/// 주간 자료만 돌려주는 대역. 이 시험은 읽기만 한다.
class _FixedWeekRepository implements ExerciseRepository {
  _FixedWeekRepository(this._sessions);

  final List<ExerciseSession> _sessions;

  @override
  Future<ExerciseAdvice> fetchAdvice(String period) async =>
      const ExerciseAdvice(message: '조언');

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _week(_sessions);

  @override
  Future<List<ExercisePeriodWeek>> fetchPeriod({
    DateTime? from,
    DateTime? to,
  }) async => const <ExercisePeriodWeek>[];

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async => _week(_sessions);

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
  }) async => throw UnimplementedError();

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
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
  }) async => throw UnimplementedError();
}

/// 그날 걸려 있던 추천 개인운동 목록을 **모르는** 코치 저장소. (#2161)
///
/// 지난 날짜는 원래 그날의 체크 목록(읽기 전용)으로 추천 개인운동을 보여 준다.
/// 이 시험이 보는 `완료한 개인운동` 기록 카드는 목록을 알 수 없을 때(담당이
/// 바뀌어 옛 목록이 지금 담당의 것이 아닐 때) 한 운동을 잃지 않으려고 서는
/// 자리다. 그 경우를 만든다.
class _NoDayListCoachRepository extends MockMemberCoachRepository {
  @override
  Future<List<CoachRoutine>> fetchRoutinesOn(DateTime day) async =>
      const <CoachRoutine>[];
}

Widget _app(ExerciseRepository repo) => ProviderScope(
  overrides: <Override>[
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
      _NoDayListCoachRepository() as MemberCoachRepository,
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

void main() {
  // 월요일에는 다른 평일이 모두 미래라 선택할 수 없다.
  // 과거 기록을 고르는 시나리오는 주 중간으로 고정한다.
  setUp(() => useFixedKstDate());

  DateTime today() {
    final DateTime now = nowKst();
    return DateTime(now.year, now.month, now.day);
  }

  /// 오늘이 아닌 이번 주의 다른 날 — 지난 날짜 상세(`_ExerciseDayDetail`)로
  /// 들어가야 이 목록이 그려진다.
  DateTime otherDay() => today().weekday == DateTime.monday
      ? today().add(const Duration(days: 1))
      : today().subtract(const Duration(days: 1));

  ExerciseSession trainerSession({
    required String id,
    required DateTime date,
    required ExerciseSource source,
    required String name,
    String? timeLabel,
    String trainerFeedback = '',
    int sets = 4,
    int reps = 10,
    double weight = 40,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
  }) => ExerciseSession(
    id: id,
    dayLabel: _labelOf(date),
    date: date,
    type: ExerciseType.strength,
    minutes: 50,
    calories: 300,
    // 운동 하나가 세션 하나다(#1902). 종목별 값이 이 행의 필드로 온다.
    name: name,
    sets: sets,
    reps: reps,
    weight: weight,
    source: source,
    intensity: intensity,
    assignedRoutineName: name,
    timeLabel: timeLabel,
    trainerFeedback: trainerFeedback,
  );

  Future<AppLocalizations> pumpDay(
    WidgetTester tester,
    List<ExerciseSession> sessions,
  ) async {
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_FixedWeekRepository(sessions)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${otherDay().day}').first);
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(ExercisePage)));
  }

  testWidgets('지난 날짜의 PT 기록이 오늘 카드와 같은 차림으로 선다', (tester) async {
    useFixedKstDate();
    final DateTime target = otherDay();
    final AppLocalizations l = await pumpDay(tester, <ExerciseSession>[
      trainerSession(
        id: 'pt-1',
        date: target,
        source: ExerciseSource.trainerPt,
        name: 'PT 세션',
        timeLabel: '18:00',
        trainerFeedback: '어깨 힘 빼고 가슴으로 미세요.',
      ),
    ]);

    final Finder card = find.byKey(
      const ValueKey<String>('exercise-pt-records'),
    );
    expect(card, findsOneWidget);

    Finder inCard(Finder f) => find.descendant(of: card, matching: f);
    // 제목·완료 시각·운동 시간·구분선·종목 줄·피드백 — 오늘 화면과 같은 순서다.
    expect(inCard(find.text(l.exCompletedPtDayTitle)), findsOneWidget);
    expect(inCard(find.text(l.exCompletedPtTime('18:00'))), findsOneWidget);
    expect(inCard(find.text(l.exDurationMinutes(50))), findsOneWidget);
    expect(inCard(find.byType(AppDivider)), findsOneWidget);
    expect(
      inCard(find.text('PT 세션 · 4세트 · 10회 · 40kg · 보통')),
      findsOneWidget,
      reason: '무슨 운동을 했는지가 종목 줄로 남는다',
    );
    expect(inCard(find.text('어깨 힘 빼고 가슴으로 미세요.')), findsOneWidget);
  });

  testWidgets('시각·피드백이 없는 기록에는 없는 값을 지어내지 않는다', (tester) async {
    useFixedKstDate();
    final DateTime target = otherDay();
    final AppLocalizations l = await pumpDay(tester, <ExerciseSession>[
      trainerSession(
        id: 'routine-1',
        date: target,
        source: ExerciseSource.assignedRoutine,
        name: '코어 루틴',
      ),
    ]);

    final Finder card = find.byKey(
      const ValueKey<String>('exercise-routine-records'),
    );
    expect(card, findsOneWidget);
    // 배정 개인운동은 언제 했는지를 남기지 않는다 — 완료 시각 태그가 서지 않는다.
    expect(find.byIcon(AppIcons.checkCircle), findsNothing);
    // 운동 시간은 기록에 있으므로 그대로 적는다.
    expect(
      find.descendant(of: card, matching: find.text(l.exDurationMinutes(50))),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('코어 루틴 · 4세트 · 10회 · 40kg · 보통'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('그날 어느 강도로 했는지가 줄에 남는다 (#2160)', (tester) async {
    // 직접 기록한 운동 줄은 강도를 이미 말하는데 PT·추천 운동에서 파생된
    // 기록만 빠져 있었다. 회원이 지난 날짜를 열어도 자기가 어느 강도로 했는지
    // 다시 볼 수 있어야 한다.
    useFixedKstDate();
    final DateTime target = otherDay();
    await pumpDay(tester, <ExerciseSession>[
      trainerSession(
        id: 'pt-high',
        date: target,
        source: ExerciseSource.trainerPt,
        name: 'PT 세션',
        timeLabel: '18:00',
        intensity: ExerciseIntensity.high,
      ),
    ]);

    expect(find.text('PT 세션 · 4세트 · 10회 · 40kg · 높음'), findsOneWidget);
  });

  testWidgets('트레이너 쪽 기록이 직접 기록한 운동보다 위에 선다 (#2017)', (tester) async {
    useFixedKstDate();
    final DateTime target = otherDay();
    final AppLocalizations l = await pumpDay(tester, <ExerciseSession>[
      trainerSession(
        id: 'pt-1',
        date: target,
        source: ExerciseSource.trainerPt,
        name: 'PT 세션',
        timeLabel: '18:00',
      ),
    ]);

    // 오늘 화면과 같은 차례다: 완료한 PT → 추천 개인운동 → 직접 기록.
    // 날짜만 옮겼는데 순서가 뒤집히면 어느 것이 트레이너 쪽이고 어느 것이 내가
    // 적은 것인지 매번 다시 읽어야 한다.
    final double ptTitleTop = tester
        .getRect(find.text(l.exCompletedPtDayTitle))
        .top;
    final double itemTop = tester
        .getRect(find.text('PT 세션 · 4세트 · 10회 · 40kg · 보통'))
        .top;
    final double ownTitleTop = tester.getRect(find.text(l.exOwnRecords)).top;

    expect(itemTop, greaterThan(ptTitleTop));
    expect(ownTitleTop, greaterThan(itemTop));

    // 직접 적은 기록이 없는 날이라 빈 안내가 그 제목 아래에 남는다 — PT 카드가
    // 그 문구에 딸려 읽히지 않는다(#1884).
    final double emptyTop = tester.getRect(find.text(l.exOwnRecordsEmpty)).top;
    expect(emptyTop, greaterThan(ownTitleTop));

    // 두 묶음이 붙어 보이지 않게 띄운다.
    final double ptBottom = tester
        .getRect(find.text('PT 세션 · 4세트 · 10회 · 40kg · 보통'))
        .bottom;
    expect(ownTitleTop - ptBottom, greaterThanOrEqualTo(OnCareSpacing.s20));
  });

  testWidgets('배정 개인운동은 PT 카드에 섞이지 않고 제 카드로 선다', (tester) async {
    useFixedKstDate();
    final DateTime target = otherDay();
    final AppLocalizations l = await pumpDay(tester, <ExerciseSession>[
      trainerSession(
        id: 'pt-1',
        date: target,
        source: ExerciseSource.trainerPt,
        name: 'PT 세션',
        timeLabel: '18:00',
      ),
      trainerSession(
        id: 'routine-1',
        date: target,
        source: ExerciseSource.assignedRoutine,
        name: '코어 루틴',
      ),
    ]);

    final Finder ptCard = find.byKey(
      const ValueKey<String>('exercise-pt-records'),
    );
    final Finder routineCard = find.byKey(
      const ValueKey<String>('exercise-routine-records'),
    );
    expect(ptCard, findsOneWidget);
    expect(routineCard, findsOneWidget);
    expect(
      find.descendant(of: ptCard, matching: find.text(l.exCompletedPtDayTitle)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: routineCard,
        matching: find.text(l.exCompletedRoutineDayTitle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: routineCard,
        matching: find.byIcon(AppIcons.exercise),
      ),
      findsOneWidget,
      reason: '완료한 루틴 헤더도 공통 운동 아이콘을 쓴다',
    );

    // 각자의 종목은 제 카드 안에만 있다.
    expect(
      find.descendant(
        of: ptCard,
        matching: find.text('PT 세션 · 4세트 · 10회 · 40kg · 보통'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: ptCard,
        matching: find.text('코어 루틴 · 4세트 · 10회 · 40kg · 보통'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: routineCard,
        matching: find.text('코어 루틴 · 4세트 · 10회 · 40kg · 보통'),
      ),
      findsOneWidget,
    );

    // 수업 시각은 PT 카드에만 붙는다 — 개인운동은 수업이 아니다.
    expect(
      find.descendant(
        of: ptCard,
        matching: find.text(l.exCompletedPtTime('18:00')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: routineCard,
        matching: find.byIcon(AppIcons.checkCircle),
      ),
      findsNothing,
    );
  });

  testWidgets('배정 개인운동만 있는 날에는 PT 카드가 서지 않는다', (tester) async {
    useFixedKstDate();
    final DateTime target = otherDay();
    final AppLocalizations l = await pumpDay(tester, <ExerciseSession>[
      trainerSession(
        id: 'routine-1',
        date: target,
        source: ExerciseSource.assignedRoutine,
        name: '코어 루틴',
      ),
    ]);

    // 수업을 하지 않은 날이다. `완료한 PT` 라는 제목이 뜨면 안 된다.
    expect(
      find.byKey(const ValueKey<String>('exercise-pt-records')),
      findsNothing,
    );
    expect(find.text(l.exCompletedPtDayTitle), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('exercise-routine-records')),
      findsOneWidget,
    );
  });

  testWidgets('회원이 직접 적은 기록은 두 카드 어디에도 오지 않는다', (tester) async {
    useFixedKstDate();
    final DateTime target = otherDay();
    await pumpDay(tester, <ExerciseSession>[
      ExerciseSession(
        id: 'own-1',
        dayLabel: _labelOf(target),
        date: target,
        type: ExerciseType.cardio,
        minutes: 40,
        calories: 280,
        name: '내가 적은 러닝',
      ),
    ]);

    // 회원 기록뿐인 날에는 두 카드 다 서지 않는다(#1428 — 두 번 그리지 않는다).
    expect(
      find.byKey(const ValueKey<String>('exercise-pt-records')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('exercise-routine-records')),
      findsNothing,
    );
    // 직접 기록은 제자리에 그대로 남는다.
    expect(find.text('내가 적은 러닝'), findsOneWidget);
  });
}
