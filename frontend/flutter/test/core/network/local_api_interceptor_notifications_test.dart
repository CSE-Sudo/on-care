import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/utils/clock.dart';

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
          title: '서비스 점검 안내',
          body: '내일 02:00~03:00 점검 예정입니다.',
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
    expect(list[2]['time_ago'], '어제');
  });

  // 데모 시드 알림은 문구 키를 함께 준다. 화면이 로케일 문장을 고른다(#1812).
  test('데모 시드 알림에만 문구 키가 붙는다', () async {
    await db
        .into(db.notificationItems)
        .insert(
          NotificationItemsCompanion.insert(
            id: 'seed-noti-1',
            createdAt: nowKst().subtract(const Duration(minutes: 5)),
            title: '나트륨 섭취 주의',
            body: '점심 짬뽕으로 오늘 나트륨이 3,428mg까지 올랐어요.',
            category: 'reminder',
          ),
        );

    final res = await dio.get<List<Object?>>('/notifications');
    final byId = <String, Map<String, Object?>>{
      for (final e in res.data!.cast<Map<String, Object?>>())
        e['id']! as String: e,
    };
    expect(byId['seed-noti-1']!['message_key'], 'sodium');
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
}
