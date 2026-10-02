/// 운동 유형 어휘 — 유산소 / 근력 / 스트레칭 / 기타 네 가지. (#996, #1276, #2861)
///
/// 서버 `backend/app/services/exercise_types.py` 의 `_TO_CODE` 와 **같은 표**다.
/// 영문 코드(회원 기록), 한글 라벨(트레이너 루틴), 옛 값(`walking`·`걷기`·`yoga`·
/// `요가`·`flexibility`·`유연성`)을 모두 받고, 모르는 값은 `other`(기타)로 둔다.
///
/// 예전에는 두 앱의 화면·데모 서버가 이 표를 각자 적어, 어떤 자리는 한글을 몰라
/// `유산소` 를 기타로 떨어뜨리고 어떤 자리는 모르는 값을 근력으로 떨어뜨렸다.
/// 데모 자료·캐시·서버 응답 중 한쪽 어휘만 바뀌어도 기록이 다른 유형 칸으로 옮겨
/// 가 주간 그래프·유형별 합계·kcal 이 조용히 틀어진다. 표는 여기 하나만 둔다.
library;

/// 유산소 — 표준 영문 코드.
const String kExerciseTypeCardio = 'cardio';

/// 근력 — 표준 영문 코드.
const String kExerciseTypeStrength = 'strength';

/// 스트레칭 — 표준 영문 코드. 한때 `flexibility`(유연성) 였다.
const String kExerciseTypeStretching = 'stretching';

/// 기타 — 표준 영문 코드. 모르는 값도 여기로 간다.
const String kExerciseTypeOther = 'other';

/// 표준 영문 코드 네 가지(집계 순서).
const List<String> kExerciseTypeCodes = <String>[
  kExerciseTypeCardio,
  kExerciseTypeStrength,
  kExerciseTypeStretching,
  kExerciseTypeOther,
];

/// 표준 코드 → 표준 한글 라벨. 트레이너 루틴(`trainer_routines.type`)이 쓰는
/// 계약값이고, 서버 `exercise_types._CODE_TO_KO` 와 같다.
const Map<String, String> kExerciseTypeKoLabels = <String, String>{
  kExerciseTypeCardio: '유산소',
  kExerciseTypeStrength: '근력',
  kExerciseTypeStretching: '스트레칭',
  kExerciseTypeOther: '기타',
};

/// 어떤 표기 → 표준 코드. 서버 `exercise_types._TO_CODE` 와 같다.
const Map<String, String> _toCode = <String, String>{
  // 표준
  kExerciseTypeCardio: kExerciseTypeCardio,
  kExerciseTypeStrength: kExerciseTypeStrength,
  kExerciseTypeStretching: kExerciseTypeStretching,
  kExerciseTypeOther: kExerciseTypeOther,
  '유산소': kExerciseTypeCardio,
  '근력': kExerciseTypeStrength,
  '스트레칭': kExerciseTypeStretching,
  '기타': kExerciseTypeOther,
  // 옛 값 — 걷기는 유산소로, 요가·유연성은 스트레칭으로 접는다.
  'walking': kExerciseTypeCardio,
  '걷기': kExerciseTypeCardio,
  'yoga': kExerciseTypeStretching,
  '요가': kExerciseTypeStretching,
  'flexibility': kExerciseTypeStretching,
  '유연성': kExerciseTypeStretching,
};

/// 어떤 표기로 들어와도 표준 영문 코드로. 모르는 값·빈 값은 `other`.
///
/// 서버 `exercise_types.normalize` 와 같다 — 앞뒤 공백만 걷고, 대소문자는 바꾸지
/// 않는다(서버도 `Cardio` 를 모르는 값으로 본다).
String normalizeExerciseType(String? value) {
  if (value == null || value.isEmpty) return kExerciseTypeOther;
  return _toCode[value.trim()] ?? kExerciseTypeOther;
}

/// 어떤 표기로 들어와도 표준 한글 라벨로. 모르는 값은 `기타`.
///
/// 서버 `exercise_types.normalize_ko` 와 같다.
String normalizeExerciseTypeKo(String? value) =>
    kExerciseTypeKoLabels[normalizeExerciseType(value)]!;
