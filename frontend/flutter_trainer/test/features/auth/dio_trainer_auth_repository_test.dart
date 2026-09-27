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

DioException _httpError(int status, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
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

  group('register', () {
    // 회원용 `/auth/register` 가 아니라 트레이너 전용 경로다 — 그쪽은
    // role='member' 를 만들어 `/trainer/me` 가 403 인 계정이 생겼다. (#475)
    const String path = '/auth/trainer/register';

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
          inviteCode: 'ONCARE1',
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

    test('maps 422 to an invite-code message', () async {
      // 없는·만료된·이미 쓰인 코드를 서버가 구분하지 않는다. 트레이너가 할 일은
      // 어느 경우든 헬스장에 코드를 다시 받는 것이라 결론이 같다.
      when(
        () => dio.post<Map<String, Object?>>(
          path,
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(_httpError(422, path));

      await expectLater(
        repo.register(
          email: 'e@x.com',
          password: 'pw',
          name: '김',
          inviteCode: 'NOPE',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.inviteCodeInvalid,
          ),
        ),
      );
    });

    test('sends the invite code to the trainer signup path', () async {
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
          inviteCode: 'ONCARE1',
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
      expect(data['invite_code'], 'ONCARE1');
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
