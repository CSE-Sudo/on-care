/// 목업 가입·동의 경로 — 서버와 같은 필수 동의 규칙을 본다. #2819.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  final Options anyStatus = Options(validateStatus: (int? s) => true);

  Future<Response<Map<String, Object?>>> register(Object? consents) =>
      dio.post<Map<String, Object?>>(
        '/auth/register',
        data: <String, Object?>{
          'email': 'new@oncare.com',
          'password': 'password123',
          'name': '홍길동',
          'consents': ?consents,
        },
        options: anyStatus,
      );

  group('POST /auth/register', () {
    test('필수 동의를 모두 보내면 가입된다', () async {
      final res = await register(<String>[
        'terms',
        'privacy',
        'health',
        'age14',
      ]);
      expect(res.statusCode, 201);
    });

    test('옛 빌드가 더는 받지 않는 마케팅 항목을 실어 보내도 가입된다 (#3007)', () async {
      final res = await register(<String>[
        'terms',
        'privacy',
        'health',
        'age14',
        'marketing',
      ]);
      expect(res.statusCode, 201);
    });

    test('건강정보 동의가 빠지면 422 다', () async {
      final res = await register(<String>['terms', 'privacy', 'age14']);
      expect(res.statusCode, 422);
    });

    test('빈 목록도 422 다 — 보냈는데 아무것도 체크하지 않았다', () async {
      final res = await register(<String>[]);
      expect(res.statusCode, 422);
    });

    test('목록을 보내지 않은 옛 빌드는 막지 않는다', () async {
      final res = await register(null);
      expect(res.statusCode, 201);
    });
  });

  test('GET /users/me — 데모 회원은 동의를 마친 계정이다', () async {
    final res = await dio.get<Map<String, Object?>>('/users/me');
    expect(res.data!['consent_required'], isFalse);
    expect(res.data!['consent_pending'], isEmpty);
  });

  group('POST /users/me/consents', () {
    test('필수 항목을 모두 보내면 동의 요구가 풀린다', () async {
      final res = await dio.post<Map<String, Object?>>(
        '/users/me/consents',
        data: <String, Object?>{
          'consents': <String>['terms', 'privacy', 'health', 'age14'],
        },
      );
      expect(res.statusCode, 200);
      expect(res.data!['consent_required'], isFalse);
    });

    test('빠진 항목을 정렬해 422 로 알린다', () async {
      final res = await dio.post<Map<String, Object?>>(
        '/users/me/consents',
        data: <String, Object?>{
          'consents': <String>['terms'],
        },
        options: anyStatus,
      );
      expect(res.statusCode, 422);
      final Map<String, Object?> detail =
          res.data!['detail']! as Map<String, Object?>;
      expect(detail['code'], 'consent_required');
      expect(detail['missing'], <String>['age14', 'health', 'privacy']);
    });

    test('목록이 없으면 필수 전부가 빠진 것이다', () async {
      final res = await dio.post<Map<String, Object?>>(
        '/users/me/consents',
        data: <String, Object?>{},
        options: anyStatus,
      );
      expect(res.statusCode, 422);
    });
  });
}
