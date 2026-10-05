import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';

ReportSheetWeekData _week({
  int booked = 0,
  int done = 0,
  int? calorieTarget,
  double? sugarTarget,
  List<int> calories = const <int>[],
  List<double> sugar = const <double>[],
  List<int> meals = const <int>[],
}) => ReportSheetWeekData(
  memberName: '김회원',
  weekStart: DateTime(2026, 9, 14),
  sessionsBooked: booked,
  sessionsDone: done,
  completionAvg: null,
  sodiumAvg: null,
  isCurrentWeek: false,
  calorieTarget: calorieTarget,
  sugarTarget: sugarTarget,
  caloriesWeek: calories,
  sugarWeek: sugar,
  mealCounts: meals,
);

void main() {
  group('recordedMean', () {
    test('기록된 날(0 초과)만 평균한다', () {
      expect(recordedMean(<int>[2000, 0, 1800, 0]), 1900);
    });

    test('기록이 하나도 없으면 null 이다 — 0 으로 보고하지 않는다', () {
      expect(recordedMean(<int>[0, 0, 0]), isNull);
      expect(recordedMean(const <int>[]), isNull);
    });

    test('정수 목록과 소수 목록을 모두 받는다', () {
      expect(recordedMean(<double>[1.5, 2.5]), 2);
      expect(recordedMean(<int>[1, 2]), 1.5);
    });
  });

  group('reportWeekStartOf', () {
    test('그 주의 월요일 자정으로 내린다', () {
      expect(
        reportWeekStartOf(DateTime(2026, 9, 17, 21, 30)),
        DateTime(2026, 9, 14),
      );
      expect(reportWeekStartOf(DateTime(2026, 9, 14)), DateTime(2026, 9, 14));
      expect(reportWeekStartOf(DateTime(2026, 9, 20)), DateTime(2026, 9, 14));
    });

    test('달을 넘기는 주도 달력 날짜로 뺀다', () {
      expect(reportWeekStartOf(DateTime(2026, 10, 2)), DateTime(2026, 9, 28));
    });
  });

  group('ReportSheetWeekFigures', () {
    test('일요일은 월요일에서 엿새 뒤다', () {
      expect(_week().weekEnd, DateTime(2026, 9, 20));
    });

    test('잡힌 수업이 없으면 출석률이 없다', () {
      expect(_week().attendanceRate, isNull);
      expect(_week(booked: 4, done: 3).attendanceRate, 75);
    });

    test('목표가 없으면 공통 기본값으로 판정한다', () {
      expect(_week().calorieGoal, kReportCalorieTargetKcal);
      expect(_week().sugarLimit, sugarLimitG);
      expect(_week(calorieTarget: 1800).calorieGoal, 1800);
      expect(_week(sugarTarget: 30).sugarLimit, 30);
    });

    test('평균은 기록된 날만 센다', () {
      final ReportSheetWeekData w = _week(
        calories: <int>[2000, 0, 2200],
        sugar: <double>[0, 40, 60],
      );
      expect(w.calorieMean, 2100);
      expect(w.sugarMean, 50);
    });

    test('끼니를 하나라도 적은 날을 센다', () {
      expect(_week(meals: <int>[3, 0, 1, 0, 2, 0, 0]).mealLoggedDays, 3);
    });
  });

  group('ReportSheetDayCounts', () {
    test('건너뛴 운동(✗)은 한 수에서 뺀다', () {
      const ReportSheetDayData day = ReportSheetDayData(
        completion: 50,
        exercises: <String>['스쿼트 ✓', '런지 ✗'],
      );
      expect(day.doneCount, 1);
      expect(day.totalCount, 2);
    });

    test('배정 수를 알면 그것이 분모다', () {
      const ReportSheetDayData day = ReportSheetDayData(
        completion: 33,
        exercises: <String>['스쿼트'],
        assigned: 3,
      );
      expect(day.totalCount, 3);
    });
  });

  group('추이 비율', () {
    const ReportSheetTrendData trend = ReportSheetTrendData(
      goals: ReportSheetGoals(
        weeklyCardioMinutes: 100,
        weeklyStrengthSets: 10,
        weeklyStretchingMinutes: 50,
      ),
      weeks: <ReportSheetTrendWeek>[],
    );

    test('유형마다 자기 단위의 목표로 나눈다', () {
      final ReportSheetTrendWeekData week = ReportSheetTrendWeekData(
        weekStart: DateTime(2026, 9, 14),
        cardioMinutes: 50,
        strengthSets: 10,
        stretchingMinutes: 100,
      );
      expect(trend.kindRatio(ExerciseKind.cardio, week), 0.5);
      expect(trend.kindRatio(ExerciseKind.strength, week), 1);
      expect(trend.kindRatio(ExerciseKind.stretching, week), 2);
      // 한 유형이 두 배여도 1 에서 자른다: (0.5 + 1 + 1) / 3.
      expect(trend.weekRate(week), closeTo(2.5 / 3, 1e-9));
    });

    test('목표가 0 이면 견줄 수 없다', () {
      expect(reportTrendRatio(0, 30), isNull);
      expect(reportTrendRate(<double?>[null, null]), isNull);
    });

    test('리포트가 보는 주는 목록의 마지막이다', () {
      expect(trend.currentWeek, isNull);
      final ReportSheetTrendData two = ReportSheetTrendData(
        goals: const ReportSheetGoals(),
        weeks: <ReportSheetTrendWeek>[
          ReportSheetTrendWeekData(
            weekStart: DateTime(2026, 9, 7),
            cardioMinutes: 0,
            strengthSets: 0,
            stretchingMinutes: 0,
          ),
          ReportSheetTrendWeekData(
            weekStart: DateTime(2026, 9, 14),
            cardioMinutes: 30,
            strengthSets: 0,
            stretchingMinutes: 0,
          ),
        ],
      );
      expect(two.currentWeek!.weekStart, DateTime(2026, 9, 14));
      expect(two.weeks.first.isEmpty, isTrue);
      expect(two.currentWeek!.isEmpty, isFalse);
    });

    test('기본 목표는 두 앱의 기본값과 같다', () {
      const ReportSheetGoals goals = ReportSheetGoals();
      expect(goals.of(ExerciseKind.cardio), 150);
      expect(goals.of(ExerciseKind.strength), 21);
      expect(goals.of(ExerciseKind.stretching), 60);
    });
  });

  group('ReportSheetAnswersData.fromWire', () {
    test('컨디션·강도를 모르는 값이면 답이 아니다', () {
      expect(
        ReportSheetAnswersData.fromWire(condition: 'meh', intensity: 'right'),
        isNull,
      );
      expect(
        ReportSheetAnswersData.fromWire(condition: 'good', intensity: ''),
        isNull,
      );
    });

    test('아픈 곳이 비면 날짜도 버린다', () {
      final ReportSheetAnswersData a = ReportSheetAnswersData.fromWire(
        condition: 'ok',
        intensity: 'hard',
        painArea: '  ',
        painOn: '2026-09-17',
        note: ' 메모 ',
      )!;
      expect(a.hasPain, isFalse);
      expect(a.painOn, isNull);
      expect(a.note, '메모');
    });

    test('아픈 곳과 날짜를 함께 읽는다', () {
      final ReportSheetAnswersData a = ReportSheetAnswersData.fromWire(
        condition: 'tired',
        intensity: 'too_hard',
        painArea: '오른쪽 어깨',
        painOn: '2026-09-17',
      )!;
      expect(a.hasPain, isTrue);
      expect(a.painOn, DateTime(2026, 9, 17));
    });
  });

  test('withAnswers 는 답만 바꿔 끼운다', () {
    final ReportSheetWeekData w = _week(booked: 2, done: 1);
    const ReportSheetAnswersData a = ReportSheetAnswersData(
      conditionWire: 'good',
      intensityWire: 'right',
    );
    final ReportSheetWeekData next = w.withAnswers(a);
    expect(next.answers, same(a));
    expect(next.sessionsBooked, 2);
    expect(next.weekStart, w.weekStart);
    expect(w.answers, isNull);
  });
}
