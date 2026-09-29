import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 운동 시간(초)을 읽는 말로 — `45초` · `30분` · `1시간 30분`. (#2221)
///
/// 0 인 칸은 빼므로 딱 떨어지는 30분은 예전(`30분`)과 같은 모양이다 — 초를
/// 적었을 때만 길어진다. 회원 앱(`formatDurationParts`)과 같은 규칙이되, 단위
/// 사이 띄어쓰기는 로케일이 정한다(`30 min`).
String formatExerciseDuration(AppLocalizations l, int seconds) {
  final int total = seconds < 0 ? 0 : seconds;
  final List<String> parts = <String>[
    if (total ~/ 3600 > 0) l.hoursShort(total ~/ 3600),
    if (total % 3600 ~/ 60 > 0) l.minutesShort(total % 3600 ~/ 60),
    if (total % 60 > 0) l.secondsShort(total % 60),
  ];
  return parts.isEmpty ? l.minutesShort(0) : parts.join(' ');
}
