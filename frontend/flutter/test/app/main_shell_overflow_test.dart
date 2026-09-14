/// 하단 네비게이션이 넘치지 않는지 (#840).
///
/// 430px 는 iPhone 15 Pro Max 의 논리 폭이라 특별히 좁은 조건이 아닌데도
/// `_Destination` 의 아이콘+라벨 열이 배정된 높이를 넘겨 세로로 잘렸다. E2E
/// 로그에만 `RenderFlex overflowed by 19 pixels on the bottom` 으로 남아 있어
/// 아무도 보지 못했다 — 앱의 전역 오류 핸들러가 예외를 받아 로깅만 하기 때문이다.
///
/// 한국어와 영어를 모두 돈다. 영어 라벨이 더 길어 같은 자리가 다시 샐 수 있다
/// (#743 과 같은 계열).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required String lang,
    required Size size,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.dashboard);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[appConfigProvider.overrideWithValue(_config)],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('하단 네비게이션 레이아웃 (#840)', () {
    for (final String lang in <String>['ko', 'en']) {
      for (final double scale in <double>[1.0, 1.3]) {
        testWidgets('폭 430 · $lang · 글자 배율 $scale 에서 넘치지 않는다', (
          WidgetTester tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await pumpShell(tester, lang: lang, size: const Size(430, 932));

          // overflow 는 렌더링 예외로 보고된다. 예외가 없으면 넘친 곳이 없다.
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('네 개의 목적지 라벨이 모두 보인다', (WidgetTester tester) async {
      await pumpShell(tester, lang: 'ko', size: const Size(430, 932));

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(Scaffold).first),
      );
      for (final String label in <String>[
        l.navDashboard,
        l.navDiet,
        l.navExercise,
        l.navMyHealth,
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });
}
