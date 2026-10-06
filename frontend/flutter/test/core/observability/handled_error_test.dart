import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/observability/error_reporter.dart';
import 'package:oncare/core/observability/handled_error.dart';

/// 처리된 오류 창구(#3051) — 보고·로그 규칙.
class _FakeReporter extends ErrorReporter {
  final List<(Object, String, Map<String, String>)> reports =
      <(Object, String, Map<String, String>)>[];

  @override
  bool get isEnabled => true;

  @override
  Future<void> report(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    Map<String, String> tags = const <String, String>{},
  }) async {
    reports.add((error, source, tags));
  }
}

/// 로그 줄을 모으는 출력.
class _MemoryOutput extends LogOutput {
  final List<String> lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

Logger _logger(_MemoryOutput out) => Logger(
  printer: SimplePrinter(colors: false),
  output: out,
  level: Level.trace,
  filter: ProductionFilter(),
);

void main() {
  group('HandledErrorReporter.report', () {
    test('예상 밖 오류는 보고하고 로그도 남긴다', () async {
      final _FakeReporter reporter = _FakeReporter();
      final _MemoryOutput out = _MemoryOutput();
      HandledErrorReporter(
        reporter: reporter,
        logger: _logger(out),
      ).report(StateError('boom'), StackTrace.current, context: 'a.b');
      await Future<void>.delayed(Duration.zero);

      expect(reporter.reports, hasLength(1));
      expect(reporter.reports.single.$2, HandledErrorReporter.source);
      expect(reporter.reports.single.$3, <String, String>{
        'handled_context': 'a.b',
      });
      expect(out.lines.join('\n'), contains('[a.b]'));
    });

    for (final (String name, Object error) in <(String, Object)>[
      ('연결 끊김', const NetworkError()),
      ('이미 지워진 항목', const NotFoundError()),
      ('로그인 만료', const UnauthorizedError()),
      ('취소', const CancelledError()),
      // 앱이 건 시간 제한 — 늦으면 물러서도록 정해 둔 자리다(#3244).
      ('시간 제한', TimeoutException('slow')),
    ]) {
      test('$name 은 로그만 남기고 보고하지 않는다', () async {
        final _FakeReporter reporter = _FakeReporter();
        final _MemoryOutput out = _MemoryOutput();
        HandledErrorReporter(
          reporter: reporter,
          logger: _logger(out),
        ).report(error, null, context: 'x');
        await Future<void>.delayed(Duration.zero);

        expect(reporter.reports, isEmpty);
        expect(out.lines, isNotEmpty);
      });
    }

    test('서버 오류·알 수 없는 오류는 보고한다', () async {
      final _FakeReporter reporter = _FakeReporter();
      final HandledErrorReporter handled = HandledErrorReporter(
        reporter: reporter,
      );
      handled
        ..report(const ServerError(statusCode: 500), null, context: 'x')
        ..report(const UnknownError(), null, context: 'y');
      await Future<void>.delayed(Duration.zero);

      expect(reporter.reports, hasLength(2));
    });

    test('보내지 않는 보고기여도 예외 없이 지나간다', () {
      expect(
        () => HandledErrorReporter(
          reporter: NoopErrorReporter(),
        ).report(StateError('x'), null, context: 'x'),
        returnsNormally,
      );
    });
  });

  group('logMessage', () {
    test('릴리스에서는 예외 본문을 싣지 않는다', () {
      final String line = HandledErrorReporter.logMessage(
        StateError('secret body /users/me?token=abc'),
        context: 'coach.completeRoutine',
        verbose: false,
      );
      expect(line, contains('coach.completeRoutine'));
      expect(line, contains('StateError'));
      expect(line, isNot(contains('secret body')));
      expect(line, isNot(contains('token=abc')));
    });

    test('개발 환경에서는 예외 본문을 덧붙인다', () {
      final String line = HandledErrorReporter.logMessage(
        StateError('detail'),
        context: 'c',
        verbose: true,
      );
      expect(line, contains('detail'));
    });
  });

  group('handledErrorReporterProvider', () {
    test('로거·설정을 덮어쓰지 않아도 만들어진다', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        () => container
            .read(handledErrorReporterProvider)
            .report(StateError('x'), null, context: 'x'),
        returnsNormally,
      );
    });

    test('덮어쓴 보고기로 보낸다', () async {
      final _FakeReporter reporter = _FakeReporter();
      final _MemoryOutput out = _MemoryOutput();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          errorReporterProvider.overrideWithValue(reporter),
          appLoggerProvider.overrideWithValue(_logger(out)),
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.prod,
              apiBaseUrl: 'https://api.example.invalid/v1',
              useMockApi: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(handledErrorReporterProvider)
          .report(StateError('hidden'), null, context: 'z');
      await Future<void>.delayed(Duration.zero);

      expect(reporter.reports, hasLength(1));
      expect(out.lines.join('\n'), isNot(contains('hidden')));
    });
  });
}
