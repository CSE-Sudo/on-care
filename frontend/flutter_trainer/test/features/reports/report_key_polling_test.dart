import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue_summary.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 몇 번 불렸는지 세는 리포트 저장소. 실서버처럼 한 번 읽고 끝나는 스트림이다.
class _CountingReports implements ReportRepository {
  int watches = 0;
  int summaries = 0;
  int drafts = 0;

  @override
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) => reportQueueFromReports(this, clients: clients, weekStart: weekStart);

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) {
    watches++;
    return Stream<WeeklyReport>.value(
      buildWeeklyReport(
        client: client,
        sessions: const [],
        weekStart: weekStart,
      ),
    );
  }

  @override
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
    required AppLocalizations l,
  }) async {
    summaries++;
    return ruleReportSummary(
      l,
      buildWeeklyReport(
        client: client,
        sessions: const [],
        weekStart: weekStart,
      ),
      client,
    );
  }

  @override
  Future<ReportFeedbackDraft> feedbackDraft({
    required TrainerClient client,
    required DateTime weekStart,
  }) async {
    drafts++;
    return const ReportFeedbackDraft.none();
  }

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

/// 폴링이 내보내는 것과 같은 회원 — 내용은 같고 객체만 새것이다. 최근 대화처럼
/// 폴링마다 바뀔 수 있는 표시 필드도 바꿔 둔다.
TrainerClient _polled(TrainerClient c, {String? lastMessage}) => makeClient(
  id: c.id,
  name: c.name,
  lastMessage: lastMessage ?? c.lastMessage,
);

void main() {
  final DateTime week = DateTime(2026, 8, 10);
  final TrainerClient minsu = makeClient(id: 'seed-client-1', name: '김민수');

  group('ReportKey (#2768)', () {
    test('같은 회원·주면 객체가 달라도 같은 열쇠다', () {
      final ReportKey a = ReportKey(client: minsu, weekStart: week);
      final ReportKey b = ReportKey(
        client: _polled(minsu, lastMessage: '새 메시지'),
        weekStart: week,
      );

      expect(identical(a.client, b.client), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.clientId, 'seed-client-1');
    });

    test('주가 다르면 다른 열쇠다', () {
      expect(
        ReportKey(client: minsu, weekStart: week),
        isNot(
          ReportKey(
            client: minsu,
            weekStart: week.subtract(const Duration(days: 7)),
          ),
        ),
      );
    });

    test('회원이 다르면 다른 열쇠다', () {
      expect(
        ReportKey(client: minsu, weekStart: week),
        isNot(
          ReportKey(
            client: makeClient(id: 'other'),
            weekStart: week,
          ),
        ),
      );
    });

    test('이름이 바뀌면 다른 열쇠다 — 리포트가 새 이름으로 다시 선다', () {
      expect(
        ReportKey(client: minsu, weekStart: week),
        isNot(
          ReportKey(
            client: makeClient(id: minsu.id, name: '김민수B'),
            weekStart: week,
          ),
        ),
      );
    });

    test('요약 열쇠도 회원 객체가 아니라 내용으로 가른다', () {
      final ReportSummaryKey a = (
        report: ReportKey(client: minsu, weekStart: week),
        locale: const Locale('ko'),
      );
      final ReportSummaryKey b = (
        report: ReportKey(client: _polled(minsu), weekStart: week),
        locale: const Locale('ko'),
      );
      final ReportSummaryKey english = (
        report: ReportKey(client: _polled(minsu), weekStart: week),
        locale: const Locale('en'),
      );

      expect(a, b);
      expect(a, isNot(english));
    });
  });

  group('폴링으로 새 회원 객체가 와도 다시 부르지 않는다 (#2768)', () {
    late _CountingReports reports;
    late ProviderContainer container;

    setUp(() {
      reports = _CountingReports();
      container = ProviderContainer(
        overrides: <Override>[
          reportRepositoryProvider.overrideWithValue(reports),
        ],
      );
      addTearDown(container.dispose);
    });

    test('weeklyReportProvider — 한 번만 읽고 같은 값을 준다', () async {
      final WeeklyReport first = await container.read(
        weeklyReportProvider(ReportKey(client: minsu, weekStart: week)).future,
      );
      for (int poll = 0; poll < 3; poll++) {
        final ReportKey polled = ReportKey(
          client: _polled(minsu, lastMessage: 'poll $poll'),
          weekStart: week,
        );
        expect(container.exists(weeklyReportProvider(polled)), isTrue);
        final WeeklyReport again = await container.read(
          weeklyReportProvider(polled).future,
        );
        expect(identical(again, first), isTrue);
      }

      expect(reports.watches, 1);
    });

    test('reportFeedbackDraftProvider — 한 번만 읽는다', () async {
      final ProviderSubscription<AsyncValue<ReportFeedbackDraft>> keep =
          container.listen(
            reportFeedbackDraftProvider(
              ReportKey(client: minsu, weekStart: week),
            ),
            (_, _) {},
          );
      addTearDown(keep.close);
      await container.read(
        reportFeedbackDraftProvider(
          ReportKey(client: minsu, weekStart: week),
        ).future,
      );
      await container.read(
        reportFeedbackDraftProvider(
          ReportKey(client: _polled(minsu), weekStart: week),
        ).future,
      );

      expect(reports.drafts, 1);
    });

    test('reportSummaryProvider — 폴링으로는 다시 만들지 않고 언어가 바뀌면 만든다', () async {
      ReportSummaryKey keyOf(TrainerClient c, String lang) =>
          (report: ReportKey(client: c, weekStart: week), locale: Locale(lang));
      final ProviderSubscription<AsyncValue<ReportSummary>> keep = container
          .listen(reportSummaryProvider(keyOf(minsu, 'ko')), (_, _) {});
      addTearDown(keep.close);
      await container.read(reportSummaryProvider(keyOf(minsu, 'ko')).future);
      await container.read(
        reportSummaryProvider(keyOf(_polled(minsu), 'ko')).future,
      );
      expect(reports.summaries, 1);

      await container.read(
        reportSummaryProvider(keyOf(_polled(minsu), 'en')).future,
      );
      expect(reports.summaries, 2);
    });

    test('이름이 바뀐 회원은 새로 읽어 새 이름이 실린다', () async {
      await container.read(
        weeklyReportProvider(ReportKey(client: minsu, weekStart: week)).future,
      );
      final WeeklyReport renamed = await container.read(
        weeklyReportProvider(
          ReportKey(
            client: makeClient(id: minsu.id, name: '김민수B'),
            weekStart: week,
          ),
        ).future,
      );

      expect(reports.watches, 2);
      expect(renamed.memberName, '김민수B');
    });
  });

  group('편집기 (#2768)', () {
    final Finder feedbackField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '회원에게 전달할 코칭 피드백을 작성하세요.',
    );

    testWidgets('명단 폴링 한 주기가 지나도 편집기가 깜빡이지 않고 입력이 이어진다', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final _CountingReports reports = _CountingReports();
      final StreamController<List<TrainerClient>> roster =
          StreamController<List<TrainerClient>>.broadcast();
      addTearDown(roster.close);
      Stream<List<TrainerClient>> rosterStream() async* {
        yield <TrainerClient>[minsu];
        yield* roster.stream;
      }

      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.reportFor('seed-client-1'),
        extraOverrides: <Override>[
          reportRepositoryProvider.overrideWithValue(reports),
          clientsProvider.overrideWith((ref) => rosterStream()),
        ],
      );
      await settle(tester);
      // ② 작성 — 피드백 입력창과 요약 카드가 서는 단계다.
      await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
      await settle(tester);

      await tester.tap(feedbackField);
      await tester.enterText(feedbackField, '이번 주 잘했어요');
      await tester.pump();
      final int watches = reports.watches;
      final int summaries = reports.summaries;
      final int drafts = reports.drafts;

      // 실서버 명단 폴링 — 내용이 같은 새 객체 목록이 온다.
      roster.add(<TrainerClient>[_polled(minsu, lastMessage: '방금 온 메시지')]);
      await tester.pump();
      expect(find.byType(AppLoading), findsNothing);
      await settle(tester);

      expect(reports.watches, watches);
      expect(reports.summaries, summaries);
      expect(reports.drafts, drafts);
      expect(find.byType(AppLoading), findsNothing);
      final EditableText editable = tester.widget<EditableText>(
        find.descendant(of: feedbackField, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(editable.controller.text, '이번 주 잘했어요');
    });
  });
}
