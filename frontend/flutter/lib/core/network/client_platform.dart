import 'package:flutter/foundation.dart';

/// 요청을 보낸 클라이언트 종류를 서버에 알리는 헤더(#2828).
///
/// 서버는 웹(`web`)에서 온 로그인·토큰 회전에 더 짧은 refresh 토큰을 준다 — 웹은
/// 토큰을 탭 단위 저장소에 두므로 오래 갈 필요가 없고, 새어 나갔을 때 쓸 수 있는
/// 기간이 짧을수록 좋다. 모바일은 헤더를 보내지 않아 지금 수명을 그대로 쓴다.
const String kClientPlatformHeader = 'X-Client-Platform';

/// 웹 빌드가 [kClientPlatformHeader] 에 싣는 값.
const String kClientPlatformWeb = 'web';

/// 모든 요청에 붙일 기본 헤더. [isWeb] 은 테스트에서 웹 분기를 보려고 연다.
Map<String, Object?> clientPlatformHeaders({bool isWeb = kIsWeb}) =>
    <String, Object?>{if (isWeb) kClientPlatformHeader: kClientPlatformWeb};
