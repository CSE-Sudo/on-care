/// 목업 헬스장 저장소의 포인트 체험 규칙 — 서버 `points_trial_service` 와 같다. (#1790)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';

void main() {
  tearDown(() => debugNowKstOverride = null);

  Future<TrainerSlot> slotOf(
    MockGymRepository repo,
    String trainerId,
    String id,
  ) async => (await repo.fetchSlots(
    trainerId,
  )).firstWhere((TrainerSlot s) => s.id == id);

  test('담당 트레이너가 있으면 체험 자리를 내주지 않고 예약도 막는다', () async {
    final DemoPointsLedger ledger = DemoPointsLedger();
    final MockGymRepository repo = MockGymRepository(points: ledger);

    final List<TrainerSlot> park = await repo.fetchSlots('trainer-park');

    expect(park.any((TrainerSlot s) => s.isPointsTrial), isFalse);
    await expectLater(repo.reserve('slot-park-trial'), throwsStateError);
    expect(ledger.balance, kDemoOpeningPoints);
  });

  test('담당이 없으면 500P 로 예약하고, 트레이너별로 한 번뿐이다', () async {
    // 데모 시작 잔액 1240P.
    final DemoPointsLedger ledger = DemoPointsLedger();
    final MockGymRepository repo = MockGymRepository(points: ledger);
    await repo.disconnectMyTrainer();

    final List<TrainerSlot> choi = await repo.fetchSlots('trainer-choi');
    expect(choi.where((TrainerSlot s) => s.isPointsTrial), hasLength(2));
    expect(
      choi.firstWhere((TrainerSlot s) => s.isPointsTrial).trialBlockedReason,
      isNull,
    );

    await repo.reserve('slot-choi-trial');
    expect(ledger.balance, 740);

    final TrainerSlot second = await slotOf(
      repo,
      'trainer-choi',
      'slot-choi-trial-2',
    );
    expect(second.trialBlockedReason, TrialBlockedReason.trialUsed);
    await expectLater(repo.reserve('slot-choi-trial-2'), throwsStateError);

    // 다른 트레이너의 체험은 따로 센다.
    await repo.reserve('slot-park-trial');
    expect(ledger.balance, 240);

    final List<MyReservation> mine = await repo.fetchMyReservations();
    final MyReservation trial = mine.firstWhere(
      (MyReservation r) => r.slotId == 'slot-choi-trial',
    );
    expect(trial.isPointsTrial, isTrue);
    expect(trial.pointsCost, kPointsTrialCost);
  });

  test('잔액이 모자라면 이유를 싣고 예약을 막는다', () async {
    final DemoPointsLedger ledger = DemoPointsLedger(openingBalance: 499);
    final MockGymRepository repo = MockGymRepository(points: ledger);
    await repo.disconnectMyTrainer();

    final TrainerSlot slot = await slotOf(
      repo,
      'trainer-park',
      'slot-park-trial',
    );

    expect(slot.trialBlockedReason, TrialBlockedReason.insufficientPoints);
    await expectLater(repo.reserve('slot-park-trial'), throwsStateError);
    expect(ledger.balance, 499);
  });

  test('시작 24시간 전까지 취소하면 돌려받고 다시 체험할 수 있다', () async {
    final DemoPointsLedger ledger = DemoPointsLedger(openingBalance: 1000);
    final MockGymRepository repo = MockGymRepository(points: ledger);
    await repo.disconnectMyTrainer();
    await repo.reserve('slot-park-trial');

    final MyReservation booked = (await repo.fetchMyReservations()).single;
    expect(booked.pointsRefundable, isTrue);

    await repo.cancelReservation(booked.id);

    expect(ledger.balance, 1000);
    final TrainerSlot slot = await slotOf(
      repo,
      'trainer-park',
      'slot-park-trial',
    );
    expect(slot.trialBlockedReason, isNull);
    await repo.reserve('slot-park-trial');
    expect(ledger.balance, 500);
  });

  test('24시간 이내 취소는 돌려받지 못하고 한 번으로 센다', () async {
    final DemoPointsLedger ledger = DemoPointsLedger(openingBalance: 1000);
    final MockGymRepository repo = MockGymRepository(points: ledger);
    await repo.disconnectMyTrainer();
    final TrainerSlot slot = await slotOf(
      repo,
      'trainer-park',
      'slot-park-trial',
    );
    await repo.reserve(slot.id);

    // 체험 두 시간 전으로 시계를 옮긴다.
    debugNowKstOverride = () =>
        slot.startsAt.subtract(const Duration(hours: 2));
    final MyReservation booked = (await repo.fetchMyReservations()).single;
    expect(booked.pointsRefundable, isFalse);

    await repo.cancelReservation(booked.id);

    expect(ledger.balance, 500);
    await expectLater(repo.reserve(slot.id), throwsStateError);
  });
}
