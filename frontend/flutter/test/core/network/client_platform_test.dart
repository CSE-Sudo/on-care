import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/network/client_platform.dart';

/// 웹 빌드가 서버에 자기가 웹이라고 알리는 헤더(#2828). 서버는 이 헤더를 보고
/// 웹 로그인에 짧은 refresh 토큰을 준다.
void main() {
  test('web builds tag every request as web', () {
    expect(clientPlatformHeaders(isWeb: true), <String, Object?>{
      'X-Client-Platform': 'web',
    });
  });

  test('mobile builds send no platform header', () {
    expect(clientPlatformHeaders(isWeb: false), isEmpty);
  });

  test('defaults to the current platform (VM tests are not web)', () {
    expect(clientPlatformHeaders(), isEmpty);
  });

  test('header name and value match the server contract', () {
    expect(kClientPlatformHeader, 'X-Client-Platform');
    expect(kClientPlatformWeb, 'web');
  });
}
