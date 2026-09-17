import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/ai_coach/domain/chat_insight_detector.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';

class MockAiCoachRepository implements AiCoachRepository {
  MockAiCoachRepository();

  /// 이 세션에 회원이 보낸 메시지 — 감지 기록을 계산할 원문이다(#1824).
  final List<({String id, DateTime at, String text})> _sent =
      <({String id, DateTime at, String text})>[];

  @override
  Future<List<ChatMessage>> fetchHistory() async {
    // 목업/데모 모드는 서버에 저장된 대화가 없다. 빈 목록을 주면 채팅이 지금처럼
    // welcome 메시지 하나로 시작한다(데모 화면 불변).
    return const <ChatMessage>[];
  }

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _sent.add((
      id: 'mock-user-${_sent.length + 1}',
      at: nowKst(),
      text: message,
    ));
    return ChatMessage(
      role: ChatRole.coach,
      content: '기록을 보고 도와드릴게요. 식단·운동에 대해 더 구체적으로 물어봐 주세요.',
      replyToInsight: detectChatInsight(message),
    );
  }

  /// 회원이 치운 줄. 실서버의 `insight_dismissed` 에 해당한다(#1975).
  final Set<String> _dismissed = <String>{};

  @override
  Future<void> dismissInsight(String messageId) async {
    _dismissed.add(messageId);
  }

  @override
  Future<ChatInsightHistory> fetchInsights() async {
    final DateTime now = nowKst();
    return ChatInsightHistory(
      records: <ChatInsightRecord>[
        for (final sent in _sent.reversed)
          if (!_dismissed.contains(sent.id))
            if (isWithinInsightWindow(sent.at, now))
            if (detectChatInsight(sent.text) case final ChatInsight insight)
              ChatInsightRecord(
                messageId: sent.id,
                createdAt: sent.at,
                insight: insight,
                text: sent.text,
              ),
      ],
    );
  }

  @override
  Future<AiCoachState> fetchState() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return const AiCoachState(
      greeting: '안녕하세요, 오늘 컨디션은 어떠세요?',
      suggestions: <AiSuggestion>[
        AiSuggestion(
          tag: AiSuggestionTag.diet,
          title: '점심에 단백질을 +10g 추가해 보세요',
          body: '오전 운동량을 보면 점심에 단백질을 조금 더 채우는 것이 좋아요.',
        ),
        AiSuggestion(
          tag: AiSuggestionTag.exercise,
          title: '저녁 산책 15분',
          body: '저녁 시간대 가벼운 유산소는 수면의 질도 함께 끌어올립니다.',
        ),
        AiSuggestion(
          tag: AiSuggestionTag.hydration,
          title: '수분 보충',
          body: '오늘 평소보다 활동량이 많았어요. 물 한 컵 더 마셔봐요.',
        ),
      ],
    );
  }
}
