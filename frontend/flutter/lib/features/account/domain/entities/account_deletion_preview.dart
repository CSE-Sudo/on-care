/// 탈퇴하면 사라지거나 취소되는 것의 건수. `GET /users/me/deletion-preview`. (#3006)
///
/// 탈퇴 확인창이 "보유 포인트 1,200P가 사라져요" 처럼 **이 계정의 숫자**로
/// 말하게 하는 값이다. 숫자를 못 받아도 탈퇴는 막지 않는다 — 확인창은 일반
/// 문구만으로 뜬다.
library;

class AccountDeletionPreview {
  const AccountDeletionPreview({
    this.points = 0,
    this.activeCoupons = 0,
    this.upcomingReservations = 0,
    this.pendingConsultations = 0,
  });

  /// 보유 포인트 잔액.
  final int points;

  /// 사용 전이고 만료되지 않은 쿠폰 수.
  final int activeCoupons;

  /// 아직 시작하지 않은 PT 예약 수. 탈퇴하면 취소된다.
  final int upcomingReservations;

  /// 트레이너 응답을 기다리는 상담 요청 수. 탈퇴하면 취소된다.
  final int pendingConsultations;

  /// 하나라도 사라지는 것이 있는가. 없으면 확인창에 숫자 줄을 달지 않는다.
  bool get hasLosses =>
      points > 0 ||
      activeCoupons > 0 ||
      upcomingReservations > 0 ||
      pendingConsultations > 0;

  factory AccountDeletionPreview.fromJson(Map<String, Object?> json) =>
      AccountDeletionPreview(
        points: _count(json['points']),
        activeCoupons: _count(json['active_coupons']),
        upcomingReservations: _count(json['upcoming_reservations']),
        pendingConsultations: _count(json['pending_consultations']),
      );

  AccountDeletionPreview copyWith({
    int? points,
    int? activeCoupons,
    int? upcomingReservations,
    int? pendingConsultations,
  }) => AccountDeletionPreview(
    points: points ?? this.points,
    activeCoupons: activeCoupons ?? this.activeCoupons,
    upcomingReservations: upcomingReservations ?? this.upcomingReservations,
    pendingConsultations: pendingConsultations ?? this.pendingConsultations,
  );

  @override
  bool operator ==(Object other) =>
      other is AccountDeletionPreview &&
      other.points == points &&
      other.activeCoupons == activeCoupons &&
      other.upcomingReservations == upcomingReservations &&
      other.pendingConsultations == pendingConsultations;

  @override
  int get hashCode => Object.hash(
    points,
    activeCoupons,
    upcomingReservations,
    pendingConsultations,
  );

  @override
  String toString() =>
      'AccountDeletionPreview(points: $points, coupons: $activeCoupons, '
      'reservations: $upcomingReservations, '
      'consultations: $pendingConsultations)';
}

/// 빠지거나 음수·소수로 온 값은 0 이상 정수로 읽는다 — 확인창에 "-1건" 이 뜨지 않게.
int _count(Object? raw) => raw is num && raw > 0 ? raw.toInt() : 0;
