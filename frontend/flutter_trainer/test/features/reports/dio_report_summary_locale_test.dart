import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/network/accept_language_interceptor.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_ai_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/client_factory.dart';

/// 요청을 받아 두고, 요청 언어에 맞춘 요약을 돌려주는 가짜 서버(#2298).
///
/// 실서버처럼 `Accept-Language` 를 보고 문장을 고른다 — 앱이 어떤 언어를
/// 요청했는지와 그 언어의 문장이 돌아왔는지를 함께 본다.
class _SummaryServer implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  /// 다음 응답의 상태 코드. 200 이 아니면 오류 응답이다.
  int status = 200;

  /// 다음 응답 본문을 통째로 바꾼다(null 이면 언어별 기본 요약).
  String? rawBody;

  static const Map<String, Object> english = <String, Object>{
    'member_id': 'm1',
    'week_start': '2026-08-10',
    'headline':
        'Alex did well with workout completion rate at 87%; next week, '
        "let's also work on sodium over goal on 4 days.",
    'points': <String>[
      'Avg sodium 2,288 mg · over the default goal of 2,000 mg on 4 days',
      'Avg workout completion rate 87%',
    ],
    'generated_by': 'rule',
  };

  static const Map<String, Object> korean = <String, Object>{
    'member_id': 'm1',
    'week_start': '2026-08-10',
    'headline': 'Alex 회원은 운동 완료율 87%로 잘 지켰고, 다음 주는 나트륨 목표 초과 4일을 함께 챙기면 좋겠습니다.',
    'points': <String>['나트륨 평균 2,288mg · 기본 목표 2,000mg 초과 4일', '운동 완료율 평균 87%'],
    'generated_by': 'llm',
  };

  /// 마지막 요청의 `Accept-Language`.
  Object? get lastLanguage =>
      requests.last.headers[AcceptLanguageInterceptor.headerName];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final Object? language =
        options.headers[AcceptLanguageInterceptor.headerName];
    final String body =
        rawBody ?? jsonEncode(language == 'en' ? english : korean);
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 앱과 같은 `dioProvider`·`reportRepositoryProvider` 를 쓰되 어댑터만 바꾼
/// 컨테이너. [appLanguage] 는 트레이너가 설정에서 고른 화면 언어다.
Future<(ProviderContainer, _SummaryServer)> _setUp({
  TrainerLanguage appLanguage = TrainerLanguage.korean,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: Environment.prod,
          apiBaseUrl: 'https://api.test/v1',
          useMockApi: false,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(trainerLocaleProvider.notifier).setLanguage(appLanguage);
  final _SummaryServer server = _SummaryServer();
  container.read(dioProvider).httpClientAdapter = server;
  return (container, server);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final client = makeClient(id: 'm1', name: 'Alex');
  final DateTime weekStart = DateTime(2026, 8, 10);

  group('summaryLanguageTag', () {
    test('is the primary language of the localizations', () {
      expect(summaryLanguageTag(en), 'en');
      expect(summaryLanguageTag(ko), 'ko');
    });
  });

  group('DioReportRepository.summary', () {
    Future<ReportSummary> fetch(ProviderContainer c, AppLocalizations l) => c
        .read(reportRepositoryProvider)
        .summary(client: client, weekStart: weekStart, l: l);

    test('asks the server for English when the summary is English', () async {
      final (ProviderContainer c, _SummaryServer server) = await _setUp();

      final ReportSummary summary = await fetch(c, en);

      expect(server.lastLanguage, 'en');
      expect(summary.headline, _SummaryServer.english['headline']);
      expect(summary.points, _SummaryServer.english['points']);
      expect(summary.generatedBy, 'rule');
      expect(summary.isGenerated, isFalse);
    });

    test('asks the server for Korean when the summary is Korean', () async {
      final (ProviderContainer c, _SummaryServer server) = await _setUp(
        appLanguage: TrainerLanguage.english,
      );

      final ReportSummary summary = await fetch(c, ko);

      expect(server.lastLanguage, 'ko');
      expect(summary.headline, _SummaryServer.korean['headline']);
      expect(summary.isGenerated, isTrue);
    });

    test(
      'the summary language wins over the app-wide interceptor language',
      () async {
        // 화면 언어는 한국어인데 영어 요약 칸을 채우는 요청 — 인터셉터가 덮어
        // 쓰면 영어 칸에 한국어 문장이 들어간다.
        final (ProviderContainer c, _SummaryServer server) = await _setUp();

        await fetch(c, en);

        expect(server.lastLanguage, 'en');
        expect(server.requests.single.path, endsWith('/report/summary'));
      },
    );

    test('keeps the week and the escaped client id in the request', () async {
      final (ProviderContainer c, _SummaryServer server) = await _setUp();

      await c
          .read(reportRepositoryProvider)
          .summary(
            client: makeClient(id: 'user a/b', name: 'Alex'),
            weekStart: weekStart,
            l: en,
          );

      final RequestOptions request = server.requests.single;
      expect(request.uri.path, contains('/trainer/clients/user%20a%2Fb/'));
      expect(request.queryParameters['week_start'], '2026-08-10');
    });

    test('other requests still follow the app language', () async {
      final (ProviderContainer c, _SummaryServer server) = await _setUp(
        appLanguage: TrainerLanguage.english,
      );

      await c.read(dioProvider).get<Object?>('/health');

      expect(server.lastLanguage, 'en');
    });

    test('trims the headline and drops non-string points', () async {
      final (ProviderContainer c, _SummaryServer server) = await _setUp();
      server.rawBody = jsonEncode(<String, Object?>{
        'headline': '  Solid week.  ',
        'points': <Object?>['Avg calories 1,624 kcal', 3, null],
      });

      final ReportSummary summary = await fetch(c, en);

      expect(summary.headline, 'Solid week.');
      expect(summary.points, <String>['Avg calories 1,624 kcal']);
      // 계약에 없는 응답은 규칙 기반으로 읽는다 — 모델이 쓴 것처럼 보이지 않게.
      expect(summary.generatedBy, 'rule');
    });

    test('a server error becomes an AppError in either language', () async {
      final (ProviderContainer c, _SummaryServer server) = await _setUp();
      server.status = 500;

      await expectLater(fetch(c, en), throwsA(isA<AppError>()));
      expect(server.lastLanguage, 'en');
      await expectLater(fetch(c, ko), throwsA(isA<AppError>()));
      expect(server.lastLanguage, 'ko');
    });

    test('a refused client is still an error in English', () async {
      final (ProviderContainer c, _SummaryServer server) = await _setUp();
      server.status = 404;

      await expectLater(fetch(c, en), throwsA(isA<AppError>()));
    });
  });

  group('reportSummaryProvider', () {
    test('each language is its own request and its own answer', () async {
      final (ProviderContainer c, _SummaryServer server) = await _setUp();
      final ReportKey report = ReportKey(client: client, weekStart: weekStart);

      final ReportSummary english = await c.read(
        reportSummaryProvider((
          report: report,
          locale: const Locale('en'),
        )).future,
      );
      final ReportSummary korean = await c.read(
        reportSummaryProvider((
          report: report,
          locale: const Locale('ko'),
        )).future,
      );

      expect(
        server.requests.map(
          (RequestOptions r) => r.headers[AcceptLanguageInterceptor.headerName],
        ),
        <Object?>['en', 'ko'],
      );
      expect(english.headline, _SummaryServer.english['headline']);
      expect(korean.headline, _SummaryServer.korean['headline']);
    });
  });

  group('ReportAiCard with the real server', () {
    WeeklyReport weekly() => WeeklyReport(
      client: client,
      weekStart: weekStart,
      sessionsBooked: 1,
      sessionsDone: 1,
      completionAvg: 87,
      sodiumOverDays: 4,
      sodiumAvg: 2288,
      isCurrentWeek: false,
    );

    Future<(_SummaryServer, List<String>)> pumpCard(
      WidgetTester tester,
      Locale locale,
    ) async {
      final (ProviderContainer c, _SummaryServer server) = await _setUp(
        // 앱 설정 언어와 화면 언어가 같다 — 화면은 설정 언어로 그려진다.
        appLanguage: locale.languageCode == 'en'
            ? TrainerLanguage.english
            : TrainerLanguage.korean,
      );
      final List<String> drafts = <String>[];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ReportAiCard(report: weekly(), onUseAsDraft: drafts.add),
              ),
            ),
          ),
        ),
      );
      // Dio 의 인터셉터 체인과 가짜 어댑터는 실제 비동기로 돈다 — 요약이
      // 도착할 때까지 실제 시간을 흘려보낸다.
      bool arrived() =>
          find.text(en.reportsAiUseAsDraft).evaluate().isNotEmpty ||
          find.text(ko.reportsAiUseAsDraft).evaluate().isNotEmpty;
      for (var i = 0; i < 20 && !arrived(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      return (server, drafts);
    }

    testWidgets('an English screen shows the English server summary', (
      WidgetTester tester,
    ) async {
      final (_SummaryServer server, List<String> drafts) = await pumpCard(
        tester,
        const Locale('en'),
      );

      expect(server.lastLanguage, 'en');
      expect(
        find.text(_SummaryServer.english['headline']! as String),
        findsOneWidget,
      );
      expect(find.textContaining('회원은'), findsNothing);
      expect(find.text(en.reportsAiGenerated), findsNothing);

      await tester.tap(find.text(en.reportsAiUseAsDraft));
      await tester.pump();
      expect(drafts.single, startsWith('Alex did well with'));
      expect(drafts.single, contains('· Avg sodium 2,288 mg'));
    });

    testWidgets('a Korean screen shows the Korean server summary', (
      WidgetTester tester,
    ) async {
      final (_SummaryServer server, List<String> drafts) = await pumpCard(
        tester,
        const Locale('ko'),
      );

      expect(server.lastLanguage, 'ko');
      expect(
        find.text(_SummaryServer.korean['headline']! as String),
        findsOneWidget,
      );
      expect(find.text(ko.reportsAiGenerated), findsOneWidget);

      await tester.tap(find.text(ko.reportsAiUseAsDraft));
      await tester.pump();
      expect(drafts.single, contains('· 나트륨 평균 2,288mg'));
    });
  });
}
