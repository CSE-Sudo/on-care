import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/member_tab_header.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 헤더 아이콘 버튼은 켜져 있든 꺼져 있든 배경이 없다(#1781).
void main() {
  late double iconButtonSize;
  int taps = 0;

  Future<void> pumpButtons(WidgetTester tester) async {
    taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            iconButtonSize = context.oncare.density.iconButton;
            return Material(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    HeaderActionButton(
                      key: const Key('enabledHeaderButton'),
                      icon: Icons.notifications_rounded,
                      tooltip: 'enabled',
                      onPressed: () {},
                    ),
                    HeaderActionButton(
                      key: const Key('disabledHeaderButton'),
                      icon: Icons.chat_bubble_rounded,
                      tooltip: 'disabled',
                      enabled: false,
                      onPressed: () => taps++,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Color? backgroundOf(WidgetTester tester, String key) {
    final IconButton button = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(IconButton),
      ),
    );
    return button.style?.backgroundColor?.resolve(<WidgetState>{});
  }

  AppIconButton appButtonOf(WidgetTester tester, String key) =>
      tester.widget<AppIconButton>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(AppIconButton),
        ),
      );

  testWidgets('켜진 버튼은 배경 없이 브랜드색 아이콘이다', (WidgetTester tester) async {
    await pumpButtons(tester);

    final AppIconButton button = appButtonOf(tester, 'enabledHeaderButton');
    expect(button.variant, AppIconButtonVariant.plain);
    expect(button.color, OnCareBrand.member.primary);
    expect(backgroundOf(tester, 'enabledHeaderButton'), Colors.transparent);
    expect(
      tester.getSize(find.byKey(const Key('enabledHeaderButton'))),
      Size.square(iconButtonSize),
    );
  });

  testWidgets('꺼진 버튼은 회색 상자 없이 회색 아이콘만 남고 탭은 받는다', (
    WidgetTester tester,
  ) async {
    await pumpButtons(tester);

    const String key = 'disabledHeaderButton';
    final AppIconButton button = appButtonOf(tester, key);
    expect(button.variant, AppIconButtonVariant.plain);
    expect(button.color, OnCareColors.textDisabled);
    expect(backgroundOf(tester, key), Colors.transparent);

    // 예전에는 버튼 뒤에 입력 회색(`surfaceInput`) 상자를 깔았다.
    final Iterable<DecoratedBox> grayBoxes = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(const Key(key)),
            matching: find.byType(DecoratedBox),
          ),
        )
        .where(
          (DecoratedBox box) =>
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).color ==
                  OnCareColors.surfaceInput,
        );
    expect(grayBoxes, isEmpty);

    // 켜진 버튼과 터치 크기가 같다.
    expect(
      tester.getSize(find.byKey(const Key(key))),
      Size.square(iconButtonSize),
    );

    // 흐린 채로도 탭을 받아 왜 쓸 수 없는지 알린다(#786).
    await tester.tap(find.byKey(const Key(key)));
    await tester.pump();
    expect(taps, 1);
  });
}
