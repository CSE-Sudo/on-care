/// 메시지 알림은 보낸 회원의 대화로 간다. (#2291)
///
/// 전에는 메시지 알림을 누르면 고객 목록으로 가서, 누가 보낸 메시지인지 다시
/// 찾아 들어가야 했다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_view.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/pages/notifications_page.dart';

import '../../helpers/pump_app.dart';

TrainerNotification _message({
  String id = 'noti-msg',
  String? subjectId,
  bool read = false,
  String title = '이지수 회원의 메시지',
}) => TrainerNotification(
  id: id,
  title: title,
  body: '오늘 수업 시간 조정 가능할까요?',
  kind: TrainerNotificationKind.message,
  read: read,
  createdAt: DateTime.utc(2026, 9, 27, 10),
  timeAgo: '3분 전',
  subjectId: subjectId,
);

TrainerNotification _fromJson(Object? subjectId) =>
    TrainerNotification.fromJson(<String, Object?>{
      'id': 'noti-json',
      'title': '이지수 회원의 메시지',
      'body': '안녕하세요',
      'category': 'message',
      'read': false,
      'created_at': '2026-09-27T01:00:00Z',
      'time_ago': '방금 전',
      'subject_id': subjectId,
    });

/// 읽음 처리 호출을 기록하는 페이크.
class _FakeRepo implements TrainerNotificationRepository {
  _FakeRepo(this._rows, {this.failRead = false});

  List<TrainerNotification> _rows;
  final bool failRead;
  final List<String> readCalls = <String>[];

  @override
  bool get supportsInbox => true;

  @override
  Future<List<TrainerNotification>> fetch() async => _rows;

  @override
  Stream<List<TrainerNotification>> watch() =>
      Stream<List<TrainerNotification>>.value(_rows);

  @override
  Future<int> unreadCount() async =>
      _rows.where((TrainerNotification r) => !r.read).length;

  @override
  Stream<int> watchUnreadCount() => Stream<int>.fromFuture(unreadCount());

  @override
  Future<void> markRead(String id) async {
    readCalls.add(id);
    if (failRead) throw StateError('read failed');
    _rows = <TrainerNotification>[
      for (final TrainerNotification r in _rows)
        if (r.id == id)
          _message(id: r.id, subjectId: r.subjectId, read: true, title: r.title)
        else
          r,
    ];
  }

  @override
  Future<int> markAllRead() async => 0;
}

void main() {
  group('targetOf', () {
    test('보낸 회원이 있으면 그 회원 대화로 간다', () {
      expect(
        NotificationsPage.targetOf(_message(subjectId: 'user-jisu')),
        AppRoutes.messagesFor('user-jisu'),
      );
      expect(
        NotificationsPage.targetOf(_message(subjectId: 'user-jisu')),
        '/messages?client=user-jisu',
      );
    });

    test('보낸 회원이 없는 옛 알림은 메시지 목록으로 간다', () {
      expect(NotificationsPage.targetOf(_message()), AppRoutes.messages);
      // 고객 목록으로 가던 예전 동작으로 돌아가지 않는다.
      expect(NotificationsPage.targetOf(_message()), isNot(AppRoutes.clients));
    });

    test('회원 id 의 특수 문자는 주소에서 인코딩된다', () {
      final String target = NotificationsPage.targetOf(
        _message(subjectId: 'user a&b'),
      )!;
      expect(Uri.parse(target).path, AppRoutes.messages);
      expect(Uri.parse(target).queryParameters['client'], 'user a&b');
    });

    test('읽음 여부와 상관없이 같은 곳으로 간다', () {
      expect(
        NotificationsPage.targetOf(_message(subjectId: 'm1', read: true)),
        NotificationsPage.targetOf(_message(subjectId: 'm1')),
      );
    });

    test('건강 목표 변경 알림의 이동은 그대로다(회귀)', () {
      final TrainerNotification goal = TrainerNotification(
        id: 'noti-goal',
        title: '건강 목표 변경',
        body: '',
        kind: TrainerNotificationKind.healthGoal,
        read: false,
        createdAt: DateTime.utc(2026, 9, 27),
        timeAgo: '',
        subjectId: 'user-jisu',
      );
      expect(
        NotificationsPage.targetOf(goal),
        AppRoutes.clientDetail('user-jisu'),
      );
    });
  });

  group('fromJson', () {
    test('subject_id 를 보낸 회원으로 읽는다', () {
      final TrainerNotification n = _fromJson('user-jisu');
      expect(n.kind, TrainerNotificationKind.message);
      expect(n.subjectId, 'user-jisu');
      expect(NotificationsPage.targetOf(n), '/messages?client=user-jisu');
    });

    test('subject_id 가 null 이면 메시지 목록으로 간다', () {
      final TrainerNotification n = _fromJson(null);
      expect(n.subjectId, isNull);
      expect(NotificationsPage.targetOf(n), AppRoutes.messages);
    });

    test('subject_id 가 빈 문자열이면 없는 것으로 본다', () {
      final TrainerNotification n = _fromJson('');
      expect(n.subjectId, isNull);
      expect(NotificationsPage.targetOf(n), AppRoutes.messages);
    });

    test('subject_id 가 문자열이 아니면 없는 것으로 본다', () {
      final TrainerNotification n = _fromJson(42);
      expect(n.subjectId, isNull);
      expect(NotificationsPage.targetOf(n), AppRoutes.messages);
    });
  });

  group('알림함에서 누르기', () {
    for (final Locale locale in const <Locale>[Locale('ko'), Locale('en')]) {
      testWidgets('메시지 알림은 읽음 처리 후 그 회원 대화를 연다 '
          '(${locale.languageCode})', (tester) async {
        await withWideSurface(tester, () async {
          final _FakeRepo repo = _FakeRepo(<TrainerNotification>[
            _message(subjectId: 'seed-client-1'),
          ]);
          await pumpTrainerApp(
            tester,
            token: 'demo-token',
            at: AppRoutes.notifications,
            locale: locale,
            extraOverrides: <Override>[
              trainerNotificationRepositoryProvider.overrideWithValue(repo),
            ],
          );

          await tester.tap(
            find.byKey(const ValueKey<String>('notification-noti-msg')),
          );
          await settle(tester);

          expect(repo.readCalls, <String>['noti-msg']);
          expect(currentLocation(tester), '/messages?client=seed-client-1');
          final ChatView chat = tester.widget<ChatView>(find.byType(ChatView));
          expect(chat.clientId, 'seed-client-1');
        });
      });
    }

    testWidgets('보낸 회원이 없는 옛 메시지 알림은 메시지 목록을 연다', (tester) async {
      await withWideSurface(tester, () async {
        final _FakeRepo repo = _FakeRepo(<TrainerNotification>[_message()]);
        await pumpTrainerApp(
          tester,
          token: 'demo-token',
          at: AppRoutes.notifications,
          extraOverrides: <Override>[
            trainerNotificationRepositoryProvider.overrideWithValue(repo),
          ],
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('notification-noti-msg')),
        );
        await settle(tester);

        expect(repo.readCalls, <String>['noti-msg']);
        expect(Uri.parse(currentLocation(tester)).path, AppRoutes.messages);
      });
    });

    testWidgets('이미 읽은 메시지 알림은 읽음 호출 없이 대화를 연다', (tester) async {
      await withWideSurface(tester, () async {
        final _FakeRepo repo = _FakeRepo(<TrainerNotification>[
          _message(subjectId: 'seed-client-2', read: true),
        ]);
        await pumpTrainerApp(
          tester,
          token: 'demo-token',
          at: AppRoutes.notifications,
          extraOverrides: <Override>[
            trainerNotificationRepositoryProvider.overrideWithValue(repo),
          ],
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('notification-noti-msg')),
        );
        await settle(tester);

        expect(repo.readCalls, isEmpty);
        expect(currentLocation(tester), '/messages?client=seed-client-2');
      });
    });

    testWidgets('읽음 처리가 실패해도 대화로 이동한다', (tester) async {
      await withWideSurface(tester, () async {
        final _FakeRepo repo = _FakeRepo(<TrainerNotification>[
          _message(subjectId: 'seed-client-1'),
        ], failRead: true);
        await pumpTrainerApp(
          tester,
          token: 'demo-token',
          at: AppRoutes.notifications,
          extraOverrides: <Override>[
            trainerNotificationRepositoryProvider.overrideWithValue(repo),
          ],
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('notification-noti-msg')),
        );
        await settle(tester);

        expect(repo.readCalls, <String>['noti-msg']);
        expect(currentLocation(tester), '/messages?client=seed-client-1');
      });
    });
  });
}
