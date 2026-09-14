import 'package:flutter/material.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' hide showAppToast, AppToastType;

typedef TimeRangeValue = ({TimeOfDay start, TimeOfDay end});

/// 상담 희망 시각의 시작·종료를 차례로 고른다.
///
/// 두 앱이 같은 시간 선택기를 쓰도록 공용 [showAppTimeRangePicker] 에 맡긴다
/// (#1701) — 시작을 고르고 확인하면 이어서 종료를 고른다. 중간에 취소하거나
/// 종료가 시작보다 이르거나 같으면 `null` 이다(범위로 쓸 수 없는 값이다).
Future<TimeRangeValue?> showConsultTimeRangePicker({
  required BuildContext context,
  required TimeOfDay start,
  required TimeOfDay end,
}) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final (TimeOfDay, TimeOfDay)? picked = await showAppTimeRangePicker(
    context: context,
    initialStart: start,
    initialEnd: end,
    startHelpText: l.exTimeRangeStartTime,
    endHelpText: l.exTimeRangeEndTime,
  );
  if (picked == null) return null;
  final (TimeOfDay pickedStart, TimeOfDay pickedEnd) = picked;
  return (start: pickedStart, end: pickedEnd);
}
