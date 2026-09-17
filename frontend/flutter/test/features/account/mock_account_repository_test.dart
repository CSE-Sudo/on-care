import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/measure_update.dart';

void main() {
  test('mock onboarding and profile edits persist across fetches', () async {
    final repository = MockAccountRepository();

    await repository.submitOnboarding(
      gender: 'female',
      heightCm: 164.5,
      weightKg: 56.2,
      goals: '주 3회 근력 운동',
    );
    var profile = await repository.fetchProfile();
    expect(profile.gender, 'female');
    expect(profile.heightCm, 164.5);
    expect(profile.weightKg, 56.2);
    expect(profile.goals, '주 3회 근력 운동');

    await repository.updateProfile(
      name: '수정 회원',
      weightKg: const MeasureUpdate(55.8),
    );
    profile = await repository.fetchProfile();
    expect(profile.name, '수정 회원');
    expect(profile.weightKg, 55.8);
    expect(profile.goals, '주 3회 근력 운동');
  });
}
