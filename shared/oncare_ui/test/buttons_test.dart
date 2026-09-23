import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  OnCareDensity density = OnCareDensity.mobile,
}) {
  return tester.pumpWidget(
    MaterialApp(
      // 밀도를 바꿔 다시 그릴 때 테마 전환 애니메이션 중간값을 읽지 않게 한다.
      themeAnimationDuration: Duration.zero,
      theme: OnCareTheme.light(brand: OnCareBrand.member, density: density),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('버튼 높이가 밀도·크기를 따른다', (tester) async {
    for (final OnCareDensity density in <OnCareDensity>[
      OnCareDensity.mobile,
      OnCareDensity.web,
    ]) {
      for (final OnCareButtonSize size in OnCareButtonSize.values) {
        await _pump(
          tester,
          AppButton(label: '저장', onPressed: () {}, size: size),
          density: density,
        );
        expect(
          tester.getSize(find.byType(AppButton)).height,
          density.buttonHeight(size),
          reason: '$density $size',
        );
      }
    }
  });

  testWidgets('위험 확정 버튼은 빨간 채움 하나다', (tester) async {
    await _pump(
      tester,
      AppButtonPair(
        cancelLabel: '취소',
        onCancel: () {},
        confirmLabel: '삭제',
        onConfirm: () {},
        destructive: true,
      ),
    );
    final Material confirm = tester.widget<Material>(
      find
          .descendant(of: find.widgetWithText(TextButton, '삭제'),
              matching: find.byType(Material))
          .first,
    );
    expect(confirm.color, OnCareColors.danger);
    expect(
      tester.getCenter(find.text('취소')).dx,
      lessThan(tester.getCenter(find.text('삭제')).dx),
    );
  });

  testWidgets('두 버튼을 각자의 키로 집을 수 있다', (tester) async {
    await _pump(
      tester,
      AppButtonPair(
        cancelKey: const Key('pair-cancel'),
        cancelLabel: '취소',
        onCancel: () {},
        confirmKey: const Key('pair-confirm'),
        confirmLabel: '저장',
        onConfirm: () {},
      ),
    );
    expect(
      tester.widget<AppButton>(find.byKey(const Key('pair-cancel'))).label,
      '취소',
    );
    expect(
      tester.widget<AppButton>(find.byKey(const Key('pair-confirm'))).label,
      '저장',
    );
  });

  testWidgets('버튼 아이콘은 글자와 같은 색이다', (tester) async {
    Color iconColorOf(IconData icon) {
      final BuildContext context = tester.element(find.byIcon(icon));
      return IconTheme.of(context).color!;
    }

    final Map<AppButtonVariant, Color> expected = <AppButtonVariant, Color>{
      AppButtonVariant.primary: OnCareColors.textOnFill,
      AppButtonVariant.destructive: OnCareColors.textOnFill,
      AppButtonVariant.secondary: OnCareColors.textPrimary,
      AppButtonVariant.destructiveText: OnCareColors.danger,
      AppButtonVariant.strongOutline: OnCareBrand.member.strong,
      AppButtonVariant.strong: OnCareColors.textOnFill,
    };
    for (final MapEntry<AppButtonVariant, Color> entry in expected.entries) {
      await _pump(
        tester,
        AppButton(
          // 종류마다 새로 그려 이전 버튼의 색 전환 중간값을 읽지 않는다.
          key: ValueKey<AppButtonVariant>(entry.key),
          label: '추가',
          onPressed: () {},
          variant: entry.key,
          leadingIcon: Icons.add_rounded,
          trailingIcon: Icons.chevron_right_rounded,
        ),
      );
      for (final IconData icon in <IconData>[
        Icons.add_rounded,
        Icons.chevron_right_rounded,
      ]) {
        expect(iconColorOf(icon), entry.value, reason: '${entry.key}');
      }
    }

    await _pump(
      tester,
      const AppButton(
        key: ValueKey<String>('disabled'),
        label: '추가',
        onPressed: null,
        leadingIcon: Icons.add_rounded,
      ),
    );
    expect(iconColorOf(Icons.add_rounded), OnCareColors.textDisabled);
  });

  // #2180 — 칠하지 않아 놓인 바탕(페이지 배경·흰 카드)이 그대로 보이고,
  // 테두리와 글자는 진한 브랜드 색이다. 비활성은 다른 외곽선 버튼과 같다.
  testWidgets('strongOutline 은 투명 바탕에 진한 브랜드 테두리·글자다', (tester) async {
    ButtonStyle styleOf() =>
        tester.widget<TextButton>(find.byType(TextButton)).style!;

    await _pump(
      tester,
      AppButton(
        label: '오늘',
        onPressed: () {},
        variant: AppButtonVariant.strongOutline,
      ),
    );
    final Set<WidgetState> idle = <WidgetState>{};
    expect(styleOf().backgroundColor!.resolve(idle), Colors.transparent);
    expect(
      styleOf().foregroundColor!.resolve(idle),
      OnCareBrand.member.strong,
    );
    expect(
      styleOf().side!.resolve(idle),
      BorderSide(color: OnCareBrand.member.strong),
    );

    final Set<WidgetState> disabled = <WidgetState>{WidgetState.disabled};
    expect(styleOf().backgroundColor!.resolve(disabled), Colors.transparent);
    expect(
      styleOf().foregroundColor!.resolve(disabled),
      OnCareColors.textDisabled,
    );
    expect(
      styleOf().side!.resolve(disabled),
      const BorderSide(color: OnCareColors.lineSubtle),
    );
  });

  // #2202 — 옅은 브랜드 바탕 위에서 묻히지 않도록 진한 브랜드로 채운다.
  // 비활성은 다른 채움 버튼과 같은 회색 채움이다.
  testWidgets('strong 은 진한 브랜드 채움에 흰 글자다', (tester) async {
    ButtonStyle styleOf() =>
        tester.widget<TextButton>(find.byType(TextButton)).style!;

    await _pump(
      tester,
      AppButton(
        label: '회원',
        onPressed: () {},
        variant: AppButtonVariant.strong,
      ),
    );
    final Set<WidgetState> idle = <WidgetState>{};
    expect(
      styleOf().backgroundColor!.resolve(idle),
      OnCareBrand.member.strong,
    );
    expect(styleOf().foregroundColor!.resolve(idle), OnCareColors.textOnFill);
    expect(styleOf().side, isNull);

    final Set<WidgetState> disabled = <WidgetState>{WidgetState.disabled};
    expect(
      styleOf().backgroundColor!.resolve(disabled),
      OnCareColors.surfaceInput,
    );
    expect(
      styleOf().foregroundColor!.resolve(disabled),
      OnCareColors.textDisabled,
    );
  });

  testWidgets('처리 중이면 탭이 막히고 스피너가 보인다', (tester) async {
    int taps = 0;
    await _pump(
      tester,
      AppButton(label: '저장', onPressed: () => taps++, loading: true),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(AppButton));
    expect(taps, 0);
  });

  // #2057 — 호출부가 중복 탭을 막으려고 핸들러까지 null 로 넘기면 비활성 회색
  // 바탕이 되는데 스피너는 흰색 그대로라 묻혔다. 처리 중에는 핸들러와 상관없이
  // 활성 모양이다.
  testWidgets('처리 중에는 핸들러가 null 이어도 활성 채움 그대로다', (tester) async {
    for (final (AppButtonVariant variant, Color fill)
        in <(AppButtonVariant, Color)>[
          (AppButtonVariant.primary, OnCareBrand.member.primary),
          (AppButtonVariant.destructive, OnCareColors.danger),
        ]) {
      await _pump(
        tester,
        AppButton(
          label: '저장',
          onPressed: null,
          loading: true,
          variant: variant,
        ),
      );
      final Material material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(TextButton),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, fill, reason: '$variant');
    }
  });

  // 포인터를 막는 것만으로는 키보드 Enter 가 새어 들어가 중복 제출이 된다.
  testWidgets('처리 중에는 키보드로도 눌리지 않는다', (tester) async {
    int taps = 0;
    await _pump(
      tester,
      AppButton(label: '저장', onPressed: () => taps++, loading: true),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextButton>(),
      isNotNull,
      reason: 'Tab 으로 버튼에 초점이 가야 이 테스트가 의미가 있다',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('뒤로·닫기는 터치 44, 아이콘 24, 접근성 이름이 있다', (tester) async {
    await _pump(
      tester,
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[AppBackButton(), AppCloseButton()],
      ),
      density: OnCareDensity.web,
    );
    for (final Type type in <Type>[AppBackButton, AppCloseButton]) {
      expect(tester.getSize(find.byType(type)), const Size.square(44));
    }
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('아이콘 버튼 한 변이 밀도를 따른다', (tester) async {
    await _pump(
      tester,
      AppIconButton(
        icon: Icons.notifications_none_rounded,
        tooltip: '알림',
        onPressed: () {},
        variant: AppIconButtonVariant.tonal,
      ),
      density: OnCareDensity.web,
    );
    expect(tester.getSize(find.byType(AppIconButton)), const Size.square(36));
  });
}
