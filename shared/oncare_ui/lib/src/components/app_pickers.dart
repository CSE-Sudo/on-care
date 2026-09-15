import 'package:flutter/material.dart';
import 'package:oncare_ui/src/components/app_icon.dart';

/// 날짜 선택(#1695) — 두 앱의 `portrait_date_picker` 복사본을 대체한다.
///
/// 모양(흰 바탕·반경 20·선택일 브랜드·오늘 테두리)은 테마의 `datePickerTheme` 가
/// 정한다. 세로 방향 달력으로 연다. 달 이동 꺾쇠·연도 펼침 화살표는 Flutter 가
/// 아이콘을 고정해 두어 아이콘 묶음(#1803)을 따르지 않는다.
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
