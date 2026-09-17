import 'package:oncare/features/account/presentation/health_focus_label.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// [ExerciseGoal] → 화면 문구. 상담 신청 폼과 상담 내역 카드가 함께 쓴다. (#1992)
///
/// 여덟 목표는 건강 목표와 **같은 문구**로 부른다 — 온보딩에서 고른 이름이 상담에서
/// 다른 이름으로 불리면 회원은 같은 것인지 알 수 없다. 그래서 문구도 건강 목표 쪽
/// ([healthFocusLabel])에서 한 번만 만든다.
///
/// 여덟 목표 밖은 이 화면만 부르는 이름이 있다 — [ExerciseGoal.other] 는 `기타`,
/// 없앤 선택지로 이미 저장된 [ExerciseGoal.health] 는 저장될 때의 `건강 관리` 다.
String exerciseGoalLabel(AppLocalizations l, ExerciseGoal goal) {
  final String? focus = exerciseGoalHealthFocus(goal);
  if (focus != null) return healthFocusLabel(l, focus);
  return switch (goal) {
    ExerciseGoal.health => l.exGoalHealth,
    _ => l.exOptionOther,
  };
}
