import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';

Map<String, dynamic> _json() => <String, dynamic>{
  'member_id': 'm-1',
  'member_name': '김민수',
  'week_start': '2026-09-14',
  'week_end': '2026-09-20',
  'sessions_booked': 2,
  'sessions_done': 1,
  'completion_avg': 67,
  'sodium_over_days': 3,
  'sodium_avg': 2310,
  'week_completion': <int>[100, 0, 67, 0, 0, 0, 0],
  'sodium_week': <int>[2100, 0, 2520, 0, 0, 0, 0],
  'calories_week': <int>[2140, 0, 1980, 0, 0, 0, 0],
  'sugar_week': <num>[41.5, 0, 38, 0, 0, 0, 0],
  'carbs_week': <num>[280, 0, 250.5, 0, 0, 0, 0],
  'protein_week': <num>[90, 0, 110, 0, 0, 0, 0],
  'fat_week': <num>[60, 0, 55, 0, 0, 0, 0],
  'calorie_target': 2200,
  'sodium_target': 1800,
  'sugar_target': 40,
  'carbs_target': null,
  'days': <Map<String, dynamic>>[
    <String, dynamic>{
      'completion': 100,
      'exercises': <String>['스쿼트 ✓', '플랭크 ✓'],
    },
    <String, dynamic>{'completion': 0, 'exercises': <String>[]},
    <String, dynamic>{
      'completion': 67,
      'exercises': <String>['벤치 ✓', '런지 ✗'],
    },
  ],
  'message': '트레이너가 보낼 초안',
};

void main() {
  group('reportSheetWeekFromJson (#2652)', () {
    test('WeeklyReportOut 의 칸을 그대로 읽는다', () {
      final ReportSheetWeekData w = reportSheetWeekFromJson(
        _json(),
        today: DateTime(2026, 9, 30),
      );
      expect(w.memberName, '김민수');
      expect(w.weekStart, DateTime(2026, 9, 14));
      expect(w.sessionsBooked, 2);
      expect(w.sessionsDone, 1);
      expect(w.completionAvg, 67);
      expect(w.sodiumAvg, 2310);
      expect(w.caloriesWeek, <int>[2140, 0, 1980, 0, 0, 0, 0]);
      expect(w.sugarWeek.first, 41.5);
      expect(w.carbsWeek[2], 250.5);
      expect(w.calorieTarget, 2200);
      expect(w.sodiumTarget, 1800);
      expect(w.sugarTarget, 40);
      expect(w.carbsTarget, isNull);
      expect(w.days, hasLength(3));
      expect(w.days[2].doneCount, 1);
      expect(w.days[2].totalCount, 2);
    });

    test('끼니 횟수가 없는 옛 응답은 비어 있다 — 끼니 기록일이 `미집계`', () {
      final ReportSheetWeekData w = reportSheetWeekFromJson(_json());
      expect(w.mealCounts, isEmpty);
      expect(ReportSheet.of(w).mealDaysDue, isNull);
    });

    test('meal_counts 를 요일별 끼니 수로 읽는다 (#2772)', () {
      final ReportSheetWeekData w = reportSheetWeekFromJson(
        _json()..['meal_counts'] = <int>[3, 0, 2, 0, 0, 0, 0],
        today: DateTime(2026, 9, 30),
      );
      expect(w.mealCounts, <int>[3, 0, 2, 0, 0, 0, 0]);
      final ReportSheet sheet = ReportSheet.of(w, today: DateTime(2026, 9, 30));
      expect(sheet.mealDays, 2);
      expect(sheet.mealDaysDue, 7);
    });

    test('days[].assigned 를 그날 배정 수로 읽는다 (#2772)', () {
      final Map<String, dynamic> json = _json();
      final List<Map<String, dynamic>> days =
          json['days'] as List<Map<String, dynamic>>;
      days[0]['assigned'] = 3;
      days[1]['assigned'] = 0;
      days[2]['assigned'] = null;
      final ReportSheetWeekData w = reportSheetWeekFromJson(json);

      expect(w.days[0].assigned, 3);
      expect(w.days[0].doneCount, 2);
      expect(w.days[0].totalCount, 3);
      // 0 은 쉬는 날과 구분되지 않아 모르는 날(null)이다 — 분모는 한 운동 수.
      expect(w.days[1].assigned, isNull);
      expect(w.days[1].totalCount, 0);
      expect(w.days[2].assigned, isNull);
      expect(w.days[2].totalCount, 2);
    });

    test('배정 칸이 숫자가 아니면 모르는 날이다', () {
      final Map<String, dynamic> json = _json();
      (json['days'] as List<Map<String, dynamic>>)[0]['assigned'] = 'three';
      expect(reportSheetWeekFromJson(json).days[0].assigned, isNull);
    });

    test('이번 주인지는 기준일로 가른다', () {
      expect(
        reportSheetWeekFromJson(
          _json(),
          today: DateTime(2026, 9, 17),
        ).isCurrentWeek,
        isTrue,
      );
      expect(
        reportSheetWeekFromJson(
          _json(),
          today: DateTime(2026, 9, 21),
        ).isCurrentWeek,
        isFalse,
      );
    });

    test('다른 응답에서 온 답을 함께 싣는다', () {
      const ReportSheetAnswersData a = ReportSheetAnswersData(
        conditionWire: 'good',
        intensityWire: 'right',
      );
      expect(reportSheetWeekFromJson(_json(), answers: a).answers, same(a));
    });

    test('깨진 값은 빈 값으로 읽는다', () {
      final ReportSheetWeekData w = reportSheetWeekFromJson(<String, dynamic>{
        'week_start': 'not-a-date',
        'calories_week': <Object?>['x', 1800, null],
        'days': <Object?>['x'],
      }, today: DateTime(2026, 9, 17));
      expect(w.memberName, '');
      expect(w.weekStart, DateTime(2026, 9, 14));
      expect(w.caloriesWeek, <int>[1800]);
      expect(w.days, isEmpty);
      expect(w.sessionsBooked, 0);
      expect(w.completionAvg, isNull);
    });

    test('월요일이 아닌 날짜가 와도 그 주의 월요일로 맞춘다', () {
      final ReportSheetWeekData w = reportSheetWeekFromJson(<String, dynamic>{
        'week_start': '2026-09-17',
      });
      expect(w.weekStart, DateTime(2026, 9, 14));
    });
  });

  group('reportSheetAnswersFromJson', () {
    test('내지 않은 주는 답이 아니다', () {
      expect(
        reportSheetAnswersFromJson(<String, dynamic>{
          'submitted': false,
          'condition': '',
          'intensity': '',
        }),
        isNull,
      );
    });

    test('낸 답을 읽는다', () {
      final ReportSheetAnswersData a =
          reportSheetAnswersFromJson(<String, dynamic>{
            'submitted': true,
            'condition': 'ok',
            'intensity': 'too_hard',
            'pain_area': '오른쪽 어깨',
            'pain_on': '2026-09-17',
            'note': '벤치 할 때 어깨가 걸려요',
          })!;
      expect(a.conditionWire, 'ok');
      expect(a.intensityWire, 'too_hard');
      expect(a.painOn, DateTime(2026, 9, 17));
      expect(a.note, '벤치 할 때 어깨가 걸려요');
    });
  });
}
