/// 데모 모드의 기간별 AI 맞춤 조언. (#1574)
///
/// 실 서버는 `GET /diet/advice`·`GET /exercise/advice` 가 이 말을 한다
/// (`diet_service.period_coach_message`, `exercise_service.period_coach_message`).
/// 데모에는 그 서버가 없으므로 **같은 규칙을 같은 문장으로** 여기서 재현한다 —
/// 데모로 본 화면과 실 연동으로 본 화면이 다른 말을 하면, 시연에서 확인한 것이
/// 무엇이었는지 알 수 없게 된다.
///
/// 규칙도 문장도 서버 쪽이 원본이다. 한쪽을 고치면 다른 쪽도 함께 고친다.
library;

/// 하루치 식단 합계. **기록이 있는 날만** 들어온다 — 안 먹은 날과 기록하지 않은
/// 날은 다른 말이고, 평균이 그 차이를 삼키면 조언이 사실과 어긋난다.
typedef DietDayTotals = ({DateTime date, int sodiumMg});

/// 하루치 운동 합계. 식단과 같은 규칙으로 **기록이 있는 날만** 들어온다.
typedef ExerciseDayTotals = ({
  DateTime date,
  int minutes,
  int calories,
  Map<String, int> byType,
});

/// 하루 나트륨 상한(WHO 권고). 서버의 `diet_service.SODIUM_LIMIT_MG` 와 같은 값이다.
const int kSodiumLimitMg = 2000;

/// 기간 이름 — 화면의 기간 토글, 서버의 `period` 쿼리와 같은 말이다.
const String kPeriodToday = 'today';
const String kPeriodWeek = 'week';
const String kPeriodAll = 'all';

double _avg(List<int> values) => values.isEmpty
    ? 0
    : values.fold<int>(0, (int a, int b) => a + b) / values.length;

/// 주중(월~금)·주말(토·일) 나트륨을 갈라 담는다.
({List<int> weekday, List<int> weekend}) _weekdaySplit(
  List<DietDayTotals> days,
) => (
  weekday: <int>[
    for (final DietDayTotals d in days)
      if (d.date.weekday < DateTime.saturday) d.sodiumMg,
  ],
  weekend: <int>[
    for (final DietDayTotals d in days)
      if (d.date.weekday >= DateTime.saturday) d.sodiumMg,
  ],
);

/// 기간에 맞는 식단 조언. [days] 는 날짜순이고 기록이 있는 날만 든다.
String dietPeriodAdvice(List<DietDayTotals> days, String period) {
  if (days.isEmpty) {
    // 없는 기록으로 조언을 지어내지 않는다.
    if (period == kPeriodWeek) return '이번 주 식단 기록이 아직 없어요. 한 끼만 남겨도 흐름이 보여요.';
    if (period == kPeriodAll) return '기록이 쌓이면 나트륨·칼로리 흐름을 짚어 드릴게요.';
    return '오늘 식단 기록이 아직 없어요. 첫 끼니를 기록해 볼까요?';
  }

  final List<DietDayTotals> over = <DietDayTotals>[
    for (final DietDayTotals d in days)
      if (d.sodiumMg > kSodiumLimitMg) d,
  ];

  if (period == kPeriodWeek) {
    if (over.length >= 3) {
      return '이번 주 ${over.length}일이나 나트륨을 넘겼어요. 국물은 건더기 위주로 드세요.';
    }
    final ({List<int> weekday, List<int> weekend}) split = _weekdaySplit(days);
    if (split.weekend.isNotEmpty &&
        split.weekday.isNotEmpty &&
        _avg(split.weekend) > _avg(split.weekday) * 1.3) {
      return '주중엔 잘 지키다 주말에 나트륨이 올라요. 주말 외식은 한 끼만 정해요.';
    }
    if (over.isNotEmpty) {
      return '이번 주 ${over.length}일만 권장량을 넘었어요. 나머지 날의 균형은 좋았어요.';
    }
    return '이번 주 ${days.length}일 모두 나트륨을 권장량 안에서 지켰어요!';
  }

  if (period == kPeriodAll) {
    // 최근 4주와 그 이전을 견준다 — 나아지는 중인지가 이 화면의 질문이다.
    final DateTime last = days.last.date;
    final DateTime recentFrom = DateTime(last.year, last.month, last.day - 27);
    final List<int> recent = <int>[
      for (final DietDayTotals d in days)
        if (!d.date.isBefore(recentFrom)) d.sodiumMg,
    ];
    final List<int> earlier = <int>[
      for (final DietDayTotals d in days)
        if (d.date.isBefore(recentFrom)) d.sodiumMg,
    ];
    if (earlier.isNotEmpty && recent.isNotEmpty) {
      if (_avg(recent) < _avg(earlier) * 0.9) {
        return '최근 4주 나트륨이 그 전보다 낮아졌어요. 지금 방식이 잘 맞아요.';
      }
      if (_avg(recent) > _avg(earlier) * 1.1) {
        return '최근 4주 나트륨이 다시 올라가고 있어요. 한 주만 되짚어 볼까요?';
      }
    }
    final ({List<int> weekday, List<int> weekend}) split = _weekdaySplit(days);
    if (split.weekend.isNotEmpty &&
        split.weekday.isNotEmpty &&
        _avg(split.weekend) > _avg(split.weekday) * 1.3) {
      return '기록을 통틀어 주말마다 나트륨이 올라요. 주말 한 끼만 담백하게 바꿔요.';
    }
    final int ratio = (over.length * 100 / days.length).round();
    if (ratio >= 40) return '기록한 날의 $ratio%가 나트륨 권장량을 넘었어요. 국물부터 남겨 봐요.';
    return '기록한 ${days.length}일 대부분이 권장량 안이에요. 지금 흐름이 좋아요.';
  }

  // 오늘 — 그날 합계 하나로 말한다.
  final DietDayTotals today = days.last;
  if (today.sodiumMg > kSodiumLimitMg) {
    return '오늘 나트륨 ${today.sodiumMg}mg 로 권장량을 넘겼어요. 남은 끼니는 담백하게.';
  }
  return '오늘 나트륨 ${today.sodiumMg}mg 로 권장량 안이에요. 이대로 마무리해요.';
}

/// 운동 유형 코드 → 사람이 읽는 라벨. 서버 `exercise_types.label_for` 와 같다.
String exerciseTypeLabel(String code) => switch (code) {
  'cardio' || 'walking' => '유산소',
  'strength' => '근력',
  'flexibility' || 'stretching' || 'yoga' => '스트레칭',
  _ => '기타',
};

/// 그날 가장 오래 한 유형. 같으면 유산소 → 근력 → 스트레칭 → 기타 순이다.
String _mainType(Map<String, int> byType) {
  const List<String> order = <String>[
    'cardio',
    'strength',
    'stretching',
    'other',
  ];
  String best = order.first;
  int bestMinutes = -1;
  for (final String kind in order) {
    final int minutes = byType[kind] ?? 0;
    if (minutes > bestMinutes) {
      best = kind;
      bestMinutes = minutes;
    }
  }
  return best;
}

/// `전체` 가 거슬러 올라가는 주 수. 서버의 `ALL_PERIOD_DAYS`(84일)와 같다.
const int kAllPeriodWeeks = 12;

/// 기간에 맞는 운동 조언. [days] 는 날짜순이고 기록이 있는 날만 든다.
///
/// 오늘 걸린 추천 개인운동([routineDays])이 있으면 그 목록을 기준으로 말한다
/// (#2162, [routineCoachMessage]). 없으면 직접 기록 기준 조언이다.
String exercisePeriodAdvice(
  List<ExerciseDayTotals> days,
  String period, {
  List<RoutineAdviceDay> routineDays = const <RoutineAdviceDay>[],
}) {
  final String? routineMessage = routineCoachMessage(routineDays, period);
  if (routineMessage != null) return routineMessage;
  if (days.isEmpty) {
    if (period == kPeriodWeek) return '이번 주 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?';
    if (period == kPeriodAll) return '기록이 쌓이면 운동량과 유형의 흐름을 짚어 드릴게요.';
    return '오늘 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?';
  }

  if (period == kPeriodToday) {
    final ExerciseDayTotals today = days.last;
    final String label = exerciseTypeLabel(_mainType(today.byType));
    return '오늘 $label 위주로 ${today.minutes}분, ${today.calories}kcal 썼어요. 스트레칭으로 마무리해요.';
  }

  final int totalMinutes = days.fold<int>(
    0,
    (int sum, ExerciseDayTotals d) => sum + d.minutes,
  );
  final int activeDays = days.length;

  if (period == kPeriodWeek) {
    if (activeDays <= 1) {
      return '이번 주는 $totalMinutes분 하루뿐이에요. 한 번 더 나가면 흐름이 이어져요.';
    }
    // 한 유형에 쏠렸는지 — 코칭에서 가장 먼저 짚는 지점이다.
    final Map<String, int> byType = <String, int>{};
    for (final ExerciseDayTotals d in days) {
      d.byType.forEach((String kind, int minutes) {
        byType[kind] = (byType[kind] ?? 0) + minutes;
      });
    }
    if (byType.isNotEmpty && totalMinutes > 0) {
      final String top = byType.keys.reduce(
        (String a, String b) => byType[a]! >= byType[b]! ? a : b,
      );
      if (byType[top]! / totalMinutes >= 0.8) {
        final String missing = top == 'cardio' ? 'strength' : 'cardio';
        return '이번 주 $activeDays일 $totalMinutes분이 ${exerciseTypeLabel(top)}에 몰렸어요. '
            '${exerciseTypeLabel(missing)}도 섞어 볼까요?';
      }
    }
    return '이번 주 $activeDays일 $totalMinutes분, 유형도 고르게 섞였어요.';
  }

  // 전체 — 최근 4주와 그 이전을 견준다.
  final DateTime last = days.last.date;
  final DateTime recentFrom = DateTime(last.year, last.month, last.day - 27);
  final List<int> recent = <int>[
    for (final ExerciseDayTotals d in days)
      if (!d.date.isBefore(recentFrom)) d.minutes,
  ];
  final List<int> earlier = <int>[
    for (final ExerciseDayTotals d in days)
      if (d.date.isBefore(recentFrom)) d.minutes,
  ];
  if (earlier.isNotEmpty && recent.isNotEmpty) {
    if (_avg(recent) > _avg(earlier) * 1.1) {
      return '최근 4주 운동량이 그 전보다 늘었어요. 지금 방식이 잘 맞아요.';
    }
    if (_avg(recent) < _avg(earlier) * 0.9) {
      return '최근 4주 운동량이 줄고 있어요. 짧게라도 주 3일을 지켜 봐요.';
    }
  }
  return '$kAllPeriodWeeks주 동안 $activeDays일 $totalMinutes분, 기복 없이 이어가고 있어요.';
}

// --- 추천 개인운동 기준 조언 (#2162) ------------------------------------------
//
// 서버 `routine_advice.py` 의 재현이다. 규칙도 문장도 서버가 원본이고, 두 쪽이
// 같은지는 공유 사례(`test/core/demo/routine_advice_cases.json`)로 본다.
//
// 운동은 **이름으로 센다** — AI 추천은 날마다 새 줄로 만들어져 id 가 매일 다르다.
// 문장은 **45자를 넘기지 않는다**(#1574). 짧아지는 후보를 차례로 두고 한도 안의
// 첫 문장을 쓴다.

/// 그날 걸려 있던 추천 개인운동 하나와 그날 했는지. 서버 `RoutineDayItem` 의 필요한
/// 칸만 담는다. [type] 은 한글 라벨(`유산소`)이든 코드(`cardio`)든 받는다.
typedef RoutineAdviceItem = ({
  String name,
  String type,
  int minutes,
  bool done,
  int? completedMinutes,
});

/// 하루치 추천 개인운동 — 그날 목록(정렬순)과 그날 완료.
typedef RoutineAdviceDay = ({DateTime date, List<RoutineAdviceItem> routines});

/// 조언 한 마디의 상한. 서버 `routine_advice.ADVICE_MAX_LEN` 과 같다.
const int kAdviceMaxLen = 45;

const double _skewShare = 0.8;
const double _praiseRate = 0.8;
const double _missRate = 0.5;
const int _missMin = 2;
const double _missGap = 0.2;
const int _allMinDays = 7;

const String kPartLower = '하체';
const String kPartUpper = '상체';
const String kPartCore = '코어';
const String kPartFull = '전신';

/// 이름에 직접 적힌 부위. 서버 `_PART_WORDS` 와 같은 차례다.
const List<(String, List<String>)> _partWords = <(String, List<String>)>[
  (kPartFull, <String>['전신']),
  (kPartLower, <String>['하체', '다리', '허벅지', '엉덩이', '둔근', '종아리']),
  (kPartUpper, <String>['상체', '어깨', '가슴', '팔']),
  (kPartCore, <String>['코어', '복근', '복부', '허리']),
];

/// 동작 이름으로 짐작하는 부위. 서버 `_PART_MOVES` 와 같은 차례다.
const List<(String, List<String>)> _partMoves = <(String, List<String>)>[
  (kPartFull, <String>['버피', 'burpee']),
  (
    kPartLower,
    <String>[
      '스쿼트',
      '런지',
      '브릿지',
      '레그',
      '카프',
      '데드리프트',
      '스텝업',
      '힙',
      'squat',
      'lunge',
      'bridge',
      'leg',
      'deadlift',
    ],
  ),
  (
    kPartCore,
    <String>['플랭크', '크런치', '윗몸', '버드독', '데드버그', 'plank', 'crunch', 'core'],
  ),
  (
    kPartUpper,
    <String>[
      '푸시업',
      '팔굽혀',
      '풀업',
      '턱걸이',
      '로우',
      '벤치',
      '프레스',
      '숄더',
      '풀다운',
      '컬',
      '딥스',
      '레이즈',
      'push',
      'pull',
      'row',
      'bench',
      'press',
      'shoulder',
      'curl',
    ],
  ),
];

/// 운동 이름 → 부위(하체·상체·코어·전신). 모르면 null — 조언은 이름을 그대로 말한다.
String? bodyPartOf(String name) {
  final String text = name.toLowerCase();
  for (final List<(String, List<String>)> rules
      in <List<(String, List<String>)>>[_partWords, _partMoves]) {
    for (final (String part, List<String> keywords) in rules) {
      if (keywords.any(text.contains)) return part;
    }
  }
  return null;
}

/// 조언이 읽을 추천 목록의 시작일. 서버 `routine_advice.fetch_start` 와 같다 —
/// 이번 주는 지난주까지 읽는다(월·화 회고).
DateTime routineAdviceFetchStart(String period, DateTime today) {
  final DateTime day = DateTime(today.year, today.month, today.day);
  if (period == kPeriodToday) return day;
  if (period == kPeriodWeek) {
    return DateTime(day.year, day.month, day.day - (day.weekday - 1) - 7);
  }
  return DateTime(day.year, day.month, day.day - (kAllPeriodWeeks * 7 - 1));
}

/// 유형 표기 → 코드. 서버 `exercise_types.normalize` 와 같다.
String _typeCode(String type) => switch (type.trim()) {
  'cardio' || '유산소' || 'walking' || '걷기' => 'cardio',
  'strength' || '근력' => 'strength',
  'stretching' ||
  '스트레칭' ||
  'yoga' ||
  '요가' ||
  'flexibility' ||
  '유연성' => 'stretching',
  _ => 'other',
};

const List<String> _typeOrder = <String>[
  'cardio',
  'strength',
  'stretching',
  'other',
];

/// 마지막 글자에 받침이 있나. 한글로 끝나지 않으면 null.
bool? _hasFinalConsonant(String word) {
  String stripped = word;
  while (stripped.isNotEmpty &&
      ' )]}'.contains(stripped[stripped.length - 1])) {
    stripped = stripped.substring(0, stripped.length - 1);
  }
  if (stripped.isEmpty) return null;
  final int last = stripped.runes.last;
  if (last < 0xAC00 || last > 0xD7A3) return null;
  return (last - 0xAC00) % 28 != 0;
}

String _josa(String word, String withFinal, String withoutFinal) {
  final bool? finalConsonant = _hasFinalConsonant(word);
  if (finalConsonant == null) return '$word$withFinal($withoutFinal)';
  return word + (finalConsonant ? withFinal : withoutFinal);
}

/// 한도 안에 드는 첫 문장. 길이는 서버(파이썬 `len`)처럼 글자 수로 센다.
String _firstFit(List<String> candidates) {
  for (final String text in candidates) {
    if (text.runes.length <= kAdviceMaxLen) return text;
  }
  return candidates.last;
}

int _pct(num part, num whole) =>
    whole == 0 ? 0 : (part * 100 / whole + 0.5).floor();

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 날짜만 — UTC 로 두어 서머타임이 있는 시간대에서도 하루가 24시간이다.
DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// 셀 수 있는 추천 — 지난 날의 것 전부와 오늘 이미 한 것. 오늘 아직 안 한 것은
/// 빠진 것이 아니다.
({List<RoutineAdviceItem> assigned, List<RoutineAdviceItem> done}) _tally(
  Iterable<RoutineAdviceDay> days,
  DateTime today, {
  Set<String>? names,
}) {
  final List<RoutineAdviceItem> assigned = <RoutineAdviceItem>[];
  final List<RoutineAdviceItem> done = <RoutineAdviceItem>[];
  for (final RoutineAdviceDay day in days) {
    for (final RoutineAdviceItem item in day.routines) {
      if (names != null && !names.contains(item.name)) continue;
      if (_sameDay(day.date, today) && !item.done) continue;
      assigned.add(item);
      if (item.done) done.add(item);
    }
  }
  return (assigned: assigned, done: done);
}

/// 추천 목록 기준 조언. 오늘 걸린 추천이 없으면 null. [days] 는 날짜순이고 마지막
/// 날이 오늘이다. 서버 `routine_advice.coach_message` 와 같다.
String? routineCoachMessage(List<RoutineAdviceDay> days, String period) {
  if (days.isEmpty || days.last.routines.isEmpty) return null;
  if (period == kPeriodToday) return _routineToday(days.last);
  if (period == kPeriodWeek) return _routineWeek(days);
  return _routineAll(days);
}

String _routineToday(RoutineAdviceDay day) {
  final List<String> pending = <String>[
    for (final RoutineAdviceItem i in day.routines)
      if (!i.done) i.name,
  ];
  final List<String> done = <String>[
    for (final RoutineAdviceItem i in day.routines)
      if (i.done) i.name,
  ];
  if (pending.isEmpty) {
    return '오늘 추천 운동 ${day.routines.length}개를 모두 마쳤어요. 잘했어요!';
  }
  final String left = '남은 추천 운동이 ${pending.length}개예요. 목록 순서대로 해 보세요.';
  // 남은 것이 하나면 "순서" 가 없다 — 그 하나의 차례라고만 말한다.
  final String? order = pending.length >= 2
      ? pending.take(2).join(' → ')
      : null;
  // 한글로 끝나지 않는 이름(`Squat`)에는 조사를 붙일 수 없다 — 마친 운동을
  // 말하는 문장을 건너뛴다.
  if (done.isNotEmpty && _hasFinalConsonant(done.last) != null) {
    final String finished = '${_josa(done.last, '을', '를')} 마쳤어요.';
    return _firstFit(<String>[
      if (order != null) '$finished 다음은 $order 순서로 해 보세요.',
      '$finished 다음은 ${pending.first} 차례예요.',
      if (order != null) '다음은 $order 순서로 해 보세요.',
      '다음은 ${pending.first} 차례예요.',
      left,
    ]);
  }
  if (done.isNotEmpty) {
    return _firstFit(<String>[
      if (order != null) '다음은 $order 순서로 해 보세요.',
      '다음은 ${pending.first} 차례예요.',
      left,
    ]);
  }
  return _firstFit(<String>[
    if (order != null) '오늘 추천 운동은 $order 순서로 시작해 보세요.',
    '오늘은 ${pending.first}부터 시작해 보세요.',
    left,
  ]);
}

String _routineWeek(List<RoutineAdviceDay> days) {
  final DateTime today = _dateOnly(days.last.date);
  final DateTime monday = DateTime.utc(
    today.year,
    today.month,
    today.day - (today.weekday - 1),
  );
  final DateTime lastMonday = DateTime.utc(
    monday.year,
    monday.month,
    monday.day - 7,
  );
  final List<RoutineAdviceDay> thisWeek = <RoutineAdviceDay>[
    for (final RoutineAdviceDay d in days)
      if (!_dateOnly(d.date).isBefore(monday)) d,
  ];
  final List<RoutineAdviceDay> lastWeek = <RoutineAdviceDay>[
    for (final RoutineAdviceDay d in days)
      if (!_dateOnly(d.date).isBefore(lastMonday) &&
          _dateOnly(d.date).isBefore(monday))
        d,
  ];
  final int doneDays = thisWeek
      .where(
        (RoutineAdviceDay d) => d.routines.any((RoutineAdviceItem i) => i.done),
      )
      .length;
  // 주 초반(월·화)에 이번 주 한 날이 이틀이 안 되면 지난주를 돌아본다.
  final bool lookingBack =
      today.weekday <= DateTime.tuesday &&
      doneDays < 2 &&
      _tally(lastWeek, today).assigned.isNotEmpty;
  final ({List<RoutineAdviceItem> assigned, List<RoutineAdviceItem> done})
  tally = _tally(lookingBack ? lastWeek : thisWeek, today);
  final String when = lookingBack ? '지난주' : '이번 주';
  // 일요일에는 이번 주에 남은 날이 없다 — 다음 주를 말한다.
  final bool sunday = today.weekday == DateTime.sunday;
  final String rest = sunday ? '다음 주엔' : '남은 날엔';
  final String keepGoing = sunday ? '다음 주도 이어 가요.' : '남은 날도 이어 가요.';
  final String? firstPending = days.last.routines
      .where((RoutineAdviceItem i) => !i.done)
      .map((RoutineAdviceItem i) => i.name)
      .firstOrNull;

  if (tally.done.isEmpty) {
    if (lookingBack) {
      return _firstFit(<String>[
        if (firstPending != null)
          '지난주엔 추천 운동을 못 했어요. 이번 주는 $firstPending부터 해 봐요.'
        else
          '지난주엔 추천 운동을 못 했어요. 이번 주는 하나씩 해 봐요.',
        '지난주엔 추천 운동을 못 했어요. 이번 주는 하나씩 해 봐요.',
      ]);
    }
    return _firstFit(<String>[
      '이번 주엔 추천 운동을 아직 안 했어요. 오늘 $firstPending부터 해 볼까요?',
      '이번 주엔 추천 운동을 아직 안 했어요. $firstPending부터 해 봐요.',
      '이번 주엔 추천 운동을 아직 안 했어요. 오늘 하나부터 해 봐요.',
    ]);
  }

  // 유형 쏠림 — 한 추천 운동의 시간으로 센다. 목록에 한 유형만 걸려 있으면
  // 쏠림은 목록의 모양이라 짚지 않는다.
  final Map<String, int> minutes = <String, int>{};
  for (final RoutineAdviceItem item in tally.done) {
    final String code = _typeCode(item.type);
    minutes[code] =
        (minutes[code] ?? 0) + (item.completedMinutes ?? item.minutes);
  }
  final int total = minutes.values.fold<int>(0, (int a, int b) => a + b);
  final Set<String> listedTypes = <String>{
    for (final RoutineAdviceItem i in tally.assigned) _typeCode(i.type),
  };
  if (total > 0 && tally.done.length >= 2 && listedTypes.length >= 2) {
    String top = _typeOrder.first;
    for (final String t in _typeOrder) {
      if ((minutes[t] ?? 0) > (minutes[top] ?? 0)) top = t;
    }
    if ((minutes[top] ?? 0) / total >= _skewShare) {
      final String missing = _leastDoneType(tally.assigned, exclude: top);
      final int share = _pct(minutes[top]!, total);
      final String topLabel = _josa(exerciseTypeLabel(top), '이', '가');
      final String missingLabel = exerciseTypeLabel(missing);
      // 한 유형만 했으면 "100%" 가 아니라 그 유형만 했다고 말한다.
      if (share == 100) {
        final String only = '$when엔 ${exerciseTypeLabel(top)} 추천 운동만 했어요.';
        final String nextStep = lookingBack ? '이번 주는' : rest;
        return _firstFit(<String>[
          '$only $nextStep $missingLabel부터 해 보세요.',
          only,
        ]);
      }
      if (lookingBack) {
        return _firstFit(<String>[
          '지난주 추천 운동 중 $topLabel $share%였어요. 이번 주는 $missingLabel부터 해 보세요.',
          '지난주 추천 운동은 $topLabel $share%였어요.',
        ]);
      }
      return _firstFit(<String>[
        '이번 주 추천 운동 중 $topLabel $share%예요. $rest $missingLabel부터 해 보세요.',
        '이번 주 추천 운동은 $topLabel $share%예요.',
      ]);
    }
  }

  final double rate = tally.done.length / tally.assigned.length;
  if (rate >= _praiseRate) {
    final String how =
        <String>{
              for (final RoutineAdviceItem i in tally.done) _typeCode(i.type),
            }.length >=
            2
        ? '고르게'
        : '꾸준히';
    if (lookingBack) return '지난주 추천 운동을 $how 해냈어요. 이번 주도 이어 가요!';
    return '이번 주 추천 운동을 $how 해냈어요. 이대로 이어 가요!';
  }
  final String counts =
      '$when 추천 운동 ${tally.assigned.length}개 중 ${tally.done.length}개를 했어요.';
  if (lookingBack) return _firstFit(<String>['$counts 이번 주는 더 채워 봐요.', counts]);
  if (firstPending == null) {
    return _firstFit(<String>['$counts $keepGoing', counts]);
  }
  return _firstFit(<String>[
    '$counts 오늘 $firstPending부터 이어 가요.',
    '$counts $keepGoing',
    counts,
  ]);
}

/// 걸려 있던 유형 중 완료율이 가장 낮은 것. 같으면 유산소 → 근력 → … 순.
String _leastDoneType(
  List<RoutineAdviceItem> assigned, {
  required String exclude,
}) {
  final Map<String, int> listed = <String, int>{};
  final Map<String, int> done = <String, int>{};
  for (final RoutineAdviceItem item in assigned) {
    final String code = _typeCode(item.type);
    listed[code] = (listed[code] ?? 0) + 1;
    if (item.done) done[code] = (done[code] ?? 0) + 1;
  }
  String? best;
  double bestRate = double.infinity;
  for (final String t in _typeOrder) {
    if (!listed.containsKey(t) || t == exclude) continue;
    final double r = (done[t] ?? 0) / listed[t]!;
    if (r < bestRate) {
      best = t;
      bestRate = r;
    }
  }
  return best!;
}

/// 자주 빠진 것을 셀 묶음 — 부위, 모르면 운동 이름. 서버 `_group_key` 와 같다.
///
/// 스트레칭은 부위로 묶지 않는다. `어깨 관절 보호 스트레칭` 이 빠진 것을 "상체
/// 운동이 자주 빠졌어요" 라고 하면 회원은 상체 근력 운동을 떠올린다.
String _groupKey(RoutineAdviceItem item) {
  if (_typeCode(item.type) == 'stretching') return item.name;
  return bodyPartOf(item.name) ?? item.name;
}

/// 자주 빠지던 부위·운동을 오늘 해냈을 때의 말. 서버 `_done_today_praise` 와 같다.
String _doneTodayPraise(String key) {
  const String tail = '이대로 이어 가요!';
  if (<String>[kPartLower, kPartUpper, kPartCore, kPartFull].contains(key)) {
    return '자주 빠지던 $key 운동을 오늘 해냈어요. $tail';
  }
  if (_hasFinalConsonant(key) == null) {
    return _firstFit(<String>[
      '자주 빠지던 $key, 오늘 해냈어요. $tail',
      '자주 빠지던 운동을 오늘 해냈어요. $tail',
    ]);
  }
  return _firstFit(<String>[
    '자주 빠지던 ${_josa(key, '을', '를')} 오늘 해냈어요. $tail',
    '자주 빠지던 운동을 오늘 해냈어요. $tail',
  ]);
}

String _routineAll(List<RoutineAdviceDay> days) {
  final DateTime today = _dateOnly(days.last.date);
  final List<String> current = <String>[
    for (final RoutineAdviceItem i in days.last.routines) i.name,
  ];
  final Set<String> names = current.toSet();
  // 지금 목록이 걸린 동안 — 지금 목록의 운동이 처음 걸린 날부터 센다.
  final DateTime since = _dateOnly(
    days
        .firstWhere(
          (RoutineAdviceDay d) =>
              d.routines.any((RoutineAdviceItem i) => names.contains(i.name)),
        )
        .date,
  );
  final int span = today.difference(since).inDays + 1;
  if (span < _allMinDays) {
    return '추천 목록을 받은 지 $span일째예요. 일주일 뒤 빠진 운동을 짚어 드릴게요.';
  }
  final ({List<RoutineAdviceItem> assigned, List<RoutineAdviceItem> done})
  tally = _tally(
    days.where((RoutineAdviceDay d) => !_dateOnly(d.date).isBefore(since)),
    today,
    names: names,
  );
  if (tally.done.isEmpty) {
    // 한 번도 하지 않았으면 짚을 곳이 없다 — 탓하지 않고 오늘 첫 운동을 권한다.
    final String? firstPending = days.last.routines
        .where((RoutineAdviceItem i) => !i.done)
        .map((RoutineAdviceItem i) => i.name)
        .firstOrNull;
    final String sinceText = '추천 목록을 받은 지 $span일째예요.';
    return _firstFit(<String>[
      if (firstPending != null) '$sinceText 오늘 $firstPending부터 시작해 볼까요?',
      '$sinceText 오늘 하나부터 시작해 봐요.',
    ]);
  }

  // 부위로 묶는다. 부위를 모르면 운동 이름이 한 묶음이다.
  final Map<String, int> firstSeen = <String, int>{};
  for (int index = 0; index < days.last.routines.length; index++) {
    firstSeen.putIfAbsent(_groupKey(days.last.routines[index]), () => index);
  }
  final Map<String, List<int>> groups = <String, List<int>>{};
  for (final RoutineAdviceItem item in tally.assigned) {
    final String key = _groupKey(item);
    final List<int> counts = groups.putIfAbsent(key, () => <int>[0, 0]);
    counts[0] += 1;
    if (item.done) counts[1] += 1;
  }
  final double leastMissed = groups.values
      .map((List<int> c) => (c[0] - c[1]) / c[0])
      .reduce((double a, double b) => a < b ? a : b);
  String? worst;
  (double, int, int)? worstScore;
  groups.forEach((String key, List<int> c) {
    final int missed = c[0] - c[1];
    final double rate = missed / c[0];
    if (missed < _missMin ||
        rate < _missRate ||
        rate - leastMissed < _missGap) {
      return;
    }
    final (double, int, int) score = (
      rate,
      missed,
      -(firstSeen[key] ?? current.length),
    );
    if (worstScore == null || _greater(score, worstScore!)) {
      worst = key;
      worstScore = score;
    }
  });
  if (worst != null) {
    final String key = worst!;
    // 자주 빠지던 것을 오늘 했으면 그것부터 알아준다. 방금 체크한 운동을 두고
    // "다음엔 먼저 해 볼까요?" 라고 하면 회원은 체크가 반영되지 않은 줄 안다.
    if (days.last.routines.any(
      (RoutineAdviceItem i) => i.done && _groupKey(i) == key,
    )) {
      return _doneTodayPraise(key);
    }
    if (<String>[kPartLower, kPartUpper, kPartCore, kPartFull].contains(key)) {
      return _firstFit(<String>[
        '추천 운동 중 $key 운동이 자주 빠졌어요. $key 운동을 먼저 해 볼까요?',
        '$key 추천 운동이 자주 빠졌어요. 먼저 하는 순서로 바꿔 볼까요?',
      ]);
    }
    if (_hasFinalConsonant(key) == null) {
      return _firstFit(<String>[
        '추천 운동 $key, 자주 빠졌어요. 다음엔 먼저 해 볼까요?',
        '$key, 자주 빠졌어요. 먼저 해 볼까요?',
        '자주 빠진 추천 운동이 있어요. 목록 순서를 바꿔 볼까요?',
      ]);
    }
    final String subject = _josa(key, '이', '가');
    return _firstFit(<String>[
      '추천 운동 중 $subject 자주 빠졌어요. 다음엔 먼저 해 볼까요?',
      '$subject 자주 빠졌어요. 먼저 해 볼까요?',
      '자주 빠진 추천 운동이 있어요. 목록 순서를 바꿔 볼까요?',
    ]);
  }

  final double rate = tally.done.length / tally.assigned.length;
  if (rate >= _praiseRate) {
    return '추천 운동을 ${span ~/ 7}주째 꾸준히 하고 있어요. 앞으로도 화이팅!';
  }
  final int pct = _pct(tally.done.length, tally.assigned.length);
  return '지금 추천 운동의 $pct%를 했어요. 빠지는 날 없이 이어 가 봐요.';
}

bool _greater((double, int, int) a, (double, int, int) b) {
  if (a.$1 != b.$1) return a.$1 > b.$1;
  if (a.$2 != b.$2) return a.$2 > b.$2;
  return a.$3 > b.$3;
}
