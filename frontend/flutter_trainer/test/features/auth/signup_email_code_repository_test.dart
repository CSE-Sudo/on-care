/// 가입 이메일 인증 코드(#3038) — 요청 본문·응답·실패 매핑과 데모 가입 규칙.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/features/auth/data/repositories/mock_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/data/repositories/signup_email_code_repositories.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/signup_email_code_repository.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';

class _MockDio extends Mock implements Dio {}

const String _path = '/auth/register/email-code';

DioException _error(int status, {Object? body}) => DioException(
  requestOptions: RequestOptions(path: _path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: _path),
    statusCode: status,
    data: body,
  ),
);

void main() {
  group('DioSignupEmailCodeRepository', () {
    late _MockDio dio;
    late DioSignupEmailCodeRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioSignupEmailCodeRepository(dio);
    });

    test('트레이너 가입 목적으로 요청하고 202 응답을 읽는다', () async {
      when(
        () => dio.post<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: _path),
          statusCode: 202,
          data: <String, dynamic>{
            'expires_in_minutes': 10,
            'resend_after_seconds': 60,
          },
        ),
      );

      final SignupEmailCodeSent sent = await repo.request(
        email: 'new@oncare.com',
      );

      expect(sent.expiresInMinutes, 10);
      expect(sent.resendAfterSeconds, 60);
      // 실 서버는 코드를 화면에 알려 주지 않는다.
      expect(sent.demoCode, isNull);
      final Object? body = verify(
        () => dio.post<Map<String, dynamic>>(
          _path,
          data: captureAny(named: 'data'),
        ),
      ).captured.single;
      expect(body, <String, String>{
        'email': 'new@oncare.com',
        'purpose': 'trainer_signup',
      });
    });

    for (final MapEntry<int, SignupEmailCodeFailure> c
        in <int, SignupEmailCodeFailure>{
          422: SignupEmailCodeFailure.invalidEmail,
          429: SignupEmailCodeFailure.tooMany,
          503: SignupEmailCodeFailure.unavailable,
          500: SignupEmailCodeFailure.temporary,
        }.entries) {
      test('${c.key} → ${c.value.name}', () async {
        when(
          () => dio.post<Map<String, dynamic>>(_path, data: any(named: 'data')),
        ).thenThrow(_error(c.key, body: <String, Object?>{'detail': '서버 문장'}));

        await expectLater(
          repo.request(email: 'new@oncare.com'),
          throwsA(
            isA<SignupEmailCodeError>().having((e) => e.kind, 'kind', c.value),
          ),
        );
      });
    }

    test('연결 실패는 temporary', () async {
      when(
        () => dio.post<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repo.request(email: 'new@oncare.com'),
        throwsA(
          isA<SignupEmailCodeError>().having(
            (e) => e.kind,
            'kind',
            SignupEmailCodeFailure.temporary,
          ),
        ),
      );
    });
  });

  group('MockSignupEmailCodeRepository (데모)', () {
    test('늘 202 와 같은 값 — 10분 유효, 60초 뒤 다시 받기, 데모 코드', () async {
      final SignupEmailCodeSent sent =
          await const MockSignupEmailCodeRepository().request(
            email: 'anyone@oncare.com',
          );

      expect(sent.expiresInMinutes, 10);
      expect(sent.resendAfterSeconds, 60);
      expect(sent.demoCode, '000000');
      expect(SignupEmailCode.isComplete(sent.demoCode!), isTrue);
    });
  });

  group('MockTrainerAuthRepository.register 의 코드 검사 (데모)', () {
    const MockTrainerAuthRepository repo = MockTrainerAuthRepository();

    Future<void> register(String code) => repo.register(
      email: 'new@oncare.com',
      password: 'signup-pw-1234',
      name: '김신규',
      emailCode: code,
    );

    Matcher failsWith(AuthFailure failure) => throwsA(
      isA<AuthException>().having((e) => e.failure, 'failure', failure),
    );

    test('데모 코드 000000 만 통과한다', () async {
      await expectLater(register('000000'), completes);
    });

    test('코드가 비면 email_code_required 와 같다', () async {
      await expectLater(register(''), failsWith(AuthFailure.emailCodeRequired));
      await expectLater(
        register('   '),
        failsWith(AuthFailure.emailCodeRequired),
      );
    });

    test('다른 코드는 invalid_email_code 와 같다', () async {
      for (final String wrong in <String>['123456', '00000', '0000000']) {
        await expectLater(
          register(wrong),
          failsWith(AuthFailure.emailCodeInvalid),
          reason: wrong,
        );
      }
    });
  });

  group('SignupEmailCode', () {
    test('6자리 숫자만 완성된 코드다', () {
      expect(SignupEmailCode.isComplete('012345'), isTrue);
      expect(SignupEmailCode.isComplete(' 012345 '), isTrue);
      expect(SignupEmailCode.isComplete('12345'), isFalse);
      expect(SignupEmailCode.isComplete('1234567'), isFalse);
      expect(SignupEmailCode.isComplete('12a456'), isFalse);
      expect(SignupEmailCode.isComplete(''), isFalse);
    });

    test('코드가 묶인 이메일은 대소문자·앞뒤 공백을 가리지 않는다', () {
      expect(
        SignupEmailCode.emailKey(' New@OnCare.com '),
        SignupEmailCode.emailKey('new@oncare.com'),
      );
    });
  });
}
