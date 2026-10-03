import 'package:oncare_trainer/features/admin/domain/entities/admin_trainer.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// `AdminTrainerVerificationOut` → [AdminTrainer] (#3008).
///
/// 모양: `{ trainer_id, name, email, specialty, career_years, certifications[],
/// gym_id, gym_name, gym_address, gym_is_fitness, status, decided_at,
/// decided_by, note, created_at, is_active }`. `is_active` 가 없는 예전 서버는
/// 살아 있는 계정으로 읽는다 — 정지 기능 이전에는 정지된 계정이 없었다.
AdminTrainer adminTrainerFromJson(Map<String, Object?> json) {
  final Object? certs = json['certifications'];
  final Object? gymId = json['gym_id'];
  return AdminTrainer(
    trainerId: _str(json['trainer_id']),
    name: _str(json['name']).trim(),
    email: _str(json['email']),
    specialty: _str(json['specialty']).trim(),
    careerYears: switch (json['career_years']) {
      final num years => years.toInt(),
      _ => 0,
    },
    certifications: certs is List
        ? certs
              .whereType<String>()
              .map((String c) => c.trim())
              .where((String c) => c.isNotEmpty)
              .toList(growable: false)
        : const <String>[],
    gymName: _str(json['gym_name']).trim(),
    gymAddress: _str(json['gym_address']).trim(),
    gymIsFitness: json['gym_is_fitness'] == true,
    hasGym: gymId is String && gymId.isNotEmpty,
    status: TrainerVerificationStatus.fromWire(json['status']),
    note: _str(json['note']).trim(),
    isActive: json['is_active'] != false,
    decidedAt: _date(json['decided_at']),
    createdAt: _date(json['created_at']),
  );
}

/// `AdminUserStatusOut` → [AdminUserStatus] (#3009).
AdminUserStatus adminUserStatusFromJson(Map<String, Object?> json) =>
    AdminUserStatus(
      userId: _str(json['user_id']),
      isActive: json['is_active'] == true,
      releasedClients: switch (json['released_clients']) {
        final num n => n.toInt(),
        _ => 0,
      },
    );

String _str(Object? value) => value is String ? value : '';

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;
