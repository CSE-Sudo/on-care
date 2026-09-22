import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/clock.dart';

/// 데모의 MY 프로필 펫 이모지. 서버 `profile_pet_service` 의 대역이다. (#2021)
///
/// 규칙은 서버와 같다 — 강아지나 고양이 하나를 200P 에 7일 동안 단다. 달고 있는
/// 동안에는 다시 사지 못하고, 기간이 지나면 저절로 떨어진다.
///
/// MY 프로필 카드와 포인트 사용처가 **같은 원장**을 봐야 한다 — 따로 세면 사용처에서
/// 샀는데 이름 옆은 비어 있는 화면이 된다.
class DemoProfilePetBook {
  DemoProfilePetBook({
    required DemoPointsLedger ledger,
    DateTime Function()? now,
  }) : _ledger = ledger,
       _now = now ?? nowKst;

  /// 포인트 사용처의 항목 id·가격·기간 — 서버와 같은 값이다.
  static const String itemId = 'profile_pet';
  static const int cost = 200;
  static const int days = 7;
  static const List<String> kinds = <String>['dog', 'cat'];

  final DemoPointsLedger _ledger;
  final DateTime Function() _now;
  final Map<String, String> _requests = <String, String>{};
  String? _kind;
  DateTime? _expiresAt;
  int _sequence = 0;

  /// 남은 기간. 달고 있지 않거나 기간이 끝났으면 null.
  Duration? get remaining {
    final DateTime? until = _expiresAt;
    if (until == null) return null;
    final Duration left = until.difference(_now());
    return left > Duration.zero ? left : null;
  }

  bool get active => remaining != null;

  /// 달고 있는 펫. 기간이 끝났으면 null.
  String? get kind => active ? _kind : null;

  Map<String, Object?>? _petJson() => active
      ? <String, Object?>{
          'kind': _kind,
          'expires_at': _expiresAt!.toIso8601String(),
          'remaining_seconds': remaining!.inSeconds,
        }
      : null;

  /// `GET /me/profile-pet`.
  Map<String, Object?> stateJson() => <String, Object?>{
    'pet': _petJson(),
    'cost': cost,
    'days': days,
    'kinds': kinds,
  };

  /// 사용처 카드가 남은 기간을 그릴 값. 달고 있지 않으면 빈 맵.
  Map<String, Object?> activeFieldsJson() => active
      ? <String, Object?>{
          'active_option': _kind,
          'active_until': _expiresAt!.toIso8601String(),
          'remaining_seconds': remaining!.inSeconds,
        }
      : const <String, Object?>{};

  /// `POST /me/points/exchange` 의 `item: profile_pet`.
  DemoCouponResult exchange(String? kind, {String? clientRequestId}) {
    if (clientRequestId != null && _requests.containsKey(clientRequestId)) {
      return DemoCouponResult(201, _exchangeJson());
    }
    if (kind == null || !kinds.contains(kind)) {
      return _error(404, '고를 수 없는 펫이에요.');
    }
    if (active) return _error(409, '이미 달고 있는 펫이 있어요.');
    final int shortfall = cost - _ledger.balance;
    if (shortfall > 0) return _error(409, '포인트가 ${shortfall}P 부족해요.');
    if (!_ledger.spend('pet-demo-${++_sequence}', cost, reason: itemId)) {
      return _error(409, '포인트가 부족해요.');
    }
    _kind = kind;
    _expiresAt = _now().add(const Duration(days: days));
    if (clientRequestId != null) _requests[clientRequestId] = kind;
    return DemoCouponResult(201, _exchangeJson());
  }

  Map<String, Object?> _exchangeJson() => <String, Object?>{
    'coupon': null,
    'profile_pet': _petJson(),
    'spent': cost,
    'balance': _ledger.balance,
  };

  static DemoCouponResult _error(int status, String detail) =>
      DemoCouponResult(status, <String, Object?>{'detail': detail});
}

/// 목업 경로가 함께 쓰는 펫 원장 하나 — 사용처 교환과 MY 프로필 카드가 같은 것을 본다.
final demoProfilePetBookProvider = Provider<DemoProfilePetBook>(
  (ref) => DemoProfilePetBook(ledger: ref.watch(demoPointsLedgerProvider)),
  name: 'demoProfilePetBook',
);
