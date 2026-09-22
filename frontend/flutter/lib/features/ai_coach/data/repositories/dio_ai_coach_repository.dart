import 'package:dio/dio.dart';

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

  @override
  Future<AiCoachState> fetchState() async {
    final res = await _dio.get<Map<String, Object?>>('/ai-coach/feedback');
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
          'message': message,
          'history': <Map<String, Object?>>[
            for (final m in history) m.toJson(),
          ],
          'pay_with_points': payWithPoints,
          'client_request_id': ?clientRequestId,
        },
      );
    } on DioException catch (e) {
      throw _blocked(e.response?.data) ?? e;
    }
    // 목업 인터셉터가 만든 응답은 상태코드 검사를 거치지 않고 그대로 돌아온다 —
    // 한도 거절도 여기서 실서버와 같은 예외로 바꾼다(#2145).
    if ((res.statusCode ?? 200) >= 400) {
      throw _blocked(res.data) ??
          DioException.badResponse(
            statusCode: res.statusCode!,
            requestOptions: res.requestOptions,
            response: res,
          );
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
