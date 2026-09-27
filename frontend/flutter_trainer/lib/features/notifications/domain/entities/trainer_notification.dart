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

  /// 담당 회원이 탈퇴했거나 담당 연결을 끊었다(#2174). 회원이 목록에서 이미
  /// 빠져 갈 곳이 없다 — 알림함에서 확인만 한다.
  memberLeft,

  /// 회원이 트레이너의 담당 요청을 수락했다 — 새 담당 회원 상세로 간다(#2292).
  /// 전에는 상담 종류로 남아 스케줄로 갔다.
  inviteAccepted,

  /// 회원이 담당 요청을 거절했다 — 담당이 아니라 상세가 없어 고객 목록으로
  /// 간다(#2292).
  inviteRejected,
  other,
}

TrainerNotificationKind _kindFrom(String? raw) => switch (raw) {
  'message' => TrainerNotificationKind.message,
  'consultation' => TrainerNotificationKind.consultation,
  'reservation' => TrainerNotificationKind.reservation,
  'health_goal' => TrainerNotificationKind.healthGoal,
  'member_name' => TrainerNotificationKind.memberName,
  'member_left' => TrainerNotificationKind.memberLeft,
  'invite_accepted' => TrainerNotificationKind.inviteAccepted,
  'invite_rejected' => TrainerNotificationKind.inviteRejected,
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
    this.targetDate,
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
  /// 변경)에만 있다(#1832). 메시지 알림은 보낸 회원이다(#2291) — 그 전에 만든
  /// 메시지 알림에는 없다. 예약·상담·담당 요청 결과 알림은 그 회원이다(#2292).
  final String? subjectId;

  /// 알림이 가리키는 날짜(`YYYY-MM-DD`). 예약 알림이 스케줄을 그 날짜로 여는 데
  /// 쓴다(#2292). 날짜가 기록되기 전의 옛 알림이나 형식이 맞지 않는 값이면 없다
  /// — 잘못된 날짜로 스케줄을 여는 것보다 오늘 스케줄로 가는 편이 낫다.
  final String? targetDate;

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
        targetDate: _ymdOrNull(json['target_date']),
      );
}

final RegExp _ymdPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// 서버 날짜가 실제 달력 날짜(`YYYY-MM-DD`)일 때만 그대로 돌려준다.
String? _ymdOrNull(Object? raw) {
  if (raw is! String || !_ymdPattern.hasMatch(raw)) return null;
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  // `2026-02-31` 처럼 넘치는 날짜는 DateTime 이 다음 달로 굴려 받아 준다.
  // 굴린 결과가 원문과 다르면 없는 날짜다.
  final String roundTrip =
      '${parsed.year.toString().padLeft(4, '0')}-'
      '${parsed.month.toString().padLeft(2, '0')}-'
      '${parsed.day.toString().padLeft(2, '0')}';
  return roundTrip == raw ? raw : null;
}
