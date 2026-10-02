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
}) => _lastChanged(
  l,
  profile.focusChangedBy,
  profile.focusChangedAt,
  locale: locale,
);

/// 건강상태·주의사항 글 아래 같은 모양의 한 줄. (#2942)
///
/// 목표 칩 기록과 따로다 — 주의사항만 고친 저장은 칩 줄을 움직이지 않는다.
String? notesLastChangedLabel(
  AppLocalizations l,
  MemberHealthProfile profile, {
  required String locale,
}) => _lastChanged(
  l,
  profile.notesChangedBy,
  profile.notesChangedAt,
  locale: locale,
);

String? _lastChanged(
  AppLocalizations l,
  String? by,
  DateTime? at, {
  required String locale,
}) {
  if (by == null || at == null) return null;
  final String who = by == MemberHealthProfile.focusChangedByTrainer
      ? l.memberHealthFocusChangedByTrainer
      : l.memberHealthFocusChangedByMember;
  return l.memberHealthFocusLastChanged(
    who,
    DateFormat.MMMd(locale).format(at),
  );
}
