/// 알림 목록 페이지네이션 — 회원 앱 쪽. (#965)
///
/// 예전에는 `/notifications` 가 사용자의 알림을 **전부** 돌려주고 화면이 한 번에
/// 다 그렸다. 알림은 식단·운동·일정 훅에서 계속 생기는데 지우는 경로가 없어, 오래
/// 쓴 계정일수록 알림 탭이 무거워졌다.
///
/// 여기서 못 박는 것: 첫 쪽만 받는다 · 바닥에 닿으면 이어 붙인다 · 커서는 서버가
/// 준 값을 그대로 되돌려 준다 · 경계에서 같은 알림을 두 번 그리지 않는다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/notification/data/repositories/dio_notification_repository.dart';
import 'package:oncare/features/notification/data/repositories/mock_notification_repository.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/features/notification/presentation/pages/notification_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _realConfig = AppConfig(
  environment: Environment.prod,
  apiBaseUrl: 'https://api.test/v1',
  useMockApi: false,
);

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 서버가 준 것과 같은 모양의 알림. `createdAt` 이 커서로 되돌아간다.
AlertItem _item(int i) => AlertItem(
  id: 'n$i',
  title: '알림 $i',
  body: '',
  timeAgo: '방금 전',
  category: AlertCategory.reminder,
  createdAt: '2026-01-01T00:00:${(59 - i % 60).toString().padLeft(2, '0')}Z',
);

/// 커서를 실제로 따라 자르는 가짜 서버.
///
/// `beforeId` 를 무시하고 늘 처음부터 주는 가짜였다면 이어 받기가 무너져도 테스트가
/// 통과한다 — 그래서 여기서는 커서대로 자른다.
class _PagingRepo implements NotificationRepository {
  _PagingRepo(this.total);

  /// 이 사용자에게 있는 전체 알림 수.
  final int total;

  /// 받은 요청. 앱이 무엇을 커서로 보냈는지 본다.
  final List<({int limit, String? before, String? beforeId})> calls =
      <({int limit, String? before, String? beforeId})>[];

  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async {
    calls.add((limit: limit, before: before, beforeId: beforeId));
    final int start = beforeId == null
        ? 0
        : int.parse(beforeId.substring(1)) + 1;
    if (start >= total) return const <AlertItem>[];
    final int end = (start + limit) > total ? total : start + limit;
    return <AlertItem>[for (int i = start; i < end; i++) _item(i)];
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}

  @override
  Future<int> unreadCount() async => total;
}

ProviderContainer _container(NotificationRepository repo, AppConfig config) {
  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(config),
      notificationRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('컨트롤러', () {
    test('첫 조회는 한 쪽만 받고, 더 있다고 표시한다', () async {
      final repo = _PagingRepo(notificationPageSize * 3);
      final container = _container(repo, _realConfig);

      container.read(notificationControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final NotificationState state = container.read(
        notificationControllerProvider,
      );
      expect(state.items, hasLength(notificationPageSize));
      expect(state.hasMore, isTrue);
      expect(repo.calls.single.before, isNull, reason: '첫 쪽은 커서 없이 부른다');
      expect(repo.calls.single.limit, notificationPageSize);
    });

    test('이어 받기는 직전 쪽 마지막 알림을 커서로 보낸다', () async {
      final repo = _PagingRepo(notificationPageSize * 3);
      final container = _container(repo, _realConfig);
      container.read(notificationControllerProvider);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(notificationControllerProvider.notifier)
          .loadMore();

      final AlertItem lastOfFirstPage = _item(notificationPageSize - 1);
      expect(repo.calls.last.before, lastOfFirstPage.createdAt);
      expect(repo.calls.last.beforeId, lastOfFirstPage.id);
      expect(
        container.read(notificationControllerProvider).items,
        hasLength(notificationPageSize * 2),
      );
    });

    test('마지막 쪽까지 가면 더 부르지 않는다', () async {
      // 한 쪽이 꽉 차지 않게 — 그래야 서버가 "여기까지" 라고 말한 셈이 된다.
      final repo = _PagingRepo(notificationPageSize + 5);
      final container = _container(repo, _realConfig);
      container.read(notificationControllerProvider);
      await Future<void>.delayed(Duration.zero);
      final notifier = container.read(notificationControllerProvider.notifier);

      await notifier.loadMore();
      final int callsAfterLastPage = repo.calls.length;
      await notifier.loadMore(); // 더 없는데 한 번 더 당겨 본다

      expect(
        container.read(notificationControllerProvider).hasMore,
        isFalse,
      );
      expect(repo.calls.length, callsAfterLastPage, reason: '헛된 요청을 내지 않는다');
      expect(
        container.read(notificationControllerProvider).items,
        hasLength(notificationPageSize + 5),
      );
    });

    test('경계에서 겹쳐 온 알림은 한 번만 남는다', () async {
      // 같은 시각의 알림이 여러 건이면 서버가 경계 항목을 다시 줄 수 있다.
      final repo = _OverlappingRepo();
      final container = _container(repo, _realConfig);
      container.read(notificationControllerProvider);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(notificationControllerProvider.notifier)
          .loadMore();

      final List<String> ids = container
          .read(notificationControllerProvider)
          .items
          .map((AlertItem i) => i.id)
          .toList();
      expect(ids.toSet(), hasLength(ids.length), reason: '같은 알림이 두 번 그려졌다');
    });

    test('새로고침은 첫 쪽으로 되돌린다', () async {
      final repo = _PagingRepo(notificationPageSize * 3);
      final container = _container(repo, _realConfig);
      container.read(notificationControllerProvider);
      await Future<void>.delayed(Duration.zero);
      final notifier = container.read(notificationControllerProvider.notifier);
      await notifier.loadMore();

      await notifier.refresh();

      // 이어 받아 둔 과거 알림을 그대로 두면, 그 사이 지워진 알림이 목록에 남는다.
      expect(
        container.read(notificationControllerProvider).items,
        hasLength(notificationPageSize),
      );
    });

    test('목/데모 모드는 이어 받지 않는다', () async {
      final repo = MockNotificationRepository();
      final container = _container(repo, _mockConfig);
      container.read(notificationControllerProvider);

      await container
          .read(notificationControllerProvider.notifier)
          .loadMore();

      // 데모는 시드가 진실원본이다 — 없는 서버를 향한 요청이 나가면 안 된다.
      expect(
        container.read(notificationControllerProvider).items,
        hasLength(demoAlerts.length),
      );
    });
  });

  group('화면', () {
    testWidgets('바닥까지 내리면 과거 알림이 이어 붙는다', (WidgetTester tester) async {
      final repo = _PagingRepo(notificationPageSize * 2);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appConfigProvider.overrideWithValue(_realConfig),
            notificationRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NotificationPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('알림 0'), findsOneWidget);
      expect(repo.calls, hasLength(1));

      await tester.fling(find.byType(ListView), const Offset(0, -6000), 4000);
      await tester.pumpAndSettle();

      expect(repo.calls.length, greaterThan(1), reason: '바닥에서 다음 쪽을 불렀다');
      expect(repo.calls.last.beforeId, isNotNull);
    });
  });

  group('실 백엔드 계약', () {
    test('limit 과 커서를 쿼리로 보낸다', () async {
      final RequestOptions captured = await _capture(
        (DioNotificationRepository repo) => repo.fetchPage(
          limit: 7,
          before: '2026-01-01T00:00:00Z',
          beforeId: 'noti-1',
        ),
      );

      expect(captured.path, '/notifications');
      expect(captured.queryParameters['limit'], 7);
      expect(captured.queryParameters['before'], '2026-01-01T00:00:00Z');
      expect(captured.queryParameters['before_id'], 'noti-1');
    });

    test('첫 쪽에는 커서를 싣지 않는다', () async {
      final RequestOptions captured = await _capture(
        (DioNotificationRepository repo) => repo.fetchPage(),
      );

      // null 을 실어 보내면 서버가 빈 커서를 파싱하다 422 로 답할 수 있다.
      expect(captured.queryParameters.containsKey('before'), isFalse);
      expect(captured.queryParameters.containsKey('before_id'), isFalse);
    });

    test('created_at 을 문자열 그대로 들고 온다', () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions o, RequestInterceptorHandler h) => h.resolve(
            Response<Object?>(
              requestOptions: o,
              statusCode: 200,
              data: <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'noti-1',
                  'title': '제목',
                  'body': '본문',
                  'category': 'reminder',
                  'read': false,
                  'created_at': '2026-01-01T00:00:00+00:00',
                  'time_ago': '방금 전',
                },
              ],
            ),
          ),
        ),
      );

      final AlertItem item =
          (await DioNotificationRepository(dio).fetchPage()).single;

      // 다시 문자열로 만들면 표기가 미묘하게 달라져 커서 경계가 어긋난다.
      expect(item.createdAt, '2026-01-01T00:00:00+00:00');
    });
  });
}

/// 겹치는 경계를 흉내 내는 가짜 — 두 번째 쪽이 첫 쪽 마지막 항목을 다시 준다.
class _OverlappingRepo implements NotificationRepository {
  int _page = 0;

  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async {
    final int start = _page == 0 ? 0 : notificationPageSize - 1;
    _page++;
    return <AlertItem>[
      for (int i = start; i < start + notificationPageSize; i++) _item(i),
    ];
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}

  @override
  Future<int> unreadCount() async => 0;
}

/// 리포가 실제로 보낸 요청을 잡아 준다.
Future<RequestOptions> _capture(
  Future<void> Function(DioNotificationRepository repo) call,
) async {
  late RequestOptions captured;
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        captured = o;
        h.resolve(
          Response<Object?>(
            requestOptions: o,
            statusCode: 200,
            data: const <Object?>[],
          ),
        );
      },
    ),
  );
  await call(DioNotificationRepository(dio));
  return captured;
}
