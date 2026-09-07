import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show weekdayCount;
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/bar_line_chart.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/client_report_view.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/metric_comparison_section.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_client_picker.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_pdf_export_dialog.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_nav.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/week_trend_bar.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_actions.dart';
import 'package:oncare_trainer/features/reports/services/report_pdf_generator.dart';
import 'package:oncare_trainer/features/search/presentation/widgets/client_search_bar.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/action_button.dart';
import 'package:oncare_trainer/shared/widgets/metric_trend_chart.dart';
import 'package:oncare_trainer/shared/widgets/mini_charts.dart';
import 'package:oncare_trainer/shared/widgets/page_scaffold.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 요약 생성만 실패한다 — 리포트 본문은 정상이라 카드 하나만 폴백으로 간다.
class _SummaryFailsRepository implements ReportRepository {
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
  }) async => throw StateError('summary provider down');

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
}

/// 이번 주 리포트의 요일 칸에 실제로 뜨는 김민수의 운동 이름 하나.
///
/// 값은 공유 픽스처가 갖고 있다(#757). 화면은 ✓/✗ 표시를 떼고 이름만 보여 준다.
String _minsuExerciseThisWeek() {
  final DemoFixture fixture = DemoFixture.parse(
    File('../../shared/demo_fixture/assets/kim_minsu.json').readAsStringSync(),
  );
  final List<FixtureDay> days = fixture.daysFor(nowKst());
  final String monday = days.last.weekStart;
  for (final FixtureDay day in days.reversed) {
    if (day.weekStart != monday) break;
    if (day.exercises.isNotEmpty) return day.exercises.first.name;
  }
  throw StateError('이번 주에 운동한 날이 없다 — 요일 칸이 전부 비어 검증이 뜻을 잃는다');
}

class _ReportFailsOncePerKeyRepository implements ReportRepository {
  final Map<String, int> _attempts = <String, int>{};
  final List<ReportKey> calls = <ReportKey>[];

  @override
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
  }) async => ruleReportSummary(
    buildWeeklyReport(client: client, sessions: const [], weekStart: weekStart),
    client,
  );

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) {
    final key = '${client.id}/${weekStart.toIso8601String()}';
    calls.add((client: client, weekStart: weekStart));
    final attempt = (_attempts[key] ?? 0) + 1;
    _attempts[key] = attempt;
    if (attempt == 1) {
      return Stream<WeeklyReport>.error(StateError('report transport detail'));
    }
    return Stream<WeeklyReport>.value(
      buildWeeklyReport(
        client: client,
        sessions: const [],
        weekStart: weekStart,
      ),
    );
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
  }) async {}

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
}

/// 리포트 against the seeded roster — the trainer's own week plus one
/// client's report, and sending it into their chat thread.
void main() {
  /// 헤더의 공유 메뉴를 연다 — 전송은 이제 이 메뉴 안에 있다(#735).
  Future<void> openShareMenu(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('reports-share-action')),
    );
    await settle(tester);
  }

  /// 리포트 본문의 피드백 입력창.
  final Finder feedbackField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == '회원에게 전달할 코칭 피드백을 작성하세요.',
  );

  /// 리포트 카드 제목 줄의 주 이동 화살표. 헤더가 아니라 카드 안에 있다(#1177).
  final Finder prevWeek = find.byKey(
    const ValueKey<String>('report-week-prev'),
  );
  final Finder nextWeek = find.byKey(
    const ValueKey<String>('report-week-next'),
  );

  Future<ProviderContainer> openReports(
    WidgetTester tester, {
    String? clientId,
    Size size = const Size(1600, 1200),
    List<Override> extraOverrides = const <Override>[],
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: clientId == null ? AppRoutes.reports : AppRoutes.reportFor(clientId),
      extraOverrides: extraOverrides,
    );
  }

  testWidgets('shows the trainer week alongside a client report', (
    tester,
  ) async {
    await openReports(tester);

    expect(find.text('리포트'), findsWidgets);
    expect(find.text('이번 주 vs 지난 주'), findsOneWidget);
    expect(find.text('트레이너 피드백'), findsOneWidget);
    expect(find.text('다음 주'), findsNothing);
    // 비교 그래프는 지표 넷을 한 자리에서 돌려 쓴다 — 알약 버튼이 그 넷이다.
    // 운동 상자와 식단 상자가 각자의 지표를 들고 나란히 선다.
    for (final metric in <String>[
      'burned',
      'cardio',
      'strength',
      'stretching',
    ]) {
      expect(
        find.byKey(ValueKey<String>('compare-exercise-$metric')),
        findsOneWidget,
      );
    }
    for (final metric in <String>['calories', 'sodium', 'sugar']) {
      expect(
        find.byKey(ValueKey<String>('compare-diet-$metric')),
        findsOneWidget,
      );
    }
    // Defaults to the first client rather than an empty right pane.
    expect(find.text('김민수님 주간 리포트'), findsOneWidget);
    // 카드 안에 회원 신상을 다시 적지 않는다 — 왼쪽 목록에서 방금 고른
    // 회원이고, 카드 제목이 이미 누구의 리포트인지 말한다(#1177).
    expect(
      find.descendant(
        of: find.byType(ClientReportView),
        matching: find.text('남성 · 35세'),
      ),
      findsNothing,
    );
  });

  testWidgets('비교 상자는 알약 버튼으로 지표를 갈아 끼운다 (#1177)', (tester) async {
    await openReports(tester);

    // 식단 상자는 칼로리로 열리고, 막대는 탄·단·지로 쌓이므로 그 셋이
    // 무엇인지 적어 준다. 회원 목록에도 `체지방 감량` 같은 목표가 있어 비교
    // 상자 안으로 범위를 좁혀 본다.
    Finder inBox(String text) => find.descendant(
      of: find.byType(MetricComparisonSection),
      matching: find.textContaining(text),
    );
    expect(inBox('탄수화물'), findsOneWidget);
    expect(inBox('단백질'), findsOneWidget);
    expect(inBox('지방'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('compare-diet-sugar')));
    await settle(tester);
    expect(inBox('탄수화물'), findsNothing);

    // 운동 상자는 따로 움직인다 — 식단 지표를 바꿔도 그대로다.
    await tester.tap(
      find.byKey(const ValueKey<String>('compare-exercise-cardio')),
    );
    await settle(tester);
    expect(
      find.byKey(const ValueKey<String>('compare-exercise-cardio')),
      findsOneWidget,
    );
  });

  testWidgets('공유는 상단에서 전송과 PDF 내보내기를 함께 보여 준다 (#735)', (tester) async {
    await openReports(tester);

    final shareAction = find.byKey(
      const ValueKey<String>('reports-share-action'),
    );
    expect(shareAction, findsOneWidget);
    expect(tester.getCenter(shareAction).dy, lessThan(88));
    // 메뉴를 열기 전에는 항목이 보이지 않는다.
    expect(find.text('PDF 내보내기'), findsNothing);

    await openShareMenu(tester);
    expect(find.text('김민수님에게 전송'), findsOneWidget);
    expect(find.text('PDF 내보내기'), findsOneWidget);
    // PDF 는 현재 리포트로 실제 binary를 만드는 경로와 연결된다.
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey<String>('reports-share-pdf')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('PDF 대화상자의 저장과 인쇄는 각각 플랫폼 경계를 호출한다', (tester) async {
    final actions = _RecordingPdfActions();
    final container = await openReports(
      tester,
      extraOverrides: <Override>[
        reportPdfActionsProvider.overrideWithValue(actions),
      ],
    );
    final client = (await container.read(clientsProvider.future)).first;
    final report = buildWeeklyReport(
      client: client,
      sessions: const [],
      weekStart: DateTime(2026, 8, 10),
    );
    final bytes = Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);

    showDialog<void>(
      context: tester.element(find.byType(Scaffold).last),
      builder: (_) => ReportPdfExportDialog(report: report, bytes: bytes),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('report-pdf-save')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('report-pdf-print')));
    await tester.pump();

    expect(actions.savedBytes, same(bytes));
    expect(actions.printedBytes, same(bytes));
    expect(actions.savedName, '${client.name}_2026-08-10_주간리포트.pdf');
    expect(actions.printedName, actions.savedName);
  });

  testWidgets('PDF 생성 중에는 중복을 막고 실패 후 재시도한다', (tester) async {
    final first = Completer<Uint8List>();
    final generator = _QueuedPdfGenerator(<Future<Uint8List>>[
      first.future,
      Future<Uint8List>.value(
        Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
      ),
    ]);
    await openReports(
      tester,
      extraOverrides: <Override>[
        reportPdfGeneratorProvider.overrideWithValue(generator),
      ],
    );

    await openShareMenu(tester);
    await tester.tap(find.byKey(const ValueKey<String>('reports-share-pdf')));
    await settle(tester);
    expect(generator.calls, 1);

    await openShareMenu(tester);
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey<String>('reports-share-pdf')),
          )
          .onPressed,
      isNull,
    );
    await openShareMenu(tester); // 열려 있는 메뉴를 닫는다. 재시도는 아래에서 연다.
    first.completeError(StateError('render failed'));
    await settle(tester);
    expect(find.text('PDF를 생성하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);

    // 실패가 현재 리포트를 없애지 않고, 재시도는 액션 대화상자로 이어진다.
    await openShareMenu(tester);
    await tester.tap(find.byKey(const ValueKey<String>('reports-share-pdf')));
    await settle(tester);
    expect(generator.calls, 2);
    expect(
      find.byKey(const ValueKey<String>('report-pdf-send')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('report-pdf-save')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('report-pdf-print')),
      findsOneWidget,
    );
  });

  // ---- 요약 카드 자리와 주 이동 라벨 (#897) ----

  testWidgets('넓은 화면에서 요약 카드는 회원 목록 바로 아래에 놓인다 (#897)', (tester) async {
    await openReports(tester);

    final Finder leftColumn = find.byKey(
      const ValueKey<String>('reports-left-column'),
    );
    final Finder summaryTitle = find.text('AI 코칭 보조 · 리포트 요약');
    expect(summaryTitle, findsOneWidget);
    // 왼쪽 열 안에 있고, 회원 목록보다 아래다.
    expect(
      find.descendant(of: leftColumn, matching: summaryTitle),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(summaryTitle).dy,
      greaterThan(
        tester
            .getTopLeft(
              find.descendant(of: leftColumn, matching: find.text('회원')),
            )
            .dy,
      ),
    );
    // 오른쪽 리포트 열에는 더 이상 같은 카드가 없다.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reports-report-scroll')),
        matching: summaryTitle,
      ),
      findsNothing,
    );
  });

  testWidgets('짧은 창에서도 요약 카드가 띠로 눌리지 않는다 (#1177)', (tester) async {
    // 목록이 열을 거의 다 쓰는 높이다. `Expanded` 만 쓰면 요약이 몇 픽셀짜리
    // 띠가 되어 내용이 넘치고, 렌더 오버플로가 난다.
    await openReports(tester, size: const Size(1600, 700));

    expect(tester.takeException(), isNull);
    final Finder summary = find.text('AI 코칭 보조 · 리포트 요약');
    expect(summary, findsOneWidget);
    // 열은 그 대신 스스로 스크롤한다.
    expect(
      find.byKey(const ValueKey<String>('reports-left-scroll')),
      findsOneWidget,
    );
  });

  testWidgets('좁은 화면 목록에서는 요약 자리에 무엇이 뜨는지 알린다 (#897)', (tester) async {
    await openReports(tester, size: const Size(700, 1000));

    expect(find.text('회원을 선택하면 그 주의 리포트 요약과 코칭 제안이 여기에 표시돼요'), findsOneWidget);
    // 아직 고른 회원이 없으니 요약을 만들지 않는다.
    expect(find.text('피드백으로 가져오기'), findsNothing);
  });

  testWidgets('주 이동은 리포트 카드 제목 줄에서 하고, 보고 있는 주를 적는다 (#1177)', (tester) async {
    await openReports(tester);

    String rangeOf(DateTime start) {
      final DateTime end = start.add(const Duration(days: 6));
      return '${start.month}월 ${start.day}일 – ${end.month}월 ${end.day}일';
    }

    final DateTime thisWeek = weekStartOf(nowKst());
    // 헤더가 아니라 카드 안이다 — 제목과 같은 줄에서 지금 보고 있는 주를 적는다.
    expect(
      find.descendant(
        of: find.byType(ClientReportView),
        matching: find.text(rangeOf(thisWeek)),
      ),
      findsOneWidget,
    );

    await tester.tap(prevWeek);
    await settle(tester);

    final DateTime lastWeek = thisWeek.subtract(const Duration(days: 7));
    expect(find.text(rangeOf(lastWeek)), findsOneWidget);
    expect(find.text(rangeOf(thisWeek)), findsNothing);

    // 오른쪽 화살표로 되돌아온다.
    await tester.tap(nextWeek);
    await settle(tester);
    expect(find.text(rangeOf(thisWeek)), findsOneWidget);
  });

  testWidgets('가장 최근 주에서는 다음 주 화살표가 죽어 있다 (#1177)', (tester) async {
    await openReports(tester);

    InkResponse arrow(Finder finder) => tester.widget<InkResponse>(finder);
    expect(arrow(nextWeek).onTap, isNull, reason: '앞으로 갈 주가 없다');
    expect(arrow(prevWeek).onTap, isNotNull);

    await tester.tap(prevWeek);
    await settle(tester);
    expect(arrow(nextWeek).onTap, isNotNull);
  });

  testWidgets('`이번 주` 버튼은 주 이동 줄 안에 있고 이번 주에서는 아예 감춘다 (#1177, #1245)', (
    tester,
  ) async {
    await openReports(tester);

    final Finder currentWeek = find.byKey(
      const ValueKey<String>('reports-go-this-week'),
    );
    // 헤더에는 더 이상 없다.
    expect(
      find.descendant(
        of: find.byType(PageScaffold),
        matching: find.widgetWithText(ActionButton, '이번 주로'),
      ),
      findsNothing,
    );
    // 스케줄 탭의 `오늘` 처럼 이번 주에는 버튼 자체를 그리지 않는다 — 회색
    // 비활성이 아니라 미표시다. 자리는 고정폭 슬롯이 대신 지켜, 화살표는
    // 밀리지 않는다.
    expect(currentWeek, findsNothing);

    await tester.tap(prevWeek);
    await settle(tester);

    // 스케줄 탭의 `오늘` 처럼 두 화살표 사이에 선다 — 옮기는 대상과 같은 줄이다.
    expect(
      find.descendant(of: find.byType(ReportWeekNav), matching: currentWeek),
      findsOneWidget,
    );
    expect(tester.widget<ActionButton>(currentWeek).onPressed, isNotNull);
    // 비교 카드와 최근 4주 목록에 같은 말이 쓰인다.
    expect(find.text('선택 주'), findsWidgets);

    await tester.tap(currentWeek);
    await settle(tester);

    expect(currentWeek, findsNothing);
  });

  testWidgets('채팅의 리포트 카드가 가리킨 주로 열린다 (#1421)', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.reset);

    // 카드는 지나간 주를 가리킨다 — 이번 주로 열리면 트레이너가 어느 주였는지
    // 다시 찾아야 한다.
    final DateTime lastWeek = weekStartOf(
      nowKst(),
    ).subtract(const Duration(days: 7));
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.reportFor('seed-client-1', weekStart: lastWeek),
    );
    await settle(tester);

    final DateTime weekEnd = lastWeek.add(const Duration(days: 6));
    expect(
      find.text(
        '${lastWeek.month}월 ${lastWeek.day}일 – ${weekEnd.month}월 ${weekEnd.day}일',
      ),
      findsWidgets,
    );
    // 이번 주가 아니라는 증거 — 이번 주에는 이 버튼을 아예 그리지 않는다.
    expect(
      find.byKey(const ValueKey<String>('reports-go-this-week')),
      findsOneWidget,
    );
  });

  testWidgets('`이번 주` 버튼 여부와 무관하게 날짜·화살표 묶음은 중앙이다 (#1295)', (
    WidgetTester tester,
  ) async {
    await openReports(tester);

    final Finder nav = find.byType(ReportWeekNav);
    double arrowGroupCenter() =>
        (tester.getCenter(prevWeek).dx + tester.getCenter(nextWeek).dx) / 2;

    final double currentNavCenter = tester.getCenter(nav).dx;
    expect(arrowGroupCenter(), closeTo(currentNavCenter, 0.5));
    final double currentPrevX = tester.getCenter(prevWeek).dx;
    final double currentNextX = tester.getCenter(nextWeek).dx;

    await tester.tap(prevWeek);
    await settle(tester);

    expect(
      find.byKey(const ValueKey<String>('reports-go-this-week')),
      findsOneWidget,
    );
    expect(arrowGroupCenter(), closeTo(tester.getCenter(nav).dx, 0.5));
    expect(tester.getCenter(prevWeek).dx, closeTo(currentPrevX, 0.5));
    expect(tester.getCenter(nextWeek).dx, closeTo(currentNextX, 0.5));
  });

  testWidgets('헤더 검색 바가 다른 탭과 같은 인라인 모양이다 (#1177)', (tester) async {
    await openReports(tester);

    // 날짜 버튼이 헤더 폭을 먹던 때에는 가운데 검색 바가 아이콘으로 접혀,
    // 리포트 탭만 다른 탭과 다른 모양이었다.
    expect(find.byKey(clientSearchFieldKey), findsOneWidget);
    expect(find.byKey(clientSearchIconKey), findsNothing);
    // 대시보드에서 보는 것과 같은 폭·같은 안내 문구다.
    final double reportsWidth = tester
        .getSize(find.byKey(clientSearchFieldKey))
        .width;
    expect(find.text('회원·목표·최근 메시지·마지막 프로그램 전송일 검색'), findsOneWidget);

    await goTo(tester, AppRoutes.dashboard);
    expect(
      tester.getSize(find.byKey(clientSearchFieldKey)).width,
      closeTo(reportsWidth, 0.5),
    );
  });

  testWidgets('좁은 화면에서 회원 선택 시 목록 대신 상세를 바로 연다', (tester) async {
    await openReports(
      tester,
      size: const Size(700, 1000),
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            makeClient(id: 'mobile-client', name: '모바일 회원'),
          ]),
        ),
      ],
    );

    expect(find.text('모바일 회원님 주간 리포트'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('reports-back-to-list')),
      findsNothing,
    );

    await tester.tap(find.text('모바일 회원'));
    await settle(tester);

    final back = find.byKey(const ValueKey<String>('reports-back-to-list'));
    expect(back, findsOneWidget);
    expect(find.text('모바일 회원님 주간 리포트'), findsOneWidget);
    expect(tester.getTopLeft(back).dy, lessThan(220));

    await tester.tap(back);
    await settle(tester);

    expect(back, findsNothing);
    expect(find.text('모바일 회원님 주간 리포트'), findsNothing);
    // 목록으로 돌아오면 회원 카드가 다시 보인다.
    expect(find.text('회원'), findsWidgets);
  });

  testWidgets('the client query parameter focuses that client', (tester) async {
    await openReports(tester, clientId: 'seed-client-3');
    expect(find.text('박성호님 주간 리포트'), findsOneWidget);
  });

  testWidgets('a failed client roster retries independently', (tester) async {
    int attempts = 0;
    await openReports(
      tester,
      clientId: 'seed-client-3',
      extraOverrides: <Override>[
        clientsProvider.overrideWith((ref) {
          attempts++;
          return attempts == 1
              ? Stream<List<TrainerClient>>.error(
                  StateError('client transport detail'),
                )
              : Stream<List<TrainerClient>>.value(<TrainerClient>[
                  makeClient(id: 'seed-client-1', name: '첫 회원'),
                  makeClient(id: 'seed-client-3', name: '복구 회원'),
                ]);
        }),
      ],
    );

    expect(find.text('리포트를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('client transport detail'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('reports-clients-retry')),
    );
    await settle(tester);

    expect(attempts, 2);
    expect(find.text('복구 회원님 주간 리포트'), findsOneWidget);
  });

  testWidgets('weekly report retry keeps the selected client and week', (
    tester,
  ) async {
    final repository = _ReportFailsOncePerKeyRepository();
    await openReports(
      tester,
      clientId: 'seed-client-3',
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(repository),
      ],
    );

    await tester.tap(prevWeek);
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('reports-weekly-retry')),
    );
    await settle(tester);

    final selectedWeek = weekStartOf(
      nowKst(),
    ).subtract(const Duration(days: 7));
    final selectedCalls = repository.calls
        .where(
          (call) =>
              call.client.id == 'seed-client-3' &&
              call.weekStart == selectedWeek,
        )
        .toList();
    // Comparison/trend cards legitimately request adjacent weeks too. The
    // failed selected week itself must still be retried without losing scope.
    expect(selectedCalls.length, greaterThanOrEqualTo(2));
    expect(find.text('박성호님 주간 리포트'), findsOneWidget);
    expect(find.text('report transport detail'), findsNothing);
  });

  testWidgets('picking another client swaps the report', (tester) async {
    await openReports(tester);

    // The API does not expose saved feedback status. Session-local send state
    // must not be presented as a persistent member-list status.
    expect(find.text('피드백 미작성'), findsNothing);
    expect(find.text('피드백 완료'), findsNothing);

    await tester.tap(find.text('이지수').last);
    await settle(tester);
    expect(find.text('이지수님 주간 리포트'), findsOneWidget);
  });

  testWidgets('회원 목록은 이름·목표만 적고 이행률 막대는 두지 않는다 (#1177)', (tester) async {
    await openReports(
      tester,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            makeClient(
              id: 'measured',
              name: '기록회원',
              goal: '혈압 관리',
              weekCompletion: const <int>[80, 0, 60, 0, 0, 0, 0],
            ),
          ]),
        ),
      ],
    );

    // 같은 값을 오른쪽 리포트가 훨씬 자세히 말한다 — 고르는 자리에는 이름과
    // 목표만 둔다.
    expect(
      find.byKey(const ValueKey<String>('report-client-completion-measured')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(ReportClientPicker),
        matching: find.byType(InlineBarValue),
      ),
      findsNothing,
    );
    expect(find.text('기록회원'), findsWidgets);
    expect(find.text('혈압 관리'), findsWidgets);
  });

  testWidgets('좁은 리포트 회원 목록도 넘치지 않는다', (tester) async {
    await openReports(
      tester,
      size: const Size(700, 760),
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            makeClient(
              id: 'narrow',
              name: '매우긴이름의회원',
              goal: '체중 감량과 근력 향상을 함께 관리하는 목표',
              weekCompletion: const <int>[100, 100, 100, 100, 100, 100, 100],
            ),
          ]),
        ),
      ],
    );

    expect(
      find.byKey(const ValueKey<String>('report-client-narrow')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report previews exactly what the member will receive', (
    tester,
  ) async {
    await openReports(tester);

    // The preview box is the message body itself, so the trainer can
    // read it before sending rather than discovering it in the thread.
    expect(find.textContaining('주간 리포트'), findsWidgets);
    // PT 진행 횟수는 초안에서 뺐다 — 회원에게 보낼 글이 아니다(#1177).
    expect(find.textContaining('PT 세션'), findsNothing);
    // 전송 경로는 화면에 하나뿐이다 — 본문에는 더 이상 전송 버튼이 없다.
    await openShareMenu(tester);
    expect(find.text('김민수님에게 전송'), findsOneWidget);
  });

  testWidgets('empty feedback cannot be sent', (tester) async {
    await openReports(tester);

    await tester.enterText(feedbackField, '   ');
    await settle(tester);

    await openShareMenu(tester);
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey<String>('reports-share-send')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('전송 delivers the report into the client chat thread', (
    tester,
  ) async {
    // 전송 기본 흐름이 PDF를 만들어 보낸다(#1378) — 실 `ReportPdfGenerator`는
    // dart:ui 래스터를 거쳐 fake pump 로는 settle 되지 않으니, 다른
    // PDF 관련 테스트처럼 즉시 끝나는 가짜로 바꾼다. 이 테스트가 보는 것은
    // "채팅에 도착하는가"이지 PDF 렌더링 자체가 아니다.
    final container = await openReports(
      tester,
      extraOverrides: <Override>[
        reportPdfGeneratorProvider.overrideWithValue(
          _QueuedPdfGenerator(<Future<Uint8List>>[
            Future<Uint8List>.value(
              Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
            ),
          ]),
        ),
      ],
    );
    await openShareMenu(tester);

    await tester.tap(find.text('김민수님에게 전송'));
    await settle(tester);

    // 메뉴 항목이 잠겨 두 번 보내지지 않는다.
    await openShareMenu(tester);
    expect(find.text('전송됨'), findsOneWidget);

    final messages = await tester.runAsync(
      () => container
          .read(chatRepositoryProvider)
          .watchThread('seed-client-1')
          .first,
    );
    expect(
      messages!.map((m) => m.body).where((t) => t.contains('주간 리포트')),
      isNotEmpty,
    );
  });

  testWidgets('a failed send keeps the button actionable and warns', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.reports,
      extraOverrides: <Override>[
        chatRepositoryProvider.overrideWith(
          (ref) => _FailingChatRepository(ref.watch(appDatabaseProvider)),
        ),
        // PDF 생성 자체는 성공해야 이 테스트가 노리는 실패(채팅 전송)만
        // 남는다 — 실 생성기는 fake pump 로 settle 되지 않는다(위 테스트와
        // 같은 이유).
        reportPdfGeneratorProvider.overrideWithValue(
          _QueuedPdfGenerator(<Future<Uint8List>>[
            Future<Uint8List>.value(
              Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
            ),
          ]),
        ),
      ],
    );
    await openShareMenu(tester);

    await tester.tap(find.text('김민수님에게 전송'));
    await settle(tester);

    // No false "전송됨" — the trainer would otherwise believe the member
    // got a report that never arrived.
    expect(find.text('전송됨'), findsNothing);
    expect(find.text('리포트 전송에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
    // 실패해도 작성한 피드백이 남고 다시 보낼 수 있다.
    expect(
      tester.widget<TextField>(feedbackField).controller!.text,
      contains('주간 리포트'),
    );
    await openShareMenu(tester);
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey<String>('reports-share-send')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('추이 그래프는 고른 지표의 주간 계열을 그린다 (#746)', (tester) async {
    final container = await openReports(tester);
    final client = (await container.read(clientsProvider.future)).first;

    Future<void> pickMetric(String name) async {
      final chip = find.byKey(ValueKey<String>('trend-metric-$name'));
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await settle(tester);
    }

    List<double> drawnValues() =>
        tester.widget<MetricTrendChart>(find.byType(MetricTrendChart)).values;

    // 어제는 약속이 있던 날이라 로스터의 평상시 배열 대신 그날 값이 그려진다.
    // 어제가 주 안에서 몇 번째 칸인지는 데모를 여는 날마다 달라지므로 계산해서
    // 덮는다 — 숫자를 박아 두면 하루만 지나도 깨진다.
    final int feastSlot = nowKst().weekday - 2;
    List<double> expected(List<num> series, double feast) {
      final values = series.map((v) => v.toDouble()).toList();
      if (feastSlot >= 0) values[feastSlot] = feast;
      return values;
    }

    // 기본은 칼로리 — 나트륨 하나만 보여 주던 자리를 세 지표가 나눠 쓴다.
    expect(find.text('칼로리 추이'), findsOneWidget);
    expect(drawnValues(), expected(client.caloriesWeek, 2380));

    await pickMetric('sodium');
    expect(find.text('나트륨 추이'), findsOneWidget);
    expect(drawnValues(), expected(client.sodiumWeek, 2261));

    await pickMetric('sugar');
    expect(find.text('당류 추이'), findsOneWidget);
    // 당류는 소수를 유지한다 — 17.8 이 18 로 뭉개지면 요약 수치와 어긋난다.
    expect(drawnValues(), expected(client.sugarWeek, 63.0));
    expect(client.sugarWeek.any((v) => v != v.roundToDouble()), isTrue);
  });

  testWidgets('지난 주도 그 주의 계열로 그려지고 이번 주와 섞이지 않는다 (#752)', (tester) async {
    await openReports(tester);
    List<double> drawnValues() =>
        tester.widget<MetricTrendChart>(find.byType(MetricTrendChart)).values;

    final thisWeek = drawnValues();
    expect(thisWeek, hasLength(7));

    await tester.tap(prevWeek);
    await settle(tester);

    // 과거 주도 그래프가 그려진다 — 예전에는 이 자리가 통째로 비어 있었다.
    final lastWeek = drawnValues();
    expect(lastWeek, hasLength(7));
    expect(lastWeek, isNot(equals(thisWeek)), reason: '이번 주 수치가 그대로 실렸다');
    // 지난 주는 이미 다 지났으니 마지막 요일까지 값이 있다.
    expect(lastWeek.last, greaterThan(0));
    // 지난 주 일요일에 '오늘' 표시가 붙으면 그 날이 오늘인 것처럼 읽힌다.
    expect(
      tester.widget<MetricTrendChart>(find.byType(MetricTrendChart)).markToday,
      isFalse,
    );

    // 지난 주도 요약 줄이 그 주의 값으로 채워진다.
    expect(find.text('최근 4주 평균'), findsOneWidget);
  });

  testWidgets('주를 가리키는 말은 이번 주·지난 주·선택 주 셋뿐이다', (tester) async {
    await openReports(tester);

    // 주 이동 줄은 주 이름 대신 **보고 있는 주의 날짜 범위**를 적는다.
    // '이전 주' 라고 쓰면 비교 카드의 '지난 주' 열과 같은 말이 되어 어느 주를
    // 보고 있는지 헷갈린다.
    expect(prevWeek, findsOneWidget);
    expect(find.textContaining(' – '), findsWidgets);
    expect(find.text('이번 주 vs 지난 주'), findsOneWidget);

    await tester.tap(prevWeek);
    await settle(tester);

    // 과거 주에서는 제목도 보고 있는 주를 따라간다.
    expect(find.text('선택 주 vs 지난 주'), findsOneWidget);
    expect(find.text('이번 주 vs 지난 주'), findsNothing);
    // 앞선 주는 상황과 무관하게 늘 '지난 주' — 비교 카드와 최근 4주 목록이
    // 같은 말을 쓴다.
    expect(find.text('지난 주'), findsWidgets);
    expect(find.text('이전 주'), findsNothing);
  });

  testWidgets('평균이 며칠을 나눈 값인지 화면에 적힌다 (#754)', (tester) async {
    // 기록이 빠진 날을 시드에 기대지 않고 여기서 못 박는다. 시드의 주간 계열은
    // 이번 주 요일 자리에 놓이므로(#746) 월요일에는 오늘 하루만 남고, 기록이
    // 빠진 날이 아예 없어 이 테스트가 요일에 따라 깨졌다(#826).
    const weekCompletion = <int>[80, 0, 90, 70, 0, 60, 0];
    // 막대는 이행률이 아니라 그날 소모 칼로리다(#1289). 두 계열을 따로 두어야
    // 칩(이행률)과 막대(칼로리)가 서로 다른 값을 말하는 것을 확인할 수 있다.
    const burn = <int>[320, 0, 410, 260, 0, 180, 0];
    await openReports(
      tester,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            makeClient(
              id: 'week-client',
              name: '주간회원',
              weekCompletion: weekCompletion,
            ),
          ]),
        ),
        clientExercisePeriodProvider.overrideWith((ref, key) async {
          final ClientDateRange range = clientRangeFor(
            key.period,
            key.day,
            exercise: true,
          );
          final List<DateTime> dates = clientRangeDates(range);
          return ClientExercisePeriod(
            range: range,
            weeklyGoalCalories: 2100,
            days: <ClientExerciseDay>[
              for (int i = 0; i < dates.length; i++)
                ClientExerciseDay(
                  date: dates[i],
                  calories: i < burn.length ? burn[i] : 0,
                  cardioCalories: i < burn.length ? burn[i] : 0,
                ),
            ],
          );
        }),
      ],
    );

    // 기록이 없는 날은 평균에서 빠지므로 7 이 아니다 — 그 사실이 적혀 있어야
    // 트레이너가 아래 막대를 세어 평균을 확인할 수 있다.
    final logged = weekCompletion.where((v) => v > 0).length;
    expect(logged, lessThan(7), reason: '기록이 빠진 날이 있는 회원이어야 한다');
    // 마지막 줄에 이번 주가 앞선 세 주 옆에 놓인다. 며칠을 나눈 값인지는
    // 값이 있는 막대를 세면 나오므로 따로 적지 않는다.
    expect(find.text('최근 4주 평균'), findsOneWidget);

    // 기록이 없는 날은 0kcal 가 아니라 기록이 없다고 말한다. 막대·꺾은선·값이
    // 한 그림이라 글자는 캔버스에 그려진다 — 무엇을 비워 둘지는 그래프가 받는
    // `missing` 이 정한다(#1177).
    expect(find.text('0kcal'), findsNothing);
    final chart = tester.widget<BarLineChart>(
      find.byKey(const ValueKey<String>('reports-burn-chart')),
    );
    // 규칙으로 확인한다 — 요일 번호를 못 박으면 월요일에 도는 CI 에서는
    // 지나간 날이 하루뿐이라 기대값이 통째로 어긋난다.
    final int elapsed = chart.pendingFrom ?? weekdayCount;
    expect(elapsed, nowKst().weekday, reason: '아직 오지 않은 날은 비워 둔다');
    for (var i = 0; i < elapsed; i++) {
      expect(
        chart.values[i],
        burn[i] == 0 ? isNull : burn[i].toDouble(),
        reason: '지난 날의 0 은 기록 없음이고, 그 밖은 그날 소모 칼로리다',
      );
    }
    expect(chart.emptyLabel, '기록 없음');
    // 눈금 끝은 하루 목표(2100/7 = 300)와 그 주 최댓값 중 큰 쪽이다 — 목표를
    // 넘긴 날의 막대가 잘리면 넘겼다는 사실이 사라진다.
    expect(chart.ceiling, 410);
    // 카드 제목 줄이 평균과 며칠을 나눈 값인지 함께 말한다.
    expect(find.text('기록 $logged일'), findsOneWidget);

    // 운동과 식단이 카드로 나뉜다. 운동 카드 제목은 막대가 말하는 값을 따라
    // 소모 칼로리다(#1289) — 이행률은 제목 줄의 칩으로 남는다.
    expect(find.text('주간 소모 칼로리'), findsOneWidget);
    // 칩만 이 문구를 그대로 쓴다 — 요약 문장은 앞에 `· 운동` 이 붙는다.
    expect(find.text('이행률 평균 75%'), findsOneWidget);
    expect(find.text('주간 식단 추이'), findsOneWidget);
    // 식단 카드 제목 옆에 지표 하나의 수치(`나트륨 초과 n일`)를 붙이지 않는다 —
    // 카드가 식단 전체를 말하는 자리다(#1177).
    expect(find.textContaining('나트륨 초과'), findsNothing);
  });

  testWidgets('요일 칸에 그날 한 운동 이름이 남는다 (#754)', (tester) async {
    // 요일 칸에는 운동 이름만 둔다 — 퍼센트는 바로 위 막대가 말하고,
    // 아직 오지 않은 날은 빈칸으로 둔다.
    //
    // 목록의 첫 회원은 김민수라, 그의 운동 이름은 공유 픽스처가 정한다(#757).
    // 이름을 여기 적으면 픽스처와 두 벌이 되어 한쪽만 고쳤을 때 조용히 갈린다.
    // 시드 로스터를 그대로 쓰므로 위 테스트와 달리 회원을 바꾸지 않는다.
    await openReports(tester);

    expect(find.text(_minsuExerciseThisWeek()), findsWidgets);
  });

  testWidgets('요약 카드가 안내문 대신 이번 주 요약을 말한다 (#755)', (tester) async {
    await openReports(tester);

    // 예전에는 이 자리에 "API 연결 후 사용할 수 있어요" 만 있었다.
    expect(
      find.text('실제 리포트 요약 API 연결 후 사용할 수 있어요. 현재 문구는 자동 생성하지 않습니다.'),
      findsNothing,
    );
    // 데모에는 모델이 없어 수치에서 조립한 문장이 온다 — 그래서 'AI 생성'
    // 배지는 달리지 않는다. 트레이너가 이 문장을 어디까지 믿을지 알아야 한다.
    expect(find.text('AI 생성'), findsNothing);
    expect(find.textContaining('운동 이행률'), findsWidgets);
  });

  testWidgets('요약 카드가 다음 주 할 일까지 적어 아래를 채운다 (#1177)', (tester) async {
    await openReports(tester);

    // PT 세션 수는 옆 카드 제목 줄이 이미 말한다 — 요약에서 되풀이하지 않는다.
    expect(find.textContaining('PT 세션 1/1회 완료'), findsNothing);
    // 그 자리를 수치에서 곧바로 나오는 다음 주 할 일이 가져간다. 어떤 제안이
    // 뜨는지는 그 주 수치에 달렸으므로 줄이 있다는 것만 본다 — 문구는
    // `summaryCoachingActions` 테스트가 규칙으로 확인한다.
    expect(find.text('다음 주 코칭 제안'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reports-summary-action-0')),
      findsOneWidget,
    );
  });

  testWidgets('요약을 피드백 초안으로 가져온다 (#755)', (tester) async {
    await openReports(tester);

    // 헤더의 통합 검색창도 TextField 다 — 피드백 입력창만 집는다.
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.minLines == 4,
    );
    final before = tester.widget<TextField>(field).controller!.text;

    await tester.ensureVisible(find.text('피드백으로 가져오기'));
    await tester.pump();
    await tester.tap(find.text('피드백으로 가져오기'));
    await settle(tester);

    final after = tester.widget<TextField>(field).controller!.text;
    expect(after, isNot(before), reason: '입력창이 요약으로 바뀌지 않았다');
    // 제목 줄과 근거가 함께 들어가야 트레이너가 손볼 재료가 된다.
    expect(after, contains('회원은'));
    expect(after, contains('· '));
  });

  testWidgets('초안이 자동으로 채워졌다고 입력창이 말해 준다 (#755)', (tester) async {
    await openReports(tester);

    // 회원에게 그대로 나가는 글이라, 확인하고 보내라는 신호가 그 자리에
    // 있어야 한다. 'AI' 라고 하지 않는다 — 이 초안은 수치에서 조립한
    // 템플릿이지 생성된 문장이 아니다.
    expect(
      find.text('수치에서 자동으로 채운 초안이에요. 보내기 전에 확인하고 고쳐 주세요.'),
      findsOneWidget,
    );
  });

  testWidgets('가져온 요약을 초안으로 되돌린다 (#755)', (tester) async {
    await openReports(tester);

    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.minLines == 4,
    );
    final draft = tester.widget<TextField>(field).controller!.text;

    // 되돌릴 것이 없으면 버튼은 꺼져 있다.
    ActionButton restore() => tester.widget<ActionButton>(
      find.widgetWithText(ActionButton, '초안으로 되돌리기'),
    );
    expect(restore().onPressed, isNull);

    await tester.ensureVisible(find.text('피드백으로 가져오기'));
    await tester.pump();
    await tester.tap(find.text('피드백으로 가져오기'));
    await settle(tester);
    expect(tester.widget<TextField>(field).controller!.text, isNot(draft));

    await tester.ensureVisible(find.text('초안으로 되돌리기'));
    await tester.pump();
    await tester.tap(find.text('초안으로 되돌리기'));
    await settle(tester);

    expect(tester.widget<TextField>(field).controller!.text, draft);
  });

  testWidgets('요약 생성이 실패해도 카드가 안내문으로 돌아간다 (#755)', (tester) async {
    await openReports(
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(_SummaryFailsRepository()),
      ],
    );

    expect(
      find.text('실제 리포트 요약 API 연결 후 사용할 수 있어요. 현재 문구는 자동 생성하지 않습니다.'),
      findsOneWidget,
    );
  });

  // ---- 피드백 초안 저장 (#821) ----

  final Finder saveFeedback = find.byKey(
    const ValueKey<String>('report-feedback-save'),
  );

  testWidgets('피드백 저장 버튼이 켜져 있고 입력창의 현재 문구를 저장한다 (#821)', (tester) async {
    final drafts = _DraftStore();
    await openReports(
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(drafts),
      ],
    );

    expect(tester.widget<ActionButton>(saveFeedback).onPressed, isNotNull);

    await tester.enterText(feedbackField, '어깨 안정화 위주로 한 주 더 갑니다.');
    await settle(tester);
    await tester.tap(saveFeedback);
    await settle(tester);

    expect(drafts.saved, <String>['어깨 안정화 위주로 한 주 더 갑니다.']);
    expect(find.text('피드백 초안을 저장했어요.'), findsOneWidget);
  });

  testWidgets('지난 주 리포트에는 저장·되돌리기가 없다 (#1177)', (tester) async {
    await openReports(tester);

    expect(saveFeedback, findsOneWidget);
    expect(find.text('초안으로 되돌리기'), findsOneWidget);

    await tester.tap(prevWeek);
    await settle(tester);

    // 트레이너가 손볼 것은 이번 주에 보낼 글이다. 이미 지나간 주의 초안을
    // 저장해 둘 자리는 없다.
    expect(saveFeedback, findsNothing);
    expect(find.text('초안으로 되돌리기'), findsNothing);
    // 글은 그대로 읽을 수 있다 — 숨긴 것은 버튼뿐이다.
    expect(feedbackField, findsOneWidget);
  });

  testWidgets('부제는 리포트를 쓰라고 하지 않고 확인해 전달하라고 말한다 (#1177)', (tester) async {
    await openReports(tester);

    expect(find.text('주간 변화를 확인하고 회원에게 전달하세요'), findsOneWidget);
  });

  testWidgets('식단 추이 막대는 목표를 넘긴 주만 빨강이고 목표 표기는 없다 (#1177)', (tester) async {
    await openReports(
      tester,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
            makeClient(
              id: 'salty-client',
              name: '나트륨회원',
              sodiumWeek: List<int>.filled(7, 2500),
            ),
          ]),
        ),
      ],
    );

    // 식단 카드는 리포트 열 아래쪽이라 먼저 보이는 곳까지 굴린다.
    final Finder sodiumPill = find.byKey(
      const ValueKey<String>('trend-metric-sodium'),
    );
    await tester.ensureVisible(sodiumPill);
    await settle(tester);
    await tester.tap(sodiumPill);
    await settle(tester);

    final bars = tester
        .widgetList<WeekTrendBar>(find.byType(WeekTrendBar))
        .toList();
    expect(bars.where((b) => b.warn), isNotEmpty, reason: '목표를 넘긴 주가 있어야 한다');
    // 세로선이 무엇인지 적어 주던 `│ 목표 …` 는 사라졌다 — 초과 여부는 색이
    // 말한다.
    expect(find.textContaining('│'), findsNothing);
  });

  testWidgets('저장에 실패해도 쓰던 문구는 입력창에 남는다 (#821)', (tester) async {
    await openReports(
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(_DraftStore(failSave: true)),
      ],
    );

    await tester.enterText(feedbackField, '저장은 실패해도 이 문구는 남아야 한다');
    await settle(tester);
    await tester.tap(saveFeedback);
    await settle(tester);

    expect(find.text('초안을 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    // 저장하려다 잃는 것이 이 기능이 없애려던 문제다.
    expect(
      tester.widget<TextField>(feedbackField).controller!.text,
      '저장은 실패해도 이 문구는 남아야 한다',
    );
  });

  testWidgets('저장해 둔 초안이 있으면 입력창이 그 문구로 열린다 (#821)', (tester) async {
    await openReports(
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(
          _DraftStore(stored: '지난번에 쓰다 만 문구'),
        ),
      ],
    );

    expect(
      tester.widget<TextField>(feedbackField).controller!.text,
      '지난번에 쓰다 만 문구',
    );
  });

  testWidgets('되돌리기는 자동 생성본이 아니라 저장된 초안으로 돌아간다 (#821)', (tester) async {
    await openReports(
      tester,
      extraOverrides: <Override>[
        reportRepositoryProvider.overrideWithValue(
          _DraftStore(stored: '저장해 둔 초안'),
        ),
      ],
    );

    await tester.enterText(feedbackField, '고치는 중인 문구');
    await settle(tester);

    await tester.ensureVisible(find.text('초안으로 되돌리기'));
    await tester.pump();
    await tester.tap(find.text('초안으로 되돌리기'));
    await settle(tester);

    expect(
      tester.widget<TextField>(feedbackField).controller!.text,
      '저장해 둔 초안',
    );
  });
}

/// 저장한 초안을 기억하는 리포트 저장소. 리포트 본문·요약은 데모 계산을 그대로
/// 쓰고, 초안만 이 double 이 들고 있다.
class _DraftStore implements ReportRepository {
  _DraftStore({this.stored, this.failSave = false});

  /// 화면을 열 때 이미 저장돼 있는 초안. null 이면 저장한 적 없는 주다.
  final String? stored;
  final bool failSave;
  final List<String> saved = <String>[];

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
  }) async => ruleReportSummary(
    buildWeeklyReport(client: client, sessions: const [], weekStart: weekStart),
    client,
  );

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
  Future<ReportFeedbackDraft> feedbackDraft({
    required TrainerClient client,
    required DateTime weekStart,
  }) async {
    final String? body = saved.isNotEmpty ? saved.last : stored;
    if (body == null) return const ReportFeedbackDraft.none();
    return ReportFeedbackDraft(body: body, saved: true);
  }

  @override
  Future<ReportFeedbackDraft> saveFeedbackDraft({
    required String clientId,
    required DateTime weekStart,
    required String body,
  }) async {
    if (failSave) throw StateError('draft save failed');
    saved.add(body);
    return ReportFeedbackDraft(body: body, saved: true);
  }
}

class _RecordingPdfActions implements ReportPdfActions {
  Uint8List? savedBytes;
  Uint8List? printedBytes;
  String? savedName;
  String? printedName;

  @override
  Future<void> save(Uint8List bytes, String fileName) async {
    savedBytes = bytes;
    savedName = fileName;
  }

  @override
  Future<void> print(Uint8List bytes, String fileName) async {
    printedBytes = bytes;
    printedName = fileName;
  }
}

class _QueuedPdfGenerator extends ReportPdfGenerator {
  _QueuedPdfGenerator(this._results);

  final List<Future<Uint8List>> _results;
  int calls = 0;

  @override
  Future<Uint8List> generate({
    required AppLocalizations l,
    required WeeklyReport report,
    required String feedback,
    WeeklyReport? previousReport,
  }) {
    final result = _results[calls];
    calls++;
    return result;
  }
}

/// Chat repository whose sends always fail.
class _FailingChatRepository extends DriftChatRepository {
  const _FailingChatRepository(super.db);

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
  }) async {
    throw StateError('send failed');
  }
}
