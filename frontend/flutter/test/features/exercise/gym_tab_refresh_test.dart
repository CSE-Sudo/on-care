/// 운동 탭 헬스장 영역의 재조회 대상과 그 결과. (#2856)
///
/// 내 헬스장·담당 트레이너·내 예약·예약 가능 시간은 autoDispose 가 아니라서
/// 앱을 켠 뒤 처음 읽은 값이 계속 남았다. 트레이너가 웹에서 예약을 취소하거나
/// 연결을 해제해도 회원 앱은 옛 값을 보였다. 여기서는 셸이 부르는 갱신 함수의
/// **대상 목록**과, 서버 값이 바뀐 뒤 그 함수로 새 값이 읽히는지를 본다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_refresh.dart';
import 'package:oncare/features/exercise/presentation/utils/next_pt.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

const Gym _gym = Gym(
  id: 'gym-refresh',
  name: '재조회 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.3,
  rating: 4.5,
  tags: <String>[],
);

const Trainer _trainer = Trainer(
  id: 'trainer-refresh',
  gymId: 'gym-refresh',
  name: '박트레이너',
  role: '퍼스널 트레이너',
);

/// 고정 KST 시각 — 다음 PT 계산의 기준.
final DateTime _now = DateTime(2026, 8, 20, 9);

MyReservation _reservation(String id, DateTime at) => MyReservation(
  id: id,
  slotId: 'slot-$id',
  trainerId: _trainer.id,
  startsAt: at,
  cancellable: true,
);

TrainerSlot _slot(String id, {required bool booked}) => TrainerSlot(
  id: id,
  trainerId: _trainer.id,
  startsAt: DateTime(2026, 8, 21, 19),
  booked: booked,
  sessionType: '1:1 PT',
);

/// 서버 쪽 값을 테스트가 바꿀 수 있는 대역. 지연 없이 바로 답한다.
class _ServerGymRepository extends MockGymRepository {
  Gym? gym = _gym;
  Trainer? trainer = _trainer;
  List<MyReservation> reservations = <MyReservation>[];
  List<TrainerSlot> slots = <TrainerSlot>[];

  int gymCalls = 0;
  int trainerCalls = 0;
  int reservationCalls = 0;
  int slotCalls = 0;

  @override
  Future<Gym?> fetchMyGym() async {
    gymCalls++;
    return gym;
  }

  @override
  Future<Trainer?> fetchMyTrainer() async {
    trainerCalls++;
    return trainer;
  }

  @override
  Future<List<MyReservation>> fetchMyReservations({
    int limit = reservationPageSize,
    DateTime? before,
    String? beforeId,
  }) async {
    reservationCalls++;
    return List<MyReservation>.of(reservations);
  }

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async {
    slotCalls++;
    return List<TrainerSlot>.of(slots);
  }
}

ProviderContainer _container(GymRepository repository) {
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[gymRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('대상 목록', () {
    test('헬스장 영역 네 provider 를 모두 담는다', () {
      final List<ProviderOrFamily> seen = <ProviderOrFamily>[];
      refreshGymTabData(seen.add);

      expect(
        seen,
        containsAll(<ProviderOrFamily>[
          myGymProvider,
          myTrainerProvider,
          myReservationsProvider,
          trainerSlotsProvider,
        ]),
      );
      expect(seen, kGymTabRefreshTargets);
    });

    test('운동 기록 갱신 목록과 섞이지 않는다', () {
      // 운동을 저장할 때마다 예약까지 다시 읽을 까닭은 없다.
      for (final ProviderOrFamily target in kGymTabRefreshTargets) {
        expect(kExerciseChangeRefreshTargets, isNot(contains(target)));
      }
    });
  });

  group('서버 값이 바뀐 뒤', () {
    test('트레이너가 취소한 예약은 갱신 뒤 내 예약과 다음 PT 에서 빠진다', () async {
      final _ServerGymRepository repo = _ServerGymRepository()
        ..reservations = <MyReservation>[
          _reservation('r1', DateTime(2026, 8, 21, 19)),
        ];
      final ProviderContainer c = _container(repo);

      final List<MyReservation> before = await c.read(
        myReservationsProvider.future,
      );
      expect(
        nextPtAt(
          sessions: const <CoachSession>[],
          reservations: before,
          now: _now,
        ),
        DateTime(2026, 8, 21, 19),
      );

      // 트레이너가 웹에서 그 예약을 취소했다.
      repo.reservations = <MyReservation>[];
      // 갱신 전에는 옛 값 그대로다 — 이것이 고친 결함이다.
      expect(await c.read(myReservationsProvider.future), hasLength(1));

      refreshGymTabData(c.invalidate);
      final List<MyReservation> after = await c.read(
        myReservationsProvider.future,
      );
      expect(after, isEmpty);
      expect(
        nextPtAt(
          sessions: const <CoachSession>[],
          reservations: after,
          now: _now,
        ),
        isNull,
      );
      expect(repo.reservationCalls, 2);
    });

    test('다른 회원이 잡은 자리는 갱신 뒤 마감으로 보인다', () async {
      final _ServerGymRepository repo = _ServerGymRepository()
        ..slots = <TrainerSlot>[_slot('s1', booked: false)];
      final ProviderContainer c = _container(repo);

      expect(
        (await c.read(trainerSlotsProvider(_trainer.id).future)).single.booked,
        isFalse,
      );

      repo.slots = <TrainerSlot>[_slot('s1', booked: true)];
      refreshGymTabData(c.invalidate);

      expect(
        (await c.read(trainerSlotsProvider(_trainer.id).future)).single.booked,
        isTrue,
      );
      expect(repo.slotCalls, 2);
    });

    test('연결이 해제되면 갱신 뒤 내 헬스장·담당 트레이너가 비어 있다', () async {
      final _ServerGymRepository repo = _ServerGymRepository();
      final ProviderContainer c = _container(repo);

      expect(await c.read(myGymProvider.future), isNotNull);
      expect(await c.read(myTrainerProvider.future), isNotNull);

      repo
        ..gym = null
        ..trainer = null;
      refreshGymTabData(c.invalidate);

      expect(await c.read(myGymProvider.future), isNull);
      expect(await c.read(myTrainerProvider.future), isNull);
      expect(repo.gymCalls, 2);
      expect(repo.trainerCalls, 2);
    });

    test('다시 읽는 동안 이전 값을 그대로 들고 있어 카드가 비지 않는다', () async {
      final _ServerGymRepository repo = _ServerGymRepository();
      final ProviderContainer c = _container(repo);
      // 붙어 있는 화면처럼 계속 듣는다 — 그래야 비운 뒤 곧바로 다시 읽힌다.
      final ProviderSubscription<AsyncValue<Gym?>> sub = c.listen(
        myGymProvider,
        (_, _) {},
      );
      addTearDown(sub.close);
      await c.read(myGymProvider.future);

      refreshGymTabData(c.invalidate);
      final AsyncValue<Gym?> refreshing = c.read(myGymProvider);

      expect(refreshing.isLoading, isTrue);
      expect(refreshing.hasValue, isTrue);
      expect(refreshing.valueOrNull?.id, _gym.id);
      await c.read(myGymProvider.future);
    });
  });
}
