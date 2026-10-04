import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/repositories/trainer_report_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/trainer_report_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 신고 시트가 닫히며 알려 주는 결과.
enum TrainerReportOutcome { submitted, alreadyOpen }

/// 트레이너 신고 시트를 띄우고, 닫히면 결과를 토스트로 알린다 (#3008).
///
/// 트레이너 상세·헬스장 상세의 소속 트레이너 줄·연결된 내 트레이너 카드가 같은
/// 시트를 연다. 실패(네트워크 등)는 시트 안에서 알리고 입력을 남겨 다시 보내게
/// 한다 — 닫아 버리면 적은 메모가 사라진다.
Future<void> showTrainerReportSheet(
  BuildContext context,
  Trainer trainer,
) async {
  final TrainerReportOutcome? outcome =
      await showAppSheet<TrainerReportOutcome>(
        context: context,
        builder: (BuildContext sheetContext) =>
            TrainerReportSheet(trainer: trainer),
      );
  if (outcome == null || !context.mounted) return;
  final AppLocalizations l = AppLocalizations.of(context);
  switch (outcome) {
    case TrainerReportOutcome.submitted:
      showAppToast(
        context,
        l.exTrainerReportSubmitted,
        type: AppToastType.success,
      );
    case TrainerReportOutcome.alreadyOpen:
      showAppToast(context, l.exTrainerReportAlreadyOpen);
  }
}

/// 사유(사칭·부적절한 메시지·기타)와 메모를 받아 신고를 보내는 시트.
class TrainerReportSheet extends ConsumerStatefulWidget {
  const TrainerReportSheet({required this.trainer, super.key});

  final Trainer trainer;

  @override
  ConsumerState<TrainerReportSheet> createState() => _TrainerReportSheetState();
}

class _TrainerReportSheetState extends ConsumerState<TrainerReportSheet> {
  final TextEditingController _memo = TextEditingController();
  TrainerReportReason? _reason;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // 기타 사유는 메모가 있어야 보낼 수 있어, 글자가 바뀔 때 버튼을 다시 그린다.
    _memo.addListener(_onMemoChanged);
  }

  void _onMemoChanged() => setState(() {});

  @override
  void dispose() {
    _memo
      ..removeListener(_onMemoChanged)
      ..dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final TrainerReportReason? reason = _reason;
    if (reason == null || _submitting) return false;
    return !reason.needsMemo || _memo.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    final TrainerReportReason? reason = _reason;
    if (reason == null) return;
    setState(() => _submitting = true);
    final NavigatorState navigator = Navigator.of(context);
    try {
      await ref
          .read(trainerReportRepositoryProvider)
          .report(widget.trainer.id, reason: reason, memo: _memo.text);
      if (!mounted) return;
      navigator.pop(TrainerReportOutcome.submitted);
    } on TrainerReportAlreadyOpen {
      if (!mounted) return;
      navigator.pop(TrainerReportOutcome.alreadyOpen);
    } on Object {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppToast(
        context,
        AppLocalizations.of(context).errorUnknown,
        type: AppToastType.error,
      );
    }
  }

  String _label(AppLocalizations l, TrainerReportReason reason) =>
      switch (reason) {
        TrainerReportReason.impersonation =>
          l.exTrainerReportReasonImpersonation,
        TrainerReportReason.inappropriateMessage =>
          l.exTrainerReportReasonInappropriateMessage,
        TrainerReportReason.other => l.exTrainerReportReasonOther,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final bool memoRequired = _reason?.needsMemo ?? false;
    return AppSheet(
      key: const Key('trainer-report-sheet'),
      title: l.exTrainerReport,
      subtitle: widget.trainer.name,
      footer: AppButton(
        key: const Key('trainer-report-submit'),
        label: l.exTrainerReportSubmit,
        onPressed: _canSubmit ? _submit : null,
        loading: _submitting,
        size: OnCareButtonSize.large,
        fullWidth: true,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l.exTrainerReportReasonLabel,
            style: tokens
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          // 상담 폼·루틴 완료 시트와 같은 분리형 칩이다. 사유가 셋이라 한 줄에
          // 서지 않는 폭에서는 다음 줄로 흐른다.
          Wrap(
            key: const Key('trainer-report-reasons'),
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              for (final TrainerReportReason reason
                  in TrainerReportReason.values)
                AppChoiceChip(
                  key: Key('trainer-report-reason-${reason.wire}'),
                  label: _label(l, reason),
                  selected: _reason == reason,
                  onSelected: _submitting
                      ? null
                      : (bool _) => setState(() => _reason = reason),
                ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s16),
          AppTextField(
            key: const Key('trainer-report-memo'),
            controller: _memo,
            label: l.exTrainerReportMemoLabel,
            hint: l.exTrainerReportMemoHint,
            helper: memoRequired ? l.exTrainerReportMemoRequired : null,
            minLines: 3,
            maxLines: 5,
            maxLength: kTrainerReportMemoMax,
            showCounter: true,
            enabled: !_submitting,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const AppIcon(
                AppIcons.info,
                size: OnCareSize.iconSmall,
                color: OnCareColors.textSecondary,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Text(
                  l.exTrainerReportNotice,
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 신고 시트를 여는 낮은 강조 버튼. 상세·카드의 다른 동작보다 앞서지 않게
/// 작은 빨간 글자 버튼이다 — 연결 해제처럼 위험을 알리는 자리와 같은 결이다.
class TrainerReportButton extends StatelessWidget {
  const TrainerReportButton({
    required this.trainer,
    this.compact = false,
    super.key,
  });

  final Trainer trainer;

  /// 목록 줄 안처럼 좁은 자리에서는 `신고` 한 단어만 적는다.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppButton(
      label: compact ? l.exTrainerReportShort : l.exTrainerReport,
      onPressed: () => showTrainerReportSheet(context, trainer),
      variant: AppButtonVariant.destructiveText,
      size: OnCareButtonSize.small,
      leadingIcon: compact ? null : AppIcons.warning,
    );
  }
}

/// 소속 헬스장 옆에 붙는 안내 — 소속은 트레이너가 직접 고른 것이다 (#3008).
///
/// 운영자가 소속을 확인하지 않으므로, 회원이 그 사실을 알고 판단하게 한다.
class SelfRegisteredAffiliationNote extends StatelessWidget {
  const SelfRegisteredAffiliationNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context).exTrainerSelfRegisteredAffiliation,
      style: context.oncare
          .text(OnCareTypography.caption)
          .copyWith(color: OnCareColors.textSecondary),
    );
  }
}
