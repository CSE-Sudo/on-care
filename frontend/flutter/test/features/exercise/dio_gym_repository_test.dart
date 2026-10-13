import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/exercise/data/repositories/dio_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/gym_search_area.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';

/// 백엔드 실응답을 그대로 돌려주는 어댑터. 필드명이 어긋나면 여기서 걸린다.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.routes);
  final Map<String, Object?> routes;
  final List<String> calls = <String>[];
  final Map<String, Map<String, dynamic>> queries =
      <String, Map<String, dynamic>>{};

  /// 경로에 실제로 실려 나간 query parameter.
  Map<String, dynamic> queryOf(String path) =>
      queries[path] ?? <String, dynamic>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) async {
    calls.add('${options.method} ${options.path}');
    queries[options.path] = Map<String, dynamic>.from(options.queryParameters);
    final body = routes[options.path];
    if (body == null) {
      return ResponseBody.fromString(
        '{"detail":"not found"}',
        404,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      _encode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  static String _encode(Object? v) {
    // dart:convert 를 쓰지 않고 미리 만든 JSON 문자열을 그대로 쓴다.
    return v! as String;
  }

  @override
  void close({bool force = false}) {}
}

/// `GET /v1/gyms` 실응답(gym_service.GymOut) 그대로.
const String _gymsJson = '''
[{"id":"gym-oncare-sinchon","name":"온케어짐 신촌점","address":"서울 서대문구 신촌로 120",
  "distance_km":0.0,"rating":4.7,"tags":["다이어트","재활운동"],
  "weekday_hours":"06:00 – 23:00","weekend_hours":"08:00 - 20:00",
  "phone":"02-1234-5678","lat":37.5559,"lng":126.9368,"is_partner":true}]
''';

/// `GET /v1/gyms/{id}` 실응답(단일 객체).
const String _gymDetailJson = '''
{"id":"gym-oncare-sinchon","name":"온케어짐 신촌점","address":"서울 서대문구 신촌로 120",
 "distance_km":0.0,"rating":4.7,"tags":["다이어트","재활운동"],
 "weekday_hours":"06:00 – 23:00","weekend_hours":"08:00 - 20:00",
 "phone":"02-1234-5678","lat":37.5559,"lng":126.9368,"is_partner":true}
''';

/// 서버가 아직 보내는 모양 — `reason` 한 칸에 문자열 하나.
const String _trainersJson = '''
[{"id":"trainer-demo","gym_id":"gym-oncare-sinchon","name":"김트레이너",
  "role":"퍼스널 트레이너","reason":"혈압 관리","career":"7년",
  "intro":"혈압 관리와 체중 감량을 함께 다루는 퍼스널 트레이너입니다.",
  "certifications":["생활스포츠지도사 2급","퍼스널트레이닝 CPT"]}]
''';

/// 계약이 넓어졌을 때의 모양 — 같은 칸에 배열이 온다(#1881).
const String _trainersManyReasonsJson = '''
[{"id":"trainer-demo","gym_id":"gym-oncare-sinchon","name":"김트레이너",
  "role":"퍼스널 트레이너","reason":["혈압 관리","체중 감량"],"career":"7년"},
 {"id":"trainer-bare","gym_id":"gym-oncare-sinchon","name":"박트레이너"}]
''';

/// `GET /v1/reservations/me` 실응답 — 늦은 예약부터(#980).
const String _reservationsJson = '''
[{"id":"resv-2","slot_id":"slot-2","trainer_id":"trainer-demo",
  "starts_at":"2026-03-02T02:00:00+00:00","cancellable":true},
 {"id":"resv-1","slot_id":"slot-1","trainer_id":"trainer-demo",
  "starts_at":"2026-03-02T01:00:00+00:00","cancellable":false}]
''';

/// `GET /v1/gyms/search` 실응답 — 등록된 헬스장 한 곳과 외부 검색에서만 찾은 한 곳.
/// 뒤쪽은 평점·태그·영업시간이 비어 온다(#3355).
const String _gymSearchJson = '''
[{"id":"gym-oncare-sinchon","name":"온케어짐 신촌점","address":"서울 서대문구 신촌로 120",
  "distance_km":0.4,"rating":4.7,"tags":["다이어트","재활운동"],
  "weekday_hours":"06:00 – 23:00","weekend_hours":"08:00 - 20:00",
  "phone":"02-1234-5678","lat":37.5559,"lng":126.9368,"is_partner":true},
 {"id":"328969863","name":"온케어 부산짐","address":"부산 해운대구 테스트로 1",
  "distance_km":325.2,"rating":0.0,"tags":[],
  "weekday_hours":null,"weekend_hours":null,
  "phone":null,"lat":35.1631,"lng":129.1636,"is_partner":false}]
''';

Dio _dio(_StubAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://x/v1'))..httpClientAdapter = adapter;

void main() {
  group('이름 검색 (#3355)', () {
    test('GET /gyms/search 에 검색어를 q 로 싣는다', () async {
      final adapter = _StubAdapter(<String, Object?>{
        '/gyms/search': _gymSearchJson,
      });
      await DioGymRepository(_dio(adapter)).searchGyms('온케어 부산');

      expect(adapter.calls, <String>['GET /gyms/search']);
      expect(adapter.queryOf('/gyms/search')['q'], '온케어 부산');
    });

    test('회원 위치가 없으면 좌표를 싣지 않는다 — 기본 검색 영역도 보내지 않는다', () async {
      final adapter = _StubAdapter(<String, Object?>{'/gyms/search': '[]'});
      await DioGymRepository(_dio(adapter)).searchGyms('온케어');

      final Map<String, dynamic> query = adapter.queryOf('/gyms/search');
      expect(query.keys, <String>['q']);
    });

    test('회원 위치를 얻었으면 좌표를 함께 싣는다', () async {
      final adapter = _StubAdapter(<String, Object?>{'/gyms/search': '[]'});
      await DioGymRepository(
        _dio(adapter),
        lat: 35.1,
        lng: 129.1,
      ).searchGyms('온케어');

      final Map<String, dynamic> query = adapter.queryOf('/gyms/search');
      expect(query['q'], '온케어');
      expect(query['lat'], 35.1);
      expect(query['lng'], 129.1);
    });

    test('응답이 서버가 준 순서 그대로 Gym 으로 매핑된다', () async {
      final adapter = _StubAdapter(<String, Object?>{
        '/gyms/search': _gymSearchJson,
      });
      final List<Gym> gyms = await DioGymRepository(
        _dio(adapter),
      ).searchGyms('온케어');

      expect(gyms.map((Gym g) => g.id), <String>[
        'gym-oncare-sinchon',
        '328969863',
      ]);
      expect(gyms.first.rating, 4.7);
      expect(gyms.first.distanceKm, 0.4);
    });

    test('외부 검색에서만 찾은 헬스장은 빈 칸을 비운 채 읽는다', () async {
      final adapter = _StubAdapter(<String, Object?>{
        '/gyms/search': _gymSearchJson,
      });
      final Gym found = (await DioGymRepository(
        _dio(adapter),
      ).searchGyms('온케어')).last;

      expect(found.name, '온케어 부산짐');
      expect(found.rating, 0);
      expect(found.tags, isEmpty);
      expect(found.phone, isNull);
      expect(found.weekdayHours, isNull);
      expect(found.weekendHours, isNull);
      expect(found.hasCoordinates, isTrue);
    });

    test('빈 배열은 빈 목록이다', () async {
      final adapter = _StubAdapter(<String, Object?>{'/gyms/search': '[]'});
      expect(await DioGymRepository(_dio(adapter)).searchGyms('없는곳'), isEmpty);
    });

    test('서버 오류는 삼키지 않는다 — 화면이 오류 상태를 그린다', () async {
      // 라우트가 없으면 어댑터가 404 를 준다.
      final adapter = _StubAdapter(<String, Object?>{});
      await expectLater(
        DioGymRepository(_dio(adapter)).searchGyms('온케어'),
        throwsA(isA<DioException>()),
      );
    });
  });

  test('사용자 좌표를 목록과 내 헬스장 API에 전달한다', () async {
    final adapter = _StubAdapter({'/gyms': '[]'});
    final dio = Dio()..httpClientAdapter = adapter;
    final repo = DioGymRepository(dio, lat: 35.1, lng: 129.1);
    await repo.fetchNearby();
    await repo.fetchMyGym();
    for (final path in ['/gyms', '/me/gym']) {
      expect(adapter.queryOf(path)['lat'], 35.1);
      expect(adapter.queryOf(path)['lng'], 129.1);
    }
    dio.close();
  });

  test('GET /gyms 응답이 Gym 으로 매핑된다', () async {
    final adapter = _StubAdapter(<String, Object?>{'/gyms': _gymsJson});
    final gyms = await DioGymRepository(_dio(adapter)).fetchNearby();

    expect(gyms, hasLength(1));
    final Gym g = gyms.single;
    expect(g.id, 'gym-oncare-sinchon');
    expect(g.name, '온케어짐 신촌점');
    expect(g.rating, 4.7);
    expect(g.tags, <String>['다이어트', '재활운동']);
    expect(g.phone, '02-1234-5678');
    expect(g.weekdayHours, '06:00 – 23:00');
    // 지도 핀에 필요하다.
    expect(g.hasCoordinates, isTrue);
  });

  test('회원 위치가 없으면 목록은 기본 검색 영역을 검색 중심으로 보낸다 (#3044)', () async {
    final adapter = _StubAdapter(<String, Object?>{'/gyms': _gymsJson});
    await DioGymRepository(_dio(adapter)).fetchNearby();

    expect(adapter.calls, contains('GET /gyms'));
    // 경로만 보면 lat/lng 가 빠져도 통과한다 — 값까지 확인한다. 목록은 검색
    // 중심이 필요하다. 그 거리는 화면이 감춘다.
    final Map<String, dynamic> q = adapter.queryOf('/gyms');
    expect(q['lat'], kGymDefaultAreaLat);
    expect(q['lng'], kGymDefaultAreaLng);
  });

  test('회원 위치가 없으면 /me/gym 에 좌표를 싣지 않는다 (#3044)', () async {
    // 예전에는 늘 신촌 좌표가 실려, 회원과 무관한 거리가 엔티티에 들어왔다.
    final adapter = _StubAdapter(<String, Object?>{'/me/gym': _gymDetailJson});
    await DioGymRepository(_dio(adapter)).fetchMyGym();

    final Map<String, dynamic> q = adapter.queryOf('/me/gym');
    expect(q.containsKey('lat'), isFalse);
    expect(q.containsKey('lng'), isFalse);
  });

  test('좌표가 하나만 있으면 /me/gym 에 싣지 않는다', () async {
    // 서버는 한쪽만 오면 422 다 — 반쪽 좌표는 아예 보내지 않는다.
    final adapter = _StubAdapter(<String, Object?>{
      '/me/gym': _gymDetailJson,
      '/gyms': '[]',
    });
    final repo = DioGymRepository(_dio(adapter), lat: 35.1);
    await repo.fetchMyGym();
    await repo.fetchNearby();

    expect(adapter.queryOf('/me/gym'), isEmpty);
    expect(adapter.queryOf('/gyms')['lat'], kGymDefaultAreaLat);
  });

  test('GET /trainers 응답이 Trainer 로 매핑된다', () async {
    final adapter = _StubAdapter(<String, Object?>{'/trainers': _trainersJson});
    final trainers = await DioGymRepository(_dio(adapter)).fetchAllTrainers();

    final Trainer t = trainers.single;
    expect(t.id, 'trainer-demo');
    expect(t.gymId, 'gym-oncare-sinchon');
    expect(t.role, '퍼스널 트레이너');
    // 단수 문자열은 한 칸짜리 목록으로 읽는다 — 화면은 배지를 여럿 그린다.
    expect(t.reasons, <String>['혈압 관리']);
    expect(t.career, '7년');
    expect(t.certifications, hasLength(2));
  });

  test('추천 사유가 배열로 와도, 아예 없어도 읽는다 (#1881)', () async {
    final adapter = _StubAdapter(<String, Object?>{
      '/trainers': _trainersManyReasonsJson,
    });
    final trainers = await DioGymRepository(_dio(adapter)).fetchAllTrainers();

    expect(trainers.first.reasons, <String>['혈압 관리', '체중 감량']);
    // 사유 칸이 없으면 빈 목록이다 — 화면이 배지 자리를 통째로 접는다.
    expect(trainers.last.reasons, isEmpty);
  });

  test('담당이 없으면 404 를 null 로 바꾼다', () async {
    // /me/coach 미등록 → 404. 예외가 그대로 올라가면 화면이 오류로 덮인다.
    final repo = DioGymRepository(_dio(_StubAdapter(<String, Object?>{})));
    expect(await repo.fetchMyGym(), isNull);
    expect(await repo.fetchMyTrainer(), isNull);
  });

  test('내 헬스장은 담당 트레이너를 거치지 않고 /me/gym 에서 읽는다', () async {
    // 트레이너만 해제한 회원은 /me/coach 가 404 다. 그걸 거쳐 읽으면 헬스장 카드가
    // 함께 사라진다(#444).
    final adapter = _StubAdapter(<String, Object?>{'/me/gym': _gymDetailJson});

    final gym = await DioGymRepository(_dio(adapter)).fetchMyGym();
    expect(gym, isNotNull);
    // 목록과 같은 형태라 상세를 한 번 더 읽지 않는다.
    expect(gym!.rating, 4.7);
    expect(gym.tags, isNotEmpty);
    expect(adapter.calls, <String>['GET /me/gym']);
    // 회원 위치가 없으니 좌표를 싣지 않는다(#3044).
    expect(adapter.queryOf('/me/gym'), isEmpty);
  });

  group('내 예약 목록 (#980)', () {
    test('첫 쪽은 상한만 싣고 커서는 싣지 않는다', () async {
      final adapter = _StubAdapter(<String, Object?>{
        '/reservations/me': _reservationsJson,
      });

      final list = await DioGymRepository(_dio(adapter)).fetchMyReservations();

      expect(list.first.id, 'resv-2');
      final Map<String, dynamic> q = adapter.queryOf('/reservations/me');
      expect(q['limit'], reservationPageSize);
      expect(q.containsKey('before'), isFalse);
      expect(q.containsKey('before_id'), isFalse);
    });

    test('이어 받기는 마지막 예약의 (starts_at, id) 를 UTC 로 넘긴다', () async {
      // 엔티티는 화면용 KST 벽시계를 들고 있다(#2876). 그대로 보내면 서버가
      // UTC 로 읽어 쪽 경계가 9시간 밀린다.
      final adapter = _StubAdapter(<String, Object?>{
        '/reservations/me': _reservationsJson,
      });

      await DioGymRepository(_dio(adapter)).fetchMyReservations(
        limit: 10,
        // KST 2026-03-02 10:00 = 01:00Z
        before: DateTime(2026, 3, 2, 10),
        beforeId: 'resv-1',
      );

      final Map<String, dynamic> q = adapter.queryOf('/reservations/me');
      expect(q['limit'], 10);
      expect(q['before'], '2026-03-02T01:00:00.000Z');
      expect(q['before_id'], 'resv-1');
    });
  });

  test('헬스장 해제는 DELETE /me/coach, 트레이너 해제는 DELETE /me/coach/trainer', () async {
    // 두 휴지통이 같은 엔드포인트로 나가면 트레이너만 끊어도 헬스장이 사라진다.
    final adapter = _StubAdapter(<String, Object?>{
      '/me/coach': '{}',
      '/me/coach/trainer': '{}',
    });
    final repo = DioGymRepository(_dio(adapter));

    await repo.disconnectMyGym();
    await repo.disconnectMyTrainer();

    expect(adapter.calls, <String>[
      'DELETE /me/coach',
      'DELETE /me/coach/trainer',
    ]);
  });

  group('헬스장 단건 조회 (#3356)', () {
    test('GET /gyms/{id} 응답이 Gym 으로 매핑된다', () async {
      final adapter = _StubAdapter(<String, Object?>{
        '/gyms/gym-oncare-sinchon': _gymDetailJson,
      });
      final Gym? gym = await DioGymRepository(
        _dio(adapter),
      ).fetchGym('gym-oncare-sinchon');

      expect(adapter.calls, <String>['GET /gyms/gym-oncare-sinchon']);
      expect(gym, isNotNull);
      expect(gym!.id, 'gym-oncare-sinchon');
      expect(gym.name, '온케어짐 신촌점');
      expect(gym.tags, <String>['다이어트', '재활운동']);
      expect(gym.hasCoordinates, isTrue);
    });

    test('회원 위치가 있으면 좌표를 싣는다', () async {
      final adapter = _StubAdapter(<String, Object?>{
        '/gyms/gym-oncare-sinchon': _gymDetailJson,
      });
      await DioGymRepository(
        _dio(adapter),
        lat: 35.1,
        lng: 129.1,
      ).fetchGym('gym-oncare-sinchon');

      final Map<String, dynamic> q = adapter.queryOf(
        '/gyms/gym-oncare-sinchon',
      );
      expect(q['lat'], 35.1);
      expect(q['lng'], 129.1);
    });

    test('회원 위치가 없으면 좌표를 싣지 않는다 (#3044)', () async {
      final adapter = _StubAdapter(<String, Object?>{
        '/gyms/gym-oncare-sinchon': _gymDetailJson,
      });
      await DioGymRepository(_dio(adapter)).fetchGym('gym-oncare-sinchon');

      final Map<String, dynamic> q = adapter.queryOf(
        '/gyms/gym-oncare-sinchon',
      );
      expect(q.containsKey('lat'), isFalse);
      expect(q.containsKey('lng'), isFalse);
    });

    test('서버에 없는 헬스장(404)은 null 이다', () async {
      final adapter = _StubAdapter(<String, Object?>{});
      expect(
        await DioGymRepository(_dio(adapter)).fetchGym('12345678'),
        isNull,
      );
    });

    test('서버 오류는 그대로 올라간다', () async {
      final repo = DioGymRepository(
        Dio(BaseOptions(baseUrl: 'http://x/v1'))
          ..httpClientAdapter = _StatusAdapter(500),
      );
      await expectLater(
        repo.fetchGym('gym-oncare-sinchon'),
        throwsA(isA<DioException>()),
      );
    });

    test('목록 조회는 반경·상한을 싣지 않고 서버 기본값을 따른다', () async {
      final adapter = _StubAdapter(<String, Object?>{'/gyms': _gymsJson});
      await DioGymRepository(_dio(adapter)).fetchNearby();

      final Map<String, dynamic> q = adapter.queryOf('/gyms');
      expect(q.containsKey('radius_m'), isFalse);
      expect(q.containsKey('limit'), isFalse);
    });
  });

  group('소속 트레이너 조회 (#2857)', () {
    test('서버에 없는 헬스장(404)은 소속 트레이너가 없는 것과 같다', () async {
      // 카카오로 찾은 헬스장은 서버 목록에 없다 — 화면이 이를 조회 실패로
      // 보이면 그런 카드마다 오류가 뜬다.
      final repo = DioGymRepository(_dio(_StubAdapter(<String, Object?>{})));
      expect(await repo.fetchTrainersByGym('kakao-123'), isEmpty);
    });

    test('서버 오류는 그대로 올라가 화면이 다시 시도를 보인다', () async {
      final repo = DioGymRepository(
        Dio(BaseOptions(baseUrl: 'http://x/v1'))
          ..httpClientAdapter = _StatusAdapter(500),
      );
      await expectLater(
        repo.fetchTrainersByGym('gym-oncare-sinchon'),
        throwsA(isA<DioException>()),
      );
    });
  });
}

/// 모든 요청에 [status] 로 답하는 어댑터.
class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);

  final int status;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) async =>
      ResponseBody.fromString(
        '{"detail":"error"}',
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}
