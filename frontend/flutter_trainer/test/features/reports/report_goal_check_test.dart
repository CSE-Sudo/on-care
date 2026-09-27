/// ③ 지난 주 목표 판정 — 목표 문장을 그 주 수치로 회수한다. (#2287)
///
/// 이 파일이 지키는 것:
///  * 목표가 무엇에 관한 것인지 한·영 어느 언어로 적혀 있어도 가른다.
///  * 영양소 → 운동 → 기록 순서로 가른다(`저녁 단백질 기록` 은 단백질 목표).
///  * 채울수록 좋은 값·적을수록 좋은 값·목표 근처가 좋은 값을 각자 맞는
///    방향으로 판정하고, 경계값에서 한쪽으로만 떨어진다.
///  * 판정할 기록이 없거나 수치로 볼 수 없는 목표는 `직접 확인` 이다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/domain/report_goal_check.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

import '../../helpers/client_factory.dart';

final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

List<double> _days(double v) => List<double>.filled(7, v);

WeeklyReport _report({
  List<String> goals = const <String>[],
  bool isCurrentWeek = false,
  int? completionAvg = 80,
  int? sodiumAvg = 1800,
  int? sodiumTarget = 2000,
  List<double> sugarWeek = const <double>[],
  double? sugarTarget = 50,
  List<double> carbsWeek = const <double>[],
  double? carbsTarget = 250,
  List<double> proteinWeek = const <double>[],
  double? proteinTarget = 120,
  List<double> fatWeek = const <double>[],
  double? fatTarget = 60,
  List<int> caloriesWeek = const <int>[],
  int? calorieTarget = 2000,
  List<int> mealCounts = const <int>[],
}) => WeeklyReport(
  client: makeClient(name: '김민수'),
  weekStart: DateTime(2026, 9, 14),
  sessionsBooked: 2,
  sessionsDone: 2,
  completionAvg: completionAvg,
  sodiumOverDays: 0,
  sodiumAvg: sodiumAvg,
  sodiumTarget: sodiumTarget,
  isCurrentWeek: isCurrentWeek,
  sugarWeek: sugarWeek,
  sugarTarget: sugarTarget,
  carbsWeek: carbsWeek,
  carbsTarget: carbsTarget,
  proteinWeek: proteinWeek,
  proteinTarget: proteinTarget,
  fatWeek: fatWeek,
  fatTarget: fatTarget,
  caloriesWeek: caloriesWeek,
  calorieTarget: calorieTarget,
  mealCounts: mealCounts,
  weekGoals: goals,
);

GoalCheck _one(WeeklyReport report, {AppLocalizations? l}) =>
    checkWeekGoals(l ?? ko, report).single;

void main() {
  group('목록', () {
    test('목표가 없으면 빈 목록', () {
      expect(checkWeekGoals(ko, _report()), isEmpty);
    });

    test('고른 순서대로 한 줄씩 판정한다', () {
      final List<GoalCheck> checks = checkWeekGoals(
        ko,
        _report(
          goals: <String>['저녁 단백질 챙기기', '주 3회 운동', '물 2L'],
          proteinWeek: _days(120),
        ),
      );
      expect(checks.map((GoalCheck c) => c.goal), <String>[
        '저녁 단백질 챙기기',
        '주 3회 운동',
        '물 2L',
      ]);
    });

    test('달성한 목표 수를 센다', () {
      final List<GoalCheck> checks = checkWeekGoals(
        ko,
        _report(
          goals: <String>['단백질', '운동', '물 2L'],
          proteinWeek: _days(120),
          completionAvg: 30,
        ),
      );
      expect(metGoalCount(checks), 1);
    });
  });

  group('주제 가르기', () {
    test('수치로 볼 수 없는 목표는 직접 확인이고 근거가 없다', () {
      final GoalCheck c = _one(_report(goals: <String>['물 2L 마시기']));
      expect(c.outcome, GoalOutcome.unknown);
      expect(c.evidence, isNull);
    });

    test('한국어로 고른 목표를 영어 화면에서도 판정한다', () {
      final GoalCheck c = _one(
        _report(goals: <String>['저녁 단백질 챙기기'], proteinWeek: _days(30)),
        l: en,
      );
      expect(c.outcome, GoalOutcome.missed);
      expect(c.evidence, '30 / 120g');
    });

    test('영어로 고른 목표를 한국어 화면에서도 판정한다', () {
      final GoalCheck c = _one(
        _report(goals: <String>['Protein at dinner'], proteinWeek: _days(120)),
      );
      expect(c.outcome, GoalOutcome.met);
    });

    test('대소문자를 가리지 않는다', () {
      expect(
        _one(
          _report(goals: <String>['PROTEIN first'], proteinWeek: _days(120)),
        ).outcome,
        GoalOutcome.met,
      );
    });

    test('영양소를 기록보다 먼저 본다', () {
      final GoalCheck c = _one(
        _report(goals: <String>['저녁 단백질 기록하기'], proteinWeek: _days(120)),
      );
      expect(c.evidence, '120 / 120g');
    });

    test('운동을 기록보다 먼저 본다', () {
      final GoalCheck c = _one(
        _report(goals: <String>['운동 기록 3회'], completionAvg: 70),
      );
      expect(c.evidence, '70 / 70%');
    });

    test('데모 목표들이 각자 맞는 주제로 간다', () {
      final List<GoalCheck> checks = checkWeekGoals(
        ko,
        _report(
          goals: <String>['주 2회 하체 추가', '주 5일 이상 기록', '스쿼트 60kg 3세트'],
          completionAvg: 90,
          caloriesWeek: <int>[1800, 1800, 1800, 1800, 1800, 0, 0],
        ),
      );
      expect(checks[0].evidence, '90 / 70%');
      expect(checks[1].evidence, '5일 기록');
      expect(checks[2].evidence, '90 / 70%');
    });

    test('요약이 내놓은 제안 문장도 주제를 찾는다', () {
      for (final (String goal, String evidence) in <(String, String)>[
        (ko.summaryCompletionLow('40', '70'), '40 / 70%'),
        (ko.summarySodium('2,400', '목표', '2,000', '3'), '1800 / 2000mg'),
        (en.summarySkipped('Squat'), '40 / 70%'),
        (en.reportsActionUnlogged(3), 'Logged 4 days'),
      ]) {
        final GoalCheck c = _one(
          _report(
            goals: <String>[goal],
            completionAvg: 40,
            caloriesWeek: <int>[1800, 1800, 1800, 1800, 0, 0, 0],
          ),
          l: en,
        );
        expect(c.evidence, evidence, reason: goal);
      }
    });
  });

  group('채울수록 좋은 값 — 탄단지', () {
    GoalOutcome protein(double grams) => _one(
      _report(goals: <String>['단백질 챙기기'], proteinWeek: _days(grams)),
    ).outcome;

    test('목표의 80% 이상이면 달성 — 경계 포함', () {
      expect(protein(96), GoalOutcome.met);
      expect(protein(150), GoalOutcome.met);
    });

    test('50% 이상 80% 미만이면 절반', () {
      expect(protein(95), GoalOutcome.partial);
      expect(protein(60), GoalOutcome.partial);
    });

    test('50% 미만이면 미달', () {
      expect(protein(59), GoalOutcome.missed);
    });

    test('탄수화물·지방도 같은 규칙이다', () {
      expect(
        _one(
          _report(goals: <String>['탄수화물 늘리기'], carbsWeek: _days(100)),
        ).outcome,
        GoalOutcome.missed,
      );
      expect(
        _one(
          _report(goals: <String>['Fat intake'], fatWeek: _days(55)),
        ).outcome,
        GoalOutcome.met,
      );
    });

    test('안 적은 날은 평균에 넣지 않는다', () {
      final GoalCheck c = _one(
        _report(
          goals: <String>['단백질'],
          proteinWeek: <double>[120, 120, 0, 0, 0, 0, 0],
        ),
      );
      expect(c.outcome, GoalOutcome.met);
      expect(c.evidence, '120 / 120g');
    });

    test('회원 목표가 없으면 기본값으로 판정한다', () {
      final GoalCheck c = _one(
        _report(
          goals: <String>['단백질'],
          proteinWeek: _days(100),
          proteinTarget: null,
        ),
      );
      expect(c.outcome, GoalOutcome.met);
      expect(c.evidence, '100 / 100g');
    });

    test('기록이 하나도 없으면 직접 확인', () {
      final GoalCheck c = _one(_report(goals: <String>['단백질']));
      expect(c.outcome, GoalOutcome.unknown);
      expect(c.evidence, isNull);
    });
  });

  group('적을수록 좋은 값 — 나트륨·당류', () {
    GoalOutcome sodium(int avg) =>
        _one(_report(goals: <String>['나트륨 줄이기'], sodiumAvg: avg)).outcome;

    test('목표 이하면 달성 — 경계 포함', () {
      expect(sodium(2000), GoalOutcome.met);
      expect(sodium(1200), GoalOutcome.met);
    });

    test('120% 까지는 절반', () {
      expect(sodium(2001), GoalOutcome.partial);
      expect(sodium(2400), GoalOutcome.partial);
    });

    test('그 위는 미달', () {
      expect(sodium(2401), GoalOutcome.missed);
    });

    test('근거는 평균 / 목표 mg', () {
      expect(
        _one(_report(goals: <String>['Less sodium'], sodiumAvg: 2600)).evidence,
        '2600 / 2000mg',
      );
    });

    test('당류는 g 로 판정한다', () {
      final GoalCheck c = _one(
        _report(goals: <String>['당류 줄이기'], sugarWeek: _days(70)),
      );
      expect(c.outcome, GoalOutcome.missed);
      expect(c.evidence, '70 / 50g');
    });

    test('평균이 없으면 직접 확인', () {
      expect(
        _one(_report(goals: <String>['나트륨'], sodiumAvg: null)).outcome,
        GoalOutcome.unknown,
      );
    });
  });

  group('목표 근처가 좋은 값 — 칼로리', () {
    GoalOutcome calories(int kcal) => _one(
      _report(
        goals: <String>['칼로리 맞추기'],
        caloriesWeek: List<int>.filled(7, kcal),
      ),
    ).outcome;

    test('±15% 안이면 달성', () {
      expect(calories(2000), GoalOutcome.met);
      expect(calories(1700), GoalOutcome.met);
      expect(calories(2300), GoalOutcome.met);
    });

    test('±30% 안이면 절반', () {
      expect(calories(1500), GoalOutcome.partial);
      expect(calories(2500), GoalOutcome.partial);
    });

    test('그 밖은 넘쳐도 모자라도 미달', () {
      expect(calories(1300), GoalOutcome.missed);
      expect(calories(2700), GoalOutcome.missed);
    });

    test('근거는 kcal', () {
      expect(
        _one(
          _report(
            goals: <String>['Calorie target'],
            caloriesWeek: List<int>.filled(7, 1800),
          ),
        ).evidence,
        '1800 / 2000kcal',
      );
    });
  });

  group('기록 목표', () {
    GoalCheck logged(List<int> meals, {bool current = false}) => _one(
      _report(
        goals: <String>['식단 기록 매일'],
        mealCounts: meals,
        isCurrentWeek: current,
      ),
    );

    test('다섯 날 이상이면 달성', () {
      expect(logged(<int>[3, 2, 3, 1, 2, 0, 0]).outcome, GoalOutcome.met);
    });

    test('세 날 이상이면 절반', () {
      expect(logged(<int>[3, 2, 3, 0, 0, 0, 0]).outcome, GoalOutcome.partial);
    });

    test('그 아래는 미달', () {
      expect(logged(<int>[3, 2, 0, 0, 0, 0, 0]).outcome, GoalOutcome.missed);
    });

    test('근거는 기록한 날 수 — 한·영', () {
      expect(logged(<int>[1, 1, 1, 1, 0, 0, 0]).evidence, '4일 기록');
      expect(
        _one(
          _report(
            goals: <String>['Log every meal'],
            mealCounts: <int>[1, 1, 1, 1, 0, 0, 0],
          ),
          l: en,
        ).evidence,
        'Logged 4 days',
      );
    });

    test('끼니 수가 없으면(실서버) 칼로리가 있는 날로 센다', () {
      final GoalCheck c = _one(
        _report(
          goals: <String>['기록 습관'],
          caloriesWeek: <int>[1800, 1800, 1800, 1800, 1800, 0, 0],
        ),
      );
      expect(c.outcome, GoalOutcome.met);
      expect(c.evidence, '5일 기록');
    });

    test('기록할 계열이 없으면 직접 확인', () {
      expect(logged(const <int>[]).outcome, GoalOutcome.unknown);
    });
  });

  group('운동 목표', () {
    GoalOutcome workout(int? pct) =>
        _one(_report(goals: <String>['운동 이행률'], completionAvg: pct)).outcome;

    test('이행률 기준(70%)에 닿으면 달성', () {
      expect(workout(70), GoalOutcome.met);
      expect(workout(100), GoalOutcome.met);
    });

    test('기준의 절반 이상이면 절반', () {
      expect(workout(69), GoalOutcome.partial);
      expect(workout(35), GoalOutcome.partial);
    });

    test('그 아래는 미달', () {
      expect(workout(34), GoalOutcome.missed);
      expect(workout(0), GoalOutcome.missed);
    });

    test('이행률이 없으면 직접 확인', () {
      expect(workout(null), GoalOutcome.unknown);
    });
  });
}
