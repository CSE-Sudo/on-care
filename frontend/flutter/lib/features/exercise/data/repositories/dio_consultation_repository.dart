import 'package:dio/dio.dart';

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
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
/// 나가지 않는다. 중복 판정은 컨트롤러의 `hasPending` 이 이미 하므로 여기선 id 만
/// 만들어 준다.
class MockConsultationRepository implements ConsultationRepository {
  const MockConsultationRepository(this._gyms);

  /// 자리는 목 헬스장 저장소가 들고 있다 — 헬스장 탭의 예약 가능 시간과 상담 폼이
  /// **같은 자리**를 봐야 데모가 앞뒤로 맞는다. (#1873)
  final GymRepository _gyms;

  /// 빈 id 를 돌려 화면이 만든 id 를 그대로 쓰게 한다 — 데모에는 서버가 없으므로
  /// 서버 id 로 갈아끼울 것이 없다.
  ///
  /// 인위적 지연도 두지 않는다. 이전 구현이 동기였어서 데모 체감이 같아야 하고,
  /// `testWidgets` 의 가짜 시간대에서는 `Future.delayed` 가 펌프 없이는 끝나지 않아
  /// 위젯 테스트가 멈춘다.
  @override
  Future<String> create(ConsultationDraft draft) async => '';

  /// 데모에는 서버가 없으므로 복원할 것도 없다.
  @override
  Future<List<ConsultationRequest>> fetchMine({
    int limit = consultationPageSize,
  }) async => const <ConsultationRequest>[];

  @override
  Future<void> cancel(String consultationId) async {}

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
