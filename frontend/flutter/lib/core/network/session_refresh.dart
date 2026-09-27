import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 만료된 접근 토큰을 갈아 끼우려 한 결과의 종류. (#1546)
enum TokenRefreshStatus {
  /// 새 접근 토큰을 받았다 — 원 요청을 그 토큰으로 다시 보낸다.
  refreshed,

  /// 서버가 갱신을 거부했다 — 세션이 끝났고 이미 로그인 화면으로 보냈다.
  rejected,

  /// 이번에는 갱신하지 못했다(연결 실패·서버 오류·세션이 이미 바뀜).
  /// 토큰은 그대로 두고 원래 오류를 호출부에 돌려준다.
  unavailable,
}

/// 만료된 접근 토큰을 갈아 끼우려 한 결과.
class TokenRefreshResult {
  /// 새 접근 토큰 [accessToken] 을 받았다.
  const TokenRefreshResult.refreshed(String this.accessToken)
    : status = TokenRefreshStatus.refreshed;

  /// 서버가 갱신을 거부해 세션을 끝냈다.
  const TokenRefreshResult.rejected()
    : status = TokenRefreshStatus.rejected,
      accessToken = null;

  /// 이번에는 갱신하지 못했다. 세션은 그대로다.
  const TokenRefreshResult.unavailable()
    : status = TokenRefreshStatus.unavailable,
      accessToken = null;

  /// 결과의 종류.
  final TokenRefreshStatus status;

  /// [TokenRefreshStatus.refreshed] 일 때만 새 접근 토큰.
  final String? accessToken;
}

/// 세션을 가진 쪽(세션 컨트롤러)이 구현하는 토큰 갱신.
///
/// 네트워크 계층이 인증 기능을 직접 가져오면 `dio_client ↔ session_controller`
/// 가 서로를 가져오게 된다. 그래서 이 잎(leaf) 인터페이스만 두고, 컨트롤러가
/// 만들어질 때 [SessionRefreshBridge] 에 자신을 붙인다.
abstract interface class SessionTokenRefresher {
  /// [staleToken] 이 401 로 거부되었다. 갱신 토큰으로 한 번 회전한다.
  ///
  /// 갱신이 401/403 으로 거부되면 세션을 끝내고(로그인 화면으로)
  /// [TokenRefreshStatus.rejected] 를 준다. 연결 실패·5xx 는 토큰을 지우지
  /// 않고 [TokenRefreshStatus.unavailable] 을 준다.
  Future<TokenRefreshResult> refreshAfterUnauthorized(String staleToken);
}

/// 인증 인터셉터와 세션 컨트롤러를 잇고, 갱신을 **한 번에 하나만** 돌린다.
///
/// 갱신 토큰은 일회용이다 — 서버는 한 번 회전에 쓴 토큰이 다시 오면 탈취로 보고
/// 거부한다. 화면 하나가 여러 요청을 동시에 보내 모두 401 을 받으면, 각자
/// 갱신하는 순간 두 번째부터는 거부되어 멀쩡한 세션이 끝난다. 그래서 진행 중인
/// 갱신이 있으면 새로 시작하지 않고 그 결과를 함께 기다린다.
class SessionRefreshBridge {
  SessionTokenRefresher? _refresher;
  Future<TokenRefreshResult>? _inFlight;

  /// 세션 컨트롤러를 붙인다.
  void attach(SessionTokenRefresher refresher) => _refresher = refresher;

  /// [refresher] 가 지금 붙어 있는 것일 때만 뗀다.
  void detach(SessionTokenRefresher refresher) {
    if (identical(_refresher, refresher)) _refresher = null;
  }

  /// 갱신이 진행 중인가.
  bool get isRefreshing => _inFlight != null;

  /// [staleToken] 이 거부된 뒤의 갱신. 진행 중인 갱신이 있으면 그것을 함께 기다린다.
  Future<TokenRefreshResult> refresh(String staleToken) {
    final Future<TokenRefreshResult>? running = _inFlight;
    if (running != null) return running;
    final SessionTokenRefresher? refresher = _refresher;
    if (refresher == null) {
      return Future<TokenRefreshResult>.value(
        const TokenRefreshResult.unavailable(),
      );
    }
    final Future<TokenRefreshResult> run = _run(refresher, staleToken);
    _inFlight = run;
    run.whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
    return run;
  }

  static Future<TokenRefreshResult> _run(
    SessionTokenRefresher refresher,
    String staleToken,
  ) async {
    try {
      return await refresher.refreshAfterUnauthorized(staleToken);
    } catch (_) {
      // 갱신 중의 예기치 못한 실패는 세션의 끝이 아니다.
      return const TokenRefreshResult.unavailable();
    }
  }
}

/// 앱 전체가 함께 쓰는 [SessionRefreshBridge].
final sessionRefreshBridgeProvider = Provider<SessionRefreshBridge>(
  (ref) => SessionRefreshBridge(),
  name: 'sessionRefreshBridge',
);
