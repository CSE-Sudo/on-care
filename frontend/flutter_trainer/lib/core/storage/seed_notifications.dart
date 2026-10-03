import 'dart:convert';

import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 데모 알림함에 든 알림(JSON 배열)을 담는 키. (#2628)
///
/// 실 서버의 `/trainer/notifications` 응답과 같은 모양의 행을 담는다 — 화면은
/// 같은 `TrainerNotification.fromJson` 으로 읽는다. 읽음 처리도 이 값을 고쳐
/// 쓴다.
const String demoNotificationsKey = 'trainer_demo_notifications';

/// 데모 알림함의 과거 알림을 심는다. 이미 있으면 두지 않는다 — 트레이너가
/// 읽음 처리한 기록이 날이 바뀌어도 남는다(#2628).
///
/// 알림은 트레이너가 받는 종류를 골고루 담는다 — 알림 화면의 종류 메뉴(#2628)가
/// 어느 칸도 비지 않게. 문장은 틀 코드·인자로 적어
/// 두어, 화면이 지금 언어로 조립한다(#2302). 회원 이름은 이미 심어 둔 회원 행에서
/// 읽는다.
Future<void> seedDemoNotifications(
  AppDatabase db, {
  required DateTime now,
}) async {
  if (await db.readValue(demoNotificationsKey) != null) return;
  final Map<String, String> names = <String, String>{
    for (final TrainerClientRow c in await db.select(db.trainerClients).get())
      c.id: c.name,
  };
  String? name(int id) => names['seed-client-$id'];

  final DateTime tomorrow = DateTime(now.year, now.month, now.day + 1, 19);

  Map<String, Object?> row({
    required String id,
    required Duration ago,
    required String category,
    required String template,
    required Map<String, Object?> args,
    required int client,
    required String title,
    String body = '',
    bool read = false,
    String? targetDate,
  }) => <String, Object?>{
    'id': id,
    'title': title,
    'body': body,
    'category': category,
    'read': read,
    // [now] 은 서울 벽시계다 — 기기 시간대와 무관하게 같은 순간이 되도록
    // 서울 오프셋을 붙여 적는다.
    'created_at': '${now.subtract(ago).toIso8601String()}+09:00',
    'subject_id': 'seed-client-$client',
    'template': template,
    'args': <String, Object?>{'member_name': name(client), ...args},
    'target_date': ?targetDate,
  };

  final DateTime thisMonday = mondayOf(DateTime(now.year, now.month, now.day));

  final List<Map<String, Object?>> rows = <Map<String, Object?>>[
    // 회원이 이번 주 피드백을 냈다(#3026) — 데모 김민수(1)의 이번 주 답(통증 있음)과
    // 같은 값이다(`seed_data.dart` 의 `_demoFeedback`). 누르면 메모 창 `피드백`
    // 탭이 바로 열린다. 아픈 곳 글은 알림에 싣지 않는다.
    row(
      id: 'demo-noti-7',
      ago: const Duration(minutes: 20),
      category: 'weekly_feedback',
      template: 'trainer_member_weekly_feedback',
      args: const <String, Object?>{
        'condition': 'ok',
        'intensity': 'too_hard',
        'pain': true,
        'revised': false,
      },
      client: 1,
      title: '회원이 통증을 알렸어요',
      body: '컨디션 보통이었어요 · 운동 강도 너무 힘들었어요 · 통증 있음',
      targetDate: wireDate(thisMonday),
    ),
    // 회원이 건강상태·주의사항을 고쳤다(#2619) — 누르면 신체·목표 창의 `건강
    // 목표` 탭이 바로 열린다.
    row(
      id: 'demo-noti-1',
      ago: const Duration(minutes: 40),
      category: 'health_goal',
      template: 'trainer_health_notes',
      args: <String, Object?>{'focus': <String>[], 'with_focus': false},
      client: 2,
      title: '회원 주의사항 변경',
    ),
    row(
      id: 'demo-noti-2',
      ago: const Duration(hours: 2),
      category: 'message',
      template: 'trainer_member_message',
      args: const <String, Object?>{},
      client: 1,
      title: '새 메시지',
      body: '오늘 PT 끝나고 스트레칭 루틴 한 번 더 봐 주실 수 있을까요?',
    ),
    row(
      id: 'demo-noti-3',
      ago: const Duration(hours: 5),
      category: 'reservation',
      template: 'trainer_reservation_booked',
      args: <String, Object?>{
        'starts_at': '${wireDate(tomorrow)}T19:00:00+09:00',
      },
      client: 4,
      title: '새 예약',
      targetDate: wireDate(tomorrow),
    ),
    row(
      id: 'demo-noti-4',
      ago: const Duration(days: 1, hours: 3),
      category: 'health_goal',
      template: 'trainer_health_goal',
      args: const <String, Object?>{
        'focus': <String>['근력 향상', '체력 강화'],
      },
      client: 3,
      title: '회원 건강 목표 변경',
      read: true,
    ),
    row(
      id: 'demo-noti-6',
      ago: const Duration(days: 2),
      category: 'consultation',
      template: 'trainer_consult_requested',
      args: <String, Object?>{'preferred_date': wireDate(tomorrow)},
      client: 6,
      title: '새 상담 요청이 도착했어요',
      read: true,
    ),
    row(
      id: 'demo-noti-5',
      ago: const Duration(days: 3),
      category: 'invite_accepted',
      template: 'trainer_invite_accepted',
      args: const <String, Object?>{},
      client: 5,
      title: '담당 요청 수락',
      read: true,
    ),
  ];
  await db.putValue(demoNotificationsKey, jsonEncode(rows));
}
