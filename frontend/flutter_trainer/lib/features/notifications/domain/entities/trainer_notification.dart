/// 트레이너가 받은 알림 한 건. `GET /trainer/notifications`. (#503)
library;

/// 알림 종류. 서버 `category` 값과 1:1이고, 어디로 이동할지를 정한다.
///
/// 회원 알림의 category 집합(reminder|health_check|achievement|system)과 다르다 —
/// 같은 테이블을 쓰지만 읽는 화면과 갈 곳이 다르다.
enum TrainerNotificationKind {
  message,
  consultation,
  reservation,

  /// 담당 회원이 건강 목표를 바꿨다 — 그 회원 상세로 간다(#1832).
  healthGoal,

  /// 담당 회원이 이름을 바꿨다 — 그 회원 상세로 간다(#2065). 이미 받은 알림은
  /// 옛 이름으로 남아, 이 알림이 옛 이름과 목록의 새 이름을 잇는다.
  memberName,
  other,
}

TrainerNotificationKind _kindFrom(String? raw) => switch (raw) {
  'message' => TrainerNotificationKind.message,
  'consultation' => TrainerNotificationKind.consultation,
  'reservation' => TrainerNotificationKind.reservation,
  'health_goal' => TrainerNotificationKind.healthGoal,
  'member_name' => TrainerNotificationKind.memberName,
  // 서버가 새 종류를 추가했는데 앱이 모르는 경우. 목록에서 빼지 않고 이동만
  // 하지 않는다 — 안 보이는 알림보다 갈 곳 없는 알림이 낫다.
  _ => TrainerNotificationKind.other,
};

class TrainerNotification {
  const TrainerNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.read,
    required this.createdAt,
    required this.timeAgo,
    this.subjectId,
  });

  final String id;
  final String title;
  final String body;
  final TrainerNotificationKind kind;
  final bool read;
  final DateTime createdAt;

  /// 서버가 만든 상대 시각 문구("3분 전"). 회원 알림함과 같은 규칙을 쓰도록
  /// 서버 판단을 그대로 받는다.
  final String timeAgo;

  /// 알림이 가리키는 회원 id. 종류만으로 갈 곳이 정해지지 않는 알림(건강 목표
  /// 변경)에만 있다(#1832).
  final String? subjectId;

  factory TrainerNotification.fromJson(Map<String, Object?> json) =>
      TrainerNotification(
        id: json['id']! as String,
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        kind: _kindFrom(json['category'] as String?),
        read: (json['read'] as bool?) ?? false,
        createdAt: DateTime.parse(json['created_at']! as String).toLocal(),
        timeAgo: (json['time_ago'] as String?) ?? '',
        subjectId: switch (json['subject_id']) {
          final String id when id.isNotEmpty => id,
          _ => null,
        },
      );
}
