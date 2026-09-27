/// 회원별 지난 리포트 — 화면 위젯. (#2394)
///
/// 이 파일이 지키는 것:
///  * 제목은 `OOO님의 지난 리포트`, 왼쪽 위 `< 회원 목록` 이 돌아가기다.
///  * 한 줄에 주 범위·전송일·열람 여부·피드백 첫 줄·`보기` 가 선다.
///  * 이번 주를 아직 안 보냈으면 맨 위에 `미전송 · 열기` 줄이 서고, 보냈으면
///    서지 않는다.
///  * 불러오는 중·빈 이력·실패(다시 시도)를 따로 보인다.
///  * `더 보기` 로 다음 쪽을 붙이고, 실패하면 읽은 줄은 남긴 채 알린다.
///  * 영어로 바꾸면 한국어가 남지 않는다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/reports/data/member_report_history_provider.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/member_report_history_view.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/fixed_clock.dart';

/// [kMidWeekKst](2026-08-20 목)의 이번 주·지난 주·지지난 주 월요일.
final DateTime _thisWeek = DateTime(2026, 8, 17);
final DateTime _lastWeek = DateTime(2026, 8, 10);
final DateTime _twoAgo = DateTime(2026, 8, 3);

MemberReportHistoryItem _item(
  DateTime week, {
  String preview = '이번 주도 수고 많으셨어요.',
  bool read = true,
  int sendCount = 1,
  bool hasPdf = false,
}) => MemberReportHistoryItem(
  weekStart: week,
  sentAt: DateTime(week.year, week.month, week.day + 6, 20),
  read: read,
  sendCount: sendCount,
  feedbackPreview: preview,
  hasPdf: hasPdf,
);

/// 쪽을 정해 둔 저장소.
class _FakeRepository implements ReportRepository {
  _FakeRepository(this.pages);

  final Map<DateTime?, MemberReportHistoryPage> pages;
  final Set<DateTime?> failOn = <DateTime?>{};
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<MemberReportHistoryPage> memberReportHistory({
    required String clientId,
    DateTime? before,
    int limit = memberReportHistoryPageSize,
  }) async {
    calls++;
    if (gate case final Completer<void> g) await g.future;
    if (failOn.contains(before)) throw StateError('history failed');
    return pages[before] ?? const MemberReportHistoryPage.empty();
  }

  // 본문이 빈 줄만 그 주 리포트를 읽는다 — 여기서는 수치가 오지 않는다.
  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) => const Stream<WeeklyReport>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final TrainerClient _client = makeClient(name: '김민수');

void main() {
  setUp(() => useFixedKstDate(kMidWeekKst));

  late int backs;
  late List<DateTime> viewed;
  late int opened;

  Future<void> pump(
    WidgetTester tester,
    _FakeRepository repo, {
    Locale locale = const Locale('ko'),
    bool settle = true,
  }) async {
    backs = 0;
    viewed = <DateTime>[];
    opened = 0;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reportRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MemberReportHistoryView(
              client: _client,
              onBack: () => backs++,
              onView: viewed.add,
              onOpenThisWeek: () => opened++,
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  _FakeRepository onePage(List<MemberReportHistoryItem> items) =>
      _FakeRepository({null: MemberReportHistoryPage(items: items)});

  testWidgets('제목은 회원 이름이 든 지난 리포트고, 회원 목록으로 돌아간다', (tester) async {
    await pump(tester, onePage(<MemberReportHistoryItem>[_item(_lastWeek)]));

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('reports-history-title')))
          .data,
      '김민수님의 지난 리포트',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reports-history-back')),
        matching: find.text('회원 목록'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('reports-history-back')));
    expect(backs, 1);
  });

  testWidgets('한 줄에 주 범위·전송일·열람·첫 줄·보기가 선다', (tester) async {
    await pump(
      tester,
      onePage(<MemberReportHistoryItem>[
        _item(_lastWeek, preview: '지난 주 첫 줄', read: false),
      ]),
    );

    final Finder row = find.byKey(
      const ValueKey('reports-history-week-2026-08-10'),
    );
    Finder inRow(String text) =>
        find.descendant(of: row, matching: find.text(text));
    expect(inRow('8월 10일 – 8월 16일'), findsOneWidget);
    expect(inRow('8월 16일 전송'), findsOneWidget);
    expect(inRow('안 읽음'), findsOneWidget);
    expect(inRow('지난 주 첫 줄'), findsOneWidget);
    expect(inRow('보기'), findsOneWidget);
  });

  testWidgets('읽은 줄은 읽음, 여러 번 보낸 줄은 횟수, PDF 는 PDF 표시가 선다', (tester) async {
    await pump(
      tester,
      onePage(<MemberReportHistoryItem>[
        _item(_lastWeek, sendCount: 3, hasPdf: true),
        _item(_twoAgo),
      ]),
    );

    final Finder last = find.byKey(
      const ValueKey('reports-history-week-2026-08-10'),
    );
    final Finder older = find.byKey(
      const ValueKey('reports-history-week-2026-08-03'),
    );
    expect(
      find.descendant(of: last, matching: find.text('읽음')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: last, matching: find.text('3번 보냄')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: last, matching: find.text('PDF')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: older, matching: find.text('PDF')),
      findsNothing,
    );
    expect(
      find.descendant(of: older, matching: find.textContaining('번 보냄')),
      findsNothing,
    );
  });

  testWidgets('줄은 최신 주부터 선다', (tester) async {
    await pump(
      tester,
      onePage(<MemberReportHistoryItem>[_item(_lastWeek), _item(_twoAgo)]),
    );

    final double lastY = tester
        .getTopLeft(
          find.byKey(const ValueKey('reports-history-week-2026-08-10')),
        )
        .dy;
    final double olderY = tester
        .getTopLeft(
          find.byKey(const ValueKey('reports-history-week-2026-08-03')),
        )
        .dy;
    expect(lastY, lessThan(olderY));
  });

  testWidgets('보기를 누르면 그 주 월요일로 연다', (tester) async {
    await pump(
      tester,
      onePage(<MemberReportHistoryItem>[_item(_lastWeek), _item(_twoAgo)]),
    );

    await tester.tap(
      find.byKey(const ValueKey('reports-history-view-2026-08-03')),
    );
    expect(viewed, <DateTime>[_twoAgo]);
  });

  testWidgets('이번 주를 안 보냈으면 맨 위에 미전송·열기 줄이 선다', (tester) async {
    await pump(tester, onePage(<MemberReportHistoryItem>[_item(_lastWeek)]));

    final Finder unsent = find.byKey(const ValueKey('reports-history-unsent'));
    expect(unsent, findsOneWidget);
    expect(
      find.descendant(of: unsent, matching: find.text('미전송')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: unsent,
        matching: find.text('8월 17일 – 8월 23일 · 이번 주'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(unsent).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('reports-history-week-2026-08-10')),
            )
            .dy,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('reports-history-open')));
    expect(opened, 1);
  });

  testWidgets('이번 주를 보냈으면 미전송 줄 없이 이번 주 줄이 맨 위다', (tester) async {
    await pump(
      tester,
      onePage(<MemberReportHistoryItem>[_item(_thisWeek), _item(_lastWeek)]),
    );

    expect(find.byKey(const ValueKey('reports-history-unsent')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reports-history-week-2026-08-17')),
        matching: find.text('8월 17일 – 8월 23일 · 이번 주'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('보낸 적이 없으면 빈 안내와 이번 주 미전송 줄이 선다', (tester) async {
    await pump(tester, onePage(const <MemberReportHistoryItem>[]));

    expect(find.byKey(const ValueKey('reports-history-empty')), findsOneWidget);
    expect(find.text('아직 보낸 리포트가 없어요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reports-history-unsent')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('reports-history-more')), findsNothing);
  });

  testWidgets('불러오는 동안은 불러오는 중 표시가 선다', (tester) async {
    final _FakeRepository repo = onePage(<MemberReportHistoryItem>[
      _item(_lastWeek),
    ])..gate = Completer<void>();
    await pump(tester, repo, settle: false);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('reports-history-loading')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('reports-history-unsent')), findsNothing);

    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reports-history-loading')), findsNothing);
    expect(
      find.byKey(const ValueKey('reports-history-week-2026-08-10')),
      findsOneWidget,
    );
  });

  testWidgets('실패하면 안내와 다시 시도가 서고, 다시 시도하면 다시 묻는다', (tester) async {
    final _FakeRepository repo = onePage(<MemberReportHistoryItem>[
      _item(_lastWeek),
    ])..failOn.add(null);
    await pump(tester, repo);

    expect(find.byKey(const ValueKey('reports-history-retry')), findsOneWidget);
    expect(find.text('지난 리포트를 불러오지 못했어요'), findsOneWidget);
    // 실패를 빈 이력처럼 보이지 않는다.
    expect(find.byKey(const ValueKey('reports-history-empty')), findsNothing);
    expect(find.byKey(const ValueKey('reports-history-unsent')), findsNothing);

    repo.failOn.clear();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('reports-history-retry')),
        matching: find.text('다시 시도'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.calls, 2);
    expect(
      find.byKey(const ValueKey('reports-history-week-2026-08-10')),
      findsOneWidget,
    );
  });

  testWidgets('더 보기는 다음 쪽을 아래에 붙이고, 다 읽으면 사라진다', (tester) async {
    final _FakeRepository repo = _FakeRepository({
      null: MemberReportHistoryPage(
        items: <MemberReportHistoryItem>[_item(_lastWeek)],
        nextBefore: _lastWeek,
      ),
      _lastWeek: MemberReportHistoryPage(
        items: <MemberReportHistoryItem>[_item(_twoAgo)],
      ),
    });
    await pump(tester, repo);

    expect(
      find.byKey(const ValueKey('reports-history-week-2026-08-03')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('reports-history-more')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('reports-history-week-2026-08-03')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('reports-history-more')), findsNothing);
  });

  testWidgets('더 보기가 실패하면 읽은 줄은 남고 안내가 선다', (tester) async {
    final _FakeRepository repo = _FakeRepository({
      null: MemberReportHistoryPage(
        items: <MemberReportHistoryItem>[_item(_lastWeek)],
        nextBefore: _lastWeek,
      ),
    })..failOn.add(_lastWeek);
    await pump(tester, repo);

    await tester.tap(find.byKey(const ValueKey('reports-history-more')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('reports-history-week-2026-08-10')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('reports-history-more-failed')),
      findsOneWidget,
    );
    // 다시 누를 수 있게 버튼은 남는다.
    expect(find.byKey(const ValueKey('reports-history-more')), findsOneWidget);
  });

  testWidgets('영어로 바꾸면 한국어가 남지 않는다', (tester) async {
    final TrainerClient english = makeClient(name: 'Minsu');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportRepositoryProvider.overrideWithValue(
            _FakeRepository({
              null: MemberReportHistoryPage(
                items: <MemberReportHistoryItem>[
                  _item(
                    _lastWeek,
                    preview: 'Great week.',
                    sendCount: 2,
                    hasPdf: true,
                    read: false,
                  ),
                ],
                nextBefore: _lastWeek,
              ),
            }),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MemberReportHistoryView(
              client: english,
              onBack: () {},
              onView: (_) {},
              onOpenThisWeek: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Minsu's past reports"), findsOneWidget);
    final RegExp hangul = RegExp('[가-힣]');
    for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
      expect(hangul.hasMatch(text.data ?? ''), isFalse, reason: text.data);
    }
    for (final RichText text in tester.widgetList<RichText>(
      find.byType(RichText),
    )) {
      final String plain = text.text.toPlainText();
      expect(hangul.hasMatch(plain), isFalse, reason: plain);
    }
  });
}
