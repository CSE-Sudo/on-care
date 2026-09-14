/// 홈 탭의 그래프가 스크린리더에 무엇을 말하는지. (#972)
///
/// 두 그래프 모두 `CustomPaint` 라, 감싸는 위젯이 라벨을 주지 않으면 음성
/// 안내에서는 통째로 존재하지 않는 영역이 된다. 이 앱이 다루는 것이 혈압·혈당
/// 위험군의 건강 지표라, 숫자를 눈으로만 읽을 수 있게 두면 안 된다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
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

void main() {
  const DashboardSummary summary = DashboardSummary(
    indicators: <HealthIndicator>[
      HealthIndicator(label: '칼로리', current: 1860, max: 2000, unit: 'kcal'),
      HealthIndicator(label: '나트륨', current: 2329, max: 2000, unit: 'mg'),
      HealthIndicator(label: '당류', current: 43, max: 50, unit: 'g'),
    ],
    macros: DietMacros.zero(),
    dietEntries: 4,
    exerciseMinutes: 45,
    exerciseCalories: 520,
    exerciseCount: 4,
    todaySchedule: <ScheduleItem>[],
    weekScore: 85,
    weekScoreDelta: 12,
    sodiumWarning: null,
  );

  /// 한 주 통째로 기록이 없는 경우 — 요일 배열 자체가 비어 있다.
  const ExerciseWeek emptyWeek = ExerciseWeek(
    sessions: <ExerciseSession>[],
    dailyMinutes: <double>[],
    dayLabels: <String>[],
    totalMinutes: 0,
    totalCalories: 0,
    streakDays: 0,
    aiCoachMessage: '',
  );

  ExerciseWeek weekWith(List<double> daily) => ExerciseWeek(
    sessions: const <ExerciseSession>[],
    dailyMinutes: const <double>[0, 0, 0, 0, 0, 0, 0],
    dayLabels: const <String>['월', '화', '수', '목', '금', '토', '일'],
    totalMinutes: 45,
    totalCalories: 520,
    streakDays: 2,
    aiCoachMessage: '',
    dailyCalories: daily,
  );

  Future<void> pumpHome(
    WidgetTester tester,
    AsyncValue<ExerciseWeek> week, {
    Locale locale = const Locale('ko'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
          dashboardSummaryProvider.overrideWith((_) async => summary),
          memberCoachRepositoryProvider.overrideWithValue(
            MockMemberCoachRepository(),
          ),
          exerciseWeekViewProvider.overrideWithValue(week),
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
    await tester.pump();
    await tester.pump();
  }

  /// [needle] 을 담은 시맨틱 노드. 그래프가 카드 안 어디에 놓이든 잡힌다.
  Finder labelled(String needle) =>
      find.bySemanticsLabel(RegExp(RegExp.escape(needle)));

  testWidgets('이번 주 카드가 유형별 달성률을 말한다', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpHome(
      tester,
      AsyncValue<ExerciseWeek>.data(
        weekWith(const <double>[300, 0, 0, 0, 0, 0, 0]),
      ),
    );

    // 링 셋은 낱개로는 색 원일 뿐이라, 세 유형의 달성률을 한 덩어리로 읽는다.
    expect(
      labelled('유산소'),
      findsWidgets,
      reason: '이번 주 카드가 시맨틱 트리에 아무것도 남기지 않았습니다.',
    );
    expect(labelled('근력'), findsWidgets);
    expect(labelled('스트레칭'), findsWidgets);
    handle.dispose();
  });

  testWidgets('기록이 없는 주는 비어 있다고 말한다', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpHome(tester, const AsyncValue<ExerciseWeek>.data(emptyWeek));

    // 값 없이 조용한 카드는 "0kcal 태웠다" 와 구분되지 않는다.
    expect(labelled('기록이 없어요'), findsWidgets);
    handle.dispose();
  });

  testWidgets('영어 로케일에서는 비어 있다는 말도 영어다', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpHome(
      tester,
      const AsyncValue<ExerciseWeek>.data(emptyWeek),
      locale: const Locale('en'),
    );

    expect(labelled('No records yet'), findsWidgets);
    expect(labelled('기록이 없어요'), findsNothing);
    handle.dispose();
  });

  testWidgets('영양 추이 꺾은선도 요일별 값을 말한다', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpHome(
      tester,
      AsyncValue<ExerciseWeek>.data(
        weekWith(const <double>[300, 0, 0, 0, 0, 0, 0]),
      ),
    );

    // 홈의 영양 카드는 칼로리 지표로 열린다.
    expect(labelled('kcal'), findsWidgets);
    handle.dispose();
  });
}
