import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_social_login/oncare_social_login.dart';
import 'package:oncare_social_login/src/kakao_web_login.dart';

const String _restKey = '0123456789abcdef0123456789abcdef';
final Uri _callback = Uri.parse(
  'https://app.example.com/frontend/kakao_login_callback.html',
);

class _FakePort implements KakaoPopupPort {
  _FakePort({this.allowPopup = true});

  final bool allowPopup;
  final List<Uri> opened = <Uri>[];
  final StreamController<Object?> _messages =
      StreamController<Object?>.broadcast();
  int listeners = 0;

  @override
  Uri callbackUri() => _callback;

  @override
  bool open(Uri url) {
    opened.add(url);
    return allowPopup;
  }

  @override
  Stream<Object?> messages() {
    listeners++;
    return _messages.stream;
  }

  String get lastState => opened.last.queryParameters['state']!;

  void send(Map<String, Object?> body) => _messages.add(
    jsonEncode(<String, Object?>{'type': kKakaoLoginChannel, ...body}),
  );

  bool get hasListener => _messages.hasListener;
}

void main() {
  late _FakePort port;
  late List<(String, String)> exchanged;
  late Future<String> Function(String, String) exchange;

  KakaoWebLogin login({Duration timeout = const Duration(minutes: 10)}) =>
      KakaoWebLogin(
        restApiKey: _restKey,
        port: port,
        exchangeCode: (code, redirect) {
          exchanged.add((code, redirect));
          return exchange(code, redirect);
        },
        random: Random(7),
        timeout: timeout,
      );

  setUp(() {
    port = _FakePort();
    exchanged = <(String, String)>[];
    exchange = (_, _) async => 'kakao-access-token';
  });

  test('인가 창 주소에 REST 키·콜백·code·state 를 담는다', () {
    final Uri url = login().authorizeUrl(redirectUri: _callback, state: 'abc');
    expect(url.host, 'kauth.kakao.com');
    expect(url.path, '/oauth/authorize');
    expect(url.queryParameters, <String, String>{
      'client_id': _restKey,
      'redirect_uri': _callback.toString(),
      'response_type': 'code',
      'state': 'abc',
    });
  });

  test('코드를 받으면 서버에서 바꿔 access_token 으로 성공한다', () async {
    int authorized = 0;
    final Future<SocialSignInResult> result = login().signIn(
      onAuthorized: () => authorized++,
    );
    expect(port.opened, hasLength(1));
    expect(port.lastState, hasLength(32));

    port.send(<String, Object?>{'code': 'auth-code', 'state': port.lastState});

    final SocialSignInResult r = await result;
    expect(r, isA<SocialSignInSuccess>());
    expect((r as SocialSignInSuccess).token, 'kakao-access-token');
    expect(r.provider, SocialLoginProvider.kakao);
    expect(authorized, 1);
    expect(exchanged, <(String, String)>[('auth-code', _callback.toString())]);
    expect(port.hasListener, isFalse);
  });

  test('state 가 다르거나 우리 메시지가 아니면 무시한다', () async {
    final Future<SocialSignInResult> result = login().signIn();
    final String state = port.lastState;

    port
      ..send(<String, Object?>{'code': 'stolen', 'state': 'other-state'})
      .._messages.add('not json')
      .._messages.add(
        jsonEncode(<String, Object?>{'type': 'x', 'state': state}),
      )
      .._messages.add(42)
      ..send(<String, Object?>{'code': 'mine', 'state': state});

    final SocialSignInResult r = await result;
    expect(r, isA<SocialSignInSuccess>());
    expect(exchanged.single.$1, 'mine');
  });

  test('같은 코드가 두 번 와도 한 번만 바꾼다', () async {
    final Completer<String> slow = Completer<String>();
    exchange = (_, _) => slow.future;
    final Future<SocialSignInResult> result = login().signIn();
    final String state = port.lastState;

    port
      ..send(<String, Object?>{'code': 'c', 'state': state})
      ..send(<String, Object?>{'code': 'c', 'state': state});
    await Future<void>.delayed(Duration.zero);
    slow.complete('t');

    expect(await result, isA<SocialSignInSuccess>());
    expect(exchanged, hasLength(1));
  });

  test('동의 거부(access_denied)는 취소다', () async {
    final Future<SocialSignInResult> result = login().signIn();
    port.send(<String, Object?>{
      'error': 'access_denied',
      'state': port.lastState,
    });
    expect(await result, isA<SocialSignInCancelled>());
    expect(exchanged, isEmpty);
  });

  test('그 밖의 카카오 오류는 실패다', () async {
    final Future<SocialSignInResult> result = login().signIn();
    port.send(<String, Object?>{
      'error': 'server_error',
      'state': port.lastState,
    });
    final SocialSignInResult r = await result;
    expect(r, isA<SocialSignInFailure>());
    expect(
      (r as SocialSignInFailure).reason,
      SocialSignInFailureReason.providerError,
    );
  });

  test('팝업이 막히면 popupBlocked', () async {
    port = _FakePort(allowPopup: false);
    final SocialSignInResult r = await login().signIn();
    expect(
      (r as SocialSignInFailure).reason,
      SocialSignInFailureReason.popupBlocked,
    );
    expect(port.hasListener, isFalse);
  });

  test('서버 교환이 실패하면 providerError', () async {
    exchange = (_, _) async => throw StateError('401');
    final Future<SocialSignInResult> result = login().signIn();
    port.send(<String, Object?>{'code': 'c', 'state': port.lastState});
    final SocialSignInResult r = await result;
    expect(
      (r as SocialSignInFailure).reason,
      SocialSignInFailureReason.providerError,
    );
  });

  test('서버가 빈 토큰을 주면 실패다', () async {
    exchange = (_, _) async => '';
    final Future<SocialSignInResult> result = login().signIn();
    port.send(<String, Object?>{'code': 'c', 'state': port.lastState});
    expect(await result, isA<SocialSignInFailure>());
  });

  test('다시 누르면 지난 시도는 취소로 끝나고 새 state 로 연다', () async {
    final KakaoWebLogin web = login();
    final Future<SocialSignInResult> first = web.signIn();
    final String firstState = port.lastState;
    final Future<SocialSignInResult> second = web.signIn();
    final String secondState = port.lastState;

    expect(await first, isA<SocialSignInCancelled>());
    expect(secondState, isNot(firstState));

    port.send(<String, Object?>{'code': 'old', 'state': firstState});
    port.send(<String, Object?>{'code': 'new', 'state': secondState});
    expect(await second, isA<SocialSignInSuccess>());
    expect(exchanged.single.$1, 'new');
  });

  test('시간이 지나면 취소로 끝난다', () async {
    final SocialSignInResult r = await login(
      timeout: const Duration(milliseconds: 20),
    ).signIn();
    expect(r, isA<SocialSignInCancelled>());
    expect(port.hasListener, isFalse);
  });

  test('REST 키가 없으면 팝업을 열지 않는다', () async {
    final SocialSignInResult r = await KakaoWebLogin(
      restApiKey: '',
      port: port,
      exchangeCode: (_, _) async => 't',
    ).signIn();
    expect(
      (r as SocialSignInFailure).reason,
      SocialSignInFailureReason.notConfigured,
    );
    expect(port.opened, isEmpty);
    expect(port.listeners, 0);
  });

  group('KakaoCallbackMessage.parse', () {
    test('우리 메시지만 읽는다', () {
      final KakaoCallbackMessage? m = KakaoCallbackMessage.parse(
        jsonEncode(<String, Object?>{
          'type': kKakaoLoginChannel,
          'state': 's',
          'code': 'c',
          'error': null,
        }),
      );
      expect(m?.state, 's');
      expect(m?.code, 'c');
      expect(m?.error, '');
    });

    test('state 가 없거나 형식이 다르면 null', () {
      expect(KakaoCallbackMessage.parse(null), isNull);
      expect(KakaoCallbackMessage.parse('[1]'), isNull);
      expect(KakaoCallbackMessage.parse('{'), isNull);
      expect(
        KakaoCallbackMessage.parse(
          jsonEncode(<String, Object?>{'type': kKakaoLoginChannel}),
        ),
        isNull,
      );
    });
  });
}
