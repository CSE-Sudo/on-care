import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/benefits/domain/entities/weekly_challenge.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/benefits/presentation/widgets/benefit_cards.dart';
import 'package:oncare/features/benefits/presentation/widgets/challenge_cards.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/app_error_state_for.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 지난 챌린지 결과 — 참가한 주마다 목표·운동한 날·성공 여부·받은 포인트. (#3361)
///
/// 사용처 화면의 챌린지 카드 `지난 결과` 에서 들어온다. 서버(`GET /me/challenges`)가
/// 최근 주 먼저 주는 순서 그대로 적는다. 이번 주처럼 아직 판정 전인 주도 함께
/// 오므로 `진행 중`·`집계 중` 으로 적어 결과가 난 주와 가른다.
class ChallengeHistoryPage extends ConsumerWidget {
  const ChallengeHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<List<Challenge>> history = ref.watch(
      challengeHistoryProvider,
    );
    return AppPage(
      key: const Key('challengeHistoryPage'),
      bottomInset: MediaQuery.paddingOf(context).bottom,
      header: AppTopBar(title: l.challengeHistoryTitle),
      children: <Widget>[
        AppCard(
          child: history.when(
            loading: () => const AppLoading(placement: AppStatePlacement.card),
            error: (Object error, _) => appErrorStateFor(
              context,
              error: error,
              title: l.challengeHistoryLoadFailed,
              onRetry: () => ref.invalidate(challengeHistoryProvider),
              placement: AppStatePlacement.card,
            ),
            data: (List<Challenge> rows) => rows.isEmpty
                ? AppEmptyState(
                    title: l.challengeHistoryEmpty,
                    message: l.challengeHistoryEmptyMessage,
                    icon: kChallengeIcon,
                    placement: AppStatePlacement.card,
                  )
                : Column(
                    children: <Widget>[
                      for (int i = 0; i < rows.length; i++) ...<Widget>[
                        if (i > 0) const AppDivider(),
                        _ResultRow(challenge: rows[i]),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// 결과 한 줄 — 주, 목표와 운동한 날, 성공 여부, 받은 포인트.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final Challenge c = challenge;
    final bool settled = c.status != ChallengeStatus.active;
    final (String label, AppTagTone tone) = switch (c.status) {
      ChallengeStatus.succeeded => (
        l.challengeStatusSucceeded,
        AppTagTone.brand,
      ),
      ChallengeStatus.failed => (l.challengeStatusFailed, AppTagTone.neutral),
      ChallengeStatus.active => (
        c.settling ? l.challengeStatusSettling : l.challengeStatusActive,
        AppTagTone.neutral,
      ),
    };
    return Padding(
      key: ValueKey<String>('challenge-result-${c.id}'),
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s8),
      child: Row(
        children: <Widget>[
          const BenefitIconTile(icon: kChallengeIcon),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  challengeWeekRange(
                    Localizations.localeOf(context).toString(),
                    c,
                  ),
                  style: tokens
                      .text(OnCareTypography.body)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                Text(
                  l.challengeHistoryResult(c.goal, c.progress),
                  key: ValueKey<String>('challenge-result-days-${c.id}'),
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              AppTag(
                key: ValueKey<String>('challenge-result-status-${c.id}'),
                label: label,
                tone: tone,
              ),
              // 받은 포인트는 판정이 끝난 주에만 적는다 — 진행 중인 주의 0P 는
              // 실패처럼 읽힌다.
              if (settled) ...<Widget>[
                const SizedBox(height: OnCareSpacing.s4),
                Text(
                  pointsDelta(l, c.rewarded),
                  key: ValueKey<String>('challenge-result-points-${c.id}'),
                  style:
                      OnCareTypography.numeric(
                        tokens.text(
                          OnCareTypography.strong(OnCareTypography.body),
                        ),
                      ).copyWith(
                        color: c.rewarded > 0
                            ? tokens.brand.primary
                            : OnCareColors.textTertiary,
                      ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
