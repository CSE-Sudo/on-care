// DateFormat 만 가져온다 — intl 의 TextDirection 이 dart:ui 것과 충돌한다.
import 'package:intl/intl.dart' show DateFormat;
import 'package:oncare_core/build_info.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 이 번들의 빌드 번호(#3226).
///
/// 릴리스 웹 빌드(데모 Pages·운영)가 `--build-number` 와 함께
/// `--dart-define=BUILD_NUMBER=...` 로 넣는다. 값은 빌드한 커밋까지의 커밋 수라
/// 병합할 때마다 커지고, 같은 배포의 회원 앱과 같은 번호다. 로컬 실행·테스트
/// 빌드에는 없어 빈 값이고, 그러면 설정의 `버전 정보` 가 개발 빌드로 보인다.
const String kBuildNumber = String.fromEnvironment('BUILD_NUMBER');

/// 이 번들을 빌드한 UTC 시각(ISO 8601, 예: `2026-10-05T05:30:00Z`). (#3226)
///
/// [kBuildNumber] 와 같은 단계에서 워크플로가 넣는다. 화면은 KST 로 바꿔 보인다.
const String kReleaseDate = String.fromEnvironment('RELEASE_DATE');

/// 배포 일시를 화면 언어의 날짜·시각으로 적는다 — `2026년 10월 5일 14:30` /
/// `Oct 5, 2026 14:30`. [kst] 는 이미 KST 벽시계다.
String formatReleaseDate(DateTime kst, String locale) {
  return DateFormat.yMMMd(locale).add_Hm().format(kst);
}

/// `버전 정보` 줄의 설명 한 줄 — 회원 앱과 같은 모양이다.
///
/// - 배포 빌드: `0.2.0 (7032) · 2026년 10월 5일 14:30 KST 배포`
/// - 배포 일시를 읽지 못한 배포 빌드: `0.2.0 (7032)`
/// - 개발 빌드: `0.2.0 · 개발 빌드` (버전 이름도 못 읽었으면 `개발 빌드`)
String buildInfoSummary(AppLocalizations l, String locale, BuildInfo info) {
  final List<String> parts = <String>[
    ?info.versionLabel,
    if (info.isDevelopmentBuild)
      l.buildInfoDevelopment
    else if (info.releasedAtKst case final DateTime at)
      l.buildInfoReleasedAt(formatReleaseDate(at, locale)),
  ];
  return parts.join(' · ');
}
