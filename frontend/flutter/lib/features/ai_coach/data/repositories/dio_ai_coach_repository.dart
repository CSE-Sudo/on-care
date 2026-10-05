import 'package:dio/dio.dart';

import 'package:oncare/features/ai_coach/domain/ai_coach_limits.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';

class DioAiCoachRepository implements AiCoachRepository {
  DioAiCoachRepository(this._dio);
  final Dio _dio;

  /// 채팅 응답 대기 시간. 전역 receiveTimeout(15초)으로는 모자란다.
  ///
  /// 코치 답변은 RAG 검색 + Gemini 생성이라 로컬 실측이 7.6~12.8초였다. 15초는
  /// 로컬에서도 여유가 2초뿐이고 배포 후 네트워크 지연이 붙으면 정기적으로 넘는다.
  /// 게다가 서버는 답변을 저장하므로, 앱만 타임아웃되면 사용자는 실패 메시지를 본
  /// 뒤 다음에 채팅을 열었을 때 **본 적 없는 답변**을 발견하게 된다.
  static const Duration _chatTimeout = Duration(seconds: 60);

  /// 코칭 피드백 응답 대기 시간. 전역 receiveTimeout(15초)으로는 모자란다.
  ///
  /// 서버는 식단·운동 코치를 차례로 두 번 부르고, 각 Gemini 호출의 상한이
  /// 30초다. 15초에서 앱이 먼저 끊으면 정상 응답도 실패가 되어 시트가 오류에
  /// 머문다(#2813). 두 호출의 상한에 네트워크 여유를 더한다.
  static const Duration feedbackTimeout = Duration(seconds: 75);

  @override
  Future<AiCoachState> fetchState() async {
    final res = await _dio.get<Map<String, Object?>>(
      '/ai-coach/feedback',
      options: Options(receiveTimeout: feedbackTimeout),
    );
    return AiCoachState.fromJson(res.data!);
  }

  @override
  Future<List<ChatMessage>> fetchHistory() async {
    final res = await _dio.get<Map<String, Object?>>('/ai-coach/messages');
    final raw = (res.data?['messages'] as List<Object?>?) ?? const <Object?>[];
    return <ChatMessage>[
      for (final Object? m in raw)
        ChatMessage.fromStored(m! as Map<String, Object?>),
    ];
  }

  @override
  Future<ChatMessage> sendMessage({
    required String message,
    required List<ChatMessage> history,
    bool payWithPoints = false,
    String? clientRequestId,
  }) async {
    final Response<Map<String, Object?>> res;
    try {
      res = await _dio.post<Map<String, Object?>>(
        '/ai-coach/chat',
        options: Options(receiveTimeout: _chatTimeout),
        data: <String, Object?>{
          'message': aiCoachMessagePayload(message),
          // 서버 한도(최근 20턴·턴당 2000자, #1549)에 맞춰 잘라 보낸다.
          'history': aiCoachHistoryPayload(history),
          'pay_with_points': payWithPoints,
          'client_request_id': ?clientRequestId,
        },
      );
    } on DioException catch (e) {
      throw _blocked(e.response?.data) ?? e;
    }
    return ChatMessage.coachFromReply(res.data!);
  }

  static AiChatBlocked? _blocked(Object? body) =>
      body is Map ? AiChatBlocked.fromDetail(body['detail']) : null;

  @override
  Future<AiChatQuota> fetchQuota() async {
    final res = await _dio.get<Map<String, Object?>>('/ai-coach/quota');
    return AiChatQuota.fromJson(res.data ?? const <String, Object?>{});
  }

  @override
  Future<ChatInsightHistory> fetchInsights() async {
    final res = await _dio.get<Map<String, Object?>>('/ai-coach/insights');
    return ChatInsightHistory.fromJson(res.data ?? const <String, Object?>{});
  }

  @override
  Future<void> dismissInsight(String messageId) async {
    await _dio.delete<Map<String, Object?>>('/ai-coach/insights/$messageId');
  }
}
