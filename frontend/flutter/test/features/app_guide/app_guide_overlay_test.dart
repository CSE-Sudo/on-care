import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/points/points_rules.dart';
import 'package:oncare/features/app_guide/domain/guide_step.dart';
import 'package:oncare/features/app_guide/presentation/controllers/app_guide_controller.dart';
import 'package:oncare/features/app_guide/presentation/widgets/app_guide_overlay.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 스포트라이트 가이드 덮개(#1857) — 가이드라는 표시·단계·짚는 자리·건너뛰기.
void main() {
  Future<ProviderContainer> pumpGuide(
    WidgetTester tester, {
    Locale locale = const Locale('ko'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final GuideAnchors anchors = container.read(guideAnchorsProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                // 짚을 자리들 — 탭마다 다른 화면이지만, 덮개가 보기에는 모두
                // "이 화면 어딘가의 네모" 다.
                Positioned(
                  top: 100,
                  left: 16,
                  child: SizedBox(
                    key: anchors.homeAdvice,
                    width: 360,
                    height: 140,
                  ),
                ),
                Positioned(
                  bottom: 24,
                  left: 172,
                  child: SizedBox(key: anchors.quickAdd, width: 56, height: 56),
                ),
                Positioned(
                  top: 260,
                  left: 16,
                  child: SizedBox(
                    key: anchors.dietNutrition,
                    width: 360,
                    height: 180,
                  ),
                ),
                Positioned(
                  top: 100,
                  left: 16,
                  child: SizedBox(
                    key: anchors.exerciseStatus,
                    width: 360,
                    height: 200,
                  ),
                ),
                Positioned(
                  top: 320,
                  left: 16,
                  child: SizedBox(key: anchors.gym, width: 360, height: 120),
                ),
                Positioned(
                  top: 120,
                  left: 16,
                  child: SizedBox(
                    key: anchors.mySettings,
                    width: 360,
                    height: 160,
                  ),
                ),
                Positioned(
                  top: 300,
                  left: 16,
                  child: SizedBox(key: anchors.points, width: 360, height: 120),
                ),
                const Positioned.fill(child: AppGuideOverlay()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('가이드가 꺼져 있으면 아무것도 덮지 않는다', (WidgetTester tester) async {
    await pumpGuide(tester);

    expect(find.byKey(const Key('appGuideOverlay')), findsNothing);
    expect(find.byKey(const Key('appGuideCard')), findsNothing);
  });

  testWidgets('가이드라는 표시와 단계를 보여 주고, 짚는 자리를 밝게 뚫는다', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpGuide(tester);
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));

    container.read(appGuideControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appGuideOverlay')), findsOneWidget);
    // 갑자기 어두워진 이유와 남은 길이를 먼저 말한다.
    expect(
      find.text(l.guideBadgeWithStep(1, kGuideSteps.length)),
      findsOneWidget,
    );
    expect(find.text(l.guideHomeAdviceTitle), findsOneWidget);

    // 뚫린 자리는 짚는 요소를 감싼다.
    final AppSpotlight spotlight = tester.widget<AppSpotlight>(
      find.byType(AppSpotlight),
    );
    final Rect anchor = tester.getRect(
      find.byKey(container.read(guideAnchorsProvider).homeAdvice),
    );
    // 짚는 요소의 자리와 **같은 사각형**이어야 한다. 덮개와 요소는 형제라
    // 좌표계를 잘못 맞추면 구멍이 밀리거나 사라진다.
    expect(spotlight.hole, anchor);
  });

  testWidgets('다음으로 끝까지 가면 가이드가 끝나고, 마지막은 포인트다', (WidgetTester tester) async {
    final ProviderContainer container = await pumpGuide(tester);
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));

    container.read(appGuideControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    for (int step = 1; step < kGuideSteps.length; step++) {
      expect(find.text(l.guideNext), findsOneWidget);
      await tester.tap(find.byKey(const Key('appGuideNext')));
      await tester.pumpAndSettle();
    }

    // 마지막은 포인트 — 숫자는 적립 규칙에서 읽는다.
    expect(find.text(l.guidePointsTitle), findsOneWidget);
    expect(
      find.text(
        l.guidePointsBody(
          PointsRule.dietEntry.points,
          PointsRule.exerciseManual.points,
          PointsRule.routineComplete.points,
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('+${PointsRule.dietEntry.points}P'), findsOne);
    expect(find.text(l.guideDone), findsOneWidget);

    await tester.tap(find.byKey(const Key('appGuideNext')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appGuideOverlay')), findsNothing);
    expect(container.read(appGuideControllerProvider).active, isFalse);
  });

  testWidgets('첫 자리에는 이전이 없고, 둘째 자리부터 앞으로 돌아갈 수 있다', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpGuide(tester);
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));

    container.read(appGuideControllerProvider.notifier).start();
    await tester.pumpAndSettle();
    // 첫 자리에서 `이전` 은 갈 곳이 없다.
    expect(find.byKey(const Key('appGuidePrev')), findsNothing);

    await tester.tap(find.byKey(const Key('appGuideNext')));
    await tester.pumpAndSettle();
    expect(find.text(l.guideQuickAddTitle), findsOneWidget);

    await tester.tap(find.byKey(const Key('appGuidePrev')));
    await tester.pumpAndSettle();

    expect(find.text(l.guideHomeAdviceTitle), findsOneWidget);
    expect(
      find.text(l.guideBadgeWithStep(1, kGuideSteps.length)),
      findsOneWidget,
    );
  });

  testWidgets('건너뛰기는 언제나 있고, 누르면 바로 끝난다', (WidgetTester tester) async {
    final ProviderContainer container = await pumpGuide(tester);

    container.read(appGuideControllerProvider.notifier).start();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appGuideNext')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('appGuideSkip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appGuideOverlay')), findsNothing);
    expect(container.read(appGuideControllerProvider).active, isFalse);
  });

  testWidgets('영어 화면에는 한글이 남지 않는다', (WidgetTester tester) async {
    final ProviderContainer container = await pumpGuide(
      tester,
      locale: const Locale('en'),
    );

    container.read(appGuideControllerProvider.notifier).start();
    await tester.pumpAndSettle();

    for (int step = 0; step < kGuideSteps.length; step++) {
      final Iterable<String> texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '');
      for (final String text in texts) {
        expect(RegExp('[가-힣]').hasMatch(text), isFalse, reason: text);
      }
      await tester.tap(find.byKey(const Key('appGuideNext')));
      await tester.pumpAndSettle();
    }
  });
}
