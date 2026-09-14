import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/design_system/tokens/colors.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 확인 창의 배경은 **카드와 같은 흰색**이다. (#925)
///
/// Material 3 의 `AlertDialog` 는 배경을 `ColorScheme.surfaceContainerHigh`
/// 에서 가져오는데, 이 앱은 그 자리에 `AppColors.accent`(연한 파랑)를 두었다.
/// 그래서 헬스장 예약 취소 창을 비롯한 모든 확인 창이 연한 파랑으로 떴다.
void main() {
  Future<void> openDialog(WidgetTester tester, Widget dialog) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showDialog<void>(context: context, builder: (_) => dialog),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Color backgroundOf(WidgetTester tester, Type dialogType) {
    final Material material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(dialogType),
            matching: find.byType(Material),
          )
          .first,
    );
    return material.color!;
  }

  testWidgets('AlertDialog 배경이 흰색이다', (WidgetTester tester) async {
    await openDialog(
      tester,
      AlertDialog(
        title: const Text('예약을 취소할까요?'),
        actions: <Widget>[
          TextButton(onPressed: () {}, child: const Text('유지')),
        ],
      ),
    );

    expect(backgroundOf(tester, AlertDialog), AppColors.card);
    // accent 는 카드 **안**에서 한 덩이를 구분하는 색이다 — 창 전체를 그 색으로
    // 칠하면 대화상자가 카드 위에 뜬 또 하나의 알약처럼 보인다.
    expect(backgroundOf(tester, AlertDialog), isNot(AppColors.accent));
  });

  testWidgets('Dialog 배경도 같은 흰색이다', (WidgetTester tester) async {
    await openDialog(
      tester,
      const Dialog(child: SizedBox(width: 200, height: 100)),
    );

    expect(backgroundOf(tester, Dialog), AppColors.card);
  });

  test('accent 는 대화상자 배경으로 쓰이지 않는다', () {
    // 목록 행·알약이 쓰는 옅은 브랜드 채움은 ColorScheme 쪽에 그대로 둔다(#1691).
    expect(
      AppTheme.light().colorScheme.surfaceContainerHigh,
      OnCareBrand.member.surface,
    );
    expect(AppTheme.light().dialogTheme.backgroundColor, AppColors.card);
  });
}
