/// 상담·예약·담당 요청 알림의 이동 목적지. (#2292)
///
/// 전에는 상담·예약 알림이 모두 오늘 주 스케줄로만 갔고, 담당 요청 수락·거절
/// 알림은 상담 종류로 남아 역시 스케줄로 갔다. 이제 상담은 상담 요청함으로,
/// 예약은 그 수업 날짜의 스케줄로, 수락은 새 담당 회원 상세로, 거절은 고객
/// 목록으로 간다. 대상이 기록되기 전의 옛 알림은 전처럼 스케줄로 간다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/pages/notifications_page.dart';
import 'package:oncare_trainer/features/schedule/presentation/pages/schedule_page.dart';

import '../../helpers/pump_app.dart';

TrainerNotification _notice(
  TrainerNotificationKind kind, {
  String id = 'noti-target',
  String? subjectId,
  String? targetDate,
  bool read = false,
  String title = '알림 제목',
}) => TrainerNotification(
  id: id,
  title: title,
  body: '이지수 회원 · 10월 02일 10:00',
  kind: kind,
  read: read,
  createdAt: DateTime.utc(2026, 9, 27, 10),
  timeAgo: '3분 전',
  subjectId: subjectId,
  targetDate: targetDate,
);

TrainerNotification _fromJson(
  String category, {
  Object? subject,
  Object? date,
}) => TrainerNotification.fromJson(<String, Object?>{
  'id': 'noti-json',
  'title': '제목',
  'body': '본문',
  'category': category,
  'read': false,
  'created_at': '2026-09-27T01:00:00Z',
  'time_ago': '방금 전',
  'subject_id': subject,
  'target_date': date,
});

/// 읽음 처리 호출을 기록하는 페이크.
class _FakeRepo implements TrainerNotificationRepository {
  _FakeRepo(this._rows);

  List<TrainerNotification> _rows;
  final List<String> readCalls = <String>[];

  @override
  bool get supportsInbox => true;

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async => TrainerNotificationPage(items: _rows);

  @override
  Stream<TrainerNotificationPage> watch() =>
      Stream<TrainerNotificationPage>.value(
        TrainerNotificationPage(items: _rows),
      );

  @override
  Future<int> unreadCount() async =>
      _rows.where((TrainerNotification r) => !r.read).length;

  @override
  Stream<int> watchUnreadCount() => Stream<int>.fromFuture(unreadCount());

  @override
  Future<void> markRead(String id) async {
    readCalls.add(id);
    _rows = <TrainerNotification>[
      for (final TrainerNotification r in _rows)
        if (r.id == id)
          _notice(
            r.kind,
            id: r.id,
            subjectId: r.subjectId,
            targetDate: r.targetDate,
            read: true,
            title: r.title,
          )
        else
          r,
    ];
  }

  @override
  Future<int> markAllRead() async => 0;
}

Future<_FakeRepo> _pumpInbox(
  WidgetTester tester,
  List<TrainerNotification> rows, {
  Locale locale = const Locale('ko'),
}) async {
  final _FakeRepo repo = _FakeRepo(rows);
  await pumpTrainerApp(
    tester,
    token: 'demo-token',
    at: AppRoutes.notifications,
    locale: locale,
    extraOverrides: <Override>[
      trainerNotificationRepositoryProvider.overrideWithValue(repo),
    ],
  );
  return repo;
}

Future<void> _tap(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey<String>('notification-$id')));
  await settle(tester);
}

void main() {
  group('targetOf — 예약', () {
    test('수업 날짜가 있으면 그 날짜의 스케줄로 간다', () {
      final String? target = NotificationsPage.targetOf(
        _notice(
          TrainerNotificationKind.reservation,
          subjectId: 'user-jisu',
          targetDate: '2026-10-02',
        ),
      );
      expect(target, AppRoutes.scheduleAt(date: '2026-10-02'));
      expect(target, '/schedule?d=2026-10-02');
    });

    test('날짜가 없는 옛 예약 알림은 전처럼 오늘 스케줄로 간다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(TrainerNotificationKind.reservation),
        ),
        AppRoutes.schedule,
      );
    });

    test('회원만 있고 날짜가 없어도 오늘 스케줄로 간다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(TrainerNotificationKind.reservation, subjectId: 'user-jisu'),
        ),
        AppRoutes.schedule,
      );
    });

    test('연말 날짜도 그대로 싣는다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(
            TrainerNotificationKind.reservation,
            targetDate: '2026-12-31',
          ),
        ),
        '/schedule?d=2026-12-31',
      );
    });
  });

  group('targetOf — 상담', () {
    test('회원이 기록된 상담 알림은 상담 요청함으로 간다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(
            TrainerNotificationKind.consultation,
            subjectId: 'user-jisu',
            targetDate: '2026-10-03',
          ),
        ),
        AppRoutes.consultations,
      );
      expect(AppRoutes.consultations, '/schedule/consultations');
    });

    test('희망 날짜가 없어도 회원이 있으면 상담 요청함이다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(TrainerNotificationKind.consultation, subjectId: 'user-jisu'),
        ),
        AppRoutes.consultations,
      );
    });

    test('대상이 없는 옛 상담 알림은 전처럼 스케줄로 간다', () {
      // 옛 담당 요청 결과도 상담 종류로 남아 있어 상담 요청함이 맞는지 모른다.
      expect(
        NotificationsPage.targetOf(
          _notice(TrainerNotificationKind.consultation),
        ),
        AppRoutes.schedule,
      );
    });
  });

  group('targetOf — 담당 요청 결과', () {
    test('수락은 새 담당 회원 상세로 간다', () {
      final String? target = NotificationsPage.targetOf(
        _notice(TrainerNotificationKind.inviteAccepted, subjectId: 'user-new'),
      );
      expect(target, AppRoutes.clientDetail('user-new'));
      expect(target, '/clients/user-new/diet');
    });

    test('회원이 없는 수락 알림은 고객 목록으로 간다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(TrainerNotificationKind.inviteAccepted),
        ),
        AppRoutes.clients,
      );
    });

    test('수락한 회원 id 의 특수 문자는 인코딩된다', () {
      final String target = NotificationsPage.targetOf(
        _notice(TrainerNotificationKind.inviteAccepted, subjectId: 'user a/b'),
      )!;
      expect(target, '/clients/${Uri.encodeComponent('user a/b')}/diet');
    });

    test('거절은 회원이 있어도 고객 목록으로 간다 — 담당이 아니다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(TrainerNotificationKind.inviteRejected, subjectId: 'user-x'),
        ),
        AppRoutes.clients,
      );
      expect(
        NotificationsPage.targetOf(
          _notice(TrainerNotificationKind.inviteRejected),
        ),
        AppRoutes.clients,
      );
    });
  });

  group('targetOf — 다른 종류는 그대로(회귀)', () {
    test('회원 탈퇴·모르는 종류는 이동하지 않는다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(TrainerNotificationKind.memberLeft, targetDate: '2026-10-01'),
        ),
        isNull,
      );
      expect(
        NotificationsPage.targetOf(_notice(TrainerNotificationKind.other)),
        isNull,
      );
    });

    test('메시지·건강 목표는 날짜가 있어도 원래 목적지다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(
            TrainerNotificationKind.message,
            subjectId: 'user-jisu',
            targetDate: '2026-10-01',
          ),
        ),
        AppRoutes.messagesFor('user-jisu'),
      );
      expect(
        NotificationsPage.targetOf(
          _notice(
            TrainerNotificationKind.healthGoal,
            subjectId: 'user-jisu',
            targetDate: '2026-10-01',
          ),
        ),
        AppRoutes.clientDetail('user-jisu'),
      );
    });
  });

  group('fromJson', () {
    test('invite_accepted·invite_rejected 를 각 종류로 읽는다', () {
      expect(
        _fromJson('invite_accepted').kind,
        TrainerNotificationKind.inviteAccepted,
      );
      expect(
        _fromJson('invite_rejected').kind,
        TrainerNotificationKind.inviteRejected,
      );
    });

    test('target_date 를 그대로 읽는다', () {
      final TrainerNotification n = _fromJson(
        'reservation',
        subject: 'user-jisu',
        date: '2026-10-02',
      );
      expect(n.kind, TrainerNotificationKind.reservation);
      expect(n.subjectId, 'user-jisu');
      expect(n.targetDate, '2026-10-02');
      expect(NotificationsPage.targetOf(n), '/schedule?d=2026-10-02');
    });

    test('target_date 가 없거나 null 이면 없다', () {
      expect(_fromJson('reservation').targetDate, isNull);
      final TrainerNotification missing =
          TrainerNotification.fromJson(<String, Object?>{
            'id': 'noti-old',
            'category': 'reservation',
            'created_at': '2026-09-27T01:00:00Z',
          });
      expect(missing.targetDate, isNull);
      expect(NotificationsPage.targetOf(missing), AppRoutes.schedule);
    });

    for (final Object bad in <Object>[
      '',
      '2026-10-2',
      '2026/10/02',
      '2026-10-02T10:00:00',
      '2026-02-30',
      '2026-13-01',
      'tomorrow',
      20261002,
    ]) {
      test('형식이 맞지 않는 target_date($bad)는 버리고 오늘 스케줄로 간다', () {
        final TrainerNotification n = _fromJson('reservation', date: bad);
        expect(n.targetDate, isNull);
        expect(NotificationsPage.targetOf(n), AppRoutes.schedule);
      });
    }

    test('윤년 2월 29일은 올바른 날짜다', () {
      expect(
        _fromJson('reservation', date: '2028-02-29').targetDate,
        '2028-02-29',
      );
      expect(_fromJson('reservation', date: '2027-02-29').targetDate, isNull);
    });

    test('옛 상담 알림(회원 없음)은 스케줄로, 새 알림은 상담 요청함으로', () {
      expect(
        NotificationsPage.targetOf(_fromJson('consultation')),
        AppRoutes.schedule,
      );
      expect(
        NotificationsPage.targetOf(
          _fromJson('consultation', subject: 'user-jisu', date: '2026-10-03'),
        ),
        AppRoutes.consultations,
      );
    });
  });

  group('알림함에서 누르기', () {
    for (final Locale locale in const <Locale>[Locale('ko'), Locale('en')]) {
      testWidgets('예약 알림은 그 수업 날짜의 스케줄을 연다 '
          '(${locale.languageCode})', (tester) async {
        await withWideSurface(tester, () async {
          final _FakeRepo repo = await _pumpInbox(tester, <TrainerNotification>[
            _notice(
              TrainerNotificationKind.reservation,
              id: 'noti-res',
              subjectId: 'seed-client-1',
              targetDate: '2026-10-02',
              title: '새 예약이 들어왔어요',
            ),
          ], locale: locale);

          await _tap(tester, 'noti-res');

          expect(repo.readCalls, <String>['noti-res']);
          expect(currentLocation(tester), '/schedule?d=2026-10-02');
          final SchedulePage page = tester.widget<SchedulePage>(
            find.byType(SchedulePage),
          );
          expect(page.date, '2026-10-02');
        });
      });

      testWidgets('상담 알림은 상담 요청함을 연다 (${locale.languageCode})', (tester) async {
        await withWideSurface(tester, () async {
          final _FakeRepo repo = await _pumpInbox(tester, <TrainerNotification>[
            _notice(
              TrainerNotificationKind.consultation,
              id: 'noti-consult',
              subjectId: 'seed-client-1',
              targetDate: '2026-10-03',
              title: '새 상담 요청이 도착했어요',
            ),
          ], locale: locale);

          await _tap(tester, 'noti-consult');

          expect(repo.readCalls, <String>['noti-consult']);
          expect(
            Uri.parse(currentLocation(tester)).path,
            AppRoutes.consultations,
          );
        });
      });

      testWidgets('담당 요청 수락 알림은 그 회원 상세를 연다 '
          '(${locale.languageCode})', (tester) async {
        await withWideSurface(tester, () async {
          final _FakeRepo repo = await _pumpInbox(tester, <TrainerNotification>[
            _notice(
              TrainerNotificationKind.inviteAccepted,
              id: 'noti-accept',
              subjectId: 'seed-client-1',
              title: '담당 요청이 수락되었어요',
            ),
          ], locale: locale);

          await _tap(tester, 'noti-accept');

          expect(repo.readCalls, <String>['noti-accept']);
          expect(currentLocation(tester), '/clients/seed-client-1/diet');
        });
      });

      testWidgets('담당 요청 거절 알림은 고객 목록을 연다 (${locale.languageCode})', (
        tester,
      ) async {
        await withWideSurface(tester, () async {
          final _FakeRepo repo = await _pumpInbox(tester, <TrainerNotification>[
            _notice(
              TrainerNotificationKind.inviteRejected,
              id: 'noti-reject',
              subjectId: 'user-stranger',
              title: '담당 요청이 거절되었어요',
            ),
          ], locale: locale);

          await _tap(tester, 'noti-reject');

          expect(repo.readCalls, <String>['noti-reject']);
          expect(Uri.parse(currentLocation(tester)).path, AppRoutes.clients);
        });
      });
    }

    testWidgets('날짜가 없는 옛 예약 알림은 오늘 스케줄을 연다', (tester) async {
      await withWideSurface(tester, () async {
        final _FakeRepo repo = await _pumpInbox(tester, <TrainerNotification>[
          _notice(TrainerNotificationKind.reservation, id: 'noti-old-res'),
        ]);

        await _tap(tester, 'noti-old-res');

        expect(repo.readCalls, <String>['noti-old-res']);
        expect(currentLocation(tester), AppRoutes.schedule);
      });
    });

    testWidgets('이미 읽은 예약 알림은 읽음 호출 없이 그 날짜로 간다', (tester) async {
      await withWideSurface(tester, () async {
        final _FakeRepo repo = await _pumpInbox(tester, <TrainerNotification>[
          _notice(
            TrainerNotificationKind.reservation,
            id: 'noti-read-res',
            targetDate: '2026-11-15',
            read: true,
          ),
        ]);

        await _tap(tester, 'noti-read-res');

        expect(repo.readCalls, isEmpty);
        expect(currentLocation(tester), '/schedule?d=2026-11-15');
      });
    });

    testWidgets('담당 요청 결과 알림은 알림함에 제목·본문과 함께 보인다', (tester) async {
      await withWideSurface(tester, () async {
        await _pumpInbox(tester, <TrainerNotification>[
          _notice(
            TrainerNotificationKind.inviteAccepted,
            id: 'noti-a',
            subjectId: 'seed-client-1',
            title: '담당 요청이 수락되었어요',
          ),
          _notice(
            TrainerNotificationKind.inviteRejected,
            id: 'noti-r',
            title: '담당 요청이 거절되었어요',
          ),
        ]);

        expect(find.text('담당 요청이 수락되었어요'), findsOneWidget);
        expect(find.text('담당 요청이 거절되었어요'), findsOneWidget);
        expect(find.byIcon(Icons.how_to_reg_rounded), findsOneWidget);
        expect(find.byIcon(Icons.person_off_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
