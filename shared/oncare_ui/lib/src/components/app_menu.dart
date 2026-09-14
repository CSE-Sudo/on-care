import 'package:flutter/material.dart';

import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';

/// 메뉴 항목 하나.
@immutable
class AppMenuItem {
  const AppMenuItem({
    required this.label,
    required this.onSelected,
    this.icon,
    this.destructive = false,
    this.selected = false,
  });

  final String label;

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
  });

  final List<AppMenuItem> items;
  final Widget Function(BuildContext context, VoidCallback toggle)
  triggerBuilder;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: <Widget>[
        for (final AppMenuItem item in items)
          MenuItemButton(
            onPressed: item.onSelected,
            leadingIcon: item.selected
                ? const Icon(Icons.check_rounded, size: OnCareSize.iconMedium)
                : item.icon == null
                ? null
                : Icon(item.icon, size: OnCareSize.iconMedium),
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
      ],
      builder: (BuildContext context, MenuController controller, Widget? _) =>
          triggerBuilder(
            context,
            () => controller.isOpen ? controller.close() : controller.open(),
          ),
    );
  }
}
