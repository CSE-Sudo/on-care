import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_button.dart';
import 'package:oncare_ui/src/components/app_dialog.dart';
import 'package:oncare_ui/src/components/app_icon_button.dart';
import 'package:oncare_ui/src/components/app_inputs.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/calendar.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 날짜 하나를 고르는 공용 달력 창(#1695, #1778).
///
/// Material 기본 [showDatePicker] 는 넓은 화면(트레이너웹)에서 달력을 좌우로 나눈
/// landscape 모양으로 바꾼다. 이 창은 그 대신 [CalendarDatePicker](Material 이
/// 그리드에만 쓰는 하위 위젯)를 [AppDialog] 로 감싸 늘 세로 배치로 그린다 —
/// `2db5b04` 시점의 `portrait_date_picker` 모양이다.
///
/// 날짜 값 자체가 입력창이라 따로 전환할 필요 없이 타이핑도, 바로 아래 달력에서
/// 탭으로 고르는 것도 둘 다 항상 된다. 입력창에 타이핑하면
/// [MaterialLocalizations.parseCompactDate] 로 즉시 해석해 달력도 같이 움직이고,
/// 달력에서 고르면 입력창 글자도 같이 바뀐다. 오른쪽 위 X 와 아래 2열
/// `취소 / 확인` 을 모두 둔다.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  return showAppDialog<DateTime>(
    context: context,
    builder: (BuildContext _) => AppDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
    ),
  );
}

/// [showAppDatePicker] 가 띄우는 창. 확인하면 고른 날(시각 없음)을 돌려준다.
class AppDatePickerDialog extends StatefulWidget {
  const AppDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.helpText,
  });

  /// 창·입력창·버튼 키. 테스트가 이 창을 지목한다(옛 `portraitDatePicker*` 키).
  static const Key dialogKey = Key('portraitDatePicker');
  static const Key inputKey = Key('portraitDatePickerInput');
  static const Key cancelKey = Key('portraitDatePickerCancel');
  static const Key confirmKey = Key('portraitDatePickerConfirm');

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  /// 제목. 비우면 플랫폼 문구(`날짜 선택`)다.
  final String? helpText;

  @override
  State<AppDatePickerDialog> createState() => _AppDatePickerDialogState();
}

class _AppDatePickerDialogState extends State<AppDatePickerDialog> {
  late DateTime _selected = DateUtils.dateOnly(widget.initialDate);
  final TextEditingController _controller = TextEditingController();
  bool _textReady = false;
  String? _errorText;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 처음 한 번만 채운다 — 사용자가 지운 입력을 다시 그릴 때마다 되살리지 않는다.
    if (!_textReady) {
      _controller.text = MaterialLocalizations.of(
        context,
      ).formatCompactDate(_selected);
      _textReady = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 입력창 글자가 바뀔 때마다(키 입력마다) 유효한 날짜인지 확인해 곧장
  /// 반영한다 — 아래 달력이 입력과 같이 움직여야 한다.
  void _handleTextChanged(MaterialLocalizations l, String text) {
    if (text.isEmpty) {
      setState(() => _errorText = null);
      return;
    }
    final DateTime? parsed = l.parseCompactDate(text);
    if (parsed == null) {
      setState(() => _errorText = l.invalidDateFormatLabel);
      return;
    }
    if (parsed.isBefore(DateUtils.dateOnly(widget.firstDate)) ||
        parsed.isAfter(DateUtils.dateOnly(widget.lastDate))) {
      setState(() => _errorText = l.dateOutOfRangeLabel);
      return;
    }
    setState(() {
      _selected = parsed;
      _errorText = null;
    });
  }

  /// 달력 탭은 입력창 글자도 같이 바꾼다 — 사용자가 지금 커서를 두고 타이핑
  /// 중이 아니므로 컨트롤러 글자를 직접 덮어써도 된다.
  void _handleCalendarChanged(MaterialLocalizations l, DateTime date) {
    setState(() {
      _selected = DateUtils.dateOnly(date);
      _errorText = null;
      _controller.text = l.formatCompactDate(_selected);
    });
  }

  /// 입력이 틀린 동안에는 닫지 않는다 — 오류 문구를 보고 고치게 한다.
  void _confirm() {
    if (_errorText != null) return;
    Navigator.of(context).pop(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations l = MaterialLocalizations.of(context);
    return AppDialog(
      key: AppDatePickerDialog.dialogKey,
      title: widget.helpText ?? l.datePickerHelpText,
      footer: AppButtonPair(
        cancelKey: AppDatePickerDialog.cancelKey,
        confirmKey: AppDatePickerDialog.confirmKey,
        cancelLabel: l.cancelButtonLabel,
        onCancel: () => Navigator.of(context).pop(),
        confirmLabel: l.okButtonLabel,
        onConfirm: _confirm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 날짜 값 자체가 입력창이다 — 한쪽이 바뀌면 다른 쪽도 같이 움직인다.
          AppTextField(
            key: AppDatePickerDialog.inputKey,
            controller: _controller,
            label: l.dateInputLabel,
            hint: l.dateHelpText,
            errorText: _errorText,
            keyboardType: TextInputType.datetime,
            onChanged: (String text) => _handleTextChanged(l, text),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          CalendarDatePicker(
            // 입력으로 고른 날이 바뀌면 달력도 그 달로 새로 연다.
            key: ValueKey<DateTime>(_selected),
            initialDate: _selected,
            firstDate: widget.firstDate,
            lastDate: widget.lastDate,
            onDateChanged: (DateTime date) => _handleCalendarChanged(l, date),
          ),
        ],
      ),
    );
  }
}

/// 시작·종료 날짜를 한 번의 달력에서 고르는 기간 선택창(#1778, 트레이너웹 반복 일정).
///
/// Material 기본 [showDateRangePicker] 는 전체 화면에 달이 끝없이 이어지는 목록이라
/// 다른 창과 모양이 완전히 달랐다. 이 창은 한 번에 한 달만 보여 주고 좌우 꺾쇠로
/// 달을 넘기는 고정 격자를 그린다 — 시작·종료일 사이는 브랜드 색 알약 띠로 잇는다.
/// 시작·종료일 값 자체가 입력창이라 타이핑도 달력 탭도 둘 다 항상 된다.
///
/// [initialRange] 가 없으면 두 칸을 비우고 오늘이 든 달부터 연다.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialRange,
  String? helpText,
}) {
  return showAppDialog<DateTimeRange>(
    context: context,
    builder: (BuildContext _) => AppDateRangePickerDialog(
      firstDate: firstDate,
      lastDate: lastDate,
      initialRange: initialRange,
      helpText: helpText,
    ),
  );
}

/// [showAppDateRangePicker] 가 띄우는 창.
class AppDateRangePickerDialog extends StatefulWidget {
  const AppDateRangePickerDialog({
    super.key,
    required this.firstDate,
    required this.lastDate,
    this.initialRange,
    this.helpText,
  });

  /// 창·입력창·버튼 키(옛 `portraitDateRangePicker*` 키).
  static const Key dialogKey = Key('portraitDateRangePicker');
  static const Key startInputKey = Key('portraitDateRangePickerStartInput');
  static const Key endInputKey = Key('portraitDateRangePickerEndInput');
  static const Key cancelKey = Key('portraitDateRangePickerCancel');
  static const Key confirmKey = Key('portraitDateRangePickerConfirm');

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialRange;

  /// 제목. 비우면 플랫폼 문구(`기간 선택`)다.
  final String? helpText;

  @override
  State<AppDateRangePickerDialog> createState() =>
      _AppDateRangePickerDialogState();
}

class _AppDateRangePickerDialogState extends State<AppDateRangePickerDialog> {
  late DateTime? _start = widget.initialRange == null
      ? null
      : DateUtils.dateOnly(widget.initialRange!.start);
  late DateTime? _end = widget.initialRange == null
      ? null
      : DateUtils.dateOnly(widget.initialRange!.end);
  late DateTime _displayedMonth = _monthOf(_start ?? _clampedToday());
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  bool _textReady = false;
  String? _startErrorText;
  String? _endErrorText;

  DateTime get _first => DateUtils.dateOnly(widget.firstDate);
  DateTime get _last => DateUtils.dateOnly(widget.lastDate);

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

  DateTime _clampedToday() {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    if (today.isBefore(_first)) return _first;
    if (today.isAfter(_last)) return _last;
    return today;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_textReady) {
      final MaterialLocalizations l = MaterialLocalizations.of(context);
      if (_start != null) _startController.text = l.formatCompactDate(_start!);
      if (_end != null) _endController.text = l.formatCompactDate(_end!);
      _textReady = true;
    }
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  /// 시작일 입력창에 타이핑할 때마다 곧장 해석해 달력에 반영한다. 새 시작일이
  /// 종료일보다 뒤라면 기간이 깨지므로 종료일은 다시 고르게 비운다.
  void _handleStartTextChanged(MaterialLocalizations l, String text) {
    if (text.isEmpty) {
      setState(() => _startErrorText = null);
      return;
    }
    final DateTime? parsed = l.parseCompactDate(text);
    if (parsed == null) {
      setState(() => _startErrorText = l.invalidDateFormatLabel);
      return;
    }
    if (parsed.isBefore(_first) || parsed.isAfter(_last)) {
      setState(() => _startErrorText = l.dateOutOfRangeLabel);
      return;
    }
    setState(() {
      _start = parsed;
      _startErrorText = null;
      _displayedMonth = _monthOf(parsed);
      if (_end != null && _end!.isBefore(parsed)) {
        _end = null;
        _endController.clear();
      }
    });
  }

  /// 종료일 입력창도 마찬가지다 — 시작일보다 앞선 날짜는 범위 밖으로 본다.
  void _handleEndTextChanged(MaterialLocalizations l, String text) {
    if (text.isEmpty) {
      setState(() => _endErrorText = null);
      return;
    }
    final DateTime? parsed = l.parseCompactDate(text);
    if (parsed == null) {
      setState(() => _endErrorText = l.invalidDateFormatLabel);
      return;
    }
    final DateTime lower = _start ?? _first;
    if (parsed.isBefore(lower) || parsed.isAfter(_last)) {
      setState(() => _endErrorText = l.dateOutOfRangeLabel);
      return;
    }
    setState(() {
      _end = parsed;
      _endErrorText = null;
      _displayedMonth = _monthOf(parsed);
    });
  }

  /// 달력 탭 — 기간이 비었거나 이미 닫혀 있으면 새 시작일, 시작일보다 앞이면
  /// 시작일을 옮기고, 아니면 종료일이다. 입력창 글자도 같이 바꾼다.
  void _handleCalendarTap(MaterialLocalizations l, DateTime day) {
    setState(() {
      if (_start == null || _end != null) {
        _start = day;
        _end = null;
        _startController.text = l.formatCompactDate(day);
        _endController.clear();
      } else if (day.isBefore(_start!)) {
        _start = day;
        _startController.text = l.formatCompactDate(day);
      } else {
        _end = day;
        _endController.text = l.formatCompactDate(day);
      }
      _startErrorText = null;
      _endErrorText = null;
    });
  }

  /// 시작·종료가 모두 있고 입력 오류가 없을 때만 닫는다.
  void _confirm() {
    if (_start == null || _end == null) return;
    if (_startErrorText != null || _endErrorText != null) return;
    Navigator.of(context).pop(DateTimeRange(start: _start!, end: _end!));
  }

  bool get _canGoPrevious => DateTime(
    _displayedMonth.year,
    _displayedMonth.month - 1,
  ).isAfter(DateTime(_first.year, _first.month - 1));

  bool get _canGoNext => DateTime(
    _displayedMonth.year,
    _displayedMonth.month + 1,
  ).isBefore(DateTime(_last.year, _last.month + 1));

  void _goToMonth(int delta) {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + delta,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations l = MaterialLocalizations.of(context);
    return AppDialog(
      key: AppDateRangePickerDialog.dialogKey,
      title: widget.helpText ?? l.dateRangePickerHelpText,
      footer: AppButtonPair(
        cancelKey: AppDateRangePickerDialog.cancelKey,
        confirmKey: AppDateRangePickerDialog.confirmKey,
        cancelLabel: l.cancelButtonLabel,
        onCancel: () => Navigator.of(context).pop(),
        confirmLabel: l.okButtonLabel,
        onConfirm: _confirm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 시작·종료일 값 자체가 입력창이다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  key: AppDateRangePickerDialog.startInputKey,
                  controller: _startController,
                  label: l.dateRangeStartLabel,
                  hint: l.dateHelpText,
                  errorText: _startErrorText,
                  keyboardType: TextInputType.datetime,
                  onChanged: (String text) => _handleStartTextChanged(l, text),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: AppTextField(
                  key: AppDateRangePickerDialog.endInputKey,
                  controller: _endController,
                  label: l.dateRangeEndLabel,
                  hint: l.dateHelpText,
                  errorText: _endErrorText,
                  keyboardType: TextInputType.datetime,
                  onChanged: (String text) => _handleEndTextChanged(l, text),
                ),
              ),
            ],
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Row(
            children: <Widget>[
              AppIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: l.previousMonthTooltip,
                onPressed: _canGoPrevious ? () => _goToMonth(-1) : null,
              ),
              Expanded(
                child: Text(
                  l.formatMonthYear(_displayedMonth),
                  textAlign: TextAlign.center,
                  style: context.oncare
                      .text(OnCareCalendar.rangeMonthLabel)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              AppIconButton(
                icon: Icons.chevron_right_rounded,
                tooltip: l.nextMonthTooltip,
                onPressed: _canGoNext ? () => _goToMonth(1) : null,
              ),
            ],
          ),
          _RangeMonthGrid(
            month: _displayedMonth,
            firstDate: _first,
            lastDate: _last,
            start: _start,
            end: _end,
            onDayTap: (DateTime day) => _handleCalendarTap(l, day),
          ),
        ],
      ),
    );
  }
}

/// 한 달을 고정 격자로 그린다 — [start]~[end] 는 이어진 브랜드 색 띠로,
/// 시작·종료일 자체는 띠의 둥근 끝으로 강조한다. [firstDate]~[lastDate] 밖의
/// 날짜는 흐리게 두고 탭을 막는다.
class _RangeMonthGrid extends StatelessWidget {
  const _RangeMonthGrid({
    required this.month,
    required this.firstDate,
    required this.lastDate,
    required this.start,
    required this.end,
    required this.onDayTap,
  });

  final DateTime month;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime? start;
  final DateTime? end;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations l = MaterialLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final int daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final int firstOffset = DateUtils.firstDayOffset(
      month.year,
      month.month,
      l,
    );
    final int weeks = ((firstOffset + daysInMonth) / 7).ceil();

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (int i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    l.narrowWeekdays[(l.firstDayOfWeekIndex + i) % 7],
                    style: tokens
                        .text(OnCareCalendar.rangeWeekday)
                        .copyWith(color: OnCareColors.textSecondary),
                  ),
                ),
              ),
          ],
        ),
        for (int week = 0; week < weeks; week++)
          Row(
            children: <Widget>[
              for (int col = 0; col < 7; col++)
                Expanded(
                  child: AspectRatio(
                    aspectRatio: OnCareCalendar.rangeCellAspectRatio,
                    child: _dayCell(
                      tokens,
                      week * 7 + col - firstOffset + 1,
                      daysInMonth,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(OnCareTokens tokens, int dayOfMonth, int daysInMonth) {
    if (dayOfMonth < 1 || dayOfMonth > daysInMonth) {
      return const SizedBox.shrink();
    }
    final DateTime day = DateTime(month.year, month.month, dayOfMonth);
    final bool disabled = day.isBefore(firstDate) || day.isAfter(lastDate);
    final bool isStart = start != null && DateUtils.isSameDay(day, start);
    final bool isEnd = end != null && DateUtils.isSameDay(day, end);
    // 시작·종료일도 띠에 넣어(양 끝 포함) 하나로 이어진 알약처럼 보이게 한다.
    // 시작일의 왼쪽·종료일의 오른쪽 모서리만 둥글리고, 주가 바뀌며 줄이 꺾이는
    // 자리를 포함한 나머지는 각지게 둬 옆 칸과 색이 그대로 이어진다.
    final bool inBand =
        start != null &&
        end != null &&
        !day.isBefore(start!) &&
        !day.isAfter(end!);
    final BorderRadius bandRadius = BorderRadius.horizontal(
      left: isStart ? OnCareRadius.pill : Radius.zero,
      right: isEnd ? OnCareRadius.pill : Radius.zero,
    );
    final TextStyle base = OnCareTypography.numeric(
      tokens.text(OnCareCalendar.rangeDay),
    );
    final TextStyle cap = base.copyWith(fontWeight: FontWeight.w700);

    return Semantics(
      button: true,
      enabled: !disabled,
      selected: isStart || isEnd,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : () => onDayTap(day),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // 띠와 양 끝을 같은 진한 색으로 둬 한 덩이로 읽힌다.
            color: inBand ? tokens.brand.primary : Colors.transparent,
            borderRadius: bandRadius,
          ),
          child: Center(
            child: Text(
              '$dayOfMonth',
              style: (isStart || isEnd ? cap : base).copyWith(
                color: inBand
                    ? OnCareColors.textOnFill
                    : disabled
                    ? OnCareColors.textDisabled
                    : OnCareColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 시각 선택. 시계 다이얼 모양의 통합은 복합 위젯 이슈(#1697)에서 한다.
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    helpText: helpText,
  );
}

/// 시작·종료 시각을 차례로 고른다. 종료가 시작보다 이르면 `null` 이다.
Future<(TimeOfDay, TimeOfDay)?> showAppTimeRangePicker({
  required BuildContext context,
  required TimeOfDay initialStart,
  required TimeOfDay initialEnd,
  String? startHelpText,
  String? endHelpText,
}) async {
  final TimeOfDay? start = await showAppTimePicker(
    context: context,
    initialTime: initialStart,
    helpText: startHelpText,
  );
  if (start == null || !context.mounted) return null;
  final TimeOfDay? end = await showAppTimePicker(
    context: context,
    initialTime: initialEnd,
    helpText: endHelpText,
  );
  if (end == null) return null;
  final int startMinutes = start.hour * 60 + start.minute;
  final int endMinutes = end.hour * 60 + end.minute;
  return endMinutes > startMinutes ? (start, end) : null;
}
