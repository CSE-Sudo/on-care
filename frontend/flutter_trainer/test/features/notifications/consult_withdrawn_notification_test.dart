/// 회원 탈퇴로 사라진 상담 요청 알림. (#1632)
///
/// 회원이 탈퇴하면 대기 중이던 상담 요청이 함께 지워진다. 서버는 요청을 받은
/// 트레이너에게 `consult_withdrawn` 알림을 남기고(틀 `trainer_consult_withdrawn`,
/// 인자 `member_name`·`preferred_date`), 떠난 회원을 가리키는 `subject_id` 는
/// 두지 않는다. 트레이너 웹은 이 알림을 화면 언어로 조립하고, 누르면 상담
/// 요청함으로 간다 — 떠난 회원 상세로는 가지 않는다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/pages/notifications_page.dart';
import 'package:oncare_trainer/features/notifications/presentation/trainer_notification_text.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

import '../../helpers/pump_app.dart';

const String _template = 'trainer_consult_withdrawn';
const String _koTitle = '회원 탈퇴로 상담 요청이 취소됐어요';
const String _enTitle =
    'Consultation request cancelled: member account deleted';

final AppLocalizations _ko = AppLocalizationsKo();
final AppLocalizations _en = AppLocalizationsEn();

/// 서버가 주는 한 건 그대로. 제목·본문은 서버가 요청 언어로 조립한 값이다.
Map<String, Object?> _json({
  String id = 'noti-withdrawn',
  String category = 'consult_withdrawn',
  String title = _koTitle,
  String body = '지수 회원 · 2026-10-01',
  Object? subjectId,
  Object? args = const <String, Object?>{
    'member_name': '지수',
    'preferred_date': '2026-10-01',
  },
  Object? targetDate = '2026-10-01',
}) => <String, Object?>{
  'id': id,
  'title': title,
  'body': body,
  'category': category,
  'read': false,
  'created_at': '2026-09-27T01:00:00Z',
  'time_ago': '방금 전',
  'subject_id': subjectId,
  'template': _template,
  'args': args,
  'target_date': targetDate,
};

TrainerNotification _notice({
  String id = 'noti-withdrawn',
  bool read = false,
  String? subjectId,
  Map<String, Object?> args = const <String, Object?>{
    'member_name': '지수',
    'preferred_date': '2026-10-01',
  },
  String title = '저장된 제목',
  String body = '저장된 본문',
}) => TrainerNotification(
  id: id,
  title: title,
  body: body,
  kind: TrainerNotificationKind.consultationWithdrawn,
  read: read,
  createdAt: DateTime.utc(2026, 9, 27, 10),
  timeAgo: '3분 전',
  subjectId: subjectId,
  template: _template,
  args: args,
  targetDate: '2026-10-01',
);

class _FakeRepo implements TrainerNotificationRepository {
  _FakeRepo(this._rows);

  final List<TrainerNotification> _rows;
  final List<String> readCalls = <String>[];

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
  Future<void> markRead(String id) async => readCalls.add(id);

  @override
  Future<int> markAllRead() async => 0;
}

class _MockDio extends Mock implements Dio {}

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

void main() {
  group('서버 응답 읽기', () {
    test('consult_withdrawn 을 탈퇴 상담 취소 종류로 읽는다', () {
      final TrainerNotification n = TrainerNotification.fromJson(_json());

      expect(n.kind, TrainerNotificationKind.consultationWithdrawn);
      expect(n.template, _template);
      expect(n.args, <String, Object?>{
        'member_name': '지수',
        'preferred_date': '2026-10-01',
      });
      expect(n.targetDate, '2026-10-01');
      expect(n.subjectId, isNull);
    });

    test('다른 상담 종류와 섞이지 않는다', () {
      expect(
        TrainerNotification.fromJson(_json(category: 'consultation')).kind,
        TrainerNotificationKind.consultation,
      );
      expect(
        TrainerNotification.fromJson(_json(category: 'member_left')).kind,
        TrainerNotificationKind.memberLeft,
      );
    });

    test('인자 모양이 깨져도 목록은 읽힌다 — 저장된 문장으로 돌아간다', () {
      final TrainerNotification n = TrainerNotification.fromJson(
        _json(args: 'broken', targetDate: 'tomorrow'),
      );

      expect(n.kind, TrainerNotificationKind.consultationWithdrawn);
      expect(n.args, isEmpty);
      expect(n.targetDate, isNull);
      expect(trainerNotificationText(_en, n), (
        title: _koTitle,
        body: '지수 회원 · 2026-10-01',
      ));
    });

    test('저장소가 알림함 응답에서 그대로 읽는다', () async {
      const String path = '/trainer/notifications';
      final _MockDio dio = _MockDio();
      when(() => dio.get<List<dynamic>>(path)).thenAnswer(
        (_) async => Response<List<dynamic>>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: <dynamic>[_json()],
        ),
      );

      final TrainerNotificationPage page = await DioNotificationRepository(
        dio,
      ).fetch();

      final TrainerNotification n = page.items.single;
      expect(n.kind, TrainerNotificationKind.consultationWithdrawn);
      expect(n.template, _template);
      expect(n.targetDate, '2026-10-01');
      expect(page.hasMore, isFalse);
    });
  });

  group('문장 조립', () {
    test('한국어는 서버가 저장한 문장과 같다', () {
      expect(trainerNotificationText(_ko, _notice()), (
        title: _koTitle,
        body: '지수 회원 · 2026-10-01',
      ));
    });

    test('영어는 서버 영어 조립과 같다', () {
      expect(trainerNotificationText(_en, _notice()), (
        title: _enTitle,
        body: '지수 · 2026-10-01',
      ));
    });

    test('회원이 직접 취소한 알림과 제목이 다르다', () {
      expect(
        _ko.notifTplConsultWithdrawnTitle,
        isNot(_ko.notifTplConsultCancelledTitle),
      );
      expect(
        _en.notifTplConsultWithdrawnTitle,
        isNot(_en.notifTplConsultCancelledTitle),
      );
    });

    for (final Map<String, Object?> args in <Map<String, Object?>>[
      <String, Object?>{'member_name': '', 'preferred_date': '2026-10-01'},
      <String, Object?>{'member_name': ' 지수 ', 'preferred_date': '2026-10-01'},
      <String, Object?>{'preferred_date': '2026-10-01'},
      <String, Object?>{'member_name': '지수', 'preferred_date': ''},
      <String, Object?>{'member_name': '지수'},
      <String, Object?>{'member_name': '지수', 'preferred_date': 20261001},
    ]) {
      test('조립할 수 없는 인자 $args 는 저장된 문장을 쓴다', () {
        final TrainerNotification n = _notice(
          args: args,
          title: '서버 제목',
          body: '서버 본문',
        );
        for (final AppLocalizations l in <AppLocalizations>[_ko, _en]) {
          expect(trainerNotificationText(l, n), (
            title: '서버 제목',
            body: '서버 본문',
          ));
        }
      });
    }
  });

  group('이동할 곳', () {
    test('상담 요청함으로 간다', () {
      expect(NotificationsPage.targetOf(_notice()), AppRoutes.consultations);
    });

    test('회원 id 가 실려 와도 회원 상세로 가지 않는다', () {
      final String? target = NotificationsPage.targetOf(
        _notice(subjectId: 'user-gone'),
      );
      expect(target, AppRoutes.consultations);
      expect(target, isNot(contains('user-gone')));
    });

    test('회원이 떠난 알림(member_left)은 전처럼 이동하지 않는다', () {
      expect(
        NotificationsPage.targetOf(
          TrainerNotification.fromJson(_json(category: 'member_left')),
        ),
        isNull,
      );
    });
  });

  group('알림함', () {
    for (final (Locale locale, String title, String body)
        in const <(Locale, String, String)>[
          (Locale('ko'), _koTitle, '지수 회원 · 2026-10-01'),
          (Locale('en'), _enTitle, '지수 · 2026-10-01'),
        ]) {
      testWidgets('화면 언어로 제목·본문을 보인다 (${locale.languageCode})', (tester) async {
        await withWideSurface(tester, () async {
          await _pumpInbox(tester, <TrainerNotification>[
            _notice(),
          ], locale: locale);

          expect(find.text(title), findsOneWidget);
          expect(find.text(body), findsOneWidget);
          expect(find.byIcon(AppIcons.eventBusy), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });

      testWidgets('누르면 읽음 처리하고 상담 요청함을 연다 '
          '(${locale.languageCode})', (tester) async {
        await withWideSurface(tester, () async {
          final _FakeRepo repo = await _pumpInbox(tester, <TrainerNotification>[
            _notice(),
          ], locale: locale);

          await tester.tap(
            find.byKey(const ValueKey<String>('notification-noti-withdrawn')),
          );
          await settle(tester);

          expect(repo.readCalls, <String>['noti-withdrawn']);
          expect(Uri.parse(currentLocation(tester)).path, AppRoutes.schedule);
          expect(
            find.byKey(const ValueKey<String>('consultations-dialog')),
            findsOneWidget,
          );
        });
      });
    }

    testWidgets('이미 읽은 알림은 읽음 호출 없이 상담 요청함을 연다', (tester) async {
      await withWideSurface(tester, () async {
        final _FakeRepo repo = await _pumpInbox(tester, <TrainerNotification>[
          _notice(read: true),
        ]);

        await tester.tap(
          find.byKey(const ValueKey<String>('notification-noti-withdrawn')),
        );
        await settle(tester);

        expect(repo.readCalls, isEmpty);
        expect(Uri.parse(currentLocation(tester)).path, AppRoutes.schedule);
        expect(
          find.byKey(const ValueKey<String>('consultations-dialog')),
          findsOneWidget,
        );
      });
    });

    testWidgets('회원 탈퇴 알림과 함께 와도 각자 아이콘으로 구분된다', (tester) async {
      await withWideSurface(tester, () async {
        await _pumpInbox(tester, <TrainerNotification>[
          _notice(),
          TrainerNotification.fromJson(
            _json(
              id: 'noti-left',
              category: 'member_left',
              title: '회원 탈퇴',
              body: '지수 회원이 탈퇴했어요.',
              args: <String, Object?>{'member_name': '지수'},
              targetDate: null,
            )..['template'] = 'trainer_member_withdrawn',
          ),
        ]);

        expect(find.text(_koTitle), findsOneWidget);
        expect(find.text('회원 탈퇴'), findsOneWidget);
        expect(find.byIcon(AppIcons.eventBusy), findsOneWidget);
        expect(find.byIcon(AppIcons.memberLeft), findsOneWidget);
      });
    });
  });
}
