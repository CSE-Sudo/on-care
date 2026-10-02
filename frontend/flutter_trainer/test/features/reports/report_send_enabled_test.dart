/// 전송 버튼의 활성 상태가 입력창의 실제 문구와 같은가. (#2771)
///
/// 예전에는 `비었는가` 를 입력 이벤트로만 따로 들고 있어 두 길에서 어긋났다.
///  * (A) 회원 A 의 문구를 다 지우고 회원 B 를 열면, B 에는 자동 문구가 있는데
///    전송이 잠겨 있었다.
///  * (B) 빈 초안을 저장하고 다시 열면, 입력창은 비었는데 전송이 켜져 있어 빈
///    문구가 나갔다(데모는 빈 말풍선, 실서버는 한국어 기본 문장).
library;

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/report_queue_summary.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/pages/reports_page.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_send_preview.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 회원마다 저장된 초안을 정해 두는 저장소. 보낸 글을 모은다.
class _Drafts implements ReportRepository {
  _Drafts([this.stored = const <String, String>{}]);

  /// 회원 id → 저장된 초안. 없는 회원은 저장한 적 없는 주다.
  final Map<String, String> stored;
  final List<String> sent = <String>[];

  @override
  Stream<List<ReportQueueSummary>> watchQueue({
    required List<TrainerClient> clients,
    required DateTime weekStart,
  }) => reportQueueFromReports(this, clients: clients, weekStart: weekStart);

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) => Stream<WeeklyReport>.value(
    buildWeeklyReport(client: client, sessions: const [], weekStart: weekStart),
  );

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
  }) async {
    final String? body = stored[client.id];
    if (body == null) return const ReportFeedbackDraft.none();
    return ReportFeedbackDraft(body: body, saved: true);
  }

  @override
  Future<ReportFeedbackDraft> saveFeedbackDraft({
    required String clientId,
    required DateTime weekStart,
    required String body,
  }) async {
    stored[clientId] = body;
    return ReportFeedbackDraft(body: body, saved: true);
  }

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
  }) async => sent.add(message);

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

class _InstantPdf extends ReportPdfGenerator {
  @override
  Future<Uint8List> generate({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) async => Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);
}

void main() {
  final Finder sendButton = find.byKey(
    const ValueKey<String>('report-step-send'),
  );
  final Finder nextButton = find.byKey(
    const ValueKey<String>('report-step-next'),
  );
  final Finder prevButton = find.byKey(
    const ValueKey<String>('report-step-prev'),
  );
  final Finder feedbackField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == '회원에게 전달할 코칭 피드백을 작성하세요.',
  );

  bool sendEnabled(WidgetTester tester) =>
      tester.widget<AppButton>(sendButton).onPressed != null;

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(feedbackField).controller!.text;

  Future<void> open(
    WidgetTester tester,
    _Drafts reports, {
    String clientId = 'seed-client-1',
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.reportFor(clientId),
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(reports),
        reportPdfGeneratorProvider.overrideWithValue(_InstantPdf()),
        reportPdfRasterizerProvider.overrideWithValue(
          (Uint8List bytes) async => <Uint8List>[bytes],
        ),
      ],
    );
    await settle(tester);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(nextButton);
    await settle(tester);
  }

  testWidgets('(A) 앞 회원의 문구를 지우고 다른 회원을 열면 그 회원의 자동 문구로 전송이 켜진다', (
    tester,
  ) async {
    await open(tester, _Drafts(<String, String>{}));
    await next(tester);
    await tester.enterText(feedbackField, '');
    await settle(tester);
    await next(tester);
    expect(sendEnabled(tester), isFalse);

    // 회원 목록으로 돌아가 다른 회원을 연다.
    await tester.tap(
      find.byKey(const ValueKey<String>('reports-back-to-list')),
    );
    await settle(tester);
    GoRouter.of(
      tester.element(find.byType(ReportsPage)),
    ).go(AppRoutes.reportFor('seed-client-2'));
    await settle(tester);
    await next(tester);
    expect(fieldText(tester).trim(), isNotEmpty);
    await next(tester);

    expect(sendEnabled(tester), isTrue);
  });

  testWidgets('(B) 빈 초안이 저장된 주는 입력창이 비어 있고 전송이 꺼져 있다', (tester) async {
    final _Drafts reports = _Drafts(<String, String>{'seed-client-1': ''});
    await open(tester, reports);
    await next(tester);
    expect(fieldText(tester), isEmpty);
    await next(tester);

    expect(sendEnabled(tester), isFalse);
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == '피드백을 입력하면 전송할 수 있어요',
      ),
      findsOneWidget,
    );
    await tester.tap(sendButton, warnIfMissed: false);
    await settle(tester);
    expect(reports.sent, isEmpty);
  });

  testWidgets('글을 넣으면 켜지고 모두 지우면 꺼진다', (tester) async {
    final _Drafts reports = _Drafts(<String, String>{'seed-client-1': ''});
    await open(tester, reports);
    await next(tester);

    await tester.enterText(feedbackField, '이번 주 수고했어요');
    await settle(tester);
    await next(tester);
    expect(sendEnabled(tester), isTrue);

    await tester.tap(prevButton);
    await settle(tester);
    await tester.enterText(feedbackField, '   ');
    await settle(tester);
    await next(tester);
    expect(sendEnabled(tester), isFalse);
  });

  testWidgets('저장된 초안이 있으면 그 문구로 전송이 켜지고 그 글이 나간다', (tester) async {
    final _Drafts reports = _Drafts(<String, String>{
      'seed-client-1': '저장해 둔 피드백',
    });
    await open(tester, reports);
    await next(tester);
    await next(tester);

    expect(sendEnabled(tester), isTrue);
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await settle(tester);
    expect(reports.sent, <String>['저장해 둔 피드백']);
  });

  group('데모 저장소', () {
    late AppDatabase db;

    setUp(() async {
      useFixedKstDate(kMidWeekKst);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db, clock: kMidWeekKst);
    });

    tearDown(() async {
      await db.close();
    });

    test('빈 문구 전송은 거절하고 채팅에 빈 말풍선을 남기지 않는다', () async {
      final DriftChatRepository chat = DriftChatRepository(db);
      final LocalReportRepository reports = LocalReportRepository(
        DriftScheduleRepository(db),
        chat,
        db,
      );
      final int before = (await chat.watchThread('seed-client-1').first)
          .where((m) => m.reportWeekStart != null)
          .length;

      for (final String blank in <String>['', '   ', '\n']) {
        await expectLater(
          reports.sendPdf(
            clientId: 'seed-client-1',
            weekStart: weekStartOf(nowKst()),
            bytes: Uint8List(0),
            fileName: 'weekly.pdf',
            message: blank,
          ),
          throwsA(isA<ValidationError>()),
        );
      }

      final int after = (await chat.watchThread('seed-client-1').first)
          .where((m) => m.reportWeekStart != null)
          .length;
      expect(after, before);
    });

    test('글이 있으면 그대로 채팅에 남긴다', () async {
      final DriftChatRepository chat = DriftChatRepository(db);
      final LocalReportRepository reports = LocalReportRepository(
        DriftScheduleRepository(db),
        chat,
        db,
      );

      await reports.sendPdf(
        clientId: 'seed-client-1',
        weekStart: weekStartOf(nowKst()),
        bytes: Uint8List(0),
        fileName: 'weekly.pdf',
        message: '이번 주 리포트예요',
      );

      final thread = await chat.watchThread('seed-client-1').first;
      expect(thread.map((m) => m.body), contains('이번 주 리포트예요'));
    });
  });
}
