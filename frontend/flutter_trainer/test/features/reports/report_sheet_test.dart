import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/domain/report_sheet.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart'
    show calorieTargetKcal;

import '../../helpers/client_factory.dart';

WeeklyReport _report({
  DateTime? weekStart,
  int sessionsBooked = 2,
  int sessionsDone = 1,
  int? completionAvg = 72,
  int? sodiumAvg = 1890,
  bool isCurrentWeek = false,
  List<int> caloriesWeek = const <int>[2000, 0, 1900, 2600, 1000, 0, 0],
  List<double> carbsWeek = const <double>[],
  List<double> proteinWeek = const <double>[],
  List<double> fatWeek = const <double>[],
  List<double> sugarWeek = const <double>[],
  List<int> mealCounts = const <int>[3, 0, 2, 3, 1, 0, 0],
  int? calorieTarget = 2000,
}) => WeeklyReport(
  client: makeClient(id: 'sheet-client', name: '김회원'),
  weekStart: weekStart ?? DateTime(2026, 8, 10),
  sessionsBooked: sessionsBooked,
  sessionsDone: sessionsDone,
  completionAvg: completionAvg,
  sodiumOverDays: 1,
  sodiumAvg: sodiumAvg,
  isCurrentWeek: isCurrentWeek,
  caloriesWeek: caloriesWeek,
  carbsWeek: carbsWeek,
  proteinWeek: proteinWeek,
  fatWeek: fatWeek,
  sugarWeek: sugarWeek,
  mealCounts: mealCounts,
  calorieTarget: calorieTarget,
);

ReportTrendWeek _week(
  DateTime start, {
  int cardio = 0,
  int strength = 0,
  int stretching = 0,
}) => ReportTrendWeek(
  weekStart: start,
  cardioMinutes: cardio,
  strengthSets: strength,
  stretchingMinutes: stretching,
  cardioCalories: 0,
  strengthCalories: 0,
  stretchingCalories: 0,
);

WeeklyReport _empty() => WeeklyReport(
  client: makeClient(id: 'sheet-empty', name: '무기록'),
  weekStart: DateTime(2026, 8, 10),
  sessionsBooked: 0,
  sessionsDone: 0,
  completionAvg: null,
  sodiumOverDays: null,
  sodiumAvg: null,
  isCurrentWeek: false,
);

void main() {
  group('sheetBarPosition — 세 칸 고정 폭 막대 (#2485)', () {
    test('부족·적정·초과 칸의 경계가 늘 같은 자리에 선다', () {
      const double normalStart = kSheetUnderSpan;
      const double overStart = kSheetUnderSpan + kSheetNormalSpan;

      expect(
        sheetBarPosition(0.85, low: 0.85, high: 1.15, axisMax: 2),
        normalStart,
      );
      expect(
        sheetBarPosition(1.15, low: 0.85, high: 1.15, axisMax: 2),
        closeTo(overStart, 1e-9),
      );
      // 적정 범위가 다른 항목도 같은 칸 경계를 쓴다.
      expect(
        sheetBarPosition(0.8, low: 0.8, high: 1.2, axisMax: 2),
        normalStart,
      );
      expect(
        sheetBarPosition(1.2, low: 0.8, high: 1.2, axisMax: 2),
        closeTo(overStart, 1e-9),
      );
    });

    test('칸 안에서는 비율에 따라 곧게 늘어난다', () {
      expect(
        sheetBarPosition(0.4, low: 0.8, high: 1.2, axisMax: 2),
        closeTo(kSheetUnderSpan / 2, 1e-9),
      );
      expect(
        sheetBarPosition(1.0, low: 0.8, high: 1.2, axisMax: 2),
        closeTo(kSheetUnderSpan + kSheetNormalSpan / 2, 1e-9),
      );
      expect(
        sheetBarPosition(1.6, low: 0.8, high: 1.2, axisMax: 2),
        closeTo(0.8, 1e-9),
      );
    });

    test('축 끝을 넘는 값은 끝에 붙고, 음수는 0 이다', () {
      expect(sheetBarPosition(9, low: 0.8, high: 1.2, axisMax: 2), 1);
      expect(sheetBarPosition(-1, low: 0.8, high: 1.2, axisMax: 2), 0);
    });

    test('상한만 있는 항목은 0 부터 적정 칸에서 시작한다', () {
      expect(sheetBarPosition(0, low: 0, high: 1, axisMax: 2), kSheetUnderSpan);
      expect(
        sheetBarPosition(1, low: 0, high: 1, axisMax: 2),
        closeTo(kSheetUnderSpan + kSheetNormalSpan, 1e-9),
      );
    });

    test('100% 가 끝인 항목은 적정 칸 끝에서 멈춘다', () {
      expect(
        sheetBarPosition(1, low: 0.8, high: 1, axisMax: 1),
        closeTo(kSheetUnderSpan + kSheetNormalSpan, 1e-9),
      );
      expect(
        sheetBarPosition(1.3, low: 0.8, high: 1, axisMax: 1),
        closeTo(kSheetUnderSpan + kSheetNormalSpan, 1e-9),
      );
    });
  });

  group('SheetMeasure', () {
    test('비율로 칸을 고른다', () {
      SheetBand? band(double v) =>
          SheetMeasure(value: v, target: 100, low: 0.8, high: 1.2).band;

      expect(band(50), SheetBand.under);
      expect(band(80), SheetBand.normal);
      expect(band(120), SheetBand.normal);
      expect(band(121), SheetBand.over);
    });

    test('값이 없거나 목표가 없으면 칸도 자리도 없다', () {
      const SheetMeasure none = SheetMeasure(
        value: null,
        target: 100,
        low: 0.8,
        high: 1.2,
      );
      const SheetMeasure noTarget = SheetMeasure(
        value: 10,
        target: 0,
        low: 0.8,
        high: 1.2,
      );

      expect(none.band, isNull);
      expect(none.position, isNull);
      expect(none.concerning, isNull);
      expect(noTarget.ratio, isNull);
      expect(noTarget.band, isNull);
    });

    test('상한만 있는 항목에는 부족 칸이, 100% 끝 항목에는 초과 칸이 없다', () {
      const SheetMeasure limit = SheetMeasure(
        value: 100,
        target: 2000,
        low: 0,
        high: 1,
      );
      const SheetMeasure rate = SheetMeasure(
        value: 100,
        target: 100,
        low: 0.8,
        high: 1,
        axisMax: 1,
      );

      expect(limit.hasUnder, isFalse);
      expect(limit.hasOver, isTrue);
      expect(limit.band, SheetBand.normal);
      expect(rate.hasUnder, isTrue);
      expect(rate.hasOver, isFalse);
      expect(rate.band, SheetBand.normal);
    });

    test('운동량은 목표를 넘겨도 짚지 않지만 식단은 짚는다', () {
      const SheetMeasure workout = SheetMeasure(
        value: 300,
        target: 100,
        low: 0.8,
        high: 1.2,
        overIsFine: true,
      );
      const SheetMeasure food = SheetMeasure(
        value: 300,
        target: 100,
        low: 0.8,
        high: 1.2,
      );

      expect(workout.band, SheetBand.over);
      expect(workout.concerning, isFalse);
      expect(food.concerning, isTrue);
    });
  });

  group('ReportSheet.of — 식단', () {
    test('열량은 기록한 날의 평균을 목표 ±15% 로 판정한다', () {
      final ReportSheet sheet = ReportSheet.of(_report());
      final SheetMeasure kcal = sheet.diet[SheetDietItem.calories]!;

      // (2000 + 1900 + 2600 + 1000) / 4 = 1875
      expect(kcal.value, 1875);
      expect(kcal.target, 2000);
      expect(kcal.low, closeTo(0.85, 1e-9));
      expect(kcal.high, closeTo(1.15, 1e-9));
      expect(kcal.band, SheetBand.normal);
    });

    test('회원 목표가 없으면 공통 기본값으로 견준다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(
          calorieTarget: null,
          proteinWeek: const <double>[50, 0, 0, 0, 0, 0, 0],
        ),
      );

      expect(sheet.diet[SheetDietItem.calories]!.target, calorieTargetKcal);
      expect(sheet.diet[SheetDietItem.protein]!.value, 50);
      expect(sheet.diet[SheetDietItem.protein]!.band, SheetBand.under);
    });

    test('나트륨·당류는 상한만 본다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(sugarWeek: const <double>[80, 0, 70, 0, 0, 0, 0]),
      );

      final SheetMeasure sodium = sheet.diet[SheetDietItem.sodium]!;
      final SheetMeasure sugar = sheet.diet[SheetDietItem.sugar]!;
      expect(sodium.hasUnder, isFalse);
      expect(sodium.band, SheetBand.normal);
      expect(sugar.band, SheetBand.over);
      expect(sugar.concerning, isTrue);
    });

    test('기록이 없는 항목은 값이 없다', () {
      final ReportSheet sheet = ReportSheet.of(_empty());

      for (final SheetMeasure m in sheet.diet.values) {
        expect(m.value, isNull);
        expect(m.band, isNull);
      }
    });
  });

  group('ReportSheet.of — 운동', () {
    final DateTime monday = DateTime(2026, 8, 10);

    test('수행률·출석은 100% 가 끝이고 80% 부터 적정이다', () {
      final ReportSheet sheet = ReportSheet.of(_report());
      final SheetMeasure completion =
          sheet.exercise[SheetExerciseItem.completion]!;
      final SheetMeasure attendance =
          sheet.exercise[SheetExerciseItem.attendance]!;

      expect(completion.value, 72);
      expect(completion.band, SheetBand.under);
      expect(completion.hasOver, isFalse);
      expect(attendance.value, 50);
      expect(attendance.band, SheetBand.under);
    });

    test('예약이 없으면 출석은 값이 없다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(sessionsBooked: 0, sessionsDone: 0),
      );

      expect(sheet.exercise[SheetExerciseItem.attendance]!.value, isNull);
    });

    test('유형별 줄은 이번 주 실적을 주간 목표와 견준다', () {
      final ReportTrend trend = ReportTrend(
        weeks: <ReportTrendWeek>[
          _week(monday.subtract(const Duration(days: 7)), cardio: 10),
          _week(monday, cardio: 150, strength: 3, stretching: 60),
        ],
        // 유산소 150분·스트레칭 60분은 기본 목표 그대로다.
        goals: const ExerciseBurnGoals(weeklyStrengthSets: 12),
      );
      final ReportSheet sheet = ReportSheet.of(_report(), trend: trend);

      final SheetMeasure cardio = sheet.exercise[SheetExerciseItem.cardio]!;
      final SheetMeasure strength = sheet.exercise[SheetExerciseItem.strength]!;
      expect(cardio.value, 150);
      expect(cardio.target, 150);
      expect(cardio.band, SheetBand.normal);
      expect(strength.band, SheetBand.under);
      expect(strength.concerning, isTrue);
    });

    test('추세가 없으면 유형별 줄과 주별 달성률이 비어 있다', () {
      final ReportSheet sheet = ReportSheet.of(_report());

      expect(sheet.exercise[SheetExerciseItem.cardio]!.value, isNull);
      expect(sheet.exercise[SheetExerciseItem.cardio]!.band, isNull);
      expect(sheet.weeklyRates, isEmpty);
    });

    test('주별 달성률은 기록 없는 주를 비워 둔다', () {
      final ReportTrend trend = ReportTrend(
        weeks: <ReportTrendWeek>[
          _week(monday.subtract(const Duration(days: 14))),
          _week(
            monday.subtract(const Duration(days: 7)),
            cardio: 150,
            strength: 12,
            stretching: 60,
          ),
          _week(monday, cardio: 75),
        ],
        // 유산소 150분·스트레칭 60분은 기본 목표 그대로다.
        goals: const ExerciseBurnGoals(weeklyStrengthSets: 12),
      );
      final ReportSheet sheet = ReportSheet.of(_report(), trend: trend);

      expect(sheet.weeklyRates, hasLength(3));
      expect(sheet.weeklyRates[0], isNull);
      expect(sheet.weeklyRates[1], closeTo(1, 1e-9));
      expect(sheet.weeklyRates[2], closeTo(0.5 / 3, 1e-9));
    });
  });

  group('주간 관리 점수', () {
    test('네 항목 점수의 평균이다', () {
      final ReportSheet sheet = ReportSheet.of(_report());
      final Map<SheetScorePart, double> parts = sheet.score.parts;

      expect(parts[SheetScorePart.completion], 72);
      expect(parts[SheetScorePart.attendance], 50);
      // 지난 주 — 이레 중 나흘 기록.
      expect(parts[SheetScorePart.mealLogging], closeTo(400 / 7, 1e-9));
      // 기록한 나흘 중 목표 ±15% 안: 2000·1900 두 날.
      expect(parts[SheetScorePart.calorieDays], 50);
      expect(sheet.score.value, ((72 + 50 + 400 / 7 + 50) / 4).round());
    });

    test('기록 없는 항목은 빼고 평균한다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(
          sessionsBooked: 0,
          sessionsDone: 0,
          caloriesWeek: const <int>[],
          mealCounts: const <int>[],
        ),
      );

      expect(sheet.score.parts.keys, <SheetScorePart>[
        SheetScorePart.completion,
      ]);
      expect(sheet.score.value, 72);
    });

    test('아무 기록도 없으면 점수가 없다', () {
      expect(ReportSheet.of(_empty()).score.value, isNull);
    });

    test('이번 주는 오늘까지의 날로 식단 기록을 센다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(isCurrentWeek: true),
        // 목요일 — 나흘이 지났다.
        today: DateTime(2026, 8, 13),
      );

      expect(sheet.mealDaysDue, 4);
      expect(sheet.mealDays, 4);
      expect(sheet.score.parts[SheetScorePart.mealLogging], 100);
    });

    test('항목 점수는 100 을 넘지 않는다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(sessionsBooked: 1, sessionsDone: 3, completionAvg: 140),
      );

      expect(sheet.score.parts[SheetScorePart.completion], 100);
      expect(sheet.score.parts[SheetScorePart.attendance], 100);
    });
  });

  group('4주 평균 대비', () {
    WeeklyReport past(int back, {int? completion, int? sodium, int kcal = 0}) =>
        _report(
          weekStart: DateTime(2026, 8, 10 - 7 * back),
          completionAvg: completion,
          sodiumAvg: sodium,
          caloriesWeek: <int>[kcal, 0, 0, 0, 0, 0, 0],
          mealCounts: const <int>[1, 1, 0, 0, 0, 0, 0],
        );

    test('직전 주들의 평균과 이번 주의 차이를 낸다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(),
        history: <WeeklyReport>[
          past(1, completion: 60, sodium: 2000, kcal: 2200),
          past(2, completion: 80, sodium: 1800, kcal: 1800),
        ],
      );

      final SheetAverage completion =
          sheet.averages[SheetAverageItem.completion]!;
      expect(completion.current, 72);
      expect(completion.average, 70);
      expect(completion.change, 2);

      final SheetAverage kcal = sheet.averages[SheetAverageItem.calories]!;
      // 기록한 날만 — 2200 과 1800.
      expect(kcal.average, 2000);
      expect(kcal.change, -125);

      expect(sheet.averages[SheetAverageItem.sodium]!.average, 1900);
      expect(sheet.averages[SheetAverageItem.mealDays]!.current, 4);
      expect(sheet.averages[SheetAverageItem.mealDays]!.average, 2);
    });

    test('집계가 없던 주는 평균에서 빠진다', () {
      final ReportSheet sheet = ReportSheet.of(
        _report(),
        history: <WeeklyReport>[past(1, completion: 60), past(2)],
      );

      expect(sheet.averages[SheetAverageItem.completion]!.average, 60);
      expect(sheet.averages[SheetAverageItem.sodium]!.average, isNull);
      expect(sheet.averages[SheetAverageItem.sodium]!.change, isNull);
      expect(sheet.averages[SheetAverageItem.calories]!.average, isNull);
    });

    test('지난 주들이 없으면 평균도 변화도 없다', () {
      final ReportSheet sheet = ReportSheet.of(_report());

      for (final SheetAverage a in sheet.averages.values) {
        expect(a.average, isNull);
        expect(a.change, isNull);
      }
    });
  });
}
