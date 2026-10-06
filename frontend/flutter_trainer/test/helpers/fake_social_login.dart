import 'dart:async';
import 'dart:convert';

import 'package:oncare_social_login/oncare_social_login.dart';

/// 테스트용 카카오 앱 키(형식만 맞춘 값).
const String kTestKakaoKey = '0123456789abcdef0123456789abcdef';

/// 테스트용 구글 웹 client_id(형식만 맞춘 값).
const String kTestGoogleWebClientId = '123-web.apps.googleusercontent.com';

/// 카카오 SDK 대신 — 정해 둔 결과를 돌려준다.
class FakeKakaoGateway implements KakaoNativeGateway {
  /// 던질 오류. null 이면 [token] 으로 성공한다.
  Object? error;
  String token = 'kakao-sdk-token';
  int logins = 0;

  @override
  Future<void> init(String nativeAppKey) async {}

  @override
  Future<bool> isKakaoTalkInstalled() async => false;

  @override
  Future<String> loginWithKakaoTalk() async => token;

  @override
  Future<String> loginWithKakaoAccount() async {
    logins++;
    if (error != null) throw error!;
    return token;
  }

  @override
  Future<void> clearToken() async {}
}

/// 구글 플러그인 대신.
class FakeGoogleGateway implements GoogleSignInGateway {
  Object? error;
  String idToken = 'google-id-token';
  final StreamController<String?> webEvents =
      StreamController<String?>.broadcast();

  @override
  Future<void> initialize({String? clientId, String? serverClientId}) async {}

  @override
  Future<String?> authenticate() async {
    if (error != null) throw error!;
    return idToken;
  }

  @override
  Stream<String?> signInIdTokens() => webEvents.stream;

  Future<void> dispose() => webEvents.close();
}

/// 브라우저 팝업 대신 — 연 주소를 기록하고, 콜백 메시지를 흉내 낸다.
class FakeKakaoPopup implements KakaoPopupPort {
  FakeKakaoPopup({this.allow = true});

  final bool allow;
  final List<Uri> opened = <Uri>[];
  final StreamController<Object?> callbacks =
      StreamController<Object?>.broadcast();

  @override
  Uri callbackUri() =>
      Uri.parse('https://app.test/trainer/$kKakaoLoginCallbackPage');

  @override
  bool open(Uri url) {
    opened.add(url);
    return allow;
  }

  @override
  Stream<Object?> messages() => callbacks.stream;

  /// 마지막으로 연 팝업이 [code] 를 받아 돌아온다.
  void approve(String code) => callbacks.add(
    jsonEncode(<String, Object?>{
      'type': kKakaoLoginChannel,
      'state': opened.last.queryParameters['state'],
      'code': code,
    }),
  );

  Future<void> dispose() => callbacks.close();
}
