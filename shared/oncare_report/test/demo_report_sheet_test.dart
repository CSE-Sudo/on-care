import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';

final DemoFixture _fixture = DemoFixture.load();

/// 데모를 여는 날 — 목요일 저녁. 이번 주는 월~목까지만 날짜가 붙는다.
final DateTime _now = DateTime(2026, 9, 17, 20);
final DateTime _thisMonday = DateTime(2026, 9, 14);

ReportSheetInputs _inputs({DateTime? weekStart, String lang = 'ko'}) =>
    demoReportSheetInputs(
      fixture: _fixture,
      weekStart: weekStart ?? _thisMonday,
      now: _now,
      languageCode: lang,
    );

void main() {
  group('demoReportSheetInputs — 트레이너 웹 데모와 같은 김민수 (#2652)', () {
    test('회원 이름은 픽스처의 이름이다', () {
      expect(_inputs().week.memberName, _fixture.memberName);
    });

    test('직전 네 주와 여덟 주 추이를 함께 만든다', () {
      final ReportSheetInputs inputs = _inputs();
      expect(inputs.history, hasLength(kReportSheetHistoryWeeks));
      expect(inputs.history.first.weekStart, DateTime(2026, 9, 7));
      expect(inputs.history.last.weekStart, DateTime(2026, 8, 17));
      final ReportSheetTrend trend = inputs.trend!;
      expect(trend.weeks, hasLength(kReportSheetTrendWeeks));
      expect(trend.weeks.last.weekStart, _thisMonday);
      expect(trend.weeks.first.weekStart, DateTime(2026, 7, 27));
    });

    test('목표는 김민수가 적어 둔 주간 운동 목표다', () {
      final ReportSheetTrend trend = _inputs().trend!;
      expect(trend.goalOf(ExerciseKind.cardio), 180);
      expect(trend.goalOf(ExerciseKind.strength), 18);
      expect(trend.goalOf(ExerciseKind.stretching), 60);
    });

    test('하루 목표는 적혀 있지 않아 공통 기본값으로 판정한다', () {
      final ReportSheetWeek w = _inputs().week;
      expect(w.calorieTarget, isNull);
      expect(w.sodiumTarget, isNull);
      expect(w.calorieGoal, kReportCalorieTargetKcal);
    });

    test('PT 는 픽스처가 적은 지난 PT 날과 오늘 수업이고, 모두 진행했다', () {
      final String today =
          '${_now.year}-${_now.month.toString().padLeft(2, '0')}-'
          '${_now.day.toString().padLeft(2, '0')}';
      for (int back = 0; back <= kDemoReportPtWeeks; back++) {
        final DateTime monday = DateTime(
          _thisMonday.year,
          _thisMonday.month,
          _thisMonday.day - 7 * back,
        );
        final ReportSheetWeek w = _inputs(weekStart: monday).week;
        final String mondayYmd =
            '${monday.year}-${monday.month.toString().padLeft(2, '0')}-'
            '${monday.day.toString().padLeft(2, '0')}';
        final int pastPt = _fixture
            .daysFor(_now)
            .where(
              (FixtureDay d) =>
                  d.weekStart == mondayYmd && d.isPt && d.date != today,
            )
            .length;
        final int expected = pastPt + (back == 0 ? 1 : 0);
        expect(w.sessionsBooked, expected, reason: '$back주 전');
        expect(w.sessionsDone, expected, reason: '$back주 전');
      }
      // 이번 주는 오늘 수업이 늘 한 번 선다.
      expect(_inputs().week.sessionsBooked, greaterThanOrEqualTo(1));
      // 지난 주에도 픽스처 PT 날이 있다 — 빈 PT 이력이 아니다.
      expect(
        _inputs(
          weekStart: _thisMonday.subtract(const Duration(days: 7)),
        ).week.sessionsBooked,
        greaterThan(0),
      );
    });

    test('요일별 수치는 픽스처의 그날 값 그대로다', () {
      final ReportSheetWeek w = _inputs().week;
      final List<FixtureDay> days = _fixture
          .daysFor(_now)
          .where((FixtureDay d) => d.weekStart == '2026-09-14' && d.hasRecord)
          .toList();
      expect(days, isNotEmpty);
      for (final FixtureDay d in days) {
        final int i = DateTime.parse(d.date).weekday - 1;
        expect(w.caloriesWeek[i], d.calories, reason: d.date);
        expect(w.sodiumWeek[i], d.sodiumMg, reason: d.date);
        expect(w.weekCompletion[i], d.completion, reason: d.date);
        expect(w.mealCounts[i], d.meals.length, reason: d.date);
        expect(w.days[i].doneCount, d.doneExercises.length, reason: d.date);
      }
      // 오지 않은 요일(금~일)은 비어 있다.
      expect(w.caloriesWeek.sublist(4), <int>[0, 0, 0]);
      expect(w.mealCounts, hasLength(kReportWeekdayCount));
    });

    test('이번 주만 이번 주로 본다', () {
      expect(_inputs().week.isCurrentWeek, isTrue);
      for (final ReportSheetWeek past in _inputs().history) {
        expect(past.isCurrentWeek, isFalse);
      }
    });

    test('이번 주 답은 트레이너 웹 시드와 같다', () {
      final ReportSheetAnswers a = _inputs().week.answers!;
      expect(a.conditionWire, 'ok');
      expect(a.intensityWire, 'too_hard');
      expect(a.painArea, '오른쪽 어깨');
      expect(a.painOn, DateTime(2026, 9, 17));
      expect(a.note, startsWith('야근이 많아서'));
    });

    test('영어면 답도 영어로 옮긴다', () {
      final ReportSheetAnswers a = _inputs(lang: 'en').week.answers!;
      expect(a.painArea, 'Right shoulder');
      expect(a.note, startsWith('Lots of late nights'));
    });

    test('메모 없이 답만 낸 주와 답이 없는 주도 있다', () {
      final ReportSheetAnswers nine = _inputs(
        weekStart: DateTime(2026, 7, 13),
      ).week.answers!;
      expect(nine.conditionWire, 'tired');
      expect(nine.note, isEmpty);
      expect(_inputs(weekStart: DateTime(2026, 6, 15)).week.answers, isNull);
    });

    test('답은 열세 주치이고 주가 겹치지 않는다', () {
      final Set<int> weeks = <int>{
        for (final DemoReportAnswer a in kDemoReportAnswers) a.weeksAgo,
      };
      expect(weeks, hasLength(kDemoReportAnswers.length));
      expect(weeks, containsAll(List<int>.generate(13, (int i) => i)));
      for (final DemoReportAnswer a in kDemoReportAnswers) {
        expect(kReportConditionWires, contains(a.condition));
        expect(kReportIntensityWires, contains(a.intensity));
        expect(a.painArea.isEmpty, a.painAreaEn.isEmpty);
        expect(a.note.isEmpty, a.noteEn.isEmpty);
      }
    });
  });

  group('demoReportTrendWeek', () {
    test('실제로 한 운동만 유형별로 더한다', () {
      final List<FixtureDay> days = _fixture.daysFor(_now);
      final ReportSheetTrendWeekData week = demoReportTrendWeek(
        days,
        DateTime(2026, 9, 7),
      );
      int cardio = 0;
      int stretching = 0;
      for (final FixtureDay d in days) {
        if (d.weekStart != '2026-09-07') continue;
        for (final FixtureExercise e in d.doneExercises) {
          if (e.type == 'cardio' || e.type == 'walking') cardio += e.minutes;
          if (<String>['flexibility', 'stretching', 'yoga'].contains(e.type)) {
            stretching += e.minutes;
          }
        }
      }
      expect(week.cardioMinutes, cardio);
      expect(week.stretchingMinutes, stretching);
      expect(week.weekStart, DateTime(2026, 9, 7));
    });

    test('기록이 없는 주는 비어 있다', () {
      final ReportSheetTrendWeekData week = demoReportTrendWeek(
        const <FixtureDay>[],
        DateTime(2026, 9, 7),
      );
      expect(week.isEmpty, isTrue);
    });
  });

  test('데모 결과지의 점수가 선다', () {
    final ReportSheetInputs inputs = _inputs();
    final ReportSheet sheet = ReportSheet.of(
      inputs.week,
      trend: inputs.trend,
      history: inputs.history,
      today: _now,
    );
    expect(sheet.score.value, isNotNull);
    expect(sheet.mealDaysDue, 4);
    expect(sheet.exercise[SheetExerciseItem.attendance]!.value, 100);
  });
}
