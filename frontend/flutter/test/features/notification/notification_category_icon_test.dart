/// 알림함 줄의 갈래 아이콘 — 서버 갈래마다 다르다. (#2084·#2085)
///
/// 예전에는 서버 갈래를 네 가지로 접어서 트레이너가 한 일(루틴·대화·일정·상담)이
/// 모두 종 아이콘으로 뭉쳤고, 건강 목표 변경은 공지와 같은 ⓘ 에 화면 읽기 라벨도
/// `시스템` 이었다. 여기서는 서버가 준 갈래 문자열부터 줄에 그려진 아이콘·라벨까지
/// 한 번에 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/notification/data/repositories/dio_notification_repository.dart';
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

/// 서버 갈래 → 기대하는 아이콘과 한국어 화면 읽기 라벨.
const Map<String, (IconData, String)> _expected = <String, (IconData, String)>{
  'reminder': (AppIcons.notifications, '리마인더'),
  'coach_chat': (AppIcons.chat, '트레이너 메시지'),
  'coach_report': (AppIcons.document, '주간 리포트'),
  'routine': (AppIcons.routine, '운동 루틴'),
  'member_schedule': (AppIcons.eventAvailable, 'PT 일정'),
  'coach_invite': (AppIcons.person, '담당 트레이너'),
  'consultation_result': (AppIcons.person, '담당 트레이너'),
  'consult_decision': (AppIcons.request, '상담 요청'),
  'health_goals': (AppIcons.goal, '건강 목표'),
  'benefits': (AppIcons.coupon, '혜택'),
  'points_shop': (AppIcons.challenge, '챌린지'),
  'achievement': (AppIcons.achievement, '달성'),
  'system': (AppIcons.info, '시스템'),
  // 보내는 곳이 없는 옛 갈래·모르는 갈래.
  'health_check': (AppIcons.notifications, '리마인더'),
  'brand_new': (AppIcons.info, '시스템'),
};

/// 서버 갈래마다 한 건씩 주는 가짜 서버. 갈래 해석은 실서버와 같은 함수를 쓴다.
class _OnePerCategoryRepo implements NotificationRepository {
  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async => <AlertItem>[
    for (final String wire in _expected.keys)
      AlertItem(
        id: wire,
        title: wire,
        body: '',
        timeAgo: '방금 전',
        category: DioNotificationRepository.categoryFromWire(wire),
        wireCategory: wire,
      ),
  ];

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}

  @override
  Future<int> unreadCount() async => _expected.length;
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_realConfig),
        notificationRepositoryProvider.overrideWithValue(_OnePerCategoryRepo()),
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
}

Finder _rowOf(String id) =>
    find.byKey(ValueKey<String>('notification-row-$id'));

IconData? _iconOf(WidgetTester tester, String id) => tester
    .widget<Icon>(find.descendant(of: _rowOf(id), matching: find.byType(Icon)))
    .icon;

void main() {
  testWidgets('서버 갈래마다 정한 아이콘과 화면 읽기 라벨로 그린다', (WidgetTester tester) async {
    await _pump(tester);

    _expected.forEach((String wire, (IconData, String) want) {
      expect(_iconOf(tester, wire), want.$1, reason: wire);
      expect(
        tester.widget<Semantics>(_rowOf(wire)).properties.label,
        want.$2,
        reason: wire,
      );
    });
  });

  testWidgets('트레이너가 한 일은 종 아이콘으로 뭉치지 않는다', (WidgetTester tester) async {
    await _pump(tester);

    for (final String wire in <String>[
      'coach_chat',
      'coach_report',
      'routine',
      'member_schedule',
      'consultation_result',
      'consult_decision',
      'health_goals',
    ]) {
      expect(
        _iconOf(tester, wire),
        isNot(AppIcons.notifications),
        reason: wire,
      );
    }
  });

  testWidgets('주간 리포트와 트레이너 메시지는 다른 아이콘이다', (WidgetTester tester) async {
    await _pump(tester);

    expect(
      _iconOf(tester, 'coach_report'),
      isNot(_iconOf(tester, 'coach_chat')),
    );
  });

  testWidgets('건강 목표 변경은 공지처럼 보이지 않는다', (WidgetTester tester) async {
    await _pump(tester);

    expect(_iconOf(tester, 'health_goals'), isNot(AppIcons.info));
    expect(
      tester.widget<Semantics>(_rowOf('health_goals')).properties.label,
      isNot('시스템'),
    );
  });

  testWidgets('포인트 별은 알림 갈래에 쓰지 않는다', (WidgetTester tester) async {
    await _pump(tester);

    for (final String wire in _expected.keys) {
      expect(_iconOf(tester, wire), isNot(AppIcons.points), reason: wire);
    }
  });
}
