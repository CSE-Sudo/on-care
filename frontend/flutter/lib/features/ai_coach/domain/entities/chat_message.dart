import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare_core/clock.dart';

enum ChatRole { user, coach }

/// 서버가 준 답이 아니라 **앱이 스스로 띄우는** 말풍선.
///
/// 인사와 실패 안내가 그렇다. 문구를 [ChatMessage.content] 에 담아 두면 로케일을
/// 따라가지 못하므로(#847), 어떤 말풍선인지만 표시하고 문구는 화면이
/// `AppLocalizations` 에서 가져와 그린다.
enum ChatNotice {
  /// 대화를 처음 열었을 때의 인사.
  welcome,

  /// 답을 받지 못했을 때의 안내.
  failure,
}

/// One message in the coach conversation. [pending] marks the transient
/// "typing…" placeholder shown while awaiting the coach's reply.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.sources = const <String>[],
    this.pending = false,
    this.notice,
    this.insight,
    this.replyToInsight,
    this.at,
    this.pointsSpent = 0,
    this.balanceAfter,
    this.replyQuota,
    this.failed = false,
    this.clientRequestId,
    this.paidAttempt = false,
    this.id,
    this.questionId,
    this.questionAt,
  });

  final ChatRole role;
  final String content;
  final List<String> sources; // 근거 공공 가이드라인 제목(코치 메시지에만)
  final bool pending;

  /// 앱이 스스로 띄운 말풍선이면 어떤 것인지. 서버 응답이면 null 이다.
  /// null 이 아니면 [content] 는 비어 있고 문구는 화면이 그린다.
  final ChatNotice? notice;

  /// 회원 메시지에서 찾은 통증·부정적 반응(#1824). 코치 답변이나 신호가 없으면 null.
  final ChatInsight? insight;

  /// 코치 답변에 실려 온 **방금 보낸 회원 메시지**의 감지 결과. 컨트롤러가 그 회원
  /// 메시지로 옮겨 붙인다(#1824). 저장된 대화에서는 늘 null 이다.
  final ChatInsight? replyToInsight;

  /// 주고받은 때. 저장된 대화는 서버가 준 값이고, 방금 보낸 것은 컨트롤러가
  /// 찍는다. 화면이 날짜 구분선과 말풍선 옆 시각을 이것으로 그린다(#1918).
  /// 앱이 스스로 띄운 말풍선(인사·실패 안내)에는 없다 — 주고받은 것이 아니다.
  final DateTime? at;

  /// 이 코치 답변에 쓴 포인트(#2145). 무료거나 AI 가 답하지 못했으면 0 이다.
  /// 0 보다 크면 답변 아래에 `−50P · 남은 포인트` 를 적는다.
  final int pointsSpent;

  /// 포인트를 쓴 뒤의 잔액. 모르면 null 이고 차감한 값만 적는다.
  final int? balanceAfter;

  /// 답에 실려 온 **보낸 뒤의 오늘 한도**. 컨트롤러가 입력칸 위 줄로 옮긴다 —
  /// [replyToInsight] 처럼 방금 받은 답에만 있고 저장된 대화에서는 늘 null 이다.
  final AiChatQuota? replyQuota;

  /// 보내지 못한 회원 메시지(#2846). 지우지 않고 남겨 `다시 보내기` 로 같은 키를
  /// 다시 보낸다.
  final bool failed;

  /// 이 메시지를 만든 전송의 멱등키(#2846). 다시 보낼 때 같은 키를 써야 서버가
  /// 이미 처리한 질문을 다시 세거나 차감하지 않는다.
  ///
  /// 서버도 저장한 질문과 답에 같은 값을 남겨 돌려준다(#3352) — 방금 보낸 말과
  /// 저장된 대화가 같은 전송인지는 본문이 아니라 이 값으로 가른다. 키 없이 보낸
  /// 전송이나 예전에 저장된 줄은 null 이다.
  final String? clientRequestId;

  /// 포인트로 보내기로 동의하고 보낸 메시지인가(#2846). 다시 보낼 때도 같게 보낸다.
  final bool paidAttempt;

  /// 서버가 준 메시지 식별자(#3352). 아직 서버에 저장되지 않았거나(보내는 중·
  /// 보내지 못함) 앱이 스스로 띄운 말풍선이면 null 이다.
  final String? id;

  /// 코치 답변에 실려 온 **방금 보낸 회원 메시지**의 식별자와 저장 시각(#3352).
  /// 컨트롤러가 그 회원 메시지로 옮겨 붙인다 — [replyToInsight] 처럼 방금 받은
  /// 답에만 있고 저장된 대화에서는 늘 null 이다.
  final String? questionId;
  final DateTime? questionAt;

  bool get isUser => role == ChatRole.user;

  /// 서버가 저장하며 준 식별자와 시각을 채운 사본(#3352). 주지 않은 값은 그대로 둔다.
  ChatMessage asStored({String? id, DateTime? at}) => ChatMessage(
    role: role,
    content: content,
    sources: sources,
    pending: pending,
    notice: notice,
    insight: insight,
    replyToInsight: replyToInsight,
    at: at ?? this.at,
    pointsSpent: pointsSpent,
    balanceAfter: balanceAfter,
    replyQuota: replyQuota,
    failed: failed,
    clientRequestId: clientRequestId,
    paidAttempt: paidAttempt,
    id: id ?? this.id,
  );

  /// 보내지 못한 상태로 바꾼 사본. 키와 포인트 여부를 함께 남긴다. (#2846)
  ChatMessage asFailed({
    required String clientRequestId,
    required bool paidAttempt,
  }) => ChatMessage(
    role: role,
    content: content,
    sources: sources,
    insight: insight,
    at: at,
    failed: true,
    clientRequestId: clientRequestId,
    paidAttempt: paidAttempt,
  );

  /// 주고받은 때만 채운 사본.
  ChatMessage withTime(DateTime value) => ChatMessage(
    role: role,
    content: content,
    sources: sources,
    pending: pending,
    notice: notice,
    insight: insight,
    replyToInsight: replyToInsight,
    at: value,
    pointsSpent: pointsSpent,
    balanceAfter: balanceAfter,
    replyQuota: replyQuota,
    failed: failed,
    clientRequestId: clientRequestId,
    paidAttempt: paidAttempt,
    id: id,
    questionId: questionId,
    questionAt: questionAt,
  );

  /// 감지 결과만 바꾼 사본.
  ChatMessage withInsight(ChatInsight? value) => ChatMessage(
    role: role,
    content: content,
    sources: sources,
    pending: pending,
    notice: notice,
    insight: value,
    at: at,
    pointsSpent: pointsSpent,
    balanceAfter: balanceAfter,
    failed: failed,
    clientRequestId: clientRequestId,
    paidAttempt: paidAttempt,
    id: id,
  );

  /// Request shape sent as chat history to the server (snake_case-safe).
  Map<String, Object?> toJson() => <String, Object?>{
    'role': isUser ? 'user' : 'coach',
    'content': content,
  };

  /// Parse a stored turn from `GET /ai-coach/messages` → `{ role, content, sources }`.
  factory ChatMessage.fromStored(Map<String, Object?> json) => ChatMessage(
    role: (json['role'] as String?) == 'user' ? ChatRole.user : ChatRole.coach,
    content: ((json['content'] as String?) ?? '').trim(),
    sources: <String>[
      for (final Object? s
          in (json['sources'] as List<Object?>?) ?? const <Object?>[])
        s.toString(),
    ],
    insight: ChatInsight.fromJson(json['insight']),
    // 서버 시각은 KST 벽시계로 읽는다 — 기기 시간대에 매이지 않게(#2876).
    at: _kstOrNull(json['created_at']),
    pointsSpent: (json['points_spent'] as num?)?.toInt() ?? 0,
    balanceAfter: (json['balance_after'] as num?)?.toInt(),
    // 식별자와 그 줄을 만든 전송의 키(#3352). 예전 서버는 주지 않는다.
    id: json['id'] as String?,
    clientRequestId: json['client_request_id'] as String?,
  );

  /// Parse a coach reply from `POST /ai-coach/chat` → `{ reply, sources }`.
  factory ChatMessage.coachFromReply(Map<String, Object?> json) => ChatMessage(
    role: ChatRole.coach,
    content: ((json['reply'] as String?) ?? '').trim(),
    sources: <String>[
      for (final Object? s
          in (json['sources'] as List<Object?>?) ?? const <Object?>[])
        s.toString(),
    ],
    replyToInsight: ChatInsight.fromJson(json['user_insight']),
    pointsSpent: (json['points_spent'] as num?)?.toInt() ?? 0,
    balanceAfter: (json['balance_after'] as num?)?.toInt(),
    replyQuota: json['quota'] is Map
        ? AiChatQuota.fromJson(
            (json['quota']! as Map<Object?, Object?>).cast<String, Object?>(),
          )
        : null,
    // 저장된 두 줄의 식별자·시각·키(#3352). 예전 서버는 주지 않는다 — 그때는
    // 컨트롤러가 받은 시각을 찍는다.
    id: json['reply_message_id'] as String?,
    at: _kstOrNull(json['reply_created_at']),
    questionId: json['user_message_id'] as String?,
    questionAt: _kstOrNull(json['user_created_at']),
    clientRequestId: json['client_request_id'] as String?,
  );

  /// 서버 시각 문자열을 KST 벽시계로. 없거나 읽지 못하면 null.
  static DateTime? _kstOrNull(Object? raw) =>
      switch (DateTime.tryParse(raw is String ? raw : '')) {
        final DateTime t => toKst(t),
        null => null,
      };
}
