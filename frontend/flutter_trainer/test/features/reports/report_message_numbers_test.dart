import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

import '../../helpers/client_factory.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

/// 지난 주(2026-08-03 월요일) 리포트. 지난 주라 아직 오지 않은 날이 없어,
/// 문장이 오늘 날짜에 따라 달라지지 않는다.
WeeklyReport _week({
  int booked = 2,
  int done = 2,
  int? completion = 85,
  List<int> calories = const <int>[1900, 1950, 2000, 1980, 1900, 1990, 1950],
  List<int> sodium = const <int>[1500, 1500, 1500, 1500, 1500, 1500, 1500],
  List<double> sugar = const <double>[30, 30, 30, 30, 30, 30, 30],
  List<int> meals = const <int>[3, 3, 3, 3, 3, 3, 3],
  List<ReportDay> days = const <ReportDay>[],
  int? calorieTarget,
  MemberWeeklyFeedback? feedback,
}) {
  final over = sodium.where((mg) => mg > 2000).length;
  final logged = sodium.where((mg) => mg > 0).toList();
  return WeeklyReport(
    client: makeClient(name: '강서연'),
    weekStart: DateTime(2026, 8, 3),
    sessionsBooked: booked,
    sessionsDone: done,
    completionAvg: completion,
    sodiumOverDays: logged.isEmpty ? null : over,
    sodiumAvg: logged.isEmpty
        ? null
        : (logged.reduce((a, b) => a + b) / logged.length).round(),
    isCurrentWeek: false,
    weekCompletion: List<int>.filled(7, completion ?? 0),
    sodiumWeek: sodium,
    caloriesWeek: calories,
    sugarWeek: sugar,
    mealCounts: meals,
    days: days,
    calorieTarget: calorieTarget,
    memberFeedback: feedback,
  );
}

/// 스크린숏에 나온 주 — 매일 2,368~3,187kcal, PT 0회, 주말 운동 0/3.
WeeklyReport _overWeek() => _week(
  booked: 0,
  done: 0,
  completion: 71,
  calories: const <int>[2368, 2540, 2711, 2880, 3012, 3187, 2402],
  days: const <ReportDay>[
    ReportDay(completion: 100, exercises: <String>['스쿼트 3세트', '플랭크 1분']),
    ReportDay(completion: 100, exercises: <String>['스쿼트 3세트', '플랭크 1분']),
    ReportDay(completion: 100, exercises: <String>['스쿼트 3세트', '플랭크 1분']),
    ReportDay(completion: 100, exercises: <String>['스쿼트 3세트', '플랭크 1분']),
    ReportDay(completion: 100, exercises: <String>['스쿼트 3세트', '플랭크 1분']),
    ReportDay(
      completion: 0,
      exercises: <String>['스쿼트 3세트✗', '플랭크 1분✗', '런지 10회✗'],
    ),
    ReportDay(completion: 0, exercises: <String>['걷기 30분✗']),
  ],
);

void main() {
  group('isGoodWeek — 칼로리·당류도 본다 (#2422)', () {
    test('이행률·나트륨이 좋아도 칼로리가 매일 넘은 주는 좋은 주가 아니다', () {
      final report = _week(
        calories: const <int>[2368, 2540, 2711, 2880, 3012, 3187, 2402],
      );
      expect(report.caloriesOffTarget, isTrue);
      expect(report.isGoodWeek, isFalse);
    });

    test('평균은 목표 근처여도 절반 넘는 날이 넘었으면 벗어난 주다', () {
      final report = _week(
        calories: const <int>[2100, 2100, 2100, 2100, 1500, 1500, 1500],
      );
      expect(report.calorieGap!.abs(), lessThan(calorieTolerance));
      expect(report.calorieOverDays, 4);
      expect(report.caloriesOffTarget, isTrue);
      expect(report.isGoodWeek, isFalse);
    });

    test('칼로리가 목표보다 한참 적은 주도 좋은 주가 아니다', () {
      final report = _week(
        calories: const <int>[1200, 1300, 1250, 1200, 1300, 1250, 1200],
      );
      expect(report.calorieGap, lessThan(-calorieTolerance));
      expect(report.isGoodWeek, isFalse);
    });

    test('당류가 기준을 넘은 주는 좋은 주가 아니다', () {
      final report = _week(sugar: const <double>[70, 70, 70, 70, 20, 20, 20]);
      expect(report.sugarOverDays, 4);
      expect(report.sugarOverLimit, isTrue);
      expect(report.isGoodWeek, isFalse);
    });

    test('모든 지표가 목표 안이면 좋은 주다', () {
      expect(_week().isGoodWeek, isTrue);
    });

    test('기록이 없는 지표는 칭찬을 막지 않는다', () {
      final report = _week(
        calories: const <int>[0, 0, 0, 0, 0, 0, 0],
        sugar: const <double>[],
      );
      expect(report.calorieMean, isNull);
      expect(report.caloriesOffTarget, isFalse);
      expect(report.sugarOverLimit, isFalse);
      expect(report.isGoodWeek, isTrue);
    });

    test('회원이 적어 둔 칼로리 목표가 공통 기본값보다 먼저다', () {
      final report = _week(
        calories: const <int>[2400, 2400, 2400, 2400, 2400, 2400, 2400],
        calorieTarget: 2500,
      );
      expect(report.calorieGoal, 2500);
      expect(report.calorieOverDays, 0);
      expect(report.caloriesOffTarget, isFalse);
    });
  });

  group('reportMessage — 칼로리를 넘긴 주 (#2422)', () {
    late String message;
    setUp(() => message = reportMessage(_ko, _overWeek()));

    test('칭찬으로 끝나지 않고 다음 주 할 일로 이어진다', () {
      expect(message, isNot(contains('정말 잘하셨어요')));
      expect(message, isNot(contains('지금 루틴은 그대로')));
      expect(message, contains('위 내용만 하나씩 같이 챙겨 가면'));
    });

    test('칼로리를 목표와 견주고 넘긴 날 수를 적는다', () {
      expect(
        message,
        contains('칼로리는 하루 평균 2,729kcal로 목표(2,000kcal)보다 36% 많았고'),
      );
      expect(message, contains('목표를 넘긴 날이 7일이었어요'));
      expect(message, contains('저녁 밥 양을 3분의 2로 줄이고'));
    });

    test('PT 세션이 없었다는 것과 다음 주 일정을 말한다', () {
      expect(message, contains('이 주에는 진행한 PT 세션이 없었어요'));
      expect(message, contains('다음 주 PT 일정도 이번에 같이 잡아 둘게요'));
    });

    test('배정된 개인 운동 개수와 건너뛴 운동을 적는다', () {
      expect(message, contains('배정된 개인 운동 14개 중 10개를 완료하셨어요'));
      expect(message, contains('건너뛰셨더라고요'));
    });

    test('스크린숏 2의 초안보다 짧지 않다 — 다섯 문단 이상', () {
      final paragraphs = message.split('\n\n');
      expect(paragraphs.length, greaterThanOrEqualTo(5));
      expect(paragraphs.first, startsWith('강서연님,'));
    });
  });

  group('reportMessage — 식단 문단', () {
    test('칼로리가 목표 안이면 잘 조절했다고 말한다', () {
      final message = reportMessage(_ko, _week());
      expect(message, contains('목표(2,000kcal)에 맞게 잘 조절해 주셨어요'));
      expect(message, contains('정말 잘하셨어요'));
      expect(message, contains('지금 루틴은 그대로 유지하면서'));
    });

    test('평균은 근처지만 넘긴 날이 있으면 그 날 수를 적는다', () {
      final message = reportMessage(
        _ko,
        _week(calories: const <int>[2100, 2100, 1900, 1900, 1900, 1900, 1900]),
      );
      expect(message, contains('목표(2,000kcal) 근처였지만, 목표를 넘긴 날이 2일'));
    });

    test('칼로리가 한참 적으면 부족하다고 말하고 끼니를 챙기게 한다', () {
      final message = reportMessage(
        _ko,
        _week(calories: const <int>[1200, 1300, 1250, 1200, 1300, 1250, 1200]),
      );
      expect(message, contains('목표(2,000kcal)보다 38% 적었어요'));
      expect(message, contains('끼니를 거르지 말고'));
      expect(message, isNot(contains('정말 잘하셨어요')));
    });

    test('당류는 기준을 넘긴 날 수와 함께 적는다', () {
      final message = reportMessage(
        _ko,
        _week(sugar: const <double>[70, 70, 70, 70, 20, 20, 20]),
      );
      expect(message, contains('당류는 하루 평균 49g이었고, 기준(50g)을 넘긴 날이 4일'));
      expect(message, contains('단 음료와 디저트는 하루 한 번까지만'));
    });

    test('끼니를 적은 날 수를 말하고, 빠진 날이 있으면 기록을 권한다', () {
      final all = reportMessage(_ko, _week());
      expect(all, contains('식단은 7일 모두 빠짐없이 기록해 주셨어요'));

      final some = reportMessage(
        _ko,
        _week(meals: const <int>[3, 2, 0, 3, 0, 1, 0]),
      );
      expect(some, contains('식단은 7일 중 4일 기록해 주셨어요'));
      expect(some, contains('매 끼니 남겨 주시면'));
    });

    test('끼니 수가 비었는데 칼로리가 있으면 기록 일수를 지어내지 않는다', () {
      final message = reportMessage(
        _ko,
        _week(meals: const <int>[0, 0, 0, 0, 0, 0, 0]),
      );
      expect(message, isNot(contains('기록해 주셨어요')));
    });
  });

  group('reportMessage — PT 세션', () {
    test('예약한 세션을 모두 했으면 그렇게 말한다', () {
      expect(reportMessage(_ko, _week()), contains('PT는 예약된 2회를 모두 진행했어요'));
    });

    test('빠진 세션은 몇 회인지 적고 보강을 제안한다', () {
      final message = reportMessage(_ko, _week(booked: 3, done: 1));
      expect(message, contains('PT는 예약된 3회 중 1회 진행했어요'));
      expect(message, contains('보강 일정으로 잡아 드릴게요'));
    });
  });

  group('reportMessage — 회원이 남긴 답', () {
    MemberWeeklyFeedback answer({
      WeekIntensity intensity = WeekIntensity.right,
      String painArea = '',
    }) => MemberWeeklyFeedback(
      weekStart: DateTime(2026, 8, 3),
      condition: WeekCondition.values.first,
      intensity: intensity,
      painArea: painArea,
    );

    test('통증을 적었으면 그 부위를 짚는다', () {
      final message = reportMessage(
        _ko,
        _week(feedback: answer(painArea: '무릎')),
      );
      expect(message, contains('무릎이 아프셨다고 남겨 주셨는데'));
    });

    test('강도가 너무 힘들었다면 낮추고, 쉬웠다면 올린다', () {
      expect(
        reportMessage(
          _ko,
          _week(feedback: answer(intensity: WeekIntensity.tooHard)),
        ),
        contains('다음 주 강도는 한 단계 낮춰 둘게요'),
      );
      expect(
        reportMessage(
          _ko,
          _week(feedback: answer(intensity: WeekIntensity.tooEasy)),
        ),
        contains('강도를 한 단계 올려 볼게요'),
      );
    });

    test('답이 없으면 그 문단을 만들지 않는다', () {
      expect(reportMessage(_ko, _week()), isNot(contains('소감')));
    });
  });

  group('reportMessage — 기록이 없는 주', () {
    test('인사와 기록 없음 안내만 남고 PT 한 줄로 채우지 않는다', () {
      final message = reportMessage(
        _ko,
        _week(
          booked: 0,
          done: 0,
          completion: null,
          calories: const <int>[0, 0, 0, 0, 0, 0, 0],
          sodium: const <int>[0, 0, 0, 0, 0, 0, 0],
          sugar: const <double>[],
          meals: const <int>[0, 0, 0, 0, 0, 0, 0],
        ),
      );
      expect(message.split('\n\n'), hasLength(2));
      expect(message, contains('남은 기록이 없어서'));
      expect(message, isNot(contains('PT')));
    });
  });

  group('reportMessage — 영어', () {
    test('칼로리를 넘긴 주를 영어로도 같은 판정으로 적는다', () {
      final message = reportMessage(_en, _overWeek());
      expect(message, contains('36% above your 2,000kcal target'));
      expect(message, contains('There were no PT sessions this week.'));
      expect(message, isNot(contains('Great work')));
      expect(message, isNot(contains('은 ')));
    });
  });
}
