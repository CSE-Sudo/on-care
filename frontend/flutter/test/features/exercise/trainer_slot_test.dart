import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';

/// 예약 슬롯은 트레이너에 귀속된다(#426). 예전에는 위젯 안에 슬롯 3개가
/// 하드코딩되어 있어 누구를 예약하든 같은 시간이 떴다.
///
/// 시각 의존을 피하려고 "특정 슬롯이 있다"고 단정하지 않는다. 시드에 오늘
/// 자리가 섞여 있어 실행 시각에 따라 목록에서 빠질 수 있으므로, 어느 시각에
/// 돌려도 성립하는 성질만 검증한다.
void main() {
  test('트레이너마다 다른 슬롯을 돌려준다', () async {
    final MockGymRepository repo = MockGymRepository();

    final List<TrainerSlot> kim = await repo.fetchSlots('trainer-kim');
    final List<TrainerSlot> park = await repo.fetchSlots('trainer-park');

    expect(kim, isNotEmpty);
    expect(park, isNotEmpty);
    expect(kim.every((TrainerSlot s) => s.trainerId == 'trainer-kim'), isTrue);
    expect(
      park.every((TrainerSlot s) => s.trainerId == 'trainer-park'),
      isTrue,
    );
    // 같은 헬스장 소속이어도 빈 시간이 겹치지 않는다.
    expect(
      kim
          .map((TrainerSlot s) => s.startsAt)
          .toSet()
          .intersection(park.map((TrainerSlot s) => s.startsAt).toSet()),
      isEmpty,
    );
  });

  test('지난 시간은 목록에 나오지 않는다', () async {
    final DateTime now = nowKst();
    final MockGymRepository repo = MockGymRepository();

    for (final String id in <String>[
      'trainer-kim',
      'trainer-park',
      'trainer-kang',
    ]) {
      final List<TrainerSlot> slots = await repo.fetchSlots(id);
      expect(slots, isNotEmpty, reason: '$id 는 항상 미래 자리가 남아 있어야 함');
      for (final TrainerSlot slot in slots) {
        expect(
          slot.startsAt.isAfter(now),
          isTrue,
          reason: '지난 시간이 예약 가능으로 노출되면 안 됨: ${slot.id}',
        );
      }
    }
  });

  test('슬롯은 시작 시각 오름차순이다', () async {
    final List<TrainerSlot> slots = await MockGymRepository().fetchSlots(
      'trainer-kim',
    );

    for (int i = 1; i < slots.length; i++) {
      expect(
        slots[i].startsAt.isBefore(slots[i - 1].startsAt),
        isFalse,
        reason: '슬롯이 시간순으로 정렬돼야 함',
      );
    }
  });

  test('슬롯이 없는 트레이너는 빈 목록이다', () async {
    // 윤재희는 빈 상태 화면을 데모에서 보려고 일부러 비워 뒀다.
    expect(await MockGymRepository().fetchSlots('trainer-yoon'), isEmpty);
    expect(await MockGymRepository().fetchSlots('trainer-nope'), isEmpty);
  });

  test('예약하면 그 자리가 마감되고 다시 조회해도 유지된다', () async {
    final MockGymRepository repo = MockGymRepository();
    final List<TrainerSlot> before = await repo.fetchSlots('trainer-kim');
    final TrainerSlot open = before.firstWhere((TrainerSlot s) => !s.booked);

    await repo.reserve(open.id);

    final List<TrainerSlot> after = await repo.fetchSlots('trainer-kim');
    final TrainerSlot same = after.firstWhere(
      (TrainerSlot s) => s.id == open.id,
    );
    // 1:1 PT 라 한 번 잡히면 그 자리는 그대로 마감이다 — 남는 자리가 없다.
    expect(same.booked, isTrue);
    // 같은 자리를 두 번 잡을 수 없다.
    await expectLater(repo.reserve(open.id), throwsStateError);
  });

  test('마감된 자리는 예약할 수 없다', () async {
    final MockGymRepository repo = MockGymRepository();
    final List<TrainerSlot> slots = await repo.fetchSlots('trainer-kim');
    final TrainerSlot full = slots.firstWhere((TrainerSlot s) => s.booked);

    await expectLater(repo.reserve(full.id), throwsStateError);
  });

  test('없는 슬롯 예약은 실패한다', () async {
    await expectLater(
      MockGymRepository().reserve('slot-nope'),
      throwsStateError,
    );
  });

  test('목록에서 빠진 지난 자리는 오래된 화면에서도 예약되지 않는다', () async {
    final MockGymRepository repo = MockGymRepository();
    final DateTime now = nowKst();
    // 오늘 06:00 자리는 아침에 돌리면 살아 있고 저녁이면 이미 빠져 있다.
    // 빠져 있을 때만 "지난 자리 예약 거부"를 검증한다.
    final List<TrainerSlot> live = await repo.fetchSlots('trainer-kang');
    final bool todaySlotGone = !live.any(
      (TrainerSlot s) => s.id == 'slot-kang-today',
    );
    if (!todaySlotGone) {
      // 아직 오늘 자리가 유효한 시각이므로 이 성질은 검증 대상이 아니다.
      expect(live.every((TrainerSlot s) => s.startsAt.isAfter(now)), isTrue);
      return;
    }
    await expectLater(repo.reserve('slot-kang-today'), throwsStateError);
  });

  test('한 저장소의 예약이 다른 트레이너 슬롯을 건드리지 않는다', () async {
    final MockGymRepository repo = MockGymRepository();
    final List<TrainerSlot> parkBefore = await repo.fetchSlots('trainer-park');
    final TrainerSlot kimSlot = (await repo.fetchSlots(
      'trainer-kim',
    )).firstWhere((TrainerSlot s) => !s.booked);

    await repo.reserve(kimSlot.id);

    final List<TrainerSlot> parkAfter = await repo.fetchSlots('trainer-park');
    expect(
      parkAfter.map((TrainerSlot s) => s.booked),
      parkBefore.map((TrainerSlot s) => s.booked),
    );
  });
}
