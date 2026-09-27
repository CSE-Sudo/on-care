/// 리포트 탭이 서버의 전송 이력을 읽는가. (#2288)
///
/// 예전에는 전송 기록이 앱 메모리에만 있어, 새로고침하면 이미 보낸 회원이
/// 작업대의 미전송 줄로 돌아가고 같은 리포트를 아무 확인 없이 다시 보낼 수
/// 있었다. 이 파일이 지키는 것:
///  * 새로 연 작업대가 서버 이력만으로 `전송 완료` 열을 세운다.
///  * 이미 보낸 회원에게 다시 보내려 하면 먼저 묻고, 취소하면 보내지 않는다.
///  * 이력을 읽지 못하면 작업대가 그 사실을 말한다 — 조용히 미전송으로 세우지
///    않는다. 한·영 두 로케일 모두.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/sent_report_view.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

import '../../helpers/pump_app.dart';

/// 시연의 주인공 — 데모 명단에서는 이번 주 미전송이다.
const String _minsu = 'seed-client-1';

/// PDF 생성은 즉시 끝나는 가짜로 둔다. 실 생성기는 dart:ui 래스터를 거쳐
/// fake pump 로 settle 되지 않는다 — 이 파일이 보는 것은 전송 흐름이다.
class _InstantPdfGenerator extends ReportPdfGenerator {
  @override
  Future<Uint8List> generate({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) async => Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);
}

/// 서버 이력을 흉내 내는 자리. 몇 번 물었는지 센다.
class _History {
  _History(this.records, {this.fail = false});

  final Map<String, ReportSendRecord> records;
  final bool fail;
  int asked = 0;

  Override get override =>
      reportSendHistoryProvider.overrideWith((ref, DateTime week) async {
        asked++;
        if (fail) throw StateError('history failed');
        return records;
      });
}

Map<String, ReportSendRecord> _sentThisWeek(
  String clientId, {
  String message = '지난번에 보낸 리포트',
  DateTime? sentAt,
}) {
  final DateTime monday = weekStartOf(nowKst());
  return <String, ReportSendRecord>{
    sendLogKey(clientId, monday): ReportSendRecord(
      clientId: clientId,
      weekStart: monday,
      sentAt: sentAt ?? monday.add(const Duration(hours: 9)),
      message: message,
      read: false,
    ),
  };
}

void main() {
  Future<ProviderContainer> open(
    WidgetTester tester, {
    required _History history,
    String at = AppRoutes.reports,
    Locale locale = const Locale('ko'),
    int stage = 0,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProviderContainer container = await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: at,
      locale: locale,
      extraOverrides: <Override>[
        history.override,
        reportPdfGeneratorProvider.overrideWithValue(_InstantPdfGenerator()),
      ],
    );
    await settle(tester);
    for (int i = 0; i < stage; i++) {
      await tester.tap(find.byKey(const ValueKey<String>('report-step-next')));
      await settle(tester);
    }
    return container;
  }

  /// 편집기 하단의 `전송` 버튼을 누른다 — 헤더 공유 메뉴가 물러난 뒤(#2389)
  /// 리포트를 보내는 길은 이것 하나뿐이다.
  Future<void> tapSend(WidgetTester tester) async {
    final Finder send = find.byKey(const ValueKey<String>('report-step-send'));
    await tester.ensureVisible(send);
    await tester.pump();
    await tester.tap(send);
    await settle(tester);
  }

  Future<int> reportMessages(
    WidgetTester tester,
    ProviderContainer container,
    String clientId,
  ) async {
    final List<ClientChatMessage>? thread = await tester.runAsync(
      () => container.read(chatRepositoryProvider).watchThread(clientId).first,
    );
    return thread!.where((m) => m.reportWeekStart != null).length;
  }

  group('작업대', () {
    testWidgets('새로 연 작업대가 서버에 남은 전송을 전송 완료 열에 세운다', (tester) async {
      await open(tester, history: _History(_sentThisWeek(_minsu)));

      expect(
        find.byKey(const ValueKey<String>('reports-sent-$_minsu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('reports-queue-$_minsu')),
        findsNothing,
      );
    });

    testWidgets('안 읽음 안내는 목록 밑이 아니라 전송 완료 상자 바닥에 선다 (#2396)', (tester) async {
      await open(tester, history: _History(_sentThisWeek(_minsu)));

      final Finder hint = find.byKey(
        const ValueKey<String>('reports-sent-unread-hint'),
      );
      expect(hint, findsOneWidget);
      final Rect box = tester.getRect(
        find.byKey(const ValueKey<String>('reports-workbench-sent')),
      );
      final Rect row = tester.getRect(
        find.byKey(const ValueKey<String>('reports-sent-$_minsu')),
      );
      final Rect hintRect = tester.getRect(hint);
      // 상자 바닥 — 카드 안쪽 여백만큼만 위다.
      expect(box.bottom - hintRect.bottom, lessThan(40));
      // 한 줄뿐이니 줄 바로 밑과는 떨어져 있다.
      expect(hintRect.top - row.bottom, greaterThan(100));
    });

    testWidgets('서버 이력이 비어 있으면 그 회원은 미전송 줄에 선다', (tester) async {
      await open(tester, history: _History(<String, ReportSendRecord>{}));

      expect(
        find.byKey(const ValueKey<String>('reports-queue-$_minsu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('reports-sent-$_minsu')),
        findsNothing,
      );
    });

    testWidgets('서버 이력의 줄을 누르면 회원이 받은 글을 그대로 본다', (tester) async {
      await open(
        tester,
        history: _History(_sentThisWeek(_minsu, message: '서버에 남은 그 글')),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('reports-sent-$_minsu')),
      );
      await settle(tester);

      expect(find.byType(SentReportView), findsOneWidget);
      expect(find.text('서버에 남은 그 글'), findsOneWidget);
    });

    testWidgets('이력을 읽지 못하면 경고를 띄운다', (tester) async {
      await open(
        tester,
        history: _History(<String, ReportSendRecord>{}, fail: true),
      );

      final Finder warning = find.byKey(
        const ValueKey<String>('reports-send-history-failed'),
      );
      expect(warning, findsOneWidget);
      expect(
        find.text('전송 이력을 불러오지 못했어요. 이미 보낸 회원이 미전송으로 보일 수 있어요.'),
        findsOneWidget,
      );
    });

    testWidgets('이력 경고는 영어 화면에서도 영어로 선다', (tester) async {
      await open(
        tester,
        history: _History(<String, ReportSendRecord>{}, fail: true),
        locale: const Locale('en'),
      );

      expect(
        find.text(
          "Couldn't load send history. Members you've already sent to may "
          'show as not sent.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('이력을 읽었으면 경고가 없다', (tester) async {
      await open(tester, history: _History(<String, ReportSendRecord>{}));

      expect(
        find.byKey(const ValueKey<String>('reports-send-history-failed')),
        findsNothing,
      );
    });
  });

  group('다시 보내기 확인', () {
    testWidgets('이미 보낸 회원에게 보내려 하면 먼저 묻고, 취소하면 보내지 않는다', (tester) async {
      final ProviderContainer container = await open(
        tester,
        history: _History(_sentThisWeek(_minsu)),
        at: AppRoutes.reportFor(_minsu),
        stage: 2,
      );
      final int before = await reportMessages(tester, container, _minsu);

      await tapSend(tester);

      expect(find.text('이미 보낸 리포트예요'), findsOneWidget);
      expect(find.textContaining('김민수님에게'), findsWidgets);
      expect(find.textContaining('다시 보내면 회원 채팅에 한 번 더 도착해요'), findsOneWidget);

      await tester.tap(find.text('취소'));
      await settle(tester);

      expect(find.text('이미 보낸 리포트예요'), findsNothing);
      expect(await reportMessages(tester, container, _minsu), before);
    });

    testWidgets('확인하면 다시 보내고 서버 이력을 다시 읽는다', (tester) async {
      final _History history = _History(_sentThisWeek(_minsu));
      final ProviderContainer container = await open(
        tester,
        history: history,
        at: AppRoutes.reportFor(_minsu),
        stage: 2,
      );
      final int before = await reportMessages(tester, container, _minsu);
      final int askedBefore = history.asked;

      await tapSend(tester);
      await tester.tap(find.text('다시 보내기'));
      await settle(tester);

      expect(await reportMessages(tester, container, _minsu), before + 1);
      expect(history.asked, greaterThan(askedBefore));
    });

    testWidgets('보낸 적 없는 회원은 묻지 않고 바로 보낸다', (tester) async {
      final ProviderContainer container = await open(
        tester,
        history: _History(<String, ReportSendRecord>{}),
        at: AppRoutes.reportFor(_minsu),
        stage: 2,
      );
      final int before = await reportMessages(tester, container, _minsu);

      await tapSend(tester);

      expect(find.text('이미 보낸 리포트예요'), findsNothing);
      expect(await reportMessages(tester, container, _minsu), before + 1);
      // 보낸 뒤에는 작업대로 돌아가고, 그 회원은 전송 완료 열에 선다.
      expect(
        find.byKey(const ValueKey<String>('reports-sent-$_minsu')),
        findsOneWidget,
      );
    });

    testWidgets('이력을 읽지 못해도 전송은 막지 않는다 — 경고가 이미 서 있다', (tester) async {
      final ProviderContainer container = await open(
        tester,
        history: _History(<String, ReportSendRecord>{}, fail: true),
        at: AppRoutes.reportFor(_minsu),
        stage: 2,
      );
      final int before = await reportMessages(tester, container, _minsu);

      await tapSend(tester);

      expect(find.text('이미 보낸 리포트예요'), findsNothing);
      expect(await reportMessages(tester, container, _minsu), before + 1);
    });

    testWidgets('데모 명단에서 이미 보낸 회원도 다시 보내기 전에 묻는다', (tester) async {
      // seed-client-5 는 데모 작업대의 전송 완료 쪽에 선다.
      await open(
        tester,
        history: _History(<String, ReportSendRecord>{}),
        at: AppRoutes.reportFor('seed-client-5'),
        stage: 2,
      );

      await tapSend(tester);

      expect(find.text('이미 보낸 리포트예요'), findsOneWidget);
    });

    testWidgets('영어 화면의 확인 창은 영어로 묻는다', (tester) async {
      await open(
        tester,
        history: _History(_sentThisWeek(_minsu)),
        at: AppRoutes.reportFor(_minsu),
        locale: const Locale('en'),
        stage: 2,
      );

      await tapSend(tester);

      expect(find.text('Already sent'), findsOneWidget);
      expect(find.text('Send again'), findsOneWidget);
      expect(
        find.textContaining('Sending it again delivers a second copy'),
        findsOneWidget,
      );
    });
  });
}
