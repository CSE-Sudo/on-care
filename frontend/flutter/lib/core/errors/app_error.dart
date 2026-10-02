import 'package:dio/dio.dart';

/// Domain-level error type for the whole app. Repositories convert
/// any transport / framework exception into one of these before
/// surfacing it to controllers, so UI code never has to type-test
/// `DioException` etc. directly.
sealed class AppError {
  const AppError({this.message, this.detail, this.cause, this.stackTrace});

  /// 기록용 설명. 서버 사유([detail])가 있으면 그것이고, 없으면 Dio 의 기술
  /// 문구(영어)다 — 그래서 화면에 바로 쓰지 않는다.
  final String? message;

  /// 서버가 응답 본문 `detail` 에 **문자열로** 준 사유(#2859). 백엔드는 이 사유를
  /// 한국어로만 준다. 화면은 `serverDetailOr` 로 한국어 화면에서만 쓴다.
  /// FastAPI 스키마 검증의 목록형 `detail` 이나 본문이 없는 응답이면 null 이다.
  final String? detail;

  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType(message: $message)';

  /// Map a `DioException` into the closest AppError. Add new branches
  /// here rather than at call sites.
  ///
  /// 상태 코드는 "다시 하면 되는가, 무엇을 하면 되는가" 로 나눈다(#2859).
  /// - 401 → [UnauthorizedError]: 로그인이 끝났다. 다시 로그인한다.
  /// - 403 → [ForbiddenError]: 로그인은 유효한데 이 기능을 쓸 권한·동의가 없다.
  ///   다시 로그인해도 같은 403 이라 로그인으로 안내하면 안 된다.
  /// - 400·422 → [ValidationError]: 보낸 값이 거절됐다. 같은 값으로 다시 해도
  ///   소용없다.
  /// - 429 → [RateLimitedError]: 잠시 뒤에는 된다.
  /// - 나머지(409·5xx 등) → [ServerError] 가 상태 코드를 그대로 들고 간다.
  factory AppError.fromDio(DioException e) {
    final String? detail = serverDetailOf(e.response?.data);
    final String? message = detail ?? e.message;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return NetworkError(
          message: message,
          cause: e,
          stackTrace: e.stackTrace,
        );
      case DioExceptionType.cancel:
        return const CancelledError();
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code == 401) {
          return UnauthorizedError(message: message, detail: detail);
        }
        if (code == 403) {
          return ForbiddenError(message: message, detail: detail);
        }
        if (code == 404) {
          return NotFoundError(message: message, detail: detail);
        }
        if (code == 429) {
          return RateLimitedError(message: message, detail: detail);
        }
        if (code == 400 || code == 422) {
          return ValidationError(
            statusCode: code,
            message: message,
            detail: detail,
          );
        }
        return ServerError(statusCode: code, message: message, detail: detail);
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return UnknownError(
          message: message,
          cause: e,
          stackTrace: e.stackTrace,
        );
    }
  }
}

class NetworkError extends AppError {
  const NetworkError({super.message, super.cause, super.stackTrace});
}

/// 401 — 로그인이 없거나 끝났다. 다시 로그인하는 것이 답이다.
class UnauthorizedError extends AppError {
  const UnauthorizedError({super.message, super.detail});
}

/// 403 — 로그인은 유효한데 이 기능을 쓸 권한·동의가 없다(#2859). 다시
/// 로그인해도 같은 응답이라, 화면은 로그인이 아니라 권한·동의를 안내한다.
class ForbiddenError extends AppError {
  const ForbiddenError({super.message, super.detail});
}

class NotFoundError extends AppError {
  const NotFoundError({super.message, super.detail});
}

/// 400 / 422 — 요청은 닿았고 **보낸 값**이 거절됐다(#2859). 같은 값으로 다시
/// 해도 소용없으므로 "다시 시도" 가 아니라 값을 고치도록 안내한다. 서버가 문장
/// 사유를 주면 [detail] 에 있다.
class ValidationError extends AppError {
  const ValidationError({this.statusCode, super.message, super.detail});

  /// 400 인지 422 인지. 화면이 둘을 다르게 다룰 일은 드물지만, 기존에
  /// `ServerError(statusCode)` 로 400 을 가르던 자리가 그대로 가를 수 있게 둔다.
  final int? statusCode;

  @override
  String toString() =>
      'ValidationError(status: $statusCode, message: $message)';
}

/// 429 — 요청 한도를 넘었다. 실패가 아니라 **잠시 뒤에는 되는** 상태라
/// 일반 서버 오류와 따로 둔다(#2859, 트레이너 웹 #582 와 같다).
class RateLimitedError extends AppError {
  const RateLimitedError({super.message, super.detail});
}

class ServerError extends AppError {
  const ServerError({this.statusCode, super.message, super.detail});
  final int? statusCode;

  @override
  String toString() => 'ServerError(status: $statusCode, message: $message)';
}

class CancelledError extends AppError {
  const CancelledError();
}

class UnknownError extends AppError {
  const UnknownError({super.message, super.cause, super.stackTrace});
}

/// 응답 본문에서 서버 사유를 꺼낸다(#2859).
///
/// `{"detail": "문장"}` 일 때만 그 문장을 돌려준다. FastAPI 스키마 검증은
/// `detail` 을 목록으로 주고, 일부 응답은 `{"detail": {"code": ...}}` 처럼
/// 객체로 준다 — 그런 값은 화면에 그대로 보일 문장이 아니므로 null 이다. 빈
/// 문자열도 null 이다.
String? serverDetailOf(Object? body) {
  if (body is! Map) return null;
  final Object? detail = body['detail'];
  if (detail is! String) return null;
  final String text = detail.trim();
  return text.isEmpty ? null : text;
}
