/// 회원이 포인트로 교환한 PT 재등록 할인 쿠폰 — 트레이너가 보는 모양. (#1787)
///
/// `GET /trainer/clients/{member_id}/coupons` 의 항목이다. 코드는 싣지 않는다 —
/// 트레이너는 이미 회원을 특정한 상세 화면에서 처리하므로 코드 입력 단계가 없다.
class RenewalCoupon {
  const RenewalCoupon({
    required this.id,
    required this.item,
    required this.benefit,
    required this.status,
    required this.issuedOn,
    required this.expiresOn,
    required this.daysLeft,
  });

  final String id;

  /// 교환 항목 id — 지금은 `pt_renewal` 뿐이다.
  final String item;

  /// 서버 문구(한국어). 화면은 아는 항목이면 현지화 문구를 쓴다.
  final String benefit;

  /// issued|used|expired|cancelled.
  final String status;

  /// 교환한 날(KST).
  final DateTime issuedOn;

  /// 쓸 수 있는 마지막 날(KST).
  final DateTime expiresOn;

  /// 마지막 날까지 남은 날 — 당일 0.
  final int daysLeft;

  bool get usable => status == 'issued';

  RenewalCoupon copyWith({String? status}) => RenewalCoupon(
    id: id,
    item: item,
    benefit: benefit,
    status: status ?? this.status,
    issuedOn: issuedOn,
    expiresOn: expiresOn,
    daysLeft: daysLeft,
  );

  factory RenewalCoupon.fromJson(Map<String, Object?> json) => RenewalCoupon(
    id: json['id']! as String,
    item: (json['item'] as String?) ?? 'pt_renewal',
    benefit: (json['benefit'] as String?) ?? '',
    status: (json['status'] as String?) ?? 'issued',
    issuedOn: _date(json['issued_on']),
    expiresOn: _date(json['expires_on']),
    daysLeft: (json['days_left'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'item': item,
    'benefit': benefit,
    'status': status,
    'issued_on': _ymd(issuedOn),
    'expires_on': _ymd(expiresOn),
    'days_left': daysLeft,
  };

  static DateTime _date(Object? raw) {
    final DateTime? parsed = raw is String ? DateTime.tryParse(raw) : null;
    if (parsed == null) return DateTime(1970);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _ymd(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
