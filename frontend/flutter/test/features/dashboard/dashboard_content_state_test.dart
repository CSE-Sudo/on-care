import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/dashboard/presentation/widgets/dashboard_content.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/member_tab_header.dart';
import 'package:oncare/shared/widgets/metric_trend_chart.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  const liveSummary = DashboardSummary(
    indicators: <HealthIndicator>[
      HealthIndicator(label: '칼로리', current: 1860, max: 2000, unit: 'kcal'),
      HealthIndicator(
        label: '나트륨',
        current: 2329,
        max: 2000,
        unit: 'mg',
        overBudget: true,
      ),
      HealthIndicator(label: '당류', current: 43, max: 50, unit: 'g'),
    ],
    macros: DietMacros(
      carbsG: 203.6,
      proteinG: 109.3,
      fatG: 66.5,
      carbsPct: 44,
      proteinPct: 24,
      fatPct: 32,
    ),
    dietEntries: 4,
    exerciseMinutes: 45,
    exerciseCalories: 520,
    exerciseCount: 4,
    nutritionWeek: <NutritionDay>[
      NutritionDay(label: '월', calories: 1100, sodiumMg: 110, sugarG: 11),
      NutritionDay(label: '화', calories: 1200, sodiumMg: 120, sugarG: 12),
      NutritionDay(label: '수', calories: 1300, sodiumMg: 130, sugarG: 13),
      NutritionDay(label: '목', calories: 1400, sodiumMg: 140, sugarG: 14),
      NutritionDay(label: '금', calories: 1500, sodiumMg: 150, sugarG: 15),
      NutritionDay(label: '토', calories: 1600, sodiumMg: 160, sugarG: 16),
      NutritionDay(label: '일', calories: 1700, sodiumMg: 170, sugarG: 17),
    ],
    todaySchedule: <ScheduleItem>[
      ScheduleItem(time: '10:00', title: '병원 정기검진', emoji: '🏥'),
    ],
    weekScore: 85,
    weekScoreDelta: 12,
    sodiumWarning: '김치찌개·배추김치 섭취로 나트륨이 높아요.',
    exerciseFeedback: '이번 주 운동 목표의 80%를 달성했어요.',
  );

  /// 홈 운동 카드는 이제 주간 조회가 실패하면 막대 대신 실패를 그린다(#962).
  /// 예전에는 그 자리에 데모 상수가 들어가 provider 가 터져도 차트가 보였다 —
  /// 그래서 이 테스트들이 통과했다. 레이아웃을 보는 테스트이니 값을 넣어 준다.
  const AsyncValue<ExerciseWeek> exerciseWeek = AsyncValue<ExerciseWeek>.data(
    ExerciseWeek(
      sessions: <ExerciseSession>[],
      // 합계가 summary 와 맞는다 — 45분 · 520kcal · 운동 4일.
      dailyMinutes: <double>[10, 10, 0, 15, 10, 0, 0],
      dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
      totalMinutes: 45,
      totalCalories: 520,
      streakDays: 2,
      aiCoachMessage: '',
      dailyCalories: <double>[120, 120, 0, 160, 120, 0, 0],
    ),
  );

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required Future<DashboardSummary> Function() load,
    Size size = const Size(800, 1600),
    Locale locale = const Locale('ko'),
    List<Override> extraOverrides = const <Override>[],
    UserProfile profile = const UserProfile(
      id: 'member',
      name: '테스트',
      email: 'member@example.com',
    ),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          accountRepositoryProvider.overrideWithValue(
            MockAccountRepository(profile: profile),
          ),
          dashboardSummaryProvider.overrideWith((ref) => load()),
          memberCoachRepositoryProvider.overrideWithValue(
            MockMemberCoachRepository(),
          ),
          exerciseWeekViewProvider.overrideWithValue(exerciseWeek),
          ...extraOverrides,
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: DashboardContent()),
        ),
      ),
    );
  }

  testWidgets('shows loading state', (WidgetTester tester) async {
    final completer = Completer<DashboardSummary>();
    await pumpDashboard(tester, load: () => completer.future);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('home header opens the assigned trainer chat', (
    WidgetTester tester,
  ) async {
    await pumpDashboard(
      tester,
      load: () async => liveSummary,
      // 채팅 화면이 데모 안내 배너 노출을 이 설정으로 가른다. 기본값이 없는
      // provider 라, 채팅을 실제로 여는 이 테스트에서만 넣어 준다 — 공통
      // 헬퍼에 넣으면 데모 저장소들이 함께 살아나 다른 테스트의 전제가 바뀐다.
      extraOverrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'http://localhost',
            useMockApi: true,
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trainerChatHeaderButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('trainerChatHeaderButton')));
    await tester.pumpAndSettle();

    expect(find.byType(TrainerChatPage), findsOneWidget);
  });

  testWidgets('weekly nutrition chart uses DashboardSummary history', (
    WidgetTester tester,
  ) async {
    await pumpDashboard(tester, load: () async => liveSummary);
    await tester.pumpAndSettle();

    final chart = find.byKey(
      const ValueKey<String>('dashboard-nutrition-chart'),
    );
    final paints = tester.widgetList<CustomPaint>(
      find.descendant(of: chart, matching: find.byType(CustomPaint)),
    );
    // 홈과 식단 탭이 같은 차트를 쓰면서 페인터가 공개 타입이 됐다. 이름을
    // 문자열로 맞추던 것을 실제 타입으로 바꾼다.
    final CustomPaint trendPaint = paints.firstWhere(
      (paint) => paint.painter is MetricTrendPainter,
    );
    final MetricTrendPainter trendPainter =
        trendPaint.painter! as MetricTrendPainter;

    expect(trendPainter.cur, <double>[
      1100,
      1200,
      1300,
      1400,
      1500,
      1600,
      1700,
    ]);
  });

  testWidgets('home uses the shared tab header and notification style', (
    WidgetTester tester,
  ) async {
    await pumpDashboard(
      tester,
      load: () async => liveSummary,
      extraOverrides: <Override>[
        notificationUnreadProvider.overrideWith((ref) => Stream<int>.value(2)),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byType(MemberTabHeader), findsOneWidget);
    expect(find.byType(MemberLogo), findsOneWidget);

    final Finder bellFinder = find.byWidgetPredicate(
      (Widget widget) =>
          widget is HeaderActionButton &&
          widget.icon == Icons.notifications_none_rounded,
    );
    final HeaderActionButton notificationButton = tester.widget(bellFinder);
    // 점은 이제 **서버 미읽음을 따른다.** 예전에는 항상 켜져 있어서 읽을 것이
    // 없어도 남았다(#636).
    expect(notificationButton.showDot, isTrue);
    // 읽지 않은 알림은 `주의` 가 아니라 새 소식이다 — 주황은 같은 화면의
    // 주의 색과 겹쳤다. 새 알림 점은 위험 빨강 한 가지다. (#1060, #1690)
    final AppStatusDot dot = tester.widget(
      find.descendant(of: bellFinder, matching: find.byType(AppStatusDot)),
    );
    expect(dot.color, OnCareColors.danger);
  });

  testWidgets('읽지 않은 알림이 없으면 벨에 점이 없다', (WidgetTester tester) async {
    await pumpDashboard(
      tester,
      load: () async => liveSummary,
      extraOverrides: <Override>[
        notificationUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
      ],
    );
    await tester.pumpAndSettle();

    final HeaderActionButton bell = tester.widget(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is HeaderActionButton &&
            widget.icon == Icons.notifications_none_rounded,
      ),
    );
    expect(bell.showDot, isFalse);
  });

  testWidgets('shows error state', (WidgetTester tester) async {
    await pumpDashboard(
      tester,
      load: () => Future<DashboardSummary>.error(StateError('boom')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('대시보드 정보를 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('shows empty state with zero values', (
    WidgetTester tester,
  ) async {
    await pumpDashboard(
      tester,
      load: () async => const DashboardSummary(
        indicators: <HealthIndicator>[
          HealthIndicator(label: '칼로리', current: 0, max: 2000, unit: 'kcal'),
          HealthIndicator(label: '나트륨', current: 0, max: 2000, unit: 'mg'),
          HealthIndicator(label: '당류', current: 0, max: 50, unit: 'g'),
        ],
        macros: DietMacros.zero(),
        dietEntries: 0,
        exerciseMinutes: 0,
        todaySchedule: <ScheduleItem>[],
        weekScore: 50,
        weekScoreDelta: 0,
        sodiumWarning: null,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('아직 오늘 기록이 없어요. 식단이나 운동을 기록해 보세요.'), findsOneWidget);
    // 오늘의 일정 카드는 화면에서 내려 뒀다 (#1055) — 빈 상태 문구도 함께 없다.
    expect(find.text('오늘 예정된 일정이 없어요.'), findsNothing);
    // 탄단지는 홈 식단 카드에서 뺐다 (#1117) — 식단 탭이 말한다.
    expect(find.text('0g'), findsNothing);
    expect(find.text('탄수화물'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('dashboard-nutrition-chart')),
      findsNothing,
    );
    // 운동 카드는 요약이 비어도 이번 주 카드를 그린다 (#1183) — 주간 기록은
    // 오늘 기록과 별개 소스라, 오늘이 비었다고 한 주가 빈 것은 아니다.
    expect(
      find.byKey(const ValueKey<String>('dashboard-exercise-week')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('지표 카드는 소수 수치를 반올림하지 않는다 (당류 17.8)', (WidgetTester tester) async {
    await pumpDashboard(
      tester,
      load: () async => const DashboardSummary(
        indicators: <HealthIndicator>[
          HealthIndicator(label: '칼로리', current: 1067, max: 2000, unit: 'kcal'),
          HealthIndicator(label: '나트륨', current: 3428, max: 2000, unit: 'mg'),
          HealthIndicator(label: '당류', current: 17.8, max: 50, unit: 'g'),
        ],
        macros: DietMacros(
          carbsG: 120,
          proteinG: 45,
          fatG: 45,
          carbsPct: 45,
          proteinPct: 17,
          fatPct: 38,
        ),
        dietEntries: 3,
        exerciseMinutes: 0,
        todaySchedule: <ScheduleItem>[],
        weekScore: 60,
        weekScoreDelta: 0,
        sodiumWarning: null,
      ),
    );
    await tester.pumpAndSettle();

    // 식단 탭·그래프 라벨과 같은 표기(17.8)여야 한다 — 18 로 반올림되면 회귀.
    expect(find.text('17.8'), findsOneWidget);
    expect(find.text('18'), findsNothing);
    // 정수 수치는 천단위 콤마 표기를 유지한다.
    expect(find.text('1,067'), findsOneWidget);
    expect(find.text('3,428'), findsOneWidget);
  });

  testWidgets('지표 카드 단위는 라벨이 아니라 목표치 오른쪽에 붙는다', (WidgetTester tester) async {
    await pumpDashboard(
      tester,
      load: () async => liveSummary,
      size: const Size(390, 2200),
    );
    await tester.pumpAndSettle();

    // "칼로리" - "1,860" - "/2,000kcal" 순으로 읽혀야 한다.
    expect(find.text('/2,000kcal'), findsOneWidget);
    expect(find.text('/2,000mg'), findsOneWidget);
    expect(find.text('/50g'), findsOneWidget);

    // 라벨에는 단위를 달지 않는다 — 좁은 카드에서 라벨이 먼저 축소되던 문제.
    expect(find.text('칼로리'), findsOneWidget);
    expect(find.text('칼로리 (kcal)'), findsNothing);
    expect(find.text('나트륨 (mg)'), findsNothing);
    expect(find.text('당류 (g)'), findsNothing);

    // 단위 없는 예전 목표치 표기가 남아 있으면 회귀.
    expect(find.text('/2,000'), findsNothing);
    expect(find.text('/50'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('목표가 없는 지표(max=0)는 목표치 대신 단위만 남긴다', (WidgetTester tester) async {
    // 단위가 목표치 줄로 옮겨간 뒤로는, 목표치 줄이 통째로 빠지면 큰 숫자가
    // 단위를 잃는다. 그래서 max=0 이면 같은 자리에 단위만 적는다.
    await pumpDashboard(
      tester,
      load: () async => const DashboardSummary(
        indicators: <HealthIndicator>[
          HealthIndicator(label: '칼로리', current: 1860, max: 2000, unit: 'kcal'),
          HealthIndicator(label: '나트륨', current: 900, max: 2000, unit: 'mg'),
          HealthIndicator(label: '당류', current: 43, max: 0, unit: 'g'),
        ],
        macros: DietMacros(
          carbsG: 203.6,
          proteinG: 109.3,
          fatG: 66.5,
          carbsPct: 44,
          proteinPct: 24,
          fatPct: 32,
        ),
        dietEntries: 4,
        exerciseMinutes: 45,
        todaySchedule: <ScheduleItem>[],
        weekScore: 85,
        weekScoreDelta: 12,
        sodiumWarning: null,
      ),
      size: const Size(390, 2200),
    );
    await tester.pumpAndSettle();

    expect(find.text('g'), findsOneWidget);
    expect(find.text('/0g'), findsNothing);
    // 목표가 있는 지표는 그대로 "/목표+단위".
    expect(find.text('/2,000kcal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('운동 카드는 운동 탭과 같은 유형별 주간 목표를 쓴다', (WidgetTester tester) async {
    await pumpDashboard(
      tester,
      load: () async => const DashboardSummary(
        indicators: <HealthIndicator>[
          HealthIndicator(label: '칼로리', current: 1067, max: 2000, unit: 'kcal'),
          HealthIndicator(label: '나트륨', current: 900, max: 2000, unit: 'mg'),
          HealthIndicator(label: '당류', current: 20, max: 50, unit: 'g'),
        ],
        macros: DietMacros.zero(),
        dietEntries: 1,
        exerciseMinutes: 30,
        exerciseCalories: 300,
        exerciseCount: 1,
        exerciseBurnGoal: 800,
        todaySchedule: <ScheduleItem>[],
        weekScore: 60,
        weekScoreDelta: 0,
        sodiumWarning: null,
      ),
      profile: const UserProfile(
        id: 'member',
        name: '테스트',
        email: 'member@example.com',
        weeklyWorkoutGoal: 5,
        weeklyExerciseMinutesGoal: 240,
        weeklyBurnGoal: 900,
      ),
    );
    await tester.pumpAndSettle();

    // 홈은 운동 탭 `운동 현황 - 이번 주` 카드를 그대로 쓴다 (#1183) — 목표도
    // 그 카드의 것이다. 프로필에 저장된 주 3회·240분·900kcal 은 이 카드의
    // 기준이 아니다 — MY 목표를 이 값에 연결하는 것은 #1139 이 다룬다.
    //
    // 값과 목표는 한 덩어리(`Text.rich`)로 적히므로 부분 문자열로 찾는다.
    expect(find.textContaining('/2,100', findRichText: true), findsOneWidget);
    expect(find.textContaining('/150분', findRichText: true), findsOneWidget);
    expect(find.textContaining('/21세트', findRichText: true), findsOneWidget);
    expect(find.textContaining('/60분', findRichText: true), findsOneWidget);
    expect(find.textContaining('/5일', findRichText: true), findsNothing);
    expect(find.textContaining('/900', findRichText: true), findsNothing);
  });

  for (final width in <double>[360, 480, 800]) {
    testWidgets('renders live PR #293 layout without overflow at ${width}px', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        load: () async => liveSummary,
        size: Size(width, 2200),
      );
      await tester.pumpAndSettle();

      expect(find.text('식단 · 영양'), findsOneWidget);
      expect(find.text('1,860'), findsWidgets);
      // 탄단지는 홈에서 뺐다 (#1117).
      expect(find.text('203.6g'), findsNothing);
      expect(find.text('109.3g'), findsNothing);
      expect(find.text('66.5g'), findsNothing);
      expect(find.text('주간 운동'), findsOneWidget);
      // 운동 카드 본문은 운동 탭 `이번 주` 카드 그대로다 (#1183) — 주간 소모
      // 한 줄과 유형별 세 줄. 예전의 지표 네 줄·주간 추이 막대는 없다.
      expect(find.text('이번 주 소모'), findsOneWidget);
      expect(find.text('유산소'), findsOneWidget);
      expect(find.text('근력'), findsOneWidget);
      expect(find.text('스트레칭'), findsOneWidget);
      expect(find.text('소모 칼로리'), findsNothing);
      expect(find.text('운동 시간'), findsNothing);
      expect(find.text('운동 일수'), findsNothing);
      expect(find.text('운동 추이 (kcal)'), findsNothing);
      // 오늘의 일정 카드는 화면에서 내려 뒀다 (#1055).
      expect(find.text('병원 정기검진'), findsNothing);
      expect(find.textContaining('김치찌개·배추김치'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('dashboard-nutrition-chart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('dashboard-exercise-week')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // 위 회귀 테스트는 한국어로만 돌아 영어 폭을 전혀 보지 않았다(#440).
  //
  // 주의 — 여기서 재는 폭은 **실제 기기보다 보수적이다.** 위젯 테스트의 기본
  // 폰트는 모든 글자를 `fontSize` 크기의 정사각형으로 그려서 라틴 문자가 실제의
  // 약 2배로 잡힌다(`Diet & nutrition`@12.5px 가 200px, 실제 폰트는 ~85px).
  // 따라서 이 테스트가 통과한다고 실제 기기에서 안전하다는 보장은 아니고,
  // 반대로 여기서 넘친다고 사용자가 그대로 겪는다는 뜻도 아니다.
  //
  // 그래도 남겨 두는 이유는 헤더가 **줄어들 수 있는 구조인지**를 지키기
  // 위해서다. 문구가 길어지면 그냥 넘치던 예전 구조(고유 폭 3개 + Spacer)로
  // 되돌아가면 이 테스트가 먼저 깨진다.
  for (final double width in <double>[360, 390, 480]) {
    testWidgets('영어 로케일도 ${width}px 에서 넘치지 않는다 (#440)', (
      WidgetTester tester,
    ) async {
      await pumpDashboard(
        tester,
        load: () async => liveSummary,
        size: Size(width, 2200),
        locale: const Locale('en'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
      // 헤더가 줄어들지 못하면 밀려난 더보기 링크부터 넘친다.
      expect(find.text(en.homeDetails), findsWidgets);
      // `AI 분석` 필은 뗐다 (#1055) — 헤더가 줄어들 수 있는 구조인지만 본다.
      expect(find.text(en.homeDietNutritionTitle), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
