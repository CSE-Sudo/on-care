import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/network/session_refresh.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/auth_token.dart';
import 'package:oncare_trainer/core/network/consent_gate.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/secure_token_store.dart';
import 'package:oncare_trainer/features/auth/data/repositories/consent_repositories.dart';
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
    // 실행 중 트레이너 API 가 403 consent_required 를 주면 알려 온다(#3155).
    _consentBridge = _ref.read(consentGateBridgeProvider)
      ..attach(markConsentRequired);
    _restore();
  }

  final Ref _ref;
  late final SessionRefreshBridge _refreshBridge;
  late final ConsentGateBridge _consentBridge;

  @override
  void dispose() {
    _refreshBridge.detach(this);
    _consentBridge.detach(markConsentRequired);
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
    _ref.read(accountEmailProvider.notifier).state = email;
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

  /// 동의가 끝날 때까지 저장하지 않고 들고 있는 토큰. (#2819)
  ///
  /// 동의가 남은 세션을 저장해 두면, 동의 화면에서 새로고침만 해도 복구가
  /// 동의 없이 들여보낸다 — 복구는 `/trainer/me` 만 보고 동의 여부를 모른다.
  /// 저장하지 않으면 새로고침은 로그인 화면으로 돌아가고, 다시 로그인하면 서버가
  /// 다시 동의를 요구한다. 동의를 마치면 그때 저장한다.
  TrainerAuthTokens? _consentPendingTokens;
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
      // 역할 확인을 통과한 앱만 옛 키를 지운다(#3260). 트레이너가 아니면 아래
      // [_expire] 가 복사해 온 새 키만 버리고 옛 키를 남겨, 회원 앱이 가져가게 한다.
      await _claimLegacyKeys(access);
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
    AuthFailure.emailCodeInvalid ||
    AuthFailure.emailCodeRequired ||
    AuthFailure.noSocialToken ||
    AuthFailure.tooManyAttempts ||
    AuthFailure.signedUpSignInFailed ||
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
    required String emailCode,
    String phone = '',
    List<String>? consents,
  }) async {
    _userActionStarted = true;
    final tokens = await _repo.register(
      email: email,
      password: password,
      name: name,
      emailCode: emailCode,
      phone: phone,
      consents: consents,
    );
    await _establishAfterSignUp(tokens);
  }

  /// 가입 뒤 세션을 연다. 실패해도 계정은 이미 있다 — 가입 실패로 알리면 다시
  /// 누른 가입이 409 가 되므로 [AuthFailure.signedUpSignInFailed] 로 바꾼다(#3248).
  Future<void> _establishAfterSignUp(TrainerAuthTokens tokens) async {
    try {
      await _establish(tokens);
    } on AuthException catch (e) {
      throw AuthException(
        AuthFailure.signedUpSignInFailed,
        detail: e.failure.name,
      );
    }
  }

  /// Social sign-in (kakao / google). Throws [AuthException].
  ///
  /// [token] 은 provider 에서 받은 토큰이다(구글 ID 토큰·카카오 access_token).
  /// 로그인 화면과 탈퇴 본인 확인(#3039)이 같은 `trainerSocialLoginProvider` 로
  /// 받는다(#330).
  Future<void> socialLogin({
    required String provider,
    required String token,
  }) async {
    _userActionStarted = true;
    final tokens = await _repo.socialLogin(provider: provider, token: token);
    await _establish(tokens);
  }

  /// Persists fresh tokens and attaches the trainer profile from `/me`.
  /// Any failure clears the just-issued tokens and rethrows an
  /// [AuthException] (role rejection keeps its specific message).
  Future<void> _establish(TrainerAuthTokens tokens) async {
    // 동의가 남았으면 저장하지 않는다 — 앞 계정의 저장 토큰도 지워, 새로고침이
    // 앞 계정으로 되살아나지 않게 한다(#2819, [_consentPendingTokens]).
    if (tokens.consentRequired) {
      await _clearPersistedTokens();
      _consentPendingTokens = tokens;
    } else {
      await _persist(tokens);
      _consentPendingTokens = null;
    }
    _setAccessToken(tokens.access);
    try {
      final profile = await _repo.fetchProfile(tokens.access);
      if (!mounted) return;
      _ref.read(sessionExpiredNoticeProvider.notifier).state = false;
      _ref.read(signedOutByUserProvider.notifier).state = false;
      state = SessionState(
        status: SessionStatus.authenticated,
        profile: profile,
        consentRequired: tokens.consentRequired,
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
    _ref.read(signedOutByUserProvider.notifier).state = false;
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
    state = SessionState(
      status: status,
      profile: profile,
      consentRequired: state.consentRequired,
    );
  }

  /// 동의 화면에서 체크한 항목을 남긴다 → `POST /users/me/consents`. (#2819)
  ///
  /// 서버가 남은 동의가 없다고 하면 들고 있던 토큰을 그제야 저장하고 동의 요구를
  /// 푼다 — 라우터 가드가 동의 화면을 걷어 낸다. 실패는 그대로 던진다(화면이
  /// 알린다). 그 사이 로그아웃·다른 계정 로그인이 있었다면 결과를 버린다.
  Future<void> submitConsents(List<String> consents) async {
    final String? token = _ref.read(authAccessTokenProvider);
    final bool stillRequired = await _ref
        .read(consentRepositoryProvider)
        .submit(consents);
    if (token == null || !_holdsToken(token)) return;
    if (!stillRequired) {
      final TrainerAuthTokens? pending = _consentPendingTokens;
      _consentPendingTokens = null;
      if (pending != null) await _persist(pending);
      if (!_holdsToken(token)) return;
    }
    state = SessionState(
      status: state.status,
      profile: state.profile,
      consentRequired: stillRequired,
    );
  }

  /// 서버가 [token] 세션에 필수 동의가 남았다고 했다 → 동의 화면으로. (#3155)
  ///
  /// 로그인 응답으로 알게 된 경우([_establish])와 달리 토큰은 이미 저장돼 있다
  /// (복구한 세션이거나 쓰는 사이 문서 버전이 올랐다). 그대로 두어도 된다 —
  /// 새로고침으로 복구해도 서버가 다시 403 을 주어 이 길로 돌아온다. 프로필은
  /// 남겨 동의 화면 뒤에서도 같은 계정임을 지킨다. 이미 로그아웃했거나 다른
  /// 계정으로 바뀐 뒤 늦게 온 응답은 버린다.
  void markConsentRequired(String token) {
    if (!_holdsToken(token) || state.consentRequired) return;
    state = SessionState(
      status: SessionStatus.authenticated,
      profile: state.profile,
      consentRequired: true,
    );
  }

  /// Signs out — revokes the session server-side, clears persisted tokens,
  /// and returns to the login screen.
  ///
  /// 사용자가 직접 끝낸 세션이라 로그인 화면 주소에 지금 자리를 싣지 않는다
  /// (#2765). 탈퇴도 이 길로 온다. 상태가 바뀌기 **전에** 표시해야 라우터 가드가
  /// 로그아웃 상태를 처음 볼 때 이미 이 값을 읽는다.
  Future<void> signOut() async {
    _userActionStarted = true;
    _ref.read(signedOutByUserProvider.notifier).state = true;
    // 지우기 **전에** 서버에 알린다 — 지운 뒤에는 폐기할 토큰이 없다.
    await _revokeSession();
    // 사용자가 직접 요청한 만료다 — 자기 자신의 가드에 막히면 안 된다.
    await _expire(userInitiated: true, forgetLegacy: true);
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
    // 동의가 남은 세션의 토큰은 저장소가 아니라 메모리에 있다(#2819). 저장소만
    // 보면 동의 화면에 접근 토큰 수명(60분)보다 오래 머문 트레이너가 갱신할
    // 수단이 없어 강제로 로그아웃됐다(#3248).
    final TrainerAuthTokens? pending = _consentPendingTokens;
    String? refresh = pending?.refresh;
    if (pending == null) {
      try {
        // 읽기도 저장 큐를 탄다 — 먼저 시작한 저장·삭제가 끝난 값을 읽는다.
        await _serializeTokenStorage(() async {
          refresh = await _tokens.readRefreshToken();
        });
      } catch (_) {
        return const TokenRefreshResult.unavailable();
      }
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
    // 계정 확인보다 **먼저** 저장한다. 갱신 토큰은 일회용이라 방금 쓴 [stored] 는
    // 서버에서 이미 폐기됐다. 아래에서 다른 계정의 토큰으로 밝혀져도, 저장소는 그
    // 계정의 세션이므로 회전 결과를 돌려놓아야 그 세션이 다음 회전에서 끊기지
    // 않는다(#2764). 동의가 남은 세션은 저장하지 않고 들고만 있는다(#2819).
    // 회전하는 사이 동의를 마쳤다면 그쪽이 옛 토큰을 저장했으니 새 토큰으로 덮는다.
    if (pending != null && identical(_consentPendingTokens, pending)) {
      _consentPendingTokens = TrainerAuthTokens(
        access: rotated.access,
        refresh: rotated.refresh,
        consentRequired: true,
      );
    } else {
      await _persist(rotated);
    }
    if (!_holdsToken(staleToken)) {
      return const TokenRefreshResult.unavailable();
    }

    // 웹 토큰이 모든 탭이 함께 보는 저장소(localStorage)에 있던 때에는, 다른
    // 탭이 다른 트레이너로 다시 로그인하면 방금 받은 토큰이 **그 계정의 것**이
    // 됐다. 지금은 탭 단위 저장소(sessionStorage, #2828)라 다른 탭과 나누지 않고,
    // 저장소를 복사해 받는 복제 탭은 시작할 때 받은 토큰을 버린다(#3248). 그래도
    // 회전 결과를 쓰기 전에 주인을 확인하는 규칙은 남긴다 — 저장소가 다른 계정의
    // 것이면 화면은 이전 트레이너인데 요청은 그 계정 명의로 나간다(#2764).
    final _AccountCheck check = await _checkSameAccount(rotated.access);
    if (!_holdsToken(staleToken)) {
      return const TokenRefreshResult.unavailable();
    }
    switch (check) {
      case _AccountCheck.same:
        _setAccessToken(rotated.access);
        return TokenRefreshResult.refreshed(rotated.access);
      case _AccountCheck.other:
        await _endSwitchedAccountSession(staleToken);
        return const TokenRefreshResult.rejected();
      case _AccountCheck.unknown:
        // 확인을 못 했다(연결 실패·서버 오류) — 다른 계정의 토큰일 수 있으니 채택하지
        // 않되, 세션도 끝내지 않는다. 회전 결과는 저장소에 있어 다음 401 때 그것으로
        // 다시 회전하고 다시 확인한다.
        return const TokenRefreshResult.unavailable();
    }
  }

  /// [access] 의 주인이 이 탭에 로그인한 트레이너와 같은가(#2764).
  ///
  /// 프로필 이메일로 비교한다 — 세션이 들고 있는 계정 식별자가 이메일뿐이고, 계정
  /// 경계([_syncAccountScope])도 같은 값을 쓴다. 토큰을 클라이언트에서 디코드해
  /// `sub` 를 보는 길은 요청이 하나 줄지만 클라이언트가 JWT 구조에 묶인다.
  Future<_AccountCheck> _checkSameAccount(String access) async {
    final String? mine = _accountKey(state.profile?.email);
    if (mine == null) return _AccountCheck.unknown;
    final TrainerProfile profile;
    try {
      profile = await _repo.fetchProfile(access);
    } on NotTrainerException {
      // 트레이너가 아닌 계정의 토큰이다 — 이 탭의 계정일 수 없다.
      return _AccountCheck.other;
    } catch (_) {
      // 방금 받은 토큰의 401 을 포함해 모두 "모름"으로 둔다. 확인 실패만으로
      // 이 탭의 세션을 끝내면 잠깐 끊긴 사용자에게 재로그인을 요구하게 된다.
      return _AccountCheck.unknown;
    }
    return _accountKey(profile.email) == mine
        ? _AccountCheck.same
        : _AccountCheck.other;
  }

  /// 이메일 비교용 정규화. 비어 있으면 비교할 수 없다.
  static String? _accountKey(String? email) {
    final String key = (email ?? '').trim().toLowerCase();
    return key.isEmpty ? null : key;
  }

  /// 다른 탭이 다른 계정으로 로그인해 이 탭의 세션을 이을 수 없다 — **이 탭만**
  /// 로그아웃 상태로 보내고 만료 안내를 띄운다(#2764).
  ///
  /// [_endExpiredSession] 과 달리 저장소를 지우지 않는다. 저장소의 토큰은 다른 탭이
  /// 지금 쓰는 계정의 것이라, 지우면 그 탭까지 다음 회전에서 끊긴다. 서버 폐기
  /// (`/auth/logout`)도 같은 이유로 부르지 않는다.
  Future<void> _endSwitchedAccountSession(String staleToken) async {
    if (!_holdsToken(staleToken)) return;
    // 사용자가 끝낸 세션이 아니다 — 로그인 뒤 원래 자리로 잇는다.
    _ref.read(signedOutByUserProvider.notifier).state = false;
    _setAccessToken(null);
    state = const SessionState(status: SessionStatus.signedOut);
    _ref.read(sessionExpiredNoticeProvider.notifier).state = true;
  }

  /// 비밀번호 변경 응답이 준 새 토큰으로 갈아 끼운다(#2766).
  ///
  /// 서버는 비밀번호를 바꾸면 그 전에 발급한 토큰을 모두 무효로 만든다. 이 기기도
  /// 예외가 아니어서, 응답의 새 토큰을 메모리와 저장소에 넣어야 로그아웃되지 않는다.
  /// 메모리를 먼저 바꾼다 — 그 사이 401 을 받은 요청은 인터셉터가 새 토큰으로
  /// 다시 보낸다(회전하지 않는다). 프로필·계정 경계는 그대로다(같은 계정).
  Future<void> adoptReissuedTokens(TrainerAuthTokens tokens) async {
    if (!mounted || state.status != SessionStatus.authenticated) return;
    if (tokens.access.isEmpty) return;
    _setAccessToken(tokens.access);
    String? keptRefresh;
    if (tokens.refresh.isEmpty) {
      try {
        await _serializeTokenStorage(() async {
          keptRefresh = await _tokens.readRefreshToken();
        });
      } catch (_) {
        keptRefresh = null;
      }
    }
    await _persist(
      TrainerAuthTokens(
        access: tokens.access,
        refresh: tokens.refresh.isEmpty ? (keptRefresh ?? '') : tokens.refresh,
      ),
    );
  }

  /// 갱신이 거부되었다 — 로그아웃과 같은 길([_expire])로 세션을 닫고 로그인
  /// 화면에 안내를 띄운다.
  ///
  /// 서버는 이미 이 갱신 토큰을 받지 않으므로 폐기(`/auth/logout`)는 부르지 않는다.
  Future<void> _endExpiredSession(String staleToken) async {
    if (!_holdsToken(staleToken)) return;
    // 만료는 사용자가 끝낸 세션이 아니다 — 로그인 뒤 원래 자리로 잇는다.
    _ref.read(signedOutByUserProvider.notifier).state = false;
    // 로그인한 뒤라 사용자 행동 가드는 이미 켜져 있다. 그 가드는 **복구**가 뒤늦게
    // 세션을 덮지 못하게 하는 것이고, 이 만료는 지금 세션에 대한 것이다.
    await _expire(userInitiated: true, forgetLegacy: true);
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
    // 동의 화면에서 로그아웃하면 토큰이 저장소가 아니라 메모리에 있다(#2819).
    // 저장소만 보면 폐기할 것이 없다고 여겨 서버 세션이 그대로 남았다(#3248).
    String? refresh = _consentPendingTokens?.refresh;
    if (refresh == null || refresh.isEmpty) {
      try {
        // 읽기도 저장 큐를 탄다 — 회전이 방금 저장한 토큰이 있다면 그것을 끊어야 한다.
        await _serializeTokenStorage(() async {
          refresh = await _tokens.readRefreshToken();
        });
      } catch (_) {
        return; // secure storage 를 못 읽으면 끊을 대상도 모른다.
      }
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

  /// [forgetLegacy] 는 [SecureTokenStore.clear] 와 같다 — 이 앱이 세션을 끝낼
  /// 때(로그아웃·실행 중 만료)만 켠다(#3260).
  Future<void> _clearPersistedTokens({bool forgetLegacy = false}) async {
    try {
      await _serializeTokenStorage(
        () => _tokens.clear(forgetLegacy: forgetLegacy),
      );
    } catch (_) {}
  }

  /// 복원이 [access] 로 트레이너 역할을 확인했다 — 그 토큰이 옛 키에서 왔으면 옛
  /// 키를 지운다(#3260). 실패해도 세션은 이어 간다 — 다음 복원이 다시 지운다.
  Future<void> _claimLegacyKeys(String access) async {
    try {
      await _serializeTokenStorage(() => _tokens.claimLegacyKeys(access));
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
  ///
  /// [forgetLegacy] 는 이름공간 없던 옛 키도 지운다(#3260) — 로그아웃·실행 중
  /// 만료처럼 이 앱이 세션을 끝낼 때만 켠다. 복원의 역할 확인에 걸린 경우는 끈
  /// 채로 두어 옛 키를 원래 주인 앱(회원 앱)이 가져가게 한다.
  Future<void> _expire({
    bool userInitiated = false,
    bool forgetLegacy = false,
  }) async {
    if (!mounted) return;
    if (!userInitiated && _userActionStarted) return;
    await _clearPersistedTokens(forgetLegacy: forgetLegacy);
    // `_setAccessToken` reads a provider — guard it behind the mounted check
    // so it never runs against a disposed container during teardown.
    if (!mounted) return;
    if (!userInitiated && _userActionStarted) return;
    _setAccessToken(null);
    _consentPendingTokens = null;
    state = const SessionState(status: SessionStatus.signedOut);
  }
}

/// 회전으로 받은 토큰의 주인 확인 결과(#2764).
enum _AccountCheck {
  /// 이 탭의 계정이다 — 채택한다.
  same,

  /// 다른 계정이다 — 채택하지 않고 이 탭의 세션을 끝낸다.
  other,

  /// 확인하지 못했다 — 채택하지도, 끝내지도 않는다.
  unknown,
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

/// 지금의 로그아웃 상태가 **사용자가 직접** 로그아웃·탈퇴한 결과인가(#2765).
///
/// 라우터 가드는 이 값이 참이면 로그인 화면 주소에 이전 자리(`?from=`)를 싣지
/// 않는다. 세션 만료·첫 실행 딥링크는 거짓이라 지금처럼 이어 간다. 새 세션
/// (로그인·가입·소셜·데모)이 시작되면 거짓으로 돌아간다.
///
/// 세션 상태에 넣지 않는 이유는 [sessionExpiredNoticeProvider] 와 같다.
final signedOutByUserProvider = StateProvider<bool>(
  (ref) => false,
  name: 'signedOutByUser',
);

/// Exposes the trainer session state + controller app-wide.
final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>(
      (ref) => SessionController(ref),
      name: 'trainerSession',
    );
