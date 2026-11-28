/// 데모 AI 챗봇이 질문 갈래에 맞는 답을 돌려준다(#2712).
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

  Future<Map<String, Object?>> ask(String message) async {
    final res = await dio.post<Map<String, Object?>>(
      '/ai-coach/chat',
      data: <String, Object?>{'message': message},
    );
    return res.data!;
  }

  test('나트륨 질문에는 나트륨 답을 한다', () async {
    final Map<String, Object?> res = await ask('오늘 나트륨 얼마나 먹었어?');
    expect(res['reply'], startsWith('나트륨을 줄이려면'));
  });
}
