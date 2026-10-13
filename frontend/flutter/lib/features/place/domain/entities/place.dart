enum PlaceCategory { medical, fitness, healthyFood, pharmacy }

/// Wire form: `medical | fitness | healthy_food | pharmacy`.
PlaceCategory _categoryFromWire(String s) => switch (s) {
  'healthy_food' => PlaceCategory.healthyFood,
  'fitness' => PlaceCategory.fitness,
  'pharmacy' => PlaceCategory.pharmacy,
  _ => PlaceCategory.medical,
};

/// Inverse of [_categoryFromWire] — used for the `category` query parameter.
String categoryToWire(PlaceCategory c) => switch (c) {
  PlaceCategory.healthyFood => 'healthy_food',
  PlaceCategory.fitness => 'fitness',
  PlaceCategory.pharmacy => 'pharmacy',
  PlaceCategory.medical => 'medical',
};

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.distanceMeters,
    required this.lat,
    required this.lng,
    this.phone,
  });

  final String id;
  final String name;
  final PlaceCategory category;
  final String address;
  final int distanceMeters;

  /// 좌표. 서버 계약(`PlaceOut.lat/lng`)이 null 을 허용한다(#2879) — 좌표가
  /// 없는 장소도 목록에는 서고, 지도 마커만 빠진다.
  final double? lat;
  final double? lng;

  /// 전화번호. 서버가 모르면 null 이다(#3357). 가입한 트레이너가 없는 헬스장은
  /// 상담을 걸 대상이 없어, 헬스장 상세가 이 번호로 전화 문의를 연다.
  final String? phone;

  factory Place.fromJson(Map<String, Object?> json) => Place(
    id: json['id']! as String,
    name: json['name']! as String,
    category: _categoryFromWire(json['category']! as String),
    address: json['address']! as String,
    distanceMeters: (json['distance_meters']! as num).toInt(),
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    phone: _phoneFromWire(json['phone']),
  );

  /// 빈 문자열·공백은 번호가 없는 것으로 읽는다 — 누를 수 없는 전화 줄이 서지
  /// 않게.
  static String? _phoneFromWire(Object? raw) {
    if (raw is! String) return null;
    final String phone = raw.trim();
    return phone.isEmpty ? null : phone;
  }
}
