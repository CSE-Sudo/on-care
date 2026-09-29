import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/auth_token.dart';
import 'package:oncare_trainer/core/network/session_refresh.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/secure_token_store.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// Owns the trainer session lifecycle: restore-on-launch (with token
/// refresh), login / register / social login, demo bypass, and sign-out.
///
/// Real credentials now: login exchanges email/password for JWT tokens,
/// the profile comes from `GET /v1/trainer/me`, and a non-trainer account
/// is rejected (the trainer and member apps use separate accounts). In
/// `USE_MOCK_API=true` / demo mode the same flow runs against the
/// in-memory mock repository.
class SessionController extends StateNotifier<SessionState>
    implements SessionTokenRefresher {
  SessionController(this._ref) : super(const SessionState()) {
    // 첫 값(복구 전 unknown)은 기준으로만 삼는다 — provider 를 만드는 도중에
    // 다른 provider 를 고치면 Riverpod 이 막는다.
    addListener(_syncAccountScope, fireImmediately: false);
    // 실행 중 401 을 받은 인터셉터가 이 컨트롤러로 토큰을 회전한다(#1546).
    _refreshBridge = _ref.read(sessionRefreshBridgeProvider)..attach(this);
    _restore();
  }

  final Ref _ref;
  late final SessionRefreshBridge _refreshBridge;

  @override
  void dispose() {
    _refreshBridge.detach(this);
    super.dispose();
  }

  /// 마지막으로 [accountScopeProvider] 에 반영한 계정 경계. (#2285)
  SessionStatus _scopeStatus = SessionStatus.unknown;
  String? _scopeEmail;

  /// 세션이 계정 경계를 넘으면 계정 범위 provider 를 전부 새로 만들게 한다.
  ///
  /// 경계는 상태(로그인·데모·로그아웃)가 바뀌거나 로그인한 계정의 이메일이 바뀔
  /// 때다. 로그아웃·토큰 만료·복구 실패가 모두 `signedOut` 으로 모이므로 어느
  /// 길로 세션이 끝나도 이전 계정의 캐시가 남지 않는다. 같은 계정 안의 프로필
  /// 편집([replaceProfile])은 경계가 아니다 — 거기서 올리면 MY 에서 이름만 고쳐도
  /// 회원 목록을 다시 읽는다.
  void _syncAccountScope(SessionState next) {
    // 데모는 계정이 없다 — 데모에서 프로필을 고쳐도 같은 데모 세션이다.
    final String? email = next.status == SessionStatus.authenticated
        ? next.profile?.email
        : null;
    if (next.status == _scopeStatus && email == _scopeEmail) return;
    _scopeStatus = next.status;
    _scopeEmail = email;
    _ref.read(accountSignedOutProvider.notifier).state =
        next.status == SessionStatus.signedOut;
    _ref.read(accountScopeProvider.notifier).state++;
  }

  /// Set once the user drives an explicit auth action (login / register /
  /// social / demo / sign-out). The launch-time [_restore] is async, so on
  /// a slow real-backend `/me` the login screen (shown during
  /// [SessionStatus.unknown]) is interactive while restore is still in
  /// flight — this flag stops a late-resolving restore from clobbering the
  /// state the user just chose.
  bool _userActionStarted = false;

  /// Secure-storage mutations must finish in invocation order. In particular,
  /// a sign-out that starts while a refresh token save is in flight must clear
  /// after that save, otherwise the stale refresh can resurrect credentials.
  Future<void> _tokenStorageTail = Future<void>.value();

  TrainerAuthRepository get _repo => _ref.read(trainerAuthRepositoryProvider);
  SecureTokenStore get _tokens => _ref.read(secureTokenStoreProvider);

  void _setAccessToken(String? token) {
    _ref.read(authAccessTokenProvider.notifier).state = token;
  }

  // --- restore ------------------------------------------------------------

  /// Resolves the initial session from persisted tokens. A valid token
  /// (optionally after a refresh) plus a trainer `/me` lands authenticated;
  /// anything else lands signed out. Demo mode is never persisted.
  Future<void> _restore() async {
    // Read the two tokens independently: a refresh-token read failure must
    // not discard an access token that read back fine (review).
    String? access;
    String? refresh;
    try {
      access = await _tokens.readAccessToken();
    } catch (_) {
      access = null; // secure storage unavailable → treat as signed out
    }
    try {
      refresh = await _tokens.readRefreshToken();
    } catch (_) {
      refresh = null; // no refresh available; access alone can still restore
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

  /// Attempts to authenticate with [access]; on 401 rotates once with
  /// [refresh]. Auth/role failures clear the session; transient failures
  /// (network/server) sign out without discarding the stored tokens so a
  /// later relaunch can retry.
  Future<void> _resolveSession({
    required String access,
    required String refresh,
    required bool allowRefresh,
  }) async {
    if (_userActionStarted) return;
    _setAccessToken(access);
    try {
      final profile = await _repo.fetchProfile(access);
      if (!mounted || _userActionStarted) return;
      state = SessionState(
        status: SessionStatus.authenticated,
        profile: profile,
      );
    } on NotTrainerException {
      if (_userActionStarted) return;
      await _expire();
    } on UnauthorizedError {
      if (_userActionStarted) return;
      if (allowRefresh && refresh.isNotEmpty) {
        await _refreshAndResolve(refresh);
      } else {
        await _expire();
      }
    } on AuthException catch (e) {
      if (_userActionStarted) return;
      // 인증 계열 실패라도 **명시적으로 거부된 것만** 세션의 끝이다. 같은 예외로
      // 실려 오는 연결 실패·서버 오류를 만료로 처리하면, 잠깐 끊긴 사용자에게
      // 재로그인을 요구하게 된다.
      if (_endsSession(e.failure)) {
        await _expire();
      } else {
        _keepTokensAndSignOut();
      }
    } catch (_) {
      // Transient (network/server) — keep tokens, just show signed out.
      if (!mounted || _userActionStarted) return;
      _keepTokensAndSignOut();
    }
  }

  /// 이 실패가 **세션의 끝**인가.
  ///
  /// 서버가 자격을 거부한 것(만료·잘못된 자격·트레이너 아님)만 해당한다. 연결 실패나
  /// 계약이 깨진 응답은 다음 실행에서 다시 시도할 여지가 있으므로 토큰을 남긴다.
  bool _endsSession(AuthFailure failure) => switch (failure) {
    AuthFailure.sessionExpired ||
    AuthFailure.invalidCredentials ||
    AuthFailure.notTrainer => true,
    AuthFailure.network ||
    AuthFailure.emptyResponse ||
    AuthFailure.unknown ||
    AuthFailure.emailTaken ||
    AuthFailure.passwordWeak ||
    AuthFailure.passwordTooLong ||
    AuthFailure.noSocialToken ||
    AuthFailure.emptyCredentials => false,
  };

  /// 이번에는 못 들어갔지만 세션이 끝난 것은 아니다 — 저장된 토큰을 남긴 채 로그인
  /// 화면으로 보낸다. 다음 실행에서 다시 시도한다.
  void _keepTokensAndSignOut() {
    if (!mounted || _userActionStarted) return;
    _setAccessToken(null);
    state = const SessionState(status: SessionStatus.signedOut);
  }

  Future<void> _refreshAndResolve(String refresh) async {
    if (_userActionStarted) return;
    final TrainerAuthTokens tokens;
    try {
      tokens = await _repo.refresh(refresh);
    } on AuthException catch (e) {
      // The refresh failed — but a user action (login/demo/sign-out) may
      // have landed during the slow call; don't clobber it.
      if (_userActionStarted) return;
      // 확인 요청과 같은 기준을 쓴다. 예전에는 여기서 모든 실패를 만료로 보내,
      // 갱신이 연결 실패나 서버 오류로 끝나도 저장된 토큰을 지웠다.
      if (_endsSession(e.failure)) {
        await _expire();
      } else {
        _keepTokensAndSignOut();
      }
      return;
    } catch (_) {
      if (_userActionStarted) return;
      _keepTokensAndSignOut();
      return;
    }
    // Re-check the race guard after the await, like every _resolveSession
    // branch does — a user action during a slow refresh must win.
    if (_userActionStarted) return;
    // Some backends rotate only the access token and omit a new refresh
    // token — keep the existing one then, or the next expiry can never
    // restore. An empty access is still a failure (fromJson guards it), so
    // only the refresh needs the fallback.
    final rotated = TrainerAuthTokens(
      access: tokens.access,
      refresh: tokens.refresh.isEmpty ? refresh : tokens.refresh,
    );
    await _persist(rotated);
    // A login/demo/sign-out may have started while secure storage was saving.
    // Its queued storage mutation runs after this stale save and must win.
    if (_userActionStarted) return;
    await _resolveSession(
      access: rotated.access,
      refresh: rotated.refresh,
      allowRefresh: false,
    );
  }

  // --- login flows --------------------------------------------------------

  /// Email/password login. Throws [AuthException] on failure and
  /// [NotTrainerException] when the account is not a trainer.
  Future<void> login({required String email, required String password}) async {
    _userActionStarted = true;
    final tokens = await _repo.login(email: email, password: password);
    await _establish(tokens);
  }

  /// Creates a trainer account then signs in. Throws [AuthException].
  Future<void> register({
    required String email,
    required String password,
    required String name,
  }) async {
    _userActionStarted = true;
    final tokens = await _repo.register(
      email: email,
      password: password,
      name: name,
    );
    await _establish(tokens);
  }

  /// Social sign-in (kakao / google). Throws [AuthException].
  Future<void> socialLogin({required String provider}) async {
    _userActionStarted = true;
    final tokens = await _repo.socialLogin(
      provider: provider,
      token: 'demo-$provider-token',
    );
    await _establish(tokens);
  }

  /// Persists fresh tokens and attaches the trainer profile from `/me`.
  /// Any failure clears the just-issued tokens and rethrows an
  /// [AuthException] (role rejection keeps its specific message).
  Future<void> _establish(TrainerAuthTokens tokens) async {
    await _persist(tokens);
    _setAccessToken(tokens.access);
    try {
      final profile = await _repo.fetchProfile(tokens.access);
      if (!mounted) return;
      _ref.read(sessionExpiredNoticeProvider.notifier).state = false;
      state = SessionState(
        status: SessionStatus.authenticated,
        profile: profile,
      );
    } catch (e) {
      // 로그인·가입·소셜이 실패한 것이라 이 만료도 그 사용자 행동의 일부다 —
      // 사용자 행동 가드에 막히면 거부된 자격이 저장소에 남는다.
      await _expire(userInitiated: true);
      if (e is AuthException) rethrow;
      throw const AuthException(AuthFailure.unknown);
    }
  }

  // --- demo / sign-out ----------------------------------------------------

  /// Enters demo mode — skip login, no token, browse with mock data.
  /// Not persisted, so a restart returns to the signed-out state.
  void enterDemo() {
    _userActionStarted = true;
    // Demo is intentionally in-memory only. Queue the clear so it also wins
    // over any launch-time refresh save that is already in flight.
    unawaited(_clearPersistedTokens());
    _setAccessToken(null);
    state = const SessionState(status: SessionStatus.demo);
  }

  /// Replaces the authenticated or demo profile after a successful profile
  /// mutation. Demo keeps its status and only updates the in-memory snapshot.
  /// Keeping this in the session owner prevents MY, the sidebar, and
  /// subsequent consumers from showing different snapshots.
  void replaceProfile(TrainerProfile profile) {
    final status = state.status;
    if (status != SessionStatus.authenticated && status != SessionStatus.demo) {
      return;
    }
    state = SessionState(status: status, profile: profile);
  }

  /// Signs out — revokes the session server-side, clears persisted tokens,
  /// and returns to the login screen.
  Future<void> signOut() async {
    _userActionStarted = true;
    // 지우기 **전에** 서버에 알린다 — 지운 뒤에는 폐기할 토큰이 없다.
    await _revokeSession();
    // 사용자가 직접 요청한 만료다 — 자기 자신의 가드에 막히면 안 된다.
    await _expire(userInitiated: true);
    // 직접 로그아웃한 것이다 — 만료 안내가 남아 있었다면 거둔다.
    if (mounted) _ref.read(sessionExpiredNoticeProvider.notifier).state = false;
  }

  // --- 실행 중 만료 (#1546) -----------------------------------------------

  /// 이 세션이 아직 [token] 으로 로그인해 있는가.
  ///
  /// 느린 갱신 중에 로그아웃했거나 다른 계정으로 로그인했다면 거짓이다 — 그때
  /// 뒤늦게 도착한 갱신 결과가 새 세션을 덮거나 끝내면 안 된다.
  bool _holdsToken(String token) =>
      mounted &&
      state.status == SessionStatus.authenticated &&
      _ref.read(authAccessTokenProvider) == token;

  /// 실행 중 401 을 받은 뒤 갱신 토큰으로 한 번 회전한다.
  ///
  /// 복구([_refreshAndResolve])와 같은 기준([_endsSession])을 쓴다: 서버가
  /// 갱신을 **거부한 것만** 세션의 끝이다. 연결 실패·5xx 는 저장된 토큰을 그대로
  /// 두고 원래 오류를 돌려준다.
  @override
  Future<TokenRefreshResult> refreshAfterUnauthorized(String staleToken) async {
    if (!_holdsToken(staleToken)) {
      return const TokenRefreshResult.unavailable();
    }
    String? refresh;
    try {
      // 읽기도 저장 큐를 탄다 — 먼저 시작한 저장·삭제가 끝난 값을 읽는다.
      await _serializeTokenStorage(() async {
        refresh = await _tokens.readRefreshToken();
      });
    } catch (_) {
      return const TokenRefreshResult.unavailable();
    }
    if (!_holdsToken(staleToken)) {
      return const TokenRefreshResult.unavailable();
    }
    final String? stored = refresh;
    if (stored == null || stored.isEmpty) {
      // 접근 토큰은 거부됐고 회전할 수단이 없다 — 세션이 끝났다.
      await _endExpiredSession(staleToken);
      return const TokenRefreshResult.rejected();
    }

    final TrainerAuthTokens tokens;
    try {
      tokens = await _repo.refresh(stored);
    } on AuthException catch (e) {
      if (_endsSession(e.failure)) {
        await _endExpiredSession(staleToken);
        return const TokenRefreshResult.rejected();
      }
      return const TokenRefreshResult.unavailable();
    } catch (_) {
      return const TokenRefreshResult.unavailable();
    }
    // 회전하는 사이 로그아웃·다른 계정 로그인이 있었다면 새 토큰을 버린다.
    if (!_holdsToken(staleToken)) {
      return const TokenRefreshResult.unavailable();
    }
    final TrainerAuthTokens rotated = TrainerAuthTokens(
      access: tokens.access,
      refresh: tokens.refresh.isEmpty ? stored : tokens.refresh,
    );
    await _persist(rotated);
    if (!_holdsToken(staleToken)) {
      return const TokenRefreshResult.unavailable();
    }
    _setAccessToken(rotated.access);
    return TokenRefreshResult.refreshed(rotated.access);
  }

  /// 갱신이 거부되었다 — 로그아웃과 같은 길([_expire])로 세션을 닫고 로그인
  /// 화면에 안내를 띄운다.
  ///
  /// 서버는 이미 이 갱신 토큰을 받지 않으므로 폐기(`/auth/logout`)는 부르지 않는다.
  Future<void> _endExpiredSession(String staleToken) async {
    if (!_holdsToken(staleToken)) return;
    // 로그인한 뒤라 사용자 행동 가드는 이미 켜져 있다. 그 가드는 **복구**가 뒤늦게
    // 세션을 덮지 못하게 하는 것이고, 이 만료는 지금 세션에 대한 것이다.
    await _expire(userInitiated: true);
    if (!mounted || state.status != SessionStatus.signedOut) return;
    _ref.read(sessionExpiredNoticeProvider.notifier).state = true;
  }

  /// 저장된 갱신 토큰을 서버에서 폐기한다(`POST /auth/logout`).
  ///
  /// 여기까지 로그아웃은 이 브라우저의 저장소를 비우는 일이었다. 갱신 토큰은 만료
  /// (기본 30일)까지 살아 있어서, 공용 PC 에서 저장소가 복사되거나 토큰이 새면
  /// 로그아웃을 눌러도 그 세션은 그대로였다 — 트레이너 계정은 담당 회원의 식단·운동·
  /// 건강 정보를 전부 읽는 계정이라 영향 범위가 좁지 않다(#966).
  ///
  /// **어떤 실패도 로그아웃을 막지 않는다.** 폐기는 성사되면 좋은 일이고, 실패했다고
  /// 사용자를 로그인된 화면에 붙잡아 두는 쪽이 훨씬 나쁘다.
  Future<void> _revokeSession() async {
    String? refresh;
    try {
      // 읽기도 저장 큐를 탄다 — 회전이 방금 저장한 토큰이 있다면 그것을 끊어야 한다.
      await _serializeTokenStorage(() async {
        refresh = await _tokens.readRefreshToken();
      });
    } catch (_) {
      return; // secure storage 를 못 읽으면 끊을 대상도 모른다.
    }
    final token = refresh;
    // 데모 세션에는 저장된 토큰이 없다 — 부를 것도 없다.
    if (token == null || token.isEmpty) return;
    try {
      await _repo.logout(token);
    } catch (_) {
      // 위 주석 참고 — 삼킨다.
    }
  }

  // --- helpers ------------------------------------------------------------

  Future<void> _persist(TrainerAuthTokens tokens) async {
    try {
      await _serializeTokenStorage(
        () =>
            _tokens.saveTokens(access: tokens.access, refresh: tokens.refresh),
      );
    } catch (_) {
      // Secure storage unavailable — proceed with the in-memory token.
    }
  }

  Future<void> _clearPersistedTokens() async {
    try {
      await _serializeTokenStorage(_tokens.clear);
    } catch (_) {}
  }

  Future<void> _serializeTokenStorage(Future<void> Function() operation) {
    final result = _tokenStorageTail.then((_) => operation());
    // Keep the queue usable even when a platform storage operation fails;
    // the caller still receives [result] and applies its existing error policy.
    _tokenStorageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// Clears tokens + in-memory state and lands signed out.
  /// 세션을 끝내고 저장된 토큰을 지운다.
  ///
  /// [userInitiated] 는 **이 만료가 지금 진행 중인 사용자 행동의 일부인가**다.
  /// 로그아웃, 그리고 로그인·가입·소셜이 거부되어 방금 받은 자격을 지우는 경우가
  /// 여기 해당한다. 이때 사용자 행동 가드를 적용하면 그 행동이 자기 자신의 가드에
  /// 막혀 아무 일도 일어나지 않는다.
  ///
  /// 기본값(false)은 복구가 만료로 흘러가는 경우다. 이때는 **지우기 전에** 확인한다.
  /// 느린 복구 중에 로그인이 끝났다면 저장소에는 방금 받은 토큰이 들어 있고, 저장소
  /// 작업은 큐로 직렬화되어 나중에 들어간 것이 뒤에 실행되므로, 뒤늦은 만료의 `clear`
  /// 는 그 저장을 **확실히** 덮어쓴다 — 화면은 로그인 상태인데 다음 실행에서 로그아웃된다.
  Future<void> _expire({bool userInitiated = false}) async {
    if (!mounted) return;
    if (!userInitiated && _userActionStarted) return;
    await _clearPersistedTokens();
    // `_setAccessToken` reads a provider — guard it behind the mounted check
    // so it never runs against a disposed container during teardown.
    if (!mounted) return;
    if (!userInitiated && _userActionStarted) return;
    _setAccessToken(null);
    state = const SessionState(status: SessionStatus.signedOut);
  }
}

/// 실행 중 세션이 만료되어 로그인 화면으로 보냈다 — 로그인 화면이 한 번 안내하고
/// 거둔다. (#1546)
///
/// 세션 상태에 넣지 않는 이유: 세션 상태가 바뀔 때마다 라우터 가드와 계정 범위가
/// 다시 계산된다. 안내를 거두는 일로 그것들이 다시 돌 이유가 없다.
final sessionExpiredNoticeProvider = StateProvider<bool>(
  (ref) => false,
  name: 'sessionExpiredNotice',
);

/// Exposes the trainer session state + controller app-wide.
final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>(
      (ref) => SessionController(ref),
      name: 'trainerSession',
    );
