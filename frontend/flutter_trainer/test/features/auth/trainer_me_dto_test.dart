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

    // 소셜로만 가입한 계정은 탈퇴 본인 확인을 소셜 재로그인으로 받는다(#3039).
    test('reads has_password, defaulting to true when absent', () {
      expect(
        trainerProfileFromJson(<String, Object?>{
          'has_password': false,
        }).hasPassword,
        isFalse,
      );
      expect(
        trainerProfileFromJson(<String, Object?>{
          'has_password': true,
        }).hasPassword,
        isTrue,
      );
      // 칸이 없는 옛 서버·잘못된 값은 서버 기본값(true)과 같게 읽는다.
      expect(trainerProfileFromJson(<String, Object?>{}).hasPassword, isTrue);
      expect(
        trainerProfileFromJson(<String, Object?>{
          'has_password': 'no',
        }).hasPassword,
        isTrue,
      );
    });
  });
}
