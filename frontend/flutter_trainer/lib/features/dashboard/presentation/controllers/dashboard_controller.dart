import 'dart:async';

import 'package:flutter/foundation.dart';
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
final dashboardSummaryProvider =
    Provider.autoDispose<AsyncValue<DashboardSummary>>((ref) {
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
/// 남아 여러 테스트가 실패했다. [_firstValue] 로 첫 값만 받고 구독을 바로 끊어
/// 진짜 "한 번 조회"로 만든다.
final _churnRecentSessionsProvider =
    FutureProvider.autoDispose<List<ScheduleSession>>((ref) {
      final today = nowKst();
      final from = ymd(
        today.subtract(const Duration(days: _churnSessionLookbackDays)),
      );
      final to = ymd(today);
      final stream = ref.watch(scheduleRepositoryProvider).watchRange(from, to);
      return _firstValue(stream, onCancel: ref.onDispose);
    }, name: 'churnRecentSessions');

/// [stream] 의 첫 값 — 구독 해제가 끝나기를 기다리지 않는다. (#2891)
///
/// `Stream.first` 는 첫 값을 받은 뒤 **구독 해제 Future 가 끝나야** 값을
/// 돌려준다. drift 조회 스트림의 해제는 위젯 테스트의 가짜 시간 안에서 끝나지
/// 않아, 첫 값이 이미 왔는데도 이 provider 가 테스트 내내 로딩에 머물렀다 —
/// 예전에는 로딩을 빈 목록으로 바꿔 계산해 드러나지 않았다. 첫 값(또는
/// 오류)을 받는 즉시 끝내고, 해제는 뒤에서 마저 한다. provider 가 먼저
/// 버려지면 [onCancel] 로 구독을 끊는다.
Future<T> _firstValue<T>(
  Stream<T> stream, {
  required void Function(void Function() cb) onCancel,
}) {
  final completer = Completer<T>();
  var cancelled = false;
  late final StreamSubscription<T> subscription;
  void finish() {
    if (cancelled) return;
    cancelled = true;
    unawaited(subscription.cancel());
  }

  subscription = stream.listen(
    (value) {
      if (completer.isCompleted) return;
      completer.complete(value);
      finish();
    },
    onError: (Object error, StackTrace stackTrace) {
      if (completer.isCompleted) return;
      completer.completeError(error, stackTrace);
      finish();
    },
    onDone: () {
      if (completer.isCompleted) return;
      completer.completeError(StateError('No element'), StackTrace.current);
    },
  );
  onCancel(finish);
  return completer.future;
}

/// 이탈 위험·활동 피드백이 함께 쓰는 원자재(로스터·최근 세션).
///
/// `.autoDispose` 다 — [dashboardSummaryProvider] 는 그렇지 않아 앱이 켜져
/// 있는 내내 살아 있으므로, 대시보드 전용 데이터는 그쪽이 아니라 대시보드
/// 페이지가 직접 구독하는 이 provider에 둔다.
///
/// **둘 다 준비됐을 때만 값이다**(#2891). 예전에는 로딩·실패를 빈 목록으로
/// 바꿔 계산했는데, 세션이 비면 모든 회원이 "최근 트레이너 피드백 없음" 이
/// 되어 기록 공백이 하루라도 있는 회원이 전부 이탈 위험으로 잡혔다 — 조회가
/// 실패하거나 아직 오지 않은 동안 부풀린 숫자가 빨간색으로 떴다.
final _churnInputsProvider =
    Provider.autoDispose<
      AsyncValue<
        ({List<TrainerClient> clients, List<ScheduleSession> recentSessions})
      >
    >((ref) {
      final clients = ref.watch(clientsProvider);
      final sessions = ref.watch(_churnRecentSessionsProvider);
      return combineChurnInputs(clients, sessions);
    }, name: 'churnInputs');

/// 로스터·최근 세션 두 조회를 하나의 상태로 합친다. (#2891)
///
/// * 어느 한쪽이라도 실패했고 다시 읽는 중이 아니면 실패다.
/// * 세션을 (다시) 읽는 중이거나 어느 한쪽의 값이 아직 없으면 로딩이다 —
///   재시도 중에 지난 실패나 지난 숫자를 확정 값처럼 두지 않는다.
/// * 둘 다 값이 있을 때만 값이다.
@visibleForTesting
AsyncValue<
  ({List<TrainerClient> clients, List<ScheduleSession> recentSessions})
>
combineChurnInputs(
  AsyncValue<List<TrainerClient>> clients,
  AsyncValue<List<ScheduleSession>> sessions,
) {
  for (final AsyncValue<Object?> v in <AsyncValue<Object?>>[
    clients,
    sessions,
  ]) {
    if (v.hasError && !v.isLoading) {
      return AsyncError(v.error!, v.stackTrace ?? StackTrace.empty);
    }
  }
  if (sessions.isLoading || !sessions.hasValue || !clients.hasValue) {
    return const AsyncLoading();
  }
  return AsyncData((
    clients: clients.requireValue,
    recentSessions: sessions.requireValue,
  ));
}

/// 이탈 위험 신호를 다시 읽는다 — KPI 카드의 재시도. (#2891)
///
/// 로스터는 다른 화면도 함께 보는 스트림이라 건드리지 않고, 이 카드만 쓰는
/// 최근 세션 조회를 새로 한다. 로스터 조회가 실패했다면 대시보드 전체가
/// 이미 오류 화면이라 이 카드가 보이지 않는다.
///
/// `ref.invalidate`(위젯)나 `container.invalidate`(테스트)를 받는다.
void retryChurnInputs(void Function(ProviderOrFamily provider) invalidate) =>
    invalidate(_churnRecentSessionsProvider);

/// 이탈 위험 KPI 카드와 그 상세 다이얼로그가 함께 쓰는 목록.
///
/// 입력이 준비되지 않았거나 실패했으면 그 상태 그대로다(#2891) — 카드가
/// 숫자 대신 자리 표시·조회 실패를 그린다.
final dashboardChurnRiskProvider =
    Provider.autoDispose<AsyncValue<List<ChurnRiskClient>>>((ref) {
      return ref
          .watch(_churnInputsProvider)
          .whenData(
            (inputs) => buildChurnRisk(
              clients: inputs.clients,
              recentSessionsByClient: groupSessionsByClient(
                inputs.recentSessions,
              ),
              now: nowKst(),
            ),
          );
    }, name: 'dashboardChurnRisk');

/// "활동 피드백" 카드의 트레이너 활동 피드백 bullets.
///
/// 이탈 위험과 같은 입력이라 같은 이유로 준비될 때까지 값을 내지 않는다
/// (#2891) — 빈 세션으로 계산하면 "7일간 활동 없음" 같은 신호가 부풀려진다.
final dashboardActivityFeedbackProvider =
    Provider.autoDispose<AsyncValue<List<ActivityFeedbackItem>>>((ref) {
      return ref
          .watch(_churnInputsProvider)
          .whenData(
            (inputs) => buildActivityFeedback(
              clients: inputs.clients,
              recentSessionsByClient: groupSessionsByClient(
                inputs.recentSessions,
              ),
              now: nowKst(),
            ),
          );
    }, name: 'dashboardActivityFeedback');
