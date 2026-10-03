import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/auth/data/dtos/trainer_me_dto.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// 운영자 승인 상태의 모델·DTO 경계 (#2825).
void main() {
  group('TrainerVerificationStatus.fromWire', () {
    test('reads the three server values', () {
      expect(
        TrainerVerificationStatus.fromWire('pending'),
        TrainerVerificationStatus.pending,
      );
      expect(
        TrainerVerificationStatus.fromWire('approved'),
        TrainerVerificationStatus.approved,
      );
      expect(
        TrainerVerificationStatus.fromWire('rejected'),
        TrainerVerificationStatus.rejected,
      );
    });

    test('reads an unknown or missing value as pending (closed side)', () {
      expect(
        TrainerVerificationStatus.fromWire('suspended'),
        TrainerVerificationStatus.pending,
      );
      expect(
        TrainerVerificationStatus.fromWire(null),
        TrainerVerificationStatus.pending,
      );
      expect(
        TrainerVerificationStatus.fromWire(1),
        TrainerVerificationStatus.pending,
      );
    });
  });

  group('TrainerVerification', () {
    test('only approved is approved', () {
      expect(TrainerVerification.approved.isApproved, isTrue);
      expect(
        const TrainerVerification(
          status: TrainerVerificationStatus.pending,
        ).isApproved,
        isFalse,
      );
      expect(
        const TrainerVerification(
          status: TrainerVerificationStatus.rejected,
          note: '소속 확인 불가',
        ).isApproved,
        isFalse,
      );
    });

    test(
      'a profile without verification is approved — demo trainers are approved',
      () {
        final TrainerProfile profile = trainerProfileFromJson(<String, Object?>{
          'name': '데모',
        });
        expect(profile.verification.isApproved, isTrue);
      },
    );

    test('copyWith carries the verification', () {
      final TrainerProfile profile = trainerProfileFromJson(<String, Object?>{
        'name': '김트레이너',
      });
      final TrainerProfile pending = profile.copyWith(
        verification: const TrainerVerification(
          status: TrainerVerificationStatus.pending,
        ),
      );
      expect(pending.verification.status, TrainerVerificationStatus.pending);
      expect(
        pending.copyWith(name: '이름만').verification.status,
        TrainerVerificationStatus.pending,
      );
    });
  });

  group('trainerVerificationFromJson', () {
    test('a server without the field reads as approved', () {
      expect(trainerVerificationFromJson(null).isApproved, isTrue);
      expect(trainerVerificationFromJson('pending').isApproved, isTrue);
    });

    test('reads status and trims the note', () {
      final TrainerVerification rejected =
          trainerVerificationFromJson(<String, Object?>{
            'status': 'rejected',
            'decided_at': '2026-09-30T05:00:00Z',
            'note': '  소속 확인 불가  ',
          });
      expect(rejected.status, TrainerVerificationStatus.rejected);
      expect(rejected.note, '소속 확인 불가');
    });

    test('a map with an unknown status reads as pending', () {
      final TrainerVerification v = trainerVerificationFromJson(
        <String, Object?>{'status': 'mystery'},
      );
      expect(v.status, TrainerVerificationStatus.pending);
      expect(v.note, '');
    });

    test('/trainer/me carries the verification into the profile', () {
      final TrainerProfile profile = trainerProfileFromJson(<String, Object?>{
        'name': '박트레이너',
        'verification': <String, Object?>{
          'status': 'pending',
          'decided_at': null,
          'note': '',
        },
      });
      expect(profile.verification.status, TrainerVerificationStatus.pending);

      final TrainerProfile legacy = trainerProfileFromJson(<String, Object?>{
        'name': '박트레이너',
      });
      expect(legacy.verification.isApproved, isTrue);
    });
  });
}
