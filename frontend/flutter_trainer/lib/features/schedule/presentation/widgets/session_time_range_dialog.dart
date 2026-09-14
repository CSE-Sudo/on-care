import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/time_range_picker_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 시작·종료 시간을 한 번에 고르는 가운데 모달(#1229, #1250).
///
/// 날짜 선택([showAppDatePicker])과 같은 세로 배치다 — 위에 키보드로
/// 바로 적는 한 줄(`10:00 - 11:00`), 그 아래 달력 대신 시작·종료 시계
/// 다이얼을 위아래로 둔다. 시계는 시(時)를 훑어 고르는 자리고, 분은 그
/// 위 텍스트 필드에 직접 적는다 — 두 값(시작·종료) 다이얼을 한 화면에
/// 같이 두면서 각각 시·분을 다 고르게 하면 자리도 손동작도 두 배가 된다.
Future<(TimeOfDay, TimeOfDay)?> showSessionTimeRangeDialog({
  required BuildContext context,
  required TimeOfDay initialStart,
  required TimeOfDay initialEnd,
}) {
  return showAppDialog<(TimeOfDay, TimeOfDay)>(
    context: context,
    builder: (_) => _SessionTimeRangeDialog(
      initialStart: initialStart,
      initialEnd: initialEnd,
    ),
  );
}

class _SessionTimeRangeDialog extends StatefulWidget {
  const _SessionTimeRangeDialog({
    required this.initialStart,
    required this.initialEnd,
  });

  final TimeOfDay initialStart;
  final TimeOfDay initialEnd;

  @override
  State<_SessionTimeRangeDialog> createState() =>
      _SessionTimeRangeDialogState();
}

class _SessionTimeRangeDialogState extends State<_SessionTimeRangeDialog> {
  late TimeOfDay _start = widget.initialStart;
  late TimeOfDay _end = widget.initialEnd;
  late final TextEditingController _startText = TextEditingController(
    text: _format(_start),
  );
  late final TextEditingController _endText = TextEditingController(
    text: _format(_end),
  );
  String? _error;

  static String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  /// `HH:mm` 을 24시간 기준으로 읽는다. 형식이 아니면 null.
  static TimeOfDay? _parse(String raw) {
    final match = RegExp(r'^([0-9]{1,2}):([0-9]{2})$').firstMatch(raw.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  void dispose() {
    _startText.dispose();
    _endText.dispose();
    super.dispose();
  }

  void _setStart(TimeOfDay t) {
    setState(() {
      _start = t;
      _startText.text = _format(t);
      _error = null;
    });
  }

  void _setEnd(TimeOfDay t) {
    setState(() {
      _end = t;
      _endText.text = _format(t);
      _error = null;
    });
  }

  void _onStartHourTap(int hour12) => _setStart(_withHour12(_start, hour12));

  void _onEndHourTap(int hour12) => _setEnd(_withHour12(_end, hour12));

  static TimeOfDay _withHour12(TimeOfDay current, int hour12) {
    final isPM = current.period == DayPeriod.pm;
    final hour24 = (hour12 % 12) + (isPM ? 12 : 0);
    return TimeOfDay(hour: hour24, minute: current.minute);
  }

  void _setStartPeriod(DayPeriod period) => _setStart(
    TimeOfDay(hour: _to24(_start.hourOfPeriod, period), minute: _start.minute),
  );

  void _setEndPeriod(DayPeriod period) => _setEnd(
    TimeOfDay(hour: _to24(_end.hourOfPeriod, period), minute: _end.minute),
  );

  static int _to24(int hourOfPeriod, DayPeriod period) {
    final h12 = hourOfPeriod == 0 ? 12 : hourOfPeriod;
    return (h12 % 12) + (period == DayPeriod.pm ? 12 : 0);
  }

  void _confirm(AppLocalizations l) {
    final start = _parse(_startText.text);
    final end = _parse(_endText.text);
    if (start == null || end == null) {
      setState(() => _error = l.schedTimeRangeInvalid);
      return;
    }
    if (end.hour * 60 + end.minute <= start.hour * 60 + start.minute) {
      setState(() => _error = l.schedEndBeforeStart);
      return;
    }
    Navigator.of(context).pop((start, end));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppDialog(
      title: l.schedTimeRangeTitle,
      // AppButtonPair 와 같은 배치 — 버튼마다 키를 달아야 해서 직접 둔다.
      footer: Row(
        children: <Widget>[
          Expanded(
            child: AppButton(
              key: const ValueKey<String>('session-time-range-cancel'),
              label: l.actionCancel,
              onPressed: () => Navigator.of(context).pop(),
              variant: AppButtonVariant.secondary,
              fullWidth: true,
            ),
          ),
          const SizedBox(width: OnCareSpacing.buttonGap),
          Expanded(
            child: AppButton(
              key: const ValueKey<String>('session-time-range-confirm'),
              label: l.schedTimeRangeConfirm,
              onPressed: () => _confirm(l),
              fullWidth: true,
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 키보드로 바로 적는 한 줄 — 시작 시간 - 종료 시간.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: _TimeTextField(
                  fieldKey: const ValueKey<String>(
                    'session-time-range-start-input',
                  ),
                  label: l.schedFieldStart,
                  controller: _startText,
                  onTyped: (t) => setState(() {
                    _start = t;
                    _error = null;
                  }),
                  onSubmitted: _setStart,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: OnCareSpacing.s4,
                  vertical: OnCareSpacing.s8,
                ),
                child: Text(
                  '-',
                  style: tokens
                      .text(OnCareTypography.body)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ),
              Expanded(
                child: _TimeTextField(
                  fieldKey: const ValueKey<String>(
                    'session-time-range-end-input',
                  ),
                  label: l.schedFieldEnd,
                  controller: _endText,
                  onTyped: (t) => setState(() {
                    _end = t;
                    _error = null;
                  }),
                  onSubmitted: _setEnd,
                ),
              ),
            ],
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              _error!,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.danger),
            ),
          ],
          const SizedBox(height: OnCareSpacing.s16),
          _DialClock(
            keyPrefix: 'session-time-range-start-dial',
            label: l.schedFieldStart,
            time: _start,
            onHourTap: _onStartHourTap,
            onPeriodChanged: _setStartPeriod,
          ),
          const SizedBox(height: OnCareSpacing.s16),
          _DialClock(
            keyPrefix: 'session-time-range-end-dial',
            label: l.schedFieldEnd,
            time: _end,
            onHourTap: _onEndHourTap,
            onPeriodChanged: _setEndPeriod,
          ),
        ],
      ),
    );
  }
}

/// `HH:mm` 한 칸. 적는 도중 올바른 값이 되면 다이얼에 바로 반영하고,
/// 제출하면 두 자리 형식으로 다듬는다.
class _TimeTextField extends StatelessWidget {
  const _TimeTextField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.onTyped,
    required this.onSubmitted,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final ValueChanged<TimeOfDay> onTyped;
  final ValueChanged<TimeOfDay> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      key: fieldKey,
      controller: controller,
      label: label,
      keyboardType: TextInputType.datetime,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
        LengthLimitingTextInputFormatter(5),
      ],
      onChanged: (raw) {
        final parsed = _SessionTimeRangeDialogState._parse(raw);
        if (parsed != null) onTyped(parsed);
      },
      onSubmitted: (raw) {
        final parsed = _SessionTimeRangeDialogState._parse(raw);
        if (parsed != null) onSubmitted(parsed);
      },
    );
  }
}

class _DialClock extends StatelessWidget {
  const _DialClock({
    required this.keyPrefix,
    required this.label,
    required this.time,
    required this.onHourTap,
    required this.onPeriodChanged,
  });

  final String keyPrefix;
  final String label;
  final TimeOfDay time;
  final ValueChanged<int> onHourTap;
  final ValueChanged<DayPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final hour12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    return Column(
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.textTertiary),
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppChoiceChip(
              key: ValueKey<String>('$keyPrefix-period-am'),
              label: l.slotAm,
              selected: time.period == DayPeriod.am,
              onSelected: (_) => onPeriodChanged(DayPeriod.am),
            ),
            const SizedBox(width: OnCareSpacing.s4),
            AppChoiceChip(
              key: ValueKey<String>('$keyPrefix-period-pm'),
              label: l.slotPm,
              selected: time.period == DayPeriod.pm,
              onSelected: (_) => onPeriodChanged(DayPeriod.pm),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s8),
        ScheduleClockDial(
          mode: ScheduleClockDialMode.hour12,
          size: ScheduleClockDialSize.compact,
          keyPrefix: keyPrefix,
          selected: hour12,
          onSelected: onHourTap,
        ),
      ],
    );
  }
}
