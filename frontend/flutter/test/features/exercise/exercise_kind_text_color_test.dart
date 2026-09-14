/// 운동 현황이 유형과 `기타` 를 색으로 가르는 규칙 (#1352 → #1364).
///
///  * `전체` 에서 고른 주의 유형별 내역은 **이름만** 유형 색이고, 그 색은 옆
///    막대·링과 같은 [kindColor] 다. 값(`195분`·`12세트`)은 검정이다.
///  * `기타` 는 유형이 아니라 회색이고, 기록이 있는 날에만 맨 아래 붙는다.
///  * 세 유형은 값이 0 이어도 줄로 남는다 — 무엇을 안 했는지도 답해야 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' show OnCareColors;

const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

/// 오늘 자리에만 값을 넣은 한 주. [other] 를 주면 기타도 오늘에 붙는다.
ExerciseWeek _week({double other = 0}) {
  final int today = nowKst().weekday - 1;
  List<double> only(double v) => <double>[
    for (int i = 0; i < 7; i++) i == today ? v : 0,
  ];
  return ExerciseWeek(
    sessions: const <ExerciseSession>[],
    dailyMinutes: only(40 + other),
    dailyCalories: only(240),
    cardioMinutes: only(0),
    strengthMinutes: only(40),
    stretchingMinutes: only(0),
    otherMinutes: only(other),
    strengthSets: only(15),
    dayLabels: _dayLabels,
    totalMinutes: (40 + other).round(),
    totalCalories: 240,
    streakDays: 1,
    aiCoachMessage: '',
  );
}

/// 8월 한 주에 몰아 넣은 `전체` 그래프 재료. 기타는 하루치만 둔다.
List<ExerciseDayBar> _bars() {
  final DateTime now = nowKst();
  final DateTime today = DateTime(now.year, now.month, now.day);
  return <ExerciseDayBar>[
    for (int back = 13; back >= 0; back--)
      () {
        final DateTime d = today.subtract(Duration(days: back));
        return ExerciseDayBar(
          date: d,
          cardio: 30,
          strength: 15,
          stretching: 10,
          other: back == 0 ? 20 : 0,
          strengthSets: 5,
          minutes: 55,
          calories: 300,
        );
      }(),
  ];
}

Widget _app(int period, ExerciseWeek week) => ProviderScope(
  overrides: <Override>[
    exerciseActivityPeriodProvider.overrideWith((ref) => period),
    exerciseWeekProvider.overrideWith((ref) async => week),
    exerciseAllPeriodProvider.overrideWith((ref) async => _bars()),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ExerciseActivityStatus(week: week),
      ),
    ),
  ),
);

/// 글자 하나의 색. `Text.rich` 는 바깥 style 이 색을 갖는다.
Color? _colorOf(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).style?.color;

/// [text] 로 시작하는 `전체` 내역 한 줄. 이름과 값이 한 `Text.rich` 의 두
/// 조각이라, 색은 조각마다 따로 본다 (#1364).
Finder _startsWith(String text) => find.byWidgetPredicate(
  (Widget w) => w is Text && (w.textSpan?.toPlainText() ?? '').startsWith(text),
);

/// 그 줄의 (이름 색, 값 색).
(Color?, Color?) _lineColors(WidgetTester tester, String label) {
  final Text line = tester.widget<Text>(_startsWith(label));
  final List<InlineSpan> spans = (line.textSpan! as TextSpan).children!;
  return (spans.first.style?.color, spans.last.style?.color);
}

void main() {
  testWidgets('전체: 유형 이름은 그래프 색이고 값은 검정이다 (#1364)', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(2, _week()));
    await tester.pumpAndSettle();

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExerciseActivityStatus)),
    );
    // 마지막(이번 주) 막대를 고른다. 막대는 그린 자리가 값에 따라 달라져
    // 좌표가 빗나가므로, `all_period_chart_size_test` 와 같이 눌러 준다.
    final Finder bars = find.byWidgetPredicate(
      (Widget w) => w.runtimeType.toString() == '_BurnBar',
    );
    expect(bars, findsWidgets);
    await tester.tap(bars.last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // 이름은 옆 막대·링과 **같은 색**이다. 값은 색이 가리키는 것이 아니므로
    // 검정으로 적는다.
    for (final (String label, ExerciseLoadKind kind)
        in <(String, ExerciseLoadKind)>[
          (l.exTypeCardio, ExerciseLoadKind.cardio),
          (l.exTypeStrength, ExerciseLoadKind.strength),
          (l.exTypeFlexibility, ExerciseLoadKind.flexibility),
        ]) {
      final (Color? name, Color? value) = _lineColors(tester, label);
      expect(name, kindColor(kind), reason: label);
      expect(value, OnCareColors.textPrimary, reason: label);
    }
    // 기타는 유형이 아니라 회색 이름이다. 값은 다른 줄과 같이 검정이다.
    final (Color? otherName, Color? otherValue) = _lineColors(
      tester,
      l.exTypeOtherChip,
    );
    expect(otherName, OnCareColors.textSecondary);
    expect(otherValue, OnCareColors.textPrimary);
  });

  testWidgets('오늘: 세 유형은 0 이어도 남고, 기타는 없으면 뜨지 않는다', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(0, _week()));
    await tester.pumpAndSettle();

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExerciseActivityStatus)),
    );
    expect(find.text(l.exTypeCardio), findsOneWidget);
    expect(find.text(l.exTypeStrength), findsOneWidget);
    expect(find.text(l.exTypeFlexibility), findsOneWidget);
    expect(find.text(l.unitMinutesValue(0)), findsNWidgets(2));
    expect(find.text(l.exTypeOtherChip), findsNothing);
  });

  testWidgets('오늘·이번 주: 기타는 회색 한 줄로 맨 아래 붙는다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final int period in <int>[0, 1]) {
      await tester.pumpWidget(_app(period, _week(other: 20)));
      await tester.pumpAndSettle();

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(ExerciseActivityStatus)),
      );
      expect(find.text(l.exTypeOtherChip), findsOneWidget);
      expect(
        _colorOf(tester, find.text(l.exTypeOtherChip)),
        OnCareColors.textTertiary,
        reason: '기타가 유형 셋과 같은 진하기로 적혀 있다 (period=$period)',
      );
      // 유형 셋보다 아래다.
      expect(
        tester.getRect(find.text(l.exTypeOtherChip)).top,
        greaterThan(tester.getRect(find.text(l.exTypeFlexibility)).top),
      );
    }
  });
}
