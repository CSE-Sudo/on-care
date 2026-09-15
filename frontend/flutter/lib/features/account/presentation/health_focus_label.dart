import 'package:oncare/features/account/domain/entities/health_focus.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 건강 목표 저장 값 → 화면 문구. 온보딩과 MY `건강 목표` 가 함께 쓴다. (#1814)
///
/// 저장 값은 로케일과 상관없이 한국어로 고정한다 — AI 코치·트레이너 추천이 같은
/// 값을 읽는다. 모르는 값은 받은 그대로 보여 준다.
String healthFocusLabel(AppLocalizations l, String value) => switch (value) {
  kHealthFocusWeightLoss => l.healthFocusWeightLoss,
  kHealthFocusStrength => l.healthFocusStrength,
  kHealthFocusFitness => l.healthFocusFitness,
  kHealthFocusPosture => l.healthFocusPosture,
  kHealthFocusRehab => l.healthFocusRehab,
  kHealthFocusEating => l.healthFocusEating,
  kHealthFocusExerciseHabit => l.healthFocusExerciseHabit,
  kHealthFocusBloodPressure => l.healthFocusBloodPressure,
  _ => value,
};
