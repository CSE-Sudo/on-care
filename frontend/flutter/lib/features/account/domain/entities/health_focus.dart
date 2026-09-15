/// 건강 목표 — 온보딩 2단계와 MY `건강 목표` 가 고르는 값. (#1471, #1814)
///
/// 서버는 이 값을 `HealthProfile.conditions` 한 칸에 쉼표로 이어 저장한다 —
/// 온보딩이 처음부터 그렇게 저장해 왔고, 그 값을 MY `건강 목표` 가 그대로
/// 이어받는다. 저장 형식을 바꾸면 이미 저장된 값이 화면에서 사라지므로,
/// 형식은 그대로 두고 읽고 쓰는 규칙만 한곳에 모은다.
///
/// 예전에는 질환명(고혈압·당뇨)을 골랐다. 타깃이 PT 회원으로 바뀌어 **운동을
/// 시작하는 이유**를 고르게 했고, 옛 질환 이름은 새 목표로 읽는다. 서버
/// `app/services/health_focus.py` 와 같은 목록·같은 순서여야 한다.
///
/// 같은 칸에 트레이너가 적은 건강상태·주의사항도 들어간다. 그래서 목표를 고쳐
/// 저장할 때 그 글은 지우지 않는다([mergeHealthFocus]).
library;

/// 저장에 쓰는 값. 화면 라벨은 로케일이 따로 들고 있다.
const String kHealthFocusWeightLoss = '체중 감량';
const String kHealthFocusStrength = '근력 향상';
const String kHealthFocusFitness = '체력 강화';
const String kHealthFocusPosture = '자세 교정';
const String kHealthFocusRehab = '재활';
const String kHealthFocusEating = '식습관 개선';
const String kHealthFocusExerciseHabit = '운동 습관';
const String kHealthFocusBloodPressure = '혈압 관리';

/// 고를 수 있는 건강 목표. 화면에 그리는 순서이자 저장 순서다.
const List<String> kHealthFocusOptions = <String>[
  kHealthFocusWeightLoss,
  kHealthFocusStrength,
  kHealthFocusFitness,
  kHealthFocusPosture,
  kHealthFocusRehab,
  kHealthFocusEating,
  kHealthFocusExerciseHabit,
  kHealthFocusBloodPressure,
];

/// 옛 질환 선택지 → 새 목표. `null` 은 이어받을 목표가 없어 지운다.
const Map<String, String?> kLegacyHealthFocus = <String, String?>{
  '고혈압': kHealthFocusBloodPressure,
  '비만': kHealthFocusWeightLoss,
  '당뇨': null,
  '당뇨 전단계': null,
  '고지혈증': null,
};

/// 저장 문자열을 조각으로. 옛 질환 이름은 새 목표로 바꾸거나 지우고, 겹치는
/// 값은 하나로 합친다. 순서는 적힌 순서다.
List<String> _tokens(String raw) {
  final List<String> out = <String>[];
  for (final String part in raw.split(',')) {
    String token = part.trim();
    if (token.isEmpty) continue;
    if (kLegacyHealthFocus.containsKey(token)) {
      final String? replacement = kLegacyHealthFocus[token];
      if (replacement == null) continue;
      token = replacement;
    }
    if (!out.contains(token)) out.add(token);
  }
  return out;
}

/// 저장 문자열 → 고른 목표. 목표가 아닌 글은 버린다 — 칩을 지어내지 않는다.
Set<String> parseHealthFocus(String raw) =>
    _tokens(raw).where(kHealthFocusOptions.contains).toSet();

/// 고른 목표 → 저장 문자열. 순서를 고정해 같은 선택이 늘 같은 문자열이 된다.
String formatHealthFocus(Set<String> focus) => <String>[
  for (final String option in kHealthFocusOptions)
    if (focus.contains(option)) option,
].join(', ');

/// 고른 목표로 [original] 을 고쳐 쓴다. 목표가 아닌 글(트레이너가 적은
/// 주의사항 등)은 뒤에 그대로 남긴다.
String mergeHealthFocus(String original, Set<String> focus) => <String>[
  formatHealthFocus(focus),
  ..._tokens(original).where((String t) => !kHealthFocusOptions.contains(t)),
].where((String part) => part.isNotEmpty).join(', ');

/// 서버 `normalize_conditions` 와 같은 정리. 목표는 목록 순서로 앞에, 그 밖의
/// 글은 적힌 순서대로 뒤에 둔다. 로컬 목 모드가 서버처럼 저장하는 데 쓴다.
String normalizeHealthFocusText(String raw) =>
    mergeHealthFocus(raw, parseHealthFocus(raw));
