import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare_core/clock.dart';

void main() {
  late AppDatabase db;
  late Dio dio;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));

    // 인터셉터가 상대 시각("10분 전")을 KST 기준으로 셈한다(#850). 시드도 같은
    // 시계를 써야 한다 — `DateTime.now()` 를 섞으면 기기가 KST 가 아닌 환경(CI 는
    // UTC)에서 두 값이 9시간 어긋난다.
    final now = nowKst();
    await db.batch((b) {
      b.insertAll(db.notificationItems, <NotificationItemsCompanion>[
        NotificationItemsCompanion.insert(
          id: 'n-1',
          createdAt: now.subtract(const Duration(minutes: 10)),
          title: '식단 입력 알림',
          body: '오늘 점심 입력이 비어있어요.',
          category: 'reminder',
        ),
        NotificationItemsCompanion.insert(
          id: 'n-2',
          createdAt: now.subtract(const Duration(hours: 1)),
          title: '운동 목표 달성',
          body: '주간 240분 달성',
          category: 'achievement',
        ),
        NotificationItemsCompanion.insert(
          id: 'n-3',
          createdAt: now.subtract(const Duration(days: 1)),
          title: '서비스 점검이 예정돼 있어요',
          body: '내일 02:00~03:00에 점검해요.',
          category: 'system',
          read: const Value(true),
        ),
      ]);
    });
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  test('GET /notifications returns rows newest-first with time_ago', () async {
    final res = await dio.get<List<Object?>>('/notifications');
    expect(res.statusCode, 200);
    final list = res.data!.cast<Map<String, Object?>>();
    expect(list.length, 3);
    expect(list.first['id'], 'n-1');
    expect(list.first['time_ago'], '10분 전');
    expect(list[1]['time_ago'], '1시간 전');
    // 시드 밖 알림은 서버 `time_ago` 처럼 `1일 전` 이다 — `어제` 는 데모 시드
    // 알림에만 쓴다(#3099).
    expect(list[2]['time_ago'], '1일 전');
  });

  // 데모와 실서버가 같은 문구를 낸다 — 시드 밖 알림은 서버 일반 문구, 시드 알림은
  // 서버 `demo_time_ago` 문구다(#3099).
  test('하루 지난 알림은 시드 밖이면 `1일 전`, 시드면 `어제` 다', () async {
    final now = nowKst();
    await db.batch((b) {
      b.insertAll(db.notificationItems, <NotificationItemsCompanion>[
        NotificationItemsCompanion.insert(
          id: 'n-30h',
          createdAt: now.subtract(const Duration(hours: 30)),
          title: '트레이너가 루틴을 보냈어요',
          body: '새 개인운동이 도착했어요.',
          category: 'system',
        ),
        NotificationItemsCompanion.insert(
          id: 'seed-noti-9',
          createdAt: now,
          title: '시드 알림',
          body: '시드 알림',
          category: 'system',
        ),
      ]);
    });

    final list = (await dio.get<List<Object?>>(
      '/notifications',
    )).data!.cast<Map<String, Object?>>();
    String ago(String id) =>
        list.firstWhere((e) => e['id'] == id)['time_ago']! as String;
    expect(ago('n-30h'), '1일 전');
    expect(ago('seed-noti-9'), '어제');
  });

  // 데모 시드 알림은 문구 키를 함께 준다. 화면이 로케일 문장을 고른다(#1812).
  test('데모 시드 알림에만 문구 키가 붙는다', () async {
    await db
        .into(db.notificationItems)
        .insert(
          NotificationItemsCompanion.insert(
            id: 'seed-noti-5',
            createdAt: nowKst().subtract(const Duration(minutes: 5)),
            title: '새 개인운동이 왔어요',
            body: '트레이너가 걷기 위주 개인운동으로 조정해 보냈어요.',
            category: 'routine',
          ),
        );

    final res = await dio.get<List<Object?>>('/notifications');
    final byId = <String, Map<String, Object?>>{
      for (final e in res.data!.cast<Map<String, Object?>>())
        e['id']! as String: e,
    };
    expect(byId['seed-noti-5']!['message_key'], 'routine');
    expect(byId['n-1']!.containsKey('message_key'), isFalse);
  });

  test('Read flag round-trips through the response', () async {
    final res = await dio.get<List<Object?>>('/notifications');
    final list = res.data!.cast<Map<String, Object?>>();
    final byId = <String, Map<String, Object?>>{
      for (final e in list) e['id']! as String: e,
    };
    expect(byId['n-1']!['read'], isFalse);
    expect(byId['n-3']!['read'], isTrue);
  });

  // 로컬 모드가 상한을 무시하면 여기서만 무한 목록이 되어, 이어 받기가 도는지
  // 개발 중에 확인할 수 없다. 실서버와 같은 계약으로 답해야 한다(#965).
  test('limit 만큼만 돌려준다', () async {
    final res = await dio.get<List<Object?>>(
      '/notifications',
      queryParameters: <String, Object?>{'limit': 2},
    );

    final list = res.data!.cast<Map<String, Object?>>();
    expect(list.map((e) => e['id']), <String>['n-1', 'n-2']);
  });

  test('커서 뒤쪽을 이어 받는다', () async {
    final first = await dio.get<List<Object?>>(
      '/notifications',
      queryParameters: <String, Object?>{'limit': 2},
    );
    final last = first.data!.cast<Map<String, Object?>>().last;

    final next = await dio.get<List<Object?>>(
      '/notifications',
      queryParameters: <String, Object?>{
        'limit': 2,
        'before': last['created_at'],
        'before_id': last['id'],
      },
    );

    final list = next.data!.cast<Map<String, Object?>>();
    expect(list.map((e) => e['id']), <String>['n-3']);
  });

  // 데모 알림함도 실서버와 같은 경로로 읽음을 남기고 배지를 센다(#2660).
  group('읽음 처리·미읽음 수', () {
    Future<int> unread() async {
      final res = await dio.get<Map<String, Object?>>(
        '/notifications/unread-count',
      );
      return res.data!['unread']! as int;
    }

    test('미읽음 수를 서버와 같은 키로 준다', () async {
      expect(await unread(), 2);
    });

    test('한 건 읽음은 그 알림만 바꾸고 다시 읽어도 남는다', () async {
      final res = await dio.post<Map<String, Object?>>(
        '/notifications/n-1/read',
      );
      expect(res.data, <String, Object?>{'id': 'n-1', 'read': true});
      expect(await unread(), 1);

      final list = (await dio.get<List<Object?>>(
        '/notifications',
      )).data!.cast<Map<String, Object?>>();
      final byId = <String, Map<String, Object?>>{
        for (final e in list) e['id']! as String: e,
      };
      expect(byId['n-1']!['read'], isTrue);
      expect(byId['n-2']!['read'], isFalse);
    });

    test('없는 알림을 읽으면 서버처럼 404 다', () async {
      final gone = await dio.post<Object?>(
        '/notifications/nope/read',
        options: Options(validateStatus: (int? s) => true),
      );
      expect(gone.statusCode, 404);
      expect(await unread(), 2);
    });

    test('모두 읽음은 바꾼 건수를 주고 미읽음이 0 이 된다', () async {
      final res = await dio.post<Map<String, Object?>>(
        '/notifications/read-all',
      );
      expect(res.data, <String, Object?>{'marked_read': 2});
      expect(await unread(), 0);
    });
  });

  // 목적지는 서버 `_ACTION_BY_CATEGORY` 와 같다 — 데모 알림을 눌러도 실서버 데모
  // 계정과 같은 화면으로 간다(#2660).
  test('갈래마다 서버와 같은 목적지를 싣는다', () async {
    final now = nowKst();
    await db.batch((b) {
      b.insertAll(db.notificationItems, <NotificationItemsCompanion>[
        for (final c in <String>['coach_chat', 'coach_report', 'routine'])
          NotificationItemsCompanion.insert(
            id: 'c-$c',
            createdAt: now,
            title: c,
            body: c,
            category: c,
          ),
      ]);
    });

    final list = (await dio.get<List<Object?>>(
      '/notifications',
    )).data!.cast<Map<String, Object?>>();
    String? target(String id) =>
        (list.firstWhere((e) => e['id'] == id)['action']
                as Map<String, Object?>?)?['target']
            as String?;
    expect(target('n-1'), 'dashboard');
    expect(target('n-2'), 'dashboard');
    expect(target('n-3'), isNull);
    expect(target('c-coach_chat'), 'coach_chat');
    expect(target('c-coach_report'), 'coach_chat');
    expect(target('c-routine'), 'exercise');
  });

  // 데모 시드 알림은 예전 데모 목록처럼 보인다 — 시각은 정해 둔 값, 목적지는 알림별
  // 값이다. 같은 날 안에서 몇 시간이 지나도 "10분 전" 이다(#2660).
  test('데모 시드 알림은 정해 둔 시각과 알림별 목적지로 답한다', () async {
    await db
        .into(db.notificationItems)
        .insert(
          NotificationItemsCompanion.insert(
            id: 'seed-noti-6',
            createdAt: nowKst().subtract(const Duration(hours: 5)),
            title: '이번 주 운동 목표까지 조금 남았어요',
            body: '저강도 유산소(걷기) 30분부터 채워 봐요.',
            category: 'reminder',
          ),
        );

    final list = (await dio.get<List<Object?>>(
      '/notifications',
    )).data!.cast<Map<String, Object?>>();
    final seed = list.firstWhere((e) => e['id'] == 'seed-noti-6');
    expect(seed['time_ago'], '3시간 전');
    // 갈래(리마인더)의 기본 목적지가 아니라 이 알림의 목적지(운동)다.
    expect(seed['action'], <String, Object?>{
      'label': '운동 보기',
      'target': 'exercise',
    });
    // 시드가 아닌 알림은 실제 경과와 갈래별 목적지다.
    final other = list.firstWhere((e) => e['id'] == 'n-1');
    expect(other['time_ago'], '10분 전');
    expect((other['action']! as Map<String, Object?>)['target'], 'dashboard');
  });

  // 예전 데모는 다시 로그인하면 알림이 처음 상태였다(#1936). 읽음이 drift 에 남게
  // 된 뒤에도 로그인이 시드 알림을 되돌린다 — 데모 중에 생긴 알림은 둔다(#2660).
  group('데모 로그인은 시드 알림 읽음을 처음 상태로 되돌린다', () {
    setUp(() async {
      final now = nowKst();
      await db.batch((b) {
        b.insertAll(db.notificationItems, <NotificationItemsCompanion>[
          NotificationItemsCompanion.insert(
            id: 'seed-noti-5',
            createdAt: now,
            title: 't',
            body: 'b',
            category: 'routine',
          ),
          NotificationItemsCompanion.insert(
            id: 'seed-noti-9',
            createdAt: now,
            title: 't',
            body: 'b',
            category: 'achievement',
            read: const Value(true),
          ),
        ]);
      });
      await dio.post<Object?>('/notifications/read-all');
      await (db.update(db.notificationItems)
            ..where((t) => t.id.equals('seed-noti-9')))
          .write(const NotificationItemsCompanion(read: Value(false)));
    });

    Future<Map<String, bool>> reads() async => <String, bool>{
      for (final r in await db.select(db.notificationItems).get()) r.id: r.read,
    };

    for (final (String path, Map<String, Object?> body)
        in <(String, Map<String, Object?>)>[
          ('/auth/login', <String, Object?>{'username': 'a', 'password': 'b'}),
          ('/auth/social/kakao', <String, Object?>{'token': 't'}),
        ]) {
      test(path, () async {
        await dio.post<Object?>(path, data: body);

        final r = await reads();
        expect(r['seed-noti-5'], isFalse);
        expect(r['seed-noti-9'], isTrue);
        expect(r['n-1'], isTrue, reason: '시드가 아닌 알림은 건드리지 않는다');
      });
    }
  });
}
