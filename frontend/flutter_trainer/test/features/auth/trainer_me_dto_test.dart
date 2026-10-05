import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/auth/data/dtos/trainer_me_dto.dart';

void main() {
  group('trainerProfileFromJson', () {
    test('maps a full /trainer/me body into a TrainerProfile', () {
      final profile = trainerProfileFromJson(<String, Object?>{
        'id': 't1',
        'name': '김트레이너',
        'email': 'trainer@oncare.com',
        'phone': '010-1234-5678',
        'specialty': '퍼스널 트레이너',
        'career': '7년',
        'intro': '안녕하세요',
        'certifications': <Object?>['CPT', '영양사'],
        'gym': <String, Object?>{
          'id': 'gym-1',
          'name': '온케어짐 신촌점',
          'address': '서울 서대문구 신촌로 120',
          'hours': '06:00 – 23:00',
          'phone': '02-1234-5678',
          'lat': 37.5559,
          'lng': 126,
        },
      });

      expect(profile.name, '김트레이너');
      expect(profile.careerYears, 7);
      expect(profile.certifications, <String>['CPT', '영양사']);
      expect(profile.gym.name, '온케어짐 신촌점');
      expect(profile.gym.id, 'gym-1');
      expect(profile.gym.hours, '06:00 – 23:00');
      // 정수로 와도 좌표로 읽는다 — 헬스장 찾기 지도의 첫 위치다(#3206).
      expect(profile.gym.lat, 37.5559);
      expect(profile.gym.lng, 126.0);
      expect(profile.gym.hasLocation, isTrue);
    });

    test('drops non-string certifications and tolerates a missing gym', () {
      final profile = trainerProfileFromJson(<String, Object?>{
        'name': '이코치',
        'certifications': <Object?>['CPT', 42, null],
      });

      expect(profile.name, '이코치');
      expect(profile.email, '');
      expect(profile.certifications, <String>['CPT']);
      expect(profile.gym.name, '');
    });

    test('coerces a non-list certifications field to empty', () {
      final profile = trainerProfileFromJson(<String, Object?>{
        'name': '박트레이너',
        'certifications': 'not-a-list',
      });

      expect(profile.certifications, isEmpty);
    });

    test('safely converts a non-string gym id', () {
      final profile = trainerProfileFromJson(<String, Object?>{
        'gym': <String, Object?>{'id': 42, 'name': '온케어짐'},
      });

      expect(profile.gym.id, '42');
    });

    test('leaves gym coordinates null when missing or not numbers', () {
      final profile = trainerProfileFromJson(<String, Object?>{
        'gym': <String, Object?>{'name': '온케어짐', 'lat': '37.5', 'lng': null},
      });

      expect(profile.gym.lat, isNull);
      expect(profile.gym.lng, isNull);
      expect(profile.gym.hasLocation, isFalse);
    });
  });
}
