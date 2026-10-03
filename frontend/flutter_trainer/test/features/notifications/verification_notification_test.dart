/// 운영자 승인·반려 알림 (#3010).
///
/// 서버는 `category='verification'` 에 틀 `trainer_verification_approved` /
/// `trainer_verification_rejected`(인자 `has_note`)를 준다. 승인은 대시보드로,
/// 반려는 사유를 보고 프로필을 고칠 MY 로 간다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/pages/notifications_page.dart';
import 'package:oncare_trainer/features/notifications/presentation/trainer_notification_text.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

final AppLocalizations _ko = AppLocalizationsKo();
final AppLocalizations _en = AppLocalizationsEn();

TrainerNotification _notice({
  String? template,
  Map<String, Object?> args = const <String, Object?>{},
  String title = '운영자 승인이 반려되었어요',
  String body = '',
}) => TrainerNotification.fromJson(<String, Object?>{
  'id': 'noti-verify',
  'title': title,
  'body': body,
  'category': 'verification',
  'read': false,
  'created_at': '2026-10-03T01:00:00Z',
  'time_ago': '방금 전',
  'template': template,
  'args': args,
});

void main() {
  test('verification 종류로 읽는다', () {
    expect(_notice().kind, TrainerNotificationKind.verification);
  });

  group('이동', () {
    test('승인은 대시보드로 간다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(template: 'trainer_verification_approved'),
        ),
        AppRoutes.dashboard,
      );
    });

    test('반려는 MY 로 간다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(template: 'trainer_verification_rejected'),
        ),
        AppRoutes.my,
      );
    });

    test('틀이 없는 알림은 대시보드다 — 배너가 상태를 말한다', () {
      expect(NotificationsPage.targetOf(_notice()), AppRoutes.dashboard);
    });
  });

  group('문장', () {
    test('승인 — 한국어·영어', () {
      final TrainerNotification n = _notice(
        template: 'trainer_verification_approved',
      );
      expect(trainerNotificationText(_ko, n), (
        title: '운영자 승인이 완료되었어요',
        body: '이제 회원 앱 트레이너 찾기에 보이고 상담 요청·회원 연결을 받을 수 있어요.',
      ));
      expect(trainerNotificationText(_en, n), (
        title: 'Your trainer account is approved',
        body:
            'You now appear in Find a trainer and can take consultations '
            'and connect members.',
      ));
    });

    test('사유가 있는 반려는 운영자가 쓴 사유를 그대로 보인다', () {
      final TrainerNotification n = _notice(
        template: 'trainer_verification_rejected',
        args: const <String, Object?>{'has_note': true},
        body: '소속 헬스장을 확인할 수 없어요.',
      );
      expect(trainerNotificationText(_ko, n).body, '소속 헬스장을 확인할 수 없어요.');
      expect(trainerNotificationText(_en, n), (
        title: 'Your trainer account was not approved',
        body: '소속 헬스장을 확인할 수 없어요.',
      ));
    });

    test('사유 없는 반려는 MY 확인을 안내한다', () {
      final TrainerNotification n = _notice(
        template: 'trainer_verification_rejected',
        args: const <String, Object?>{'has_note': false},
        body: 'MY 에서 프로필과 소속 헬스장을 확인해 주세요.',
      );
      expect(trainerNotificationText(_ko, n), (
        title: '운영자 승인이 반려되었어요',
        body: 'MY 에서 프로필과 소속 헬스장을 확인해 주세요.',
      ));
      expect(
        trainerNotificationText(_en, n).body,
        'Check your profile and gym in MY.',
      );
    });
  });
}
