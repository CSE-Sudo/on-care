import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Deployment environment. Selected at build time via `--dart-define=ENV`.
enum Environment { dev, staging, prod }

/// 릴리스 빌드로 내보내면 안 되는 설정 조합 하나(#3022).
///
/// 컴파일 타임 기본값은 로컬 개발용이다(`ENV=dev`·`USE_MOCK_API=true`·예시 주소).
/// 릴리스 빌드 명령에서 define 하나를 빠뜨려도 빌드는 성공하므로, 앱이 기동할 때
/// 스스로 이 목록을 보고 기능 화면에 들어가지 않는다([releaseGuardProblems]).
enum ReleaseProblem {
  /// `ENV` 가 `prod`·`staging` 이 아니다 — API 요청 로그가 켜지고, 오류 보고가
  /// 꺼진다.
  devEnvironment,

  /// 목업(`USE_MOCK_API=true`)인데 데모 빌드 표시(`DEMO_BUILD=true`)가 없다 —
  /// 실서버 대신 기기 안 데모 데이터로 도는 앱이다.
  mockWithoutDemoBuild,

  /// 실서버를 부르는데 API 주소가 예시·로컬 주소다(`example.com` 계열 등).
  placeholderApiUrl,

  /// 실서버를 부르는데 API 주소가 `https://` 가 아니거나 읽을 수 없다.
  insecureApiUrl,
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

/// 기동 시 가드가 볼 문제 목록. 릴리스 모드가 아니면(`flutter run`·테스트) 늘
/// 비어 있다 — 로컬 개발은 기본값 그대로 돈다(#3022).
List<ReleaseProblem> releaseGuardProblems(
  AppConfig config, {
  bool releaseMode = kReleaseMode,
}) => releaseMode ? config.releaseProblems() : const <ReleaseProblem>[];

/// App-wide configuration resolved from `--dart-define`s at build time.
///
/// Mirrors the user app (`frontend/flutter`) so both On-Care apps share
/// the same networking contract. 운영 웹 빌드(`aws-frontend-deploy.yml`)는
/// `USE_MOCK_API=false`·`API_BASE_URL`(저장소 변수)·`ENV=prod` 를 넘겨 실서버를
/// 본다. GitHub Pages 데모 빌드(`deploy.yml`)는 기본으로 `USE_MOCK_API=true` 를
/// 넘겨 브라우저 drift 시드를 읽는다(#2810).
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.useMockApi,
    this.showDemoEntry = false,
    this.sentryDsn,
    this.demoBuild = false,
  });

  final Environment environment;

  /// Base URL of the FastAPI backend, including the `/v1` prefix.
  final String apiBaseUrl;

  /// When true, feature providers resolve to the in-memory / drift mock
  /// repositories instead of the Dio-backed ones. Used for the demo
  /// bypass and while running without a backend.
  final bool useMockApi;

  /// 로그인 화면에 "로그인 없이 데모 둘러보기" 진입을 노출할지. (#1526)
  ///
  /// 기본은 꺼짐 — 로그인 없이 콘솔로 들어가는 경로를 화면에서 내렸다. 진입
  /// 코드와 문구는 그대로 살려 두고 노출만 막는다. 주석 처리 대신 플래그인
  /// 이유: 죽은 코드는 주변이 바뀌면 그대로 되살아나지 않지만, 플래그는 경로가
  /// 살아 있어 테스트가 계속 지켜 준다. 사용자 앱과 같은 이름·같은 기본값이다.
  ///
  /// 다시 열 때: `--dart-define=SHOW_DEMO_ENTRY=true`
  final bool showDemoEntry;

  /// 에러 추적(Sentry) 수신 주소. 비어 있으면 보내지 않는다 (#2839).
  ///
  /// 배포 빌드가 `--dart-define=SENTRY_DSN=...` 으로 넣는다. 데모(목업)·개발
  /// 환경에서는 값이 있어도 보내지 않는다 — `shouldReportErrors` 참고.
  final String? sentryDsn;

  bool get isProd => environment == Environment.prod;

  bool get isDev => environment == Environment.dev;

  /// 데모 배포(GitHub Pages) 빌드 표시 — `--dart-define=DEMO_BUILD=true` (#3022).
  ///
  /// 릴리스 빌드에서 목업을 허용하는 유일한 근거다. 데모 배포 워크플로(`deploy.yml`)만
  /// 넘기고, 운영 웹 빌드는 넘기지 않는다. 회원 앱과 같은 이름·같은 기본값이다.
  final bool demoBuild;

  /// 실 네트워크로 나가는 요청이 있는가.
  bool get usesNetwork => !useMockApi;

  /// 이 설정을 릴리스로 내보내면 생기는 문제들. 비어 있으면 내보내도 된다(#3022).
  ///
  /// 순수 함수다 — 빌드 모드는 보지 않는다. 기동 가드는 [releaseGuardProblems] 로
  /// 릴리스 모드일 때만 이 목록을 쓴다. 판정 기준은 회원 앱과 같다.
  ///
  /// * 데모 빌드(`DEMO_BUILD=true` + 목업)는 `ENV=dev` 여도 된다.
  /// * 주소는 실서버 모드일 때만 본다. 목업 빌드는 주소를 넘기지 않는다.
  List<ReleaseProblem> releaseProblems() {
    final bool demoMock = useMockApi && demoBuild;
    return <ReleaseProblem>[
      if (isDev && !demoMock) ReleaseProblem.devEnvironment,
      if (useMockApi && !demoBuild) ReleaseProblem.mockWithoutDemoBuild,
      if (usesNetwork) ...apiBaseUrlProblems(apiBaseUrl),
    ];
  }

  factory AppConfig.fromEnvironment() {
    const envStr = String.fromEnvironment('ENV', defaultValue: 'dev');
    final env = switch (envStr) {
      'prod' => Environment.prod,
      'staging' => Environment.staging,
      _ => Environment.dev,
    };
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://dev.api.oncare.example.com/v1',
    );
    // Default to mock so `flutter run`/tests work with no backend; the
    // real web build opts in with USE_MOCK_API=false.
    const useMockApi = bool.fromEnvironment('USE_MOCK_API', defaultValue: true);
    const showDemoEntry = bool.fromEnvironment('SHOW_DEMO_ENTRY');
    const sentryDsn = String.fromEnvironment('SENTRY_DSN');
    // 데모 Pages 빌드만 넘긴다(#3022). 릴리스 가드가 목업을 허용하는 근거다.
    const demoBuild = bool.fromEnvironment('DEMO_BUILD');
    return AppConfig(
      environment: env,
      apiBaseUrl: apiBaseUrl,
      useMockApi: useMockApi,
      // 기본값과 같은 값이어도 그대로 흘려보낸다 — SHOW_DEMO_ENTRY 를 주면
      // 여기서 값이 갈린다.
      // ignore: avoid_redundant_argument_values
      showDemoEntry: showDemoEntry,
      sentryDsn: sentryDsn.isEmpty ? null : sentryDsn,
      // ignore: avoid_redundant_argument_values
      demoBuild: demoBuild,
    );
  }
}

/// Overridden in [ProviderScope] at startup (see `bootstrap()`), resolved
/// from [AppConfig.fromEnvironment]. Reading it before the override throws.
final appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError(
    'appConfigProvider must be overridden in bootstrap() before use.',
  );
}, name: 'appConfig');
