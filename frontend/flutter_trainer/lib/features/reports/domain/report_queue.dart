import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show weekdayCount;
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// 작업대의 한 줄이 다는 신호 — **운동 쪽 사실만** 담는다.
///
/// 식단 지표(칼로리·나트륨·당류)는 여기 오지 않는다. 이 목록이 답하는 질문은
/// "이 회원의 리포트를 왜 먼저 열어야 하나" 이고, 그 답은 훈련이 어떻게
/// 굴러갔는가다 — 식단은 리포트 본문의 식단 카드가 따로 말한다. (#2232)
enum ReportSignalKind {
  /// 이행률.
  completion,

  /// 예약한 PT 를 빠졌다.
  noShow,

  /// 예약한 PT 를 전부 소화했다.
  sessionDone,

  /// 기록이 아예 없는 날이 여럿이다.
  silentDays,

  /// 주 후반이 앞쪽보다 크게 떨어졌다.
  slump,

  /// 주 후반이 앞쪽보다 크게 올랐다.
  rising,

  /// 이레 내내 기록이 있다.
  fullLog,

  /// 이번 주 수치가 아직 없는 회원 — 새로 붙었거나 첫 주다.
  onboarding,
}

/// 신호 하나. [value] 는 종류에 따라 퍼센트·날 수·횟수다.
class ReportSignal {
  /// Creates a signal.
  const ReportSignal(this.kind, [this.value = 0]);

  /// 무엇에 대한 신호인가.
  final ReportSignalKind kind;

  /// 그 신호가 든 수. 수가 필요 없는 종류는 0 이다.
  final int value;

  @override
  bool operator ==(Object other) =>
      other is ReportSignal && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'ReportSignal(${kind.name}, $value)';
}

/// 한 줄에 다는 신호 수. 넷째부터는 줄이 두 단으로 접혀 큐가 길어진다.
const int reportSignalLimit = 3;

/// 주 후반이 앞쪽과 이만큼(%p) 벌어지면 흐름이 바뀐 것으로 본다.
const int reportSignalSwingPoints = 15;

/// [report] 의 한 주를 신호로 옮긴다. 순서가 곧 화면 순서다.
List<ReportSignal> reportSignals(WeeklyReport report) {
  final List<int> week = report.weekCompletion;
  final List<int> logged = <int>[
    for (final int v in week)
      if (v > 0) v,
  ];
  final int? completion = report.completionAvg;
  if (completion == null && logged.isEmpty) {
    return const <ReportSignal>[ReportSignal(ReportSignalKind.onboarding)];
  }
  final signals = <ReportSignal>[];
  if (completion != null) {
    signals.add(ReportSignal(ReportSignalKind.completion, completion));
  }
  final int missed = report.sessionsBooked - report.sessionsDone;
  if (missed > 0) {
    signals.add(ReportSignal(ReportSignalKind.noShow, missed));
  }
  final int silent = week.length == weekdayCount
      ? week.where((v) => v == 0).length
      : 0;
  if (silent >= 2) {
    signals.add(ReportSignal(ReportSignalKind.silentDays, silent));
  }
  // 앞 사흘과 뒤 사흘을 견준다. 같은 이행률 70% 라도 오르는 주와 무너지는
  // 주는 다음 주에 할 말이 다르다.
  final double? front = _mean(week.take(3));
  final double? back = _mean(week.skip(4));
  if (front != null && back != null) {
    final double swing = back - front;
    if (swing <= -reportSignalSwingPoints) {
      signals.add(ReportSignal(ReportSignalKind.slump, swing.abs().round()));
    } else if (swing >= reportSignalSwingPoints) {
      signals.add(ReportSignal(ReportSignalKind.rising, swing.round()));
    }
  }
  if (silent == 0 && week.length == weekdayCount) {
    signals.add(const ReportSignal(ReportSignalKind.fullLog));
  }
  if (missed == 0 && report.sessionsBooked > 0) {
    signals.add(
      ReportSignal(ReportSignalKind.sessionDone, report.sessionsDone),
    );
  }
  return signals.take(reportSignalLimit).toList(growable: false);
}

double? _mean(Iterable<int> values) {
  final List<int> logged = <int>[
    for (final int v in values)
      if (v > 0) v,
  ];
  if (logged.isEmpty) return null;
  return logged.reduce((a, b) => a + b) / logged.length;
}

/// 작업대의 정렬 기준.
enum ReportQueueSort {
  /// 손이 필요한 회원이 위로 — 기본값.
  ///
  /// 트레이너가 리포트를 여덟 장 쓰는 날, 첫 장이 가장 집중해서 쓰는 장이다.
  /// 그 자리를 이름 가나다순 첫 회원이 아니라 **이번 주가 무너진 회원**이
  /// 가져가야 한다.
  priority,

  /// 이름 가나다순 — 특정 회원을 찾을 때.
  name,
}

/// 작업대에 서는 한 줄 — 한 회원의 이번 주.
class ReportQueueEntry {
  /// Creates an entry.
  const ReportQueueEntry({
    required this.client,
    required this.report,
    required this.sent,
  });

  /// 누구의 주인가.
  final TrainerClient client;

  /// 그 주의 리포트. 아직 못 읽었으면 null 이고, 줄은 수치 없이 선다 —
  /// 한 명을 못 읽었다고 나머지 일곱 명의 작업대가 비면 안 된다.
  final WeeklyReport? report;

  /// 이번 주 리포트를 이미 보냈는가.
  final bool sent;

  /// 이행률(%). 모르면 null.
  int? get completion => report?.completionAvg;

  /// 이 줄이 다는 신호. 수치를 못 읽었으면 비어 있다.
  List<ReportSignal> get signals {
    final WeeklyReport? r = report;
    return r == null ? const <ReportSignal>[] : reportSignals(r);
  }

  /// 우선 확인 점수 — **낮을수록 위**.
  ///
  /// 이행률이 낮을수록, 세션을 빠졌을수록, 기록이 끊긴 날이 많을수록 위로
  /// 온다. 아직 못 읽은 줄은 가운데에 둔다 — 맨 위로 올리면 불러오기 실패가
  /// 곧 "가장 급한 회원"이 되고, 맨 아래로 내리면 정말 급한 회원이 화면
  /// 밖으로 밀린다.
  ///
  /// 식단 수치는 점수에 넣지 않는다. 먼저 열 리포트를 고르는 기준은 훈련이
  /// 무너진 정도이고, 나트륨이 잦은 주가 운동을 못 한 주보다 급하지는
  /// 않다(#2232).
  int get priority {
    final WeeklyReport? r = report;
    if (r == null) return 50;
    int score = r.completionAvg ?? 50;
    // 예약한 세션을 빠진 주는 이행률과 무관하게 먼저 본다.
    if (r.sessionsBooked > r.sessionsDone) score -= 30;
    for (final ReportSignal s in reportSignals(r)) {
      score += switch (s.kind) {
        ReportSignalKind.silentDays => -6 * s.value,
        ReportSignalKind.slump => -10,
        ReportSignalKind.onboarding => 0,
        _ => 0,
      };
    }
    return score;
  }
}

/// [clients] 를 작업대 순서로 세운다.
///
/// [reports] 는 `회원 id → 그 주 리포트` 다. 비어 있어도 목록은 그대로
/// 선다 — 정렬만 이름순에 가까워진다.
List<ReportQueueEntry> buildReportQueue({
  required List<TrainerClient> clients,
  required Map<String, WeeklyReport> reports,
  required Set<String> sentIds,
  required ReportQueueSort sort,
}) {
  final entries = <ReportQueueEntry>[
    for (final TrainerClient c in clients)
      ReportQueueEntry(
        client: c,
        report: reports[c.id],
        sent: sentIds.contains(c.id),
      ),
  ];
  entries.sort((a, b) {
    if (sort == ReportQueueSort.name) {
      return a.client.name.compareTo(b.client.name);
    }
    final int byPriority = a.priority.compareTo(b.priority);
    // 점수가 같으면 이름으로 — 다시 그릴 때마다 순서가 뒤바뀌면 방금 보던
    // 줄이 어디로 갔는지 알 수 없다.
    return byPriority != 0
        ? byPriority
        : a.client.name.compareTo(b.client.name);
  });
  return entries;
}
