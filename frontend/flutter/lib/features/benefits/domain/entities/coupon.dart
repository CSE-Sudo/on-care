/// 포인트로 교환한 쿠폰 한 장 — `GET /me/coupons` 의 항목. (#1787)
library;

import 'package:oncare/core/utils/clock.dart' show kstOffset;

/// 쿠폰 상태. 서버가 기한이 지난 쿠폰을 아직 만료로 내리지 않았어도 응답은
/// 만료로 온다 — 앱은 받은 값만 믿는다.
enum CouponStatus { issued, used, expired, cancelled }

/// 누가 사용 처리하나. 지금은 모든 쿠폰을 회원 휴대폰에서 처리한다(PT 재등록
/// 쿠폰도 직원 확인 뒤 회원 화면에서 누른다). 서버가 다른 값을 주면 [trainer] 다.
enum CouponRedeemer { trainer, member }

CouponRedeemer couponRedeemerFrom(Object? raw) =>
    raw == 'trainer' ? CouponRedeemer.trainer : CouponRedeemer.member;

/// 모르는 상태는 쓸 수 없는 쪽(만료)으로 읽는다 — 새 상태가 생겼을 때 사용
/// 버튼이 잘못 열리는 것보다 낫다.
CouponStatus _statusFrom(Object? raw) => switch (raw) {
  'issued' => CouponStatus.issued,
  'used' => CouponStatus.used,
  'cancelled' => CouponStatus.cancelled,
  _ => CouponStatus.expired,
};

/// `YYYY-MM-DD` 를 그 날짜(시각 없음)로 읽는다.
DateTime _dateFrom(Object? raw) {
  final DateTime? parsed = raw is String ? DateTime.tryParse(raw) : null;
  if (parsed == null) return DateTime(1970);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// 서버 시각을 KST 벽시계 값으로 읽는다 — 앱의 `nowKst()` 와 같은 모양(필드에
/// 서울 시각을 담은 로컬 `DateTime`)이다.
///
/// 오프셋이 붙은 서버 값은 UTC 로 읽힌 뒤 +9 시간 한다. 오프셋 없는 값(목업이
/// `nowKst()` 로 만든 값)은 이미 KST 벽시계라 그대로 쓴다.
DateTime? _kstFrom(Object? raw) {
  final DateTime? parsed = raw is String ? DateTime.tryParse(raw) : null;
  if (parsed == null) return null;
  if (!parsed.isUtc) return parsed;
  final DateTime seoul = parsed.add(kstOffset);
  return DateTime(
    seoul.year,
    seoul.month,
    seoul.day,
    seoul.hour,
    seoul.minute,
    seoul.second,
  );
}

class Coupon {
  const Coupon({
    required this.id,
    required this.item,
    required this.title,
    required this.benefit,
    required this.cost,
    required this.status,
    required this.redeemer,
    required this.issuedOn,
    required this.expiresOn,
    required this.daysLeft,
    this.trainerName = '',
    this.gymName = '',
    this.usedAt,
  });

  final String id;

  /// 교환 항목 id — pt_renewal|salad_discount|protein_discount.
  final String item;

  /// 서버 문구. 앱은 아는 항목이면 현지화 문구를 쓰고, 모르는 항목에만 이 값을 쓴다.
  final String title;
  final String benefit;

  /// 교환에 쓴 포인트.
  final int cost;
  final CouponStatus status;
  final CouponRedeemer redeemer;

  /// 교환할 때의 담당 트레이너·헬스장(PT 재등록 쿠폰만).
  final String trainerName;
  final String gymName;

  /// 교환한 날(KST).
  final DateTime issuedOn;

  /// 쓸 수 있는 마지막 날(KST).
  final DateTime expiresOn;

  /// 마지막 날까지 남은 날 — 당일 0. 사용 가능이 아니면 0.
  final int daysLeft;

  /// 사용 완료를 누른 시각(KST 벽시계). 사용하지 않았으면 null.
  final DateTime? usedAt;

  bool get usable => status == CouponStatus.issued;

  factory Coupon.fromJson(Map<String, Object?> json) => Coupon(
    id: json['id']! as String,
    item: (json['item'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    benefit: (json['benefit'] as String?) ?? '',
    cost: (json['cost'] as num?)?.toInt() ?? 0,
    status: _statusFrom(json['status']),
    redeemer: couponRedeemerFrom(json['redeemer']),
    trainerName: (json['trainer_name'] as String?) ?? '',
    gymName: (json['gym_name'] as String?) ?? '',
    issuedOn: _dateFrom(json['issued_on']),
    expiresOn: _dateFrom(json['expires_on']),
    daysLeft: (json['days_left'] as num?)?.toInt() ?? 0,
    usedAt: _kstFrom(json['used_at']),
  );
}

/// 교환 결과 — 발급한 쿠폰, 쓴 포인트, 그 뒤의 잔액.
class CouponExchange {
  const CouponExchange({
    required this.coupon,
    required this.spent,
    required this.balance,
  });

  /// 연속 기록 보호권(#1788)은 쿠폰이 아니라 null 이다 — 서버는 대신 `shield` 를
  /// 싣는다. 받은 보호권은 내 혜택의 보호권 구역이 다시 읽는다.
  final Coupon? coupon;
  final int spent;
  final int balance;

  factory CouponExchange.fromJson(Map<String, Object?> json) => CouponExchange(
    coupon: json['coupon'] is Map
        ? Coupon.fromJson(
            (json['coupon']! as Map<Object?, Object?>).cast<String, Object?>(),
          )
        : null,
    spent: (json['spent'] as num?)?.toInt() ?? 0,
    balance: (json['balance'] as num?)?.toInt() ?? 0,
  );
}
