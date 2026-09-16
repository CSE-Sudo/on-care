import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';

/// In-memory gym + trainer data matching the prototype's `GymCard` /
/// `GymFinder` mocks. The user starts connected to 온케어짐 신촌점 and to
/// 김트레이너 — the same gym and person the trainer app's
/// `seedTrainerProfile` describes, so both apps show one relationship.
///
/// Stateful (not const) so the two links can be dropped for the session. The
/// provider holds one instance, so MY 탭과 운동 탭이 같은 연결 상태를 본다.
class MockGymRepository implements GymRepository {
  MockGymRepository();

  /// 연결 상태는 id 만 들고 있다 — 목록과 어긋날 수 없다.
  String? _myGymId = 'gym-oncare-sinchon';
  String? _myTrainerId = 'trainer-kim';

  /// 담당 트레이너 연결이 살아 있는가(#1865).
  ///
  /// 조회([fetchMyTrainer])와 달리 **기다리지 않는다**. 데모 조회는 실제 요청처럼
  /// 잠깐 지연을 두는데, 위젯 테스트는 시간을 스스로 진행시키지 않으면 그 대기가
  /// 끝나지 않는다 — 연결 여부만 묻는 자리까지 지연을 타면 멀쩡하던 테스트가 멈춘다.
  bool get hasTrainer => _myTrainerId != null;

  static const Gym _sinchon = Gym(
    id: 'gym-oncare-sinchon',
    name: '온케어짐 신촌점',
    address: '서울 서대문구 신촌로 120',
    distanceKm: 0.8,
    rating: 4.7,
    tags: <String>['다이어트', '재활운동'],
    weekdayHours: '06:00 – 23:00',
    weekendHours: '08:00 - 20:00',
    phone: '02-1234-5678',
    lat: 37.5559,
    lng: 126.9368,
  );

  static const Gym _healthmate = Gym(
    id: 'gym-healthmate',
    name: '헬스메이트 신촌점',
    address: '서울 서대문구 신촌로 83',
    distanceKm: 1.2,
    rating: 4.5,
    tags: <String>['근력운동', '만성질환 관리'],
    weekdayHours: '05:30 - 24:00',
    weekendHours: '07:00 - 22:00',
    phone: '02-2345-6789',
    lat: 37.5548,
    lng: 126.9385,
  );

  static const Gym _bodyAndSoul = Gym(
    id: 'gym-bodyandsoul',
    name: '바디앤소울 피트니스',
    address: '서울 마포구 백범로 23',
    distanceKm: 1.5,
    rating: 4.8,
    tags: <String>['PT', '식단 상담'],
    weekdayHours: '06:00 - 22:00',
    weekendHours: '09:00 - 18:00',
    phone: '02-3456-7890',
    lat: 37.5455,
    lng: 126.9425,
  );

  static const List<Gym> _gyms = <Gym>[_sinchon, _healthmate, _bodyAndSoul];

  /// 트레이너 앱 `seedTrainerProfile` 과 같은 값이어야 한다.
  static const Trainer _kim = Trainer(
    id: 'trainer-kim',
    gymId: 'gym-oncare-sinchon',
    name: '김트레이너',
    role: '퍼스널 트레이너',
    reason: '혈압 관리와 운동 병행 지도',
    career: '7년',
    intro:
        '혈압 관리와 체중 감량을 함께 다루는 퍼스널 트레이너입니다. 회원 상태에 맞춘 '
        'AI 추천 프로그램을 활용해 안전한 강도부터 시작합니다.',
    certifications: <String>['생활스포츠지도사 2급', '퍼스널트레이닝 CPT', '스포츠 영양사'],
  );

  /// 같은 헬스장 소속 트레이너들 — 헬스장당 1명 제약이 없음을 보여준다.
  static const List<Trainer> _trainers = <Trainer>[
    _kim,
    Trainer(
      id: 'trainer-park',
      gymId: 'gym-oncare-sinchon',
      name: '박트레이너',
      role: '재활 트레이너',
      reason: '무릎·허리 통증 관리 다수 경험',
      career: '11년',
      intro:
          '수술 후 회복과 만성 통증 관리를 주로 맡습니다. 무리하지 않는 범위에서 '
          '가동 범위를 조금씩 넓혀 갑니다.',
      certifications: <String>['물리치료사', '재활 트레이닝 NASM-CES'],
    ),
    Trainer(
      id: 'trainer-choi',
      gymId: 'gym-oncare-sinchon',
      name: '최트레이너',
      role: '그룹 PT 트레이너',
      reason: '2~4인 소그룹 수업 운영',
      career: '4년',
      intro:
          '2~4인 소그룹 수업을 진행합니다. 혼자서는 운동을 이어 가기 어려운 회원에게 '
          '적합한 방식입니다.',
      certifications: <String>['생활스포츠지도사 2급'],
    ),
    Trainer(
      id: 'trainer-kang',
      gymId: 'gym-healthmate',
      name: '강트레이너',
      role: '퍼스널 트레이너',
      reason: '교대근무 일정 맞춤 설계',
      career: '5년',
      intro:
          '불규칙한 근무 일정에 맞춘 운동 설계를 주로 합니다. 짧은 시간에 집중도를 '
          '높이는 근력 프로그램을 구성합니다.',
      certifications: <String>['건강운동관리사', '퍼스널트레이닝 CPT'],
    ),
    Trainer(
      id: 'trainer-yoon',
      gymId: 'gym-healthmate',
      name: '윤트레이너',
      role: '근력 전문 트레이너',
      reason: '기초 근력부터 단계별 지도',
      career: '8년',
      intro:
          '기초 근력부터 파워리프팅까지 단계를 나눠 지도합니다. 현재 들 수 있는 '
          '무게를 확인한 뒤 다음 단계를 정합니다.',
      certifications: <String>['퍼스널트레이닝 CPT'],
    ),
    Trainer(
      id: 'trainer-lee',
      gymId: 'gym-bodyandsoul',
      name: '이트레이너',
      role: '퍼스널 트레이너',
      reason: '초심자용 간단 프로그램 구성',
      career: '9년',
      intro:
          '운동을 처음 시작하는 회원을 오래 지도했습니다. 식단 상담을 함께 진행해 '
          '생활 습관부터 조정합니다.',
      certifications: <String>['생활스포츠지도사 2급', '스포츠 영양사', '재활 트레이닝 NASM-CES'],
    ),
    Trainer(
      id: 'trainer-cho',
      gymId: 'gym-bodyandsoul',
      name: '조트레이너',
      role: '시니어 운동 트레이너',
      reason: '고령 회원 균형 운동 장기 지도',
      career: '12년',
      intro:
          '60대 이상 회원 수업을 오래 맡았습니다. 균형 잡기와 낙상 예방 동작부터 '
          '시작해 천천히 강도를 올립니다.',
      certifications: <String>['건강운동관리사', '노인스포츠지도사'],
    ),
    // 카카오 Local 에서 온 주변 헬스장의 소속 트레이너(#329). gymId 가 카카오
    // place id 라서 데모 픽스처와 실 API 응답 양쪽에 그대로 붙는다.
    // **시연용 가상 인물이다** — 실재 업체의 실제 트레이너가 아니다.
    Trainer(
      id: 'trainer-demo-jung',
      gymId: '11621774', // 휘트니스에이든
      name: '정트레이너',
      role: '퍼스널 트레이너',
      reason: '감량 정체기 식사·운동량 재조정',
      career: '6년',
      intro:
          '체중이 멈춘 시점에 식사량과 운동량을 다시 맞추는 일을 자주 합니다. '
          '몸무게보다 둘레와 체성분 변화를 기준으로 판단합니다.',
      certifications: <String>['생활스포츠지도사 2급'],
    ),
    Trainer(
      id: 'trainer-demo-ha',
      gymId: '11621774',
      name: '하트레이너',
      role: '체형 교정 트레이너',
      reason: '장시간 착석형 목·어깨 교정',
      career: '4년',
      intro:
          '오래 앉아 생긴 목과 어깨 불편을 주로 다룹니다. 스트레칭과 가벼운 근력 '
          '운동을 번갈아 배치해 한 시간을 구성합니다.',
      certifications: <String>['필라테스 지도자', '생활스포츠지도사 2급'],
    ),
    Trainer(
      id: 'trainer-demo-han',
      gymId: '1558845892', // 하이핏
      name: '한트레이너',
      role: '퍼스널 트레이너',
      reason: '기구 입문자 눈높이 지도',
      career: '3년',
      intro:
          '기구 사용법부터 하나씩 익히는 수업입니다. 무게를 올리기 전에 자세가 '
          '자리를 잡을 때까지 시간을 들입니다.',
      certifications: <String>['퍼스널트레이닝 CPT'],
    ),
    Trainer(
      id: 'trainer-demo-oh',
      gymId: '1558845892',
      name: '오트레이너',
      role: '그룹 PT 트레이너',
      reason: '3~5인 그룹 수업 출석 관리',
      career: '5년',
      intro:
          '3~5인 그룹 수업을 맡습니다. 서로 속도를 맞추는 구성이라 혼자 할 때보다 '
          '출석이 안정적으로 유지됩니다.',
      certifications: <String>['생활스포츠지도사 2급'],
    ),
    Trainer(
      id: 'trainer-demo-seo',
      gymId: '328969863', // 빌드업짐 PT 신촌점
      name: '서트레이너',
      role: '재활 전문 트레이너',
      reason: '병원 재활 이후 복귀 단계 관리',
      career: '10년',
      intro:
          '병원 재활이 끝난 뒤 일상 운동으로 넘어가는 구간을 담당합니다. 통증 기록을 '
          '함께 남기며 주 단위로 강도를 조절합니다.',
      certifications: <String>['물리치료사', '건강운동관리사'],
    ),
    Trainer(
      id: 'trainer-demo-nam',
      gymId: '328969863',
      name: '남트레이너',
      role: '퍼스널 트레이너',
      reason: '스쿼트·데드리프트 영상 자세 교정',
      career: '7년',
      intro:
          '스쿼트와 데드리프트 자세 교정을 주로 합니다. 수행 장면을 영상으로 남겨 '
          '회차별로 달라진 점을 함께 확인합니다.',
      certifications: <String>['퍼스널트레이닝 CPT'],
    ),
    Trainer(
      id: 'trainer-demo-moon',
      gymId: '696444256', // 신인규피티스튜디오
      name: '문트레이너',
      role: '퍼스널 트레이너',
      reason: '주간 식단 기록 점검',
      career: '7년',
      intro:
          '1:1 수업만 진행합니다. 매주 식사 기록을 함께 보고 다음 주에 바꿀 항목을 '
          '한 가지씩 정합니다.',
      certifications: <String>['스포츠 영양사', '생활스포츠지도사 2급'],
    ),
    Trainer(
      id: 'trainer-demo-bae',
      gymId: '696444256',
      name: '배트레이너',
      role: '러닝 코치',
      reason: '무릎 부담 적은 러닝 자세 교정',
      career: '5년',
      intro:
          '달리기 자세와 호흡을 함께 점검합니다. 무릎에 부담이 덜 가는 보폭을 찾는 '
          '데 수업 시간을 많이 배정합니다.',
      certifications: <String>['생활스포츠지도사 2급'],
    ),
  ];

  @override
  Future<Gym?> fetchMyGym() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (_myGymId == null) return null;
    return _gyms.where((Gym gym) => gym.id == _myGymId).firstOrNull;
  }

  @override
  Future<List<Gym>> fetchNearby() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return _gyms;
  }

  @override
  Future<void> disconnectMyGym() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // 헬스장을 떠나면 그곳 소속 트레이너 연결도 함께 사라진다.
    _myGymId = null;
    _myTrainerId = null;
  }

  @override
  Future<Trainer?> fetchMyTrainer() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (_myTrainerId == null) return null;
    return _trainers
        .where((Trainer trainer) => trainer.id == _myTrainerId)
        .firstOrNull;
  }

  @override
  Future<List<Trainer>> fetchTrainersByGym(String gymId) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return _trainers
        .where((Trainer trainer) => trainer.gymId == gymId)
        .toList(growable: false);
  }

  @override
  Future<List<Trainer>> fetchAllTrainers() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return _trainers;
  }

  @override
  Future<Trainer?> fetchTrainer(String trainerId) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return _trainers
        .where((Trainer trainer) => trainer.id == trainerId)
        .firstOrNull;
  }

  @override
  Future<List<Trainer>> fetchRecommendedTrainers() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    // 추천 사유가 붙은 트레이너만 레일에 올린다.
    return _trainers
        .where((Trainer trainer) => trainer.reason?.isNotEmpty ?? false)
        .toList(growable: false);
  }

  @override
  Future<void> disconnectMyTrainer() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // 헬스장 연결은 그대로 두고 담당 트레이너만 뗀다.
    _myTrainerId = null;
  }

  // ── 예약 슬롯 ──────────────────────────────────────────────────────────
  //
  // 슬롯은 트레이너마다 다르다. 시각은 저장소를 만든 시점의 "오늘"을 기준으로
  // 잡아, 화면에 실제 날짜가 뜨고 날이 바뀌어도 문구가 어긋나지 않는다.
  // 예약 결과는 이 인스턴스에 남으므로 화면을 나갔다 와도 유지된다.
  late final List<TrainerSlot> _slots = _seedSlots();

  static DateTime _at(DateTime day, int addDays, int hour, int minute) {
    return DateTime(day.year, day.month, day.day + addDays, hour, minute);
  }

  static List<TrainerSlot> _seedSlots() {
    final DateTime today = nowKst();
    return <TrainerSlot>[
      // 오늘 자리는 데모에서 "가까운 시간"을 보여주려고 둔다. 저녁에 앱을 켜면
      // 이미 지나 목록에서 빠지므로, 트레이너마다 내일 이후 자리를 함께 둬서
      // 어느 시각에 열어도 예약할 수 있는 자리가 남는다.
      //
      // 슬롯은 늘 한 사람 몫이다(#1012) — 정원은 언제나 1. 종류(1:1 PT/상담)
      // 는 트레이너가 열 때 고른다(#1083). 상담 자리도 여기 섞어 둬야 회원
      // 헬스장 탭의 "희망 시간대" 목록에서 상담도 고를 수 있는지 볼 수 있다.
      TrainerSlot(
        id: 'slot-kim-today',
        trainerId: 'trainer-kim',
        startsAt: _at(today, 0, 19, 0),
        booked: false,
        sessionType: '1:1 PT',
      ),
      TrainerSlot(
        id: 'slot-kim-1',
        trainerId: 'trainer-kim',
        startsAt: _at(today, 1, 7, 30),
        booked: false,
        sessionType: '1:1 PT',
      ),
      TrainerSlot(
        id: 'slot-kim-2',
        trainerId: 'trainer-kim',
        // 마감된 자리도 남겨 두어야 "그날은 꽉 찼다"가 읽힌다.
        startsAt: _at(today, 1, 20, 0),
        booked: true,
        sessionType: '1:1 PT',
      ),
      TrainerSlot(
        id: 'slot-kim-3',
        trainerId: 'trainer-kim',
        startsAt: _at(today, 2, 18, 0),
        booked: false,
        sessionType: '상담',
      ),
      // 박트레이너 — 재활 세션이라 1:1, 낮 시간대.
      TrainerSlot(
        id: 'slot-park-today',
        trainerId: 'trainer-park',
        startsAt: _at(today, 0, 14, 0),
        booked: false,
        sessionType: '1:1 PT',
      ),
      TrainerSlot(
        id: 'slot-park-1',
        trainerId: 'trainer-park',
        startsAt: _at(today, 1, 11, 0),
        booked: false,
        sessionType: '상담',
      ),
      TrainerSlot(
        id: 'slot-park-2',
        trainerId: 'trainer-park',
        startsAt: _at(today, 2, 15, 0),
        booked: false,
        sessionType: '1:1 PT',
      ),
      TrainerSlot(
        id: 'slot-choi-1',
        trainerId: 'trainer-choi',
        startsAt: _at(today, 1, 18, 30),
        booked: false,
        sessionType: '1:1 PT',
      ),
      // 강트레이너 — 교대근무 대응이라 이른 아침·늦은 밤.
      TrainerSlot(
        id: 'slot-kang-today',
        trainerId: 'trainer-kang',
        startsAt: _at(today, 0, 6, 0),
        booked: false,
        sessionType: '1:1 PT',
      ),
      TrainerSlot(
        id: 'slot-kang-1',
        trainerId: 'trainer-kang',
        startsAt: _at(today, 1, 22, 0),
        booked: false,
        sessionType: '1:1 PT',
      ),
      TrainerSlot(
        id: 'slot-lee-1',
        trainerId: 'trainer-lee',
        startsAt: _at(today, 2, 10, 0),
        booked: false,
        sessionType: '1:1 PT',
      ),
      // 윤트레이너는 슬롯이 없다 — 빈 상태를 데모에서도 볼 수 있어야 한다.
    ];
  }

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // 이미 지난 시간은 보여주지 않는다 — 저녁에 앱을 켰을 때 오늘 아침 자리가
    // "예약 가능"으로 뜨면 안 된다.
    final DateTime now = nowKst();
    final List<TrainerSlot> mine =
        _slots
            .where(
              (TrainerSlot slot) =>
                  slot.trainerId == trainerId && slot.startsAt.isAfter(now),
            )
            .toList()
          ..sort(
            (TrainerSlot a, TrainerSlot b) => a.startsAt.compareTo(b.startsAt),
          );
    return List<TrainerSlot>.unmodifiable(mine);
  }

  @override
  Future<void> reserve(String slotId) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final int i = _slots.indexWhere((TrainerSlot slot) => slot.id == slotId);
    if (i < 0) {
      throw StateError('slot not found: $slotId');
    }
    if (_slots[i].booked) {
      throw StateError('slot already booked: $slotId');
    }
    // 목록에서 이미 빠진 시간을 오래된 화면이 그대로 잡는 것도 막는다.
    if (!_slots[i].startsAt.isAfter(nowKst())) {
      throw StateError('slot already started: $slotId');
    }
    _slots[i] = _slots[i].copyWith(booked: true);
    _reservations.add(
      MyReservation(
        // 데모는 서버가 없으니 슬롯 id 로 결정론적 id 를 만든다 — 취소가 어느
        // 예약을 가리키는지 화면과 저장소가 같은 값을 본다.
        id: 'res-$slotId',
        slotId: slotId,
        trainerId: _slots[i].trainerId,
        startsAt: _slots[i].startsAt,
        cancellable: true,
      ),
    );
  }

  /// 데모에서 잡아 둔 예약. 인스턴스에 남으므로 화면을 나갔다 와도 유지된다.
  final List<MyReservation> _reservations = <MyReservation>[];

  @override
  Future<List<MyReservation>> fetchMyReservations({
    int limit = reservationPageSize,
    DateTime? before,
    String? beforeId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    // 서버와 같은 순서·상한을 흉내 낸다(#980) — 데모에서만 순서가 다르면 패널이
    // 실모드와 다르게 보인다. 데모 예약은 한 줌이라 커서가 실제로 쓰이지는 않는다.
    final List<MyReservation> ordered = <MyReservation>[..._reservations]
      ..sort(
        (MyReservation a, MyReservation b) => b.startsAt.compareTo(a.startsAt),
      );
    final Iterable<MyReservation> page = before == null
        ? ordered
        : ordered.where(
            (MyReservation r) =>
                r.startsAt.isBefore(before) ||
                (r.startsAt == before &&
                    beforeId != null &&
                    r.id.compareTo(beforeId) < 0),
          );
    return List<MyReservation>.unmodifiable(page.take(limit));
  }

  @override
  Future<void> cancelReservation(String reservationId) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final int i = _reservations.indexWhere(
      (MyReservation r) => r.id == reservationId,
    );
    if (i < 0) {
      throw StateError('reservation not found: $reservationId');
    }
    final MyReservation reservation = _reservations[i];
    if (!reservation.startsAt.isAfter(nowKst())) {
      throw StateError('reservation no longer cancellable: $reservationId');
    }
    // 자리를 다시 연다 — 실서버와 같은 결과가 화면에 보여야 한다.
    final int s = _slots.indexWhere(
      (TrainerSlot slot) => slot.id == reservation.slotId,
    );
    if (s >= 0) {
      _slots[s] = _slots[s].copyWith(booked: false);
    }
    _reservations.removeAt(i);
  }
}
