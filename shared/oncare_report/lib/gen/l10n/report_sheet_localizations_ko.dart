// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'report_sheet_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class ReportSheetLocalizationsKo extends ReportSheetLocalizations {
  ReportSheetLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get chartNoRecord => '기록 없음';

  @override
  String dateMonthDay(int month, int day) {
    return '$month월 $day일';
  }

  @override
  String get metricCalories => '칼로리';

  @override
  String get metricCarbs => '탄수화물';

  @override
  String get metricFat => '지방';

  @override
  String get metricProtein => '단백질';

  @override
  String get metricSodium => '나트륨';

  @override
  String get metricSugar => '당류';

  @override
  String get reportsFeedbackTitle => '트레이너 피드백';

  @override
  String get reportsMemberFeedbackConditionLabel => '컨디션';

  @override
  String get reportsMemberFeedbackIntensityLabel => '운동 강도';

  @override
  String get reportsMemberFeedbackNoteLabel => '한 줄 피드백';

  @override
  String get reportsMemberFeedbackNoteNone => '한 줄 피드백 없음';

  @override
  String get reportsMemberFeedbackPainLabel => '통증';

  @override
  String get reportsMemberFeedbackPainNone => '없음';

  @override
  String reportsMemberFeedbackPainOn(String area, String date) {
    return '$area ($date)';
  }

  @override
  String get reportsMemberFeedbackTitle => '회원 주간 피드백';

  @override
  String get reportsMemberFeedbackUnanswered => '미응답';

  @override
  String reportsPdfAttendance(String done, String booked, String rate) {
    return '$done/$booked회 ($rate%)';
  }

  @override
  String get reportsPdfDocTitle => '주간 코칭 리포트';

  @override
  String get reportsPdfLabelCompletion => '운동 수행률';

  @override
  String get reportsPdfLabelSessions => 'PT 진행';

  @override
  String get reportsPdfNoData => '미집계';

  @override
  String get reportsPdfNoFeedback => '피드백 없음';

  @override
  String reportsPdfValueDays(String value) {
    return '$value일';
  }

  @override
  String reportsPdfValueGram(String value) {
    return '${value}g';
  }

  @override
  String reportsPdfValueKcal(String value) {
    return '${value}kcal';
  }

  @override
  String reportsPdfValueMg(String value) {
    return '${value}mg';
  }

  @override
  String reportsPdfValuePercent(String value) {
    return '$value%';
  }

  @override
  String reportsPdfValueSessions(String value) {
    return '$value회';
  }

  @override
  String get reportsSheetAttendance => 'PT 출석';

  @override
  String get reportsSheetAverageBase => '4주 평균';

  @override
  String get reportsSheetAverageChange => '변화';

  @override
  String get reportsSheetAverageNow => '이번 주';

  @override
  String get reportsSheetAverageTitle => '4주 평균 대비';

  @override
  String get reportsSheetBandNormal => '적정';

  @override
  String get reportsSheetBandOver => '초과';

  @override
  String get reportsSheetBandUnder => '부족';

  @override
  String get reportsSheetCalorieDays => '열량 적정일';

  @override
  String get reportsSheetDailyCalories => '열량';

  @override
  String get reportsSheetDailyCompletion => '수행률';

  @override
  String get reportsSheetDailyMeals => '끼니';

  @override
  String get reportsSheetDailyTitle => '요일별 기록';

  @override
  String get reportsSheetDailyWorkouts => '운동';

  @override
  String reportsSheetDaysOf(String days, String due) {
    return '$days/$due일';
  }

  @override
  String get reportsSheetDietHint => '하루 평균 · 목표 대비';

  @override
  String get reportsSheetDietTitle => '식단 분석';

  @override
  String get reportsSheetEvalTitle => '항목별 평가';

  @override
  String get reportsSheetExerciseHint => '이번 주 · 목표 대비';

  @override
  String get reportsSheetExerciseTitle => '운동 분석';

  @override
  String get reportsSheetFootnote =>
      '범위는 이번 주 기록을 회원의 목표와 견줍니다. 기록이 없는 항목은 미집계로 표시합니다.';

  @override
  String reportsSheetGoal(String value) {
    return '목표 $value';
  }

  @override
  String get reportsSheetInfoMealDays => '식단 기록';

  @override
  String get reportsSheetInfoMember => '회원';

  @override
  String get reportsSheetInfoPeriod => '기간';

  @override
  String get reportsSheetMealDaysLabel => '식단 기록일';

  @override
  String reportsSheetPeriodValue(String start, String end) {
    return '$start ~ $end';
  }

  @override
  String get reportsSheetScoreFormula =>
      '운동 수행률·PT 출석·식단 기록·열량 적정일 비율의 평균입니다. 기록이 없는 항목은 빠집니다.';

  @override
  String get reportsSheetScoreNone => '점수를 낼 기록이 없어요';

  @override
  String get reportsSheetScoreTitle => '주간 관리 점수';

  @override
  String get reportsSheetScoreUnit => '/100점';

  @override
  String get reportsSheetTrendDaily => '요일별 섭취 열량 · 목표선';

  @override
  String get reportsSheetTrendTitle => '추이';

  @override
  String get reportsSheetTrendWeekly => '주별 운동 달성률 (8주)';

  @override
  String get reportsTrendUnavailable => '이 주의 운동 기록을 불러오지 못했어요';

  @override
  String get weekdayMon => '월';

  @override
  String get weekdayTue => '화';

  @override
  String get weekdayWed => '수';

  @override
  String get weekdayThu => '목';

  @override
  String get weekdayFri => '금';

  @override
  String get weekdaySat => '토';

  @override
  String get weekdaySun => '일';

  @override
  String get routineTypeCardio => '유산소';

  @override
  String get routineTypeStrength => '근력';

  @override
  String get routineTypeStretching => '스트레칭';

  @override
  String minutesShort(int minutes) {
    return '$minutes분';
  }

  @override
  String progSetsValue(int sets) {
    return '$sets세트';
  }

  @override
  String get reportsMemberFeedbackConditionGreat => '아주 좋았어요';

  @override
  String get reportsMemberFeedbackConditionGood => '좋았어요';

  @override
  String get reportsMemberFeedbackConditionOk => '보통이었어요';

  @override
  String get reportsMemberFeedbackConditionTired => '지쳤어요';

  @override
  String get reportsMemberFeedbackConditionBad => '많이 힘들었어요';

  @override
  String get reportsMemberFeedbackIntensityTooEasy => '너무 쉬웠어요';

  @override
  String get reportsMemberFeedbackIntensityRight => '적당했어요';

  @override
  String get reportsMemberFeedbackIntensityHard => '힘들었어요';

  @override
  String get reportsMemberFeedbackIntensityTooHard => '너무 힘들었어요';
}
