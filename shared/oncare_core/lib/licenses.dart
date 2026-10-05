/// 두 앱이 함께 쓰는 오픈소스 라이선스 고지. (#3150)
///
/// 의존 패키지의 라이선스는 Flutter 가 빌드 때 모아 [LicenseRegistry] 에 넣는다.
/// 패키지가 아닌 자산 — 두 앱이 담아 배포하는 Pretendard 글꼴(SIL OFL 1.1) —
/// 은 저절로 모이지 않으므로 기동할 때 [registerBundledLicenses] 로 직접 넣는다.
/// OFL 은 글꼴을 함께 배포할 때 라이선스 전문을 함께 줄 것을 요구한다.
///
/// 라이선스 화면은 Flutter 기본 화면([showLicensePage])을 앱 테마 그대로 쓰고,
/// [showOnCareLicenses] 가 앱 이름·버전·로고를 채워 연다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 두 앱 모두 이 경로에 OFL 전문을 두고 `pubspec.yaml` assets 에 등록한다.
const String kPretendardLicenseAsset = 'assets/fonts/Pretendard-OFL.txt';

/// 라이선스 목록에 보일 글꼴 이름.
const String kPretendardPackageName = 'Pretendard';

/// 라이선스 화면 머리에 싣는 앱 로고. 두 앱 모두 같은 경로에 둔다.
const String kOnCareLogoAsset = 'assets/images/oncare-logo.png';

/// 머리 로고의 지름.
const double _logoSize = 48;

bool _registered = false;

/// 앱에 담긴 글꼴의 라이선스를 [LicenseRegistry] 에 넣는다.
///
/// 여러 번 불러도 한 번만 넣는다 — 목록에 같은 글꼴이 겹쳐 보이지 않게.
/// 파일은 라이선스 화면이 목록을 모을 때 읽으므로 기동을 늦추지 않는다.
/// [bundle] 은 테스트가 바꿔 끼운다. 기본은 앱 번들([rootBundle]).
void registerBundledLicenses({AssetBundle? bundle}) {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() => _pretendardLicenses(bundle ?? rootBundle));
}

Stream<LicenseEntry> _pretendardLicenses(AssetBundle bundle) async* {
  final String text = await bundle.loadString(kPretendardLicenseAsset);
  yield LicenseEntryWithLineBreaks(const <String>[
    kPretendardPackageName,
  ], text);
}

/// [registerBundledLicenses] 의 한 번 표시를 되돌린다. 테스트 전용 —
/// [LicenseRegistry.reset] 과 함께 부른다.
@visibleForTesting
void resetBundledLicensesForTest() {
  _registered = false;
}

/// 오픈소스 라이선스 목록 화면을 연다. 앱 이름·버전·로고를 머리에 싣는다.
///
/// 버전을 아직 읽지 못했으면 [applicationVersion] 을 비워 둔다 — 머리에는 앱
/// 이름만 보인다(두 앱 고객 지원의 버전 줄과 같은 규칙). [applicationIcon] 을
/// 주지 않으면 앱 로고([OnCareLicenseLogo])를 싣는다.
void showOnCareLicenses(
  BuildContext context, {
  required String applicationName,
  String? applicationVersion,
  Widget? applicationIcon,
}) {
  showLicensePage(
    context: context,
    applicationName: applicationName,
    applicationVersion: applicationVersion,
    applicationIcon: applicationIcon ?? const OnCareLicenseLogo(),
  );
}

/// 라이선스 화면 머리의 앱 로고. 로고 그림이 이미 원이라 원으로 자른다.
class OnCareLicenseLogo extends StatelessWidget {
  const OnCareLicenseLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _logoSize,
      child: ClipOval(
        child: Image.asset(
          kOnCareLogoAsset,
          fit: BoxFit.cover,
          // 로고를 읽지 못해도 라이선스 목록은 그대로 보여야 한다.
          errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
              const SizedBox.shrink(),
        ),
      ),
    );
  }
}
