import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// 이탈 위험 — PT 관리 신호 중 **관계가 끊기고 있다**는 신호로 판정한다. (#2364)
///
/// 예전에는 여기서 따로 여섯 가지(이번 주 운동 기록 없음·식단 중단·연속
/// 취소·노쇼·이행률 정체·미응답 메시지·트레이너 피드백 없음)를 세었다. 그래서
/// 주의 회원은 아홉 명인데 이탈 위험은 0명이거나, 트레이너 사정 취소 두 번이
/// 회원의 이탈 위험이 되거나, 회원 상태와 무관한 "미응답 + 피드백 없음" 만으로
/// 위험이 됐다. 이제 판정 재료는 회원 목록·상세와 같은 서버 신호
/// (`client_signals.py`)이고, 트레이너 쪽 사실은 "최근 트레이너 피드백 없음"
/// 하나만 곁들인다.
///
/// 아래 중 하나면 이탈 위험이다.
/// - `노쇼·취소 반복` — 약속 자체가 깨지고 있다.
/// - `기록 끊김` 이 [churnRecordGapDays] 일 이상 — 앱을 놓은 지 오래다.
/// - `기록 끊김` 에 최근 [churnLookbackDays] 일 트레이너 피드백 없음 —
///   회원도 트레이너도 서로를 들여다보지 않고 있다.
///
/// 기록 끊김 3~6일, 운동 목표 미달, 식단 신호, 통증은 `주의 회원` 이 말한다.
/// 둘을 같은 규칙으로 두면 카드가 둘일 까닭이 없다.
class ChurnRiskClient {
  /// Creates a flagged entry.
  const ChurnRiskClient({
    required this.client,
    required this.signals,
    required this.noRecentFeedback,
  });

  /// The client.
  final TrainerClient client;

  /// 이 회원의 PT 관리 신호(답장 대기 제외), 급한 순 — 회원 상세 헤더와 같다.
  final List<ClientSignal> signals;

  /// 최근 [churnLookbackDays] 일 안에 트레이너가 남긴 세션 피드백이 없는가.
  final bool noRecentFeedback;
}

/// "최근" 트레이너 피드백을 찾는 기간.
const int churnLookbackDays = 7;

/// 기록 끊김이 이만큼 길면 그 하나로 이탈 위험이다. 3~6일은 `주의 회원` 이다.
const int churnRecordGapDays = 7;

/// 최근 [churnLookbackDays] 일 안에, 완료 처리하며 메모를 남긴 세션이 있는가.
///
/// 세션 메모는 트레이너가 실제로 남기는 유일한 피드백 기록이다. [sessions] 는
/// 그 회원의 세션(공백 제외)이다.
bool hasRecentTrainerFeedback(
  List<ScheduleSession> sessions, {
  required DateTime now,
}) => sessions.any(
  (s) =>
      s.isDone &&
      s.note.trim().isNotEmpty &&
      _withinDays(s.date, now, churnLookbackDays),
);

bool _withinDays(String date, DateTime now, int days) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return false;
  return now.difference(parsed).inDays <= days;
}

/// [client] 가 이탈 위험인가 — 규칙은 이 파일 머리 주석.
bool isChurnRisk(TrainerClient client, {required bool noRecentFeedback}) {
  for (final ClientSignal s in client.signals) {
    switch (s.kind) {
      case ClientSignalKind.noShow:
        return true;
      case ClientSignalKind.recordGap:
        if ((s.days ?? 0) >= churnRecordGapDays || noRecentFeedback) {
          return true;
        }
      default:
        break;
    }
  }
  return false;
}

/// 로스터의 이탈 위험 목록. 신호가 많은 회원이 위, 같으면 이름순.
List<ChurnRiskClient> buildChurnRisk({
  required List<TrainerClient> clients,
  required Map<String, List<ScheduleSession>> recentSessionsByClient,
  required DateTime now,
}) {
  final result = <ChurnRiskClient>[];
  for (final client in clients) {
    if (!client.active) continue;
    final noRecentFeedback = !hasRecentTrainerFeedback(
      recentSessionsByClient[client.id] ?? const <ScheduleSession>[],
      now: now,
    );
    if (!isChurnRisk(client, noRecentFeedback: noRecentFeedback)) continue;
    result.add(
      ChurnRiskClient(
        client: client,
        signals: <ClientSignal>[
          for (final s in sortedSignals(client.signals))
            if (s.kind.isAttention) s,
        ],
        noRecentFeedback: noRecentFeedback,
      ),
    );
  }
  result.sort((a, b) {
    final byCount = b.signals.length.compareTo(a.signals.length);
    return byCount != 0 ? byCount : a.client.name.compareTo(b.client.name);
  });
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
