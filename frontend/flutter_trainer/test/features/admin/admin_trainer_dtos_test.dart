import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/admin/data/dtos/admin_trainer_dtos.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_trainer.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// `GET /admin/trainers` 한 줄과 정지 결과 (#3008·#3009).
Map<String, Object?> _row({
  String status = 'pending',
  Object? isActive = true,
  Object? gymId = 'gym-1',
  bool fitness = true,
}) => <String, Object?>{
  'trainer_id': 'trainer-1',
  'name': ' 김코치 ',
  'email': 'coach@oncare.com',
  'specialty': '체형 교정',
  'career_years': 4,
  'certifications': <Object?>['CPT', ' ', 7, '생활스포츠지도사'],
  'gym_id': gymId,
  'gym_name': '온케어짐 신촌점',
  'gym_address': '서울 서대문구 신촌로 120',
  'gym_is_fitness': fitness,
  'status': status,
  'decided_at': status == 'pending' ? null : '2026-10-02T03:00:00Z',
  'decided_by': null,
  'note': status == 'rejected' ? ' 서류 보완 ' : '',
  'created_at': '2026-10-01T01:00:00Z',
  'is_active': isActive,
};

void main() {
  test('필드를 읽고 공백·숫자 자격증을 거른다', () {
    final AdminTrainer t = adminTrainerFromJson(_row());
    expect(t.trainerId, 'trainer-1');
    expect(t.name, '김코치');
    expect(t.careerYears, 4);
    expect(t.certifications, <String>['CPT', '생활스포츠지도사']);
    expect(t.hasGym, isTrue);
    expect(t.gymIsFitness, isTrue);
    expect(t.status, TrainerVerificationStatus.pending);
    expect(t.isActive, isTrue);
    expect(t.createdAt, isNotNull);
    expect(t.decidedAt, isNull);
  });

  test('반려 사유는 다듬는다', () {
    final AdminTrainer t = adminTrainerFromJson(_row(status: 'rejected'));
    expect(t.status, TrainerVerificationStatus.rejected);
    expect(t.note, '서류 보완');
    expect(t.decidedAt, isNotNull);
  });

  test('is_active 가 없으면 살아 있는 계정이다(정지 기능 이전 서버)', () {
    final Map<String, Object?> json = _row()..remove('is_active');
    expect(adminTrainerFromJson(json).isActive, isTrue);
    expect(adminTrainerFromJson(_row(isActive: false)).isActive, isFalse);
  });

  test('소속이 없으면 hasGym 이 거짓이다', () {
    expect(adminTrainerFromJson(_row(gymId: null)).hasGym, isFalse);
    expect(adminTrainerFromJson(_row(gymId: '')).hasGym, isFalse);
  });

  test('승인·반려 버튼은 상태와 정지 여부를 따른다', () {
    final AdminTrainer pending = adminTrainerFromJson(_row());
    expect(pending.canApprove, isTrue);
    expect(pending.canReject, isTrue);

    final AdminTrainer approved = adminTrainerFromJson(
      _row(status: 'approved'),
    );
    expect(approved.canApprove, isFalse);
    expect(approved.canReject, isTrue);

    final AdminTrainer rejected = adminTrainerFromJson(
      _row(status: 'rejected'),
    );
    expect(rejected.canApprove, isTrue);
    expect(rejected.canReject, isFalse);

    final AdminTrainer suspended = adminTrainerFromJson(_row(isActive: false));
    expect(suspended.canApprove, isFalse);
    expect(suspended.canReject, isFalse);
  });

  test('모르는 상태는 승인 대기로 읽는다', () {
    expect(
      adminTrainerFromJson(_row(status: 'weird')).status,
      TrainerVerificationStatus.pending,
    );
  });

  test('정지 결과를 읽는다', () {
    final AdminUserStatus s = adminUserStatusFromJson(<String, Object?>{
      'user_id': 'trainer-1',
      'role': 'trainer',
      'is_active': false,
      'released_clients': 3,
    });
    expect(s.userId, 'trainer-1');
    expect(s.isActive, isFalse);
    expect(s.releasedClients, 3);
    expect(
      adminUserStatusFromJson(<String, Object?>{
        'user_id': 'u',
        'is_active': true,
      }).releasedClients,
      0,
    );
  });

  test('칩 값은 서버 status 쿼리와 같다', () {
    expect(
      AdminTrainerFilter.values.map((AdminTrainerFilter f) => f.wire),
      <String>['pending', 'approved', 'rejected', 'all'],
    );
  });
}
