import 'package:flutter/material.dart';

import 'package:oncare_trainer/app/app_icons.dart';
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
    required this.route,
    this.badge = NavBadge.none,
  });

  /// Which label to show. **문자열이 아니라 키다.** 이 리스트는 `const` 라
  /// (브랜치 순서를 구조로 못 박는다) 생성 시점에 로케일을 알 수 없다. 화면이
  /// `navLabel(l, destination.label)` 로 그릴 때 비로소 문구가 정해진다. (#501)
  final NavLabel label;

  /// 켜짐·꺼짐 모두 이 아이콘 하나다(#2466). 회원앱 하단 탭처럼 아이콘은 늘
  /// 채움이고, 선택은 `AppSidebarItem` 의 옅은 브랜드 채움·왼쪽 막대·색으로만
  /// 보인다. 예전(#1703)에는 윤곽/채움 짝이 있는 셋만 선택 때 채움으로 바뀌어
  /// 나머지와 규칙이 갈렸다.
  final IconData icon;

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
    icon: AppIcons.dashboard,
    route: AppRoutes.dashboard,
  ),
  NavDestination(
    label: NavLabel.clients,
    icon: AppIcons.clients,
    route: AppRoutes.clients,
  ),
  NavDestination(
    label: NavLabel.messages,
    icon: AppIcons.chat,
    route: AppRoutes.messages,
    badge: NavBadge.unreadMessages,
  ),
  NavDestination(
    label: NavLabel.schedule,
    icon: AppIcons.calendar,
    route: AppRoutes.schedule,
    badge: NavBadge.todayPendingSessions,
  ),
  NavDestination(
    label: NavLabel.coaching,
    // 회원 상세의 '프로그램' 버튼과 같은 운동 계획서다(#2330). 예전 반짝이(✦)는
    // AI 추천 표시와 같은 모양이라, 사이드바 메뉴가 AI 기능처럼 읽혔다.
    icon: AppIcons.coaching,
    route: AppRoutes.coaching,
  ),
  NavDestination(
    label: NavLabel.reports,
    // 고객 상세의 '리포트' 버튼과 같은 그림이다(#2330) — 같은 화면으로 가는 두
    // 자리가 서로 다른 그림이면 같은 곳인 줄 모른다.
    icon: AppIcons.reports,
    route: AppRoutes.reports,
  ),
];

/// 알림함 — [navDestinations] 밖에 둔다. 실 API 빌드에서만 보이고, 브랜치 인덱스를 사이드바가 직접 넘긴다. (#503)
const NavDestination notificationsDestination = NavDestination(
  label: NavLabel.notifications,
  icon: AppIcons.notifications,
  route: AppRoutes.notifications,
  badge: NavBadge.unreadNotifications,
);
