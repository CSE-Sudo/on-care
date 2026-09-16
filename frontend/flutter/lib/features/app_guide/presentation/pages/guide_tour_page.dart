import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/app_guide/presentation/controllers/app_guide_controller.dart';
import 'package:oncare/features/app_guide/presentation/widgets/app_guide_overlay.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/member_tab_header.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 온보딩 끝에 한 번 보는 사용 가이드 — **예시 화면 위에서** 진행한다. (#1857)
///
/// 실제 홈 위에서 짚지 않는 이유: 방금 가입한 회원의 홈은 기록이 하나도 없어
/// 비어 있다. 빈 카드를 밝게 뚫어 놓고 "여기에 오늘 먹은 것이 모여요" 라고 말하면
/// 무엇을 보라는 것인지 알 수 없다. 그래서 기록이 쌓인 뒤의 모습을 **예시 자료로**
/// 만들어 두고 그 위에서 짚는다. 예시라는 것은 화면 위에 그대로 적는다.
///
/// 이 화면의 카드·버튼은 눌리지 않는다. 안내 도중 다른 화면으로 새지 않게 하려는
/// 것이고, 진짜 기능은 가이드가 끝난 뒤 홈에서 만난다.
class GuideTourPage extends ConsumerStatefulWidget {
  const GuideTourPage({super.key});

  @override
  ConsumerState<GuideTourPage> createState() => _GuideTourPageState();
}

class _GuideTourPageState extends ConsumerState<GuideTourPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final AppGuideController controller = ref.read(
        appGuideControllerProvider.notifier,
      );
      controller.start();
      // 이미 본 회원이면 가이드가 켜지지 않는다 — 그대로 홈으로 보낸다.
      if (!ref.read(appGuideControllerProvider).active) _goHome();
    });
  }

  void _goHome() {
    if (!mounted) return;
    context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    // 마지막까지 봤든 건너뛰었든, 가이드가 끝나면 홈으로 간다.
    ref.listen<AppGuideState>(appGuideControllerProvider, (
      AppGuideState? before,
      AppGuideState after,
    ) {
      if ((before?.active ?? false) && !after.active) _goHome();
    });

    return Scaffold(
      backgroundColor: context.oncare.pageBackground,
      body: const Stack(
        children: <Widget>[
          Positioned.fill(child: _SampleHome()),
          Positioned.fill(child: AppGuideOverlay()),
        ],
      ),
    );
  }
}

/// 가이드가 짚는 **예시 홈**. 진짜 홈과 같은 부품으로 같은 자리에 그리되, 숫자는
/// 예시고 아무것도 눌리지 않는다.
class _SampleHome extends ConsumerWidget {
  const _SampleHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final GuideAnchors anchors = ref.watch(guideAnchorsProvider);
    return IgnorePointer(
      child: Column(
        children: <Widget>[
          _SampleHeader(anchors: anchors),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: OnCareLayout.mobileContentMaxWidth,
                ),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    context.oncare.density.pagePadding,
                    OnCareSpacing.s8,
                    context.oncare.density.pagePadding,
                    OnCareSpacing.sectionGap,
                  ),
                  children: <Widget>[
                    // 이 화면이 예시라는 것을 화면 안에서도 밝힌다.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppTag(
                        key: const Key('guideSampleBadge'),
                        label: l.guideSampleBadge,
                        icon: AppIcons.info,
                      ),
                    ),
                    const SizedBox(height: OnCareSpacing.cardGap),
                    KeyedSubtree(
                      key: anchors.homeSummary,
                      child: const _SampleSummaryCard(),
                    ),
                    const SizedBox(height: OnCareSpacing.cardGap),
                    const _SampleExerciseCard(),
                  ],
                ),
              ),
            ),
          ),
          _SampleBottomNav(anchors: anchors),
        ],
      ),
    );
  }
}

/// 예시 홈의 머리 — 로고·제목과 알림 벨. 벨은 가이드가 짚는 자리다.
class _SampleHeader extends StatelessWidget implements PreferredSizeWidget {
  const _SampleHeader({required this.anchors});

  final GuideAnchors anchors;

  @override
  Size get preferredSize => AppTabHeader(title: '').preferredSize;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppTabHeader(
      title: 'On - Care',
      leading: const MemberLogo(),
      actions: <Widget>[
        KeyedSubtree(
          key: anchors.alerts,
          child: HeaderActionButton(
            icon: AppIcons.notifications,
            tooltip: l.pageNotificationTitle,
            // 예시니까 새 알림이 와 있는 모습으로 둔다.
            showDot: true,
          ),
        ),
        HeaderActionButton(
          icon: AppIcons.chat,
          tooltip: l.coachChatWithTrainer,
        ),
      ],
    );
  }
}

/// 예시 오늘 기록 — 목표까지 얼마나 남았는지가 보이는 모습.
class _SampleSummaryCard extends StatelessWidget {
  const _SampleSummaryCard();

  /// 예시 숫자. 하루 목표를 절반쯤 채운, 가장 흔한 모습으로 고른다.
  static const int _calories = 1480;
  static const int _calorieGoal = 2000;
  static const int _sodium = 1720;
  static const int _sugar = 32;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.homeDietNutritionTitle,
            style: tokens
                .text(OnCareTypography.titleSmall)
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '$_calories',
                style: OnCareTypography.numeric(
                  tokens.text(OnCareTypography.display),
                ).copyWith(color: tokens.brand.primary),
              ),
              const SizedBox(width: OnCareSpacing.s4),
              Padding(
                padding: const EdgeInsets.only(bottom: OnCareSpacing.s4),
                child: Text(
                  '/ $_calorieGoal ${l.unitKcal}',
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Row(
            children: <Widget>[
              Expanded(
                child: _SampleStat(
                  label: l.dietSodium,
                  value: '$_sodium${l.dietUnitMg}',
                ),
              ),
              Expanded(
                child: _SampleStat(
                  label: l.dietSugar,
                  value: '$_sugar${l.dietUnitG}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 예시 운동 카드 — 이번 주에 쌓인 모습.
class _SampleExerciseCard extends StatelessWidget {
  const _SampleExerciseCard();

  static const int _minutes = 95;
  static const int _burned = 420;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.exActivityTitle,
            style: tokens
                .text(OnCareTypography.titleSmall)
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Row(
            children: <Widget>[
              Expanded(
                child: _SampleStat(
                  label: l.exWeekSummary,
                  value: l.unitMinutesValue(_minutes),
                ),
              ),
              Expanded(
                child: _SampleStat(
                  label: l.homeExerciseBurned,
                  value: l.unitKcalValue(_burned),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 예시 카드 안의 지표 한 칸.
class _SampleStat extends StatelessWidget {
  const _SampleStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: tokens
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textSecondary),
        ),
        const SizedBox(height: OnCareSpacing.s2),
        Text(
          value,
          style: OnCareTypography.numeric(
            tokens.text(OnCareTypography.titleSmall),
          ).copyWith(color: OnCareColors.textPrimary),
        ),
      ],
    );
  }
}

/// 예시 하단 내비 — 진짜 홈과 같은 부품이라 가이드가 짚는 자리도 같다.
class _SampleBottomNav extends StatelessWidget {
  const _SampleBottomNav({required this.anchors});

  final GuideAnchors anchors;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppBottomNav(
      selectedIndex: 0,
      onSelected: (_) {},
      destinations: <AppNavDestination>[
        AppNavDestination(
          icon: AppIcons.home,
          selectedIcon: AppIcons.home,
          label: l.navDashboard,
        ),
        AppNavDestination(
          anchorKey: anchors.diet,
          icon: AppIcons.diet,
          selectedIcon: AppIcons.diet,
          label: l.navDiet,
        ),
        AppNavDestination(
          anchorKey: anchors.exercise,
          icon: AppIcons.exercise,
          selectedIcon: AppIcons.exercise,
          label: l.navExercise,
        ),
        AppNavDestination(
          anchorKey: anchors.points,
          icon: AppIcons.my,
          selectedIcon: AppIcons.my,
          label: l.navMyHealth,
        ),
      ],
      centerAction: KeyedSubtree(
        key: anchors.quickAdd,
        child: AppNavAddButton(tooltip: l.navAddRecordTitle, onPressed: () {}),
      ),
    );
  }
}
