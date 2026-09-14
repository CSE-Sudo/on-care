import 'package:flutter/material.dart';

/// 날짜 선택(#1695) — 두 앱의 `portrait_date_picker` 복사본을 대체한다.
///
/// 모양(흰 바탕·반경 20·선택일 브랜드·오늘 테두리)은 테마의 `datePickerTheme` 가
/// 정한다. 세로 방향 달력으로 연다.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
    initialEntryMode: DatePickerEntryMode.calendarOnly,
  );
}

/// 기간 선택 — 시작일·종료일.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialRange,
  String? helpText,
}) {
  return showDateRangePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDateRange: initialRange,
    helpText: helpText,
    initialEntryMode: DatePickerEntryMode.calendarOnly,
  );
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
