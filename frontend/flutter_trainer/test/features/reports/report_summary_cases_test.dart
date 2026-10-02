import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart'
    show calorieTolerance, kReportGoodCompletionThreshold;
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart'
    show weeklyReportFromJson;
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/shared_rule_vectors.dart';

/// 데모 리포트 요약의 주의사항 판정이 서버와 같은가(#2906).
///
/// 원본은 서버 스크립트(`backend/scripts/gen_report_summary_cases.py`)가 만든
/// `shared/oncare_rules/vectors/report_summary_cases.json` 이고, 서버 pytest
/// (`tests/test_report_summary_cases.py`)도 같은 파일을 읽는다. 사례의 리포트는
/// 서버 응답(`WeeklyReportOut`) 모양이라 실서버 경로와 같은 디코더로 읽는다.
void main() {
  final Map<String, Object?> file = loadSharedRuleVectors(
    'report_summary_cases',
  );
  final Map<String, Object?> thresholds =
      file['thresholds']! as Map<String, Object?>;

  test('기준값이 서버와 같다', () {
    expect(lowCompletionThreshold, thresholds['low_completion']);
    expect(goodCompletionThreshold, thresholds['good_completion']);
    expect(summaryCalorieTolerance, thresholds['calorie_tolerance']);
    expect(summarySodiumOverDays, thresholds['sodium_over_days']);
    expect(summarySugarOverDays, thresholds['sugar_over_days']);
    expect(summaryMacroTolerance, thresholds['macro_tolerance']);
    expect(summaryMaxPoints, thresholds['max_points']);
    expect(summarySodiumTargetMg, thresholds['sodium_target_mg']);
    expect(summaryCalorieTargetKcal, thresholds['calorie_target_kcal']);
    expect(summarySugarTargetG, thresholds['sugar_target_g']);
  });

  test('결과지 패키지의 기준값도 서버와 같다', () {
    expect(calorieTolerance, thresholds['calorie_tolerance']);
    expect(kReportGoodCompletionThreshold, thresholds['good_completion']);
  });

  final AppLocalizationsKo ko = AppLocalizationsKo();
  for (final Map<String, Object?> c in vectorRows(file, 'cases')) {
    test('판정: ${c['name']}', () {
      final report = weeklyReportFromJson(
        c['report']! as Map<String, dynamic>,
        makeClient(name: '김회원'),
      );
      final Map<String, Object?> expected =
          c['expected']! as Map<String, Object?>;
      expect(<Map<String, Object?>>[
        for (final SummaryWatchpoint w in summaryWatchpoints(ko, report))
          <String, Object?>{'kind': w.kind, 'severity': w.severity},
      ], expected['watchpoints']);
      expect(summarySkippedExercises(report), expected['skipped']);
    });
  }
}
