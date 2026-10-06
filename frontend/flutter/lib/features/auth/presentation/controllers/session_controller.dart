import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/consent_gate.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare_core/network/session_refresh.dart';

enum SessionStatus { unknown, signedOut, demo, authenticated }

class SessionState {
  const SessionState({
    this.status = SessionStatus.unknown,
    this.restoreFailed = false,
    this.consentRequired = false,
  });
  final SessionStatus status;

  /// 로그인은 됐지만 가입 동의가 남았다 — 다른 화면보다 먼저 동의 화면을
  /// 거친다. (#2819)
  ///
  /// 동의 절차가 생기기 전에 가입한 계정, 소셜 로그인으로 처음 들어온 계정,
  /// 문서 버전이 올라간 계정이 여기 해당한다. 서버가 로그인 응답과
  /// `GET /users/me` 의 `consent_required` 로 알린다. 데모에는 계정이 없어
  /// 언제나 거짓이다.
  final bool consentRequired;

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

/// 회원 앱에 트레이너 계정으로 로그인하려 했다. (#3137)
///
/// 서버는 트레이너 토큰에 회원 API 를 403 으로 거절하므로, 이 토큰으로 들어가면
/// 로그인 직후부터 모든 회원 화면이 오류가 된다. 받은 토큰은 저장하지 않고 서버에서
/// 폐기한 뒤 이 예외를 던진다 — 로그인 화면이 트레이너 웹 안내를 보인다.
class TrainerAccountSignInRejected implements Exception {
  const TrainerAccountSignInRejected();

  @override
  String toString() => 'TrainerAccountSignInRejected()';
}

class SessionController extends StateNotifier<SessionState>
    implements SessionTokenRefresher {
  SessionController(this._ref) : super(const SessionState()) {
    // 실행 중 401 을 받은 인터셉터가 이 컨트롤러로 토큰을 회전한다(#1546).
    _refreshBridge = _ref.read(sessionRefreshBridgeProvider)..attach(this);
    // 실행 중 데이터 요청이 403 consent_required 를 받으면 알려 온다(#3088).
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

  /// 같은 세션 안에서 회전([refreshAfterUnauthorized])·재발급
  /// ([adoptReissuedTokens])으로 물러난 접근 토큰들. (#3231)
  ///
  /// 느린 요청 사이에 토큰이 회전돼도 같은 계정의 세션이다. 그 요청의 결과까지
  /// "다른 세션의 뒤늦은 응답" 으로 버리면 동의 저장 같은 결과가 사라진다.
  /// 로그인·로그아웃처럼 계정 경계를 넘는 전환에서는 비운다.
  final Set<String> _rotatedTokens = <String>{};

  void _setToken(String? token, {bool rotated = false}) {
    final String? previous = _ref.read(authAccessTokenProvider);
    if (!rotated) {
      _rotatedTokens.clear();
    } else if (previous != null) {
      _rotatedTokens.add(previous);
    }
    _ref.read(authAccessTokenProvider.notifier).state = token;
  }

  void _resetFeatureState() {
    _ref.read(sessionFeatureResetProvider)();
  }

  /// 첫 설정 기기 기록을 지운다 — 새 토큰으로 로그인할 때 부른다. (#2630)
  /// 세션이 끝날 때는 홈 가이드까지 지우는 [_forgetAccountRecords] 를 쓴다.
  ///
  /// 그 기록은 프로필을 못 받아 왔을 때 "이 계정은 이미 끝냈다" 로 쓰는 보조
  /// 판단이다. 기기 전체에 하나로 남으면 앞 계정의 기록이 다음 계정의 판단에
  /// 섞여, 첫 설정을 안 한 새 계정도 홈으로 간다. 같은 토큰으로 되살아나는
  /// 세션 복구만 그 기록을 이어 쓴다.
  Future<void> _forgetDeviceFirstRun() async {
    try {
      await _ref.read(appPrefsProvider).forgetOnboardingDone();
    } catch (_) {
      // 설정 저장소가 없거나 쓰기에 실패해도 세션 전환은 막지 않는다.
    }
  }

  /// 계정에 매인 기기 기록(첫 설정·홈 가이드)을 모두 지운다 — 세션이 끝나는
  /// 길(로그아웃·만료·갱신 거부)마다 부른다. (#3154)
  ///
  /// 다음에 이 기기로 들어오는 사람이 같은 계정이라는 보장이 없다. 첫 설정 기록만
  /// 지우면 앞 계정이 끝낸 홈 가이드 기록이 남아, 다른 계정으로 로그인한 새
  /// 회원이 첫 사용 안내를 한 번도 보지 못한다. 언어와 설치 표식은 기기의 것이라
  /// 남는다([AppPrefs.clearAccountScoped]).
  Future<void> _forgetAccountRecords() async {
    try {
      await _ref.read(appPrefsProvider).clearAccountScoped();
    } catch (_) {
      // 설정 저장소가 없거나 쓰기에 실패해도 로그아웃은 막지 않는다.
    }
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
      final res = await _ref
          .read(dioProvider)
          .get<Map<String, Object?>>(
            '/users/me',
            options: Options(
              headers: <String, Object?>{'Authorization': 'Bearer $access'},
            ),
          );
      if (!mounted || _userActionStarted) return;
      // 회원 계정인지 확인한다(#3054). 회원 앱과 트레이너 웹은 한 출처의 브라우저
      // 저장소를 같이 써서, 옛 키에서 옮겨 온 토큰이 트레이너 것일 수 있다. 서버가
      // 역할을 주지 않으면(배포 전 백엔드) 지금처럼 들어간다 — 앱이 먼저 나가도
      // 회원이 막히지 않게.
      if (!isMemberRole(res.data)) {
        await _expire();
        return;
      }
      // 역할 확인을 통과한 앱만 옛 키를 지운다(#3260). 걸린 앱은 위 [_expire] 가
      // 복사해 온 새 키만 버리고 옛 키를 남겨, 원래 주인 앱이 가져가게 한다.
      try {
        await _ref.read(secureTokenStoreProvider).claimLegacyKeys(access);
      } catch (_) {
        // 옛 키를 못 지워도 이번 세션은 이어 간다 — 다음 복원이 다시 지운다.
      }
      if (!mounted || _userActionStarted) return;
      _setToken(access);
      // 저장된 세션으로 돌아온 계정도 동의가 남았으면 동의 화면부터 거친다
      // (#2819) — 기존 가입자가 "다음 로그인" 을 기다리지 않게 한다.
      state = SessionState(
        status: SessionStatus.authenticated,
        consentRequired: consentRequiredIn(res.data),
      );
    } on DioException catch (e) {
      if (!mounted || _userActionStarted) return;
      final int? code = e.response?.statusCode;
      // 403 은 회원 전용 API 를 다른 역할(트레이너) 토큰으로 부른 것이다(#3054).
      // 갱신해도 역할은 그대로라 회전하지 않고 이 앱의 저장소만 비운다 — 다른
      // 앱의 갱신 토큰을 돌려 그쪽 세션까지 흔들지 않는다.
      if (code == 403) {
        await _expire();
        return;
      }
      if (code == 401) {
        if (allowRefresh &&
            refresh.isNotEmpty &&
            !await _isUnconfirmedLegacy(access)) {
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

  /// [access] 가 역할 확인 전의 옛 키 토큰이면 회전하지 않는다(#3260) — 다른 앱의
  /// 일회용 갱신 토큰일 수 있다. [_expire] 가 이 앱의 새 키만 비우고 옛 키는
  /// 남긴다. 확인하지 못하면 회전하지 않는 쪽으로 둔다.
  Future<bool> _isUnconfirmedLegacy(String access) async {
    try {
      return await _ref
          .read(secureTokenStoreProvider)
          .isUnconfirmedLegacy(access);
    } catch (_) {
      return true;
    }
  }

  /// 갱신 토큰으로 접근 토큰을 회전하고 다시 확정한다.
  Future<void> _refreshAndResolve(String refresh) async {
    if (_userActionStarted) return;
    final Map<String, Object?>? data;
    try {
      final res = await _ref
          .read(dioProvider)
          .post<Map<String, Object?>>(
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
    await _forgetAccountRecords();
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
    // 저장하기 **전에** 회원 계정인지 확인한다(#3137). 세션 복구(#3054)와 같은
    // 규칙이다 — 응답에 역할이 없으면(배포 전 서버) 지금처럼 들어간다.
    if (!isMemberRole(data)) {
      await _rejectTrainerAccount(refresh);
      throw const TrainerAccountSignInRejected();
    }
    try {
      await _ref
          .read(secureTokenStoreProvider)
          .saveTokens(access: access, refresh: refresh);
    } catch (_) {
      // secure storage 저장 실패해도 세션 메모리 토큰으로 진행
    }
    // 새 토큰은 새 계정일 수 있다 — 앞 계정의 첫 설정 기록을 넘기지 않는다.
    await _forgetDeviceFirstRun();
    _setToken(access);
    _resetFeatureState();
    _ref.read(sessionExpiredNoticeProvider.notifier).state = false;
    _ref.read(trainerAccountNoticeProvider.notifier).state = false;
    state = SessionState(
      status: SessionStatus.authenticated,
      consentRequired: consentRequiredIn(data),
    );
  }

  /// 트레이너 계정으로 받은 토큰을 버린다. (#3137)
  ///
  /// 저장소에도 메모리에도 넣지 않고, 서버에 폐기를 보낸다 — 이 기기에서 쓰지 않을
  /// 토큰이 만료까지 살아 있을 이유가 없다. 폐기 실패는 안내를 막지 않는다(로그아웃
  /// [_revokeSession] 과 같은 원칙). 저장소에 있던 앞 세션은 건드리지 않는다.
  Future<void> _rejectTrainerAccount(String refresh) async {
    if (refresh.isNotEmpty) {
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
    if (!mounted) return;
    _setToken(null);
    _ref.read(trainerAccountNoticeProvider.notifier).state = true;
    state = const SessionState(status: SessionStatus.signedOut);
  }

  /// 비밀번호를 바꾼 뒤 서버가 새로 준 토큰으로 **이 기기의 세션을 이어 간다.**
  /// (#2824)
  ///
  /// 비밀번호 변경은 토큰 세대를 올려 그 전 토큰을 모든 기기에서 끊는다(#2766).
  /// 바꾼 기기까지 다시 로그인시키지 않으려고 서버가 새 쌍을 돌려주고, 이 메서드가
  /// 그것을 저장소와 메모리에 넣는다. 같은 계정이 이어지는 것이라 로그인과 달리
  /// 화면 상태([_resetFeatureState])·첫 설정 기록은 건드리지 않는다.
  ///
  /// 로그인 상태가 아니면 아무것도 하지 않는다 — 느린 응답 사이에 로그아웃했다면
  /// 뒤늦은 토큰으로 세션을 되살리면 안 된다. 접근 토큰이 비면 [StateError].
  Future<void> adoptReissuedTokens({
    required String access,
    required String refresh,
  }) async {
    if (access.isEmpty) {
      throw StateError('비밀번호 변경 응답에 토큰이 없습니다.');
    }
    if (!mounted || state.status != SessionStatus.authenticated) return;
    try {
      await _ref
          .read(secureTokenStoreProvider)
          .saveTokens(access: access, refresh: refresh);
    } catch (_) {
      // 저장에 실패해도 이번 실행은 메모리 토큰으로 이어 간다.
    }
    if (!mounted || state.status != SessionStatus.authenticated) return;
    _setToken(access, rotated: true);
  }

  /// Email/password login → POST /auth/login (OAuth2 form). Throws on failure.
  Future<void> login({required String email, required String password}) async {
    _userActionStarted = true;
    _ref.read(trainerAccountNoticeProvider.notifier).state = false;
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
    _ref.read(trainerAccountNoticeProvider.notifier).state = false;
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
  ///
  /// [emailCode] 는 그 이메일로 받은 6자리 인증 코드다(#3038). 틀리면 서버가
  /// 계정을 만들지 않고 400 `invalid_email_code` 를 준다 — 가입 실패이므로
  /// 로그인은 시도하지 않는다.
  Future<void> register({
    required String email,
    required String password,
    required String emailCode,
    String name = '',
    String phone = '',
    List<String>? consents,
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
        'email_code': emailCode,
        // 가입 화면에서 체크한 동의(#2819). 서버가 계정과 한 트랜잭션으로
        // 남기고, 필수 항목이 빠졌으면 계정을 만들지 않고 422 를 준다.
        'consents': ?consents,
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

  /// 동의 화면에서 체크한 항목을 남긴다 → `POST /users/me/consents`. (#2819)
  ///
  /// 성공하면 서버가 돌려준 `consent_required` 로 상태를 바꾼다 — 거짓이면
  /// 라우터 가드가 동의 화면을 풀어 준다. 실패는 그대로 던진다(화면이 알린다).
  /// 그 사이 로그아웃·다른 계정 로그인이 있었다면 결과를 버린다. 같은 세션의
  /// 토큰 회전은 버리지 않는다(#3231).
  Future<void> submitConsents(List<String> consents) async {
    final String? token = _ref.read(authAccessTokenProvider);
    final res = await _ref
        .read(dioProvider)
        .post<Map<String, Object?>>(
          '/users/me/consents',
          data: <String, Object?>{'consents': consents},
        );
    if (!mounted || token == null || !_holdsSessionOf(token)) return;
    state = SessionState(
      status: SessionStatus.authenticated,
      consentRequired: consentRequiredIn(res.data),
    );
  }

  /// [token] 으로 나간 데이터 요청을 서버가 "필수 동의가 남았다" 며 거절했다.
  /// (#3088)
  ///
  /// 앱을 쓰는 사이 문서 버전이 올랐거나 동의가 철회된 경우다. 세션을 동의가
  /// 남은 상태로 바꾸면 라우터 가드가 동의 화면으로 보내고, 동의를 제출하면
  /// [submitConsents] 가 풀어 준다. 그 사이 로그아웃·다른 계정 로그인이 있었다면
  /// 뒤늦은 응답이므로 무시한다.
  void markConsentRequired(String token) {
    if (!_holdsToken(token) || state.consentRequired) return;
    state = const SessionState(
      status: SessionStatus.authenticated,
      consentRequired: true,
    );
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
    await _closeSession();
    // 직접 로그아웃한 것이다 — 만료 안내가 남아 있었다면 거둔다.
    if (mounted) _ref.read(sessionExpiredNoticeProvider.notifier).state = false;
  }

  /// 저장된 토큰을 지우고, 회원별 화면 상태를 비우고, 로그인 화면으로 보낸다.
  ///
  /// 로그아웃과 실행 중 만료(#1546)가 함께 쓰는 마지막 단계다. 계정에 매인
  /// 기기 기록도 여기서 지운다(#3154). 이름공간 없던 옛 키도 지운다 — 남겨 두면
  /// 새로 고침이 그 토큰을 다시 복사해 로그인이 되살아난다(#3260).
  Future<void> _closeSession() async {
    try {
      await _ref.read(secureTokenStoreProvider).clear(forgetLegacy: true);
    } catch (_) {}
    await _forgetAccountRecords();
    if (!mounted) return;
    _setToken(null);
    _resetFeatureState();
    state = const SessionState(status: SessionStatus.signedOut);
  }

  // --- 실행 중 만료 (#1546) -------------------------------------------------

  /// 이 세션이 아직 [token] 으로 로그인해 있는가.
  ///
  /// 느린 갱신 중에 로그아웃했거나 다른 계정으로 로그인했다면 거짓이다 — 그때
  /// 뒤늦게 도착한 갱신 결과가 새 세션을 덮거나 끝내면 안 된다.
  bool _holdsToken(String token) =>
      mounted &&
      state.status == SessionStatus.authenticated &&
      _ref.read(authAccessTokenProvider) == token;

  /// [token] 으로 시작한 세션이 아직 이어지는가 — 그 사이 같은 세션 안에서
  /// 토큰이 회전됐어도 참이다(#3231). 로그아웃·다른 계정 로그인이면 거짓이다.
  bool _holdsSessionOf(String token) =>
      _holdsToken(token) ||
      (mounted &&
          state.status == SessionStatus.authenticated &&
          _rotatedTokens.contains(token));

  /// 실행 중 401 을 받은 뒤 갱신 토큰으로 한 번 회전한다.
  ///
  /// 복구([_refreshAndResolve])와 같은 기준을 쓴다: **명시적인 401/403 만 세션의
  /// 끝이다.** 연결 실패·5xx 는 저장된 토큰을 그대로 두고 원래 오류를 돌려준다 —
  /// 잠깐 끊긴 망 때문에 재로그인을 요구하지 않는다.
  @override
  Future<TokenRefreshResult> refreshAfterUnauthorized(String staleToken) async {
    if (!_holdsToken(staleToken)) {
      return const TokenRefreshResult.unavailable();
    }
    final String? refresh;
    try {
      refresh = await _ref.read(secureTokenStoreProvider).readRefreshToken();
    } catch (_) {
      return const TokenRefreshResult.unavailable();
    }
    if (!_holdsToken(staleToken)) {
      return const TokenRefreshResult.unavailable();
    }
    if (refresh == null || refresh.isEmpty) {
      // 접근 토큰은 거부됐고 회전할 수단이 없다 — 세션이 끝났다.
      await _endExpiredSession(staleToken);
      return const TokenRefreshResult.rejected();
    }

    final Map<String, Object?>? data;
    try {
      final res = await _ref
          .read(dioProvider)
          .post<Map<String, Object?>>(
            '/auth/refresh',
            data: <String, Object?>{'refresh_token': refresh},
          );
      data = res.data;
    } on DioException catch (e) {
      final int? code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        await _endExpiredSession(staleToken);
        return const TokenRefreshResult.rejected();
      }
      return const TokenRefreshResult.unavailable();
    } catch (_) {
      return const TokenRefreshResult.unavailable();
    }

    final String access = (data?['access_token'] as String?) ?? '';
    // 200 인데 토큰이 없다 — 서버 계약이 깨진 것이지 세션이 끝난 것이 아니다.
    if (access.isEmpty) return const TokenRefreshResult.unavailable();
    final String rotated = (data?['refresh_token'] as String?) ?? '';
    final String nextRefresh = rotated.isEmpty ? refresh : rotated;
    // 회전하는 사이 로그아웃·다른 계정 로그인이 있었다면 새 토큰을 버린다.
    if (!_holdsToken(staleToken)) {
      return const TokenRefreshResult.unavailable();
    }
    try {
      await _ref
          .read(secureTokenStoreProvider)
          .saveTokens(access: access, refresh: nextRefresh);
    } catch (_) {
      // 저장에 실패해도 이번 실행은 메모리 토큰으로 이어 간다.
    }
    if (!_holdsToken(staleToken)) {
      return const TokenRefreshResult.unavailable();
    }
    _setToken(access, rotated: true);
    return TokenRefreshResult.refreshed(access);
  }

  /// 갱신이 거부되었다 — 로그아웃과 같은 길로 세션을 닫고 로그인 화면에 안내를
  /// 띄운다.
  ///
  /// 서버는 이미 이 갱신 토큰을 받지 않으므로 폐기(`/auth/logout`)는 부르지 않는다.
  Future<void> _endExpiredSession(String staleToken) async {
    if (!_holdsToken(staleToken)) return;
    await _closeSession();
    if (!mounted) return;
    _ref.read(sessionExpiredNoticeProvider.notifier).state = true;
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

/// 서버 응답의 `consent_required` 를 읽는다. (#2819)
///
/// 칸이 없으면 거짓이다 — 동의 절차가 없던 서버를 상대할 때 막혀 들어가지 못하는
/// 쪽보다, 지금처럼 들어가는 쪽이 낫다. 서버가 동의를 요구하면 이 칸이 항상 있다.
bool consentRequiredIn(Map<String, Object?>? data) =>
    data?['consent_required'] == true;

/// `GET /users/me`·로그인 응답이 회원 계정인가. (#3054, #3137)
///
/// 칸이 없거나 비었으면 회원으로 본다 — 역할을 주지 않던 서버를 상대할 때
/// 막혀 들어가지 못하는 쪽보다 지금처럼 들어가는 쪽이 낫다. 서버는 트레이너
/// 토큰에 이 API 를 403 으로 거절하므로, 역할 칸은 그 위에 한 겹 더 두는 확인이다.
bool isMemberRole(Map<String, Object?>? data) {
  final Object? role = data?['role'];
  if (role is! String || role.isEmpty) return true;
  return role == 'member';
}

/// 방금 트레이너 계정으로 로그인하려 했다 — 로그인 화면이 트레이너 웹 안내를
/// 보인다. (#3137)
///
/// 토스트처럼 사라지면 회원이 다시 같은 계정으로 시도하게 된다. 다음 로그인
/// 시도까지 화면에 남긴다.
final trainerAccountNoticeProvider = StateProvider<bool>(
  (ref) => false,
  name: 'trainerAccountNotice',
);

/// 실행 중 세션이 만료되어 로그인 화면으로 보냈다 — 로그인 화면이 한 번 안내하고
/// 거둔다. (#1546)
///
/// 세션 상태에 넣지 않는 이유: 라우터가 세션 상태가 바뀔 때마다 가드를 다시
/// 계산한다. 안내를 거두는 일로 가드가 다시 돌 이유가 없다.
final sessionExpiredNoticeProvider = StateProvider<bool>(
  (ref) => false,
  name: 'sessionExpiredNotice',
);

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>(
      (ref) => SessionController(ref),
      name: 'session',
    );
