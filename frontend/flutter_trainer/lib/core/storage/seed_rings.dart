part of 'seed_data.dart';

/// 회원 한 명이 받은 개인운동 기간(=운동 탭 `전체` 의 링) 모양. (#2508)
class _RingPlan {
  const _RingPlan(
    this.weeks, {
    this.split = const <int, int>{},
    this.trend = const <double>[],
    this.nextWeek = false,
  });

  /// 이번 주부터 거슬러 몇 주 동안 매주 한 벌을 보냈나.
  final int weeks;

  /// 거슬러 몇 주 → 요일(월=0). 그 주 것을 7일을 못 채우고 그 요일에 바꿨다.
  final Map<int, int> split;

  /// 거슬러 몇 주의 이행률 배수(없으면 1.0) — 링 완료율의 흐름이다.
  final List<double> trend;

  /// 다음 주 첫날부터 걸 한 벌을 어제 미리 보냈다(#2656).
  final bool nextWeek;
}

/// 회원 번호 → 링 모양. 백엔드 `seed_roster._RING_PLAN` 과 같은 표다 — 데모와
/// 실서버가 같은 회원에게 같은 링 수·날짜를 그린다. 한 벌은 그 회원의 AI 개인운동
/// (`aiRoutine`)이다. 표에 없는 회원은 따로 정한다 — 김민수는 공유 픽스처,
/// 이지수·박성호는 기한 없는 배정, 임도현은 오늘 처음 보낸 한 벌(#3003).
///
/// 한 벌은 그 주 `weekCompletion` 의 처음~끝 0 이 아닌 요일에 걸린다. 최근
/// [_RingPlan.weeks] 주만 개인운동이고, 그 앞 주들의 한 벌은 일반 배정이라 링이
/// 아니다 — 리포트 이력의 이행률은 그대로다.
const Map<int, _RingPlan> _ringPlans = <int, _RingPlan>{
  // 정하윤 — 오래 받음, 가운데 주들이 꺼진 V자.
  4: _RingPlan(
    15,
    trend: <double>[
      1.0, 0.94, 0.88, 0.82, 0.76, 0.7, 0.64, 0.6, //
      0.64, 0.7, 0.76, 0.82, 0.88, 0.94, 1.0,
    ],
  ),
  5: _RingPlan(7, nextWeek: true), // 최우진 — 다음 주 것도 미리
  6: _RingPlan(4), // 강서연
  // 오세라 — 받을수록 떨어진다(주별 계수의 흔들림을 상쇄한 값).
  8: _RingPlan(7, trend: <double>[1.0, 1.19, 1.15, 1.51, 1.41, 1.65, 1.55]),
  9: _RingPlan(2, split: <int, int>{1: 3}), // 배준혁 — 지난주 목요일에 교체
  10: _RingPlan(1), // 신유나 — 이번 주 처음
  11: _RingPlan(15), // 한지호
  12: _RingPlan(2), // 문가영
  13: _RingPlan(3, split: <int, int>{2: 2}), // 류태경 — 2주 전 수요일에 교체
  14: _RingPlan(15), // 백서진
  15: _RingPlan(1), // 노은채 — 이번 주 처음
};

/// 시드 한 벌이 걸린 기간 — [from] 부터 [until] 전날까지. [week] 는 거슬러 몇
/// 주(미리 보낸 다음 주 것은 -1)다.
typedef DemoRingWindow = ({
  DateTime from,
  DateTime until,
  int week,
  bool personal,
});

int? _ringClientId(String memberId) =>
    int.tryParse(memberId.replaceFirst('seed-client-', ''));

/// [memberId] 의 시드 기간들 — 오래된 것부터. 백엔드 `ring_windows` 와 같은
/// 규칙이다.
List<DemoRingWindow> demoRingWindows(String memberId, DateTime today) {
  final int? id = _ringClientId(memberId);
  final _RingPlan? plan = _ringPlans[id];
  if (plan == null) return const <DemoRingWindow>[];
  final List<int> completion = _clients
      .firstWhere((_Client c) => c.id == id)
      .weekCompletion;
  final List<int> active = <int>[
    for (final (int i, int rate) in completion.indexed)
      if (rate > 0) i,
  ];
  if (active.isEmpty) return const <DemoRingWindow>[];
  final int first = active.first;
  final int last = active.last;
  final DateTime day = DateTime(today.year, today.month, today.day);
  final DateTime monday = mondayOf(day);
  DateTime at(int week, int weekday) =>
      DateTime(monday.year, monday.month, monday.day - 7 * week + weekday);
  final List<DemoRingWindow> windows = <DemoRingWindow>[];
  for (int week = demoMetricsHistoryWeeks - 1; week >= 0; week--) {
    DateTime from = at(week, first);
    final DateTime until = at(week, last + 1);
    // 이번 주 것을 아직 보내지 않았다(수요일부터 받는 회원의 월·화).
    if (from.isAfter(day)) continue;
    final bool personal = week < plan.weeks;
    final int? cut = plan.split[week];
    if (personal && cut != null && first < cut && cut <= last) {
      windows.add((
        from: from,
        until: at(week, cut),
        week: week,
        personal: true,
      ));
      from = at(week, cut);
    }
    windows.add((from: from, until: until, week: week, personal: personal));
  }
  if (plan.nextWeek) {
    final DateTime start = at(-1, first);
    windows.add((
      from: start,
      until: DateTime(start.year, start.month, start.day + 7),
      week: -1,
      personal: true,
    ));
  }
  return windows;
}

/// 미리 보낸 다음 주 한 벌을 보낸 날 — 어제, 이번 주 월요일보다 앞서지 않는다.
DateTime demoRingSentOn(DateTime today) {
  final DateTime day = DateTime(today.year, today.month, today.day);
  final DateTime yesterday = DateTime(day.year, day.month, day.day - 1);
  final DateTime monday = mondayOf(day);
  return yesterday.isBefore(monday) ? monday : yesterday;
}

/// 거슬러 [back] 주의 이행률 흐름 배수.
double _ringTrend(int clientId, int back) {
  final List<double> trend = _ringPlans[clientId]?.trend ?? const <double>[];
  return back < trend.length ? trend[back] : 1.0;
}
