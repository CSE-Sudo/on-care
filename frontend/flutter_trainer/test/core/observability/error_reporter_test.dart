import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/observability/error_reporter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// 보고 호출을 모으는 가짜 보고기.
class _FakeReporter extends ErrorReporter {
  final List<(Object, StackTrace?, String)> reports =
      <(Object, StackTrace?, String)>[];

  @override
  bool get isEnabled => true;

  String? routeForTest() => currentRoute();

  @override
  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    required String source,
  }) async {
    reports.add((error, stackTrace, source));
  }
}

const String _dsn = 'https://publickey@o0.ingest.example.invalid/1';

AppConfig _config({
  Environment environment = Environment.prod,
  bool useMockApi = false,
  String? sentryDsn = _dsn,
}) => AppConfig(
  environment: environment,
  apiBaseUrl: 'https://api.example.invalid/v1',
  useMockApi: useMockApi,
  sentryDsn: sentryDsn,
);

void main() {
  group('shouldReportErrors', () {
    test('DSN 이 있고 실서버·운영이면 보낸다', () {
      expect(shouldReportErrors(_config()), isTrue);
      expect(
        shouldReportErrors(_config(environment: Environment.staging)),
        isTrue,
      );
    });

    test('DSN 이 없으면 보내지 않는다', () {
      expect(shouldReportErrors(_config(sentryDsn: null)), isFalse);
      expect(shouldReportErrors(_config(sentryDsn: '  ')), isFalse);
    });

    test('데모(목업) 모드에서는 보내지 않는다', () {
      expect(shouldReportErrors(_config(useMockApi: true)), isFalse);
    });

    test('개발 환경에서는 보내지 않는다', () {
      expect(
        shouldReportErrors(_config(environment: Environment.dev)),
        isFalse,
      );
    });
  });

  group('initErrorReporter', () {
    test('데모 설정이면 SDK 를 건드리지 않고 보내지 않는 보고기를 준다', () async {
      final ErrorReporter reporter = await initErrorReporter(
        _config(useMockApi: true),
      );
      expect(reporter, isA<NoopErrorReporter>());
      expect(reporter.isEnabled, isFalse);
      expect(Sentry.isEnabled, isFalse);
    });

    test('개발 환경이면 보내지 않는 보고기를 준다', () async {
      final ErrorReporter reporter = await initErrorReporter(
        _config(environment: Environment.dev),
      );
      expect(reporter, isA<NoopErrorReporter>());
    });
  });

  test('errorReporterProvider 기본값은 보내지 않는 보고기다', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(errorReporterProvider), isA<NoopErrorReporter>());
  });

  group('configureSentryOptions', () {
    test('개인정보가 실릴 수 있는 수집을 끈다', () {
      final SentryFlutterOptions options = SentryFlutterOptions();
      configureSentryOptions(options, _config());

      expect(options.dsn, _dsn);
      expect(options.environment, 'prod');
      expect(options.sendDefaultPii, isFalse);
      expect(options.tracesSampleRate, isNull);
      expect(options.maxRequestBodySize, MaxRequestBodySize.never);
      expect(options.enablePrintBreadcrumbs, isFalse);
      expect(options.enableUserInteractionBreadcrumbs, isFalse);
      expect(options.attachScreenshot, isFalse);
      expect(options.beforeSend, isNotNull);
      expect(options.beforeBreadcrumb, isNotNull);
    });

    test('환경 태그는 설정의 환경 이름이다', () {
      final SentryFlutterOptions options = SentryFlutterOptions();
      configureSentryOptions(
        options,
        _config(environment: Environment.staging),
      );
      expect(options.environment, 'staging');
    });
  });

  group('scrubSentryEvent', () {
    test('요청은 메서드와 쿼리 뗀 URL 만 남긴다', () {
      final SentryEvent event = SentryEvent(
        request: SentryRequest(
          method: 'POST',
          url: 'https://api.example.invalid/v1/diet/analyze?token=dummy',
          queryString: 'token=dummy',
          headers: const <String, String>{
            'Authorization': 'Bearer dummy-token',
          },
          data: const <String, dynamic>{'note': 'dummy-health-note'},
        ),
      );
      final SentryEvent out = scrubSentryEvent(event, Hint())!;

      expect(out.request!.method, 'POST');
      expect(out.request!.url, 'https://api.example.invalid/v1/diet/analyze');
      expect(out.request!.queryString, isNull);
      expect(out.request!.headers, isEmpty);
      expect(out.request!.data, isNull);
    });

    test('요청이 없는 이벤트는 그대로 둔다', () {
      final SentryEvent event = SentryEvent(
        message: const SentryMessage('boom'),
      );
      final SentryEvent out = scrubSentryEvent(event, Hint())!;
      expect(out.request, isNull);
      expect(out.message!.formatted, 'boom');
    });

    test('이벤트에 실린 브레드크럼도 거른다', () {
      final SentryEvent event = SentryEvent(
        breadcrumbs: <Breadcrumb>[
          Breadcrumb(
            category: 'console',
            message: 'dummy-health-note',
            data: const <String, dynamic>{'note': 'dummy-health-note'},
          ),
        ],
      );
      final SentryEvent out = scrubSentryEvent(event, Hint())!;
      final Breadcrumb crumb = out.breadcrumbs!.single;
      expect(crumb.message, isNull);
      expect(crumb.data, isNull);
      expect(crumb.category, 'console');
    });
  });

  group('scrubSentryBreadcrumb', () {
    test('메서드·상태·쿼리 뗀 URL 만 남기고 메시지를 지운다', () {
      final Breadcrumb out = scrubSentryBreadcrumb(
        Breadcrumb(
          category: 'http',
          message: 'GET dummy',
          data: const <String, dynamic>{
            'method': 'GET',
            'status_code': 500,
            'url': 'https://api.example.invalid/v1/diet?date=2026-10-01#x',
            'request_body': 'dummy-health-note',
          },
        ),
        Hint(),
      )!;
      expect(out.message, isNull);
      expect(out.data, <String, dynamic>{
        'method': 'GET',
        'status_code': 500,
        'url': 'https://api.example.invalid/v1/diet',
      });
    });

    test('null 은 null 로 돌려준다', () {
      expect(scrubSentryBreadcrumb(null, Hint()), isNull);
    });
  });

  group('오류 처리기', () {
    test('FlutterError 처리기는 알리고 로그를 남긴 뒤 보고한다', () async {
      final _FakeReporter reporter = _FakeReporter();
      final List<String> logs = <String>[];
      final List<FlutterErrorDetails> presented = <FlutterErrorDetails>[];
      final FlutterExceptionHandler handler = buildFlutterErrorHandler(
        reporter: reporter,
        log: (String message, Object error, StackTrace? stack) =>
            logs.add(message),
        present: presented.add,
      );
      final StateError error = StateError('broken widget');
      final StackTrace stack = StackTrace.current;

      handler(FlutterErrorDetails(exception: error, stack: stack));
      await Future<void>.delayed(Duration.zero);

      expect(presented, hasLength(1));
      expect(logs, <String>['FlutterError']);
      expect(reporter.reports, hasLength(1));
      expect(reporter.reports.single.$1, same(error));
      expect(reporter.reports.single.$2, same(stack));
      expect(reporter.reports.single.$3, 'flutter');
    });

    test('조용히 넘기는(silent) 오류는 보고하지 않는다', () async {
      final _FakeReporter reporter = _FakeReporter();
      final FlutterExceptionHandler handler = buildFlutterErrorHandler(
        reporter: reporter,
        log: (String message, Object error, StackTrace? stack) {},
        present: (FlutterErrorDetails details) {},
      );

      handler(FlutterErrorDetails(exception: StateError('x'), silent: true));
      await Future<void>.delayed(Duration.zero);

      expect(reporter.reports, isEmpty);
    });

    test('플랫폼 오류 처리기는 보고하고 처리했다고 알린다', () async {
      final _FakeReporter reporter = _FakeReporter();
      final List<String> logs = <String>[];
      final ErrorCallback handler = buildPlatformErrorHandler(
        reporter: reporter,
        log: (String message, Object error, StackTrace? stack) =>
            logs.add(message),
      );

      final bool handled = handler(
        const FormatException('bad'),
        StackTrace.current,
      );
      await Future<void>.delayed(Duration.zero);

      expect(handled, isTrue);
      expect(logs, <String>['Uncaught platform error']);
      expect(reporter.reports.single.$3, 'platform');
    });

    test('보내지 않는 보고기여도 처리기는 로그를 남긴다', () async {
      final List<String> logs = <String>[];
      final ErrorCallback handler = buildPlatformErrorHandler(
        reporter: NoopErrorReporter(),
        log: (String message, Object error, StackTrace? stack) =>
            logs.add(message),
      );
      expect(handler(StateError('x'), StackTrace.current), isTrue);
      expect(logs, hasLength(1));
    });
  });

  group('화면 경로 태그', () {
    test('붙인 함수가 주는 경로 패턴을 쓴다', () {
      final _FakeReporter reporter = _FakeReporter()
        ..attachRouteResolver(() => '/legal/:document');
      expect(reporter.routeForTest(), '/legal/:document');
    });

    test('경로를 알 수 없거나 함수가 실패하면 null 이다', () {
      final _FakeReporter reporter = _FakeReporter();
      expect(reporter.routeForTest(), isNull);
      reporter.attachRouteResolver(() => '');
      expect(reporter.routeForTest(), isNull);
      reporter.attachRouteResolver(() => throw StateError('no router'));
      expect(reporter.routeForTest(), isNull);
    });
  });
}
