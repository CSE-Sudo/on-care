import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// [CancelSessionDialog] 가 돌려주는 선택. (#2175)
///
/// [noShow] 면 취소가 아니라 노쇼로 남긴다 — 노쇼에는 주체도 사유도 없다
/// (서버 `no-show` 가 받지 않는다). 그때 [source]·[reason] 은 비어 있다.
@immutable
class CancelSessionChoice {
  const CancelSessionChoice.cancel({required this.source, this.reason = ''})
    : noShow = false;

  const CancelSessionChoice.noShow() : noShow = true, source = '', reason = '';

  final bool noShow;
  final String source;
  final String reason;
}

/// 취소 확인 — 주체를 고르고 (선택) 사유를 남긴다. (#871)
///
/// 주체에 기본값을 두지 않는다. 무엇이든 기본으로 저장되면 그 값이 사실인지 알
/// 수 없고, 나중에 "고객 취소가 몇 건이었나" 를 읽을 때 그대로 거짓이 된다.
///
/// `노쇼` 도 이 창에서 고른다(#2175). 둘 다 "예정대로 진행되지 않은 PT" 를
/// 남기는 일이라, 카드에 버튼을 따로 세우지 않고 선택지 하나로 합쳤다.
class CancelSessionDialog extends StatefulWidget {
  const CancelSessionDialog({
    super.key,
    required this.session,
    this.allowNoShow = false,
  });

  final ScheduleSession session;

  /// `노쇼` 선택지를 세우는가. 오늘·지난 PT 에서만 — 오지 않았다는 사실은 그
  /// 시간이 와야 알고, 서버도 미래 PT 의 노쇼를 거절한다(400).
  final bool allowNoShow;

  @override
  State<CancelSessionDialog> createState() => _CancelSessionDialogState();
}

class _CancelSessionDialogState extends State<CancelSessionDialog> {
  final TextEditingController _reason = TextEditingController();

  /// 고른 취소 주체, 또는 [_noShowChoice]. 고르기 전에는 null.
  String? _source;

  /// 선택지 줄에서 `노쇼` 를 가리키는 값. 취소 주체 계약값과 겹치지 않는
  /// 상태 계약값을 그대로 쓴다.
  static const String _noShowChoice = ScheduleStatus.noShow;

  bool get _isNoShow => _source == _noShowChoice;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final s = widget.session;
    return AppDialog(
      // 노쇼를 고르면 무엇이 남는지도 그에 맞게 말한다 — `취소로 기록됩니다`
      // 를 그대로 두면 누른 결과와 문장이 어긋난다.
      title: _isNoShow ? l.schedNoShowTitle : l.schedCancelTitle,
      showClose: false,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: () => Navigator.of(context).pop(),
        confirmKey: const ValueKey<String>('session-cancel-confirm'),
        confirmLabel: _isNoShow ? l.schedNoShow : l.schedCancel,
        destructive: true,
        // 주체를 고르기 전에는 저장할 수 없다 — 기본값으로 채우면 그 값이
        // 사실인지 알 수 없다.
        onConfirm: _source == null
            ? null
            : () => Navigator.of(context).pop(
                _isNoShow
                    ? const CancelSessionChoice.noShow()
                    : CancelSessionChoice.cancel(
                        source: _source!,
                        reason: _reason.text.trim(),
                      ),
              ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _isNoShow
                ? l.schedNoShowConfirm(s.time, s.clientName)
                : l.schedCancelConfirm(s.time, s.clientName),
          ),
          const SizedBox(height: OnCareSpacing.s16),
          Text(
            l.schedCancelSource,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              for (final source in CancellationSource.all)
                AppChoiceChip(
                  key: ValueKey<String>('cancel-source-$source'),
                  label: cancellationSourceLabel(l, source),
                  selected: _source == source,
                  onSelected: (_) => setState(() => _source = source),
                ),
              if (widget.allowNoShow)
                AppChoiceChip(
                  key: const ValueKey<String>('cancel-source-no-show'),
                  label: l.scheduleStatusNoShow,
                  selected: _isNoShow,
                  onSelected: (_) => setState(() => _source = _noShowChoice),
                ),
            ],
          ),
          // 노쇼에는 사유 칸을 세우지 않는다 — 서버가 받지 않아, 적어도
          // 어디에도 남지 않는다.
          if (!_isNoShow) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s16),
            AppTextField(
              key: const ValueKey<String>('cancel-reason-input'),
              controller: _reason,
              maxLength: 200,
              hint: l.schedCancelReasonHint,
            ),
          ],
        ],
      ),
    );
  }
}
