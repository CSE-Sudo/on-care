import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/benefits/presentation/widgets/benefit_cards.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 챌린지 아이콘 — 사용처 카드·내 혜택·운동 현황이 같은 것을 쓴다.
const IconData kChallengeIcon = AppIcons.challenge;

/// `9.14~9.20`.
String challengeWeekRange(Challenge challenge) =>
    '${challenge.weekStart.month}.${challenge.weekStart.day}~'
    '${challenge.weekEnd.month}.${challenge.weekEnd.day}';

/// 참가 카드에 적는 막힌 이유. 참가할 수 있거나 이미 참가했으면 null.
String? challengeBlockLabel(AppLocalizations l, WeeklyChallenge state) {
  if (state.joinable) return null;
  return switch (state.blockReason) {
    ChallengeBlockReason.joinClosed => l.challengeJoinClosed,
    ChallengeBlockReason.insufficientPoints => l.myPointsShortfall(
      l.myPointsCost(state.shortfall),
    ),
    ChallengeBlockReason.alreadyJoined ||
    ChallengeBlockReason.unknown ||
    null => null,
  };
}

/// 사용처 화면의 주간 운동 챌린지 카드. (#1789)
///
/// 참가 전에는 건 포인트·목표·보상과 `참가` 버튼을, 참가했으면 이번 주 진행을
/// 보여 준다. 참가할 수 없으면 버튼을 막고 이유를 버튼 왼쪽에 적는다.
class WeeklyChallengeCard extends StatelessWidget {
  const WeeklyChallengeCard({
    super.key,
    required this.state,
    required this.onJoin,
    this.busy = false,
  });

  final WeeklyChallenge state;

  /// null 이면 버튼이 막힌다(참가 불가이거나 다른 요청이 진행 중).
  final VoidCallback? onJoin;

  /// 참가 요청이 나가 있다.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final Challenge? joined = state.challenge;
    final String? blocked = challengeBlockLabel(l, state);
    return AppCard(
      key: const Key('weeklyChallengeCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const BenefitIconTile(icon: kChallengeIcon),
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
                            l.challengeTitle,
                            style: tokens
                                .text(OnCareTypography.titleSmall)
                                .copyWith(color: OnCareColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: OnCareSpacing.s8),
                        AppTag(
                          label: l.myPointsCost(state.stake),
                          tone: AppTagTone.brand,
                        ),
                      ],
                    ),
                    const SizedBox(height: OnCareSpacing.s4),
                    Text(
                      l.challengeDescription(
                        l.myPointsCost(state.stake),
                        state.goal,
                        l.myPointsCost(state.reward),
                      ),
                      key: const Key('weeklyChallengeDescription'),
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                    if (joined == null) ...<Widget>[
                      const SizedBox(height: OnCareSpacing.s4),
                      Text(
                        l.challengeJoinWindow,
                        style: tokens
                            .text(OnCareTypography.caption)
                            .copyWith(color: OnCareColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s12),
          if (joined != null)
            ChallengeProgressView(challenge: joined)
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: blocked == null
                      ? const SizedBox.shrink()
                      : Text(
                          blocked,
                          key: const Key('weeklyChallengeBlocked'),
                          style: tokens
                              .text(
                                OnCareTypography.strong(
                                  OnCareTypography.caption,
                                ),
                              )
                              .copyWith(color: OnCareColors.textSecondary),
                        ),
                ),
                const SizedBox(width: OnCareSpacing.s8),
                AppButton(
                  key: const Key('weeklyChallengeJoin'),
                  label: l.challengeJoin,
                  size: OnCareButtonSize.small,
                  loading: busy,
                  onPressed: state.joinable ? onJoin : null,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 챌린지 진행 — `이번 주 진행  2 / 3회`, 막대, 남은 횟수 안내 한 줄.
class ChallengeProgressView extends StatelessWidget {
  const ChallengeProgressView({
    super.key,
    required this.challenge,
    this.title,
    this.showHint = true,
  });

  final Challenge challenge;

  /// 왼쪽 제목. 없으면 `이번 주 진행`.
  final String? title;

  /// 남은 횟수·달성 안내 줄을 보일지.
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    final Challenge c = challenge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title ?? l.challengeThisWeek,
                style: tokens
                    .text(OnCareTypography.label)
                    .copyWith(color: OnCareColors.textSecondary),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            Text(
              l.challengeProgress(c.progress, c.goal),
              key: ValueKey<String>('challenge-progress-${c.id}'),
              style: OnCareTypography.numeric(
                tokens.text(OnCareTypography.titleSmall),
              ).copyWith(color: tokens.brand.primary),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        AppProgressBar(
          value: c.goal <= 0 ? 0 : c.progress / c.goal,
          color: c.achieved ? OnCareColors.success : null,
        ),
        if (showHint) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            c.achieved
                ? l.challengeAchieved(l.myPointsCost(c.reward))
                : l.challengeRemaining(c.remaining, l.myPointsCost(c.reward)),
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ],
      ],
    );
  }
}


/// 운동 탭의 주간 챌린지 진행 줄. 이번 주에 참가했을 때만 선다. (#1789)
///
/// 불러오는 중·실패·참가 전에는 아무것도 그리지 않는다 — 운동 탭이 먼저 답할
/// 것은 "얼마나 했나" 이고, 챌린지는 참가한 회원에게만 덧붙는 정보다.
///
/// `운동 현황`·`AI 맞춤 조언` 아래에 선다. 그 둘은 기간 토글(오늘·이번 주·전체)을
/// 따라가는데 챌린지는 언제나 이번 주라, 사이에 끼우면 한 세로줄에서 기준 기간이
/// 말없이 바뀐다. 제목에 주 범위를 적는 것도 같은 이유다.
class ExerciseChallengeProgress extends ConsumerWidget {
  const ExerciseChallengeProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Challenge? challenge = ref
        .watch(weeklyChallengeProvider)
        .valueOrNull
        ?.challenge;
    if (challenge == null || challenge.status != ChallengeStatus.active) {
      return const SizedBox.shrink();
    }
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: OnCareSpacing.s12),
        AppCard(
          key: const Key('exerciseChallengeProgress'),
          child: Row(
            children: <Widget>[
              AppIcon(
                kChallengeIcon,
                size: OnCareSize.iconMedium,
                color: tokens.brand.primary,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: ChallengeProgressView(
                  challenge: challenge,
                  title: l.challengeShortWithRange(
                    challengeWeekRange(challenge),
                  ),
                  showHint: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
