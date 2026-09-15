import 'package:intl/intl.dart';

import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// MY 건강 목표 칩 아래 한 줄 — `마지막 변경: 트레이너 · 9월 16일`. (#1832)
///
/// 회원과 담당 트레이너가 같은 건강 목표를 고친다. 승인 대신 누가 언제 바꿨는지를
/// 보여 준다. 바꾼 적이 없으면 null 이라 줄을 그리지 않는다.
String? focusLastChangedLabel(
  AppLocalizations l,
  UserProfile profile, {
  required String locale,
}) {
  final String? by = profile.focusChangedBy;
  final DateTime? at = profile.focusChangedAt;
  if (by == null || at == null) return null;
  final String who = by == UserProfile.focusChangedByTrainer
      ? l.myGoalsFocusChangedByTrainer
      : l.myGoalsFocusChangedByMe;
  return l.myGoalsFocusLastChanged(who, DateFormat.MMMd(locale).format(at));
}
