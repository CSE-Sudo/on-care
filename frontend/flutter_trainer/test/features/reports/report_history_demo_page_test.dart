/// 데모 작업대가 지난 주에도 그 주 전송 이력대로 서는가. (#2399)
///
/// 예전에는 데모 전송 기록이 이번 주에만 붙어, 주 이동으로 지난 주에 가면
/// 열다섯 명이 전부 `미전송` 에 섰다. 이 파일이 지키는 것:
///  * 지난 주 작업대의 `전송 완료`·`미전송` 이 그 주 데모 이력과 같다.
///  * 이번 주에 붙은 신규 회원은 지난 주에 보낸 기록이 없다.
///  * 지난 주 `전송 완료` 줄의 `보기` 를 누르면 그 주 수치로 만든 피드백이
///    열린다 — 목표별 고정 문장이 아니다(#2423).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_nav.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/sent_report_view.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 지난 주 월요일 — [kMidWeekKst](2026-08-20 목)의 한 주 전.
final DateTime _lastMonday = DateTime(2026, 8, 10);

/// 로스터 열다섯 명.
final List<DemoReportMember> _roster = <DemoReportMember>[
  for (int i = 1; i <= 15; i++) (id: 'seed-client-$i'),
];

void main() {
  final Finder prevWeek = find.descendant(
    of: find.byType(ReportWeekNav),
    matching: find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
  );

  Future<void> openLastWeek(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.reports,
      seedClock: kMidWeekKst,
    );
    await settle(tester);
    await tester.tap(prevWeek);
    await settle(tester);
  }

  Set<String> sentLastWeek() => <String>{
    for (final ReportSendRecord r in demoSentReportsForWeek(
      roster: _roster,
      weekStart: _lastMonday,
      today: kMidWeekKst,
    ))
      r.clientId,
  };

  testWidgets('지난 주 작업대의 두 열이 그 주 데모 이력대로 선다', (tester) async {
    await openLastWeek(tester);

    final Set<String> sent = sentLastWeek();
    expect(sent, isNotEmpty);
    for (final DemoReportMember m in _roster) {
      final bool wasSent = sent.contains(m.id);
      expect(
        find.byKey(ValueKey<String>('reports-sent-${m.id}')),
        wasSent ? findsOneWidget : findsNothing,
        reason: '${m.id} 전송 완료',
      );
      expect(
        find.byKey(ValueKey<String>('reports-queue-${m.id}')),
        wasSent ? findsNothing : findsOneWidget,
        reason: '${m.id} 미전송',
      );
    }
  });

  testWidgets('이번 주에 붙은 신규 회원은 지난 주 미전송에 선다', (tester) async {
    await openLastWeek(tester);

    expect(
      find.byKey(const ValueKey<String>('reports-queue-seed-client-7')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('reports-sent-seed-client-7')),
      findsNothing,
    );
  });

  testWidgets('지난 주 전송 완료 줄의 보기를 누르면 그 주 수치로 만든 피드백이 열린다', (tester) async {
    await openLastWeek(tester);

    // 최우진은 매주 빠짐없이 받는다 — 지난 주도 전송 완료다.
    const String id = 'seed-client-5';
    final ReportSendRecord record = demoSentReportsForWeek(
      roster: <DemoReportMember>[(id: id)],
      weekStart: _lastMonday,
      today: kMidWeekKst,
    ).single;
    // 본문을 적어 두지 않는다 — 화면이 그 주 수치로 만든다(#2423).
    expect(record.message, isEmpty);

    final Finder view = find.byKey(const ValueKey<String>('reports-view-$id'));
    await tester.ensureVisible(view);
    await tester.tap(view);
    await settle(tester);

    expect(find.byType(SentReportView), findsOneWidget);
    Finder inView(String text) => find.descendant(
      of: find.byType(SentReportView),
      matching: find.textContaining(text),
    );
    // 그 주 수치로 만든 초안이다 — 인사말이 첫 문단이다.
    expect(inView('주간 리포트 정리해서 보내드려요'), findsOneWidget);
    // 예전 목표별 고정 문장은 남지 않는다.
    expect(inView('체력은 쉬지 않고 이어 가는 게 핵심이에요'), findsNothing);
  });
}
