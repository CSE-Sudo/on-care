/// 알림함 첫 조회 실패 안내가 원인을 말한다. (#3140)
///
/// 컨트롤러가 실패를 `failedToLoad` 참·거짓으로만 들고 있어, 화면은 왜 못
/// 받았는지 알 수 없었다. 이제 실패한 오류를 함께 들고, 성공하거나 다시 받기
/// 시작하면 내려놓는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/errors/app_error.dart';
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

class _Repo implements NotificationRepository {
  Object? error;
  List<AlertItem> items = const <AlertItem>[];

  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return items;
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}

  @override
  Future<int> unreadCount() async => 0;
}

void main() {
  group('NotificationState.loadError', () {
    test('copyWith 가 넘기지 않은 오류는 그대로 둔다', () {
      const NotificationState failed = NotificationState(
        items: <AlertItem>[],
        failedToLoad: true,
        loadError: NetworkError(),
      );
      expect(failed.copyWith(loading: true).loadError, isA<NetworkError>());
    });

    test('copyWith 에 null 을 넘기면 오류를 지운다', () {
      const NotificationState failed = NotificationState(
        items: <AlertItem>[],
        failedToLoad: true,
        loadError: NetworkError(),
      );
      expect(failed.copyWith(loadError: null).loadError, isNull);
    });
  });

  group('컨트롤러', () {
    test('실패하면 오류를 들고, 다시 받아 성공하면 내려놓는다', () async {
      final _Repo repo = _Repo()..error = const ServerError(statusCode: 503);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_realConfig),
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final NotificationController controller = container.read(
        notificationControllerProvider.notifier,
      );
      await controller.refresh();
      NotificationState state = container.read(notificationControllerProvider);
      expect(state.failedToLoad, isTrue);
      expect(state.loadError, isA<ServerError>());

      repo.error = null;
      await controller.refresh();
      state = container.read(notificationControllerProvider);
      expect(state.failedToLoad, isFalse);
      expect(state.loadError, isNull);
    });
  });

  testWidgets('첫 조회가 연결 끊김으로 실패하면 연결 확인 안내가 선다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final _Repo repo = _Repo()..error = const NetworkError();
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
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(NotificationPage)),
    );

    expect(
      find.byKey(const Key('notificationFirstLoadFailed')),
      findsOneWidget,
    );
    expect(find.text(l.alertLoadFailed), findsOneWidget);
    expect(find.text(l.errorNetwork), findsOneWidget);
  });
}
