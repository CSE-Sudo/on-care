/// On-Care 회원 앱·트레이너 웹 공용 카카오·구글 로그인(#330).
library;

// 취소 판정에 쓰는 구글 예외 — 앱 테스트가 플러그인에 직접 의존하지 않게 내보낸다.
export 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignInException, GoogleSignInExceptionCode;
export 'package:oncare_social_login/src/google_login.dart'
    show GoogleSignInGateway, isGoogleCancellation;
export 'package:oncare_social_login/src/kakao_native_login.dart'
    show KakaoNativeGateway, isKakaoCancellation;
export 'package:oncare_social_login/src/kakao_web_login.dart'
    show
        KakaoCallbackMessage,
        KakaoCodeExchange,
        KakaoPopupPort,
        kKakaoLoginCallbackPage,
        kKakaoLoginChannel;
export 'package:oncare_social_login/src/social_login_config.dart';
export 'package:oncare_social_login/src/social_login_service.dart';
export 'package:oncare_social_login/src/social_sign_in_result.dart';
