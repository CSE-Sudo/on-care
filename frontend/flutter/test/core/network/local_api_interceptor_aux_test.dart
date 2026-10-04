import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppInputRules;

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

  test('GET /ai-coach/feedback returns diet + exercise', () async {
    final res = await dio.get<Map<String, Object?>>('/ai-coach/feedback');
    expect(res.statusCode, 200);
    expect(res.data!['greeting'], isNotEmpty);
    final suggestions = (res.data!['suggestions']! as List<Object?>)
        .cast<Map<String, Object?>>();
    // 실서버와 같은 식단·운동 두 건 — 데모 코칭 시트의 카드 구성이다(#2706).
    final tags = suggestions.map((s) => s['tag']! as String).toList();
    expect(tags, <String>['diet', 'exercise']);
  });

  test('GET /users/me returns the demo profile', () async {
    final res = await dio.get<Map<String, Object?>>('/users/me');
    expect(res.statusCode, 200);
    expect(res.data!['email'], 'minsu@oncare.com');
  });

  test('GET /users/me/health returns the same shape as the server', () async {
    final res = await dio.get<Map<String, Object?>>('/users/me/health');
    expect(res.statusCode, 200);
    final body = res.data!;
    // 실서버와 같은 두 키뿐 — 고정 위험 문구·순위·설정 메뉴는 없다(#2903).
    expect(body.keys.toSet(), <String>{'profile', 'activity_points'});
    expect((body['profile']! as Map)['name'], '김민수');
    expect(body['activity_points'], kDemoOpeningPoints);
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
    expect(places.map((p) => p['category']! as String).toSet(), <String>{
      'fitness',
    });
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
      '온케어 핏스튜디오': 126,
      '온케어 PT랩': 133,
      '온케어 1:1 스튜디오': 177,
      '온케어 무브랩': 186,
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
    expect(res.data!['commit_sha'], 'unknown');
  });

  test('GET /version matches the server keys including commit_sha', () async {
    final res = await dio.get<Map<String, Object?>>('/version');
    expect(res.statusCode, 200);
    expect(res.data!['api_version'], 'v1');
    expect(res.data!.keys.toSet(), <String>{
      'api_version',
      'app_version',
      'min_app_version',
      'commit_sha',
    });
    expect(res.data!['commit_sha'], 'unknown');
    // 데모는 최소 지원 버전을 두지 않는다 — 업데이트 화면이 뜨지 않는다(#3045).
    expect(res.data!['min_app_version'], isNull);
  });

  test('POST /ai-coach/chat returns a grounded reply with sources', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/ai-coach/chat',
      data: <String, Object?>{'message': '나트륨을 줄이려면 어떻게 해요?'},
    );
    expect(res.statusCode, 200);
    expect(res.data!['reply'], isNotEmpty);
    final sources = (res.data!['sources']! as List<Object?>).cast<String>();
    // 목업도 서버가 실제로 돌려주는 공개 문서 제목을 그대로 싣는다(#1652).
    expect(sources, contains('2025 한국인 영양소 섭취기준 · 보건복지부/한국영양학회 — 나트륨과 염소'));
  });

  test(
    'POST /ai-coach/chat answers the dinner quick reply with today\'s meal',
    () async {
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
    },
  );

  test('POST /ai-coach/chat rejects an empty message', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/ai-coach/chat',
      data: <String, Object?>{'message': '   '},
      options: Options(validateStatus: (int? s) => true),
    );
    expect(res.statusCode, 400);
  });

  test(
    'PUT /users/me persists profile; GET /users/me/profile + /users/me reflect it',
    () async {
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
    },
  );

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

  test('POST /auth/refresh 는 데모에서도 받아 준다 (#1944)', () async {
    // 라우트 표에 없으면 갱신 요청이 두 인터셉터를 모두 지나쳐 **실제
    // apiBaseUrl 로 나간다** — #966 이 /auth/logout 에 대해 막았던 그 누출이다.
    final res = await dio.post<Map<String, Object?>>(
      '/auth/refresh',
      data: <String, Object?>{'refresh_token': 'demo-refresh'},
    );
    expect(res.statusCode, 200);
    expect((res.data!['access_token']! as String).isNotEmpty, isTrue);
    // 회전 토큰을 새로 주지 않는 서버도 있다 — 쓰던 것을 그대로 돌려준다.
    expect(res.data!['refresh_token'], 'demo-refresh');
  });

  test('POST /auth/refresh 는 갱신 토큰이 없으면 400 이다', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/auth/refresh',
      data: <String, Object?>{'refresh_token': ''},
      options: Options(validateStatus: (int? s) => true),
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
        'email_code': '000000',
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
        'email_code': '000000',
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

  // 목업 가입도 서버와 같은 비밀번호 기준을 본다 — 목업에서만 되는 비밀번호가
  // 있으면 실서버에서 처음 실패를 보게 된다(#1555).
  group('POST /auth/register 비밀번호 기준(#1555)', () {
    Future<Response<Map<String, Object?>>> register(String password) =>
        dio.post<Map<String, Object?>>(
          '/auth/register',
          data: <String, Object?>{
            'email': 'policy@oncare.com',
            'password': password,
            'name': '정책',
            'email_code': '000000',
          },
          options: Options(validateStatus: (int? s) => true),
        );

    for (final MapEntry<String, String> c in <String, String>{
      '': 'password_empty',
      'abc1234': 'password_weak',
      '12345678': 'password_weak',
      'abcdefgh': 'password_weak',
      '        ': 'password_weak',
      '${'a1' * 32}x': 'password_too_long',
      '${'가' * 22}abc1234': 'password_too_long',
    }.entries) {
      test(
        '"${c.key.length > 12 ? '${c.key.substring(0, 12)}…' : c.key}" → 422 ${c.value}',
        () async {
          final res = await register(c.key);
          expect(res.statusCode, 422);
          final List<Object?> detail = res.data!['detail']! as List<Object?>;
          final Map<String, Object?> item =
              detail.single! as Map<String, Object?>;
          expect(item['type'], c.value);
          expect(item['loc'], <Object?>['body', 'password']);
          // 앱이 서버 응답을 읽는 것과 같은 방법으로 읽힌다.
          expect(AppInputRules.serverPasswordError(res.data), isNotNull);
        },
      );
    }

    for (final String ok in <String>[
      'abcd1234',
      'a1' * 32,
      '${'가' * 22}abc123',
      ' abcd123 ',
    ]) {
      test('기준에 맞으면 201 (${ok.runes.length}자)', () async {
        final res = await register(ok);
        expect(res.statusCode, 201);
      });
    }
  });

  // MY 건강 목표가 보내는 건강 목표도 저장한다. 빠져 있어 데모에서 고른 목표가
  // 사라졌다(#1814). 자유 입력 목표(`goals`)는 없앴다 — 보내도 남지 않는다(#2358).
  test('PUT /users/me/health-goals 가 건강 목표를 저장하고 자유 목표는 버린다', () async {
    final res = await dio.put<Map<String, Object?>>(
      '/users/me/health-goals',
      data: <String, Object?>{
        'conditions': '혈압 관리, 비만, 무릎 통증',
        'goals': '주 3회 근력 운동',
        'daily_calories': 2100,
      },
    );
    expect(res.statusCode, 200);

    final prof = await dio.get<Map<String, Object?>>('/users/me/profile');
    expect(prof.data!['conditions'], '체중 감량, 혈압 관리, 무릎 통증');
    expect(prof.data!.containsKey('goals'), isFalse);
    expect(prof.data!['daily_calories'], 2100);
  });

  test('POST /users/me/onboarding persists fields + onboarded flag', () async {
    final res = await dio.post<Map<String, Object?>>(
      '/users/me/onboarding',
      data: <String, Object?>{
        'birth_date': '1988-03-03',
        'gender': 'female',
        // 옛 질환 이름으로 보내도 서버처럼 새 건강 목표로 정리한다(#1814).
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
    expect(prof.data!['conditions'], '혈압 관리');
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

    // 탈퇴는 본인 확인을 거친다(#3039). 테스트 전용 값이다.
    final del = await dio.delete<Map<String, Object?>>(
      '/users/me',
      data: <String, Object?>{'current_password': 'pw-current-1'},
    );
    expect(del.statusCode, 200);
    expect(del.data!['status'], 'deleted');

    // Overlay wiped → profile back to defaults.
    final prof = await dio.get<Map<String, Object?>>('/users/me/profile');
    expect(prof.data!['name'], '김민수');
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

    final ok = await dio.delete<Map<String, Object?>>(
      '/diet/entries/del-diet-1',
    );
    expect(ok.statusCode, 200);
    expect(ok.data!['status'], 'deleted');

    final gone = await dio.delete<Map<String, Object?>>(
      '/diet/entries/del-diet-1',
      options: Options(validateStatus: (int? s) => true),
    );
    expect(gone.statusCode, 404);
  });

  test(
    'DELETE /exercise/sessions/{id} deletes a session; 404 once gone',
    () async {
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
    },
  );

  test(
    'PUT /diet/entries/{id} updates meal type + time; 404 when missing',
    () async {
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
    },
  );

  test(
    'PUT /exercise/sessions/{id} updates the session; 404 when missing',
    () async {
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
    },
  );
}
