import 'package:flutter/widgets.dart';
import 'package:oncare/core/errors/app_error_message.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 오류 객체로 만드는 회원 앱 오류 상태 — 설명 줄이 **원인**을 말한다. (#3140)
///
/// 제목은 화면이 정한다(무엇을 못 불러왔는가). 설명은 [error] 의 원인에서
/// 고른다(왜, 그래서 무엇을 하면 되는가) — 연결 끊김·서버 일시 문제·권한·
/// 동의·요청 한도·로그인 만료가 서로 다른 문구다([appErrorCauseMessage]).
/// 원인을 가릴 수 없는 오류는 화면이 준 [message] 로, 그것도 없으면 지금처럼
/// 제목만 남는다.
///
/// 공용 위젯 [AppErrorState] 는 두 앱이 함께 쓰는 문자열 계약이라 그대로 두고,
/// 오류를 해석하는 일만 여기서 한다. 트레이너 웹은 자기 오류 해석을 따로 둔다.
/// 버튼 문구는 어느 화면이든 [다시 시도] 다.
AppErrorState appErrorStateFor(
  BuildContext context, {
  Key? key,
  required Object? error,
  required String title,
  String? message,
  required VoidCallback? onRetry,
  Key? retryKey,
  AppStatePlacement placement = AppStatePlacement.page,
}) {
  final AppLocalizations l = AppLocalizations.of(context);
  return AppErrorState(
    key: key,
    title: title,
    message: appErrorCauseMessage(l, error) ?? message,
    retryLabel: l.actionRetry,
    retryKey: retryKey,
    onRetry: onRetry,
    placement: placement,
  );
}
