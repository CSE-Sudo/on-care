import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/notification/data/repositories/dio_notification_repository.dart';
import 'package:oncare/features/notification/data/repositories/mock_notification_repository.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';

/// 데모 알림함 — 트레이너와 이어진 서비스 흐름이 보이는 예시 목록(#1812).
void main() {
  AlertItem byTitle(String title) =>
      demoAlerts.singleWhere((AlertItem a) => a.title == title);

  test('열 건이고 id 가 겹치지 않는다', () {
    expect(demoAlerts, hasLength(10));
    final ids = demoAlerts.map((AlertItem a) => a.id).toSet();
    expect(ids, hasLength(demoAlerts.length));
  });

  test('이전 타깃 문구(혈압·당뇨·검진)가 없다', () {
    for (final AlertItem a in demoAlerts) {
      for (final String word in <String>['혈압', '당뇨', '검진']) {
        expect(
          a.title.contains(word) || a.body.contains(word),
          isFalse,
          reason: '${a.id}: $word',
        );
      }
    }
  });

  test('안 읽은 알림 여섯 건이 위에 모여 있다', () {
    final reads = demoAlerts.map((AlertItem a) => a.read).toList();
    expect(reads.where((bool r) => !r), hasLength(6));
    final int firstRead = reads.indexOf(true);
    expect(reads.sublist(firstRead).every((bool r) => r), isTrue);
  });

  test('예시 알림은 승인한 갈래와 목적지로 이어진다', () {
    final expected = <String, (AlertCategory, AlertTarget)>{
      '새 운동 루틴이 도착했어요': (AlertCategory.reminder, AlertTarget.exercise),
      '내일 PT 일정이 있어요': (AlertCategory.reminder, AlertTarget.schedule),
      '이번 주 리포트가 등록됐어요': (AlertCategory.achievement, AlertTarget.coachChat),
      '저녁 식단을 기록해 주세요': (AlertCategory.reminder, AlertTarget.diet),
      '7일 연속 기록 달성!': (AlertCategory.achievement, AlertTarget.dashboard),
      '이번 주 운동 목표 80% 달성': (AlertCategory.achievement, AlertTarget.exercise),
    };
    expected.forEach((String title, (AlertCategory, AlertTarget) want) {
      final AlertItem a = byTitle(title);
      expect(a.category, want.$1, reason: title);
      expect(a.action?.target, want.$2, reason: title);
    });
  });

  test('점검 공지만 목적지가 없다', () {
    expect(byTitle('서비스 점검 안내').action, isNull);
    expect(
      demoAlerts.where((AlertItem a) => a.action == null).map((a) => a.title),
      <String>['서비스 점검 안내'],
    );
  });

  test('목업 저장소의 미읽음 수가 데모 목록과 같다', () async {
    final MockNotificationRepository repo = MockNotificationRepository();
    expect(await repo.unreadCount(), 6);
    await repo.markAllRead();
    expect(await repo.unreadCount(), 0);
  });

  group('서버 갈래 해석', () {
    test('트레이너 활동이 만든 회원 알림은 리마인더다', () {
      for (final String wire in <String>[
        'coach_chat',
        'routine',
        'member_schedule',
        'consultation_result',
      ]) {
        expect(
          DioNotificationRepository.categoryFromWire(wire),
          AlertCategory.reminder,
          reason: wire,
        );
      }
    });

    test('기존 갈래는 그대로, 모르는 갈래는 시스템이다', () {
      expect(
        DioNotificationRepository.categoryFromWire('reminder'),
        AlertCategory.reminder,
      );
      expect(
        DioNotificationRepository.categoryFromWire('health_check'),
        AlertCategory.healthCheck,
      );
      expect(
        DioNotificationRepository.categoryFromWire('achievement'),
        AlertCategory.achievement,
      );
      expect(
        DioNotificationRepository.categoryFromWire('system'),
        AlertCategory.system,
      );
      expect(
        DioNotificationRepository.categoryFromWire('brand_new'),
        AlertCategory.system,
      );
    });
  });
}
