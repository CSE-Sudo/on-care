import 'package:oncare_ui/oncare_ui.dart' show AppTextLimits;

/// 회원이 트레이너를 신고하는 사유 (#3008).
///
/// 트레이너는 가입하고 소속 헬스장을 고르면 바로 활동한다 — 운영자 승인 단계가
/// 없다. 대신 회원이 사칭·부적절한 메시지를 신고하고, 운영자가 트레이너 웹
/// `신고·계정 관리` 에서 보고 계정을 정지한다. [wire] 는 서버 계약값이다.
enum TrainerReportReason {
  impersonation('impersonation'),
  inappropriateMessage('inappropriate_message'),
  other('other');

  const TrainerReportReason(this.wire);

  final String wire;

  /// 기타는 무엇이 문제인지 적어야 운영자가 판단할 수 있다 — 서버도 같은 규칙으로
  /// 빈 메모를 422 로 거절한다.
  bool get needsMemo => this == TrainerReportReason.other;
}

/// 신고 메모 상한. 서버 `TEXT_LINE_MAX` 와 같은 `한 줄` 등급이다.
const int kTrainerReportMemoMax = AppTextLimits.line;

/// 같은 트레이너에 대한 내 신고가 아직 처리 전이다 — 서버 409 `report_already_open`.
///
/// 오류가 아니라 "이미 접수됨" 상태라 화면은 그 사실을 안내한다.
class TrainerReportAlreadyOpen implements Exception {
  const TrainerReportAlreadyOpen();
}

/// 트레이너 신고 접수 (#3008).
abstract class TrainerReportRepository {
  /// [trainerId] 를 [reason] 으로 신고한다. 메모는 앞뒤 공백을 떼고 보낸다.
  ///
  /// 처리 전 신고가 이미 있으면 [TrainerReportAlreadyOpen].
  Future<void> report(
    String trainerId, {
    required TrainerReportReason reason,
    String memo = '',
  });
}
