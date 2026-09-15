import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/health_focus.dart';

/// 건강 목표 저장 값 → 화면 문구. 저장 값은 로케일과 상관없이 한국어다. (#1818)
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

/// 로스터 목표(`체중 감량 · 혈압 관리`)를 로케일 문구로. 목표가 아닌 조각은 받은
/// 그대로 둔다 — 옛 데이터의 자유 문장이 사라지지 않게.
String healthFocusGoalLabel(AppLocalizations l, String goal) => goal
    .split(kHealthFocusLabelSeparator.trim())
    .map((String part) => part.trim())
    .where((String part) => part.isNotEmpty)
    .map((String part) => healthFocusLabel(l, part))
    .join(kHealthFocusLabelSeparator);
