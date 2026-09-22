/// 포인트 내역 — 무엇으로 얼마가 쌓이고 쓰였는가. (#2146)
///
/// 서버(`GET /me/points/history`)가 기록이 있는 날 기준 최근 며칠치를 최신순으로
/// 준다. 더 앞의 날은 [PointsHistory.nextBefore] 로 이어 받는다.
library;

/// 잔액이 움직인 방향.
enum PointsEntryKind {
  /// 적립 — 기록·챌린지 보상.
  earn,

  /// 사용 — 사용처 교환·AI 코치 대화.
  spend,

  /// 회수 — 기록을 지워 받은 적립이 빠졌다.
  revoke,

  /// 반환 — 쿠폰 취소 등으로 쓴 포인트가 돌아왔다.
  refund,
}

class PointsHistoryEntry {
  const PointsHistoryEntry({
    required this.id,
    required this.kind,
    required this.reason,
    required this.delta,
    required this.day,
    this.count = 1,
  });

  final String id;
  final PointsEntryKind kind;

  /// 사유 코드 — `diet_entry`·`coupon_locker_month`·`ai_chat` …
  final String reason;

  /// 잔액 변화량. 적립·반환은 양수, 사용·회수는 0 이하다.
  final int delta;

  /// 묶은 줄 수. AI 코치 대화만 하루치를 한 줄로 묶어 1 보다 크다.
  final int count;

  /// 이 줄이 생긴 KST 날짜.
  final DateTime day;

  static PointsHistoryEntry? fromJson(Map<String, Object?> json) {
    final DateTime? day = DateTime.tryParse(
      (json['kst_date'] as String?) ?? '',
    );
    if (day == null) return null;
    return PointsHistoryEntry(
      id: (json['id'] as String?) ?? '',
      kind: switch (json['kind']) {
        'spend' => PointsEntryKind.spend,
        'revoke' => PointsEntryKind.revoke,
        'refund' => PointsEntryKind.refund,
        _ => PointsEntryKind.earn,
      },
      reason: (json['reason'] as String?) ?? '',
      delta: (json['delta'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 1,
      day: DateTime(day.year, day.month, day.day),
    );
  }
}

class PointsHistory {
  const PointsHistory({
    required this.balance,
    required this.entries,
    this.nextBefore,
  });

  final int balance;
  final List<PointsHistoryEntry> entries;

  /// 더 앞의 날이 있으면 다음 요청의 `before`. 없으면 null.
  final String? nextBefore;

  factory PointsHistory.fromJson(Map<String, Object?> json) =>
      PointsHistory(
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        entries: <PointsHistoryEntry>[
          for (final Object? raw
              in (json['items'] as List<Object?>?) ?? const <Object?>[])
            if (raw is Map)
              ?PointsHistoryEntry.fromJson(raw.cast<String, Object?>()),
        ],
        nextBefore: json['next_before'] as String?,
      );
}
