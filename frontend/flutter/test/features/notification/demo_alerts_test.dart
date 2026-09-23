import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:oncare/features/notification/data/repositories/dio_notification_repository.dart';
import 'package:oncare/features/notification/data/repositories/mock_notification_repository.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';

/// 데모 알림함 — 트레이너와 이어진 서비스 흐름이 보이는 예시 목록(#1812).
void main() {
  AlertItem byTitle(String title) =>
      demoAlerts.singleWhere((AlertItem a) => a.title == title);

  test('아홉 건이고 id 가 겹치지 않는다', () {
    expect(demoAlerts, hasLength(9));
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

  test('안 읽은 알림 일곱 건이 위에 모여 있다', () {
    final reads = demoAlerts.map((AlertItem a) => a.read).toList();
    expect(reads.where((bool r) => !r), hasLength(7));
    final int firstRead = reads.indexOf(true);
    expect(reads.sublist(firstRead).every((bool r) => r), isTrue);
  });

  test('예시 알림은 승인한 갈래와 목적지로 이어진다', () {
    final expected = <String, (AlertCategory, AlertTarget)>{
      '새 운동 루틴이 도착했어요': (AlertCategory.routine, AlertTarget.exercise),
      // 서버 시드와 같은 갈래다(#2084·#2085).
      '이번 주 리포트가 등록됐어요': (AlertCategory.coachReport, AlertTarget.coachChat),
      '트레이너 피드백 도착': (AlertCategory.coachChat, AlertTarget.coachChat),
      '저녁 식단을 기록해 주세요': (AlertCategory.reminder, AlertTarget.diet),
      '식단 기록을 꾸준히 이어가고 있어요': (AlertCategory.achievement, AlertTarget.dashboard),
      '이번 주 운동 목표까지 조금 남았어요': (AlertCategory.reminder, AlertTarget.exercise),
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
    expect(await repo.unreadCount(), 7);
    await repo.markAllRead();
    expect(await repo.unreadCount(), 0);
  });

  // 알림은 식단·운동·채팅 목업을 따라 적은 문장이다. 픽스처가 바뀌면 조용히
  // 틀린 말을 하게 되므로, 문구가 기대는 사실을 픽스처에서 직접 확인한다.
  group('데모 픽스처와 같은 사실', () {
    final DemoFixture fixture = DemoFixture.load();
    final List<FixtureDay> days = fixture.daysFor(DateTime(2026, 9, 15, 19));
    final FixtureDay today = days.last;

    test('나트륨 알림의 수치가 오늘 식단 합계와 같다', () {
      final String total = NumberFormat('#,###').format(today.sodiumMg);
      expect(byTitle('나트륨 섭취 주의').body, contains('${total}mg'));
    });

    test('저녁 기록 알림은 저녁이 빈 오늘의 알림이다', () {
      expect(
        today.meals.map((FixtureMeal m) => m.mealType),
        isNot(contains('dinner')),
      );
      final AlertItem dinner = byTitle('저녁 식단을 기록해 주세요');
      expect(dinner.read, isFalse);
      expect(dinner.age, lessThan(const Duration(hours: 1)));
    });

    test('루틴 알림은 픽스처에 있는 걷기 루틴을 말한다', () {
      expect(byTitle('새 운동 루틴이 도착했어요').body, contains('걷기'));
      expect(
        fixture.routines.any((FixtureRoutine r) => r.name.contains('걷기')),
        isTrue,
      );
    });

    test('PT 완료 알림은 오늘 PT 날과 같다', () {
      expect(today.isPt, isTrue);
      expect(byTitle('PT 수업 완료').body, contains('오늘'));
    });

    test('연속 기록 알림은 요일과 상관없이 보름 넘게 끊기지 않은 기록과 같다', () {
      // 픽스처의 빈 날은 요일이 정해져 있다 — 일주일 치 오늘을 모두 돌려 본다.
      //
      // "한 달" 이 아닌 이유: 보호권(#1788)을 시연하려면 최근 30일 안에 빈 날이
      // 하나 있어야 하고(#2075), 그러면 식단이 한 달을 넘게 이어질 수 없다.
      for (int offset = 0; offset < 7; offset++) {
        final List<FixtureDay> week = fixture.daysFor(
          DateTime(2026, 9, 14 + offset, 19),
        );
        int run = 0;
        for (final FixtureDay d in week.reversed) {
          if (d.meals.isEmpty) break;
          run++;
        }
        expect(run, greaterThan(15), reason: week.last.date);
      }
      final String body = byTitle('식단 기록을 꾸준히 이어가고 있어요').body;
      expect(body, contains('보름 넘게'));
      expect(body, isNot(matches(RegExp(r'\d'))));
    });

    test('요일에 따라 달라지는 값은 문구에 없다', () {
      for (final AlertItem a in demoAlerts) {
        for (final String word in <String>['주차', '내일 PT', '13회차', '80%']) {
          expect('${a.title} ${a.body}', isNot(contains(word)), reason: a.id);
        }
      }
    });
  });

  group('서버 갈래 해석', () {
    // 서버 갈래를 접지 않고 갈래마다 아이콘을 고른다(#2084).
    test('서버 갈래마다 앱 갈래가 따로 있다', () {
      const Map<String, AlertCategory> expected = <String, AlertCategory>{
        'reminder': AlertCategory.reminder,
        'coach_chat': AlertCategory.coachChat,
        // 주간 리포트는 트레이너 메시지와 다른 갈래다(#2085).
        'coach_report': AlertCategory.coachReport,
        'routine': AlertCategory.routine,
        'member_schedule': AlertCategory.schedule,
        'coach_invite': AlertCategory.trainerLink,
        'consultation_result': AlertCategory.trainerLink,
        // 상담 요청의 승인·거절·만료(#2067).
        'consult_decision': AlertCategory.consultDecision,
        // 예전에는 빠져 있어 시스템 공지로 떨어졌다(#1832).
        'health_goals': AlertCategory.healthGoals,
        'benefits': AlertCategory.benefits,
        'points_shop': AlertCategory.challenge,
        'achievement': AlertCategory.achievement,
        'system': AlertCategory.system,
      };
      expected.forEach((String wire, AlertCategory want) {
        expect(
          DioNotificationRepository.categoryFromWire(wire),
          want,
          reason: wire,
        );
      });
    });

    test('보내는 곳이 없는 health_check 는 리마인더로 그린다', () {
      expect(
        DioNotificationRepository.categoryFromWire('health_check'),
        AlertCategory.reminder,
      );
    });

    test('모르는 갈래는 시스템이다', () {
      expect(
        DioNotificationRepository.categoryFromWire('brand_new'),
        AlertCategory.system,
      );
    });
  });
}
