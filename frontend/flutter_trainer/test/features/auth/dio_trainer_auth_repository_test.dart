import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';

class _MockDio extends Mock implements Dio {}

Response<Map<String, Object?>> _ok(Map<String, Object?> body, String path) =>
    Response<Map<String, Object?>>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body,
    );

DioException _httpError(int status, String path, {Object? body}) =>
    DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.badResponse,
      response: Response<Object?>(
        requestOptions: RequestOptions(path: path),
        statusCode: status,
        data: body,
      ),
    );

void main() {
  late _MockDio dio;
  late DioTrainerAuthRepository repo;

  setUpAll(() => registerFallbackValue(Options()));

  setUp(() {
    dio = _MockDio();
    repo = DioTrainerAuthRepository(dio);
  });

  group('login', () {
    test('parses access/refresh tokens on success', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/auth/login',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _ok(<String, Object?>{
          'access_token': 'a',
          'refresh_token': 'r',
        }, '/auth/login'),
      );

      final tokens = await repo.login(email: 'e@x.com', password: 'pw');
      expect(tokens.access, 'a');
      expect(tokens.refresh, 'r');
    });

    test('maps 401 to a friendly AuthException', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/auth/login',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(_httpError(401, '/auth/login'));

      await expectLater(
        repo.login(email: 'e@x.com', password: 'bad'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.invalidCredentials,
          ),
        ),
      );
    });

    test('maps a connection error to a network AuthException', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/auth/login',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repo.login(email: 'e@x.com', password: 'pw'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.network,
          ),
        ),
      );
    });
  });

  // 실행 중 만료 뒤의 갱신 — 거부(401/403)만 세션의 끝이다(#1546).
  group('refresh', () {
    Matcher failsWith(AuthFailure failure) => throwsA(
      isA<AuthException>().having((e) => e.failure, 'failure', failure),
    );

    void answerRefresh(Object error) => when(
      () => dio.post<Map<String, Object?>>(
        '/auth/refresh',
        data: any(named: 'data'),
      ),
    ).thenThrow(error);

    test('parses rotated tokens', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/auth/refresh',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok(<String, Object?>{
          'access_token': 'a2',
          'refresh_token': 'r2',
        }, '/auth/refresh'),
      );

      final tokens = await repo.refresh('r1');
      expect(tokens.access, 'a2');
      expect(tokens.refresh, 'r2');
    });

    test('maps 401 to sessionExpired', () async {
      answerRefresh(_httpError(401, '/auth/refresh'));
      await expectLater(
        repo.refresh('r1'),
        failsWith(AuthFailure.sessionExpired),
      );
    });

    test('maps 403 to sessionExpired like the member app', () async {
      answerRefresh(_httpError(403, '/auth/refresh'));
      await expectLater(
        repo.refresh('r1'),
        failsWith(AuthFailure.sessionExpired),
      );
    });

    test('keeps a 5xx as a non-terminal failure', () async {
      answerRefresh(_httpError(503, '/auth/refresh'));
      await expectLater(repo.refresh('r1'), failsWith(AuthFailure.unknown));
    });

    test('keeps a connection error as a network failure', () async {
      answerRefresh(
        DioException(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          type: DioExceptionType.connectionError,
        ),
      );
      await expectLater(repo.refresh('r1'), failsWith(AuthFailure.network));
    });

    test('a 403 on login is still not a session expiry', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/auth/login',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(_httpError(403, '/auth/login'));
      await expectLater(
        repo.login(email: 'e@x.com', password: 'pw'),
        failsWith(AuthFailure.unknown),
      );
    });
  });

  // 시도 제한(429)은 알 수 없는 오류가 아니다 — 잠긴 줄 알려야 다시 누르지
  // 않는다(#3248).
  group('429', () {
    DioException rateLimited(String path, {String? retryAfter}) => DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.badResponse,
      response: Response<Object?>(
        requestOptions: RequestOptions(path: path),
        statusCode: 429,
        data: <String, Object?>{'detail': '요청이 너무 많습니다.'},
        headers: Headers.fromMap(<String, List<String>>{
          if (retryAfter != null) 'retry-after': <String>[retryAfter],
        }),
      ),
    );

    test('로그인 잠금은 tooManyAttempts 와 남은 시간이다', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/auth/login',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(rateLimited('/auth/login', retryAfter: '900'));

      await expectLater(
        repo.login(email: 'e@x.com', password: 'pw'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.failure, 'failure', AuthFailure.tooManyAttempts)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(minutes: 15),
              ),
        ),
      );
    });

    test('Retry-After 가 없으면 남은 시간은 모름이다', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/auth/login',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(rateLimited('/auth/login'));

      await expectLater(
        repo.login(email: 'e@x.com', password: 'pw'),
        throwsA(
          isA<AuthException>()
              .having((e) => e.failure, 'failure', AuthFailure.tooManyAttempts)
              .having((e) => e.retryAfter, 'retryAfter', isNull),
        ),
      );
    });

    test('가입 429 도 tooManyAttempts 다 — "로그인 중 문제" 가 아니다', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/auth/trainer/register',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(rateLimited('/auth/trainer/register', retryAfter: '60'));

      await expectLater(
        repo.register(
          email: 'e@x.com',
          password: 'pw',
          name: '김',
          emailCode: '123456',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.tooManyAttempts,
          ),
        ),
      );
    });
  });

  group('register', () {
    // 회원용 `/auth/register` 가 아니라 트레이너 전용 경로다 — 그쪽은
    // role='member' 를 만들어 `/trainer/me` 가 403 인 계정이 생겼다. (#475)
    const String path = '/auth/trainer/register';

    test('계정을 만든 뒤 로그인이 실패하면 signedUpSignInFailed 다 (#3248)', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          path,
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => _ok(<String, Object?>{'id': 'u1'}, path));
      when(
        () => dio.post<Map<String, Object?>>(
          '/auth/login',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repo.register(
          email: 'e@x.com',
          password: 'pw',
          name: '김',
          emailCode: '123456',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.signedUpSignInFailed,
          ),
        ),
      );
    });

    test('maps 409 to a duplicate-email AuthException', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          path,
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(_httpError(409, path));

      await expectLater(
        repo.register(
          email: 'e@x.com',
          password: 'pw',
          name: '김',
          emailCode: '123456',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.emailTaken,
          ),
        ),
      );
    });

    // 서버 비밀번호 기준(#1555)에 걸린 422 는 그 이유를 그대로 알린다.
    Map<String, Object?> detail(List<Map<String, Object?>> items) =>
        <String, Object?>{'detail': items};

    Future<void> expectFailure(Object? body, AuthFailure failure) async {
      when(
        () => dio.post<Map<String, Object?>>(
          path,
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(_httpError(422, path, body: body));

      await expectLater(
        repo.register(
          email: 'e@x.com',
          password: 'pw',
          name: '김',
          emailCode: '123456',
        ),
        throwsA(
          isA<AuthException>().having((e) => e.failure, 'failure', failure),
        ),
      );
    }

    test('maps a password_weak 422 to passwordWeak, not the invite code', () {
      return expectFailure(
        detail(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'password_weak',
            'loc': <Object?>['body', 'password'],
          },
        ]),
        AuthFailure.passwordWeak,
      );
    });

    test('maps a password_empty 422 to passwordWeak', () {
      return expectFailure(
        detail(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'password_empty',
            'loc': <Object?>['body', 'password'],
          },
        ]),
        AuthFailure.passwordWeak,
      );
    });

    test('maps a password_too_long 422 to passwordTooLong', () {
      return expectFailure(
        detail(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'password_too_long',
            'loc': <Object?>['body', 'password'],
          },
        ]),
        AuthFailure.passwordTooLong,
      );
    });

    test('a password problem wins when another field is also wrong', () {
      // 스키마 오류는 한 번에 모두 온다. 비밀번호 오류를 골라 알린다.
      return expectFailure(
        detail(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'value_error',
            'loc': <Object?>['body', 'email'],
          },
          <String, Object?>{
            'type': 'password_weak',
            'loc': <Object?>['body', 'password'],
          },
        ]),
        AuthFailure.passwordWeak,
      );
    });

    test('a 422 without a password code is an unknown failure', () {
      // 초대 코드(#1627)가 사라져, 비밀번호가 아닌 422 는 화면이 미리 거르는
      // 형식 오류뿐이다.
      return expectFailure(
        detail(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'value_error',
            'loc': <Object?>['body', 'email'],
          },
        ]),
        AuthFailure.unknown,
      );
    });

    test('does not send an invite code to the trainer signup path', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          path,
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(_httpError(409, path));

      // 409 로 끝나지만, 여기서 확인하려는 것은 나간 payload 다.
      await expectLater(
        repo.register(
          email: 'e@x.com',
          password: 'pw',
          name: '김',
          emailCode: '123456',
        ),
        throwsA(isA<AuthException>()),
      );

      final data =
          verify(
                () => dio.post<Map<String, Object?>>(
                  path,
                  data: captureAny(named: 'data'),
                  options: any(named: 'options'),
                ),
              ).captured.first
              as Map<String, Object?>;
      expect(data.containsKey('invite_code'), isFalse);
      expect(data['name'], '김');
    });

    // --- 이메일 인증 코드 (#3038) ----------------------------------------

    test('sends the email code as a string in the register body', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          path,
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(_httpError(409, path));

      await expectLater(
        repo.register(
          email: 'e@x.com',
          password: 'pw',
          name: '김',
          emailCode: '012345',
        ),
        throwsA(isA<AuthException>()),
      );

      final data =
          verify(
                () => dio.post<Map<String, Object?>>(
                  path,
                  data: captureAny(named: 'data'),
                  options: any(named: 'options'),
                ),
              ).captured.first
              as Map<String, Object?>;
      // 앞자리 0 을 잃지 않게 숫자가 아니라 문자열로 싣는다.
      expect(data['email_code'], '012345');
      expect(data['email'], 'e@x.com');
    });

    Future<void> expectCodeFailure(
      int status,
      Object? body,
      AuthFailure failure,
    ) async {
      when(
        () => dio.post<Map<String, Object?>>(
          path,
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(_httpError(status, path, body: body));

      await expectLater(
        repo.register(
          email: 'e@x.com',
          password: 'pw',
          name: '김',
          emailCode: '999999',
        ),
        throwsA(
          isA<AuthException>().having((e) => e.failure, 'failure', failure),
        ),
      );
    }

    test('maps 400 invalid_email_code to emailCodeInvalid', () {
      return expectCodeFailure(400, <String, Object?>{
        'detail': <String, Object?>{
          'code': 'invalid_email_code',
          'message': '인증 코드가 맞지 않거나 만료됐어요. 코드를 다시 받아 주세요.',
        },
      }, AuthFailure.emailCodeInvalid);
    });

    test('maps 422 email_code_required to emailCodeRequired', () {
      return expectCodeFailure(422, <String, Object?>{
        'detail': <String, Object?>{
          'code': 'email_code_required',
          'message': '이메일 인증 코드를 입력해 주세요.',
        },
      }, AuthFailure.emailCodeRequired);
    });

    test('a 400 without the code stays an unknown failure', () {
      return expectCodeFailure(400, <String, Object?>{
        'detail': '잘못된 요청',
      }, AuthFailure.unknown);
    });

    test('409 duplicate email still wins over the code', () {
      return expectCodeFailure(409, null, AuthFailure.emailTaken);
    });
  });

  group('socialLogin', () {
    test('같은 이메일 계정이 있다는 409 를 socialEmailInUse 로 바꾼다 (#1551)', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/auth/social/kakao',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        _httpError(
          409,
          '/auth/social/kakao',
          body: <String, Object?>{
            'detail': <String, Object?>{
              'code': 'social_email_in_use',
              'message': '이 이메일로 가입한 계정이 있어요.',
            },
          },
        ),
      );

      await expectLater(
        repo.socialLogin(provider: 'kakao', token: 't'),
        throwsA(
          isA<AuthException>().having(
            (AuthException e) => e.failure,
            'failure',
            AuthFailure.socialEmailInUse,
          ),
        ),
      );
    });

    test('코드가 다른 409 는 그대로 일반 실패다', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/auth/social/kakao',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        _httpError(
          409,
          '/auth/social/kakao',
          body: <String, Object?>{'detail': 'conflict'},
        ),
      );

      await expectLater(
        repo.socialLogin(provider: 'kakao', token: 't'),
        throwsA(
          isA<AuthException>().having(
            (AuthException e) => e.failure,
            'failure',
            isNot(AuthFailure.socialEmailInUse),
          ),
        ),
      );
    });
  });

  group('fetchProfile', () {
    test('maps a trainer body to a profile', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          '/trainer/me',
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => _ok(<String, Object?>{
          'name': '김트레이너',
          'email': 'trainer@oncare.com',
          'gym': <String, Object?>{'name': '온케어짐 신촌점'},
        }, '/trainer/me'),
      );

      final profile = await repo.fetchProfile('token');
      expect(profile.name, '김트레이너');
      expect(profile.gym.name, '온케어짐 신촌점');
    });

    test('maps 403 to NotTrainerException', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          '/trainer/me',
          options: any(named: 'options'),
        ),
      ).thenThrow(_httpError(403, '/trainer/me'));

      await expectLater(
        repo.fetchProfile('member-token'),
        throwsA(isA<NotTrainerException>()),
      );
    });

    test('rethrows 401 so the session can refresh', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          '/trainer/me',
          options: any(named: 'options'),
        ),
      ).thenThrow(_httpError(401, '/trainer/me'));

      await expectLater(
        repo.fetchProfile('stale'),
        throwsA(isA<UnauthorizedError>()),
      );
    });

    test('maps a network failure to NetworkError, NOT AuthException '
        '(so restore keeps the tokens)', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          '/trainer/me',
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/trainer/me'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repo.fetchProfile('valid'),
        throwsA(isA<NetworkError>()),
      );
    });
  });
}
