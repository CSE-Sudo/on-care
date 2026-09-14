import 'package:flutter/material.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// Which live counter, if any, a destination shows as a badge.
enum NavBadge {
  /// No badge.
  none,

  /// Total unread client messages (답장 필요).
  unreadMessages,

  /// 오늘 아직 처리하지 않은(예정) 세션 수. 완료한 수업과 공백 슬롯은
  /// 빠진다 — 배지는 "여기 처리할 게 남았다" 는 신호다. (#860)
  todayPendingSessions,

  /// Undecided consultation requests. Supplied by the sidebar directly
  /// rather than looked up from [navDestinations] — this destination is
  /// conditional, so it is not in that list. (#467)
  pendingConsultations,

  /// Unread trainer notifications. Supplied by the sidebar directly for the
  /// same reason as [pendingConsultations]. (#503)
  unreadNotifications,
}

/// One entry in the sidebar. The order of [navDestinations] is the tab
/// order used by the router's [StatefulShellRoute] branches — index N
/// here is branch N there, so the two must never drift apart.
class NavDestination {
  /// Creates a sidebar destination.
  const NavDestination({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
    this.badge = NavBadge.none,
  });

  /// Which label to show. **문자열이 아니라 키다.** 이 리스트는 `const` 라
  /// (브랜치 순서를 구조로 못 박는다) 생성 시점에 로케일을 알 수 없다. 화면이
  /// `navLabel(l, destination.label)` 로 그릴 때 비로소 문구가 정해진다. (#501)
  final NavLabel label;

  /// Icon in the unselected state. `_rounded` 계열만 쓰고, 채움/윤곽 짝이 있는
  /// 아이콘은 선택 상태에만 채움 아이콘을 쓴다(#1703).
  final IconData icon;

  /// Icon in the selected state.
  final IconData activeIcon;

  /// Branch root location.
  final String route;

  /// Live counter rendered next to the label.
  final NavBadge badge;
}

/// The console's five destinations, in branch order.
///
/// One flat list, evenly spaced. An earlier revision split these into
/// 운영 / 코칭 groups with headings; the headings named the obvious and
/// the extra gap made the five rows read as two lists instead of one.
/// 사이드바 라벨 키. 값이 아니라 키인 이유는 [NavDestination.label] 참고.
enum NavLabel {
  dashboard,
  clients,
  schedule,
  messages,
  coaching,
  reports,
  consultations,
  notifications,
}

/// 라벨 키 → 현재 로케일의 문구.
String navLabel(AppLocalizations l, NavLabel label) => switch (label) {
  NavLabel.dashboard => l.navDashboard,
  NavLabel.clients => l.navClients,
  NavLabel.schedule => l.navSchedule,
  NavLabel.messages => l.navMessages,
  NavLabel.coaching => l.navCoaching,
  NavLabel.reports => l.navReports,
  NavLabel.consultations => l.navConsultations,
  NavLabel.notifications => l.navNotifications,
};

const List<NavDestination> navDestinations = <NavDestination>[
  NavDestination(
    label: NavLabel.dashboard,
    icon: Icons.space_dashboard_rounded,
    activeIcon: Icons.space_dashboard_rounded,
    route: AppRoutes.dashboard,
  ),
  NavDestination(
    label: NavLabel.clients,
    icon: Icons.people_outline_rounded,
    activeIcon: Icons.people_rounded,
    route: AppRoutes.clients,
  ),
  NavDestination(
    label: NavLabel.messages,
    icon: Icons.chat_bubble_outline_rounded,
    activeIcon: Icons.chat_bubble_rounded,
    route: AppRoutes.messages,
    badge: NavBadge.unreadMessages,
  ),
  NavDestination(
    label: NavLabel.schedule,
    icon: Icons.calendar_today_rounded,
    activeIcon: Icons.calendar_today_rounded,
    route: AppRoutes.schedule,
    badge: NavBadge.todayPendingSessions,
  ),
  NavDestination(
    label: NavLabel.coaching,
    icon: Icons.auto_awesome_rounded,
    activeIcon: Icons.auto_awesome_rounded,
    route: AppRoutes.coaching,
  ),
  NavDestination(
    label: NavLabel.reports,
    // 고객 상세의 '리포트' 버튼과 같은 막대그래프다 — 같은 화면으로 가는 두
    // 자리가 서로 다른 그림이면 같은 곳인 줄 모른다.
    icon: Icons.bar_chart_rounded,
    activeIcon: Icons.bar_chart_rounded,
    route: AppRoutes.reports,
  ),
];

/// 상담 요청 — deliberately NOT in [navDestinations]. (#467)
///
/// That list defines branch order (index N here is branch N there), and the
/// row is only shown against the real API. A conditional entry would make
/// the list's length depend on build config, which is exactly what
/// `AppShell.myBranchIndex` reads. Keeping it separate lets the sidebar
/// render it with an explicit branch index and leaves the demo untouched.
const NavDestination consultationsDestination = NavDestination(
  label: NavLabel.consultations,
  icon: Icons.mark_email_unread_rounded,
  activeIcon: Icons.mark_email_unread_rounded,
  route: AppRoutes.consultations,
  badge: NavBadge.pendingConsultations,
);

/// 알림함 — [consultationsDestination] 과 같은 이유로 [navDestinations] 밖에
/// 둔다. 실 API 빌드에서만 보이고, 브랜치 인덱스를 사이드바가 직접 넘긴다. (#503)
const NavDestination notificationsDestination = NavDestination(
  label: NavLabel.notifications,
  icon: Icons.notifications_none_rounded,
  activeIcon: Icons.notifications_rounded,
  route: AppRoutes.notifications,
  badge: NavBadge.unreadNotifications,
);
