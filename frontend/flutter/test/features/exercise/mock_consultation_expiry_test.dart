/// 데모 상담 요청도 실서버처럼 내 목록을 읽을 때 지난 대기 요청이 만료된다. (#3360)
///
/// 서버는 회원이 목록을 열면 그 회원의 지난 대기 요청을 만료로 내리고 자리를
/// 푼다. 데모에는 요청을 확인해 줄 트레이너가 없어, 대역이 같은 일을 하지 않으면
/// 요청이 "대기 중" 으로 영영 남고 같은 트레이너에게 다시 신청할 수 없다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/data/repositories/dio_consultation_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare_core/clock.dart';

/// 김트레이너의 내일 07:00 `1:1 PT` 자리.
const String _slotId = 'slot-kim-1';

ConsultationDraft _draft({String slotId = _slotId}) => ConsultationDraft(
  trainerId: 'trainer-kim',
  exerciseGoal: ExerciseGoal.bloodPressure,
  healthPurposeType: HealthPurposeType.chronic,
  healthPurposeDetail: null,
  slotId: slotId,
  message: null,
  dataSharingConsent: true,
);

Future<TrainerSlot> _slot(MockGymRepository gym, String id) async =>
    (await gym.fetchSlots(
      'trainer-kim',
    )).singleWhere((TrainerSlot slot) => slot.id == id);

void main() {
  late MockGymRepository gym;
  late MockConsultationRepository repository;

  setUp(() {
    gym = MockGymRepository();
    repository = MockConsultationRepository(gym);
  });
  tearDown(() => debugNowKstOverride = null);

  test('만료 시각 전에는 대기 중으로 남는다', () async {
    await repository.create(_draft());
    final DateTime startsAt = (await _slot(gym, _slotId)).startsAt;

    debugNowKstOverride = () => startsAt
        .subtract(kConsultationExpireBeforeStart)
        .subtract(const Duration(minutes: 1));

    expect((await repository.fetchMine()).single.isPending, isTrue);
    expect((await _slot(gym, _slotId)).booked, isTrue);
  });

  test('자리 시작 두 시간 전이 되면 만료로 바뀌고 자리가 풀린다', () async {
    await repository.create(_draft());
    final DateTime startsAt = (await _slot(gym, _slotId)).startsAt;

    debugNowKstOverride = () =>
        startsAt.subtract(kConsultationExpireBeforeStart);

    expect(
      (await repository.fetchMine()).single.status,
      ConsultationStatus.expired,
    );
    expect((await _slot(gym, _slotId)).booked, isFalse);
  });

  test('신청 뒤 하루가 지나면 자리 시각과 무관하게 만료다', () async {
    final DateTime base = nowKst();
    debugNowKstOverride = () => base;
    await repository.create(_draft());

    // 내일 07:00 자리라 두 시간 전 규칙이 먼저 올 수도 있다 — 어느 쪽이든 만료다.
    debugNowKstOverride = () => base.add(kConsultationHold);

    expect(
      (await repository.fetchMine()).single.status,
      ConsultationStatus.expired,
    );
  });

  test('수락된 상담은 시각이 지나도 만료로 바뀌지 않는다', () async {
    final String id = await repository.create(_draft());
    repository.acceptForTesting(id);
    final DateTime startsAt = (await _slot(gym, _slotId)).startsAt;

    debugNowKstOverride = () => startsAt.add(const Duration(hours: 1));

    expect(
      (await repository.fetchMine()).single.status,
      ConsultationStatus.accepted,
    );
  });

  test('만료된 요청은 취소할 수 없다', () async {
    final String id = await repository.create(_draft());
    final DateTime startsAt = (await _slot(gym, _slotId)).startsAt;
    debugNowKstOverride = () =>
        startsAt.subtract(kConsultationExpireBeforeStart);
    await repository.fetchMine();

    await expectLater(
      repository.cancel(id),
      throwsA(isA<ConsultationNoLongerPending>()),
    );
  });

  test('접수도 지난 대기 요청을 먼저 만료로 내려 대기 중복에 걸리지 않는다', () async {
    final DateTime base = nowKst();
    debugNowKstOverride = () => base;
    await repository.create(_draft());

    // 하루가 지나 첫 요청이 만료됐다. 그 뒤의 다른 자리로 다시 신청한다.
    debugNowKstOverride = () => base.add(kConsultationHold);
    final List<TrainerSlot> open = await repository.fetchSlots('trainer-kim');
    final TrainerSlot next = open.firstWhere(
      (TrainerSlot slot) => slot.id != _slotId,
    );

    final String second = await repository.create(_draft(slotId: next.id));

    final List<ConsultationRequest> mine = await repository.fetchMine();
    expect(mine.first.id, second);
    expect(mine.first.isPending, isTrue);
    expect(mine.last.status, ConsultationStatus.expired);
  });
}
