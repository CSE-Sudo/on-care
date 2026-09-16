import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/points/points_rules.dart';
import 'package:oncare/features/app_guide/domain/guide_step.dart';
import 'package:oncare/features/app_guide/presentation/controllers/app_guide_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 사용 가이드의 덮개 — 화면을 어둡게 덮고 지금 짚는 자리만 밝게 뚫는다. (#1857)
///
/// 짚는 자리에는 꼬리 달린 작은 말풍선이 붙고, 화면 위쪽에 `앱 사용 가이드 n/N`
/// 과 `건너뛰기`, 아래쪽에 `이전`·`다음` 이 선다. 말풍선을 크게 만들지 않는 이유는
/// 단순하다 — 설명이 크면 정작 짚은 자리를 가린다.
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
    final RenderObject? anchor = key.currentContext?.findRenderObject();
    final RenderObject? self = context.findRenderObject();
    if (anchor is! RenderBox || !anchor.hasSize) return null;
    if (self is! RenderBox || !self.hasSize) return null;
    // 짚는 요소는 이 덮개의 **형제**다(같은 Stack 아래 예시 화면 쪽에 있다).
    // 덮개를 기준으로 바로 변환할 수 없으므로 둘 다 화면 좌표로 읽어 뺀다 —
    // 예전에는 덮개를 조상으로 넘겨, 구멍이 엉뚱한 자리에 생기거나 아예 생기지
    // 않았다.
    final Offset delta =
        anchor.localToGlobal(Offset.zero) - self.localToGlobal(Offset.zero);
    final Rect rect = delta & anchor.size;
    // 화면 밖으로 밀린 자리는 짚지 않는다 — 덮기만 한다.
    if (!rect.isFinite || !rect.overlaps(Offset.zero & self.size)) return null;
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    final AppGuideState guide = ref.watch(appGuideControllerProvider);
    final GuideStepId? step = guide.step;
    if (step == null) return const SizedBox.shrink();
    // 단계가 바뀌면 새 자리를 잰다.
    if (step != _measuredStep) _scheduleMeasure(step);

    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final AppGuideController controller = ref.read(
      appGuideControllerProvider.notifier,
    );

    return AppSpotlight(
      key: const Key('appGuideOverlay'),
      hole: _hole,
      holeRadius: step == GuideStepId.homeSummary
          ? OnCareRadius.xl
          : OnCareRadius.lg,
      // 갑자기 어두워진 이유와 남은 길이를 화면 맨 위에서 먼저 말한다.
      topBar: Row(
        children: <Widget>[
          AppTag(
            key: const Key('appGuideBadge'),
            label: l.guideBadgeWithStep(guide.stepNumber, guide.totalSteps),
            tone: AppTagTone.brand,
            icon: AppIcons.info,
          ),
          const Spacer(),
          // 건너뛰기는 작게, 그러나 어느 단계에서나 열려 있다.
          AppSpotlightAction(
            key: const Key('appGuideSkip'),
            label: l.guideSkip,
            onPressed: controller.skip,
          ),
        ],
      ),
      caption: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _title(l, step),
            key: const Key('appGuideCard'),
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
        ],
      ),
      bottomBar: Row(
        children: <Widget>[
          if (!guide.isFirst)
            AppSpotlightAction(
              key: const Key('appGuidePrev'),
              label: l.guidePrev,
              leadingIcon: AppIcons.back,
              onPressed: controller.previous,
            ),
          const Spacer(),
          AppSpotlightAction(
            key: const Key('appGuideNext'),
            label: guide.isLast ? l.guideDone : l.guideNext,
            trailingIcon: AppIcons.chevronRight,
            onPressed: controller.next,
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
