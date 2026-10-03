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
        },
      });

      expect(profile.name, '김트레이너');
      expect(profile.careerYears, 7);
      expect(profile.certifications, <String>['CPT', '영양사']);
      expect(profile.gym.name, '온케어짐 신촌점');
      expect(profile.gym.id, 'gym-1');
      expect(profile.gym.hours, '06:00 – 23:00');
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

    // 운영자 표시(#3008) — 참일 때만 운영자다.
    test('reads is_admin only when it is literally true', () {
      expect(
        trainerProfileFromJson(<String, Object?>{'is_admin': true}).isAdmin,
        isTrue,
      );
      expect(
        trainerProfileFromJson(<String, Object?>{'is_admin': false}).isAdmin,
        isFalse,
      );
      expect(
        trainerProfileFromJson(<String, Object?>{'is_admin': 'true'}).isAdmin,
        isFalse,
      );
      // 칸이 없는 예전 서버는 운영자가 아니다.
      expect(trainerProfileFromJson(<String, Object?>{}).isAdmin, isFalse);
    });

    test('copyWith keeps isAdmin unless replaced', () {
      final profile = trainerProfileFromJson(<String, Object?>{
        'name': '운영자',
        'is_admin': true,
      });
      expect(profile.copyWith(name: '새 이름').isAdmin, isTrue);
      expect(profile.copyWith(isAdmin: false).isAdmin, isFalse);
    });
  });
}
