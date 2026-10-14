import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// 로그인 화면 `체험하기` 를 다른 사이트의 둘러보기 데모로 보내는 길(#3437).
///
/// 운영 서버는 데모 폴백이 꺼져 있어(`ENV=prod`) 운영 빌드에서 앱 안 데모로
/// 들어가면 화면이 모두 401 로 빈다. 그래서 운영 웹 빌드는 `DEMO_SITE_URL`
/// (GitHub Pages 데모의 같은 앱 주소)을 받아, 체험하기를 누르면 같은 탭에서 그
/// 주소로 옮긴다. 주소에 [kDemoEntryQueryKey] 표시를 붙여 데모 쪽이 로그인 화면을
/// 건너뛰고 곧장 데모로 들어가게 한다([demoEntryLinkProvider]).

/// 데모 사이트에 붙이는 진입 표시의 질의 키. 값은 [kDemoEntryQueryValue].
///
/// 해시 라우팅(`#/…`) 앞의 질의라 라우터 위치에는 섞이지 않는다.
const String kDemoEntryQueryKey = 'demo';

/// 진입 표시의 값.
const String kDemoEntryQueryValue = '1';

/// [site] 로 갈 체험하기 주소 — 진입 표시를 붙인다. 주소가 비었거나
/// `https://` 가 아니면 null 이다(그때 화면은 앱 안 데모 진입을 쓴다).
Uri? demoSiteEntryAddress(String? site) {
  final String raw = site?.trim() ?? '';
  if (raw.isEmpty) return null;
  final Uri? uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri.removeFragment().replace(
    queryParameters: <String, String>{
      ...uri.queryParameters,
      kDemoEntryQueryKey: kDemoEntryQueryValue,
    },
  );
}

/// [page] 가 운영 앱의 체험하기에서 넘어온 주소인가.
bool isDemoEntryLink(Uri page) =>
    page.queryParameters[kDemoEntryQueryKey] == kDemoEntryQueryValue;

/// 이 실행이 곧장 데모로 들어가야 하는가 — 기동 때 한 번 정한다(#3437).
///
/// 앱 안 데모 진입이 열린 빌드(`SHOW_DEMO_ENTRY=true` — 데모 Pages)이고, 웹 페이지
/// 주소에 진입 표시가 있을 때만 참이다. 운영 빌드는 데모 진입이 닫혀 있어 표시가
/// 붙어 와도 거짓이다. 저장된 토큰이 있으면 세션 복원이 먼저다 — 이 값은 토큰이
/// 없을 때 로그인 화면 대신 데모로 들이는 데만 쓴다.
bool shouldEnterDemoOnLaunch(
  AppConfig config, {
  bool isWeb = kIsWeb,
  Uri? page,
}) =>
    isWeb &&
    config.showDemoEntry &&
    demoSiteEntryAddress(config.demoSiteUrl) == null &&
    isDemoEntryLink(page ?? Uri.base);

/// 기동 때 정한 [shouldEnterDemoOnLaunch] 값. 기본은 거짓이고 `bootstrap()` 이
/// 덮는다 — 테스트·기존 화면은 지금과 같이 로그인 화면에서 시작한다.
final demoEntryLinkProvider = Provider<bool>(
  (ref) => false,
  name: 'demoEntryLink',
);

/// 체험하기 주소를 같은 탭에서 연다. 테스트는 이 provider 를 덮어 연 주소를 본다.
final demoSiteLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (Uri target) => launchUrl(target, webOnlyWindowName: '_self'),
  name: 'demoSiteLauncher',
);
