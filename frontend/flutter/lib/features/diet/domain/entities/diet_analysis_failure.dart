import 'package:oncare/core/errors/app_error.dart';

/// Why `POST /diet/analyze` failed, in the terms the user needs.
///
/// The distinction that matters is **whether retrying the same photo can
/// ever succeed**. Telling someone to "잠시 후 다시 시도" when the server
/// rejected the image format sends them into a loop that always fails, so
/// each value below carries [canRetry] and the UI follows it.
///
/// Some refusals also point to **manual entry** ([offersManualEntry]): the
/// photo path is closed for now (no food found, today's analyses used up,
/// analysis switched off) but the meal can still be logged by hand.
///
/// Status codes and `detail.code` values come from
/// `backend/app/api/v1/diet.py` — keep in sync.
enum DietAnalysisFailure {
  /// 415 — the server can't decode this image type.
  unsupportedFormat(canRetry: false),

  /// 400 — empty file, or a request the server refused to parse.
  badRequest(canRetry: false),

  /// 401 / 403 — the session is gone. There is no token refresh, so the
  /// user has to sign in again; retrying sends the same dead token.
  unauthorized(canRetry: false),

  /// 501 — no recognizer is wired up for this deployment.
  notImplemented(canRetry: false),

  /// 502 — the recognizer itself failed. Transient by nature.
  recognitionFailed(canRetry: true),

  /// 422 `no_food_detected` — the photo has no food in it (#2848). Nothing
  /// was saved; the same photo will never work, a different one or manual
  /// entry will.
  noFood(canRetry: false, offersManualEntry: true),

  /// 429 `daily_limit` — today's photo analyses are used up (#2827). Opens
  /// again after midnight (KST); until then only manual entry records.
  dailyLimit(canRetry: false, offersManualEntry: true),

  /// 429 `rate_limited` — too many analyses in a minute (#2827). A retry a
  /// moment later goes through.
  rateLimited(canRetry: true, offersManualEntry: true),

  /// 503 `analysis_unavailable` — photo analysis is switched off on this
  /// server (#2812). Retrying won't change that; manual entry still works.
  unavailable(canRetry: false, offersManualEntry: true),

  /// Timeouts, connection drops, other 5xx — worth another attempt.
  temporary(canRetry: true);

  const DietAnalysisFailure({
    required this.canRetry,
    this.offersManualEntry = false,
  });

  /// Whether re-sending the *same* photo has any chance of succeeding.
  final bool canRetry;

  /// Whether the sheet should offer to log the meal by hand instead.
  final bool offersManualEntry;

  /// Classifies whatever `analyze()` threw.
  ///
  /// Anything unrecognized becomes [temporary]: offering a retry on an
  /// unknown failure is the safer default — the request is idempotent by
  /// key, so a pointless retry costs nothing, while wrongly telling the
  /// user their photo is unusable would strand a perfectly good capture.
  factory DietAnalysisFailure.fromError(Object error) {
    if (error is DietAnalysisRejected) return error.failure;
    if (error is! AppError) return DietAnalysisFailure.temporary;
    return switch (error) {
      UnauthorizedError() => DietAnalysisFailure.unauthorized,
      NetworkError() => DietAnalysisFailure.temporary,
      ServerError(:final int? statusCode) => switch (statusCode) {
        400 || 422 => DietAnalysisFailure.badRequest,
        415 => DietAnalysisFailure.unsupportedFormat,
        // 429 without a code is the generic per-minute limiter — wait and retry.
        429 => DietAnalysisFailure.rateLimited,
        501 => DietAnalysisFailure.notImplemented,
        502 => DietAnalysisFailure.recognitionFailed,
        _ => DietAnalysisFailure.temporary,
      },
      _ => DietAnalysisFailure.temporary,
    };
  }

  /// The refusal named by the server's `detail.code`, or null when the body
  /// carries no code this screen knows.
  static DietAnalysisFailure? fromCode(Object? code) => switch (code) {
    'no_food_detected' => DietAnalysisFailure.noFood,
    'daily_limit' => DietAnalysisFailure.dailyLimit,
    'rate_limited' => DietAnalysisFailure.rateLimited,
    'analysis_unavailable' => DietAnalysisFailure.unavailable,
    _ => null,
  };
}

/// `POST /diet/analyze` refused with a coded `detail` (`{code, message}`).
///
/// Thrown by the repository instead of a bare [AppError] so the sheet can
/// tell "no food in this photo" (422) from a malformed request, and "today's
/// analyses are used up" from "slow down" (both 429) — the status alone
/// can't.
class DietAnalysisRejected implements Exception {
  const DietAnalysisRejected(this.failure, {this.message});

  final DietAnalysisFailure failure;

  /// The server's own wording. The sheet shows localized copy instead; this
  /// is kept for logs.
  final String? message;

  /// From an error response body `{detail: {code, message}}`. Null when the
  /// body has no known code — the caller falls back to [AppError.fromDio].
  static DietAnalysisRejected? fromResponseData(Object? data) {
    if (data is! Map) return null;
    final Object? detail = data['detail'];
    if (detail is! Map) return null;
    final DietAnalysisFailure? failure = DietAnalysisFailure.fromCode(
      detail['code'],
    );
    if (failure == null) return null;
    final Object? message = detail['message'];
    return DietAnalysisRejected(
      failure,
      message: message is String ? message : null,
    );
  }

  @override
  String toString() => 'DietAnalysisRejected($failure)';
}
