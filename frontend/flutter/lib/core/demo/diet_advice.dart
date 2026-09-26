/// 데모 모드의 식단 AI 맞춤 조언 — 규칙 한 줄 + 다음 할 일. (#2255)
///
/// 실 서버는 `GET /diet/advice` 가 이 말을 한다(`diet_period_advice`·
/// `diet_week_advice`·`diet_all_advice`). 데모에는 그 서버가 없으므로 **같은 규칙**을
/// 여기서 재현한다 — 데모로 본 화면과 실 연동으로 본 화면이 다른 말을 하면, 시연에서
/// 확인한 것이 무엇이었는지 알 수 없게 된다. 두 쪽이 같은 결과를 내는지는 공유 사례
/// (`test/core/demo/diet_advice_cases.json`)로 본다.
///
/// 데모와 서버가 다른 점(데모에는 AI·저장소가 없다):
/// - 이번 주·전체의 다음 할 일은 AI 문장 대신 **AI 가 실패했을 때의 규칙 문장**이다.
/// - 추천 메뉴 리스트는 서버가 기록 없는 회원에게 만드는 카탈로그 리스트로 고정이다.
/// - 최근 3일 안에 추천한 메뉴를 미루지 않고, 이번 주(하루)·전체(한 주) 조언을 두지
///   않고 부를 때마다 계산한다. 지난주 전체 조언의 종류도 기억하지 않는다.
///
/// 규칙도 문장도 서버 쪽이 원본이다. 한쪽을 고치면 다른 쪽도 함께 고치고, 서버의
/// `scripts/gen_diet_advice_cases.py` 로 사례 파일을 다시 만든다.
library;

import 'dart:ui' show Locale;

import 'package:oncare/core/advice/diet_advice.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 끼니 한 행. 탄단지는 음식에서 되짚은 값이다.
typedef DemoDietEntry = ({
  String date,
  String mealType,
  List<String> foods,
  num kcal,
  num proteinG,
  num sodiumMg,
  num sugarG,
  num carbsG,
  num fatG,
});

/// 하루 목표. 서버 `diet_coach_inputs.targets_of` 와 같은 기본값을 쓴다.
typedef DemoDietTargets = ({
  int calories,
  int proteinG,
  int sodiumMg,
  int sugarG,
});

/// 추천 메뉴 한 개.
typedef DemoPlanMenu = ({String slot, String name, String tag, String keyword});

/// 개인 목표 → 하루 목표. 단백질은 목표 → 체중 × 1.2g → 60g 순이다.
DemoDietTargets demoDietTargets(Map<String, Object?> profile) {
  int? positive(Object? v) => v is num && v > 0 ? v.toInt() : null;
  final num? weight = profile['weight_kg'] as num?;
  return (
    calories: positive(profile['daily_calories']) ?? 2000,
    proteinG:
        positive(profile['daily_protein_g']) ??
        (weight != null && weight > 0 ? pyRound(weight * 1.2) : 60),
    sodiumMg: positive(profile['daily_sodium_mg']) ?? 2000,
    sugarG: positive(profile['daily_sugar_g']) ?? 50,
  );
}

/// 파이썬 `round()` 와 같은 반올림(0.5 는 짝수 쪽). 서버와 수치를 맞춘다.
int pyRound(num x) {
  final int f = x.floor();
  final num diff = x - f;
  if (diff > 0.5) return f + 1;
  if (diff < 0.5) return f;
  return f.isEven ? f : f + 1;
}

// ── 공통 ───────────────────────────────────────────────────────────────

const String _breakfast = 'breakfast';
const String _lunch = 'lunch';
const String _dinner = 'dinner';
const String _snack = 'snack';
const List<String> _mainSlots = <String>[_breakfast, _lunch, _dinner];
const Set<String> _snackSlots = <String>{'snack', 'lateNight'};

/// 아침·점심·저녁이 끝났다고 보는 시각(분).
const Map<String, int> _deadlines = <String, int>{
  _breakfast: 11 * 60,
  _lunch: 15 * 60,
  _dinner: 21 * 60,
};

const String _sodiumLow = 'sodium_low';
const String _proteinHigh = 'protein_high';
const String _calorieLow = 'calorie_low';
const String _calorieHigh = 'calorie_high';
const String _sugarLow = 'sugar_low';
const List<String> _tags = <String>[
  _proteinHigh,
  _sodiumLow,
  'fiber_high',
  _calorieLow,
  _sugarLow,
  _calorieHigh,
];

typedef _Line = ({String key, Map<String, Object> params});

_Line _line(
  String key, [
  Map<String, Object> params = const <String, Object>{},
]) => (key: key, params: params);

DateTime _day(String iso) {
  final List<String> p = iso.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _plusDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

String normName(String name) =>
    name.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// 끼니 한 번 — (끼니, 음식 이름, 칼로리, 단백질, 나트륨, 당류). 수는 반올림한 값이다.
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
  num protein = 0;
  num sodium = 0;
  num sugar = 0;
  final Set<String> slots = <String>{};
  final List<_Meal> meals = <_Meal>[];

  int get mainMeals => slots.where(_mainSlots.contains).length;
}

/// 날짜별 기록 — 들어온 순서를 지킨다(서버 dict 와 같은 순서라야 동점이 같게 갈린다).
Map<DateTime, _DayRecord> _dayRecords(List<DemoDietEntry> entries) {
  final Map<DateTime, _DayRecord> days = <DateTime, _DayRecord>{};
  for (final DemoDietEntry e in entries) {
    final DateTime when = _day(e.date);
    final _DayRecord rec = days.putIfAbsent(when, () => _DayRecord(when));
    rec.kcal += e.kcal;
    rec.protein += e.proteinG;
    rec.sodium += e.sodiumMg;
    rec.sugar += e.sugarG;
    rec.slots.add(e.mealType);
    rec.meals.add((
      slot: e.mealType,
      names: e.foods,
      kcal: pyRound(e.kcal),
      protein: pyRound(e.proteinG),
      sodium: pyRound(e.sodiumMg),
      sugar: pyRound(e.sugarG),
    ));
  }
  return days;
}

/// 파이썬 `Counter.most_common()` — 많은 순, 같으면 먼저 나온 순.
List<MapEntry<String, int>> _mostCommon(Iterable<String> names) {
  final Map<String, int> counts = <String, int>{};
  for (final String n in names) {
    counts[n] = (counts[n] ?? 0) + 1;
  }
  final List<String> order = counts.keys.toList();
  final List<MapEntry<String, int>> rows = counts.entries.toList();
  rows.sort((MapEntry<String, int> a, MapEntry<String, int> b) {
    final int byCount = b.value.compareTo(a.value);
    return byCount != 0 ? byCount : order.indexOf(a.key) - order.indexOf(b.key);
  });
  return rows;
}

// ── 오늘 ───────────────────────────────────────────────────────────────

typedef _TodayDecision = ({
  _Line analysis,
  String? slot,
  List<String> needs,
  Set<String> satisfied,
  _Line? action,
});

_TodayDecision _decideToday(
  List<DemoDietEntry> entries,
  DemoDietTargets t,
  int minutes,
) {
  final bool has = entries.isNotEmpty;
  final int kcal = pyRound(
    entries.fold<num>(0, (num a, DemoDietEntry e) => a + e.kcal),
  );
  final num protein = entries.fold<num>(
    0,
    (num a, DemoDietEntry e) => a + e.proteinG,
  );
  final int sodium = pyRound(
    entries.fold<num>(0, (num a, DemoDietEntry e) => a + e.sodiumMg),
  );
  final num sugar = entries.fold<num>(
    0,
    (num a, DemoDietEntry e) => a + e.sugarG,
  );
  final Set<String> slots = <String>{
    for (final DemoDietEntry e in entries) e.mealType,
  };
  final num gap = t.proteinG - protein;

  final bool missing = _mainSlots.any(
    (String s) => !slots.contains(s) && minutes >= _deadlines[s]!,
  );
  final _Line analysis;
  if (!has) {
    analysis = _line('today_empty');
  } else if (missing) {
    analysis = _line('today_missing_meal');
  } else if (sodium > t.sodiumMg) {
    analysis = _line('today_sodium_over', <String, Object>{
      'sodium_mg': sodium,
    });
  } else if (kcal > t.calories * 1.1) {
    analysis = _line('today_calorie_over', <String, Object>{'kcal': kcal});
  } else if (pyRound(gap) >= 10) {
    analysis = _line('today_protein_left', <String, Object>{
      'protein_g': pyRound(gap),
    });
  } else {
    analysis = _line('today_balanced', <String, Object>{'kcal': kcal});
  }

  if (analysis.key == 'today_missing_meal') {
    return (
      analysis: analysis,
      slot: null,
      needs: const <String>[],
      satisfied: const <String>{},
      action: _line('today_log_first'),
    );
  }

  final List<int> logged = <int>[
    for (int i = 0; i < _mainSlots.length; i++)
      if (slots.contains(_mainSlots[i])) i,
  ];
  final int after = logged.isEmpty
      ? -1
      : logged.reduce((int a, int b) => a > b ? a : b);
  String? slot;
  for (int i = 0; i < _mainSlots.length; i++) {
    if (i > after && minutes < _deadlines[_mainSlots[i]]!) {
      slot = _mainSlots[i];
      break;
    }
  }

  List<String> needs = <String>[];
  if (slot != null) {
    if (has) {
      if (sodium >= t.sodiumMg * 0.6) needs.add(_sodiumLow);
      if (gap >= 10) needs.add(_proteinHigh);
      if (kcal >= t.calories * 0.9) needs.add(_calorieLow);
      if (sugar >= t.sugarG * 0.7) needs.add(_sugarLow);
    }
  } else if (has) {
    needs = <String>[
      if (gap >= 10) _proteinHigh,
      if (kcal <= t.calories * 0.7) _calorieHigh,
    ];
    slot = needs.isEmpty ? null : _snack;
  }
  if (slot == null) {
    return (
      analysis: analysis,
      slot: null,
      needs: const <String>[],
      satisfied: const <String>{},
      action: has ? _line('today_done') : null,
    );
  }
  return (
    analysis: analysis,
    slot: slot,
    needs: needs,
    satisfied: <String>{if (has && gap < 10) _proteinHigh},
    action: null,
  );
}

DemoPlanMenu? _pickMenu(
  List<DemoPlanMenu> menus,
  List<String> needs,
  Set<String> recent,
  Set<String> satisfied,
) {
  final List<String> order = <String>[
    ...needs,
    for (final String t in _tags)
      if (t != _calorieHigh && !needs.contains(t) && !satisfied.contains(t)) t,
  ];
  if (needs.contains(_calorieLow)) order.remove(_calorieHigh);
  for (final String tag in order) {
    final List<DemoPlanMenu> ofTag = menus
        .where((DemoPlanMenu m) => m.tag == tag)
        .toList();
    final List<DemoPlanMenu> fresh = ofTag
        .where((DemoPlanMenu m) => !recent.contains(normName(m.name)))
        .toList();
    if (fresh.isNotEmpty) return fresh.first;
    if (ofTag.isNotEmpty && needs.contains(tag)) return ofTag.first;
  }
  return menus.isEmpty ? null : menus.first;
}

// ── 이번 주 ────────────────────────────────────────────────────────────

const List<String> _focusOrder = <String>[
  'sodium',
  'calorie',
  'sugar',
  'protein',
];
const Map<String, String> _focusTips = <String, String>{
  'sodium': 'tip_sodium',
  'calorie': 'tip_calorie',
  'sugar': 'tip_sugar',
  'protein': 'tip_protein',
};

({String from, String to, int days, _Line analysis, _Line action}) _decideWeek(
  List<DemoDietEntry> entries,
  DemoDietTargets t,
  DateTime today,
  int minutes,
) {
  final DateTime monday = _plusDays(today, -(today.weekday - DateTime.monday));
  final DateTime lastMonday = _plusDays(monday, -7);
  final Map<DateTime, _DayRecord> all = _dayRecords(
    entries.where((DemoDietEntry e) {
      final DateTime d = _day(e.date);
      return !d.isBefore(lastMonday) && !d.isAfter(today);
    }).toList(),
  );
  final int thisWeek = all.keys
      .where((DateTime d) => !d.isBefore(monday))
      .length;
  final bool hasLast = all.keys.any((DateTime d) => d.isBefore(monday));
  final bool back =
      today.weekday <= DateTime.tuesday && thisWeek < 2 && hasLast;
  final String scope = back ? 'last' : 'this';
  final DateTime start = back ? lastMonday : monday;
  final DateTime end = back ? _plusDays(monday, -1) : today;
  final List<_DayRecord> days =
      all.values
          .where(
            (_DayRecord r) => !r.day.isBefore(start) && !r.day.isAfter(end),
          )
          .toList()
        ..sort((_DayRecord a, _DayRecord b) => a.day.compareTo(b.day));
  if (days.isEmpty) {
    return (
      from: _iso(start),
      to: _iso(end),
      days: 0,
      analysis: _line('week_empty'),
      action: _line('week_empty_hint'),
    );
  }

  final List<_DayRecord> finished = days
      .where(
        (_DayRecord r) =>
            r.day.isBefore(today) || (r.day == today && minutes >= 11 * 60),
      )
      .toList();
  final List<_DayRecord> closed = days
      .where((_DayRecord r) => r.day.isBefore(today))
      .toList();
  final List<_DayRecord> skipped = finished
      .where((_DayRecord r) => !r.slots.contains(_breakfast))
      .toList();

  _Line analysis;
  String tip;
  if (skipped.length >= 3) {
    final int withSnack = skipped
        .where((_DayRecord r) => r.slots.any(_snackSlots.contains))
        .length;
    analysis = withSnack >= 2
        ? _line('week_skip_breakfast_snack', <String, Object>{
            'scope': scope,
            'days': skipped.length,
            'snack_days': withSnack,
          })
        : _line('week_skip_breakfast', <String, Object>{
            'scope': scope,
            'days': skipped.length,
          });
    tip = 'tip_breakfast';
  } else {
    final Map<String, int> counted = <String, int>{
      'sodium': days.where((_DayRecord r) => r.sodium > t.sodiumMg).length,
      'calorie': days.where((_DayRecord r) => r.kcal > t.calories * 1.1).length,
      'sugar': days.where((_DayRecord r) => r.sugar > t.sugarG).length,
      'protein': closed
          .where(
            (_DayRecord r) => r.mainMeals >= 2 && r.protein < t.proteinG * 0.8,
          )
          .length,
    };
    String kind = _focusOrder.first;
    for (final String k in _focusOrder) {
      if (counted[k]! > counted[kind]!) kind = k;
    }
    if (counted[kind]! >= 1) {
      analysis = _line('week_focus_$kind', <String, Object>{
        'scope': scope,
        'days': counted[kind]!,
      });
      tip = _focusTips[kind]!;
    } else {
      analysis = _line('week_good', <String, Object>{
        'scope': scope,
        'days': days.length,
      });
      tip = 'tip_keep';
    }
  }
  return (
    from: _iso(start),
    to: _iso(end),
    days: days.length,
    analysis: analysis,
    action: _line(tip),
  );
}

// ── 전체(최근 4주) ─────────────────────────────────────────────────────

const Map<String, String> _allTips = <String, String>{
  'all_slot_sodium': 'tip_sodium',
  'all_carb_heavy': 'tip_carb',
  'all_protein_light': 'tip_protein',
  'all_protein_trend_up': 'tip_keep',
  'all_protein_trend_down': 'tip_protein',
  'all_frequent_menu': 'tip_swap',
  'all_repeated_foods': 'tip_variety',
};

typedef _Finding = ({String kind, _Line analysis});

_Finding? _slotSodium(Map<DateTime, _DayRecord> records, DemoDietTargets t) {
  ({String slot, int days})? best;
  for (final String slot in _mainSlots) {
    final Set<DateTime> slotDays = <DateTime>{};
    final Set<DateTime> highDays = <DateTime>{};
    for (final _DayRecord r in records.values) {
      for (final _Meal m in r.meals) {
        if (m.slot != slot) continue;
        slotDays.add(r.day);
        if (m.sodium > t.sodiumMg * 0.5) highDays.add(r.day);
      }
    }
    if (highDays.length < 4 || highDays.length < slotDays.length * 0.3) {
      continue;
    }
    if (best == null || highDays.length > best.days) {
      best = (slot: slot, days: highDays.length);
    }
  }
  if (best == null) return null;
  return (
    kind: 'slot_sodium',
    analysis: _line('all_slot_sodium', <String, Object>{
      'slot': best.slot,
      'days': best.days,
    }),
  );
}

_Finding? _macro(List<DemoDietEntry> entries) {
  final num carbs = entries.fold<num>(
    0,
    (num a, DemoDietEntry e) => a + e.carbsG,
  );
  final num protein = entries.fold<num>(
    0,
    (num a, DemoDietEntry e) => a + e.proteinG,
  );
  final num fat = entries.fold<num>(0, (num a, DemoDietEntry e) => a + e.fatG);
  final num energy = carbs * 4 + protein * 4 + fat * 9;
  if (energy <= 0) return null;
  final int carbPct = pyRound(carbs * 4 * 100 / energy);
  final int proteinPct = pyRound(protein * 4 * 100 / energy);
  if (carbPct >= 65) {
    return (
      kind: 'macro',
      analysis: _line('all_carb_heavy', <String, Object>{'pct': carbPct}),
    );
  }
  if (proteinPct <= 15) {
    return (
      kind: 'macro',
      analysis: _line('all_protein_light', <String, Object>{'pct': proteinPct}),
    );
  }
  return null;
}

_Finding? _trend(
  Map<DateTime, _DayRecord> records,
  DemoDietTargets t,
  DateTime today,
) {
  final DateTime split = _plusDays(today, -13);
  final List<_DayRecord> recent = records.values
      .where((_DayRecord r) => !r.day.isBefore(split) && r.day.isBefore(today))
      .toList();
  final List<_DayRecord> before = records.values
      .where((_DayRecord r) => r.day.isBefore(split))
      .toList();
  if (recent.length < 3 || before.length < 3) return null;
  int met(List<_DayRecord> rs) =>
      rs.where((_DayRecord r) => r.protein >= t.proteinG * 0.9).length;
  final int a = met(before);
  final int b = met(recent);
  if ((b - a).abs() < 2) return null;
  return (
    kind: 'trend',
    analysis: _line(
      b > a ? 'all_protein_trend_up' : 'all_protein_trend_down',
      <String, Object>{'before': a, 'after': b},
    ),
  );
}

_Finding? _frequent(Map<DateTime, _DayRecord> records) {
  ({String slot, String name, int count})? best;
  for (final String slot in _mainSlots) {
    final List<MapEntry<String, int>> counts = _mostCommon(<String>[
      for (final _DayRecord r in records.values)
        for (final _Meal m in r.meals)
          if (m.slot == slot) ...m.names,
    ]);
    for (final MapEntry<String, int> e in counts) {
      if (e.key.runes.length > 6) continue;
      if (e.value >= 5 && (best == null || e.value > best.count)) {
        best = (slot: slot, name: e.key, count: e.value);
      }
      break;
    }
  }
  if (best == null) return null;
  return (
    kind: 'frequent',
    analysis: _line('all_frequent_menu', <String, Object>{
      'slot': best.slot,
      'food': best.name,
      'count': best.count,
    }),
  );
}

_Finding? _repeated(Map<DateTime, _DayRecord> records) {
  final List<MapEntry<String, int>> counts = _mostCommon(<String>[
    for (final _DayRecord r in records.values)
      for (final _Meal m in r.meals) ...m.names,
  ]);
  final int total = counts.fold<int>(
    0,
    (int a, MapEntry<String, int> e) => a + e.value,
  );
  if (total < 20 || counts.length < 2) return null;
  final MapEntry<String, int> a = counts[0];
  final MapEntry<String, int> b = counts[1];
  if ((a.value + b.value) / total < 0.25 ||
      a.key.runes.length > 6 ||
      b.key.runes.length > 6) {
    return null;
  }
  return (
    kind: 'repeated',
    analysis: _line('all_repeated_foods', <String, Object>{
      'food1': a.key,
      'food2': b.key,
    }),
  );
}

({String from, String to, int days, _Line analysis, _Line action}) _decideAll(
  List<DemoDietEntry> entries,
  DemoDietTargets t,
  DateTime today,
  String? lastKind,
) {
  final DateTime start = _plusDays(today, -27);
  final List<DemoDietEntry> window = entries.where((DemoDietEntry e) {
    final DateTime d = _day(e.date);
    return !d.isBefore(start) && !d.isAfter(today);
  }).toList();
  final Map<DateTime, _DayRecord> records = _dayRecords(window);
  final String from = _iso(start);
  final String to = _iso(today);
  if (records.length < 7) {
    return (
      from: from,
      to: to,
      days: records.length,
      analysis: _line('all_few_records', <String, Object>{
        'days': records.length,
      }),
      action: _line('all_few_hint'),
    );
  }
  final List<_Finding> candidates = <_Finding>[
    ?_slotSodium(records, t),
    ?_macro(window),
    ?_trend(records, t, today),
    ?_frequent(records),
    ?_repeated(records),
  ];
  final List<_Finding> fresh = candidates
      .where((_Finding f) => f.kind != lastKind)
      .toList();
  final _Finding? chosen = fresh.isNotEmpty
      ? fresh.first
      : (candidates.isNotEmpty ? candidates.first : null);
  final _Line analysis =
      chosen?.analysis ??
      _line('all_good', <String, Object>{'days': records.length});
  return (
    from: from,
    to: to,
    days: records.length,
    analysis: analysis,
    action: _line(_allTips[analysis.key] ?? 'tip_keep'),
  );
}

// ── 응답 ───────────────────────────────────────────────────────────────

/// 서버가 기록 없는 회원에게 만드는 카탈로그 리스트(`diet_menu_plan.rules_plan`).
/// 공유 사례 파일의 `demo_plan` 과 같은지 테스트가 본다.
const Map<String, List<DemoPlanMenu>>
kDemoMenuPlan = <String, List<DemoPlanMenu>>{
  'ko': <DemoPlanMenu>[
    (slot: 'breakfast', name: '그릭요거트 볼', tag: 'protein_high', keyword: '고단백'),
    (slot: 'breakfast', name: '현미 누룽지와 달걀', tag: 'sodium_low', keyword: '저나트륨'),
    (slot: 'breakfast', name: '바나나 오트밀', tag: 'fiber_high', keyword: '식이섬유'),
    (slot: 'breakfast', name: '과일 요거트 스무디', tag: 'calorie_low', keyword: '가벼운'),
    (slot: 'breakfast', name: '요거트와 견과', tag: 'sugar_low', keyword: '저당'),
    (slot: 'lunch', name: '닭가슴살 샐러드', tag: 'protein_high', keyword: '고단백'),
    (slot: 'lunch', name: '두부 스테이크 정식', tag: 'sodium_low', keyword: '저나트륨'),
    (slot: 'lunch', name: '현미 비빔밥', tag: 'fiber_high', keyword: '식이섬유'),
    (slot: 'lunch', name: '닭안심 샐러드 랩', tag: 'calorie_low', keyword: '가벼운'),
    (slot: 'lunch', name: '곤약 채소 비빔밥', tag: 'sugar_low', keyword: '저당'),
    (slot: 'dinner', name: '구운 고등어 정식', tag: 'protein_high', keyword: '고단백'),
    (slot: 'dinner', name: '연두부 채소찜', tag: 'sodium_low', keyword: '저나트륨'),
    (slot: 'dinner', name: '잡곡밥과 나물 반찬', tag: 'fiber_high', keyword: '식이섬유'),
    (slot: 'dinner', name: '두부 닭가슴살볼', tag: 'calorie_low', keyword: '가벼운'),
    (slot: 'dinner', name: '돼지 안심 수육', tag: 'sugar_low', keyword: '저당'),
    (slot: 'snack', name: '그릭요거트', tag: 'protein_high', keyword: '고단백'),
    (slot: 'snack', name: '방울토마토', tag: 'calorie_low', keyword: '가벼운'),
    (slot: 'snack', name: '무가당 두유', tag: 'sugar_low', keyword: '저당'),
  ],
  'en': <DemoPlanMenu>[
    (
      slot: 'breakfast',
      name: 'Greek yogurt bowl',
      tag: 'protein_high',
      keyword: 'High protein',
    ),
    (
      slot: 'breakfast',
      name: 'Brown rice porridge & egg',
      tag: 'sodium_low',
      keyword: 'Low sodium',
    ),
    (
      slot: 'breakfast',
      name: 'Banana oatmeal',
      tag: 'fiber_high',
      keyword: 'High fiber',
    ),
    (
      slot: 'breakfast',
      name: 'Fruit yogurt smoothie',
      tag: 'calorie_low',
      keyword: 'Light',
    ),
    (
      slot: 'breakfast',
      name: 'Plain yogurt & nuts',
      tag: 'sugar_low',
      keyword: 'Low sugar',
    ),
    (
      slot: 'lunch',
      name: 'Chicken breast salad',
      tag: 'protein_high',
      keyword: 'High protein',
    ),
    (
      slot: 'lunch',
      name: 'Tofu steak set',
      tag: 'sodium_low',
      keyword: 'Low sodium',
    ),
    (
      slot: 'lunch',
      name: 'Brown rice bibimbap',
      tag: 'fiber_high',
      keyword: 'High fiber',
    ),
    (
      slot: 'lunch',
      name: 'Chicken tender wrap',
      tag: 'calorie_low',
      keyword: 'Light',
    ),
    (
      slot: 'lunch',
      name: 'Konjac veggie bibimbap',
      tag: 'sugar_low',
      keyword: 'Low sugar',
    ),
    (
      slot: 'dinner',
      name: 'Grilled mackerel set',
      tag: 'protein_high',
      keyword: 'High protein',
    ),
    (
      slot: 'dinner',
      name: 'Steamed soft tofu & veggies',
      tag: 'sodium_low',
      keyword: 'Low sodium',
    ),
    (
      slot: 'dinner',
      name: 'Multigrain rice & namul',
      tag: 'fiber_high',
      keyword: 'High fiber',
    ),
    (
      slot: 'dinner',
      name: 'Chicken tofu patties',
      tag: 'calorie_low',
      keyword: 'Light',
    ),
    (
      slot: 'dinner',
      name: 'Boiled pork tenderloin',
      tag: 'sugar_low',
      keyword: 'Low sugar',
    ),
    (
      slot: 'snack',
      name: 'Greek yogurt',
      tag: 'protein_high',
      keyword: 'High protein',
    ),
    (
      slot: 'snack',
      name: 'Cherry tomatoes',
      tag: 'calorie_low',
      keyword: 'Light',
    ),
    (
      slot: 'snack',
      name: 'Unsweetened soy milk',
      tag: 'sugar_low',
      keyword: 'Low sugar',
    ),
  ],
};

final AppLocalizations _ko = lookupAppLocalizations(const Locale('ko'));

Map<String, Object?> _lineJson(String prefix, _Line? line) {
  if (line == null) {
    return <String, Object?>{
      prefix: '',
      '${prefix}_key': null,
      '${prefix}_params': <String, Object>{},
    };
  }
  return <String, Object?>{
    prefix: dietAdviceKeyText(_ko, line.key, line.params) ?? '',
    '${prefix}_key': line.key,
    '${prefix}_params': line.params,
  };
}

/// `GET /diet/advice` 응답 — 서버 `DietAdviceResponse` 와 같은 모양이다.
///
/// [entries] 는 최근 4주(오늘 포함)의 끼니다. [now] 는 KST 시각이다.
Map<String, Object?> demoDietAdvice({
  required String period,
  required String lang,
  required DateTime now,
  required List<DemoDietEntry> entries,
  required DemoDietTargets targets,
  Set<String> recent = const <String>{},
  String? lastKind,
}) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final int minutes = now.hour * 60 + now.minute;
  final String todayIso = _iso(today);

  late final String from;
  late final String to;
  late final int days;
  late final _Line analysis;
  _Line? action;
  String? source;
  if (period == 'today') {
    final List<DemoDietEntry> todays = entries
        .where((DemoDietEntry e) => e.date == todayIso)
        .toList();
    final _TodayDecision d = _decideToday(todays, targets, minutes);
    from = todayIso;
    to = todayIso;
    days = todays.isEmpty ? 0 : 1;
    analysis = d.analysis;
    action = d.action;
    source = action == null ? null : 'rules';
    if (d.slot != null) {
      final List<DemoPlanMenu> plan =
          kDemoMenuPlan[lang] ?? kDemoMenuPlan['ko']!;
      final DemoPlanMenu? menu = _pickMenu(
        plan.where((DemoPlanMenu m) => m.slot == d.slot).toList(),
        d.needs,
        recent,
        d.satisfied,
      );
      if (menu != null) {
        action = d.slot == _snack
            ? _line('next_snack', <String, Object>{
                'menu': menu.name,
                'keyword': menu.keyword,
              })
            : _line('next_meal', <String, Object>{
                'slot': d.slot!,
                'menu': menu.name,
                'keyword': menu.keyword,
              });
        source = 'plan';
      }
    }
  } else if (period == 'week') {
    final r = _decideWeek(entries, targets, today, minutes);
    from = r.from;
    to = r.to;
    days = r.days;
    analysis = r.analysis;
    action = r.action;
    source = 'rules';
  } else {
    final r = _decideAll(entries, targets, today, lastKind);
    from = r.from;
    to = r.to;
    days = r.days;
    analysis = r.analysis;
    action = r.action;
    source = 'rules';
  }

  final Map<String, Object?> a = _lineJson('analysis', analysis);
  final Map<String, Object?> b = _lineJson('action', action);
  final String message = <String>[
    a['analysis']! as String,
    b['action']! as String,
  ].where((String s) => s.isNotEmpty).join(' ').replaceAll('**', '');
  return <String, Object?>{
    'period': period,
    'from_date': from,
    'to_date': to,
    'days_logged': days,
    'message': message,
    ...a,
    ...b,
    'action_source': source,
  };
}
