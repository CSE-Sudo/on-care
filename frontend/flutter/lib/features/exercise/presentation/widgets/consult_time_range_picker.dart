import 'package:flutter/material.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

typedef TimeRangeValue = ({TimeOfDay start, TimeOfDay end});

/// 상담 희망 시각의 시작·종료를 한 창에서 차례로 고른다(#1779).
///
/// `2db5b04` 시점의 상담 신청 전용 시간 선택창으로 되돌렸다 — 제목과 닫기 X,
/// 시작/종료 칸(`HH:mm` 직접 입력), 지금 고르는 단계 라벨, 오전/오후, 시계판.
/// 창은 공용 [showAppTimeRangePicker] 가 그리고 여기서는 회원앱 문구와 키
/// 접두사(`consult-time-range`)만 넣는다. 종료가 시작보다 이르거나 같으면 확인이
/// 막힌다. 닫거나 취소하면 `null` 이다.
Future<TimeRangeValue?> showConsultTimeRangePicker({
  required BuildContext context,
  required TimeOfDay start,
  required TimeOfDay end,
}) {
  final AppLocalizations l = AppLocalizations.of(context);
  return showAppTimeRangePicker(
    context: context,
    initialStart: start,
    initialEnd: end,
    labels: AppTimePickerLabels(
      title: l.exTimeRangeTitle,
      am: l.exSlotAm,
      pm: l.exSlotPm,
      previousStep: l.exTimeRangePrevStep,
      nextStep: l.exTimeRangeNextStep,
      cancel: l.actionCancel,
      confirm: l.actionConfirm,
    ),
    startLabel: l.exTimeRangeStartTime,
    endLabel: l.exTimeRangeEndTime,
    startHourStepLabel: l.exTimeRangeStartHourStep,
    startMinuteStepLabel: l.exTimeRangeStartMinuteStep,
    endHourStepLabel: l.exTimeRangeEndHourStep,
    endMinuteStepLabel: l.exTimeRangeEndMinuteStep,
    invalidEndMessage: l.exTimeRangeInvalidEnd,
    keyPrefix: 'consult-time-range',
  );
}
