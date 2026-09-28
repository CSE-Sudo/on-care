import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show weekdayCount;
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// 작업대의 한 줄이 다는 **리포트 고유** 신호 — 그 주의 흐름만 담는다.
///
/// 회원의 상태(기록 끊김·노쇼·취소·통증 등)는 여기서 판정하지 않는다. 그건
/// 회원 목록·상세·메시지가 쓰는 PT 관리 신호([reportAttentionSignals])가
/// 말하고, 작업대도 그 배지를 그대로 단다(#2344). 예전에는 여기서 `N일 무기록`·
/// `노쇼 N회` 를 따로 셌는데, 같은 회원이 목록에서는 `기록 끊김` 이 아니고
/// 리포트에서는 `무기록` 이었고, 노쇼는 아직 하지 않은 예정 세션까지 셌다(#2343).
///
/// 식단 지표(칼로리·나트륨·당류)는 여기 오지 않는다. 이 목록이 답하는 질문은
/// "이 회원의 리포트를 왜 먼저 열어야 하나" 이고, 그 답은 훈련이 어떻게
/// 굴러갔는가다 — 식단은 리포트 본문의 식단 카드가 따로 말한다. (#2232)
enum ReportSignalKind {
  /// 이행률.
  completion,

  /// 예약한 PT 를 전부 소화했다.
  sessionDone,

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
  final int silent = week.length == weekdayCount
      ? week.where((v) => v == 0).length
      : 0;
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
  if (report.sessionsBooked > 0 &&
      report.sessionsDone == report.sessionsBooked) {
    signals.add(
      ReportSignal(ReportSignalKind.sessionDone, report.sessionsDone),
    );
  }
  return signals.take(reportSignalLimit).toList(growable: false);
}

/// 작업대 줄이 다는 PT 관리 신호 — 회원 상세 헤더와 **같은 신호·같은 순서**.
///
/// 판정은 서버(`client_signals.py`)가 하고 여기서는 고르기만 한다. 운동·몸
/// 상태 쪽(통증·불편, 기록 끊김, 노쇼·취소, 배정 루틴 미수행, 운동 목표 미달)만
/// 남긴다 — 칼로리·단백질은 작업대가 운동 쪽 사실만 적는다는 결정(#2232)을
/// 따라 빼고, 답장 대기는 리포트와 무관한 받은편지함이라 뺀다.
List<ClientSignal> reportAttentionSignals(TrainerClient client) =>
    <ClientSignal>[
      for (final ClientSignal s in sortedSignals(client.signals))
        if (s.kind.isAttention && !s.kind.isDiet) s,
    ];

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

  /// 이름 역순 — 회원 탭 정렬과 같은 세 가지를 두어 탭마다 고를 수 있는 것이
  /// 달라지지 않게 한다(#2398).
  nameDescending,
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

  /// 이 줄이 다는 리포트 고유 신호. 수치를 못 읽었으면 비어 있다.
  List<ReportSignal> get signals {
    final WeeklyReport? r = report;
    return r == null ? const <ReportSignal>[] : reportSignals(r);
  }

  /// 이 줄이 다는 PT 관리 신호 — 로스터에서 오므로 리포트를 못 읽어도 있다.
  List<ClientSignal> get attention => reportAttentionSignals(client);

  /// 우선 확인 점수 — **낮을수록 위**.
  ///
  /// 이행률이 낮을수록, PT 관리 신호가 걸렸을수록 위로 온다. 아직 못 읽은
  /// 줄은 이행률 자리를 가운데(50)로 둔다 — 맨 위로 올리면 불러오기 실패가
  /// 곧 "가장 급한 회원"이 되고, 맨 아래로 내리면 정말 급한 회원이 화면
  /// 밖으로 밀린다. PT 관리 신호는 리포트와 무관하게 로스터에 있으므로 그때도
  /// 셈에 넣는다.
  ///
  /// 식단 수치는 점수에 넣지 않는다. 먼저 열 리포트를 고르는 기준은 훈련이
  /// 무너진 정도이고, 나트륨이 잦은 주가 운동을 못 한 주보다 급하지는
  /// 않다(#2232).
  int get priority {
    final WeeklyReport? r = report;
    int score = r?.completionAvg ?? 50;
    for (final ClientSignal s in attention) {
      score += switch (s.kind) {
        // 몸이 아프다는 말과 반복된 노쇼·취소는 이행률과 무관하게 먼저 본다.
        ClientSignalKind.discomfort || ClientSignalKind.noShow => -30,
        // 끊긴 날이 길수록 위로 — 한 주(7일)를 넘으면 더 가르지 않는다.
        ClientSignalKind.recordGap => -6 * (s.days ?? 3).clamp(0, weekdayCount),
        _ => -10,
      };
    }
    if (r != null &&
        reportSignals(r).any((s) => s.kind == ReportSignalKind.slump)) {
      score -= 10;
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
    switch (sort) {
      case ReportQueueSort.name:
        return a.client.name.compareTo(b.client.name);
      case ReportQueueSort.nameDescending:
        return b.client.name.compareTo(a.client.name);
      case ReportQueueSort.priority:
        break;
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

/// 전송 완료 목록의 순서 (#2447).
///
/// 미전송 목록과 같은 세 갈래다. 보낸 줄에서 먼저 볼 것은 **아직 안 읽은
/// 회원**이라 그 순서가 기본이다.
enum ReportSentSort {
  /// 안 읽은 회원이 위로 — 기본값. 같은 무리 안에서는 이름순.
  unreadFirst,

  /// 이름 가나다순.
  name,

  /// 이름 역순.
  nameDescending,
}

/// 전송 완료 줄 [done] 을 [sort] 순서로 세운 새 목록.
///
/// [records] 는 `회원 id → 그 주 전송 기록` 이다. 기록이 없는 줄(방금 보내
/// 이력이 아직 안 온 줄)은 열람 여부를 모르므로 읽은 줄과 같이 둔다 — 안
/// 읽었다고 단정해 위로 올리지 않는다.
List<ReportQueueEntry> sortSentEntries(
  List<ReportQueueEntry> done, {
  required Map<String, ReportSendRecord> records,
  required ReportSentSort sort,
}) {
  bool unread(ReportQueueEntry e) => records[e.client.id]?.read == false;
  final List<ReportQueueEntry> sorted = List<ReportQueueEntry>.of(done);
  sorted.sort((a, b) {
    switch (sort) {
      case ReportSentSort.name:
        return a.client.name.compareTo(b.client.name);
      case ReportSentSort.nameDescending:
        return b.client.name.compareTo(a.client.name);
      case ReportSentSort.unreadFirst:
        final bool ua = unread(a);
        final bool ub = unread(b);
        if (ua != ub) return ua ? -1 : 1;
        return a.client.name.compareTo(b.client.name);
    }
  });
  return sorted;
}
