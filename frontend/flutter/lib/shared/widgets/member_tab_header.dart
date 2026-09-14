import 'package:flutter/material.dart';

import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 네 메인 탭(홈·식단·운동·MY)이 함께 쓰는 머리 — [AppTabHeader] 에 알림 벨과
/// 탭별 동작 하나를 얹는다(#1699).
///
/// 벨의 새 알림 점은 화면이 서버 미읽음을 받아 넘긴다. 이 위젯은 알림을 모른다.
class MemberTabHeader extends StatelessWidget implements PreferredSizeWidget {
  const MemberTabHeader({
    super.key,
    required this.title,
    required this.trailingAction,
    this.leading,
    this.onBell,
    this.onCalendar,
    this.bellHasUnread = false,
  });

  final String title;
  final Widget trailingAction;
  final Widget? leading;
  final VoidCallback? onBell;

  /// 캘린더 버튼은 지금 쓰지 않는다. 되살릴 수 있어 자리만 남겨 둔다(#1055).
  final VoidCallback? onCalendar;

  /// 벨에 새 알림 점을 띄울지.
  final bool bellHasUnread;

  @override
  Size get preferredSize => AppTabHeader(title: title).preferredSize;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppTabHeader(
      title: title,
      leading: leading,
      actions: <Widget>[
        HeaderActionButton(
          icon: Icons.notifications_none_rounded,
          tooltip: l.pageNotificationTitle,
          showDot: bellHasUnread,
          onPressed: onBell,
        ),
        trailingAction,
      ],
    );
  }
}

/// 헤더 오른쪽의 옅은 채움 아이콘 버튼 + 새 소식 점.
///
/// [enabled] 를 [onPressed] 와 따로 둔다. 쓸 수 없다는 것과 눌러도 소용없다는
/// 것은 다르다 — 왜 쓸 수 없는지 알려 주려면 흐린 채로도 탭을 받아야 한다(#786).
class HeaderActionButton extends StatelessWidget {
  const HeaderActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.showDot = false,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool showDot;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Widget button = enabled
        ? AppIconButton(
            icon: icon,
            tooltip: tooltip,
            onPressed: onPressed,
            variant: AppIconButtonVariant.tonal,
          )
        : DecoratedBox(
            decoration: const BoxDecoration(
              color: OnCareColors.surfaceInput,
              borderRadius: OnCareRadius.mdAll,
            ),
            child: AppIconButton(
              icon: icon,
              tooltip: tooltip,
              onPressed: onPressed,
              color: OnCareColors.textDisabled,
            ),
          );
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        button,
        if (showDot)
          const Positioned(
            top: OnCareSpacing.s8,
            right: OnCareSpacing.s8,
            child: AppStatusDot(),
          ),
      ],
    );
  }
}

/// 서비스 로고. 로그인 화면과 홈 머리가 같은 그림으로 같은 서비스를 가리킨다
/// (#1055).
class MemberLogo extends StatelessWidget {
  const MemberLogo({super.key, this.size = OnCareSize.iconLarge});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/oncare-logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      // 자산이 빠져도 머리는 그려야 한다.
      errorBuilder: (BuildContext _, Object _, StackTrace? _) => Icon(
        Icons.favorite_rounded,
        size: size,
        color: context.oncare.brand.primary,
      ),
    );
  }
}
