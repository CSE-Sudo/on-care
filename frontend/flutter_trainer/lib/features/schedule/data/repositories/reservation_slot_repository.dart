import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/active_polling_stream.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/data/demo_reservation_slots.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/reservation_slot.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
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

  /// 자리의 시간이 다른 일정과 겹치면 `ScheduleOverlapError` 로 멈춘다
  /// (#2284). [update] 도 같다.
  ///
  /// [startsAt] 은 **KST 벽시계 값**이다(`nowKst()` 와 같은 모양) — 기기
  /// 시간대와 관계없이 서울 시각으로 저장된다(#2759).
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

  /// 시간 겹침 409 는 겹친 일정을 짚어 줄 수 있게 타입 있는 오류로 바꾸고
  /// (#2284), 그 밖의 실패는 지금처럼 그대로 올린다 — 화면이 서버 문구를
  /// 읽는 경로(`serverDetailOr`)를 바꾸지 않는다.
  Future<Response<Map<String, dynamic>>> _write(
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      final overlap = scheduleOverlapFromResponse(
        e.response?.statusCode,
        e.response?.data,
      );
      if (overlap != null) throw overlap;
      rethrow;
    }
  }

  @override
  Future<ReservationSlot> create({
    required DateTime startsAt,
    int durationMinutes = 60,
    required String sessionType,
  }) async {
    final response = await _write(
      () => _dio.post<Map<String, dynamic>>(
        '/trainer/reservation-slots',
        data: <String, dynamic>{
          // KST 벽시계 값이다 — `toUtc()` 는 브라우저 시간대로 읽어 KST 가
          // 아닌 기기에서 다른 시각으로 저장됐다(#2759).
          'starts_at': kstWallToUtc(startsAt).toIso8601String(),
          'duration_minutes': durationMinutes,
          'session_type': sessionType,
        },
      ),
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
    final response = await _write(
      () => _dio.put<Map<String, dynamic>>(
        '/trainer/reservation-slots/$id',
        data: <String, dynamic>{
          'starts_at': ?switch (startsAt) {
            final DateTime at => kstWallToUtc(at).toIso8601String(),
            null => null,
          },
          'duration_minutes': ?durationMinutes,
          'session_type': ?sessionType,
        },
      ),
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
  /// [seed] 는 처음부터 열려 있는 자리다. 기본은 빈 목록 — 앱의 목업 모드만
  /// 데모 자리([demoReservationSlots])를 넣어 만든다.
  ///
  /// [db] 가 있으면 트레이너가 열고 고치고 닫은 자리를 키-값 저장소에 적어
  /// 두고 다시 읽는다(#2669) — 예전에는 메모리뿐이라 새로고침하면 사라졌다.
  /// 시드 자리는 "오늘" 기준으로 매번 새로 만들고, 그 위에 저장해 둔 자리를
  /// id 로 덮어 얹는다. 없으면(단위 테스트) 메모리에만 둔다.
  MockReservationSlotRepository({
    Iterable<ReservationSlot> seed = const <ReservationSlot>[],
    this.db,
  }) : _slots = <ReservationSlot>[...seed];

  final List<ReservationSlot> _slots;

  /// 바꾼 자리를 적어 두는 데모 저장소.
  final AppDatabase? db;

  /// 트레이너가 바꾼 자리 — id 로 찾는다. 저장소에 적는 것은 이것뿐이다.
  final Map<String, ReservationSlot> _changed = <String, ReservationSlot>{};
  bool _restored = false;

  /// 바꾼 자리를 적어 두는 키.
  static const String storageKey = 'demo_reservation_slots';

  Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    final String? saved = await db?.readValue(storageKey);
    if (saved == null) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(saved);
    } on FormatException {
      return;
    }
    if (decoded is! List) return;
    for (final Object? item in decoded) {
      if (item is! Map<String, Object?>) continue;
      final Object? id = item['id'];
      final DateTime? startsAt = DateTime.tryParse(
        item['starts_at'] as String? ?? '',
      );
      if (id is! String || startsAt == null) continue;
      _remember(
        ReservationSlot(
          id: id,
          startsAt: startsAt,
          durationMinutes: (item['duration_minutes'] as num?)?.toInt() ?? 60,
          booked: item['booked'] == true,
          isClosed: item['is_closed'] == true,
          sessionType:
              item['session_type'] as String? ?? SessionType.personalTraining,
        ),
      );
    }
  }

  /// [slot] 을 목록에 넣거나 같은 id 를 바꾼다.
  void _remember(ReservationSlot slot) {
    _changed[slot.id] = slot;
    final int index = _slots.indexWhere((s) => s.id == slot.id);
    if (index < 0) {
      _slots.add(slot);
    } else {
      _slots[index] = slot;
    }
  }

  Future<void> _save(ReservationSlot slot) async {
    _remember(slot);
    await db?.putValue(
      storageKey,
      jsonEncode(<Object?>[
        for (final ReservationSlot s in _changed.values)
          <String, Object?>{
            'id': s.id,
            // 벽시계 그대로 적는다 — 읽을 때도 같은 벽시계로 돌아온다.
            'starts_at': s.startsAt.toIso8601String(),
            'duration_minutes': s.durationMinutes,
            'booked': s.booked,
            'is_closed': s.isClosed,
            'session_type': s.sessionType,
          },
      ]),
    );
  }

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
    await _restore();
    final now = nowKst();
    final List<ReservationSlot> upcoming =
        _slots.where((slot) => slot.startsAt.isAfter(now)).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return _againstSchedule(upcoming);
  }

  /// 데모 일정과 견준 자리 목록. (#2758, #2761)
  ///
  /// 서버는 자리 목록을 만들 때마다 그 시간의 일정을 본다 — 데모도 같은 답을
  /// 내도록 일정 저장소(drift)를 읽어 [judgeDemoSlot] 으로 판정한다. 자리를
  /// 바꿔 적지 않으므로 일정을 취소·이동하면 다음 조회에서 원래대로 돌아온다.
  /// [db] 가 없으면(단위 테스트) 그대로 둔다.
  Future<List<ReservationSlot>> _againstSchedule(
    List<ReservationSlot> slots,
  ) async {
    final AppDatabase? database = db;
    if (database == null || slots.isEmpty) return slots;
    final Set<String> days = <String>{
      for (final ReservationSlot slot in slots) ymd(slot.startsAt),
    };
    final rows =
        await (database.select(database.trainerScheduleEntries)..where(
              (t) =>
                  t.date.isIn(days) &
                  t.status.isIn(<String>[
                    ScheduleStatus.upcoming,
                    ScheduleStatus.done,
                  ]),
            ))
            .get();
    final List<DemoSlotSession> sessions = <DemoSlotSession>[
      for (final row in rows)
        (
          date: row.date,
          time: row.time,
          durationMinutes: row.durationMinutes,
          type: row.type,
          clientName: row.clientName,
        ),
    ];
    return <ReservationSlot>[
      for (final ReservationSlot slot in slots) judgeDemoSlot(slot, sessions),
    ];
  }

  @override
  Future<ReservationSlot> create({
    required DateTime startsAt,
    int durationMinutes = 60,
    required String sessionType,
  }) async {
    await _restore();
    _validateFuture(startsAt);
    // 슬롯은 늘 한 사람 몫이라 새로 연 자리는 비어 있는 상태로 시작한다
    // (#1012, #1072).
    final slot = ReservationSlot(
      id: 'slot-${DateTime.now().microsecondsSinceEpoch}',
      startsAt: startsAt,
      durationMinutes: durationMinutes,
      booked: false,
      isClosed: false,
      sessionType: sessionType,
    );
    await _save(slot);
    _bump();
    return slot;
  }

  @override
  Future<ReservationSlot> update(
    String id, {
    DateTime? startsAt,
    int? durationMinutes,
    String? sessionType,
  }) async {
    await _restore();
    final index = _slots.indexWhere((slot) => slot.id == id);
    if (index < 0) throw StateError('not_found');
    final old = _slots[index];
    if (startsAt != null) _validateFuture(startsAt);
    if (sessionType != null && sessionType != old.sessionType && old.booked) {
      throw StateError('type_locked_by_booking');
    }
    final updated = ReservationSlot(
      id: old.id,
      startsAt: startsAt ?? old.startsAt,
      durationMinutes: durationMinutes ?? old.durationMinutes,
      booked: old.booked,
      isClosed: old.isClosed,
      sessionType: sessionType ?? old.sessionType,
    );
    await _save(updated);
    _bump();
    return updated;
  }

  @override
  Future<ReservationSlot> close(String id) async {
    await _restore();
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
    await _save(closed);
    _bump();
    return closed;
  }
}

/// 데모 자리와 견줄 일정 한 건 — 시간을 차지하는(`예정`·`완료`) 것만 넘긴다.
typedef DemoSlotSession = ({
  String date,
  String time,
  int durationMinutes,
  String type,
  String clientName,
});

/// 데모 자리 하나를 그날 일정과 견준다. (#2758, #2761)
///
/// - 같은 시각에 시작하는 **상담** 일정은 그 자리로 신청해 수락된 상담이다 —
///   서버에서는 신청이 자리를 잠그고 그 회원 이름이 실린다. 데모도 예약된
///   자리로 그리고 이름을 단다. 그 상담을 취소하거나 옮기면 자리가 다시 빈다.
/// - 그 밖에 시간이 겹치는 일정이 있으면 [ReservationSlot.overlapped] 다 —
///   회원에게는 마감이다.
///
/// 닫혔거나 이미 예약된 자리는 그대로 둔다. 데모 일정은 같은 날만 본다 —
/// 자정을 넘기는 일정까지 따지는 것은 서버 몫이다(일정 저장소와 같은 규칙).
ReservationSlot judgeDemoSlot(
  ReservationSlot slot,
  Iterable<DemoSlotSession> sessions,
) {
  if (slot.isClosed || slot.booked) return slot;
  final String day = ymd(slot.startsAt);
  final String time =
      '${slot.startsAt.hour.toString().padLeft(2, '0')}:'
      '${slot.startsAt.minute.toString().padLeft(2, '0')}';
  DemoSlotSession? heldBy;
  var overlapped = false;
  for (final DemoSlotSession session in sessions) {
    if (session.date != day) continue;
    if (!timeRangesOverlap(
      session.time,
      session.durationMinutes,
      time,
      slot.durationMinutes,
    )) {
      continue;
    }
    if (session.type == SessionType.consultation && session.time == time) {
      heldBy ??= session;
    } else {
      overlapped = true;
    }
  }
  if (heldBy == null && !overlapped) return slot;
  return ReservationSlot(
    id: slot.id,
    startsAt: slot.startsAt,
    durationMinutes: slot.durationMinutes,
    booked: heldBy != null,
    isClosed: slot.isClosed,
    sessionType: slot.sessionType,
    bookedByName: heldBy?.clientName,
    overlapped: heldBy == null && overlapped,
  );
}

final reservationSlotRepositoryProvider = Provider<ReservationSlotRepository>((
  ref,
) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  final ReservationSlotRepository repository =
      ref.watch(appConfigProvider).useMockApi
      ? MockReservationSlotRepository(
          seed: demoReservationSlots(),
          db: ref.watch(appDatabaseProvider),
        )
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
