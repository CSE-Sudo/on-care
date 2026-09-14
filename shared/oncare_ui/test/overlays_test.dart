import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<BuildContext> _pump(
  WidgetTester tester, {
  OnCareDensity density = OnCareDensity.web,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(brand: OnCareBrand.trainer, density: density),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            captured = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  testWidgets('웹 다이얼로그 폭은 S400/M560/L800 이다', (tester) async {
    final BuildContext context = await _pump(tester);
    for (final (AppDialogSize size, double width) in <(AppDialogSize, double)>[
      (AppDialogSize.small, 400),
      (AppDialogSize.medium, 560),
      (AppDialogSize.large, 800),
    ]) {
      showAppDialog<void>(
        context: context,
        builder: (_) =>
            AppDialog(title: '제목', size: size, child: const Text('본문')),
      );
      await tester.pumpAndSettle();
      final Finder surface = find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first;
      expect(tester.getSize(surface).width, width);
      Navigator.pop(tester.element(find.text('본문')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('확인창은 확정하면 true, 위험 확정은 빨간 채움이다', (tester) async {
    final BuildContext context = await _pump(tester);
    final Future<bool> result = showAppConfirmDialog(
      context: context,
      title: '삭제할까요?',
      confirmLabel: '삭제',
      destructive: true,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppButtonPair), findsOneWidget);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('토스트는 뜬 뒤 정해진 시간 뒤 사라진다', (tester) async {
    final BuildContext context = await _pump(tester);
    showAppToast(context, '저장했어요', type: AppToastType.success);
    await tester.pump(OnCareMotion.toastEnter);
    expect(find.text('저장했어요'), findsOneWidget);
    await tester.pump(OnCareMotion.toastVisible);
    await tester.pumpAndSettle();
    expect(find.text('저장했어요'), findsNothing);
  });

  testWidgets('시트는 화면 높이 90% 를 넘지 않는다', (tester) async {
    final BuildContext context = await _pump(
      tester,
      density: OnCareDensity.mobile,
    );
    showAppSheet<void>(
      context: context,
      builder: (_) =>
          const AppSheet(title: '기록 추가', child: SizedBox(height: 3000)),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(AppSheet)).height,
      lessThanOrEqualTo(900 * OnCareLayout.sheetMaxHeightFactor),
    );
  });
}
