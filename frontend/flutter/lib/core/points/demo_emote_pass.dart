import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/clock.dart';

/// 데모의 채팅 이모티콘 24시간 이용권. 서버 `emote_service` 의 대역이다. (#2020)
///
/// 채팅의 고르는 창과 MY 탭의 포인트 사용처가 **같은 이용권**을 봐야 한다 —
/// 두 곳이 따로 세면 MY 에서 샀는데 채팅은 잠겨 있는 화면이 된다.
class DemoEmotePassBook {
  DemoEmotePassBook({required DemoPointsLedger ledger, DateTime Function()? now})
    : _ledger = ledger,
      _now = now ?? nowKst;

  final DemoPointsLedger _ledger;
  final DateTime Function() _now;
  DateTime? _expiresAt;
  int _sequence = 0;

  static const int cost = 300;
  static const int hours = 24;

  /// 남은 시간. 이용권이 없거나 끝났으면 null.
  Duration? get remaining {
    final DateTime? until = _expiresAt;
    if (until == null) return null;
    final Duration left = until.difference(_now());
    return left > Duration.zero ? left : null;
  }

  bool get active => remaining != null;
  DateTime? get expiresAt => active ? _expiresAt : null;

  /// `GET /me/emotes`.
  Map<String, Object?> stateJson() => <String, Object?>{
    'pass': active
        ? <String, Object?>{
            'expires_at': _expiresAt!.toIso8601String(),
            'remaining_seconds': remaining!.inSeconds,
          }
        : null,
    'cost': cost,
    'hours': hours,
    'balance': _ledger.balance,
  };

  /// `POST /me/emotes/pass` 와 사용처의 `emote_pass_24h` 교환이 함께 쓴다.
  DemoCouponResult buy({String? clientRequestId}) {
    if (active) {
      return const DemoCouponResult(409, <String, Object?>{
        'detail': '이미 이용 중이에요.',
      });
    }
    final int shortfall = cost - _ledger.balance;
    if (shortfall > 0) {
      return DemoCouponResult(400, <String, Object?>{
        'detail': '포인트가 ${shortfall}P 부족해요.',
      });
    }
    if (!_ledger.spend(
      'emote-pass-demo-${++_sequence}',
      cost,
      reason: 'emote_pass_24h',
    )) {
      return const DemoCouponResult(400, <String, Object?>{
        'detail': '포인트가 부족해요.',
      });
    }
    _expiresAt = _now().add(const Duration(hours: hours));
    return DemoCouponResult(200, stateJson());
  }
}

/// 목업 경로가 함께 쓰는 이용권 하나 — 채팅의 고르는 창과 MY 탭이 같은 것을 본다.
final demoEmotePassBookProvider = Provider<DemoEmotePassBook>(
  (ref) => DemoEmotePassBook(ledger: ref.watch(demoPointsLedgerProvider)),
  name: 'demoEmotePassBook',
);
