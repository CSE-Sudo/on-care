import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
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

  test('GET /ai-coach/feedback returns greeting + 3 suggestions', () async {
    final res = await dio.get<Map<String, Object?>>('/ai-coach/feedback');
    expect(res.statusCode, 200);
    expect(res.data!['greeting'], isNotEmpty);
    final suggestions = (res.data!['suggestions']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(suggestions.length, 3);
    final tags = suggestions.map((s) => s['tag']! as String).toSet();
    expect(
      tags,
      containsAll(<String>['diet', 'exercise', 'hydration']),
    );
  });

  test('GET /users/me returns the demo profile', () async {
    final res = await dio.get<Map<String, Object?>>('/users/me');
    expect(res.statusCode, 200);
    expect(res.data!['email'], 'minsu@oncare.com');
  });

  test('GET /users/me/health returns the full MyHealthState shape', () async {
    final res = await dio.get<Map<String, Object?>>('/users/me/health');
    expect(res.statusCode, 200);
    final body = res.data!;
    expect((body['profile']! as Map)['name'], '김민수');
    expect((body['risk']! as Map)['level'], 'medium');
    expect(body.containsKey('indicators'), isFalse);
    expect(body['activity_points'], kDemoOpeningPoints);
    final settings = (body['settings']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      settings.map((s) => s['kind']).toList(),
      <String>['my-profile', 'notification', 'support'],
    );
  });

  test('GET /places/nearby returns every category when unfiltered', () async {
    final res = await dio.get<List<Object?>>('/places/nearby');
    expect(res.statusCode, 200);
    final places = res.data!.cast<Map<String, Object?>>();
    final categories = places.map((p) => p['category']! as String).toSet();
    expect(
      categories,
      containsAll(<String>['medical', 'fitness', 'healthy_food', 'pharmacy']),
    );
  });

  test('GET /places/nearby honours the category filter (#329)', () async {
    // 필터를 무시하면 헬스장 찾기 시트에 병원·약국이 섞여 들어온다.
    final res = await dio.get<List<Object?>>(
      '/places/nearby',
      queryParameters: <String, Object?>{'category': 'fitness'},
    );
    final places = res.data!.cast<Map<String, Object?>>();
    expect(places, isNotEmpty);
    expect(
      places.map((p) => p['category']! as String).toSet(),
      <String>{'fitness'},
    );
    // 지도 핀을 찍으려면 좌표가 반드시 있어야 한다.
    expect(places.every((p) => p['lat'] != null && p['lng'] != null), isTrue);
  });

  test('GET /places/nearby 는 요청 중심 기준으로 거리를 다시 계산한다', () async {
    // 신촌(헬스장 찾기 중심)에서 보면 강남 시드 장소는 8km 넘게 떨어져 있다.
    const sinchonLat = 37.5559;
    const sinchonLng = 126.9368;
    final res = await dio.get<List<Object?>>(
      '/places/nearby',
      queryParameters: <String, Object?>{
        'lat': sinchonLat,
        'lng': sinchonLng,
        'radius_m': 20000,
        'category': 'fitness',
      },
    );
    final places = res.data!.cast<Map<String, Object?>>();
    expect(places, isNotEmpty);

    // 고정값이 아니라 중심에서 잰 값이어야 한다: 신촌 헬스장은 1km 이내.
    final near = places.first;
    expect((near['distance_meters']! as int), lessThan(1000));
    // 거리순 정렬
    final distances = places.map((p) => p['distance_meters']! as int).toList();
    expect(distances, orderedEquals(List<int>.of(distances)..sort()));
  });

  test('GET /places/nearby 거리 계산이 백엔드 _haversine_m 과 같다', () async {
    // 백엔드는 int(...) 로 절삭한다. round() 를 쓰면 1m 어긋난다(리뷰 지적).
    // 아래 기대값은 backend/app/api/v1/places.py 의 _haversine_m 실행 결과다.
    const sinchonLat = 37.5559;
    const sinchonLng = 126.9368;
    const expected = <String, int>{
      '휘트니스에이든': 126,
      '빌드업짐 PT 신촌점': 133,
      '신인규피티스튜디오': 177,
      '하이핏': 186,
    };

    final res = await dio.get<List<Object?>>(
      '/places/nearby',
      queryParameters: <String, Object?>{
        'lat': sinchonLat,
        'lng': sinchonLng,
        'radius_m': 20000,
        'category': 'fitness',
      },
    );
    final places = res.data!.cast<Map<String, Object?>>();
    for (final place in places) {
      final want = expected[place['name']! as String];
      if (want == null) continue;
      expect(
        place['distance_meters'],
        want,
        reason: '${place['name']} 거리가 백엔드 계산과 다름',
      );
    }
  });

  test('GET /places/nearby 는 radius_m 밖 장소를 제외한다', () async {
    // 서울시청 기준 500m 안에는 신촌 헬스장이 하나도 없다.
    final res = await dio.get<List<Object?>>(
      '/places/nearby',
      queryParameters: <String, Object?>{
        'lat': 37.5665,
        'lng': 126.9780,
        'radius_m': 500,
        'category': 'fitness',
      },
    );
    expect(res.data!.cast<Map<String, Object?>>(), isEmpty);
  });

  test('GET /healthz returns drift-local marker', () async {
    final res = await dio.get<Map<String, Object?>>('/healthz');
    expect(res.statusCode, 200);
    expect(res.data!['status'], 'ok');
    expect(res.data!['backend'], 'drift-local');
  });

  test('POST /ai-coach/chat returns a grounded reply with sources', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/ai-coach/chat',
      data: <String, Object?>{'message': '나트륨을 줄이려면 어떻게 해요?'},
    );
    expect(res.statusCode, 200);
    expect(res.data!['reply'], isNotEmpty);
    final sources = (res.data!['sources']! as List<Object?>).cast<String>();
    expect(sources, contains('나트륨 줄이기'));
  });

  test('POST /ai-coach/chat answers the dinner quick reply with today\'s meal', () async {
    // 빠른 질문 첫 줄. 일반적인 식단 안내가 아니라 오늘 점심(짬뽕) 기록과
    // 이어지는 한 끼가 나와야 "맞춤"으로 읽힌다(#1180).
    final res = await dio.post<Map<String, Object?>>(
      '/ai-coach/chat',
      data: <String, Object?>{'message': '오늘 저녁 메뉴 추천해줘'},
    );
    expect(res.statusCode, 200);
    final reply = res.data!['reply']! as String;
    expect(reply, contains('짬뽕'));
    expect(reply, contains('닭가슴살 채소구이'));
    expect(reply, contains('현미밥'));
  });

  test('POST /ai-coach/chat rejects an empty message', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/ai-coach/chat',
      data: <String, Object?>{'message': '   '},
      options: Options(validateStatus: (int? s) => true),
    );
    expect(res.statusCode, 400);
  });

  test('PUT /users/me persists profile; GET /users/me/profile + /users/me reflect it', () async {
    final put = await dio.put<Map<String, Object?>>(
      '/users/me',
      data: <String, Object?>{'name': '이순신', 'phone': '010-9999-0000'},
    );
    expect(put.statusCode, 200);
    expect(put.data!['name'], '이순신');

    final prof = await dio.get<Map<String, Object?>>('/users/me/profile');
    expect(prof.data!['name'], '이순신');
    expect(prof.data!['phone'], '010-9999-0000');
    expect(prof.data!['email'], 'minsu@oncare.com'); // 안 바꾼 값은 기본 유지

    final me = await dio.get<Map<String, Object?>>('/users/me');
    expect(me.data!['name'], '이순신');
  });

  test('PUT /users/me/health-goals persists weekly exercise goals', () async {
    final initialProfile = await dio.get<Map<String, Object?>>(
      '/users/me/profile',
    );
    expect(initialProfile.data!['weekly_workout_goal'], isNull);
    expect(initialProfile.data!['weekly_exercise_minutes_goal'], isNull);
    expect(initialProfile.data!['weekly_burn_goal'], isNull);

    final put = await dio.put<Map<String, Object?>>(
      '/users/me/health-goals',
      data: <String, Object?>{
        'weekly_workout_goal': 5,
        'weekly_exercise_minutes_goal': 240,
        'weekly_burn_goal': 900,
      },
    );
    expect(put.statusCode, 200);

    final profile = await dio.get<Map<String, Object?>>('/users/me/profile');
    expect(profile.data!['weekly_workout_goal'], 5);
    expect(profile.data!['weekly_exercise_minutes_goal'], 240);
    expect(profile.data!['weekly_burn_goal'], 900);
  });

  test('POST /auth/login issues a token for non-empty credentials', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/auth/login',
      data: <String, Object?>{'username': 'a@b.com', 'password': 'pw'},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    expect(res.statusCode, 200);
    expect((res.data!['access_token']! as String).isNotEmpty, isTrue);
    expect(res.data!['token_type'], 'bearer');
  });

  test('POST /auth/login rejects empty credentials', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/auth/login',
      data: <String, Object?>{'username': '', 'password': ''},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (int? s) => true,
      ),
    );
    expect(res.statusCode, 400);
  });

  test('POST /auth/register creates a user (201) for valid input', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/auth/register',
      data: <String, Object?>{
        'email': 'new@oncare.com',
        'password': 'password123',
        'name': '홍길동',
      },
    );
    expect(res.statusCode, 201);
    expect(res.data!['email'], 'new@oncare.com');
    expect(res.data!['name'], '홍길동');
    expect((res.data!['id']! as String).isNotEmpty, isTrue);
  });

  test('POST /auth/register defaults name to the email local-part', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/auth/register',
      data: <String, Object?>{
        'email': 'solo@oncare.com',
        'password': 'password123',
      },
    );
    expect(res.statusCode, 201);
    expect(res.data!['name'], 'solo');
  });

  test('POST /auth/register rejects empty credentials', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/auth/register',
      data: <String, Object?>{'email': '', 'password': ''},
      options: Options(validateStatus: (int? s) => true),
    );
    expect(res.statusCode, 400);
  });

  test('POST /users/me/onboarding persists fields + onboarded flag', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/users/me/onboarding',
      data: <String, Object?>{
        'birth_date': '1988-03-03',
        'gender': 'female',
        'conditions': '고혈압, 당뇨',
        'height_cm': 162,
        'daily_sodium_mg': 1500,
      },
    );
    expect(res.statusCode, 200);
    expect(res.data!['onboarded'], true);
    expect(res.data!['gender'], 'female');

    // GET /users/me/profile reflects the onboarding write.
    final prof = await dio.get<Map<String, Object?>>('/users/me/profile');
    expect(prof.data!['birth_date'], '1988-03-03');
    expect(prof.data!['conditions'], '고혈압, 당뇨');
    expect(prof.data!['height_cm'], 162);
    expect(prof.data!['daily_sodium_mg'], 1500);
    expect(prof.data!['onboarded'], true);
  });

  test('POST /auth/social/kakao issues a token for a provider token', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/auth/social/kakao',
      data: <String, Object?>{'token': 'kakao-oauth-token'},
    );
    expect(res.statusCode, 200);
    expect((res.data!['access_token']! as String).isNotEmpty, isTrue);
    expect(res.data!['token_type'], 'bearer');
  });

  test('POST /auth/social/google rejects an empty provider token', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/auth/social/google',
      data: <String, Object?>{'token': ''},
      options: Options(validateStatus: (int? s) => true),
    );
    expect(res.statusCode, 400);
  });

  test('DELETE /users/me withdraws and resets the profile overlay', () async {
    // Seed an overlay so we can prove the delete wiped it.
    await dio.put<Map<String, Object?>>(
      '/users/me',
      data: <String, Object?>{'name': '탈퇴예정'},
    );

    final del = await dio.delete<Map<String, Object?>>('/users/me');
    expect(del.statusCode, 200);
    expect(del.data!['status'], 'deleted');

    // Overlay wiped → profile back to defaults.
    final prof = await dio.get<Map<String, Object?>>('/users/me/profile');
    expect(prof.data!['name'], '김민수');
  });

  test('POST /schedule/events persists; GET returns it for that date', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/schedule/events',
      data: <String, Object?>{
        'date': '2026-07-04',
        'time': '15:30',
        'title': '치과 예약',
        'category': 'hospital',
      },
    );
    expect(res.statusCode, 201);
    expect(res.data!['title'], '치과 예약');
    expect(res.data!['emoji'], '🏥'); // derived from category
    expect((res.data!['id']! as String).isNotEmpty, isTrue);

    final list = await dio.get<List<Object?>>(
      '/schedule/events',
      queryParameters: <String, Object?>{'date': '2026-07-04'},
    );
    final titles = list.data!
        .cast<Map<String, Object?>>()
        .map((e) => e['title']);
    expect(titles, contains('치과 예약'));
  });

  test('POST /schedule/events rejects a missing title', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/schedule/events',
      data: <String, Object?>{'date': '2026-07-04', 'title': ''},
      options: Options(validateStatus: (int? s) => true),
    );
    expect(res.statusCode, 400);
  });

  test('DELETE /diet/entries/{id} deletes an entry; 404 once gone', () async {
    await db
        .into(db.dietEntries)
        .insert(
          DietEntriesCompanion.insert(
            id: 'del-diet-1',
            date: '2026-07-04',
            mealType: 'lunch',
            timeLabel: '12:00',
            foodsJson: '[]',
            totalCalories: 100,
          ),
        );

    final ok = await dio.delete<Map<String, Object?>>('/diet/entries/del-diet-1');
    expect(ok.statusCode, 200);
    expect(ok.data!['status'], 'deleted');

    final gone = await dio.delete<Map<String, Object?>>(
      '/diet/entries/del-diet-1',
      options: Options(validateStatus: (int? s) => true),
    );
    expect(gone.statusCode, 404);
  });

  test('DELETE /exercise/sessions/{id} deletes a session; 404 once gone', () async {
    await db
        .into(db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: 'del-ex-1',
            weekStart: '2026-06-29',
            dayLabel: '월',
            type: 'cardio',
            minutes: 30,
            calories: 200,
          ),
        );

    final ok = await dio.delete<Map<String, Object?>>(
      '/exercise/sessions/del-ex-1',
    );
    expect(ok.statusCode, 200);
    expect(ok.data!['status'], 'deleted');

    final gone = await dio.delete<Map<String, Object?>>(
      '/exercise/sessions/del-ex-1',
      options: Options(validateStatus: (int? s) => true),
    );
    expect(gone.statusCode, 404);
  });

  test('PUT /diet/entries/{id} updates meal type + time; 404 when missing', () async {
    await db
        .into(db.dietEntries)
        .insert(
          DietEntriesCompanion.insert(
            id: 'edit-diet-1',
            date: '2026-07-04',
            mealType: 'lunch',
            timeLabel: '12:00',
            foodsJson: '[]',
            totalCalories: 100,
          ),
        );

    final r = await dio.put<Map<String, Object?>>(
      '/diet/entries/edit-diet-1',
      data: <String, Object?>{'meal_type': 'dinner', 'time_label': '19:30'},
    );
    expect(r.statusCode, 200);
    expect(r.data!['meal_type'], 'dinner');
    expect(r.data!['time_label'], '19:30');

    final gone = await dio.put<Map<String, Object?>>(
      '/diet/entries/nope',
      data: <String, Object?>{'meal_type': 'dinner'},
      options: Options(validateStatus: (int? s) => true),
    );
    expect(gone.statusCode, 404);
  });

  test('PUT /exercise/sessions/{id} updates the session; 404 when missing', () async {
    await db
        .into(db.exerciseSessions)
        .insert(
          ExerciseSessionsCompanion.insert(
            id: 'edit-ex-1',
            weekStart: '2026-06-29',
            dayLabel: '월',
            type: 'cardio',
            minutes: 30,
            calories: 150,
          ),
        );

    final r = await dio.put<Map<String, Object?>>(
      '/exercise/sessions/edit-ex-1',
      data: <String, Object?>{
        'type': 'strength',
        'minutes': 50,
        'calories': 250,
        'day_label': '화',
      },
    );
    expect(r.statusCode, 200);
    expect(r.data!['type'], 'strength');
    expect(r.data!['minutes'], 50);

    final gone = await dio.put<Map<String, Object?>>(
      '/exercise/sessions/nope',
      data: <String, Object?>{'type': 'cardio', 'minutes': 10},
      options: Options(validateStatus: (int? s) => true),
    );
    expect(gone.statusCode, 404);
  });

  test('GET /schedule/events?month returns the whole month only', () async {
    for (final ({String id, String date, String cat}) e in <({
      String id,
      String date,
      String cat,
    })>[
      (id: 'm-1', date: '2029-09-03', cat: 'hospital'),
      (id: 'm-2', date: '2029-09-21', cat: 'meal'),
      (id: 'm-3', date: '2029-10-01', cat: 'other'),
    ]) {
      await db
          .into(db.scheduleEvents)
          .insert(
            ScheduleEventsCompanion.insert(
              id: e.id,
              date: e.date,
              time: '10:00',
              title: e.id,
              category: e.cat,
            ),
          );
    }

    final res = await dio.get<List<Object?>>(
      '/schedule/events',
      queryParameters: <String, Object?>{'month': '2029-09'},
    );
    expect(res.statusCode, 200);
    final ids = res.data!.cast<Map<String, Object?>>().map((e) => e['id']);
    expect(ids, containsAll(<String>['m-1', 'm-2']));
    expect(ids, isNot(contains('m-3'))); // 다른 달 제외
  });
}
