/// 신고 사유 — 서버 `reason` 과 1:1 이다 (#3008).
enum AdminReportReason {
  /// 소속·신원 사칭.
  impersonation,

  /// 부적절한 메시지.
  inappropriateMessage,

  /// 기타 — 회원이 내용을 적는다.
  other;

  /// 서버 문자열을 읽는다. 모르는 값은 [other] 다 — 내용 칸이 사정을 말한다.
  static AdminReportReason fromWire(Object? value) => switch (value) {
    'impersonation' => impersonation,
    'inappropriate_message' => inappropriateMessage,
    _ => other,
  };
}

/// 신고 처리 상태.
enum AdminReportStatus {
  /// 처리 전.
  open,

  /// 조치함 — 계정 정지 등 조치를 마쳤다.
  resolved,

  /// 넘김 — 조치가 필요 없었다.
  dismissed;

  /// 서버 문자열을 읽는다. 모르는 값은 [open] — 처리할 쪽으로 읽는다.
  static AdminReportStatus fromWire(Object? value) => switch (value) {
    'resolved' => resolved,
    'dismissed' => dismissed,
    _ => open,
  };
}

/// 운영 화면의 신고 한 건 — `GET /admin/trainer-reports` 의 한 줄 (#3008).
///
/// 신고한 회원은 싣지 않는다 — 처리에는 대상과 사유면 충분하다.
class AdminTrainerReport {
  /// Creates a report row.
  const AdminTrainerReport({
    required this.id,
    required this.trainerId,
    required this.trainerName,
    required this.trainerEmail,
    required this.trainerIsActive,
    required this.reason,
    required this.memo,
    required this.status,
    this.createdAt,
    this.resolvedAt,
  });

  /// 신고 id — 처리 경로에 쓴다.
  final String id;

  /// 신고 대상 트레이너 id — 정지·해제 경로에 쓴다.
  final String trainerId;

  /// 대상 트레이너 이름.
  final String trainerName;

  /// 대상 트레이너 이메일.
  final String trainerEmail;

  /// 대상 계정이 살아 있는가.
  final bool trainerIsActive;

  /// 사유.
  final AdminReportReason reason;

  /// 회원이 적은 내용. 비어 올 수 있다.
  final String memo;

  /// 처리 상태.
  final AdminReportStatus status;

  /// 신고 시각.
  final DateTime? createdAt;

  /// 처리 시각.
  final DateTime? resolvedAt;

  /// 아직 처리하지 않았는가.
  bool get isOpen => status == AdminReportStatus.open;
}

/// 신고 목록의 상태 칩 — 서버 `status` 쿼리와 1:1 이다.
enum AdminReportFilter {
  /// 처리 전(기본) — 운영자가 볼 것.
  open,

  /// 처리됨(조치함·넘김).
  closed,

  /// 전체.
  all;

  /// `GET /admin/trainer-reports?status=` 값.
  String get wire => name;
}

/// 신고를 닫는 방식 — `POST /admin/trainer-reports/{id}/close` 의 `outcome`.
enum AdminReportOutcome {
  /// 조치함.
  resolved,

  /// 넘김.
  dismissed;

  /// 서버 값.
  String get wire => name;
}
