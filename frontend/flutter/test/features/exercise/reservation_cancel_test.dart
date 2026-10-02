/// 회원 예약 취소. (#502)
///
/// 목 저장소가 실서버와 같은 결과를 내야 데모 화면과 실모드가 갈리지 않는다 —
/// 자리가 다시 열리고, 취소한 자리는 다시 잡을 수 있고, 지난 예약과 남의 예약은
/// 거절된다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare_core/clock.dart';

/// 지금 이후에 시작하는 자리 하나. 시드에 오늘 자리가 섞여 있어 실행 시각에
/// 따라 목록이 달라지므로, 예약 가능한 것을 골라 쓴다.
Future<TrainerSlot> _bookableSlot(MockGymRepository repo) async {
  final List<TrainerSlot> slots = await repo.fetchSlots('trainer-kim');
  return slots.firstWhere(
    (TrainerSlot s) => !s.booked && s.startsAt.isAfter(nowKst()),
  );
}

void main() {
  test('취소하면 자리가 다시 열리고 내 예약에서 빠진다', () async {
    final MockGymRepository repo = MockGymRepository();
    final TrainerSlot slot = await _bookableSlot(repo);

    await repo.reserve(slot.id);
    final List<MyReservation> mine = await repo.fetchMyReservations();
    final MyReservation reservation = mine.firstWhere(
      (MyReservation r) => r.slotId == slot.id,
    );
    expect(reservation.trainerId, slot.trainerId);
    expect(reservation.cancellable, isTrue);

    final List<TrainerSlot> booked = await repo.fetchSlots('trainer-kim');
    expect(
      booked.firstWhere((TrainerSlot s) => s.id == slot.id).booked,
      isTrue,
    );

    await repo.cancelReservation(reservation.id);

    final List<TrainerSlot> after = await repo.fetchSlots('trainer-kim');
    expect(
      after.firstWhere((TrainerSlot s) => s.id == slot.id).booked,
      isFalse,
      reason: '취소했는데 자리가 다시 열리지 않으면 그 시간은 영영 잠긴다',
    );
    expect(await repo.fetchMyReservations(), isEmpty);
  });

  test('취소한 자리는 다시 예약할 수 있다', () async {
    final MockGymRepository repo = MockGymRepository();
    final TrainerSlot slot = await _bookableSlot(repo);

    await repo.reserve(slot.id);
    final MyReservation first = (await repo.fetchMyReservations()).single;
    await repo.cancelReservation(first.id);

    // 다시 잡히지 않으면 회원은 '취소했더니 그 시간을 잃었다'가 된다.
    await repo.reserve(slot.id);
    expect(await repo.fetchMyReservations(), hasLength(1));
  });

  test('없는 예약을 취소하면 StateError', () async {
    final MockGymRepository repo = MockGymRepository();

    // 실서버의 404(남의 예약 포함)와 같은 예외로 옮겨, 화면이 한 갈래만 다룬다.
    expect(
      () => repo.cancelReservation('res-nope'),
      throwsA(isA<StateError>()),
    );
  });

  test('이미 취소한 예약을 또 취소하면 StateError', () async {
    final MockGymRepository repo = MockGymRepository();
    final TrainerSlot slot = await _bookableSlot(repo);

    await repo.reserve(slot.id);
    final MyReservation reservation = (await repo.fetchMyReservations()).single;
    await repo.cancelReservation(reservation.id);

    expect(
      () => repo.cancelReservation(reservation.id),
      throwsA(isA<StateError>()),
    );
  });
}
