import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

export 'package:oncare_trainer/shared/models/client_alerts.dart'
    show AttentionClient, ClientAlert, alertSeverity, lowCompletionThreshold;

/// Weekday labels for the 주간 이행률 chart, in the current locale.
/// [TrainerClient.weekCompletion] is indexed 월→일, matching
/// `DateTime.weekday` (월=1 … 일=7) minus one.
///
/// 함수인 이유: const 리스트로 두면 생성 시점에 로케일을 알 수 없다. (#501)
/// 주간 시리즈의 길이(월~일). 라벨과 달리 로케일과 무관한 숫자라 상수로 둔다.
const int weekdayCount = 7;

List<String> weekdayLabels(AppLocalizations l) => <String>[
  l.weekdayMon,
  l.weekdayTue,
  l.weekdayWed,
  l.weekdayThu,
  l.weekdayFri,
  l.weekdaySat,
  l.weekdaySun,
];

/// How many weekday slots of the current (월-start) week have actually
/// happened, counting today: 월요일이면 1, 목요일이면 4.
///
/// Everything that renders or averages a Mon–Sun series for *this* week
/// clips at this index. Without it a chart drawn on Thursday still shows
/// Fri/Sat/Sun, and whatever the source happens to hold for those days —
/// a seeded value, or a zero — reads as a real result.
int elapsedWeekdays(DateTime today) => today.weekday;

/// Everything the 대시보드 renders, derived from the same streams the
/// other tabs already use — no dedicated summary endpoint.
///
/// Kept as a plain value object built by [buildDashboardSummary] so the
/// aggregation rules (what counts as "주의", how the weekly average is
/// computed) are unit-testable without pumping a widget.
class DashboardSummary {
  /// Creates a summary.
  const DashboardSummary({
    required this.activeClients,
    required this.totalClients,
    required this.unreadTotal,
    required this.unreadClients,
    required this.attention,
    required this.weeklyCompletion,
    this.healthAttentionCount = 0,
  });

  /// Clients currently marked 활성.
  final int activeClients;

  /// Roster size.
  final int totalClients;

  /// Unread messages across all threads.
  final int unreadTotal;

  /// How many clients are waiting on a reply.
  final int unreadClients;

  /// Clients with something to act on today, most urgent first — health
  /// signals then unanswered messages.
  final List<AttentionClient> attention;

  /// 주의 회원 KPI — PT 관리 신호가 있는 회원 수([needsAttention], #2204).
  ///
  /// 이 카드를 누르면 회원 목록의 `주의 회원` 으로 간다. 그 목록과 **같은
  /// 규칙**으로 세야 "3명" 을 눌러 5명이 뜨는 일이 없다 — 그래서 아래
  /// [attention] 목록(옛 나트륨·이행률 기준, 대시보드 카드가 쓴다)이 아니라
  /// 신호로 센다. 답장 대기는 주의가 아니다.
  final int healthAttentionCount;

  /// Mean routine completion (%) per weekday, 월→일. Empty when no
  /// client has weekly data yet.
  final List<int> weeklyCompletion;

  /// An empty summary — used while the streams are still loading.
  static const DashboardSummary empty = DashboardSummary(
    activeClients: 0,
    totalClients: 0,
    unreadTotal: 0,
    unreadClients: 0,
    attention: <AttentionClient>[],
    weeklyCompletion: <int>[],
  );
}

/// Aggregates the dashboard's numbers from the roster and unread counts.
///
/// [clients] is expected in coaching-priority order (the same ordering
/// the 고객 list uses); ties inside the attention list therefore keep
/// that order rather than inventing a second one.
DashboardSummary buildDashboardSummary({
  required List<TrainerClient> clients,
  required Map<String, int> unread,
}) {
  final attention = <AttentionClient>[];
  var unreadTotal = 0;
  var unreadClients = 0;

  for (final client in clients) {
    final pending = unread[client.id] ?? 0;
    if (pending > 0) {
      unreadTotal += pending;
      unreadClients++;
    }
    final alerts = alertsFor(client, unread: pending);
    if (alerts.isNotEmpty) {
      attention.add(AttentionClient(client: client, alerts: alerts));
    }
  }

  // 목표를 가장 크게 벗어난 회원부터. 예전에는 신호 **종류** 순으로 묶었는데,
  // 카드가 다섯 행만 보여 주다 보니 첫 종류가 카드를 통째로 차지했다 — 배지를
  // 회원별로 고르게 만들어도 화면은 여전히 한 가지 말만 했다(#767).
  //
  // 동점이면 들어온 순서를 지킨다. `List.sort` 는 안정 정렬이 아니라 원래
  // 위치를 명시적 타이브레이커로 둔다.
  final order = <String, int>{
    for (var i = 0; i < clients.length; i++) clients[i].id: i,
  };
  attention.sort((a, b) {
    final bySeverity = alertSeverity(
      b.client,
      b.primary,
    ).compareTo(alertSeverity(a.client, a.primary));
    if (bySeverity != 0) return bySeverity;
    return (order[a.client.id] ?? 0).compareTo(order[b.client.id] ?? 0);
  });

  return DashboardSummary(
    activeClients: clients.where((c) => c.active).length,
    totalClients: clients.length,
    unreadTotal: unreadTotal,
    unreadClients: unreadClients,
    attention: attention,
    weeklyCompletion: _meanWeeklyCompletion(clients),
    healthAttentionCount: clients.where(needsAttention).length,
  );
}

/// Mean completion per weekday across every client that has a full week
/// of data. Days no client recorded stay 0.
List<int> _meanWeeklyCompletion(List<TrainerClient> clients) {
  final weeks = clients
      .map((c) => c.weekCompletion)
      .where((w) => w.length == weekdayCount)
      .toList();
  if (weeks.isEmpty) return const <int>[];
  return <int>[
    for (var day = 0; day < weekdayCount; day++)
      (weeks.map((w) => w[day]).reduce((a, b) => a + b) / weeks.length).round(),
  ];
}
