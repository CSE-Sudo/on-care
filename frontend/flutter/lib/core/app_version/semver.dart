/// 앱 버전 이름(`MAJOR.MINOR.PATCH`) 비교(#3045).
///
/// `pubspec.yaml` 의 `version: 0.4.0+4` 에서 `+` 뒤 빌드 번호는 스토어 업로드
/// 순번일 뿐이라 비교에서 뺀다. 자리마다 숫자로 비교하므로 `1.10.0` 이 `1.9.0`
/// 보다 높다(문자열 비교와 다르다).
class AppSemver implements Comparable<AppSemver> {
  const AppSemver(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final RegExp _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$');

  /// [raw] 를 읽는다. 형식이 다르면 `null` — 비교하지 않는다.
  static AppSemver? tryParse(String? raw) {
    if (raw == null) return null;
    final RegExpMatch? m = _pattern.firstMatch(raw.trim());
    if (m == null) return null;
    final int? major = int.tryParse(m.group(1)!);
    final int? minor = int.tryParse(m.group(2)!);
    final int? patch = int.tryParse(m.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    return AppSemver(major, minor, patch);
  }

  @override
  int compareTo(AppSemver other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(AppSemver other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is AppSemver &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
