/// 리포트 탭을 다시 열 때·전송 직전에 서버 값을 다시 읽는가. (#3100)
///
/// 실서버 리포트·작업대 요약은 한 번 읽고 끝나는 값이고 계정 동안 붙잡혀
/// 있다. 예전에는 다시 읽는 길이 오류 상태의 `다시 시도` 하나뿐이라, 금요일에
/// 연 편집기의 수치가 일요일 전송 때까지 남아 그 수치로 PDF 가 나갔다. 이
/// 파일이 지키는 것:
///  * 같은 열쇠를 무효화하면 요청이 다시 나가고 새 값이 흐른다(무효화 없이는
///    한 번).
///  * 다른 탭에 다녀오면 편집기·작업대가 다시 읽고, 읽는 동안 이전 값을 그린다.
///  * 전송은 다시 읽은 리포트로 PDF 를 만들고, 다시 읽지 못하면 보내지 않는다.
///  * 데모와 실서버가 같은 때에 같은 횟수로 다시 읽는다.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue_summary.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/client_report_view.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_send_preview.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

class _MockDio extends Mock implements Dio {}

const String _minsu = 'seed-client-1';

Response<Map<String, dynamic>> _ok(Map<String, dynamic> body, String path) =>
    Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body,
    );

/// 실서버처럼 부를 때마다 지금 값을 한 번 내고 끝나는 저장소.
///
/// [done] 을 바꾸면 다음 읽기부터 그 값이 나간다. [gate] 가 있으면 그것이
/// 끝날 때까지 응답을 미룬다 — 다시 읽는 동안의 화면을 보려고 쓴다.
class _LiveServer implements ReportRepository {
  int done = 1;
  bool fail = false;
  Future<void>? gate;

  /// 회원에게 실제로 나간 문구.
  final List<String> sentMessages = <String>[];

  WeeklyReport reportFor(TrainerClient client, DateTime weekStart) =>
      WeeklyReport(
        client: client,
        weekStart: weekStartOf(weekStart),
        sessionsBooked: 3,
        sessionsDone: done,
        completionAvg: 60,
        sodiumOverDays: 0,
        sodiumAvg: 0,
        isCurrentWeek: true,
      );

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) {
    if (fail) return Stream<WeeklyReport>.error(const NetworkError());
    final WeeklyReport report = reportFor(client, weekStart);
    final Future<void>? wait = gate;
    if (wait == null) return Stream<WeeklyReport>.value(report);
    return Stream<WeeklyReport>.fromFuture(wait.then((_) => report));
  }

  @override
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) => Stream<List<ReportQueueSummary>>.value(<ReportQueueSummary>[
    for (final TrainerClient c in clients)
      ReportQueueSummary(
        clientId: c.id,
        sessionsBooked: 3,
        sessionsDone: done,
        completionAvg: 60,
        weekCompletion: const <int>[60, 60, 60, 0, 0, 0, 0],
      ),
  ]);

  @override
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
    required AppLocalizations l,
  }) async => ruleReportSummary(l, reportFor(client, weekStart), client);

  @override
  Future<ReportFeedbackDraft> feedbackDraft({
    required TrainerClient client,
    required DateTime weekStart,
  }) async => const ReportFeedbackDraft.none();

  @override
  Future<ReportFeedbackDraft> saveFeedbackDraft({
    required String clientId,
    required DateTime weekStart,
    required String body,
  }) async => ReportFeedbackDraft(body: body, saved: true);

  @override
  Future<void> send({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) async {}

  @override
  Future<void> sendPdf({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async => sentMessages.add(message);

  @override
  Future<List<ReportSendRecord>> sentReports({
    required DateTime weekStart,
  }) async => const <ReportSendRecord>[];

  @override
  Future<MemberReportHistoryPage> memberReportHistory({
    required String clientId,
    DateTime? before,
    int limit = memberReportHistoryPageSize,
  }) async => const MemberReportHistoryPage.empty();
}

/// 저장소를 감싸 몇 번 읽었는지 센다 — 데모·실서버에 같은 잣대를 대려고.
class _Counting implements ReportRepository {
  _Counting(this._inner);

  final ReportRepository _inner;

  /// `회원 id|주 월요일` 별 리포트 읽기.
  final List<String> watched = <String>[];

  /// 작업대 요약 읽기.
  int queueCalls = 0;

  /// 전송된 PDF 수.
  int sends = 0;

  int watchesOf(String clientId, DateTime week) =>
      watched.where((String k) => k == _keyOf(clientId, week)).length;

  static String _keyOf(String clientId, DateTime week) =>
      '$clientId|${weekStartOf(week).toIso8601String()}';

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) {
    watched.add(_keyOf(client.id, weekStart));
    return _inner.watch(client: client, weekStart: weekStart);
  }

  @override
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) {
    queueCalls++;
    return _inner.watchQueue(clients: clients, weekStart: weekStart);
  }

  @override
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
    required AppLocalizations l,
  }) => _inner.summary(client: client, weekStart: weekStart, l: l);

  @override
  Future<ReportFeedbackDraft> feedbackDraft({
    required TrainerClient client,
    required DateTime weekStart,
  }) => _inner.feedbackDraft(client: client, weekStart: weekStart);

  @override
  Future<ReportFeedbackDraft> saveFeedbackDraft({
    required String clientId,
    required DateTime weekStart,
    required String body,
  }) => _inner.saveFeedbackDraft(
    clientId: clientId,
    weekStart: weekStart,
    body: body,
  );

  @override
  Future<void> send({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) => _inner.send(clientId: clientId, weekStart: weekStart, message: message);

  @override
  Future<void> sendPdf({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) {
    sends++;
    return _inner.sendPdf(
      clientId: clientId,
      weekStart: weekStart,
      bytes: bytes,
      fileName: fileName,
      message: message,
    );
  }

  @override
  Future<List<ReportSendRecord>> sentReports({required DateTime weekStart}) =>
      _inner.sentReports(weekStart: weekStart);

  @override
  Future<MemberReportHistoryPage> memberReportHistory({
    required String clientId,
    DateTime? before,
    int limit = memberReportHistoryPageSize,
  }) => _inner.memberReportHistory(
    clientId: clientId,
    before: before,
    limit: limit,
  );
}

/// 받은 리포트를 남기는 PDF 생성기.
class _RecordingPdf extends ReportPdfGenerator {
  final List<WeeklyReport> reports = <WeeklyReport>[];

  @override
  Future<Uint8List> generate({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) async {
    reports.add(report);
    return Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);
  }
}

/// 같은 장면을 두 저장소로 돌린다.
enum _Mode { real, demo }

void main() {
  group('저장소 — 무효화하면 다시 부른다 (#3100)', () {
    late _MockDio dio;
    late ProviderContainer container;
    final TrainerClient minsu = makeClient(id: 'm1', name: '김민수');
    final DateTime week = DateTime(2026, 8, 10);
    const String reportPath = '/trainer/clients/m1/report';
    const String queuePath = '/trainer/reports/queue';
    int booked = 1;

    setUpAll(() => registerFallbackValue(<String, String>{}));

    setUp(() {
      booked = 1;
      dio = _MockDio();
      when(
        () => dio.get<Map<String, dynamic>>(
          reportPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _ok(<String, dynamic>{
          'week_start': '2026-08-10',
          'sessions_booked': booked,
          'sessions_done': 1,
        }, reportPath),
      );
      when(
        () => dio.get<Map<String, dynamic>>(
          queuePath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _ok(<String, dynamic>{
          'week_start': '2026-08-10',
          'items': <Object?>[
            <String, dynamic>{
              'member_id': 'm1',
              'sessions_booked': booked,
              'sessions_done': 1,
              'completion_avg': 50,
              'week_completion': <Object?>[50, 0, 0, 0, 0, 0, 0],
            },
          ],
        }, queuePath),
      );
      container = ProviderContainer(
        overrides: <Override>[
          reportRepositoryProvider.overrideWithValue(DioReportRepository(dio)),
        ],
      );
      addTearDown(container.dispose);
    });

    int gets(String path) => verify(
      () => dio.get<Map<String, dynamic>>(
        path,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).callCount;

    test('주간 리포트 — 무효화 없이는 한 번, 무효화하면 다시 읽어 새 값이 흐른다', () async {
      final provider = weeklyReportProvider(
        ReportKey(client: minsu, weekStart: week),
      );
      expect((await container.read(provider.future)).sessionsBooked, 1);
      booked = 4;
      expect((await container.read(provider.future)).sessionsBooked, 1);
      expect(gets(reportPath), 1);

      container.invalidate(provider);
      expect((await container.read(provider.future)).sessionsBooked, 4);
      expect(gets(reportPath), 1, reason: 'verify 가 앞의 횟수를 비운다');
    });

    test('작업대 요약 — 무효화 없이는 한 번, 무효화하면 다시 읽어 새 값이 흐른다', () async {
      final provider = reportQueueProvider(
        ReportQueueKey(clients: <TrainerClient>[minsu], weekStart: week),
      );
      expect((await container.read(provider.future))['m1']!.sessionsBooked, 1);
      booked = 4;
      expect((await container.read(provider.future))['m1']!.sessionsBooked, 1);
      expect(gets(queuePath), 1);

      container.invalidate(provider);
      expect((await container.read(provider.future))['m1']!.sessionsBooked, 4);
      expect(gets(queuePath), 1, reason: 'verify 가 앞의 횟수를 비운다');
    });
  });

  group('리포트 화면', () {
    final Finder nextButton = find.byKey(
      const ValueKey<String>('report-step-next'),
    );
    final Finder sendButton = find.byKey(
      const ValueKey<String>('report-step-send'),
    );
    const String failedToast = '리포트 전송에 실패했어요. 다시 시도해 주세요';
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

    /// [mode] 의 저장소를 [_Counting] 으로 감싸 [at] 을 연다.
    Future<_Counting> open(
      WidgetTester tester,
      _Mode mode, {
      required String at,
      _LiveServer? server,
      _RecordingPdf? pdf,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _Counting counting;
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: at,
        extraOverrides: <Override>[
          reportRepositoryProvider.overrideWith((ref) {
            final ReportRepository inner = switch (mode) {
              _Mode.real => server ?? _LiveServer(),
              _Mode.demo => LocalReportRepository(
                ref.watch(scheduleRepositoryProvider),
                ref.watch(chatRepositoryProvider),
                ref.watch(appDatabaseProvider),
              ),
            };
            return counting = _Counting(inner);
          }),
          reportPdfGeneratorProvider.overrideWithValue(pdf ?? _RecordingPdf()),
          reportPdfRasterizerProvider.overrideWithValue(
            (Uint8List bytes) async => <Uint8List>[bytes],
          ),
        ],
      );
      await settle(tester);
      return counting;
    }

    Future<void> tapSend(WidgetTester tester) async {
      await tester.ensureVisible(sendButton);
      await tester.pump();
      await tester.tap(sendButton);
      await settle(tester);
    }

    for (final _Mode mode in _Mode.values) {
      testWidgets('[${mode.name}] 다른 탭에 다녀오면 편집기의 리포트를 다시 읽는다', (tester) async {
        final _Counting repo = await open(
          tester,
          mode,
          at: AppRoutes.reportFor(_minsu),
        );
        final DateTime week = weekStartOf(nowKst());
        expect(repo.watchesOf(_minsu, week), 1);

        await goTo(tester, AppRoutes.dashboard);
        expect(repo.watchesOf(_minsu, week), 1, reason: '보이지 않는 탭은 읽지 않는다');
        await goTo(tester, AppRoutes.reportFor(_minsu));

        expect(repo.watchesOf(_minsu, week), 2);
        expect(find.byType(ClientReportView), findsOneWidget);
      });

      testWidgets('[${mode.name}] 다른 탭에 다녀오면 작업대 요약을 다시 읽는다', (tester) async {
        final _Counting repo = await open(tester, mode, at: AppRoutes.reports);
        expect(find.byType(ReportWorkbench), findsOneWidget);
        expect(repo.queueCalls, 1);

        await goTo(tester, AppRoutes.dashboard);
        await goTo(tester, AppRoutes.reports);

        expect(repo.queueCalls, 2);
        expect(find.byType(ReportWorkbench), findsOneWidget);
      });

      testWidgets('[${mode.name}] 처음 여는 회원은 한 번만 읽는다', (tester) async {
        final _Counting repo = await open(tester, mode, at: AppRoutes.reports);
        await goTo(tester, AppRoutes.reportFor(_minsu));

        expect(repo.watchesOf(_minsu, weekStartOf(nowKst())), 1);
      });

      testWidgets('[${mode.name}] 전송은 그 리포트를 한 번 더 읽고 보낸다', (tester) async {
        final _Counting repo = await open(
          tester,
          mode,
          at: AppRoutes.reportFor(_minsu),
        );
        await tester.tap(nextButton);
        await settle(tester);
        await tester.tap(nextButton);
        await settle(tester);
        final int before = repo.watchesOf(_minsu, weekStartOf(nowKst()));

        await tapSend(tester);

        expect(repo.watchesOf(_minsu, weekStartOf(nowKst())), before + 1);
        expect(repo.sends, 1);
      });
    }

    testWidgets('탭에 돌아와 새 수치를 그리고, 읽는 동안에는 이전 수치를 둔다', (tester) async {
      final _LiveServer server = _LiveServer();
      await open(
        tester,
        _Mode.real,
        at: AppRoutes.reportFor(_minsu),
        server: server,
      );
      WeeklyReport shown() =>
          tester.widget<ClientReportView>(find.byType(ClientReportView)).report;
      expect(shown().sessionsDone, 1);

      // 회원이 그 사이 더 기록했다.
      await goTo(tester, AppRoutes.dashboard);
      server.done = 3;
      final Completer<void> gate = Completer<void>();
      server.gate = gate.future;
      await goTo(tester, AppRoutes.reportFor(_minsu));

      expect(find.byType(AppLoading), findsNothing);
      expect(shown().sessionsDone, 1);

      gate.complete();
      await settle(tester);
      expect(shown().sessionsDone, 3);
    });

    final Finder staleNotice = find.byKey(
      const ValueKey<String>('reports-send-stale-notice'),
    );
    final Finder feedbackField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '회원에게 전달할 코칭 피드백을 작성하세요.',
    );

    testWidgets('수치가 같으면 안내 없이 바로 보낸다', (tester) async {
      final _LiveServer server = _LiveServer();
      await open(
        tester,
        _Mode.real,
        at: AppRoutes.reportFor(_minsu),
        server: server,
      );
      await tester.tap(nextButton);
      await settle(tester);
      await tester.tap(nextButton);
      await settle(tester);

      await tapSend(tester);

      expect(server.sentMessages, hasLength(1));
      expect(staleNotice, findsNothing);
    });

    testWidgets('전송 직전 수치가 바뀌었으면 멈추고 안내하며, 새 수치로 다시 그린 뒤 다시 눌러야 나간다', (
      tester,
    ) async {
      final _LiveServer server = _LiveServer();
      final _RecordingPdf pdf = _RecordingPdf();
      await open(
        tester,
        _Mode.real,
        at: AppRoutes.reportFor(_minsu),
        server: server,
        pdf: pdf,
      );
      await tester.tap(nextButton);
      await settle(tester);
      await tester.tap(nextButton);
      await settle(tester);
      expect(pdf.reports.last.sessionsDone, 1, reason: '③ 미리보기는 처음 값');
      expect(staleNotice, findsNothing);

      server.done = 3;
      await tapSend(tester);

      // 보내지 않았다 — 트레이너가 본 것과 다른 수치가 나가지 않는다.
      expect(server.sentMessages, isEmpty);
      expect(staleNotice, findsOneWidget);
      expect(find.text('그사이 회원 기록이 바뀌었어요'), findsOneWidget);
      expect(find.text(failedToast), findsNothing);
      // 미리보기·자동 문구가 새 수치로 다시 섰다.
      expect(pdf.reports.last.sessionsDone, 3);
      final String refreshed = reportMessage(ko, pdf.reports.last);

      await tapSend(tester);

      expect(server.sentMessages, <String>[refreshed]);
      expect(pdf.reports.last.sessionsDone, 3);
    });

    testWidgets('트레이너가 고친 문구는 수치가 바뀌어 다시 그려도 그대로 나간다', (tester) async {
      final _LiveServer server = _LiveServer();
      final _RecordingPdf pdf = _RecordingPdf();
      await open(
        tester,
        _Mode.real,
        at: AppRoutes.reportFor(_minsu),
        server: server,
        pdf: pdf,
      );
      await tester.tap(nextButton);
      await settle(tester);
      const String edited = '이번 주 하체 운동 좋았어요.';
      await tester.enterText(feedbackField, edited);
      await settle(tester);
      await tester.tap(nextButton);
      await settle(tester);

      server.done = 3;
      await tapSend(tester);
      expect(server.sentMessages, isEmpty);
      expect(staleNotice, findsOneWidget);

      // ② 로 돌아가도 고친 글이 그대로다.
      await tester.tap(find.byKey(const ValueKey<String>('report-step-prev')));
      await settle(tester);
      final EditableText editable = tester.widget<EditableText>(
        find.descendant(of: feedbackField, matching: find.byType(EditableText)),
      );
      expect(editable.controller.text, edited);
      await tester.tap(nextButton);
      await settle(tester);

      await tapSend(tester);
      expect(server.sentMessages, <String>[edited]);
      expect(pdf.reports.last.sessionsDone, 3);
    });

    testWidgets('전송 직전 다시 읽기가 실패하면 보내지 않고 실패를 알린다', (tester) async {
      final _LiveServer server = _LiveServer();
      await open(
        tester,
        _Mode.real,
        at: AppRoutes.reportFor(_minsu),
        server: server,
      );
      await tester.tap(nextButton);
      await settle(tester);
      await tester.tap(nextButton);
      await settle(tester);

      server.fail = true;
      await tapSend(tester);

      expect(server.sentMessages, isEmpty);
      expect(find.text(failedToast), findsOneWidget);
    });
  });
}
