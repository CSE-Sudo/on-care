import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/signup_email_code_repository.dart';

/// 실 서버 가입 인증 코드 요청(#3038). 같은 엔드포인트를 회원 앱도 쓴다 —
/// 목적(`purpose`)만 다르다.
class DioSignupEmailCodeRepository implements SignupEmailCodeRepository {
  const DioSignupEmailCodeRepository(this._dio);

  final Dio _dio;

  @override
  Future<SignupEmailCodeSent> request({required String email}) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(
        '/auth/register/email-code',
        data: <String, String>{
          'email': email,
          'purpose': SignupEmailCode.purpose,
        },
      );
    } on DioException catch (e) {
      throw signupEmailCodeErrorOf(e);
    }
    final Map<String, dynamic>? body = res.data;
    return SignupEmailCodeSent(
      expiresInMinutes: _int(body?['expires_in_minutes']),
      resendAfterSeconds: _int(body?['resend_after_seconds']),
    );
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;
}

/// 코드 요청의 실패를 화면이 고를 이유로.
SignupEmailCodeError signupEmailCodeErrorOf(DioException e) =>
    switch (e.response?.statusCode) {
      422 => const SignupEmailCodeError(SignupEmailCodeFailure.invalidEmail),
      429 => const SignupEmailCodeError(SignupEmailCodeFailure.tooMany),
      503 => const SignupEmailCodeError(SignupEmailCodeFailure.unavailable),
      _ => const SignupEmailCodeError(SignupEmailCodeFailure.temporary),
    };

/// 데모 빌드의 코드 요청(#3038). 메일이 실제로 가지 않으니 요청은 늘 받아 주고,
/// 화면이 안내할 [demoCode] 를 돌려준다. 데모 가입은 이 코드만 통과시킨다
/// (`MockTrainerAuthRepository.register`).
class MockSignupEmailCodeRepository implements SignupEmailCodeRepository {
  const MockSignupEmailCodeRepository();

  /// 데모 가입 코드. 실 코드와 같은 6자리 숫자다.
  static const String demoCode = '000000';

  /// 서버 기본값과 같은 유효 시간(분)·다시 받기 대기(초).
  static const int demoExpiresInMinutes = 10;
  static const int demoResendAfterSeconds = 60;

  @override
  Future<SignupEmailCodeSent> request({required String email}) async =>
      const SignupEmailCodeSent(
        expiresInMinutes: demoExpiresInMinutes,
        resendAfterSeconds: demoResendAfterSeconds,
        demoCode: demoCode,
      );
}

/// 지금 빌드의 코드 요청 리포지토리 — 데모면 목업, 아니면 실 서버.
final signupEmailCodeRepositoryProvider = Provider<SignupEmailCodeRepository>((
  ref,
) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return const MockSignupEmailCodeRepository();
  }
  return DioSignupEmailCodeRepository(ref.watch(dioProvider));
}, name: 'signupEmailCodeRepository');
