import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

import '../../helpers/client_factory.dart';

/// 문구 기대값은 로케일을 명시해 읽는다.
final AppLocalizationsKo _ko = AppLocalizationsKo();

WeeklyReport _report({
  required int? completionAvg,
  required int? sodiumAvg,
  required int sodiumOverDays,
  List<int> weekCompletion = const <int>[],
  List<double> sugarWeek = const <double>[],
  List<int> caloriesWeek = const <int>[],
  List<double> proteinWeek = const <double>[],
  int? calorieTarget,
  double? proteinTarget,
  List<ReportDay> days = const <ReportDay>[],
}) => WeeklyReport(
  client: makeClient(name: '김민수'),
  weekStart: DateTime(2026, 8, 17),
  sessionsBooked: 0,
  sessionsDone: 0,
  completionAvg: completionAvg,
  sodiumOverDays: sodiumOverDays,
  sodiumAvg: sodiumAvg,
  isCurrentWeek: false,
  weekCompletion: weekCompletion,
  sugarWeek: sugarWeek,
  caloriesWeek: caloriesWeek,
  proteinWeek: proteinWeek,
  calorieTarget: calorieTarget,
  proteinTarget: proteinTarget,
  days: days,
);

void main() {
  group('ruleReportSummary', () {
    test('목표를 사흘 넘긴 주를 `목표 범위 안` 이라고 하지 않는다 (#1177)', () {
      // 평균만 보던 때에는 1,916mg(목표 안) 이면 초과 3일이 있어도 잘 지킨
      // 주로 넘어갔다. 바로 아래 근거 줄이 `초과 3일` 을 적고 있어 카드 하나가
      // 서로 다른 말을 했다.
      final summary = ruleReportSummary(
        _ko,
        _report(completionAvg: 81, sodiumAvg: 1916, sodiumOverDays: 3),
        makeClient(name: '김민수'),
      );

      expect(summary.headline, isNot(contains('목표 범위 안')));
      expect(summary.headline, contains('나트륨 목표 초과 3일'));
      // 잘한 쪽도 함께 말한다 — 챙길 것만 남으면 보낼 만한 글이 못 된다.
      expect(summary.headline, contains('운동 이행률 81%'));
    });

    test('평균도 초과일도 목표 안이면 지금 강도를 유지하라고 말한다', () {
      final summary = ruleReportSummary(
        _ko,
        _report(completionAvg: 90, sodiumAvg: 1500, sodiumOverDays: 0),
        makeClient(name: '김민수'),
      );

      expect(summary.headline, contains('목표 범위 안'));
    });

    test('근거의 수치는 화면과 같은 서식으로 적는다 (#1177)', () {
      final summary = ruleReportSummary(
        _ko,
        _report(completionAvg: 81, sodiumAvg: 1916, sodiumOverDays: 3),
        makeClient(name: '김민수'),
      );

      // 어느 기준으로 판정했는지도 문장에 남는다 — 회원마다 목표가 다르다(#1430).
      expect(summary.points, contains('나트륨 평균 1,916mg · 기본 목표 2,000mg 초과 3일'));
    });
  });

  group('summaryEvidence', () {
    test('PT 세션 수는 요약이 다시 말하지 않는다 (#1177)', () {
      // 바로 옆 `주간 운동 이행률` 카드 제목 줄이 같은 값을 이미 적고 있어,
      // 근거 세 줄 중 하나를 되풀이에 쓰고 있었다.
      final lines = summaryEvidence(
        _ko,
        _report(completionAvg: 81, sodiumAvg: 1500, sodiumOverDays: 0),
      );

      expect(lines.any((line) => line.contains('PT 세션')), isFalse);
      expect(lines, contains('운동 이행률 평균 81%'));
    });
  });

  group('summaryCoachingActions', () {
    test('수치에서 다음 주에 할 일을 뽑고 둘까지만 적는다 (#1177)', () {
      final actions = summaryCoachingActions(
        _ko,
        _report(
          completionAvg: 55,
          sodiumAvg: 2400,
          sodiumOverDays: 4,
          sugarWeek: const <double>[60, 55, 20, 20, 20, 20, 20],
          days: const <ReportDay>[
            ReportDay(completion: 55, exercises: <String>['하체 스트레칭 10분✗']),
          ],
        ),
      );

      // 카드가 스스로 스크롤하기 시작하면 채우려던 자리가 오히려 잘려 보인다.
      // 자를 때는 위험도 순으로 남긴다 — 입력 순서로 자르면 이행률처럼 무거운
      // 항목이 조용히 빠진다(#1430).
      expect(actions.length, 2);
      expect(actions.first, contains('프로그램 난이도'));
      expect(actions.last, contains('국물'));
    });

    test('잘 지킨 주에는 다음 단계를 권한다', () {
      final actions = summaryCoachingActions(
        _ko,
        _report(
          completionAvg: 95,
          sodiumAvg: 1400,
          sodiumOverDays: 0,
          weekCompletion: const <int>[95, 95, 95, 95, 95, 95, 95],
        ),
      );

      expect(actions, <String>[_ko.reportsActionHighCompletion]);
    });
  });

  group('summaryWatchpoints (#1430)', () {
    test('당류만 넘긴 주도 주의 주간으로 판정한다', () {
      final report = _report(
        completionAvg: 95,
        sodiumAvg: 1400,
        sodiumOverDays: 0,
        sugarWeek: const <double>[72, 80, 61, 90, 0, 0, 0],
      );

      final kinds = summaryWatchpoints(_ko, report).map((w) => w.kind).toList();
      final summary = ruleReportSummary(_ko, report, makeClient(name: '김민수'));

      expect(kinds, contains('sugar'));
      expect(summary.headline, isNot(contains('목표 범위 안')));
      expect(summary.headline, contains('당류'));
      expect(summaryEvidence(_ko, report).any((l) => l.contains('당류')), isTrue);
    });

    test('칼로리는 평균이 아니라 목표와 견준 결과로 말한다', () {
      final report = _report(
        completionAvg: 95,
        sodiumAvg: 1400,
        sodiumOverDays: 0,
        calorieTarget: 2600,
        caloriesWeek: const <int>[1700, 1750, 1680, 1720, 0, 0, 0],
      );

      final watch = summaryWatchpoints(_ko, report);

      expect(watch.any((w) => w.kind == 'calories'), isTrue);
      expect(
        summaryEvidence(
          _ko,
          report,
        ).any((l) => l.contains('개인 목표 2,600kcal') && l.contains('부족')),
        isTrue,
      );
    });

    test('탄·단·지는 개인 목표가 있을 때만 본다', () {
      const series = <double>[40, 45, 38, 0, 0, 0, 0];
      final without = _report(
        completionAvg: 95,
        sodiumAvg: 1400,
        sodiumOverDays: 0,
        proteinWeek: series,
      );
      final withTarget = _report(
        completionAvg: 95,
        sodiumAvg: 1400,
        sodiumOverDays: 0,
        proteinWeek: series,
        proteinTarget: 120,
      );

      expect(
        summaryWatchpoints(_ko, without).any((w) => w.kind == 'macro'),
        isFalse,
      );
      final macro = summaryWatchpoints(
        _ko,
        withTarget,
      ).firstWhere((w) => w.kind == 'macro');
      expect(macro.text, contains('단백질'));
      expect(macro.text, contains('부족'));
    });

    test('기록 없는 날과 아직 오지 않은 날은 초과·부족으로 세지 않는다', () {
      final report = _report(
        completionAvg: 95,
        sodiumAvg: 1400,
        sodiumOverDays: 0,
        // 화요일까지만 기록한 주 — 나머지 0 을 함께 나누면 평균이 반토막 난다.
        caloriesWeek: const <int>[2000, 2050, 0, 0, 0, 0, 0],
        sugarWeek: const <double>[20, 22, 0, 0, 0, 0, 0],
      );

      final kinds = summaryWatchpoints(_ko, report).map((w) => w.kind).toSet();

      expect(kinds.contains('calories'), isFalse);
      expect(kinds.contains('sugar'), isFalse);
    });

    test('주의사항이 여럿이면 잘린 수를 카드가 말한다', () {
      final report = _report(
        completionAvg: 40,
        sodiumAvg: 2600,
        sodiumOverDays: 5,
        sugarWeek: const <double>[80, 90, 75, 70, 60, 0, 0],
        caloriesWeek: const <int>[3000, 3100, 2900, 3050, 0, 0, 0],
      );

      final summary = ruleReportSummary(_ko, report, makeClient(name: '김민수'));

      expect(
        summaryWatchpoints(_ko, report).length,
        greaterThan(summaryMaxPoints),
      );
      expect(summary.points.length, summaryMaxPoints);
      expect(summary.points.last, startsWith('외 '));
      // 가장 위험한 항목이 먼저 남는다.
      expect(summary.points.first, contains('운동 이행률'));
      expect(summaryHiddenWatchCount(_ko, report), greaterThan(0));
    });
  });

  group('hasFinalConsonant', () {
    test('한글 받침과 숫자·단위의 소리를 함께 본다 (#1177)', () {
      expect(hasFinalConsonant('3일'), isTrue);
      expect(hasFinalConsonant('하체'), isFalse);
      // 81% 는 `퍼센트`, 1,916mg 은 `밀리그램` 으로 읽혀 받침이 없다.
      expect(hasFinalConsonant('81%'), isFalse);
      expect(hasFinalConsonant('1,916mg'), isFalse);
    });
  });

  group('영어 요약 (#2232)', () {
    final AppLocalizationsEn en = AppLocalizationsEn();
    final RegExp hangul = RegExp(r'[가-힣]');
    // 주의사항이 골고루 걸리는 주 — 이행률·나트륨·당류·칼로리·단백질.
    final report = _report(
      completionAvg: 55,
      sodiumAvg: 2600,
      sodiumOverDays: 4,
      sugarWeek: const <double>[72, 80, 61, 90, 0, 0, 0],
      caloriesWeek: const <int>[2900, 3000, 2800, 0, 0, 0, 0],
      proteinWeek: const <double>[40, 42, 38, 0, 0, 0, 0],
      proteinTarget: 120,
    );

    test('머리 문장과 근거 줄에 한글이 남지 않는다', () {
      final summary = ruleReportSummary(en, report, makeClient(name: 'Min'));

      expect(summary.headline, isNot(matches(hangul)));
      for (final String point in summary.points) {
        expect(point, isNot(matches(hangul)), reason: point);
      }
    });

    test('주의사항·다음 주 할 일에도 한글이 남지 않는다', () {
      for (final w in summaryWatchpoints(en, report)) {
        expect(w.text, isNot(matches(hangul)), reason: w.text);
        expect(w.topic, isNot(matches(hangul)), reason: w.topic);
      }
      for (final String a in summaryCoachingActionsAll(en, report)) {
        expect(a, isNot(matches(hangul)), reason: a);
      }
    });

    test('영어에는 한국어 조사를 붙이지 않는다', () {
      final summary = ruleReportSummary(
        en,
        _report(completionAvg: 95, sodiumAvg: 2600, sodiumOverDays: 4),
        makeClient(name: 'Min'),
      );

      expect(summary.headline, contains('workout completion at 95% on track'));
    });

    test('기록이 없는 주도 영어로 말한다', () {
      final summary = ruleReportSummary(
        en,
        _report(completionAvg: null, sodiumAvg: null, sodiumOverDays: 0),
        makeClient(name: 'Min'),
      );

      expect(summary.headline, en.summaryHeadlineNoData('Min'));
    });
  });
}
