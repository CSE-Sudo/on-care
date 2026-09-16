import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
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
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 지난 날짜의 PT 기록이 **제 제목 아래** 선다. (#1884)
///
/// 이 목록에는 제목이 없어, 바로 위 `직접 기록한 운동` 이 비었을 때 띄우는
/// `직접 추가한 운동이 없어요` 아래로 카드가 그대로 흘러나왔다 — 없다고 해 놓고
/// 보여 주는 꼴이라 저 카드가 무엇인지 알 수 없었다. 오늘 화면이 PT 일지를
/// `오늘 완료한 PT` 아래 두는 것과 같은 짜임 — 아이콘 달린 제목을 인 흰 카드 —
/// 으로 갈라 세운다. 지난 날짜는 이제 **직접 기록한 운동** 과 **완료한 PT** 두
/// 갈래로만 읽힌다.
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
  Future<String> fetchAdvice(String period) async => '조언';

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _week(_sessions);

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
    double? weight,
  }) async => throw UnimplementedError();
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

void main() {
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
  }) => ExerciseSession(
    id: id,
    dayLabel: _labelOf(date),
    date: date,
    type: ExerciseType.strength,
    minutes: 50,
    calories: 300,
    source: source,
    assignedRoutineName: name,
    items: const <String>['벤치프레스 4세트'],
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

  testWidgets('지난 날짜의 PT 기록이 제목 아래 선다', (tester) async {
    final DateTime target = otherDay();
    final AppLocalizations l = await pumpDay(tester, <ExerciseSession>[
      trainerSession(
        id: 'pt-1',
        date: target,
        source: ExerciseSource.trainerPt,
        name: 'PT 세션',
      ),
    ]);

    final Finder card = find.byKey(
      const ValueKey<String>('exercise-pt-records'),
    );
    expect(card, findsOneWidget);
    // 제목은 카드 **안**에 있다 — 오늘 화면의 `오늘 완료한 PT` 와 같은 짜임이다.
    expect(
      find.descendant(of: card, matching: find.text(l.exCompletedPtDayTitle)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('PT 세션')),
      findsOneWidget,
    );
  });

  testWidgets('제목이 `직접 추가한 운동이 없어요` 아래에 온다 — 카드가 그 문구에 딸려 읽히지 않는다', (
    tester,
  ) async {
    final DateTime target = otherDay();
    final AppLocalizations l = await pumpDay(tester, <ExerciseSession>[
      trainerSession(
        id: 'pt-1',
        date: target,
        source: ExerciseSource.trainerPt,
        name: 'PT 세션',
      ),
    ]);

    // 회원이 직접 적은 기록은 없는 날이다 — 빈 안내가 떠 있다.
    expect(find.text(l.exOwnRecordsEmpty), findsOneWidget);

    final double emptyBottom = tester
        .getRect(find.text(l.exOwnRecordsEmpty))
        .bottom;
    final double titleTop = tester
        .getRect(find.text(l.exCompletedPtDayTitle))
        .top;
    final double itemTop = tester.getRect(find.text('PT 세션')).top;

    // 제목이 빈 안내와 기록 **사이**에 선다. 기록이 안내 바로 밑에 붙으면
    // 없다고 해 놓고 보여 주는 꼴이 된다.
    expect(titleTop, greaterThan(emptyBottom));
    expect(itemTop, greaterThan(titleTop));
    // 안내와 카드가 붙어 보이지 않게 띄운다(#1884).
    expect(titleTop - emptyBottom, greaterThanOrEqualTo(OnCareSpacing.s20));
  });

  testWidgets('트레이너가 배정한 개인운동도 같은 카드 안에 남는다', (tester) async {
    final DateTime target = otherDay();
    await pumpDay(tester, <ExerciseSession>[
      trainerSession(
        id: 'pt-1',
        date: target,
        source: ExerciseSource.trainerPt,
        name: 'PT 세션',
      ),
      trainerSession(
        id: 'routine-1',
        date: target,
        source: ExerciseSource.assignedRoutine,
        name: '코어 루틴',
      ),
    ]);

    // 개인운동을 따로 어떻게 보여 줄지는 아직 정해지지 않았다. 그 결정 전까지
    // 회원이 직접 적지 않은 기록은 한 자리에 모아 둔다 — 어디에도 없는 것보다
    // 낫다.
    final Finder card = find.byKey(
      const ValueKey<String>('exercise-pt-records'),
    );
    for (final String id in <String>['pt-1', 'routine-1']) {
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(ValueKey<String>('exercise-pt-record-$id')),
        ),
        findsOneWidget,
        reason: id,
      );
    }
    expect(
      find.descendant(of: card, matching: find.text('코어 루틴')),
      findsOneWidget,
    );
  });

  testWidgets('회원이 직접 적은 기록은 이 카드에 오지 않는다', (tester) async {
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

    // 회원 기록뿐인 날에는 이 카드가 아예 서지 않는다(#1428 — 두 번 그리지 않는다).
    expect(
      find.byKey(const ValueKey<String>('exercise-pt-records')),
      findsNothing,
    );
    // 직접 기록은 제자리에 그대로 남는다.
    expect(find.text('내가 적은 러닝'), findsOneWidget);
  });
}
