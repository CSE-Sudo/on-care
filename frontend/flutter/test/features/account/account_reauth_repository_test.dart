/// 계정 저장소가 본인 확인(#3039)을 본문에 싣고, 거절을 이유로 올리며, 이메일
/// 변경 뒤 새 토큰을 넘기는지.
///
/// 아래 비밀번호·토큰은 모두 테스트 전용 값이다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/account/data/repositories/dio_account_repository.dart';
import 'package:oncare/features/account/domain/entities/account_reauth.dart';
import 'package:oncare/features/account/domain/entities/profile_update_rejected.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart'
    show ReissuedTokens;

const Map<String, Object?> _profileJson = <String, Object?>{
  'id': 'user-1',
  'name': '김민수',
  'email': 'minsu.new@oncare.com',
};

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

Matcher _reauthRejected(AccountReauthFailure kind) => throwsA(
  isA<AccountReauthRejected>().having(
    (AccountReauthRejected e) => e.kind,
    'kind',
    kind,
  ),
);

void main() {
  group('AccountReauth.toJson', () {
    test('비밀번호 계정은 current_password 만 싣는다', () {
      expect(
        const AccountReauth.password('pw-current-1').toJson(),
        <String, Object?>{'current_password': 'pw-current-1'},
      );
    });

    test('소셜 전용 계정은 provider 와 토큰만 싣는다', () {
      expect(
        const AccountReauth.social(
          provider: 'kakao',
          token: 'demo-kakao-token',
        ).toJson(),
        <String, Object?>{
          'social_provider': 'kakao',
          'social_token': 'demo-kakao-token',
        },
      );
    });
  });

  group('AccountReauthRejected.fromResponse', () {
    test('400 코드마다 이유가 정해져 있다', () {
      expect(
        AccountReauthRejected.fromResponse(
          400,
          _detail('reauth_required'),
        )?.kind,
        AccountReauthFailure.required,
      );
      expect(
        AccountReauthRejected.fromResponse(
          400,
          _detail('invalid_current_password'),
        )?.kind,
        AccountReauthFailure.wrongPassword,
      );
      expect(
        AccountReauthRejected.fromResponse(
          400,
          _detail('invalid_reauth'),
        )?.kind,
        AccountReauthFailure.invalidSocial,
      );
    });

    test('429 는 너무 잦은 시도다', () {
      expect(
        AccountReauthRejected.fromResponse(429, <String, Object?>{
          'detail': '잠시 후 다시 시도해 주세요.',
        })?.kind,
        AccountReauthFailure.tooMany,
      );
    });

    test('다른 400·409·401 은 본인 확인 거절이 아니다', () {
      expect(
        AccountReauthRejected.fromResponse(400, _detail('something_else')),
        isNull,
      );
      expect(
        AccountReauthRejected.fromResponse(409, <String, Object?>{
          'detail': '이미 사용 중인 이메일이에요.',
        }),
        isNull,
      );
      expect(AccountReauthRejected.fromResponse(401, null), isNull);
    });
  });

  group('DioAccountRepository.updateProfile', () {
    test('본인 확인을 본문에 싣고, 새 토큰을 넘긴다', () async {
      final (DioAccountRepository repo, _Server server) = _repo(
        200,
        <String, Object?>{
          ..._profileJson,
          'access_token': 'new-access',
          'refresh_token': 'new-refresh',
        },
      );
      ReissuedTokens? got;

      await repo.updateProfile(
        email: 'minsu.new@oncare.com',
        reauth: const AccountReauth.password('pw-current-1'),
        onTokensReissued: (ReissuedTokens t) => got = t,
      );

      expect(server.lastBody['email'], 'minsu.new@oncare.com');
      expect(server.lastBody['current_password'], 'pw-current-1');
      expect(got?.access, 'new-access');
      expect(got?.refresh, 'new-refresh');
    });

    test('본인 확인이 없으면 그 칸을 보내지 않고, 토큰이 없으면 넘기지 않는다', () async {
      final (DioAccountRepository repo, _Server server) = _repo(
        200,
        <String, Object?>{
          ..._profileJson,
          'access_token': null,
          'refresh_token': null,
        },
      );
      bool called = false;

      await repo.updateProfile(
        name: '김민수2',
        onTokensReissued: (_) => called = true,
      );

      expect(server.lastBody.containsKey('current_password'), isFalse);
      expect(server.lastBody.containsKey('social_token'), isFalse);
      expect(called, isFalse);
    });

    test('틀린 비밀번호(400)는 본인 확인 거절로 올린다', () async {
      final (DioAccountRepository repo, _) = _repo(
        400,
        _detail('invalid_current_password'),
      );
      await expectLater(
        repo.updateProfile(
          email: 'minsu.new@oncare.com',
          reauth: const AccountReauth.password('wrong-pw-1'),
        ),
        _reauthRejected(AccountReauthFailure.wrongPassword),
      );
    });

    test('본인 확인 뒤의 409 는 지금처럼 이메일 중복이다', () async {
      final (DioAccountRepository repo, _) = _repo(409, <String, Object?>{
        'detail': '이미 사용 중인 이메일이에요.',
      });
      await expectLater(
        repo.updateProfile(
          email: 'trainer@oncare.com',
          reauth: const AccountReauth.password('pw-current-1'),
        ),
        throwsA(
          isA<ProfileUpdateRejected>().having(
            (ProfileUpdateRejected e) => e.reason,
            'reason',
            ProfileUpdateRejection.emailTaken,
          ),
        ),
      );
    });
  });

  group('DioAccountRepository.deleteAccount', () {
    test('사유와 본인 확인을 한 본문에 싣는다', () async {
      final (DioAccountRepository repo, _Server server) = _repo(
        200,
        <String, Object?>{'status': 'deleted'},
      );

      await repo.deleteAccount(
        reasons: <String>['privacy'],
        reauth: const AccountReauth.social(
          provider: 'google',
          token: 'demo-google-token',
        ),
      );

      expect(server.requests.single.method, 'DELETE');
      expect(server.lastBody, <String, Object?>{
        'reasons': <String>['privacy'],
        'social_provider': 'google',
        'social_token': 'demo-google-token',
      });
    });

    test('400 reauth_required 는 본인 확인 거절이다 — 로그아웃할 일이 아니다', () async {
      final (DioAccountRepository repo, _) = _repo(
        400,
        _detail('reauth_required'),
      );
      await expectLater(
        repo.deleteAccount(),
        _reauthRejected(AccountReauthFailure.required),
      );
    });

    test('소셜 확인 실패(400 invalid_reauth)', () async {
      final (DioAccountRepository repo, _) = _repo(
        400,
        _detail('invalid_reauth'),
      );
      await expectLater(
        repo.deleteAccount(
          reauth: const AccountReauth.social(provider: 'kakao', token: 'x'),
        ),
        _reauthRejected(AccountReauthFailure.invalidSocial),
      );
    });

    test('429 는 너무 잦은 시도다', () async {
      final (DioAccountRepository repo, _) = _repo(429, <String, Object?>{
        'detail': '잠시 후 다시 시도해 주세요.',
      });
      await expectLater(
        repo.deleteAccount(
          reauth: const AccountReauth.password('pw-current-1'),
        ),
        _reauthRejected(AccountReauthFailure.tooMany),
      );
    });

    test('그 밖의 실패는 그대로 올린다', () async {
      final (DioAccountRepository repo, _) = _repo(500, null);
      await expectLater(
        repo.deleteAccount(
          reauth: const AccountReauth.password('pw-current-1'),
        ),
        throwsA(isA<DioException>()),
      );
    });
  });
}
