import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/page_scroll_reset.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 알림함 — 트레이너가 놓친 변화를 나중에 확인하는 자리. (#503)
///
/// 전에는 사이드바 배지와 대시보드 강조뿐이라, 그 순간을 지나가면 다시 볼
/// 방법이 없었다. 회원의 메시지·상담 요청·예약은 트레이너가 그 화면에 직접
/// 들어가야만 알 수 있었다.
///
/// 데모 빌드는 이 화면에 닿지 않는다 — 저장소가 인박스 없음을 보고하고
/// 사이드바 진입점이 그려지지 않는다([notificationInboxEnabledProvider]).
class NotificationsPage extends ConsumerWidget {
  /// Creates the inbox page.
  const NotificationsPage({super.key});

  /// 알림 종류별 이동할 곳. 모르는 종류는 이동하지 않는다.
  ///
  /// 건강 목표 변경은 **그 회원** 상세로 간다(#1832). 회원 id 가 빠진 알림이면
  /// 고객 목록으로 간다 — 누구의 목표인지는 본문에 적혀 있다.
  @visibleForTesting
  static String? targetOf(TrainerNotification notification) =>
      switch (notification.kind) {
        TrainerNotificationKind.message => AppRoutes.clients,
        TrainerNotificationKind.consultation => AppRoutes.schedule,
        TrainerNotificationKind.reservation => AppRoutes.schedule,
        TrainerNotificationKind.healthGoal => switch (notification.subjectId) {
          final String id => AppRoutes.clientDetail(id),
          null => AppRoutes.clients,
        },
        TrainerNotificationKind.other => null,
      };

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    TrainerNotification notification,
  ) async {
    final String? target = targetOf(notification);
    // 읽음 처리는 이동과 무관하게 먼저 한다 — 갈 곳이 없는 알림도 확인하면
    // 배지에서 빠져야 한다.
    if (!notification.read) {
      try {
        await ref
            .read(trainerNotificationRepositoryProvider)
            .markRead(notification.id);
        ref
          ..invalidate(trainerNotificationsProvider)
          ..invalidate(trainerUnreadNotificationsProvider);
      } catch (_) {
        // 읽음 처리 실패로 이동까지 막지 않는다. 다음 조회에서 다시 미읽음으로
        // 보이는 편이, 누른 알림이 아무 반응도 없는 것보다 낫다.
      }
    }
    if (target != null && context.mounted) context.go(target);
  }

  Future<void> _readAll(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l = AppLocalizations.of(context);
    try {
      await ref.read(trainerNotificationRepositoryProvider).markAllRead();
    } catch (_) {
      if (!context.mounted) return;
      showAppToast(context, l.notifReadAllFailed, type: AppToastType.error);
      return;
    }
    ref
      ..invalidate(trainerNotificationsProvider)
      ..invalidate(trainerUnreadNotificationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final notifications = ref.watch(trainerNotificationsProvider);
    final unread = ref.watch(trainerUnreadNotificationsProvider).valueOrNull;

    return AppWebPage(
      title: l.notifTitle,
      subtitle: unread == null
          ? null
          : (unread > 0 ? l.notifUnreadCount(unread) : l.notifAllRead),
      width: AppWebPageWidth.narrow,
      actions: <Widget>[
        if (unread != null && unread > 0)
          AppButton(
            label: l.notifReadAll,
            leadingIcon: Icons.done_all_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () => _readAll(context, ref),
          ),
      ],
      body: PageScrollResetListener(
        child: notifications.when(
          loading: () => const AppLoading(),
          error: (error, _) => _ErrorView(
            message: serverDetailOr(
              l,
              error is AppError ? error.message : null,
              l.notifLoadFailed,
            ),
            retryLabel: l.actionRetry,
            onRetry: notifications.isLoading
                ? null
                : () => ref.invalidate(trainerNotificationsProvider),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return AppEmptyState(
                title: l.notifEmpty,
                icon: Icons.notifications_none_rounded,
              );
            }
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: OnCareSpacing.s8),
              itemBuilder: (context, i) => _NotificationTile(
                notification: rows[i],
                onTap: () => _open(context, ref, rows[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 오류 화면. [AppErrorState] 와 같은 모양이지만 재시도 버튼에 테스트·자동화가
/// 찾는 Key(`notifications-retry`)를 달아야 해서 버튼을 따로 둔다.
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(OnCareSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppEmptyState(
              title: message,
              icon: Icons.cloud_off_rounded,
              placement: AppStatePlacement.card,
            ),
            AppButton(
              key: const ValueKey<String>('notifications-retry'),
              label: retryLabel,
              variant: AppButtonVariant.secondary,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final TrainerNotification notification;
  final VoidCallback onTap;

  IconData get _icon => switch (notification.kind) {
    TrainerNotificationKind.message => Icons.chat_bubble_outline_rounded,
    TrainerNotificationKind.consultation => Icons.mark_email_unread_rounded,
    TrainerNotificationKind.reservation => Icons.event_available_rounded,
    TrainerNotificationKind.healthGoal => Icons.flag_rounded,
    TrainerNotificationKind.other => Icons.notifications_none_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final bool unread = !notification.read;
    // 미읽음은 옅은 브랜드 채움 + 빨간 점 + 제목 600 으로 구분한다(#1690).
    // 진한 남색 채움은 목록 글자를 가려 규격에서 뺐다(#1703).
    return DecoratedBox(
      decoration: BoxDecoration(
        color: unread ? tokens.brand.surface : OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
      ),
      child: AppListRow(
        key: ValueKey<String>('notification-${notification.id}'),
        title: notification.title,
        subtitle: notification.body.isEmpty ? null : notification.body,
        unread: unread,
        onTap: onTap,
        leading: Icon(
          _icon,
          size: OnCareSize.iconMedium,
          color: unread ? tokens.brand.primary : OnCareColors.textSecondary,
        ),
        trailing: Text(
          notification.timeAgo,
          style: tokens
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textTertiary),
        ),
      ),
    );
  }
}
