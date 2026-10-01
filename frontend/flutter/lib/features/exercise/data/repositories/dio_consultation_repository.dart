import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';

class DioConsultationRepository implements ConsultationRepository {
  DioConsultationRepository(this._dio);
  final Dio _dio;

  @override
  Future<String> create(ConsultationDraft draft) async {
    try {
      final res = await _dio.post<Map<String, Object?>>(
        '/consultations',
        data: draft.toJson(),
      );
      final id = res.data?['id'];
      // 빈 id 를 성공으로 넘기면 컨트롤러가 데모 응답으로 보고 화면이 만든 임시
      // id 를 유지한다 — 서버에 생긴 상담과 화면의 상담이 영영 이어지지 않는다.
      if (id is! String || id.isEmpty) {
        throw StateError('상담 접수 응답에 id 가 없습니다: ${res.data}');
      }
      return id;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // 409 는 두 가지다. 고른 자리를 잡지 못한 경우는 서버가 `detail.code` 로
        // 밝힌다(#1873) — 그때는 다른 자리를 고르게 해야 한다.
        final Object? detail = switch (e.response?.data) {
          final Map<String, Object?> body => body['detail'],
          _ => null,
        };
        if (detail is Map && detail['code'] == 'slot_unavailable') {
          throw const ConsultationSlotTaken();
        }
        // 답을 기다리는 요청이 상한에 닿았다(#1628). 이 트레이너에게는 신청한 적이
        // 없으므로 "이미 대기 중" 으로 읽으면 안 된다.
        if (detail is Map && detail['code'] == 'too_many_pending') {
          final Object? limit = detail['limit'];
          throw TooManyPendingConsultations(
            limit: limit is int && limit > 0 ? limit : null,
          );
        }
        // 담당 트레이너가 따로 있다(#2611). 역시 이 트레이너에게는 신청한 적이 없다.
        if (detail is Map && detail['code'] == 'linked_to_other_trainer') {
          throw const ConsultationLinkedToOtherTrainer();
        }
        // 나머지 409 는 오류가 아니라 "이미 신청함" 상태다 — 화면이 오류 대신
        // 기존 신청을 보여줘야 한다.
        throw const DuplicatePendingConsultation();
      }
      if (e.response?.statusCode == 429) {
        // 24시간 신청 한도(#1628). 다시 신청할 수 있는 시점은 헤더가 알려 준다.
        final int? seconds = int.tryParse(
          e.response?.headers.value('retry-after') ?? '',
        );
        throw ConsultationRateLimited(
          retryAfter: seconds == null ? null : Duration(seconds: seconds),
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<ConsultationRequest>> fetchMine({
    int limit = consultationPageSize,
  }) async {
    final res = await _dio.get<List<Object?>>(
      '/consultations/me',
      queryParameters: <String, Object?>{'limit': limit},
    );
    return (res.data ?? const <Object?>[])
        .cast<Map<String, Object?>>()
        .map(consultationFromJson)
        .toList();
  }

  @override
  Future<void> cancel(String consultationId) async {
    await _dio.delete<void>('/consultations/$consultationId');
  }

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async {
    final res = await _dio.get<List<Object?>>(
      '/consultations/slots',
      queryParameters: <String, Object?>{'trainer_id': trainerId},
    );
    return (res.data ?? const <Object?>[])
        .cast<Map<String, Object?>>()
        .map(trainerSlotFromJson)
        .toList();
  }
}

/// 데모용. `LocalApiInterceptor` 에 `/consultations` 핸들러가 없어 데모에서는 서버로
/// 나가지 않는다. 대신 이 대역이 서버가 하던 일을 메모리에서 한다(#2659) — 낸
/// 신청을 들고 있다가 돌려주고, 고른 자리를 잠그고, 취소하면 푼다.
class MockConsultationRepository implements ConsultationRepository {
  MockConsultationRepository(this._gyms);

  /// 자리는 목 헬스장 저장소가 들고 있다 — 헬스장 탭의 예약 가능 시간과 상담 폼이
  /// **같은 자리**를 봐야 데모가 앞뒤로 맞는다. (#1873)
  final GymRepository _gyms;

  /// 이번 세션에 낸 신청 — 최신이 앞. 실서버의 `GET /consultations/me` 순서다.
  final List<ConsultationRequest> _mine = <ConsultationRequest>[];

  /// 신청 id → 그 신청이 잡은 자리. 취소할 때 무엇을 풀지 알아야 한다.
  final Map<String, String> _slotOf = <String, String>{};
  int _seq = 0;

  /// 목 헬스장 저장소일 때만 자리를 잠그고 이름을 채운다. 테스트가 다른 대역을
  /// 끼우면 신청만 남는다 — 화면이 죽는 것보다 낫다.
  MockGymRepository? get _mockGyms => switch (_gyms) {
    final MockGymRepository gyms => gyms,
    _ => null,
  };

  /// 신청을 남기고 고른 자리를 잠근 뒤 id 를 돌려준다(#2659).
  ///
  /// 예전에는 빈 id 만 돌려주고 아무것도 남기지 않아, 화면을 새로 읽으면 대기
  /// 상태가 사라지고 자리도 헬스장 탭에서 계속 비어 보였다. 실서버처럼 같은
  /// 트레이너에게 이미 대기 중이면 [DuplicatePendingConsultation], 자리가 찼거나
  /// 지났으면 [ConsultationSlotTaken] 이다.
  ///
  /// 인위적 지연은 두지 않는다. `testWidgets` 의 가짜 시간대에서는
  /// `Future.delayed` 가 펌프 없이는 끝나지 않아 위젯 테스트가 멈춘다. 같은
  /// 까닭으로 헬스장 저장소도 기다리지 않는 조회만 쓴다.
  @override
  Future<String> create(ConsultationDraft draft) async {
    if (_mine.any(
      (ConsultationRequest r) => r.trainerId == draft.trainerId && r.isPending,
    )) {
      throw const DuplicatePendingConsultation();
    }
    final MockGymRepository? gyms = _mockGyms;
    final DateTime now = nowKst();
    final TrainerSlot? slot = gyms?.slotById(draft.slotId);
    if (slot != null) {
      if (slot.booked || !slot.startsAt.isAfter(now)) {
        throw const ConsultationSlotTaken();
      }
      gyms!.setSlotBooked(slot.id, booked: true);
    }
    final Trainer? trainer = gyms?.trainerById(draft.trainerId);
    final String id = 'demo-consultation-${++_seq}';
    if (slot != null) _slotOf[id] = slot.id;
    _mine.insert(
      0,
      ConsultationRequest(
        id: id,
        trainerId: draft.trainerId,
        trainerName: trainer?.name,
        trainerRole: trainer?.role,
        trainerGymName: trainer == null ? null : gyms!.gymNameOf(trainer.gymId),
        exerciseGoal: draft.exerciseGoal,
        healthPurposeType: draft.healthPurposeType,
        healthPurposeDetail: draft.healthPurposeDetail,
        // 서버처럼 고른 자리의 시각을 옮겨 적는다 — 상담 폼이 만드는 표시값과 같다.
        preferredDate: slot?.startsAt ?? now,
        preferredTimeSlot: slot == null
            ? const PreferredTime.flexible()
            : PreferredTime.at(TimeOfDay.fromDateTime(slot.startsAt)),
        slotStartsAt: slot?.startsAt,
        slotDurationMinutes: slot?.durationMinutes,
        message: draft.message,
        status: ConsultationStatus.pending,
        createdAt: now,
      ),
    );
    return id;
  }

  /// 이번 세션에 낸 신청. 앱을 새로 켜면 사라진다 — 데모의 다른 기록과 같다.
  @override
  Future<List<ConsultationRequest>> fetchMine({
    int limit = consultationPageSize,
  }) async => List<ConsultationRequest>.unmodifiable(_mine.take(limit));

  /// 대기 중인 신청을 취소하고 잡아 둔 자리를 푼다. 실서버처럼 대기 중이 아니면
  /// 취소할 수 없다.
  @override
  Future<void> cancel(String consultationId) async {
    final int i = _mine.indexWhere(
      (ConsultationRequest r) => r.id == consultationId,
    );
    if (i < 0) throw StateError('consultation not found: $consultationId');
    if (!_mine[i].isPending) {
      throw StateError('consultation not pending: $consultationId');
    }
    _mine[i] = _mine[i].copyWith(status: ConsultationStatus.cancelled);
    final String? slotId = _slotOf.remove(consultationId);
    if (slotId != null) _mockGyms?.setSlotBooked(slotId, booked: false);
  }

  /// 서버 `GET /consultations/slots` 와 같은 조건으로 거른다 — `1:1 PT` 이고,
  /// 비어 있고, 시작까지 [kConsultationSlotMinLead] 이상 남은 자리만.
  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async {
    final DateTime cutoff = nowKst().add(kConsultationSlotMinLead);
    final List<TrainerSlot> slots = await _gyms.fetchSlots(trainerId);
    return <TrainerSlot>[
      for (final TrainerSlot slot in slots)
        if (!slot.booked &&
            slot.sessionType == kConsultationSessionType &&
            slot.startsAt.isAfter(cutoff))
          slot,
    ];
  }
}
