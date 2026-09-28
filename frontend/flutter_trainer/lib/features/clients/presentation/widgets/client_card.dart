import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart'
    show recordedCompletionMean;
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';
import 'package:oncare_trainer/shared/widgets/client_signal_badges.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// A member row on the 회원 관리 list: avatar, identity, goal, and this
/// week's routine adherence.
///
/// 활성 표시(아바타의 초록 점)는 없앴다(#2204). PT 관리 신호 배지는 평소에는
/// 이 행이 아니라 **회원 상세**에서 본다(#2258) — 목록은 회원의 한 주를 막대로
/// 훑는 자리다. 필터로 좁힌 동안에만 [signals] 로 **걸린 이유**를 카드 오른쪽
/// 위에 함께 보여 준다 — 이름 줄 옆 빈자리를 쓰므로 막대도 행 높이도 그대로다.
class ClientCard extends StatelessWidget {
  /// Creates a card for [client]; [onTap] opens the detail screen.
  const ClientCard({
    super.key,
    required this.client,
    required this.onTap,
    this.selected = false,
    this.unread = 0,
    this.signals = const <ClientSignal>[],
    this.action,
  });

  /// The client to render.
  final TrainerClient client;

  /// Called when the card is tapped.
  final VoidCallback onTap;

  /// Highlighted in the wide-viewport split layout when this client's
  /// detail panel is open.
  final bool selected;

  /// Unread chat messages retained for call-site compatibility. The member
  /// roster intentionally does not expose chat previews or notification badges.
  final int unread;

  /// 필터로 좁힌 동안 이 회원이 걸린 이유. 비어 있으면(평소) 배지 줄이 없다.
  final List<ClientSignal> signals;

  /// 이름 줄 오른쪽 끝의 동작(예: 내 정보 › 회원 관리의 삭제 아이콘). 카드
  /// 안에 두어 어느 회원의 동작인지 한눈에 보이게 한다. 없으면 자리도 없다.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          // 이름 줄 옆 배지·동작과 아래 막대까지 한 묶음이라 [ClientRow] 대신
          // 같은 밀도의 아바타·이름 묶음을 직접 놓는다(#2467).
          ClientAvatar(
            name: client.avatar,
            size: ClientRowDensity.list.avatarSize,
          ),
          SizedBox(width: ClientRowDensity.list.avatarGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: ClientIdentityBlock(client: client)),
                    if (signals.isNotEmpty) ...<Widget>[
                      const SizedBox(width: OnCareSpacing.s8),
                      _MatchedSignals(clientId: client.id, signals: signals),
                    ],
                    if (action != null) ...<Widget>[
                      const SizedBox(width: OnCareSpacing.s8),
                      action!,
                    ],
                  ],
                ),
                const SizedBox(height: OnCareSpacing.s8),
                _WeeklyRoutineAdherence(client: client),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 필터로 좁힌 동안 카드 오른쪽 위에 붙는 **걸린 이유** — 목록 배지와 같은
/// 문구·색. 여럿이면 오른쪽 끝을 맞춰 아래로 쌓는다 — 옆으로 늘어놓으면 이름이
/// 먼저 잘린다.
class _MatchedSignals extends StatelessWidget {
  const _MatchedSignals({required this.clientId, required this.signals});

  final String clientId;
  final List<ClientSignal> signals;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey<String>('client-signals-$clientId'),
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: OnCareSpacing.s4,
      children: <Widget>[
        for (final ClientSignal signal in signals)
          ClientSignalTag(signal: signal, detailed: false),
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
