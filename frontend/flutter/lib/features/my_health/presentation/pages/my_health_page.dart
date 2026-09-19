import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/points/points_rules.dart';
import 'package:oncare/core/utils/request_id.dart';
import 'package:oncare/features/app_guide/presentation/controllers/app_guide_controller.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/benefits/presentation/widgets/benefit_cards.dart';
import 'package:oncare/features/benefits/presentation/widgets/challenge_cards.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/features/exercise/presentation/widgets/connected_gym_card.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/trainer_chat_header_button.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/features/my_health/presentation/widgets/trainer_sync_sheet.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Stable identifiers for the settings rows, decoupled from their localized
/// display labels so the switch never keys off a translated string.
enum _MySetting { profile, goals, notif, guide, support }

/// MY 탭 — 프로필 카드, 내 트레이너 · 헬스장 섹션, 활동 포인트 카드, 설정 목록과
/// 로그아웃 순서다. 포인트 카드는 트레이너 · 헬스장 아래에 둔다(#1785).
class MyHealthPage extends ConsumerWidget {
  const MyHealthPage({super.key, this.settingsAnchorKey, this.pointsAnchorKey});

  /// 사용 가이드가 설정 묶음의 자리를 재는 열쇠(#1857). MY 탭은 이 값을 주지
  /// 않는다 — 가이드 화면만 자기 사본에 달아 쓴다.
  final GlobalKey? settingsAnchorKey;

  /// 사용 가이드가 포인트 카드의 자리를 재는 열쇠(#1857).
  final GlobalKey? pointsAnchorKey;

  void _openSetting(BuildContext context, WidgetRef ref, _MySetting id) {
    switch (id) {
      case _MySetting.profile:
        openProfilePage(context);
      case _MySetting.goals:
        openGoalsPage(context);
      case _MySetting.notif:
        openNotificationSettingsPage(context);
      case _MySetting.guide:
        // 온보딩 때 지나쳤거나 다시 보고 싶은 사람을 위한 자리(#1857). 본
        // 기억을 지워야 가이드가 다시 뜬다 — 그 판단은 가이드 화면이 한다.
        ref.read(appGuideControllerProvider.notifier).resetSeen();
        context.go(AppRoutes.guideTour);
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
        const SizedBox(height: OnCareSpacing.sectionGap),
        _TrainerGymSection(onFindGym: () => context.go(AppRoutes.exerciseGym)),
        const SizedBox(height: OnCareSpacing.sectionGap),
        KeyedSubtree(
          key: pointsAnchorKey,
          child: _PointsCard(points: health.valueOrNull?.activityPoints),
        ),
        const SizedBox(height: OnCareSpacing.sectionGap),
        KeyedSubtree(
          key: settingsAnchorKey,
          child: _Settings(
            onTap: (_MySetting id) => _openSetting(context, ref, id),
            onLogout: () => _confirmLogout(context, ref),
          ),
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
          icon: AppIcons.notifications,
          tooltip: l.pageNotificationTitle,
          color: context.oncare.brand.primary,
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

/// 설정 행·혜택 카드 앞의 아이콘 자리. 배경 없이 칸 크기만 잡아 글줄 정렬을
/// 지킨다(#1781).
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
      child: AppIcon(
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
///
/// 앞머리 아이콘은 두지 않는다 — 제목이 프로필 이름과 같은 왼쪽 선에서 시작한다(#1785).
class _TrainerSyncRow extends ConsumerWidget {
  const _TrainerSyncRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await showTrainerSyncSheet(context);
          // 시트를 여는 동안 트레이너가 코드를 쓰면 서버에는 담당·헬스장 연결이
          // 생긴다. 셋 다 폴링 없는 provider 라 다시 읽지 않으면, 벨 알림은
          // 연결됐다고 하는데 바로 아래 섹션은 `없음` 으로 남는다(#1931).
          ref
            ..invalidate(myGymProvider)
            ..invalidate(myTrainerProvider)
            ..invalidate(memberCoachProvider);
        },
        child: Row(
          children: <Widget>[
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
            const AppIcon(
              AppIcons.chevronRight,
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
///
/// 적립 안내 (i) 버튼은 카드가 아니라 포인트 사용처 화면 헤더에 있다(#1785).
///
/// 잔액이 마지막으로 보인 값보다 오르면 숫자가 그 값에서 올라가고 별이 톡
/// 튄다(#1786). 처음 읽을 때는 움직이지 않는다 — 오른 것이 아니라 처음 보는
/// 값이다. 줄면(기록 삭제로 회수) 그대로 바꾼다.
class _PointsCard extends StatefulWidget {
  const _PointsCard({required this.points});

  final int? points;

  @override
  State<_PointsCard> createState() => _PointsCardState();
}

class _PointsCardState extends State<_PointsCard>
    with TickerProviderStateMixin {
  late final AnimationController _count = AnimationController(
    vsync: this,
    duration: OnCareMotion.pointsCountUp,
  );
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: OnCareMotion.pointsPop,
  );
  late final Animation<double> _countCurve = CurvedAnimation(
    parent: _count,
    curve: OnCareMotion.curve,
  );
  late final Animation<double> _starScale =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1,
            end: OnCareMotion.rewardPopScale,
          ).chain(CurveTween(curve: OnCareMotion.curve)),
          weight: 1,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: OnCareMotion.rewardPopScale,
            end: 1,
          ).chain(CurveTween(curve: OnCareMotion.curve)),
          weight: 1,
        ),
      ]).animate(_pop);

  /// 올라가기 시작하는 값 — 마지막으로 화면에 보인 숫자.
  int _from = 0;

  /// 오른 값을 받았지만 아직 움직이지 않았다.
  ///
  /// 다른 탭에서 저장하면 가려진 MY 탭이 먼저 새 값을 받는다. 가려진 탭은
  /// TickerMode 가 꺼져 있어 거기서 시작하면 회원이 보기 전에 끝나므로, 탭이
  /// 보일 때까지 이전 숫자에 머문다.
  bool _holding = false;
  bool _startScheduled = false;

  int? _shown(int? target) {
    if (target == null) return null;
    if (_holding) return _from;
    if (!_count.isAnimating) return target;
    return (_from + (target - _from) * _countCurve.value).round();
  }

  @override
  void didUpdateWidget(covariant _PointsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final int? before = oldWidget.points;
    final int? after = widget.points;
    if (after == before) return;
    if (before == null || after == null || after < before) {
      _holding = false;
      _count.stop();
      return;
    }
    _from = _shown(before) ?? before;
    _count.stop();
    _holding = true;
  }

  void _startWhenVisible() {
    if (!_holding || _startScheduled || !TickerMode.valuesOf(context).enabled) {
      return;
    }
    _startScheduled = true;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScheduled = false;
      if (!mounted || !_holding) return;
      if (reduceMotion) {
        // 움직임 줄이기 — 새 숫자로 바로 바꾼다.
        setState(() => _holding = false);
        return;
      }
      _holding = false;
      _count.forward(from: 0);
      _pop.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _count.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final int? points = widget.points;
    _startWhenVisible();
    return Semantics(
      button: true,
      child: AppCard(
        key: const Key('pointsBanner'),
        onTap: () => _openPointsBenefitsPage(context, points),
        child: Row(
          children: <Widget>[
            ScaleTransition(
              key: const Key('pointsStar'),
              scale: _starScale,
              child: AppIcon(
                AppIcons.points,
                color: tokens.brand.primary,
                size: OnCareSize.iconLarge,
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            // 숫자가 남는 폭을 모두 차지하게 한다. 느슨한 칸(Flexible)이면 숫자가
            // 못 쓴 몫이 화살표 오른쪽에 빈칸으로 남아, 화살표가 다른 행보다
            // 안쪽에 선다(#1744).
            Expanded(
              child: AnimatedBuilder(
                animation: _count,
                builder: (BuildContext context, Widget? _) {
                  final int? shown = _shown(points);
                  return Text(
                    shown != null ? '${shown}P' : '—P',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OnCareTypography.numeric(
                      tokens.text(OnCareTypography.titleMedium),
                    ).copyWith(color: OnCareColors.textPrimary),
                  );
                },
              ),
            ),
            const AppIcon(
              AppIcons.chevronRight,
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

/// 포인트 사용처 — 포인트를 쿠폰으로 교환한다. (#1787)
///
/// 예전 카드 셋(결제 차감 할인·예측 리포트·레시피)은 지금 서비스와 맞지 않았고
/// 교환 버튼도 없었다. 서버가 주는 교환 목록을 그리고, 카드마다 `교환` → 파란 2열
/// 확인창(`취소 / 교환하기`) → 포인트 차감 순서로 쓴다. 잔액이 모자라거나 조건이
/// 안 되면 버튼을 막고 이유(모자란 포인트 등)를 카드에 적는다.
///
/// [points] 는 MY 가 들고 온 잔액이다 — 목록을 받기 전에도 보유 포인트 줄이
/// 비지 않게 한다. 목록을 받으면 그 응답의 잔액을 쓴다.
class PointsBenefitsPage extends ConsumerStatefulWidget {
  const PointsBenefitsPage({super.key, required this.points});

  final int? points;

  @override
  ConsumerState<PointsBenefitsPage> createState() => _PointsBenefitsPageState();
}

class _PointsBenefitsPageState extends ConsumerState<PointsBenefitsPage> {
  /// 교환 요청이 나가 있는 항목. 그 카드는 진행 표시, 다른 카드 버튼은 막는다 —
  /// 두 교환이 겹치면 잔액 표시가 어느 쪽 응답을 따를지 알 수 없다.
  String? _exchanging;

  Future<void> _exchange(ShopItem item) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.myPointsExchangeConfirmTitle,
      message: l.myPointsExchangeConfirmMessage(
        shopItemTitle(l, item),
        l.myPointsCost(item.cost),
      ),
      confirmLabel: l.myPointsExchangeConfirmAction,
      cancelLabel: l.myCancel,
    );
    if (!ok || !mounted || _exchanging != null) return;
    setState(() => _exchanging = item.id);
    try {
      await ref
          .read(benefitsRepositoryProvider)
          .exchange(item.id, clientRequestId: newClientRequestId());
      if (!mounted) return;
      // 잔액·교환 가능 여부·보유 쿠폰이 함께 바뀌었다. MY 잔액도 다시 읽는다.
      ref
        ..invalidate(pointsShopProvider)
        ..invalidate(myCouponsProvider)
        ..invalidate(myHealthStateProvider);
      if (item.id == kStreakShieldItem) {
        // 보호권(#1788)은 내 혜택의 보유 수와 운동 현황의 `보호권 쓰기` 를 바꾼다.
        ref
          ..invalidate(myStreakShieldsProvider)
          ..invalidate(exerciseWeekProvider);
      }
      showAppToast(
        context,
        l.myPointsExchangeDone,
        type: AppToastType.success,
        actionLabel: l.myBenefitsView,
        onAction: () => context.push<void>(AppRoutes.myBenefits),
      );
    } on Object {
      if (!mounted) return;
      // 그사이 조건이 바뀌었을 수 있다(다른 기기에서 교환 등) — 목록을 다시 읽어
      // 막힌 이유를 카드에 보여 준다.
      ref.invalidate(pointsShopProvider);
      showAppToast(context, l.myPointsExchangeFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _exchanging = null);
    }
  }

  /// 주간 챌린지 참가 요청이 나가 있다(#1789). 교환과 겹치지 않게 서로 막는다.
  bool _joiningChallenge = false;

  /// 주간 챌린지 참가 — 파란 2열 확인창에서 건 포인트·목표·보상을 밝힌 뒤 건다.
  Future<void> _joinChallenge(WeeklyChallenge state) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.challengeJoinConfirmTitle,
      message: l.challengeJoinConfirmMessage(
        l.myPointsCost(state.stake),
        state.goal,
        l.myPointsCost(state.reward),
      ),
      confirmLabel: l.challengeJoinConfirmAction,
      cancelLabel: l.myCancel,
    );
    if (!ok || !mounted || _joiningChallenge || _exchanging != null) return;
    setState(() => _joiningChallenge = true);
    try {
      await ref
          .read(challengeRepositoryProvider)
          .join(clientRequestId: newClientRequestId());
      if (!mounted) return;
      // 참가 기록·잔액·교환 가능 여부가 함께 바뀌었다. MY 잔액도 다시 읽는다.
      ref
        ..invalidate(weeklyChallengeProvider)
        ..invalidate(pointsShopProvider)
        ..invalidate(myHealthStateProvider);
      showAppToast(
        context,
        l.challengeJoinDone,
        type: AppToastType.success,
        actionLabel: l.myBenefitsView,
        onAction: () => context.push<void>(AppRoutes.myBenefits),
      );
    } on Object {
      if (!mounted) return;
      // 그사이 요일이 넘어갔거나 잔액이 바뀌었을 수 있다 — 다시 읽어 이유를 보여 준다.
      ref.invalidate(weeklyChallengeProvider);
      showAppToast(context, l.challengeJoinFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _joiningChallenge = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<PointsShop> shop = ref.watch(pointsShopProvider);
    final AsyncValue<WeeklyChallenge> challenge = ref.watch(
      weeklyChallengeProvider,
    );
    final bool idle = _exchanging == null && !_joiningChallenge;
    final int? balance = shop.valueOrNull?.balance ?? widget.points;
    return AppPage(
      key: const Key('pointsBenefitsPage'),
      bottomInset: MediaQuery.paddingOf(context).bottom,
      header: AppTopBar(
        title: l.myPointsBenefitsTitle,
        actions: const <Widget>[_PointsInfoButton()],
      ),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                balance != null
                    ? l.myPointsBalance(balance)
                    : l.myPointsBenefitsSubtitle,
                key: const Key('pointsShopBalance'),
                style: tokens
                    .text(OnCareTypography.label)
                    .copyWith(color: tokens.brand.primary),
              ),
            ),
            AppButton(
              key: const Key('pointsShopMyBenefits'),
              label: l.myBenefitsTitle,
              variant: AppButtonVariant.text,
              size: OnCareButtonSize.small,
              trailingIcon: AppIcons.chevronRight,
              onPressed: () => context.push<void>(AppRoutes.myBenefits),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s16),
        // 주간 운동 챌린지(#1789) — 쿠폰 교환 위에 선다. 불러오는 중·실패면 교환
        // 목록만 보인다(챌린지를 못 읽었다고 교환까지 막지 않는다).
        ...challenge.maybeWhen(
          data: (WeeklyChallenge state) => <Widget>[
            WeeklyChallengeCard(
              state: state,
              busy: _joiningChallenge,
              onJoin: idle ? () => _joinChallenge(state) : null,
            ),
            const SizedBox(height: OnCareSpacing.cardGap),
          ],
          orElse: () => const <Widget>[],
        ),
        ...shop.when(
          loading: () => const <Widget>[
            AppCard(child: AppLoading(placement: AppStatePlacement.card)),
          ],
          error: (_, _) => <Widget>[
            AppCard(
              child: AppErrorState(
                title: l.myPointsShopLoadFailed,
                retryLabel: l.actionRetry,
                onRetry: () => ref.invalidate(pointsShopProvider),
                placement: AppStatePlacement.card,
              ),
            ),
          ],
          data: (PointsShop data) => <Widget>[
            for (int i = 0; i < data.items.length; i++) ...<Widget>[
              ShopItemCard(
                item: data.items[i],
                busy: _exchanging == data.items[i].id,
                onExchange: idle ? () => _exchange(data.items[i]) : null,
              ),
              if (i < data.items.length - 1)
                const SizedBox(height: OnCareSpacing.cardGap),
            ],
          ],
        ),
        const SizedBox(height: OnCareSpacing.s16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const AppIcon(
              AppIcons.info,
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

/// 포인트 사용처 화면 헤더 오른쪽 끝의 (i) 버튼 — 누르면 포인트 적립 안내 창을
/// 연다. MY 포인트 카드의 잔액 옆에 있던 것을 헤더로 옮겼다(#1785).
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
        // 포인트와 하루 한도는 적립 규칙([PointsRule])에서 읽는다(#1786). 안내창에
        // 숫자를 따로 적어 두면 규칙을 바꿀 때 문구만 옛 값으로 남는다.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _PointRule.of(
              l,
              icon: AppIcons.diet,
              action: l.myPointsDietAdd,
              rule: PointsRule.dietEntry,
            ),
            const SizedBox(height: OnCareSpacing.s12),
            _PointRule.of(
              l,
              // AI 추천과 트레이너 배정을 한 규칙으로 묶었다 — AI 를 뜻하던 반짝이
              // 대신 완료 표시를 쓴다.
              icon: AppIcons.checkCircle,
              action: l.myPointsRoutineComplete,
              rule: PointsRule.routineComplete,
            ),
            const SizedBox(height: OnCareSpacing.s12),
            _PointRule.of(
              l,
              icon: AppIcons.exercise,
              action: l.myPointsExerciseAdd,
              rule: PointsRule.exerciseManual,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 배경 없는(plain) 버튼에 채운 글리프를 얹는다.
    return AppIconButton(
      icon: AppIcons.info,
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

  /// 적립 규칙 한 줄 — 왼쪽에 `식단 추가 (하루 3회)`, 오른쪽에 `+50P`.
  _PointRule.of(
    AppLocalizations l, {
    required IconData icon,
    required String action,
    required PointsRule rule,
  }) : this(
         icon: icon,
         text: l.myPointsRuleWithDailyCap(action, rule.dailyCap),
         points: l.pointsRewardBadge(rule.points),
       );

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
    _SettingItem(AppIcons.person, _MySetting.profile),
    _SettingItem(AppIcons.goal, _MySetting.goals),
    _SettingItem(AppIcons.notifications, _MySetting.notif),
    _SettingItem(AppIcons.guide, _MySetting.guide),
    _SettingItem(AppIcons.chat, _MySetting.support),
  ];

  static String _label(AppLocalizations l, _MySetting id) {
    switch (id) {
      case _MySetting.profile:
        return l.myProfileTitle;
      case _MySetting.goals:
        return l.myHealthGoalsTitle;
      case _MySetting.notif:
        return l.myNotifTitle;
      case _MySetting.guide:
        return l.myGuideTitle;
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
                  trailing: const AppIcon(
                    AppIcons.chevronRight,
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
                  leadingIcon: AppIcons.logout,
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
        AppSectionHeader(title: l.myGymTrainerTitle),
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
                    icon: AppIcons.gym,
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
