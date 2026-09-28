import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/dashboard/domain/churn_risk.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';
import 'package:oncare_trainer/shared/widgets/client_signal_badges.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Opens the 이탈 위험 dialog: who's flagged, and why.
Future<void> showChurnRiskDialog(
  BuildContext context, {
  required List<ChurnRiskClient> entries,
}) => showAppDialog<void>(
  context: context,
  builder: (_) => ChurnRiskDialog(entries: entries),
);

/// Lists every 이탈 위험 client with the reasons they were flagged — the
/// KPI card is a count, this is the "왜" behind it (#[dashboard]).
class ChurnRiskDialog extends StatelessWidget {
  /// Creates the dialog body.
  const ChurnRiskDialog({super.key, required this.entries});

  /// Flagged clients, worst (most reasons) first.
  final List<ChurnRiskClient> entries;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppDialog(
      key: const ValueKey<String>('churn-risk-dialog'),
      title: l.dashChurnRiskTitle,
      size: AppDialogSize.medium,
      child: entries.isEmpty
          ? AppEmptyState(
              title: l.dashChurnRiskEmpty,
              placement: AppStatePlacement.card,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < entries.length; i++) ...<Widget>[
                  if (i > 0) const AppDivider(),
                  _ChurnRiskTile(entry: entries[i]),
                ],
              ],
            ),
    );
  }
}

class _ChurnRiskTile extends StatelessWidget {
  const _ChurnRiskTile({required this.entry});

  final ChurnRiskClient entry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final client = entry.client;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 이름·성별 나이·목표는 회원 목록과 같은 공용 이름 묶음이다(#2364·
        // #2467) — 같은 회원을 이 창에서만 다른 글씨로 부르지 않는다. 줄의
        // 여백·높이·눌림은 목록 줄([AppListRow])과 같다.
        Material(
          key: ValueKey<String>('churn-risk-tile-${client.id}'),
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () {
              Navigator.of(context).pop();
              context.go(AppRoutes.clientDetail(client.id));
            },
            hoverColor: context.oncare.brand.surface,
            borderRadius: OnCareRadius.mdAll,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: context.oncare.density.listRowMin,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: OnCareSpacing.s16,
                  vertical: OnCareSpacing.s12,
                ),
                child: Row(
                  children: <Widget>[
                    ClientAvatar(name: client.avatar),
                    const SizedBox(width: OnCareSpacing.s12),
                    Expanded(child: ClientIdentityBlock(client: client)),
                    const SizedBox(width: OnCareSpacing.s8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: OnCareSize.iconMedium,
                      color: OnCareColors.textDisabled,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            OnCareSpacing.s16,
            0,
            OnCareSpacing.s16,
            OnCareSpacing.s12,
          ),
          child: Wrap(
            spacing: OnCareSpacing.s4,
            runSpacing: OnCareSpacing.s4,
            children: <Widget>[
              // 회원 상세 헤더와 같은 배지 — 같은 회원을 여기서 다른 말로
              // 부르지 않는다(#2364).
              for (final signal in entry.signals)
                KeyedSubtree(
                  key: ValueKey<String>(
                    'churn-risk-alert-${client.id}-${signal.kind.wire}',
                  ),
                  child: ClientSignalTag(signal: signal),
                ),
              // 트레이너 자신의 활동이지 회원의 상태가 아니다 — 회색으로 둔다.
              if (entry.noRecentFeedback)
                AppTag(
                  key: ValueKey<String>('churn-risk-no-feedback-${client.id}'),
                  label: l.churnNoRecentFeedback,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
