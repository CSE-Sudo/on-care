import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// 처리하지 못한 오류를 에러 추적 도구(Sentry)로 보내는 창구 (#2839).
///
/// 예전에는 오류가 기기 로그에만 남아, 특정 기기·화면에서 반복해서 깨져도 회원이
/// 신고하기 전까지 아무도 몰랐다. 여기서 보내되 다음을 지킨다.
///
///  * 데모(목업, `USE_MOCK_API=true`)·개발 환경·DSN 없음이면 보내지 않는다
///    ([shouldReportErrors]).
///  * 사용자 식별·요청 본문·헤더·화면 터치 기록·print 로그를 싣지 않는다
///    ([configureSentryOptions], [scrubSentryEvent]).
///  * 태그는 오류 출처·화면 경로 **패턴**(`/diet/:id` 처럼 값이 빠진 형태)·환경이고,
///    앱 버전은 SDK 가 패키지 정보에서 채운다.
abstract class ErrorReporter {
  /// 오류를 보낼 수 있는 상태인가.
  bool get isEnabled;

  String? Function()? _routeResolver;

  /// 지금 화면의 경로 패턴을 알려 줄 함수를 붙인다. 라우터가 만들어질 때 부른다.
  void attachRouteResolver(String? Function() resolver) {
    _routeResolver = resolver;
  }

  /// 지금 화면의 경로 패턴. 알 수 없으면 null.
  @protected
  String? currentRoute() {
    try {
      final String? route = _routeResolver?.call();
      return (route == null || route.isEmpty) ? null : route;
    } catch (_) {
      return null;
    }
  }

  /// [error] 를 보낸다. [source] 는 어디서 왔는지 — 전역 처리기(`flutter`·
  /// `platform`)이거나, 화면이 잡아서 처리한 오류(`handled`, #3051)다. [tags] 는
  /// 이벤트에 덧붙일 태그(`handled_context` 등)로, 값에 개인정보를 담지 않는다.
  /// 실패해도 예외를 던지지 않는다 — 오류 보고가 앱을 다시 깨뜨리면 안 된다.
  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    Map<String, String> tags = const <String, String>{},
  });
}

/// 보내지 않는 보고기. 데모·개발 환경과 테스트의 기본값이다.
class NoopErrorReporter extends ErrorReporter {
  @override
  bool get isEnabled => false;

  @override
  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    Map<String, String> tags = const <String, String>{},
  }) async {}
}

/// Sentry 로 보내는 보고기. [initErrorReporter] 가 SDK 를 초기화한 뒤에만 만든다.
class SentryErrorReporter extends ErrorReporter {
  @override
  bool get isEnabled => true;

  @override
  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    Map<String, String> tags = const <String, String>{},
  }) async {
    try {
      final String? route = currentRoute();
      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (Scope scope) async {
          await scope.setTag('source', source);
          for (final MapEntry<String, String> tag in tags.entries) {
            await scope.setTag(tag.key, tag.value);
          }
          if (route != null) await scope.setTag('route', route);
        },
      );
    } catch (_) {
      // 보고 실패는 삼킨다. 로컬 로그는 처리기가 이미 남겼다.
    }
  }
}

/// 이 설정에서 오류를 보낼지 — DSN 이 있고, 데모(목업)가 아니고, 개발 환경이 아닐 때만.
bool shouldReportErrors(AppConfig config) {
  final String dsn = config.sentryDsn?.trim() ?? '';
  return dsn.isNotEmpty && !config.useMockApi && !config.isDev;
}

/// 설정이 허락하면 Sentry 를 초기화하고 그 보고기를, 아니면 [NoopErrorReporter] 를 준다.
Future<ErrorReporter> initErrorReporter(AppConfig config) async {
  if (!shouldReportErrors(config)) return NoopErrorReporter();
  try {
    await SentryFlutter.init(
      (SentryFlutterOptions options) => configureSentryOptions(options, config),
    );
    return SentryErrorReporter();
  } catch (_) {
    // 초기화 실패로 앱이 안 뜨는 것보다 보고 없이 뜨는 쪽이 낫다.
    return NoopErrorReporter();
  }
}

/// SDK 옵션 — 개인정보가 실릴 수 있는 수집을 모두 끈다.
@visibleForTesting
void configureSentryOptions(SentryFlutterOptions options, AppConfig config) {
  options
    ..dsn = config.sentryDsn?.trim()
    ..environment = config.environment.name
    ..sendDefaultPii = false
    // 성능 추적(APM)은 범위 밖 — 트랜잭션을 만들지 않는다.
    ..tracesSampleRate = null
    ..maxRequestBodySize = MaxRequestBodySize.never
    // print·로거 출력에는 식단·건강 기록이 섞일 수 있다.
    ..enablePrintBreadcrumbs = false
    // 터치 기록은 위젯 이름·문구를 싣는다.
    ..enableUserInteractionBreadcrumbs = false
    // 화면 캡처에는 식단 사진·건강 수치가 그대로 담긴다(뷰 계층 첨부도 기본값 꺼짐 유지).
    ..attachScreenshot = false
    ..beforeSend = scrubSentryEvent
    ..beforeBreadcrumb = scrubSentryBreadcrumb;
}

/// 보내기 직전 이벤트에서 요청 정보를 메서드·쿼리 뗀 URL 만 남기고, 브레드크럼도 거른다.
@visibleForTesting
SentryEvent? scrubSentryEvent(SentryEvent event, Hint hint) {
  final SentryRequest? request = event.request;
  return event.copyWith(
    request: request == null
        ? null
        : SentryRequest(method: request.method, url: _stripQuery(request.url)),
    breadcrumbs: event.breadcrumbs
        ?.map((Breadcrumb b) => scrubSentryBreadcrumb(b, Hint()))
        .whereType<Breadcrumb>()
        .toList(),
  );
}

/// 브레드크럼은 종류·시각·수준과 메서드·상태·쿼리 뗀 URL 만 남긴다. 메시지는 지운다.
@visibleForTesting
Breadcrumb? scrubSentryBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
  if (breadcrumb == null) return null;
  final Map<String, dynamic>? data = breadcrumb.data;
  final Map<String, dynamic> kept = <String, dynamic>{
    for (final String key in const <String>['method', 'status_code', 'url'])
      if (data != null && data.containsKey(key))
        key: key == 'url' ? _stripQuery(data[key]?.toString()) : data[key],
  };
  return Breadcrumb(
    category: breadcrumb.category,
    type: breadcrumb.type,
    level: breadcrumb.level,
    timestamp: breadcrumb.timestamp,
    data: kept.isEmpty ? null : kept,
  );
}

String? _stripQuery(String? url) {
  if (url == null) return null;
  final int cut = url.indexOf(RegExp('[?#]'));
  return cut < 0 ? url : url.substring(0, cut);
}

/// 로컬 로그 함수 — 처리기가 보고와 별개로 기기 로그에 남길 때 쓴다.
typedef ErrorLog =
    void Function(String message, Object error, StackTrace? stackTrace);

/// `FlutterError.onError` 처리기. 화면에 알리고 로그를 남긴 뒤 보고한다.
/// 프레임워크가 조용히 넘기는 오류(`silent`)는 보내지 않는다.
@visibleForTesting
FlutterExceptionHandler buildFlutterErrorHandler({
  required ErrorReporter reporter,
  required ErrorLog log,
  void Function(FlutterErrorDetails details)? present,
}) {
  return (FlutterErrorDetails details) {
    (present ?? FlutterError.presentError)(details);
    log('FlutterError', details.exception, details.stack);
    if (details.silent) return;
    unawaited(
      reporter.report(details.exception, details.stack, source: 'flutter'),
    );
  };
}

/// `PlatformDispatcher.onError` 처리기. 로그를 남기고 보고한 뒤 처리했다고 알린다.
@visibleForTesting
ErrorCallback buildPlatformErrorHandler({
  required ErrorReporter reporter,
  required ErrorLog log,
}) {
  return (Object error, StackTrace stack) {
    log('Uncaught platform error', error, stack);
    unawaited(reporter.report(error, stack, source: 'platform'));
    return true;
  };
}

/// 두 전역 오류 처리기를 설치한다. SDK 가 초기화 때 건 처리기는 여기서 바뀐다 —
/// 보고는 [reporter] 가 한 번만 한다.
void installErrorHandlers({
  required ErrorReporter reporter,
  required ErrorLog log,
}) {
  FlutterError.onError = buildFlutterErrorHandler(reporter: reporter, log: log);
  WidgetsBinding.instance.platformDispatcher.onError =
      buildPlatformErrorHandler(reporter: reporter, log: log);
}

/// 앱 전체가 쓰는 오류 보고기. `bootstrap` 이 [initErrorReporter] 결과로 덮어쓴다.
/// 덮어쓰지 않은 곳(테스트)에서는 보내지 않는다.
final Provider<ErrorReporter> errorReporterProvider = Provider<ErrorReporter>(
  (ref) => NoopErrorReporter(),
  name: 'errorReporter',
);
