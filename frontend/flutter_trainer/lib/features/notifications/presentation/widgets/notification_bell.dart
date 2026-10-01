import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/pages/notifications_page.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 화면 머리 오른쪽 끝의 알림 종(#2628).
///
/// 알림은 어디로 가는 메뉴가 아니라 어디서든 확인하는 소식이다. 사이드바의
/// 운영·코칭 묶음 끝에 두면 코칭 항목처럼 읽혀, 모든 화면 머리의 같은 자리에
/// 둔다. 누르면 최근 알림을 그 자리에서 펼치고, 전체는 알림 화면에서 본다.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  /// 펼침에 보이는 최근 알림 수.
  static const int previewCount = 5;

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  final OverlayPortalController _panel = OverlayPortalController();

  /// 펼침 폭 — 알림 한 줄(제목·본문·시각)이 두 줄로 꺾이지 않는 폭.
  static const double _panelWidth = 400;

  void _toggle() => setState(_panel.toggle);

  void _close() {
    if (_panel.isShowing) setState(_panel.hide);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final int unread = ref.watch(trainerUnreadBadgeProvider) ?? 0;
    return AppPopover(
      controller: _panel,
      alignEnd: true,
      width: _panelWidth,
      maxHeight: 520,
      onTapOutside: _close,
      panelKey: const ValueKey<String>('notification-bell-panel'),
      panel: (BuildContext context) => _Panel(onDone: _close),
      anchor: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          AppIconButton(
            key: const ValueKey<String>('notification-bell'),
            icon: AppIcons.notifications,
            tooltip: unread > 0
                ? '${l.navNotifications} · ${l.notifUnreadCount(unread)}'
                : l.navNotifications,
            color: OnCareColors.textSecondary,
            onPressed: _toggle,
          ),
          if (unread > 0)
            Positioned(
              top: -OnCareSpacing.s2,
              right: -OnCareSpacing.s2,
              // 상담 요청·메시지 배지와 같은 공용 배지·같은 남색이다 —
              // 예전 자체 배지는 흰 테두리가 둘려 같은 머리 줄의 상담 배지와
              // 모양이 달랐다(#2808).
              child: IgnorePointer(
                child: AppCountBadge(
                  key: const ValueKey<String>('notification-bell-badge'),
                  count: unread,
                  color: context.oncare.brand.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 펼침 — 머리(제목·모두 읽음), 최근 알림, 아래 `전체 보기`.
class _Panel extends ConsumerWidget {
  const _Panel({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final int unread = ref.watch(trainerUnreadBadgeProvider) ?? 0;
    final AsyncValue<TrainerNotificationPage> page = ref.watch(
      trainerNotificationsProvider,
    );
    final List<TrainerNotification> items =
        (page.valueOrNull?.items ?? const <TrainerNotification>[])
            .take(NotificationBell.previewCount)
            .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OnCareSpacing.s16,
            OnCareSpacing.s12,
            OnCareSpacing.s8,
            OnCareSpacing.s8,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l.notifTitle,
                  style: tokens
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              if (unread > 0)
                AppButton(
                  key: const ValueKey<String>('notification-bell-read-all'),
                  label: l.notifReadAll,
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                  onPressed: () => NotificationsPage.readAll(context, ref),
                ),
            ],
          ),
        ),
        const AppDivider(),
        Flexible(
          child: page.isLoading && items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(OnCareSpacing.s24),
                  child: AppLoading.inline(),
                )
              : items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(OnCareSpacing.s24),
                  child: Text(
                    page.hasError ? l.notifLoadFailed : l.notifEmpty,
                    textAlign: TextAlign.center,
                    style: tokens
                        .text(OnCareTypography.bodySmall)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(OnCareSpacing.s8),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: OnCareSpacing.s4),
                  itemBuilder: (BuildContext context, int i) =>
                      NotificationTile(
                        notification: items[i],
                        // 이동·읽음 처리에 쓸 라우터와 container 를 먼저 잡고
                        // 닫는다 — 닫히면 이 펼침의 context 는 끝난다(#2762).
                        onTap: () {
                          NotificationsPage.open(context, items[i]);
                          onDone();
                        },
                      ),
                ),
        ),
        const AppDivider(),
        AppButton(
          key: const ValueKey<String>('notification-bell-see-all'),
          label: l.notifSeeAll,
          variant: AppButtonVariant.text,
          onPressed: () {
            onDone();
            // 보던 화면을 적어 두어 알림 화면의 뒤로 가기가 그리로 돌아간다.
            context.go(
              AppRoutes.notificationsFrom(
                GoRouterState.of(context).uri.toString(),
              ),
            );
          },
        ),
      ],
    );
  }
}
