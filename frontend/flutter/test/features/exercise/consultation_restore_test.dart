import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';

/// `GET /consultations/me` 실응답 한 건.
const Map<String, Object?> _serverRow = <String, Object?>{
  'id': 'consult-abc123',
  'member_id': 'user-7d4e9a2c5f18',
  'target_type': 'trainer',
  'gym_id': null,
  'trainer_id': 'trainer-demo',
  'gym_name': null,
  'trainer_name': '김트레이너',
  'exercise_goal': 'weight_loss',
  'health_purpose_type': 'chronic',
  'health_purpose_detail': null,
  'preferred_date': '2026-08-20',
  'preferred_time_slot': '14:30',
  'message': '문의합니다',
  'status': 'pending',
  'created_at': '2026-08-07T10:00:00Z',
  'updated_at': '2026-08-07T10:00:00Z',
};

class _RestoringRepository implements ConsultationRepository {
  @override
  Future<String> create(ConsultationDraft draft) async => 'new-id';

  @override
  Future<List<ConsultationRequest>> fetchMine({
    int limit = consultationPageSize,
  }) async => <ConsultationRequest>[consultationFromJson(_serverRow)];

  @override
  Future<void> cancel(String consultationId) async {}

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async =>
      const <TrainerSlot>[];
}

class _FailingRepository implements ConsultationRepository {
  @override
  Future<String> create(ConsultationDraft draft) async => 'new-id';

  @override
  Future<List<ConsultationRequest>> fetchMine({
    int limit = consultationPageSize,
  }) async => throw StateError('network down');

  @override
  Future<void> cancel(String consultationId) async {}

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async =>
      const <TrainerSlot>[];
}

void main() {
  test('서버 응답이 엔티티로 복원된다', () {
    final r = consultationFromJson(_serverRow);
    expect(r.id, 'consult-abc123');
    expect(r.trainerName, '김트레이너');
    // 라벨이 아니라 계약 enum 이어야 화면이 현지화 문구를 만들 수 있다.
    expect(r.exerciseGoal, ExerciseGoal.weightLoss);
    expect(r.healthPurposeType, HealthPurposeType.chronic);
    expect(
      r.preferredTimeSlot,
      const PreferredTime.at(TimeOfDay(hour: 14, minute: 30)),
    );
    expect(r.status, ConsultationStatus.pending);
    expect(r.preferredDate, DateTime(2026, 8, 20));
  });

  test('모르는 코드가 와도 예외 없이 떨어진다', () {
    final r = consultationFromJson(<String, Object?>{
      ..._serverRow,
      'exercise_goal': 'brand_new_goal',
      'preferred_time_slot': 'dawn',
    });
    // 서버가 값을 추가해도 앱이 죽지 않아야 한다.
    expect(r.exerciseGoal, ExerciseGoal.other);
    expect(r.preferredTimeSlot, const PreferredTime.flexible());
  });

  test('과거 morning/afternoon/evening 값도 시간 협의로 복원된다 (#1256)', () {
    final r = consultationFromJson(<String, Object?>{
      ..._serverRow,
      'preferred_time_slot': 'morning',
    });
    expect(r.preferredTimeSlot, const PreferredTime.flexible());
  });

  test('기동 시 서버 상태를 불러와 hasPending 이 살아난다', () async {
    final c = ConsultationRequestController(_RestoringRepository());
    await c.restore();

    expect(c.state, hasLength(1));
    // 복원이 없으면 목록이 비어 같은 대상에 다시 눌러 409 를 받는다.
    expect(c.hasPending(trainerId: 'trainer-demo'), isTrue);
  });

  test('복원 실패는 화면을 깨뜨리지 않는다', () async {
    final c = ConsultationRequestController(_FailingRepository());
    await c.restore();
    expect(c.state, isEmpty);
  });
}
