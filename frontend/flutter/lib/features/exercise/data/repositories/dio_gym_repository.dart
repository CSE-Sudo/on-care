import 'package:dio/dio.dart';

import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/gym_search_area.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';

/// 헬스장·트레이너 디렉터리 실 API. (#324)
///
/// 회원의 "내 헬스장"과 "내 트레이너"는 서버에서도 각각의 링크다 — 헬스장은
/// `GET /me/gym`, 담당 트레이너는 `GET /me/coach`. 그래서 트레이너만 해제해도
/// 헬스장 카드는 남는다(#444).
class DioGymRepository implements GymRepository {
  DioGymRepository(this._dio);
  final Dio _dio;

  static Gym _gym(Map<String, Object?> j) => Gym(
    id: j['id']! as String,
    name: j['name']! as String,
    address: (j['address'] as String?) ?? '',
    distanceKm: ((j['distance_km'] as num?) ?? 0).toDouble(),
    rating: ((j['rating'] as num?) ?? 0).toDouble(),
    tags: <String>[...?(j['tags'] as List<Object?>?)?.cast<String>()],
    weekdayHours: j['weekday_hours'] as String?,
    weekendHours: j['weekend_hours'] as String?,
    phone: j['phone'] as String?,
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
  );

  static TrainerSlot _slot(Map<String, Object?> j) => trainerSlotFromJson(j);

  /// 추천 사유. 서버는 아직 `reason` 한 칸에 문자열 하나를 담아 보내지만,
  /// 앱은 여러 개를 그린다(#1881). 계약이 배열로 넓어지기 전까지 양쪽을 다
  /// 읽는다 — 문자열이면 한 칸짜리 목록으로, 배열이면 그대로.
  static List<String> _reasons(Object? raw) => switch (raw) {
    final List<Object?> many => <String>[
      for (final Object? one in many)
        if (one is String && one.isNotEmpty) one,
    ],
    final String one when one.isNotEmpty => <String>[one],
    _ => const <String>[],
  };

  static Trainer _trainer(Map<String, Object?> j) => Trainer(
    id: j['id']! as String,
    gymId: (j['gym_id'] as String?) ?? '',
    name: j['name']! as String,
    role: j['role'] as String?,
    reasons: _reasons(j['reason']),
    career: j['career'] as String?,
    intro: j['intro'] as String?,
    certifications: <String>[
      ...?(j['certifications'] as List<Object?>?)?.cast<String>(),
    ],
  );

  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, Object?>) map, {
    Map<String, Object?>? query,
  }) async {
    final res = await _dio.get<List<Object?>>(path, queryParameters: query);
    return (res.data ?? const <Object?>[])
        .cast<Map<String, Object?>>()
        .map(map)
        .toList();
  }

  /// 담당 트레이너 요약. 담당이 없으면 서버가 404 를 주므로 null 로 바꾼다.
  Future<Map<String, Object?>?> _coach() async {
    try {
      final res = await _dio.get<Map<String, Object?>>('/me/coach');
      return res.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<Gym>> fetchNearby() => _list(
    '/gyms',
    _gym,
    query: <String, Object?>{'lat': kGymSearchLat, 'lng': kGymSearchLng},
  );

  @override
  Future<List<Trainer>> fetchTrainersByGym(String gymId) =>
      _list('/gyms/$gymId/trainers', _trainer);

  @override
  Future<List<Trainer>> fetchAllTrainers() => _list('/trainers', _trainer);

  @override
  Future<List<Trainer>> fetchRecommendedTrainers() =>
      _list('/trainers/recommended', _trainer);

  @override
  Future<Trainer?> fetchTrainer(String trainerId) async {
    try {
      final res = await _dio.get<Map<String, Object?>>('/trainers/$trainerId');
      return res.data == null ? null : _trainer(res.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<Gym?> fetchMyGym() async {
    // 담당 트레이너를 거치지 않는다 — 트레이너만 해제한 회원은 `/me/coach` 가
    // 404 여도 헬스장은 남아 있어야 한다(#444). 응답이 목록·상세와 같은 형태라
    // 상세를 한 번 더 읽을 필요도 없다.
    try {
      final res = await _dio.get<Map<String, Object?>>(
        '/me/gym',
        queryParameters: <String, Object?>{
          'lat': kGymSearchLat,
          'lng': kGymSearchLng,
        },
      );
      if (res.data != null) return _gym(res.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }
    return null;
  }

  @override
  Future<Trainer?> fetchMyTrainer() async {
    final coach = await _coach();
    final trainerId = coach?['trainer_id'] as String?;
    if (trainerId == null) return null;
    // 요약에는 자격증·추천 사유가 없어 상세를 읽는다.
    return fetchTrainer(trainerId);
  }

  /// 헬스장과 그곳 담당 트레이너를 함께 끊는다 — 떠난 헬스장의 트레이너를 담당으로
  /// 남길 수 없다. mock 과 같은 규칙이다.
  @override
  Future<void> disconnectMyGym() => _dio.delete<void>('/me/coach');

  @override
  Future<void> disconnectMyTrainer() => _dio.delete<void>('/me/coach/trainer');

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) =>
      _list('/trainers/$trainerId/slots', _slot);

  @override
  Future<List<MyReservation>> fetchMyReservations({
    int limit = reservationPageSize,
    DateTime? before,
    String? beforeId,
  }) => _list(
    '/reservations/me',
    MyReservation.fromJson,
    query: <String, Object?>{
      'limit': limit,
      // 커서는 서버가 준 시각 그대로여야 한다 — 엔티티는 화면용으로 로컬 시각을
      // 들고 있으므로 UTC 로 되돌려 보낸다.
      if (before != null) 'before': before.toUtc().toIso8601String(),
      'before_id': ?beforeId,
    },
  );

  @override
  Future<void> cancelReservation(String reservationId) async {
    try {
      await _dio.delete<void>('/reservations/$reservationId');
    } on DioException catch (e) {
      // 예약과 같은 규칙: 없음(남의 것 포함)·이미 시작함을 StateError 로 옮겨
      // 목과 실서버가 같은 예외를 내게 한다.
      final int? code = e.response?.statusCode;
      if (code == 404) {
        throw StateError('reservation not found: $reservationId');
      }
      if (code == 409) {
        throw StateError('reservation no longer cancellable: $reservationId');
      }
      rethrow;
    }
  }

  @override
  Future<void> reserve(String slotId) async {
    try {
      await _dio.post<void>(
        '/reservations',
        data: <String, Object?>{'slot_id': slotId},
      );
    } on DioException catch (e) {
      // 도메인 계약(GymRepository.reserve)은 "없음/마감"을 StateError 로
      // 정의한다. 목과 실서버가 같은 예외를 내야 호출자가 한 갈래만 다룬다.
      final int? code = e.response?.statusCode;
      if (code == 404) {
        throw StateError('slot not found: $slotId');
      }
      if (code == 409 || code == 410) {
        throw StateError('slot no longer bookable: $slotId');
      }
      rethrow;
    }
  }
}
