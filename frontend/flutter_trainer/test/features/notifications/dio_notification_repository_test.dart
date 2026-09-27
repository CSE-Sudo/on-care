import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T body, String path) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: body,
);

DioException _httpError(int status, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
  ),
);

/// 알림함이 **다시 읽는지**를 본다. 한 번 읽고 끝나는 구현에서는 트레이너가
/// 알림함을 열어 보기 전까지 배지가 처음 센 숫자에 멈춰 있었다. (#917)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String unreadPath = '/trainer/notifications/unread-count';

  late _MockDio dio;

  setUp(() => dio = _MockDio());

  test('watchUnreadCount keeps reading while something listens', () async {
    var calls = 0;
    when(() => dio.get<Map<String, Object?>>(unreadPath)).thenAnswer((_) async {
      calls += 1;
      return _ok<Map<String, Object?>>(<String, Object?>{
        'unread': calls,
      }, unreadPath);
    });

    final emissions = await DioNotificationRepository(
      dio,
      pollInterval: const Duration(milliseconds: 5),
    ).watchUnreadCount().take(2).toList().timeout(const Duration(seconds: 1));

    expect(emissions, <int>[1, 2]);
  });

  test(
    'watchUnreadCount holds the last count through a transient failure',
    () async {
      var calls = 0;
      when(() => dio.get<Map<String, Object?>>(unreadPath)).thenAnswer((
        _,
      ) async {
        calls += 1;
        if (calls == 2) throw _httpError(503, unreadPath);
        return _ok<Map<String, Object?>>(<String, Object?>{
          'unread': calls,
        }, unreadPath);
      });

      final emissions = await DioNotificationRepository(
        dio,
        pollInterval: const Duration(milliseconds: 5),
      ).watchUnreadCount().take(2).toList().timeout(const Duration(seconds: 1));

      // 실패한 폴은 스트림에 오류로 새지 않는다 — 배지가 0 으로 깜빡였다가
      // 돌아오면, 트레이너는 알림이 사라졌다고 읽는다.
      expect(emissions, <int>[1, 3]);
    },
  );

  test('watch re-reads the inbox so the open list matches the badge', () async {
    var calls = 0;
    when(() => dio.get<List<dynamic>>('/trainer/notifications')).thenAnswer((
      _,
    ) async {
      calls += 1;
      return _ok<List<dynamic>>(<dynamic>[
        <String, Object?>{
          'id': 'noti-$calls',
          'title': '새 메시지',
          'body': '김민수님이 메시지를 보냈어요',
          'category': 'message',
          'read': false,
          'created_at': '2026-08-19T09:00:00Z',
          'time_ago': '방금',
        },
      ], '/trainer/notifications');
    });

    final emissions = await DioNotificationRepository(
      dio,
      pollInterval: const Duration(milliseconds: 5),
    ).watch().take(2).toList().timeout(const Duration(seconds: 1));

    expect(emissions.map((page) => page.items.single.id).toList(), <String>[
      'noti-1',
      'noti-2',
    ]);
  });

  test(
    'the demo source stays inert — no backend makes notifications',
    () async {
      const repo = DemoNotificationRepository();

      expect(await repo.watchUnreadCount().first, 0);
      expect((await repo.watch().first).items, isEmpty);
      expect((await repo.watch().first).hasMore, isFalse);
    },
  );

  group('pagination (#2293)', () {
    const String path = '/trainer/notifications';

    Map<String, Object?> row(String id) => <String, Object?>{
      'id': id,
      'title': '새 메시지',
      'body': '',
      'category': 'message',
      'read': false,
      'created_at': '2026-09-01T09:00:00Z',
      'time_ago': '방금',
      'template': 'trainer_member_message',
      'args': <String, Object?>{'member_name': '지수'},
      'target_date': null,
    };

    Response<List<dynamic>> page(
      List<String> ids, {
      Map<String, List<String>> headers = const <String, List<String>>{},
    }) => Response<List<dynamic>>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <dynamic>[for (final String id in ids) row(id)],
      headers: Headers.fromMap(headers),
    );

    test('the first page is the same bare request as before', () async {
      when(
        () => dio.get<List<dynamic>>(path),
      ).thenAnswer((_) async => page(<String>['n-1']));

      final result = await DioNotificationRepository(dio).fetch();

      expect(result.items.single.id, 'n-1');
      final captured = verify(
        () => dio.get<List<dynamic>>(
          path,
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured, <Object?>[null]);
    });

    test('the cursor comes from the response headers', () async {
      when(() => dio.get<List<dynamic>>(path)).thenAnswer(
        (_) async => page(
          <String>['n-1', 'n-2'],
          headers: <String, List<String>>{
            'X-Next-Before': <String>['2026-09-01T09:00:00.123456+00:00'],
            'X-Next-Before-Id': <String>['n-2'],
          },
        ),
      );

      final result = await DioNotificationRepository(dio).fetch();

      expect(result.hasMore, isTrue);
      expect(
        result.next,
        const TrainerNotificationCursor(
          before: '2026-09-01T09:00:00.123456+00:00',
          beforeId: 'n-2',
        ),
      );
    });

    test('no headers means the last page', () async {
      when(
        () => dio.get<List<dynamic>>(path),
      ).thenAnswer((_) async => page(<String>['n-1']));

      final result = await DioNotificationRepository(dio).fetch();

      expect(result.hasMore, isFalse);
      expect(result.next, isNull);
    });

    test('a half cursor is treated as the last page', () async {
      when(() => dio.get<List<dynamic>>(path)).thenAnswer(
        (_) async => page(
          <String>['n-1'],
          headers: <String, List<String>>{
            'X-Next-Before': <String>['2026-09-01T09:00:00+00:00'],
          },
        ),
      );

      final result = await DioNotificationRepository(dio).fetch();

      expect(result.next, isNull);
    });

    test('an older page sends the cursor back verbatim', () async {
      when(
        () => dio.get<List<dynamic>>(
          path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => page(<String>['n-3']));

      final result = await DioNotificationRepository(dio).fetch(
        before: const TrainerNotificationCursor(
          before: '2026-09-01T09:00:00.123456+00:00',
          beforeId: 'n-2',
        ),
      );

      expect(result.items.single.id, 'n-3');
      final captured = verify(
        () => dio.get<List<dynamic>>(
          path,
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured.single, <String, String>{
        'before': '2026-09-01T09:00:00.123456+00:00',
        'before_id': 'n-2',
      });
    });

    test('older pages keep template, args and target fields', () async {
      when(
        () => dio.get<List<dynamic>>(
          path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => page(<String>['n-3']));

      final result = await DioNotificationRepository(dio).fetch(
        before: const TrainerNotificationCursor(before: 'x', beforeId: 'y'),
      );

      final TrainerNotification n = result.items.single;
      expect(n.template, 'trainer_member_message');
      expect(n.args, <String, Object?>{'member_name': '지수'});
      expect(n.targetDate, isNull);
    });

    test('a failed page surfaces as an AppError', () async {
      when(
        () => dio.get<List<dynamic>>(
          path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(_httpError(422, path));

      await expectLater(
        DioNotificationRepository(dio).fetch(
          before: const TrainerNotificationCursor(before: 'bad', beforeId: 'y'),
        ),
        throwsA(isA<AppError>()),
      );
    });

    test('watch polls only the first page', () async {
      when(() => dio.get<List<dynamic>>(path)).thenAnswer(
        (_) async => page(
          <String>['n-1'],
          headers: <String, List<String>>{
            'X-Next-Before': <String>['2026-09-01T09:00:00+00:00'],
            'X-Next-Before-Id': <String>['n-1'],
          },
        ),
      );

      final emissions = await DioNotificationRepository(
        dio,
        pollInterval: const Duration(milliseconds: 5),
      ).watch().take(2).toList().timeout(const Duration(seconds: 1));

      expect(emissions.every((p) => p.hasMore), isTrue);
      final captured = verify(
        () => dio.get<List<dynamic>>(
          path,
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      // 폴링은 늘 쿼리 없는 첫 쪽이다 — 이어 받은 과거 쪽을 다시 읽지 않는다.
      expect(captured, everyElement(isNull));
    });
  });
}
