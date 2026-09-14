/// AI 조언 플로팅 버튼 임시 숨김. (#862)
///
/// 지우는 것이 아니라 감추는 것이라 확인할 것이 둘이다 — 화면에 없다는 것과,
/// 되살리는 방법이 상수 하나라는 것. 기능으로 들어가는 길(홈의 AI 조언 배너)이
/// 살아 있다는 것은 `widget_test.dart` 의 시트 테스트가 그 배너로 시트를 열어
/// 확인한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/main_shell.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/oni_fab.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.dashboard);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[appConfigProvider.overrideWithValue(_config)],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('회원 화면에 AI 조언 플로팅 버튼이 노출되지 않는다', (tester) async {
    await pumpShell(tester);

    expect(find.byKey(const Key('coachingFab')), findsNothing);
    expect(find.byType(OniFab), findsNothing);
  });

  testWidgets('가운데 기록 추가 버튼과 하단 네비는 그대로다', (tester) async {
    await pumpShell(tester);

    // 가운데 + 는 AI 조언이 아니라 기록 추가다 — 함께 사라지면 안 된다.
    expect(find.byKey(const Key('recordAddButton')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('nav-exercise')), findsOneWidget);
  });

  test('숨김은 상수 하나로 되돌린다', () {
    // 값을 true 로 되돌리면 위 두 위젯 테스트가 실패하며 알려 준다 — 복원할 때
    // 함께 손봐야 할 자리가 테스트에 적혀 있는 셈이다.
    expect(kShowCoachingFab, isFalse);
  });
}
