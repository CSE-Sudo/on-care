/// 로그인 이메일 변경 전 새 주소 인증(#3230) — 저장소가 코드를 요청하고, 저장에
/// 코드를 싣고, 코드 거절을 이유로 올리는지.
///
/// 아래 비밀번호·코드는 모두 테스트 전용 값이다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/account/data/repositories/dio_account_repository.dart';
import 'package:oncare/features/account/domain/entities/account_reauth.dart';
import 'package:oncare/features/account/domain/entities/profile_update_rejected.dart';
import 'package:oncare/features/auth/domain/signup_email_code.dart';

/// 정해 둔 상태 코드·본문으로 답하고, 받은 요청을 적어 두는 대역.
class _Server extends Interceptor {
  _Server(this.status, this.body);

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

  Map<String, Object?> get lastBody =>
      requests.last.data! as Map<String, Object?>;
}

(DioAccountRepository, _Server) _repo(int status, Object? body) {
  final _Server server = _Server(status, body);
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
    ..interceptors.add(server);
  addTearDown(dio.close);
  return (DioAccountRepository(dio), server);
}

Map<String, Object?> _detail(String code) => <String, Object?>{
  'detail': <String, Object?>{'code': code, 'message': '서버 문장'},
};

Matcher _codeError(SignupEmailCodeFailure kind) => throwsA(
  isA<SignupEmailCodeError>().having(
    (SignupEmailCodeError e) => e.kind,
    'kind',
    kind,
  ),
);

Matcher _rejectedWith(ProfileUpdateRejection reason) => throwsA(
  isA<ProfileUpdateRejected>().having(
    (ProfileUpdateRejected e) => e.reason,
    'reason',
    reason,
  ),
);

void main() {
  group('DioAccountRepository.requestEmailChangeCode', () {
    test('새 주소로 코드를 요청하고 유효 시간·다시 받기 간격을 읽는다', () async {
      final (DioAccountRepository repo, _Server server) = _repo(
        202,
        <String, Object?>{'expires_in_minutes': 10, 'resend_after_seconds': 60},
      );

      final SignupEmailCodeSent sent = await repo.requestEmailChangeCode(
        email: 'minsu.new@oncare.com',
      );

      expect(server.requests.single.method, 'POST');
      expect(server.requests.single.path, '/users/me/email/code');
      expect(server.lastBody, <String, Object?>{
        'email': 'minsu.new@oncare.com',
      });
      expect(sent.expiresInMinutes, 10);
      expect(sent.resendAfterSeconds, 60);
    });

    test('응답에 값이 없으면 서버 기본값을 쓴다', () async {
      final (DioAccountRepository repo, _) = _repo(202, <String, Object?>{});
      final SignupEmailCodeSent sent = await repo.requestEmailChangeCode(
        email: 'minsu.new@oncare.com',
      );
      expect(sent.expiresInMinutes, 10);
      expect(sent.resendAfterSeconds, 60);
    });

    for (final (int status, SignupEmailCodeFailure kind)
        in <(int, SignupEmailCodeFailure)>[
          (422, SignupEmailCodeFailure.invalidEmail),
          (429, SignupEmailCodeFailure.tooMany),
          (503, SignupEmailCodeFailure.unavailable),
          (500, SignupEmailCodeFailure.temporary),
        ]) {
      test('$status 는 ${kind.name}', () async {
        final (DioAccountRepository repo, _) = _repo(
          status,
          _detail('email_unchanged'),
        );
        await expectLater(
          repo.requestEmailChangeCode(email: 'minsu.new@oncare.com'),
          _codeError(kind),
        );
      });
    }
  });

  group('DioAccountRepository.updateProfile 의 새 주소 코드', () {
    test('이메일을 바꾸는 저장은 코드를 본인 확인과 함께 싣는다', () async {
      final (DioAccountRepository repo, _Server server) = _repo(
        200,
        <String, Object?>{
          'id': 'user-1',
          'name': '김민수',
          'email': 'minsu.new@oncare.com',
        },
      );

      await repo.updateProfile(
        email: 'minsu.new@oncare.com',
        reauth: const AccountReauth.password('pw-current-1'),
        emailCode: '123456',
      );

      expect(server.lastBody['email_code'], '123456');
      expect(server.lastBody['current_password'], 'pw-current-1');
    });

    test('코드가 없으면 그 칸을 보내지 않는다', () async {
      final (DioAccountRepository repo, _Server server) = _repo(
        200,
        <String, Object?>{'id': 'user-1', 'name': '김민수2', 'email': 'a@b.com'},
      );
      await repo.updateProfile(name: '김민수2');
      expect(server.lastBody.containsKey('email_code'), isFalse);
    });

    test('틀린 코드(400 invalid_email_code)는 코드 거절로 올린다', () async {
      final (DioAccountRepository repo, _) = _repo(
        400,
        _detail('invalid_email_code'),
      );
      await expectLater(
        repo.updateProfile(
          email: 'minsu.new@oncare.com',
          reauth: const AccountReauth.password('pw-current-1'),
          emailCode: '000001',
        ),
        _rejectedWith(ProfileUpdateRejection.emailCodeInvalid),
      );
    });

    test('코드 없음(422 email_code_required)도 코드 거절이다', () async {
      final (DioAccountRepository repo, _) = _repo(
        422,
        _detail('email_code_required'),
      );
      await expectLater(
        repo.updateProfile(
          email: 'minsu.new@oncare.com',
          reauth: const AccountReauth.password('pw-current-1'),
        ),
        _rejectedWith(ProfileUpdateRejection.emailCodeInvalid),
      );
    });
  });

  group('ProfileUpdateRejected.fromResponse', () {
    test('코드 거절이 아닌 422 는 예전 판정 그대로다', () {
      expect(
        ProfileUpdateRejected.fromResponse(422, <String, Object?>{
          'detail': '전화번호는 비울 수 없습니다.',
        })?.reason,
        ProfileUpdateRejection.phoneRequired,
      );
      expect(
        ProfileUpdateRejected.fromResponse(422, <String, Object?>{
          'detail': <Object?>[],
        })?.reason,
        ProfileUpdateRejection.invalid,
      );
      expect(
        ProfileUpdateRejected.fromResponse(409, null)?.reason,
        ProfileUpdateRejection.emailTaken,
      );
      expect(ProfileUpdateRejected.fromResponse(400, _detail('other')), isNull);
    });
  });
}
