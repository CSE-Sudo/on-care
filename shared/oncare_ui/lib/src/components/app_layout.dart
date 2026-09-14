import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_icon_button.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/layout.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 모바일 페이지 틀(#1696) — 연회색 배경·좌우 20·최대 폭 720.
///
/// [header] 는 탭 첫 화면이면 [AppTabHeader], 서브 페이지면 [AppTopBar] 다.
/// [bottomInset] 은 하단 내비 위로 올라올 여백이다.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    this.header,
    required this.children,
    this.bottomInset = 0,
    this.controller,
  });

  final PreferredSizeWidget? header;
  final List<Widget> children;
  final double bottomInset;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final double side = context.oncare.density.pagePadding;
    return Scaffold(
      backgroundColor: OnCareColors.surfacePage,
      appBar: header,
      body: SafeArea(
        top: header == null,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnCareLayout.mobileContentMaxWidth,
            ),
            child: ListView(
              controller: controller,
              padding: EdgeInsets.fromLTRB(
                side,
                OnCareSpacing.s8,
                side,
                OnCareSpacing.sectionGap + bottomInset,
              ),
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// 탭 첫 화면 헤더 — 로고 슬롯 + `titleLarge` 대제목 + 오른쪽 tonal 버튼 최대 2개.
class AppTabHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppTabHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions = const <Widget>[],
  }) : assert(actions.length <= 2, '헤더 액션은 최대 2개다');

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  static const double _height = 64;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return SafeArea(
      bottom: false,
      child: Container(
        height: _height,
        color: OnCareColors.surfacePage,
        padding: EdgeInsets.symmetric(horizontal: tokens.density.pagePadding),
        child: Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: OnCareSpacing.s8),
            ],
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  title,
                  maxLines: 1,
                  style: tokens
                      .text(OnCareTypography.titleLarge)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
            ),
            for (int i = 0; i < actions.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: OnCareSpacing.s8),
              actions[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// 서브 페이지 앱바 — 뒤로 ‹ + 가운데 `titleMedium` + 오른쪽 액션 최대 2개.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
    this.showBack = true,
    this.onBack,
  }) : assert(actions.length <= 2, '앱바 액션은 최대 2개다');

  final String title;
  final List<Widget> actions;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: showBack ? AppBackButton(onPressed: onBack) : null,
      title: Text(title),
      actions: <Widget>[
        ...actions,
        const SizedBox(width: OnCareSpacing.s8),
      ],
    );
  }
}

/// 하단 내비 목적지.
@immutable
class AppNavDestination {
  const AppNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
    this.key,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;

  /// 이 목적지 칸을 가리키는 열쇠. 아이콘·라벨이 화면의 다른 곳과 겹칠 때
  /// 테스트·자동화가 칸을 지목하는 데 쓴다.
  final Key? key;
}

/// 모바일 하단 내비(#1696, #1664) — 바 높이 64, 아이콘 24, 라벨 `caption` 600.
///
/// 안전영역이 0 인 환경에서도 라벨 아래 여백 8 이 남는다. 가운데 [centerAction]
/// (기록 추가)을 둘 수 있다.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.centerAction,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget? centerAction;

  static const double barHeight = 64;
  static const double minBottomPadding = OnCareSpacing.s8;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final double inset = MediaQuery.paddingOf(context).bottom;
    final int half = destinations.length ~/ 2;
    Widget item(int index) {
      final AppNavDestination d = destinations[index];
      final bool selected = index == selectedIndex;
      final Color color = selected
          ? tokens.brand.primary
          : OnCareColors.textTertiary;
      return Expanded(
        key: d.key,
        child: Semantics(
          button: true,
          selected: selected,
          label: d.label,
          child: InkResponse(
            onTap: () => onSelected(index),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Badge(
                  isLabelVisible: d.badgeCount > 0,
                  label: Text('${d.badgeCount}'),
                  child: Icon(
                    selected ? d.selectedIcon : d.icon,
                    size: OnCareSize.iconLarge,
                    color: color,
                  ),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                Text(
                  d.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.caption))
                      .copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        border: Border(top: BorderSide(color: OnCareColors.lineSubtle)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: inset > minBottomPadding ? inset : minBottomPadding,
        ),
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < half; i++) item(i),
              if (centerAction != null)
                SizedBox(
                  width: tokens.density.buttonLarge + OnCareSpacing.s16,
                  child: Center(child: centerAction),
                ),
              for (int i = half; i < destinations.length; i++) item(i),
            ],
          ),
        ),
      ),
    );
  }
}

/// 웹 페이지 폭.
enum AppWebPageWidth {
  /// 760 — 한 열짜리 폼·목록·설정.
  narrow,

  /// 1440 — 대시보드·분할 화면.
  wide,
}

/// 웹 페이지 틀(#1696) — 헤더 88(`titleLarge` + `bodySmall` 부제 + 액션), 좌우 24.
///
/// 여백은 틀만 넣는다. 페이지가 직접 여백을 더하지 않는다.
class AppWebPage extends StatelessWidget {
  const AppWebPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    required this.body,
    this.width = AppWebPageWidth.wide,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final AppWebPageWidth width;

  /// 제목 앞 뒤로가기 등.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final double side = tokens.density.pagePadding;
    return ColoredBox(
      color: OnCareColors.surfacePage,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width == AppWebPageWidth.narrow
                ? OnCareLayout.webNarrowMaxWidth + side * 2
                : OnCareLayout.webWideMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: OnCareLayout.webHeaderHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  child: Row(
                    children: <Widget>[
                      if (leading != null) ...<Widget>[
                        leading!,
                        const SizedBox(width: OnCareSpacing.s8),
                      ],
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens
                                  .text(OnCareTypography.titleLarge)
                                  .copyWith(color: OnCareColors.textPrimary),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tokens
                                    .text(OnCareTypography.bodySmall)
                                    .copyWith(
                                      color: OnCareColors.textSecondary,
                                    ),
                              ),
                          ],
                        ),
                      ),
                      for (final Widget action in actions) ...<Widget>[
                        const SizedBox(width: OnCareSpacing.s8),
                        action,
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(side, 0, side, side),
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 분할 레이아웃 — 목록 380 + 간격 16 + 상세. 좁으면 목록·상세 중 하나만 보인다.
class AppSplitView extends StatelessWidget {
  const AppSplitView({
    super.key,
    required this.list,
    required this.detail,
    this.showDetailWhenNarrow = false,
  });

  final Widget list;
  final Widget detail;

  /// 좁은 폭에서 상세를 보일지(선택된 항목이 있을 때).
  final bool showDetailWhenNarrow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < OnCareLayout.splitBreakpoint) {
          return showDetailWhenNarrow ? detail : list;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(width: OnCareLayout.splitListWidth, child: list),
            const SizedBox(width: OnCareLayout.splitGap),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

/// 사이드바 항목 — 높이 44, 아이콘 24, 선택 = 옅은 브랜드 채움 + 왼쪽 브랜드 막대.
class AppSidebarItem extends StatelessWidget {
  const AppSidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
    this.collapsed = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  /// 레일(아이콘만) 모드. 라벨은 툴팁으로 옮긴다.
  final bool collapsed;

  static const double height = 44;
  static const double indicatorWidth = 3;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color color = selected
        ? tokens.brand.primary
        : OnCareColors.textSecondary;
    final Widget icon0 = Badge(
      isLabelVisible: badgeCount > 0,
      label: Text(badgeCount > 99 ? '99+' : '$badgeCount'),
      child: Icon(icon, size: OnCareSize.iconLarge, color: color),
    );
    final Widget content = Material(
      color: selected ? tokens.brand.surface : Colors.transparent,
      borderRadius: OnCareRadius.mdAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: tokens.brand.surface,
        child: SizedBox(
          height: height,
          child: Row(
            children: <Widget>[
              Container(
                width: indicatorWidth,
                height: OnCareSpacing.s24,
                decoration: BoxDecoration(
                  color: selected ? tokens.brand.primary : Colors.transparent,
                  borderRadius: OnCareRadius.pillAll,
                ),
              ),
              const SizedBox(width: OnCareSpacing.s12),
              icon0,
              if (!collapsed) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens
                        .text(
                          selected
                              ? OnCareTypography.strong(
                                  OnCareTypography.bodyLarge,
                                )
                              : OnCareTypography.bodyLarge,
                        )
                        .copyWith(color: color),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: collapsed ? label : null,
      child: collapsed ? Tooltip(message: label, child: content) : content,
    );
  }
}

/// 로그인·가입·온보딩 틀 — 로고 + 최대 폭 400 + 연회색 배경 + `titleLarge` 제목.
class AppAuthLayout extends StatelessWidget {
  const AppAuthLayout({
    super.key,
    this.logo,
    required this.title,
    this.subtitle,
    required this.child,
    this.leading,
  });

  final Widget? logo;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Scaffold(
      backgroundColor: OnCareColors.surfacePage,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(tokens.density.pagePadding),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: OnCareLayout.authMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (logo != null) ...<Widget>[
                        Center(child: logo),
                        const SizedBox(height: OnCareSpacing.s24),
                      ],
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: tokens
                            .text(OnCareTypography.titleLarge)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: OnCareSpacing.s8),
                        Text(
                          subtitle!,
                          textAlign: TextAlign.center,
                          style: tokens
                              .text(OnCareTypography.bodySmall)
                              .copyWith(color: OnCareColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: OnCareSpacing.s32),
                      child,
                    ],
                  ),
                ),
              ),
            ),
            if (leading != null)
              Positioned(
                top: OnCareSpacing.s4,
                left: OnCareSpacing.s4,
                child: leading!,
              ),
          ],
        ),
      ),
    );
  }
}
