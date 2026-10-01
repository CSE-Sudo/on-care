import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/app_icons.dart';
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
/// 시간순 목록 위에 종류(전체·메시지·상담 요청·예약·담당 회원 소식) 칩 한 줄을
/// 둔다(#2628). 알림은 훑어보는 소식이라 목록이 주인공이고 종류는 가끔 거르는
/// 보조다 — 회원 탭의 필터 줄과 같은 방식이다. 종류 이름은 설정 › 알림의 수신
/// 항목과 같다. 들어오는 길은 화면 머리의 알림 종이다.
///
/// 서버는 한 쪽(100건)씩 준다. 목록 끝에 닿거나 "지난 알림 더 보기" 를 누르면
/// 다음 쪽을 이어 붙인다(#2293). 전에는 100건이 전부라, 그보다 오래된 미읽음은
/// 배지에만 잡히고 목록 어디에서도 볼 수 없었다.
class NotificationsPage extends ConsumerStatefulWidget {
  /// Creates the inbox page.
  const NotificationsPage({super.key, this.from});

  /// 알림 종을 누른 화면. 뒤로 가기가 그리로 간다 — 없으면 대시보드(#2628).
  final String? from;

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();

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
    // 주의사항 알림은 글이 있는 신체·목표 창의 `건강 목표` 탭까지 연다(#2619).
    TrainerNotificationKind.healthGoal
        when notification.template == 'trainer_health_notes' =>
      switch (notification.subjectId) {
        final String id => AppRoutes.clientDetail(id, openHealthNotes: true),
        null => AppRoutes.clients,
      },
    TrainerNotificationKind.healthGoal ||
    TrainerNotificationKind.memberName => switch (notification.subjectId) {
      final String id => AppRoutes.clientDetail(id),
      null => AppRoutes.clients,
    },
    // 떠난 회원의 상세는 더 열 수 없다(#2174).
    TrainerNotificationKind.memberLeft || TrainerNotificationKind.other => null,
  };

  /// 알림 한 건을 연다 — 그 알림이 가리키는 곳으로 **바로** 가고, 읽음 처리는
  /// 뒤에서 마친다. 머리의 알림 종 팝오버(#2628)도 같은 길을 쓴다.
  ///
  /// 부르는 위젯은 곧 사라질 수 있다 — 팝오버는 항목을 누르는 순간 닫힌다.
  /// 그래서 첫 비동기 작업 전에 라우터와 앱 전체의 [ProviderContainer] 를
  /// 잡아 두고, 이후로는 그 둘만 쓴다(#2762). 전에는 읽음 요청을 기다린 뒤
  /// 이미 닫힌 위젯의 `ref`·`context` 로 이어 가다, 안 읽은 알림만 이동도 배지
  /// 갱신도 빠졌다.
  static void open(BuildContext context, TrainerNotification notification) {
    final GoRouter router = GoRouter.of(context);
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    final String? target = targetOf(notification);
    // 갈 곳이 없는 알림도 확인하면 배지에서 빠져야 한다. 요청 실패로 이동까지
    // 막지 않는다 — 다음 조회에서 다시 미읽음으로 보이는 편이, 누른 알림이
    // 아무 반응도 없는 것보다 낫다.
    if (!notification.read) {
      unawaited(NotificationReadTracker(container).markRead(notification.id));
    }
    if (target != null) router.go(target);
  }

  /// 전체 읽음 처리. 머리의 알림 종 팝오버(#2628)도 같은 길을 쓴다.
  static Future<void> readAll(BuildContext context, WidgetRef ref) async {
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
}

/// 알림 종류 — 설정 › 알림의 수신 항목과 같은 묶음이다(#2628).
enum NotificationGroup {
  all,
  messages,
  consultations,
  reservations,
  members;

  /// [n] 이 이 묶음에 드는가. 모르는 종류는 `전체` 에만 보인다.
  bool includes(TrainerNotification n) => switch (this) {
    NotificationGroup.all => true,
    NotificationGroup.messages => n.kind == TrainerNotificationKind.message,
    NotificationGroup.consultations => switch (n.kind) {
      TrainerNotificationKind.consultation ||
      TrainerNotificationKind.consultationWithdrawn ||
      TrainerNotificationKind.inviteAccepted ||
      TrainerNotificationKind.inviteRejected => true,
      _ => false,
    },
    NotificationGroup.reservations =>
      n.kind == TrainerNotificationKind.reservation,
    NotificationGroup.members => switch (n.kind) {
      TrainerNotificationKind.healthGoal ||
      TrainerNotificationKind.memberName ||
      TrainerNotificationKind.memberLeft => true,
      _ => false,
    },
  };

  String label(AppLocalizations l) => switch (this) {
    NotificationGroup.all => l.notifGroupAll,
    NotificationGroup.messages => l.notifGroupMessages,
    NotificationGroup.consultations => l.myNotifConsultation,
    NotificationGroup.reservations => l.myNotifReservation,
    NotificationGroup.members => l.myNotifMemberUpdates,
  };

  IconData get icon => switch (this) {
    NotificationGroup.all => AppIcons.notifications,
    NotificationGroup.messages => AppIcons.chat,
    NotificationGroup.consultations => AppIcons.consultation,
    NotificationGroup.reservations => AppIcons.eventAvailable,
    NotificationGroup.members => AppIcons.goal,
  };
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  NotificationGroup _group = NotificationGroup.all;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final notifications = ref.watch(trainerNotificationsProvider);
    final TrainerNotificationPaging paging = ref.watch(
      trainerNotificationPagingProvider,
    );
    final int? unread = ref.watch(trainerUnreadBadgeProvider);

    return AppWebPage(
      title: l.notifTitle,
      subtitle: unread == null
          ? null
          : (unread > 0 ? l.notifUnreadCount(unread) : l.notifAllRead),
      // 한 줄 소식을 읽는 목록이라 좁은 폭이 읽기 쉽다 — 넓으면 제목과 시각
      // 사이가 멀어진다.
      width: AppWebPageWidth.narrow,
      // 알림 종이 여는 곳이 이 화면이다 — 여기서는 종을 두지 않는다(#2628).
      showHeaderTrailing: false,
      // 사이드바 탭이 아니라 선택된 탭이 없다 — 돌아갈 길을 제목 옆에 둔다.
      leading: AppBackButton(
        key: const ValueKey<String>('notifications-back'),
        onPressed: () =>
            context.go(AppRoutes.notificationsBackTarget(widget.from)),
      ),
      actions: <Widget>[
        if (unread != null && unread > 0)
          AppButton(
            label: l.notifReadAll,
            leadingIcon: AppIcons.markAllRead,
            variant: AppButtonVariant.secondary,
            onPressed: () => NotificationsPage.readAll(context, ref),
          ),
      ],
      body: PageScrollResetListener(
        child: notifications.when(
          loading: () => const AppLoading(),
          error: (error, _) => AppErrorState(
            retryKey: const ValueKey<String>('notifications-retry'),
            title: serverDetailOr(
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _chips(l),
                const SizedBox(height: OnCareSpacing.s12),
                Expanded(child: _list(context, l, first, inbox)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 목록 위의 종류 칩 한 줄. 좁으면 옆으로 밀어 넘긴다.
  Widget _chips(AppLocalizations l) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: <Widget>[
        for (final NotificationGroup group in NotificationGroup.values)
          Padding(
            padding: const EdgeInsets.only(right: OnCareSpacing.s8),
            child: AppChoiceChip(
              key: ValueKey<String>('notifications-chip-${group.name}'),
              label: group.label(l),
              selected: _group == group,
              onSelected: (_) => setState(() => _group = group),
            ),
          ),
      ],
    ),
  );

  Widget _list(
    BuildContext context,
    AppLocalizations l,
    TrainerNotificationPage first,
    TrainerNotificationInbox inbox,
  ) {
    final List<TrainerNotification> rows = inbox.items
        .where(_group.includes)
        .toList(growable: false);
    // 종류를 골랐는데 비었어도 이어 받을 쪽이 있으면 더 보기를 남긴다 — 오래된
    // 그 종류 알림이 다음 쪽에 있을 수 있다.
    final bool footer = inbox.hasMore || (inbox.reachedEnd && rows.isNotEmpty);
    if (rows.isEmpty && !inbox.hasMore) {
      return AppEmptyState(
        title: _group == NotificationGroup.all
            ? l.notifEmpty
            : l.notifGroupEmpty,
        icon: _group.icon,
      );
    }
    void loadMore() =>
        ref.read(trainerNotificationPagingProvider.notifier).loadMore(first);
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
        key: ValueKey<String>('notifications-list-${_group.name}'),
        itemCount: rows.length + (footer ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: OnCareSpacing.s8),
        itemBuilder: (context, i) {
          if (i == rows.length) {
            return _LoadMoreFooter(inbox: inbox, onLoadMore: loadMore);
          }
          return NotificationTile(
            notification: rows[i],
            onTap: () => NotificationsPage.open(context, rows[i]),
          );
        },
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
        leadingIcon: AppIcons.history,
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

/// 알림 한 줄 — 알림 화면과 머리의 알림 종 팝오버(#2628)가 함께 쓴다.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
  });

  final TrainerNotification notification;
  final VoidCallback onTap;

  IconData get _icon => switch (notification.kind) {
    TrainerNotificationKind.message => AppIcons.chat,
    TrainerNotificationKind.consultation => AppIcons.consultation,
    TrainerNotificationKind.reservation => AppIcons.eventAvailable,
    TrainerNotificationKind.healthGoal => AppIcons.goal,
    TrainerNotificationKind.memberName => AppIcons.badge,
    TrainerNotificationKind.memberLeft => AppIcons.memberLeft,
    TrainerNotificationKind.inviteAccepted => AppIcons.inviteAccepted,
    TrainerNotificationKind.inviteRejected => AppIcons.personOff,
    TrainerNotificationKind.consultationWithdrawn => AppIcons.eventBusy,
    TrainerNotificationKind.other => AppIcons.notifications,
  };

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final bool unread = !notification.read;
    final TrainerNotificationText text = trainerNotificationText(
      AppLocalizations.of(context),
      notification,
    );
    // 미읽음은 옅은 브랜드 채움 + 제목 600 으로 구분한다(#1690). 빨간 점은
    // 뺐다 — 읽으면 채움이 사라져 그것만으로 충분하다(#2628). 진한 남색
    // 채움은 목록 글자를 가려 규격에서 뺐다(#1703).
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
        leading: AppIcon(
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
