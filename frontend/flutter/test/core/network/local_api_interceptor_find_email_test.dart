import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';

/// 데모의 아이디(가입 이메일) 찾기(#3337) — 서버와 같은 규칙으로 데모 회원과 이
/// 데모에서 가입한 계정을 찾고, 가려진 이메일만 준다.
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
    String name = '이서연',
    String phone = '010-2222-3333',
  }) => dio.post<Map<String, Object?>>(
    '/auth/register',
    data: <String, Object?>{
      'email': email,
      'password': 'password123',
      'name': name,
      'phone': phone,
      // 데모가 받아 주는 가입 인증 코드(#3038).
      'email_code': '000000',
    },
  );

  Future<Response<Map<String, Object?>>> find(Object? name, Object? phone) =>
      dio.post<Map<String, Object?>>(
        '/auth/find-email',
        data: <String, Object?>{'name': name, 'phone': phone},
      );

  List<Object?> accounts(Response<Map<String, Object?>> res) =>
      res.data!['accounts']! as List<Object?>;

  test('데모 회원은 이름과 번호로 가려진 이메일을 찾는다', () async {
    final res = await find('김민수', '010-1234-5678');
    expect(res.statusCode, 200);
    expect(accounts(res), <Object?>[
      <String, Object?>{
        'masked_email': 'mi***@oncare.com',
        'providers': <String>[],
      },
    ]);
  });

  test('전체 이메일은 응답 어디에도 없다', () async {
    final res = await find('김민수', '010-1234-5678');
    expect(res.data.toString(), isNot(contains('minsu')));
  });

  test('하이픈 없이 보낸 번호와 이름 앞뒤 공백도 같은 계정을 찾는다', () async {
    final res = await find('  김민수 ', '01012345678');
    expect(accounts(res), hasLength(1));
  });

  test('이 데모에서 가입한 계정도 찾는다', () async {
    expect((await register('seoyeon@example.com')).statusCode, 201);
    final res = await find('이서연', '010-2222-3333');
    expect(accounts(res), <Object?>[
      <String, Object?>{
        'masked_email': 'se***@example.com',
        'providers': <String>[],
      },
    ]);
  });

  test('이름과 번호가 같은 계정은 모두 준다', () async {
    await register('first@example.com');
    await register('second@example.com');
    final res = await find('이서연', '010-2222-3333');
    expect(
      accounts(res).map((Object? a) => (a! as Map)['masked_email']).toSet(),
      <String>{'fi***@example.com', 'se***@example.com'},
    );
  });

  test('짧은 이메일은 한 글자를 반드시 가린다', () async {
    await register('ab@example.com', phone: '010-3333-4444');
    await register('a@example.com', phone: '010-5555-6666');
    expect(
      (accounts(await find('이서연', '010-3333-4444')).single!
          as Map)['masked_email'],
      'a***@example.com',
    );
    expect(
      (accounts(await find('이서연', '010-5555-6666')).single!
          as Map)['masked_email'],
      '***@example.com',
    );
  });

  test('맞는 계정이 없으면 200 에 빈 목록이다', () async {
    final none = await find('없는사람', '010-9999-0000');
    expect(none.statusCode, 200);
    expect(accounts(none), isEmpty);

    // 번호는 맞고 이름이 다르거나, 이름은 맞고 번호가 다른 경우도 같다.
    expect(accounts(await find('이민수', '010-1234-5678')), isEmpty);
    expect(accounts(await find('김민수', '010-0000-0000')), isEmpty);
  });

  test('이름이 비었거나 번호 형식이 틀리면 서버와 같은 422 다', () async {
    expect((await find('', '010-1234-5678')).statusCode, 422);
    expect((await find('   ', '010-1234-5678')).statusCode, 422);
    expect((await find('김민수', '')).statusCode, 422);
    expect((await find('김민수', '0101234')).statusCode, 422);
    expect((await find('김민수', '011-1234-5678')).statusCode, 422);
    expect((await find(null, null)).statusCode, 422);
  });
}
