import 'package:oncare/core/errors/app_error.dart';

/// Why `POST /diet/analyze` failed, in the terms the user needs.
///
/// The distinction that matters is **whether retrying the same photo can
/// ever succeed**. Telling someone to "잠시 후 다시 시도" when the server
/// rejected the image format sends them into a loop that always fails, so
/// each value below carries [canRetry] and the UI follows it.
///
/// Status codes come from `backend/app/api/v1/diet.py` — keep in sync.
enum DietAnalysisFailure {
  /// 415 — the server can't decode this image type.
  unsupportedFormat(canRetry: false),

  /// 400 / 422 — empty file, or a request the server refused to parse.
  badRequest(canRetry: false),

  /// 401 — the session is gone. Retrying sends the same dead token, so the
  /// user has to sign in again.
  unauthorized(canRetry: false),

  /// 403 — 로그인은 유효한데 이 기능을 쓸 권한·동의가 없다(#2859). 다시
  /// 로그인해도 같은 403 이라 로그인으로 보내면 로그아웃·로그인만 되풀이된다.
  forbidden(canRetry: false),

  /// 429 — 요청 한도를 넘었다(#2859). 잠시 뒤 같은 사진으로 다시 하면 된다.
  rateLimited(canRetry: true),

  /// 501 — no recognizer is wired up for this deployment.
  notImplemented(canRetry: false),

  /// 502 — the recognizer itself failed. Transient by nature.
  recognitionFailed(canRetry: true),

  /// Timeouts, connection drops, other 5xx — worth another attempt.
  temporary(canRetry: true);

  const DietAnalysisFailure({required this.canRetry});

  /// Whether re-sending the *same* photo has any chance of succeeding.
  final bool canRetry;

  /// Classifies whatever `analyze()` threw.
  ///
  /// Anything unrecognized becomes [temporary]: offering a retry on an
  /// unknown failure is the safer default — the request is idempotent by
  /// key, so a pointless retry costs nothing, while wrongly telling the
  /// user their photo is unusable would strand a perfectly good capture.
  factory DietAnalysisFailure.fromError(Object error) {
    if (error is! AppError) return DietAnalysisFailure.temporary;
    return switch (error) {
      UnauthorizedError() => DietAnalysisFailure.unauthorized,
      ForbiddenError() => DietAnalysisFailure.forbidden,
      RateLimitedError() => DietAnalysisFailure.rateLimited,
      ValidationError() => DietAnalysisFailure.badRequest,
      NetworkError() => DietAnalysisFailure.temporary,
      ServerError(:final int? statusCode) => switch (statusCode) {
        // 목업이 상태 코드로 직접 던지는 400 도 같은 뜻이다.
        400 || 422 => DietAnalysisFailure.badRequest,
        415 => DietAnalysisFailure.unsupportedFormat,
        501 => DietAnalysisFailure.notImplemented,
        502 => DietAnalysisFailure.recognitionFailed,
        _ => DietAnalysisFailure.temporary,
      },
      _ => DietAnalysisFailure.temporary,
    };
  }
}
