import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/app_sidebar.dart';
import 'package:oncare_trainer/app/shell/nav_destinations.dart';
import 'package:oncare_trainer/app/shell/page_scroll_reset.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Persistent console shell: a left [AppSidebar] plus the active branch.
///
/// The trainer surface is a desktop/tablet web console, so navigation is
/// a vertical sidebar rather than the phone-era bottom tab bar. Three
/// responsive forms, keyed off the viewport:
///
/// | 뷰포트 | 형태 |
/// | --- | --- |
/// | ≥ 1280 | 사이드바 펼침 (아이콘 + 라벨 + 프로필) |
/// | ≥ 1024 | 아이콘 레일 (라벨은 툴팁) |
/// | < 1024 | 드로어 + 상단 메뉴 버튼 |
///
/// Branch order matches [navDestinations]; the trailing branch (내 정보 /
/// 설정) has no nav row — it is reached from the sidebar footer.
class AppShell extends StatefulWidget {
  /// Creates the shell around the current [navigationShell] branch.
  const AppShell({
    required this.navigationShell,
    required this.location,
    super.key,
  });

  /// The indexed-stack shell driving branch switching + state retention.
  final StatefulNavigationShell navigationShell;

  /// Current router location, including query parameters.
  final String location;

  /// Branch index of the 내 정보 / 설정 page — the one branch that is not
  /// a nav destination.
  static int get myBranchIndex => navDestinations.length;

  /// Branch index of 알림함. 상담 요청과 같은 이유로 맨 뒤에 붙인다 — 앞에
  /// 끼우면 `myBranchIndex` 가 밀려 푸터 선택이 조용히 깨진다. (#503)
  static int get notificationsBranchIndex => myBranchIndex + 1;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final ValueNotifier<int> _scrollReset = ValueNotifier<int>(0);

  void _requestScrollReset() => _scrollReset.value++;

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestScrollReset();
      });
    }
  }

  @override
  void dispose() {
    _scrollReset.dispose();
    super.dispose();
  }

  void _goBranch(int index) {
    // Tapping the active destination resets it to its branch root (e.g.
    // 고객 상세에서 l.clientsTitle을 다시 누르면 목록으로) — the standard console
    // behaviour; tapping another switches branch, keeping its state.
    _requestScrollReset();
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _goDashboard() {
    _requestScrollReset();
    context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < OnCareLayout.sidebarDrawerBreakpoint;
    final expanded = width >= OnCareLayout.sidebarExpandBreakpoint;
    final onMy = widget.navigationShell.currentIndex == AppShell.myBranchIndex;

    final shell = PageScrollResetScope(
      notifier: _scrollReset,
      child: widget.navigationShell,
    );

    if (compact) {
      return Scaffold(
        backgroundColor: OnCareColors.surfacePage,
        drawer: Drawer(
          width: OnCareLayout.sidebarWidth,
          backgroundColor: OnCareColors.surfaceCard,
          child: Builder(
            builder: (drawerContext) => AppSidebar(
              currentIndex: widget.navigationShell.currentIndex,
              profileSelected: onMy,
              expanded: true,
              onSelect: _goBranch,
              onHome: _goDashboard,
              onNavigate: () => Navigator.of(drawerContext).maybePop(),
            ),
          ),
        ),
        appBar: _CompactBar(onHome: _goDashboard),
        body: shell,
      );
    }

    return Scaffold(
      backgroundColor: OnCareColors.surfacePage,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSidebar(
            currentIndex: widget.navigationShell.currentIndex,
            profileSelected: onMy,
            expanded: expanded,
            onSelect: _goBranch,
            onHome: _goDashboard,
          ),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

/// Top bar for the drawer (narrow) form — the menu button plus the
/// wordmark, since the sidebar's brand block is off-screen there.
class _CompactBar extends StatelessWidget implements PreferredSizeWidget {
  const _CompactBar({required this.onHome});

  final VoidCallback onHome;

  /// 좁은 화면 상단바 높이. 패키지에 웹 상단바 토큰이 없어 부품 치수로 둔다.
  static const double _barHeight = 52;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return SafeArea(
      bottom: false,
      child: Container(
        height: _barHeight,
        padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
        decoration: const BoxDecoration(
          color: OnCareColors.surfaceCard,
          border: Border(bottom: BorderSide(color: OnCareColors.lineStrong)),
        ),
        child: Row(
          children: <Widget>[
            AppIconButton(
              icon: Icons.menu_rounded,
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
              color: OnCareColors.textSecondary,
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            const SizedBox(width: OnCareSpacing.s4),
            Flexible(
              child: InkWell(
                key: const ValueKey<String>('compact-brand-home'),
                onTap: onHome,
                borderRadius: OnCareRadius.mdAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OnCareSpacing.s4,
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(
                          text: 'On-Care ',
                          style: TextStyle(color: OnCareColors.textPrimary),
                        ),
                        TextSpan(
                          text: l.appWordmarkTrainer,
                          style: TextStyle(color: tokens.brand.primary),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    style: tokens.text(OnCareTypography.titleMedium),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
