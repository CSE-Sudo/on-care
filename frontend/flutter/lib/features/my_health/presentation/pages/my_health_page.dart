import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/connected_gym_card.dart';
import 'package:oncare/features/member_coach/presentation/widgets/trainer_chat_header_button.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/features/my_health/presentation/widgets/trainer_sync_sheet.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// MY tab: profile, an activity-points card, the trainer & gym section, the
/// settings list, and logout.
/// Stable identifiers for the settings rows, decoupled from their localized
/// display labels so the switch never keys off a translated string.
enum _MySetting { profile, goals, notif, support }

class MyHealthPage extends ConsumerWidget {
  const MyHealthPage({super.key});

  void _openSetting(BuildContext context, _MySetting id) {
    switch (id) {
      case _MySetting.profile:
        openProfilePage(context);
      case _MySetting.goals:
        openGoalsPage(context);
      case _MySetting.notif:
        openNotificationSettingsPage(context);
      case _MySetting.support:
        openSupportPage(context);
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.myLogout,
      message: l.myLogoutConfirm,
      confirmLabel: l.myLogout,
      cancelLabel: l.myCancel,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(sessionControllerProvider.notifier).signOut();
    if (context.mounted) context.go(AppRoutes.signIn);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<MyHealthState> health = ref.watch(myHealthStateProvider);
    final bool bellHasUnread =
        (ref.watch(notificationUnreadProvider).valueOrNull ?? 0) > 0;
    return AppPage(
      // MainShell 은 `extendBody` 라 이 화면의 아래 여백(padding.bottom)에 하단
      // 내비 높이가 이미 들어 있다. 마지막 항목이 내비 뒤에 숨지 않게 그만큼 띄운다.
      bottomInset: MediaQuery.paddingOf(context).bottom,
      header: AppTabHeader(
        title: l.myTabTitle,
        actions: <Widget>[
          _BellButton(
            hasUnread: bellHasUnread,
            onPressed: () => context.push(AppRoutes.notification),
          ),
          const TrainerChatHeaderButton(),
        ],
      ),
      children: <Widget>[
        _ProfileCard(profile: health.valueOrNull?.profile),
        const SizedBox(height: OnCareSpacing.cardGap),
        _PointsCard(points: health.valueOrNull?.activityPoints),
        const SizedBox(height: OnCareSpacing.sectionGap),
        _TrainerGymSection(onFindGym: () => context.go(AppRoutes.exerciseGym)),
        const SizedBox(height: OnCareSpacing.sectionGap),
        _Settings(
          onTap: (_MySetting id) => _openSetting(context, id),
          onLogout: () => _confirmLogout(context, ref),
        ),
      ],
    );
  }
}

/// 헤더 알림 버튼 — 읽지 않은 알림이 있으면 빨간 점을 단다.
class _BellButton extends StatelessWidget {
  const _BellButton({required this.hasUnread, required this.onPressed});

  final bool hasUnread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        AppIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: l.pageNotificationTitle,
          variant: AppIconButtonVariant.tonal,
          onPressed: onPressed,
        ),
        if (hasUnread)
          const Positioned(
            top: OnCareSpacing.s8,
            right: OnCareSpacing.s8,
            child: IgnorePointer(child: AppStatusDot()),
          ),
      ],
    );
  }
}

/// 브랜드 채움 위에 아이콘을 얹은 작은 사각 표시(설정 행·혜택 카드 앞).
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Container(
      width: OnCareSize.avatarLarge,
      height: OnCareSize.avatarLarge,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.brand.surface,
        borderRadius: OnCareRadius.mdAll,
      ),
      child: Icon(
        icon,
        size: OnCareSize.iconMedium,
        color: tokens.brand.primary,
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final String name = profile?.name ?? '';
    final String email = profile?.email ?? '';
    final String displayName = name.isEmpty ? l.myDefaultUserName : name;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppAvatar(name: displayName, size: AppAvatarSize.xLarge),
              const SizedBox(width: OnCareSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens
                          .text(OnCareTypography.titleSmall)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens
                            .text(OnCareTypography.bodySmall)
                            .copyWith(color: OnCareColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          const AppDivider(),
          const SizedBox(height: OnCareSpacing.s12),
          const _TrainerSyncRow(),
        ],
      ),
    );
  }
}

/// 트레이너와 데이터 동기화 — 누르면 6자리 코드를 띄운다. (#1634)
///
/// 예전에는 이 자리가 "내 회원 ID"(`User.id`)를 보여 주고 복사 버튼을 뒀다.
/// 트레이너가 그 값을 완전 일치로 입력해야 했는데, `user-<12자리 hex>` 는 마주
/// 앉아 불러 주거나 받아 적을 수 있는 형태가 아니었다.
///
/// 코드를 여기서 바로 띄우지 않고 한 단계 두는 이유는, 코드를 띄우는 것이 곧
/// 데이터 공유 동의라서다 — 스스로 누른 것이어야 한다.
class _TrainerSyncRow extends StatelessWidget {
  const _TrainerSyncRow();

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showTrainerSyncSheet(context),
        child: Row(
          children: <Widget>[
            const _IconTile(icon: Icons.sync_rounded),
            const SizedBox(width: OnCareSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l.trainerSyncEntryLabel,
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.body))
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                  Text(
                    l.trainerSyncEntryHint,
                    style: tokens
                        .text(OnCareTypography.caption)
                        .copyWith(color: OnCareColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            const Icon(
              Icons.chevron_right_rounded,
              size: OnCareSize.iconMedium,
              color: OnCareColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 활동 포인트 — 누르면 포인트 혜택 페이지로 간다.
class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.points});

  final int? points;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Semantics(
      button: true,
      child: AppCard(
        key: const Key('pointsBanner'),
        onTap: () => _openPointsBenefitsPage(context, points),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.stars_rounded,
              color: tokens.brand.primary,
              size: OnCareSize.iconLarge,
            ),
            const SizedBox(width: OnCareSpacing.s8),
            // 숫자와 (i) 를 한 칸으로 묶어 남는 폭을 모두 차지하게 한다.
            // Flexible(loose)와 Spacer 가 flex 를 반씩 나누면 숫자가 못 쓴
            // 몫이 화살표 오른쪽에 빈칸으로 남아, 화살표가 다른 행보다 안쪽에 선다.
            Expanded(
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      points != null ? '${points}P' : '—P',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OnCareTypography.numeric(
                        tokens.text(OnCareTypography.titleMedium),
                      ).copyWith(color: OnCareColors.textPrimary),
                    ),
                  ),
                  const _PointsInfoButton(),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: OnCareColors.textTertiary,
              size: OnCareSize.iconMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens point benefits as a full page above the member tab shell.
Future<void> _openPointsBenefitsPage(BuildContext context, int? points) {
  return context.push<void>(AppRoutes.myPoints, extra: points);
}

/// A point redemption option shown in the benefits sheet.
class _PointBenefit {
  const _PointBenefit({
    required this.icon,
    required this.title,
    required this.desc,
    required this.cost,
  });
  final IconData icon;
  final String title;
  final String desc;
  final String cost;
}

List<_PointBenefit> _pointBenefitsOf(AppLocalizations l) => <_PointBenefit>[
  _PointBenefit(
    icon: Icons.savings_rounded,
    title: l.myPointsDiscountTitle,
    desc: l.myPointsDiscountDescription,
    cost: l.myPointsDiscountCost,
  ),
  _PointBenefit(
    icon: Icons.lock_open_rounded,
    title: l.myPointsReportTitle,
    desc: l.myPointsReportDescription,
    cost: l.myPointsReportCost,
  ),
  _PointBenefit(
    icon: Icons.menu_book_rounded,
    title: l.myPointsRecipeTitle,
    desc: l.myPointsRecipeDescription,
    cost: l.myPointsRecipeCost,
  ),
];

class PointsBenefitsPage extends StatelessWidget {
  const PointsBenefitsPage({super.key, required this.points});

  final int? points;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final List<_PointBenefit> benefits = _pointBenefitsOf(l);
    return AppPage(
      key: const Key('pointsBenefitsPage'),
      bottomInset: MediaQuery.paddingOf(context).bottom,
      header: AppTopBar(title: l.myPointsBenefitsTitle),
      children: <Widget>[
        Text(
          points != null
              ? l.myPointsBalance(points!)
              : l.myPointsBenefitsSubtitle,
          style: tokens
              .text(OnCareTypography.label)
              .copyWith(color: tokens.brand.primary),
        ),
        const SizedBox(height: OnCareSpacing.s16),
        for (int i = 0; i < benefits.length; i++) ...<Widget>[
          _PointBenefitCard(benefit: benefits[i]),
          if (i < benefits.length - 1)
            const SizedBox(height: OnCareSpacing.cardGap),
        ],
        const SizedBox(height: OnCareSpacing.s16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.info_outline_rounded,
              size: OnCareSize.iconSmall,
              color: OnCareColors.textTertiary,
            ),
            const SizedBox(width: OnCareSpacing.s4),
            Expanded(
              child: Text(
                l.myPointsBenefitsHint,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PointBenefitCard extends StatelessWidget {
  const _PointBenefitCard({required this.benefit});

  final _PointBenefit benefit;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _IconTile(icon: benefit.icon),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        benefit.title,
                        style: tokens
                            .text(OnCareTypography.titleSmall)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s8),
                    AppTag(label: benefit.cost, tone: AppTagTone.brand),
                  ],
                ),
                const SizedBox(height: OnCareSpacing.s4),
                Text(
                  benefit.desc,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "i" button on the points card — taps open a dialog explaining how points
/// are earned.
class _PointsInfoButton extends StatelessWidget {
  const _PointsInfoButton();

  void _show(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    showAppDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AppDialog(
        title: l.myPointsGuideTitle,
        showClose: false,
        footer: AppButton(
          label: l.actionConfirm,
          onPressed: () => Navigator.of(ctx).pop(),
          fullWidth: true,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _PointRule(
              icon: Icons.restaurant_rounded,
              text: l.myPointsDietAdd,
              points: '+50P',
            ),
            const SizedBox(height: OnCareSpacing.s12),
            _PointRule(
              icon: Icons.auto_awesome_rounded,
              text: l.myPointsAiExercise,
              points: '+50P',
            ),
            const SizedBox(height: OnCareSpacing.s12),
            _PointRule(
              icon: Icons.fitness_center_rounded,
              text: l.myPointsExerciseAdd,
              points: '+20P',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: Icons.info_outline_rounded,
      tooltip: AppLocalizations.of(context).myPointsGuideTitle,
      color: OnCareColors.textTertiary,
      onPressed: () => _show(context),
    );
  }
}

class _PointRule extends StatelessWidget {
  const _PointRule({
    required this.icon,
    required this.text,
    required this.points,
  });

  final IconData icon;
  final String text;
  final String points;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      children: <Widget>[
        _IconTile(icon: icon),
        const SizedBox(width: OnCareSpacing.s12),
        Expanded(
          child: Text(
            text,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                .copyWith(color: OnCareColors.textPrimary),
          ),
        ),
        const SizedBox(width: OnCareSpacing.s8),
        Text(
          points,
          style: OnCareTypography.numeric(
            tokens.text(OnCareTypography.titleSmall),
          ).copyWith(color: tokens.brand.primary),
        ),
      ],
    );
  }
}

class _SettingItem {
  const _SettingItem(this.icon, this.id);
  final IconData icon;
  final _MySetting id;
}

class _Settings extends StatelessWidget {
  const _Settings({required this.onTap, required this.onLogout});
  final ValueChanged<_MySetting> onTap;
  final VoidCallback onLogout;

  static const List<_SettingItem> _items = <_SettingItem>[
    _SettingItem(Icons.person_outline_rounded, _MySetting.profile),
    _SettingItem(Icons.outlined_flag_rounded, _MySetting.goals),
    _SettingItem(Icons.notifications_none_rounded, _MySetting.notif),
    _SettingItem(Icons.chat_bubble_outline_rounded, _MySetting.support),
  ];

  static String _label(AppLocalizations l, _MySetting id) {
    switch (id) {
      case _MySetting.profile:
        return l.myProfileTitle;
      case _MySetting.goals:
        return l.myHealthGoalsTitle;
      case _MySetting.notif:
        return l.myNotifTitle;
      case _MySetting.support:
        return l.mySupportTitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(title: l.mySettingsTitle),
        const SizedBox(height: OnCareSpacing.s12),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final _SettingItem item in _items) ...<Widget>[
                AppListRow(
                  leading: _IconTile(icon: item.icon),
                  title: _label(l, item.id),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    size: OnCareSize.iconMedium,
                    color: OnCareColors.textTertiary,
                  ),
                  onTap: () => onTap(item.id),
                ),
                const AppDivider(),
              ],
              // 위험 동작은 화면 안에서 빨간 글자 버튼으로 두고, 확정은 확인창의
              // 빨간 채움 버튼에서 한다(#1690). 확인 절차와 동작은 그대로다(#1472).
              Padding(
                padding: const EdgeInsets.all(OnCareSpacing.s4),
                child: AppButton(
                  key: const ValueKey<String>('my-logout-button'),
                  label: l.myLogout,
                  leadingIcon: Icons.logout_rounded,
                  variant: AppButtonVariant.destructiveText,
                  size: OnCareButtonSize.large,
                  fullWidth: true,
                  onPressed: onLogout,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// 내 트레이너 · 헬스장 섹션
// ──────────────────────────────────────────────

class _TrainerGymSection extends ConsumerWidget {
  const _TrainerGymSection({required this.onFindGym});

  /// 연결된 헬스장이 없을 때 "헬스장 찾기"로 보낼 콜백.
  final VoidCallback onFindGym;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<Gym?> gymAsync = ref.watch(myGymProvider);
    final Trainer? trainer = ref.watch(myTrainerProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSectionHeader(title: l.myTrainerGymTitle),
        const SizedBox(height: OnCareSpacing.s12),
        gymAsync.when(
          loading: () => const AppCard(
            child: AppLoading(placement: AppStatePlacement.card),
          ),
          error: (_, _) => AppCard(
            child: AppErrorState(
              title: l.myGymLoadFailed,
              retryLabel: l.actionRetry,
              onRetry: () => ref.invalidate(myGymProvider),
              placement: AppStatePlacement.card,
            ),
          ),
          data: (Gym? gym) => gym == null
              ? AppCard(
                  child: AppEmptyState(
                    title: l.myNoGymConnected,
                    icon: Icons.fitness_center_rounded,
                    actionLabel: l.exFindGym,
                    onAction: onFindGym,
                    placement: AppStatePlacement.card,
                  ),
                )
              : ConnectedGymCard(
                  gym: gym,
                  trainer: trainer,
                  onGymTap: () => context.push(AppRoutes.gymDetailPath(gym.id)),
                  onTrainerDetail: trainer == null
                      ? null
                      : () => context.push(
                          AppRoutes.trainerDetailPath(trainer.id),
                        ),
                  // 헬스장은 이미 연결돼 있고 트레이너만 없는 상태다. 헬스장을
                  // 찾는 화면이 아니라 **그 헬스장의 소속 트레이너**로 보낸다 —
                  // 예전에는 라벨이 '트레이너 찾기'인데 헬스장 탭으로 갔다(#793).
                  onFindTrainer: () =>
                      context.push(AppRoutes.gymDetailPath(gym.id)),
                ),
        ),
      ],
    );
  }
}
