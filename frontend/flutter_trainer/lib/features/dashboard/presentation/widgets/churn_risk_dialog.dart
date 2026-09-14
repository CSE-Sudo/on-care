import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/dashboard/domain/churn_risk.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';
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
        AppListRow(
          key: ValueKey<String>('churn-risk-tile-${client.id}'),
          title: clientIdentityLabel(context, client),
          subtitle: client.goal.trim().isNotEmpty ? client.goal : null,
          leading: AppAvatar(name: client.name),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            size: OnCareSize.iconMedium,
            color: OnCareColors.textDisabled,
          ),
          onTap: () {
            Navigator.of(context).pop();
            context.go(AppRoutes.clientDetail(client.id));
          },
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
              for (final signal in entry.signals)
                AppTag(label: signal.label(l), tone: AppTagTone.danger),
            ],
          ),
        ),
      ],
    );
  }
}
