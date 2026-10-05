import 'package:oncare_social_login/src/kakao_web_login.dart';

/// 웹이 아닌 빌드 — 카카오 웹 로그인 팝업을 쓰지 않는다(모바일은 SDK).
class UnsupportedKakaoPopupPort implements KakaoPopupPort {
  const UnsupportedKakaoPopupPort();

  @override
  Uri callbackUri() => Uri.parse(kKakaoLoginCallbackPage);

  @override
  bool open(Uri url) => false;

  @override
  Stream<Object?> messages() => const Stream<Object?>.empty();
}

KakaoPopupPort createKakaoPopupPort() => const UnsupportedKakaoPopupPort();
