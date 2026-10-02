import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/network/auth_interceptor.dart';
import 'package:oncare_core/network/session_refresh.dart';

/// The current access token, mirrored here (a leaf provider) so the
/// [AuthInterceptor] can read it synchronously without importing the auth
/// feature (avoids a dio_client ↔ session_controller import cycle). The
/// [SessionController] writes it on login/restore and clears it on
/// sign-out.
final authAccessTokenProvider = StateProvider<String?>(
  (ref) => null,
  name: 'authAccessToken',
);

/// 앱 전체가 함께 쓰는 [SessionRefreshBridge].
///
/// 브리지 자체는 공용 패키지(`oncare_core`)에 있고, 앱마다 하나를 두는 이
/// provider 만 앱에 남긴다(#2907).
final sessionRefreshBridgeProvider = Provider<SessionRefreshBridge>(
  (ref) => SessionRefreshBridge(),
  name: 'sessionRefreshBridge',
);

/// 이 앱의 토큰·갱신 브리지 provider 로 조립한 공용 [AuthInterceptor].
///
/// 둘 다 요청·오류마다 [ref] 에서 새로 읽는다 — 로그인·로그아웃·갱신이 토큰을
/// 바꿔도 인터셉터를 다시 만들지 않는다. 로그인 → `/trainer/me` 처럼 토큰을
/// 세션에 넣기 전에 직접 헤더를 넣은 요청은 덮지 않는다. [retryClient] 가 없으면
/// 헤더만 붙인다.
AuthInterceptor authInterceptorFor(Ref ref, {Dio? retryClient}) =>
    AuthInterceptor(
      accessToken: () => ref.read(authAccessTokenProvider),
      refreshBridge: () => ref.read(sessionRefreshBridgeProvider),
      retryClient: retryClient,
    );
