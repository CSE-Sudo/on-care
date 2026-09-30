/// 데모 AI 챗봇 답이 요청 언어를 따른다(#2712).
///
/// 실서버는 `Accept-Language` 로 답하는 언어를 고른다. 데모도 영어 화면에서는
/// 영어 질문(빠른 질문 포함)을 같은 갈래로 알아듣고 영어로 답한다. 한국어는
/// 예전 답 그대로다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';

final RegExp _hangul = RegExp('[가-힣]');

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

  Future<Map<String, Object?>> ask(String message, {String? lang}) async {
    final res = await dio.post<Map<String, Object?>>(
      '/ai-coach/chat',
      data: <String, Object?>{'message': message},
      options: Options(headers: <String, Object?>{'Accept-Language': ?lang}),
    );
    return res.data!;
  }

  test('영어 빠른 질문은 같은 갈래의 영어 답을 받는다', () async {
    final Map<String, Object?> sodium = await ask(
      'How much sodium have I had today?',
      lang: 'en',
    );
    expect(sodium['reply'], contains('sodium'));
    expect(_hangul.hasMatch(sodium['reply']! as String), isFalse);

    final Map<String, Object?> dinner = await ask(
      'Recommend a dinner menu for today',
      lang: 'en',
    );
    expect(dinner['reply'], contains('dinner'));
    expect(_hangul.hasMatch(dinner['reply']! as String), isFalse);
  });

  test('한국어는 예전 답 그대로다', () async {
    final Map<String, Object?> res = await ask('오늘 나트륨 얼마나 먹었어?');
    expect(res['reply'], startsWith('나트륨을 줄이려면'));
  });
}
