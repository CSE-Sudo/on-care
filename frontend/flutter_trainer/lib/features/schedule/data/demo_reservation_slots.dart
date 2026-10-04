import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/reservation_slot.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

/// 목업 데모에서 트레이너가 이미 열어 둔 예약 자리.
///
/// 목업 저장소가 빈 목록으로 시작해, 데모의 `예약 슬롯` 창은 늘 "열린 예약
/// 슬롯이 없습니다" 만 보였다 — 날짜별 묶음(#2182)도, 예약된 자리의 회색 칸도
/// 볼 수 없었다.
///
/// **회원 앱 목업과 같은 자리다.** 데모 트레이너는 회원 앱의 `trainer-kim`
/// (`frontend/flutter/.../mock_gym_repository.dart` 의 `_seedSlots`)이고, 두
/// 앱이 같은 트레이너의 같은 달력을 보여야 하므로 시각·종류·예약 여부를 똑같이
/// 둔다. 한쪽을 바꾸면 다른 쪽도 바꾼다.
///
/// 시각은 데모 스케줄 시드(09:00~21:30)와 겹치지 않는 이른 아침·늦은 저녁에
/// 둔다 — 트레이너 달력의 일정과 같은 시간에 자리가 열려 있으면 안 된다.
/// 날짜는 만든 날의 "오늘" 기준이라, 며칠 뒤에 열어도 앞으로의 자리로 보인다.
List<ReservationSlot> demoReservationSlots({DateTime? now}) {
  final DateTime today = now ?? nowKst();
  DateTime at(int addDays, int hour, int minute) =>
      DateTime(today.year, today.month, today.day + addDays, hour, minute);

  return <ReservationSlot>[
    ReservationSlot(
      id: 'slot-kim-today',
      startsAt: at(0, 20, 0),
      booked: false,
      isClosed: false,
      sessionType: SessionType.personalTraining,
    ),
    ReservationSlot(
      id: 'slot-kim-1',
      startsAt: at(1, 7, 0),
      booked: false,
      isClosed: false,
      sessionType: SessionType.personalTraining,
    ),
    // 회원이 이미 잡아 간 자리 — 회원 앱에서는 "마감" 으로, 여기서는 회색
    // `예약됨` 칸으로 보인다.
    ReservationSlot(
      id: 'slot-kim-2',
      startsAt: at(1, 22, 0),
      booked: true,
      isClosed: false,
      sessionType: SessionType.personalTraining,
    ),
    ReservationSlot(
      id: 'slot-kim-3',
      startsAt: at(2, 7, 30),
      booked: false,
      isClosed: false,
      sessionType: SessionType.consultation,
    ),
    // 회원이 신청해 대기 중인 상담 자리 둘(#2797) — 상담함의 시드 요청
    // ([demoPendingRequestSlots])이 고른 자리다. 실서버처럼 신청이 자리를
    // 잡으므로 예약 슬롯 창에서는 예약된 칸으로 선다(저장소가 신청 상태를 보고
    // 정한다). 빈 상담 자리(`slot-kim-3`·`slot-kim-5`)는 회원 앱 데모 사용자가
    // 신청해 볼 수 있게 그대로 둔다.
    ReservationSlot(
      id: 'slot-kim-6',
      startsAt: at(3, 22, 0),
      booked: false,
      isClosed: false,
      sessionType: SessionType.consultation,
    ),
    ReservationSlot(
      id: 'slot-kim-4',
      startsAt: at(4, 6, 30),
      booked: false,
      isClosed: false,
      sessionType: SessionType.personalTraining,
    ),
    // 김민수의 재상담 신청이 잡은 자리(#2797).
    ReservationSlot(
      id: 'slot-kim-7',
      startsAt: at(5, 7, 0),
      booked: false,
      isClosed: false,
      sessionType: SessionType.consultation,
    ),
    ReservationSlot(
      id: 'slot-kim-5',
      startsAt: at(6, 21, 30),
      booked: false,
      isClosed: false,
      sessionType: SessionType.consultation,
    ),
  ];
}

/// 상담함 시드 요청이 고른 자리 — 자리 id → 그 신청과 신청한 회원. (#2797)
///
/// 실서버에서 대기 중인 신청은 고른 자리를 잡는다(`remaining = 0`). 데모 예약
/// 슬롯 저장소는 이 표를 보고, 트레이너가 아직 결정하지 않은 신청의 자리를
/// 예약된 칸(신청자 이름)으로 그린다. 거절하면 자리가 다시 비고, 수락하면 그
/// 시각의 상담 일정이 자리를 잡는다.
const Map<String, ({String requestId, String memberName})>
demoPendingRequestSlots = <String, ({String requestId, String memberName})>{
  'slot-kim-6': (requestId: 'demo-consultation-1', memberName: '김하늘'),
  'slot-kim-7': (requestId: 'demo-consultation-2', memberName: '김민수'),
};
