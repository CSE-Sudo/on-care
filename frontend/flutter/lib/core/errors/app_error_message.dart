import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/utils/server_message.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 오류에 맞는 **공통** 안내 문구. (#2859)
///
/// 화면마다 상태 코드를 다시 해석하지 않도록, 어느 화면에서 나도 같은 뜻인
/// 오류만 여기서 문구를 정한다.
/// - [ForbiddenError](403) — 로그인 문제가 아니라 권한·동의 문제다. 서버가 준
///   사유가 있으면 한국어 화면에서 그 사유를, 아니면 앱 문구를 쓴다.
/// - [RateLimitedError](429) — 잠시 뒤에는 된다. 서버 사유보다 "잠시 뒤 다시"
///   라는 행동 안내가 중요해 앱 문구를 쓴다.
/// - [ValidationError](400·422) — 보낸 값이 거절됐다. 서버 사유가 가장 정확하므로
///   한국어 화면에서는 그것을, 아니면 화면이 준 [fallback] 을 쓴다.
///
/// 나머지(네트워크·로그인 만료·서버 오류 등)는 화면마다 할 일이 달라 [fallback]
/// 을 그대로 돌려준다. 로그인 만료는 다시 로그인 버튼과 함께 다뤄야 하므로 이
/// 함수가 문구만으로 덮지 않는다.
String appErrorMessage(
  AppLocalizations l,
  Object error, {
  required String fallback,
}) {
  return switch (error) {
    ForbiddenError(:final String? detail) => serverDetailOr(
      l,
      detail,
      l.errorForbidden,
    ),
    RateLimitedError() => l.errorRateLimited,
    ValidationError(:final String? detail) => serverDetailOr(
      l,
      detail,
      fallback,
    ),
    _ => fallback,
  };
}
