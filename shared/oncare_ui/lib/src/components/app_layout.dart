import 'package:flutter/material.dart';
import 'package:oncare_ui/src/components/app_icon_button.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/density.dart';
import 'package:oncare_ui/src/tokens/elevation.dart';
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
      backgroundColor: context.oncare.pageBackground,
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
        color: tokens.pageBackground,
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
/// (기록 추가)을 둘 수 있다 — 바 위로 [centerActionLift] 만큼 튀어나온 원형
/// 버튼([AppNavAddButton])이 자리 잡는다(#1742).
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

  /// 가운데 원형 버튼 지름과 바 위로 튀어나오는 높이.
  static const double centerActionSize = 56;
  static const double centerActionLift = OnCareSpacing.s24;

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

    final double bottom = inset > minBottomPadding ? inset : minBottomPadding;
    final Widget bar = DecoratedBox(
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        border: Border(top: BorderSide(color: OnCareColors.lineSubtle)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < half; i++) item(i),
              // 가운데 칸은 비워 두고, 원형 버튼이 바 윗선에 걸쳐 앉는다.
              if (centerAction != null)
                const SizedBox(width: centerActionSize + OnCareSpacing.s8),
              for (int i = half; i < destinations.length; i++) item(i),
            ],
          ),
        ),
      ),
    );
    final Widget? action = centerAction;
    if (action == null) return bar;
    return SizedBox(
      height: centerActionLift + barHeight + bottom,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(left: 0, right: 0, bottom: 0, child: bar),
          Positioned(top: 0, left: 0, right: 0, child: Center(child: action)),
        ],
      ),
    );
  }
}

/// 하단 내비 가운데의 원형 `+` 버튼 — 브랜드 채움, 흰 아이콘, 바 위로 튀어나온다
/// (#1742). 아이콘 하나뿐이라 [tooltip] 이 무엇을 여는지 말한다.
class AppNavAddButton extends StatelessWidget {
  const AppNavAddButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.icon = Icons.add_rounded,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          color: tokens.brand.primary,
          shape: const CircleBorder(),
          elevation: OnCareShadows.overlayElevation,
          shadowColor: tokens.brand.primary,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: AppBottomNav.centerActionSize,
              child: Icon(
                icon,
                size: OnCareSize.iconLarge,
                color: OnCareColors.textOnFill,
              ),
            ),
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

  /// 1680 — 대시보드·분할 화면.
  wide,
}

/// 웹 페이지 틀(#1696) — 헤더 88(`titleLarge` + `bodySmall` 부제 + 액션), 좌우 16.
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
    this.headerCenter,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final AppWebPageWidth width;

  /// 제목 앞 뒤로가기 등.
  final Widget? leading;

  /// 헤더 가운데 자리 — 트레이너웹 통합 검색 바.
  ///
  /// 제목과 액션 중 넓은 쪽 폭을 **양쪽에 똑같이** 비워 두고 그 사이에 둔다.
  /// 그래서 탭마다 제목 길이·액션 수가 달라도 헤더(=콘텐츠) 폭의 한가운데,
  /// 같은 가로 위치에 선다. 대칭으로 비우면 [OnCareLayout.headerCenterMinWidth]
  /// 보다 좁아질 때만 대칭을 포기하고 제목과 액션 사이 남는 폭을 쓴다(#995).
  /// 자식은 받은 폭을 보고 스스로 아이콘으로 접을 수 있다.
  final Widget? headerCenter;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final double side = tokens.density.pagePadding;
    final Widget titleBlock = Column(
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
                .copyWith(color: OnCareColors.textSecondary),
          ),
      ],
    );
    final Widget header = headerCenter == null
        ? Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: OnCareSpacing.s8),
              ],
              Expanded(child: titleBlock),
              for (final Widget action in actions) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s8),
                action,
              ],
            ],
          )
        : CustomMultiChildLayout(
            delegate: _WebHeaderLayoutDelegate(
              centerMinExtent: tokens.density.iconButton,
            ),
            children: <Widget>[
              LayoutId(
                id: _WebHeaderSlot.start,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (leading != null) ...<Widget>[
                      leading!,
                      const SizedBox(width: OnCareSpacing.s8),
                    ],
                    Flexible(child: titleBlock),
                  ],
                ),
              ),
              LayoutId(id: _WebHeaderSlot.center, child: headerCenter!),
              LayoutId(
                id: _WebHeaderSlot.end,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < actions.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: OnCareSpacing.s8),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ],
          );
    return ColoredBox(
      color: tokens.pageBackground,
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
                  child: header,
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

enum _WebHeaderSlot { start, center, end }

/// [AppWebPage.headerCenter] 를 헤더의 물리적 가운데에 둔다.
///
/// 액션과 제목을 먼저 재고, 둘 중 넓은 폭을 양쪽에 똑같이 비운다 — 탭을 옮겨도
/// 짧은 쪽으로 가운데가 끌려가지 않는다. 대칭 예약 때문에 가운데가
/// [OnCareLayout.headerCenterMinWidth] 아래로 떨어지면 대칭을 포기하고 제목과
/// 액션 사이 남는 폭을 준다. 가운데에는 늘 [centerMinExtent](아이콘 한 칸)만큼은
/// 남기도록 제목 폭을 먼저 제한한다.
class _WebHeaderLayoutDelegate extends MultiChildLayoutDelegate {
  _WebHeaderLayoutDelegate({required this.centerMinExtent});

  final double centerMinExtent;

  static const double _gap = OnCareSpacing.s16;

  @override
  void performLayout(Size size) {
    final Size endSize = layoutChild(
      _WebHeaderSlot.end,
      BoxConstraints.loose(size),
    );
    final double startMax =
        size.width - endSize.width - centerMinExtent - _gap * 2;
    final Size startSize = layoutChild(
      _WebHeaderSlot.start,
      BoxConstraints(
        maxWidth: startMax > 0 ? startMax : 0,
        maxHeight: size.height,
      ),
    );
    positionChild(
      _WebHeaderSlot.start,
      Offset(0, (size.height - startSize.height) / 2),
    );
    positionChild(
      _WebHeaderSlot.end,
      Offset(size.width - endSize.width, (size.height - endSize.height) / 2),
    );

    final double sideWidth = startSize.width > endSize.width
        ? startSize.width
        : endSize.width;
    double centerWidth = (size.width - (sideWidth + _gap) * 2).clamp(
      0.0,
      size.width,
    );
    double centerLeft = (size.width - centerWidth) / 2;

    // 대칭 예약이 가운데를 굶기면 대칭을 포기한다(#995).
    if (centerWidth < OnCareLayout.headerCenterMinWidth) {
      final double freeGap =
          size.width - startSize.width - endSize.width - _gap * 2;
      if (freeGap > centerWidth) {
        centerWidth = freeGap;
        centerLeft = startSize.width + _gap;
      }
    }

    layoutChild(
      _WebHeaderSlot.center,
      BoxConstraints.tightFor(width: centerWidth, height: size.height),
    );
    positionChild(_WebHeaderSlot.center, Offset(centerLeft, 0));
  }

  @override
  bool shouldRelayout(_WebHeaderLayoutDelegate oldDelegate) =>
      centerMinExtent != oldDelegate.centerMinExtent;
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
    final bool hasBadge = badgeCount > 0;
    final Widget iconGlyph = Icon(
      icon,
      size: OnCareSize.iconLarge,
      color: color,
    );
    // 배지는 빨간 알림 점이 아니라 브랜드 남색 원이다(통일 전 트레이너웹 모양).
    // 펼침: 행 오른쪽 끝. 레일: 아이콘 오른쪽 위에 겹친다.
    final Widget icon0 = collapsed && hasBadge
        ? Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              iconGlyph,
              Positioned(
                top: -OnCareSpacing.s4,
                right: -OnCareSpacing.s12,
                width: OnCareSize.countBadgeMin,
                height: OnCareSize.countBadgeMin,
                child: _SidebarCountBadge(count: badgeCount),
              ),
            ],
          )
        : iconGlyph;
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
                if (hasBadge) ...<Widget>[
                  const SizedBox(width: OnCareSpacing.s8),
                  _SidebarCountBadge(count: badgeCount),
                  const SizedBox(width: OnCareSpacing.s12),
                ],
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

/// 사이드바 카운트 배지 — 브랜드 주색으로 채운 고정 지름 원 + 흰 굵은 숫자.
///
/// 숫자 자릿수에 따라 폭이 늘어나는 알약이면 내비 행 끝이 들쭉날쭉해진다.
/// 그래서 원 크기는 고정이고 "99+" 처럼 긴 글자는 원 안에 맞게 줄인다.
class _SidebarCountBadge extends StatelessWidget {
  const _SidebarCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Container(
      key: const ValueKey<String>('app-sidebar-item-badge'),
      width: OnCareSize.countBadgeMin,
      height: OnCareSize.countBadgeMin,
      padding: const EdgeInsets.all(OnCareSpacing.s2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.brand.primary,
        shape: BoxShape.circle,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          count > 99 ? '99+' : '$count',
          maxLines: 1,
          style: tokens
              .text(OnCareTypography.strong(OnCareTypography.caption))
              .copyWith(color: OnCareColors.textOnFill, height: 1),
        ),
      ),
    );
  }
}

/// 로그인·가입·온보딩 틀 — 로고 + 최대 폭 400 + 앱 페이지 배경 + `display` 제목.
///
/// 회원앱(모바일)과 트레이너웹(웹)이 **같은 크기·같은 위치**로 보이도록 안쪽
/// 내용은 모바일 밀도로 그린다(#1770) — 웹 밀도면 입력칸·버튼이 낮아져 두
/// 로그인 화면의 세로 배치가 어긋났다. 브랜드 색과 배경은 앱 것을 그대로 쓴다.
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
      backgroundColor: tokens.pageBackground,
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
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      extensions: <ThemeExtension<dynamic>>[
                        tokens.copyWith(density: OnCareDensity.mobile),
                      ],
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
                              .text(OnCareTypography.display)
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
