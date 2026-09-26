/// ① 이번 주 격자 — 네 줄을 한 요일 축에 겹쳐 놓는다. (#2232)
///
/// 이 격자가 답하는 질문은 "무엇이 나빴나" 가 아니라 **"어느 날이 무너졌나"**
/// 다. 그래서 여기서 보는 것은 칸마다의 숫자가 아니라 규칙이다 — 무엇을
/// 붉게 짚는가, 모르는 것을 어떻게 적는가, 없는 날을 어떻게 다루는가.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_grid.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';

final DateTime _week = DateTime(2026, 9, 14);

/// 월~일 전부 배정 2개 중 2개를 한, 아무 데도 붉지 않은 주.
List<ReportDay> _fullWeek() => <ReportDay>[
  for (int i = 0; i < 7; i++)
    const ReportDay(
      completion: 100,
      exercises: <String>['스쿼트', '런지'],
      assigned: 2,
    ),
];

WeeklyReport _report({
  int sessionsBooked = 2,
  int sessionsDone = 2,
  List<ReportDay>? days,
  List<int> mealCounts = const <int>[3, 3, 3, 3, 3, 3, 3],
  List<int> caloriesWeek = const <int>[
    1800,
    1850,
    1900,
    1750,
    1820,
    1780,
    1860,
  ],
  int? calorieTarget = 2000,
}) => WeeklyReport(
  client: makeClient(name: '김민수'),
  weekStart: _week,
  sessionsBooked: sessionsBooked,
  sessionsDone: sessionsDone,
  completionAvg: 86,
  sodiumOverDays: 0,
  sodiumAvg: 1800,
  isCurrentWeek: false,
  days: days ?? _fullWeek(),
  mealCounts: mealCounts,
  caloriesWeek: caloriesWeek,
  calorieTarget: calorieTarget,
);

Future<void> _pump(
  WidgetTester tester, {
  WeeklyReport? report,
  double? baseline,
  String locale = 'ko',
  Size size = const Size(900, 600),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(OnCareSpacing.s16),
          child: ReportWeekGrid(
            report: report ?? _report(),
            calorieBaseline: baseline,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 그 글월을 그리는 [Text] 의 색.
Color? _colorOf(WidgetTester tester, String text, {int at = 0}) {
  final Iterable<Element> found = find.text(text).evaluate();
  return (found.elementAt(at).widget as Text).style?.color;
}

void main() {
  testWidgets('네 줄이 같은 요일 축 위에 선다', (tester) async {
    await _pump(tester);

    expect(find.text('PT 세션'), findsOneWidget);
    expect(find.text('개인 운동'), findsOneWidget);
    expect(find.text('식단 기록'), findsOneWidget);
    expect(find.text('섭취 칼로리'), findsOneWidget);
  });

  testWidgets('요일 머리글은 맨 아래에 있다 — 네 줄을 읽고 눈을 올리지 않게', (tester) async {
    await _pump(tester);

    final double monday = tester.getCenter(find.text('월')).dy;
    final double calories = tester.getCenter(find.text('섭취 칼로리')).dy;
    expect(monday, greaterThan(calories));
  });

  testWidgets('일곱 요일이 모두 선다', (tester) async {
    await _pump(tester);

    for (final String day in <String>['월', '화', '수', '목', '금', '토', '일']) {
      expect(find.text(day), findsOneWidget);
    }
  });

  testWidgets('PT 는 나온 횟수만큼 앞에서부터 채운다 — 요일을 지어내지 않는다', (tester) async {
    await _pump(tester, report: _report(sessionsBooked: 3));

    expect(find.text('주 3회'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
  });

  testWidgets('한 번도 안 나온 주에는 체크가 하나도 없다', (tester) async {
    await _pump(tester, report: _report(sessionsDone: 0));

    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('개인 운동은 수행과 배정을 함께 적는다', (tester) async {
    await _pump(tester);

    expect(find.text('2 / 2회'), findsNWidgets(7));
  });

  testWidgets('배정이 있는데 하나도 안 한 날만 붉다', (tester) async {
    final List<ReportDay> days = _fullWeek();
    days[1] = const ReportDay(completion: 0, assigned: 3);
    await _pump(tester, report: _report(days: days));

    expect(_colorOf(tester, '0 / 3회'), OnCareColors.danger);
    expect(_colorOf(tester, '2 / 2회'), isNot(OnCareColors.danger));
  });

  testWidgets('배정이 없는 쉬는 날은 붉지 않다 — 매주 절반이 빨간 격자를 만들지 않는다', (tester) async {
    final List<ReportDay> days = _fullWeek();
    days[6] = const ReportDay(completion: 0, assigned: 0);
    await _pump(tester, report: _report(days: days));

    expect(_colorOf(tester, '0 / 0회'), isNot(OnCareColors.danger));
  });

  testWidgets('절반만 한 날은 붉지 않다 — 빨강은 하나도 못 한 날의 것이다', (tester) async {
    final List<ReportDay> days = _fullWeek();
    days[2] = const ReportDay(
      completion: 50,
      exercises: <String>['스쿼트'],
      assigned: 2,
    );
    await _pump(tester, report: _report(days: days));

    expect(_colorOf(tester, '1 / 2회'), isNot(OnCareColors.danger));
  });

  testWidgets('건너뛴 운동은 수행에서 빠진다 — 저장 규칙의 ✗ 를 읽는다', (tester) async {
    final List<ReportDay> days = _fullWeek();
    days[0] = const ReportDay(
      completion: 50,
      exercises: <String>['스쿼트', '런지 ✗'],
      assigned: 2,
    );
    await _pump(tester, report: _report(days: days));

    expect(find.text('1 / 2회'), findsOneWidget);
  });

  testWidgets('끼니를 한 번도 안 적은 날은 붉다', (tester) async {
    await _pump(
      tester,
      report: _report(mealCounts: const <int>[3, 0, 3, 3, 3, 3, 3]),
    );

    expect(_colorOf(tester, '0회'), OnCareColors.danger);
  });

  testWidgets('한 번이라도 적은 날은 붉지 않다', (tester) async {
    await _pump(
      tester,
      report: _report(mealCounts: const <int>[1, 3, 3, 3, 3, 3, 3]),
    );

    expect(_colorOf(tester, '1회'), isNot(OnCareColors.danger));
  });

  testWidgets('0kcal 인 날은 0 이 아니라 줄표다 — 굶은 날이 아니라 안 적은 날이다', (tester) async {
    await _pump(
      tester,
      report: _report(
        caloriesWeek: const <int>[0, 1850, 1900, 1750, 1820, 1780, 1860],
      ),
    );

    // 칼로리 줄에서 안 적은 날은 수치 없이 바닥의 옅은 점으로만 남는다.
    expect(find.text('0'), findsNothing);
    expect(find.text('1,850'), findsOneWidget);
  });

  testWidgets('목표를 넘긴 날만 붉다', (tester) async {
    await _pump(
      tester,
      report: _report(
        // 목표는 2,000kcal 이다.
        caloriesWeek: const <int>[2400, 1850, 1900, 1750, 1820, 1780, 1860],
      ),
    );

    expect(_colorOf(tester, '2,400'), OnCareColors.danger);
    expect(_colorOf(tester, '1,850'), isNot(OnCareColors.danger));
  });

  testWidgets('목표와 같은 날은 넘긴 것이 아니다 — 경계값', (tester) async {
    await _pump(
      tester,
      report: _report(
        // 목표와 정확히 같은 날이 첫날이다.
        caloriesWeek: const <int>[2000, 1850, 1900, 1750, 1820, 1780, 1860],
      ),
    );

    expect(_colorOf(tester, '2,000'), isNot(OnCareColors.danger));
  });

  testWidgets('목표를 적어 두지 않은 회원은 기본 목표로 견준다 — 요약이 말하는 기준과 같다 (#2232)', (
    tester,
  ) async {
    await _pump(
      tester,
      report: _report(
        caloriesWeek: const <int>[2400, 2600, 2900, 1750, 1820, 1780, 1860],
        calorieTarget: null,
      ),
    );

    // 기준이 무엇인지 이름 아래에 밝힌다 — 회원이 정한 목표가 아니다.
    expect(find.text('기본 목표 2,000'), findsOneWidget);
    expect(_colorOf(tester, '2,400'), OnCareColors.danger);
    expect(_colorOf(tester, '1,750'), isNot(OnCareColors.danger));
  });

  testWidgets('목표가 있으면 이름 아래에 적어 준다 — 어느 기준의 빨강인지 말한다', (tester) async {
    await _pump(tester);

    expect(find.text('목표 2,000'), findsOneWidget);
  });

  testWidgets('네 자리 수는 천 단위로 끊어 적는다 — 그래프와 같은 서식이다', (tester) async {
    await _pump(tester);

    expect(find.text('1800'), findsNothing);
    expect(find.text('1,800'), findsOneWidget);
  });

  testWidgets('자료가 아예 없는 주에도 격자가 서고 칸은 줄표다', (tester) async {
    await _pump(
      tester,
      report: _report(
        days: const <ReportDay>[],
        mealCounts: const <int>[],
        caloriesWeek: const <int>[],
        calorieTarget: null,
      ),
    );

    expect(tester.takeException(), isNull);
    // 개인 운동·식단 두 줄 × 일곱 칸. 칼로리 줄은 점 위에 수를 적으니 빈
    // 날에는 적을 수가 없다.
    expect(find.text('–'), findsNWidgets(14));
  });

  testWidgets('요일이 모자란 주도 있는 만큼만 그리고 나머지는 줄표다', (tester) async {
    await _pump(
      tester,
      report: _report(
        days: _fullWeek().take(3).toList(),
        mealCounts: const <int>[3, 3, 3],
        caloriesWeek: const <int>[1800, 1850, 1900],
      ),
    );

    expect(find.text('2 / 2회'), findsNWidgets(3));
    expect(find.text('–'), findsNWidgets(8));
  });

  testWidgets('영어에서 모든 자리가 번역되어 있다', (tester) async {
    await _pump(tester, locale: 'en');

    expect(find.text('PT sessions'), findsOneWidget);
    expect(find.text('Personal workouts'), findsOneWidget);
    expect(find.text('Meal logs'), findsOneWidget);
    expect(find.text('Calories eaten'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
  });

  testWidgets('영어 격자에 한글이 남아 있지 않다', (tester) async {
    await _pump(tester, locale: 'en');

    final RegExp hangul = RegExp(r'[가-힣]');
    for (final Element e in find.byType(Text).evaluate()) {
      final String? data = (e.widget as Text).data;
      if (data == null) continue;
      expect(hangul.hasMatch(data), isFalse, reason: '번역되지 않은 글: $data');
    }
  });

  testWidgets('좁은 폭에서도 넘치지 않는다', (tester) async {
    await _pump(tester, size: const Size(420, 600));

    expect(tester.takeException(), isNull);
  });

  group('평소와 견주는 줄 (#2232)', () {
    // 회원은 자기 앱에서 이번 주 칼로리를 이미 본다. 트레이너에게 새로운
    // 것은 `이 수가 이 사람에게 많은가` 이고, 그 기준이 이 줄이다.
    testWidgets('이번 주 평균과 지난 4주 평균을 나란히 적는다', (tester) async {
      await _pump(
        tester,
        report: _report(
          caloriesWeek: const <int>[2000, 2200, 2400, 0, 0, 0, 0],
        ),
        baseline: 2000,
      );

      // 기록한 세 날의 평균 2,200.
      expect(find.textContaining('이번 주 평균 2,200kcal'), findsOneWidget);
      expect(find.textContaining('지난 4주 평균 2,000kcal'), findsOneWidget);
    });

    testWidgets('늘면 ▲, 줄면 ▼ 로 그 폭을 적는다', (tester) async {
      await _pump(
        tester,
        report: _report(
          caloriesWeek: const <int>[2200, 2200, 2200, 0, 0, 0, 0],
        ),
        baseline: 2000,
      );
      expect(find.textContaining('▲200'), findsOneWidget);

      await _pump(
        tester,
        report: _report(
          caloriesWeek: const <int>[1800, 1800, 1800, 0, 0, 0, 0],
        ),
        baseline: 2000,
      );
      expect(find.textContaining('▼200'), findsOneWidget);
    });

    testWidgets('평소와 같은 주에는 화살표를 붙이지 않는다', (tester) async {
      await _pump(
        tester,
        report: _report(
          caloriesWeek: const <int>[2000, 2000, 2000, 0, 0, 0, 0],
        ),
        baseline: 2000,
      );

      expect(find.textContaining('▲'), findsNothing);
      expect(find.textContaining('▼'), findsNothing);
    });

    testWidgets('바뀐 폭은 목표 초과와 다른 색이다 — 잘못이 아니라 달라짐이다', (tester) async {
      await _pump(
        tester,
        report: _report(
          caloriesWeek: const <int>[2600, 2600, 2600, 0, 0, 0, 0],
        ),
        baseline: 2000,
      );

      final InlineSpan span = tester
          .widgetList<Text>(find.textContaining('▲600'))
          .first
          .textSpan!;
      final List<Color?> colors = <Color?>[];
      span.visitChildren((InlineSpan child) {
        if (child is TextSpan && (child.text ?? '').contains('▲')) {
          colors.add(child.style?.color);
        }
        return true;
      });
      expect(colors, isNotEmpty);
      expect(colors.first, isNot(OnCareColors.danger));
    });

    testWidgets('견줄 것이 없으면 이번 주 평균만 적는다 — `평소 0kcal` 은 굶었다는 뜻이다', (
      tester,
    ) async {
      await _pump(
        tester,
        report: _report(caloriesWeek: const <int>[2000, 2200, 0, 0, 0, 0, 0]),
      );

      expect(find.textContaining('이번 주 평균 2,100kcal'), findsOneWidget);
      expect(find.textContaining('지난 4주 평균'), findsNothing);
    });

    testWidgets('기록이 하나도 없는 주에는 줄 자체가 없다', (tester) async {
      await _pump(
        tester,
        report: _report(caloriesWeek: const <int>[0, 0, 0, 0, 0, 0, 0]),
        baseline: 2000,
      );

      expect(find.textContaining('이번 주 평균'), findsNothing);
    });

    testWidgets('영어에서도 두 수가 다 번역되어 있다', (tester) async {
      await _pump(
        tester,
        report: _report(
          caloriesWeek: const <int>[2200, 2200, 2200, 0, 0, 0, 0],
        ),
        baseline: 2000,
        locale: 'en',
      );

      expect(find.textContaining('This week 2,200 kcal/day'), findsOneWidget);
      expect(
        find.textContaining('Past 4 weeks 2,000 kcal/day'),
        findsOneWidget,
      );
    });
  });
}
