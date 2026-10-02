import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';

/// 데모에서 가입한 계정(#2665) — 실서버처럼 저장되고, 첫 설정 전 프로필로
/// 시작하고, 가입한 비밀번호로만 로그인된다. 가입하지 않은 이메일은 지금처럼
/// 데모 회원(김민수)으로 든다.
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

  Future<Response<Map<String, Object?>>> register(
    String email, {
    String password = 'password123',
    String name = '이서연',
    String phone = '010-2222-3333',
  }) => dio.post<Map<String, Object?>>(
    '/auth/register',
    data: <String, Object?>{
      'email': email,
      'password': password,
      'name': name,
      'phone': phone,
    },
  );

  Future<Response<Map<String, Object?>>> login(
    String email, [
    String password = 'password123',
  ]) => dio.post<Map<String, Object?>>(
    '/auth/login',
    data: <String, Object?>{'username': email, 'password': password},
    options: Options(contentType: Headers.formUrlEncodedContentType),
  );

  Future<Map<String, Object?>> profile() async =>
      (await dio.get<Map<String, Object?>>('/users/me/profile')).data!;

  test('새 계정은 가입 때 받은 값만 든 첫 설정 전 프로필로 시작한다', () async {
    final created = await register('seoyeon@example.com');
    expect(created.statusCode, 201);
    expect(created.data!['id'], matches(RegExp(r'^user-[0-9a-f]{12}$')));

    expect((await login('seoyeon@example.com')).statusCode, 200);
    final Map<String, Object?> p = await profile();
    expect(p['id'], created.data!['id']);
    expect(p['name'], '이서연');
    expect(p['email'], 'seoyeon@example.com');
    expect(p['phone'], '010-2222-3333');
    expect(p['onboarded'], isFalse);
    // 김민수의 신체·목표 값을 물려받지 않는다.
    expect(p['height_cm'], isNull);
    expect(p['weight_kg'], isNull);
    expect(p['birth_date'], isNull);
    expect(p['conditions'], isNull);
    expect(p['daily_calories'], isNull);
  });

  test('첫 설정을 마치면 그 계정만 onboarded 가 된다', () async {
    await register('seoyeon@example.com');
    await login('seoyeon@example.com');
    final res = await dio.post<Map<String, Object?>>(
      '/users/me/onboarding',
      data: <String, Object?>{'gender': 'female', 'height_cm': 162},
    );
    expect(res.data!['onboarded'], isTrue);
    expect(res.data!['name'], '이서연');
    expect(res.data!['height_cm'], 162);

    // 데모 회원의 프로필은 그대로다.
    await login('anyone@example.com', 'whatever');
    final Map<String, Object?> demo = await profile();
    expect(demo['name'], '김민수');
    expect(demo['height_cm'], 175.0);
    expect(demo['onboarded'], isTrue);

    // 다시 들어가도 첫 설정을 마친 상태다.
    await login('seoyeon@example.com');
    expect((await profile())['onboarded'], isTrue);
  });

  test('가입한 계정은 틀린 비밀번호를 서버와 같은 401 로 거절한다', () async {
    await register('seoyeon@example.com');
    final res = await login('seoyeon@example.com', 'wrong-pass1');
    expect(res.statusCode, 401);
    expect(res.data!['detail'], '이메일 또는 비밀번호가 올바르지 않습니다.');
    // 대소문자만 다른 주소도 같은 계정이다.
    expect((await login('SeoYeon@Example.com')).statusCode, 200);
  });

  test('가입하지 않은 이메일은 지금처럼 데모 회원으로 든다', () async {
    final res = await login('a@b.com', 'pw');
    expect(res.statusCode, 200);
    final Map<String, Object?> p = await profile();
    expect(p['email'], 'minsu@oncare.com');
    expect(p['onboarded'], isTrue);
  });

  test('이미 있는 이메일로는 서버와 같은 409 로 가입되지 않는다', () async {
    expect((await register('seoyeon@example.com')).statusCode, 201);
    for (final String email in <String>[
      'seoyeon@example.com',
      'SEOYEON@example.com',
      'minsu@oncare.com',
      'trainer@oncare.com',
    ]) {
      final res = await register(email);
      expect(res.statusCode, 409, reason: email);
      expect(res.data!['detail'], '이미 가입된 이메일입니다.');
    }
  });

  test('탈퇴한 가입 계정은 지워져 같은 이메일로 다시 가입할 수 있다', () async {
    await register('seoyeon@example.com');
    await login('seoyeon@example.com');
    await dio.post<Object?>(
      '/users/me/onboarding',
      data: <String, Object?>{'height_cm': 162},
    );
    expect((await dio.delete<Object?>('/users/me')).statusCode, 200);

    expect((await register('seoyeon@example.com')).statusCode, 201);
    await login('seoyeon@example.com');
    final Map<String, Object?> p = await profile();
    expect(p['onboarded'], isFalse);
    expect(p['height_cm'], isNull);
  });

  test('내 프로필에서 바꾼 이메일로 다음에 로그인한다', () async {
    await register('seoyeon@example.com');
    await login('seoyeon@example.com');
    final res = await dio.put<Map<String, Object?>>(
      '/users/me',
      data: <String, Object?>{'email': 'new-seoyeon@example.com'},
    );
    expect(res.statusCode, 200);
    expect((await login('new-seoyeon@example.com')).statusCode, 200);
    expect((await profile())['email'], 'new-seoyeon@example.com');
    // 데모 회원의 이메일로는 바꿀 수 없다.
    final taken = await dio.put<Map<String, Object?>>(
      '/users/me',
      data: <String, Object?>{'email': 'minsu@oncare.com'},
    );
    expect(taken.statusCode, 409);
  });

  test('MY 카드도 가입 계정의 id·이름·이메일을 보여 준다', () async {
    final created = await register('seoyeon@example.com');
    await login('seoyeon@example.com');
    final state = await MockMyHealthRepository(db: db).fetchState();
    expect(state.profile.id, created.data!['id']);
    expect(state.profile.name, '이서연');
    expect(state.profile.email, 'seoyeon@example.com');

    await login('a@b.com', 'pw');
    final demo = await MockMyHealthRepository(db: db).fetchState();
    expect(demo.profile.id, 'user-7d4e9a2c5f18');
    expect(demo.profile.name, '김민수');
  });
}
