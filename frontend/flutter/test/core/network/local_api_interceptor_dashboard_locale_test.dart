/// 데모 홈 AI 조언의 서버 문장이 요청 언어를 따른다(#2721).
///
/// 시드 조언이 없을 때 데모가 만드는 운동 피드백·나트륨 경고는 서버처럼
/// `Accept-Language` 로 언어를 고른다. 한국어는 예전 문장 그대로다.
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

  Future<Map<String, Object?>> summary({String? lang}) async {
    final res = await dio.get<Map<String, Object?>>(
      '/dashboard/summary',
      options: Options(headers: <String, Object?>{'Accept-Language': ?lang}),
    );
    return res.data!;
  }

  test('영어 요청이면 운동 피드백이 영어다', () async {
    final Map<String, Object?> body = await summary(lang: 'en');
    // 시드 조언이 없으면 운동 피드백 키를 싣고(#2644), 옛 앱이 읽는 문장도 영어다.
    expect(body['ai_advice_key'], 'exercise_start');
    final String feedback = body['exercise_feedback']! as String;
    expect(_hangul.hasMatch(feedback), isFalse);
  });

  test('헤더가 없으면 예전 한국어 문장이다', () async {
    final Map<String, Object?> body = await summary();
    expect(body['exercise_feedback'], startsWith('이번 주 운동을 시작해'));
  });
}
