/// MY 탭 로그아웃의 위험 동작 표시. (#1472, #1702)
///
/// 로그아웃이 다른 설정 항목과 같은 무게로 보이지 않도록 위험 동작으로 세운다.
/// 규격(#1690)에 따라 화면 안의 진입점은 빨간 글자 버튼이고, 확정은 확인창의
/// 빨간 채움 버튼에서 한다 — 확인 절차와 동작은 그대로다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  Future<void> pumpMyTab(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          gymRepositoryProvider.overrideWithValue(MockGymRepository()),
          myHealthRepositoryProvider.overrideWithValue(
            const MockMyHealthRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MyHealthPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder logout() => find.byKey(const ValueKey<String>('my-logout-button'));

  testWidgets('로그아웃은 빨간 글자 위험 동작 버튼이다', (WidgetTester tester) async {
    await pumpMyTab(tester);

    expect(logout(), findsOneWidget);
    final AppButton button = tester.widget<AppButton>(logout());
    expect(button.variant, AppButtonVariant.destructiveText);
    expect(button.leadingIcon, AppIcons.logout);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(MyHealthPage)),
    );
    expect(
      find.descendant(of: logout(), matching: find.text(l.myLogout)),
      findsOneWidget,
    );
  });

  testWidgets('누르면 빨간 확정 버튼이 있는 확인창이 열리고, 취소하면 그대로다', (
    WidgetTester tester,
  ) async {
    await pumpMyTab(tester);

    await tester.ensureVisible(logout());
    await tester.pumpAndSettle();
    await tester.tap(logout());
    await tester.pumpAndSettle();

    // 누르자마자 로그아웃되지 않는다 — 확인창이 먼저 뜬다.
    expect(find.byType(AppDialog), findsOneWidget);
    final AppButtonPair pair = tester.widget<AppButtonPair>(
      find.byType(AppButtonPair),
    );
    expect(pair.destructive, isTrue);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(MyHealthPage)),
    );
    expect(find.text(l.myLogoutConfirm), findsOneWidget);

    await tester.tap(find.text(l.myCancel));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(find.byType(MyHealthPage), findsOneWidget);
  });
}
