import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart'
    show clientDemographicsLabel;
import 'package:oncare_ui/oncare_ui.dart';

/// A client row on the 고객 관리 list: avatar + active dot, identity,
/// goal, and a quick-metric footer (칼로리 / 나트륨 / 마지막 루틴).
class ClientCard extends StatelessWidget {
  /// Creates a card for [client]; [onTap] opens the detail screen.
  const ClientCard({
    super.key,
    required this.client,
    required this.onTap,
    this.selected = false,
    this.unread = 0,
    this.compact = false,
  });

  /// The client to render.
  final TrainerClient client;

  /// Called when the card is tapped.
  final VoidCallback onTap;

  /// Highlighted in the wide-viewport split layout when this client's
  /// detail panel is open.
  final bool selected;

  /// Unread chat messages retained for call-site compatibility. The customer
  /// roster intentionally does not expose chat previews or notification badges.
  final int unread;

  /// Dense master-list presentation used by the Figma 회원 관리 split view.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppCard(
      selected: selected,
      onTap: onTap,
      child: compact
          ? _CompactClientContent(client: client)
          : Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AppAvatar(
                      name: client.avatar,
                      size: AppAvatarSize.large,
                      online: client.active,
                    ),
                    const SizedBox(width: OnCareSpacing.s12),
                    Expanded(child: _Identity(client: client)),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: OnCareSize.iconMedium,
                      color: OnCareColors.textDisabled,
                    ),
                  ],
                ),
                const SizedBox(height: OnCareSpacing.s12),
                _WeeklyRoutineAdherence(client: client),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
                  child: AppDivider(),
                ),
                Row(
                  children: <Widget>[
                    _Metric(
                      label: l.metricCalories,
                      value: '${client.calories}kcal',
                    ),
                    _Metric(
                      label: l.metricSodium,
                      value: '${client.sodiumMg}mg',
                      warn: client.sodiumOverBudget,
                    ),
                    _Metric(
                      label: l.clientLastRoutine,
                      value: client.lastRoutine,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _CompactClientContent extends StatelessWidget {
  const _CompactClientContent({required this.client});

  final TrainerClient client;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        AppAvatar(
          name: client.avatar,
          size: AppAvatarSize.large,
          online: client.active,
        ),
        const SizedBox(width: OnCareSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Identity(client: client),
              const SizedBox(height: OnCareSpacing.s8),
              _WeeklyRoutineAdherence(client: client),
            ],
          ),
        ),
      ],
    );
  }
}

/// 이름 + 인구정보(`여성 · 29세`) 한 줄, 그 아래 목표 한 줄.
///
/// 이름이 같은 회원을 가르는 인구정보는 이름 옆에 한 단계 흐리게 둔다.
class _Identity extends StatelessWidget {
  const _Identity({required this.client});

  final TrainerClient client;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                client.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.strong(OnCareTypography.bodyLarge))
                    .copyWith(color: OnCareColors.textPrimary),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s4),
            Flexible(
              child: Text(
                clientDemographicsLabel(context, client),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ),
          ],
        ),
        Text(
          client.goal,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens
              .text(OnCareTypography.bodySmall)
              .copyWith(color: OnCareColors.textSecondary),
        ),
      ],
    );
  }
}

/// 이번 주에 기록된 날만 평균낸 루틴 수행률.
///
/// 0은 미수행이 아니라 미집계이므로 빈 주를 0% 실패처럼 그리지 않는다. 주의
/// 배지와 고객 검색이 쓰는 [recordedCompletionMean]을 그대로 사용해 고객
/// 목록 안에서 같은 회원을 서로 다른 숫자로 말하지 않게 한다. (#1284)
class _WeeklyRoutineAdherence extends StatelessWidget {
  const _WeeklyRoutineAdherence({required this.client});

  final TrainerClient client;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double? mean = recordedCompletionMean(client);
    final int? percent = mean?.round();
    final String valueLabel = percent == null
        ? l.clientRoutineAdherenceUnmeasured
        : '$percent%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l.clientWeeklyRoutineAdherence,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            Text(
              valueLabel,
              style:
                  OnCareTypography.numeric(
                    tokens.text(
                      OnCareTypography.strong(OnCareTypography.caption),
                    ),
                  ).copyWith(
                    color: percent == null
                        ? OnCareColors.textSecondary
                        : OnCareColors.textPrimary,
                  ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s4),
        Semantics(
          label: l.clientWeeklyRoutineAdherence,
          value: valueLabel,
          child: ExcludeSemantics(
            child: AppProgressBar(
              key: ValueKey<String>('client-weekly-adherence-${client.id}'),
              value: (mean ?? 0).clamp(0, 100) / 100,
            ),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s2),
          Text(
            value,
            style:
                OnCareTypography.numeric(
                  tokens.text(
                    OnCareTypography.strong(OnCareTypography.bodySmall),
                  ),
                ).copyWith(
                  color: warn ? OnCareColors.danger : OnCareColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}
