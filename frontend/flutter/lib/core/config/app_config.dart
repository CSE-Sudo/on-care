import 'package:flutter_riverpod/flutter_riverpod.dart';

enum Environment { dev, staging, prod }

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
    required this.useMockApi,
    this.sentryDsn,
    this.realApiFeatures = const <String>{},
    this.showDemoEntry = false,
  });

  final Environment environment;
  final String apiBaseUrl;
  final String? sentryDsn;

  /// When true, [MockApiInterceptor] short-circuits any HTTP request
  /// matching a known path and returns canned data. Used while the
  /// real REST backend (Q1 decision) is being built.
  final bool useMockApi;

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

  /// 로그인 화면의 카카오·구글 버튼을 쓸 수 있는가. (#1553)
  ///
  /// 실 OAuth SDK 를 붙이기 전이라 버튼은 고정 `demo-<provider>-token` 을 보낸다.
  /// 그 토큰을 받아 주는 것은 기기 안의 목업 인터셉터뿐이므로, 소셜 교환 요청이
  /// **목업에서 끝나는 설정에서만** 연다. 요청이 실서버로 나가는 설정 —
  /// `USE_MOCK_API=false`, `REAL_API=auth`, `ENV=prod` — 에서는 닫는다. 운영
  /// 서버는 고정 토큰을 거절해 죽은 버튼이 되고, 검증이 느슨해지면 누르는 사람
  /// 모두가 같은 계정을 나눠 쓰게 된다.
  ///
  /// 실 OAuth 를 붙이면 이 게이트 대신 provider SDK 가 받은 토큰을 보낸다.
  bool get socialDemoLoginEnabled =>
      useMockApi && !isProd && !isRealApi('POST', '/auth/social');

  /// 로그인 화면에 "로그인 없이 데모 둘러보기" 진입을 노출할지. (#1526)
  ///
  /// 기본은 꺼짐 — 로그인 없이 앱 안으로 들어가는 경로를 화면에서 내렸다. 코드와
  /// 문구·`SessionController.enterDemo` 는 그대로 살려 두고 노출만 막는다.
  /// 주석 처리 대신 플래그인 이유: 죽은 코드는 주변이 바뀌면 그대로 되살아나지
  /// 않지만, 플래그는 경로가 살아 있어 테스트가 계속 지켜 준다.
  ///
  /// 다시 열 때: `--dart-define=SHOW_DEMO_ENTRY=true`
  final bool showDemoEntry;

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
      defaultValue: 'https://dev.api.oncare.example.com',
    );
    const sentryDsn = String.fromEnvironment('SENTRY_DSN');
    const useMockApi = bool.fromEnvironment('USE_MOCK_API', defaultValue: true);
    // 예: --dart-define=REAL_API=ai-coach,auth
    // 알 수 없는 키는 무시된다(오타가 조용히 전 기능을 실서버로 보내지 않도록,
    // 매칭되는 경로가 없으면 아무 일도 일어나지 않는다).
    const realApi = String.fromEnvironment('REAL_API');
    const showDemoEntry = bool.fromEnvironment('SHOW_DEMO_ENTRY');
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
