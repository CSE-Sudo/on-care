import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/build_info.dart';
import 'package:oncare_trainer/core/release/build_info.dart';
import 'package:oncare_trainer/features/my/data/app_version.dart';

/// 고객 지원 버전 줄이 보일 빌드 정보 — pubspec 버전 이름, 빌드 번호, 배포 일시(#3226).
///
/// 버전 이름은 [appVersionProvider] 를 그대로 쓴다(읽기 전·실패면 `null`). 해석 규칙은
/// 회원 앱과 같은 `oncare_core` 의 [BuildInfo.fromDefines] 다. 테스트는 이 provider 를
/// 덮어 배포 빌드·개발 빌드를 만든다.
final buildInfoProvider = Provider<BuildInfo>((ref) {
  return BuildInfo.fromDefines(
    version: ref.watch(appVersionProvider).valueOrNull,
    buildNumber: kBuildNumber,
    releaseDate: kReleaseDate,
  );
}, name: 'buildInfo');
