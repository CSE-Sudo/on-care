import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';

/// 피드백이 나온 자리. (#2615)
enum ClientFeedbackKind {
  /// 완료 PT 세션 피드백(스케줄 일정의 `트레이너 메모`).
  ptSession,

  /// 회원에게 보낸 주간 리포트.
  report,

  /// 회원이 쓴 주간 피드백(컨디션·강도·통증·한 줄).
  weekly;

  static ClientFeedbackKind? fromWire(String? value) => switch (value) {
    'pt_session' => ClientFeedbackKind.ptSession,
    'report' => ClientFeedbackKind.report,
    'weekly' => ClientFeedbackKind.weekly,
    _ => null,
  };

  /// 누가 누구에게 쓴 글인가. 회원 주간 피드백만 회원이 쓴다.
  bool get fromMember => this == ClientFeedbackKind.weekly;
}

/// 회원 한 명과 주고받은 피드백 한 건 — 메모 창 `피드백` 탭의 한 줄. (#2615)
///
/// 읽기 전용이다. 고치는 곳은 원래 자리 하나뿐이라, 그 자리로 가는 값
/// ([scheduleId]·[weekStart])만 들고 있다.
class ClientFeedback {
  const ClientFeedback({
    required this.id,
    required this.kind,
    required this.date,
    this.body = '',
    this.scheduleId,
    this.weekStart,
    this.weekly,
  });

  final String id;
  final ClientFeedbackKind kind;

  /// 붙는 날 — PT 는 수업 날, 리포트·주간 피드백은 그 주 월요일.
  final DateTime date;

  /// 피드백 글. 주간 피드백은 한 줄 피드백이라 비어 있을 수 있다.
  final String body;

  /// PT 세션 피드백의 일정 id.
  final String? scheduleId;

  /// 리포트·주간 피드백의 주(월요일).
  final DateTime? weekStart;

  /// 주간 피드백의 세 문항. 컨디션·강도를 읽을 수 없으면 null 이다.
  final MemberWeeklyFeedback? weekly;

  /// 서버 응답 한 건. 모르는 출처나 읽을 수 없는 날짜는 null — 목록 전체를
  /// 깨뜨리지 않고 그 한 건만 버린다.
  static ClientFeedback? fromJson(Map<String, Object?> json) {
    final ClientFeedbackKind? kind = ClientFeedbackKind.fromWire(
      json['kind'] as String?,
    );
    final DateTime? date = DateTime.tryParse(json['date'] as String? ?? '');
    if (kind == null || date == null) return null;
    final DateTime? week = DateTime.tryParse(
      json['week_start'] as String? ?? '',
    );
    final String body = json['body'] as String? ?? '';
    return ClientFeedback(
      id: json['id'] as String? ?? '${kind.name}:${json['date']}',
      kind: kind,
      date: date,
      body: body,
      scheduleId: json['schedule_id'] as String?,
      weekStart: week,
      weekly: kind == ClientFeedbackKind.weekly && week != null
          ? MemberWeeklyFeedback.fromWire(
              weekStart: week,
              condition: json['condition'] as String?,
              intensity: json['intensity'] as String?,
              painArea: json['pain_area'] as String? ?? '',
              painOn: json['pain_on'] as String? ?? '',
              note: body,
            )
          : null,
    );
  }
}
