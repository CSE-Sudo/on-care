import 'dart:async';
import 'dart:js_interop';

import 'package:oncare_social_login/src/kakao_web_login.dart';
import 'package:web/web.dart' as web;

/// 브라우저 카카오 로그인 팝업(#330). 콜백 페이지는 `web/kakao_login_callback.html`.
class BrowserKakaoPopupPort implements KakaoPopupPort {
  const BrowserKakaoPopupPort();

  @override
  Uri callbackUri() =>
      Uri.parse(web.document.baseURI).resolve(kKakaoLoginCallbackPage);

  @override
  bool open(Uri url) {
    final web.Window? popup = web.window.open(
      url.toString(),
      'oncare-kakao-login',
      'popup,width=480,height=720',
    );
    return popup != null;
  }

  @override
  Stream<Object?> messages() => Stream<Object?>.multi((controller) {
    final web.BroadcastChannel channel = web.BroadcastChannel(
      kKakaoLoginChannel,
    );
    final StreamSubscription<web.MessageEvent> subscription = web
        .EventStreamProviders
        .messageEvent
        .forTarget(channel)
        .listen(
          (web.MessageEvent event) => controller.add(event.data.dartify()),
        );
    controller.onCancel = () async {
      await subscription.cancel();
      channel.close();
    };
  });
}

KakaoPopupPort createKakaoPopupPort() => const BrowserKakaoPopupPort();
