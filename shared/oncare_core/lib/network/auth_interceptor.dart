import 'package:dio/dio.dart';

import 'package:oncare_core/network/session_refresh.dart';

/// Attaches `Authorization: Bearer <token>` to outgoing requests when a
/// session token is present **and the caller has not already set one**.
/// 회원 앱의 목업 모드에서는 LocalApiInterceptor 가 이보다 먼저 요청을 끝내므로,
/// 토큰은 실서버(FastAPI)를 상대할 때만 의미가 있다.
///
/// 회원 앱과 트레이너 웹이 이 인터셉터 하나를 함께 쓴다(#2907). 토큰과 갱신
/// 브리지는 각 앱의 provider 에 있으므로 읽는 함수로 받는다 — 두 앱의 조립은
/// 각 앱 `core/network/auth_token.dart` 의 `authInterceptorFor` 에 있다.
///
/// 호출부가 이미 넣은 헤더를 덮지 않는 이유: 세션 복구는 아직 세션에 반영하지 않은
/// 토큰으로 내 정보(회원 `GET /users/me`, 트레이너 `GET /trainer/me`)를 찔러 본다.
/// 그 토큰이 유효한지 확인하기 전에 세션에 넣어 버리면, 만료된 토큰으로 앱이 잠시
/// 로그인 상태가 된다.
///
/// ## 실행 중 만료 (#1546)
///
/// 접근 토큰은 하루면 만료된다. 앱·콘솔을 켜 둔 채 그 시간을 넘기면 화면은 로그인
/// 상태인데 모든 조회·저장이 401 로 실패했다 — 갱신은 앱 시작 복구에만 있었다.
/// 이제 **이 인터셉터가 붙인 세션 토큰**으로 나간 요청이 401 을 받으면:
///
///  * [SessionRefreshBridge] 로 갱신 토큰을 한 번 회전하고(동시에 여러 건이
///    401 이어도 회전은 한 번), 새 토큰으로 원 요청을 **한 번만** 다시 보낸다.
///  * 그 사이 다른 요청이 이미 회전했다면 회전 없이 지금 토큰으로 다시 보낸다.
///  * 회전이 거부되면 세션 컨트롤러가 세션을 끝낸다(로그인 화면). 원 오류는
///    그대로 호출부에 간다.
///  * 연결 실패·5xx 로 회전하지 못하면 토큰을 지우지 않고 원 오류를 돌려준다.
///
/// 호출부가 직접 헤더를 넣은 요청(복구의 확인 요청 등)과 `/auth/*` 요청(로그인·
/// 갱신·로그아웃 — 토큰이 필요 없는 경로)은 손대지 않는다. 다시 보낸 요청이 또
/// 401 이어도 더 시도하지 않는다.
///
/// 순서: 트레이너 웹에서는 이 인터셉터가 담당 해제 감지(`ClientAccessInterceptor`)
/// 앞에 있다. 다시 보낸 요청은 사슬을 처음부터 다시 지나므로 그 404 는 거기서
/// 한 번만 보고된다.
class AuthInterceptor extends Interceptor {
  /// [retryClient] 가 없으면 헤더만 붙인다.
  ///
  /// [accessToken] 과 [refreshBridge] 는 쓸 때마다 부른다 — 로그인·로그아웃·갱신이
  /// 토큰을 바꿔도 인터셉터를 다시 만들지 않는다.
  AuthInterceptor({
    required this.accessToken,
    required this.refreshBridge,
    this.retryClient,
  });

  /// 지금 세션의 접근 토큰. 없으면 null.
  final String? Function() accessToken;

  /// 갱신을 한 번에 하나만 돌리는 앱 전체의 브리지.
  final SessionRefreshBridge Function() refreshBridge;

  /// 만료 뒤 원 요청을 다시 보낼 Dio. 보통 이 인터셉터가 붙은 그 Dio 다.
  final Dio? retryClient;

  /// 이 인터셉터가 요청에 붙인 세션 토큰. 401 이 **그 토큰**에 대한 것인지 가린다.
  static const String sessionTokenExtra = 'auth_session_token';

  /// 만료 뒤 한 번 다시 보낸 요청 표시 — 두 번째 401 에서 멈추게 한다.
  static const String retriedExtra = 'auth_retried';

  /// 토큰 발급·폐기 경로(`/auth/login`, `/auth/refresh`, `/auth/logout` …)인가.
  ///
  /// 이 경로들은 접근 토큰을 요구하지 않는다. 여기서 받은 401 은 자격이 틀렸다는
  /// 뜻이지 토큰이 만료됐다는 뜻이 아니고, 갱신 요청이 401 로 다시 갱신을 부르면
  /// 끝나지 않는다.
  static bool isAuthEndpoint(RequestOptions options) =>
      options.uri.pathSegments.contains('auth');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.headers.containsKey('Authorization')) {
      final String? token = accessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
        options.extra[sessionTokenExtra] = token;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions request = err.requestOptions;
    final Object? sent = request.extra[sessionTokenExtra];
    final Dio? client = retryClient;
    if (client == null ||
        err.response?.statusCode != 401 ||
        sent is! String ||
        request.extra[retriedExtra] == true ||
        isAuthEndpoint(request) ||
        request.data is Stream) {
      handler.next(err);
      return;
    }

    String? token = accessToken();
    // 그 사이 로그아웃했거나 세션이 끝났다 — 다시 보낼 토큰이 없다.
    if (token == null || token.isEmpty) {
      handler.next(err);
      return;
    }
    if (token == sent) {
      final TokenRefreshResult result = await refreshBridge().refresh(sent);
      final String? refreshed = result.accessToken;
      if (result.status != TokenRefreshStatus.refreshed || refreshed == null) {
        handler.next(err);
        return;
      }
      token = refreshed;
    }

    final Object? data = request.data;
    final RequestOptions retry = request.copyWith(
      headers: <String, dynamic>{
        ...request.headers,
        'Authorization': 'Bearer $token',
      },
      extra: <String, dynamic>{
        ...request.extra,
        sessionTokenExtra: token,
        retriedExtra: true,
      },
      // multipart 본문은 한 번만 읽힌다 — 다시 보낼 때는 복제본을 싣는다.
      data: data is FormData ? data.clone() : data,
    );
    try {
      handler.resolve(await client.fetch<Object?>(retry));
    } on DioException catch (e) {
      // 다시 보낸 요청은 이미 인터셉터 사슬을 한 번 다 지났다. 뒤따르는
      // 인터셉터에게 같은 실패를 두 번 알리지 않는다.
      handler.reject(e);
    }
  }
}
