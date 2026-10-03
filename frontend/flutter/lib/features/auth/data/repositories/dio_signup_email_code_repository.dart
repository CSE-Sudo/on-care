import 'package:dio/dio.dart';
import 'package:oncare/features/auth/domain/signup_email_code.dart';

/// 가입 이메일 인증 코드 요청(#3038). 데모 빌드에서는 같은 요청을 기기 안
/// 목업 API(`LocalApiInterceptor`)가 받는다.
class DioSignupEmailCodeRepository implements SignupEmailCodeRepository {
  const DioSignupEmailCodeRepository(this._dio);

  final Dio _dio;

  /// 응답에 값이 없을 때 쓰는 기본값 — 서버 기본 설정과 같다.
  static const int defaultExpiresInMinutes = 10;
  static const int defaultResendAfterSeconds = 60;

  @override
  Future<SignupEmailCodeSent> requestCode({required String email}) async {
    final Response<Map<String, Object?>> res;
    try {
      res = await _dio.post<Map<String, Object?>>(
        '/auth/register/email-code',
        data: <String, String>{
          'email': email,
          'purpose': SignupEmailCode.memberPurpose,
        },
      );
    } on DioException catch (e) {
      throw SignupEmailCodeError(switch (e.response?.statusCode) {
        422 => SignupEmailCodeFailure.invalidEmail,
        429 => SignupEmailCodeFailure.tooMany,
        503 => SignupEmailCodeFailure.unavailable,
        _ => SignupEmailCodeFailure.temporary,
      });
    }
    final Object? minutes = res.data?['expires_in_minutes'];
    final Object? seconds = res.data?['resend_after_seconds'];
    return SignupEmailCodeSent(
      expiresInMinutes: minutes is num
          ? minutes.toInt()
          : defaultExpiresInMinutes,
      resendAfterSeconds: seconds is num
          ? seconds.toInt()
          : defaultResendAfterSeconds,
    );
  }
}
