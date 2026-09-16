import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/points/points_rules.dart';
import 'package:oncare/features/app_guide/domain/guide_step.dart';
import 'package:oncare/features/app_guide/presentation/controllers/app_guide_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 첫 홈 진입 가이드의 덮개 — 화면을 어둡게 덮고 지금 짚는 자리만 밝게 뚫는다.
/// (#1857)
///
/// 셸(하단 내비까지 포함한 화면 전체) 위에 얹혀야 한다 — 짚는 자리의 절반이
/// 하단 내비이기 때문이다.
class AppGuideOverlay extends ConsumerStatefulWidget {
  const AppGuideOverlay({super.key});

  @override
  ConsumerState<AppGuideOverlay> createState() => _AppGuideOverlayState();
}

class _AppGuideOverlayState extends ConsumerState<AppGuideOverlay> {
  /// 지금 짚는 자리(이 덮개 좌표계). 아직 재지 못했으면 null 이고, 그때는
  /// 구멍 없이 덮는다.
  Rect? _hole;
  GuideStepId? _measuredStep;

  /// 한 프레임 뒤에 잰다 — 덮개가 그려지는 시점에는 짚을 요소가 이미 배치돼
  /// 있지만, 자리(Rect)는 그 프레임이 끝나야 확정된다.
  void _scheduleMeasure(GuideStepId? step) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final Rect? next = _measure(step);
      if (_measuredStep == step && next == _hole) return;
      setState(() {
        _measuredStep = step;
        _hole = next;
      });
    });
  }

  Rect? _measure(GuideStepId? step) {
    if (step == null) return null;
    final GlobalKey key = ref.read(guideAnchorsProvider).keyOf(step);
    final BuildContext? anchor = key.currentContext;
    final RenderObject? render = anchor?.findRenderObject();
    final RenderBox? self = context.findRenderObject() as RenderBox?;
    if (render is! RenderBox || !render.hasSize) return null;
    if (self == null || !self.hasSize) return null;
    final Offset topLeft = render.localToGlobal(Offset.zero, ancestor: self);
    return topLeft & render.size;
  }

  @override
  Widget build(BuildContext context) {
    final AppGuideState guide = ref.watch(appGuideControllerProvider);
    final GuideStepId? step = guide.step;
    if (step == null) return const SizedBox.shrink();
    // 단계가 바뀌면 새 자리를 잰다.
    if (step != _measuredStep) _scheduleMeasure(step);

    return AppSpotlight(
      key: const Key('appGuideOverlay'),
      hole: _hole,
      holeRadius: step == GuideStepId.homeSummary
          ? OnCareRadius.xl
          : OnCareRadius.lg,
      caption: _GuideCard(guide: guide, step: step),
    );
  }
}

/// 구멍 옆 설명 카드 — 가이드라는 표시와 `n/N`, 제목·한 줄 설명, 건너뛰기와 다음.
class _GuideCard extends ConsumerWidget {
  const _GuideCard({required this.guide, required this.step});

  final AppGuideState guide;
  final GuideStepId step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final AppGuideController controller = ref.read(
      appGuideControllerProvider.notifier,
    );
    return AppCard(
      key: const Key('appGuideCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              // 이것이 무엇인지부터 말한다 — 갑자기 화면이 어두워진 이유다.
              AppTag(
                key: const Key('appGuideBadge'),
                label: l.guideBadge,
                tone: AppTagTone.brand,
                icon: AppIcons.info,
              ),
              const Spacer(),
              Text(
                l.guideStepCount(guide.stepNumber, guide.totalSteps),
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            _title(l, step),
            style: tokens
                .text(OnCareTypography.titleSmall)
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            _body(l, step),
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Row(
            children: <Widget>[
              // 건너뛰기는 작게 — 보고 싶은 사람을 막지 않으면서, 그만 보고
              // 싶은 사람에게는 늘 열려 있어야 한다.
              AppButton(
                key: const Key('appGuideSkip'),
                label: l.guideSkip,
                variant: AppButtonVariant.text,
                size: OnCareButtonSize.small,
                onPressed: controller.skip,
              ),
              const Spacer(),
              AppButton(
                key: const Key('appGuideNext'),
                label: guide.isLast ? l.guideDone : l.guideNext,
                size: OnCareButtonSize.small,
                onPressed: controller.next,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _title(AppLocalizations l, GuideStepId step) => switch (step) {
    GuideStepId.homeSummary => l.guideHomeTitle,
    GuideStepId.alerts => l.guideAlertsTitle,
    GuideStepId.diet => l.guideDietTitle,
    GuideStepId.quickAdd => l.guideQuickAddTitle,
    GuideStepId.exercise => l.guideExerciseTitle,
    GuideStepId.points => l.guidePointsTitle,
  };

  /// 포인트 단계의 숫자는 적립 규칙([PointsRule]) 한 곳에서 읽는다 — 안내가
  /// 규칙보다 오래 살아남아 옛 숫자를 말하는 일이 없게(#1826 과 같은 규칙).
  static String _body(AppLocalizations l, GuideStepId step) => switch (step) {
    GuideStepId.homeSummary => l.guideHomeBody,
    GuideStepId.alerts => l.guideAlertsBody,
    GuideStepId.diet => l.guideDietBody,
    GuideStepId.quickAdd => l.guideQuickAddBody,
    GuideStepId.exercise => l.guideExerciseBody,
    GuideStepId.points => l.guidePointsBody(
      PointsRule.dietEntry.points,
      PointsRule.exerciseManual.points,
      PointsRule.routineComplete.points,
    ),
  };
}
