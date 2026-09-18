import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';

/// 빈 예약 시간 칩 한 줄 — `8/8 19:00–20:00`. (#1701, #1873)
///
/// 헬스장 탭의 예약 가능 시간과 상담 신청 폼이 **같은 자리**를 같은 모양으로 고르게
/// 한곳에 둔다. 칩은 한 줄이라 날짜를 짧은 숫자 표기로 줄이고, 시각은 트레이너 쪽
/// 스케줄과 같은 24시간 표기다. 종료 시각은 트레이너가 그 자리를 열 때 정한 길이로
/// 만든다.
String trainerSlotChipLabel(TrainerSlot slot) {
  final DateTime end = slot.startsAt.add(
    Duration(minutes: slot.durationMinutes),
  );
  return '${slot.startsAt.month}/${slot.startsAt.day} '
      '${_hhmm(slot.startsAt)}–${_hhmm(end)}';
}

String _hhmm(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';
