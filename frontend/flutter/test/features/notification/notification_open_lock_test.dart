/// 알림함에서 이동이 끝나기 전 같은 알림을 또 누르면 — #3097.
///
/// 대화 알림은 코치 정보를 새로 받은 뒤에 대화 화면을 연다. 그 사이 한 번 더
/// 누르면 대화 화면이 두 겹 쌓였다. 이동이 끝날 때까지 다른 줄 탭을 받지 않고,
/// 누른 줄에 작은 로딩 표시를 단다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/features/notification/presentation/pages/notification_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

const AlertItem _chatAlert = AlertItem(
  id: 'chat-1',
  title: '트레이너 메시지',
  body: '오늘 운동 어땠어요?',
  timeAgo: '방금',
  category: AlertCategory.coachChat,
  action: AlertAction(label: '메시지 보기', target: AlertTarget.coachChat),
);

const AlertItem _otherAlert = AlertItem(
  id: 'chat-2',
  title: '트레이너 메시지 2',
  body: '내일 봬요',
  timeAgo: '방금',
  category: AlertCategory.coachChat,
  action: AlertAction(label: '메시지 보기', target: AlertTarget.coachChat),
);

class _Repo implements NotificationRepository {
  final List<String> marked = <String>[];

  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async => const <AlertItem>[_chatAlert, _otherAlert];

  @override
  Future<void> markRead(String id) async => marked.add(id);

  @override
  Future<void> markAllRead() async {}

  @override
  Future<int> unreadCount() async => 0;
}

void main() {
  testWidgets('코치 조회 중 대화 알림을 여러 번 눌러도 한 번만 연다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    int coachFetches = 0;
    Completer<MemberCoach?> coach = Completer<MemberCoach?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          notificationRepositoryProvider.overrideWithValue(_Repo()),
          notificationUnreadProvider.overrideWith(
            (ref) => Stream<int>.value(0),
          ),
          memberCoachProvider.overrideWith((ref) {
            coachFetches++;
            return coach.future;
          }),
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

    final Finder row = find.byKey(
      const ValueKey<String>('notification-ink-chat-1'),
    );
    await tester.tap(row);
    await tester.pump();
    // 누른 줄에 이동 중 표시가 선다.
    expect(
      find.byKey(const ValueKey<String>('notification-opening-chat-1')),
      findsOneWidget,
    );

    // 코치 조회가 끝나기 전 같은 줄과 다른 줄을 다시 누른다.
    await tester.tap(row);
    await tester.tap(
      find.byKey(const ValueKey<String>('notification-ink-chat-2')),
    );
    await tester.pump();
    expect(coachFetches, 1);
    expect(
      find.byKey(const ValueKey<String>('notification-opening-chat-2')),
      findsNothing,
    );

    // 담당이 끊긴 것으로 답한다 — 대화는 열리지 않고 안내만 뜬다.
    coach.complete(null);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('notification-opening-chat-1')),
      findsNothing,
    );

    // 띄운 안내가 스스로 내려갈 때까지 시간을 흘린다.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    // 이동이 끝났으니 다시 누를 수 있다.
    coach = Completer<MemberCoach?>();
    await tester.tap(row);
    await tester.pump();
    expect(coachFetches, 2);
    coach.complete(null);

    // 띄운 토스트가 스스로 내려갈 때까지 시간을 흘린다.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });
}
