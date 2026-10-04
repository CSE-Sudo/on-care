import 'package:dio/dio.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';

/// Domain-level error type for the whole app. Repositories convert any
/// transport / framework exception into one of these before surfacing it
/// to controllers, so UI code never has to type-test `DioException`
/// directly. Mirrors the user app (`frontend/flutter`).
sealed class AppError implements Exception {
  const AppError({this.message, this.cause, this.stackTrace});

  final String? message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType(message: $message)';

  /// Map a `DioException` into the closest AppError. Add new branches
  /// here rather than at call sites.
  factory AppError.fromDio(DioException e) {
    // 문자열 `detail` 과 객체 `detail.message` 를 한 규칙으로 읽는다(#2911).
    final detail = serverDetailText(e.response?.data);
    final message = detail ?? e.message;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
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
          return UnauthorizedError(message: message);
        }
        if (code == 403) {
          return ForbiddenError(message: message);
        }
        if (code == 404) {
          return NotFoundError(message: message);
        }
        if (code == 429) {
          // 실패가 아니라 **잠시 뒤 되는** 상태다. 다른 오류와 뭉뚱그리면
          // 트레이너가 고장으로 읽는다(#582). 하루 상한(`daily_limit`)은
          // "잠시 뒤" 가 아니라 "내일" 이라 화면이 문구를 가를 수 있게 코드를
          // 함께 싣는다(#3032).
          return RateLimitedError(
            message: message,
            code: serverDetailCode(e.response?.data),
          );
        }
        if (code == 400 || code == 422) {
          // The server rejected the INPUT, not the request. Callers show
          // this inline on the offending field rather than as a "다시
          // 시도해 주세요" retry — retrying the same value can't help.
          return ValidationError(message: message);
        }
        return ServerError(statusCode: code, message: message);
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

/// 401 — missing / expired / invalid credentials. Triggers a refresh or
/// session expiry.
class UnauthorizedError extends AppError {
  const UnauthorizedError({super.message});
}

/// 403 — authenticated but not allowed (e.g. a member account hitting a
/// `/trainer/*` endpoint).
class ForbiddenError extends AppError {
  const ForbiddenError({super.message});
}

class NotFoundError extends AppError {
  const NotFoundError({super.message});
}

/// 400 / 422 — the request was understood and refused on its contents
/// (wrong current password, a value out of range). [message] carries the
/// server's own wording so the UI can show it verbatim.
class ValidationError extends AppError {
  const ValidationError({super.message});
}

/// 429 — 한도 초과. 실패가 아니라 잠시 뒤 되는 상태라, 화면이 "실패했어요"
/// 대신 기다렸다 다시 하라고 안내할 수 있게 따로 둔다(#582).
///
/// [code] 는 서버 `detail.code` 다. 분당 한도는 코드가 없고(잠시 뒤 다시),
/// 트레이너 하루 AI 상한은 [dailyLimitCode] 다(내일 다시, #3032).
class RateLimitedError extends AppError {
  const RateLimitedError({super.message, this.code});

  /// 트레이너 계정의 오늘 AI 호출 몫을 다 썼다 — 다시 눌러도 오늘은 같다.
  static const String dailyLimitCode = 'daily_limit';

  final String? code;

  /// 하루 상한인가. 참이면 "잠시 후" 가 아니라 "내일" 로 안내한다.
  bool get isDailyLimit => code == dailyLimitCode;

  @override
  String toString() => 'RateLimitedError(code: $code, message: $message)';
}

class ServerError extends AppError {
  const ServerError({this.statusCode, super.message});
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
