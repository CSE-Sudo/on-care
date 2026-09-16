import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/points/points_rules.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 온보딩이 끝나면 홈으로 가기 전에 한 번 보는 포인트 안내(#1826).
///
/// 포인트는 식단 기록·운동 추가·추천/배정 운동 완료로 쌓이는데, 그 규칙은 MY
/// `포인트 사용처` 헤더의 안내 창에만 있었다. 처음 온 회원은 포인트를 어디서
/// 얻는지 모른 채 시작했다. 게임 첫 화면의 규칙 설명처럼, 할 일(퀘스트)마다
/// 얻는 포인트와 하루 한도를 한 장에 보여 준다.
///
/// 숫자는 적립 규칙([PointsRule]) 한 곳에서 읽는다 — 규칙이 바뀌면 이 안내도
/// 같이 바뀐다.
class PointsGuidePage extends StatelessWidget {
  const PointsGuidePage({super.key});

  /// 안내하는 순서 — 매일 가장 먼저 하게 되는 기록부터.
  static const List<PointsRule> questOrder = <PointsRule>[
    PointsRule.dietEntry,
    PointsRule.exerciseManual,
    PointsRule.routineComplete,
  ];

  static IconData _iconOf(PointsRule rule) => switch (rule) {
    PointsRule.dietEntry => AppIcons.diet,
    PointsRule.exerciseManual => AppIcons.exercise,
    // AI 추천과 트레이너 배정을 한 규칙으로 묶었다 — MY 안내 창과 같은 완료 표시.
    PointsRule.routineComplete => AppIcons.checkCircle,
  };

  static String _actionOf(AppLocalizations l, PointsRule rule) =>
      switch (rule) {
        PointsRule.dietEntry => l.myPointsDietAdd,
        PointsRule.exerciseManual => l.myPointsExerciseAdd,
        PointsRule.routineComplete => l.myPointsRoutineComplete,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double side = tokens.density.pagePadding;
    return Scaffold(
      backgroundColor: OnCareColors.surfaceCard,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnCareLayout.mobileContentMaxWidth,
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s24,
                      side,
                      OnCareSpacing.s16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: OniAvatar(size: OnCareSize.avatarXLarge),
                        ),
                        const SizedBox(height: OnCareSpacing.s16),
                        Text(
                          l.pointsGuideTitle,
                          style: tokens
                              .text(OnCareTypography.titleLarge)
                              .copyWith(color: OnCareColors.textPrimary),
                        ),
                        const SizedBox(height: OnCareSpacing.s8),
                        Text(
                          l.pointsGuideSubtitle,
                          style: tokens
                              .text(OnCareTypography.bodySmall)
                              .copyWith(color: OnCareColors.textSecondary),
                        ),
                        const SizedBox(height: OnCareSpacing.sectionGap),
                        for (final (int i, PointsRule rule)
                            in questOrder.indexed) ...<Widget>[
                          if (i > 0) const SizedBox(height: OnCareSpacing.s12),
                          _QuestCard(
                            key: Key('pointsGuideQuest-${rule.name}'),
                            number: i + 1,
                            icon: _iconOf(rule),
                            action: _actionOf(l, rule),
                            rule: rule,
                          ),
                        ],
                        const SizedBox(height: OnCareSpacing.s16),
                        Text(
                          l.pointsGuideSpendNote,
                          key: const Key('pointsGuideSpendNote'),
                          style: tokens
                              .text(OnCareTypography.caption)
                              .copyWith(color: OnCareColors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    side,
                    OnCareSpacing.s16,
                    side,
                    OnCareSpacing.s16,
                  ),
                  child: AppButton(
                    key: const Key('pointsGuideStart'),
                    label: l.pointsGuideStart,
                    size: OnCareButtonSize.large,
                    fullWidth: true,
                    // 곧바로 홈이 아니라, 예시 자료로 채운 화면 위에서 주요
                    // 기능을 짚어 주는 가이드로 이어진다(#1857). 가이드를 이미
                    // 본 회원은 그 화면이 스스로 홈으로 보낸다.
                    onPressed: () => context.go(AppRoutes.guideTour),
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

/// 퀘스트 한 장 — `퀘스트 1` 태그 · 할 일 · 하루 한도, 오른쪽 끝에 얻는 포인트.
class _QuestCard extends StatelessWidget {
  const _QuestCard({
    super.key,
    required this.number,
    required this.icon,
    required this.action,
    required this.rule,
  });

  final int number;
  final IconData icon;
  final String action;
  final PointsRule rule;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      child: Row(
        children: <Widget>[
          AppIcon(
            icon,
            size: OnCareSize.iconMedium,
            color: tokens.brand.primary,
          ),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppTag(
                  label: l.pointsGuideQuest(number),
                  tone: AppTagTone.brand,
                ),
                const SizedBox(height: OnCareSpacing.s4),
                Text(
                  action,
                  style: tokens
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                Text(
                  l.pointsGuideDailyCap(rule.dailyCap),
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Text(
            l.pointsRewardBadge(rule.points),
            style: OnCareTypography.numeric(
              tokens.text(OnCareTypography.titleMedium),
            ).copyWith(color: tokens.brand.primary),
          ),
        ],
      ),
    );
  }
}
