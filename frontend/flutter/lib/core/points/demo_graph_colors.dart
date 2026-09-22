import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';

/// 목업 API 의 그래프 색. 서버 `graph_color_service` 의 대역이다. (#2076)
///
/// 기록 그래프(#2075)은 한 가지 색상 계열의 3단계 진하기로 그린다. 그 계열을
/// 포인트로 바꾼다. 규칙은 서버와 같다:
/// - 기본 색([baseColor], 회원앱 파랑)은 누구나 쓴다. 사지 않아도 고를 수 있다.
/// - 교환은 한 색에 150P, **색 하나씩** 연다. 이미 연 색은 다시 사지 못한다.
/// - 연 색은 그 자리에서 지금 색이 된다 — 샀는데 아무 일도 없는 화면이 되지 않게.
/// - 색을 바꾸는 데에는 포인트가 들지 않고, 기한도 없다.
/// - 네 색을 모두 열면 사용처 목록에서 항목이 빠진다([allUnlocked]).
class DemoGraphColorBook {
  DemoGraphColorBook({required DemoPointsLedger ledger}) : _ledger = ledger;

  /// 포인트 사용처의 항목 id·가격 — 서버와 같은 값이다.
  static const String itemId = 'graph_color';
  static const int cost = 150;

  /// 포인트가 들지 않는 기본 색.
  static const String baseColor = 'blue';

  /// 포인트로 여는 색. 화면 팔레트에 서는 순서 그대로다.
  static const List<String> buyableColors = <String>[
    'green',
    'purple',
    'orange',
    'pink',
  ];

  /// 고를 수 있는 색 전부. 기본 색이 늘 첫 칸이다.
  static const List<String> palette = <String>[baseColor, ...buyableColors];

  final DemoPointsLedger _ledger;
  final List<String> _bought = <String>[];
  final Map<String, String> _requests = <String, String>{};
  String? _selected;
  int _sequence = 0;

  /// 지금 기록 그래프를 그리는 색. 고른 색이 없으면 기본 색이다.
  String get current => _selected ?? baseColor;

  /// 고를 수 있는 색 — 기본 색과 포인트로 연 색. 팔레트 순서다.
  List<String> get unlocked => <String>[
    for (final String c in palette)
      if (c == baseColor || _bought.contains(c)) c,
  ];

  /// 살 수 있는 색을 모두 열었는가. 사용처에서 항목을 뺄지 정한다.
  bool get allUnlocked => buyableColors.every(_bought.contains);

  /// 사용처 카드의 막힌 이유. 잔액 부족뿐이다 — 이미 연 색은 시트에서 고를 수
  /// 없고, 다 열면 카드 자체가 빠진다.
  String? blockReason(int balance) =>
      balance < cost ? 'insufficient_points' : null;

  /// `GET /me/activity-calendar` 의 `color` 와 `PUT /me/graph-color` 응답.
  Map<String, Object?> statusJson() => <String, Object?>{
    'current': current,
    'unlocked': unlocked,
    'palette': palette,
    'cost': cost,
  };

  /// `POST /me/points/exchange` 의 `item: graph_color`.
  DemoCouponResult exchange(String? color, {String? clientRequestId}) {
    if (clientRequestId != null && _requests.containsKey(clientRequestId)) {
      return DemoCouponResult(201, _exchangeJson());
    }
    if (color == null || !buyableColors.contains(color)) {
      // 기본 색은 이미 누구나 쓰므로 살 것이 아니다 — 모르는 색과 같이 막는다.
      return _error(404, '고를 수 없는 색이에요.');
    }
    if (_bought.contains(color)) return _error(409, '이미 가지고 있는 색이에요.');
    final int shortfall = cost - _ledger.balance;
    if (shortfall > 0) return _error(409, '포인트가 ${shortfall}P 부족해요.');
    if (!_ledger.spend('grs-demo-${++_sequence}', cost, reason: itemId)) {
      return _error(409, '포인트가 부족해요.');
    }
    _bought.add(color);
    _selected = color;
    if (clientRequestId != null) _requests[clientRequestId] = color;
    return DemoCouponResult(201, _exchangeJson());
  }

  /// `PUT /me/graph-color`. 포인트가 들지 않는다.
  DemoCouponResult select(String color) {
    if (!palette.contains(color)) return _error(404, '없는 색이에요.');
    if (color != baseColor && !_bought.contains(color)) {
      return _error(409, '아직 열지 않은 색이에요.');
    }
    // 기본 색으로 되돌리는 것은 고른 색을 푸는 일이다.
    _selected = color == baseColor ? null : color;
    return DemoCouponResult(200, statusJson());
  }

  Map<String, Object?> _exchangeJson() => <String, Object?>{
    'coupon': null,
    'shield': null,
    'graph_color': statusJson(),
    'spent': cost,
    'balance': _ledger.balance,
  };

  static DemoCouponResult _error(int status, String detail) =>
      DemoCouponResult(status, <String, Object?>{'detail': detail});
}

/// 목업 경로가 함께 쓰는 그래프 색 원장 하나 — 목업 API(사용처 교환·색 고르기)와
/// 기록 그래프 저장소가 같은 인스턴스를 본다. 포인트는 [demoPointsLedgerProvider]
/// 에서 빠진다.
final demoGraphColorBookProvider = Provider<DemoGraphColorBook>(
  (ref) => DemoGraphColorBook(ledger: ref.watch(demoPointsLedgerProvider)),
  name: 'demoGrassColorBook',
);
