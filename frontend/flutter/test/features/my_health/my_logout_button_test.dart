/// MY 탭 로그아웃 버튼의 위험 동작 표시. (#1472)
///
/// 아이콘·글자만 붉고 배경은 일반 설정 카드와 같아서, 목록을 훑을 때 로그아웃이
/// 다른 설정 항목과 같은 무게로 보였다. 카드 전체를 파괴적 색으로 세운다 —
/// 확인 절차와 동작은 그대로다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/design_system/tokens/colors.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

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

  testWidgets('로그아웃 카드 전체가 파괴적 색으로 선다', (WidgetTester tester) async {
    await pumpMyTab(tester);

    expect(logout(), findsOneWidget);
    final BoxDecoration decoration =
        tester.widget<Container>(logout()).decoration! as BoxDecoration;
    expect(decoration.color, AppColors.destructive);
    // 모서리는 다른 설정 카드와 같은 반경 그대로다.
    expect((decoration.borderRadius! as BorderRadius).topLeft.x, 20);
  });

  testWidgets('아이콘과 문구는 붉은 바탕에서 읽히는 색이다', (WidgetTester tester) async {
    await pumpMyTab(tester);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(MyHealthPage)),
    );
    final Icon icon = tester.widget<Icon>(
      find.descendant(of: logout(), matching: find.byIcon(Icons.logout)),
    );
    final Text label = tester.widget<Text>(
      find.descendant(of: logout(), matching: find.text(l.myLogout)),
    );

    expect(icon.color, AppColors.destructiveForeground);
    expect(label.style!.color, AppColors.destructiveForeground);
  });

  testWidgets('누르면 기존 로그아웃 확인창이 그대로 열린다', (WidgetTester tester) async {
    await pumpMyTab(tester);

    await tester.ensureVisible(logout());
    await tester.pumpAndSettle();
    await tester.tap(logout());
    await tester.pumpAndSettle();

    // 확인 절차는 건드리지 않았다 — 누르자마자 로그아웃되지 않는다.
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
