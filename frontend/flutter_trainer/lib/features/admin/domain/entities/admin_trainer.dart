/// 운영 화면의 트레이너 한 명 — `GET /admin/trainers` 의 한 줄 (#3008).
///
/// 승인 절차는 없다. 운영자가 신고를 보고 계정을 정지·해제할 때 필요한 값만 담는다:
/// 누구인지(이름·이메일), 어디 소속이라고 했는지(헬스장), 지금 상태(정지 여부·처리 전
/// 신고 수).
class AdminTrainer {
  /// Creates a trainer row.
  const AdminTrainer({
    required this.trainerId,
    required this.name,
    required this.email,
    required this.gymName,
    required this.gymAddress,
    required this.isActive,
    required this.openReports,
    this.createdAt,
  });

  /// 트레이너 계정 id — 정지·해제 경로에 쓴다.
  final String trainerId;

  /// 이름. 비어 올 수 있다(화면이 대체 문구를 붙인다).
  final String name;

  /// 로그인 이메일.
  final String email;

  /// 트레이너가 고른 소속 이름. 없으면 빈 문자열이다.
  final String gymName;

  /// 소속 주소.
  final String gymAddress;

  /// 계정이 살아 있는가. 운영자가 정지하면 `false` 다.
  final bool isActive;

  /// 처리 전 신고 수.
  final int openReports;

  /// 가입 시각.
  final DateTime? createdAt;

  /// 소속이 있는가.
  bool get hasGym => gymName.isNotEmpty;
}

/// 트레이너 목록의 상태 칩 — 서버 `state` 쿼리와 1:1 이다.
enum AdminTrainerState {
  /// 전체(기본).
  all,

  /// 이용 중.
  active,

  /// 정지됨.
  suspended;

  /// `GET /admin/trainers?state=` 값.
  String get wire => name;
}

/// 계정 정지·해제 결과 — `AdminUserStatusOut`.
class AdminUserStatus {
  /// Creates a result.
  const AdminUserStatus({
    required this.userId,
    required this.isActive,
    this.releasedClients = 0,
  });

  /// 대상 계정 id.
  final String userId;

  /// 처리 뒤 계정이 살아 있는가.
  final bool isActive;

  /// 이번 정지로 해제한 담당 회원 수.
  final int releasedClients;
}
