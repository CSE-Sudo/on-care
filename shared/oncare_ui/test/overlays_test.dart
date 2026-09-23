import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('닫히지 않는 창은 바깥·뒤로가기로 닫히지 않고 버튼으로만 닫힌다', (tester) async {
    final BuildContext context = await _pump(
      tester,
      density: OnCareDensity.mobile,
    );
    String? result;
    showAppDialog<String>(
      context: context,
      dismissible: false,
      builder: (BuildContext dialogContext) => AppDialog(
        showClose: false,
        footer: AppButton(
          label: '확인',
          onPressed: () => Navigator.pop(dialogContext, 'ok'),
        ),
        child: const Text('본문'),
      ),
    ).then((String? value) => result = value);
    await tester.pumpAndSettle();

    // 바깥(배경 막)을 누른다.
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);

    // 기기 뒤로가기.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(result, 'ok');
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

  testWidgets('메뉴 항목의 키가 항목 버튼에 붙는다 (#2178)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OnCareTheme.light(
          brand: OnCareBrand.trainer,
          density: OnCareDensity.web,
        ),
        home: Scaffold(
          body: AppMenu(
            items: <AppMenuItem>[
              AppMenuItem(
                key: const ValueKey<String>('menu-edit'),
                label: '수정',
                onSelected: () {},
              ),
            ],
            triggerBuilder: (context, toggle) =>
                TextButton(onPressed: toggle, child: const Text('열기')),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey<String>('menu-edit')), findsNothing);
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    final Finder item = find.byKey(const ValueKey<String>('menu-edit'));
    expect(item, findsOneWidget);
    expect(tester.widget(item), isA<MenuItemButton>());
  });
}
