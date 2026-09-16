import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/points/points_rules.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/account/presentation/pages/onboarding_page.dart';
import 'package:oncare/features/account/presentation/pages/points_guide_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 온보딩 뒤 포인트 안내(#1826) — 규칙 상수와 같은 숫자, 완료·건너뛰기 모두
/// 안내를 거쳐 홈으로 가는 흐름, 영어 화면.

Future<void> _pump(
  WidgetTester tester, {
  required String initial,
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final GoRouter router = GoRouter(
    initialLocation: initial,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, _) => const OnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.pointsGuide,
        builder: (_, _) => const PointsGuidePage(),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (_, _) => const Scaffold(body: Text('dashboard-route')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

Future<void> _selectBirthPart(
  WidgetTester tester,
  String key,
  String label,
) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  final Finder item = find.text(label);
  await tester.dragUntilVisible(
    item,
    find.byType(Scrollable).last,
    const Offset(0, -160),
  );
  await tester.tap(item.first);
  await tester.pumpAndSettle();
}

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  testWidgets('퀘스트마다 적립 규칙의 포인트와 하루 한도를 그대로 보여 준다', (tester) async {
    await _pump(tester, initial: AppRoutes.pointsGuide);

    expect(find.text(ko.pointsGuideTitle), findsOneWidget);
    for (final (int i, PointsRule rule) in PointsGuidePage.questOrder.indexed) {
      final Finder card = find.byKey(Key('pointsGuideQuest-${rule.name}'));
      expect(card, findsOneWidget, reason: rule.name);
      Finder inCard(String text) =>
          find.descendant(of: card, matching: find.text(text));
      expect(inCard('퀘스트 ${i + 1}'), findsOneWidget);
      expect(inCard('+${rule.points}P'), findsOneWidget, reason: rule.name);
      expect(inCard('하루 ${rule.dailyCap}회까지'), findsOneWidget);
    }
    // 세 규칙이 빠짐없이 안내된다 — 규칙이 늘면 이 안내도 늘어야 한다.
    expect(PointsGuidePage.questOrder.toSet(), PointsRule.values.toSet());
    expect(find.text(ko.pointsGuideSpendNote), findsOneWidget);
  });

  testWidgets('시작하기를 누르면 홈으로 간다', (tester) async {
    await _pump(tester, initial: AppRoutes.pointsGuide);

    await tester.tap(find.byKey(const Key('pointsGuideStart')));
    await tester.pumpAndSettle();

    expect(find.text('dashboard-route'), findsOneWidget);
  });

  testWidgets('온보딩을 건너뛰어도 포인트 안내를 거쳐 홈으로 간다', (tester) async {
    await _pump(tester, initial: AppRoutes.onboarding);

    await tester.tap(find.text(ko.onboardSkip));
    await tester.pumpAndSettle();
    expect(find.byType(PointsGuidePage), findsOneWidget);
    expect(find.text('dashboard-route'), findsNothing);

    await tester.tap(find.byKey(const Key('pointsGuideStart')));
    await tester.pumpAndSettle();
    expect(find.text('dashboard-route'), findsOneWidget);
  });

  testWidgets('온보딩을 마치면 포인트 안내를 거쳐 홈으로 간다', (tester) async {
    await _pump(tester, initial: AppRoutes.onboarding);

    await _selectBirthPart(tester, 'onboardBirthYear', '1995년');
    await _selectBirthPart(tester, 'onboardBirthMonth', '4월');
    await _selectBirthPart(tester, 'onboardBirthDay', '12일');
    await tester.tap(find.text(ko.onboardGenderMale));
    await tester.pump();
    await tester.enterText(_field('onboardHeightField'), '178');
    await tester.enterText(_field('onboardWeightField'), '74');
    await tester.pumpAndSettle();

    for (int i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('onboardNextButton')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(ko.onboardDone));
    await tester.pumpAndSettle();

    expect(find.byType(PointsGuidePage), findsOneWidget);
    await tester.tap(find.byKey(const Key('pointsGuideStart')));
    await tester.pumpAndSettle();
    expect(find.text('dashboard-route'), findsOneWidget);
  });

  testWidgets('영어 화면에는 한글이 남지 않는다', (tester) async {
    await _pump(
      tester,
      initial: AppRoutes.pointsGuide,
      locale: const Locale('en'),
    );

    final Iterable<String> texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '');
    for (final String text in texts) {
      expect(RegExp('[가-힣]').hasMatch(text), isFalse, reason: text);
    }
    expect(find.text('Points quests'), findsOneWidget);
    expect(find.text('Up to 3 times a day'), findsWidgets);
    expect(find.text('Once a day'), findsOneWidget);
  });
}
