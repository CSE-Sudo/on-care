import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/app_shell.dart';
import 'package:oncare_trainer/app/shell/nav_destinations.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/my/data/trainer_settings.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// The console's left navigation column.
///
/// Three presentations, all driven by [expanded] / the host's breakpoint:
///  * expanded (≥ [OnCareLayout.sidebarExpandBreakpoint]) — brand, grouped
///    labelled destinations, trainer profile footer;
///  * rail (≥ [OnCareLayout.sidebarDrawerBreakpoint]) — icons + tooltips;
///  * drawer (below that) — the expanded form inside a [Drawer].
///
/// The profile footer is deliberately NOT a nav destination: 내 정보 /
/// 설정 is opened once in a while, so it sits below the divider rather
/// than competing with the five daily surfaces.
class AppSidebar extends ConsumerWidget {
  /// Creates the sidebar.
  const AppSidebar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.onHome,
    required this.expanded,
    this.profileSelected = false,
    this.onNavigate,
  });

  /// Index of the active branch (matches [navDestinations] order). Values
  /// beyond the destination list (the 내 정보 branch) select nothing.
  final int currentIndex;

  /// Whether the 내 정보 / 설정 branch is active — highlights the footer
  /// instead of a nav row.
  final bool profileSelected;

  /// Invoked with the branch index when a destination is tapped.
  final ValueChanged<int> onSelect;

  /// Opens the dashboard from the product brand.
  final VoidCallback onHome;

  /// Whether labels are shown (false renders the icon rail).
  final bool expanded;

  /// Called after any navigation — the drawer host uses it to close
  /// itself so the drawer doesn't stay open over the new page.
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // Badges are live counters, not decoration: they're the reason a
    // trainer looks at the sidebar between tasks.
    // 알림 설정이 이 배지를 끈다 — 설정 화면이 "사이드바 뱃지로 알려드려요"
    // 라고 적어 두고 정작 아무 데서도 읽지 않아, 꺼도 배지가 그대로였다(#817).
    final settings = ref.watch(trainerSettingsProvider);
    final unread = settings.newMessageAlerts
        ? ref
              .watch(unreadCountsProvider)
              .valueOrNull
              ?.values
              .fold<int>(0, (sum, n) => sum + n)
        : null;
    // 완료한 수업은 빠진 '남은 일감' 수. 대시보드 KPI 의 '오늘 예약' 과는
    // 다른 숫자이고, 달라야 한다(#860).
    final pendingSessions = ref
        .watch(todayPendingSessionCountProvider)
        .valueOrNull;
    final profile = ref.watch(sessionControllerProvider).profile;
    // 상담 요청 only exists against the real API — the demo has no member
    // backend to receive requests from, so the row is not built at all
    // there and the demo sidebar stays exactly as it was. (#467)
    // 알림함도 실 API 빌드에서만 — 데모에는 알림을 만드는 회원 백엔드가 없어
    // 늘 비어 있는 행이 하나 더 생길 뿐이다. (#503)
    final notificationInbox = ref.watch(notificationInboxEnabledProvider);
    final unreadNotifications = notificationInbox
        ? ref.watch(trainerUnreadNotificationsProvider).valueOrNull
        : null;

    return Container(
      width: expanded
          ? OnCareLayout.sidebarWidth
          : OnCareLayout.sidebarRailWidth,
      decoration: const BoxDecoration(
        color: OnCareColors.surfaceCard,
        border: Border(right: BorderSide(color: OnCareColors.lineStrong)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Brand(
              expanded: expanded,
              onTap: () {
                onHome();
                onNavigate?.call();
              },
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(OnCareSpacing.s8),
                children: <Widget>[
                  for (var i = 0; i < navDestinations.length; i++) ...<Widget>[
                    if (expanded && (i == 0 || i == 4))
                      _NavGroupLabel(
                        label: i == 0
                            ? l.navOperationsGroup
                            : l.navCoachingGroup,
                      ),
                    _NavTile(
                      destination: navDestinations[i],
                      selected: currentIndex == i,
                      expanded: expanded,
                      badgeCount: switch (navDestinations[i].badge) {
                        NavBadge.unreadMessages => unread,
                        NavBadge.todayPendingSessions => pendingSessions,
                        // Not reachable from this loop — 상담 요청 is not in
                        // navDestinations and is rendered below with its
                        // count passed in directly.
                        NavBadge.pendingConsultations => null,
                        NavBadge.unreadNotifications => null,
                        NavBadge.none => null,
                      },
                      onTap: () {
                        onSelect(i);
                        onNavigate?.call();
                      },
                    ),
                  ],
                  if (notificationInbox)
                    _NavTile(
                      destination: notificationsDestination,
                      selected:
                          currentIndex == AppShell.notificationsBranchIndex,
                      expanded: expanded,
                      badgeCount: unreadNotifications,
                      onTap: () {
                        onSelect(AppShell.notificationsBranchIndex);
                        onNavigate?.call();
                      },
                    ),
                ],
              ),
            ),
            _ProfileFooter(
              profile: profile,
              expanded: expanded,
              selected: profileSelected,
              onTap: () {
                context.go(AppRoutes.my);
                onNavigate?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavGroupLabel extends StatelessWidget {
  const _NavGroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OnCareSpacing.s12,
        OnCareSpacing.s12,
        OnCareSpacing.s12,
        OnCareSpacing.s4,
      ),
      child: Text(
        label,
        style: context.oncare
            .text(OnCareTypography.strong(OnCareTypography.caption))
            .copyWith(color: OnCareColors.textTertiary),
      ),
    );
  }
}

/// Logo + wordmark. The 트레이너 word keeps the brand primary so the two
/// On-Care clients read as one service with distinct audiences.
class _Brand extends StatelessWidget {
  const _Brand({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  /// 로고 원 지름. 토큰 목록에 없는 부품 치수다.
  static const double _logoSize = 40;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    // The logo art is already a filled circle — putting it on a rounded
    // square tile drew a second, competing shape around it.
    final logo = SizedBox.square(
      dimension: _logoSize,
      child: ClipOval(
        child: Image.asset(
          'assets/images/oncare-logo.png',
          fit: BoxFit.cover,
          // The logo is a bundled asset; if it ever fails to decode, fall
          // back to a glyph rather than blowing a red box into the shell.
          errorBuilder: (context, error, stack) => Icon(
            Icons.favorite_rounded,
            size: OnCareSize.iconLarge,
            color: tokens.brand.primary,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: AppLocalizations.of(context).dashTitle,
      child: InkWell(
        key: const ValueKey<String>('sidebar-brand-home'),
        onTap: onTap,
        child: Container(
          // Taller than the page header so the brand has room to breathe now
          // that no rule separates it from the nav.
          height: OnCareLayout.webHeaderHeight + OnCareSpacing.s16,
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? OnCareSpacing.s16 : OnCareSpacing.s12,
          ),
          alignment: expanded ? Alignment.centerLeft : Alignment.center,
          child: expanded
              ? Row(
                  children: <Widget>[
                    logo,
                    const SizedBox(width: OnCareSpacing.s8),
                    Expanded(
                      // 서비스 이름이 `On-Care 트레…` 가 되면 이 콘솔이 무엇인지가
                      // 사라진다 — 좁으면 글씨를 줄인다. (#1004)
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              const TextSpan(
                                text: 'On-Care ',
                                style: TextStyle(
                                  color: OnCareColors.textPrimary,
                                ),
                              ),
                              TextSpan(
                                text: AppLocalizations.of(
                                  context,
                                ).appWordmarkTrainer,
                                style: TextStyle(color: tokens.brand.primary),
                              ),
                            ],
                          ),
                          style: tokens.text(OnCareTypography.titleMedium),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                )
              : Tooltip(
                  message: AppLocalizations.of(context).appTitle,
                  child: logo,
                ),
        ),
      ),
    );
  }
}

/// One destination row — the package [AppSidebarItem] (옅은 브랜드 채움 +
/// 왼쪽 막대, 높이 44·아이콘 24). 알림 수는 행 오른쪽 끝의 브랜드 남색 원
/// 배지이고, 레일에서는 아이콘 오른쪽 위에 겹친다.
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.badgeCount,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final bool expanded;
  final int? badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = navLabel(AppLocalizations.of(context), destination.label);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s2),
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        child: AppSidebarItem(
          key: ValueKey<String>('sidebar-${destination.route}'),
          icon: selected ? destination.activeIcon : destination.icon,
          label: label,
          selected: selected,
          collapsed: !expanded,
          badgeCount: badgeCount ?? 0,
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Trainer identity + the entry to 내 정보 / 설정.
class _ProfileFooter extends StatelessWidget {
  const _ProfileFooter({
    required this.profile,
    required this.expanded,
    required this.selected,
    required this.onTap,
  });

  final TrainerProfile? profile;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    // Demo mode carries no profile; fall back to the seed identity so
    // the footer never renders as a nameless blank.
    final name = profile?.name ?? seedTrainerProfile.name;
    final gym = profile?.gym.name ?? seedTrainerProfile.gym.name;
    final avatar = AppAvatar(name: name.isEmpty ? l.appAvatarFallback : name);

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: OnCareColors.lineStrong)),
      ),
      padding: const EdgeInsets.all(OnCareSpacing.s8),
      child: Material(
        color: selected ? tokens.brand.surface : Colors.transparent,
        borderRadius: OnCareRadius.mdAll,
        child: InkWell(
          key: const ValueKey<String>('sidebar-profile'),
          onTap: onTap,
          borderRadius: OnCareRadius.mdAll,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? OnCareSpacing.s8 : 0,
              vertical: OnCareSpacing.s8,
            ),
            child: expanded
                ? Row(
                    children: <Widget>[
                      avatar,
                      const SizedBox(width: OnCareSpacing.s8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: tokens
                                  .text(OnCareTypography.label)
                                  .copyWith(color: OnCareColors.textPrimary),
                            ),
                            Text(
                              gym,
                              overflow: TextOverflow.ellipsis,
                              style: tokens
                                  .text(OnCareTypography.caption)
                                  .copyWith(color: OnCareColors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.settings_rounded,
                        size: OnCareSize.iconSmall,
                        color: OnCareColors.textTertiary,
                      ),
                    ],
                  )
                : Tooltip(
                    message: l.sidebarMyTooltip(name),
                    child: Center(child: avatar),
                  ),
          ),
        ),
      ),
    );
  }
}
