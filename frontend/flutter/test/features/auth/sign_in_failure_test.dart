import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/auth/presentation/sign_in_failure.dart';

/// 로그인 실패를 까닭별로 가른다 — 비밀번호 탓은 401·403 뿐이다. (#1940)
void main() {
  final RequestOptions req = RequestOptions(path: '/auth/login');
  DioException withStatus(int status) => DioException(
    requestOptions: req,
    response: Response<Object?>(requestOptions: req, statusCode: status),
    type: DioExceptionType.badResponse,
  );

  test('자격 증명·망·서버 장애를 가른다', () {
    expect(signInFailureOf(withStatus(401)), SignInFailure.credentials);
    // 비행기 모드 — 응답이 없다.
    expect(
      signInFailureOf(
        DioException(
          requestOptions: req,
          type: DioExceptionType.connectionError,
        ),
      ),
      SignInFailure.network,
    );
    expect(signInFailureOf(withStatus(503)), SignInFailure.unavailable);
    expect(signInFailureOf(withStatus(429)), SignInFailure.unavailable);
  });
}
