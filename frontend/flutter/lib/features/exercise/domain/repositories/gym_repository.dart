import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';

/// Gym + trainer directory, plus the user's own two links. Both live here
/// because the links are coupled: leaving a gym also drops its trainer.
/// 예약 목록 한 쪽의 건수. 서버 기본값과 같다(#980).
///
/// 한 화면에 다 그리는 패널이라 알림함(30)보다 크게 잡는다 — 회원 한 명이 잡아 둔
/// 예약은 트레이너별로 갈라 보이고, 첫 쪽에 다가오는 예약이 모두 들어와야 한다.
const int reservationPageSize = 50;

/// 고른 자리의 시간에 트레이너의 다른 일정이 이미 있어 예약하지 않았다.
/// (#2284)
///
/// 자리가 마감된 것(`StateError`)과 구분한다 — 마감은 "다른 사람이 먼저
/// 잡았다"이고, 이것은 "트레이너가 그 시간을 다른 일로 쓰게 됐다"라서 회원에게
/// 할 말이 다르다. 서버는 다른 회원의 일정을 알려 주지 않으므로 목록은 없다.
class SlotTimeTakenError implements Exception {
  const SlotTimeTakenError(this.slotId);

  final String slotId;

  @override
  String toString() => 'SlotTimeTakenError($slotId)';
}

abstract class GymRepository {
  /// User's current gym (one). `null` until they register one.
  Future<Gym?> fetchMyGym();

  /// Nearby gyms shown in the "헬스장 찾기" finder sheet.
  Future<List<Gym>> fetchNearby();

  /// Drops the gym link, and the trainer with it — you cannot keep a trainer
  /// at a gym you left. [fetchMyGym] and [fetchMyTrainer] both return `null`
  /// after this.
  Future<void> disconnectMyGym();

  /// User's assigned trainer (one). `null` when unassigned.
  Future<Trainer?> fetchMyTrainer();

  /// Every trainer working at [gymId]. Empty when the gym has none.
  Future<List<Trainer>> fetchTrainersByGym(String gymId);

  /// Whole trainer directory, for the "트레이너 찾기" list page.
  Future<List<Trainer>> fetchAllTrainers();

  /// One trainer by their own id, `null` when not found.
  Future<Trainer?> fetchTrainer(String trainerId);

  /// Trainers suggested in the 추천 트레이너 rail, across gyms.
  Future<List<Trainer>> fetchRecommendedTrainers();

  /// Drops only the trainer link; the gym link stays. No-op when unassigned.
  Future<void> disconnectMyTrainer();

  /// Bookable times for one trainer, earliest first. Past slots are already
  /// filtered out; booked-out ones are kept so the day reads as full rather
  /// than empty.
  Future<List<TrainerSlot>> fetchSlots(String trainerId);

  /// Takes one place in [slotId].
  ///
  /// Throws [StateError] when the slot is unknown or already booked out, so a
  /// stale screen cannot silently overbook. 그 시간에 트레이너의 다른 일정이
  /// 있으면 [SlotTimeTakenError] 다(#2284).
  Future<void> reserve(String slotId);

  /// 내가 잡아 둔 예약 한 쪽. 예약 패널이 '내 자리'를 표시하고 취소를 걸 근거다. (#502)
  ///
  /// **다가오는 예약부터** 온다. 서버가 한 번에 주는 건수에 상한이 있어(#980), 더 과거를
  /// 보려면 받은 마지막 예약의 `startsAt`·`id` 를 [before]·[beforeId] 로 넘긴다.
  Future<List<MyReservation>> fetchMyReservations({
    int limit,
    DateTime? before,
    String? beforeId,
  });

  /// 예약 취소. 좌석과 트레이너 일정이 함께 돌아간다.
  ///
  /// 이미 시작한 수업이거나 남의 예약이면 [StateError] — 예약 실패와 같은 규칙으로,
  /// 목과 실서버가 같은 예외를 낸다.
  Future<void> cancelReservation(String reservationId);
}
