/// 데모 API 의 서버 전체 AI 하루 상한(#3032).
///
/// 실서버는 상한에 걸리면 AI 코치 대화와 사진 분석을 503 `ai_capacity` +
/// `Retry-After` 로 거절하고, 회원 하루 몫·포인트·끼니를 남기지 않는다. 데모도
/// 같은 본문으로 거절해 앱이 같은 안내 길을 타게 한다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis_failure.dart';

void main() {
  late AppDatabase db;
  late Dio dio;
  late LocalApiInterceptor api;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    api = LocalApiInterceptor(
      db,
      Logger(level: Level.off),
      points: DemoPointsLedger(openingBalance: 1000),
    );
    dio.interceptors.add(api);
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Future<DioException> refused(Future<Object?> request) =>
      request.then<DioException>(
        (_) => fail('상한에 걸렸는데 요청이 통과했다'),
        onError: (Object e) => e as DioException,
      );

  Map<String, Object?> detailOf(DioException e) =>
      (e.response!.data! as Map<String, Object?>)['detail']!
          as Map<String, Object?>;

  Future<Response<Map<String, Object?>>> chat({String? lang}) =>
      dio.post<Map<String, Object?>>(
        '/ai-coach/chat',
        data: <String, Object?>{'message': '오늘 뭐 먹을까요'},
        options: Options(headers: <String, Object?>{'Accept-Language': ?lang}),
      );

  Future<Response<Map<String, Object?>>> analyze() {
    final FormData form = FormData.fromMap(<String, Object?>{
      'image': MultipartFile.fromBytes(<int>[1, 2, 3, 4], filename: 'meal.jpg'),
      'meal_type': 'lunch',
    });
    return dio.post<Map<String, Object?>>('/diet/analyze', data: form);
  }

  Future<Map<String, Object?>> quota() async =>
      (await dio.get<Map<String, Object?>>('/ai-coach/quota')).data!;

  Future<int> storedMessages() async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/ai-coach/messages');
    return (res.data!['messages']! as List<Object?>).length;
  }

  test('기본은 꺼져 있어 대화와 분석이 그대로 된다', () async {
    expect(api.demoAiCapacityReached, isFalse);
    expect((await chat()).statusCode, 200);
    expect((await analyze()).statusCode, 200);
  });

  group('상한에 걸린 날', () {
    setUp(() => api.demoAiCapacityReached = true);

    test('AI 코치 대화는 503 ai_capacity + Retry-After — 회원 몫을 깎지 않는다', () async {
      final Map<String, Object?> before = await quota();
      final int storedBefore = await storedMessages();

      final DioException error = await refused(chat());

      expect(error.response?.statusCode, 503);
      expect(error.response?.headers.value('retry-after'), isNotNull);
      expect(detailOf(error)['code'], 'ai_capacity');
      expect(await quota(), before);
      expect(await storedMessages(), storedBefore, reason: '대화를 저장하지 않는다');
    });

    test('영어 화면에는 영어 문구를 싣는다', () async {
      final DioException error = await refused(chat(lang: 'en'));

      expect(detailOf(error)['message'], contains('high demand'));
    });

    test('저장소가 읽는 거절은 대화 한도와 같은 길이다', () async {
      final DioException error = await refused(chat());

      final AiChatBlocked? blocked = AiChatBlocked.fromDetail(detailOf(error));
      expect(blocked?.reason, AiChatBlockReason.aiCapacity);
    });

    test('사진 분석은 503 ai_capacity — 끼니를 남기지 않고 직접 추가로 안내된다', () async {
      final DioException error = await refused(analyze());

      expect(error.response?.statusCode, 503);
      expect(detailOf(error)['code'], 'ai_capacity');
      expect(await db.select(db.dietEntries).get(), isEmpty);
      final DietAnalysisRejected? rejected =
          DietAnalysisRejected.fromResponseData(error.response?.data);
      expect(rejected?.failure, DietAnalysisFailure.aiCapacity);
      expect(rejected?.failure.offersManualEntry, isTrue);
    });
  });
}
