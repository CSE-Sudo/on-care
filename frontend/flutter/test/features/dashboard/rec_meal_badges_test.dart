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
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
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
  weekScore: 80,
  weekScoreDelta: 5,
  sodiumWarning: '',
  exerciseFeedback: '',
);

Future<void> _pump(
  WidgetTester tester, {
  MemberCoach? coach,
  MealRecommendations? recs,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachProvider.overrideWith((Ref ref) async => coach),
        dashboardSummaryProvider.overrideWith((Ref ref) async => _summary),
        if (recs != null)
          dietRecommendationsProvider.overrideWith((Ref ref) async => recs),
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

  /// 설명이 한 줄인 카드와 두 줄인 카드를 섞어 놓고 배지 높이를 견준다.
  ///
  /// 배지가 설명 **아래**에 있으면 이 둘의 세로 위치가 어긋난다. 카드 높이는
  /// `IntrinsicHeight` 가 가장 높은 것에 맞춰 주므로 카드 테두리는 가지런한데
  /// 안의 배지만 제각각이었다.
  testWidgets('설명 줄 수가 달라도 배지는 같은 높이에 놓인다', (WidgetTester tester) async {
    await _pump(
      tester,
      recs: const MealRecommendations(
        items: <MealRecommendation>[
          MealRecommendation(
            key: 'chicken_salad',
            reasonKey: 'sodium',
            reasonText: '짧은 이유',
          ),
          MealRecommendation(
            key: 'brown_rice_box',
            reasonKey: 'glucose',
            reasonText: '두 줄을 채울 만큼 긴 개인화 문구를 서버가 보내 온 경우입니다',
          ),
          MealRecommendation(
            key: 'salmon',
            reasonKey: 'omega',
            reasonText: '짧은 이유',
          ),
        ],
      ),
    );

    final List<double> tops = tester
        .widgetList<Text>(find.byKey(const Key('rec-meal-tag')))
        .map((Text t) => tester.getTopLeft(find.byWidget(t)).dy)
        .toList();
    expect(tops.length, greaterThan(1));
    for (final double top in tops) {
      expect(top, moreOrLessEquals(tops.first, epsilon: 0.5));
    }
  });

  /// 배지는 요리 이름보다 위다 — 사진 바로 아래 자리라는 뜻이다.
  testWidgets('배지가 요리 이름보다 위에 있다', (WidgetTester tester) async {
    await _pump(tester, coach: _coach);

    final double badge = tester
        .getTopLeft(find.byKey(const Key('rec-meal-tag')).first)
        .dy;
    final double name = tester
        .getTopLeft(
          find.text(
            AppLocalizations.of(
              tester.element(find.byType(DashboardContent)),
            ).homeMealChickenSalad,
          ),
        )
        .dy;
    expect(badge, lessThan(name));
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
