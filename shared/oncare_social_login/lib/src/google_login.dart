import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';

import 'package:oncare_social_login/src/social_login_config.dart';
import 'package:oncare_social_login/src/social_sign_in_result.dart';

/// `google_sign_in` 호출만 모은 경계 — 테스트는 이걸 바꿔 끼운다.
abstract interface class GoogleSignInGateway {
  /// 한 번만 초기화한다(플러그인이 두 번째 초기화를 허용하지 않는다).
  Future<void> initialize({String? clientId, String? serverClientId});

  /// 모바일 로그인 창을 띄우고 ID 토큰을 돌려준다.
  Future<String?> authenticate();

  /// 웹 GIS 버튼으로 로그인할 때마다 ID 토큰이 들어온다. 실패는 스트림 오류로 온다.
  Stream<String?> signInIdTokens();
}

/// 실제 `google_sign_in` 플러그인.
class PluginGoogleSignInGateway implements GoogleSignInGateway {
  const PluginGoogleSignInGateway();

  // 앱 전체에서 하나 — 화면이 여러 번 만들어도 초기화는 한 번이다.
  static Future<void>? _initialized;

  @override
  Future<void> initialize({String? clientId, String? serverClientId}) {
    final Future<void> running = _initialized ??= GoogleSignIn.instance
        .initialize(clientId: clientId, serverClientId: serverClientId);
    // 실패했으면 다음 시도에서 다시 초기화한다.
    return running.catchError((Object e, StackTrace st) {
      if (identical(_initialized, running)) _initialized = null;
      return Future<void>.error(e, st);
    });
  }

  @override
  Future<String?> authenticate() async {
    final GoogleSignInAccount account = await GoogleSignIn.instance
        .authenticate();
    return account.authentication.idToken;
  }

  @override
  Stream<String?> signInIdTokens() => GoogleSignIn.instance.authenticationEvents
      .where((e) => e is GoogleSignInAuthenticationEventSignIn)
      .map(
        (e) => (e as GoogleSignInAuthenticationEventSignIn)
            .user
            .authentication
            .idToken,
      );
}

/// 사용자가 구글 로그인 창을 닫았는가(오류 안내를 띄우지 않는다).
bool isGoogleCancellation(Object error) =>
    error is GoogleSignInException &&
    (error.code == GoogleSignInExceptionCode.canceled ||
        error.code == GoogleSignInExceptionCode.interrupted);

/// 구글 로그인(#330) — 서버에는 ID 토큰을 보낸다.
///
/// - Android: 웹 client_id 를 `serverClientId` 로 넘긴다(ID 토큰 aud 가 웹 client_id).
///   Android client_id 는 콘솔에 패키지명·SHA-1 로 등록만 하면 된다.
/// - iOS: iOS client_id 를 `clientId`, 웹 client_id 를 `serverClientId` 로 넘긴다.
/// - 웹: 웹 client_id 를 `clientId` 로 넘기고, 로그인은 구글이 그리는 버튼(GIS)으로만
///   한다 — 웹 플러그인은 `authenticate()` 를 지원하지 않는다.
class GoogleLogin {
  GoogleLogin({
    required this.config,
    required this.platform,
    this.gateway = const PluginGoogleSignInGateway(),
  });

  final SocialLoginConfig config;
  final SocialLoginPlatform platform;
  final GoogleSignInGateway gateway;

  bool get isEnabled => config.isEnabled(SocialLoginProvider.google, platform);

  /// 플랫폼별 초기화. 설정이 없으면 아무것도 하지 않는다.
  Future<void> ensureInitialized() {
    if (!isEnabled) return Future<void>.value();
    return switch (platform) {
      SocialLoginPlatform.web => gateway.initialize(
        clientId: config.googleWebClientId,
      ),
      SocialLoginPlatform.ios => gateway.initialize(
        clientId: config.googleIosClientId,
        serverClientId: config.googleWebClientId,
      ),
      _ => gateway.initialize(serverClientId: config.googleWebClientId),
    };
  }

  /// 모바일 로그인. 웹은 [webResults] 를 쓴다.
  Future<SocialSignInResult> signIn() async {
    if (!isEnabled) {
      return const SocialSignInFailure(SocialSignInFailureReason.notConfigured);
    }
    if (platform == SocialLoginPlatform.web) {
      return const SocialSignInFailure(
        SocialSignInFailureReason.providerError,
        'web uses the Google button',
      );
    }
    try {
      await ensureInitialized();
      return _success(await gateway.authenticate());
    } on Object catch (e) {
      return googleErrorResult(e);
    }
  }

  /// 웹 GIS 버튼 로그인 결과. 화면이 떠 있는 동안 구독한다.
  Stream<SocialSignInResult> webResults() {
    if (!isEnabled || platform != SocialLoginPlatform.web) {
      return const Stream<SocialSignInResult>.empty();
    }
    late final StreamController<SocialSignInResult> controller;
    StreamSubscription<String?>? subscription;
    controller = StreamController<SocialSignInResult>(
      onListen: () {
        unawaited(
          ensureInitialized().then(
            (_) {
              if (controller.isClosed) return;
              subscription = gateway.signInIdTokens().listen(
                (token) => controller.add(_success(token)),
                onError: (Object e) => controller.add(googleErrorResult(e)),
              );
            },
            onError: (Object e) {
              if (!controller.isClosed) controller.add(googleErrorResult(e));
            },
          ),
        );
      },
      onCancel: () async {
        await subscription?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  static SocialSignInResult _success(String? idToken) =>
      idToken == null || idToken.isEmpty
      ? const SocialSignInFailure(
          SocialSignInFailureReason.providerError,
          'no id token',
        )
      : SocialSignInSuccess(SocialLoginProvider.google, idToken);
}

/// 구글 예외를 화면 갈래로 바꾼다.
SocialSignInResult googleErrorResult(Object error) =>
    isGoogleCancellation(error)
    ? const SocialSignInCancelled()
    : SocialSignInFailure(SocialSignInFailureReason.providerError, error);
