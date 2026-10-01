import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 효과 표의 자동 문구를 화면 언어로 옮긴다(#2737).
///
/// 효과 입력칸은 비워 두면 갈 자동 문구(`routine_effects.dart` 의 한국어 표
/// 문장)를 안내 글로 보인다. 저장되는 값과 자동 문구 판별은 한국어 표 그대로
/// 두고, **보이는 글만** 화면 언어로 바꾼다. 표에 없는 문장은 그대로 둔다.
///
/// 회원 앱 `routineEffectText`(#2725)와 같은 문장 목록이다 — 테스트가 공용
/// JSON 을 읽어 빠진 문장을 잡는다.
String routineEffectText(AppLocalizations l, String effect) => switch (effect) {
  '체력 향상·만성질환 예방' => l.routineEffectCardioDefault,
  '근력·근지구력 향상' => l.routineEffectStrengthDefault,
  '유연성·부상 예방' => l.routineEffectStretchDefault,
  '혈압 관리에 도움' => l.routineEffectBloodPressure,
  '체지방 감량에 도움' => l.routineEffectFatLoss,
  '심폐 체력 향상' => l.routineEffectCardioFitness,
  '무리 없는 체력 회복' => l.routineEffectGentleRecovery,
  '근육량 유지·증가' => l.routineEffectMuscleMass,
  '근력 향상' => l.routineEffectStrength,
  '자세 지지 근육 강화' => l.routineEffectPostureMuscles,
  '혈압·심박 안정' => l.routineEffectHeartRate,
  '근육 회복' => l.routineEffectMuscleRecovery,
  '굳은 근육 이완' => l.routineEffectLoosen,
  '관절 가동 범위 회복' => l.routineEffectJointRange,
  _ => effect,
};
