/// 홈 카드의 그래프 진입 애니메이션 (#653).
///
/// 그래프는 `CustomPaint` 라 위젯 트리만 봐서는 모양을 알 수 없다. painter 를
/// 직접 래스터화해 칠해진 픽셀이 늘어나는 것으로 "자라 오른다"를, `shouldRepaint`
/// 가 다시 거짓이 되는 것으로 "그리고 멈춘다"를 못박는다.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
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
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// [painter] 를 [size] 로 그려 **거의 불투명하고 트랙보다 진한**(RGB 합 600
/// 미만) 픽셀 수를 센다. 옅은 불투명 트랙은 빠지고 자라는 호만 남는다.
Future<int> _strongInk(CustomPainter painter, Size size) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final ui.Image image = await recorder.endRecording().toImage(
    size.width.ceil(),
    size.height.ceil(),
  );
  final ByteData pixels = (await image.toByteData())!;
  image.dispose();
  int ink = 0;
  for (int i = 0; i < pixels.lengthInBytes; i += 4) {
    if (pixels.getUint8(i + 3) < 200) continue;
    final int sum =
        pixels.getUint8(i) + pixels.getUint8(i + 1) + pixels.getUint8(i + 2);
    if (sum < 600) ink++;
  }
  return ink;
}

void main() {
  const DashboardSummary summary = DashboardSummary(
    indicators: <HealthIndicator>[
      HealthIndicator(label: '칼로리', current: 1860, max: 2000, unit: 'kcal'),
      HealthIndicator(label: '나트륨', current: 2329, max: 2000, unit: 'mg'),
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
    todaySchedule: <ScheduleItem>[],
    weekScore: 85,
    weekScoreDelta: 12,
    sodiumWarning: null,
  );

  /// 홈 운동 카드는 주간 조회가 실패하면 카드 대신 실패를 그린다(#962).
  /// 예전에는 그 자리에 데모 상수가 들어가 provider 가 터져도 차트가 보였다 —
  /// 그래서 이 테스트들이 통과했다. 그림을 보는 테스트이니 값을 넣어 준다.
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

  /// 홈을 띄우되 `pumpAndSettle` 은 하지 않는다 — 진입 애니메이션이 도는 중을
  /// 봐야 하므로, 데이터 로딩만 끝나도록 한 프레임씩 진행한다.
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          accountRepositoryProvider.overrideWithValue(
            MockAccountRepository(
              profile: const UserProfile(
                id: 'member',
                name: '테스트',
                email: 'member@example.com',
              ),
            ),
          ),
          dashboardSummaryProvider.overrideWith((ref) async => summary),
          memberCoachRepositoryProvider.overrideWithValue(
            MockMemberCoachRepository(),
          ),
          exerciseWeekViewProvider.overrideWithValue(exerciseWeek),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: DashboardContent()),
        ),
      ),
    );
    // 요약 provider 가 풀리고 카드가 붙을 때까지만.
    await tester.pump();
    await tester.pump();
  }

  // 홈 운동 카드는 이제 운동 탭 `이번 주` 카드를 그대로 쓴다 (#1183) —
  // 움직이는 것은 주간 소모 막대가 아니라 유형별 목표 링 셋이다.
  final Finder exerciseRings = find.byKey(
    const ValueKey<String>('dashboard-exercise-week'),
  );
  final Finder nutritionChart = find.byKey(
    const ValueKey<String>('dashboard-nutrition-chart'),
  );

  CustomPainter painterIn(WidgetTester tester, Finder scope) {
    return tester
        .widget<CustomPaint>(
          find.descendant(of: scope, matching: find.byType(CustomPaint)).first,
        )
        .painter!;
  }

  testWidgets('주간 운동 링은 12시에서 자라 돈다', (WidgetTester tester) async {
    await pumpHome(tester);
    final Size size = tester.getSize(exerciseRings);

    final CustomPainter atStart = painterIn(tester, exerciseRings);
    await tester.pump(const Duration(milliseconds: 350));
    final CustomPainter midway = painterIn(tester, exerciseRings);
    await tester.pumpAndSettle();
    final CustomPainter settled = painterIn(tester, exerciseRings);

    // 링 트랙이 불투명 토큰 색이라(#1701) 칠해진 픽셀 수는 처음부터 같다 —
    // 트랙보다 진한 호만 세어 자라는 것을 잰다.
    final List<int> ink = (await tester.runAsync(() async {
      return <int>[
        await _strongInk(atStart, size),
        await _strongInk(midway, size),
        await _strongInk(settled, size),
      ];
    }))!;

    expect(ink[1], greaterThan(ink[0]), reason: '링이 자라지 않았다');
    expect(ink[2], greaterThan(ink[1]), reason: '링이 끝까지 돌지 않았다');
  });

  testWidgets('주간 운동 링은 진입 애니메이션 동안 계속 다시 그려진다', (WidgetTester tester) async {
    await pumpHome(tester);
    expect(exerciseRings, findsOneWidget);

    final CustomPainter atStart = painterIn(tester, exerciseRings);
    await tester.pump(const Duration(milliseconds: 300));
    final CustomPainter midway = painterIn(tester, exerciseRings);

    // 진행도가 올라갔다 = 원호가 더 돌았다.
    expect(midway.shouldRepaint(atStart), isTrue);

    await tester.pumpAndSettle();
    final CustomPainter settled = painterIn(tester, exerciseRings);
    expect(settled.shouldRepaint(midway), isTrue);

    // 끝난 뒤에는 더 이상 움직이지 않는다 — 계속 도는 애니메이션이 아니다.
    await tester.pump(const Duration(milliseconds: 300));
    expect(painterIn(tester, exerciseRings).shouldRepaint(settled), isFalse);
  });

  testWidgets('영양 추이 그래프는 한 번 그려지고 멈춘다 (#1879)', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester);
    await tester.pumpAndSettle();

    // 그래프가 칼로리 하나로 고정되면서 다시 재생할 지표 전환이 없다 —
    // 지표 칸은 읽는 것이지 누르는 것이 아니다.
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(DashboardContent)),
    );
    final String title = l.homeWeeklyMetricTrend(l.dashboardMetricCalories);
    expect(find.text(title), findsOneWidget);

    await tester.tap(find.text(l.homeMacroProtein));
    await tester.pumpAndSettle();
    expect(
      find.text(title),
      findsOneWidget,
      reason: '지표 칸을 눌렀더니 그래프가 그 지표로 바뀌었다',
    );

    // 다 그린 뒤에는 더 이상 움직이지 않는다.
    final CustomPainter settled = painterIn(tester, nutritionChart);
    await tester.pump(const Duration(milliseconds: 300));
    expect(painterIn(tester, nutritionChart).shouldRepaint(settled), isFalse);
  });

  testWidgets('애니메이션이 꺼진 환경에서는 첫 프레임부터 최종 상태로 그린다', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          accountRepositoryProvider.overrideWithValue(
            MockAccountRepository(
              profile: const UserProfile(
                id: 'member',
                name: '테스트',
                email: 'member@example.com',
              ),
            ),
          ),
          dashboardSummaryProvider.overrideWith((ref) async => summary),
          memberCoachRepositoryProvider.overrideWithValue(
            MockMemberCoachRepository(),
          ),
          exerciseWeekViewProvider.overrideWithValue(exerciseWeek),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(body: DashboardContent()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final CustomPainter first = painterIn(tester, exerciseRings);
    await tester.pump(const Duration(milliseconds: 300));

    // 진행도가 처음부터 1 이라 다시 그릴 일이 없다.
    expect(painterIn(tester, exerciseRings).shouldRepaint(first), isFalse);
    expect(
      find.descendant(
        of: exerciseRings,
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsNothing,
    );
  });
}
