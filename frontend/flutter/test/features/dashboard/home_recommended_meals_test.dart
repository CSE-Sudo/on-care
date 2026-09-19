/// 홈 "AI 추천 식단" 카드 렌더링.
///
/// 이 섹션은 하드코딩에서 서버 추천(GET /diet/recommendations) 소비로 바뀌었다.
/// **목업/데모 모드 화면은 그 전과 완전히 같아야 한다**는 게 요구사항이라, 여기서
/// 다음을 못박는다:
///
/// 1. 목업 모드(기본 추천)에서 카드 5장이 기존 순서·문구 그대로 나온다.
/// 2. 응답을 기다리는 동안에도 스켈레톤 없이 같은 카드가 즉시 보인다(깜빡임 없음).
/// 3. 서버가 실패해도 화면이 유지된다.
/// 4. 실 모드에서 서버가 순서를 바꾸거나 개인화 문구를 주면 그대로 반영된다.
library;

import 'dart:async';

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
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  const DashboardSummary summary = DashboardSummary(
    indicators: <HealthIndicator>[
      HealthIndicator(label: '칼로리', current: 1860, max: 2000, unit: 'kcal'),
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
    weekScore: 85,
    weekScoreDelta: 12,
    sodiumWarning: null,
  );

  /// 데모(목업) 모드에서 지금 보이는 카드 — 순서까지 계약이다.
  const List<String> demoOrder = <String>[
    '닭가슴살 샐러드',
    '현미 도시락',
    '연어 구이 + 나물',
    '두부 채소 볶음',
    '나물 비빔밥',
  ];

  Future<void> pumpHome(
    WidgetTester tester, {
    required Future<MealRecommendations> Function() recommendations,
  }) async {
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
          dietRecommendationsProvider.overrideWith(
            (ref) => recommendations(),
          ),
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
  }

  /// 캐러셀에 **실제로 그려진 순서대로** 카드 제목을 읽는다.
  ///
  /// 이름 목록을 미리 정해 두고 존재 여부만 확인하면 순서가 바뀌어도 통과해 버린다
  /// (그렇게 짰다가 서버 정렬 반영을 검증하지 못했다). 가로 캐러셀이므로 각 제목
  /// 위젯의 x 좌표로 정렬해 화면 순서를 그대로 얻는다.
  List<String> renderedMealNames(WidgetTester tester) {
    final List<({String name, double dx})> found = <({String name, double dx})>[
      for (final String name in demoOrder)
        if (find.text(name).evaluate().isNotEmpty)
          (name: name, dx: tester.getTopLeft(find.text(name)).dx),
    ]..sort((({String name, double dx}) a, ({String name, double dx}) b) =>
        a.dx.compareTo(b.dx));
    return <String>[for (final entry in found) entry.name];
  }

  testWidgets('목업 모드 추천은 기존 카드·순서·문구 그대로다', (WidgetTester tester) async {
    await pumpHome(
      tester,
      recommendations: () async => MealRecommendations.fallback,
    );
    await tester.pumpAndSettle();

    expect(renderedMealNames(tester), demoOrder);
    // 기본 이유 문구도 그대로(서버 개인화 문구가 없을 때의 경로).
    expect(find.text('나트륨 조절에 좋아요'), findsOneWidget);
    expect(find.text('식이섬유가 풍부해요'), findsOneWidget);
  });

  testWidgets('응답 전에도 스켈레톤 없이 같은 카드가 즉시 보인다', (WidgetTester tester) async {
    // 영원히 끝나지 않는 요청 = 첫 프레임 상태. 여기서 카드가 비면 홈 진입 때
    // 화면이 깜빡인다.
    final Completer<MealRecommendations> pending =
        Completer<MealRecommendations>();
    await pumpHome(tester, recommendations: () => pending.future);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(renderedMealNames(tester), demoOrder);
  });

  testWidgets('추천 API 가 실패해도 홈 카드가 유지된다', (WidgetTester tester) async {
    await pumpHome(
      tester,
      recommendations: () async => throw Exception('recommendation down'),
    );
    await tester.pumpAndSettle();

    expect(renderedMealNames(tester), demoOrder);
  });

  testWidgets('실 모드: 서버가 준 순서와 개인화 문구가 반영된다', (WidgetTester tester) async {
    await pumpHome(
      tester,
      recommendations: () async => const MealRecommendations(
        personalized: true,
        daysWithData: 3,
        avgSodiumMg: 2400,
        sodiumLimitMg: 2000,
        items: <MealRecommendation>[
          MealRecommendation(
            key: 'salmon',
            reasonKey: 'omega',
            reasonText: '부족한 단백질을 채워요',
          ),
          MealRecommendation(key: 'chicken_salad', reasonKey: 'sodium'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final List<String> rendered = renderedMealNames(tester);
    // 서버가 준 두 장이 앞으로 오고, 나머지는 기본 순서로 채워져 5장을 유지한다.
    expect(rendered.length, demoOrder.length);
    expect(rendered.take(2), <String>['연어 구이 + 나물', '닭가슴살 샐러드']);
    // 기본 순서(닭가슴살 → 현미 → 연어)와 실제로 달라야 정렬이 반영된 것이다.
    expect(rendered, isNot(demoOrder));

    expect(find.text('부족한 단백질을 채워요'), findsOneWidget);
    // 개인화 문구가 없는 항목은 기본 l10n 문구를 쓴다.
    expect(find.text('나트륨 조절에 좋아요'), findsOneWidget);
  });

  testWidgets('개인화되면 근거가 화면에 드러난다', (WidgetTester tester) async {
    // #275 수용 기준: "추천 근거(나트륨 과다 → 저염)가 드러남".
    await pumpHome(
      tester,
      recommendations: () async => const MealRecommendations(
        personalized: true,
        daysWithData: 3,
        avgSodiumMg: 2400,
        sodiumLimitMg: 2000,
        items: <MealRecommendation>[
          MealRecommendation(key: 'chicken_salad', reasonKey: 'sodium'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2,400mg'), findsOneWidget);
    expect(find.textContaining('권장 초과'), findsOneWidget);
  });

  testWidgets('개인화되지 않으면 근거 줄이 아예 없다', (WidgetTester tester) async {
    // 목업/데모 모드와 신규 가입자 경로 — 화면에 아무것도 추가되면 안 된다.
    await pumpHome(
      tester,
      recommendations: () async => MealRecommendations.fallback,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('평균 나트륨'), findsNothing);
    expect(find.textContaining('권장 초과'), findsNothing);
  });

  testWidgets('앱이 모르는 key 는 버리고 카드 수를 유지한다', (WidgetTester tester) async {
    // 서버 카탈로그가 앱보다 먼저 늘어난 경우. 그릴 에셋·문구가 없으므로
    // 조용히 버리고 기본 추천으로 자리를 채운다.
    await pumpHome(
      tester,
      recommendations: () async => const MealRecommendations(
        personalized: true,
        items: <MealRecommendation>[
          MealRecommendation(key: 'truffle_pasta', reasonKey: 'sodium'),
          MealRecommendation(key: 'tofu', reasonKey: 'low_cal'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(renderedMealNames(tester).length, demoOrder.length);
  });

  testWidgets('이유 문구는 제목보다 작은 회색으로 남는다', (WidgetTester tester) async {
    // 카드 폭이 고정이라, 앱 전역 가독성 개선(3299f996)에서 이 문구까지 키웠더니
    // "나트륨 조절에 좋아요" 가 두 줄로 밀려 아래가 잘렸다. 이유는 가장 작은 역할
    // 글자(`caption`)·옅은 색으로 두고 제목보다 작아야 한다 — 숫자 대신 그 관계를
    // 못박는다(#1690 글자 역할).
    await pumpHome(
      tester,
      recommendations: () async => MealRecommendations.fallback,
    );
    await tester.pumpAndSettle();

    final TextStyle reason = tester
        .widget<Text>(find.text('나트륨 조절에 좋아요'))
        .style!;
    final TextStyle name = tester.widget<Text>(find.text('닭가슴살 샐러드')).style!;

    final OnCareTokens tokens = AppTheme.light().extension<OnCareTokens>()!;
    expect(
      reason.fontSize,
      tokens.text(OnCareTypography.caption).fontSize,
    );
    expect(reason.fontSize, lessThan(name.fontSize!));
    expect(reason.color, OnCareColors.textTertiary);
    expect(name.color, OnCareColors.textPrimary);
  });
}
