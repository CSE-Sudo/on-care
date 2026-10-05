import 'dart:async';

import 'package:dio/dio.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/utils/server_message.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 오류에 맞는 **공통** 안내 문구. (#2859, #3140)
///
/// 화면마다 상태 코드를 다시 해석하지 않도록, 어느 화면에서 나도 같은 뜻인
/// 오류만 여기서 문구를 정한다.
/// - [ValidationError](400·422) — 보낸 값이 거절됐다. 서버 사유가 가장 정확하므로
///   한국어 화면에서는 그것을, 아니면 화면이 준 [fallback] 을 쓴다.
/// - 나머지는 [appErrorCauseMessage] 가 고른 원인별 문구다. 원인을 가릴 수 없는
///   오류(404·409·알 수 없는 오류 등)만 [fallback] 으로 떨어진다.
String appErrorMessage(
  AppLocalizations l,
  Object error, {
  required String fallback,
}) {
  final Object resolved = _resolve(error);
  if (resolved is ValidationError) {
    return serverDetailOr(l, resolved.detail, fallback);
  }
  return appErrorCauseMessage(l, resolved) ?? fallback;
}

/// 오류의 **원인**을 회원이 할 일로 옮긴 문구. 가릴 수 없으면 null 이다. (#3140)
///
/// 오류 화면이 원인과 상관없이 같은 문구를 보이면, 회원은 [다시 시도] 가 의미
/// 있는지 알 수 없다 — 연결이 끊긴 것이면 연결을 확인하면 되고, 동의 문제면
/// 몇 번을 다시 해도 같다. 그래서 할 일이 다른 원인끼리 문구를 가른다.
/// - [NetworkError]·[TimeoutException] — 연결 끊김·시간 초과. 연결을 확인한다.
/// - [UnauthorizedError](401) — 로그인이 끝났다. 다시 로그인한다. 로그인 화면으로
///   보내는 일은 세션 만료 흐름이 맡고, 여기서는 왜 실패했는지만 말한다.
/// - [ForbiddenError](403) — 로그인 문제가 아니라 권한·동의 문제다. 서버가 준
///   사유가 있으면 한국어 화면에서 그 사유를, 아니면 앱 문구를 쓴다.
/// - [RateLimitedError](429) — 잠시 뒤에는 된다. 서버 사유보다 "잠시 뒤 다시"
///   라는 행동 안내가 중요해 앱 문구를 쓴다.
/// - [ValidationError](400·422) — 보낸 값이 거절됐다. 한국어 화면에서는 서버
///   사유를, 아니면 요청을 확인하라는 앱 문구를 쓴다.
/// - 5xx [ServerError] — 서버 쪽 일시 문제. 회원이 고칠 것이 없으니 조금 뒤에
///   다시 하도록 안내한다.
///
/// 처리 전 [DioException] 이 그대로 올라와도 같은 규칙으로 읽는다 — 저장소가
/// 감싸지 않은 경로 하나 때문에 문구가 일반 문구로 돌아가면 안 된다.
String? appErrorCauseMessage(AppLocalizations l, Object? error) {
  if (error == null) return null;
  return switch (_resolve(error)) {
    NetworkError() || TimeoutException() => l.errorNetwork,
    UnauthorizedError() => l.authSessionExpired,
    ForbiddenError(:final String? detail) => serverDetailOr(
      l,
      detail,
      l.errorForbidden,
    ),
    RateLimitedError() => l.errorRateLimited,
    ValidationError(:final String? detail) => serverDetailOr(
      l,
      detail,
      l.errorInvalidRequest,
    ),
    ServerError(:final int? statusCode)
        when statusCode != null && statusCode >= 500 =>
      l.errorServer,
    _ => null,
  };
}

/// [DioException] 은 앱 공통 오류로 옮겨 읽는다. 나머지는 그대로다.
Object _resolve(Object error) =>
    error is DioException ? AppError.fromDio(error) : error;
