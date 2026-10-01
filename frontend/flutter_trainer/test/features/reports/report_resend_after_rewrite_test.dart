/// 같은 주에 보낸 회원을 `다시 쓰기` 로 고쳐 다시 보낼 수 있는가. (#2770)
///
/// 예전에는 편집기가 이번 세션에 보낸 회원을 기억해 두고 전송을 조용히
/// 돌려보냈다. 다시 쓰기로 고친 리포트의 ③ 전송이 오류도 확인창도 없이 아무
/// 반응이 없었다. 이 파일이 지키는 것:
///  * 다시 쓰기로 연 편집기의 전송은 서버 기록 기반 재전송 확인창을 띄운다.
///  * 확인하면 고친 문구로 다시 나가고, 취소하면 나가지 않는다.
///  * 지난 리포트의 다시 쓰기(주소로 편집기를 다시 여는 길)도 같다.
///  * 전송 중 연타는 여전히 한 번만 보낸다.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/pages/reports_page.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_send_preview.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// 시연의 주인공 — 데모 명단에서는 이번 주 미전송이다.
const String _minsu = 'seed-client-1';

/// 부를 때마다 [gate] 가 열릴 때까지 기다리는 PDF 생성기. 비어 있으면 곧바로 낸다.
class _GatedPdfGenerator extends ReportPdfGenerator {
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<Uint8List> generate({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) async {
    calls++;
    final Completer<void>? wait = gate;
    if (wait != null) await wait.future;
    return Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);
  }
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

  Future<ProviderContainer> open(
    WidgetTester tester, {
    _GatedPdfGenerator? pdf,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProviderContainer container = await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.reportFor(_minsu),
      extraOverrides: <Override>[
        // 서버 이력은 비어 있다 — 이미 보냈다는 근거는 이번 세션의 전송뿐이다.
        reportSendHistoryProvider.overrideWith(
          (ref, DateTime week) async => const <String, ReportSendRecord>{},
        ),
        reportPdfGeneratorProvider.overrideWithValue(
          pdf ?? _GatedPdfGenerator(),
        ),
        reportPdfRasterizerProvider.overrideWithValue(
          (Uint8List bytes) async => <Uint8List>[bytes],
        ),
      ],
    );
    await settle(tester);
    return container;
  }

  Future<void> tapSend(WidgetTester tester) async {
    await tester.ensureVisible(sendButton);
    await tester.pump();
    await tester.tap(sendButton);
    await settle(tester);
  }

  /// ① 에서 ② 로 가 [text] 로 고치고 ③ 으로 간다.
  Future<void> rewriteAndGoToSend(WidgetTester tester, String text) async {
    await tester.tap(nextButton);
    await settle(tester);
    await tester.enterText(feedbackField, text);
    await settle(tester);
    await tester.tap(nextButton);
    await settle(tester);
  }

  Future<List<ClientChatMessage>> reportMessages(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final List<ClientChatMessage>? thread = await tester.runAsync(
      () => container.read(chatRepositoryProvider).watchThread(_minsu).first,
    );
    return thread!.where((m) => m.reportWeekStart != null).toList();
  }

  /// 처음 한 번 보내고 작업대로 돌아온다.
  Future<void> sendOnce(WidgetTester tester) async {
    await tester.tap(nextButton);
    await settle(tester);
    await tester.tap(nextButton);
    await settle(tester);
    await tapSend(tester);
    expect(
      find.byKey(const ValueKey<String>('reports-sent-$_minsu')),
      findsOneWidget,
    );
  }

  /// 작업대의 `전송 완료` 줄 → 보낸 리포트 → `이 내용으로 다시 작성`.
  Future<void> rewriteFromWorkbench(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('reports-view-$_minsu')),
    );
    await settle(tester);
    await tester.tap(find.text('이 내용으로 다시 작성'));
    await settle(tester);
    expect(nextButton, findsOneWidget);
  }

  testWidgets('다시 쓰기로 고쳐 전송하면 재전송 확인창이 뜨고, 확인하면 고친 문구로 간다', (tester) async {
    final ProviderContainer container = await open(tester);
    await sendOnce(tester);
    final int before = (await reportMessages(tester, container)).length;

    await rewriteFromWorkbench(tester);
    await rewriteAndGoToSend(tester, '고친 피드백입니다');
    expect(find.byType(ReportSendPreview), findsOneWidget);
    expect(tester.widget<AppButton>(sendButton).onPressed, isNotNull);
    await tapSend(tester);

    // 무반응이 아니라 확인창이 선다.
    expect(find.text('이미 보낸 리포트예요'), findsOneWidget);
    await tester.tap(find.text('다시 보내기'));
    await settle(tester);

    final List<ClientChatMessage> after = await reportMessages(
      tester,
      container,
    );
    expect(after.length, before + 1);
    expect(after.map((m) => m.body), contains('고친 피드백입니다'));
  });

  testWidgets('다시 쓰기 뒤 확인창에서 취소하면 보내지 않는다', (tester) async {
    final ProviderContainer container = await open(tester);
    await sendOnce(tester);
    final int before = (await reportMessages(tester, container)).length;

    await rewriteFromWorkbench(tester);
    await rewriteAndGoToSend(tester, '보내지 않을 글');
    await tapSend(tester);
    expect(find.text('이미 보낸 리포트예요'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await settle(tester);

    expect(find.text('이미 보낸 리포트예요'), findsNothing);
    expect((await reportMessages(tester, container)).length, before);
    // 편집기 ③ 에 그대로 남아 다시 누를 수 있다.
    expect(sendButton, findsOneWidget);
  });

  testWidgets('지난 리포트의 다시 쓰기(주소로 편집기를 다시 여는 길)도 확인창을 거친다', (tester) async {
    final ProviderContainer container = await open(tester);
    await sendOnce(tester);
    final int before = (await reportMessages(tester, container)).length;

    // 지난 리포트의 `열기`·다시 쓰기는 편집기 주소로 간다(`_openEditor`).
    GoRouter.of(
      tester.element(find.byType(ReportsPage)),
    ).go(AppRoutes.reportFor(_minsu));
    await settle(tester);
    await rewriteAndGoToSend(tester, '이력에서 고친 글');
    await tapSend(tester);

    expect(find.text('이미 보낸 리포트예요'), findsOneWidget);
    await tester.tap(find.text('다시 보내기'));
    await settle(tester);
    final List<ClientChatMessage> after = await reportMessages(
      tester,
      container,
    );
    expect(after.length, before + 1);
    expect(after.map((m) => m.body), contains('이력에서 고친 글'));
  });

  testWidgets('전송 중 연타는 한 번만 보낸다', (tester) async {
    final _GatedPdfGenerator pdf = _GatedPdfGenerator();
    final ProviderContainer container = await open(tester, pdf: pdf);
    final int before = (await reportMessages(tester, container)).length;
    await tester.tap(nextButton);
    await settle(tester);
    await tester.tap(nextButton);
    await settle(tester);

    // PDF 를 새로 만들게 해 전송이 길어지도록 미리보기를 버리고 문을 닫는다.
    pdf.gate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey<String>('report-step-prev')));
    await settle(tester);
    await tester.enterText(feedbackField, '연타 확인');
    await settle(tester);
    await tester.tap(nextButton);
    await tester.pump();
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton, warnIfMissed: false);
    await tester.pump();
    await tester.tap(sendButton, warnIfMissed: false);
    await tester.pump();
    pdf.gate!.complete();
    await settle(tester);

    expect((await reportMessages(tester, container)).length, before + 1);
  });
}
