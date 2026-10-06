/// 결과지의 판정 기준값이 서버 리포트 요약과 같다(#2906).
///
/// 원본은 서버 스크립트(`backend/scripts/gen_report_summary_cases.py`)가 만든
/// `shared/oncare_rules/vectors/report_summary_cases.json` 이다. 결과지는 두 앱
/// (회원 앱 리포트·트레이너 웹 결과지)이 함께 그리므로, 기준이 서버와 갈리면 한
/// 회원의 같은 주가 요약 카드와 결과지에서 다른 판정을 받는다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_report/oncare_report.dart';

void main() {
  final Map<String, Object?> thresholds =
      (jsonDecode(
                File(
                  '../oncare_rules/vectors/report_summary_cases.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>)['thresholds']!
          as Map<String, Object?>;

  test('칼로리 허용 폭이 서버와 같다', () {
    expect(calorieTolerance, thresholds['calorie_tolerance']);
  });

  test('탄단지 허용 폭과 나트륨·당류 초과일 기준이 서버와 같다 (#3246)', () {
    expect(macroTolerance, thresholds['macro_tolerance']);
    expect(kReportSodiumOverDays, thresholds['sodium_over_days']);
    expect(kReportSugarOverDays, thresholds['sugar_over_days']);
  });

  test('이행률 좋음 기준이 서버와 같다', () {
    expect(kReportGoodCompletionThreshold, thresholds['good_completion']);
  });

  test('기본 목표가 서버 요약의 기본값과 같다', () {
    expect(kReportCalorieTargetKcal, thresholds['calorie_target_kcal']);
    expect(kReportSodiumTargetMg, thresholds['sodium_target_mg']);
    expect(sugarLimitG, thresholds['sugar_target_g']);
  });
}
