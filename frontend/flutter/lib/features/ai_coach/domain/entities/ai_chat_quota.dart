/// AI 챗봇의 오늘 대화 한도. (#2145)
///
/// 하루 무료 [freeLimit] 번, 다 쓰면 한 번에 [cost] 포인트로 [paidLimit] 번까지 더
/// 보낸다. 값은 서버(`GET /ai-coach/quota`)가 정한다 — 앱이 따로 들고 있으면 서버
/// 설정을 바꿨을 때 화면만 옛 값으로 남는다.
library;

/// 다음 대화가 무엇으로 나가는가.
enum AiChatNext {
  /// 무료 대화가 남았다.
  free,

  /// 무료를 다 썼다 — 포인트로 보낸다.
  paid,

  /// 오늘은 더 보낼 수 없다.
  exhausted,
}

class AiChatQuota {
  const AiChatQuota({
    required this.freeLimit,
    required this.freeLeft,
    required this.paidLimit,
    required this.paidLeft,
    required this.cost,
    required this.balance,
    required this.next,
  });

  final int freeLimit;
  final int freeLeft;
  final int paidLimit;
  final int paidLeft;

  /// 포인트로 보내는 한 번의 값.
  final int cost;

  /// 지금 포인트 잔액.
  final int balance;
  final AiChatNext next;

  /// 오늘 포인트로 산 대화 수.
  int get paidUsed => paidLimit - paidLeft;

  /// 포인트로 보내야 하는데 잔액이 모자란가.
  bool get short => next == AiChatNext.paid && balance < cost;

  factory AiChatQuota.fromJson(Map<String, Object?> json) => AiChatQuota(
    freeLimit: (json['free_limit'] as num?)?.toInt() ?? 0,
    freeLeft: (json['free_left'] as num?)?.toInt() ?? 0,
    paidLimit: (json['paid_limit'] as num?)?.toInt() ?? 0,
    paidLeft: (json['paid_left'] as num?)?.toInt() ?? 0,
    cost: (json['cost'] as num?)?.toInt() ?? 0,
    balance: (json['balance'] as num?)?.toInt() ?? 0,
    next: switch (json['next']) {
      'paid' => AiChatNext.paid,
      'exhausted' => AiChatNext.exhausted,
      _ => AiChatNext.free,
    },
  );
}

/// 서버가 대화를 보내지 않은 까닭. (#2145)
enum AiChatBlockReason {
  /// 무료를 다 썼는데 포인트로 보내는 데 동의하지 않았다.
  pointsRequired,

  /// 오늘 무료와 포인트 대화를 모두 썼다.
  dailyLimit,

  /// 포인트가 모자라다.
  insufficientPoints,
}

/// 한도 때문에 보내지 못했다. 저장소가 서버 거절을 이것으로 바꾼다.
class AiChatBlocked implements Exception {
  const AiChatBlocked(this.reason, {this.shortfall = 0});

  final AiChatBlockReason reason;

  /// 모자란 포인트. [AiChatBlockReason.insufficientPoints] 일 때만 의미가 있다.
  final int shortfall;

  /// 서버 응답 `detail: {code, shortfall}` 에서. 한도 거절이 아니면 null.
  static AiChatBlocked? fromDetail(Object? detail) {
    if (detail is! Map) return null;
    final int shortfall = (detail['shortfall'] as num?)?.toInt() ?? 0;
    return switch (detail['code']) {
      'points_required' => const AiChatBlocked(
        AiChatBlockReason.pointsRequired,
      ),
      'daily_limit' => const AiChatBlocked(AiChatBlockReason.dailyLimit),
      'insufficient_points' => AiChatBlocked(
        AiChatBlockReason.insufficientPoints,
        shortfall: shortfall,
      ),
      _ => null,
    };
  }

  @override
  String toString() => 'AiChatBlocked($reason, shortfall: $shortfall)';
}
