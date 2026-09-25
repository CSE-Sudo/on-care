import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// Weekly completion below this (%) counts as a client who needs the
/// trainer to step in.
const int lowCompletionThreshold = 60;

/// A reason a client's row is flagged, ordered by urgency.
///
/// Lives in `shared` because two features ask the same question: the
/// 대시보드 (who do I chase today?) and the 고객 list filter (show me
/// only those). One definition, so the dashboard count and the filtered
/// list can never disagree.
enum ClientAlert {
  /// Today's sodium is over the daily target.
  sodiumOver,

  /// Today's sugar is over the daily target.
  ///
  /// 나트륨과 나란히 둔다 — 둘 다 식단 신호이고, "적을수록 낫다" 가 모든
  /// 회원에게 성립한다. 칼로리는 그렇지 않아 배지로 두지 않는다: 벌크업
  /// 회원에게 칼로리 초과는 잘한 것이다(#767).
  sugarOver,

  /// This week's routine completion is low.
  lowCompletion,

  /// The member sent messages the trainer hasn't answered.
  ///
  /// Last on purpose: a client's badge is their first alert, and while a
  /// waiting message is urgent, it is also the one the 답장 필요 counter
  /// already shows. Putting it first hid every sodium overshoot behind it.
  unanswered;

  /// Badge text shown next to the client's name, in the current locale. (#501)
  String label(AppLocalizations l) => switch (this) {
    ClientAlert.sodiumOver => l.alertSodiumOver,
    ClientAlert.sugarOver => l.alertSugarOver,
    ClientAlert.lowCompletion => l.alertLowCompletion,
    ClientAlert.unanswered => l.alertAwaitingReply,
  };

  /// Whether this is a signal from the member's own health data.
  ///
  /// The 주의 고객 count is health only — an unanswered message is the
  /// trainer's own inbox, and counting it as 주의 made every client with
  /// a message look like a health concern. The list itself still shows
  /// 답장 대기 rows; it just doesn't call them 주의.
  bool get isHealth => this != ClientAlert.unanswered;
}

/// Every alert raised for [client], most urgent first. Empty means the
/// client is fine today.
///
/// This is the full picture — what the 오늘 챙길 고객 list and the client
/// detail header show. For the 주의 고객 *count* use [healthAlertsFor].
List<ClientAlert> alertsFor(TrainerClient client, {int unread = 0}) {
  // 건강 신호는 **그 회원에게 얼마나 나쁜지** 로 줄 세운다. 지표 종류의 고정
  // 순서로 두면 나트륨이 1mg 만 넘어도 이행률 36% 를 덮어, 배지가 늘 같은 말을
  // 한다(#767). 배지는 첫 신호 하나뿐이라 그 자리를 가장 급한 것에 준다.
  final health =
      <ClientAlert>[
        if (client.sodiumOverBudget) ClientAlert.sodiumOver,
        if (client.sugarOverBudget) ClientAlert.sugarOver,
        if (isLowCompletion(client)) ClientAlert.lowCompletion,
      ]..sort(
        (a, b) => alertSeverity(client, b).compareTo(alertSeverity(client, a)),
      );

  return <ClientAlert>[
    ...health,
    // 답장 대기는 늘 마지막이다. 트레이너 자신의 받은편지함이지 회원의 건강
    // 신호가 아니고, `답장 필요` 카운터가 이미 그 수를 보여 준다.
    if (unread > 0) ClientAlert.unanswered,
  ];
}

/// [alert] 가 [client] 에게 얼마나 나쁜지. 1 을 넘을수록 나쁘다.
///
/// 세 지표를 **같은 저울** 에 올린다. 나트륨·당류는 `값 ÷ 목표` 로 1 을 넘고,
/// 이행률은 낮을수록 나쁘니 뒤집어 `기준선 ÷ 실제` 로 둔다. 그래야 "나트륨을
/// 조금 넘긴 회원" 과 "이행률이 절반인 회원" 중 누가 더 급한지 견줄 수 있다.
///
/// 답장 대기는 0 이다 — 건강 신호가 아니라 견줄 저울이 없고, 늘 마지막이다.
double alertSeverity(TrainerClient client, ClientAlert alert) =>
    switch (alert) {
      ClientAlert.sodiumOver => client.sodiumMg / sodiumTargetMg,
      ClientAlert.sugarOver => client.sugarG / sugarTargetG,
      ClientAlert.lowCompletion => _completionRatio(client),
      ClientAlert.unanswered => 0,
    };

double _completionRatio(TrainerClient client) {
  final mean = recordedCompletionMean(client);
  if (mean == null || mean <= 0) return double.infinity;
  return lowCompletionThreshold / mean;
}

/// The subset of [alertsFor] that comes from the member's health data.
List<ClientAlert> healthAlertsFor(TrainerClient client) =>
    alertsFor(client).where((a) => a.isHealth).toList();

/// Mean routine completion (%) across the days [client] actually
/// recorded this week, or null when they recorded none.
///
/// Days at 0 are treated as "not recorded", not as "failed": the roster
/// seeds a full Mon–Sun series, so a week that has only started would
/// otherwise average in the days that haven't happened yet.
///
/// One definition, three readers — the 주의 badge, the weekly report,
/// and 고객 검색 — so a client can't be "이행률 78%" in one place and
/// 낮은 이행률 in another.
double? recordedCompletionMean(TrainerClient client) {
  final recorded = client.weekCompletion.where((d) => d > 0).toList();
  if (recorded.isEmpty) return null;
  return recorded.reduce((a, b) => a + b) / recorded.length;
}

/// Whether [client]'s recorded week averages under
/// [lowCompletionThreshold].
///
/// Clients with no data yet (empty week / all zeros) are NOT flagged —
/// a client registered this morning would otherwise show up as failing
/// on day one, which trains the trainer to ignore the badge.
bool isLowCompletion(TrainerClient client) {
  final mean = recordedCompletionMean(client);
  return mean != null && mean < lowCompletionThreshold;
}
