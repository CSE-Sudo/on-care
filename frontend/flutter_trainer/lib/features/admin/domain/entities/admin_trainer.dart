import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// 운영 화면의 트레이너 한 명 — `GET /admin/trainers` 의 한 줄 (#3008).
///
/// 운영자가 승인·반려를 판단하는 데 쓰는 값만 담는다: 누구인지(이름·이메일),
/// 무엇을 한다고 했는지(전문 분야·경력·자격증), 어디 소속인지(헬스장), 지금 어떤
/// 상태인지(승인 상태·계정 정지).
class AdminTrainer {
  /// Creates a review row.
  const AdminTrainer({
    required this.trainerId,
    required this.name,
    required this.email,
    required this.specialty,
    required this.careerYears,
    required this.certifications,
    required this.gymName,
    required this.gymAddress,
    required this.gymIsFitness,
    required this.hasGym,
    required this.status,
    required this.note,
    required this.isActive,
    this.decidedAt,
    this.createdAt,
  });

  /// 트레이너 계정 id — 승인·반려·정지 경로에 쓴다.
  final String trainerId;

  /// 이름. 비어 올 수 있다(화면이 대체 문구를 붙인다).
  final String name;

  /// 로그인 이메일.
  final String email;

  /// 전문 분야 문구.
  final String specialty;

  /// 경력 연수.
  final int careerYears;

  /// 자격증 목록.
  final List<String> certifications;

  /// 소속 장소 이름.
  final String gymName;

  /// 소속 장소 주소.
  final String gymAddress;

  /// 소속 장소가 헬스장인가. 아니면 승인해도 회원 앱에 나오지 않는다.
  final bool gymIsFitness;

  /// 소속 장소가 있는가.
  final bool hasGym;

  /// 승인 대기·승인·반려.
  final TrainerVerificationStatus status;

  /// 반려 사유. 승인·대기면 빈 문자열이다.
  final String note;

  /// 계정이 살아 있는가. 운영자가 정지하면 `false` 다 (#3009).
  final bool isActive;

  /// 승인·반려 시각.
  final DateTime? decidedAt;

  /// 가입 시각.
  final DateTime? createdAt;

  /// 승인 버튼을 보일까 — 승인되지 않은 살아 있는 계정.
  bool get canApprove =>
      isActive && status != TrainerVerificationStatus.approved;

  /// 반려 버튼을 보일까 — 반려되지 않은 살아 있는 계정.
  bool get canReject =>
      isActive && status != TrainerVerificationStatus.rejected;
}

/// 운영 화면의 상태 칩 — 서버 `status` 쿼리와 1:1 이다.
enum AdminTrainerFilter {
  /// 승인 대기(기본) — 운영자가 처리할 것.
  pending,

  /// 승인됨.
  approved,

  /// 반려됨.
  rejected,

  /// 전체.
  all;

  /// `GET /admin/trainers?status=` 값.
  String get wire => name;
}

/// 계정 정지·해제 결과 — `AdminUserStatusOut` (#3009).
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
