/// 데모 상담 요청이 서버처럼 남고, 자리를 잠그고, 취소된다. (#2659)
///
/// 예전 데모 저장소는 접수에 빈 id 만 돌려주고 아무것도 남기지 않았다. 그래서
/// 화면을 새로 읽으면 대기 상태가 사라지고, 신청한 자리도 헬스장 탭에서 계속
/// `예약 가능` 이었다.
library;

import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/data/repositories/dio_consultation_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';

/// 김트레이너의 내일 07:00 `1:1 PT` 자리 — 어느 시각에 돌려도 아직 오지 않았다.
const String _slotId = 'slot-kim-1';

ConsultationDraft _draft({String slotId = _slotId}) => ConsultationDraft(
  trainerId: 'trainer-kim',
  exerciseGoal: ExerciseGoal.bloodPressure,
  healthPurposeType: HealthPurposeType.chronic,
  healthPurposeDetail: null,
  slotId: slotId,
  message: '혈압 관리 상담 받고 싶어요',
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

  test('낸 신청이 내 목록에 대기 중으로 남는다', () async {
    final String id = await repository.create(_draft());

    final ConsultationRequest mine = (await repository.fetchMine()).single;
    expect(id, isNotEmpty);
    expect(mine.id, id);
    expect(mine.isPending, isTrue);
    expect(mine.trainerName, kDemoTrainerName);
    expect(mine.trainerGymName, '온케어짐 신촌점');
    expect(mine.exerciseGoal, ExerciseGoal.bloodPressure);
    expect(mine.message, '혈압 관리 상담 받고 싶어요');
    expect(mine.slotStartsAt, (await _slot(gym, _slotId)).startsAt);
  });

  test('신청한 자리는 잠겨 헬스장 탭에서도 찬 자리로 보인다', () async {
    await repository.create(_draft());

    expect((await _slot(gym, _slotId)).booked, isTrue);
    // 상담 폼의 빈 자리 목록에서도 빠진다.
    expect(
      (await repository.fetchSlots('trainer-kim')).map((TrainerSlot s) => s.id),
      isNot(contains(_slotId)),
    );
  });

  test('같은 트레이너에게 대기 중이면 또 낼 수 없다', () async {
    await repository.create(_draft());

    await expectLater(
      repository.create(_draft(slotId: 'slot-kim-4')),
      throwsA(isA<DuplicatePendingConsultation>()),
    );
  });

  test('이미 찬 자리는 잡을 수 없다', () async {
    // `slot-kim-2` 는 처음부터 마감된 자리다.
    await expectLater(
      repository.create(_draft(slotId: 'slot-kim-2')),
      throwsA(isA<ConsultationSlotTaken>()),
    );
    expect(await repository.fetchMine(), isEmpty);
  });

  test('취소하면 취소로 남고 자리가 다시 열린다', () async {
    final String id = await repository.create(_draft());

    await repository.cancel(id);

    expect(
      (await repository.fetchMine()).single.status,
      ConsultationStatus.cancelled,
    );
    expect((await _slot(gym, _slotId)).booked, isFalse);
    // 취소한 뒤에는 같은 트레이너에게 다시 낼 수 있다.
    expect(await repository.create(_draft()), isNotEmpty);
  });

  test('대기 중이 아닌 신청은 취소할 수 없다', () async {
    final String id = await repository.create(_draft());
    await repository.cancel(id);

    await expectLater(
      repository.cancel(id),
      throwsA(isA<ConsultationNoLongerPending>()),
    );
  });

  test('없는 신청을 취소하면 실서버의 404 와 같은 예외다 (#2858)', () async {
    await expectLater(
      repository.cancel('consult-unknown'),
      throwsA(isA<ConsultationNotFound>()),
    );
  });

  test('컨트롤러를 새로 만들어도 낸 신청이 복원된다', () async {
    await repository.create(_draft());

    final ConsultationRequestController controller =
        ConsultationRequestController(repository);
    addTearDown(controller.dispose);
    await controller.restore();

    expect(controller.hasPending(trainerId: 'trainer-kim'), isTrue);
  });
}
