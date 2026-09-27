import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// A reason a client was flagged 이탈 위험 (churn risk), most-urgent-first
/// ordering is not implied here — a client can carry several at once.
enum ChurnSignal {
  /// 이번 주(월→오늘) 운동 기록 없음. 주가 [churnMinElapsedDays] 일 이상
  /// 지난 뒤에만 켜진다.
  noRecentWorkout,

  /// 최근 7일 트레이너 피드백(완료 세션 메모) 없음.
  noRecentFeedback,

  /// 가장 최근 두 예약이 연달아 취소 또는 노쇼로 끝남.
  consecutiveCancelOrNoShow,

  /// 이번 주 앞쪽에 기록이 있던 고객의 최근 식단 기록이 끊김.
  dietStopped,

  /// 목표 지표(이행률)가 낮은 수준에서 장기간 정체.
  goalStagnant,

  /// 답이 없는 메시지가 남아 있음.
  unresolvedRequest;

  /// Localized label for the churn-risk dialog chips.
  String label(AppLocalizations l) => switch (this) {
    ChurnSignal.noRecentWorkout => l.churnNoRecentWorkout,
    ChurnSignal.noRecentFeedback => l.churnNoRecentFeedback,
    ChurnSignal.consecutiveCancelOrNoShow => l.churnConsecutiveCancel,
    ChurnSignal.dietStopped => l.churnDietStopped,
    ChurnSignal.goalStagnant => l.churnGoalStagnant,
    ChurnSignal.unresolvedRequest => l.churnUnresolvedRequest,
  };
}

/// A client flagged as 이탈 위험, with every triggered [signals].
class ChurnRiskClient {
  /// Creates a flagged entry.
  const ChurnRiskClient({required this.client, required this.signals});

  /// The client.
  final TrainerClient client;

  /// Why they were flagged, unordered.
  final Set<ChurnSignal> signals;
}

/// How far back "최근" reaches for the 운동·피드백·상담 signals.
const int churnLookbackDays = 7;

/// Computes every triggered [ChurnSignal] for one client.
///
/// [recentSessions] is that client's own booked sessions (공백 제외) inside
/// the lookback window used by the caller — newest first. [unreadCount] is
/// this client's pending message count, the same value the KPI row's
/// 메시지 card and the `답장 대기` signal already use.
Set<ChurnSignal> computeChurnSignals(
  TrainerClient client, {
  required List<ScheduleSession> recentSessions,
  required int unreadCount,
  required DateTime now,
}) {
  final signals = <ChurnSignal>{};

  // 최근 운동 기록 없음 — 이번 주 이행률 계열에 기록된(0 초과) 요일이
  // 하나도 없으면 최근 활동이 없다고 본다. `client_alerts.dart` 의
  // "0 = 기록 없음" 규칙(recordedCompletionMean)과 같은 정의를 쓴다.
  //
  // 계열은 요일 고정 주(월→일)라 지난주가 보이지 않는다. 주 초에는 지난 날이
  // 하루·이틀뿐이어서, 지난주 내내 운동한 회원도 월요일 아침이면 "기록 없음"
  // 이 된다. 그래서 이번 주가 [churnMinElapsedDays] 일 이상 지난 뒤에만 본다.
  if (elapsedWeekDays(now) >= churnMinElapsedDays &&
      recordedCompletionMean(client) == null) {
    signals.add(ChurnSignal.noRecentWorkout);
  }

  // 최근 7일 트레이너 피드백 없음 — 완료 처리하며 메모를 남긴 세션이 창
  // 안에 하나도 없으면 트레이너가 최근 이 고객을 들여다보지 않은 것으로
  // 본다. 세션 메모는 트레이너가 실제로 남기는 유일한 피드백 기록이다.
  final hasRecentFeedback = recentSessions.any(
    (s) =>
        s.isDone &&
        s.note.trim().isNotEmpty &&
        _withinDays(s.date, now, churnLookbackDays),
  );
  if (!hasRecentFeedback) {
    signals.add(ChurnSignal.noRecentFeedback);
  }

  // PT 2회 연속 취소/노쇼 — 예약 순서상 가장 최근 두 건(공백 제외, 예정
  // 제외)이 둘 다 취소나 노쇼면 관계가 흔들린 신호로 본다.
  final finished =
      recentSessions.where((s) => s.isFinished).toList(growable: false)..sort(
        (a, b) => '${b.date} ${b.time}'.compareTo('${a.date} ${a.time}'),
      );
  if (finished.length >= 2 &&
      (finished[0].isCancelled || finished[0].isNoShow) &&
      (finished[1].isCancelled || finished[1].isNoShow)) {
    signals.add(ChurnSignal.consecutiveCancelOrNoShow);
  }

  // 식단 기록 중단 — 이번 주 지난 날 중 앞쪽에 기록이 있던 고객의 최근
  // [dietStopRecentDays] 일 칼로리·나트륨이 모두 0 이면 "중단"으로 본다.
  // 처음부터 기록이 없던 고객은 대상이 아니다 — 그건 이 신호가 아니라 애초의
  // 미사용이다.
  if (dietRecentlyStopped(client, now: now)) {
    signals.add(ChurnSignal.dietStopped);
  }

  // 목표 지표 장기간 정체 — 이번 주 기록된 이행률이 낮은 수준에서 거의
  // 그대로다. 여러 주 이력을 갖고 있지 않아 정확한 추세는 볼 수 없으므로
  // 이번 주 안에서의 근사치다.
  if (goalStagnant(client, now: now)) {
    signals.add(ChurnSignal.goalStagnant);
  }

  // 상담·메시지 미응답 — 이 고객이 보낸 메시지에 아직 답하지 않았다.
  if (unreadCount > 0) {
    signals.add(ChurnSignal.unresolvedRequest);
  }

  return signals;
}

bool _withinDays(String date, DateTime now, int days) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return false;
  return now.difference(parsed).inDays <= days;
}

/// [TrainerClient.caloriesWeek]·[TrainerClient.sodiumWeek]·
/// [TrainerClient.weekCompletion] 의 길이. 서버(`trainer_service.py`
/// `_daily_week`)와 데모 시드(`_onWeekdays`) 모두 **이번 주 월→일** 고정
/// 창을 주고, 아직 오지 않은 요일은 0 으로 채운다 — 오늘 기준 롤링 7일이
/// 아니다.
const int weekdayCountForChurn = 7;

/// 이번 주 지난 날이 이만큼은 돼야 "최근 끊김·기록 없음"을 판단한다.
///
/// 요일 고정 창은 지난주를 담지 않는다. 월·화에는 볼 수 있는 날이 한두
/// 날뿐이라, 이때 판정하면 주말에 쉰 회원이 전부 걸린다.
const int churnMinElapsedDays = 3;

/// 식단 끊김을 볼 최근 날 수(오늘 포함). 그보다 앞선 지난 날에 기록이
/// 있어야 "끊김"이다 — 그래서 식단 판정은 목요일부터 가능하다.
const int dietStopRecentDays = 3;

/// 이번 주(월→일)에서 오늘까지 지난 날 수, 오늘 포함 — 월=1 … 일=7.
///
/// [now] 는 KST 벽시계(`nowKst()`)여야 한다. 서버가 주를 KST 로 자르므로
/// 기기 로컬 시간을 넣으면 KST 자정 부근에 하루가 어긋난다.
int elapsedWeekDays(DateTime now) => now.weekday;

/// [week] 에서 아직 오지 않은 요일을 잘라 낸 앞부분(월→오늘).
List<int> _elapsedOf(List<int> week, DateTime now) =>
    week.take(elapsedWeekDays(now)).toList(growable: false);

/// 이번 주 앞쪽에 식단 기록이 있다가 최근 [dietStopRecentDays] 일(오늘
/// 포함) 칼로리·나트륨이 모두 0 인지.
///
/// 계열은 월→일 고정 창이라 미래 요일이 0 이다. 그 0 을 "끊김"으로 읽지
/// 않도록 지난 날(월→오늘)만 본다. 앞쪽 비교 구간이 하루도 없는 월~수는
/// 판단하지 않는다.
bool dietRecentlyStopped(TrainerClient client, {required DateTime now}) {
  final calories = client.caloriesWeek;
  final sodium = client.sodiumWeek;
  if (calories.length != weekdayCountForChurn ||
      sodium.length != weekdayCountForChurn) {
    return false;
  }
  final elapsed = elapsedWeekDays(now);
  final earlierCount = elapsed - dietStopRecentDays;
  if (earlierCount < 1) return false;

  final pastCalories = _elapsedOf(calories, now);
  final pastSodium = _elapsedOf(sodium, now);
  final hadEarlierRecord =
      pastCalories.take(earlierCount).any((v) => v > 0) ||
      pastSodium.take(earlierCount).any((v) => v > 0);
  final recentlyEmpty =
      pastCalories.skip(earlierCount).every((v) => v == 0) &&
      pastSodium.skip(earlierCount).every((v) => v == 0);
  return hadEarlierRecord && recentlyEmpty;
}

/// 이번 주 지난 날(월→오늘) 중 기록된 이행률이 3일 이상이고, 평균 50%
/// 미만에서 폭 15%p 이내로 머무는지.
///
/// 0 은 "기록 없음"이라 빼므로 미래 요일의 0 은 원래 섞이지 않는다. 그래도
/// 창 모양에 기대지 않도록 아직 오지 않은 요일은 먼저 잘라 낸다.
bool goalStagnant(TrainerClient client, {required DateTime now}) {
  final recorded = _elapsedOf(
    client.weekCompletion,
    now,
  ).where((d) => d > 0).toList(growable: false);
  if (recorded.length < 3) return false;
  final mean = recorded.reduce((a, b) => a + b) / recorded.length;
  final spread =
      recorded.reduce((a, b) => a > b ? a : b) -
      recorded.reduce((a, b) => a < b ? a : b);
  return mean < 50 && spread <= 15;
}

/// Whether [signals] amount to 이탈 위험.
///
/// 연속 취소/노쇼는 그 자체로 관계가 끊기고 있다는 강한 행동 신호라 혼자서도
/// 위험으로 본다. 나머지 다섯은 부드러운 신호라 최소 두 가지가 겹쳐야
/// "위험" 이지, 그렇지 않으면 나트륨을 하루 넘긴 고객까지 전부 이탈
/// 위험으로 잡혀 카드가 소음이 된다.
bool isChurnRisk(Set<ChurnSignal> signals) =>
    signals.contains(ChurnSignal.consecutiveCancelOrNoShow) ||
    signals.length >= 2;

/// Builds the roster's 이탈 위험 list from grouped session history, worst
/// (most reasons) first.
List<ChurnRiskClient> buildChurnRisk({
  required List<TrainerClient> clients,
  required Map<String, List<ScheduleSession>> recentSessionsByClient,
  required Map<String, int> unread,
  required DateTime now,
}) {
  final result = <ChurnRiskClient>[];
  for (final client in clients) {
    if (!client.active) continue;
    final signals = computeChurnSignals(
      client,
      recentSessions:
          recentSessionsByClient[client.id] ?? const <ScheduleSession>[],
      unreadCount: unread[client.id] ?? 0,
      now: now,
    );
    if (isChurnRisk(signals)) {
      result.add(ChurnRiskClient(client: client, signals: signals));
    }
  }
  result.sort((a, b) => b.signals.length.compareTo(a.signals.length));
  return result;
}

/// Groups a flat session list (as [ScheduleRepository.watchRange] returns)
/// by client id, dropping gaps and rows with no client.
Map<String, List<ScheduleSession>> groupSessionsByClient(
  List<ScheduleSession> sessions,
) {
  final grouped = <String, List<ScheduleSession>>{};
  for (final session in sessions) {
    final clientId = session.clientId;
    if (clientId == null || session.isGap) continue;
    (grouped[clientId] ??= <ScheduleSession>[]).add(session);
  }
  return grouped;
}
