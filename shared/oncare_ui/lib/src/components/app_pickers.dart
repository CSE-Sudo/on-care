import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/gestures.dart' show kMinFlingVelocity;
import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_button.dart';
import 'package:oncare_ui/src/components/app_dialog.dart';
import 'package:oncare_ui/src/components/app_icon.dart';
import 'package:oncare_ui/src/components/app_icon_button.dart';
import 'package:oncare_ui/src/components/app_inputs.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/calendar.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/sizes.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 날짜 하나를 고르는 공용 달력 창(#1695, #1778).
///
/// Material 기본 [showDatePicker] 는 넓은 화면(트레이너웹)에서 달력을 좌우로 나눈
/// landscape 모양으로 바꾼다. 이 창은 그 대신 세로 달력([AppCalendarDatePicker])을
/// [AppDialog] 로 감싸 늘 세로 배치로 그린다 — `2db5b04` 시점의
/// `portrait_date_picker` 모양이다. 달력 머리를 누르면 열두 달 격자로 바뀐다.
///
/// 날짜 값 자체가 입력창이라 따로 전환할 필요 없이 타이핑도, 바로 아래 달력에서
/// 탭으로 고르는 것도 둘 다 항상 된다. 입력창에 타이핑하면
/// [MaterialLocalizations.parseCompactDate] 로 즉시 해석해 달력도 같이 움직이고,
/// 달력에서 고르면 입력창 글자도 같이 바뀐다. 오른쪽 위 X 와 아래 2열
/// `취소 / 확인` 을 모두 둔다 — [showClose] 를 끄면 X 없이 `취소` 로만 닫는다.
/// 회원 앱은 부분 창에 X 를 두지 않아 꺼서 쓴다(#2170). 달 이동 꺾쇠·달 보기
/// 삼각형은 앱의 아이콘 묶음(#1803)으로 그린다.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
  bool showClose = true,
}) {
  return showAppDialog<DateTime>(
    context: context,
    builder: (BuildContext _) => AppDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
      showClose: showClose,
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
    this.showClose = true,
  });

  /// 창·입력창·버튼 키. 테스트가 이 창을 지목한다(옛 `portraitDatePicker*` 키).
  static const Key dialogKey = Key('portraitDatePicker');
  static const Key inputKey = Key('portraitDatePickerInput');
  static const Key cancelKey = Key('portraitDatePickerCancel');
  static const Key confirmKey = Key('portraitDatePickerConfirm');

  /// 달력([AppCalendarDatePicker]) 키. 앱 테스트가 oncare_ui 를 들이지 않고도
  /// 달력 안의 날짜를 지목한다.
  static const Key calendarKey = Key('portraitDatePickerCalendar');

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  /// 제목. 비우면 플랫폼 문구(`날짜 선택`)다.
  final String? helpText;

  /// 오른쪽 위 닫기 X 를 둘지. 끄면 하단 `취소` 로만 닫는다.
  final bool showClose;

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
      showClose: widget.showClose,
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
          // 입력으로 고른 날이 바뀌면 달력이 스스로 그 달의 날짜 보기로 옮긴다.
          AppCalendarDatePicker(
            key: AppDatePickerDialog.calendarKey,
            selectedDate: _selected,
            firstDate: widget.firstDate,
            lastDate: widget.lastDate,
            onDateChanged: (DateTime date) => _handleCalendarChanged(l, date),
          ),
        ],
      ),
    );
  }
}

/// 날짜 선택창의 세로 달력(#1778) — 머리 + 날짜 격자, 머리를 누르면 열두 달 격자.
///
/// Material [CalendarDatePicker] 는 머리 `2026년 9월 ▾` 를 누르면 연도 목록만 열고,
/// 그 머리를 바꿀 방법도, 고른 날을 건드리지 않고 보이는 달만 옮길 방법도 없다
/// (보이는 달이 `initialDate` 에서 정해진다). 그래서 Material 달력의 모양(머리
/// 52·줄 48, 가로 화면은 42·오늘 테두리·선택 채움)은 그대로 옮기고, 보이는 달과 고른
/// 날을 따로 쥐는 달력을 직접 그린다.
///
/// - 날짜 보기: 머리 왼쪽 `2026년 9월 ▾`(누르면 달 보기), 오른쪽 이전/다음 달
///   꺾쇠. 좌우로 밀어도 달이 넘어간다.
/// - 달 보기: `‹ 2026년 ›`(꺾쇠로 해를 넘기고, 가운데를 누르면 날짜 보기로) 아래
///   3열 × 4줄 달 격자. 보던 달은 브랜드 채움 알약, [firstDate]~[lastDate] 와
///   하루도 겹치지 않는 달은 흐리고 누를 수 없다(#1765 미래 막기). 달을 누르면
///   그 달의 날짜 보기로 돌아간다 — 고른 날은 날을 누를 때까지 그대로다.
/// - [selectedDate] 가 바깥에서 바뀌면(입력창 타이핑) 그 달의 날짜 보기로 옮긴다.
class AppCalendarDatePicker extends StatefulWidget {
  const AppCalendarDatePicker({
    super.key,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
    this.currentDate,
  });

  /// 머리 라벨(날짜 보기 `2026년 9월 ▾`, 달 보기 `2026년 ▴`) 키.
  static const Key headerKey = Key('appCalendarDatePickerHeader');

  /// 고른 날. 달력은 이 날을 채운 원으로 그린다.
  final DateTime selectedDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;

  /// 테두리로 표시할 오늘. 비우면 기기 시각의 오늘이다.
  final DateTime? currentDate;

  @override
  State<AppCalendarDatePicker> createState() => _AppCalendarDatePickerState();
}

class _AppCalendarDatePickerState extends State<AppCalendarDatePicker> {
  late DateTime _displayedMonth = _clampMonth(_monthOf(widget.selectedDate));
  late int _monthsYear = _displayedMonth.year;
  bool _showMonths = false;

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

  DateTime get _first => DateUtils.dateOnly(widget.firstDate);
  DateTime get _last => DateUtils.dateOnly(widget.lastDate);

  DateTime _clampMonth(DateTime month) {
    if (month.isBefore(_monthOf(_first))) return _monthOf(_first);
    if (month.isAfter(_monthOf(_last))) return _monthOf(_last);
    return month;
  }

  @override
  void didUpdateWidget(AppCalendarDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 바깥에서(입력창) 고른 날이 바뀌면 그 달의 날짜 보기로 옮긴다.
    if (!DateUtils.isSameDay(oldWidget.selectedDate, widget.selectedDate)) {
      _displayedMonth = _clampMonth(_monthOf(widget.selectedDate));
      _showMonths = false;
    }
  }

  bool get _canPreviousMonth => _displayedMonth.isAfter(_monthOf(_first));
  bool get _canNextMonth => _displayedMonth.isBefore(_monthOf(_last));

  void _moveMonth(int delta) {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + delta,
      );
    });
  }

  /// 좌우로 밀어 달을 넘긴다. 오른쪽→왼쪽 쓸기가 다음 달이다(RTL 은 반대).
  void _handleSwipe(DragEndDetails details) {
    final double velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < kMinFlingVelocity) return;
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    final bool towardNext = (velocity < 0) != rtl;
    if (towardNext && _canNextMonth) _moveMonth(1);
    if (!towardNext && _canPreviousMonth) _moveMonth(-1);
  }

  void _openMonths() {
    setState(() {
      _monthsYear = _displayedMonth.year;
      _showMonths = true;
    });
  }

  void _closeMonths() => setState(() => _showMonths = false);

  void _pickMonth(int month) {
    setState(() {
      _displayedMonth = DateTime(_monthsYear, month);
      _showMonths = false;
    });
  }

  /// [year]년 [month]월이 고를 수 있는 기간과 하루도 겹치지 않는지.
  bool _monthDisabled(int year, int month) =>
      DateTime(year, month + 1, 0).isBefore(_first) ||
      DateTime(year, month).isAfter(_last);

  /// Material 달력과 같은 규칙 — 세로 화면은 M3 크기(줄 48·옆 12·날짜 둘레 4),
  /// 가로 화면(데스크톱 트레이너웹)은 M2 크기(줄 42·옆 8·둘레 없음)다.
  static bool _portrait(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.portrait;

  static double _rowHeight(BuildContext context) => _portrait(context)
      ? OnCareCalendar.pickerRowHeightPortrait
      : OnCareCalendar.pickerRowHeightLandscape;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height:
          OnCareCalendar.pickerHeaderHeight +
          _rowHeight(context) * (OnCareCalendar.pickerMaxWeeks + 1),
      child: _showMonths ? _buildMonths(context) : _buildDays(context),
    );
  }

  Widget _buildDays(BuildContext context) {
    final MaterialLocalizations l = MaterialLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final bool portrait = _portrait(context);
    final double rowHeight = _rowHeight(context);
    final DateTime today = DateUtils.dateOnly(
      widget.currentDate ?? DateTime.now(),
    );
    final TextStyle dayStyle = tokens.text(OnCareTypography.bodyLarge);
    final int year = _displayedMonth.year;
    final int month = _displayedMonth.month;
    final int daysInMonth = DateUtils.getDaysInMonth(year, month);
    final int offset = DateUtils.firstDayOffset(year, month, l);
    final int weeks = ((offset + daysInMonth) / DateTime.daysPerWeek).ceil();

    Widget dayCell(int day) {
      if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
      final DateTime date = DateTime(year, month, day);
      final bool disabled = date.isBefore(_first) || date.isAfter(_last);
      final bool selected = DateUtils.isSameDay(date, widget.selectedDate);
      final bool isToday = DateUtils.isSameDay(date, today);
      final Color foreground = selected
          ? OnCareColors.textOnFill
          : disabled
          ? OnCareColors.textDisabled
          : isToday
          ? tokens.brand.primary
          : OnCareColors.textPrimary;
      Widget cell = Padding(
        padding: portrait
            ? const EdgeInsets.all(OnCareSpacing.s4)
            : EdgeInsets.zero,
        child: Ink(
          decoration: ShapeDecoration(
            color: selected ? tokens.brand.primary : null,
            shape: CircleBorder(
              side: isToday
                  ? BorderSide(color: tokens.brand.primary)
                  : BorderSide.none,
            ),
          ),
          child: Center(
            child: Text(
              l.formatDecimal(day),
              style: OnCareTypography.numeric(
                dayStyle,
              ).copyWith(color: foreground),
            ),
          ),
        ),
      );
      cell = Semantics(
        // 날짜 숫자를 먼저 읽게 한다 — Material 달력과 같은 규칙이다.
        label:
            '${l.formatDecimal(day)}, ${l.formatFullDate(date)}'
            '${isToday ? ', ${l.currentDateLabel}' : ''}',
        button: true,
        selected: selected,
        enabled: !disabled,
        excludeSemantics: true,
        child: cell,
      );
      if (disabled) return cell;
      return InkResponse(
        onTap: () => widget.onDateChanged(date),
        customBorder: const CircleBorder(),
        containedInkWell: true,
        child: cell,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: OnCareSpacing.s16,
            end: OnCareSpacing.s4,
          ),
          child: SizedBox(
            height: OnCareCalendar.pickerHeaderHeight,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _PickerHeaderLabel(
                      key: AppCalendarDatePicker.headerKey,
                      label: l.formatMonthYear(_displayedMonth),
                      icon: AppIcon.setOf(context).calendarExpand,
                      onTap: _openMonths,
                    ),
                  ),
                ),
                AppIconButton(
                  icon: AppIcon.setOf(context).previous,
                  tooltip: l.previousMonthTooltip,
                  color: OnCareColors.textSecondary,
                  onPressed: _canPreviousMonth ? () => _moveMonth(-1) : null,
                ),
                AppIconButton(
                  icon: AppIcon.setOf(context).next,
                  tooltip: l.nextMonthTooltip,
                  color: OnCareColors.textSecondary,
                  onPressed: _canNextMonth ? () => _moveMonth(1) : null,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: _handleSwipe,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: portrait ? OnCareSpacing.s12 : OnCareSpacing.s8,
              ),
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: <Widget>[
                        for (int i = 0; i < DateTime.daysPerWeek; i++)
                          Expanded(
                            child: ExcludeSemantics(
                              child: Center(
                                child: Text(
                                  l.narrowWeekdays[(l.firstDayOfWeekIndex + i) %
                                      DateTime.daysPerWeek],
                                  style: dayStyle.copyWith(
                                    color: OnCareColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (int week = 0; week < weeks; week++)
                    SizedBox(
                      height: rowHeight,
                      child: Row(
                        children: <Widget>[
                          for (int col = 0; col < DateTime.daysPerWeek; col++)
                            Expanded(
                              child: dayCell(
                                week * DateTime.daysPerWeek + col - offset + 1,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonths(BuildContext context) {
    final MaterialLocalizations l = MaterialLocalizations.of(context);
    final CupertinoLocalizations months = CupertinoLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle monthStyle = tokens.text(OnCareTypography.bodyLarge);
    const int rows =
        DateTime.monthsPerYear ~/ OnCareCalendar.pickerMonthColumns;

    Widget monthCell(int month) {
      final bool disabled = _monthDisabled(_monthsYear, month);
      final bool current =
          _monthsYear == _displayedMonth.year && month == _displayedMonth.month;
      final Color foreground = current
          ? OnCareColors.textOnFill
          : disabled
          ? OnCareColors.textDisabled
          : OnCareColors.textPrimary;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
        child: Center(
          child: SizedBox(
            width: double.infinity,
            height: OnCareCalendar.pickerMonthCellHeight,
            child: Semantics(
              label: l.formatMonthYear(DateTime(_monthsYear, month)),
              button: true,
              selected: current,
              enabled: !disabled,
              excludeSemantics: true,
              child: InkWell(
                borderRadius: OnCareRadius.pillAll,
                onTap: disabled ? null : () => _pickMonth(month),
                child: Ink(
                  // 날짜 원과 같은 채움 — 모서리는 알약으로 둥글린다.
                  decoration: BoxDecoration(
                    color: current ? tokens.brand.primary : null,
                    borderRadius: OnCareRadius.pillAll,
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        months.datePickerStandaloneMonth(month),
                        maxLines: 1,
                        style: monthStyle.copyWith(color: foreground),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s4),
          child: SizedBox(
            height: OnCareCalendar.pickerHeaderHeight,
            child: Row(
              children: <Widget>[
                // 해 이동 꺾쇠의 이름은 갈 해 자체다(예: `2025년`).
                AppIconButton(
                  icon: AppIcon.setOf(context).previous,
                  tooltip: l.formatYear(DateTime(_monthsYear - 1)),
                  color: OnCareColors.textSecondary,
                  onPressed: _monthsYear > _first.year
                      ? () => setState(() => _monthsYear -= 1)
                      : null,
                ),
                Expanded(
                  child: Center(
                    child: _PickerHeaderLabel(
                      key: AppCalendarDatePicker.headerKey,
                      label: l.formatYear(DateTime(_monthsYear)),
                      icon: AppIcon.setOf(context).calendarCollapse,
                      onTap: _closeMonths,
                    ),
                  ),
                ),
                AppIconButton(
                  icon: AppIcon.setOf(context).next,
                  tooltip: l.formatYear(DateTime(_monthsYear + 1)),
                  color: OnCareColors.textSecondary,
                  onPressed: _monthsYear < _last.year
                      ? () => setState(() => _monthsYear += 1)
                      : null,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
            child: Column(
              children: <Widget>[
                for (int row = 0; row < rows; row++)
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        for (
                          int col = 0;
                          col < OnCareCalendar.pickerMonthColumns;
                          col++
                        )
                          Expanded(
                            child: monthCell(
                              row * OnCareCalendar.pickerMonthColumns + col + 1,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 달력 머리의 누르는 라벨 — `2026년 9월 ▾` / `2026년 ▴`.
class _PickerHeaderLabel extends StatelessWidget {
  const _PickerHeaderLabel({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = context.oncare
        .text(OnCareTypography.titleSmall)
        .copyWith(color: OnCareColors.textSecondary);
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: OnCareRadius.mdAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s8),
          child: SizedBox(
            height: OnCareCalendar.pickerHeaderHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                AppIcon(
                  icon,
                  size: OnCareSize.iconLarge,
                  color: OnCareColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 시작·종료 날짜를 한 번의 달력에서 고르는 기간 선택창(#1778, 트레이너웹 반복 일정).
///
/// Material 기본 [showDateRangePicker] 는 전체 화면에 달이 끝없이 이어지는 목록이라
/// 다른 창과 모양이 완전히 달랐다. 이 창은 한 번에 한 달만 보여 주고 좌우 꺾쇠로
/// 달을 넘기는 고정 격자를 그린다 — 시작·종료일은 브랜드 색 원, 그 사이는 옅은
/// 브랜드 띠로 잇는다.
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
                icon: AppIcon.setOf(context).previous,
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
                icon: AppIcon.setOf(context).next,
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

/// 한 달을 고정 격자로 그린다 — 시작·종료일은 칸 크기의 브랜드 색 원에 흰 숫자,
/// 그 사이 날은 옅은 브랜드 띠([OnCareBrand.surface])에 짙은 브랜드 숫자다. 띠는
/// 시작·종료일 칸의 안쪽 절반까지 이어져 두 원과 붙는다. [firstDate]~[lastDate]
/// 밖의 날짜는 흐리게 두고 탭을 막는다.
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
    final bool isCap = isStart || isEnd;
    // 시작·종료가 서로 다른 날일 때만 띠가 있다. 같은 날이거나 종료일을 아직
    // 고르지 않았으면 원 하나만 그린다.
    final bool hasBand =
        start != null && end != null && !DateUtils.isSameDay(start, end);
    final bool between = hasBand && day.isAfter(start!) && day.isBefore(end!);
    // 시작일은 오른쪽 절반, 종료일은 왼쪽 절반에만 띠를 깔아 원과 붙인다. 주가
    // 바뀌며 줄이 꺾이는 자리는 각진 채로 줄 끝까지 이어진다.
    final Alignment? halfBand = !hasBand
        ? null
        : isStart
        ? Alignment.centerRight
        : isEnd
        ? Alignment.centerLeft
        : null;
    final TextStyle base = OnCareTypography.numeric(
      tokens.text(OnCareCalendar.rangeDay),
    );
    final TextStyle cap = base.copyWith(fontWeight: FontWeight.w700);

    return Semantics(
      button: true,
      enabled: !disabled,
      selected: isCap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : () => onDayTap(day),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            // 원 지름 = 칸의 짧은 변. 띠도 같은 높이라 원과 매끈하게 붙는다.
            final double diameter = math.min(box.maxWidth, box.maxHeight);
            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                if (between || halfBand != null)
                  Align(
                    alignment: halfBand ?? Alignment.center,
                    child: SizedBox(
                      width: halfBand == null ? box.maxWidth : box.maxWidth / 2,
                      height: diameter,
                      // 브랜드 옅은 바탕(`surface`)이던 때에는 흰 창과 거의
                      // 구분되지 않아 고른 기간이 잘 보이지 않았다(#2183).
                      // 눌림·강조 채움 단계로 한 칸 진하게 — 사이 날 숫자(진한
                      // 브랜드)는 그대로 읽힌다.
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: OnCareColors.onWhite(
                            tokens.brand.primary,
                            OnCareAlpha.medium,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (isCap)
                  SizedBox.square(
                    dimension: diameter,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.brand.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                Text(
                  '$dayOfMonth',
                  style: (isCap ? cap : base).copyWith(
                    color: isCap
                        ? OnCareColors.textOnFill
                        : between
                        ? tokens.brand.strong
                        : disabled
                        ? OnCareColors.textDisabled
                        : OnCareColors.textPrimary,
                  ),
                ),
              ],
            );
          },
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
  // 입력 방식 전환 아이콘은 앱의 아이콘 묶음을 따른다. 묶음이 비워 두면
  // Flutter 기본 아이콘이다(#1803).
  final IconData? timeInput = AppIcon.setOf(context).timeInput;
  final IconData? timeDial = AppIcon.setOf(context).timeDial;
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    helpText: helpText,
    switchToInputEntryModeIcon: timeInput == null
        ? null
        : AppIcon.resolve(context, timeInput),
    switchToTimerEntryModeIcon: timeDial == null
        ? null
        : AppIcon.resolve(context, timeDial),
  );
}
