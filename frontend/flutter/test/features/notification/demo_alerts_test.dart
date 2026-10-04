import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/demo/demo_alert_keys.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';
import 'package:oncare/features/notification/data/repositories/dio_notification_repository.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';

import '../../helpers/demo_notifications.dart';

/// 데모 알림함 — 트레이너와 이어진 서비스 흐름이 보이는 예시 목록(#1812).
///
/// 데모 알림함은 drift 시드를 로컬 인터셉터가 `GET /notifications` 로 내준 것이다
/// (#2660). 여기서는 앱이 실제로 받는 모양(`DioNotificationRepository` 로 읽은 것)을
/// 본다.
void main() {
  late List<AlertItem> demoAlerts;

  setUpAll(() async {
    demoAlerts = await fetchDemoAlerts();
  });

  AlertItem byTitle(String title) =>
      demoAlerts.singleWhere((AlertItem a) => a.title == title);

  test('일곱 건이고 id 가 겹치지 않는다', () {
    expect(demoAlerts, hasLength(7));
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

  test('안 읽은 알림 다섯 건이 위에 모여 있다', () {
    final reads = demoAlerts.map((AlertItem a) => a.read).toList();
    expect(reads.where((bool r) => !r), hasLength(kDemoUnreadNotifications));
    final int firstRead = reads.indexOf(true);
    expect(reads.sublist(firstRead).every((bool r) => r), isTrue);
  });

  // 갈래(아이콘)와 목적지는 예전 데모 목록 그대로다 — 데모 화면이 기준이다(#2660).
  // 목적지는 서버 갈래별 표와 다를 수 있다(서버를 맞추는 일은 #2690).
  test('예시 알림은 예전 데모와 같은 갈래와 목적지로 이어진다', () {
    final expected = <String, (AlertCategory, AlertTarget)>{
      '새 개인운동이 왔어요': (AlertCategory.routine, AlertTarget.exercise),
      // 서버 시드와 같은 갈래다(#2084·#2085).
      '주간 리포트가 도착했어요': (AlertCategory.coachReport, AlertTarget.coachChat),
      '12회차 PT를 마쳤어요': (AlertCategory.ptDone, AlertTarget.exercise),
      '트레이너 피드백 도착': (AlertCategory.coachChat, AlertTarget.coachChat),
      '이번 주 운동 목표까지 조금 남았어요': (AlertCategory.reminder, AlertTarget.exercise),
      '식단 기록을 꾸준히 이어가고 있어요': (AlertCategory.achievement, AlertTarget.dashboard),
    };
    expected.forEach((String title, (AlertCategory, AlertTarget) want) {
      final AlertItem a = byTitle(title);
      expect(a.category, want.$1, reason: title);
      expect(a.action?.target, want.$2, reason: title);
    });
  });

  // 실서버에는 식단 기록·나트륨 알림을 만드는 코드가 없다(#2854). 데모에서만
  // 보이면 실서비스로 옮긴 회원에게 기능이 사라진 것으로 보인다.
  test('실서버가 만들지 않는 식단 알림이 없다', () {
    for (final AlertItem a in demoAlerts) {
      for (final String word in <String>['나트륨', '저녁 식단']) {
        expect('${a.title} ${a.body}', isNot(contains(word)), reason: a.id);
      }
      expect(a.action?.target, isNot(AlertTarget.diet), reason: a.id);
    }
    for (final String id in kRetiredDemoAlertSeedIds) {
      expect(kDemoAlertKeyBySeedId, isNot(contains(id)));
      expect(demoAlerts.map((AlertItem a) => a.id), isNot(contains(id)));
    }
  });

  test('오늘 이미 시드된 설치에 남은 식단 알림도 걷어 낸다', () async {
    // 날짜가 바뀌기 전에는 시드를 다시 깔지 않는다. 그 사이에도 뺀 알림이 남으면
    // 안 된다.
    final AppDatabase db = await seededDemoDatabase();
    addTearDown(db.close);
    await db
        .into(db.notificationItems)
        .insert(
          NotificationItemsCompanion.insert(
            id: 'seed-noti-1',
            createdAt: DateTime(2026, 9, 15, 18),
            title: '나트륨 섭취 주의',
            body: '',
            category: 'reminder',
          ),
        );

    await seedIfEmpty(db);

    final rows = await db.select(db.notificationItems).get();
    expect(
      rows.map((NotificationRow r) => r.id),
      isNot(contains('seed-noti-1')),
    );
  });

  test('점검 공지만 목적지가 없다', () {
    expect(byTitle('서비스 점검 안내').action, isNull);
    expect(
      demoAlerts.where((AlertItem a) => a.action == null).map((a) => a.title),
      <String>['서비스 점검 안내'],
    );
  });

  // 언제 열어도 같은 시각으로 보인다 — 같은 날 안에서 흐르지 않는다(#2660).
  test('시각은 예전 데모 목록과 같다', () {
    expect(demoAlerts.map((AlertItem a) => a.timeAgo), <String>[
      '30분 전',
      '45분 전',
      '1시간 전',
      '2시간 전',
      '3시간 전',
      '어제',
      '어제',
    ]);
  });

  // 인터셉터가 쓰는 표(시각·읽음)와 시드가 넣는 행이 갈라지면 순서와 시각이, 또는
  // 로그인 뒤 읽음 상태가 서로 다른 말을 한다.
  test('시드 행의 간격·읽음이 데모 표와 같다', () async {
    final AppDatabase db = await seededDemoDatabase();
    addTearDown(db.close);
    final rows = await db.select(db.notificationItems).get();
    final byId = <String, NotificationRow>{for (final r in rows) r.id: r};

    expect(byId.keys.toSet(), kDemoAlertKeyBySeedId.keys.toSet());
    expect(kDemoAlertAgeBySeedId.keys.toSet(), byId.keys.toSet());
    final DateTime newest = byId['seed-noti-5']!.createdAt;
    final Duration base = kDemoAlertAgeBySeedId['seed-noti-5']!;
    kDemoAlertAgeBySeedId.forEach((String id, Duration age) {
      expect(newest.difference(byId[id]!.createdAt), age - base, reason: id);
      expect(byId[id]!.read, kDemoAlertReadSeedIds.contains(id), reason: id);
    });
  });

  test('모든 알림이 다음 쪽 커서(created_at)를 갖는다', () {
    for (final AlertItem a in demoAlerts) {
      expect(a.createdAt, isNotEmpty, reason: a.id);
    }
  });

  // 알림은 식단·운동·채팅 목업을 따라 적은 문장이다. 픽스처가 바뀌면 조용히
  // 틀린 말을 하게 되므로, 문구가 기대는 사실을 픽스처에서 직접 확인한다.
  group('데모 픽스처와 같은 사실', () {
    final DemoFixture fixture = DemoFixture.load();
    final List<FixtureDay> days = fixture.daysFor(DateTime(2026, 9, 15, 19));
    final FixtureDay today = days.last;

    test('루틴 알림은 픽스처에 있는 걷기 위주 개인운동을 말한다', () {
      expect(byTitle('새 개인운동이 왔어요').body, contains('걷기'));
      expect(
        fixture.routines.any((FixtureRoutine r) => r.name.contains('걷기')),
        isTrue,
      );
    });

    test('PT 완료 알림은 오늘 PT 날과 같다', () {
      expect(today.isPt, isTrue);
      expect(byTitle('12회차 PT를 마쳤어요').body, contains('오늘'));
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
        // 끝난 PT 의 기록은 앞으로의 일정과 다른 갈래다(#3027).
        'pt_done': AlertCategory.ptDone,
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
