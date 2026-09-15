/// 회원 건강 목표 — 회원앱 온보딩·MY 와 트레이너 웹이 함께 읽고 고치는 값. (#1818)
///
/// 서버 `HealthProfile.conditions` 한 칸에 쉼표로 이어 저장된다. 같은 칸에
/// 트레이너가 적는 건강상태·주의사항(예: `무릎 통증으로 러닝 자제`)도 들어가므로,
/// 목표를 고쳐도 그 글은 지우지 않는다([mergeHealthFocus]).
///
/// 트레이너 화면의 회원 목표는 예전에는 트레이너가 따로 적은 자유 문장이었다
/// (`산후 체력 회복`, `마라톤 완주 준비`). 회원이 고른 목표와 따로 놀아, 같은 사람을
/// 두 화면이 다르게 말했다. 이제 로스터의 `goal` 은 이 목표를 ` · ` 로 이은 값이다.
///
/// 목록·순서·최대 개수는 회원앱 `health_focus.dart`, 서버
/// `app/services/health_focus.py` 와 같아야 한다 — 테스트가 세 파일을 대조한다.
library;

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

/// 한 회원이 고를 수 있는 건강 목표 수.
const int kHealthFocusMaxSelected = 2;

/// 로스터가 목표를 한 줄로 이을 때 쓰는 구분자.
const String kHealthFocusLabelSeparator = ' · ';

/// 옛 질환 선택지 → 새 목표. `null` 은 이어받을 목표가 없어 지운다.
const Map<String, String?> kLegacyHealthFocus = <String, String?>{
  '고혈압': kHealthFocusBloodPressure,
  '비만': kHealthFocusWeightLoss,
  '당뇨': null,
  '당뇨 전단계': null,
  '고지혈증': null,
};

/// 저장 문자열(쉼표)이나 로스터 목표(` · `)를 조각으로. 옛 질환 이름은 새 목표로
/// 바꾸거나 지우고, 겹치는 값은 하나로 합친다.
List<String> _tokens(String raw) {
  final List<String> out = <String>[];
  for (final String part in raw.split(RegExp('[,·]'))) {
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

/// 고른 목표. 목표가 아닌 글은 버리고, 넘치면 목록 순서로 앞의 둘만 남긴다.
Set<String> parseHealthFocus(String raw) {
  final List<String> tokens = _tokens(raw);
  return kHealthFocusOptions
      .where(tokens.contains)
      .take(kHealthFocusMaxSelected)
      .toSet();
}

/// 목표가 아닌 글 — 트레이너가 적은 건강상태·주의사항이다.
String healthFocusNotes(String raw) => _tokens(
  raw,
).where((String t) => !kHealthFocusOptions.contains(t)).join(', ');

/// 고른 목표를 목록 순서로 저장 문자열에.
String formatHealthFocus(Set<String> focus) => <String>[
  for (final String option in kHealthFocusOptions)
    if (focus.contains(option)) option,
].take(kHealthFocusMaxSelected).join(', ');

/// 고른 목표와 [notes] 의 주의사항 글을 한 칸으로. 목표가 앞, 글이 뒤다.
String mergeHealthFocus(String notes, Set<String> focus) => <String>[
  formatHealthFocus(focus),
  healthFocusNotes(notes),
].where((String part) => part.isNotEmpty).join(', ');

/// 서버 `normalize_conditions` 와 같은 정리. 로컬 목업이 서버처럼 저장하는 데 쓴다.
String normalizeHealthFocusText(String raw) =>
    mergeHealthFocus(raw, parseHealthFocus(raw));

/// 지금 [option] 칩을 누를 수 있는가. 고른 칩은 늘 풀 수 있다.
bool canPickHealthFocus(Set<String> focus, String option) =>
    focus.contains(option) || focus.length < kHealthFocusMaxSelected;

/// 로스터 목표(` · `) — 서버 `focus_label` 과 같다.
String healthFocusGoal(String conditions) => <String>[
  for (final String option in kHealthFocusOptions)
    if (parseHealthFocus(conditions).contains(option)) option,
].join(kHealthFocusLabelSeparator);
