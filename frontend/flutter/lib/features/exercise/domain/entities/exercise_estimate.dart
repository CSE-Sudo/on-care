/// 운동 유형·칼로리 어림값 — 화면 여러 곳이 같은 표를 쓴다.
///
/// 예전에는 `운동 추가` 시트 안에만 있던 사설 표였다. 추천 개인운동을 체크하면
/// 그것도 운동 기록이 되므로(#1131) 같은 어림값을 쓸 자리가 하나 더 생겼다 —
/// 표가 둘이면 같은 운동이 화면마다 다른 칼로리로 적힌다.
library;

import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare_rules/oncare_rules.dart' show pyRound;

/// 강도별 배수 (가벼움 / 보통 / 높음).
const Map<ExerciseIntensity, double> kIntensityFactor =
    <ExerciseIntensity, double>{
      ExerciseIntensity.light: 0.85,
      ExerciseIntensity.moderate: 1.0,
      ExerciseIntensity.high: 1.2,
    };

/// 소모 칼로리 한 건과 그 근거. (#1312)
class ExerciseCalorieEstimate {
  const ExerciseCalorieEstimate({
    required this.calories,
    this.source = ExerciseCalorieSource.estimate,
    this.matchedName = '',
    this.isometric = false,
  });

  factory ExerciseCalorieEstimate.fromJson(Map<String, Object?> json) =>
      ExerciseCalorieEstimate(
        calories: (json['calories'] as num?)?.toInt() ?? 0,
        source: ExerciseCalorieSource.fromJson(json['source']),
        matchedName: (json['matched_name'] as String?) ?? '',
        isometric: (json['isometric'] as bool?) ?? false,
      );

  final int calories;
  final ExerciseCalorieSource source;

  /// 값을 계산한 종목의 대표 이름. 회원이 적은 말과 다를 수 있어("런닝머신" →
  /// "러닝머신") 무엇으로 계산했는지 화면이 보여 준다. 폴백이면 비어 있다.
  final String matchedName;

  /// 이 이름이 **버티는 운동**인가 — 플랭크처럼 한 세트를 회가 아니라 초로
  /// 재는 종목이다(#1969). 폼이 `횟수` 칸을 `초` 칸으로 바꿔 보이는
  /// **기본값**이고, 종목표에 없는 자유 입력 이름도 있으므로 회원이 곧바로
  /// 바꿀 수 있다. 칼로리와 함께 오는 이유는 폼이 이름을 다 적은 그 시점에
  /// 이미 이 요청을 보내기 때문이다.
  final bool isometric;
}

/// 유형별 분당 칼로리 — **이름이 붙지 않을 때의 폴백**이다. 백엔드
/// `exercise_catalog.energy.fallback` 과 같은 값이어야 한다(#1312).
///
/// 이름이 있으면 서버가 종목 참조표와 회원 체중으로 계산한다. 이 표는 서버에
/// 닿지 못하는 경로(데모)와 이름이 종목으로 접히지 않는 기록에 남는다 —
/// 정확도가 아니라 화면 간 **일관성**이 목적이다(#1131). 반올림도 서버(Python
/// `round`, 0.5 는 짝수 쪽)와 같아야 미리보기와 저장값이 갈리지 않는다(#2860).
int estimateExerciseCalories(
  ExerciseType type,
  int minutes, {
  ExerciseIntensity intensity = ExerciseIntensity.moderate,
}) {
  final double perMin = switch (type) {
    ExerciseType.cardio => 9,
    ExerciseType.strength => 6,
    ExerciseType.walking => 4,
    ExerciseType.stretching => 3,
    ExerciseType.yoga => 3,
    ExerciseType.other => 5,
  };
  final double factor = kIntensityFactor[intensity] ?? 1.0;
  return pyRound(perMin * minutes * factor);
}

/// 루틴이 들고 오는 유형 표기(한글 라벨 또는 영문 코드)를 [ExerciseType] 으로.
///
/// 백엔드 `exercise_types.normalize` 와 같은 공용 표를 쓴다(#2861) — 걷기는
/// 유산소로, 요가·유연성은 스트레칭으로 접는다. 모르는 값은
/// [ExerciseType.other] 다. 기록 응답을 읽는 [exerciseTypeFromCode] 와 같은 함수다.
ExerciseType exerciseTypeFromLabel(String? label) =>
    exerciseTypeFromCode(label);

/// 강도 문자열(`light`/`moderate`/`high`) → [ExerciseIntensity].
ExerciseIntensity exerciseIntensityFromLabel(String? value) =>
    switch (value?.trim()) {
      'light' => ExerciseIntensity.light,
      'high' => ExerciseIntensity.high,
      _ => ExerciseIntensity.moderate,
    };
