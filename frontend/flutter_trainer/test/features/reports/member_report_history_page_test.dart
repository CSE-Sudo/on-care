/// 회원별 지난 리포트 — 리포트 탭 안의 길. (#2394)
///
/// 데모 앱을 통째로 띄워 작업대·편집기·보낸 리포트에서 지난 리포트로 들어가고
/// 나오는 길을 걷는다. 이 파일이 지키는 것:
///  * 작업대 줄은 통째로 눌리지 않는다 — `지난 리포트`·`열기`/`보기` 버튼만
///    눌린다.
///  * 작업대의 `지난 리포트` 가 그 회원의 지난 리포트를 연다(URL `history=`).
///  * 지난 리포트의 `보기` 가 그 주 보낸 리포트를 열고, 돌아가기는 `지난 리포트`
///    로 돌아온다. `< 회원 목록` 은 보던 주의 작업대로 돌아간다.
///  * 보낸 리포트·편집기 제목 줄의 `지난 리포트` 링크도 같은 화면을 연다.
///  * 이번 주를 안 보낸 회원은 `미전송 · 열기` 로 이번 주 편집기에 들어간다.
///  * URL 로 바로 들어와도 같은 화면이 선다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/member_report_history_view.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_nav.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/sent_report_view.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 최우진 — 매주 빠짐없이 받는 회원이라 이번 주도 이미 보냈다.
const String _steady = 'seed-client-5';

/// 임도현 — 이번 주에 붙은 신규 회원이라 보낸 리포트가 없다.
const String _newcomer = 'seed-client-7';

/// [kMidWeekKst](2026-08-20 목) 기준의 주들.
const String _thisWeek = '2026-08-17';
const String _lastWeek = '2026-08-10';

/// 데모 리포트 이력의 가장 오래된 주 — 이번 주에서 13주 전.
const String _oldestWeek = '2026-05-18';

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void main() {
  final Finder prevWeek = find.descendant(
    of: find.byType(ReportWeekNav),
    matching: find.widgetWithIcon(IconButton, AppIcons.chevronLeft),
  );
  final Finder historyTitle = _key('reports-history-title');

  Map<String, String> query(WidgetTester tester) =>
      Uri.parse(currentLocation(tester)).queryParameters;

  /// 데모 DB 는 실제 시간으로 읽힌다 — 줄이 붙을 때까지 기다린다.
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await waitFor(tester, finder);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> open(
    WidgetTester tester, {
    String at = AppRoutes.reports,
    Locale locale = const Locale('ko'),
    Size size = const Size(1600, 2400),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: at,
      seedClock: kMidWeekKst,
      locale: locale,
    );
    await settle(tester);
  }

  testWidgets('작업대 줄을 눌러도 아무 데도 가지 않는다', (tester) async {
    await open(tester);
    final Finder row = _key('reports-queue-$_newcomer');
    await waitFor(tester, row);
    await tester.ensureVisible(row);
    await tester.pump();

    // 버튼이 아닌 왼쪽 이름 자리를 누른다.
    await tester.tapAt(tester.getTopLeft(row) + const Offset(24, 24));
    await settle(tester);

    expect(currentLocation(tester), AppRoutes.reports);
    expect(find.byType(ReportWorkbench), findsOneWidget);
  });

  testWidgets('작업대 미전송 줄에 지난 리포트·열기, 전송 완료 줄에 지난 리포트·보기가 선다', (tester) async {
    await open(tester);
    await waitFor(tester, _key('reports-sent-$_steady'));

    for (final (String id, String primary) in <(String, String)>[
      (_newcomer, 'reports-open-$_newcomer'),
      (_steady, 'reports-view-$_steady'),
    ]) {
      expect(_key('reports-history-$id'), findsOneWidget, reason: id);
      expect(_key(primary), findsOneWidget, reason: id);
      expect(
        find.descendant(
          of: _key('reports-history-$id'),
          matching: find.text('지난 리포트'),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: _key('reports-open-$_newcomer'),
        matching: find.text('열기'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _key('reports-view-$_steady'),
        matching: find.text('보기'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('작업대의 지난 리포트가 그 회원의 지난 리포트를 연다', (tester) async {
    await open(tester);
    await tapAndSettle(tester, _key('reports-history-$_steady'));

    expect(query(tester), <String, String>{'history': _steady});
    expect(find.byType(MemberReportHistoryView), findsOneWidget);
    expect(tester.widget<Text>(historyTitle).data, endsWith('님의 지난 리포트'));
    // 이번 주도 이미 보냈으니 미전송 줄 없이 이번 주가 맨 위다.
    await waitFor(tester, _key('reports-history-week-$_thisWeek'));
    expect(_key('reports-history-unsent'), findsNothing);
    expect(_key('reports-history-week-$_lastWeek'), findsOneWidget);
    // 지난 주 줄에는 그때 보낸 글의 첫 줄이 선다.
    expect(_key('reports-history-preview-$_lastWeek'), findsOneWidget);
  });

  testWidgets('보기로 그 주 보낸 리포트를 열고, 돌아가기는 지난 리포트로 온다', (tester) async {
    await open(tester);
    await tapAndSettle(tester, _key('reports-history-$_steady'));
    await tapAndSettle(tester, _key('reports-history-view-$_lastWeek'));

    expect(_key('reports-history-sent-$_lastWeek'), findsOneWidget);
    expect(find.byType(SentReportView), findsOneWidget);
    expect(
      find.descendant(
        of: _key('reports-sent-back'),
        matching: find.text('지난 리포트'),
      ),
      findsOneWidget,
    );
    // 보던 작업대의 주는 움직이지 않는다 — URL 도 그대로다.
    expect(query(tester), <String, String>{'history': _steady});

    await tapAndSettle(tester, _key('reports-sent-back'));
    expect(historyTitle, findsOneWidget);
    expect(find.byType(SentReportView), findsNothing);
  });

  // 지난 리포트의 ① 칼로리 줄은 그 주 앞 4주와 견준다(#2453). `이번 주 평균` 만
  // 남으면 트레이너가 그 수가 이 회원에게 많은지 알 길이 없다.
  final Finder baselineLine = find.textContaining(
    '지난 4주 평균',
    findRichText: true,
  );
  // 증감은 같은 줄의 기준 뒤에 붙는다 — 다른 카드의 ▲/▼ 와 섞이지 않게
  // 한 줄 안에서 찾는다.
  final Finder deltaMark = find.textContaining(
    RegExp('지난 4주 평균 [0-9,]+kcal +[▲▼][0-9,]+kcal'),
    findRichText: true,
  );

  testWidgets('지난 리포트 보기의 칼로리 줄에 지난 4주 평균과 증감이 선다 (#2453)', (tester) async {
    await open(tester);
    await tapAndSettle(tester, _key('reports-history-$_steady'));
    await tapAndSettle(tester, _key('reports-history-view-$_lastWeek'));
    await waitFor(tester, baselineLine);

    expect(find.byType(SentReportView), findsOneWidget);
    expect(baselineLine, findsOneWidget);
    expect(deltaMark, findsOneWidget);
  });

  testWidgets('지난 리포트의 가장 오래된 주에도 지난 4주 평균이 선다 (#2453)', (tester) async {
    await open(tester);
    await tapAndSettle(tester, _key('reports-history-$_steady'));
    await tapAndSettle(tester, _key('reports-history-more'));
    await tapAndSettle(tester, _key('reports-history-view-$_oldestWeek'));
    await waitFor(tester, baselineLine);

    expect(_key('reports-history-sent-$_oldestWeek'), findsOneWidget);
    expect(baselineLine, findsOneWidget);
    expect(deltaMark, findsOneWidget);
  });

  testWidgets('작업대를 가장 오래된 주로 옮겨 연 편집기에도 지난 4주 평균이 선다 (#2453)', (tester) async {
    await open(
      tester,
      at: AppRoutes.reportFor(_steady, weekStart: DateTime.parse(_oldestWeek)),
    );
    await waitFor(tester, baselineLine);

    expect(baselineLine, findsOneWidget);
    expect(deltaMark, findsOneWidget);
  });

  testWidgets('회원 목록으로 돌아가면 작업대다', (tester) async {
    await open(tester);
    await tapAndSettle(tester, _key('reports-history-$_steady'));
    await tapAndSettle(tester, _key('reports-history-back'));

    expect(currentLocation(tester), AppRoutes.reports);
    expect(find.byType(ReportWorkbench), findsOneWidget);
    expect(historyTitle, findsNothing);
  });

  testWidgets('지난 주 작업대에서 들어갔다 나오면 지난 주 작업대로 돌아간다', (tester) async {
    await open(tester);
    await waitFor(tester, prevWeek);
    await tester.tap(prevWeek);
    await settle(tester);
    expect(query(tester)['week'], _lastWeek);

    await tapAndSettle(tester, _key('reports-history-$_steady'));
    expect(query(tester), <String, String>{
      'history': _steady,
      'week': _lastWeek,
    });

    await tapAndSettle(tester, _key('reports-history-back'));
    expect(query(tester), <String, String>{'week': _lastWeek});
    expect(find.byType(ReportWorkbench), findsOneWidget);
  });

  testWidgets('작업대에서 연 보낸 리포트의 지난 리포트 링크도 같은 화면을 연다', (tester) async {
    await open(tester);
    await tapAndSettle(tester, _key('reports-view-$_steady'));
    expect(find.byType(SentReportView), findsOneWidget);
    // 작업대에서 연 보낸 리포트는 원래대로 이번 주 리포트로 돌아간다.
    expect(
      find.descendant(
        of: _key('reports-sent-back'),
        matching: find.text('이번 주 리포트'),
      ),
      findsOneWidget,
    );

    await tapAndSettle(tester, _key('reports-sent-history'));
    expect(query(tester), <String, String>{'history': _steady});
    expect(historyTitle, findsOneWidget);
  });

  testWidgets('편집기 제목 줄의 지난 리포트가 그 회원의 지난 리포트를 연다', (tester) async {
    await open(tester);
    await tapAndSettle(tester, _key('reports-open-$_newcomer'));
    expect(query(tester), <String, String>{'client': _newcomer});

    await tapAndSettle(tester, _key('reports-editor-history'));
    expect(query(tester), <String, String>{'history': _newcomer});
    expect(historyTitle, findsOneWidget);
  });

  testWidgets('보낸 적 없는 회원은 빈 안내와 미전송·열기로 이번 주 편집기에 간다', (tester) async {
    await open(tester);
    await tapAndSettle(tester, _key('reports-history-$_newcomer'));
    await waitFor(tester, _key('reports-history-empty'));

    expect(_key('reports-history-empty'), findsOneWidget);
    expect(_key('reports-history-unsent'), findsOneWidget);

    await tapAndSettle(tester, _key('reports-history-open'));
    expect(query(tester), <String, String>{'client': _newcomer});
    expect(find.byType(MemberReportHistoryView), findsNothing);
  });

  testWidgets('URL 로 바로 들어와도 지난 리포트가 선다', (tester) async {
    await open(tester, at: AppRoutes.reportHistoryFor(_steady));
    await waitFor(tester, historyTitle);

    expect(historyTitle, findsOneWidget);
    await waitFor(tester, _key('reports-history-week-$_lastWeek'));
    expect(_key('reports-history-week-$_lastWeek'), findsOneWidget);
  });

  testWidgets('영어로 바꾸면 영어 제목과 버튼이다', (tester) async {
    await open(tester, locale: const Locale('en'));
    await waitFor(tester, _key('reports-history-$_steady'));
    expect(
      find.descendant(
        of: _key('reports-history-$_steady'),
        matching: find.text('Past reports'),
      ),
      findsOneWidget,
    );

    await tapAndSettle(tester, _key('reports-history-$_steady'));
    expect(tester.widget<Text>(historyTitle).data, endsWith("'s past reports"));
    expect(
      find.descendant(
        of: _key('reports-history-back'),
        matching: find.text('Member list'),
      ),
      findsOneWidget,
    );
    await waitFor(tester, _key('reports-history-view-$_lastWeek'));
    expect(
      find.descendant(
        of: _key('reports-history-view-$_lastWeek'),
        matching: find.text('View'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('가장 좁은 지원 폭·영어·큰 글자에서도 버튼이 넘치지 않는다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(
      tester,
      locale: const Locale('en'),
      size: const Size(1024, 2400),
    );

    // 작업대에서 연 보낸 리포트 — 제목 줄에 지난 리포트·다시 쓰기 두 버튼.
    await tapAndSettle(tester, _key('reports-view-$_steady'));
    expect(_key('reports-sent-history'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 지난 리포트 목록과 거기서 연 보낸 리포트.
    await tapAndSettle(tester, _key('reports-sent-history'));
    await waitFor(tester, _key('reports-history-view-$_lastWeek'));
    expect(tester.takeException(), isNull);
    await tapAndSettle(tester, _key('reports-history-view-$_lastWeek'));
    expect(_key('reports-history-sent-$_lastWeek'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
