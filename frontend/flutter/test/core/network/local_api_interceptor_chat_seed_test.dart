/// 데모 AI 챗봇의 지난 대화와 감지 기록(#2735).
///
/// 시드 대화를 저장된 그대로 돌려주고, 감지 기록은 그 대화의 줄을 짚는다.
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

  Future<Map<String, Object?>> get(String path) async {
    final res = await dio.get<Map<String, Object?>>(path);
    return res.data!;
  }

  List<Map<String, Object?>> rows(Map<String, Object?> body, String key) =>
      (body[key]! as List<Object?>).cast<Map<String, Object?>>();

  test('시드 대화를 그대로 돌려준다', () async {
    final List<Map<String, Object?>> messages = rows(
      await get('/ai-coach/messages'),
      'messages',
    );
    expect(messages.first['content'], '식단은 사진만 찍으면 되나요?');
  });

  test('감지 기록은 종류와 문장을 싣는다', () async {
    final List<Map<String, Object?>> insights = rows(
      await get('/ai-coach/insights'),
      'insights',
    );
    expect(insights, isNotEmpty);
    for (final Map<String, Object?> r in insights) {
      expect(r['kind'], isA<String>());
      expect(r['text']! as String, isNotEmpty);
    }
  });
}
