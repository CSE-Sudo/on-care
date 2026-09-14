import 'package:flutter/material.dart';
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
