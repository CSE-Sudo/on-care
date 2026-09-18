import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';

/// 상담 목록 한 쪽의 건수. 서버 기본값과 같다(#980).
const int consultationPageSize = 50;

/// 회원에게 열리는 예약 자리 종류. 헬스장 탭 목록도 상담 폼도 이것만 쓴다(#1849).
const String kConsultationSessionType = '1:1 PT';

/// 상담 폼에 보이는 자리의 하한 — 시작까지 이만큼은 남아 있어야 고를 수 있다.
///
/// 서버 `CONSULT_SLOT_MIN_LEAD_HOURS` 와 같은 값이다. 만료 기준(자리 시작 2시간
/// 전)보다 크게 둬야 트레이너에게 확인할 시간이 남는다 — 같게 두면 경계에서
/// 신청 직후 만료되는 자리를 고를 수 있다(#1873).
const Duration kConsultationSlotMinLead = Duration(hours: 4);

/// 상담 신청 접수·조회. (#327)
abstract class ConsultationRepository {
  /// 접수된 상담 id. 같은 대상에 이미 대기 중이면 [DuplicatePendingConsultation].
  Future<String> create(ConsultationDraft draft);

  /// 내가 낸 상담 **최근 [limit] 건**(최신순). 앱을 다시 열어도 대기 중 신청이 화면에
  /// 남아야 한다 — 목록이 비면 `hasPending` 이 false 라 같은 대상에 다시 눌러 409 를
  /// 받는다(#327).
  ///
  /// 서버가 한 쪽만 준다(#980). 화면이 쓰는 것은 대기 중인 신청뿐이고 그것은 대개 가장
  /// 최근 건이라 첫 쪽으로 충분하다. 그보다 오래된 대기 신청이 남아 있는 드문 경우는
  /// 접수 시 서버가 409 로 알려 주고, 컨트롤러가 그 응답으로 목록을 채운다.
  Future<List<ConsultationRequest>> fetchMine({int limit});

  Future<void> cancel(String consultationId) async {}

  /// 상담을 신청할 수 있는 그 트레이너의 빈 자리. (#1873)
  ///
  /// 헬스장 탭의 예약 가능 시간 목록과 다른 점은 둘이다 — 신청하는 순간 자리가
  /// 잠기므로 **트레이너가 확인할 틈이 남은 자리**만 오고, 이미 잠긴 자리는 빠진다.
  /// 비어 있으면 화면은 신청 버튼을 잠그고 헬스장 전화를 안내한다.
  Future<List<TrainerSlot>> fetchSlots(String trainerId);
}

/// 서버가 409 로 거절한 경우 — 같은 헬스장/트레이너에 대기 중인 신청이 이미 있다.
/// 화면은 이미 `hasPending` 으로 버튼을 막지만, 다른 기기에서 넣었을 수 있어
/// 서버 판정을 최종으로 삼는다.
class DuplicatePendingConsultation implements Exception {
  const DuplicatePendingConsultation();
}

/// 서버가 409 로 거절했는데 **고른 자리를 잡을 수 없어서**인 경우. (#1873)
///
/// 다른 회원이 먼저 그 자리를 골랐거나, 폼을 띄워 둔 사이에 신청 하한을 지났다.
/// [DuplicatePendingConsultation] 과 같은 409 지만 뜻이 반대라 따로 둔다 — 섞으면
/// 자리를 놓친 회원을 "이미 대기 중" 으로 잘못 표시해 다시 신청하는 길을 막는다.
class ConsultationSlotTaken implements Exception {
  const ConsultationSlotTaken();
}
