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

  testWidgets('웹 창은 하단 버튼이 있으면 X 를 두지 않는다, 모바일은 둔다 (#2465)', (tester) async {
    Future<void> open(OnCareDensity density, {Widget? footer}) async {
      final BuildContext context = await _pump(tester, density: density);
      showAppDialog<void>(
        context: context,
        builder: (_) =>
            AppDialog(title: '제목', footer: footer, child: const Text('본문')),
      );
      await tester.pumpAndSettle();
    }

    final Widget footer = AppButtonPair(
      cancelLabel: '취소',
      onCancel: () {},
      confirmLabel: '확인',
      onConfirm: () {},
    );

    await open(OnCareDensity.web, footer: footer);
    expect(find.byType(AppCloseButton), findsNothing);
    Navigator.pop(tester.element(find.text('본문')));
    await tester.pumpAndSettle();

    // 하단 버튼이 없는 조회용 창은 X 로 닫는다.
    await open(OnCareDensity.web);
    expect(find.byType(AppCloseButton), findsOneWidget);
    Navigator.pop(tester.element(find.text('본문')));
    await tester.pumpAndSettle();

    await open(OnCareDensity.mobile, footer: footer);
    expect(find.byType(AppCloseButton), findsOneWidget);
  });

  testWidgets('창 제목 오른쪽에 trailing 을 둔다 (#2465)', (tester) async {
    final BuildContext context = await _pump(tester);
    showAppDialog<void>(
      context: context,
      builder: (_) => AppDialog(
        title: '제목',
        trailing: AppButton(
          key: const Key('dialog-trailing'),
          label: '추가',
          onPressed: () {},
          variant: AppButtonVariant.text,
        ),
        child: const Text('본문'),
      ),
    );
    await tester.pumpAndSettle();
    final Rect title = tester.getRect(find.text('제목'));
    final Rect trailing = tester.getRect(
      find.byKey(const Key('dialog-trailing')),
    );
    // 제목은 남는 폭을 다 쓰므로 버튼은 그 바로 오른쪽에 붙는다.
    expect(trailing.left, greaterThanOrEqualTo(title.right));
    expect(trailing.center.dy, closeTo(title.center.dy, 8));
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

  group('끝 맞춤 메뉴 (alignEnd)', () {
    Future<void> pumpMenu(WidgetTester tester, {required bool alignEnd}) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: OnCareTheme.light(
            brand: OnCareBrand.trainer,
            density: OnCareDensity.web,
          ),
          home: Scaffold(
            // 카드 오른쪽 위 버튼처럼 화면 끝에서 조금 안쪽에 선 트리거.
            body: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 40, right: 60),
                child: AppMenu(
                  alignEnd: alignEnd,
                  items: <AppMenuItem>[
                    AppMenuItem(
                      key: const ValueKey<String>('menu-long'),
                      label: '개인운동 수정하기 항목',
                      onSelected: () {},
                    ),
                  ],
                  triggerBuilder: (context, toggle) => TextButton(
                    key: const ValueKey<String>('menu-trigger'),
                    onPressed: toggle,
                    child: const Text('열기'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
    }

    // 메뉴 틀(`_MenuPanel`)은 비공개라, 틀 안을 가로로 채우는 항목 칸으로 잰다.
    Rect menuRect(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey<String>('menu-long')));

    testWidgets('끝에 선 트리거의 메뉴가 화면 가장자리에 붙지 않는다', (tester) async {
      await pumpMenu(tester, alignEnd: true);
      final Rect trigger = tester.getRect(
        find.byKey(const ValueKey<String>('menu-trigger')),
      );
      final Rect menu = menuRect(tester);
      // 메뉴 끝이 트리거 끝과 같은 선에 서고, 화면 끝과는 트리거의 여백만큼
      // 떨어진다.
      expect(menu.right, moreOrLessEquals(trigger.right, epsilon: 1));
      expect(800 - menu.right, greaterThanOrEqualTo(60 - 1));
      expect(menu.top, greaterThanOrEqualTo(trigger.bottom - 1));
    });

    testWidgets('끝 맞춤이어도 항목·트리거의 글 방향은 그대로다', (tester) async {
      await pumpMenu(tester, alignEnd: true);
      final BuildContext item = tester.element(
        find.byKey(const ValueKey<String>('menu-long')),
      );
      final BuildContext trigger = tester.element(
        find.byKey(const ValueKey<String>('menu-trigger')),
      );
      expect(Directionality.of(item), TextDirection.ltr);
      expect(Directionality.of(trigger), TextDirection.ltr);
    });

    testWidgets('기본값은 예전처럼 트리거 시작에서 펼친다', (tester) async {
      await pumpMenu(tester, alignEnd: false);
      final Rect trigger = tester.getRect(
        find.byKey(const ValueKey<String>('menu-trigger')),
      );
      final Rect menu = menuRect(tester);
      // 넘치는 메뉴라 화면 끝으로 밀린다 — 끝 맞춤과 다른 자리여야 한다.
      expect(menu.right, isNot(moreOrLessEquals(trigger.right, epsilon: 1)));
    });
  });
}
