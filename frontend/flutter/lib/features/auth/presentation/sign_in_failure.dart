import 'package:dio/dio.dart';

import 'package:oncare/gen/l10n/app_localizations.dart';

/// 로그인이 실패한 까닭 — 회원에게 무엇을 하라고 말할지가 갈린다. (#1940)
///
/// 예전에는 모든 실패를 하나로 받아 "이메일·비밀번호를 확인해 주세요" 를 띄웠다.
/// 망이 끊겼거나 서버가 멈춰도 비밀번호 탓을 해서, 회원이 멀쩡한 비밀번호를
/// 재설정하러 갔다.
enum SignInFailure {
  /// 서버가 자격 증명을 거절했다(401·403). 이메일·비밀번호를 다시 본다.
  credentials,

  /// 서버에 닿지 못했다 — 연결 끊김·타임아웃·비행기 모드. 연결을 보고 다시 한다.
  network,

  /// 서버에 닿았지만 로그인을 처리하지 못했다 — 5xx·시도 제한(429) 등. 잠시 뒤
  /// 다시 한다. 비밀번호가 틀렸다는 말이 아니다.
  unavailable,
}

/// [error] 가 어느 실패인지. 로그인은 `DioException` 을 그대로 던진다.
///
/// 응답이 없으면 망 문제로 본다 — 비행기 모드는 플랫폼에 따라 연결 오류로도,
/// 알 수 없는 오류로도 오지만 어느 쪽이든 응답이 없다. 응답이 있으면 상태코드로
/// 가른다. 그 밖의 예외(토큰 없는 응답 등)는 회원이 고칠 수 없으니 [unavailable].
SignInFailure signInFailureOf(Object error) {
  if (error is! DioException) return SignInFailure.unavailable;
  if (error.type == DioExceptionType.cancel) return SignInFailure.unavailable;
  final int? status = error.response?.statusCode;
  if (status == null) return SignInFailure.network;
  if (status == 401 || status == 403) return SignInFailure.credentials;
  return SignInFailure.unavailable;
}

/// 실패마다 띄우는 문구.
String signInFailureText(AppLocalizations l, SignInFailure failure) =>
    switch (failure) {
      SignInFailure.credentials => l.authSignInFailed,
      SignInFailure.network => l.authSignInNetworkFailed,
      SignInFailure.unavailable => l.authSignInUnavailable,
    };
