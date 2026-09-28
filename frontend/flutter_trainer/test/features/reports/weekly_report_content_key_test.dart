import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

import '../../helpers/client_factory.dart';

/// 기본값에서 한 곳만 바꿔 가며 만든다 — 열쇠가 그 한 곳을 보는지 가린다.
WeeklyReport _report({
  String name = '김회원',
  DateTime? weekStart,
  int sessionsDone = 1,
  int? completionAvg = 72,
  List<int> caloriesWeek = const <int>[1800, 0, 1900, 0, 0, 0, 0],
  List<double> proteinWeek = const <double>[80, 0, 90, 0, 0, 0, 0],
  int? calorieTarget = 2000,
  List<ReportDay> days = const <ReportDay>[
    ReportDay(completion: 80, exercises: <String>['스쿼트', '런지']),
  ],
  List<int> mealCounts = const <int>[3, 0, 2, 0, 0, 0, 0],
  MemberWeeklyFeedback? memberFeedback,
}) => WeeklyReport(
  client: makeClient(id: 'key-client', name: name),
  weekStart: weekStart ?? DateTime(2026, 8, 10),
  sessionsBooked: 2,
  sessionsDone: sessionsDone,
  completionAvg: completionAvg,
  sodiumOverDays: 1,
  sodiumAvg: 1900,
  isCurrentWeek: false,
  caloriesWeek: caloriesWeek,
  proteinWeek: proteinWeek,
  calorieTarget: calorieTarget,
  days: days,
  mealCounts: mealCounts,
  memberFeedback: memberFeedback,
);

MemberWeeklyFeedback _feedback({String note = '무릎이 조금 불편했어요'}) =>
    MemberWeeklyFeedback(
      weekStart: DateTime(2026, 8, 10),
      condition: WeekCondition.values.first,
      intensity: WeekIntensity.values.first,
      note: note,
    );

void main() {
  group('WeeklyReport.contentKey (#2484)', () {
    test('내용이 같으면 다른 객체라도 열쇠가 같다', () {
      final WeeklyReport a = _report(memberFeedback: _feedback());
      final WeeklyReport b = _report(memberFeedback: _feedback());

      expect(identical(a, b), isFalse);
      expect(a.contentKey, b.contentKey);
    });

    test('회원 이름·주가 다르면 열쇠가 다르다', () {
      final String base = _report().contentKey;

      expect(_report(name: '박회원').contentKey, isNot(base));
      expect(_report(weekStart: DateTime(2026, 8, 17)).contentKey, isNot(base));
    });

    test('수치가 하나라도 바뀌면 열쇠가 다르다', () {
      final String base = _report().contentKey;

      expect(_report(sessionsDone: 2).contentKey, isNot(base));
      expect(_report(completionAvg: 73).contentKey, isNot(base));
      expect(_report(completionAvg: null).contentKey, isNot(base));
      expect(
        _report(
          caloriesWeek: const <int>[1800, 0, 1900, 0, 0, 0, 1],
        ).contentKey,
        isNot(base),
      );
      expect(
        _report(
          proteinWeek: const <double>[80, 0, 90.5, 0, 0, 0, 0],
        ).contentKey,
        isNot(base),
      );
      expect(_report(calorieTarget: 1800).contentKey, isNot(base));
      expect(
        _report(mealCounts: const <int>[3, 1, 2, 0, 0, 0, 0]).contentKey,
        isNot(base),
      );
    });

    test('요일별 운동이 바뀌면 열쇠가 다르다', () {
      final String base = _report().contentKey;

      expect(
        _report(
          days: const <ReportDay>[
            ReportDay(completion: 80, exercises: <String>['스쿼트']),
          ],
        ).contentKey,
        isNot(base),
      );
      expect(
        _report(
          days: const <ReportDay>[
            ReportDay(
              completion: 80,
              exercises: <String>['스쿼트', '런지'],
              assigned: 3,
            ),
          ],
        ).contentKey,
        isNot(base),
      );
    });

    test('운동 이름을 잇는 방식으로 서로 다른 목록이 같아지지 않는다', () {
      final String split = _report(
        days: const <ReportDay>[
          ReportDay(completion: 80, exercises: <String>['a', 'b']),
        ],
      ).contentKey;
      final String joined = _report(
        days: const <ReportDay>[
          ReportDay(completion: 80, exercises: <String>['a,b']),
        ],
      ).contentKey;

      expect(split, isNot(joined));
    });

    test('회원의 답이 생기거나 바뀌면 열쇠가 다르다', () {
      final String none = _report().contentKey;
      final String answered = _report(memberFeedback: _feedback()).contentKey;
      final String edited = _report(
        memberFeedback: _feedback(note: '괜찮았어요'),
      ).contentKey;

      expect(answered, isNot(none));
      expect(edited, isNot(answered));
    });
  });
}
