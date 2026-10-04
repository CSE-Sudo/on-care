import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';

/// 데모 목업의 계정 소유 확인 — 가입 이메일 인증 코드(#3038)와 이메일 변경·
/// 탈퇴 앞의 본인 확인(#3039). 실서버와 같은 상태 코드·`detail.code` 를 준다.
///
/// 아래 비밀번호는 모두 테스트 전용 값이다.
void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test',
        validateStatus: (int? s) => true,
      ),
    );
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Object? detailCode(Response<Map<String, Object?>> res) {
    final Object? detail = res.data?['detail'];
    return detail is Map ? detail['code'] : null;
  }

  Future<Response<Map<String, Object?>>> requestCode(
    String email, [
    String purpose = 'member_signup',
  ]) => dio.post<Map<String, Object?>>(
    '/auth/register/email-code',
    data: <String, Object?>{'email': email, 'purpose': purpose},
  );

  Future<Response<Map<String, Object?>>> register(
    String email, {
    String? code,
    String password = 'password123',
  }) => dio.post<Map<String, Object?>>(
    '/auth/register',
    data: <String, Object?>{
      'email': email,
      'password': password,
      'name': '이서연',
      'email_code': ?code,
    },
  );

  Future<Response<Map<String, Object?>>> login(String email, String password) =>
      dio.post<Map<String, Object?>>(
        '/auth/login',
        data: <String, Object?>{'username': email, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

  Future<Response<Map<String, Object?>>> putMe(Map<String, Object?> body) =>
      dio.put<Map<String, Object?>>('/users/me', data: body);

  Future<Response<Map<String, Object?>>> deleteMe(Map<String, Object?> body) =>
      dio.delete<Map<String, Object?>>('/users/me', data: body);

  Future<Map<String, Object?>> profile() async =>
      (await dio.get<Map<String, Object?>>('/users/me/profile')).data!;

  group('POST /auth/register/email-code (#3038)', () {
    test('언제나 202 와 유효 시간·다시 받기 대기를 준다', () async {
      for (final String email in <String>[
        'new@example.com',
        // 이미 가입된 주소도 같은 응답이다 — 가입 여부를 흘리지 않는다.
        'minsu@oncare.com',
      ]) {
        final res = await requestCode(email);
        expect(res.statusCode, 202, reason: email);
        expect(res.data!['expires_in_minutes'], 10);
        expect(res.data!['resend_after_seconds'], 60);
      }
    });

    test('이메일 형식이 틀리거나 용도가 낯설면 422 다', () async {
      expect((await requestCode('not-an-email')).statusCode, 422);
      expect((await requestCode('new@example.com', 'other')).statusCode, 422);
    });
  });

  group('POST /auth/register 인증 코드 (#3038)', () {
    test('데모 코드 000000 이면 가입된다', () async {
      final res = await register('new@example.com', code: '000000');
      expect(res.statusCode, 201);
    });

    test('코드가 없으면 422 email_code_required', () async {
      final missing = await register('new@example.com');
      expect(missing.statusCode, 422);
      expect(detailCode(missing), 'email_code_required');

      final empty = await register('new@example.com', code: '');
      expect(empty.statusCode, 422);
      expect(detailCode(empty), 'email_code_required');
    });

    test('다른 코드는 400 invalid_email_code 이고 계정이 생기지 않는다', () async {
      final res = await register('new@example.com', code: '123456');
      expect(res.statusCode, 400);
      expect(detailCode(res), 'invalid_email_code');
      // 계정이 없으니 그 비밀번호로는 가입 계정으로 들지 않는다 — 다시 가입된다.
      expect(
        (await register('new@example.com', code: '000000')).statusCode,
        201,
      );
    });

    test('이미 가입된 이메일은 코드보다 먼저 409 다', () async {
      final res = await register('minsu@oncare.com', code: '123456');
      expect(res.statusCode, 409);
    });
  });

  group('PUT /users/me 이메일 변경 본인 확인 (#3039)', () {
    test('이메일을 바꾸지 않는 저장은 비밀번호 없이 되고 토큰을 주지 않는다', () async {
      await login('a@b.com', 'demo-pass-1');
      final res = await putMe(<String, Object?>{
        'name': '김민수2',
        'email': 'MINSU@oncare.com',
      });
      expect(res.statusCode, 200);
      expect(res.data!['access_token'], isNull);
      expect(res.data!['refresh_token'], isNull);
    });

    test('데모 회원은 들어올 때 친 비밀번호로 확인한다', () async {
      await login('a@b.com', 'demo-pass-1');

      final missing = await putMe(<String, Object?>{'email': 'new@b.com'});
      expect(missing.statusCode, 400);
      expect(detailCode(missing), 'reauth_required');

      final wrong = await putMe(<String, Object?>{
        'email': 'new@b.com',
        'current_password': 'other-pass-1',
      });
      expect(wrong.statusCode, 400);
      expect(detailCode(wrong), 'invalid_current_password');
      expect((await profile())['email'], 'minsu@oncare.com');

      final ok = await putMe(<String, Object?>{
        'email': 'new@b.com',
        'current_password': 'demo-pass-1',
      });
      expect(ok.statusCode, 200);
      expect(ok.data!['email'], 'new@b.com');
      // 이메일이 바뀌면 새 토큰 한 쌍을 준다.
      expect(ok.data!['access_token'], isA<String>());
      expect(ok.data!['refresh_token'], isA<String>());
    });

    test('가입 계정은 가입한 비밀번호로 확인하고, 중복은 확인 뒤에 본다', () async {
      await register('seoyeon@example.com', code: '000000');
      await login('seoyeon@example.com', 'password123');

      final wrong = await putMe(<String, Object?>{
        'email': 'minsu@oncare.com',
        'current_password': 'wrong-pass-1',
      });
      expect(wrong.statusCode, 400);
      expect(detailCode(wrong), 'invalid_current_password');

      final taken = await putMe(<String, Object?>{
        'email': 'minsu@oncare.com',
        'current_password': 'password123',
      });
      expect(taken.statusCode, 409);
    });
  });

  group('DELETE /users/me 본인 확인 (#3039)', () {
    test('확인 값이 없으면 400 이고 아무것도 지우지 않는다', () async {
      await login('a@b.com', 'demo-pass-1');
      await putMe(<String, Object?>{'name': '남는이름'});

      final res = await deleteMe(<String, Object?>{'reasons': <String>[]});
      expect(res.statusCode, 400);
      expect(detailCode(res), 'reauth_required');
      expect((await profile())['name'], '남는이름');
    });

    test('비밀번호가 맞으면 지운다', () async {
      await login('a@b.com', 'demo-pass-1');
      final wrong = await deleteMe(<String, Object?>{
        'current_password': 'other-pass-1',
      });
      expect(detailCode(wrong), 'invalid_current_password');

      final ok = await deleteMe(<String, Object?>{
        'current_password': 'demo-pass-1',
      });
      expect(ok.statusCode, 200);
    });

    test('소셜로 든 회원은 비밀번호가 없고, 같은 provider 데모 토큰으로 확인한다', () async {
      await dio.post<Map<String, Object?>>(
        '/auth/social/kakao',
        data: <String, Object?>{'token': 'demo-kakao-token'},
      );
      expect((await profile())['has_password'], isFalse);

      final password = await deleteMe(<String, Object?>{
        'current_password': 'demo-pass-1',
      });
      expect(password.statusCode, 400);
      expect(detailCode(password), 'reauth_required');

      final otherProvider = await deleteMe(<String, Object?>{
        'social_provider': 'google',
        'social_token': 'demo-google-token',
      });
      expect(detailCode(otherProvider), 'invalid_reauth');

      final badToken = await deleteMe(<String, Object?>{
        'social_provider': 'kakao',
        'social_token': 'forged',
      });
      expect(detailCode(badToken), 'invalid_reauth');

      final ok = await deleteMe(<String, Object?>{
        'social_provider': 'kakao',
        'social_token': 'demo-kakao-token',
      });
      expect(ok.statusCode, 200);
    });

    test('이메일로 든 데모 회원은 비밀번호 계정이다', () async {
      await login('a@b.com', 'demo-pass-1');
      expect((await profile())['has_password'], isTrue);
    });
  });
}
