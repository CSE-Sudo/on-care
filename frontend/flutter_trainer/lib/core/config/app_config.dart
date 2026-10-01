import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Deployment environment. Selected at build time via `--dart-define=ENV`.
enum Environment { dev, staging, prod }

/// App-wide configuration resolved from `--dart-define`s at build time.
///
/// Mirrors the user app (`frontend/flutter`) so both On-Care apps share
/// the same networking contract. The GitHub Pages demo builds with the
/// default `USE_MOCK_API=true` and reads the browser-local drift seed; a
/// build that should hit the real backend passes `API_BASE_URL` +
/// `USE_MOCK_API=false`.
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.useMockApi,
    this.showDemoEntry = false,
    this.sentryDsn,
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
    return AppConfig(
      environment: env,
      apiBaseUrl: apiBaseUrl,
      useMockApi: useMockApi,
      // 기본값과 같은 값이어도 그대로 흘려보낸다 — SHOW_DEMO_ENTRY 를 주면
      // 여기서 값이 갈린다.
      // ignore: avoid_redundant_argument_values
      showDemoEntry: showDemoEntry,
      sentryDsn: sentryDsn.isEmpty ? null : sentryDsn,
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
