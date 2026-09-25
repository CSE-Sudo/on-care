import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/utils/health_focus_labels.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart'
    show clientDemographicsLabel;
import 'package:oncare_ui/oncare_ui.dart';

/// 한 행에 보여 주는 신호 배지 수. 나머지는 `+N` 으로 접는다 — 배지가 줄을
/// 넘기면 회원 사이의 높이가 들쭉날쭉해져 목록을 훑기 어렵다.
const int _maxVisibleSignals = 2;

/// A member row on the 회원 관리 list: avatar, identity, goal, and the PT
/// 관리 신호 badges (#2204).
///
/// 활성 표시(아바타의 초록 점)와 주간 이행률 막대는 없앴다 — 목록이 답하는
/// 질문은 "누가 흐름이 끊겼나, 누가 목표에서 벗어났나, 누가 불편을
/// 호소하나" 이고, 이행률은 `기록 끊김`·`운동 목표 미달` 이 대신한다.
class ClientCard extends StatelessWidget {
  /// Creates a card for [client]; [onTap] opens the detail screen.
  const ClientCard({
    super.key,
    required this.client,
    required this.onTap,
    this.selected = false,
    this.unread = 0,
  });

  /// The client to render.
  final TrainerClient client;

  /// Called when the card is tapped.
  final VoidCallback onTap;

  /// Highlighted in the wide-viewport split layout when this client's
  /// detail panel is open.
  final bool selected;

  /// Unread chat messages. The row doesn't preview chats; a non-zero count
  /// only adds the `답장 대기` badge.
  final int unread;

  @override
  Widget build(BuildContext context) {
    final List<ClientSignal> signals = rosterSignalsFor(client, unread: unread);
    return AppCard(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          AppAvatar(name: client.avatar, size: AppAvatarSize.large),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Identity(client: client),
                if (signals.isNotEmpty) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.s8),
                  _SignalBadges(clientId: client.id, signals: signals),
                ],
              ],
            ),
          ),
        ],
      ),
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
        // 회원 건강 목표를 로케일 문구로(#1818).
        Text(
          healthFocusGoalLabel(AppLocalizations.of(context), client.goal),
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

/// 급한 신호 [_maxVisibleSignals] 개와, 넘치면 `+N`.
///
/// 접힌 신호도 스크린리더에는 모두 읽힌다 — 보이지 않는다고 없는 것이 아니다.
class _SignalBadges extends StatelessWidget {
  const _SignalBadges({required this.clientId, required this.signals});

  final String clientId;
  final List<ClientSignal> signals;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<ClientSignal> shown = signals
        .take(_maxVisibleSignals)
        .toList();
    final int hidden = signals.length - shown.length;
    return Semantics(
      label: signals.map((s) => s.badgeLabel(l)).join(', '),
      child: ExcludeSemantics(
        child: Wrap(
          key: ValueKey<String>('client-signals-$clientId'),
          spacing: OnCareSpacing.s4,
          runSpacing: OnCareSpacing.s4,
          children: <Widget>[
            for (final ClientSignal signal in shown)
              AppTag(label: signal.badgeLabel(l), tone: signal.kind.tone),
            if (hidden > 0) AppTag(label: l.clientsSignalMore(hidden)),
          ],
        ),
      ),
    );
  }
}
