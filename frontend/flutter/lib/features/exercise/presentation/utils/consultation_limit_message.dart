import 'package:oncare/gen/l10n/app_localizations.dart';

/// 상담 신청 한도에 걸렸을 때의 안내 문구. (#1628)
///
/// 서버가 알려 준 `Retry-After` 를 회원이 읽을 수 있는 단위로 올려 적는다 — 한
/// 시간 이상이면 시간, 그보다 짧으면 분. 올림인 이유: 내림으로 적으면 안내한 시각에
/// 다시 눌러도 아직 막혀 있다.
String consultationRateLimitedMessage(
  AppLocalizations l,
  Duration? retryAfter,
) {
  if (retryAfter == null || retryAfter <= Duration.zero) {
    return l.exConsultRateLimited;
  }
  final int minutes = (retryAfter.inSeconds / 60).ceil();
  if (minutes >= 60) {
    return l.exConsultRateLimitedHours((minutes / 60).ceil());
  }
  return l.exConsultRateLimitedMinutes(minutes);
}

/// 답을 기다리는 요청이 상한에 닿았을 때의 안내 문구. (#1628)
String consultationTooManyPendingMessage(AppLocalizations l, int? limit) =>
    limit == null
    ? l.exConsultTooManyPendingNoCount
    : l.exConsultTooManyPending(limit);
