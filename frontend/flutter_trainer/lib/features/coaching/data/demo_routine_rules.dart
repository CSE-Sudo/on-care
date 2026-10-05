/// 서버 규칙형 A/B(`backend/app/services/routine_ai.py`)의 안전 주의·반복 운동
/// 규칙을 데모로 옮긴 것. (#2704)
///
/// 데모 A/B 생성(`MockTrainerRoutineOptionsRepository`)이 실서버 규칙형과 같은
/// 구성을 내도록, 표와 판단을 서버와 같은 값으로 둔다 — 한쪽만 바뀌면 같은
/// 회원에게 데모와 실서버가 다른 운동을 낸다.
///
/// 표와 판단 사례의 원본은 서버 스크립트(`backend/scripts/
/// gen_routine_caution_cases.py`)가 만드는 `shared/oncare_rules/vectors/
/// routine_caution_cases.json` 이다(#2906). 서버 pytest 와
/// `test/features/coaching/routine_caution_cases_test.dart` 가 같은 파일과
/// 대조하므로, 서버 표를 고치고 파일을 다시 만들면 여기가 어긋난 만큼 깨진다.
library;

/// 조심할 부위 · 그 부위를 가리키는 말 · 그 부위에 부담이 큰 운동 이름 조각.
/// 서버 `_CAUTION_RULES` 와 같다(#1440). 진단하지 않는다 — 무엇을 빼야 안전한가만
/// 안다.
const List<(String, List<String>, List<String>)> demoCautionRules =
    <(String, List<String>, List<String>)>[
      (
        '무릎',
        <String>['무릎', '슬개', '반월'],
        <String>['러닝', '런닝', '달리기', '점프', '스쿼트', '런지', '계단'],
      ),
      (
        '허리',
        <String>['허리', '요추', '디스크'],
        <String>['데드리프트', '윗몸', '점프', '러닝', '런닝', '달리기'],
      ),
      (
        '어깨',
        <String>['어깨', '회전근', '견관절'],
        <String>['숄더', '오버헤드', '푸시업', '벤치', '풀업'],
      ),
      (
        '발목',
        <String>['발목', '족저'],
        <String>['러닝', '런닝', '달리기', '점프', '줄넘기', '계단'],
      ),
    ];

/// 이 말이 보이면 강도를 올리지 않고 전문가 확인을 권한다. 서버
/// `_ESCALATION_KEYWORDS` 와 같다.
const List<String> demoEscalationKeywords = <String>[
  '가슴 통증',
  '흉통',
  '호흡 곤란',
  '숨이 차',
  '실신',
  '어지럼',
  '수술',
  '골절',
];

/// 주의 부위 이름의 영어. 근거 문장에만 쓴다(서버 `_EN_CAUTION_PARTS`).
const Map<String, String> demoEnCautionParts = <String, String>{
  '무릎': 'knee',
  '허리': 'lower back',
  '어깨': 'shoulder',
  '발목': 'ankle',
};

/// 라이브러리 운동 이름의 영어(서버 `_EN_EXERCISE_NAMES`). 회원 기록에 적힌
/// 반복 운동 이름은 여기 없어 원문 그대로다.
const Map<String, String> demoEnExerciseNames = <String, String>{
  '저강도 걷기': 'Low-intensity walk',
  '인터벌 러닝': 'Interval running',
  '스쿼트': 'Squat',
  '플랭크': 'Plank',
  '코어 스트레칭': 'Core stretch',
  '목·어깨 스트레칭': 'Neck & shoulder stretch',
};

/// 라이브러리 운동(한국어 이름·계약 유형). 서버 `_CARDIO_EASY` 등과 같다.
const (String, String) libCardioEasy = ('저강도 걷기', '유산소');
const (String, String) libCardioHard = ('인터벌 러닝', '유산소');
const (String, String) libStrength = ('스쿼트', '근력');
const (String, String) libStrength2 = ('플랭크', '근력');
const (String, String) libStretch = ('코어 스트레칭', '스트레칭');
const (String, String) libStretch2 = ('목·어깨 스트레칭', '스트레칭');

const List<String> demoStretchKeywords = <String>['스트레칭', '요가', '폼롤러'];
const List<String> demoCardioKeywords = <String>[
  '걷기',
  '러닝',
  '런닝',
  '자전거',
  '유산소',
  '인터벌',
  '달리기',
];

/// 건강 주의사항과 최근 대화를 한 덩어리 글로 — 서버 `_caution_text`.
String _cautionText(String conditions, List<String> messages) =>
    <String>[conditions, ...messages].join(' ').trim();

/// 조심할 부위 이름. 없으면 빈 목록 — 서버 `cautions_in`.
List<String> cautionsIn(String conditions, List<String> messages) {
  final String text = _cautionText(conditions, messages);
  if (text.isEmpty) return const <String>[];
  return <String>[
    for (final (String part, List<String> keywords, List<String> _)
        in demoCautionRules)
      if (keywords.any(text.contains)) part,
  ];
}

/// 운동 구성으로 답할 수 없는 상태인가 — 서버 `needs_professional_check`.
bool needsProfessionalCheck(String conditions, List<String> messages) {
  final String text = _cautionText(conditions, messages);
  return demoEscalationKeywords.any(text.contains);
}

/// 이 운동이 조심할 부위에 부담을 주는가 — 서버 `_avoids`.
bool avoidsFor(String name, List<String> cautions) {
  for (final (String part, List<String> _, List<String> risky)
      in demoCautionRules) {
    if (cautions.contains(part) && risky.any(name.contains)) return true;
  }
  return false;
}

/// 부담이 큰 운동을 저충격 대안으로 바꾼다 — 서버 `_safe_parts`.
List<(String, String, int)> safeParts(
  List<(String, String, int)> parts,
  List<String> cautions,
) {
  if (cautions.isEmpty) return parts;
  final List<(String, String, int)> kept = <(String, String, int)>[
    for (final (String, String, int) part in parts)
      if (!avoidsFor(part.$1, cautions)) part,
  ];
  if (kept.length == parts.length) return parts;
  final List<(String, String, int)> alternatives = <(String, String, int)>[
    (libStretch.$1, libStretch.$2, 2),
    (libCardioEasy.$1, libCardioEasy.$2, 2),
  ];
  for (final (String, String, int) alternative in alternatives) {
    if (!kept.any(((String, String, int) p) => p.$1 == alternative.$1)) {
      kept.add(alternative);
    }
    if (kept.length >= parts.length) break;
  }
  return kept.isEmpty ? alternatives : kept;
}

/// 근거 문장에 붙일 안전 메모 — 서버 `_caution_suffix`.
String cautionSuffix(List<String> cautions, bool escalate, {required bool en}) {
  final StringBuffer out = StringBuffer();
  if (cautions.isNotEmpty) {
    if (en) {
      final String names = cautions
          .map((String c) => demoEnCautionParts[c] ?? c)
          .join(', ');
      out.write(
        ' Cautions ($names) applied: removed movements that load those areas.',
      );
    } else {
      out.write(' 주의사항(${cautions.join(', ')}) 반영: 해당 부위 부담 동작을 뺐습니다.');
    }
  }
  if (escalate) {
    out.write(
      en
          ? ' Intensity was not raised — adjust after a professional check.'
          : ' 강도는 올리지 않았습니다 — 전문가 확인 후 조정하세요.',
    );
  }
  return out.toString();
}

/// 라이브러리 운동 이름을 화면 언어로. 라이브러리 밖 이름은 그대로다.
String libraryExerciseName(String name, {required bool en}) =>
    en ? demoEnExerciseNames[name] ?? name : name;

/// 반복 운동 이름으로 유형을 대략 짐작한다 — 서버 `_guess_type`.
String guessExerciseType(String name) {
  if (demoStretchKeywords.any(name.contains)) return '스트레칭';
  if (demoCardioKeywords.any(name.contains)) return '유산소';
  return '근력';
}

/// 완료 기록 한 줄에서 세트·횟수를 뗀 운동 이름 — 서버 `_exercise_name`.
///
/// 숫자가 시작되는 지점부터는 이름이 아니라고 본다(`"레그프레스 3세트"`).
/// 서버와 달리 끝의 수행 표시(✓·✗)와 괄호 메모도 뗀다 — 데모 이력에는
/// `걷기 ✓ (10분만)` 처럼 숫자 없이 표시가 붙은 줄이 있어, 그대로 두면
/// `걷기 ✓` 가 따로 세어진다. **안 한 운동(✗)은 빈 이름**이라 반복으로 세지
/// 않는다.
String historyExerciseName(Object? item) {
  final Object? raw = item is Map ? item['name'] : item;
  if (raw is! String || raw.contains('✗')) return '';
  return raw
      .split(RegExp('[✓(]'))
      .first
      .replaceFirst(RegExp(r'\s*\d.*$'), '')
      .trim();
}

/// 파이썬 `round` 와 같은 반올림 — 딱 절반이면 짝수 쪽이다(2.5 → 2, 3.5 → 4).
///
/// Dart 의 `round` 는 바깥쪽(2.5 → 3)이라, 서버와 같은 시간 배분 식을 써도
/// 5분 요청에서 B안 합이 6분이 됐다(#2715). 서버 셈을 옮긴 곳은 이것을 쓴다.
int pyRound(num value) {
  final int floor = value.floor();
  final num rest = value - floor;
  if (rest < 0.5) return floor;
  if (rest > 0.5) return floor + 1;
  return floor.isEven ? floor : floor + 1;
}

/// 한 운동이 기록에 가장 많이 나온 횟수 — 서버 추천 상태의 반복 문턱이 본다
/// (`max(name_counts.values())`). 안 한 운동(✗)은 세지 않는다.
int maxRepeat(Iterable<List<Object?>> sessions) {
  final Map<String, int> counts = <String, int>{};
  for (final List<Object?> items in sessions) {
    for (final Object? item in items) {
      final String name = historyExerciseName(item);
      if (name.isNotEmpty) counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  return counts.values.fold<int>(0, (int a, int b) => a > b ? a : b);
}

/// 최근 기록에서 두 번 이상 나온 운동, 많이 나온 순으로 셋까지 — 서버
/// `_analyze_routine_history` 의 `frequent`(`Counter.most_common`). 횟수가
/// 같으면 먼저 본 순서다.
List<String> frequentExercises(Iterable<List<Object?>> sessions) {
  final Map<String, int> counts = <String, int>{};
  for (final List<Object?> items in sessions) {
    for (final Object? item in items) {
      final String name = historyExerciseName(item);
      if (name.isNotEmpty) counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  final List<MapEntry<String, int>> ranked = counts.entries.toList();
  // 삽입 정렬 — 안정 정렬이라 같은 횟수는 처음 나온 순서가 남는다.
  for (var i = 1; i < ranked.length; i++) {
    final MapEntry<String, int> value = ranked[i];
    var j = i - 1;
    while (j >= 0 && ranked[j].value < value.value) {
      ranked[j + 1] = ranked[j];
      j--;
    }
    ranked[j + 1] = value;
  }
  return <String>[
    for (final MapEntry<String, int> e in ranked)
      if (e.value >= 2) e.key,
  ].take(3).toList();
}
