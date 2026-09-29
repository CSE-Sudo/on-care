import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';

/// 메뉴 항목 하나.
@immutable
class AppMenuItem {
  const AppMenuItem({
    required this.label,
    this.key,
    required this.onSelected,
    this.icon,
    this.destructive = false,
    this.selected = false,
  });

  final String label;

  /// 항목 버튼에 붙는 키. 버튼 줄을 메뉴로 접을 때 예전 버튼의 키를 그대로
  /// 이어 받아, 그 동작을 찾던 테스트·자동화가 깨지지 않게 한다(#2178).
  final Key? key;

  /// `null` 이면 비활성이다.
  final VoidCallback? onSelected;
  final IconData? icon;

  /// 삭제 같은 위험 동작이면 빨간 글자.
  final bool destructive;

  /// 정렬·필터처럼 현재 고른 항목이면 앞에 체크를 둔다.
  final bool selected;
}

/// 두 앱의 메뉴(#1693) — `MenuAnchor`·`PopupMenuButton` 을 대체한다.
///
/// 반경 12, 옅은 테두리, 떠 있는 요소 그림자, 항목 높이·글자는 테마(밀도)를 따른다.
/// [triggerBuilder] 는 메뉴를 여닫는 함수를 받아 트리거 버튼을 그린다.
class AppMenu extends StatelessWidget {
  const AppMenu({
    super.key,
    required this.items,
    required this.triggerBuilder,
    this.alignEnd = false,
  });

  final List<AppMenuItem> items;
  final Widget Function(BuildContext context, VoidCallback toggle)
  triggerBuilder;

  /// 메뉴의 끝(오른쪽) 가장자리를 트리거의 끝 가장자리에 맞춰 펼친다.
  ///
  /// 기본값은 트리거의 시작(왼쪽)에서 펼친다. 카드 오른쪽 위 버튼처럼 끝에 선
  /// 트리거에서 그렇게 펼치면 메뉴가 화면 밖으로 넘치고, `MenuAnchor` 는 그것을
  /// 화면 가장자리 8px 에 붙여 버린다. 끝에 선 트리거는 이것을 켜 메뉴가 트리거
  /// 아래에서 안쪽으로 펼쳐지게 한다.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    if (!alignEnd) return _anchor(context);
    // `MenuAnchor` 는 끝 맞춤 정렬을 따로 받지 않는다 — 글 방향을 뒤집으면
    // 기본 정렬(`bottomStart`)이 트리거의 끝 아래가 되고, 메뉴도 그 점에서
    // 시작 쪽으로 펼쳐진다. 트리거와 항목은 원래 글 방향으로 되돌려 그린다.
    final TextDirection direction = Directionality.of(context);
    return Directionality(
      textDirection: direction == TextDirection.ltr
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: _anchor(context, restore: direction),
    );
  }

  Widget _anchor(BuildContext context, {TextDirection? restore}) {
    Widget keep(Widget child) => restore == null
        ? child
        : Directionality(textDirection: restore, child: child);
    return MenuAnchor(
      menuChildren: <Widget>[
        for (final AppMenuItem item in items)
          keep(
            MenuItemButton(
              key: item.key,
              onPressed: item.onSelected,
              leadingIcon: item.selected
                  ? AppIcon(
                      AppIcon.setOf(context).check,
                      size: OnCareSize.iconMedium,
                    )
                  : item.icon == null
                  ? null
                  : AppIcon(item.icon, size: OnCareSize.iconMedium),
              style: item.destructive
                  ? const ButtonStyle(
                      foregroundColor: WidgetStatePropertyAll<Color>(
                        OnCareColors.danger,
                      ),
                      iconColor: WidgetStatePropertyAll<Color>(
                        OnCareColors.danger,
                      ),
                    )
                  : null,
              child: Text(item.label),
            ),
          ),
      ],
      builder: (BuildContext context, MenuController controller, Widget? _) =>
          keep(
            Builder(
              builder: (BuildContext context) => triggerBuilder(
                context,
                () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          ),
    );
  }
}
