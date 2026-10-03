import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/admin/data/dtos/admin_trainer_dtos.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_report.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_trainer.dart';

/// `GET /admin/trainer-reports`·`GET /admin/trainers` 한 줄과 정지 결과 (#3008).
Map<String, Object?> _report({
  String reason = 'impersonation',
  String status = 'open',
  Object? trainerIsActive = true,
}) => <String, Object?>{
  'id': 'report-1',
  'trainer_id': 'trainer-1',
  'trainer_name': ' 김코치 ',
  'trainer_email': 'coach@oncare.com',
  'trainer_is_active': trainerIsActive,
  'reason': reason,
  'memo': ' 다른 헬스장 소속이에요 ',
  'status': status,
  'created_at': '2026-10-01T01:00:00Z',
  'resolved_at': status == 'open' ? null : '2026-10-02T03:00:00Z',
};

Map<String, Object?> _trainer({Object? isActive = true, Object? open = 2}) =>
    <String, Object?>{
      'trainer_id': 'trainer-1',
      'name': ' 김코치 ',
      'email': 'coach@oncare.com',
      'gym_name': ' 온케어짐 신촌점 ',
      'gym_address': '서울 서대문구 신촌로 120',
      'is_active': isActive,
      'created_at': '2026-10-01T01:00:00Z',
      'open_reports': open,
    };

void main() {
  group('신고', () {
    test('필드를 읽고 이름·내용을 다듬는다', () {
      final AdminTrainerReport r = adminTrainerReportFromJson(_report());
      expect(r.id, 'report-1');
      expect(r.trainerId, 'trainer-1');
      expect(r.trainerName, '김코치');
      expect(r.trainerEmail, 'coach@oncare.com');
      expect(r.trainerIsActive, isTrue);
      expect(r.reason, AdminReportReason.impersonation);
      expect(r.memo, '다른 헬스장 소속이에요');
      expect(r.status, AdminReportStatus.open);
      expect(r.isOpen, isTrue);
      expect(r.createdAt, isNotNull);
      expect(r.resolvedAt, isNull);
    });

    test('사유 세 가지와 모르는 사유', () {
      expect(
        adminTrainerReportFromJson(
          _report(reason: 'inappropriate_message'),
        ).reason,
        AdminReportReason.inappropriateMessage,
      );
      expect(
        adminTrainerReportFromJson(_report(reason: 'other')).reason,
        AdminReportReason.other,
      );
      expect(
        adminTrainerReportFromJson(_report(reason: 'weird')).reason,
        AdminReportReason.other,
      );
    });

    test('처리 상태와 처리 시각을 읽는다', () {
      final AdminTrainerReport resolved = adminTrainerReportFromJson(
        _report(status: 'resolved'),
      );
      expect(resolved.status, AdminReportStatus.resolved);
      expect(resolved.isOpen, isFalse);
      expect(resolved.resolvedAt, isNotNull);
      expect(
        adminTrainerReportFromJson(_report(status: 'dismissed')).status,
        AdminReportStatus.dismissed,
      );
      expect(
        adminTrainerReportFromJson(_report(status: 'weird')).status,
        AdminReportStatus.open,
      );
    });

    test('정지 여부가 없으면 살아 있는 계정이다', () {
      final Map<String, Object?> json = _report()..remove('trainer_is_active');
      expect(adminTrainerReportFromJson(json).trainerIsActive, isTrue);
      expect(
        adminTrainerReportFromJson(
          _report(trainerIsActive: false),
        ).trainerIsActive,
        isFalse,
      );
    });

    test('칩·처리 값은 서버 쿼리·본문과 같다', () {
      expect(
        AdminReportFilter.values.map((AdminReportFilter f) => f.wire),
        <String>['open', 'closed', 'all'],
      );
      expect(
        AdminReportOutcome.values.map((AdminReportOutcome o) => o.wire),
        <String>['resolved', 'dismissed'],
      );
    });
  });

  group('트레이너', () {
    test('필드를 읽는다', () {
      final AdminTrainer t = adminTrainerFromJson(_trainer());
      expect(t.trainerId, 'trainer-1');
      expect(t.name, '김코치');
      expect(t.gymName, '온케어짐 신촌점');
      expect(t.hasGym, isTrue);
      expect(t.isActive, isTrue);
      expect(t.openReports, 2);
      expect(t.createdAt, isNotNull);
    });

    test('빈 소속·없는 신고 수·정지', () {
      final AdminTrainer t = adminTrainerFromJson(
        _trainer(isActive: false, open: null)..['gym_name'] = '',
      );
      expect(t.hasGym, isFalse);
      expect(t.openReports, 0);
      expect(t.isActive, isFalse);
    });

    test('상태 칩 값은 서버 state 쿼리와 같다', () {
      expect(
        AdminTrainerState.values.map((AdminTrainerState s) => s.wire),
        <String>['all', 'active', 'suspended'],
      );
    });
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
}
