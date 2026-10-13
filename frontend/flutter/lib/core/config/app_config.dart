import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_social_login/oncare_social_login.dart';

enum Environment { dev, staging, prod }

/// 데모 배포(GitHub Pages) 빌드 표시 — `--dart-define=DEMO_BUILD=true` (#3022).
///
/// 컴파일 타임 상수다. [kDemoCodeIncluded] 가 이 값으로 목업 코드의 포함 여부를 정한다.
const bool kDemoBuild = bool.fromEnvironment('DEMO_BUILD');

/// 목업·데모 코드(로컬 API·시드·목업 저장소)가 이 빌드에 들어가는가(#3157).
///
/// 데모 빌드이거나 릴리스가 아닌 빌드(`flutter run`·테스트·프로파일)면 참이다. 운영
/// 릴리스 빌드(`DEMO_BUILD` 없음)에서는 **상수 false** 라 [AppConfig.useMockApi] 가
/// 늘 false 로 접히고, 그 뒤의 목업 분기 전체를 dart2js·AOT 가 트리 셰이킹한다 —
/// 데모 계정·시드 인물·로컬 API 가 운영 배포물에 실리지 않는다. 운영 빌드 산출물에
/// 데모 문자열이 없는지는 `tool/ci/check_prod_web_bundle.py` 가 CI 에서 확인한다.
const bool kDemoCodeIncluded = kDemoBuild || !kReleaseMode;

/// 릴리스 빌드로 내보내면 안 되는 설정 조합 하나(#3022).
///
/// 컴파일 타임 기본값은 로컬 개발용이다(`ENV=dev`·`USE_MOCK_API=true`·예시 주소).
/// 릴리스 빌드 명령에서 define 하나를 빠뜨려도 빌드는 성공하므로, 앱이 기동할 때
/// 스스로 이 목록을 보고 기능 화면에 들어가지 않는다([releaseGuardProblems]).
enum ReleaseProblem {
  /// `ENV` 가 `prod`·`staging` 이 아니다 — API 요청 로그·라우터 진단 로그·개발용
  /// 경로가 켜지고, 오류 보고가 꺼진다.
  devEnvironment,

  /// 목업(`USE_MOCK_API=true`)인데 데모 빌드 표시(`DEMO_BUILD=true`)가 없다 —
  /// 실서버 대신 기기 안 데모 데이터로 도는 앱이다.
  mockWithoutDemoBuild,

  /// 실서버를 부르는데 API 주소가 예시·로컬 주소다(`example.com` 계열 등).
  placeholderApiUrl,

  /// 실서버를 부르는데 API 주소가 `https://` 가 아니거나 읽을 수 없다.
  insecureApiUrl,

  /// 데모 빌드 표시(`DEMO_BUILD=true`) 없이 로그인 화면의 데모 진입
  /// (`SHOW_DEMO_ENTRY=true`)이 켜졌다 — 실제 사용자가 데모 계정으로 들어가 데모
  /// 데이터를 보게 된다(#3147).
  demoEntryWithoutDemoBuild,

  /// 데모 빌드 표시 없이 부분 실연동 스위치(`REAL_API`)가 남았다 — 목업 빌드에서
  /// 일부 경로만 실서버로 보내는 데모 전용 값이라, 운영 빌드에서는 어떤 요청이
  /// 어디로 가는지 판단을 흐린다(#3147).
  realApiWithoutDemoBuild,
}

/// 실서버 주소로 쓸 수 없는 예약·로컬 호스트(RFC 2606·6761).
bool isPlaceholderHost(String host) {
  final String h = host.toLowerCase();
  const List<String> reservedDomains = <String>[
    'example.com',
    'example.org',
    'example.net',
  ];
  const List<String> reservedTlds = <String>[
    '.example',
    '.test',
    '.invalid',
    '.localhost',
  ];
  return h == 'localhost' ||
      h == '127.0.0.1' ||
      h == '::1' ||
      reservedDomains.any((String d) => h == d || h.endsWith('.$d')) ||
      reservedTlds.any(h.endsWith);
}

/// [apiBaseUrl] 이 실서버 주소로 쓸 수 있는가 — 문제 목록을 돌려준다.
List<ReleaseProblem> apiBaseUrlProblems(String apiBaseUrl) {
  final Uri? uri = Uri.tryParse(apiBaseUrl.trim());
  if (uri == null || uri.host.isEmpty) {
    return const <ReleaseProblem>[ReleaseProblem.insecureApiUrl];
  }
  return <ReleaseProblem>[
    if (uri.scheme != 'https') ReleaseProblem.insecureApiUrl,
    if (isPlaceholderHost(uri.host)) ReleaseProblem.placeholderApiUrl,
  ];
}

/// [apiBaseUrl] 이 이 컴퓨터(루프백)의 백엔드인가 — 데모 Pages 의 `local` 빌드용.
bool isLoopbackApiUrl(String apiBaseUrl) {
  final String host = (Uri.tryParse(apiBaseUrl.trim())?.host ?? '')
      .toLowerCase();
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '[::1]';
}

/// 기동 시 가드가 볼 문제 목록. 릴리스 모드가 아니면(`flutter run`·테스트) 늘
/// 비어 있다 — 로컬 개발은 기본값 그대로 돈다(#3022).
List<ReleaseProblem> releaseGuardProblems(
  AppConfig config, {
  bool releaseMode = kReleaseMode,
}) => releaseMode ? config.releaseProblems() : const <ReleaseProblem>[];

/// 실 백엔드로 넘길 엔드포인트 하나 — **메서드까지 함께** 본다.
///
/// 경로 접두사만으로 판정하면 같은 접두사의 읽기까지 함께 열린다. 그것이 실제로
/// 문제를 만들었기 때문에 메서드를 계약에 넣는다([kRealApiFeatures] 참고).
class RealApiRoute {
  /// 이 메서드 + 경로 접두사에 해당하는 요청을 실 백엔드로 보낸다.
  const RealApiRoute(this.method, this.pathPrefix);

  /// HTTP 메서드. 대문자로 적는다.
  final String method;

  /// 경로 접두사. `/` 로 시작한다.
  final String pathPrefix;

  /// [method]/[path] 요청이 이 경로에 해당하는가.
  bool matches(String method, String path) =>
      method.toUpperCase() == this.method && path.startsWith(pathPrefix);
}

/// `REAL_API` 로 켤 수 있는 기능 키 → 실 백엔드로 보낼 엔드포인트.
///
/// 목업 인터셉터가 가로채는 요청 중 **어디까지를 실 서버로 넘길지**를 여기 한 곳에서
/// 정한다. 기능별로 임시 플래그(`REAL_AI_COACH`, `REAL_AUTH` …)를 각각 만들면
/// `AppConfig` 와 인터셉터라는 같은 파일이 이슈마다 고쳐져 충돌하므로, 키 목록을 받는
/// 스위치 하나로 통일한다.
///
/// ## 기준선: 쓰기만 실 서버, 읽기는 로컬 (#616)
///
/// 예전에는 키가 경로 접두사였다(`'ai-coach' → '/ai-coach'`). 그러면 켜는 순간 대화
/// 전송뿐 아니라 **이력 조회까지** 실 서버로 갔고, 두 가지가 깨졌다.
///
///  * 코치 화면을 열 때 읽는 초기 이력이 데모 것에서 서버 것으로 바뀐다 — 데모 화면은
///    스위치와 무관하게 지금 그대로여야 한다.
///  * 배포 데모는 토큰이 없어 방문자 전원이 데모 계정 하나를 공유한다. 이력을 서버에서
///    읽으면 다음 방문자가 앞 방문자의 질문을 그대로 보게 된다.
///
/// 그래서 여는 것은 **AI 가 실제로 일하는 호출(쓰기)** 뿐이다. 조회는 로컬 인터셉터가
/// 계속 담당하므로 화면의 초기 상태가 움직이지 않는다.
///
/// 새 기능을 켤 수 있게 하려면 여기에 키와 엔드포인트만 추가한다 — 인터셉터는 손대지
/// 않는다. 추가할 때도 같은 기준을 지킨다: 조회를 여는 것은 그럴 이유를 따로 적을 때뿐이다.
const Map<String, List<RealApiRoute>> kRealApiFeatures =
    <String, List<RealApiRoute>>{
      // AI 코치(온이). 대화 전송만 실 서버로 — 이력·피드백 조회는 로컬이 준다.
      'ai-coach': <RealApiRoute>[RealApiRoute('POST', '/ai-coach/chat')],
      // 소셜 로그인 포함 인증. `/auth/*` 는 전부 쓰기(로그인·가입·소셜 교환)라
      // 접두사 하나로 충분하다.
      'auth': <RealApiRoute>[RealApiRoute('POST', '/auth')],
      // 식단 사진 분석만 실 서버로 — 날짜별 조회·추천·수정·삭제는 로컬이 준다.
      'diet': <RealApiRoute>[RealApiRoute('POST', '/diet/analyze')],
    };

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required bool useMockApi,
    this.sentryDsn,
    this.realApiFeatures = const <String>{},
    this.showDemoEntry = false,
    this.iosAppStoreId,
    this.demoBuild = false,
    this.socialLogin = const SocialLoginConfig(),
  }) : mockApiRequested = useMockApi;

  final Environment environment;

  /// FastAPI 백엔드 주소. **`/v1` 접두사까지 포함한다** — 요청 경로는
  /// `/auth/login` 처럼 `/v1` 없이 쓰인다. 트레이너 웹과 같은 규칙이다(#2810).
  final String apiBaseUrl;
  final String? sentryDsn;

  /// When true, `LocalApiInterceptor` short-circuits any HTTP request
  /// matching a known path and answers from the drift-backed demo store.
  ///
  /// [mockApiRequested] 는 빌드 값 그대로이고, 이 값은 [kDemoCodeIncluded] 를 함께
  /// 본다 — 운영 릴리스에서는 늘 false 라 목업 분기가 번들에서 빠진다(#3157).
  bool get useMockApi => kDemoCodeIncluded && mockApiRequested;

  /// 빌드 값(`USE_MOCK_API`) 그대로 — 목업을 요청했는가. 릴리스 가드
  /// ([releaseProblems])는 이 값을 본다. 운영 릴리스에 목업을 잘못 요청한 빌드도
  /// 가드가 알아채야 해서다.
  final bool mockApiRequested;

  /// 목업 모드에서도 **실 백엔드를 쓸 기능 키** 목록.
  ///
  /// `useMockApi` 는 전역 스위치라 끄는 순간 로그인·홈·식단·운동·채팅이 한꺼번에
  /// 실서버로 넘어간다. 그래서 준비된 기능 하나만 먼저 실연동해 보여줄 수가 없었다.
  /// 이 목록에 든 키에 해당하는 경로는 목업 인터셉터가 가로채지 않고 실 네트워크로
  /// 흘려보낸다.
  ///
  /// 비어 있으면(기본값) 지금까지의 데모 동작과 **완전히 동일**하다.
  ///
  /// 키 → 엔드포인트 대응은 [kRealApiFeatures] 참고.
  /// 예: `--dart-define=REAL_API=ai-coach,auth`
  final Set<String> realApiFeatures;

  /// 이 요청을 목업이 아니라 실 백엔드로 보내야 하는가.
  ///
  /// 경로만이 아니라 [method] 도 함께 받는다 — 같은 접두사의 조회까지 딸려 열리면
  /// 데모 화면이 바뀌기 때문이다([kRealApiFeatures] 참고).
  bool isRealApi(String method, String path) {
    if (realApiFeatures.isEmpty) return false;
    for (final String feature in realApiFeatures) {
      final List<RealApiRoute> routes =
          kRealApiFeatures[feature] ?? const <RealApiRoute>[];
      for (final RealApiRoute route in routes) {
        if (route.matches(method, path)) return true;
      }
    }
    return false;
  }

  /// 소셜 로그인을 기기 안 목업으로 보내는가 — 고정 토큰을 쓴다(데모·개발).
  ///
  /// 실 인증을 쓰는 설정은 [socialLogin] 의 키로 카카오·구글 SDK 를 부른다(#330).
  /// 키가 없는 provider 는 버튼이 꺼지고, 하나도 없으면 '준비 중' 안내가 뜬다(#2769).
  bool get usesMockSocialLogin =>
      useMockApi && !isProd && !isRealApi('POST', '/auth/social');

  /// 카카오·구글 로그인 키(`KAKAO_NATIVE_APP_KEY` 등, #330). 모두 공개 식별자다.
  final SocialLoginConfig socialLogin;

  /// 로그인 화면에 "로그인 없이 데모 둘러보기" 진입을 노출할지. (#1526)
  ///
  /// 기본은 꺼짐 — 로그인 없이 앱 안으로 들어가는 경로를 화면에서 내렸다. 코드와
  /// 문구·`SessionController.enterDemo` 는 그대로 살려 두고 노출만 막는다.
  /// 주석 처리 대신 플래그인 이유: 죽은 코드는 주변이 바뀌면 그대로 되살아나지
  /// 않지만, 플래그는 경로가 살아 있어 테스트가 계속 지켜 준다.
  ///
  /// 다시 열 때: `--dart-define=SHOW_DEMO_ENTRY=true`
  final bool showDemoEntry;

  /// App Store 의 앱 ID(숫자, `https://apps.apple.com/app/id<ID>`). (#3045)
  ///
  /// 앱을 App Store Connect 에 등록해야 정해지므로 `--dart-define=IOS_APP_STORE_ID`
  /// 로 넣는다. 없으면 업데이트 화면이 버튼 대신 App Store 에서 업데이트하라는
  /// 안내만 보인다.
  final String? iosAppStoreId;

  /// 데모 배포(GitHub Pages) 빌드 표시 — `--dart-define=DEMO_BUILD=true` (#3022).
  ///
  /// 릴리스 빌드에서 목업을 허용하는 유일한 근거다. 데모 배포 워크플로(`deploy.yml`)만
  /// 넘기고, 스토어·운영 웹 빌드는 넘기지 않는다.
  final bool demoBuild;

  bool get isProd => environment == Environment.prod;
  bool get isDev => environment == Environment.dev;

  /// 실 네트워크로 나가는 요청이 있는가 — 실서버 모드이거나 일부 기능을 실서버로 연다.
  bool get usesNetwork => !useMockApi || realApiFeatures.isNotEmpty;

  /// 이 설정을 릴리스로 내보내면 생기는 문제들. 비어 있으면 내보내도 된다(#3022).
  ///
  /// 순수 함수다 — 빌드 모드는 보지 않는다. 기동 가드는 [releaseGuardProblems] 로
  /// 릴리스 모드일 때만 이 목록을 쓴다.
  ///
  /// * 데모 빌드(`DEMO_BUILD=true` + 목업)는 `ENV=dev` 여도 된다 — 데모 Pages 가
  ///   지금 그렇게 빌드된다.
  /// * 주소는 실 네트워크를 쓸 때만 본다. 목업 빌드는 주소를 넘기지 않는다.
  /// * 데모 진입(`SHOW_DEMO_ENTRY`)·부분 실연동(`REAL_API`)은 데모 빌드에서만 된다
  ///   (#3147). 데모 Pages 는 `DEMO_BUILD=true` 를 넘기므로 지금처럼 뜬다.
  List<ReleaseProblem> releaseProblems() {
    final bool demoMock = mockApiRequested && demoBuild;
    // 데모 Pages 를 내 컴퓨터 백엔드(localhost)에 붙인 빌드 — 배포 웹에서 회원·트레이너
    // 연동을 로컬 서버로만 확인할 때 쓴다. 데모 빌드에서만 허용한다.
    final bool demoLocal =
        demoBuild && !mockApiRequested && isLoopbackApiUrl(apiBaseUrl);
    return <ReleaseProblem>[
      if (isDev && !demoMock && !demoLocal) ReleaseProblem.devEnvironment,
      if (mockApiRequested && !demoBuild) ReleaseProblem.mockWithoutDemoBuild,
      if (showDemoEntry && !demoBuild) ReleaseProblem.demoEntryWithoutDemoBuild,
      if (realApiFeatures.isNotEmpty && !demoBuild)
        ReleaseProblem.realApiWithoutDemoBuild,
      if (usesNetwork && !demoLocal) ...apiBaseUrlProblems(apiBaseUrl),
    ];
  }

  factory AppConfig.fromEnvironment() {
    const envStr = String.fromEnvironment('ENV', defaultValue: 'dev');
    final env = switch (envStr) {
      'prod' => Environment.prod,
      'staging' => Environment.staging,
      _ => Environment.dev,
    };
    // 기본값은 자리표시자다. 운영 웹 빌드는 저장소 변수에서 실제 주소를 받고, 비어
    // 있으면 배포 워크플로가 빌드 전에 멈춘다(#2810). 트레이너 웹과 맞춰 `/v1` 까지
    // 적어 둔다 — 값을 넣을 때 `/v1` 을 빠뜨리는 실수를 막기 위해서다.
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://dev.api.oncare.example.com/v1',
    );
    const sentryDsn = String.fromEnvironment('SENTRY_DSN');
    const useMockApi = bool.fromEnvironment('USE_MOCK_API', defaultValue: true);
    // 예: --dart-define=REAL_API=ai-coach,auth
    // 알 수 없는 키는 무시된다(오타가 조용히 전 기능을 실서버로 보내지 않도록,
    // 매칭되는 경로가 없으면 아무 일도 일어나지 않는다).
    const realApi = String.fromEnvironment('REAL_API');
    const showDemoEntry = bool.fromEnvironment('SHOW_DEMO_ENTRY');
    const iosAppStoreId = String.fromEnvironment('IOS_APP_STORE_ID');
    // 데모 Pages 빌드만 넘긴다(#3022). 릴리스 가드가 목업을 허용하는 근거다.
    const demoBuild = kDemoBuild;
    return AppConfig(
      environment: env,
      apiBaseUrl: apiBaseUrl,
      sentryDsn: sentryDsn.isEmpty ? null : sentryDsn,
      useMockApi: useMockApi,
      realApiFeatures: <String>{
        for (final String key in realApi.split(','))
          if (key.trim().isNotEmpty) key.trim(),
      },
      // 기본값과 같은 값이어도 그대로 흘려보낸다 — SHOW_DEMO_ENTRY 를 주면
      // 여기서 값이 갈린다.
      // ignore: avoid_redundant_argument_values
      showDemoEntry: showDemoEntry,
      iosAppStoreId: iosAppStoreId.trim().isEmpty ? null : iosAppStoreId.trim(),
      // ignore: avoid_redundant_argument_values
      demoBuild: demoBuild,
      socialLogin: SocialLoginConfig.fromEnvironment(),
    );
  }
}

/// Override in [ProviderScope] at app startup with the value resolved
/// from [AppConfig.fromEnvironment]. Reading it before override throws.
final appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError(
    'appConfigProvider must be overridden in ProviderScope before use.',
  );
});
