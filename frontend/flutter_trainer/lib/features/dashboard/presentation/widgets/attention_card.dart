import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Clients who need the trainer today, with the reason spelled out.
///
/// A bare priority list ("these five, in this order") makes the trainer
/// re-derive why each name is there. The badge carries the reason, and
/// the row opens straight to the section that fixes it — 답장 대기 goes
/// to the chat, 나트륨 초과 goes to the diet.
class AttentionCard extends StatelessWidget {
  /// Creates the card for [entries].
  const AttentionCard({super.key, required this.entries, this.maxRows = 5});

  /// Attention entries, most urgent first.
  final List<AttentionClient> entries;

  /// How many rows to show before deferring to the 고객 tab.
  final int maxRows;

  /// The client sub-section that addresses [alert].
  static String sectionFor(ClientAlert alert) => switch (alert) {
    ClientAlert.unanswered => 'chat',
    ClientAlert.sodiumOver => 'diet',
    ClientAlert.sugarOver => 'diet',
    ClientAlert.lowCompletion => 'workout',
  };

  /// 알림 뜻을 담는 태그 톤 — 남색 = 처리 필요, 빨강 = 목표 초과, 주황 = 이행률 저조.
  static AppTagTone _toneFor(ClientAlert alert) => switch (alert) {
    ClientAlert.unanswered => AppTagTone.brand,
    ClientAlert.sodiumOver => AppTagTone.danger,
    ClientAlert.sugarOver => AppTagTone.danger,
    ClientAlert.lowCompletion => AppTagTone.caution,
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final shown = entries.take(maxRows).toList();
    final bool hasMore = entries.length > maxRows;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSectionHeader(
            title: l.dashAttentionTitle,
            icon: Icons.priority_high_rounded,
            actionLabel: hasMore
                ? l.dashMoreCount(entries.length - maxRows)
                : null,
            onAction: hasMore
                ? () => context.go(AppRoutes.clientsFiltered('attention'))
                : null,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          if (shown.isEmpty)
            AppEmptyState(
              title: l.dashNoAttention,
              icon: Icons.check_circle_rounded,
              placement: AppStatePlacement.card,
            )
          else
            for (final entry in shown)
              AppListRow(
                title: clientIdentityLabel(context, entry.client),
                subtitle: entry.client.goal.trim().isEmpty
                    ? null
                    : entry.client.goal,
                leading: AppAvatar(name: entry.client.name),
                trailing: AppTag(
                  label: entry.primary.label(l),
                  tone: _toneFor(entry.primary),
                ),
                onTap: () => context.go(
                  AppRoutes.clientDetail(
                    entry.client.id,
                    section: sectionFor(entry.primary),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
