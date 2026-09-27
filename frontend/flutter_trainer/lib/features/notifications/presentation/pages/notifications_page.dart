import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/page_scroll_reset.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/trainer_notification_text.dart';
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
///
/// 서버는 한 쪽(100건)씩 준다. 목록 끝에 닿거나 "지난 알림 더 보기" 를 누르면
/// 다음 쪽을 이어 붙인다(#2293). 전에는 100건이 전부라, 그보다 오래된 미읽음은
/// 배지에만 잡히고 목록 어디에서도 볼 수 없었다.
class NotificationsPage extends ConsumerWidget {
  /// Creates the inbox page.
  const NotificationsPage({super.key});

  /// 알림 종류별 이동할 곳. 모르는 종류는 이동하지 않는다.
  ///
  /// 건강 목표 변경은 **그 회원** 상세로 간다(#1832). 회원 id 가 빠진 알림이면
  /// 고객 목록으로 간다 — 누구의 목표인지는 본문에 적혀 있다. 회원 이름 변경도
  /// 같은 길이다(#2065). 회원이 떠난 알림은 이동하지 않는다(#2174).
  ///
  /// 상담은 상담 요청함으로, 예약은 그 수업 날짜의 스케줄로, 담당 요청 수락은
  /// 새 담당 회원 상세로, 거절은 고객 목록으로 간다(#2292). 대상이 기록되기
  /// 전의 옛 알림은 전처럼 오늘 스케줄로 간다. 회원 탈퇴로 사라진 상담 요청은
  /// 상담 요청함으로 간다(#1632).
  @visibleForTesting
  static String? targetOf(
    TrainerNotification notification,
  ) => switch (notification.kind) {
    // 메시지는 보낸 회원의 대화로 간다(#2291). 보낸 회원이 기록되기 전의
    // 옛 알림은 누구와의 대화인지 몰라 메시지 목록으로 간다.
    TrainerNotificationKind.message => switch (notification.subjectId) {
      final String id => AppRoutes.messagesFor(id),
      null => AppRoutes.messages,
    },
    // 옛 상담 알림에는 담당 요청 결과도 섞여 있어(같은 종류로 남았다)
    // 상담 요청함이 맞는 곳인지 알 수 없다 — 회원이 기록된 알림만 보낸다.
    TrainerNotificationKind.consultation => switch (notification.subjectId) {
      String() => AppRoutes.consultations,
      null => AppRoutes.schedule,
    },
    TrainerNotificationKind.reservation => switch (notification.targetDate) {
      final String date => AppRoutes.scheduleAt(date: date),
      null => AppRoutes.schedule,
    },
    TrainerNotificationKind.inviteAccepted => switch (notification.subjectId) {
      final String id => AppRoutes.clientDetail(id),
      null => AppRoutes.clients,
    },
    TrainerNotificationKind.inviteRejected => AppRoutes.clients,
    // 요청은 사라졌지만 남은 요청을 이어 볼 자리다(#1632). 떠난 회원 상세는
    // 열 수 없어 회원으로 가지 않는다.
    TrainerNotificationKind.consultationWithdrawn => AppRoutes.consultations,
    TrainerNotificationKind.healthGoal ||
    TrainerNotificationKind.memberName => switch (notification.subjectId) {
      final String id => AppRoutes.clientDetail(id),
      null => AppRoutes.clients,
    },
    // 떠난 회원의 상세는 더 열 수 없다(#2174).
    TrainerNotificationKind.memberLeft || TrainerNotificationKind.other => null,
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
        // 이어 받은 과거 쪽은 다시 읽지 않으므로 여기서 읽음을 비춘다.
        ref
            .read(trainerNotificationPagingProvider.notifier)
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
    // 서버는 쪽과 무관하게 전체를 읽음으로 바꾼다. 받아 둔 과거 쪽도 같게 비춘다.
    ref.read(trainerNotificationPagingProvider.notifier).markAllRead();
    ref
      ..invalidate(trainerNotificationsProvider)
      ..invalidate(trainerUnreadNotificationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final notifications = ref.watch(trainerNotificationsProvider);
    final TrainerNotificationPaging paging = ref.watch(
      trainerNotificationPagingProvider,
    );
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
          data: (first) {
            final TrainerNotificationInbox inbox = mergeTrainerNotifications(
              first,
              paging,
            );
            final List<TrainerNotification> rows = inbox.items;
            if (rows.isEmpty) {
              return AppEmptyState(
                title: l.notifEmpty,
                icon: Icons.notifications_none_rounded,
              );
            }
            void loadMore() => ref
                .read(trainerNotificationPagingProvider.notifier)
                .loadMore(first);
            final bool footer = inbox.hasMore || inbox.reachedEnd;
            return NotificationListener<ScrollNotification>(
              // 끝에 가까워지면 알아서 이어 받는다. 실패한 뒤에는 멈춘다 —
              // 스크롤할 때마다 실패한 요청을 되풀이하지 않고 재시도 버튼을 둔다.
              onNotification: (ScrollNotification n) {
                if (n.metrics.extentAfter < _autoLoadExtent && inbox.hasMore) {
                  ref
                      .read(trainerNotificationPagingProvider.notifier)
                      .autoLoadMore(first);
                }
                return false;
              },
              child: ListView.separated(
                itemCount: rows.length + (footer ? 1 : 0),
                separatorBuilder: (_, _) =>
                    const SizedBox(height: OnCareSpacing.s8),
                itemBuilder: (context, i) {
                  if (i == rows.length) {
                    return _LoadMoreFooter(inbox: inbox, onLoadMore: loadMore);
                  }
                  return _NotificationTile(
                    notification: rows[i],
                    onTap: () => _open(context, ref, rows[i]),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 목록 끝에서 몇 픽셀 남았을 때 다음 쪽을 부를지. 한 줄 높이 몇 개 정도 —
/// 끝에 닿기 전에 불러 두면 스크롤이 멈칫하지 않는다.
const double _autoLoadExtent = 240;

/// 목록 맨 아래 — 이어 받는 중·실패·더 보기·끝. (#2293)
///
/// 스크롤이 생기지 않을 만큼 짧은 화면에서도 이어 받을 수 있게 "더 보기"
/// 버튼을 늘 둔다. 첫 쪽만으로 끝난 짧은 알림함에는 아무것도 붙이지 않는다.
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.inbox, required this.onLoadMore});

  final TrainerNotificationInbox inbox;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle caption = tokens
        .text(OnCareTypography.caption)
        .copyWith(color: OnCareColors.textTertiary);
    final Widget child;
    if (inbox.loadingMore) {
      child = const AppLoading.inline(
        key: ValueKey<String>('notifications-loading-more'),
      );
    } else if (inbox.loadMoreError != null) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(l.notifLoadMoreFailed, style: caption),
          const SizedBox(height: OnCareSpacing.s8),
          AppButton(
            key: const ValueKey<String>('notifications-load-more-retry'),
            label: l.actionRetry,
            variant: AppButtonVariant.secondary,
            onPressed: onLoadMore,
          ),
        ],
      );
    } else if (inbox.hasMore) {
      child = AppButton(
        key: const ValueKey<String>('notifications-load-more'),
        label: l.notifLoadMore,
        variant: AppButtonVariant.secondary,
        leadingIcon: Icons.history_rounded,
        onPressed: onLoadMore,
      );
    } else {
      child = Text(
        l.notifNoEarlier,
        key: const ValueKey<String>('notifications-end'),
        style: caption,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s16),
      child: Center(child: child),
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
    TrainerNotificationKind.memberName => Icons.badge_rounded,
    TrainerNotificationKind.memberLeft => Icons.person_remove_rounded,
    TrainerNotificationKind.inviteAccepted => Icons.how_to_reg_rounded,
    TrainerNotificationKind.inviteRejected => Icons.person_off_rounded,
    TrainerNotificationKind.consultationWithdrawn => Icons.event_busy_rounded,
    TrainerNotificationKind.other => Icons.notifications_none_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final bool unread = !notification.read;
    final TrainerNotificationText text = trainerNotificationText(
      AppLocalizations.of(context),
      notification,
    );
    // 미읽음은 옅은 브랜드 채움 + 빨간 점 + 제목 600 으로 구분한다(#1690).
    // 진한 남색 채움은 목록 글자를 가려 규격에서 뺐다(#1703).
    return DecoratedBox(
      decoration: BoxDecoration(
        color: unread ? tokens.brand.surface : OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
      ),
      child: AppListRow(
        key: ValueKey<String>('notification-${notification.id}'),
        title: text.title,
        subtitle: text.body.isEmpty ? null : text.body,
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
