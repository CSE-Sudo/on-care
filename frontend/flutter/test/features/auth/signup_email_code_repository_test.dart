/// 가입 이메일 인증 코드 요청 저장소와 가입 거절 해석 — #3038.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/auth/data/repositories/dio_signup_email_code_repository.dart';
import 'package:oncare/features/auth/domain/signup_email_code.dart';

/// 정해 둔 상태 코드·본문으로 답하고, 받은 요청을 적어 두는 대역.
class _Server extends Interceptor {
  _Server(this.status, [this.body]);

  final int status;
  final Object? body;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final Response<Object?> response = Response<Object?>(
      requestOptions: options,
      statusCode: status,
      data: body,
    );
    if (status >= 400) {
      handler.reject(
        DioException.badResponse(
          statusCode: status,
          requestOptions: options,
          response: response,
        ),
      );
      return;
    }
    handler.resolve(response);
  }
}

(DioSignupEmailCodeRepository, _Server) _repo(int status, [Object? body]) {
  final _Server server = _Server(status, body);
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
    ..interceptors.add(server);
  addTearDown(dio.close);
  return (DioSignupEmailCodeRepository(dio), server);
}

Matcher _failsWith(SignupEmailCodeFailure kind) => throwsA(
  isA<SignupEmailCodeError>().having(
    (SignupEmailCodeError e) => e.kind,
    'kind',
    kind,
  ),
);

void main() {
  group('DioSignupEmailCodeRepository', () {
    test('이메일과 회원 가입 용도를 보내고 응답 시간을 읽는다', () async {
      final (DioSignupEmailCodeRepository repo, _Server server) = _repo(
        202,
        <String, Object?>{'expires_in_minutes': 15, 'resend_after_seconds': 30},
      );

      final SignupEmailCodeSent sent = await repo.requestCode(
        email: 'new@oncare.com',
      );

      final RequestOptions req = server.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/auth/register/email-code');
      expect(req.data, <String, Object?>{
        'email': 'new@oncare.com',
        'purpose': 'member_signup',
      });
      expect(sent.expiresInMinutes, 15);
      expect(sent.resendAfterSeconds, 30);
    });

    test('응답에 시간이 없으면 서버 기본값으로 둔다', () async {
      final (DioSignupEmailCodeRepository repo, _) = _repo(
        202,
        const <String, Object?>{},
      );
      final SignupEmailCodeSent sent = await repo.requestCode(
        email: 'new@oncare.com',
      );
      expect(sent.expiresInMinutes, 10);
      expect(sent.resendAfterSeconds, 60);
    });

    test('상태 코드마다 실패 이유가 정해져 있다', () async {
      for (final MapEntry<int, SignupEmailCodeFailure> c
          in <int, SignupEmailCodeFailure>{
            422: SignupEmailCodeFailure.invalidEmail,
            429: SignupEmailCodeFailure.tooMany,
            503: SignupEmailCodeFailure.unavailable,
            500: SignupEmailCodeFailure.temporary,
          }.entries) {
        final (DioSignupEmailCodeRepository repo, _) = _repo(
          c.key,
          <String, Object?>{'detail': '서버 문장'},
        );
        await expectLater(
          repo.requestCode(email: 'new@oncare.com'),
          _failsWith(c.value),
          reason: '${c.key}',
        );
      }
    });
  });

  group('signupCodeRejectionOf', () {
    Map<String, Object?> detail(String code) => <String, Object?>{
      'detail': <String, Object?>{'code': code, 'message': '서버 문장'},
    };

    test('400 invalid_email_code 는 틀린 코드다', () {
      expect(
        signupCodeRejectionOf(400, detail('invalid_email_code')),
        SignupCodeRejection.invalid,
      );
    });

    test('422 email_code_required 는 코드 없음이다', () {
      expect(
        signupCodeRejectionOf(422, detail('email_code_required')),
        SignupCodeRejection.required,
      );
    });

    test('비밀번호 422·중복 409 는 코드 거절이 아니다', () {
      expect(
        signupCodeRejectionOf(422, <String, Object?>{
          'detail': <Object?>[
            <String, Object?>{'type': 'password_weak'},
          ],
        }),
        isNull,
      );
      expect(
        signupCodeRejectionOf(409, <String, Object?>{'detail': 'x'}),
        isNull,
      );
      // 상태 코드와 코드가 엇갈리면 믿지 않는다.
      expect(signupCodeRejectionOf(400, detail('email_code_required')), isNull);
    });
  });

  test('SignupEmailCode.isComplete 는 숫자 여섯 자리만 받는다', () {
    expect(SignupEmailCode.isComplete('000000'), isTrue);
    expect(SignupEmailCode.isComplete(' 123456 '), isTrue);
    expect(SignupEmailCode.isComplete('12345'), isFalse);
    expect(SignupEmailCode.isComplete('1234567'), isFalse);
    expect(SignupEmailCode.isComplete('12a456'), isFalse);
  });
}
