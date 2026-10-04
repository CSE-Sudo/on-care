/// 데모 트레이너 가입도 서버와 같은 비밀번호 기준을 본다(#1555).
///
/// 데모에서만 가입되는 비밀번호가 있으면 실서버에서 처음 실패를 보게 된다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/auth/data/repositories/mock_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/data/repositories/signup_email_code_repositories.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';

void main() {
  const MockTrainerAuthRepository repo = MockTrainerAuthRepository();

  Future<void> register(String password) => repo.register(
    email: 'new@oncare.com',
    password: password,
    name: '김신규',
    emailCode: MockSignupEmailCodeRepository.demoCode,
  );

  Matcher failsWith(AuthFailure failure) => throwsA(
    isA<AuthException>().having((e) => e.failure, 'failure', failure),
  );

  test('빈 비밀번호는 예전처럼 emptyCredentials', () async {
    await expectLater(register(''), failsWith(AuthFailure.emptyCredentials));
  });

  for (final String weak in <String>[
    'abc1234',
    '12345678',
    'abcdefgh',
    '        ',
  ]) {
    test('기준 미달("$weak")은 passwordWeak', () async {
      await expectLater(register(weak), failsWith(AuthFailure.passwordWeak));
    });
  }

  for (final String tooLong in <String>[
    '${'a1' * 32}x',
    '${'가' * 22}abc1234',
    '${'\u{1F4AA}' * 16}abcd12345',
  ]) {
    test('상한 초과(${tooLong.runes.length}자)는 passwordTooLong', () async {
      await expectLater(
        register(tooLong),
        failsWith(AuthFailure.passwordTooLong),
      );
    });
  }

  for (final String ok in <String>[
    'abcd1234',
    'a1' * 32,
    '${'가' * 22}abc123',
  ]) {
    test('기준에 맞으면 가입된다(${ok.runes.length}자)', () async {
      final tokens = await repo.register(
        email: 'new@oncare.com',
        password: ok,
        name: '김신규',
        emailCode: MockSignupEmailCodeRepository.demoCode,
      );
      expect(tokens.access, isNotEmpty);
    });
  }
}
