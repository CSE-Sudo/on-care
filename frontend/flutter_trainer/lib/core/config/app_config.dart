import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Deployment environment. Selected at build time via `--dart-define=ENV`.
enum Environment { dev, staging, prod }

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

  bool get isProd => environment == Environment.prod;

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
    return AppConfig(
      environment: env,
      apiBaseUrl: apiBaseUrl,
      useMockApi: useMockApi,
      // 기본값과 같은 값이어도 그대로 흘려보낸다 — SHOW_DEMO_ENTRY 를 주면
      // 여기서 값이 갈린다.
      // ignore: avoid_redundant_argument_values
      showDemoEntry: showDemoEntry,
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
