/// 설정 화면 `버전 정보` 가 보이는 빌드 정보의 해석 규칙(#3226).
///
/// 두 앱은 빌드 때 받은 두 define 을 같은 규칙으로 읽어야 한다.
///
/// - `BUILD_NUMBER` — 릴리스 빌드마다 커지는 빌드 번호. 워크플로가 빌드하는 커밋까지의
///   커밋 수로 만들어(`.github/scripts/release_build_stamp.sh`) `--build-number` 와 함께
///   넣는다. 같은 커밋이면 회원 앱·트레이너 웹, 데모·운영 어디서 만들어도 같은 번호다.
/// - `RELEASE_DATE` — 빌드한 UTC 시각(`2026-10-05T05:30:00Z`). 화면은 KST 로 보인다.
///
/// 로컬 실행·테스트 빌드에는 둘 다 없다. 빌드 번호가 없으면 **개발 빌드**로 본다.
/// 값이 비었거나 모양이 틀리면 그 칸은 없는 것으로 읽는다 — 틀린 번호·시각을 보이느니
/// 보이지 않는 편이 낫다(앱 버전 줄 #2264·#3047 과 같은 원칙). 어떤 입력에도 예외를
/// 던지지 않는다.
///
/// 날짜를 어떤 글자로 적을지는 각 앱의 l10n 이 정한다. 여기는 값만 다룬다.
library;

import 'package:oncare_core/clock.dart';

final RegExp _buildNumberPattern = RegExp(r'^[1-9][0-9]{0,9}$');
final RegExp _releaseDatePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d+)?Z$',
);

/// `BUILD_NUMBER` define 을 빌드 번호로 읽는다. 양의 정수가 아니면 `null`.
///
/// 열 자리를 넘는 값은 받지 않는다 — 커밋 수로는 나올 수 없는 크기라 잘못 넣은 값이다.
int? parseBuildNumber(String? raw) {
  if (raw == null) return null;
  final String value = raw.trim();
  if (!_buildNumberPattern.hasMatch(value)) return null;
  return int.tryParse(value);
}

/// `RELEASE_DATE` define(UTC ISO 8601, `Z` 로 끝남)을 KST 벽시계로 읽는다.
///
/// 시간대 표시가 없거나 다른 오프셋이면 `null` — 어느 시각인지 모호한 값을 KST 로
/// 단정하지 않는다. 돌려주는 값은 [toKst] 와 같은 약속(필드에 서울 시각을 담은 로컬
/// `DateTime`)이라 기기·브라우저 시간대와 상관없이 같은 시각이 보인다.
///
/// `DateTime.parse` 는 13월·40일 같은 범위 밖 값을 다음 달로 넘겨 받아 주므로, 읽은
/// 값의 필드가 원문과 같은지 한 번 더 본다.
DateTime? parseReleaseDateKst(String? raw) {
  if (raw == null) return null;
  final String value = raw.trim();
  final RegExpMatch? match = _releaseDatePattern.firstMatch(value);
  if (match == null) return null;
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) return null;
  final List<int> fields = <int>[
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
  ];
  for (int i = 0; i < fields.length; i++) {
    if (int.parse(match.group(i + 1)!) != fields[i]) return null;
  }
  return toKst(parsed);
}

/// 화면에 보일 빌드 정보 한 묶음.
class BuildInfo {
  const BuildInfo({this.version, this.buildNumber, this.releasedAtKst});

  /// define 원문과 읽은 버전 이름으로 만든다. 틀린 값은 그 칸만 비운다.
  ///
  /// [version] 은 `package_info_plus` 가 읽은 pubspec 버전 이름(`0.4.0`)이다. 비어
  /// 있으면 `null` 로 둔다.
  factory BuildInfo.fromDefines({
    String? version,
    String? buildNumber,
    String? releaseDate,
  }) {
    final String? name = version?.trim();
    return BuildInfo(
      version: name == null || name.isEmpty ? null : name,
      buildNumber: parseBuildNumber(buildNumber),
      releasedAtKst: parseReleaseDateKst(releaseDate),
    );
  }

  /// pubspec 버전 이름. 읽지 못했으면 `null`.
  final String? version;

  /// 자동 빌드 번호. 개발 빌드면 `null`.
  final int? buildNumber;

  /// 빌드한 시각(KST 벽시계). 없거나 틀렸으면 `null`.
  final DateTime? releasedAtKst;

  /// 배포 정보가 없는 빌드(로컬 실행·테스트). 빌드 번호 하나로 정한다 — 시각만 있는
  /// 빌드는 어느 배포인지 가리킬 수 없다.
  bool get isDevelopmentBuild => buildNumber == null;

  /// 버전과 빌드 번호를 `0.4.0 (7032)` 형식으로 묶는다. 두 앱이 같은 모양을 쓴다.
  ///
  /// 개발 빌드는 버전 이름만, 버전 이름을 못 읽었으면 `(7032)` 처럼 번호만 남긴다.
  /// 둘 다 없으면 `null`.
  String? get versionLabel {
    final String? name = version;
    final int? build = buildNumber;
    if (name == null) return build == null ? null : '($build)';
    return build == null ? name : '$name ($build)';
  }

  @override
  bool operator ==(Object other) =>
      other is BuildInfo &&
      other.version == version &&
      other.buildNumber == buildNumber &&
      other.releasedAtKst == releasedAtKst;

  @override
  int get hashCode => Object.hash(version, buildNumber, releasedAtKst);

  @override
  String toString() =>
      'BuildInfo(version: $version, buildNumber: $buildNumber, '
      'releasedAtKst: $releasedAtKst)';
}
