import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';

abstract class AiCoachRepository {
  Future<AiCoachState> fetchState();

  /// GET /ai-coach/messages — 서버에 저장된 이전 대화.
  ///
  /// 채팅을 열 때 불러 재접속·다른 기기에서도 대화가 이어지게 한다. 아직 나눈
  /// 대화가 없으면 빈 목록이다.
  Future<List<ChatMessage>> fetchHistory();

  /// Send a user message (+ prior turns) and get the coach's reply.
  ///
  /// 서버가 대화를 저장하므로 [history] 를 보내지 않아도 맥락이 이어진다. 서버에
  /// 저장분이 없을 때(목업으로 대화하다 실 서버로 전환한 경우)를 위해 계속 보낸다.
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
  });

  /// GET /ai-coach/insights — 최근 30일 동안 회원이 AI 챗봇에 쓴 메시지의
  /// 통증·부정적 반응 감지 기록(최신순). 트레이너 채팅 감지와 같은 규칙이다(#1824).
  Future<ChatInsightHistory> fetchInsights();
}
