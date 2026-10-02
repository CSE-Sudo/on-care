/// 리포트 작업대가 요약 하나로 서는가. (#2863)
///
/// 예전 작업대는 회원마다 주간 리포트와 회원 피드백을 불러 큐를 세웠다 — 회원
/// N명이면 첫 화면에서 요청이 2N개였고, 하나라도 오는 중이면 줄마다 `열기` 가
/// 잠겼다. 이 파일이 지키는 것:
///  * 요약에서 세운 줄의 신호·순서가 회원별 리포트로 세운 것과 같다.
///  * 데모 요약([reportQueueFromReports])은 회원별 리포트와 같은 값을 낸다.
///  * 명단 폴링(내용이 같은 새 객체)으로는 요약을 다시 부르지 않는다.
///  * 작업대는 요약 하나만 구독하고 회원별 리포트를 부르지 않는다. 요약이 오기
///    전에는 상자에 로딩 하나만 서고, 오면 `열기` 가 바로 눌린다.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue_summary.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 요약·회원별 리포트를 몇 번 불렀는지 세는 저장소.
///
/// 요약은 [queueGate] 가 풀릴 때까지 오지 않는다 — 로딩 중인 작업대를 본다.
class _CountingRepository implements ReportRepository {
  _CountingRepository({this.summaries = const <ReportQueueSummary>[]});

  final List<ReportQueueSummary> summaries;
  Completer<void>? queueGate;

  int queueCalls = 0;
  final List<String> watched = <String>[];

  @override
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) async* {
    queueCalls++;
    if (queueGate case final Completer<void> gate) await gate.future;
    yield summaries;
  }

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) {
    watched.add(client.id);
    return Stream<WeeklyReport>.value(
      buildWeeklyReport(
        client: client,
        sessions: const [],
        weekStart: weekStart,
      ),
    );
  }

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

  @override
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
    required AppLocalizations l,
  }) async => ruleReportSummary(
    l,
    buildWeeklyReport(client: client, sessions: const [], weekStart: weekStart),
    client,
  );

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
  }) async {}
}

/// 회원마다 미리 정한 리포트를 흘리는 저장소 — 데모 요약 조립을 본다.
class _ScriptedReports extends _CountingRepository {
  _ScriptedReports(this.streams);

  final Map<String, Stream<WeeklyReport>> streams;

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) {
    watched.add(client.id);
    return streams[client.id] ?? const Stream<WeeklyReport>.empty();
  }

  @override
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) {
    queueCalls++;
    return reportQueueFromReports(this, clients: clients, weekStart: weekStart);
  }
}

final DateTime _week = DateTime(2026, 8, 10);

WeeklyReport _report(
  TrainerClient client, {
  int booked = 2,
  int done = 1,
  int? avg = 70,
  List<int> week = const <int>[90, 80, 70, 0, 40, 30, 20],
}) => WeeklyReport(
  client: client,
  weekStart: _week,
  sessionsBooked: booked,
  sessionsDone: done,
  completionAvg: avg,
  sodiumOverDays: 2,
  sodiumAvg: 2400,
  isCurrentWeek: false,
  weekCompletion: week,
  caloriesWeek: const <int>[2000, 0, 0, 0, 0, 0, 0],
);

void main() {
  final TrainerClient a = makeClient(id: 'a', name: '가회원');
  final TrainerClient b = makeClient(id: 'b', name: '나회원');
  final TrainerClient c = makeClient(id: 'c', name: '다회원');

  group('ReportQueueSummary', () {
    test('요약으로 세운 줄은 회원별 리포트로 세운 줄과 신호·순서가 같다', () {
      final Map<String, WeeklyReport> full = <String, WeeklyReport>{
        'a': _report(a, avg: 90, week: const <int>[90, 90, 90, 90, 90, 90, 90]),
        'b': _report(b, avg: 40, week: const <int>[90, 80, 70, 0, 10, 5, 0]),
        'c': _report(c, booked: 3, done: 3, avg: null, week: const <int>[]),
      };
      final Map<String, WeeklyReport> light = <String, WeeklyReport>{
        for (final MapEntry<String, WeeklyReport> e in full.entries)
          e.key: ReportQueueSummary.fromReport(
            e.value,
          ).toQueueReport(e.value.client, _week),
      };
      for (final String id in full.keys) {
        expect(reportSignals(light[id]!), reportSignals(full[id]!), reason: id);
      }
      List<String> order(Map<String, WeeklyReport> reports) => buildReportQueue(
        clients: <TrainerClient>[a, b, c],
        reports: reports,
        sentIds: const <String>{},
        sort: ReportQueueSort.priority,
      ).map((ReportQueueEntry e) => e.client.id).toList();
      expect(order(light), order(full));
    });

    test('작업대 줄의 리포트는 그 주·그 회원이다', () {
      final WeeklyReport light = ReportQueueSummary.fromReport(
        _report(a),
      ).toQueueReport(a, DateTime(2026, 8, 13));
      expect(light.weekStart, _week);
      expect(light.client.id, 'a');
      expect(light.sessionsBooked, 2);
      expect(light.sessionsDone, 1);
      expect(light.completionAvg, 70);
      // 큐가 쓰지 않는 식단 값은 싣지 않는다.
      expect(light.caloriesWeek, isEmpty);
      expect(light.sodiumOverDays, isNull);
    });

    test('이번 주인지는 오늘 기준으로 가린다', () {
      final DateTime thisWeek = weekStartOf(nowKst());
      const ReportQueueSummary s = ReportQueueSummary(
        clientId: 'a',
        sessionsBooked: 0,
        sessionsDone: 0,
        completionAvg: null,
      );
      expect(s.toQueueReport(a, thisWeek).isCurrentWeek, isTrue);
      expect(
        s.toQueueReport(a, shiftWeeks(thisWeek, -1)).isCurrentWeek,
        isFalse,
      );
    });
  });

  group('reportQueueFromReports — 데모 요약', () {
    test('회원별 리포트에서 같은 값을 뽑아 명단 순서로 낸다', () async {
      final _ScriptedReports repo =
          _ScriptedReports(<String, Stream<WeeklyReport>>{
            'a': Stream<WeeklyReport>.value(_report(a, avg: 90)),
            'b': Stream<WeeklyReport>.value(_report(b, avg: 40)),
          });
      final List<ReportQueueSummary> items = await reportQueueFromReports(
        repo,
        clients: <TrainerClient>[b, a],
        weekStart: _week,
      ).first;
      expect(items, <ReportQueueSummary>[
        ReportQueueSummary.fromReport(_report(b, avg: 40)),
        ReportQueueSummary.fromReport(_report(a, avg: 90)),
      ]);
    });

    test('모든 회원의 첫 값이 올 때까지 내보내지 않는다', () async {
      final StreamController<WeeklyReport> pending =
          StreamController<WeeklyReport>();
      addTearDown(pending.close);
      final _ScriptedReports repo = _ScriptedReports(
        <String, Stream<WeeklyReport>>{
          'a': Stream<WeeklyReport>.value(_report(a)),
          'b': pending.stream,
        },
      );
      final List<List<ReportQueueSummary>> seen = <List<ReportQueueSummary>>[];
      final StreamSubscription<List<ReportQueueSummary>> sub =
          reportQueueFromReports(
            repo,
            clients: <TrainerClient>[a, b],
            weekStart: _week,
          ).listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen, isEmpty, reason: '반쪽 큐는 한 회원을 수치 없는 줄로 세운다');

      pending.add(_report(b));
      await pumpEventQueue();
      expect(seen.single, hasLength(2));
    });

    test('리포트를 읽지 못한 회원은 빠지고 나머지는 선다', () async {
      final _ScriptedReports repo =
          _ScriptedReports(<String, Stream<WeeklyReport>>{
            'a': Stream<WeeklyReport>.value(_report(a)),
            'b': Stream<WeeklyReport>.error(StateError('down')),
          });
      final List<ReportQueueSummary> items = await reportQueueFromReports(
        repo,
        clients: <TrainerClient>[a, b],
        weekStart: _week,
      ).first;
      expect(items.map((ReportQueueSummary s) => s.clientId), <String>['a']);
    });

    test('한 회원의 리포트가 바뀌면 다시 낸다 — 데모는 살아 있는 스트림이다', () async {
      final StreamController<WeeklyReport> live =
          StreamController<WeeklyReport>();
      addTearDown(live.close);
      final _ScriptedReports repo = _ScriptedReports(
        <String, Stream<WeeklyReport>>{'a': live.stream},
      );
      final List<List<ReportQueueSummary>> seen = <List<ReportQueueSummary>>[];
      final StreamSubscription<List<ReportQueueSummary>> sub =
          reportQueueFromReports(
            repo,
            clients: <TrainerClient>[a],
            weekStart: _week,
          ).listen(seen.add);
      addTearDown(sub.cancel);

      live.add(_report(a));
      await pumpEventQueue();
      live.add(_report(a, done: 2));
      await pumpEventQueue();

      expect(
        seen.map((List<ReportQueueSummary> l) => l.single.sessionsDone),
        <int>[1, 2],
      );
    });

    test('빈 명단은 바로 빈 큐다', () async {
      final _ScriptedReports repo = _ScriptedReports(
        const <String, Stream<WeeklyReport>>{},
      );
      expect(
        await reportQueueFromReports(
          repo,
          clients: const <TrainerClient>[],
          weekStart: _week,
        ).first,
        isEmpty,
      );
      expect(repo.watched, isEmpty);
    });

    test('같은 회원이 두 번 있어도 한 번만 읽고 한 줄만 낸다', () async {
      final _ScriptedReports repo = _ScriptedReports(
        <String, Stream<WeeklyReport>>{
          'a': Stream<WeeklyReport>.value(_report(a)),
        },
      );
      final List<ReportQueueSummary> items = await reportQueueFromReports(
        repo,
        clients: <TrainerClient>[a, a],
        weekStart: _week,
      ).first;
      expect(items, hasLength(1));
      expect(repo.watched, <String>['a']);
    });
  });

  group('reportQueueProvider', () {
    late _CountingRepository repo;
    late ProviderContainer container;

    setUp(() {
      repo = _CountingRepository(
        summaries: <ReportQueueSummary>[
          ReportQueueSummary.fromReport(_report(a)),
        ],
      );
      container = ProviderContainer(
        overrides: <Override>[reportRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
    });

    test('회원 id → 요약으로 낸다', () async {
      final Map<String, ReportQueueSummary> queue = await container.read(
        reportQueueProvider(
          ReportQueueKey(clients: <TrainerClient>[a, b], weekStart: _week),
        ).future,
      );
      expect(queue.keys, <String>['a']);
      expect(queue['a']!.completionAvg, 70);
    });

    test('명단 폴링으로 내용이 같은 새 객체가 와도 다시 부르지 않는다', () async {
      await container.read(
        reportQueueProvider(
          ReportQueueKey(clients: <TrainerClient>[a, b], weekStart: _week),
        ).future,
      );
      await container.read(
        reportQueueProvider(
          ReportQueueKey(
            clients: <TrainerClient>[
              makeClient(id: 'a', name: '가회원', lastMessage: '새 메시지'),
              makeClient(id: 'b', name: '나회원'),
            ],
            // 같은 주의 목요일 — 열쇠는 월요일로 맞춘다.
            weekStart: DateTime(2026, 8, 13),
          ),
        ).future,
      );
      expect(repo.queueCalls, 1);
    });

    test('회원이 늘거나 이름이 바뀌거나 주가 바뀌면 새로 부른다', () async {
      Future<void> read(List<TrainerClient> clients, DateTime week) =>
          container.read(
            reportQueueProvider(
              ReportQueueKey(clients: clients, weekStart: week),
            ).future,
          );
      await read(<TrainerClient>[a], _week);
      await read(<TrainerClient>[a, b], _week);
      await read(<TrainerClient>[makeClient(id: 'a', name: '가회원B'), b], _week);
      await read(<TrainerClient>[a], shiftWeeks(_week, -1));
      expect(repo.queueCalls, 4);
      expect(repo.watched, isEmpty, reason: '요약은 회원별 리포트를 부르지 않는다');
    });
  });

  group('작업대 화면', () {
    final Finder loading = find.byKey(
      const ValueKey<String>('reports-queue-loading'),
    );

    /// 작업대 줄의 `열기` 버튼. 키가 [AppButton] 자신에 붙어 있다 — 그 키 아래
    /// 자손에서 [AppButton] 을 찾으면 늘 비어 있다.
    Finder openButton(String clientId) => find.byWidgetPredicate(
      (Widget w) =>
          w is AppButton && w.key == ValueKey<String>('reports-open-$clientId'),
    );

    Future<ProviderContainer> open(
      WidgetTester tester,
      _CountingRepository repo,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      return pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.reports,
        extraOverrides: <Override>[
          reportRepositoryProvider.overrideWithValue(repo),
        ],
      );
    }

    testWidgets('요약 하나만 부르고 회원별 리포트는 부르지 않는다', (tester) async {
      final _CountingRepository repo = _CountingRepository(
        summaries: <ReportQueueSummary>[
          const ReportQueueSummary(
            clientId: 'seed-client-1',
            sessionsBooked: 2,
            sessionsDone: 2,
            completionAvg: 35,
            weekCompletion: <int>[40, 30, 35, 0, 0, 0, 0],
          ),
        ],
      );
      await open(tester, repo);
      await settle(tester);

      expect(find.byType(ReportWorkbench), findsOneWidget);
      expect(repo.queueCalls, 1);
      expect(repo.watched, isEmpty);
      // 요약의 이행률이 그 회원 줄의 신호로 선다.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('reports-queue-seed-client-1')),
          matching: find.textContaining('35'),
        ),
        findsWidgets,
      );
    });

    testWidgets('요약이 오기 전에는 상자에 로딩 하나만 서고, 오면 열기가 바로 눌린다', (tester) async {
      final _CountingRepository repo = _CountingRepository()
        ..queueGate = Completer<void>();
      await open(tester, repo);
      await settle(tester);

      expect(loading, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('reports-open-seed-client-1')),
        findsNothing,
        reason: '줄마다 잠긴 버튼을 세우지 않는다',
      );

      repo.queueGate!.complete();
      await settle(tester);

      expect(loading, findsNothing);
      final Finder open1 = openButton('seed-client-1');
      expect(open1, findsOneWidget);
      // 요약에 없던 회원도 수치 없이 열 수 있다 — 편집기가 따로 읽는다.
      expect(tester.widget<AppButton>(open1).onPressed, isNotNull);
    });

    testWidgets('요약을 읽지 못해도 줄은 서고 열 수 있다', (tester) async {
      final _FailingQueue repo = _FailingQueue();
      await open(tester, repo);
      await settle(tester);

      expect(loading, findsNothing);
      final Finder open1 = openButton('seed-client-1');
      expect(open1, findsOneWidget);
      expect(tester.widget<AppButton>(open1).onPressed, isNotNull);
      expect(repo.watched, isEmpty);
    });

    testWidgets('편집기를 열면 그 회원의 리포트만 읽는다', (tester) async {
      final _CountingRepository repo = _CountingRepository();
      await open(tester, repo);
      await settle(tester);
      expect(repo.watched, isEmpty);

      await tester.tap(
        openButton('seed-client-1'),
      );
      await settle(tester);

      expect(currentLocation(tester), AppRoutes.reportFor('seed-client-1'));
      // 그 회원 것만 읽는다 — 작업대의 다른 회원 리포트는 부르지 않는다.
      expect(repo.watched.toSet(), <String>{'seed-client-1'});
    });
  });
}

/// 요약이 실패하는 저장소.
class _FailingQueue extends _CountingRepository {
  @override
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) {
    queueCalls++;
    return Stream<List<ReportQueueSummary>>.error(StateError('queue down'));
  }
}
