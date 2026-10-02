import 'package:oncare_rules/oncare_rules.dart' show pyRound;
import 'package:oncare_trainer/shared/models/client_signal.dart';

/// 서버 `client_signals.decide_signals` 의 판정을 테스트에서 옮겨 둔 것. (#2906)
///
/// 트레이너 웹은 PT 관리 신호를 계산하지 않는다 — 실서버는 로스터에 실어 주고,
/// 데모는 시드에 적어 둔다. 그래서 판정은 앱 코드가 아니라 테스트가 들고,
/// 서버 스크립트가 만든 사례 파일(`client_signals_cases.json`)로 이 판정이
/// 서버와 같은지 먼저 확인한 뒤, 데모 시드의 신호가 이 판정으로 나올 수 있는
/// 값인지 검사하는 데 쓴다. 기준값은 사례 파일의 `thresholds` 를 그대로 읽는다.
class ClientSignalFacts {
  const ClientSignalFacts({
    required this.discomfort,
    required this.linkAgeDays,
    required this.recordGapDays,
    required this.noShowCount,
    required this.routineMissedDays,
    required this.weekday,
    required this.exerciseGoalPercent,
    required this.recentDiet,
    required this.calorieTarget,
    required this.proteinTarget,
    required this.focus,
  });

  /// 사례 파일의 `facts` 한 칸.
  factory ClientSignalFacts.fromJson(Map<String, Object?> json) =>
      ClientSignalFacts(
        discomfort: json['discomfort']! as bool,
        linkAgeDays: json['link_age_days']! as int,
        recordGapDays: json['record_gap_days']! as int,
        noShowCount: json['no_show_count']! as int,
        routineMissedDays: json['routine_missed_days']! as int,
        weekday: json['weekday']! as int,
        exerciseGoalPercent: json['exercise_goal_percent'] as int?,
        recentDiet: <(int, double)>[
          for (final Object? day in json['recent_diet']! as List<Object?>)
            (
              ((day! as List<Object?>)[0]! as num).toInt(),
              ((day as List<Object?>)[1]! as num).toDouble(),
            ),
        ],
        calorieTarget: json['calorie_target']! as int,
        proteinTarget: (json['protein_target'] as num?)?.toDouble(),
        focus: <String>{
          for (final Object? f in json['focus']! as List<Object?>) f! as String,
        },
      );

  final bool discomfort;
  final int linkAgeDays;
  final int recordGapDays;
  final int noShowCount;
  final int routineMissedDays;

  /// 월=0 (서버 `date.weekday()`).
  final int weekday;
  final int? exerciseGoalPercent;

  /// 어제까지 최근 창에서 칼로리를 기록한 날의 (칼로리, 단백질).
  final List<(int, double)> recentDiet;
  final int calorieTarget;
  final double? proteinTarget;
  final Set<String> focus;
}

/// 서버 `decide_signals` 와 같은 판정. [t] 는 사례 파일의 `thresholds`.
List<ClientSignal> decideClientSignals(
  ClientSignalFacts f,
  Map<String, Object?> t,
) {
  int n(String key) => t[key]! as int;
  double r(String key) => (t[key]! as num).toDouble();
  final List<String> order = (t['signal_order']! as List<Object?>)
      .cast<String>();
  final Set<String> recordDerived = (t['record_derived']! as List<Object?>)
      .cast<String>()
      .toSet();
  final Set<String> proteinFocus = (t['protein_focus']! as List<Object?>)
      .cast<String>()
      .toSet();

  List<ClientSignal> found = <ClientSignal>[];
  if (f.discomfort) found.add(const ClientSignal(ClientSignalKind.discomfort));
  if (f.linkAgeDays < n('new_link_grace_days')) return found;

  if (f.recordGapDays >= n('record_gap_days')) {
    found.add(ClientSignal(ClientSignalKind.recordGap, days: f.recordGapDays));
  }
  if (f.noShowCount >= n('no_show_min_count')) {
    found.add(ClientSignal(ClientSignalKind.noShow, count: f.noShowCount));
  }
  if (f.routineMissedDays >= n('routine_min_assigned_days')) {
    found.add(
      ClientSignal(ClientSignalKind.routineMissed, days: f.routineMissedDays),
    );
  }
  final int? percent = f.exerciseGoalPercent;
  if (f.weekday >= n('exercise_goal_from_weekday') &&
      percent != null &&
      percent < n('exercise_goal_low_percent')) {
    found.add(ClientSignal(ClientSignalKind.exerciseGoalLow, percent: percent));
  }

  if (f.recentDiet.length >= n('min_recorded_days')) {
    final double meanKcal =
        f.recentDiet.fold<int>(0, (int a, (int, double) d) => a + d.$1) /
        f.recentDiet.length;
    final double gap = (meanKcal - f.calorieTarget) / f.calorieTarget;
    if (gap.abs() > r('calorie_tolerance')) {
      found.add(
        ClientSignal(
          ClientSignalKind.calorieOff,
          percent: pyRound(gap * 100).abs(),
          over: gap > 0,
        ),
      );
    }
    final double? proteinTarget = f.proteinTarget;
    if (proteinTarget != null &&
        proteinTarget > 0 &&
        f.focus.any(proteinFocus.contains)) {
      final double meanProtein =
          f.recentDiet.fold<double>(
            0,
            (double a, (int, double) d) => a + d.$2,
          ) /
          f.recentDiet.length;
      if (meanProtein < proteinTarget * r('protein_low_ratio')) {
        found.add(
          ClientSignal(
            ClientSignalKind.proteinLow,
            percent: pyRound(meanProtein / proteinTarget * 100),
          ),
        );
      }
    }
  }

  if (found.any((ClientSignal s) => s.kind == ClientSignalKind.recordGap)) {
    found = <ClientSignal>[
      for (final ClientSignal s in found)
        if (!recordDerived.contains(s.kind.wire)) s,
    ];
  }
  found.sort(
    (ClientSignal a, ClientSignal b) =>
        order.indexOf(a.kind.wire).compareTo(order.indexOf(b.kind.wire)),
  );
  return found;
}
