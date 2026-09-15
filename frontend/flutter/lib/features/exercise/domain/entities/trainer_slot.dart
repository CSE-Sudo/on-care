/// 포인트 체험 자리의 종류 계약값(#1790). 서버 `points_trial_service` 와 같다.
const String kPointsTrialSessionType = '체험';

/// 포인트 체험에 드는 포인트.
const int kPointsTrialCost = 500;

/// 포인트 체험 시간(분).
const int kPointsTrialMinutes = 20;

/// 포인트 체험을 지금 예약할 수 없는 이유 — 서버 `trial_blocked_reason` 값.
abstract final class TrialBlockedReason {
  /// 이 트레이너의 체험을 이미 이용했다(반환된 예약은 세지 않는다).
  static const String trialUsed = 'trial_used';

  /// 잔액이 500P 보다 적다.
  static const String insufficientPoints = 'insufficient_points';

  /// 담당 트레이너가 있다. 서버는 이 경우 체험 자리를 아예 주지 않지만, 목업과
  /// 오래된 응답을 위해 값은 둔다.
  static const String hasTrainer = 'has_trainer';
}

/// One bookable time on a trainer's calendar.
///
/// Slots belong to a trainer, not to a gym: a gym employs several trainers and
/// each keeps their own hours, so the same gym shows different times depending
/// on who you are booking.
///
/// 자리는 언제나 한 사람 몫이다 — 1:1 PT 든 상담이든 여럿이 함께 듣지 않는다.
/// 그래서 정원과 잔여 인원 개념이 없고, 슬롯은 **비었거나 예약된** 두 상태뿐이다
/// (#1072).
class TrainerSlot {
  const TrainerSlot({
    required this.id,
    required this.trainerId,
    required this.startsAt,
    required this.booked,
    required this.sessionType,
    this.durationMinutes = 60,
    this.pointsCost = 0,
    this.trialBlockedReason,
  });

  final String id;
  final String trainerId;

  /// When the session starts. Rendered with the device locale rather than a
  /// fixed "오늘/내일" string, so the label stays true as days pass.
  final DateTime startsAt;

  /// 이미 예약된 자리인가. 예약된 자리도 숨기지 않고 비활성으로 남겨, 그
  /// 트레이너의 하루가 "비어 있음" 이 아니라 "찼음" 으로 읽히게 한다.
  final bool booked;

  /// `'1:1 PT'` · `'상담'` · `'체험'` — 트레이너 앱 스케줄 탭의 세션 종류와 같은
  /// 계약값이다. 회원이 이 시간을 예약하면 만들어지는 일정이 이 종류를
  /// 그대로 물려받는다. `체험` 은 포인트 체험 자리다(#1790).
  final String sessionType;
  final int durationMinutes;

  /// 이 자리를 예약하는 데 드는 포인트. 체험 자리만 500 이다.
  final int pointsCost;

  /// 체험 자리를 지금 예약할 수 없는 이유([TrialBlockedReason]). 가능하면 null.
  final String? trialBlockedReason;

  /// 담당 트레이너가 없는 회원이 포인트로 예약하는 20분 체험 자리인가.
  bool get isPointsTrial => sessionType == kPointsTrialSessionType;

  TrainerSlot copyWith({bool? booked, String? trialBlockedReason}) {
    return TrainerSlot(
      id: id,
      trainerId: trainerId,
      startsAt: startsAt,
      booked: booked ?? this.booked,
      sessionType: sessionType,
      durationMinutes: durationMinutes,
      pointsCost: pointsCost,
      trialBlockedReason: trialBlockedReason ?? this.trialBlockedReason,
    );
  }
}
