/// AI 챗봇 대화의 통증·부정적 반응 감지. (#1824)
///
/// 트레이너 웹 채팅의 감지(`ChatContextInsight`)와 같은 두 종류다. 서버
/// `app/services/coach/insights.py` 가 같은 규칙으로 계산해 내려 준다.
library;

/// 감지 기록을 모아 보는 기간(메시지 작성일 기준). 서버와 같다.
const int kChatInsightWindowDays = 30;

/// 감지 종류.
enum ChatInsightKind {
  /// 통증·불편(부위를 함께 찾으면 [ChatInsight.bodyPart]).
  discomfort,

  /// 운동을 못 했다·힘들다는 부정적 반응.
  negativeFeedback,
}

ChatInsightKind? _kindFromWire(Object? raw) => switch (raw) {
  'discomfort' => ChatInsightKind.discomfort,
  'negative_feedback' => ChatInsightKind.negativeFeedback,
  _ => null,
};

/// 회원 메시지 한 줄에서 찾은 신호.
class ChatInsight {
  const ChatInsight({required this.kind, this.bodyPart});

  final ChatInsightKind kind;

  /// 통증일 때 찾은 부위(`무릎`·`Knee` …). 문장에 쓰인 말 그대로다.
  final String? bodyPart;

  /// 서버 `{kind, body_part}`. 모르는 종류면 null — 새 종류가 생겨도 화면이 깨지지 않는다.
  static ChatInsight? fromJson(Object? json) {
    if (json is! Map) return null;
    final ChatInsightKind? kind = _kindFromWire(json['kind']);
    if (kind == null) return null;
    final Object? part = json['body_part'];
    return ChatInsight(
      kind: kind,
      bodyPart: part is String && part.trim().isNotEmpty ? part : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatInsight && other.kind == kind && other.bodyPart == bodyPart;

  @override
  int get hashCode => Object.hash(kind, bodyPart);
}

/// 감지 기록 한 줄 — 어떤 메시지가 언제 무엇을 말했나.
class ChatInsightRecord {
  const ChatInsightRecord({
    required this.messageId,
    required this.createdAt,
    required this.insight,
    required this.text,
  });

  final String messageId;
  final DateTime createdAt;
  final ChatInsight insight;

  /// 회원이 쓴 문장 그대로.
  final String text;

  static ChatInsightRecord? fromJson(Map<String, Object?> json) {
    final ChatInsight? insight = ChatInsight.fromJson(json);
    final DateTime? createdAt = DateTime.tryParse(
      (json['created_at'] as String?) ?? '',
    );
    if (insight == null || createdAt == null) return null;
    return ChatInsightRecord(
      messageId: (json['message_id'] as String?) ?? '',
      createdAt: createdAt.toLocal(),
      insight: insight,
      text: ((json['text'] as String?) ?? '').trim(),
    );
  }
}

/// 최근 [windowDays] 일의 감지 기록(최신순).
class ChatInsightHistory {
  const ChatInsightHistory({
    this.windowDays = kChatInsightWindowDays,
    this.records = const <ChatInsightRecord>[],
  });

  final int windowDays;
  final List<ChatInsightRecord> records;

  factory ChatInsightHistory.fromJson(Map<String, Object?> json) =>
      ChatInsightHistory(
        windowDays:
            (json['window_days'] as num?)?.toInt() ?? kChatInsightWindowDays,
        records: <ChatInsightRecord>[
          for (final Object? row
              in (json['insights'] as List<Object?>?) ?? const <Object?>[])
            if (row is Map)
              ?ChatInsightRecord.fromJson(row.cast<String, Object?>()),
        ],
      );
}
