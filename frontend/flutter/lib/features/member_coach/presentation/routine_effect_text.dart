import 'package:oncare/gen/l10n/app_localizations.dart';

/// 코치 루틴 효과 한 줄을 화면 언어로 옮긴다(#2725).
///
/// 트레이너가 효과를 비워 두면 서버·데모가 공용 효과 표
/// (`shared/routine_effects/routine_effects.json`)의 **한국어 문장**을 채운다.
/// 서버는 그 문장을 바꾸지 않는다 — 트레이너 웹이 받은 문장을 한국어 표와
/// 비교해 자동 문구인지 가려내기 때문이다. 그래서 회원 앱이 표의 문장을 알아보고
/// 화면 언어의 문구로 바꿔 그린다. 트레이너가 직접 쓴 문장은 그대로 둔다.
///
/// 표에 문장이 늘면 여기와 ARB 에 함께 더한다 — 테스트가 공용 JSON 을 읽어
/// 빠진 문장을 잡는다.
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
