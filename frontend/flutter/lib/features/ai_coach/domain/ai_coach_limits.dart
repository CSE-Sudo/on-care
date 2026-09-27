import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';

/// AI 코치 요청 크기 한도(#1549). 서버 `ChatRequest` 와 같은 값이다.
///
/// 서버는 이 값을 넘는 요청을 provider 를 부르기 전에 422 로 거절한다. 앱이
/// 먼저 맞춰 보내야 회원이 쓴 대화가 한도 때문에 실패하지 않는다.
abstract final class AiCoachLimits {
  /// 질문 한 건의 최대 글자 수. 입력칸이 이 이상 받지 않는다.
  static const int messageMaxLength = 1000;

  /// `history` 로 보내는 최대 턴 수. 최근 턴부터 남긴다.
  static const int historyMaxTurns = 20;

  /// `history` 한 턴의 최대 글자 수. 코치 답변이 이보다 길면 앞부분만 보낸다.
  static const int turnMaxLength = 2000;
}

/// 서버로 보낼 `history` — 최근 [AiCoachLimits.historyMaxTurns] 턴만, 각 턴은
/// [AiCoachLimits.turnMaxLength] 글자까지.
///
/// 화면의 대화는 그대로 두고 **보내는 것만** 자른다. 서버는 저장된 대화를 먼저
/// 쓰고 이 값은 저장분이 없을 때만 쓰며, 프롬프트에는 최근 몇 턴만 들어가므로
/// 오래된 턴을 빼도 답이 달라지지 않는다.
List<Map<String, Object?>> aiCoachHistoryPayload(List<ChatMessage> history) {
  final int start = history.length > AiCoachLimits.historyMaxTurns
      ? history.length - AiCoachLimits.historyMaxTurns
      : 0;
  return <Map<String, Object?>>[
    for (final ChatMessage m in history.sublist(start))
      <String, Object?>{
        ...m.toJson(),
        'content': _clip(m.content, AiCoachLimits.turnMaxLength),
      },
  ];
}

/// 서버로 보낼 질문 — [AiCoachLimits.messageMaxLength] 코드 포인트까지.
///
/// 입력칸은 화면에 보이는 글자(자소 묶음) 기준으로 막아, 여러 코드 포인트로 된
/// 이모지를 섞으면 서버가 세는 길이가 한도를 조금 넘을 수 있다. 그 요청이 422 로
/// 통째 실패하지 않게 마지막에 한 번 더 맞춘다.
String aiCoachMessagePayload(String message) =>
    _clip(message, AiCoachLimits.messageMaxLength);

/// [text] 를 [max] 글자(서버가 세는 유니코드 코드 포인트)까지 자른다.
String _clip(String text, int max) {
  final List<int> runes = text.runes.toList();
  if (runes.length <= max) return text;
  return String.fromCharCodes(runes.take(max));
}
