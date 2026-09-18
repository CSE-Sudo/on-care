/// 건강 목표 변경 기록과 알림(#1832) — 트레이너 웹 쪽.
///
/// 담당 회원이 목표를 바꾸면 알림함에 `회원 건강 목표 변경` 이 오고, 누르면 그 회원
/// 상세로 간다. 회원 신체·목표 창의 칩 아래에는 누가 언제 바꿨는지 한 줄이 남는다.
/// 데모 저장소도 목표 칩이 실제로 바뀐 저장에만 그 기록을 남긴다.
library;

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/pages/notifications_page.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/utils/focus_change_label.dart';

TrainerNotification _notice(Map<String, Object?> overrides) =>
    TrainerNotification.fromJson(<String, Object?>{
      'id': 'n1',
      'title': '회원 건강 목표 변경',
      'body': '지수 회원이 건강 목표를 바꿨어요: 근력 향상 · 재활',
      'category': 'health_goal',
      'read': false,
      'created_at': '2026-09-16T01:30:00Z',
      'time_ago': '방금',
      ...overrides,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('ko');
    await initializeDateFormatting('en');
  });

  group('알림', () {
    test('건강 목표 변경 알림은 그 회원 상세로 간다', () {
      final TrainerNotification notice = _notice(<String, Object?>{
        'subject_id': 'user-jisu',
      });
      expect(notice.kind, TrainerNotificationKind.healthGoal);
      expect(notice.subjectId, 'user-jisu');
      expect(
        NotificationsPage.targetOf(notice),
        AppRoutes.clientDetail('user-jisu'),
      );
    });

    test('회원 id 가 빠진 건강 목표 알림은 고객 목록으로 간다', () {
      final TrainerNotification notice = _notice(<String, Object?>{
        'subject_id': null,
      });
      expect(notice.subjectId, isNull);
      expect(NotificationsPage.targetOf(notice), AppRoutes.clients);
    });

    test('회원 이름 변경 알림도 그 회원 상세로 간다 (#2065)', () {
      final TrainerNotification notice = _notice(<String, Object?>{
        'title': '회원 이름 변경',
        'body': '지수 회원이 이름을 바꿨어요: 이수진',
        'category': 'member_name',
        'subject_id': 'user-jisu',
      });
      expect(notice.kind, TrainerNotificationKind.memberName);
      expect(
        NotificationsPage.targetOf(notice),
        AppRoutes.clientDetail('user-jisu'),
      );
    });

    test('기존 알림 종류의 이동은 그대로다', () {
      expect(
        NotificationsPage.targetOf(
          _notice(<String, Object?>{'category': 'message'}),
        ),
        AppRoutes.clients,
      );
      expect(
        NotificationsPage.targetOf(
          _notice(<String, Object?>{'category': 'brand_new'}),
        ),
        isNull,
      );
    });
  });

  group('마지막 변경 줄', () {
    test('서버가 준 변경자와 시각을 읽는다', () {
      final MemberHealthProfile profile =
          MemberHealthProfile.fromJson(<String, Object?>{
            'member_id': 'user-jisu',
            'member_name': '지수',
            'focus_changed_by': 'member',
            'focus_changed_at': '2026-09-16T01:30:00Z',
          });
      expect(profile.focusChangedBy, MemberHealthProfile.focusChangedByMember);
      expect(
        profile.focusChangedAt,
        DateTime.utc(2026, 9, 16, 1, 30).toLocal(),
      );
    });

    test('누가 언제 바꿨는지 한 줄로 말하고, 바꾼 적이 없으면 그리지 않는다', () {
      final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
      final MemberHealthProfile byMember = MemberHealthProfile(
        memberId: 'user-jisu',
        memberName: '지수',
        focusChangedBy: MemberHealthProfile.focusChangedByMember,
        focusChangedAt: DateTime(2026, 9, 16, 10),
      );

      expect(
        focusLastChangedLabel(ko, byMember, locale: 'ko'),
        '마지막 변경: 회원 · 9월 16일',
      );
      expect(
        focusLastChangedLabel(en, byMember, locale: 'en'),
        'Last changed by Member · Sep 16',
      );
      expect(
        focusLastChangedLabel(
          ko,
          const MemberHealthProfile(memberId: 'user-jisu', memberName: '지수'),
          locale: 'ko',
        ),
        isNull,
      );
    });
  });

  test('데모 저장소는 목표 칩이 바뀐 저장만 트레이너가 바꾼 것으로 남긴다', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seedIfEmpty(db);
    final repository = DriftClientRepository(db);

    final MemberHealthProfile untouched = await repository.updateHealthProfile(
      'seed-client-1',
      <String, Object?>{'weight_kg': 61.5},
    );
    expect(untouched.focusChangedBy, isNull);

    final MemberHealthProfile changed = await repository.updateHealthProfile(
      'seed-client-1',
      <String, Object?>{'conditions': '재활, 자세 교정'},
    );
    expect(changed.focusChangedBy, MemberHealthProfile.focusChangedByTrainer);
    expect(changed.focusChangedAt, isNotNull);

    final MemberHealthProfile reordered = await repository.updateHealthProfile(
      'seed-client-1',
      <String, Object?>{'conditions': '자세 교정, 재활'},
    );
    expect(reordered.focusChangedAt, changed.focusChangedAt);
  });
}
