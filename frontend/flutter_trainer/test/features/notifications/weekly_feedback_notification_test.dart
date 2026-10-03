/// 회원 주간 피드백 알림. (#3026)
///
/// 회원이 한 주 컨디션·운동 강도·통증을 내도 트레이너는 리포트 화면을 직접 열어야
/// 답이 왔는지 알았다. 이제 알림함에 `weekly_feedback` 한 건이 오고, 누르면 그
/// 회원의 메모 창 `피드백` 탭(회원의 답이 모인 곳)이 바로 열린다.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/notifications/data/repositories/notification_repository.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/pages/notifications_page.dart';
import 'package:oncare_trainer/features/notifications/presentation/trainer_notification_text.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

TrainerNotification _feedback({Object? subject = 'user-jisu'}) =>
    TrainerNotification.fromJson(<String, Object?>{
      'id': 'noti-weekly',
      'title': '지수 회원이 통증을 알렸어요',
      'body': '컨디션 지쳤어요 · 운동 강도 너무 힘들었어요 · 통증 있음',
      'category': 'weekly_feedback',
      'read': false,
      'created_at': '2026-09-28T01:00:00Z',
      'time_ago': '방금 전',
      'subject_id': subject,
      'template': 'trainer_member_weekly_feedback',
      'args': <String, Object?>{
        'member_name': '지수',
        'condition': 'tired',
        'intensity': 'too_hard',
        'pain': true,
        'revised': false,
      },
      'target_date': '2026-09-21',
    });

void main() {
  group('종류와 이동', () {
    test('서버 갈래 weekly_feedback 을 안다', () {
      final TrainerNotification n = _feedback();
      expect(n.kind, TrainerNotificationKind.weeklyFeedback);
      expect(n.subjectId, 'user-jisu');
      expect(n.targetDate, '2026-09-21');
    });

    test('누르면 그 회원 메모 창의 피드백 탭으로 간다', () {
      final String? target = NotificationsPage.targetOf(_feedback());
      expect(target, AppRoutes.clientDetail('user-jisu', openFeedback: true));
      expect(Uri.parse(target!).queryParameters, <String, String>{
        AppRoutes.clientOpenParam: AppRoutes.clientOpenFeedback,
      });
    });

    test('회원이 기록되지 않은 알림은 고객 목록으로 간다', () {
      expect(
        NotificationsPage.targetOf(_feedback(subject: null)),
        AppRoutes.clients,
      );
    });

    test('회원 소식 묶음에 든다', () {
      final TrainerNotification n = _feedback();
      expect(NotificationGroup.members.includes(n), isTrue);
      expect(NotificationGroup.all.includes(n), isTrue);
      expect(NotificationGroup.messages.includes(n), isFalse);
      expect(NotificationGroup.consultations.includes(n), isFalse);
      expect(NotificationGroup.reservations.includes(n), isFalse);
    });

    test('화면 문장은 ARB 로 조립한다', () {
      final TrainerNotificationText text = trainerNotificationText(
        AppLocalizationsKo(),
        _feedback(),
      );
      expect(text.title, '지수 회원이 통증을 알렸어요');
      expect(text.body, '컨디션 지쳤어요 · 운동 강도 너무 힘들었어요 · 통증 있음');
    });
  });

  group('주소', () {
    test('피드백 창을 여는 주소는 open=feedback 이다', () {
      expect(
        AppRoutes.clientDetail('a b', openFeedback: true),
        '/clients/a%20b/diet?open=feedback',
      );
    });

    test('필터와 함께 실린다', () {
      final Uri uri = Uri.parse(
        AppRoutes.clientDetail('c1', filter: 'risk', openFeedback: true),
      );
      expect(uri.queryParameters, <String, String>{
        'f': 'risk',
        AppRoutes.clientOpenParam: AppRoutes.clientOpenFeedback,
      });
    });

    test('창은 하나만 연다 — 주의사항이 함께 오면 주의사항이 이긴다', () {
      final Uri uri = Uri.parse(
        AppRoutes.clientDetail('c1', openHealthNotes: true, openFeedback: true),
      );
      expect(
        uri.queryParameters[AppRoutes.clientOpenParam],
        AppRoutes.clientOpenHealthNotes,
      );
    });

    test('아무 창도 열지 않으면 쿼리가 없다', () {
      expect(AppRoutes.clientDetail('c1'), '/clients/c1/diet');
    });
  });

  group('데모', () {
    test('데모 알림함에 주간 피드백 알림이 있다', () async {
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await seedIfEmpty(db, clock: kMidWeekKst);

      final TrainerNotificationPage page = await DemoNotificationRepository(
        db,
      ).fetch();
      final TrainerNotification n = page.items.firstWhere(
        (TrainerNotification i) =>
            i.template == 'trainer_member_weekly_feedback',
      );
      expect(n.kind, TrainerNotificationKind.weeklyFeedback);
      expect(n.subjectId, 'seed-client-1');
      expect(n.read, isFalse);
      expect(n.args['member_name'], isNotEmpty);
      // 그 주 월요일을 가리킨다.
      expect(DateTime.parse(n.targetDate!).weekday, DateTime.monday);
      // 알림 미리보기에는 아픈 곳 글이 없다.
      expect(n.args.containsKey('pain_area'), isFalse);
    });
  });

  group('딥 링크', () {
    Future<void> open(WidgetTester tester, String location) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(tester, token: 'demo-trainer-token', at: location);
      await settle(tester);
    }

    final Finder memoDialog = find.byKey(
      const ValueKey<String>('client-memo-dialog'),
    );

    testWidgets('알림에서 온 상세는 메모 창의 피드백 탭을 연다', (tester) async {
      await open(
        tester,
        AppRoutes.clientDetail('seed-client-1', openFeedback: true),
      );

      expect(memoDialog, findsOneWidget);
      // 피드백 탭의 안내 문구 — 메모 탭에는 없다.
      expect(
        find.text('회원과 주고받은 피드백이에요. 누르면 쓴 자리로 가서 고칠 수 있어요.'),
        findsOneWidget,
      );
    });

    testWidgets('그냥 들어온 상세는 메모 창을 열지 않는다', (tester) async {
      await open(tester, AppRoutes.clientDetail('seed-client-1'));

      expect(memoDialog, findsNothing);
    });
  });
}
