/// ① 탄단지 막대 — 기록한 날의 하루 평균을 목표와 나란히. (#2232)
///
/// 칼로리 총량은 같은 2,000kcal 이 밥에서 왔는지 기름에서 왔는지 말하지
/// 않는다. 그래서 이 카드가 지켜야 하는 것은 둘이다 — **안 적은 날을 0 으로
/// 세지 않는 것**, 그리고 매주 아무 데나 빨갛게 짚지 않는 것.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_macro_bars.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';

final DateTime _week = DateTime(2026, 9, 14);

/// 일곱 날 모두 기록한, 목표에 얼추 닿은 주.
WeeklyReport _report({
  List<int> caloriesWeek = const <int>[
    1850,
    1900,
    1800,
    1950,
    1880,
    1820,
    1900,
  ],
  List<double> carbsWeek = const <double>[240, 250, 245, 255, 248, 242, 250],
  List<double> proteinWeek = const <double>[115, 120, 118, 122, 119, 116, 120],
  List<double> fatWeek = const <double>[58, 60, 59, 61, 60, 58, 60],
  double? carbsTarget = 250,
  double? proteinTarget = 120,
  double? fatTarget = 60,
  List<String> weekGoals = const <String>[],
}) => WeeklyReport(
  client: makeClient(name: '김민수'),
  weekStart: _week,
  sessionsBooked: 2,
  sessionsDone: 2,
  completionAvg: 80,
  sodiumOverDays: 0,
  sodiumAvg: 1700,
  isCurrentWeek: false,
  caloriesWeek: caloriesWeek,
  carbsWeek: carbsWeek,
  proteinWeek: proteinWeek,
  fatWeek: fatWeek,
  carbsTarget: carbsTarget,
  proteinTarget: proteinTarget,
  fatTarget: fatTarget,
  weekGoals: weekGoals,
);

Future<void> _pump(
  WidgetTester tester, {
  WeeklyReport? report,
  String locale = 'ko',
  Size size = const Size(700, 600),
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
          child: ReportMacroBars(report: report ?? _report()),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 막대 안의 칸들. 화면 바탕의 ColoredBox 까지 세지 않게 막대 안에서만 찾는다.
Finder _segments() => find.descendant(
  of: find.byType(ClipRRect),
  matching: find.byType(ColoredBox),
);

/// 이어 붙인 막대에서 [index] 번째 칸의 폭.
double _segment(WidgetTester tester, int index) =>
    tester.getSize(_segments().at(index)).width;

/// 막대 전체의 폭.
double _track(WidgetTester tester) =>
    tester.getSize(find.byType(ClipRRect)).width;

void main() {
  testWidgets('셋이 한 막대에 탄·단·지 순서로 이어 붙는다', (tester) async {
    await _pump(tester);

    // 따로 세 줄을 그리면 각자의 목표 대비는 보이지만 **구성**이 보이지 않는다.
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(_segments(), findsNWidgets(3));
    final double carbs = tester.getCenter(_segments().at(0)).dx;
    final double protein = tester.getCenter(_segments().at(1)).dx;
    final double fat = tester.getCenter(_segments().at(2)).dx;
    expect(carbs, lessThan(protein));
    expect(protein, lessThan(fat));
  });

  testWidgets('칸 안에 값과 목표를 함께 적는다', (tester) async {
    await _pump(tester);

    expect(find.text('탄수화물 247 / 250g'), findsOneWidget);
    expect(find.text('단백질 119 / 120g'), findsOneWidget);
    expect(find.text('지방 59 / 60g'), findsOneWidget);
  });

  testWidgets('칸의 폭은 그램 수의 비율이다 — 구성을 보는 막대다', (tester) async {
    await _pump(tester);

    // 247 : 119 : 59 — 탄수화물이 절반을 넘는다.
    final double track = _track(tester);
    expect(_segment(tester, 0) / track, closeTo(247 / 425, 0.02));
    expect(_segment(tester, 1) / track, closeTo(119 / 425, 0.02));
  });

  testWidgets('안 적은 날은 평균에서 빠진다 — 성실한 주가 부족해 보이지 않게', (tester) async {
    // 사흘만 적었고 그 사흘은 모두 목표에 닿았다. 0 으로 세면 평균이 절반이
    // 되어, 트레이너가 그 주에 없던 문제를 고치려 든다.
    await _pump(
      tester,
      report: _report(
        caloriesWeek: const <int>[1900, 0, 0, 1900, 0, 0, 1900],
        carbsWeek: const <double>[250, 0, 0, 250, 0, 0, 250],
        proteinWeek: const <double>[120, 0, 0, 120, 0, 0, 120],
        fatWeek: const <double>[60, 0, 0, 60, 0, 0, 60],
      ),
    );

    expect(find.text('탄수화물 250 / 250g'), findsOneWidget);
  });

  testWidgets('제목 줄 없이 막대만 선다 — 칸 안의 `목표 대비` 가 이미 말한다', (tester) async {
    await _pump(tester);

    expect(find.textContaining('탄단지'), findsNothing);
  });

  testWidgets('목표를 안 적어 둔 항목은 기본값으로 견준다 — 회원 앱이 쓰는 것과 같은 수다 (#2232)', (
    tester,
  ) async {
    await _pump(tester, report: _report(fatTarget: null));

    // `59g` 만 적으면 그 수가 많은지 적은지는 그램 수를 외우는 사람만 안다.
    expect(find.text('지방 59 / 55g'), findsOneWidget);
  });

  testWidgets('기록이 없는 항목은 칸을 차지하지 않는다 — 0g 짜리 칸은 폭이 없다', (tester) async {
    await _pump(
      tester,
      report: _report(proteinWeek: const <double>[0, 0, 0, 0, 0, 0, 0]),
    );

    expect(_segments(), findsNWidgets(2));
    expect(find.textContaining('단백질'), findsNothing);
  });

  testWidgets('세 항목이 모두 비면 카드가 빈 상태로 선다', (tester) async {
    await _pump(
      tester,
      report: _report(
        carbsWeek: const <double>[],
        proteinWeek: const <double>[],
        fatWeek: const <double>[],
      ),
    );

    expect(find.text('아직 끼니 기록이 없어 탄단지를 볼 수 없어요'), findsOneWidget);
    expect(find.byType(ClipRRect), findsNothing);
  });

  testWidgets('세 칸이 서로 다른 진하기를 쓴다 — 다른 뜻의 색과 헷갈리지 않게', (tester) async {
    await _pump(tester);

    final Set<Color> colors = <Color>{
      for (int i = 0; i < 3; i++)
        tester.widget<ColoredBox>(_segments().at(i)).color,
    };
    expect(colors, hasLength(3));
  });

  testWidgets('목표의 80%에 못 미치는 항목을 한 줄로 짚어 준다', (tester) async {
    await _pump(
      tester,
      // 목표(120g)의 절반이다.
      report: _report(proteinWeek: const <double>[60, 60, 60, 60, 60, 60, 60]),
    );

    expect(find.textContaining('단백질이(가) 목표에 많이 모자라요'), findsOneWidget);
  });

  testWidgets('셋 다 모자라도 가장 많이 모자란 하나만 짚는다', (tester) async {
    await _pump(
      tester,
      report: _report(
        carbsWeek: const <double>[150, 150, 150, 150, 150, 150, 150], // 60%
        proteinWeek: const <double>[36, 36, 36, 36, 36, 36, 36], // 30%
        fatWeek: const <double>[30, 30, 30, 30, 30, 30, 30], // 50%
      ),
    );

    expect(find.textContaining('목표에 많이 모자라요'), findsOneWidget);
    expect(find.textContaining('단백질이(가) 목표에'), findsOneWidget);
  });

  testWidgets('그 모자람이 지난 주 목표를 떨어뜨렸다면 근거로 이어 적는다', (tester) async {
    await _pump(
      tester,
      report: _report(
        proteinWeek: const <double>[60, 60, 60, 60, 60, 60, 60],
        weekGoals: const <String>['저녁 단백질 챙기기'],
      ),
    );

    expect(
      find.textContaining('지난 주 목표 “저녁 단백질 챙기기”이 미이행으로 판정된 근거예요'),
      findsOneWidget,
    );
  });

  testWidgets('목표의 90%인 주는 짚지 않는다 — 매주 빨간 줄이 서면 색이 뜻을 잃는다', (tester) async {
    await _pump(
      tester,
      report: _report(
        proteinWeek: const <double>[108, 108, 108, 108, 108, 108, 108],
      ),
    );

    expect(find.textContaining('목표에 많이 모자라요'), findsNothing);
  });

  testWidgets('딱 80%인 주도 짚지 않는다 — 경계값', (tester) async {
    await _pump(
      tester,
      report: _report(proteinWeek: const <double>[96, 96, 96, 96, 96, 96, 96]),
    );

    expect(find.textContaining('목표에 많이 모자라요'), findsNothing);
  });

  testWidgets('목표를 안 적어 뒀어도 크게 모자라면 짚는다 — 기본값이 기준이 된다 (#2232)', (tester) async {
    await _pump(
      tester,
      report: _report(
        proteinWeek: const <double>[10, 10, 10, 10, 10, 10, 10],
        proteinTarget: null,
        carbsTarget: null,
        fatTarget: null,
      ),
    );

    expect(find.textContaining('목표에 많이 모자라요'), findsOneWidget);
  });

  testWidgets('영어에서 모든 자리가 번역되어 있다', (tester) async {
    await _pump(tester, locale: 'en');

    expect(find.text('Carbs 247 / 250g'), findsOneWidget);
    expect(find.text('Protein 119 / 120g'), findsOneWidget);
    expect(find.text('Fat 59 / 60g'), findsOneWidget);
  });

  testWidgets('영어에서 짚는 글월도 번역되어 있다', (tester) async {
    await _pump(
      tester,
      locale: 'en',
      report: _report(proteinWeek: const <double>[36, 36, 36, 36, 36, 36, 36]),
    );

    expect(
      find.textContaining(
        'Protein is well under target — worth picking as a goal for next week',
      ),
      findsOneWidget,
    );
  });

  testWidgets('영어 빈 카드도 번역되어 있다', (tester) async {
    await _pump(
      tester,
      locale: 'en',
      report: _report(
        carbsWeek: const <double>[],
        proteinWeek: const <double>[],
        fatWeek: const <double>[],
      ),
    );

    expect(
      find.text("No meals logged yet, so macros can't be shown"),
      findsOneWidget,
    );
  });

  testWidgets('영어 화면에 한글이 남아 있지 않다', (tester) async {
    await _pump(tester, locale: 'en');

    final RegExp hangul = RegExp(r'[가-힣]');
    for (final Element e in find.byType(Text).evaluate()) {
      final Text text = e.widget as Text;
      final String data = text.data ?? text.textSpan?.toPlainText() ?? '';
      expect(hangul.hasMatch(data), isFalse, reason: '번역되지 않은 글: $data');
    }
  });

  testWidgets('좁은 폭에서도 넘치지 않는다', (tester) async {
    await _pump(tester, size: const Size(320, 600));

    expect(tester.takeException(), isNull);
  });
}
