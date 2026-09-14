import 'package:flutter/material.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 앱 전역에서 날짜 하나를 고르는 공용 달력 모달.
///
/// Material 기본 [showDatePicker] 는 트레이너 웹처럼 늘 넓은 화면에서는
/// 달력을 좌우로 나눈 landscape 모양으로 바꾼다. 이 화면은 그 대신
/// [CalendarDatePicker](Material 이 그리드에만 쓰는 하위 위젯)를 직접 감싸
/// 늘 세로 배치로 그린다 — CalendarDatePicker 자체는 orientation 에 따라
/// 모양을 바꾸지 않아 별도 세로 고정 트릭이 필요 없다. 앱의 시간
/// 선택기와 같은 우측 상단 X 와, 하단 취소·확인 버튼을 모두 둔다.
///
/// 날짜 값 자체가 입력창이라 따로 전환할 필요 없이 타이핑도, 바로 아래
/// 달력([CalendarDatePicker])에서 탭으로 고르는 것도 둘 다 항상 된다.
/// 입력창에 타이핑하면 [MaterialLocalizations.parseCompactDate] 로 즉시
/// 해석해 달력도 같이 움직이고, 달력에서 고르면 입력창 글자도 같이 바뀐다.
Future<DateTime?> showPortraitDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierColor: Colors.black54,
    builder: (BuildContext ctx) => _PortraitDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

class _PortraitDatePickerDialog extends StatefulWidget {
  const _PortraitDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_PortraitDatePickerDialog> createState() =>
      _PortraitDatePickerDialogState();
}

class _PortraitDatePickerDialogState extends State<_PortraitDatePickerDialog> {
  late DateTime _selected = widget.initialDate;
  final TextEditingController _dateController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _dateController.dispose();
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
    if (parsed.isBefore(widget.firstDate) || parsed.isAfter(widget.lastDate)) {
      setState(() => _errorText = l.dateOutOfRangeLabel);
      return;
    }
    setState(() {
      _selected = parsed;
      _errorText = null;
    });
  }

  /// 달력 탭은 입력창의 글자도 같이 바꾼다 — 타이핑 쪽(`_handleTextChanged`)과
  /// 달리 이쪽은 사용자가 지금 커서를 두고 타이핑 중이 아니므로 컨트롤러
  /// 텍스트를 직접 덮어써도 된다.
  void _handleCalendarChanged(MaterialLocalizations l, DateTime date) {
    setState(() {
      _selected = date;
      _errorText = null;
      _dateController.text = l.formatCompactDate(date);
    });
  }

  void _confirm() {
    if (_errorText != null) return;
    Navigator.of(context).pop(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations l = MaterialLocalizations.of(context);
    if (_dateController.text.isEmpty) {
      _dateController.text = l.formatCompactDate(_selected);
    }
    return Dialog(
      key: const Key('portraitDatePicker'),
      backgroundColor: OnCareColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(OnCareRadius.xl),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s16,
        vertical: OnCareSpacing.s24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        // 오류 문구가 뜨거나 화면이 낮으면 입력창+달력+버튼 전체 높이가
        // 다이얼로그보다 커질 수 있다 — 넘치는 대신 스크롤하게 한다.
        child: SingleChildScrollView(
          child: Padding(
            // 시간 선택 다이얼로그(`_TimeRangePickerDialog`)와 같은 여백을
            // 써서 두 다이얼로그의 크기 차이가 두드러지지 않게 한다.
            padding: const EdgeInsets.all(OnCareSpacing.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l.datePickerHelpText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: OnCareColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l.closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                // 날짜 값 자체가 입력창이다 — 따로 전환할 필요 없이 타이핑도,
                // 아래 달력 탭도 둘 다 바로 된다. 한쪽이 바뀌면 다른 쪽도
                // 같이 움직인다.
                TextField(
                  key: const Key('portraitDatePickerInput'),
                  controller: _dateController,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: l.dateInputLabel,
                    errorText: _errorText,
                  ),
                  onChanged: (String text) => _handleTextChanged(l, text),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                CalendarDatePicker(
                  key: ValueKey<DateTime>(_selected),
                  initialDate: _selected,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  onDateChanged: (DateTime date) =>
                      _handleCalendarChanged(l, date),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        key: const Key('portraitDatePickerCancel'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l.cancelButtonLabel),
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s8),
                    Expanded(
                      child: FilledButton(
                        key: const Key('portraitDatePickerConfirm'),
                        onPressed: _confirm,
                        child: Text(l.okButtonLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 반복 일정의 시작·종료 날짜를 한 번의 달력에서 고른다 — 위
/// [showPortraitDatePicker] 와 같은 자리에서 쓰인다.
///
/// Material 기본 [showDateRangePicker] 는 전체화면에 월 단위로 끝없이
/// 스크롤되는 목록이라 이 앱의 다른 모달과 스타일이 완전히 달랐다. 이
/// 화면은 그 대신 한 번에 한 달만 보여주고 좌우 화살표로 달을 넘기는
/// 고정 그리드([_MonthGrid])를 직접 그린다 — 시작·종료일 사이는 이어진
/// 색 띠로, 시작·종료일 자체는 원으로 표시해 기본 다이얼로그의 범위
/// 표시 느낌은 그대로 두면서 화면만 넘치지 않게 한다.
///
/// 시작·종료일 값 자체가 입력창이라 따로 전환할 필요 없이 타이핑도,
/// 바로 아래 달력에서 탭으로 고르는 것도 둘 다 항상 된다.
Future<DateTimeRange?> showPortraitDateRangePicker({
  required BuildContext context,
  required DateTimeRange initialDateRange,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    barrierColor: Colors.black54,
    builder: (BuildContext ctx) => _PortraitDateRangePickerDialog(
      initialDateRange: initialDateRange,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _PortraitDateRangePickerDialog extends StatefulWidget {
  const _PortraitDateRangePickerDialog({
    required this.initialDateRange,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTimeRange initialDateRange;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_PortraitDateRangePickerDialog> createState() =>
      _PortraitDateRangePickerDialogState();
}

class _PortraitDateRangePickerDialogState
    extends State<_PortraitDateRangePickerDialog> {
  late DateTime? _start = _dateOnly(widget.initialDateRange.start);
  late DateTime? _end = _dateOnly(widget.initialDateRange.end);
  late DateTime _displayedMonth = DateTime(_start!.year, _start!.month);
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  String? _startErrorText;
  String? _endErrorText;

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  /// 시작일 입력창에 타이핑할 때마다 곧장 해석해 달력·종료일에 반영한다.
  /// 새 시작일이 종료일보다 뒤라면 범위가 깨지므로 종료일은 다시 고르게
  /// 비운다.
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
    if (parsed.isBefore(widget.firstDate) || parsed.isAfter(widget.lastDate)) {
      setState(() => _startErrorText = l.dateOutOfRangeLabel);
      return;
    }
    setState(() {
      _start = parsed;
      _startErrorText = null;
      _displayedMonth = DateTime(parsed.year, parsed.month);
      if (_end != null && _end!.isBefore(parsed)) {
        _end = null;
        _endController.clear();
      }
    });
  }

  /// 종료일 입력창 쪽도 마찬가지다 — 시작일보다 앞선 날짜는 범위 밖으로
  /// 취급한다.
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
    final DateTime lower = _start ?? widget.firstDate;
    if (parsed.isBefore(lower) || parsed.isAfter(widget.lastDate)) {
      setState(() => _endErrorText = l.dateOutOfRangeLabel);
      return;
    }
    setState(() {
      _end = parsed;
      _endErrorText = null;
      _displayedMonth = DateTime(parsed.year, parsed.month);
    });
  }

  /// 달력 탭은 입력창 글자도 같이 바꾼다 — 타이핑 쪽과 달리 사용자가 지금
  /// 커서를 두고 타이핑 중이 아니므로 컨트롤러 텍스트를 직접 덮어써도
  /// 된다.
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

  void _confirm() {
    if (_start == null || _end == null) return;
    if (_startErrorText != null || _endErrorText != null) return;
    Navigator.of(context).pop(DateTimeRange(start: _start!, end: _end!));
  }

  bool get _canGoPrevious => DateTime(
    _displayedMonth.year,
    _displayedMonth.month - 1,
  ).isAfter(DateTime(widget.firstDate.year, widget.firstDate.month - 1));

  bool get _canGoNext => DateTime(
    _displayedMonth.year,
    _displayedMonth.month + 1,
  ).isBefore(DateTime(widget.lastDate.year, widget.lastDate.month + 1));

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
    if (_startController.text.isEmpty) {
      _startController.text = l.formatCompactDate(_start!);
    }
    if (_endController.text.isEmpty && _end != null) {
      _endController.text = l.formatCompactDate(_end!);
    }
    return Dialog(
      key: const Key('portraitDateRangePicker'),
      backgroundColor: OnCareColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(OnCareRadius.xl),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s16,
        vertical: OnCareSpacing.s24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        // 오류 문구가 뜨거나 화면이 낮으면 입력창+달력+버튼 전체 높이가
        // 다이얼로그보다 커질 수 있다 — 넘치는 대신 스크롤하게 한다.
        child: SingleChildScrollView(
          child: Padding(
            // 시간 선택 다이얼로그(`_TimeRangePickerDialog`)와 같은 여백을
            // 써서 두 다이얼로그의 크기 차이가 두드러지지 않게 한다.
            padding: const EdgeInsets.all(OnCareSpacing.s24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l.dateRangePickerHelpText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: OnCareColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l.closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                // 시작·종료일 값 자체가 입력창이다 — 따로 전환할 필요 없이
                // 타이핑도, 바로 아래 달력 탭도 둘 다 항상 된다.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        key: const Key('portraitDateRangePickerStartInput'),
                        controller: _startController,
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          labelText: l.dateRangeStartLabel,
                          errorText: _startErrorText,
                        ),
                        onChanged: (String text) =>
                            _handleStartTextChanged(l, text),
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s8),
                    Expanded(
                      child: TextField(
                        key: const Key('portraitDateRangePickerEndInput'),
                        controller: _endController,
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          labelText: l.dateRangeEndLabel,
                          errorText: _endErrorText,
                        ),
                        onChanged: (String text) =>
                            _handleEndTextChanged(l, text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: OnCareSpacing.s8),
                Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: '이전 달',
                      onPressed: _canGoPrevious ? () => _goToMonth(-1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${_displayedMonth.year}년 ${_displayedMonth.month}월',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: '다음 달',
                      onPressed: _canGoNext ? () => _goToMonth(1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                _MonthGrid(
                  month: _displayedMonth,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  start: _start,
                  end: _end,
                  onDayTap: (DateTime day) => _handleCalendarTap(l, day),
                ),
                const SizedBox(height: OnCareSpacing.s8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        key: const Key('portraitDateRangePickerCancel'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l.cancelButtonLabel),
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s8),
                    Expanded(
                      child: FilledButton(
                        key: const Key('portraitDateRangePickerConfirm'),
                        onPressed: _confirm,
                        child: Text(l.okButtonLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 한 달을 고정 그리드로 그린다 — [start]·[end] 사이는 이어진 띠로,
/// 시작·종료일 자체는 원으로 강조한다. [firstDate]~[lastDate] 밖의
/// 날짜는 흐리게 표시하고 탭을 막는다.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
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
    final int daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final int firstOffset = DateUtils.firstDayOffset(
      month.year,
      month.month,
      l,
    );
    final int cellCount = ((firstOffset + daysInMonth) / 7).ceil() * 7;

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final String weekday in l.narrowWeekdays)
              Expanded(
                child: Center(
                  child: Text(
                    weekday,
                    style: const TextStyle(
                      fontSize: 12,
                      color: OnCareColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.2,
          children: <Widget>[
            for (int i = 0; i < cellCount; i++)
              _dayCell(i - firstOffset + 1, daysInMonth),
          ],
        ),
      ],
    );
  }

  Widget _dayCell(int dayOfMonth, int daysInMonth) {
    if (dayOfMonth < 1 || dayOfMonth > daysInMonth) return const SizedBox();
    final DateTime day = DateTime(month.year, month.month, dayOfMonth);
    final bool disabled = day.isBefore(firstDate) || day.isAfter(lastDate);
    final bool isStart = start != null && _isSameDay(day, start!);
    final bool isEnd = end != null && _isSameDay(day, end!);
    final bool isCap = isStart || isEnd;
    // 시작·종료일 자체도 띠에 포함해(양 끝 포함) 원과 이어진 것처럼 보이게
    // 한다. 알약(스타디움) 모양을 내려고 시작일의 바깥쪽(왼쪽)·종료일의
    // 바깥쪽(오른쪽) 모서리만 크게 둥글리고 — 주가 바뀌며 줄이 꺾이는
    // 자리를 포함한 나머지는 각지게 둬 옆 칸과 색이 그대로 이어지게 한다.
    final bool inBand =
        start != null &&
        end != null &&
        !day.isBefore(start!) &&
        !day.isAfter(end!);
    const Radius capRadius = Radius.circular(999);
    final BorderRadius bandRadius = BorderRadius.horizontal(
      left: isStart ? capRadius : Radius.zero,
      right: isEnd ? capRadius : Radius.zero,
    );

    return GestureDetector(
      onTap: disabled ? null : () => onDayTap(day),
      child: Container(
        decoration: BoxDecoration(
          // 띠와 시작·종료일 원을 같은 진한 색으로 둬, 두 원이 띠 하나로
          // 이어진 것처럼 보이게 한다 — 옅은 배경색을 따로 쓰지 않는다.
          color: inBand ? OnCareBrand.trainer.primary : Colors.transparent,
          borderRadius: bandRadius,
        ),
        child: Center(
          child: Text(
            '$dayOfMonth',
            style: TextStyle(
              color: inBand
                  ? Colors.white
                  : disabled
                  ? OnCareColors.textSecondary
                  : OnCareColors.textPrimary,
              fontWeight: isCap ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
