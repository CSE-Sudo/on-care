import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/presentation/alert_navigation.dart';
import 'package:oncare/features/notification/presentation/alert_text.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 알림 갈래 → 왼쪽 원에 그릴 아이콘과 화면 읽기용 이름. 갈래 자체는 서버가 주는
/// 계약값이라 그대로 두고, 사람이 읽는 이름만 로케일을 따른다(#847).
///
/// 목록형(#1810)에서는 갈래를 글자 태그 대신 아이콘으로 보여 준다 — 한 줄에 태그·
/// 제목·시각이 함께 서면 제목이 밀려 잘린다. 이름은 화면 읽기 라벨로 남긴다.
///
/// 아이콘은 알림을 눌렀을 때 도착하는 화면이 같은 뜻으로 쓰는 그림과 맞춘다(#2084).
/// 별(`AppIcons.points`)은 "내 포인트" 라 쓰지 않는다 — 포인트가 들어온 것처럼 읽힌다.
({String label, IconData icon}) _categoryDisplay(
  AppLocalizations l,
  AlertCategory c,
) => switch (c) {
  AlertCategory.reminder => (
    label: l.alertCategoryReminder,
    icon: AppIcons.notifications,
  ),
  // 코치 카드·트레이너 채팅 버튼의 말풍선.
  AlertCategory.coachChat => (
    label: l.alertCategoryCoachChat,
    icon: AppIcons.chat,
  ),
  // 코치 대화의 리포트 카드와 같은 문서(#2085).
  AlertCategory.coachReport => (
    label: l.alertCategoryCoachReport,
    icon: AppIcons.document,
  ),
  AlertCategory.routine => (
    label: l.alertCategoryRoutine,
    icon: AppIcons.routine,
  ),
  // 운동 탭의 다음 PT·헬스장 탭 예약과 같은 달력.
  AlertCategory.schedule => (
    label: l.alertCategorySchedule,
    icon: AppIcons.eventAvailable,
  ),
  AlertCategory.trainerLink => (
    label: l.alertCategoryTrainer,
    icon: AppIcons.person,
  ),
  // 헬스장 목록의 "내 상담 요청" 버튼과 같은 서류.
  AlertCategory.consultDecision => (
    label: l.alertCategoryConsultation,
    icon: AppIcons.request,
  ),
  // MY 건강 목표 항목의 깃발.
  AlertCategory.healthGoals => (
    label: l.alertCategoryHealthGoals,
    icon: AppIcons.goal,
  ),
  AlertCategory.benefits => (
    label: l.alertCategoryBenefits,
    icon: AppIcons.coupon,
  ),
  AlertCategory.challenge => (
    label: l.alertCategoryChallenge,
    icon: AppIcons.challenge,
  ),
  AlertCategory.achievement => (
    label: l.alertCategoryAchievement,
    icon: AppIcons.achievement,
  ),
  AlertCategory.system => (label: l.alertCategorySystem, icon: AppIcons.info),
};

/// 목록 행 바탕 — 안 읽은 알림은 브랜드 옅은 색, 읽은 알림은 흰색(#1810).
///
/// 카드마다 굵은 점을 찍던 방식은 목록이 길어지면 어느 줄이 새 것인지 훑기
/// 어려웠다. 줄 전체의 바탕으로 가르면 스크롤하면서도 경계가 한눈에 보인다.
Color alertRowBackground(OnCareBrand brand, {required bool read}) =>
    read ? OnCareColors.surfaceCard : brand.surface;

class NotificationPage extends ConsumerStatefulWidget {
  const NotificationPage({super.key});

  @override
  ConsumerState<NotificationPage> createState() => _NotificationPageState();
}

/// 화면이 살아 있는 동안 서버 상태를 따라간다.
///
/// 진입할 때 한 번, 그리고 앱이 앞으로 돌아올 때마다 다시 조회한다. 트레이너가
/// 무언가 해도 회원 앱을 재시작해야 보이던 문제를 없앤다 — 알림함을 열어 둔 채
/// 잠깐 다른 앱을 다녀오는 것이 실제로 자주 하는 동작이다.
class _NotificationPageState extends ConsumerState<NotificationPage>
    with WidgetsBindingObserver {
  /// 목록 끝에 다가오면 다음 쪽을 부르기 위해 스크롤 위치를 본다. (#965)
  final ScrollController _scroll = ScrollController();

  /// 바닥에서 이만큼 남았을 때 미리 부른다. 다 닿은 뒤에 부르면 기다리는 것이
  /// 그대로 보인다.
  static const double _loadMoreThreshold = 320;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_maybeLoadMore);
    // 첫 프레임 뒤에 부른다 — build 중에 provider 를 건드리지 않는다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() {
    if (!mounted) return Future<void>.value();
    return ref.read(notificationControllerProvider.notifier).refresh();
  }

  /// 바닥 근처면 다음 쪽을 잇는다. 중복 호출·더 없음은 컨트롤러가 막는다.
  void _maybeLoadMore() {
    if (!mounted || !_scroll.hasClients) return;
    final ScrollPosition p = _scroll.position;
    if (p.maxScrollExtent - p.pixels > _loadMoreThreshold) return;
    ref.read(notificationControllerProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(notificationControllerProvider);
    final notifier = ref.read(notificationControllerProvider.notifier);
    final double side = context.oncare.density.pagePadding;
    final bool showRetry = state.failedToLoad;
    final int leading = showRetry ? 1 : 0;
    final int bodyCount = state.items.isEmpty ? 1 : state.items.length;
    // 더 받을 것이 남아 있을 때만 꼬리를 단다. 빈 목록에는 달지 않는다 — 받을 것이
    // 없는데 도는 표시는 영영 도는 표시로 보인다.
    final int trailing =
        state.items.isNotEmpty && (state.hasMore || state.loadingMore) ? 1 : 0;

    // 모바일 페이지 틀(`AppPage`)과 같은 배경·좌우 여백·최대 폭이다. 당겨서
    // 새로고침과 이어 받기가 목록을 직접 쥐어야 해서 틀만 풀어 둔다.
    return Scaffold(
      key: const Key('notificationPage'),
      backgroundColor: OnCareColors.surfaceCard,
      appBar: AppTopBar(
        title: l.pageNotificationTitle,
        actions: <Widget>[
          AppButton(
            label: l.alertMarkAllRead,
            onPressed: state.unreadCount == 0 ? null : notifier.markAllRead,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
          ),
        ],
      ),
      // 목록이 비어 있어도 당겨서 새로고침할 수 있어야 한다 — 빈 화면이야말로
      // 다시 받아 보고 싶은 순간이다. 그래서 본문은 항상 스크롤 가능하다.
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: OnCareLayout.mobileContentMaxWidth,
          ),
          child: RefreshIndicator(
            onRefresh: _refresh,
            // 알림 줄은 좌우 끝까지 채운다(#1810) — 줄 바탕색이 곧 읽음 상태라
            // 여백에서 끊기면 줄 경계가 흐려진다. 여백은 줄 안쪽이 갖는다.
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: OnCareSpacing.sectionGap),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: leading + bodyCount + trailing,
              itemBuilder: (BuildContext ctx, int i) {
                // 조회가 실패해도 **받아 둔 목록은 그대로 둔다.** 맨 위에 사정과
                // 재시도만 얹는다 — 목록이 사라지면 읽지 않은 알림이 있었는지조차
                // 알 수 없다.
                if (showRetry && i == 0) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s8,
                      side,
                      OnCareSpacing.s8,
                    ),
                    child: AppBanner(
                      key: const Key('notificationRetryBanner'),
                      tone: AppBannerTone.danger,
                      icon: AppIcons.offline,
                      title: l.alertLoadFailed,
                      actionLabel: l.actionRetry,
                      onAction: _refresh,
                    ),
                  );
                }
                if (state.items.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s48,
                      side,
                      0,
                    ),
                    child: AppEmptyState(
                      icon: AppIcons.notificationsOff,
                      title: l.alertEmpty,
                    ),
                  );
                }
                final int j = i - leading;
                // 마지막 칸은 이어 받기 표시다. 과거 알림이 남아 있는 동안만 그린다.
                if (j >= state.items.length) return const _LoadingMoreFooter();
                final AlertItem item = state.items[j];
                return _AlertTile(
                  item: item,
                  // 읽음 처리를 기다리지 않고 이동한다 — 서버 왕복 동안 화면이
                  // 멈춰 있으면 누른 것이 먹지 않은 것처럼 보인다.
                  onTap: () {
                    notifier.markRead(item.id);
                    openAlertTarget(context, ref, item);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 알림 한 줄(#1810) — 왼쪽 원형 갈래 아이콘, 오른쪽에 굵은 제목·본문·시각.
///
/// 줄 바탕이 읽음 상태를 말한다([alertRowBackground]). 읽고 나면 흰 바탕이 되어
/// 새 알림만 옅은 파랑으로 남는다.
class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.item, required this.onTap});
  final AlertItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final display = _categoryDisplay(l, item.category);
    final text = alertText(l, item);
    final double side = tokens.density.pagePadding;
    return Semantics(
      key: ValueKey<String>('notification-row-${item.id}'),
      button: true,
      label: display.label,
      child: Material(
        color: alertRowBackground(tokens.brand, read: item.read),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: side,
              vertical: OnCareSpacing.s16,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _CategoryBadge(icon: display.icon),
                const SizedBox(width: OnCareSpacing.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        text.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens
                            .text(OnCareTypography.titleSmall)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                      if (text.body.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: OnCareSpacing.s4),
                        Text(
                          text.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tokens
                              .text(OnCareTypography.body)
                              .copyWith(color: OnCareColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: OnCareSpacing.s4),
                      Text(
                        alertTimeAgo(l, item),
                        key: ValueKey<String>('notification-time-${item.id}'),
                        style: OnCareTypography.numeric(
                          tokens.text(OnCareTypography.caption),
                        ).copyWith(color: OnCareColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 알림 줄 왼쪽의 흰 원 — 옅은 테두리 안에 갈래 아이콘. 줄 바탕이 파래도 원은
/// 흰색이라 아이콘이 묻히지 않는다.
class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: OnCareSize.avatarLarge,
      height: OnCareSize.avatarLarge,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        shape: BoxShape.circle,
        border: Border.all(color: OnCareColors.lineSubtle),
      ),
      child: AppIcon(
        icon,
        size: OnCareSize.iconMedium,
        color: OnCareColors.textSecondary,
      ),
    );
  }
}

/// 과거 알림을 이어 받는 동안 목록 끝에 서는 표시. (#965)
class _LoadingMoreFooter extends StatelessWidget {
  const _LoadingMoreFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('notificationLoadMore'),
      padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s16),
      child: Center(child: AppLoading.inline()),
    );
  }
}
