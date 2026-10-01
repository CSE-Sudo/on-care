/// 데모 AI 챗봇의 지난 대화가 요청 언어를 따른다(#2735).
///
/// 시드 대화는 한국어로 저장하고, 영어 요청이면 같은 흐름의 영어 대화를
/// 돌려준다. 감지 기록도 같은 줄을 같은 종류로 짚는다.
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

  Future<Map<String, Object?>> get(String path, {String? lang}) async {
    final res = await dio.get<Map<String, Object?>>(
      path,
      options: Options(headers: <String, Object?>{'Accept-Language': ?lang}),
    );
    return res.data!;
  }

  List<Map<String, Object?>> rows(Map<String, Object?> body, String key) =>
      (body[key]! as List<Object?>).cast<Map<String, Object?>>();

  test('영어 요청이면 시드 대화가 모두 영어다', () async {
    final List<Map<String, Object?>> messages = rows(
      await get('/ai-coach/messages', lang: 'en'),
      'messages',
    );
    expect(messages, isNotEmpty);
    for (final Map<String, Object?> m in messages) {
      expect(_hangul.hasMatch(m['content']! as String), isFalse, reason: '$m');
    }
  });

  test('헤더가 없으면 예전 한국어 대화 그대로다', () async {
    final List<Map<String, Object?>> messages = rows(
      await get('/ai-coach/messages'),
      'messages',
    );
    expect(messages.first['content'], '식단은 사진만 찍으면 되나요?');
  });

  test('감지 기록은 두 언어에서 같은 줄을 같은 종류로 짚는다', () async {
    List<String> kinds(Map<String, Object?> body) => <String>[
      for (final Map<String, Object?> r in rows(body, 'insights'))
        r['kind']! as String,
    ];
    final Map<String, Object?> ko = await get('/ai-coach/insights');
    final Map<String, Object?> en = await get('/ai-coach/insights', lang: 'en');
    expect(kinds(en), kinds(ko));
    expect(kinds(ko), isNotEmpty);
    for (final Map<String, Object?> r in rows(en, 'insights')) {
      expect(_hangul.hasMatch(r['text']! as String), isFalse);
    }
  });
}
