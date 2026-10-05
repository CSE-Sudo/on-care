import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:oncare_social_login/src/social_login_config.dart';
import 'package:oncare_social_login/src/social_sign_in_result.dart';

/// 콜백 페이지와 앱이 같은 출처에서 주고받는 채널 이름(`web/kakao_login_callback.js`).
const String kKakaoLoginChannel = 'oncare-kakao-login';

/// 콜백 페이지 파일 이름. 앱의 `<base href>` 아래에 둔다(두 앱 `web/` 폴더).
const String kKakaoLoginCallbackPage = 'kakao_login_callback.html';

/// 카카오 인가 창 주소.
final Uri kKakaoAuthorizeEndpoint = Uri.parse(
  'https://kauth.kakao.com/oauth/authorize',
);

/// 서버가 인가 코드를 카카오 access_token 으로 바꿔 준다(`POST /auth/social/kakao/code`).
typedef KakaoCodeExchange =
    Future<String> Function(String code, String redirectUri);

/// 콜백 페이지가 보낸 메시지 하나.
@immutable
class KakaoCallbackMessage {
  const KakaoCallbackMessage({
    required this.state,
    this.code = '',
    this.error = '',
  });

  /// 콜백 페이지가 보낸 JSON 문자열을 읽는다. 우리 메시지가 아니면 null.
  static KakaoCallbackMessage? parse(Object? data) {
    if (data is! String) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final Map<String, Object?> fields = decoded;
    if (fields['type'] != kKakaoLoginChannel) return null;
    String text(String key) {
      final Object? value = fields[key];
      return value is String ? value : '';
    }

    final String state = text('state');
    if (state.isEmpty) return null;
    return KakaoCallbackMessage(
      state: state,
      code: text('code'),
      error: text('error'),
    );
  }

  final String state;
  final String code;

  /// 카카오가 돌려준 `error`(사용자가 동의를 거부하면 `access_denied`).
  final String error;
}

/// 브라우저 쪽 일 — 팝업 열기·콜백 받기. 웹 구현은 `kakao_web_popup_web.dart`.
abstract interface class KakaoPopupPort {
  /// 이 앱의 콜백 페이지 주소. 카카오 콘솔에 Redirect URI 로 등록한 값과 같아야 한다.
  Uri callbackUri();

  /// 인가 창을 팝업으로 연다. 브라우저가 막으면 false.
  bool open(Uri url);

  /// 콜백 페이지가 보낸 메시지(구독하는 동안만 듣는다).
  Stream<Object?> messages();
}

/// 웹 카카오 로그인 — 인가 코드 팝업 + 서버 교환(#330).
///
/// 카카오 Flutter SDK 는 웹 로그인을 지원하지 않는다. 카카오 인가 창을 팝업으로 열고,
/// 같은 출처의 콜백 페이지가 받은 인가 코드를 `BroadcastChannel` 로 돌려준다. 앱은 그
/// 코드를 서버에 보내 카카오 access_token 으로 바꾸고, 모바일과 같은
/// `POST /auth/social/kakao` 로 로그인한다.
///
/// - 팝업이라 화면(본인 확인 창 포함)을 떠나지 않고, 외부 스크립트를 싣지 않는다.
/// - `state` 를 매번 새로 만들어 다른 창·지난 시도의 코드를 받지 않는다.
/// - 팝업이 닫혔는지는 보지 않는다. 카카오 페이지가 opener 를 끊으면(COOP) 열려 있어도
///   닫힌 것으로 보이기 때문이다. 대신 기다리는 동안 화면을 막지 않고, 다시 누르면
///   지난 시도를 취소로 끝내고 새로 연다. [timeout] 이 지나면 취소다.
class KakaoWebLogin {
  KakaoWebLogin({
    required this.restApiKey,
    required this.port,
    required this.exchangeCode,
    Random? random,
    this.timeout = const Duration(minutes: 10),
  }) : _random = random ?? Random.secure();

  final String restApiKey;
  final KakaoPopupPort port;
  final KakaoCodeExchange exchangeCode;
  final Duration timeout;
  final Random _random;

  _PendingKakaoLogin? _pending;

  /// 인가 창 주소. [state] 는 콜백에서 그대로 돌아온다.
  Uri authorizeUrl({required Uri redirectUri, required String state}) =>
      kKakaoAuthorizeEndpoint.replace(
        queryParameters: <String, String>{
          'client_id': restApiKey,
          'redirect_uri': redirectUri.toString(),
          'response_type': 'code',
          'state': state,
        },
      );

  /// 로그인한다. [onAuthorized] 는 사용자가 카카오에서 동의를 마쳐 서버 교환을
  /// 시작할 때 부른다 — 그때부터 화면이 진행 중 표시를 한다.
  Future<SocialSignInResult> signIn({VoidCallback? onAuthorized}) async {
    if (!SocialLoginConfig.isKakaoAppKey(restApiKey)) {
      return const SocialSignInFailure(SocialSignInFailureReason.notConfigured);
    }
    _pending?.finish(const SocialSignInCancelled());

    final Uri redirectUri = port.callbackUri();
    final String state = _newState();
    final _PendingKakaoLogin pending = _PendingKakaoLogin(state);
    _pending = pending;

    pending.subscription = port.messages().listen((Object? data) {
      final KakaoCallbackMessage? message = KakaoCallbackMessage.parse(data);
      if (message == null || message.state != state) return;
      // 같은 코드가 두 번 오더라도 한 번만 바꾼다.
      if (pending.done || pending.claimed) return;
      pending.claimed = true;
      unawaited(
        _handle(message, redirectUri, pending, onAuthorized: onAuthorized),
      );
    });
    pending.timer = Timer(
      timeout,
      () => pending.finish(const SocialSignInCancelled()),
    );

    if (!port.open(authorizeUrl(redirectUri: redirectUri, state: state))) {
      pending.finish(
        const SocialSignInFailure(SocialSignInFailureReason.popupBlocked),
      );
    }
    final SocialSignInResult result = await pending.completer.future;
    if (identical(_pending, pending)) _pending = null;
    return result;
  }

  Future<void> _handle(
    KakaoCallbackMessage message,
    Uri redirectUri,
    _PendingKakaoLogin pending, {
    VoidCallback? onAuthorized,
  }) async {
    // 더 받을 메시지가 없고, 서버 교환 중에는 시간 제한으로 끊지 않는다.
    pending
      ..stopListening()
      ..timer?.cancel();
    if (message.error.isNotEmpty || message.code.isEmpty) {
      // 동의 화면에서 '취소'·'동의하지 않음'은 사용자가 그만둔 것이다.
      pending.finish(
        message.error == 'access_denied' || message.code.isEmpty
            ? const SocialSignInCancelled()
            : SocialSignInFailure(
                SocialSignInFailureReason.providerError,
                'kakao authorize error: ${message.error}',
              ),
      );
      return;
    }
    onAuthorized?.call();
    try {
      final String token = await exchangeCode(
        message.code,
        redirectUri.toString(),
      );
      pending.finish(
        token.isEmpty
            ? const SocialSignInFailure(SocialSignInFailureReason.providerError)
            : SocialSignInSuccess(SocialLoginProvider.kakao, token),
      );
    } on Object catch (e) {
      pending.finish(
        SocialSignInFailure(SocialSignInFailureReason.providerError, e),
      );
    }
  }

  String _newState() {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < 32; i++) {
      out.write(_random.nextInt(16).toRadixString(16));
    }
    return out.toString();
  }
}

class _PendingKakaoLogin {
  _PendingKakaoLogin(this.state);

  final String state;
  final Completer<SocialSignInResult> completer =
      Completer<SocialSignInResult>();
  StreamSubscription<Object?>? subscription;
  Timer? timer;

  /// 이 시도의 콜백을 이미 받아 처리 중이다.
  bool claimed = false;

  bool get done => completer.isCompleted;

  void stopListening() {
    unawaited(subscription?.cancel());
    subscription = null;
  }

  void finish(SocialSignInResult result) {
    timer?.cancel();
    stopListening();
    if (!completer.isCompleted) completer.complete(result);
  }
}
