import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/ai_coach/data/repositories/dio_ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/repositories/ai_coach_repository.dart';

final aiCoachRepositoryProvider = Provider<AiCoachRepository>(
  (ref) => DioAiCoachRepository(ref.watch(dioProvider)),
  name: 'aiCoachRepository',
);

/// 홈 코칭 시트의 인사말과 카드.
///
/// 자동 해제되지 않는다 — 플로팅 버튼의 배지가 앱 수명 내내 읽는다. 그래서 식단·운동
/// 기록이 바뀐 때(`kDietChangeRefreshTargets`·`kExerciseChangeRefreshTargets`)와
/// 날이 바뀐 때(`kDayChangeRefreshTargets`)에 비워 새로 읽는다(#3351). 비운 횟수만큼
/// 모델을 부르지 않도록 서버가 회원별로 캐시하고 하루 생성 횟수를 묶는다.
final aiCoachStateProvider = FutureProvider<AiCoachState>((ref) {
  return ref.watch(aiCoachRepositoryProvider).fetchState();
}, name: 'aiCoachState');

/// AI 챗봇 감지 기록(최근 30일). 기록 창을 열 때마다 새로 읽는다(#1824).
final aiCoachInsightsProvider = FutureProvider.autoDispose<ChatInsightHistory>(
  (ref) => ref.watch(aiCoachRepositoryProvider).fetchInsights(),
  name: 'aiCoachInsights',
);
