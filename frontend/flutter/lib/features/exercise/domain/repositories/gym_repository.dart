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

/// 다가오는 예약이 이미 있어 새 자리를 잡지 않았다. (#3240)
///
/// 1:1 PT 라 다음 일정은 하나이고, 시간을 바꾸려면 먼저 취소한다(#1072). 마감
/// (`StateError`)과 구분한다 — 다시 눌러도 같은 결과라 "먼저 취소하라" 고 알려야 한다.
class UpcomingReservationError implements Exception {
  const UpcomingReservationError(this.slotId);

  final String slotId;

  @override
  String toString() => 'UpcomingReservationError($slotId)';
}

/// 이름 검색어의 최대 길이 — 서버 `GET /gyms/search` 의 `q` 상한과 같다(#3355).
const int kGymSearchQueryMaxLength = 100;

/// 검색 칸에 친 글을 서버에 보낼 검색어로 다듬는다. (#3355)
///
/// 앞뒤 공백을 떼고 상한을 넘는 뒤쪽을 자른다. 빈 문자열이면 검색하지 않는다는
/// 뜻이다 — 서버는 빈 검색어를 422 로 돌려보낸다. 서버가 글자(코드 포인트)로
/// 세므로 여기서도 그렇게 센다.
String gymSearchQueryOf(String typed) {
  final String trimmed = typed.trim();
  if (trimmed.runes.length <= kGymSearchQueryMaxLength) return trimmed;
  return String.fromCharCodes(
    trimmed.runes.take(kGymSearchQueryMaxLength),
  ).trim();
}

abstract class GymRepository {
  /// User's current gym (one). `null` until they register one.
  Future<Gym?> fetchMyGym();

  /// Nearby gyms shown in the "헬스장 찾기" finder sheet.
  ///
  /// 서버는 검색 중심에서 기본 반경 안의 헬스장만 가까운 순으로 준다(#3356).
  /// 목록에 없는 헬스장은 [fetchGym] 으로 읽는다.
  Future<List<Gym>> fetchNearby();

  /// 헬스장을 이름·주소로 찾는다. (#3355)
  ///
  /// [fetchNearby] 와 달리 반경이 없다 — 주변 목록에 없는 헬스장, 다른 동네의
  /// 헬스장도 나온다. 서버는 등록된 헬스장과 외부 장소 검색 결과를 합쳐 주고,
  /// 회원 위치를 알면 가까운 순으로 준다. [query] 는 [gymSearchQueryOf] 를 거친
  /// 비어 있지 않은 값이어야 한다.
  ///
  /// 외부 검색에서만 찾은 헬스장은 서버에 등록돼 있지 않아 [fetchGym] 으로는
  /// 읽히지 않는다. 화면은 여기서 받은 값으로 상세를 그린다.
  Future<List<Gym>> searchGyms(String query);

  /// 헬스장 한 곳을 id 로 읽는다. 없으면 `null`. (#3356)
  ///
  /// [fetchNearby] 가 반경·개수로 잘려 오므로, 목록 밖의 헬스장으로 들어온 상세
  /// 화면(담당 트레이너의 소속, 알림·딥링크)이 이것으로 연다.
  Future<Gym?> fetchGym(String gymId);

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
