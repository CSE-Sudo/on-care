import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/utils/active_polling_stream.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/reservation_slot.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

abstract interface class ReservationSlotRepository {
  Future<List<ReservationSlot>> list();

  /// 예약 슬롯 목록을 구독한다.
  ///
  /// 자리를 채우는 쪽은 **이 콘솔이 아니라 회원 앱**이다(#1590). 한 번 읽고
  /// 캐시해 두면 열려 있는 `예약 슬롯 관리` 는 회원이 잡아 간 자리를 계속
  /// 빈 자리로 보여 준다 — 트레이너가 이미 찬 시간에 다른 일정을 넣는다.
  /// 스케줄 탭이 회원 예약을 따라잡는 방식(`DioScheduleRepository._live`)과
  /// 같은 언어다.
  Stream<List<ReservationSlot>> watch();

  Future<ReservationSlot> create({
    required DateTime startsAt,
    int durationMinutes = 60,
    required String sessionType,
  });

  Future<ReservationSlot> update(
    String id, {
    DateTime? startsAt,
    int? durationMinutes,
    String? sessionType,
  });

  Future<ReservationSlot> close(String id);

  /// 구독 채널을 닫는다. 리포지토리를 만든 provider 가 부른다.
  void dispose();
}

class DioReservationSlotRepository implements ReservationSlotRepository {
  DioReservationSlotRepository(this._dio, {this.pollInterval = _pollInterval});

  /// 회원 예약을 따라잡는 주기. 스케줄 탭이 회원 앱의 예약·취소를 읽는 주기와
  /// 같다(`DioScheduleRepository.pollInterval`) — 같은 예약이 슬롯 목록과
  /// 시간표에 서로 다른 시점으로 나타나면 둘 중 무엇이 맞는지 알 수 없다.
  static const Duration _pollInterval = Duration(seconds: 5);

  final Dio _dio;
  final Duration pollInterval;

  /// 이 콘솔이 만든 변경을 기다리지 않고 바로 다시 읽게 하는 신호.
  final StreamController<void> _revisions = StreamController<void>.broadcast();

  @override
  Stream<List<ReservationSlot>> watch() =>
      activePollingStream<List<ReservationSlot>>(
        load: list,
        interval: pollInterval,
        refreshes: _revisions.stream,
      );

  void _bump() {
    if (!_revisions.isClosed) _revisions.add(null);
  }

  @override
  void dispose() => unawaited(_revisions.close());

  @override
  Future<List<ReservationSlot>> list() async {
    final response = await _dio.get<List<dynamic>>(
      '/trainer/reservation-slots',
    );
    return (response.data ?? const <dynamic>[])
        .map((item) => ReservationSlot.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ReservationSlot> create({
    required DateTime startsAt,
    int durationMinutes = 60,
    required String sessionType,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/trainer/reservation-slots',
      data: <String, dynamic>{
        'starts_at': startsAt.toUtc().toIso8601String(),
        'duration_minutes': durationMinutes,
        'session_type': sessionType,
      },
    );
    _bump();
    return ReservationSlot.fromJson(response.data!);
  }

  @override
  Future<ReservationSlot> update(
    String id, {
    DateTime? startsAt,
    int? durationMinutes,
    String? sessionType,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/trainer/reservation-slots/$id',
      data: <String, dynamic>{
        'starts_at': ?startsAt?.toUtc().toIso8601String(),
        'duration_minutes': ?durationMinutes,
        'session_type': ?sessionType,
      },
    );
    _bump();
    return ReservationSlot.fromJson(response.data!);
  }

  @override
  Future<ReservationSlot> close(String id) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/trainer/reservation-slots/$id',
    );
    _bump();
    return ReservationSlot.fromJson(response.data!);
  }
}

/// 목 리포지토리가 던지는 검증 코드. **문구가 아니다** — 리포지토리는 로케일을
/// 모르므로 화면이 이 코드로 자기 언어의 문구를 고른다. (#501)
class SlotErrorCodes {
  static const String futureOnly = 'future_only';
  static const String notFound = 'not_found';

  /// 이미 예약이 걸린 자리의 종류를 바꾸려 했다(#1083).
  static const String typeLockedByBooking = 'type_locked_by_booking';
}

class MockReservationSlotRepository implements ReservationSlotRepository {
  final List<ReservationSlot> _slots = <ReservationSlot>[];

  final StreamController<void> _revisions = StreamController<void>.broadcast();

  /// 데모에는 회원 앱이 없다 — 자리를 바꾸는 것은 이 화면뿐이라 주기적으로
  /// 다시 읽을 이유가 없고(`interval: null`), 이 화면의 변경만 흘려보낸다.
  @override
  Stream<List<ReservationSlot>> watch() =>
      activePollingStream<List<ReservationSlot>>(
        load: list,
        interval: null,
        refreshes: _revisions.stream,
      );

  void _bump() {
    if (!_revisions.isClosed) _revisions.add(null);
  }

  @override
  void dispose() => unawaited(_revisions.close());

  void _validateFuture(DateTime startsAt) {
    if (!startsAt.isAfter(nowKst())) {
      throw StateError('future_only');
    }
  }

  @override
  Future<List<ReservationSlot>> list() async {
    final now = nowKst();
    return _slots.where((slot) => slot.startsAt.isAfter(now)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  @override
  Future<ReservationSlot> create({
    required DateTime startsAt,
    int durationMinutes = 60,
    required String sessionType,
  }) async {
    _validateFuture(startsAt);
    // 슬롯은 늘 한 사람 몫이라 새로 연 자리는 비어 있는 상태로 시작한다
    // (#1012, #1072). 포인트 체험 자리는 서버와 같이 20분으로 고정한다(#1790).
    final slot = ReservationSlot(
      id: 'slot-${DateTime.now().microsecondsSinceEpoch}',
      startsAt: startsAt,
      durationMinutes: sessionType == SessionType.pointsTrial
          ? SessionType.pointsTrialMinutes
          : durationMinutes,
      booked: false,
      isClosed: false,
      sessionType: sessionType,
    );
    _slots.add(slot);
    _bump();
    return slot;
  }

  /// 종류를 바꿀 때 시간을 함께 주지 않았을 때의 기본 시간 — 서버
  /// `_SESSION_DURATION_MINUTES` 와 같다.
  static int _defaultMinutes(String sessionType) => switch (sessionType) {
    SessionType.consultation => 30,
    SessionType.pointsTrial => SessionType.pointsTrialMinutes,
    _ => 60,
  };

  @override
  Future<ReservationSlot> update(
    String id, {
    DateTime? startsAt,
    int? durationMinutes,
    String? sessionType,
  }) async {
    final index = _slots.indexWhere((slot) => slot.id == id);
    if (index < 0) throw StateError('not_found');
    final old = _slots[index];
    if (startsAt != null) _validateFuture(startsAt);
    if (sessionType != null && sessionType != old.sessionType && old.booked) {
      throw StateError('type_locked_by_booking');
    }
    final String nextType = sessionType ?? old.sessionType;
    // 서버와 같은 규칙 — 체험은 20분 고정, 체험에서 벗어나며 시간을 주지 않으면
    // 그 종류의 기본 시간으로 돌린다(#1790).
    final int nextMinutes = nextType == SessionType.pointsTrial
        ? SessionType.pointsTrialMinutes
        : durationMinutes ??
              (old.isPointsTrial
                  ? _defaultMinutes(nextType)
                  : old.durationMinutes);
    final updated = ReservationSlot(
      id: old.id,
      startsAt: startsAt ?? old.startsAt,
      durationMinutes: nextMinutes,
      booked: old.booked,
      isClosed: old.isClosed,
      sessionType: sessionType ?? old.sessionType,
    );
    _slots[index] = updated;
    _bump();
    return updated;
  }

  @override
  Future<ReservationSlot> close(String id) async {
    final index = _slots.indexWhere((slot) => slot.id == id);
    if (index < 0) throw StateError('not_found');
    final old = _slots[index];
    final closed = ReservationSlot(
      id: old.id,
      startsAt: old.startsAt,
      durationMinutes: old.durationMinutes,
      booked: old.booked,
      isClosed: true,
      sessionType: old.sessionType,
    );
    _slots[index] = closed;
    _bump();
    return closed;
  }
}

final reservationSlotRepositoryProvider = Provider<ReservationSlotRepository>((
  ref,
) {
  final ReservationSlotRepository repository =
      ref.watch(appConfigProvider).useMockApi
      ? MockReservationSlotRepository()
      : DioReservationSlotRepository(ref.watch(dioProvider));
  ref.onDispose(repository.dispose);
  return repository;
}, name: 'reservationSlotRepository');

/// 예약 슬롯 목록.
///
/// `autoDispose` 스트림인 것이 이 자리의 핵심이다(#1590). 예전에는 평범한
/// `FutureProvider` 라 앱이 살아 있는 동안 첫 응답을 그대로 들고 있었다 —
/// 회원이 잡아 간 자리가 반영되지 않았고, `예약 슬롯 관리` 모달을 닫았다
/// 다시 열어도 같은 목록이 나왔다. 이제 마지막 구독자가 사라지면 버려지므로
/// 모달을 열 때마다 새로 읽고, 열려 있는 동안에는 스트림이 따라잡는다.
final reservationSlotsProvider =
    StreamProvider.autoDispose<List<ReservationSlot>>((ref) {
      return ref.watch(reservationSlotRepositoryProvider).watch();
    }, name: 'reservationSlots');
