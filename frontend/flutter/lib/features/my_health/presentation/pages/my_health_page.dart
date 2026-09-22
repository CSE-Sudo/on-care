import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/points/points_rules.dart';
import 'package:oncare/core/utils/request_id.dart';
import 'package:oncare/features/app_guide/presentation/controllers/app_guide_controller.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/diet_tray.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/domain/entities/profile_pet.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/benefits/presentation/widgets/benefit_cards.dart';
import 'package:oncare/features/benefits/presentation/widgets/challenge_cards.dart';
import 'package:oncare/features/benefits/presentation/widgets/diet_tray_card.dart';
import 'package:oncare/features/benefits/presentation/widgets/graph_color_sheet.dart';
import 'package:oncare/features/benefits/presentation/widgets/profile_pet_sheet.dart';
import 'package:oncare/features/benefits/presentation/widgets/record_graph_card.dart';
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
    // 포인트 카드를 회원이 고른 그래프 색으로 칠한다(#2076). 색은 기록 그래프
    // 응답에 실려 온다 — 색만 읽는 경로가 따로 없다. 그 값은 auto-dispose 가
    // 아니라 세션에 한 번만 읽고, 사용처 화면이 어차피 같은 값을 쓰므로 여기서
    // 먼저 읽어도 요청이 늘지 않는다. 읽기 전에는 기본 색(회원앱 파랑)이다.
    final String? graphColor =
        ref.watch(activityCalendarProvider).valueOrNull?.color.current;
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
          child: _PointsCard(
            points: health.valueOrNull?.activityPoints,
            graphColor: graphColor,
          ),
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

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OnCareTokens tokens = context.oncare;
    // 포인트로 단 펫(#2021). 읽는 중이거나 읽지 못하면 이름만 그린다.
    final ProfilePet? pet = ref.watch(profilePetProvider).valueOrNull;
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
                    ProfileNameLine(name: displayName, pet: pet),
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

/// 프로필 이름과 그 옆의 펫 이모지(#2021).
///
/// 펫이 차지하는 칸은 **이름 글줄 높이 그대로**다. 칸이 글줄보다 크면 다는 날과
/// 떨어지는 날 이름 줄 높이가 달라져 아래 이메일·카드가 흔들린다. 이모티콘 그림은
/// 둘레에 여백이 있어 글줄 높이로는 작게 보이므로, 칸은 그대로 두고 그림만
/// [_petScale] 배 키워 그린다(배치에는 영향이 없다). 이름이 길면 이름이 말줄임되고
/// 펫은 끝에 남는다.
@visibleForTesting
class ProfileNameLine extends StatelessWidget {
  const ProfileNameLine({super.key, required this.name, this.pet});

  final String name;
  final ProfilePet? pet;

  static const double _petScale = 1.4;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle style = tokens
        .text(OnCareTypography.titleSmall)
        .copyWith(color: OnCareColors.textPrimary);
    final ProfilePet? worn = pet;
    final String? emote = worn == null ? null : profilePetEmote(worn.kind);
    final double line =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 16) *
        (style.height ?? 1);
    return Row(
      key: const Key('profileNameLine'),
      children: <Widget>[
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (worn != null && emote != null) ...<Widget>[
          const SizedBox(width: OnCareSpacing.s8),
          Transform.scale(
            scale: _petScale,
            child: AppEmote(
              key: const Key('profilePet'),
              id: emote,
              size: line,
              semanticLabel: l.myProfilePetLabel(profilePetName(l, worn.kind)),
            ),
          ),
        ],
      ],
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
///
/// 카드 채움은 회원이 산 기록 그래프 색을 따른다(#2076). 그래프는 사용처 화면을
/// 열어야 보이지만 이 카드는 MY 탭을 열 때마다 보이므로, 산 색이 값을 하는 자리가
/// 여기다. 기본 색(`blue`)의 진한 단계가 곧 지금까지의 카드 색이라 아무 색도 사지
/// 않은 회원에게는 달라지는 것이 없다.
class _PointsCard extends StatefulWidget {
  const _PointsCard({required this.points, this.graphColor});

  final int? points;

  /// 회원이 고른 기록 그래프 색 이름. null 이면(아직 읽기 전) 기본 색이다.
  final String? graphColor;

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
    final AppLocalizations l = AppLocalizations.of(context);
    final int? points = widget.points;
    _startWhenVisible();
    return Semantics(
      button: true,
      child: AppCard(
        key: const Key('pointsBanner'),
        backgroundColor: OnCareRecordColors.rampOf(widget.graphColor).full,
        onTap: () => _openPointsBenefitsPage(context, points),
        child: Row(
          children: <Widget>[
            ScaleTransition(
              key: const Key('pointsStar'),
              scale: _starScale,
              child: const AppIcon(
                AppIcons.star,
                color: OnCareColors.overlayReward,
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
                    shown != null ? l.myPointsCost(shown) : '—P',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OnCareTypography.numeric(
                      tokens.text(OnCareTypography.titleMedium),
                    ).copyWith(color: OnCareColors.textOnFill),
                  );
                },
              ),
            ),
            const AppIcon(
              AppIcons.chevronRight,
              color: OnCareColors.textOnFill,
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
    if (item.id == kGraphColorItem) {
      // 색은 하나씩 연다(#2076) — 어느 색을 열지 먼저 고르고 나서 확인창이다.
      final GraphColorChoice? choice = await _pickGraphColor(
        lockedOnly: true,
      );
      if (choice == null || !mounted) return;
      await _exchangeItem(item, option: choice.color);
      return;
    }
    if (item.id == kProfilePetItem) {
      // 어느 펫을 달지 먼저 고르고 나서 확인창이다(#2021).
      final String? kind = await showAppSheet<String>(
        context: context,
        builder: (BuildContext ctx) => const ProfilePetSheet(),
      );
      if (kind == null || !mounted) return;
      await _exchangeItem(item, option: kind);
      return;
    }
    await _exchangeItem(item);
  }

  Future<void> _exchangeItem(ShopItem item, {String? option}) async {
    final AppLocalizations l = AppLocalizations.of(context);
    // 그래프 색(#2076)은 쿠폰이 아니라 고른 색 하나가 열린다 — 확인창도 "쿠폰은 내
    // 혜택에서" 가 아니라 어느 색을 여는지 말한다.
    final bool isColor = item.id == kGraphColorItem && option != null;
    // 프로필 펫(#2021)도 쿠폰이 아니다 — 어느 펫을 얼마 동안 다는지 말한다.
    final bool isPet = item.id == kProfilePetItem && option != null;
    // 주간 리포트(#2022)는 어느 주를 받는지 말한다 — 지난주다.
    final bool isReport = item.id == kWeeklyReportItem;
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.myPointsExchangeConfirmTitle,
      message: isColor
          ? l.myGraphColorExchangeConfirm(
              graphColorName(l, option),
              l.myPointsCost(item.cost),
            )
          : isPet
          ? l.myProfilePetExchangeConfirm(
              profilePetName(l, option),
              l.myPointsCost(item.cost),
            )
          : isReport
          ? l.myWeeklyReportExchangeConfirm(
              reportWeekRange(l, lastWeekMonday()),
              l.myPointsCost(item.cost),
            )
          : l.myPointsExchangeConfirmMessage(
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
          .exchange(
            item.id,
            option: option,
            clientRequestId: newClientRequestId(),
          );
      if (!mounted) return;
      // 잔액·교환 가능 여부·보유 쿠폰이 함께 바뀌었다. MY 잔액도 다시 읽는다.
      ref
        ..invalidate(pointsShopProvider)
        ..invalidate(myCouponsProvider)
        ..invalidate(myHealthStateProvider);
      if (item.id == kStreakShieldItem) {
        // 보호권(#1788)은 내 혜택의 보유 수와 기록 그래프의 `보호권 쓰기` 를 바꾼다.
        ref
          ..invalidate(myStreakShieldsProvider)
          ..invalidate(exerciseWeekProvider)
          ..invalidate(activityCalendarProvider);
      }
      if (isReport) {
        // 받은 리포트는 내 혜택에서 연다 — 트레이너 리포트와 같은 문서다.
        ref.invalidate(myWeeklyReportsProvider);
        showAppToast(
          context,
          l.myWeeklyReportDone,
          type: AppToastType.success,
          actionLabel: l.myBenefitsView,
          onAction: () => context.push<void>(AppRoutes.myBenefits),
        );
        return;
      }
      if (isPet) {
        // 단 펫은 MY 프로필 이름 옆에 바로 보인다(#2021). 내 혜택으로 보낼 것이 없다.
        ref.invalidate(profilePetProvider);
        showAppToast(context, l.myProfilePetDone, type: AppToastType.success);
        return;
      }
      if (isColor) {
        // 연 색은 그 자리에서 그래프 색이 된다(#2076). 쿠폰이 아니라 내 혜택으로
        // 보낼 것이 없으므로 안내만 띄운다.
        ref.invalidate(activityCalendarProvider);
        showAppToast(
          context,
          l.myGraphColorUnlocked,
          type: AppToastType.success,
        );
        return;
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

  /// 보호권 사용 요청이 나가 있다(#1788). 교환·참가와 겹치지 않게 서로 막는다.
  bool _usingShield = false;

  /// 색 고르기 시트를 띄우고 고른 색을 돌려준다. 아무것도 고르지 않으면 null.
  ///
  /// [lockedOnly] 는 사용처 카드에서 들어온 길이다 — 아직 열지 않은 색만 보여 준다.
  Future<GraphColorChoice?> _pickGraphColor({
    bool lockedOnly = false,
  }) async {
    final GraphColorState? color = ref
        .read(activityCalendarProvider)
        .valueOrNull
        ?.color;
    if (color == null) return null;
    return showAppSheet<GraphColorChoice>(
      context: context,
      builder: (BuildContext ctx) =>
          GraphColorSheet(state: color, lockedOnly: lockedOnly),
    );
  }

  /// 그래프 카드의 팔레트 버튼 — 연 색은 바로 바꾸고, 열지 않은 색은 교환으로 잇는다.
  Future<void> _changeGraphColor() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final GraphColorChoice? choice = await _pickGraphColor();
    if (choice == null || !mounted) return;
    if (choice.unlock) {
      // 여기서도 값을 치르는 길은 사용처 교환과 같은 확인창을 탄다.
      final ShopItem? item = ref
          .read(pointsShopProvider)
          .valueOrNull
          ?.items
          .where((ShopItem i) => i.id == kGraphColorItem)
          .firstOrNull;
      if (item == null) return;
      await _exchangeItem(item, option: choice.color);
      return;
    }
    try {
      await ref
          .read(activityCalendarRepositoryProvider)
          .selectColor(choice.color);
      if (!mounted) return;
      ref.invalidate(activityCalendarProvider);
      showAppToast(context, l.myGraphColorDone, type: AppToastType.success);
    } on Object {
      if (!mounted) return;
      showAppToast(context, l.myGraphColorFailed, type: AppToastType.error);
    }
  }

  /// 빈 날을 기록 연속에 이어 붙인다(#1788). 되돌리기는 없으므로 확인창을 탄다.
  ///
  /// 보호권이 없으면 교환부터 묻고, 사겠다고 하면 산 보호권을 그 자리에서 그날에
  /// 쓴다([_buyAndUseShield]).
  Future<void> _useShield(DateTime date) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final int held =
        ref.read(activityCalendarProvider).valueOrNull?.shieldsHeld ?? 0;
    if (held <= 0) {
      await _buyAndUseShield(date);
      return;
    }
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.myGraphProtectConfirmTitle,
      message: l.myGraphProtectConfirmMessage(
        l.myGraphDate(date.month, date.day),
        // 지금 쓰는 한 장을 뺀 나머지. 확인창에서 보는 숫자가 누른 뒤의 보유 수다.
        held > 0 ? held - 1 : 0,
      ),
      confirmLabel: l.myGraphProtectAction,
      cancelLabel: l.myCancel,
    );
    if (!ok || !mounted || _usingShield) return;
    setState(() => _usingShield = true);
    try {
      await ref.read(streakShieldRepositoryProvider).use(date);
      if (!mounted) return;
      // 달력 칸·연속·보유 수가 함께 바뀌었다. 내 혜택의 보호한 날도 다시 읽는다.
      ref
        ..invalidate(activityCalendarProvider)
        ..invalidate(myStreakShieldsProvider)
        ..invalidate(pointsShopProvider);
      showAppToast(
        context,
        l.myGraphProtectDone,
        type: AppToastType.success,
      );
    } on Object {
      if (!mounted) return;
      // 그사이 날이 바뀌었거나 그날 기록이 생겼을 수 있다 — 다시 읽어 상태를 맞춘다.
      ref.invalidate(activityCalendarProvider);
      showAppToast(context, l.myGraphProtectFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _usingShield = false);
    }
  }

  /// 보호권이 없을 때 — 한 장을 사서 바로 [date] 에 쓴다.
  ///
  /// 교환과 사용은 서버에서 따로 두 요청이다. 교환이 된 뒤 사용이 막히면(그사이
  /// 그날 기록이 생겼거나 날이 넘어갔다) 산 보호권은 내 혜택에 남으므로 그렇게
  /// 알린다. 잔액이 모자라는 등 교환할 수 없으면 확인창 대신 막힌 이유를 보여 준다.
  Future<void> _buyAndUseShield(DateTime date) async {
    final AppLocalizations l = AppLocalizations.of(context);
    ShopItem? item;
    try {
      item = (await ref.read(pointsShopProvider.future)).items
          .where((ShopItem i) => i.id == kStreakShieldItem)
          .firstOrNull;
    } on Object {
      item = null;
    }
    if (!mounted) return;
    if (item == null) {
      showAppToast(context, l.myPointsExchangeFailed, type: AppToastType.error);
      return;
    }
    if (!item.available) {
      showAppToast(
        context,
        shopBlockLabel(l, item) ?? l.myPointsExchangeFailed,
        type: AppToastType.error,
      );
      return;
    }
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.myGraphProtectBuyConfirmTitle,
      message: l.myGraphProtectBuyConfirmMessage(
        l.myGraphDate(date.month, date.day),
        l.myPointsCost(item.cost),
      ),
      confirmLabel: l.myGraphProtectBuyAction,
      cancelLabel: l.myCancel,
    );
    if (!ok || !mounted || _usingShield || _exchanging != null) return;
    setState(() => _usingShield = true);
    bool bought = false;
    try {
      await ref
          .read(benefitsRepositoryProvider)
          .exchange(kStreakShieldItem, clientRequestId: newClientRequestId());
      bought = true;
      await ref.read(streakShieldRepositoryProvider).use(date);
      if (!mounted) return;
      showAppToast(context, l.myGraphProtectDone, type: AppToastType.success);
    } on Object {
      if (!mounted) return;
      showAppToast(
        context,
        bought ? l.myGraphProtectBoughtNotUsed : l.myPointsExchangeFailed,
        type: AppToastType.error,
      );
    } finally {
      // 잔액·보유 수·달력 칸·연속이 함께 바뀌었다(교환만 됐어도 잔액과 보유 수는
      // 바뀌었다). MY 잔액도 다시 읽는다.
      if (mounted) {
        ref
          ..invalidate(activityCalendarProvider)
          ..invalidate(myStreakShieldsProvider)
          ..invalidate(exerciseWeekProvider)
          ..invalidate(pointsShopProvider)
          ..invalidate(myHealthStateProvider);
        setState(() => _usingShield = false);
      }
    }
  }

  /// 식판 받기 요청이 나가 있다(#2150). 교환·참가와 겹치지 않게 서로 막는다.
  bool _claimingTray = false;

  /// 분석용 식판 수령 쿠폰을 받는다(#2150). 파란 2열 확인창에서 어디서·언제까지
  /// 받는지와 1인 1회를 밝힌 뒤 받는다. 포인트는 쓰지 않는다.
  Future<void> _claimTray() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.myDietTrayClaimConfirmTitle,
      message: keepWords(l.myDietTrayClaimConfirmMessage),
      confirmLabel: l.myDietTrayClaim,
      cancelLabel: l.myCancel,
    );
    if (!ok || !mounted || _claimingTray) return;
    setState(() => _claimingTray = true);
    try {
      await ref
          .read(benefitsRepositoryProvider)
          .claimDietTray(clientRequestId: newClientRequestId());
      if (!mounted) return;
      // 카드 상태와 내 혜택의 쿠폰이 함께 바뀌었다.
      ref
        ..invalidate(dietTrayProvider)
        ..invalidate(myCouponsProvider);
      showAppToast(
        context,
        l.myDietTrayClaimDone,
        type: AppToastType.success,
        actionLabel: l.myBenefitsView,
        onAction: () => context.push<void>(AppRoutes.myBenefits),
      );
    } on Object {
      if (!mounted) return;
      // 그사이 날이 넘어가 조건이 바뀌었거나 담당이 끊겼을 수 있다 — 다시 읽는다.
      ref.invalidate(dietTrayProvider);
      showAppToast(context, l.myDietTrayClaimFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _claimingTray = false);
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
    final AsyncValue<ActivityCalendar> calendar = ref.watch(
      activityCalendarProvider,
    );
    final AsyncValue<DietTray> tray = ref.watch(dietTrayProvider);
    final bool idle =
        _exchanging == null &&
        !_joiningChallenge &&
        !_usingShield &&
        !_claimingTray;
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
            // 보유 포인트가 곧 포인트 내역의 입구다(#2146) — 이 숫자가 무엇으로
            // 쌓이고 쓰였는지를 연다. 버튼을 하나 더 세우면 좁은 폭에서 줄이 넘친다.
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Semantics(
                  button: true,
                  label: l.myPointsHistoryTitle,
                  child: InkWell(
                    key: const Key('pointsShopHistory'),
                    borderRadius: OnCareRadius.smAll,
                    onTap: () => context.push<void>(AppRoutes.myPointsHistory),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            balance != null
                                ? l.myPointsBalance(balance)
                                : l.myPointsBenefitsSubtitle,
                            key: const Key('pointsShopBalance'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens
                                .text(OnCareTypography.label)
                                .copyWith(color: tokens.brand.primary),
                          ),
                        ),
                        AppIcon(
                          AppIcons.chevronRight,
                          size: OnCareSize.iconSmall,
                          color: tokens.brand.primary,
                        ),
                      ],
                    ),
                  ),
                ),
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
        // 기록 그래프(#2075) — 화면 맨 위다. 내 기록 흐름을 먼저 보고 그 아래로
        // "그래서 뭘 교환할까" 가 이어진다. 불러오는 중·실패면 교환 목록만 보인다.
        ...calendar.when(
          loading: () => const <Widget>[
            AppCard(child: AppLoading(placement: AppStatePlacement.card)),
            SizedBox(height: OnCareSpacing.cardGap),
          ],
          error: (_, _) => <Widget>[
            AppCard(
              child: AppErrorState(
                title: l.myGraphLoadFailed,
                retryLabel: l.actionRetry,
                onRetry: () => ref.invalidate(activityCalendarProvider),
                placement: AppStatePlacement.card,
              ),
            ),
            const SizedBox(height: OnCareSpacing.cardGap),
          ],
          data: (ActivityCalendar data) => <Widget>[
            RecordGraphCard(
              calendar: data,
              busy: _usingShield,
              onProtect: idle ? _useShield : null,
              onChangeColor: idle ? _changeGraphColor : null,
            ),
            const SizedBox(height: OnCareSpacing.cardGap),
          ],
        ),
        // 분석용 식판(#2150) — 기록 그래프 바로 아래. 사진 기록이 쌓이는 흐름과 "며칠
        // 더 찍으면 받는가" 를 한눈에 잇는다. 불러오는 중·실패면 아무것도 그리지 않는다
        // (식판을 못 읽었다고 교환까지 막지 않는다).
        ...tray.maybeWhen(
          data: (DietTray data) => <Widget>[
            DietTrayCard(
              tray: data,
              busy: _claimingTray,
              onClaim: idle ? _claimTray : null,
              onViewCoupon: (Coupon coupon) =>
                  context.push<void>(AppRoutes.myCouponDetailPath(coupon.id)),
            ),
            const SizedBox(height: OnCareSpacing.cardGap),
          ],
          orElse: () => const <Widget>[],
        ),
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
                ),
        ),
      ],
    );
  }
}
