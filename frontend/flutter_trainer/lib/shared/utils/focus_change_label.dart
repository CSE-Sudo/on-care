import 'package:intl/intl.dart';

import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 회원 신체·목표 창의 건강 목표 칩 아래 한 줄 — `마지막 변경: 회원 · 9월 16일`. (#1832)
///
/// 회원앱 MY 건강 목표와 같은 줄이다. 트레이너와 회원이 같은 목표를 고치므로 승인
/// 대신 누가 언제 바꿨는지를 보여 준다. 바꾼 적이 없으면 null 이라 줄을 그리지 않는다.
String? focusLastChangedLabel(
  AppLocalizations l,
  MemberHealthProfile profile, {
  required String locale,
}) {
  final String? by = profile.focusChangedBy;
  final DateTime? at = profile.focusChangedAt;
  if (by == null || at == null) return null;
  final String who = by == MemberHealthProfile.focusChangedByTrainer
      ? l.memberHealthFocusChangedByTrainer
      : l.memberHealthFocusChangedByMember;
  return l.memberHealthFocusLastChanged(
    who,
    DateFormat.MMMd(locale).format(at),
  );
}
