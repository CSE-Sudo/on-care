/// 포인트 화면의 기록 그래프 — 깃허브식 격자, 방패, 고정 한 줄, 색 고르기.
/// (#2075, #2076)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/presentation/widgets/graph_color_sheet.dart';
import 'package:oncare/features/benefits/presentation/widgets/record_graph_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 2026년 8월 20일(목)로 끝나는 371일 — 화면이 받는 모양 그대로다.
final DateTime _today = DateTime(2026, 8, 20);
final DateTime _yesterday = DateTime(2026, 8, 19);

ActivityCalendar _graph({
  Set<DateTime> diet = const <DateTime>{},
  Set<DateTime> exercise = const <DateTime>{},
  Set<DateTime> protectedDays = const <DateTime>{},
  int streak = 0,
  int shieldsHeld = 0,
  DateTime? protectableFrom,
  DateTime? protectableTo,
  GraphColorState color = GraphColorState.base,
  int days = 371,
}) {
  bool has(Set<DateTime> set, DateTime d) => set.any(
    (DateTime x) => x.year == d.year && x.month == d.month && x.day == d.day,
  );
  return ActivityCalendar(
    days: <ActivityDay>[
      for (int i = days - 1; i >= 0; i--)
        () {
          final DateTime date = DateTime(
            _today.year,
            _today.month,
            _today.day - i,
          );
          return ActivityDay(
            date: date,
            hasDiet: has(diet, date),
            hasExercise: has(exercise, date),
            protected: has(protectedDays, date),
          );
        }(),
    ],
    recordStreakDays: streak,
    shieldsHeld: shieldsHeld,
    protectableFrom: protectableFrom,
    protectableTo: protectableTo,
    color: color,
  );
}

Key _cellKey(DateTime day) => ValueKey<String>(
  'record-cell-${day.year.toString().padLeft(4, '0')}-'
  '${day.month.toString().padLeft(2, '0')}-'
  '${day.day.toString().padLeft(2, '0')}',
);

BoxDecoration _cellBox(WidgetTester tester, DateTime day) =>
    tester.widget<Container>(find.byKey(_cellKey(day))).decoration!
        as BoxDecoration;

Color _cellColor(WidgetTester tester, DateTime day) => _cellBox(tester, day).color!;

AppTag _streakTag(WidgetTester tester) =>
    tester.widget<AppTag>(find.byKey(const Key('recordGraphStreak')));

String _dayLine(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('recordGraphDayLine'))).data!;

/// 격자는 오늘(오른쪽 끝)에서 열리므로, 지난 칸은 먼저 그 자리로 민 뒤 누른다.
Future<void> _tapCell(WidgetTester tester, DateTime day) async {
  final Finder cell = find.byKey(_cellKey(day));
  await tester.ensureVisible(cell);
  await tester.pumpAndSettle();
  await tester.tap(cell);
  await tester.pump();
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    ActivityCalendar graph, {
    ValueChanged<DateTime>? onProtect,
    VoidCallback? onChangeColor,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecordGraphCard(
              calendar: graph,
              onProtect: onProtect,
              onChangeColor: onChangeColor,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('한 해치 칸이 요일 7줄로 서고 가로로 스크롤한다', (tester) async {
    await pump(tester, _graph());

    // 53주 × 7줄. 격자가 화면보다 넓어 가로 스크롤이 생긴다.
    expect(find.byKey(_cellKey(_today)), findsOneWidget);
    final Scrollable grid = tester.widget<Scrollable>(
      find.descendant(
        of: find.byKey(const Key('recordGraphCard')),
        matching: find.byWidgetPredicate(
          (Widget w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      ),
    );
    expect(grid.axisDirection, AxisDirection.right);
    // 요일 라벨은 두지 않는다 — 세 글자가 무엇인지 되묻게 되는 자리였다.
    for (final String label in <String>['일', '월', '화', '수', '목', '금', '토']) {
      expect(find.text(label), findsNothing, reason: label);
    }
  });

  testWidgets('칸 색은 기록에 따라 3단계로 갈린다', (tester) async {
    final DateTime dietOnly = DateTime(2026, 8, 17);
    final DateTime both = DateTime(2026, 8, 18);
    await pump(
      tester,
      _graph(diet: <DateTime>{dietOnly, both}, exercise: <DateTime>{both}),
    );

    expect(_cellColor(tester, _yesterday), OnCareRecordColors.base.none);
    expect(_cellColor(tester, dietOnly), OnCareRecordColors.base.partial);
    expect(_cellColor(tester, both), OnCareRecordColors.base.full);
  });

  testWidgets('기록이 없는 날은 계열에서 빠진 회색이다', (tester) async {
    await pump(
      tester,
      _graph(
        diet: <DateTime>{_yesterday},
        color: const GraphColorState(
          current: 'green',
          unlocked: <String>['blue', 'green'],
          palette: <String>['blue', 'green'],
          cost: 150,
        ),
      ),
    );

    // 계열의 가장 연한 색으로 두면 "조금 한 날" 처럼 보인다 — 어느 색을 골라도
    // 빈 칸은 같은 회색이다.
    expect(_cellColor(tester, DateTime(2026, 8, 18)), OnCareRecordColors.empty);
    expect(OnCareRecordColors.green.none, OnCareRecordColors.empty);
    expect(OnCareRecordColors.pink.none, OnCareRecordColors.empty);
    // 기록한 날은 고른 계열 그대로다.
    expect(_cellColor(tester, _yesterday), OnCareRecordColors.green.partial);
  });

  testWidgets('기록 연속 N일이 보이고 범례는 없다', (tester) async {
    await pump(tester, _graph(streak: 12));

    expect(find.text('기록 연속 12일'), findsOneWidget);
    expect(find.text('없음'), findsNothing);
    expect(find.text('둘 다'), findsNothing);
  });

  testWidgets('기록 연속 태그도 고른 색을 따른다', (tester) async {
    await pump(
      tester,
      _graph(
        streak: 12,
        color: const GraphColorState(
          current: 'pink',
          unlocked: <String>['blue', 'pink'],
          palette: <String>['blue', 'green', 'purple', 'orange', 'pink'],
          cost: 150,
        ),
      ),
    );

    expect(_streakTag(tester).accent, OnCareRecordColors.pink.full);
  });

  testWidgets('연속이 끊긴 0일 태그는 색을 따르지 않는다', (tester) async {
    await pump(
      tester,
      _graph(
        color: const GraphColorState(
          current: 'pink',
          unlocked: <String>['blue', 'pink'],
          palette: <String>['blue', 'green', 'purple', 'orange', 'pink'],
          cost: 150,
        ),
      ),
    );

    final AppTag tag = _streakTag(tester);
    expect(tag.accent, isNull);
    expect(tag.tone, AppTagTone.neutral);
  });

  testWidgets('보호한 날 칸에는 방패와 테두리가 함께 선다', (tester) async {
    await pump(
      tester,
      _graph(protectedDays: <DateTime>{_yesterday}, streak: 1),
    );

    // 칸 색은 빈 칸 그대로다 — 실제 기록이 아니라서다.
    expect(_cellColor(tester, _yesterday), OnCareRecordColors.base.none);
    expect(
      find.descendant(
        of: find.byKey(_cellKey(_yesterday)),
        matching: find.byType(AppIcon),
      ),
      findsOneWidget,
    );
    // 방패만으로는 한 해치를 훑을 때 눈에 걸리지 않는다 — 테두리를 함께 두른다.
    final BorderSide side = (_cellBox(tester, _yesterday).border! as Border).top;
    expect(side.color, OnCareRecordColors.base.full);
    expect(side.width, 2);

    // 방패는 테두리 안쪽에 들어가야 한다 — 남는 자리보다 크면 한쪽으로 밀려
    // 테두리를 타고 넘는다.
    final double cell = tester.getSize(find.byKey(_cellKey(_yesterday))).width;
    final AppIcon shield = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(_cellKey(_yesterday)),
        matching: find.byType(AppIcon),
      ),
    );
    expect(shield.size, lessThanOrEqualTo(cell - side.width * 2));

    // 기록한 날에는 테두리가 없다.
    expect(_cellBox(tester, DateTime(2026, 8, 18)).border, isNull);
  });

  testWidgets('누를 수 있는 빈 칸은 보호한 날보다 연한 테두리다', (tester) async {
    final DateTime empty = DateTime(2026, 8, 5);
    await pump(
      tester,
      _graph(
        protectedDays: <DateTime>{_yesterday},
        shieldsHeld: 1,
        protectableFrom: DateTime(2026, 7, 21),
        protectableTo: _yesterday,
      ),
      onProtect: (_) {},
    );

    final BorderSide open = (_cellBox(tester, empty).border! as Border).top;
    final BorderSide done = (_cellBox(tester, _yesterday).border! as Border).top;
    expect(open.color, OnCareRecordColors.base.partial);
    expect(done.color, OnCareRecordColors.base.full);
    expect(open.width, lessThan(done.width));
  });

  testWidgets('칸을 누르면 아래 한 줄이 그날 기록으로 바뀐다', (tester) async {
    final DateTime dietOnly = DateTime(2026, 8, 17);
    await pump(tester, _graph(diet: <DateTime>{dietOnly}));

    await _tapCell(tester, dietOnly);
    expect(_dayLine(tester), '8월 17일 · 식단만 기록');

    // 다른 칸을 누르면 그 줄이 다시 바뀐다 — 토스트처럼 사라지지 않는다.
    await _tapCell(tester, _yesterday);
    expect(_dayLine(tester), '8월 19일 · 기록 없음');
  });

  testWidgets('창 안의 빈 칸을 누르면 그 줄에 보호권 쓰기가 붙는다', (tester) async {
    DateTime? asked;
    final DateTime empty = DateTime(2026, 8, 5);
    await pump(
      tester,
      _graph(
        diet: <DateTime>{_today},
        shieldsHeld: 2,
        protectableFrom: DateTime(2026, 7, 21),
        protectableTo: _yesterday,
      ),
      onProtect: (DateTime d) => asked = d,
    );

    // 누르기 전에는 버튼이 없다 — 어느 날을 이어 붙일지가 정해지지 않았다.
    expect(find.byKey(const Key('recordGraphProtect')), findsNothing);

    await _tapCell(tester, empty);
    await tester.tap(find.byKey(const Key('recordGraphProtect')));
    await tester.pump();

    expect(asked, empty);
  });

  testWidgets('기록이 있는 날과 창 밖의 날에는 보호권 쓰기가 없다', (tester) async {
    await pump(
      tester,
      _graph(
        diet: <DateTime>{_yesterday},
        shieldsHeld: 2,
        protectableFrom: DateTime(2026, 8, 10),
        protectableTo: _yesterday,
      ),
      onProtect: (_) {},
    );

    // 기록이 있는 날.
    await _tapCell(tester, _yesterday);
    expect(find.byKey(const Key('recordGraphProtect')), findsNothing);

    // 창보다 오래된 빈 날.
    await _tapCell(tester, DateTime(2026, 8, 3));
    expect(find.byKey(const Key('recordGraphProtect')), findsNothing);
  });

  testWidgets('보호권이 없으면 어느 칸도 보호권 쓰기가 없다', (tester) async {
    await pump(tester, _graph(), onProtect: (_) {});

    await _tapCell(tester, _yesterday);

    expect(find.byKey(const Key('recordGraphProtect')), findsNothing);
  });

  testWidgets('연 색으로 그리고, 팔레트 버튼이 색 고르기를 연다', (tester) async {
    bool opened = false;
    await pump(
      tester,
      _graph(
        diet: <DateTime>{_yesterday},
        color: const GraphColorState(
          current: 'green',
          unlocked: <String>['blue', 'green'],
          palette: <String>['blue', 'green', 'purple', 'orange', 'pink'],
          cost: 150,
        ),
      ),
      onChangeColor: () => opened = true,
    );

    expect(_cellColor(tester, _yesterday), OnCareRecordColors.green.partial);
    await tester.tap(find.byKey(const Key('recordGraphColorButton')));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('색 고르기 시트는 연 색과 값이 붙은 색을 나눠 보여 준다', (tester) async {
    const GraphColorState state = GraphColorState(
      current: 'blue',
      unlocked: <String>['blue', 'green'],
      palette: <String>['blue', 'green', 'purple', 'orange', 'pink'],
      cost: 150,
    );
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext c) {
            ctx = c;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    final Future<GraphColorChoice?> picked = showAppSheet<GraphColorChoice>(
      context: ctx,
      builder: (BuildContext _) => const GraphColorSheet(state: state),
    );
    await tester.pumpAndSettle();

    expect(find.text('초록'), findsOneWidget);
    // 열지 않은 색에만 값이 붙는다. 이미 연 색은 포인트 없이 바꾼다.
    expect(find.text('150P로 열기'), findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey<String>('graph-color-purple')));
    await tester.pumpAndSettle();

    final GraphColorChoice? choice = await picked;
    expect(choice?.color, 'purple');
    expect(choice?.unlock, isTrue);
  });
}
