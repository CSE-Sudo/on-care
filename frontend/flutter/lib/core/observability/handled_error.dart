import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/observability/error_reporter.dart';

/// 화면·서비스가 **잡아서 처리한** 오류를 남기는 창구 (#3051).
///
/// 처리하지 못한 오류는 전역 처리기(`installErrorHandlers`)가 보고한다. 그런데
/// `try/catch` 로 잡고 토스트를 띄우거나 대체 결과로 물러선 오류는 그 처리기를
/// 거치지 않아, 예전에는 `debugPrint` 로 개발 콘솔에만 남았다. 같은 실패가 반복돼도
/// 회원이 신고하기 전까지 아무도 몰랐다.
///
/// 여기서는 다음을 지킨다.
///  * 로거에는 **어디서(context) 무슨 종류(runtimeType)** 가 났는지만 남긴다.
///    예외 메시지 본문은 개발 환경에서만 덧붙인다 — 릴리스 기기 로그(logcat·콘솔)는
///    보고기의 개인정보 처리를 거치지 않는다.
///  * 보고기로는 `source: handled` 와 `handled_context` 태그를 달아 보낸다. 요청·
///    브레드크럼 정리는 보고기 쪽 규칙을 그대로 탄다.
///  * 화면이 정상 흐름으로 처리하는 **예상된 실패**(연결 끊김·이미 지워진 항목·
///    로그인 만료·취소)는 보내지 않는다. 그래야 오류 추적이 잡음으로 덮이지 않는다.
class HandledErrorReporter {
  HandledErrorReporter({
    required ErrorReporter reporter,
    Logger? logger,
    bool verbose = false,
  }) : _reporter = reporter,
       _logger = logger,
       _verbose = verbose;

  final ErrorReporter _reporter;
  final Logger? _logger;
  final bool _verbose;

  /// 보고기로 보낼 때 다는 `source` 값.
  static const String source = 'handled';

  /// [error] 를 남긴다. [context] 는 `coach.completeRoutine` 처럼 점으로 나눈
  /// 위치 이름이다. 실패해도 예외를 던지지 않는다.
  void report(Object error, StackTrace? stackTrace, {required String context}) {
    try {
      _logger?.w(logMessage(error, context: context, verbose: _verbose));
    } catch (_) {
      // 로그를 못 남겨도 화면 흐름은 그대로 간다.
    }
    if (isExpectedFailure(error)) return;
    unawaited(
      _reporter.report(
        error,
        stackTrace,
        source: source,
        tags: <String, String>{'handled_context': context},
      ),
    );
  }

  /// 로거에 남길 한 줄. 릴리스(`verbose == false`)에서는 예외 본문을 싣지 않는다.
  static String logMessage(
    Object error, {
    required String context,
    required bool verbose,
  }) {
    final String head = 'handled error [$context] ${error.runtimeType}';
    return verbose ? '$head: $error' : head;
  }

  /// 화면이 이미 정상 흐름으로 처리하는 실패인가 — 보고하지 않는다.
  static bool isExpectedFailure(Object error) => switch (error) {
    NetworkError() ||
    NotFoundError() ||
    UnauthorizedError() ||
    CancelledError() => true,
    _ => false,
  };
}

/// 앱 전체가 쓰는 창구. 로거·설정이 덮어써지지 않은 곳(테스트)에서도 만들어진다 —
/// 그때는 로그 없이 보고기만 쓴다(기본 보고기는 보내지 않는다).
final Provider<HandledErrorReporter> handledErrorReporterProvider =
    Provider<HandledErrorReporter>((ref) {
      Logger? logger;
      try {
        logger = ref.watch(appLoggerProvider);
      } on Object {
        logger = null;
      }
      bool verbose = false;
      try {
        verbose = !ref.watch(appConfigProvider).isProd;
      } on Object {
        verbose = false;
      }
      return HandledErrorReporter(
        reporter: ref.watch(errorReporterProvider),
        logger: logger,
        verbose: verbose,
      );
    }, name: 'handledErrorReporter');
