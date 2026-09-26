import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/utils/clock.dart';

/// 데모의 AI 챗봇 하루 한도. 서버 `ai_chat_quota_service` 의 대역이다. (#2145)
///
/// 규칙은 서버와 같다 — 하루 무료 [freeLimit](5) 번, 다 쓰면 한 번에 [cost] 포인트로
/// [paidLimit] 번까지. 무료를 넘기려면 보낼 때마다 동의(`pay_with_points`)가 있어야
/// 하고(#2217), 같은 멱등키 재전송은 한 번만 센다. 데모 답은 늘 "AI 가 답한" 것으로
/// 센다.
class DemoAiChatQuota {
  DemoAiChatQuota({required DemoPointsLedger ledger, DateTime Function()? now})
    : _ledger = ledger,
      _now = now ?? nowKst;

  static const int freeLimit = 5;
  static const int paidLimit = 10;
  static const int cost = 50;

  final DemoPointsLedger _ledger;
  final DateTime Function() _now;
  final Map<String, ({int free, int paid})> _byDay =
      <String, ({int free, int paid})>{};
  final Map<String, ({int spent, int? balance})> _requests =
      <String, ({int spent, int? balance})>{};
  int _sequence = 0;

  String get _today {
    final DateTime n = _now();
    return '${n.year}-${n.month}-${n.day}';
  }

  ({int free, int paid}) get _used => _byDay[_today] ?? (free: 0, paid: 0);

  /// `GET /ai-coach/quota`.
  Map<String, Object?> statusJson() {
    final int freeLeft = (freeLimit - _used.free).clamp(0, freeLimit);
    final int paidLeft = (paidLimit - _used.paid).clamp(0, paidLimit);
    return <String, Object?>{
      'free_limit': freeLimit,
      'free_left': freeLeft,
      'paid_limit': paidLimit,
      'paid_left': paidLeft,
      'cost': cost,
      'balance': _ledger.balance,
      'next': freeLeft > 0
          ? 'free'
          : paidLeft > 0
          ? 'paid'
          : 'exhausted',
    };
  }

  /// 보낼 수 있는지 본다. 거절이면 `(상태코드, detail)`, 보낼 수 있으면 null.
  (int, Map<String, Object?>)? refusal({required bool payWithPoints}) {
    final Map<String, Object?> s = statusJson();
    if (s['next'] == 'free') return null;
    if (s['next'] == 'exhausted') {
      return (
        429,
        <String, Object?>{
          'code': 'daily_limit',
          'message': '오늘 AI 코치 대화를 다 썼어요. 내일 다시 열려요.',
        },
      );
    }
    if (!payWithPoints) {
      return (
        402,
        <String, Object?>{
          'code': 'points_required',
          'message': '오늘 무료 대화를 다 썼어요.',
        },
      );
    }
    final int shortfall = cost - _ledger.balance;
    if (shortfall > 0) {
      return (
        409,
        <String, Object?>{
          'code': 'insufficient_points',
          'message': '포인트가 ${shortfall}P 부족해요.',
          'shortfall': shortfall,
        },
      );
    }
    return null;
  }

  /// 이미 센 재전송이면 그때의 차감.
  ({int spent, int? balance})? replay(String? clientRequestId) =>
      clientRequestId == null ? null : _requests[clientRequestId];

  /// 답한 대화 한 번을 센다. 무료가 남았으면 무료, 아니면 포인트로 차감한다.
  ({int spent, int? balance}) record({String? clientRequestId}) {
    final ({int free, int paid}) used = _used;
    ({int spent, int? balance}) result = (spent: 0, balance: null);
    if (used.free < freeLimit) {
      _byDay[_today] = (free: used.free + 1, paid: used.paid);
    } else if (_ledger.spend(
      'ai-chat-demo-${++_sequence}',
      cost,
      reason: 'ai_chat',
    )) {
      _byDay[_today] = (free: used.free, paid: used.paid + 1);
      result = (spent: cost, balance: _ledger.balance);
    }
    if (clientRequestId != null) _requests[clientRequestId] = result;
    return result;
  }
}
