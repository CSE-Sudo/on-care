/// 전송이 앱에서 실패로 끝났을 때 화면이 서버 기록을 따라잡는가. (#2773)
///
/// 응답을 기다리다 끊기면 앱은 실패지만 서버에는 저장돼 회원이 이미 받았을 수
/// 있다. 예전에는 실패 토스트만 띄우고 기록을 다시 읽지 않아, 작업대가 그
/// 회원을 미전송으로 둔 채 같은 회원·주로 다시 보낼 수 없었다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_send_preview.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

const String _minsu = 'seed-client-1';

/// 서버를 흉내 내는 저장소. [failWith] 가 있으면 전송이 그 오류로 끝나되,
/// [storedAnyway] 면 서버에는 남는다(응답만 끊긴 경우).
class _FlakyServer implements ReportRepository {
  _FlakyServer({this.failWith, this.storedAnyway = false});

  AppError? failWith;
  final bool storedAnyway;

  /// 서버에 남은 전송.
  final List<ReportSendRecord> stored = <ReportSendRecord>[];

  /// 앱이 전송 기록을 물은 횟수.
  int historyAsked = 0;

  /// 앱이 회원별 지난 리포트를 물은 횟수.
  int memberHistoryAsked = 0;

  /// 앱이 보내려 한 문구.
  final List<String> attempts = <String>[];

  @override
  Future<void> sendPdf({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async {
    attempts.add(message);
    final AppError? error = failWith;
    if (error == null || storedAnyway) {
      stored.add(
        ReportSendRecord(
          clientId: clientId,
          weekStart: weekStartOf(weekStart),
          sentAt: DateTime(2026, 8, 12, 9),
          message: message,
          read: false,
        ),
      );
    }
    if (error != null) throw error;
  }

  @override
  Future<List<ReportSendRecord>> sentReports({
    required DateTime weekStart,
  }) async {
    historyAsked++;
    return List<ReportSendRecord>.of(stored);
  }

  @override
  Future<MemberReportHistoryPage> memberReportHistory({
    required String clientId,
    DateTime? before,
    int limit = memberReportHistoryPageSize,
  }) async {
    memberHistoryAsked++;
    return const MemberReportHistoryPage.empty();
  }

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
  final Finder feedbackField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == '회원에게 전달할 코칭 피드백을 작성하세요.',
  );
  const String failedToast = '리포트 전송에 실패했어요. 다시 시도해 주세요';
  const String alreadyToast = '이미 전송된 리포트예요. 전송 기록을 다시 불러왔어요';

  Future<void> openAtSend(WidgetTester tester, _FlakyServer server) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.reportFor(_minsu),
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(server),
        reportPdfGeneratorProvider.overrideWithValue(_InstantPdf()),
        reportPdfRasterizerProvider.overrideWithValue(
          (Uint8List bytes) async => <Uint8List>[bytes],
        ),
      ],
    );
    await settle(tester);
    await tester.tap(nextButton);
    await settle(tester);
    await tester.tap(nextButton);
    await settle(tester);
  }

  Future<void> tapSend(WidgetTester tester) async {
    await tester.ensureVisible(sendButton);
    await tester.pump();
    await tester.tap(sendButton);
    await settle(tester);
  }

  testWidgets('응답이 끊겨 실패해도 기록을 다시 읽어, 서버에 남은 전송을 작업대가 따라잡는다', (tester) async {
    final _FlakyServer server = _FlakyServer(
      failWith: const NetworkError(),
      storedAnyway: true,
    );
    await openAtSend(tester, server);
    final int askedBefore = server.historyAsked;
    final int memberAskedBefore = server.memberHistoryAsked;

    await tapSend(tester);

    expect(find.text(failedToast), findsOneWidget);
    expect(server.historyAsked, greaterThan(askedBefore));
    expect(server.memberHistoryAsked, greaterThanOrEqualTo(memberAskedBefore));
    // 편집기 ③ 에 머문다.
    expect(find.byType(ReportSendPreview), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('reports-back-to-list')),
    );
    await settle(tester);
    expect(
      find.byKey(const ValueKey<String>('reports-sent-$_minsu')),
      findsOneWidget,
    );
  });

  testWidgets('실패 뒤 문구를 고쳐 다시 보내면 재전송 확인을 거쳐 새로고침 없이 나간다', (tester) async {
    final _FlakyServer server = _FlakyServer(
      failWith: const NetworkError(),
      storedAnyway: true,
    );
    await openAtSend(tester, server);
    await tapSend(tester);
    expect(find.text(failedToast), findsOneWidget);

    // 이번에는 정상이다.
    server.failWith = null;
    await tester.tap(find.byKey(const ValueKey<String>('report-step-prev')));
    await settle(tester);
    await tester.enterText(feedbackField, '고친 문구');
    await settle(tester);
    await tester.tap(nextButton);
    await settle(tester);
    await tapSend(tester);

    // 서버에 첫 판이 남아 있으니 다시 보낼지 묻는다.
    expect(find.text('이미 보낸 리포트예요'), findsOneWidget);
    await tester.tap(find.text('다시 보내기'));
    await settle(tester);

    expect(server.attempts.last, '고친 문구');
    expect(
      find.byKey(const ValueKey<String>('reports-sent-$_minsu')),
      findsOneWidget,
    );
  });

  testWidgets('409 는 실패가 아니라 이미 보냈다고 알린다', (tester) async {
    final _FlakyServer server = _FlakyServer(
      failWith: const ServerError(statusCode: 409),
      storedAnyway: true,
    );
    await openAtSend(tester, server);
    final int askedBefore = server.historyAsked;

    await tapSend(tester);

    expect(find.text(alreadyToast), findsOneWidget);
    expect(find.text(failedToast), findsNothing);
    expect(server.historyAsked, greaterThan(askedBefore));
    // 다시 누를 수 있다 — 화면이 잠기지 않는다.
    expect(tester.widget<AppButton>(sendButton).onPressed, isNotNull);
  });

  testWidgets('다른 서버 오류는 그대로 실패라고 알린다', (tester) async {
    final _FlakyServer server = _FlakyServer(
      failWith: const ServerError(statusCode: 500),
    );
    await openAtSend(tester, server);

    await tapSend(tester);

    expect(find.text(failedToast), findsOneWidget);
    expect(find.text(alreadyToast), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('reports-back-to-list')),
    );
    await settle(tester);
    expect(
      find.byKey(const ValueKey<String>('reports-sent-$_minsu')),
      findsNothing,
    );
  });

  testWidgets('영어 화면의 409 안내는 영어다', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _FlakyServer server = _FlakyServer(
      failWith: const ServerError(statusCode: 409),
      storedAnyway: true,
    );
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.reportFor(_minsu),
      locale: const Locale('en'),
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(server),
        reportPdfGeneratorProvider.overrideWithValue(_InstantPdf()),
        reportPdfRasterizerProvider.overrideWithValue(
          (Uint8List bytes) async => <Uint8List>[bytes],
        ),
      ],
    );
    await settle(tester);
    await tester.tap(nextButton);
    await settle(tester);
    await tester.tap(nextButton);
    await settle(tester);

    await tapSend(tester);

    expect(
      find.text(
        'This report was already sent. Send history has been refreshed',
      ),
      findsOneWidget,
    );
  });
}
