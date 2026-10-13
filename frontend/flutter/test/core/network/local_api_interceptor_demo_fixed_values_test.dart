/// 데모가 기록·입력과 상관없는 고정값을 보여 주던 곳들(#2661).
///
/// 데모는 실서버 화면을 그대로 보여 줘야 한다. 목업 인터셉터가 서버와 같은
/// 규칙으로 답하는지를 여기서 고정한다.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare_core/clock.dart';

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

  String wire(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  group('MY 프로필 카드', () {
    test('내 프로필에서 바꾼 이름·이메일이 /users/me/health 에 보인다', () async {
      await dio.put<Map<String, Object?>>(
        '/users/me',
        data: <String, Object?>{
          'name': '김민지',
          'email': 'minji@oncare.com',
          // 이메일 변경은 본인 확인을 거친다(#3039). 테스트 전용 값이다.
          'current_password': 'pw-current-1',
          // 새 주소 인증 코드(#3230). 데모는 고정 코드를 받는다.
          'email_code': '000000',
        },
      );

      final res = await dio.get<Map<String, Object?>>('/users/me/health');
      final Map<Object?, Object?> profile =
          res.data!['profile']! as Map<Object?, Object?>;
      expect(profile['name'], '김민지');
      expect(profile['email'], 'minji@oncare.com');
      expect(profile['id'], 'user-7d4e9a2c5f18');
    });

    test('목업 저장소도 저장된 프로필을 읽는다', () async {
      await db.putValue(
        'profile_overlay',
        jsonEncode(<String, Object?>{
          'name': '김민지',
          'email': 'minji@oncare.com',
        }),
      );

      final MyHealthState state = await MockMyHealthRepository(
        db: db,
      ).fetchState();
      expect(state.profile.name, '김민지');
      expect(state.profile.email, 'minji@oncare.com');
    });

    test('저장된 프로필이 없으면 데모 기본값이다', () async {
      final MyHealthState state = await MockMyHealthRepository(
        db: db,
      ).fetchState();
      expect(state.profile.name, '김민수');
      expect(state.profile.email, 'minsu@oncare.com');
    });
  });

  group('수동 영양 검색', () {
    test('시드에 있는 PT 식단 이름도 같은 음식으로 찾는다', () async {
      final res = await dio.post<Map<String, Object?>>(
        '/diet/nutrition',
        data: <String, Object?>{'name': '닭가슴살'},
      );
      expect(res.data!['matched_name'], '닭가슴살');
      expect(res.data!['match'], 'exact');
      // 백엔드 시드: 100g 당 144kcal · 나트륨 328mg, 1회 100g.
      expect(res.data!['calories'], 144);
      expect(res.data!['sodium_mg'], 328);
    });
  });

  group('식단 추천', () {
    test('최근 기록에서 신호를 뽑아 맞는 메뉴를 앞으로 올린다', () async {
      final DateTime now = nowKst();
      final res = await dio.post<Map<String, Object?>>(
        '/diet/entries',
        data: <String, Object?>{
          'date': wire(DateTime(now.year, now.month, now.day)),
          'meal_type': 'lunch',
          'foods': <Map<String, Object?>>[
            <String, Object?>{
              'name': '떡볶이',
              'calories': 1900,
              'carbs_g': 300,
              'protein_g': 80,
              'fat_g': 40,
              'sodium_mg': 500,
              'sugar_g': 60,
            },
          ],
        },
      );
      expect(res.statusCode, 201);

      final rec = await dio.get<Map<String, Object?>>('/diet/recommendations');
      // 당류·열량 과다 — 서버 `_rule_rank` 와 같은 순서다.
      expect(
        (rec.data!['items']! as List<Object?>)
            .map((Object? e) => (e! as Map<Object?, Object?>)['key'])
            .toList(),
        <String>[
          'brown_rice_box',
          'tofu',
          'namul_bibimbap',
          'chicken_salad',
          'salmon',
        ],
      );
      expect(rec.data!['personalized'], isTrue);
      expect(rec.data!['days_with_data'], 1);
      expect(rec.data!['avg_sodium_mg'], 500);
      expect(rec.data!['sodium_limit_mg'], 2000);
    });
  });

  // 단백질 부족 신호는 식단 조언과 같은 실효 목표(개인 목표 → 체중 × 1.2g →
  // 60g)로 본다(#3270) — 서버 `build_context` 와 같다. 예전에는 개인 목표가
  // 있을 때만 봐, 목표 칸을 비운 회원은 단백질 메뉴가 앞으로 오지 않았다.
  group('추천 식단 단백질 부족', () {
    Future<void> logToday({required int proteinG}) async {
      final DateTime now = nowKst();
      final res = await dio.post<Map<String, Object?>>(
        '/diet/entries',
        data: <String, Object?>{
          'date': wire(DateTime(now.year, now.month, now.day)),
          'meal_type': 'lunch',
          'foods': <Map<String, Object?>>[
            // 칼로리·나트륨·당류는 신호 사이 — 단백질만 갈린다.
            <String, Object?>{
              'name': '비빔국수',
              'calories': 1500,
              'carbs_g': 250,
              'protein_g': proteinG,
              'fat_g': 30,
              'sodium_mg': 500,
              'sugar_g': 10,
            },
          ],
        },
      );
      expect(res.statusCode, 201);
    }

    Future<Map<String, Object?>> recommend() async =>
        (await dio.get<Map<String, Object?>>('/diet/recommendations')).data!;

    List<Object?> keys(Map<String, Object?> body) => <Object?>[
      for (final Object? e in body['items']! as List<Object?>)
        (e! as Map<Object?, Object?>)['key'],
    ];

    test('개인 목표 없이 체중만 있으면 체중 × 1.2g 의 60% 이하가 부족이다', () async {
      // 데모 회원 72kg → 실효 86g, 문턱 51.6g. 하루 40g 은 부족이다.
      await dio.put<Map<String, Object?>>(
        '/users/me/health-goals',
        data: <String, Object?>{'daily_protein_g': null},
      );
      await logToday(proteinG: 40);

      final Map<String, Object?> body = await recommend();

      expect(keys(body), <String>[
        'chicken_salad',
        'salmon',
        'brown_rice_box',
        'tofu',
        'namul_bibimbap',
      ]);
      expect(body['personalized'], isTrue);
    });

    test('개인 목표가 있으면 그것이 기준이다 — 체중으로는 부족이어도', () async {
      // 개인 목표 50g 의 60% 는 30g — 하루 45g 은 부족이 아니다. 체중(86g)으로
      // 보면 부족이지만 개인 목표가 먼저다.
      await dio.put<Map<String, Object?>>(
        '/users/me/health-goals',
        data: <String, Object?>{'daily_protein_g': 50},
      );
      await logToday(proteinG: 45);

      final Map<String, Object?> body = await recommend();

      expect(body['personalized'], isFalse);
      expect(keys(body).first, 'chicken_salad');
      expect(keys(body)[1], 'brown_rice_box');
    });
  });

  group('헬스장 발견', () {
    test('신촌 밖(강남역)에서도 주변 헬스장이 나온다', () async {
      final res = await dio.get<List<Object?>>(
        '/places/nearby',
        queryParameters: <String, Object?>{
          'lat': 37.4979,
          'lng': 127.0276,
          'radius_m': 3000,
          'category': 'fitness',
        },
      );
      final List<Map<String, Object?>> places = res.data!
          .cast<Map<String, Object?>>();
      expect(places, isNotEmpty);
      expect(
        places.every((Map<String, Object?> p) => p['category'] == 'fitness'),
        isTrue,
      );
      expect(
        places.map((Map<String, Object?> p) => p['name']),
        contains('스포애니 강남역1호점'),
      );
    });
  });
}
