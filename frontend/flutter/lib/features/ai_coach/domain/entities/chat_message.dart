import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';

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

  bool get isUser => role == ChatRole.user;

  /// 감지 결과만 바꾼 사본.
  ChatMessage withInsight(ChatInsight? value) => ChatMessage(
    role: role,
    content: content,
    sources: sources,
    pending: pending,
    notice: notice,
    insight: value,
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
  );
}
