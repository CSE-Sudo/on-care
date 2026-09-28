import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 지금 띄운 빌드의 버전(`pubspec.yaml` 의 `version`, 예: `0.1.0`). (#2264)
///
/// 예전에는 고객 지원 아래 버전을 번역 문구에 글자로 박아 두어(`버전 0.1.0`),
/// 배포해도 바뀌지 않았다. 웹 빌드는 `version.json` 에 버전을 적어 두고
/// `package_info_plus` 가 그것을 읽는다. 읽지 못하면 `null` — 화면은 버전 없이
/// 앱 이름만 보인다. 틀린 버전을 보이느니 보이지 않는 편이 낫다.
final appVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final String version = info.version.trim();
    return version.isEmpty ? null : version;
  } on Object {
    return null;
  }
}, name: 'appVersion');
