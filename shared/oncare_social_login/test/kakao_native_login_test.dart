import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:oncare_social_login/oncare_social_login.dart';
import 'package:oncare_social_login/src/kakao_native_login.dart';

const String _key = '0123456789abcdef0123456789abcdef';

class _FakeKakao implements KakaoNativeGateway {
  bool talkInstalled = true;
  Object? initError;
  Object? talkError;
  Object? accountError;
  String talkToken = 'talk-token';
  String accountToken = 'account-token';
  Object? clearError;

  final List<String> calls = <String>[];

  @override
  Future<void> init(String nativeAppKey) async {
    calls.add('init:$nativeAppKey');
    if (initError != null) throw initError!;
  }

  @override
  Future<bool> isKakaoTalkInstalled() async => talkInstalled;

  @override
  Future<String> loginWithKakaoTalk() async {
    calls.add('talk');
    if (talkError != null) throw talkError!;
    return talkToken;
  }

  @override
  Future<String> loginWithKakaoAccount() async {
    calls.add('account');
    if (accountError != null) throw accountError!;
    return accountToken;
  }

  @override
  Future<void> clearToken() async {
    calls.add('clear');
    if (clearError != null) throw clearError!;
  }
}

void main() {
  late _FakeKakao fake;
  late KakaoNativeLogin login;

  setUp(() {
    fake = _FakeKakao();
    login = KakaoNativeLogin(nativeAppKey: _key, gateway: fake);
  });

  test('카카오톡이 있으면 카카오톡으로 로그인하고 토큰을 지운다', () async {
    final SocialSignInResult r = await login.signIn();
    expect((r as SocialSignInSuccess).token, 'talk-token');
    expect(fake.calls, <String>['init:$_key', 'talk', 'clear']);
  });

  test('카카오톡이 없으면 카카오계정으로', () async {
    fake.talkInstalled = false;
    final SocialSignInResult r = await login.signIn();
    expect((r as SocialSignInSuccess).token, 'account-token');
    expect(fake.calls, <String>['init:$_key', 'account', 'clear']);
  });

  test('카카오톡 로그인 오류면 카카오계정으로 넘어간다', () async {
    fake.talkError = kakao.KakaoClientException(
      kakao.ClientErrorCause.unknown,
      'not logged in',
    );
    final SocialSignInResult r = await login.signIn();
    expect((r as SocialSignInSuccess).token, 'account-token');
    expect(fake.calls, contains('account'));
  });

  test('카카오톡에서 취소하면 계정 화면을 띄우지 않는다', () async {
    fake.talkError = PlatformException(code: 'CANCELED');
    final SocialSignInResult r = await login.signIn();
    expect(r, isA<SocialSignInCancelled>());
    expect(fake.calls, isNot(contains('account')));
    expect(fake.calls.last, 'clear');
  });

  test('계정 화면에서 취소·동의 거부는 취소다', () async {
    fake.talkInstalled = false;
    fake.accountError = kakao.KakaoClientException(
      kakao.ClientErrorCause.cancelled,
      'user cancelled',
    );
    expect(await login.signIn(), isA<SocialSignInCancelled>());

    fake.accountError = kakao.KakaoAuthException(
      kakao.AuthErrorCause.accessDenied,
      'denied',
    );
    expect(await login.signIn(), isA<SocialSignInCancelled>());
  });

  test('그 밖의 오류는 providerError', () async {
    fake.talkInstalled = false;
    fake.accountError = kakao.KakaoAuthException(
      kakao.AuthErrorCause.invalidClient,
      'bad key',
    );
    final SocialSignInResult r = await login.signIn();
    expect(
      (r as SocialSignInFailure).reason,
      SocialSignInFailureReason.providerError,
    );
  });

  test('빈 토큰은 실패다', () async {
    fake.talkToken = '';
    expect(await login.signIn(), isA<SocialSignInFailure>());
  });

  test('토큰 지우기 실패는 결과를 바꾸지 않는다', () async {
    fake.clearError = StateError('storage');
    expect(await login.signIn(), isA<SocialSignInSuccess>());
  });

  test('초기화는 한 번만, 실패하면 다음에 다시', () async {
    fake.initError = StateError('init');
    expect(await login.signIn(), isA<SocialSignInFailure>());
    fake.initError = null;
    expect(await login.signIn(), isA<SocialSignInSuccess>());
    expect(await login.signIn(), isA<SocialSignInSuccess>());
    expect(fake.calls.where((c) => c.startsWith('init')), hasLength(2));
  });

  test('키가 없으면 SDK 를 부르지 않는다', () async {
    final SocialSignInResult r = await KakaoNativeLogin(
      nativeAppKey: '',
      gateway: fake,
    ).signIn();
    expect(
      (r as SocialSignInFailure).reason,
      SocialSignInFailureReason.notConfigured,
    );
    expect(fake.calls, isEmpty);
  });

  test('취소 판정', () {
    expect(isKakaoCancellation(PlatformException(code: 'CANCELED')), isTrue);
    expect(isKakaoCancellation(PlatformException(code: 'ERROR')), isFalse);
    expect(isKakaoCancellation(StateError('x')), isFalse);
  });
}
