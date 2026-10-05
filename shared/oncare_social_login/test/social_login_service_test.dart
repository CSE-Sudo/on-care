import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_social_login/oncare_social_login.dart';

import 'fakes.dart';

const String _key = '0123456789abcdef0123456789abcdef';
const String _webId = '123-web.apps.googleusercontent.com';

void main() {
  late FakeGoogleGateway google;
  late FakeKakaoGateway kakao;
  late RecordingPopup popup;

  SocialLoginService service(
    SocialLoginPlatform platform, {
    SocialLoginConfig config = const SocialLoginConfig(
      kakaoNativeAppKey: _key,
      kakaoLoginRestApiKey: _key,
      googleWebClientId: _webId,
    ),
  }) => SocialLoginService(
    config: config,
    platform: platform,
    exchangeKakaoCode: (_, _) async => 'exchanged',
    kakaoGateway: kakao,
    kakaoPopup: popup,
    googleGateway: google,
  );

  setUp(() {
    google = FakeGoogleGateway();
    kakao = FakeKakaoGateway();
    popup = RecordingPopup();
  });

  tearDown(() async {
    await google.dispose();
    await popup.dispose();
  });

  test('모바일 카카오는 SDK 로', () async {
    final SocialLoginService s = service(SocialLoginPlatform.android);
    final SocialSignInResult r = await s.signIn(SocialLoginProvider.kakao);
    expect((r as SocialSignInSuccess).token, 'kakao-native-token');
    expect(popup.opened, isEmpty);
    expect(s.waitsInPopup(SocialLoginProvider.kakao), isFalse);
    expect(s.usesGoogleWebButton, isFalse);
  });

  test('웹 카카오는 팝업으로', () async {
    final SocialLoginService s = service(SocialLoginPlatform.web);
    expect(s.waitsInPopup(SocialLoginProvider.kakao), isTrue);
    expect(s.waitsInPopup(SocialLoginProvider.google), isFalse);
    final Future<SocialSignInResult> pending = s.signIn(
      SocialLoginProvider.kakao,
    );
    await pumpEventQueue();
    expect(popup.opened.single.host, 'kauth.kakao.com');
    expect(kakao.logins, 0);
    // 다음 시도가 앞의 것을 취소로 끝낸다.
    final Future<SocialSignInResult> next = s.signIn(SocialLoginProvider.kakao);
    expect(await pending, isA<SocialSignInCancelled>());
    expect(popup.opened, hasLength(2));
    // 팝업에서 동의하면 서버가 바꾼 토큰으로 끝난다.
    popup.messagesController.add(
      jsonEncode(<String, Object?>{
        'type': kKakaoLoginChannel,
        'state': popup.opened.last.queryParameters['state'],
        'code': 'auth-code',
      }),
    );
    expect(((await next) as SocialSignInSuccess).token, 'exchanged');
  });

  test('모바일 구글은 로그인 창으로', () async {
    final SocialSignInResult r = await service(
      SocialLoginPlatform.android,
    ).signIn(SocialLoginProvider.google);
    expect((r as SocialSignInSuccess).token, 'google-id-token');
  });

  test('웹 구글은 버튼', () {
    expect(service(SocialLoginPlatform.web).usesGoogleWebButton, isTrue);
  });

  test('켜진 provider 가 없으면 anyEnabled=false, signIn 은 notConfigured', () async {
    final SocialLoginService s = service(
      SocialLoginPlatform.ios,
      config: const SocialLoginConfig(),
    );
    expect(s.anyEnabled, isFalse);
    final SocialSignInResult r = await s.signIn(SocialLoginProvider.kakao);
    expect(
      (r as SocialSignInFailure).reason,
      SocialSignInFailureReason.notConfigured,
    );
  });

  test('provider 별로 켜진다', () {
    final SocialLoginService s = service(
      SocialLoginPlatform.android,
      config: const SocialLoginConfig(googleWebClientId: _webId),
    );
    expect(s.isEnabled(SocialLoginProvider.google), isTrue);
    expect(s.isEnabled(SocialLoginProvider.kakao), isFalse);
    expect(s.anyEnabled, isTrue);
  });

  testWidgets('웹이 아니면 구글 버튼 자리에 앱 버튼을 그대로 둔다', (tester) async {
    const Key placeholder = Key('placeholder');
    await tester.pumpWidget(
      MaterialApp(
        home: service(SocialLoginPlatform.android).googleWebButton(
          placeholder: const SizedBox(key: placeholder),
          size: 52,
        ),
      ),
    );
    expect(find.byKey(placeholder), findsOneWidget);
  });
}
