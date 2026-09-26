import 'package:oncare_trainer/shared/models/trainer_client.dart';

// 주간 루틴 이행률 계산 — 회원 목록 막대·고객 검색·코칭 화면이 함께 쓴다.
//
// 예전에는 여기에 목록 배지(`ClientAlert`: 나트륨·당류·이행률 저조·답장
// 대기)도 있었다. 배지는 PT 관리 신호(`client_signal.dart`, #2204·#2243)로
// 바뀌어 지웠고, 이행률 계산만 남는다.

/// Weekly completion below this (%) counts as a client who needs the
/// trainer to step in.
const int lowCompletionThreshold = 60;

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
