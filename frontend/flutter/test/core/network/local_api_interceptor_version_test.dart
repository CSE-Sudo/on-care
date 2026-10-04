/// 목업 `/version` — 실서버와 같은 모양으로 최소 지원 버전을 비워 둔다(#3045).
///
/// 데모·목업 빌드가 업데이트 화면에 갇히지 않아야 한다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/app_version/app_version_gate.dart';
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

  test('min_app_version 키가 있고 값은 null 이다', () async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/version');
    expect(res.statusCode, 200);
    final Map<String, Object?> body = res.data!;
    expect(body['api_version'], 'v1');
    expect(body.containsKey('min_app_version'), isTrue);
    expect(body['min_app_version'], isNull);
  });

  test('이 응답으로 확인하면 막지 않는다', () async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/version');
    final AppVersionGateState state = evaluateAppVersion(
      current: '0.0.1',
      minRaw: res.data!['min_app_version'],
    );
    expect(state.status, AppVersionStatus.supported);
  });
}
