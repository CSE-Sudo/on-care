import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';

/// 상담 요청의 상태.
///
/// [ConsultationStatus.expired] 는 트레이너가 시간 안에 확인하지 않아 잡고 있던
/// 자리가 풀린 경우다(#1873). 트레이너의 판단인 [ConsultationStatus.rejected] 와
/// 구분한다 — 회원에게 보여 줄 문구가 다르고, 다시 신청하면 되는 상황이다.
enum ConsultationStatus { pending, accepted, rejected, cancelled, expired }

class ConsultationRequest {
  const ConsultationRequest({
    required this.id,
    required this.trainerId,
    required this.trainerName,
    required this.trainerRole,
    required this.exerciseGoal,
    required this.healthPurposeType,
    required this.healthPurposeDetail,
    required this.preferredDate,
    required this.preferredTimeSlot,
    required this.message,
    required this.status,
    required this.createdAt,
    this.decisionNote,
    this.decidedAt,
    this.trainerGymName,
    this.slotStartsAt,
    this.slotDurationMinutes,
  });

  /// 서버가 접수하며 준 id 로 갈아끼울 때 쓴다 — 화면이 만든 임시 id 는 트레이너
  /// 앱과 이어지지 않는다(#327).
  ConsultationRequest copyWith({String? id, ConsultationStatus? status}) =>
      ConsultationRequest(
        id: id ?? this.id,
        trainerId: trainerId,
        trainerName: trainerName,
        trainerRole: trainerRole,
        exerciseGoal: exerciseGoal,
        healthPurposeType: healthPurposeType,
        healthPurposeDetail: healthPurposeDetail,
        preferredDate: preferredDate,
        preferredTimeSlot: preferredTimeSlot,
        message: message,
        status: status ?? this.status,
        createdAt: createdAt,
        decisionNote: decisionNote,
        decidedAt: decidedAt,
        trainerGymName: trainerGymName,
        slotStartsAt: slotStartsAt,
        slotDurationMinutes: slotDurationMinutes,
      );

  final String id;

  /// 상담을 받는 트레이너. 요청은 트레이너 한 사람 앞으로만 간다.
  final String? trainerId;
  final String? trainerName;
  final String? trainerRole;
  final String? trainerGymName;

  /// 표시용 라벨이 아니라 **계약 enum** 을 들고 있다. 서버는 코드를 주므로, 라벨을
  /// 저장하면 `GET /consultations/me` 로 복원할 때 문구를 만들 수 없다(#327).
  /// 화면이 이 값으로 현지화 문구를 고른다.
  final ExerciseGoal exerciseGoal;
  final HealthPurposeType healthPurposeType;

  /// `healthPurposeType` 이 other 일 때 사용자가 적은 내용.
  final String? healthPurposeDetail;

  /// 고른 자리의 시각 사본. 자리 선택 이전 요청에는 회원이 적어 보낸 희망 시각이
  /// 그대로 남아 있다 — 그 요청들도 계속 조회돼야 해 두 칸을 지우지 않았다(#1873).
  final DateTime preferredDate;
  final PreferredTime preferredTimeSlot;

  /// 회원이 고른 자리의 시작 시각과 길이. 화면이 **확정된 일시**를 그리는 값이다.
  ///
  /// 자리 선택 이전 요청과, 트레이너가 자리를 지운 요청에서는 null 이다. 그때는
  /// 화면이 위 [preferredDate]·[preferredTimeSlot] 로 되돌아간다.
  final DateTime? slotStartsAt;
  final int? slotDurationMinutes;
  final String? message;
  final ConsultationStatus status;
  final DateTime createdAt;

  /// 트레이너가 거절하며 남긴 사유. 승인이거나 사유를 적지 않았으면 null. (#473)
  ///
  /// "거절됨"만 보여 주면 사용자는 다시 신청해도 되는지, 다른 트레이너를 찾아야
  /// 하는지 판단할 근거가 없다. 서버가 알림 본문으로도 같은 문장을 보낸다.
  final String? decisionNote;

  /// 승인·거절된 시각. 대기 중이면 null.
  final DateTime? decidedAt;

  /// 아직 답을 기다리는 중인가.
  bool get isPending => status == ConsultationStatus.pending;
}

/// `GET /consultations/me` 응답 → 엔티티. (#327)
ConsultationRequest consultationFromJson(Map<String, Object?> j) {
  return ConsultationRequest(
    id: j['id']! as String,
    trainerId: j['trainer_id'] as String?,
    // 트레이너가 지워지면 서버가 이름을 못 준다 — null 로 두고 화면이 처리한다.
    trainerName: j['trainer_name'] as String?,
    // 서버는 트레이너 직함을 상담 응답에 담지 않는다. 목록 카드는 이름만 쓴다.
    trainerRole: null,
    trainerGymName: j['trainer_gym_name'] as String?,
    exerciseGoal: exerciseGoalFromWire(j['exercise_goal'] as String?),
    healthPurposeType: healthPurposeFromWire(
      j['health_purpose_type'] as String?,
    ),
    healthPurposeDetail: j['health_purpose_detail'] as String?,
    preferredDate:
        DateTime.tryParse((j['preferred_date'] as String?) ?? '') ?? nowKst(),
    preferredTimeSlot: preferredTimeSlotFromWire(
      j['preferred_time_slot'] as String?,
    ),
    slotStartsAt: DateTime.tryParse(
      (j['slot_starts_at'] as String?) ?? '',
    )?.toLocal(),
    slotDurationMinutes: (j['slot_duration_minutes'] as num?)?.toInt(),
    message: j['message'] as String?,
    status: switch (j['status']) {
      'accepted' => ConsultationStatus.accepted,
      'rejected' => ConsultationStatus.rejected,
      'cancelled' => ConsultationStatus.cancelled,
      'expired' => ConsultationStatus.expired,
      _ => ConsultationStatus.pending,
    },
    createdAt:
        DateTime.tryParse((j['created_at'] as String?) ?? '') ?? nowKst(),
    // 공백만 남은 사유는 null 로 접는다 — 빈 안내 줄이 그려지지 않도록.
    decisionNote: switch (j['decision_note']) {
      final String note when note.trim().isNotEmpty => note.trim(),
      _ => null,
    },
    decidedAt: DateTime.tryParse((j['decided_at'] as String?) ?? ''),
  );
}
