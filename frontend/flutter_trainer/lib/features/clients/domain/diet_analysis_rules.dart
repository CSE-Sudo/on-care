/// 트레이너 웹 `식단 분석` 규칙 — 서버 `diet_trainer_analysis` 를 옮긴 것. (#2379)
///
/// 데모(목 모드)가 서버 없이 같은 문장을 내도록 쓴다. 서버와 같은지는 공유 사례 파일
/// (`test/features/clients/diet_analysis_cases.json`, 서버
/// `scripts/gen_trainer_diet_analysis_cases.py` 가 만든다)로 두 쪽 테스트가 본다.
/// 규칙을 바꾸면 서버를 먼저 고치고 사례 파일을 다시 만든 뒤 여기를 맞춘다.
///
/// 판정은 회원 앱 조언과 같다(이번 주 `decide_week`, 전체 `decide_all`). 거기에
/// 원인 음식·끼니를 붙여 트레이너가 읽기 좋은 서술로 말한다.
library;

import 'package:oncare_rules/oncare_rules.dart' show pyRound;
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_analysis.dart';
import 'package:oncare_ui/oncare_ui.dart';

// 서버와 같은 반올림은 공용 규칙 패키지 한 곳에 있다(#2860). 이 파일을 통해
// 쓰던 자리가 그대로 읽히도록 다시 내보낸다.
export 'package:oncare_rules/oncare_rules.dart' show pyRound;

/// 음식 한 가지. 값이 없으면(옛 기록) null 이다.
class DietRuleFood {
  const DietRuleFood(this.name, {this.calories, this.sodiumMg, this.sugarG});

  final String name;
  final num? calories;
  final num? sodiumMg;
  final num? sugarG;

  num? valueOf(String nutrient) => switch (nutrient) {
    'sodium' => sodiumMg,
    'sugar' => sugarG,
    _ => calories,
  };
}

/// 끼니 한 번 — 서버 `DietEntry` 에서 규칙이 읽는 것.
class DietRuleEntry {
  const DietRuleEntry({
    required this.date,
    required this.slot,
    required this.foods,
    required this.calories,
    required this.proteinG,
    required this.sodiumMg,
    required this.sugarG,
    this.carbsG = 0,
    this.fatG = 0,
  });

  /// `YYYY-MM-DD`.
  final String date;

  /// `breakfast`·`lunch`·`dinner`·`snack`·`lateNight`.
  final String slot;
  final List<DietRuleFood> foods;
  final num calories;
  final num proteinG;
  final num sodiumMg;
  final num sugarG;
  final num carbsG;
  final num fatG;

  num totalOf(String nutrient) => switch (nutrient) {
    'sodium' => sodiumMg,
    'sugar' => sugarG,
    _ => calories,
  };

  List<String> get foodNames => <String>[
    for (final DietRuleFood f in foods)
      if (f.name.trim().isNotEmpty) f.name.trim(),
  ];
}

/// 하루 목표 — 서버 `diet_coach_inputs.DietTargets`.
typedef DietRuleTargets = ({
  int calories,
  int proteinG,
  int sodiumMg,
  int sugarG,
});

// ── 상수 — 서버와 같다 ─────────────────────────────────────────────────

const double _calorieOverRatio = 1.1;
const int _proteinGapG = 10;
const double _proteinChronicRatio = 0.8;
const Map<String, int> _mealDeadlineHour = <String, int>{
  'breakfast': 11,
  'lunch': 15,
  'dinner': 21,
};
const List<String> _main = <String>['breakfast', 'lunch', 'dinner'];
const List<String> _snacks = <String>['snack', 'lateNight'];

// 이번 주(`diet_week_advice`).
const int _skipBreakfastMin = 3;
const int _skipSnackMin = 2;
const int _focusMinDays = 1;
const int _breakfastDeadlineHour = 11;
const int _proteinMinMeals = 2;
const double _proteinShortRatio = 0.8;
const List<String> _focusOrder = <String>[
  'sodium',
  'calorie',
  'sugar',
  'protein',
];

// 전체(`diet_all_advice`).
/// `식단 분석` 전체가 **읽는** 날 수 — 최근 4주. 그래프의 `전체`(모든 기록, #2079)와
/// 뜻이 다르다: 그래프는 "지금까지 어땠나", 분석은 "최근 4주를 근거로" 말한다.
const int allWindowDays = 28;
const int _allMinDays = 7;
const double _slotSodiumRatio = 0.5;
const int _slotSodiumMin = 4;
const double _slotSodiumShare = 0.3;
const int _carbHeavyPct = 65;
const int _proteinLightPct = 15;
const double _proteinMetRatio = 0.9;
const int _trendMinDiff = 2;
const int _trendMinDays = 3;
const int _frequentMin = 5;
const int _frequentNameMax = 6;
const double _repeatedShare = 0.25;
const int _repeatedMinItems = 20;
const int _topFoods = 2;

/// 파이썬 `f"{x:.1f}"` — 소수 첫째 자리까지.
///
/// 둘 다 **실제 이진수 값**으로 반올림하지만, 정확히 절반일 때 파이썬은 짝수 쪽,
/// Dart `toStringAsFixed` 는 0 에서 먼 쪽이다(`2.25` → `2.2` / `2.3`). 소수 첫째
/// 자리의 절반이 이진수로 정확히 떨어지는 것은 `x × 4` 가 정수일 때(`.25`·`.75`)뿐이라,
/// 그때만 짝수 쪽으로 고른다. `x × 10` 을 반올림하면 안 된다 — `1.15` 는 이진수로
/// `1.1499…` 라 파이썬은 `1.1` 인데, `11.5` 로 올라가 `1.2` 가 된다.
String pyFixed1(double x) {
  final double quarters = x * 4;
  if (quarters == quarters.roundToDouble() && (x * 10) % 1 == 0.5) {
    return (pyRound(x * 10) / 10).toStringAsFixed(1);
  }
  return x.toStringAsFixed(1);
}

DateTime _day(String ymd) {
  final DateTime d = DateTime.parse(ymd);
  return DateTime(d.year, d.month, d.day);
}

/// 등장 순서를 지키는 개수 세기 — 파이썬 `Counter.most_common` 처럼 같은 수면
/// 먼저 나온 것이 앞이다.
List<MapEntry<String, int>> _mostCommon(Iterable<String> names) {
  final Map<String, int> counts = <String, int>{};
  for (final String n in names) {
    counts[n] = (counts[n] ?? 0) + 1;
  }
  final List<MapEntry<String, int>> entries = counts.entries.toList();
  final List<int> order = List<int>.generate(entries.length, (int i) => i);
  order.sort((int a, int b) {
    final int byCount = entries[b].value.compareTo(entries[a].value);
    return byCount != 0 ? byCount : a.compareTo(b);
  });
  return <MapEntry<String, int>>[for (final int i in order) entries[i]];
}

// ── 오늘 ────────────────────────────────────────────────────────────────

({String slot, String? food, int value}) _topCause(
  List<DietRuleEntry> entries,
  String nutrient,
) {
  ({String slot, String? food, int value}) best = (
    slot: '',
    food: null,
    value: -1,
  );
  for (final DietRuleEntry e in entries) {
    final List<({String name, int value})> valued =
        <({String name, int value})>[
          for (final DietRuleFood f in e.foods)
            if (f.valueOf(nutrient) != null && f.name.trim().isNotEmpty)
              (name: f.name.trim(), value: pyRound(f.valueOf(nutrient)!)),
        ];
    ({String slot, String? food, int value}) candidate;
    if (valued.isNotEmpty) {
      ({String name, int value}) top = valued.first;
      for (final ({String name, int value}) v in valued.skip(1)) {
        if (v.value > top.value) top = v;
      }
      candidate = (slot: e.slot, food: top.name, value: top.value);
    } else {
      candidate = (
        slot: e.slot,
        food: null,
        value: pyRound(e.totalOf(nutrient)),
      );
    }
    if (candidate.value > best.value) best = candidate;
  }
  return best;
}

/// 오늘 — 넘친 것(원인 음식) → 모자란 단백질 → 빠진 끼니. 없으면 칭찬.
List<ClientDietSentence> todaySentences(
  List<DietRuleEntry> entries,
  DietRuleTargets targets,
  DateTime now, {
  int? avgProteinG,
}) {
  if (entries.isEmpty) {
    return const <ClientDietSentence>[ClientDietSentence('tr_today_empty')];
  }
  int sumOf(num Function(DietRuleEntry) f) =>
      pyRound(entries.fold<num>(0, (num a, DietRuleEntry e) => a + f(e)));
  final Map<String, int> totals = <String, int>{
    'sodium': sumOf((DietRuleEntry e) => e.sodiumMg),
    'sugar': sumOf((DietRuleEntry e) => e.sugarG),
    'calorie': sumOf((DietRuleEntry e) => e.calories),
  };
  final int protein = sumOf((DietRuleEntry e) => e.proteinG);
  final Map<String, int> limits = <String, int>{
    'sodium': targets.sodiumMg,
    'sugar': targets.sugarG,
    'calorie': pyRound(targets.calories * _calorieOverRatio),
  };
  final Map<String, int> goals = <String, int>{
    'sodium': targets.sodiumMg,
    'sugar': targets.sugarG,
    'calorie': targets.calories,
  };
  final List<ClientDietSentence> out = <ClientDietSentence>[];

  final List<String> over = <String>[
    for (final String n in <String>['sodium', 'sugar', 'calorie'])
      if (totals[n]! > limits[n]! && goals[n]! > 0) n,
  ];
  if (over.isNotEmpty) {
    String worst = over.first;
    for (final String n in over.skip(1)) {
      if (totals[n]! / goals[n]! > totals[worst]! / goals[worst]!) worst = n;
    }
    final cause = _topCause(entries, worst);
    final Map<String, Object> params = <String, Object>{
      'nutrient': worst,
      'slot': cause.slot,
      'food_value': cause.value,
      'value': totals[worst]!,
      'target': goals[worst]!,
      'ratio': pyFixed1(totals[worst]! / goals[worst]!),
    };
    if (cause.food != null) {
      params['food'] = cause.food!;
      out.add(ClientDietSentence('tr_today_over', params));
    } else {
      out.add(ClientDietSentence('tr_today_over_meal', params));
    }
  }

  final int gap = targets.proteinG - protein;
  if (gap >= _proteinGapG) {
    final Map<String, Object> base = <String, Object>{
      'nutrient': 'protein',
      'value': protein,
      'gap': gap,
    };
    if (avgProteinG != null &&
        avgProteinG < targets.proteinG * _proteinChronicRatio) {
      out.add(
        ClientDietSentence('tr_today_protein_chronic', <String, Object>{
          ...base,
          'avg': avgProteinG,
        }),
      );
    } else {
      out.add(ClientDietSentence('tr_today_protein_short', base));
    }
  }

  final Set<String> slots = <String>{
    for (final DietRuleEntry e in entries) e.slot,
  };
  final double hour = now.hour + now.minute / 60;
  for (final String s in _main) {
    if (!slots.contains(s) && hour >= _mealDeadlineHour[s]!) {
      out.add(
        ClientDietSentence('tr_today_missing', <String, Object>{'slot': s}),
      );
      break;
    }
  }

  return out.isEmpty
      ? <ClientDietSentence>[
          ClientDietSentence('tr_today_good', <String, Object>{
            'kcal': totals['calorie']!,
          }),
        ]
      : out;
}

// ── 날짜별 기록(`diet_week_advice.day_records`) ────────────────────────

typedef _Meal = ({
  String slot,
  List<String> names,
  int kcal,
  int protein,
  int sodium,
  int sugar,
});

class _DayRecord {
  _DayRecord(this.day);

  final DateTime day;
  num kcal = 0;
  num proteinG = 0;
  num sodiumMg = 0;
  num sugarG = 0;
  final Set<String> slots = <String>{};
  final List<_Meal> meals = <_Meal>[];

  int get mainMeals => slots.where(_main.contains).length;
}

Map<DateTime, _DayRecord> _dayRecords(List<DietRuleEntry> entries) {
  final Map<DateTime, _DayRecord> days = <DateTime, _DayRecord>{};
  for (final DietRuleEntry e in entries) {
    final DateTime when;
    try {
      when = _day(e.date);
    } on FormatException {
      continue;
    }
    final _DayRecord rec = days.putIfAbsent(when, () => _DayRecord(when));
    rec.kcal += e.calories;
    rec.proteinG += e.proteinG;
    rec.sodiumMg += e.sodiumMg;
    rec.sugarG += e.sugarG;
    rec.slots.add(e.slot);
    rec.meals.add((
      slot: e.slot,
      names: e.foodNames,
      kcal: pyRound(e.calories),
      protein: pyRound(e.proteinG),
      sodium: pyRound(e.sodiumMg),
      sugar: pyRound(e.sugarG),
    ));
  }
  return days;
}

// ── 이번 주 ─────────────────────────────────────────────────────────────

/// (scope, 시작, 끝) — 월·화이고 이번 주 기록이 이틀 미만이며 지난주 기록이 있으면 지난주.
({String scope, DateTime start, DateTime end}) weekWindow(
  DateTime today,
  Iterable<DateTime> recorded,
) {
  final DateTime monday = mondayOf(today);
  final int thisWeekDays = recorded
      .where((DateTime d) => !d.isBefore(monday) && !d.isAfter(today))
      .length;
  final DateTime lastMonday = DateTime(
    monday.year,
    monday.month,
    monday.day - 7,
  );
  final bool hasLast = recorded.any(
    (DateTime d) => !d.isBefore(lastMonday) && d.isBefore(monday),
  );
  if (today.weekday <= DateTime.tuesday && thisWeekDays < 2 && hasLast) {
    return (
      scope: 'last',
      start: lastMonday,
      end: DateTime(monday.year, monday.month, monday.day - 1),
    );
  }
  return (scope: 'this', start: monday, end: today);
}

/// 이번 주 — 끼니 습관 → 넘친 영양(가장 큰 끼니) → 모자란 단백질 → 칭찬.
({DateTime start, DateTime end, int logged, List<ClientDietSentence> sentences})
weekSentences(
  List<DietRuleEntry> entries,
  DietRuleTargets targets,
  DateTime now,
) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final Map<DateTime, _DayRecord> all = _dayRecords(entries);
  final w = weekWindow(today, all.keys);
  final Map<DateTime, _DayRecord> records = <DateTime, _DayRecord>{
    for (final MapEntry<DateTime, _DayRecord> e in all.entries)
      if (!e.key.isBefore(w.start) && !e.key.isAfter(w.end)) e.key: e.value,
  };
  if (records.isEmpty) {
    return (
      start: w.start,
      end: w.end,
      logged: 0,
      sentences: const <ClientDietSentence>[
        ClientDietSentence('tr_week_empty'),
      ],
    );
  }
  final int logged = records.length;
  final String scope = w.scope;
  List<ClientDietSentence> one(String key, Map<String, Object> p) =>
      <ClientDietSentence>[ClientDietSentence(key, p)];
  ({
    DateTime start,
    DateTime end,
    int logged,
    List<ClientDietSentence> sentences,
  })
  done(List<ClientDietSentence> s) =>
      (start: w.start, end: w.end, logged: logged, sentences: s);

  final List<_DayRecord> days = records.values.toList()
    ..sort((_DayRecord a, _DayRecord b) => a.day.compareTo(b.day));
  final bool breakfastOver =
      now.hour + now.minute / 60 >= _breakfastDeadlineHour;
  final List<_DayRecord> finished = <_DayRecord>[
    for (final _DayRecord r in days)
      if (r.day.isBefore(today) || (r.day == today && breakfastOver)) r,
  ];
  final List<_DayRecord> closed = <_DayRecord>[
    for (final _DayRecord r in days)
      if (r.day.isBefore(today)) r,
  ];

  final List<_DayRecord> skipped = <_DayRecord>[
    for (final _DayRecord r in finished)
      if (!r.slots.contains('breakfast')) r,
  ];
  if (skipped.length >= _skipBreakfastMin) {
    final int withSnack = skipped
        .where((_DayRecord r) => r.slots.any(_snacks.contains))
        .length;
    if (withSnack >= _skipSnackMin) {
      return done(
        one('tr_week_skip_breakfast_snack', <String, Object>{
          'scope': scope,
          'logged': logged,
          'days': skipped.length,
          'snack_days': withSnack,
        }),
      );
    }
    return done(
      one('tr_week_skip_breakfast', <String, Object>{
        'scope': scope,
        'logged': logged,
        'days': skipped.length,
      }),
    );
  }

  final Map<String, List<_DayRecord>> counted = <String, List<_DayRecord>>{
    'sodium': <_DayRecord>[
      for (final _DayRecord r in days)
        if (r.sodiumMg > targets.sodiumMg) r,
    ],
    'calorie': <_DayRecord>[
      for (final _DayRecord r in days)
        if (r.kcal > targets.calories * _calorieOverRatio) r,
    ],
    'sugar': <_DayRecord>[
      for (final _DayRecord r in days)
        if (r.sugarG > targets.sugarG) r,
    ],
    'protein': <_DayRecord>[
      for (final _DayRecord r in closed)
        if (r.mainMeals >= _proteinMinMeals &&
            r.proteinG < targets.proteinG * _proteinShortRatio)
          r,
    ],
  };
  String kind = _focusOrder.first;
  for (final String k in _focusOrder.skip(1)) {
    if (counted[k]!.length > counted[kind]!.length) kind = k;
  }
  final List<_DayRecord> hits = counted[kind]!;
  if (hits.length < _focusMinDays) {
    return done(
      one('tr_week_good', <String, Object>{'scope': scope, 'days': logged}),
    );
  }
  if (kind == 'protein') {
    return done(
      one('tr_week_protein_short', <String, Object>{
        'scope': scope,
        'logged': logged,
        'days': hits.length,
      }),
    );
  }
  final List<ClientDietSentence> out = <ClientDietSentence>[
    ClientDietSentence('tr_week_over', <String, Object>{
      'scope': scope,
      'logged': logged,
      'days': hits.length,
      'nutrient': kind,
    }),
  ];
  int valueOf(_Meal m) => switch (kind) {
    'calorie' => m.kcal,
    'sodium' => m.sodium,
    _ => m.sugar,
  };
  ({DateTime day, _Meal meal})? best;
  for (final _DayRecord r in hits) {
    for (final _Meal m in r.meals) {
      if (best == null || valueOf(m) > valueOf(best.meal)) {
        best = (day: r.day, meal: m);
      }
    }
  }
  if (best != null && best.meal.names.isNotEmpty) {
    out.add(
      ClientDietSentence('tr_week_cause', <String, Object>{
        'weekday': best.day.weekday - 1,
        'slot': best.meal.slot,
        'food': best.meal.names.join(', '),
        'food_value': valueOf(best.meal),
        'nutrient': kind,
      }),
    );
  }
  return done(out);
}

// ── 전체(최근 4주) ──────────────────────────────────────────────────────

ClientDietSentence? _foodsSentence(List<MapEntry<String, int>> ranked) {
  final List<MapEntry<String, int>> top = ranked.take(_topFoods).toList();
  if (top.isEmpty) return null;
  if (top.length == 1) {
    return ClientDietSentence('tr_foods_one', <String, Object>{
      'food1': top[0].key,
      'count1': top[0].value,
    });
  }
  return ClientDietSentence('tr_foods_two', <String, Object>{
    'food1': top[0].key,
    'count1': top[0].value,
    'food2': top[1].key,
    'count2': top[1].value,
  });
}

/// 전체 — 회원 앱과 같은 최근 4주 판정 하나 + 원인 음식. 트레이너 화면은 지난주에
/// 말한 종류를 건너뛰지 않는다(서버와 같다).
({int logged, List<ClientDietSentence> sentences}) allSentences(
  List<DietRuleEntry> entries,
  DietRuleTargets targets,
  DateTime today,
) {
  final Map<DateTime, _DayRecord> records = _dayRecords(entries);
  final int days = records.length;
  ({int logged, List<ClientDietSentence> sentences}) done(
    List<ClientDietSentence> s,
  ) => (logged: days, sentences: s);
  if (days < _allMinDays) {
    return done(<ClientDietSentence>[
      ClientDietSentence('tr_all_few', <String, Object>{'days': days}),
    ]);
  }

  // 끼니별 나트륨.
  ({String slot, int days})? slotBest;
  for (final String slot in _main) {
    final List<({DateTime day, _Meal meal})> meals =
        <({DateTime day, _Meal meal})>[
          for (final MapEntry<DateTime, _DayRecord> r in records.entries)
            for (final _Meal m in r.value.meals)
              if (m.slot == slot) (day: r.key, meal: m),
        ];
    final Set<DateTime> slotDays = <DateTime>{for (final x in meals) x.day};
    final Set<DateTime> highDays = <DateTime>{
      for (final x in meals)
        if (x.meal.sodium > targets.sodiumMg * _slotSodiumRatio) x.day,
    };
    if (highDays.length < _slotSodiumMin ||
        highDays.length < slotDays.length * _slotSodiumShare) {
      continue;
    }
    if (slotBest == null || highDays.length > slotBest.days) {
      slotBest = (slot: slot, days: highDays.length);
    }
  }
  if (slotBest != null) {
    final String slot = slotBest.slot;
    final double limit = targets.sodiumMg * _slotSodiumRatio;
    final ClientDietSentence? extra = _foodsSentence(
      _mostCommon(<String>[
        for (final _DayRecord r in records.values)
          for (final _Meal m in r.meals)
            if (m.slot == slot && m.sodium > limit) ...m.names,
      ]),
    );
    return done(<ClientDietSentence>[
      ClientDietSentence('tr_all_slot_sodium', <String, Object>{
        'slot': slot,
        'days': slotBest.days,
      }),
      ?extra,
    ]);
  }

  // 탄단지 편중.
  num carbs = 0, protein = 0, fat = 0;
  for (final DietRuleEntry e in entries) {
    carbs += e.carbsG;
    protein += e.proteinG;
    fat += e.fatG;
  }
  final num energy = carbs * 4 + protein * 4 + fat * 9;
  if (energy > 0) {
    final int carbPct = pyRound(carbs * 4 * 100 / energy);
    final int proteinPct = pyRound(protein * 4 * 100 / energy);
    final String? key = carbPct >= _carbHeavyPct
        ? 'tr_all_carb_heavy'
        : proteinPct <= _proteinLightPct
        ? 'tr_all_protein_light'
        : null;
    if (key != null) {
      final ClientDietSentence? extra = _foodsSentence(
        _mostCommon(<String>[
          for (final DietRuleEntry e in entries) ...e.foodNames,
        ]),
      );
      return done(<ClientDietSentence>[
        ClientDietSentence(key, <String, Object>{
          'pct': key == 'tr_all_carb_heavy' ? carbPct : proteinPct,
        }),
        ?extra,
      ]);
    }
  }

  // 단백질 추세 — 최근 2주와 그 전.
  final DateTime split = DateTime(today.year, today.month, today.day - 13);
  final List<_DayRecord> recent = <_DayRecord>[
    for (final MapEntry<DateTime, _DayRecord> r in records.entries)
      if (!r.key.isBefore(split) && r.key.isBefore(today)) r.value,
  ];
  final List<_DayRecord> before = <_DayRecord>[
    for (final MapEntry<DateTime, _DayRecord> r in records.entries)
      if (r.key.isBefore(split)) r.value,
  ];
  if (recent.length >= _trendMinDays && before.length >= _trendMinDays) {
    int met(List<_DayRecord> rs) => rs
        .where(
          (_DayRecord r) => r.proteinG >= targets.proteinG * _proteinMetRatio,
        )
        .length;
    final int a = met(before), b = met(recent);
    if ((b - a).abs() >= _trendMinDiff) {
      return done(<ClientDietSentence>[
        ClientDietSentence(
          b > a ? 'tr_all_protein_trend_up' : 'tr_all_protein_trend_down',
          <String, Object>{'before': a, 'after': b},
        ),
      ]);
    }
  }

  // 자주 먹은 메뉴.
  ({String slot, String food, int count})? frequent;
  for (final String slot in _main) {
    for (final MapEntry<String, int> e in _mostCommon(<String>[
      for (final _DayRecord r in records.values)
        for (final _Meal m in r.meals)
          if (m.slot == slot) ...m.names,
    ])) {
      if (e.key.runes.length > _frequentNameMax) continue;
      if (e.value >= _frequentMin &&
          (frequent == null || e.value > frequent.count)) {
        frequent = (slot: slot, food: e.key, count: e.value);
      }
      break;
    }
  }
  if (frequent != null) {
    return done(<ClientDietSentence>[
      ClientDietSentence('tr_all_frequent', <String, Object>{
        'slot': frequent.slot,
        'food': frequent.food,
        'count': frequent.count,
      }),
    ]);
  }

  // 반복 음식.
  final List<MapEntry<String, int>> ranked = _mostCommon(<String>[
    for (final _DayRecord r in records.values)
      for (final _Meal m in r.meals) ...m.names,
  ]);
  final int total = ranked.fold<int>(
    0,
    (int s, MapEntry<String, int> e) => s + e.value,
  );
  if (total >= _repeatedMinItems && ranked.length >= 2) {
    final MapEntry<String, int> a = ranked[0], b = ranked[1];
    if ((a.value + b.value) / total >= _repeatedShare &&
        a.key.runes.length <= _frequentNameMax &&
        b.key.runes.length <= _frequentNameMax) {
      return done(<ClientDietSentence>[
        ClientDietSentence('tr_all_repeated', <String, Object>{
          'food1': a.key,
          'food2': b.key,
        }),
      ]);
    }
  }

  return done(<ClientDietSentence>[
    ClientDietSentence('tr_all_good', <String, Object>{'days': days}),
  ]);
}

/// [today] 로부터 [days] 일 전(포함)의 `YYYY-MM-DD`.
String daysBefore(DateTime today, int days) =>
    wireDate(DateTime(today.year, today.month, today.day - days));
