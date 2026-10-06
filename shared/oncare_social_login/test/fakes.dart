import 'dart:async';

import 'package:oncare_social_login/oncare_social_login.dart';

/// 테스트용 구글 플러그인 경계.
class FakeGoogleGateway implements GoogleSignInGateway {
  final List<(String?, String?)> initCalls = <(String?, String?)>[];
  Object? initError;
  Object? authError;
  String? idToken = 'google-id-token';
  final StreamController<String?> events =
      StreamController<String?>.broadcast();

  @override
  Future<void> initialize({String? clientId, String? serverClientId}) async {
    initCalls.add((clientId, serverClientId));
    if (initError != null) throw initError!;
  }

  @override
  Future<String?> authenticate() async {
    if (authError != null) throw authError!;
    return idToken;
  }

  @override
  Stream<String?> signInIdTokens() => events.stream;

  Future<void> dispose() => events.close();
}

/// 테스트용 카카오 SDK 경계 — 항상 같은 토큰.
class FakeKakaoGateway implements KakaoNativeGateway {
  int logins = 0;

  @override
  Future<void> init(String nativeAppKey) async {}

  @override
  Future<bool> isKakaoTalkInstalled() async => false;

  @override
  Future<String> loginWithKakaoTalk() async => 'talk';

  @override
  Future<String> loginWithKakaoAccount() async {
    logins++;
    return 'kakao-native-token';
  }

  @override
  Future<void> clearToken() async {}
}

/// 테스트용 팝업 — 열기만 기록한다.
class RecordingPopup implements KakaoPopupPort {
  final List<Uri> opened = <Uri>[];
  final StreamController<Object?> messagesController =
      StreamController<Object?>.broadcast();

  @override
  Uri callbackUri() => Uri.parse('https://a.example/kakao_login_callback.html');

  @override
  bool open(Uri url) {
    opened.add(url);
    return true;
  }

  @override
  Stream<Object?> messages() => messagesController.stream;

  Future<void> dispose() => messagesController.close();
}
