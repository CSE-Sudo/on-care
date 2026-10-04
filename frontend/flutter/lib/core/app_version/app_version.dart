import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 지금 띄운 빌드의 버전 이름(`pubspec.yaml` 의 `version` 중 `+` 앞, 예: `0.4.0`).
/// (#3047)
///
/// 모바일은 `versionName`·`CFBundleShortVersionString`, 웹은 빌드의
/// `version.json` 에서 읽힌다. 모두 `pubspec.yaml` 이 원본이다. 읽지 못하면
/// `null` — 화면은 버전 없이 앱 이름만 보인다. 틀린 버전을 보이느니 보이지 않는
/// 편이 낫다(트레이너 웹 #2264 와 같은 원칙).
///
/// 최소 지원 버전 확인(#3045)도 이 값을 쓴다.
final appVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final String version = info.version.trim();
    return version.isEmpty ? null : version;
  } on Object {
    return null;
  }
}, name: 'appVersion');
