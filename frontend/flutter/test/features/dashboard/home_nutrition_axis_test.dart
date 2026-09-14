/// 홈 "주간 추이" 그래프의 세로축.
///
/// 눈금 격자와 눈금 라벨은 걷어냈다 — 점마다 값이 붙어 있어 중복이었다. 대신
/// 목표선 하나와 그 라벨만 남는다(#756). 그래서 이 파일이 지키는 것은 둘이다.
///
///  * 축 칸에 글자가 **하나뿐**이고 그게 목표선 라벨이다. 눈금 라벨이 되살아나면
///    여기서 먼저 깨진다.
///  * 세 지표 모두 축 바닥이 0 이다 — 한 카드에서 탭으로 바뀌는데 바닥이 지표마다
///    다르면 같은 그래프를 다른 기준으로 읽게 된다(#548). 눈금을 그리지 않게 된
///    뒤에도 `ticks` 가 스케일 입력으로 남아 이 성질을 잡는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/dashboard/presentation/widgets/dashboard_content.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/metric_trend_chart.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  const DashboardSummary summary = DashboardSummary(
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
    todaySchedule: <ScheduleItem>[],
    weekScore: 85,
    weekScoreDelta: 12,
    sodiumWarning: null,
  );

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
    await tester.pumpAndSettle();
  }

  /// 세로축 라벨 칸 — 두 앱 공용 [ChartGoalAxis] 하나뿐이다(#1702).
  final Finder axis = find.descendant(
    of: find.byKey(const ValueKey<String>('dashboard-nutrition-chart')),
    matching: find.byType(ChartGoalAxis),
  );

  /// 축 칸의 글자를 위에서 아래 순서로 (문구, 사각형) 으로 읽는다.
  List<({String text, Rect rect})> axisLabels(WidgetTester tester) {
    final Finder slots = find.descendant(
      of: axis,
      // 칸 높이는 글씨 배율을 따라 달라진다 — 크기가 아니라 이름으로 찾는다.
      // (#1004)
      matching: find.byKey(chartGoalLabelKey),
    );
    return <({String text, Rect rect})>[
      for (final Element e in slots.evaluate())
        (
          text: (find
                      .descendant(of: find.byWidget(e.widget), matching: find.byType(Text))
                      .evaluate()
                      .single
                      .widget
                  as Text)
              .data!,
          rect: tester.getRect(find.byWidget(e.widget)),
        ),
    ]..sort((a, b) => a.rect.top.compareTo(b.rect.top));
  }

  testWidgets('축 칸에는 목표선 라벨 하나만 있다', (WidgetTester tester) async {
    await pumpHome(tester);

    // 눈금 라벨(2,500 · 1,500 · 0)이 있던 자리다. 이제 목표 하나뿐이다.
    // 칸 폭(38)을 지키려고 두 줄로 접는다.
    expect(<String>[for (final label in axisLabels(tester)) label.text], <String>[
      '목표\n2,000',
    ]);
  });

  testWidgets('지표를 바꾸면 목표선 라벨의 수치가 따라간다', (WidgetTester tester) async {
    await pumpHome(tester);

    for (final (String tab, String goal) in <(String, String)>[
      ('칼로리', '목표\n2,000'),
      ('나트륨', '목표\n2,000'),
      ('당류', '목표\n50'),
    ]) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();

      final List<({String text, Rect rect})> labels = axisLabels(tester);
      expect(labels.length, 1, reason: '$tab 축에 글자가 하나가 아니다');
      expect(labels.single.text, goal);
    }
  });

  test('세 지표 모두 축 바닥이 0 이다 (#548)', () {
    // 눈금을 그리지 않게 된 뒤에도 `ticks` 는 스케일 입력으로 남는다. 지우면
    // 세 지표의 축이 서로 다르게 움직인다.
    for (final (String name, List<double> values, List<double> ticks, double goal)
        in <(String, List<double>, List<double>, double)>[
      ('칼로리', <double>[1860, 1700, 1990], <double>[0, 1500, 2500], 2000),
      ('나트륨', <double>[2329, 1800, 2100], <double>[0, 1750, 3500], 2000),
      ('당류', <double>[43, 31, 47], <double>[0, 25, 50], 50),
    ]) {
      final (double lo, _) = metricTrendScale(
        values: values,
        ticks: ticks,
        goal: goal,
      );
      expect(lo, 0, reason: '$name 축의 바닥이 0 이 아니다');
    }
  });
}
