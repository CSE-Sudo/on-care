import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/dashboard/domain/activity_feedback.dart';
import 'package:oncare_trainer/features/dashboard/domain/churn_risk.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

/// The 대시보드's aggregated numbers.
///
/// Composed on the client from the streams the other tabs already
/// subscribe to ([prioritizedClientsProvider], [unreadCountsProvider])
/// rather than a dedicated `/trainer/summary` endpoint: with a roster of
/// this size the aggregation is free, and one fewer endpoint is one
/// fewer thing to keep in sync. If the roster ever grows past a few
/// hundred, move [buildDashboardSummary] behind a server call.
///
/// Unread counts are folded in as a plain value (not awaited): the
/// roster is what gates the dashboard, and a still-loading unread map
/// just means the 답장 필요 count starts at 0 and fills in.
final dashboardSummaryProvider = Provider<AsyncValue<DashboardSummary>>((ref) {
  final clients = ref.watch(prioritizedClientsProvider);
  final unread =
      ref.watch(unreadCountsProvider).valueOrNull ?? const <String, int>{};
  return clients.whenData(
    (list) => buildDashboardSummary(clients: list, unread: unread),
  );
});

/// 이탈 위험 신호(연속 취소/노쇼, 최근 세션 메모)를 찾아볼 창. 신호 자체는
/// 7일치만 보지만, "가장 최근 두 예약"을 찾으려면 그보다 넓게 봐야 하는
/// 저빈도 고객도 있어 30일로 잡는다.
const int _churnSessionLookbackDays = 30;

/// 이탈 위험·활동 피드백에 쓸 세션 히스토리 — **한 번만** 읽는다.
///
/// [ScheduleRepository.watchRange] 는 외부(회원 앱) 예약 변경을 잡으려고
/// 5초마다 다시 읽는 스트림이다(`DioScheduleRepository._live(pollExternal:
/// true)`) — 주간 캘린더처럼 화면에 늘 보이는 곳에는 맞지만, 이탈 위험은 그런
/// 실시간성이 필요 없다. 그 스트림을 그대로 구독해 뒀더니 대시보드를 떠나도
/// (또는 다른 화면의 실서버 모드 위젯 테스트에서 대시보드가 배경에 잠깐
/// 그려지기만 해도) 5초 타이머가 계속 돌아, 위젯 트리를 지운 뒤에도 타이머가
/// 남아 여러 테스트가 실패했다. `.first` 로 첫 값만 받고 구독을 바로 끊어
/// 진짜 "한 번 조회"로 만든다.
final _churnRecentSessionsProvider =
    FutureProvider.autoDispose<List<ScheduleSession>>((ref) {
      final today = nowKst();
      final from = ymd(
        today.subtract(const Duration(days: _churnSessionLookbackDays)),
      );
      final to = ymd(today);
      return ref.watch(scheduleRepositoryProvider).watchRange(from, to).first;
    }, name: 'churnRecentSessions');

/// 이탈 위험·활동 피드백이 함께 쓰는 원자재(로스터·안 읽음·최근 세션).
///
/// `.autoDispose` 다 — [dashboardSummaryProvider] 는 그렇지 않아 앱이 켜져
/// 있는 내내 살아 있으므로, 대시보드 전용 데이터는 그쪽이 아니라 대시보드
/// 페이지가 직접 구독하는 이 provider에 둔다.
final _churnInputsProvider =
    Provider.autoDispose<
      ({
        List<TrainerClient> clients,
        Map<String, int> unread,
        List<ScheduleSession> recentSessions,
      })
    >((ref) {
      final clients =
          ref.watch(clientsProvider).valueOrNull ?? const <TrainerClient>[];
      final unread =
          ref.watch(unreadCountsProvider).valueOrNull ?? const <String, int>{};
      final recentSessions =
          ref.watch(_churnRecentSessionsProvider).valueOrNull ??
          const <ScheduleSession>[];
      return (clients: clients, unread: unread, recentSessions: recentSessions);
    }, name: 'churnInputs');

/// 이탈 위험 KPI 카드와 그 상세 다이얼로그가 함께 쓰는 목록.
final dashboardChurnRiskProvider = Provider.autoDispose<List<ChurnRiskClient>>((
  ref,
) {
  final inputs = ref.watch(_churnInputsProvider);
  return buildChurnRisk(
    clients: inputs.clients,
    recentSessionsByClient: groupSessionsByClient(inputs.recentSessions),
    unread: inputs.unread,
    now: nowKst(),
  );
}, name: 'dashboardChurnRisk');

/// "활동 피드백" 카드의 트레이너 활동 피드백 bullets.
final dashboardActivityFeedbackProvider =
    Provider.autoDispose<List<ActivityFeedbackItem>>((ref) {
      final inputs = ref.watch(_churnInputsProvider);
      return buildActivityFeedback(
        clients: inputs.clients,
        recentSessionsByClient: groupSessionsByClient(inputs.recentSessions),
        unread: inputs.unread,
        now: nowKst(),
      );
    }, name: 'dashboardActivityFeedback');
