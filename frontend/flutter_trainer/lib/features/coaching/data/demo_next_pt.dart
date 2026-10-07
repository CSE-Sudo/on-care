/// AI 루틴 C안 — 지난 PT 흐름상 이번 차례 프로그램의 데모 규칙(#3282).
///
/// 서버 `backend/app/services/routine_next_pt.py` 와 같은 규칙이다. 데모 A/B 생성
/// (`MockTrainerRoutineOptionsRepository`)은 AI 를 부르지 않으므로 C안도 서버의
/// 규칙형 C안과 같은 값을 낸다 — 한쪽만 바뀌면 같은 회원에게 데모와 실서버
/// 폴백이 다른 차례를 낸다.
library;

import 'package:oncare_trainer/features/coaching/data/demo_routine_rules.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';

/// 차례를 볼 최근 완료 PT 수 — 서버 `NEXT_PT_LOOKBACK`.
const int demoNextPtLookback = 8;

/// 기록이 없을 때 시작하는 전신 기본 프로그램 — 서버 `_START_PROGRAM`.
const List<(String, String, int?, int?, int)> _startProgram =
    <(String, String, int?, int?, int)>[
      ('스쿼트', '근력', 3, 12, 8),
      ('푸시업', '근력', 3, 10, 8),
      ('밴드 로우', '근력', 3, 12, 8),
      ('플랭크', '근력', 3, null, 6),
      ('저강도 걷기', '유산소', null, null, 10),
    ];

const Map<String, String> _enStartNames = <String, String>{
  '푸시업': 'Push-up',
  '밴드 로우': 'Band row',
};

const int _minutesPerSet = 3;
const int _stepUpRate = 80;
const int _stepDownRate = 50;
const int _minSets = 2;
const int _maxSets = 6;

/// 지난 PT 프로그램의 운동 한 줄.
class DemoPtItem {
  const DemoPtItem({
    required this.name,
    required this.type,
    this.sets,
    this.reps,
    this.weight,
    this.minutes,
  });

  final String name;
  final String type;
  final int? sets;
  final int? reps;
  final double? weight;
  final int? minutes;
}

/// 완료한 PT 한 회.
class DemoPtSession {
  const DemoPtSession({required this.day, required this.items});

  final DateTime day;
  final List<DemoPtItem> items;
}

/// 이번 차례 판단 — 서버 `NextPt`.
class DemoNextPt {
  const DemoNextPt({
    required this.kind,
    required this.label,
    required this.items,
    required this.basis,
    this.sessionCount = 0,
    this.daysAgo,
  });

  /// `rotation` · `continue` · `start`.
  final String kind;
  final String label;
  final List<DemoPtItem> items;
  final String basis;
  final int sessionCount;
  final int? daysAgo;
}

/// 저장된 `programJson` 한 줄 → [DemoPtItem]. 이름이 없으면 null.
DemoPtItem? demoPtItemFromJson(Object? raw) {
  if (raw is! Map) return null;
  final String name = (raw['name'] ?? '').toString().trim();
  if (name.isEmpty) return null;
  const Set<String> types = <String>{'걷기', '유산소', '근력', '요가', '스트레칭', '기타'};
  final Object? type = raw['type'];
  num? number(Object? v) => v is num
      ? v
      : v is String
      ? num.tryParse(RegExp(r'\d+(\.\d+)?').firstMatch(v)?.group(0) ?? '')
      : null;
  num? minutes = number(raw['duration']);
  if (minutes == null) {
    final num? seconds = number(raw['duration_seconds']);
    if (seconds != null && seconds > 0) minutes = (seconds / 60).round();
  }
  final num? sets = number(raw['sets']);
  final num? reps = number(raw['reps']);
  final num? weight = number(raw['weight']);
  return DemoPtItem(
    name: name,
    type: types.contains(type) ? type! as String : '근력',
    sets: sets == null || sets == 0 ? null : sets.toInt(),
    reps: reps == null || reps == 0 ? null : reps.toInt(),
    weight: weight == null || weight == 0 ? null : weight.toDouble(),
    minutes: minutes == null || minutes == 0 ? null : minutes.toInt(),
  );
}

Set<String> _signature(List<DemoPtItem> items) {
  final Set<String> strength = <String>{
    for (final DemoPtItem i in items)
      if (i.type == '근력') i.name,
  };
  return strength.isNotEmpty
      ? strength
      : <String>{for (final DemoPtItem i in items) i.name};
}

String _label(List<DemoPtItem> items) {
  final List<String> strength = <String>[
    for (final DemoPtItem i in items)
      if (i.type == '근력') i.name,
  ];
  final List<String> names = strength.isNotEmpty
      ? strength
      : <String>[for (final DemoPtItem i in items) i.name];
  return names.take(2).join(' · ');
}

/// [sessions](최신 먼저)에서 이번 차례를 고른다 — 서버 `choose_next`.
DemoNextPt chooseNextPt(
  List<DemoPtSession> sessions, {
  required DateTime today,
  required bool en,
}) {
  String t(String ko, String english) => en ? english : ko;
  final List<DemoPtSession> recent = sessions
      .where((DemoPtSession s) => s.items.isNotEmpty)
      .take(demoNextPtLookback)
      .toList();
  if (recent.isEmpty) {
    return DemoNextPt(
      kind: 'start',
      label: t('전신 기본', 'Full-body starter'),
      items: <DemoPtItem>[
        for (final (String name, String type, int? sets, int? reps, int min)
            in _startProgram)
          DemoPtItem(
            name: en
                ? _enStartNames[name] ?? libraryExerciseName(name, en: en)
                : name,
            type: type,
            sets: sets,
            reps: reps,
            minutes: min,
          ),
      ],
      basis: t(
        'PT 기록이 아직 없어 전신 기본 프로그램으로 시작해요',
        'No PT records yet — starting with a full-body basic program',
      ),
    );
  }

  // 프로그램마다 마지막으로 한 회차(최근 쪽 위치)와 한 횟수를 센다. 집합은
  // 내용으로 비교해야 하므로 정렬한 이름 묶음을 열쇠로 쓴다.
  final Map<String, int> lastSeen = <String, int>{};
  final Map<String, int> times = <String, int>{};
  for (var i = 0; i < recent.length; i++) {
    final List<String> sig = _signature(recent[i].items).toList()..sort();
    final String key = sig.join('\u0000');
    lastSeen.putIfAbsent(key, () => i);
    times[key] = (times[key] ?? 0) + 1;
  }
  final int count = recent.length;
  int daysSince(DateTime day) => DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;

  // 두 번 이상 한 프로그램이 둘 이상이어야 순환이다 — 서버와 같다.
  final List<String> repeated = <String>[
    for (final MapEntry<String, int> e in times.entries)
      if (e.value >= 2) e.key,
  ];
  if (repeated.length >= 2) {
    final String key = repeated.reduce(
      (String a, String b) => lastSeen[a]! >= lastSeen[b]! ? a : b,
    );
    final DemoPtSession chosen = recent[lastSeen[key]!];
    final String label = _label(chosen.items);
    final int days = daysSince(chosen.day);
    final int kinds = repeated.length;
    return DemoNextPt(
      kind: 'rotation',
      label: label,
      items: chosen.items,
      basis: t(
        "최근 $count회에서 번갈아 한 프로그램 $kinds가지 중 '$label'을 "
            '가장 오래 안 했어요($days일 전) → 이번 차례',
        'Of the $kinds programs alternated over the last $count sessions, '
            "'$label' was done longest ago ($days days) → up next",
      ),
      sessionCount: count,
      daysAgo: days,
    );
  }

  // 순환이 보이지 않으면 가장 최근 PT 를 이어 가며 고친다.
  final DemoPtSession latest = recent.first;
  final String label = _label(latest.items);
  final String basis = count == 1
      ? t(
          '지난 PT 1회의 프로그램($label)을 이어 가요',
          'Continuing the program from the last PT ($label)',
        )
      : lastSeen.length == 1
      ? t(
          '최근 $count회 같은 프로그램($label)을 이어 와서 같은 흐름을 유지해요',
          'The last $count sessions repeated the same program ($label) '
              '— keeping that flow',
        )
      : t(
          '최근 $count회에서 번갈아 하는 프로그램이 보이지 않아 '
              '지난 PT($label)를 이어 가요',
          'No alternating programs over the last $count sessions — '
              'continuing the last PT ($label)',
        );
  return DemoNextPt(
    kind: 'continue',
    label: label,
    items: latest.items,
    basis: basis,
    sessionCount: count,
    daysAgo: daysSince(latest.day),
  );
}

int _itemMinutes(DemoPtItem item) {
  if (item.minutes != null && item.minutes! > 0) return item.minutes!;
  if (item.type == '근력') return (item.sets ?? 3) * _minutesPerSet;
  return 5;
}

String? _cautionPart(String name, List<String> cautions) {
  for (final String part in cautions) {
    if (avoidsFor(name, <String>[part])) return part;
  }
  return null;
}

/// 합이 [cap] 을 넘으면 비례로 줄인다 — 서버 `_fit_minutes`.
List<int> _fitMinutes(List<int> minutes, int cap) {
  final int total = minutes.fold(0, (int a, int b) => a + b);
  if (total <= cap) return minutes;
  final List<int> scaled = <int>[
    for (final int m in minutes) ((m * cap) ~/ total).clamp(1, cap),
  ];
  final List<int> order = List<int>.generate(minutes.length, (int i) => i)
    ..sort((int a, int b) => minutes[b].compareTo(minutes[a]));
  int sum() => scaled.fold(0, (int a, int b) => a + b);
  var i = 0;
  while (sum() < cap) {
    scaled[order[i % order.length]] += 1;
    i++;
  }
  while (sum() > cap) {
    final int j = order[i % order.length];
    if (scaled[j] > 1) scaled[j] -= 1;
    i++;
  }
  return scaled;
}

const Map<String, String> _intensityLabels = <String, String>{
  'low': '낮음',
  'moderate': '보통',
  'high': '높음',
};

/// 기준 프로그램을 규칙만큼 고친 C안 — 서버 `rule_plan_c`.
RoutinePlan rulePlanC(
  DemoNextPt next, {
  required int availableMinutes,
  required String intensityPreference,
  required int completion,
  required List<String> cautions,
  required bool escalate,
  required bool en,
}) {
  String t(String ko, String english) => en ? english : ko;
  final List<String> changes = <String>[];
  final List<String> names = <String>[];
  final List<_Row> rows = <_Row>[];
  for (final DemoPtItem item in next.items) {
    final String? part = _cautionPart(item.name, cautions);
    if (part != null) {
      (String, String) alt = item.type == '근력' ? libStretch : libCardioEasy;
      String altName = libraryExerciseName(alt.$1, en: en);
      if (names.contains(altName)) {
        alt = libCardioEasy;
        altName = libraryExerciseName(alt.$1, en: en);
      }
      final String partEn = demoEnCautionParts[part] ?? part;
      changes.add(
        t('${item.name} → $altName($part)', '${item.name} → $altName ($partEn)'),
      );
      names.add(altName);
      rows.add(_Row(altName, alt.$2, _itemMinutes(item)));
      continue;
    }
    final bool strength = item.type == '근력';
    names.add(item.name);
    rows.add(
      _Row(
        item.name,
        item.type,
        _itemMinutes(item),
        sets: strength ? item.sets : null,
        reps: strength ? item.reps : null,
        weight: strength ? item.weight : null,
      ),
    );
  }

  final List<_Row> strength = <_Row>[
    for (final _Row r in rows)
      if (r.type == '근력' && r.sets != null) r,
  ];
  if (strength.isNotEmpty && completion >= _stepUpRate && !escalate) {
    final List<_Row> moved = <_Row>[
      for (final _Row r in strength)
        if (r.sets! < _maxSets) r,
    ];
    for (final _Row r in moved) {
      r.sets = r.sets! + 1;
    }
    if (moved.isNotEmpty) {
      changes.add(
        t(
          '근력 세트 +1(완료율 $completion%)',
          'Strength sets +1 ($completion% completion)',
        ),
      );
    }
  } else if (strength.isNotEmpty && completion < _stepDownRate) {
    final List<_Row> moved = <_Row>[
      for (final _Row r in strength)
        if (r.sets! > _minSets) r,
    ];
    for (final _Row r in moved) {
      r.sets = r.sets! - 1;
    }
    if (moved.isNotEmpty) {
      changes.add(
        t(
          '근력 세트 -1(완료율 $completion%)',
          'Strength sets −1 ($completion% completion)',
        ),
      );
    }
  }

  final int before = rows.fold(0, (int a, _Row r) => a + r.minutes);
  final List<int> fitted = _fitMinutes(<int>[
    for (final _Row r in rows) r.minutes,
  ], availableMinutes);
  for (var i = 0; i < rows.length; i++) {
    rows[i].minutes = fitted[i];
  }
  final int after = fitted.fold(0, (int a, int b) => a + b);
  if (after < before) {
    changes.add(
      t(
        '총 $before분 → $after분(최대 $availableMinutes분 조건)',
        'Total $before → $after min (up to $availableMinutes min)',
      ),
    );
  }

  // 차례 근거·바꾼 점은 카드에 따로 서므로 되풀이하지 않는다 — 서버와 같다.
  final String rationale = changes.isEmpty
      ? t('지난 PT 프로그램을 그대로 이어 가요.', 'Continues the past PT program as is.')
      : t(
          '지난 PT 프로그램을 기준으로 주의 부위·완료율·시간 조건만 반영했어요.',
          'Based on the past PT program, adjusted only for cautions, '
              'completion and the time limit.',
        );
  return RoutinePlan(
    key: 'C',
    label: next.label.length > 50 ? next.label.substring(0, 50) : next.label,
    totalMinutes: after,
    intensity: escalate
        ? '보통'
        : _intensityLabels[intensityPreference] ?? '보통',
    exercises: <RoutineExercise>[
      for (final _Row r in rows)
        RoutineExercise(
          name: r.name,
          minutes: r.minutes,
          type: r.type,
          sets: r.sets ?? 0,
          reps: r.reps ?? 0,
          weight: r.weight ?? 0,
        ),
    ],
    reason: t(
      '지난 PT 흐름상 이번 차례인 프로그램',
      'The program that comes next in the recent PT flow',
    ),
    rationale: rationale,
    basis: next.basis,
    changes: changes,
  );
}

/// 판단 결과(#3280)에 싣는 차례 한 줄 — 서버 `finding`.
RoutineFinding nextPtFinding(DemoNextPt next, {required bool en}) {
  String t(String ko, String english) => en ? english : ko;
  if (next.kind == 'start') {
    return RoutineFinding(
      kind: 'rotation',
      finding: t('PT 기록 없음', 'No PT records'),
      source: t('PT 기록', 'PT records'),
      action: t(
        '연계안은 전신 기본 프로그램으로 시작',
        'Follow-up plan starts with a full-body basic program',
      ),
    );
  }
  return RoutineFinding(
    kind: 'rotation',
    finding: next.kind == 'continue'
        ? t('이어 갈 지난 PT: ${next.label}', 'Last PT to continue: ${next.label}')
        : t(
            '가장 오래 안 한 프로그램: ${next.label}(${next.daysAgo}일 전)',
            'Done longest ago: ${next.label} (${next.daysAgo} days)',
          ),
    source: t(
      'PT 기록 · 최근 ${next.sessionCount}회',
      'PT records · last ${next.sessionCount} sessions',
    ),
    action: t(
      '연계안: 이번 차례 프로그램을 최근 상태에 맞게 조정',
      'Follow-up plan: adjusts this program to the latest condition',
    ),
  );
}

class _Row {
  _Row(
    this.name,
    this.type,
    this.minutes, {
    this.sets,
    this.reps,
    this.weight,
  });

  final String name;
  final String type;
  int minutes;
  int? sets;
  final int? reps;
  final double? weight;
}
