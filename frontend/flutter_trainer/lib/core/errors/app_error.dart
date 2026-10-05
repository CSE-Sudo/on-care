import 'package:dio/dio.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';

/// Domain-level error type for the whole app. Repositories convert any
/// transport / framework exception into one of these before surfacing it
/// to controllers, so UI code never has to type-test `DioException`
/// directly. Mirrors the user app (`frontend/flutter`).
sealed class AppError implements Exception {
  const AppError({this.message, this.cause, this.stackTrace});

  /// 서버가 준 사유 문장(`detail`)만 담는다. 없으면 null 이다.
  ///
  /// Dio 의 `e.message`("This exception was thrown because …" 같은 영어
  /// 설명문)는 여기에 넣지 않는다 — 화면이 이 값을 그대로 보이므로, 넣으면
  /// 라이브러리 원문이 한국어 화면에 뜬다. 디버깅용 원문은 [cause] 와 API 로그
  /// (`ApiLoggingInterceptor`)에 남는다. 화면 문구는 `appErrorMessage` 가 원인별로
  /// 고른다.
  final String? message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType(message: $message)';

  /// Map a `DioException` into the closest AppError. Add new branches
  /// here rather than at call sites.
  factory AppError.fromDio(DioException e) {
    // 문자열 `detail` 과 객체 `detail.message` 를 한 규칙으로 읽는다(#2911).
    // 서버가 사유를 주지 않았으면(본문 없음·422 목록형) null 이다 — Dio 원문으로
    // 메우지 않는다. 화면은 원인별 현지화 문구로 물러난다.
    final String? message = serverDetailText(e.response?.data);
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
          return UnauthorizedError(message: message, cause: e);
        }
        if (code == 403) {
          return ForbiddenError(message: message, cause: e);
        }
        if (code == 404) {
          return NotFoundError(message: message, cause: e);
        }
        if (code == 429) {
          // 실패가 아니라 **잠시 뒤 되는** 상태다. 다른 오류와 뭉뚱그리면
          // 트레이너가 고장으로 읽는다(#582). 하루 상한(`daily_limit`)은
          // "잠시 뒤" 가 아니라 "내일" 이라 화면이 문구를 가를 수 있게 코드를
          // 함께 싣는다(#3032).
          return RateLimitedError(
            message: message,
            code: serverDetailCode(e.response?.data),
            cause: e,
          );
        }
        if (code == 400 || code == 422) {
          // The server rejected the INPUT, not the request. Callers show
          // this inline on the offending field rather than as a "다시
          // 시도해 주세요" retry — retrying the same value can't help.
          return ValidationError(message: message, cause: e);
        }
        return ServerError(statusCode: code, message: message, cause: e);
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
  const UnauthorizedError({super.message, super.cause});
}

/// 403 — authenticated but not allowed (e.g. a member account hitting a
/// `/trainer/*` endpoint).
class ForbiddenError extends AppError {
  const ForbiddenError({super.message, super.cause});
}

class NotFoundError extends AppError {
  const NotFoundError({super.message, super.cause});
}

/// 400 / 422 — the request was understood and refused on its contents
/// (wrong current password, a value out of range). [message] carries the
/// server's own wording so the UI can show it verbatim.
class ValidationError extends AppError {
  const ValidationError({super.message, super.cause});
}

/// 429 — 한도 초과. 실패가 아니라 잠시 뒤 되는 상태라, 화면이 "실패했어요"
/// 대신 기다렸다 다시 하라고 안내할 수 있게 따로 둔다(#582).
///
/// [code] 는 서버 `detail.code` 다. 분당 한도는 코드가 없고(잠시 뒤 다시),
/// 트레이너 하루 AI 상한은 [dailyLimitCode] 다(내일 다시, #3032).
class RateLimitedError extends AppError {
  const RateLimitedError({super.message, this.code, super.cause});

  /// 트레이너 계정의 오늘 AI 호출 몫을 다 썼다 — 다시 눌러도 오늘은 같다.
  static const String dailyLimitCode = 'daily_limit';

  final String? code;

  /// 하루 상한인가. 참이면 "잠시 후" 가 아니라 "내일" 로 안내한다.
  bool get isDailyLimit => code == dailyLimitCode;

  @override
  String toString() => 'RateLimitedError(code: $code, message: $message)';
}

class ServerError extends AppError {
  const ServerError({this.statusCode, super.message, super.cause});
  final int? statusCode;

  /// 5xx — 서버 쪽의 일시적인 문제. 다시 시도하면 될 수 있다.
  bool get isServerSide => (statusCode ?? 0) >= 500;

  @override
  String toString() => 'ServerError(status: $statusCode, message: $message)';
}

class CancelledError extends AppError {
  const CancelledError();
}

class UnknownError extends AppError {
  const UnknownError({super.message, super.cause, super.stackTrace});
}
