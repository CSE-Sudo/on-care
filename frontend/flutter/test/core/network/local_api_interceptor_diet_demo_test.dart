/// 식단이 인메모리 목업 저장소에서 로컬 인터셉터 경로로 옮겨 오면서, 데모 화면이
/// 그대로인지를 고정하는 회귀 테스트 — #616.
///
/// 옮기기 전 화면은 저장소가 들고 있던 값으로 그려졌다. 그 값 중 셋은 인터셉터
/// 경로에 자리가 없어서 새로 만들어야 했고, 하나라도 빠지면 시연 화면이 조용히
/// 달라진다.
///
///  * 끼니별 AI 코멘트 — 테이블에 컬럼이 없었다.
///  * 끼니 사진 — 인터셉터가 시드 id → 에셋 맵을 들고 있어 새 항목엔 붙지 않았다.
///  * 하루 코치 문구 — 저장소는 정해진 문장, 인터셉터는 나트륨 임계값 분기였다.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare/core/utils/clock.dart';

String _dateString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
  });

  tearDown(() => db.close());

  group('시드가 채운 데모 식단', () {
    setUp(() => seedIfEmpty(db));

    test('끼니마다 AI 코멘트와 사진이 함께 내려온다', () async {
      final res = await dio.get<Map<String, Object?>>('/diet/days/today');
      final entries = (res.data!['entries']! as List<Object?>)
          .cast<Map<String, Object?>>();

      expect(entries, isNotEmpty);
      for (final entry in entries) {
        expect(
          entry['ai_comment'],
          isA<String>().having((String s) => s.isNotEmpty, '비어 있지 않다', isTrue),
          reason: '${entry['meal_type']} 끼니에 코멘트가 없다',
        );
        expect(
          entry['photo_asset'],
          isA<String>().having(
            (String s) => s.startsWith('assets/images/'),
            '에셋 경로다',
            isTrue,
          ),
          reason: '${entry['meal_type']} 끼니에 사진이 없다',
        );
      }
    });

    test('하루 코치 문구는 수치가 아니라 시드가 정한 문장이다', () async {
      final res = await dio.get<Map<String, Object?>>('/diet/days/today');

      // 시드 하루 나트륨은 권장치를 넘는다. 수치 기반 분기를 그대로 쓰면 여기서
      // 일반 경고 문구가 나오고, 데모가 보여 주던 문장이 사라진다.
      expect(res.data!['total_sodium_mg'], greaterThan(2000));
      expect(res.data!['ai_coach_message'], contains('짬뽕'));
    });

    test('지난 날짜도 그 날짜의 문장을 쓴다', () async {
      final DateTime now = nowKst();
      final yesterday = _dateString(now.subtract(const Duration(days: 1)));
      final res = await dio.get<Map<String, Object?>>(
        '/diet/days/$yesterday',
      );

      // 문장은 픽스처가 갖고 있다 — 여기에 다시 적으면 두 벌이 되어 한쪽만 고쳤을 때
      // 조용히 갈린다(#757).
      final FixtureDay day = DemoFixture.parse(
        File(
          '../../shared/demo_fixture/assets/kim_minsu.json',
        ).readAsStringSync(),
      ).daysFor(now).firstWhere((FixtureDay d) => d.date == yesterday);
      expect(day.dayMessage, isNotEmpty, reason: '어제는 큐레이션된 날이다');
      expect(res.data!['ai_coach_message'], day.dayMessage);
    });

    test('끼니를 수정해도 코멘트와 사진이 남는다', () async {
      final today = await dio.get<Map<String, Object?>>('/diet/days/today');
      final first = (today.data!['entries']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .first;

      final res = await dio.put<Map<String, Object?>>(
        '/diet/entries/${first['id']}',
        data: <String, Object?>{'time_label': '09:00'},
      );

      expect(res.data!['time_label'], '09:00');
      expect(res.data!['ai_comment'], first['ai_comment']);
      expect(res.data!['photo_asset'], first['photo_asset']);
    });
  });

  group('시드가 없는 날짜', () {
    test('저장된 문장이 없으면 수치를 보고 만든 문구로 답한다', () async {
      // 시드를 돌리지 않았으므로 그 날짜에는 정해진 문장이 없다.
      final res = await dio.get<Map<String, Object?>>('/diet/days/2020-01-01');

      expect(res.data!['entries'], isEmpty);
      expect(res.data!['ai_coach_message'], contains('아직'));
    });
  });

  group('추천', () {
    test('개인화 근거가 없다고 밝히고 기본 순서를 돌려준다', () async {
      final res = await dio.get<Map<String, Object?>>('/diet/recommendations');

      final items = (res.data!['items']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(items.map((Map<String, Object?> e) => e['key']).toList(), <String>[
        'chicken_salad',
        'brown_rice_box',
        'salmon',
        'tofu',
        'namul_bibimbap',
      ]);
      // 근거가 없는데 있는 척하면 화면이 빈 근거 줄을 그린다.
      expect(res.data!['personalized'], isFalse);
      // reason_text 를 비워 둬야 카드 문구가 앱의 로케일 기본값을 쓴다.
      for (final item in items) {
        expect(item.containsKey('reason_text'), isFalse);
        expect(item['reason_key'], isA<String>());
      }
    });
  });

  group('분석 결과 저장', () {
    test('로컬이 만든 결과에도 코멘트가 함께 남는다', () async {
      await dio.post<Map<String, Object?>>(
        '/diet/analyze',
        data: <String, Object?>{'meal_type': 'dinner'},
      );

      final res = await dio.get<Map<String, Object?>>('/diet/days/today');
      final dinner = (res.data!['entries']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere((Map<String, Object?> e) => e['meal_type'] == 'dinner');

      expect(dinner['ai_comment'], contains('요거트 아이스크림'));
      // 업로드한 사진을 데모가 보관하지 않으므로 사진은 비워 둔다 — 남의 사진을
      // 대신 보여 주는 것보다 없는 편이 정직하다.
      expect(dinner['photo_asset'], isNull);
    });

    // 데모 분석도 음식마다 양을 준다 — 실서버 스텁과 같은 1회 섭취량(#2090).
    // 비어 있으면 분석 완료 시트에 끼니 내용량이 뜨지 않는다.
    test('인식된 모든 음식에 내용량이 실리고 저장까지 이어진다', () async {
      final res = await dio.post<Map<String, Object?>>(
        '/diet/analyze',
        data: <String, Object?>{'meal_type': 'dinner'},
      );
      final analysis = res.data!['analysis']! as Map<String, Object?>;
      final foods = (analysis['foods']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        foods.map((Map<String, Object?> f) => f['amount_g']).toList(),
        <Object?>[110, 90, 50],
      );

      final today = await dio.get<Map<String, Object?>>('/diet/days/today');
      final dinner = (today.data!['entries']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere((Map<String, Object?> e) => e['meal_type'] == 'dinner');
      final stored = (dinner['foods']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        stored.every((Map<String, Object?> f) => (f['amount_g'] as num) > 0),
        isTrue,
      );
    });

    test('같은 멱등키로 다시 보내도 코멘트를 잃지 않는다', () async {
      Future<Response<Map<String, Object?>>> send() => dio.post(
        '/diet/analyze',
        data: <String, Object?>{
          'meal_type': 'dinner',
          'idempotency_key': 'same-key',
        },
      );

      final first = await send();
      final second = await send();

      final firstAnalysis = first.data!['analysis']! as Map<String, Object?>;
      final secondAnalysis = second.data!['analysis']! as Map<String, Object?>;
      expect(second.data!['entry_id'], first.data!['entry_id']);
      expect(secondAnalysis['coach_comment'], firstAnalysis['coach_comment']);
    });
  });

  group('실 백엔드가 분석했을 때', () {
    late Dio realAnalyzeDio;

    setUp(() async {
      await seedIfEmpty(db);
      realAnalyzeDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      realAnalyzeDio.interceptors.add(
        LocalApiInterceptor(
          db,
          Logger(level: Level.off),
          // REAL_API=diet 과 같은 판정 — 분석만 실 백엔드로 나간다.
          isRealApi: (String method, String path) =>
              method == 'POST' && path.startsWith('/diet/analyze'),
        ),
      );
      // 실 네트워크 대신 서버 응답을 흉내 내는 어댑터. 인터셉터의 응답 반영이
      // 동작하는지가 확인 대상이라 서버는 흉내로 충분하다.
      realAnalyzeDio.httpClientAdapter = _StubAdapter();
    });

    test('서버가 인식한 끼니가 로컬 오늘 식단에 나타난다', () async {
      final before = await dio.get<Map<String, Object?>>('/diet/days/today');
      final beforeCount = (before.data!['entries']! as List<Object?>).length;

      await realAnalyzeDio.post<Map<String, Object?>>(
        '/diet/analyze',
        data: <String, Object?>{'meal_type': 'dinner'},
      );

      final after = await dio.get<Map<String, Object?>>('/diet/days/today');
      final entries = (after.data!['entries']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(entries, hasLength(beforeCount + 1));

      final added = entries.firstWhere(
        (Map<String, Object?> e) => e['id'] == 'server-entry-1',
      );
      expect(added['meal_type'], 'dinner');
      expect(added['total_calories'], 420);
      expect(added['ai_comment'], '서버가 만든 코멘트');
    });

    test('조회는 여전히 로컬이 답한다 — 데모 기록이 서버 것으로 바뀌지 않는다', () async {
      final res = await realAnalyzeDio.get<Map<String, Object?>>(
        '/diet/days/today',
      );

      // 어댑터가 답했다면 시드 끼니가 아니라 스텁 응답이 왔을 것이다.
      expect(res.data!['ai_coach_message'], contains('짬뽕'));
    });
  });
}

/// `/diet/analyze` 에만 답하는 가짜 서버.
class _StubAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{
        'entry_id': 'server-entry-1',
        'analysis': <String, Object?>{
          'engine': 'gemini',
          'foods': <Map<String, Object?>>[
            <String, Object?>{
              'name': '연어구이',
              'calories': 420,
              'sodium_mg': 500,
              'sugar_g': 2.0,
              'carbs_g': 4.0,
              'protein_g': 38.0,
              'fat_g': 26.0,
            },
          ],
          'total_calories': 420,
          'total_sodium_mg': 500,
          'total_sugar_g': 2.0,
          'coach_comment': '서버가 만든 코멘트',
        },
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}
