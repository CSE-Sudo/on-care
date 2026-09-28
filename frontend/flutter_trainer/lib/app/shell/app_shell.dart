import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/app_icons.dart';
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

  /// Root location of branch [index] — what a sidebar tap opens when there
  /// is no [StatefulNavigationShell] to switch (the 404 page sits outside
  /// the shell route). Out-of-range indexes fall back to the 대시보드.
  static String branchRoot(int index) {
    if (index >= 0 && index < navDestinations.length) {
      return navDestinations[index].route;
    }
    if (index == myBranchIndex) return AppRoutes.my;
    if (index == notificationsBranchIndex) return AppRoutes.notifications;
    return AppRoutes.dashboard;
  }

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
    return AppShellFrame(
      currentIndex: widget.navigationShell.currentIndex,
      profileSelected:
          widget.navigationShell.currentIndex == AppShell.myBranchIndex,
      onSelect: _goBranch,
      onHome: _goDashboard,
      body: PageScrollResetScope(
        notifier: _scrollReset,
        child: widget.navigationShell,
      ),
    );
  }
}

/// The console chrome — sidebar (expanded / rail / drawer by viewport)
/// around [body] — without the branch bookkeeping of [AppShell].
///
/// [AppShell] wraps the active branch in it; the 404 page wraps its
/// message in it too, so a mistyped or stale URL still shows the sidebar
/// and a way back instead of a bare error screen. (#2294)
class AppShellFrame extends StatelessWidget {
  /// Creates the console chrome around [body].
  const AppShellFrame({
    required this.currentIndex,
    required this.onSelect,
    required this.onHome,
    required this.body,
    this.profileSelected = false,
    super.key,
  });

  /// Highlighted branch; an index no row owns (e.g. `-1`) selects none.
  final int currentIndex;

  /// Whether the 내 정보 footer is highlighted.
  final bool profileSelected;

  /// Invoked with the branch index when a sidebar row is tapped.
  final ValueChanged<int> onSelect;

  /// Opens the 대시보드 from the brand.
  final VoidCallback onHome;

  /// The page area to the right of (or below, when compact) the sidebar.
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < OnCareLayout.sidebarDrawerBreakpoint;
    final expanded = width >= OnCareLayout.sidebarExpandBreakpoint;

    if (compact) {
      return Scaffold(
        backgroundColor: OnCareColors.surfacePage,
        drawer: Drawer(
          width: OnCareLayout.sidebarWidth,
          backgroundColor: OnCareColors.surfaceCard,
          child: Builder(
            builder: (drawerContext) => AppSidebar(
              currentIndex: currentIndex,
              profileSelected: profileSelected,
              expanded: true,
              onSelect: onSelect,
              onHome: onHome,
              // 드로어만 닫는다. 내비게이터 pop 으로 닫으면, 탭한 쪽이 셸
              // 밖 페이지(404)일 때 이미 바뀐 라우트 목록에서 페이지를 하나 더
              // 빼려다 go_router 가 깨진다. (#2294)
              onNavigate: () => Scaffold.of(drawerContext).closeDrawer(),
            ),
          ),
        ),
        appBar: _CompactBar(onHome: onHome),
        body: body,
      );
    }

    return Scaffold(
      backgroundColor: OnCareColors.surfacePage,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSidebar(
            currentIndex: currentIndex,
            profileSelected: profileSelected,
            expanded: expanded,
            onSelect: onSelect,
            onHome: onHome,
          ),
          Expanded(child: body),
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
              icon: AppIcons.menu,
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
