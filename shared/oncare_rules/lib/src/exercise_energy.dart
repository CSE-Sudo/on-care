/// 운동 칼로리 계수 — 강도 배수와 유형별 분당 kcal 폴백. (#1312, #2906)
///
/// 운동 이름이 종목 참조표에 붙으면 서버가 종목 계수와 회원 체중으로 계산한다.
/// 이 표는 이름이 붙지 않을 때의 **폴백**이고, 서버에 닿지 못하는 자리(데모
/// 서버·트레이너 폼 미리보기)도 같은 값을 쓴다 — 정확도가 아니라 화면 간
/// **일관성**이 목적이다(#1131).
///
/// 예전에는 회원 앱 입력 시트·회원 앱 데모 서버·트레이너 폼이 같은 표를 세 벌
/// 적어 두었다. 원본은 `vectors/exercise_energy.json` 이고, 서버
/// `exercise_catalog.energy` 의 `INTENSITY_FACTOR`·`FALLBACK_KCAL_PER_MIN` 과는
/// 그 파일로 양쪽 테스트가 대조한다.
library;

import 'exercise_type.dart';
import 'rounding.dart';

/// 강도 계약값(`light`/`moderate`/`high`) → 배수. 참조표 계수가 "보통" 수행
/// 기준이라 보통은 1 이다. 모르는 강도도 1 이다(서버와 같다).
const Map<String, double> kExerciseIntensityFactor = <String, double>{
  'light': 0.85,
  'moderate': 1.0,
  'high': 1.2,
};

/// 표준 유형 코드 → 분당 kcal 폴백.
const Map<String, double> kFallbackKcalPerMinute = <String, double>{
  kExerciseTypeCardio: 9.0,
  kExerciseTypeStrength: 6.0,
  kExerciseTypeStretching: 3.0,
  kExerciseTypeOther: 5.0,
};

/// 강도 배수. 모르는 값·누락은 1 이다.
double exerciseIntensityFactor(String? intensity) =>
    kExerciseIntensityFactor[intensity] ?? 1.0;

/// 어떤 유형 표기(영문 코드·한글 라벨·옛 값)든 받아 분당 kcal 폴백을 낸다.
/// 모르는 유형은 기타의 값이다 — 서버 `energy.fallback` 과 같다.
double fallbackKcalPerMinute(String? type) =>
    kFallbackKcalPerMinute[normalizeExerciseType(type)] ??
    kFallbackKcalPerMinute[kExerciseTypeOther]!;

/// 유형·시간·강도로 낸 소모 칼로리 어림값 — 서버 `energy.fallback` 과 같은
/// 곱셈 순서·같은 반올림(Python `round`, #2860)이다. 음수 시간은 0분이다.
int fallbackExerciseCalories(String? type, int minutes, String? intensity) =>
    pyRound(
      fallbackKcalPerMinute(type) *
          (minutes < 0 ? 0 : minutes) *
          exerciseIntensityFactor(intensity),
    );
