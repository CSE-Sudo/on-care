import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_actions.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_file_name.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_sender.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// A generated report's explicit delivery actions.
///
/// Kept public so the save and print boundaries can be exercised without
/// generating a PDF in a widget test.
class ReportPdfExportDialog extends ConsumerStatefulWidget {
  const ReportPdfExportDialog({
    required this.report,
    required this.bytes,
    super.key,
  });

  final WeeklyReport report;
  final Uint8List bytes;

  @override
  ConsumerState<ReportPdfExportDialog> createState() =>
      _ReportPdfExportDialogState();
}

class _ReportPdfExportDialogState extends ConsumerState<ReportPdfExportDialog> {
  bool _sending = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    final l = AppLocalizations.of(context);
    try {
      await action();
      if (mounted) showAppToast(context, success, type: AppToastType.success);
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          l.reportsPdfActionFailed,
          type: AppToastType.error,
        );
      }
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final l = AppLocalizations.of(context);
    await _run(
      () => ref
          .read(reportPdfSenderProvider)
          .send(
            clientId: widget.report.client.id,
            weekStart: widget.report.weekStart,
            bytes: widget.bytes,
            fileName: reportPdfFileName(l, widget.report),
            message: l.reportsPdfMessage,
          ),
      l.reportsPdfSent(widget.report.client.name),
    );
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final actions = ref.read(reportPdfActionsProvider);
    return AppDialog(
      title: l.reportsPdfLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(l.reportsPdfReady(widget.report.client.name)),
          const SizedBox(height: OnCareSpacing.s16),
          AppButton(
            key: const ValueKey<String>('report-pdf-send'),
            label: _sending ? l.reportsPdfSending : l.reportsPdfSendToClient,
            leadingIcon: Icons.send_rounded,
            variant: AppButtonVariant.secondary,
            fullWidth: true,
            onPressed: _sending ? null : _send,
          ),
          const SizedBox(height: OnCareSpacing.buttonGap),
          AppButton(
            key: const ValueKey<String>('report-pdf-save'),
            label: l.reportsPdfSave,
            leadingIcon: Icons.download_rounded,
            variant: AppButtonVariant.secondary,
            fullWidth: true,
            onPressed: () => _run(
              () => actions.save(
                widget.bytes,
                reportPdfFileName(l, widget.report),
              ),
              l.reportsPdfSaveStarted,
            ),
          ),
          const SizedBox(height: OnCareSpacing.buttonGap),
          AppButton(
            key: const ValueKey<String>('report-pdf-print'),
            label: l.reportsPdfPrint,
            leadingIcon: Icons.print_rounded,
            variant: AppButtonVariant.secondary,
            fullWidth: true,
            onPressed: () => _run(
              () => actions.print(
                widget.bytes,
                reportPdfFileName(l, widget.report),
              ),
              l.reportsPdfPrintOpened,
            ),
          ),
          const SizedBox(height: OnCareSpacing.buttonGap),
          AppButton(
            label: l.reportsPdfClose,
            variant: AppButtonVariant.text,
            fullWidth: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
