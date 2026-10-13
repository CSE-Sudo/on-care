import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_report.dart';
import 'package:oncare_trainer/features/admin/domain/entities/admin_trainer.dart';

/// `AdminTrainerOut` → [AdminTrainer] (#3008).
///
/// 모양: `{ trainer_id, name, email, gym_name, gym_address, is_active,
/// created_at, open_reports }`. `is_active` 가 없으면 살아 있는 계정으로 읽는다.
AdminTrainer adminTrainerFromJson(Map<String, Object?> json) => AdminTrainer(
  trainerId: _str(json['trainer_id']),
  name: _str(json['name']).trim(),
  email: _str(json['email']),
  gymName: _str(json['gym_name']).trim(),
  gymAddress: _str(json['gym_address']).trim(),
  isActive: json['is_active'] != false,
  openReports: _int(json['open_reports']),
  createdAt: _date(json['created_at']),
);

/// `AdminTrainerReportOut` → [AdminTrainerReport] (#3008).
///
/// 모양: `{ id, trainer_id, trainer_name, trainer_email, trainer_is_active,
/// reason, memo, status, created_at, resolved_at }`.
AdminTrainerReport adminTrainerReportFromJson(Map<String, Object?> json) =>
    AdminTrainerReport(
      id: _str(json['id']),
      trainerId: _str(json['trainer_id']),
      trainerName: _str(json['trainer_name']).trim(),
      trainerEmail: _str(json['trainer_email']),
      trainerIsActive: json['trainer_is_active'] != false,
      reason: AdminReportReason.fromWire(json['reason']),
      memo: _str(json['memo']).trim(),
      status: AdminReportStatus.fromWire(json['status']),
      createdAt: _date(json['created_at']),
      resolvedAt: _date(json['resolved_at']),
    );

/// `AdminUserStatusOut` → [AdminUserStatus].
AdminUserStatus adminUserStatusFromJson(Map<String, Object?> json) =>
    AdminUserStatus(
      userId: _str(json['user_id']),
      isActive: json['is_active'] == true,
      releasedClients: _int(json['released_clients']),
    );

String _str(Object? value) => value is String ? value : '';

int _int(Object? value) => value is num ? value.toInt() : 0;

/// 서버 시각을 KST 벽시계로 읽는다(#3248). `toLocal()` 은 브라우저 시간대라
/// 해외에서 접속한 운영자에게는 신고·가입 날짜가 하루 어긋날 수 있었다.
DateTime? _date(Object? value) =>
    switch (value is String ? DateTime.tryParse(value) : null) {
      final DateTime at => toKst(at),
      null => null,
    };
