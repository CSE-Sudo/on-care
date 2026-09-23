import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 데모의 채팅 이모티콘 — 하나씩 사서 7일 동안 쓴다. 서버 `emote_service` 의
/// 대역이다. (#2153)
class DemoEmoteBook {
  DemoEmoteBook({required DemoPointsLedger ledger, DateTime Function()? now})
    : _ledger = ledger,
      _now = now ?? nowKst;

  final DemoPointsLedger _ledger;
  final DateTime Function() _now;
  final Map<String, DateTime> _expiresAt = <String, DateTime>{};
  int _sequence = 0;

  static const int cost = 50;
  static const int days = 7;

  /// 지금 쓸 수 있는 이모티콘과 남은 기간.
  Map<String, Duration> get unlocked {
    final DateTime now = _now();
    return <String, Duration>{
      for (final MapEntry<String, DateTime> e in _expiresAt.entries)
        if (e.value.isAfter(now)) e.key: e.value.difference(now),
    };
  }

  /// `GET /me/emotes`.
  Map<String, Object?> stateJson() {
    final List<MapEntry<String, Duration>> rows = unlocked.entries.toList()
      ..sort(
        (MapEntry<String, Duration> a, MapEntry<String, Duration> b) =>
            a.value.compareTo(b.value),
      );
    return <String, Object?>{
      'unlocked': <Map<String, Object?>>[
        for (final MapEntry<String, Duration> e in rows)
          <String, Object?>{
            'emote_id': e.key,
            'expires_at': _expiresAt[e.key]!.toIso8601String(),
            'remaining_seconds': e.value.inSeconds,
          },
      ],
      'cost': cost,
      'days': days,
      'balance': _ledger.balance,
    };
  }

  /// `POST /me/emotes/{emote_id}/unlock`.
  DemoCouponResult unlock(String emoteId) {
    if (!AppEmotes.has(emoteId)) {
      return const DemoCouponResult(404, <String, Object?>{
        'detail': '없는 이모티콘이에요.',
      });
    }
    if (unlocked.containsKey(emoteId)) {
      return const DemoCouponResult(409, <String, Object?>{
        'detail': '이미 쓰고 있는 이모티콘이에요.',
      });
    }
    final int shortfall = cost - _ledger.balance;
    if (shortfall > 0) {
      return DemoCouponResult(400, <String, Object?>{
        'detail': '포인트가 ${shortfall}P 부족해요.',
      });
    }
    if (!_ledger.spend(
      'emote-unlock-demo-${++_sequence}',
      cost,
      reason: 'emote_unlock',
    )) {
      return const DemoCouponResult(400, <String, Object?>{
        'detail': '포인트가 부족해요.',
      });
    }
    _expiresAt[emoteId] = _now().add(const Duration(days: days));
    return DemoCouponResult(200, stateJson());
  }
}

/// 목업 경로가 함께 쓰는 이모티콘 원장 하나.
final demoEmoteBookProvider = Provider<DemoEmoteBook>(
  (ref) => DemoEmoteBook(ledger: ref.watch(demoPointsLedgerProvider)),
  name: 'demoEmoteBook',
);
