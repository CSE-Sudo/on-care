import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/exercise/data/repositories/dio_consultation_repository.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';

/// 한 경로에 정해 둔 상태 코드·본문을 돌려주는 어댑터.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({
    required this.status,
    required this.body,
    this.headers = const <String, List<String>>{},
  });

  final int status;
  final Object? body;
  final Map<String, List<String>> headers;
  final Map<String, Map<String, dynamic>> queries =
      <String, Map<String, dynamic>>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) async {
    queries[options.path] = Map<String, dynamic>.from(options.queryParameters);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioConsultationRepository _repo(_StubAdapter adapter) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
    ..httpClientAdapter = adapter;
  return DioConsultationRepository(dio);
}

const ConsultationDraft _draft = ConsultationDraft(
  trainerId: 'trainer-1',
  exerciseGoal: ExerciseGoal.fitness,
  healthPurposeType: HealthPurposeType.general,
  healthPurposeDetail: null,
  slotId: 'slot-1',
  message: null,
  dataSharingConsent: true,
);

void main() {
  group('상담 접수 409 는 둘로 갈린다 (#1873)', () {
    test('자리를 놓친 409 는 ConsultationSlotTaken 이다', () async {
      // 다른 회원이 먼저 그 자리를 골랐다. "이미 대기 중" 으로 읽으면 회원을
      // 대기 중으로 잘못 표시해 다른 자리로 다시 신청하는 길을 막는다.
      final repository = _repo(
        _StubAdapter(
          status: 409,
          body: <String, Object?>{
            'detail': <String, Object?>{
              'code': 'slot_unavailable',
              'message': '예약할 수 없는 시간입니다.',
            },
          },
        ),
      );

      expect(
        () => repository.create(_draft),
        throwsA(isA<ConsultationSlotTaken>()),
      );
    });

    test('대기 상한 409 는 TooManyPendingConsultations 다 (#1628)', () async {
      // 이 트레이너에게는 신청한 적이 없다. "이미 대기 중" 으로 읽으면 한도가 풀린
      // 뒤에도 그 트레이너에게 신청하지 못한다.
      final repository = _repo(
        _StubAdapter(
          status: 409,
          body: <String, Object?>{
            'detail': <String, Object?>{
              'code': 'too_many_pending',
              'message': '답을 기다리는 상담 요청이 이미 3건 있어요.',
              'limit': 3,
            },
          },
        ),
      );

      await expectLater(
        repository.create(_draft),
        throwsA(
          isA<TooManyPendingConsultations>().having(
            (TooManyPendingConsultations e) => e.limit,
            'limit',
            3,
          ),
        ),
      );
    });

    test('문자열 detail 409 는 예전처럼 이미 대기 중이다', () async {
      final repository = _repo(
        _StubAdapter(
          status: 409,
          body: <String, Object?>{'detail': '이미 대기 중인 상담 요청이 있습니다.'},
        ),
      );

      expect(
        () => repository.create(_draft),
        throwsA(isA<DuplicatePendingConsultation>()),
      );
    });
  });

  test('429 는 Retry-After 를 들고 ConsultationRateLimited 가 된다 (#1628)', () async {
    final repository = _repo(
      _StubAdapter(
        status: 429,
        body: <String, Object?>{
          'detail': <String, Object?>{
            'code': 'consultation_rate_limited',
            'message': '상담 신청이 너무 잦아요.',
            'limit': 10,
          },
        },
        headers: <String, List<String>>{
          'retry-after': <String>['3600'],
        },
      ),
    );

    await expectLater(
      repository.create(_draft),
      throwsA(
        isA<ConsultationRateLimited>().having(
          (ConsultationRateLimited e) => e.retryAfter,
          'retryAfter',
          const Duration(hours: 1),
        ),
      ),
    );
  });

  test('자리 목록은 그 트레이너로 걸러 읽는다 (#1873)', () async {
    final adapter = _StubAdapter(
      status: 200,
      body: <Object?>[
        <String, Object?>{
          'id': 'slot-1',
          'trainer_id': 'trainer-1',
          'starts_at': '2026-09-20T10:00:00Z',
          'duration_minutes': 30,
          'capacity': 1,
          'remaining': 1,
          'session_type': '1:1 PT',
        },
      ],
    );

    final List<TrainerSlot> slots = await _repo(
      adapter,
    ).fetchSlots('trainer-1');

    expect(adapter.queries['/consultations/slots'], <String, dynamic>{
      'trainer_id': 'trainer-1',
    });
    expect(slots.single.id, 'slot-1');
    // 길이는 자리가 들고 온 값이다 — 코드 상수 30분을 더하지 않는다.
    expect(slots.single.durationMinutes, 30);
    expect(slots.single.booked, isFalse);
  });
}
