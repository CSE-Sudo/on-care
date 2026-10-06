import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';
import 'package:oncare_ui/oncare_ui.dart'
    show
        kGoalDefaultDailyCarbsG,
        kGoalDefaultDailyFatG,
        kGoalDefaultDailyProteinG,
        kGoalDefaultDailySodiumMg;

ReportSheetWeekData _report({
  int sessionsBooked = 2,
  int sessionsDone = 1,
  int? completionAvg = 72,
  int? sodiumAvg = 1890,
  bool isCurrentWeek = false,
  List<int> caloriesWeek = const <int>[2000, 0, 1900, 2600, 1000, 0, 0],
  List<double> carbsWeek = const <double>[],
  List<double> proteinWeek = const <double>[],
  List<double> sugarWeek = const <double>[],
  List<int> sodiumWeek = const <int>[],
  List<int> mealCounts = const <int>[3, 0, 2, 3, 1, 0, 0],
  int? calorieTarget = 2000,
  double? proteinTarget,
  double? effectiveProteinTarget,
}) => ReportSheetWeekData(
  memberName: '김회원',
  weekStart: DateTime(2026, 8, 10),
  sessionsBooked: sessionsBooked,
  sessionsDone: sessionsDone,
  completionAvg: completionAvg,
  sodiumAvg: sodiumAvg,
  isCurrentWeek: isCurrentWeek,
  caloriesWeek: caloriesWeek,
  carbsWeek: carbsWeek,
  proteinWeek: proteinWeek,
  sugarWeek: sugarWeek,
  sodiumWeek: sodiumWeek,
  mealCounts: mealCounts,
  calorieTarget: calorieTarget,
  proteinTarget: proteinTarget,
  effectiveProteinTarget: effectiveProteinTarget,
);

ReportSheetTrendData _trend(List<(int, int, int)> weeks) =>
    ReportSheetTrendData(
      goals: const ReportSheetGoals(),
      weeks: <ReportSheetTrendWeek>[
        for (int i = 0; i < weeks.length; i++)
          ReportSheetTrendWeekData(
            weekStart: DateTime(2026, 8, 10 - 7 * (weeks.length - 1 - i)),
            cardioMinutes: weeks[i].$1,
            strengthSets: weeks[i].$2,
            stretchingMinutes: weeks[i].$3,
          ),
      ],
    );

void main() {
  group('sheetBarPosition', () {
    test('적정 칸은 비율과 상관없이 같은 자리에 선다', () {
      expect(
        sheetBarPosition(1, low: 0.8, high: 1.2, axisMax: 2),
        closeTo(kSheetUnderSpan + kSheetNormalSpan / 2, 1e-9),
      );
      expect(
        sheetBarPosition(0.4, low: 0.8, high: 1.2, axisMax: 2),
        closeTo(kSheetUnderSpan / 2, 1e-9),
      );
    });

    test('끝을 넘는 값은 끝에 붙는다', () {
      expect(sheetBarPosition(5, low: 0.8, high: 1.2, axisMax: 2), 1);
      expect(sheetBarPosition(-1, low: 0.8, high: 1.2, axisMax: 2), 0);
    });
  });

  group('SheetMeasure', () {
    test('값이 없으면 칸도 걱정 여부도 없다', () {
      const SheetMeasure m = SheetMeasure(
        value: null,
        target: 100,
        low: 0.8,
        high: 1.2,
      );
      expect(m.band, isNull);
      expect(m.concerning, isNull);
      expect(m.position, isNull);
    });

    test('운동량은 넘쳐도 걱정하지 않는다', () {
      const SheetMeasure m = SheetMeasure(
        value: 300,
        target: 100,
        low: 0.8,
        high: 1.2,
        overIsFine: true,
      );
      expect(m.band, SheetBand.over);
      expect(m.concerning, isFalse);
    });

    test('상한만 있는 항목에는 부족 칸이 없다', () {
      const SheetMeasure m = SheetMeasure(
        value: 10,
        target: 100,
        low: 0,
        high: 1,
      );
      expect(m.hasUnder, isFalse);
      expect(m.band, SheetBand.normal);
    });
  });

  group('ReportSheet.of', () {
    test('식단 막대는 기록된 날의 평균과 목표를 견준다', () {
      final ReportSheet sheet = ReportSheet.of(_report());
      final SheetMeasure kcal = sheet.diet[SheetDietItem.calories]!;
      expect(kcal.value, (2000 + 1900 + 2600 + 1000) / 4);
      expect(kcal.target, 2000);
      final SheetMeasure sodium = sheet.diet[SheetDietItem.sodium]!;
      expect(sodium.value, 1890);
      expect(sodium.target, kReportSodiumTargetMg);
    });

    test('탄단지 목표가 없으면 공통 기본값이다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(carbsWeek: <double>[250, 0, 300]),
      );
      expect(sheet.diet[SheetDietItem.carbs]!.target, kReportCarbsTargetG);
      expect(sheet.diet[SheetDietItem.carbs]!.value, 275);
      expect(sheet.diet[SheetDietItem.protein]!.value, isNull);
    });

    test('목표가 없는 탄단지는 두 앱의 기준선과 같은 값으로 견준다(#2906)', () {
      final ReportSheet sheet = ReportSheet.of(_report());
      // 단백질은 홈 카드·트레이너 영양 카드·서버 식단 분석과 같은 60g 이다.
      expect(
        sheet.diet[SheetDietItem.protein]!.target,
        kGoalDefaultDailyProteinG,
      );
      expect(sheet.diet[SheetDietItem.carbs]!.target, kGoalDefaultDailyCarbsG);
      expect(sheet.diet[SheetDietItem.fat]!.target, kGoalDefaultDailyFatG);
      expect(
        sheet.diet[SheetDietItem.sodium]!.target,
        kGoalDefaultDailySodiumMg,
      );
    });

    test('단백질은 실효 목표로 견주고, 개인 목표가 없으면 칸을 고르지 않는다 (#3246)', () {
      // 체중 80kg → 실효 목표 96g. 평균 90g 은 트레이너 화면에서 적정이다.
      final SheetMeasure m = ReportSheet.of(
        _report(
          proteinWeek: const <double>[90, 0, 90],
          effectiveProteinTarget: 96,
        ),
      ).diet[SheetDietItem.protein]!;
      expect(m.target, 96);
      expect(m.position, isNotNull);
      expect(m.band, isNull);
      expect(m.concerning, isNull);
    });

    test('탄단지는 개인 목표가 있을 때 ±25% 로 판정한다 (#3246)', () {
      SheetBand? band(double mean) => ReportSheet.of(
        _report(proteinWeek: <double>[mean], proteinTarget: 100),
      ).diet[SheetDietItem.protein]!.band;

      expect(band(76), SheetBand.normal);
      expect(band(74), SheetBand.under);
      expect(band(124), SheetBand.normal);
      expect(band(126), SheetBand.over);
    });

    test('나트륨은 평균이 목표 안이어도 초과 사흘이면 초과다 (#3246)', () {
      SheetMeasure sodium(List<int> week) => ReportSheet.of(
        _report(sodiumAvg: 1900, sodiumWeek: week),
      ).diet[SheetDietItem.sodium]!;

      final SheetMeasure three = sodium(<int>[2100, 2100, 2100, 1300]);
      expect(three.band, SheetBand.over);
      expect(three.concerning, isTrue);
      expect(sodium(<int>[2100, 2100, 1800, 1600]).band, SheetBand.normal);
    });

    test('당류는 평균이 기준 안이어도 초과 사흘이면 초과다 (#3246)', () {
      SheetBand? band(List<double> week) => ReportSheet.of(
        _report(sugarWeek: week),
      ).diet[SheetDietItem.sugar]!.band;

      // 기준 50g — 평균 46g 이지만 사흘을 넘겼다.
      expect(band(<double>[60, 55, 52, 10, 53]), SheetBand.over);
      expect(band(<double>[60, 55, 20, 10, 10]), SheetBand.normal);
    });

    test('출석은 진행 / 잡힌 수업이다', () {
      final ReportSheet sheet = ReportSheet.of(_report());
      expect(sheet.exercise[SheetExerciseItem.attendance]!.value, 50);
      final ReportSheet none = ReportSheet.of(_report(sessionsBooked: 0));
      expect(none.exercise[SheetExerciseItem.attendance]!.value, isNull);
    });

    test('추이가 없으면 유형별 줄이 비고 목표도 없다', () {
      final ReportSheet sheet = ReportSheet.of(_report());
      final SheetMeasure cardio = sheet.exercise[SheetExerciseItem.cardio]!;
      expect(cardio.value, isNull);
      expect(cardio.target, 0);
      expect(sheet.weeklyRates, isEmpty);
    });

    test('추이의 마지막 주가 유형별 줄이 된다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(),
        trend: _trend(<(int, int, int)>[(0, 0, 0), (150, 21, 30)]),
      );
      expect(sheet.exercise[SheetExerciseItem.cardio]!.value, 150);
      expect(sheet.exercise[SheetExerciseItem.strength]!.target, 21);
      expect(sheet.weeklyRates.first, isNull);
      expect(sheet.weeklyRates.last, closeTo((1 + 1 + 0.5) / 3, 1e-9));
    });

    test('지난 주는 이레 모두 끼니를 적었어야 한다', () {
      final ReportSheet sheet = ReportSheet.of(_report());
      expect(sheet.mealDays, 4);
      expect(sheet.mealDaysDue, 7);
    });

    test('이번 주는 오늘 요일까지만 센다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(isCurrentWeek: true),
        today: DateTime(2026, 8, 12), // 수요일
      );
      expect(sheet.mealDaysDue, 3);
    });

    test('끼니 횟수를 모르면 끼니 칸이 점수에서 빠진다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(mealCounts: const <int>[]),
      );
      expect(sheet.mealDaysDue, isNull);
      expect(sheet.score.parts.containsKey(SheetScorePart.mealLogging), false);
    });

    test('점수는 있는 항목의 평균이다', () {
      final ReportSheet sheet = ReportSheet.of(_report());
      // 수행 72, 출석 50, 끼니 4/7, 칼로리 2000·1900 두 날이 ±15% 안.
      expect(sheet.score.parts[SheetScorePart.completion], 72);
      expect(sheet.score.parts[SheetScorePart.attendance], 50);
      expect(
        sheet.score.parts[SheetScorePart.mealLogging],
        closeTo(400 / 7, 1e-9),
      );
      expect(sheet.score.parts[SheetScorePart.calorieDays], 50);
      expect(sheet.score.value, ((72 + 50 + 400 / 7 + 50) / 4).round());
    });

    test('아무 기록도 없으면 점수가 없다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(
          sessionsBooked: 0,
          completionAvg: null,
          caloriesWeek: const <int>[],
          mealCounts: const <int>[],
        ),
      );
      expect(sheet.score.value, isNull);
    });

    test('4주 평균은 직전 주들에서 기록된 값만 쓴다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(),
        history: <ReportSheetWeek>[
          _report(caloriesWeek: <int>[1800, 0, 2200], completionAvg: 60),
          _report(caloriesWeek: <int>[0, 0, 0], completionAvg: null),
        ],
      );
      final SheetAverage kcal = sheet.averages[SheetAverageItem.calories]!;
      expect(kcal.average, 2000);
      expect(kcal.change, kcal.current! - 2000);
      expect(sheet.averages[SheetAverageItem.completion]!.average, 60);
      expect(sheet.averages[SheetAverageItem.mealDays]!.current, 4);
    });

    test('직전 주가 없으면 증감도 없다', () {
      final ReportSheet sheet = ReportSheet.of(_report());
      expect(sheet.averages[SheetAverageItem.sodium]!.average, isNull);
      expect(sheet.averages[SheetAverageItem.sodium]!.change, isNull);
    });
  });
}
