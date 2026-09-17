import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/core/storage/secure_token_store.dart';

enum SessionStatus { unknown, signedOut, demo, authenticated }

class SessionState {
  const SessionState({
    this.status = SessionStatus.unknown,
    this.restoreFailed = false,
  });
  final SessionStatus status;

  /// 저장된 세션을 되살리려다 **일시적인 이유로** 끝내지 못했다. (#1944)
  ///
  /// 오프라인·500·타임아웃이 여기 해당한다. 토큰은 그대로 남아 있으므로 세션이
  /// 끝난 것이 아니고, 그래서 로그인 화면으로 보내지 않는다 — 전에는 아무
  /// 안내 없이 로그인 폼에 세워, 멀쩡한 세션을 두고 재시도할 방법이 "다음
  /// 실행" 뿐이었다. 상태가 [SessionStatus.unknown] 에 머무는 동안 시작 화면이
  /// 다시 시도를 준다.
  final bool restoreFailed;

  bool get isAuthenticated => status == SessionStatus.authenticated;
  bool get canEnterApp =>
      status == SessionStatus.authenticated || status == SessionStatus.demo;
}

/// 계정은 만들어졌는데 이어지는 로그인만 실패했다. (#1926)
///
/// 가입 실패와 갈라 두는 이유는 회원이 다음에 할 일이 다르기 때문이다 — 다시
/// 가입하는 것이 아니라 로그인하면 된다.
class AccountCreatedSignInFailed implements Exception {
  const AccountCreatedSignInFailed(this.cause);

  /// 로그인을 막은 원인(타임아웃·429·서버 오류 등).
  final Object cause;

  @override
  String toString() => 'AccountCreatedSignInFailed($cause)';
}

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._ref) : super(const SessionState()) {
    _restore();
  }

  final Ref _ref;

  /// 사용자가 시작한 흐름(로그인·가입·데모·로그아웃)이 시작됐는가.
  ///
  /// 복구는 네트워크 왕복을 포함해 느리다. 그 사이 사용자가 로그인 버튼을 누르면,
  /// 뒤늦게 끝난 복구가 그 결과를 덮어써 방금 로그인한 세션이 사라진다. 사용자 행동이
  /// 항상 이긴다.
  ///
  /// **한 번 켜지면 유지된다** — 로그인이 실패로 끝나도 되돌리지 않는다. 세션의 주도권이
  /// 사용자에게 넘어갔다는 뜻이라, 실패 뒤에 뒤늦은 복구가 전 계정으로 들여보내면 오히려
  /// 놀랍다. 복구는 생성자에서 한 번만 도므로 지금은 그 뒤에 기다리는 것이 없지만,
  /// 나중에 "다시 시도" 같은 복구 경로를 만든다면 이 플래그를 함께 손봐야 한다 —
  /// 그러지 않으면 그 복구가 조용히 무시된다(리뷰).
  bool _userActionStarted = false;

  void _setToken(String? token) {
    _ref.read(authAccessTokenProvider.notifier).state = token;
  }

  void _resetFeatureState() {
    _ref.read(sessionFeatureResetProvider)();
  }

  /// 저장된 토큰으로 세션을 되살린다.
  ///
  /// 토큰이 있다는 것만으로 인증 상태로 넘어가지 않는다. 접근 토큰 수명은 하루라,
  /// 존재만 보고 통과시키면 다음 날 앱을 켰을 때 **로그인된 화면이 뜨지만 모든 요청이
  /// 실패하고** 수동 로그아웃 말고는 빠져나갈 길이 없었다. 유효한지 확인하고, 만료면
  /// 갱신 토큰으로 한 번 회전한다.
  Future<void> _restore() async {
    // 두 토큰을 따로 읽는다 — 갱신 토큰 읽기가 실패했다고 멀쩡히 읽힌 접근 토큰까지
    // 버릴 이유가 없다.
    String? access;
    String? refresh;
    try {
      access = await _ref.read(secureTokenStoreProvider).readAccessToken();
    } catch (_) {
      access = null; // secure storage unavailable → treat as signed out
    }
    try {
      refresh = await _ref.read(secureTokenStoreProvider).readRefreshToken();
    } catch (_) {
      refresh = null; // 갱신은 못 해도 접근 토큰만으로 복구를 시도할 수 있다.
    }
    if (!mounted || _userActionStarted) return;
    if (access == null || access.isEmpty) {
      state = const SessionState(status: SessionStatus.signedOut);
      return;
    }
    await _resolveSession(
      access: access,
      refresh: refresh ?? '',
      allowRefresh: true,
    );
  }

  /// [access] 로 프로필을 조회해 세션을 확정한다. 인증 실패면 [refresh] 로 한 번
  /// 회전한다.
  ///
  /// 일시적 실패(네트워크·서버)는 **토큰을 지우지 않고** 로그아웃 상태로만 둔다.
  /// 지하철에서 앱을 켰다고 저장된 세션을 잃으면 안 된다.
  Future<void> _resolveSession({
    required String access,
    required String refresh,
    required bool allowRefresh,
  }) async {
    if (_userActionStarted) return;
    try {
      // 아직 세션에 넣지 않은 토큰으로 찔러 본다. 유효한지 모르는 토큰을 먼저
      // 세션에 넣으면 그 사이 앱이 만료된 토큰으로 로그인 상태가 된다.
      await _ref.read(dioProvider).get<Map<String, Object?>>(
        '/users/me',
        options: Options(
          headers: <String, Object?>{'Authorization': 'Bearer $access'},
        ),
      );
      if (!mounted || _userActionStarted) return;
      _setToken(access);
      state = const SessionState(status: SessionStatus.authenticated);
    } on DioException catch (e) {
      if (!mounted || _userActionStarted) return;
      final int? code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        if (allowRefresh && refresh.isNotEmpty) {
          await _refreshAndResolve(refresh);
        } else {
          await _expire();
        }
        return;
      }
      // 그 밖의 응답·연결 실패는 일시적으로 본다. 토큰은 남겨 둔다.
      _keepTokensAndSignOut();
    } catch (_) {
      if (!mounted || _userActionStarted) return;
      _keepTokensAndSignOut();
    }
  }

  /// 갱신 토큰으로 접근 토큰을 회전하고 다시 확정한다.
  Future<void> _refreshAndResolve(String refresh) async {
    if (_userActionStarted) return;
    final Map<String, Object?>? data;
    try {
      final res = await _ref.read(dioProvider).post<Map<String, Object?>>(
        '/auth/refresh',
        data: <String, Object?>{'refresh_token': refresh},
      );
      data = res.data;
    } on DioException catch (e) {
      // 회전이 실패했다 — 다만 느린 호출 중에 사용자가 로그인·데모를 시작했을 수
      // 있으니 그 결과를 덮지 않는다.
      if (!mounted || _userActionStarted) return;
      // 확인 요청과 같은 기준을 쓴다: **명시적인 401/403 만 세션의 끝이다.**
      // 갱신이 연결 실패나 서버 오류로 끝난 것을 만료로 처리하면, 잠깐 네트워크가
      // 끊긴 사용자에게 재로그인을 요구하게 된다(리뷰).
      final int? code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        await _expire();
      } else {
        _keepTokensAndSignOut();
      }
      return;
    } catch (_) {
      if (!mounted || _userActionStarted) return;
      _keepTokensAndSignOut();
      return;
    }
    if (!mounted || _userActionStarted) return;

    final String access = (data?['access_token'] as String?) ?? '';
    if (access.isEmpty) {
      // 200 인데 토큰이 없다 — 서버 계약이 깨진 것이지 세션이 끝난 것이 아니다.
      // 토큰을 남겨 두면 다음 실행에서 다시 시도할 수 있다.
      _keepTokensAndSignOut();
      return;
    }
    // 갱신 토큰을 새로 주지 않는 서버도 있다. 그때는 쓰던 것을 유지해야 다음 만료
    // 때도 되살릴 수 있다.
    final String rotated = (data?['refresh_token'] as String?) ?? '';
    final String nextRefresh = rotated.isEmpty ? refresh : rotated;
    try {
      await _ref
          .read(secureTokenStoreProvider)
          .saveTokens(access: access, refresh: nextRefresh);
    } catch (_) {
      // 저장에 실패해도 이번 세션은 메모리 토큰으로 진행한다.
    }
    if (!mounted || _userActionStarted) return;
    // 방금 회전한 토큰마저 거부되면 더 시도하지 않는다.
    await _resolveSession(
      access: access,
      refresh: nextRefresh,
      allowRefresh: false,
    );
  }

  /// 이번에는 못 들어갔지만 세션이 끝난 것은 아니다 — 저장된 토큰을 남긴 채
  /// 시작 화면에 재시도를 띄운다. (#1944)
  ///
  /// 예전에는 곧장 로그아웃 상태로 두어 로그인 폼이 떴다. 저장된 세션은 멀쩡한데
  /// 화면은 그 사실을 말하지 않았고, 다시 시도할 길은 앱을 껐다 켜는 것뿐이었다.
  void _keepTokensAndSignOut() {
    _setToken(null);
    // 상태는 `unknown` 그대로다 — 세션이 끝난 것이 아니라 아직 모른다.
    state = const SessionState(restoreFailed: true);
  }

  /// 실패한 복구를 다시 시도한다. 시작 화면의 `다시 시도` 가 부른다. (#1944)
  Future<void> retryRestore() async {
    if (_userActionStarted) return;
    // 다시 `unknown` 으로 두면 시작 화면이 기다리는 모양으로 돌아간다.
    state = const SessionState();
    await _restore();
  }

  /// 복구를 접고 로그인 화면으로 간다. 시작 화면의 탈출구다. (#1944)
  ///
  /// 저장된 토큰은 지우지 않는다 — 망이 돌아온 다음 실행에서 다시 되살아나야
  /// 한다. 이번 실행에서만 복구를 멈춘다.
  void dismissRestore() {
    _userActionStarted = true;
    _setToken(null);
    state = const SessionState(status: SessionStatus.signedOut);
  }

  /// 세션이 정말 끝났다 — 저장된 토큰을 지우고 로그인 화면으로 보낸다.
  Future<void> _expire() async {
    // **지우기 전에** 사용자 행동을 확인한다. 느린 복구 중에 로그인이 끝났다면
    // 저장소에는 방금 받은 토큰이 들어 있다. 뒤늦게 도착한 만료가 그것을 지우면
    // 화면은 로그인 상태인데 저장소만 비어, 다음 실행에서 로그아웃된다(리뷰).
    if (!mounted || _userActionStarted) return;
    try {
      await _ref.read(secureTokenStoreProvider).clear();
    } catch (_) {}
    if (!mounted || _userActionStarted) return;
    _setToken(null);
    state = const SessionState(status: SessionStatus.signedOut);
  }

  /// Persist tokens from an auth response and flip to authenticated.
  /// Shared by [login] and [socialLogin]. Throws if no access token.
  Future<void> _applyTokens(
    Map<String, Object?>? data, {
    required String label,
  }) async {
    final access = (data?['access_token'] as String?) ?? '';
    final refresh = (data?['refresh_token'] as String?) ?? '';
    if (access.isEmpty) throw Exception('$label 응답에 토큰이 없습니다.');
    try {
      await _ref
          .read(secureTokenStoreProvider)
          .saveTokens(access: access, refresh: refresh);
    } catch (_) {
      // secure storage 저장 실패해도 세션 메모리 토큰으로 진행
    }
    _setToken(access);
    _resetFeatureState();
    state = const SessionState(status: SessionStatus.authenticated);
  }

  /// Email/password login → POST /auth/login (OAuth2 form). Throws on failure.
  Future<void> login({required String email, required String password}) async {
    _userActionStarted = true;
    final dio = _ref.read(dioProvider);
    final res = await dio.post<Map<String, Object?>>(
      '/auth/login',
      data: <String, Object?>{'username': email, 'password': password},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    await _applyTokens(res.data, label: '로그인');
  }

  /// Social login — exchanges a provider (kakao/google) token for our
  /// session via POST /auth/social/{provider}. Throws on failure.
  Future<void> socialLogin({
    required String provider,
    required String token,
  }) async {
    _userActionStarted = true;
    final dio = _ref.read(dioProvider);
    final res = await dio.post<Map<String, Object?>>(
      '/auth/social/$provider',
      data: <String, Object?>{'token': token},
    );
    await _applyTokens(res.data, label: '소셜 로그인');
  }

  /// Register a new account → POST /auth/register (returns the created
  /// user, not a token), then log in with the same credentials so the
  /// user lands authenticated. Throws on failure (e.g. 409 duplicate).
  ///
  /// [phone] 은 가입 시점에 프로필을 채우기 위해 함께 보낸다 (#1634). 예전에는
  /// MY 탭 프로필 편집에서만 넣을 수 있어 가입 직후에는 연락처가 비어 있었다.
  /// 비워 보내도 계정은 만들어지고, 회원이 MY 탭에서 언제든 넣을 수 있다.
  Future<void> register({
    required String email,
    required String password,
    String name = '',
    String phone = '',
  }) async {
    _userActionStarted = true;
    final dio = _ref.read(dioProvider);
    await dio.post<Map<String, Object?>>(
      '/auth/register',
      data: <String, Object?>{
        'email': email,
        'password': password,
        'name': name,
        'phone': phone,
      },
    );
    // 여기부터는 **계정이 이미 만들어진 뒤**다. 로그인만 실패한 것을 가입 실패로
    // 알리면, 회원은 다시 가입을 눌러 "이미 사용 중인 이메일" 을 보게 된다 —
    // 방금 실패했다던 계정이 있다는 뜻이라 무엇이 맞는지 알 수 없다(#1926).
    try {
      await login(email: email, password: password);
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(AccountCreatedSignInFailed(error), stack);
    }
  }

  /// Skip auth — demo mode. No token; the backend demo-fallback serves data.
  void enterDemo() {
    _userActionStarted = true;
    _setToken(null);
    _resetFeatureState();
    state = const SessionState(status: SessionStatus.demo);
  }

  Future<void> signOut() async {
    _userActionStarted = true;
    // 저장소를 지우기 **전에** 서버에 알린다 — 지운 뒤에는 폐기할 토큰이 없다.
    await _revokeSession();
    try {
      await _ref.read(secureTokenStoreProvider).clear();
    } catch (_) {}
    _setToken(null);
    _resetFeatureState();
    state = const SessionState(status: SessionStatus.signedOut);
  }

  /// 저장된 갱신 토큰을 서버에서 폐기한다(`POST /auth/logout`).
  ///
  /// 지금까지 로그아웃은 이 기기의 저장소를 비우는 일이었다. 토큰 자체는 만료까지
  /// 살아 있어서, 어딘가로 새어 나갔다면 로그아웃을 눌러도 그 세션은 그대로였다(#966).
  ///
  /// **어떤 실패도 로그아웃을 막지 않는다.** 사용자가 이미 결정한 일이고, 네트워크가
  /// 끊겼다고 로그인 화면으로 못 나가는 쪽이 더 나쁘다. 기본 타임아웃(연결 10초)을
  /// 그대로 기다리면 나가는 데 그만큼 걸리므로 짧게 끊는다 — 서버가 못 받은 폐기는
  /// 그 토큰의 만료까지 남지만, 이 기기에서는 어차피 지워진다.
  Future<void> _revokeSession() async {
    String? refresh;
    try {
      refresh = await _ref.read(secureTokenStoreProvider).readRefreshToken();
    } catch (_) {
      return;
    }
    // 데모 세션에는 토큰이 없다 — 부를 것도 없다.
    if (refresh == null || refresh.isEmpty) return;
    try {
      await _ref
          .read(dioProvider)
          .post<void>(
            '/auth/logout',
            data: <String, Object?>{'refresh_token': refresh},
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // 무시한다 — 위 주석 참고.
    }
  }
}

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>(
      (ref) => SessionController(ref),
      name: 'session',
    );
