import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/features/dashboard/data/repositories/mock_dashboard_repository.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_period_view.dart';
import 'package:oncare/features/exercise/data/repositories/mock_exercise_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/services/locale_provider.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'helpers/diet_period_tabs.dart';
import 'helpers/fake_diet_repository.dart';

class _CountingMemberCoachRepository extends MockMemberCoachRepository {
  int routineLoads = 0;
  int sessionLoads = 0;

  @override
  Future<List<CoachRoutine>> fetchRoutines() {
    routineLoads += 1;
    return super.fetchRoutines();
  }

  @override
  Future<List<CoachSession>> fetchSessions() {
    sessionLoads += 1;
    return super.fetchSessions();
  }
}

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    Locale? locale,
    MemberCoachRepository? memberCoachRepository,
  }) async {
    const config = AppConfig(
      environment: Environment.dev,
      apiBaseUrl: 'https://dev.api.test',
      useMockApi: true,
      // 데모 진입은 기본 빌드에서 감춰 뒀다 — 이 테스트는 그 경로로 화면에
      // 들어가므로 플래그를 켜고 편다. (#1526)
      showDemoEntry: true,
    );
    // 식단 탭과 홈 요약이 같은 데이터를 본다 — 아래 두 override 가 공유한다.
    final FakeDietRepository diet = FakeDietRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(config),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          // Diet repo defaults to DioDietRepository (Stage 9) which
          // needs a real dio+db. Swap to the in-memory fake here.
          //
          // 아래 대시보드 override 와 **같은 인스턴스**를 쓴다. 따로 만들면 식단
          // 탭에서 추가·삭제한 끼니를 홈 요약이 못 보게 되어, 테스트가 실제와
          // 다른 상태를 검증하게 된다(리뷰).
          dietRepositoryProvider.overrideWithValue(diet as DietRepository),
          // Same reason — exercise repo defaults to DioExerciseRepository
          // (Stage 9.6); swap to the in-memory mock here.
          exerciseRepositoryProvider.overrideWithValue(
            MockExerciseRepository() as ExerciseRepository,
          ),
          // Dashboard summary defaults to DioDashboardRepository (Stage
          // 9.8); the smoke test only inspects the nav, so the mock is
          // plenty.
          dashboardRepositoryProvider.overrideWithValue(
            MockDashboardRepository(diet) as DashboardRepository,
          ),
          if (memberCoachRepository != null)
            memberCoachRepositoryProvider.overrideWithValue(
              memberCoachRepository,
            ),
          sessionFeatureResetOverride(),
          if (locale != null) localeProvider.overrideWith((ref) => locale),
        ],
        child: const OncareApp(),
      ),
    );
    await tester.pumpAndSettle();
    // The app now boots into the sign-in screen; enter demo mode to reach
    // the main app (Home tab). Find by Key so the finder is locale-independent,
    // and scroll it into view (it sits below the fold on the compact surface).
    final demoButton = find.byKey(const Key('demoEnterButton'));
    await tester.ensureVisible(demoButton);
    await tester.pumpAndSettle();
    await tester.tap(demoButton);
    await tester.pumpAndSettle();
  }

  GoRouter appRouter(WidgetTester tester) {
    return ProviderScope.containerOf(
      tester.element(find.byType(OncareApp)),
    ).read(appRouterProvider);
  }

  Future<double> openRecordSheetAndMeasureBottomSpacing(
    WidgetTester tester,
  ) async {
    await tester.tap(find.byKey(const Key('recordAddButton')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('recordAddSheet'));
    final options = find.byKey(const Key('recordOptions'));

    final logicalHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getBottomRight(sheet).dy, logicalHeight);

    return tester.getBottomRight(sheet).dy - tester.getBottomRight(options).dy;
  }

  double bottomSpacingBetween(
    WidgetTester tester,
    String surfaceKey,
    String contentKey,
  ) {
    return tester.getBottomRight(find.byKey(Key(surfaceKey))).dy -
        tester.getBottomRight(find.byKey(Key(contentKey))).dy;
  }

  Future<void> openExerciseAddSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('recordAddButton')));
    await tester.pumpAndSettle();
    final exerciseOption = find.descendant(
      of: find.byKey(const Key('recordOptions')),
      matching: find.text('운동'),
    );
    await tester.tap(exerciseOption);
    await tester.pumpAndSettle();
  }

  testWidgets('추가 메뉴 카드가 시트 바닥에 붙지 않는다 (#1154)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester, locale: const Locale('ko'));
    await tester.tap(find.byKey(const Key('recordAddButton')));
    await tester.pumpAndSettle();

    final Finder sheet = find.byKey(const Key('recordAddSheet'));
    // 카드(테두리 있는 옵션)와 시트 바닥 사이에 여백이 있어야 잘려 보이지 않는다.
    final Finder card = find.descendant(
      of: find.byKey(const Key('recordOptions')),
      matching: find.byType(InkWell),
    );
    expect(card, findsWidgets);
    expect(
      tester.getBottomRight(sheet).dy - tester.getBottomRight(card.last).dy,
      greaterThanOrEqualTo(16),
      reason: '옵션 카드가 시트 끝에 붙어 잘려 보인다',
    );
  });

  testWidgets('추가 메뉴는 두 갈래 모두 브랜드 파랑이다 (#1154)', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('recordAddButton')));
    await tester.pumpAndSettle();

    Color? iconColorOf(IconData icon) => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(const Key('recordOptions')),
            matching: find.byIcon(icon),
          ),
        )
        .color;

    // 이 시트는 "무엇을 기록할까" 를 고르는 자리라 색이 영역을 가르는 뜻으로
    // 읽히지 않는다 — 초록 하나만 남으면 그 카드가 다른 성격처럼 보인다.
    // (예전에는 식단 초록·운동 파랑이었다, #1060 → #1154)
    expect(iconColorOf(Icons.restaurant_rounded), OnCareBrand.member.primary);
    expect(iconColorOf(Icons.fitness_center_rounded), OnCareBrand.member.primary);
  });

  testWidgets('Enters the Home tab in English after demo', (tester) async {
    await pumpApp(tester, locale: const Locale('en'));
    // Bottom-nav labels match the React original.
    expect(find.text('Home'), findsAtLeastNWidgets(1));
    expect(find.text('Diet'), findsAtLeastNWidgets(1));
    expect(find.text('Exercise'), findsAtLeastNWidgets(1));
    expect(find.text('MY'), findsAtLeastNWidgets(1));
  });

  testWidgets('member coaching data refreshes on branch entry and app resume', (
    tester,
  ) async {
    final repository = _CountingMemberCoachRepository();
    await pumpApp(
      tester,
      locale: const Locale('ko'),
      memberCoachRepository: repository,
    );
    final int initialSessionLoads = repository.sessionLoads;

    await tester.tap(find.text('운동').last);
    await tester.pumpAndSettle();

    expect(repository.routineLoads, greaterThan(0));
    expect(repository.sessionLoads, greaterThan(initialSessionLoads));
    final int beforeResume = repository.sessionLoads;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(repository.sessionLoads, greaterThan(beforeResume));
  });

  testWidgets('record sheet has no fixed bottom gap without a system inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester, locale: const Locale('ko'));

    final bottomSpacing = await openRecordSheetAndMeasureBottomSpacing(tester);

    // 인셋이 없으면 시트 안쪽 여백만 남는다(#1690 바텀시트 안쪽 20).
    expect(bottomSpacing, OnCareSpacing.sheetPadding);
  });

  testWidgets('record sheet keeps only the required system inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    await pumpApp(tester, locale: const Locale('ko'));

    final bottomSpacing = await openRecordSheetAndMeasureBottomSpacing(tester);

    // 홈 인디케이터 인셋만큼 더 띄워 카드가 가리지 않는다(#1154).
    expect(bottomSpacing, OnCareSpacing.sheetPadding + 34);
  });

  testWidgets('diet add opens as a content-sized sheet with a bottom gap', (
    tester,
  ) async {
    await pumpApp(tester, locale: const Locale('ko'));
    await tester.tap(find.byKey(const Key('recordAddButton')));
    await tester.pumpAndSettle();

    final dietOption = find.descendant(
      of: find.byKey(const Key('recordOptions')),
      matching: find.text('식단'),
    );
    await tester.tap(dietOption);
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('dietAddSheet'));
    final options = find.byKey(const Key('dietAddOptions'));
    expect(sheet, findsOneWidget);
    expect(tester.getTopLeft(sheet).dy, greaterThan(0));
    final logicalHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getBottomRight(sheet).dy, logicalHeight);
    // 마지막 카드가 화면 끝(홈 인디케이터)에 붙어 잘려 보이지 않도록
    // 시트 자체가 아래 여백을 갖는다 — 시스템 인셋이 없는 기기에서도.
    expect(
      tester.getBottomRight(sheet).dy - tester.getBottomRight(options).dy,
      20,
    );
    expect(find.byKey(const Key('recordAddSheet')), findsNothing);
  });

  testWidgets('exercise add has no fixed bottom gap without a system inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester, locale: const Locale('ko'));
    await openExerciseAddSheet(tester);

    // 시트 하단은 저장 버튼 아래 규격 안쪽 여백(sheetPadding 20)뿐이다(#1701).
    expect(
      bottomSpacingBetween(tester, 'exerciseAddSheet', 'exerciseSaveButton'),
      20,
    );
  });

  testWidgets('exercise add keeps only the required system inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    await pumpApp(tester, locale: const Locale('ko'));
    await openExerciseAddSheet(tester);

    // 규격 안쪽 여백(20)에 시스템 인셋(34)만 더해진다(#1701).
    expect(
      bottomSpacingBetween(tester, 'exerciseAddSheet', 'exerciseSaveButton'),
      20 + 34,
    );
  });

  testWidgets('coaching sheet has no fixed bottom gap without a system inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester, locale: const Locale('ko'));
    // 플로팅 버튼을 감춘 뒤(#862) 같은 시트를 여는 자리는 홈의 AI 조언 배너다.
    await tester.tap(
      find.byKey(const ValueKey<String>('home-coaching-banner')),
    );
    await tester.pumpAndSettle();

    // 하단 버튼 아래 여백은 시트 안쪽 여백(AppSheet footer)만 둔다(#1690).
    expect(
      bottomSpacingBetween(tester, 'coachingSheet', 'coachingSheetCta'),
      OnCareSpacing.sheetPadding,
    );
  });

  testWidgets('coaching sheet keeps only the required system inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    await pumpApp(tester, locale: const Locale('ko'));
    // 플로팅 버튼을 감춘 뒤(#862) 같은 시트를 여는 자리는 홈의 AI 조언 배너다.
    await tester.tap(
      find.byKey(const ValueKey<String>('home-coaching-banner')),
    );
    await tester.pumpAndSettle();

    expect(
      bottomSpacingBetween(tester, 'coachingSheet', 'coachingSheetCta'),
      OnCareSpacing.sheetPadding + 34,
    );
  });

  testWidgets('coaching sheet keeps the CTA off the bottom edge (#1180)', (
    tester,
  ) async {
    // 홈 인디케이터가 없는 기기·창에서는 SafeArea 가 밀어 주는 것이 없어,
    // 버튼이 시트 끝에 붙어 잘려 보였다. 여백은 시트가 스스로 둔다.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester, locale: const Locale('ko'));
    await tester.tap(
      find.byKey(const ValueKey<String>('home-coaching-banner')),
    );
    await tester.pumpAndSettle();

    final double sheetBottom = tester
        .getBottomRight(find.byKey(const Key('coachingSheet')))
        .dy;
    final double buttonBottom = tester
        .getBottomRight(
          find.descendant(
            of: find.byKey(const Key('coachingSheetCta')),
            matching: find.byType(AppButton),
          ),
        )
        .dy;
    expect(sheetBottom - buttonBottom, greaterThanOrEqualTo(16));
  });

  testWidgets('header notification opens the existing full page', (
    tester,
  ) async {
    await pumpApp(tester, locale: const Locale('ko'));

    await tester.tap(find.byIcon(Icons.notifications_none_rounded).first);
    await tester.pumpAndSettle();

    final page = find.byKey(const Key('notificationPage'));
    expect(page, findsOneWidget);
    expect(tester.getTopLeft(page).dy, 0);
  });

  testWidgets('point benefits use a full-page URL route', (tester) async {
    await pumpApp(tester, locale: const Locale('ko'));
    await tester.tap(find.text('MY').first);
    await tester.pumpAndSettle();

    final banner = find.byKey(const Key('pointsBanner'));
    await tester.ensureVisible(banner);

    // 포인트 카드 화살표는 카드 안쪽 여백만큼 떨어진 오른쪽 끝에 선다.
    final chevron = find.descendant(
      of: banner,
      matching: find.byIcon(Icons.chevron_right_rounded),
    );
    expect(
      tester.getTopRight(chevron).dx,
      tester.getTopRight(banner).dx - OnCareSpacing.cardPadding,
    );

    await tester.tap(banner);
    await tester.pumpAndSettle();

    final page = find.byKey(const Key('pointsBenefitsPage'));
    expect(page, findsOneWidget);
    expect(
      appRouter(tester).routeInformationProvider.value.uri.path,
      AppRoutes.myPoints,
    );
  });

  testWidgets('MY settings use full-page URL routes', (tester) async {
    await pumpApp(tester, locale: const Locale('ko'));
    appRouter(tester).go(AppRoutes.mySettingsPath('support'));
    await tester.pumpAndSettle();

    final page = find.byKey(const Key('mySettingsPage'));
    expect(page, findsOneWidget);
    expect(
      appRouter(tester).routeInformationProvider.value.uri.path,
      AppRoutes.mySettingsPath('support'),
    );
  });

  testWidgets('diet detail URL restores the full-page editor', (tester) async {
    await pumpApp(tester, locale: const Locale('ko'));
    appRouter(tester).go(AppRoutes.dietEntryDetailPath('mock-breakfast'));
    await tester.pumpAndSettle();

    final page = find.byKey(const Key('mealDetailPage'));
    expect(page, findsOneWidget);
    expect(
      appRouter(tester).routeInformationProvider.value.uri.path,
      AppRoutes.dietEntryDetailPath('mock-breakfast'),
    );
  });

  testWidgets('Tapping a bottom-nav destination switches branch', (
    tester,
  ) async {
    await pumpApp(tester, locale: const Locale('en'));

    // OncareHeader is a Material+Container (not an AppBar), so we
    // settle for `find.text(...)` finders here.
    await tester.tap(find.text('Diet').first);
    await tester.pumpAndSettle();
    expect(find.text('Diet'), findsAtLeastNWidgets(1));

    final exerciseDestination = find.byKey(const ValueKey<String>('nav-exercise'));
    await tester.tap(exerciseDestination);
    await tester.pumpAndSettle();
    expect(find.text('Exercise'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('MY').first);
    await tester.pumpAndSettle();
    expect(find.text('MY'), findsAtLeastNWidgets(1));
  });

  testWidgets('전체 기간 운동 현황은 스크롤 막대 그래프다 (#1018)', (tester) async {
    await pumpApp(tester, locale: const Locale('en'));

    final exerciseDestination = find.byKey(const ValueKey<String>('nav-exercise'));
    await tester.tap(exerciseDestination);
    await tester.pumpAndSettle();
    final monthlyToggle = find.text('All');
    await tester.ensureVisible(monthlyToggle);
    await tester.tap(monthlyToggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exerciseAllPeriodChart')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Korean locale localises the bottom-nav labels', (tester) async {
    await pumpApp(tester, locale: const Locale('ko'));
    await tester.pumpAndSettle();
    expect(find.text('홈'), findsAtLeastNWidgets(1));
    expect(find.text('식단'), findsAtLeastNWidgets(1));
    expect(find.text('운동'), findsAtLeastNWidgets(1));
    expect(find.text('MY'), findsAtLeastNWidgets(1));
  });

  test('ARB resources expose nav strings for ko + en', () {
    // sanity: 'supportedLocales' is the canonical set.
    expect(AppLocalizations.supportedLocales, contains(const Locale('en')));
    expect(AppLocalizations.supportedLocales, contains(const Locale('ko')));
  });

  test('English PT set count uses the correct singular and plural forms', () {
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    expect(en.exProgramSets(1), '1 set');
    expect(en.exProgramSets(2), '2 sets');
  });

  testWidgets('English locale localises the Home AI advice (리뷰 #292)', (
    tester,
  ) async {
    await pumpApp(tester, locale: const Locale('en'));
    // 회귀: 예전엔 '오늘의 AI 통합 조언' 배너가 한국어로 하드코딩돼 영어 로케일에서도
    // 한국어로 노출됐다. 이제 ARB 를 거쳐 영어로 나오고 한국어 리터럴은 없어야 한다.
    expect(find.text("Today's combined AI advice"), findsAtLeastNWidgets(1));
    expect(
      find.text(lookupAppLocalizations(const Locale('en')).homeAiAdviceBody),
      findsOneWidget,
    );
    expect(find.text('오늘의 AI 통합 조언'), findsNothing);
    expect(find.text('나트륨 초과'), findsNothing);
  });

  test(
    'coaching/advice strings are localised — en English, ko Korean (리뷰 #292)',
    () {
      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
      final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
      final RegExp hangul = RegExp('[가-힣]');

      // 코드에 하드코딩돼 있던 문구들이 이제 로케일별 ARB 로 분리됐다.
      expect(en.coachCardDietTitle, 'Great breakfast — watch lunch sodium');
      expect(ko.coachCardDietTitle, '아침 식단 훌륭, 점심 나트륨 주의');
      expect(en.coachCardExerciseTitle, 'PT session 12 done');
      expect(en.homeAiAdviceTitle, "Today's combined AI advice");
      expect(ko.homeAiAdviceTitle, '오늘의 AI 통합 조언');
      expect(en.homeSodiumExceededBadge, 'Sodium over');
      expect(ko.homeSodiumExceededBadge, '나트륨 초과');

      // 영어 리소스에 한글이 남아 있지 않아야 한다.
      expect(hangul.hasMatch(en.coachCardDietBody), isFalse);
      expect(hangul.hasMatch(en.coachCardExerciseBody), isFalse);
      expect(hangul.hasMatch(en.homeAiAdviceBody), isFalse);
    },
  );

  test('운동 탭 기간 토글·도넛 라벨이 로케일을 따른다 (#297)', () {
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    final RegExp hangul = RegExp('[가-힣]');

    // 회귀: '이번 달'만 하드코딩돼 있어 영어 로케일에서 "Today / This week /
    // 이번 달" 처럼 한 토글 안에 두 언어가 섞였다.
    expect(en.exPeriodAll, 'All');
    expect(ko.exPeriodAll, '전체');
    for (final String s in <String>[
      en.exToday,
      en.exThisWeek,
      en.exPeriodAll,
    ]) {
      expect(hangul.hasMatch(s), isFalse);
    }

    // 도넛 세그먼트도 같은 화면에서 한국어로 굳어 있었다.
    expect(en.exTypeCardio, 'Cardio');
    expect(en.exTypeStrength, 'Strength');
    expect(en.exTypeFlexibility, 'Stretching');
    expect(ko.exTypeCardio, '유산소');
  });

  test('식단·운동 날짜별 빈 상태가 로케일을 따른다 (#297)', () {
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

    expect(ko.otherDateEmpty(ko.pageDietTitle), '선택한 날짜에 기록된 식단이 없어요.');
    expect(ko.otherDateEmpty(ko.pageExerciseTitle), '선택한 날짜에 기록된 운동이 없어요.');
    expect(
      en.otherDateEmpty(en.pageDietTitle),
      'No Diet records for the selected date.',
    );
    expect(
      en.otherDateEmpty(en.pageExerciseTitle),
      'No Exercise records for the selected date.',
    );
    expect(
      RegExp('[가-힣]').hasMatch(en.otherDateEmpty(en.pageDietTitle)),
      isFalse,
    );
  });

  test('운동 탭 UI 골격 문구가 로케일을 따른다 (#367)', () {
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    final RegExp hangul = RegExp('[가-힣]');

    // 회귀: 운동 현황 카드·도넛·툴팁의 골격 문구가 한국어로 굳어 있어
    // 영어 로케일에서 지표 라벨만 영어로 나왔다.
    expect(en.exTodayTotalTime, "Today's total time");
    expect(ko.exTodayTotalTime, '오늘 총 운동 시간');
    expect(en.exRest, 'Rest');
    expect(ko.exRest, '휴식');
    expect(en.exAiRecommendedExercise, 'AI recommended exercise');
    expect(ko.exAiRecommendedExercise, 'AI 추천 운동');

    // 이번 달 막대 차트의 주차 라벨.
    expect(en.exWeekNumber(3), 'Week 3');
    expect(ko.exWeekNumber(3), '3주');

    for (final String s in <String>[
      en.exTodayTotalTime,
      en.exRest,
      en.exAiRecommendedExercise,
      en.exWeekNumber(1),
      en.unitMinutes,
      en.unitMinutesValue(8),
    ]) {
      expect(hangul.hasMatch(s), isFalse, reason: s);
    }
  });

  test('분 단위는 기존 공용 키를 재사용한다 (#367)', () {
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

    // 신규 키를 만들지 않고 unitMinutes/unitMinutesValue 를 그대로 쓴다.
    expect(ko.unitMinutes, '분');
    expect(en.unitMinutes, 'min');
    expect(ko.unitMinutesValue(8), '8분');
    expect(en.unitMinutesValue(8), '8 min');
  });

  test('운동 탭 하위 위젯 문구가 로케일을 따른다 (#381)', () {
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    final RegExp hangul = RegExp('[가-힣]');

    // 신규 키 5개 — 나머지 17곳은 기존 키를 재사용했다.
    // '운동 유형' 은 신규 키를 만들지 않고 기존 exExerciseType('운동 종류')으로
    // 합쳤다. exercise_flows 가 같은 개념에 이미 그 키를 쓰고 있어, 두 시트가
    // 서로 다른 말을 하던 것이 정리된다.
    expect(en.exExerciseType, 'Exercise Type');
    expect(ko.exExerciseType, '운동 종류');
    expect(en.exExerciseContent, 'What you did');
    expect(en.exViewDetail, 'View details');
    expect(en.exRegister, 'Register');
    expect(en.actionClose, 'Close');
    expect(en.exGymRegistered('Gangnam Gym'), 'Registered Gangnam Gym');
    expect(ko.exGymRegistered('강남 짐'), '강남 짐을(를) 등록했어요');

    for (final String s in <String>[
      en.exExerciseType,
      en.exExerciseContent,
      en.exViewDetail,
      en.exRegister,
      en.actionClose,
      en.exGymRegistered('Gym'),
      // 재사용한 기존 키도 영문 값이 멀쩡한지 함께 본다.
      en.exStatTime,
      en.exExerciseDuration,
      en.exEnterDuration,
      en.dietDeleteFailed,
      en.dietSaveFailed,
      en.exExerciseLog,
      en.exGymTab,
      en.exTypeOtherChip,
    ]) {
      expect(hangul.hasMatch(s), isFalse, reason: s);
    }
  });

  // ───────────────────────────── 하단 탭 재진입 임시 UI 상태 초기화 (#861) ──

  testWidgets('식단 탭 재진입 시 영양 요약이 오늘 기본값으로 복원된다 (#861)', (tester) async {
    await pumpApp(tester, locale: const Locale('ko'));

    await tester.tap(find.text('식단').first);
    await tester.pumpAndSettle();

    // 이번 주로 바꾸면 하루 요약 대신 기간 뷰가 보인다.
    await tester.tap(dietPeriodTab(DietPeriodTab.week));
    await tester.pumpAndSettle();
    expect(find.byType(DietPeriodView), findsOneWidget);
    expect(find.byKey(const Key('nutrition-summary-card')), findsNothing);

    // 다른 탭으로 이동했다가 식단 탭에 다시 들어온다.
    await tester.tap(find.text('MY').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('식단').first);
    await tester.pumpAndSettle();

    // 오늘 기본값으로 복원 — 기간 뷰 대신 하루 요약 카드가 다시 보인다.
    expect(find.byType(DietPeriodView), findsNothing);
    expect(find.byKey(const Key('nutrition-summary-card')), findsOneWidget);
  });

  testWidgets('식단 탭 재진입 후에도 실제 식단 기록은 유지된다 (#861)', (tester) async {
    await pumpApp(tester, locale: const Locale('ko'));

    await tester.tap(find.text('식단').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mealCard-mock-breakfast')), findsOneWidget);

    await tester.tap(dietPeriodTab(DietPeriodTab.week));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MY').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('식단').first);
    await tester.pumpAndSettle();

    // 임시 UI 상태(기간 토글)는 초기화돼도 실제 식단 기록은 그대로 남는다.
    expect(find.byKey(const Key('mealCard-mock-breakfast')), findsOneWidget);
  });

  testWidgets('운동 탭 재진입 시 운동 현황 기간 토글이 기본값으로 복원된다 (#861)', (tester) async {
    await pumpApp(tester, locale: const Locale('ko'));

    final exerciseDestination = find.byKey(const ValueKey<String>('nav-exercise'));
    await tester.tap(exerciseDestination);
    await tester.pumpAndSettle();

    // 전체로 바꾼다 — 전체 뷰에만 붙는 키로 전환 여부를 확인한다.
    final monthlyToggle = find.text('전체');
    await tester.ensureVisible(monthlyToggle);
    await tester.tap(monthlyToggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exerciseAllPeriodChart')), findsOneWidget);

    await tester.tap(find.text('MY').first);
    await tester.pumpAndSettle();
    await tester.tap(exerciseDestination);
    await tester.pumpAndSettle();

    // 기본값(이번 주)으로 복원 — 전체 전용 차트가 더 이상 보이지 않는다.
    expect(find.byKey(const Key('exerciseAllPeriodChart')), findsNothing);
  });

  testWidgets('운동 탭 재진입 후에도 저장된 운동 기록·트레이너 프로그램은 유지된다 (#861)', (tester) async {
    final repository = _CountingMemberCoachRepository();
    await pumpApp(
      tester,
      locale: const Locale('ko'),
      memberCoachRepository: repository,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OncareApp)),
    );

    final exerciseDestination = find.byKey(const ValueKey<String>('nav-exercise'));
    await tester.tap(exerciseDestination);
    await tester.pumpAndSettle();

    final beforeWeek = await container.read(exerciseWeekProvider.future);
    final beforeRoutines = await container.read(coachRoutinesProvider.future);

    await tester.tap(find.text('MY').first);
    await tester.pumpAndSettle();
    await tester.tap(exerciseDestination);
    await tester.pumpAndSettle();

    final afterWeek = await container.read(exerciseWeekProvider.future);
    final afterRoutines = await container.read(coachRoutinesProvider.future);

    // 탭 재진입으로 임시 UI 상태만 초기화될 뿐, 저장된 운동 기록과 트레이너
    // 프로그램(AI 추천 루틴) 데이터는 그대로다.
    expect(afterWeek.sessions.length, beforeWeek.sessions.length);
    expect(
      afterRoutines.map((CoachRoutine r) => r.id),
      beforeRoutines.map((CoachRoutine r) => r.id),
    );
  });

  testWidgets('홈 탭 재진입 시 식단·영양 카드 선택 지표가 기본값(칼로리)으로 복원된다 (#861)', (
    tester,
  ) async {
    await pumpApp(tester, locale: const Locale('ko'));
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

    // 홈이 첫 화면이다 — 나트륨 카드를 선택한다.
    await tester.tap(find.text(ko.dietSodium).first);
    await tester.pumpAndSettle();
    expect(find.text(ko.homeWeeklyMetricTrend(ko.dietSodium)), findsOneWidget);

    await tester.tap(find.text('식단').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('홈').first);
    await tester.pumpAndSettle();

    // 기본값(칼로리)으로 복원된다.
    expect(
      find.text(ko.homeWeeklyMetricTrend(ko.dashboardMetricCalories)),
      findsOneWidget,
    );
  });

  testWidgets('여러 번 탭을 오가도 식단 탭 재진입 정책이 일관되게 동작한다 (#861)', (tester) async {
    await pumpApp(tester, locale: const Locale('ko'));

    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('식단').first);
      await tester.pumpAndSettle();
      await tester.tap(dietPeriodTab(DietPeriodTab.week));
      await tester.pumpAndSettle();
      expect(find.byType(DietPeriodView), findsOneWidget);

      await tester.tap(find.text('MY').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('식단').first);
      await tester.pumpAndSettle();
      expect(find.byType(DietPeriodView), findsNothing);
    }
  });

  testWidgets('이미 보고 있는 탭을 다시 눌러도 임시 UI 상태는 초기화되지 않는다 (#861)', (tester) async {
    await pumpApp(tester, locale: const Locale('ko'));

    await tester.tap(find.text('식단').first);
    await tester.pumpAndSettle();
    await tester.tap(dietPeriodTab(DietPeriodTab.week));
    await tester.pumpAndSettle();
    expect(find.byType(DietPeriodView), findsOneWidget);

    // 다른 탭으로 이동하지 않고 이미 보고 있는 식단 탭을 다시 누른다.
    await tester.tap(find.text('식단').first);
    await tester.pumpAndSettle();

    // 탭을 떠난 적이 없으므로 선택해 둔 '이번 주' 가 그대로 남는다.
    expect(find.byType(DietPeriodView), findsOneWidget);
  });

  testWidgets('resetExerciseTransientUiState 는 헬스장 예약 카드 선택도 함께 해제한다 (#861)', (
    tester,
  ) async {
    // 예약 카드는 실제 트레이너·슬롯 데이터 없이 provider 값만으로 검증한다 —
    // MainShell 이 탭 재진입 시 이 함수를 호출한다는 것은 다른 테스트가 이미
    // 증명했고(운동 현황 기간 토글 복원 테스트), 여기서는 그 함수가 예약 카드
    // 선택까지 정말로 지우는지만 좁혀서 본다.
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    capturedRef.read(exerciseSelectedReservationSlotProvider.notifier).state =
        'slot-1';
    capturedRef.read(exerciseActivityPeriodProvider.notifier).state = 2;

    resetExerciseTransientUiState(capturedRef);

    expect(capturedRef.read(exerciseSelectedReservationSlotProvider), isNull);
    expect(
      capturedRef.read(exerciseActivityPeriodProvider),
      kExerciseActivityPeriodDefault,
    );
  });
}
