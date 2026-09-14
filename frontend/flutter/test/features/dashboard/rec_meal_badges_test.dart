/// 추천 식단 카드의 배지 (#1056).
///
/// 배지 어휘는 여섯 가지로 고정한다 — `저GI` 처럼 이 앱이 다른 곳에서 쓰지
/// 않는 말이 섞이면, 같은 뜻을 화면마다 다른 말로 부르게 된다. 색도 하나다.
/// 요리마다 색이 달라지면 색이 영양 특성을 뜻하는지 요리 종류를 뜻하는지 알
/// 수 없다.
///
/// 출처 배지는 담당 트레이너가 있을 때만 첫 장에 붙는다. 담당이 없는 회원의
/// 화면에 `트레이너 추천` 이 뜨면 없는 사람의 추천이라고 말하는 셈이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/dashboard/presentation/widgets/dashboard_content.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const Set<String> _allowedTags = <String>{
  '저나트륨',
  '저칼로리',
  '저당류',
  '저탄수화물',
  '고단백질',
  '저지방',
};

const MemberCoach _coach = MemberCoach(
  trainerId: 't1',
  name: '김트레이너',
  specialty: '체형 교정',
  career: '7년',
  intro: '반갑습니다',
  gymName: '신촌점',
  goal: '체력 강화',
);

/// 홈 요약 — 추천 카드만 보면 되는 최소 형태.
const DashboardSummary _summary = DashboardSummary(
  indicators: <HealthIndicator>[
    HealthIndicator(label: '칼로리', current: 1860, max: 2000, unit: 'kcal'),
  ],
  macros: DietMacros(
    carbsG: 200,
    proteinG: 100,
    fatG: 60,
    carbsPct: 44,
    proteinPct: 24,
    fatPct: 32,
  ),
  dietEntries: 1,
  exerciseMinutes: 30,
  exerciseCalories: 300,
  exerciseCount: 1,
  todaySchedule: <ScheduleItem>[],
  weekScore: 80,
  weekScoreDelta: 5,
  sodiumWarning: '',
  exerciseFeedback: '',
);

Future<void> _pump(WidgetTester tester, {MemberCoach? coach}) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachProvider.overrideWith((Ref ref) async => coach),
        dashboardSummaryProvider.overrideWith((Ref ref) async => _summary),
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

void main() {
  testWidgets('특성 배지는 정해 둔 여섯 어휘만 쓴다', (WidgetTester tester) async {
    await _pump(tester, coach: _coach);

    final List<String> tags = tester
        .widgetList<Text>(find.byKey(const Key('rec-meal-tag')))
        .map((Text t) => t.data!)
        .toList();
    expect(tags, isNotEmpty);
    for (final String tag in tags) {
      expect(_allowedTags, contains(tag));
    }
  });

  testWidgets('특성 배지 색은 하나다', (WidgetTester tester) async {
    await _pump(tester, coach: _coach);

    final List<Color?> colors = tester
        .widgetList<Text>(find.byKey(const Key('rec-meal-tag')))
        .map((Text t) => t.style?.color)
        .toList();
    expect(colors, isNotEmpty);
    expect(colors.every((Color? c) => c == OnCareBrand.member.primary), isTrue);
  });

  testWidgets('담당이 있으면 첫 장만 트레이너 추천이다', (WidgetTester tester) async {
    await _pump(tester, coach: _coach);

    expect(find.text('트레이너 추천'), findsOneWidget);
    expect(find.text('AI 추천'), findsWidgets);
  });

  testWidgets('담당이 없으면 트레이너 추천 배지를 달지 않는다', (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text('트레이너 추천'), findsNothing);
    expect(find.text('AI 추천'), findsWidgets);
  });
}
