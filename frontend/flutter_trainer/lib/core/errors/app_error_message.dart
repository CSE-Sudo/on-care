import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 오류를 화면에 보일 한 문장으로 바꾼다 — 토스트·오류 상태가 함께 쓴다.
///
/// [AppError.message] 는 서버가 준 사유만 담는다. 사유가 있으면 지금처럼
/// [serverDetailOr] 가 로케일로 그대로 쓸지 고르고(#501), 없으면 원인별 문구로
/// 물러난다.
///
/// - 연결 오류·타임아웃 → [AppLocalizations.errorNetworkUnstable]. 다시 눌러도
///   되는 문제라는 것을 알려 준다.
/// - 5xx → 서버 사유가 없으면 [AppLocalizations.errorServerTemporary].
/// - 그 밖(422 목록형 검증 오류·본문 없는 4xx·알 수 없는 오류) → 그 화면의
///   [fallback]. "무엇이 실패했는지" 는 그 화면만 안다.
///
/// 회원 앱의 `appErrorMessage` 와 같은 자리의 함수다. 예전에는 화면마다
/// `serverDetailOr(l, error.message, fallback)` 을 불렀고, `message` 에 Dio 의
/// 영어 설명문이 들어와 한국어 화면에 그대로 떴다.
String appErrorMessage(
  AppLocalizations l,
  Object? error, {
  required String fallback,
}) {
  return switch (error) {
    NetworkError() => l.errorNetworkUnstable,
    ServerError(:final String? message, isServerSide: true) => serverDetailOr(
      l,
      message,
      l.errorServerTemporary,
    ),
    AppError(:final String? message) => serverDetailOr(l, message, fallback),
    _ => fallback,
  };
}
