/// 데모 백엔드의 프로필 응답도 대체 이메일 표시를 서버와 같은 모양으로 싣는다. (#3338)
///
/// 데모 계정의 이메일은 늘 실제 꼴의 주소라 값은 거짓·null 이다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';

import '../../helpers/fixed_clock.dart';

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() {
    useFixedKstDate(DateTime(2026, 8, 20, 12));
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() => db.close());

  Future<Map<String, Object?>> get(String path) async =>
      (await dio.get<Map<String, Object?>>(path)).data!;

  void expectRealEmail(Map<String, Object?> body) {
    expect(body['email_is_placeholder'], isFalse);
    expect(body.containsKey('email_placeholder_provider'), isTrue);
    expect(body['email_placeholder_provider'], isNull);
    expect(body['email'], isNot(contains('social.oncare')));
  }

  test('GET /users/me', () async {
    expectRealEmail(await get('/users/me'));
  });

  test('GET /users/me/profile', () async {
    expectRealEmail(await get('/users/me/profile'));
  });

  test('GET /users/me/health 의 profile', () async {
    final Map<String, Object?> body = await get('/users/me/health');
    expectRealEmail(body['profile']! as Map<String, Object?>);
  });
}
