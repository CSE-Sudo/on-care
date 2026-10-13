import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// Maps a `GET /v1/trainer/me` JSON body (the FastAPI `TrainerMe` schema)
/// into the domain [TrainerProfile]. Kept separate from the Dio
/// repository so the DTO ↔ domain mapping can be unit-tested directly.
///
/// Shape: `{ id, name, email, phone, specialty, career, intro,
/// certifications[], gym { id, name, address, hours, phone, lat, lng },
/// is_admin, has_password }`. `is_admin` 은
/// `true` 일 때만 운영자다(#3008) — 칸이 없는 예전 서버는 운영자가 아니다. Missing
/// scalar fields fall back to `''`; a missing/invalid `gym` yields an
/// empty gym; `certifications` keeps only string entries.
TrainerProfile trainerProfileFromJson(Map<String, Object?> json) {
  final gymJson = json['gym'];
  final gym = gymJson is Map<String, Object?>
      ? TrainerGym(
          id: _nullableStr(gymJson['id']),
          name: _str(gymJson['name']),
          address: _str(gymJson['address']),
          hours: _str(gymJson['hours']),
          phone: _str(gymJson['phone']),
          lat: _nullableDouble(gymJson['lat']),
          lng: _nullableDouble(gymJson['lng']),
        )
      : const TrainerGym(name: '', address: '', hours: '', phone: '');

  final certsRaw = json['certifications'];
  final certifications = certsRaw is List
      ? certsRaw.whereType<String>().toList(growable: false)
      : const <String>[];

  return TrainerProfile(
    name: _str(json['name']),
    email: _str(json['email']),
    phone: _str(json['phone']),
    specialty: _str(json['specialty']),
    careerYears: careerYearsFromJson(json),
    intro: _str(json['intro']),
    certifications: certifications,
    gym: gym,
    isAdmin: json['is_admin'] == true,
    // 칸이 없으면 비밀번호 계정으로 읽는다 — 서버 기본값과 같다(#3039).
    hasPassword: switch (json['has_password']) {
      final bool value => value,
      _ => true,
    },
  );
}

String _str(Object? v) => v is String ? v : '';

/// 경력 연수를 숫자로 읽는다 (#2304).
///
/// `career_years`(숫자)가 있으면 그것을, 없으면 서버가 조립해 보내는 `career`
/// 문구(`'7년'`)의 앞 숫자를 읽는다 — 화면이 로케일에 맞는 단위를 붙이므로
/// 서버의 한국어 단위는 버린다. 둘 다 없거나 숫자가 아니면 `null` 이다.
int? careerYearsFromJson(Map<String, Object?> json) {
  final Object? years = json['career_years'];
  if (years is num) return years.toInt();
  final Object? career = json['career'];
  if (career is! String) return null;
  final RegExpMatch? match = RegExp(r'^\s*(\d+)').firstMatch(career);
  return match == null ? null : int.parse(match.group(1)!);
}

String? _nullableStr(Object? value) => value?.toString();

double? _nullableDouble(Object? value) =>
    value is num ? value.toDouble() : null;
