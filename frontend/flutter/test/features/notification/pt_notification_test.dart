/// PT 일정·완료 알림의 갈래와 목적지. (#3027·#3028)
///
/// 실서버는 PT 일정 알림(`member_schedule`)과 PT 완료·피드백 알림(`pt_done`)에
/// 운동 탭으로 가는 버튼을 붙여 보낸다. 앱은
/// - `pt_done` 을 일정과 다른 갈래(끝난 수업의 기록)로 읽고,
/// - 두 알림의 버튼을 그대로 보여 주며,
/// - 눌렀을 때 운동 탭의 다음 PT 배지와 내 예약을 다시 읽는다.
/// 데모(목 모드)도 같은 버튼을 같은 문구로 붙인다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/demo/demo_alert_keys.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/notification/data/repositories/dio_notification_repository.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/presentation/alert_navigation.dart';
import 'package:oncare_core/clock.dart';

import '../../helpers/demo_notifications.dart';

/// 지정한 본문으로만 답하는 가짜 서버.
Dio _dio(Object? body) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.resolve(
          Response<Object?>(
            requestOptions: options,
            statusCode: 200,
            data: body,
          ),
        );
      },
    ),
  );
  return dio;
}

Map<String, Object?> _row(String category, Map<String, Object?>? action) =>
    <String, Object?>{
      'id': 'n-$category',
      'title': '제목',
      'body': '내용',
      'time_ago': '방금',
      'category': category,
      'read': false,
      'action': action,
    };

AlertItem _alert(AlertTarget target) => AlertItem(
  id: 'a1',
  title: 'PT 수업 완료',
  body: '3회차 PT 를 마쳤어요',
  createdAt: '2026-09-28T09:00:00Z',
  timeAgo: '방금',
  category: AlertCategory.ptDone,
  action: AlertAction(label: 'PT 기록 보기', target: target),
);

void main() {
  group('갈래', () {
    test('pt_done 은 PT 기록 갈래다', () {
      expect(
        DioNotificationRepository.categoryFromWire('pt_done'),
        AlertCategory.ptDone,
      );
    });

    test('PT 기록은 앞으로의 일정·달성과 다른 갈래다', () {
      final AlertCategory done = DioNotificationRepository.categoryFromWire(
        'pt_done',
      );
      expect(done, isNot(AlertCategory.schedule));
      expect(done, isNot(AlertCategory.achievement));
      expect(done, isNot(AlertCategory.system));
    });

    test('일정 갈래는 그대로다', () {
      expect(
        DioNotificationRepository.categoryFromWire('member_schedule'),
        AlertCategory.schedule,
      );
    });

    test('비슷한 철자는 PT 기록으로 넘겨짚지 않는다', () {
      for (final String wire in <String>['PT_DONE', 'pt-done', 'ptDone']) {
        expect(
          DioNotificationRepository.categoryFromWire(wire),
          isNot(AlertCategory.ptDone),
          reason: wire,
        );
      }
    });
  });

  group('실서버 버튼', () {
    test('일정 알림은 일정 보기 버튼으로 운동 탭에 간다 (#3028)', () async {
      final DioNotificationRepository repo = DioNotificationRepository(
        _dio(<Object?>[
          _row('member_schedule', <String, Object?>{
            'label': '일정 보기',
            'target': 'exercise',
          }),
        ]),
      );

      final AlertItem item = (await repo.fetchPage()).single;
      expect(item.category, AlertCategory.schedule);
      expect(item.action?.label, '일정 보기');
      expect(item.action?.target, AlertTarget.exercise);
      expect(item.action?.isNavigable, isTrue);
    });

    test('PT 완료 알림은 PT 기록 보기 버튼으로 운동 탭에 간다 (#3027)', () async {
      final DioNotificationRepository repo = DioNotificationRepository(
        _dio(<Object?>[
          _row('pt_done', <String, Object?>{
            'label': 'PT 기록 보기',
            'target': 'exercise',
          }),
        ]),
      );

      final AlertItem item = (await repo.fetchPage()).single;
      expect(item.category, AlertCategory.ptDone);
      expect(item.action?.label, 'PT 기록 보기');
      expect(item.action?.target, AlertTarget.exercise);
      expect(item.action?.isNavigable, isTrue);
    });

    test('영어 라벨도 서버 문구를 그대로 쓴다', () async {
      final DioNotificationRepository repo = DioNotificationRepository(
        _dio(<Object?>[
          _row('pt_done', <String, Object?>{
            'label': 'View PT record',
            'target': 'exercise',
          }),
        ]),
      );

      final AlertItem item = (await repo.fetchPage()).single;
      expect(item.action?.label, 'View PT record');
    });

    test('버튼이 없는 옛 일정 알림도 갈래는 읽는다', () async {
      final DioNotificationRepository repo = DioNotificationRepository(
        _dio(<Object?>[_row('member_schedule', null)]),
      );

      final AlertItem item = (await repo.fetchPage()).single;
      expect(item.category, AlertCategory.schedule);
      expect(item.action, isNull);
    });
  });

  group('데모 버튼', () {
    late AppDatabase db;
    late Dio dio;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
      final DateTime now = nowKst();
      await db.batch((b) {
        b.insertAll(db.notificationItems, <NotificationItemsCompanion>[
          NotificationItemsCompanion.insert(
            id: 'n-schedule',
            createdAt: now,
            title: 'PT 일정이 잡혔어요',
            body: '내일 18:00',
            category: 'member_schedule',
          ),
          NotificationItemsCompanion.insert(
            id: 'n-done',
            createdAt: now.subtract(const Duration(minutes: 1)),
            title: 'PT 수업 완료',
            body: '3회차 PT 를 마쳤어요',
            category: 'pt_done',
          ),
        ]);
      });
    });

    tearDown(() async {
      await db.close();
      dio.close();
    });

    Future<Map<String, Map<String, Object?>>> rows() async {
      final Response<List<Object?>> res = await dio.get<List<Object?>>(
        '/notifications',
      );
      return <String, Map<String, Object?>>{
        for (final Map<String, Object?> r
            in res.data!.cast<Map<String, Object?>>())
          r['id']! as String: r,
      };
    }

    test('일정 알림은 실서버와 같은 버튼을 붙인다', () async {
      final Map<String, Map<String, Object?>> r = await rows();
      expect(r['n-schedule']!['action'], <String, Object?>{
        'label': '일정 보기',
        'target': 'exercise',
      });
    });

    test('PT 완료 알림은 실서버와 같은 버튼을 붙인다', () async {
      final Map<String, Map<String, Object?>> r = await rows();
      expect(r['n-done']!['category'], 'pt_done');
      expect(r['n-done']!['action'], <String, Object?>{
        'label': 'PT 기록 보기',
        'target': 'exercise',
      });
    });
  });

  group('데모 시드', () {
    test('PT 수업 완료 예시는 PT 기록 갈래이고 PT 기록 보기 버튼이다', () async {
      final List<AlertItem> alerts = await fetchDemoAlerts();
      final AlertItem done = alerts.singleWhere(
        (AlertItem a) => a.id == 'seed-noti-2',
      );
      expect(done.category, AlertCategory.ptDone);
      expect(done.action?.label, 'PT 기록 보기');
      expect(done.action?.target, AlertTarget.exercise);
    });

    test('시드 버튼 표가 실서버 라벨과 같다', () {
      expect(kDemoAlertActionBySeedId['seed-noti-2']?.label, 'PT 기록 보기');
      expect(kDemoAlertActionBySeedId['seed-noti-2']?.target, 'exercise');
    });
  });

  group('눌렀을 때', () {
    late BuildContext ctx;
    late WidgetRef wref;

    Future<({int Function() sessions, int Function() reservations})> pump(
      WidgetTester tester,
    ) async {
      int sessionLoads = 0;
      int reservationLoads = 0;
      final GoRouter router = GoRouter(
        initialLocation: AppRoutes.exercise,
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.exercise,
            builder: (_, _) => Consumer(
              builder: (BuildContext c, WidgetRef r, _) {
                ctx = c;
                wref = r;
                // 듣는 사람이 있어야 무효화가 다시 읽기로 이어진다.
                r
                  ..watch(coachSessionsProvider)
                  ..watch(myReservationsProvider);
                return const Text('운동');
              },
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            coachSessionsProvider.overrideWith((ref) async {
              sessionLoads++;
              return const <CoachSession>[];
            }),
            myReservationsProvider.overrideWith((ref) async {
              reservationLoads++;
              return const <MyReservation>[];
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      return (
        sessions: () => sessionLoads,
        reservations: () => reservationLoads,
      );
    }

    testWidgets('운동 탭에 있어도 다음 PT 일정을 다시 읽는다', (WidgetTester tester) async {
      final counts = await pump(tester);
      final int before = counts.sessions();

      await openAlertTarget(ctx, wref, _alert(AlertTarget.exercise));
      await tester.pumpAndSettle();

      expect(counts.sessions(), greaterThan(before));
    });

    testWidgets('내 예약도 다시 읽는다', (WidgetTester tester) async {
      final counts = await pump(tester);
      final int before = counts.reservations();

      await openAlertTarget(ctx, wref, _alert(AlertTarget.exercise));
      await tester.pumpAndSettle();

      expect(counts.reservations(), greaterThan(before));
    });

    testWidgets('운동 탭에 머문다', (WidgetTester tester) async {
      await pump(tester);

      await openAlertTarget(ctx, wref, _alert(AlertTarget.exercise));
      await tester.pumpAndSettle();

      expect(find.text('운동'), findsOneWidget);
    });
  });
}
