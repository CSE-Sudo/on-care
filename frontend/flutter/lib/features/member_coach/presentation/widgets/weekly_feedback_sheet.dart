/// 한 주를 돌아보는 세 문항 — 회원이 담당 트레이너에게 보낸다. (#2232)
///
/// 트레이너 리포트 작업대의 `회원 주간 피드백` 칸이 읽는 값을 만드는 화면이다.
/// 수치만 보면 같은 한 주가 `게으름` 으로도 `과부하·일정 문제` 로도 읽히는데,
/// 그 둘은 다음 주 처방이 정반대다. 갈림길은 회원만 안다.
///
/// 문항이 셋뿐이고 통증·한 줄이 **선택**인 까닭 — 30초 안에 끝나지 않으면 매주
/// 돌아오지 않고, 돌아오지 않는 문항은 없는 것과 같다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/features/member_coach/presentation/weekly_feedback_labels.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 주간 피드백 시트를 연다. 보냈으면 true 로 닫힌다.
///
/// [existing] 을 주면 그 답을 채운 채로 연다 — 이미 낸 주를 다시 열었을 때
/// 빈 칸으로 시작하면, 회원은 자기가 무엇을 보냈는지 모르는 채로 덮어쓴다.
Future<bool?> openWeeklyFeedbackSheet(
  BuildContext context, {
  required DateTime weekStart,
  MemberWeeklyFeedback? existing,
}) {
  return showAppSheet<bool>(
    context: context,
    builder: (BuildContext _) =>
        WeeklyFeedbackSheet(weekStart: weekStart, existing: existing),
  );
}

/// 컨디션·강도·통증 세 문항과 한 줄.
class WeeklyFeedbackSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const WeeklyFeedbackSheet({
    required this.weekStart,
    this.existing,
    super.key,
  });

  /// 묻는 주의 월요일.
  final DateTime weekStart;

  /// 이미 낸 답. 없으면 빈 화면으로 시작한다.
  final MemberWeeklyFeedback? existing;

  @override
  ConsumerState<WeeklyFeedbackSheet> createState() =>
      _WeeklyFeedbackSheetState();
}

class _WeeklyFeedbackSheetState extends ConsumerState<WeeklyFeedbackSheet> {
  late WeekCondition? _condition = widget.existing?.condition;
  late WeekIntensity? _intensity = widget.existing?.intensity;
  late final TextEditingController _pain = TextEditingController(
    text: widget.existing?.painArea ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note ?? '',
  );
  late DateTime? _painOn = widget.existing?.painOn;
  bool _sending = false;

  /// 이미 낸 주인가 — 보내기 글자와 안내가 달라진다.
  bool get _resending => widget.existing?.submitted ?? false;

  /// 두 문항을 모두 골랐는가. 서버도 같은 규칙이라, 여기서 막지 않으면 422 로
  /// 돌아온다.
  bool get _complete => _condition != null && _intensity != null;

  @override
  void dispose() {
    _pain.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppSheet(
      key: const Key('weeklyFeedbackSheet'),
      showClose: false,
      title: l.weeklyFeedbackSheetTitle,
      subtitle: l.weeklyFeedbackSheetSubtitle(
        weekRangeLabel(l, widget.weekStart),
      ),
      // 문항이 길어 버튼이 마지막 줄을 덮는다 — 다 고른 뒤에 버튼이 나오게 한다.
      pinFooter: false,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!_complete)
            Padding(
              padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
              child: Text(
                l.weeklyFeedbackIncomplete,
                textAlign: TextAlign.center,
                style: tokens
                    .text(OnCareTypography.caption)
                    .copyWith(color: OnCareColors.textTertiary),
              ),
            ),
          AppButton(
            key: const ValueKey<String>('weekly-feedback-send'),
            label: _resending ? l.weeklyFeedbackResend : l.weeklyFeedbackSend,
            // 두 문항을 고르기 전에는 누를 수 없다 — 반쯤 낸 답을 받으면
            // 트레이너 화면이 나머지를 짐작하게 된다.
            onPressed: _complete && !_sending ? _send : null,
            loading: _sending,
            fullWidth: true,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          AppButton(
            key: const ValueKey<String>('weekly-feedback-later'),
            label: l.weeklyFeedbackLater,
            variant: AppButtonVariant.text,
            onPressed: _sending ? null : () => Navigator.of(context).pop(false),
            fullWidth: true,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _resending ? l.weeklyFeedbackAlreadySent : l.weeklyFeedbackWhy,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s20),
          _Question(label: l.weeklyFeedbackConditionQuestion),
          // 다섯 칸을 한 줄에 같은 폭으로 세운다. 줄을 넘기면 `많이 안
          // 좋았어요` 만 아랫줄로 떨어져, 가장 걱정해야 할 답이 눈에 덜 띈다.
          Row(
            children: <Widget>[
              for (final WeekCondition value
                  in WeekCondition.values) ...<Widget>[
                if (value != WeekCondition.values.first)
                  const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: WeeklyConditionTile(
                    key: ValueKey<String>(
                      'weekly-feedback-condition-${value.wire}',
                    ),
                    emoji: value.emoji,
                    label: weekConditionLabel(l, value),
                    selected: _condition == value,
                    onTap: () => setState(() => _condition = value),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: OnCareSpacing.s20),
          _Question(label: l.weeklyFeedbackIntensityQuestion),
          Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              for (final WeekIntensity value in WeekIntensity.values)
                AppChoiceChip(
                  key: ValueKey<String>(
                    'weekly-feedback-intensity-${value.wire}',
                  ),
                  label: weekIntensityLabel(l, value),
                  selected: _intensity == value,
                  onSelected: (_) => setState(() => _intensity = value),
                ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s20),
          _Question(label: l.weeklyFeedbackPainQuestion),
          AppTextField(
            key: const ValueKey<String>('weekly-feedback-pain'),
            controller: _pain,
            hint: l.weeklyFeedbackPainHint,
            maxLength: 40,
            onChanged: (String value) => setState(() {
              // 아픈 곳을 지우면 날짜도 함께 버린다 — 화면이 "(빈칸) 이
              // 아팠다" 를 그리지 않게. 서버도 같은 규칙으로 저장한다.
              if (value.trim().isEmpty) _painOn = null;
            }),
          ),
          // 날짜는 아픈 곳을 적은 다음에만 묻는다. 아프지 않은 주에 빈 날짜
          // 칸이 서 있으면 답해야 할 문항이 하나 더 있는 것처럼 보인다.
          if (_pain.text.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                key: const ValueKey<String>('weekly-feedback-pain-date'),
                label: _painOn == null
                    ? l.weeklyFeedbackPainDatePick
                    : '${l.weeklyFeedbackPainDateLabel} · '
                          '${_painOn!.month}/${_painOn!.day}',
                variant: AppButtonVariant.secondary,
                size: OnCareButtonSize.small,
                leadingIcon: AppIcons.calendar,
                onPressed: _pickPainDate,
              ),
            ),
          ],
          const SizedBox(height: OnCareSpacing.s20),
          _Question(label: l.weeklyFeedbackNoteQuestion),
          AppTextField(
            key: const ValueKey<String>('weekly-feedback-note'),
            controller: _note,
            hint: l.weeklyFeedbackNoteHint,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
          ),
        ],
      ),
    );
  }

  Future<void> _pickPainDate() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime last = widget.weekStart.add(const Duration(days: 6));
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: _painOn ?? widget.weekStart,
      // 그 주 안의 날만 고른다 — 이 답이 가리키는 것은 한 주다.
      firstDate: widget.weekStart,
      lastDate: last,
      helpText: l.weeklyFeedbackPainDateLabel,
      showClose: false,
    );
    if (picked == null || !mounted) return;
    setState(() => _painOn = picked);
  }

  Future<void> _send() async {
    final WeekCondition? condition = _condition;
    final WeekIntensity? intensity = _intensity;
    if (condition == null || intensity == null) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    final NavigatorState navigator = Navigator.of(context);
    setState(() => _sending = true);
    try {
      await ref
          .read(weeklyFeedbackSenderProvider)
          .send(
            weekStart: widget.weekStart,
            condition: condition,
            intensity: intensity,
            painArea: _pain.text,
            painOn: _painOn,
            note: _note.text,
          );
      toast.show(l.weeklyFeedbackSent, type: AppToastType.success);
      navigator.pop(true);
    } on Object {
      // 못 보냈으면 시트를 닫지 않는다 — 닫고 나면 회원이 적은 말이 사라진다.
      if (!mounted) return;
      setState(() => _sending = false);
      toast.show(l.weeklyFeedbackSendFailed, type: AppToastType.error);
    }
  }
}

/// 문항 한 줄.
class _Question extends StatelessWidget {
  const _Question({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Padding(
      padding: const EdgeInsets.only(bottom: OnCareSpacing.s8),
      child: Text(
        label,
        style: tokens
            .text(OnCareTypography.strong(OnCareTypography.body))
            .copyWith(color: OnCareColors.textPrimary),
      ),
    );
  }
}

/// 컨디션 한 칸 — 얼굴 위, 글자 아래. (#2232)
class WeeklyConditionTile extends StatelessWidget {
  const WeeklyConditionTile({
    super.key,
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final Color brand = tokens.brand.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? OnCareColors.onWhite(brand, OnCareAlpha.subtle)
            : OnCareColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: OnCareRadius.smAll,
          side: BorderSide(
            color: selected ? brand : OnCareColors.lineStrong,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: OnCareRadius.smAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: OnCareSpacing.s12,
              horizontal: OnCareSpacing.s4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(emoji, style: OnCareTypography.display),
                const SizedBox(height: OnCareSpacing.s4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: tokens
                      .text(
                        selected
                            ? OnCareTypography.strong(OnCareTypography.caption)
                            : OnCareTypography.caption,
                      )
                      .copyWith(
                        color: selected ? brand : OnCareColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
