// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'report_sheet_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class ReportSheetLocalizationsEn extends ReportSheetLocalizations {
  ReportSheetLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get chartNoRecord => 'Not logged';

  @override
  String dateMonthDay(int month, int day) {
    return '$month/$day';
  }

  @override
  String get metricCalories => 'Calories';

  @override
  String get metricCarbs => 'Carbs';

  @override
  String get metricFat => 'Fat';

  @override
  String get metricProtein => 'Protein';

  @override
  String get metricSodium => 'Sodium';

  @override
  String get metricSugar => 'Sugar';

  @override
  String get reportsFeedbackTitle => 'Trainer feedback';

  @override
  String get reportsMemberFeedbackConditionLabel => 'Condition';

  @override
  String get reportsMemberFeedbackIntensityLabel => 'Intensity';

  @override
  String get reportsMemberFeedbackNoteLabel => 'One-line feedback';

  @override
  String get reportsMemberFeedbackNoteNone => 'No one-line feedback';

  @override
  String get reportsMemberFeedbackPainLabel => 'Pain';

  @override
  String get reportsMemberFeedbackPainNone => 'None';

  @override
  String reportsMemberFeedbackPainOn(String area, String date) {
    return '$area ($date)';
  }

  @override
  String get reportsMemberFeedbackTitle => 'Member\'s weekly feedback';

  @override
  String get reportsMemberFeedbackUnanswered => 'No answer';

  @override
  String reportsPdfAttendance(String done, String booked, String rate) {
    return '$done/$booked ($rate%)';
  }

  @override
  String get reportsPdfDocTitle => 'Weekly report';

  @override
  String get reportsPdfLabelCompletion => 'Workout completion rate';

  @override
  String get reportsPdfLabelSessions => 'PT done';

  @override
  String get reportsPdfNoData => 'Not measured';

  @override
  String get reportsPdfNoFeedback => 'No feedback';

  @override
  String reportsPdfValueDays(String value) {
    return '$value days';
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
    return '$value';
  }

  @override
  String get reportsSheetAttendance => 'PT done';

  @override
  String get reportsSheetAverageBase => '4-wk avg';

  @override
  String get reportsSheetAverageChange => 'Change';

  @override
  String get reportsSheetAverageNow => 'This week';

  @override
  String get reportsSheetAverageTitle => 'vs. 4-week average';

  @override
  String get reportsSheetBandNormal => 'On target';

  @override
  String get reportsSheetBandOver => 'High';

  @override
  String get reportsSheetBandUnder => 'Low';

  @override
  String get reportsSheetCalorieDays => 'On-target calorie days';

  @override
  String get reportsSheetDailyCalories => 'Calories';

  @override
  String get reportsSheetDailyCompletion => 'Completion';

  @override
  String get reportsSheetDailyMeals => 'Meals';

  @override
  String get reportsSheetDailyTitle => 'Daily log';

  @override
  String get reportsSheetDailyWorkouts => 'Workouts';

  @override
  String reportsSheetDaysOf(String days, String due) {
    return '$days/$due days';
  }

  @override
  String get reportsSheetDietHint => 'Daily average vs. goal';

  @override
  String get reportsSheetDietTitle => 'Diet analysis';

  @override
  String get reportsSheetEvalTitle => 'Evaluation';

  @override
  String get reportsSheetExerciseHint => 'This week vs. goal';

  @override
  String get reportsSheetExerciseTitle => 'Exercise analysis';

  @override
  String get reportsSheetFootnote =>
      'Ranges compare this week with the member\'s goals. Items without records show as Not measured.';

  @override
  String reportsSheetGoal(String value) {
    return 'Goal $value';
  }

  @override
  String get reportsSheetInfoMealDays => 'Meal logs';

  @override
  String get reportsSheetInfoMember => 'Member';

  @override
  String get reportsSheetInfoPeriod => 'Period';

  @override
  String get reportsSheetMealDaysLabel => 'Meal log days';

  @override
  String reportsSheetPeriodValue(String start, String end) {
    return '$start – $end';
  }

  @override
  String get reportsSheetScoreFormula =>
      'Average of workout completion rate, PT done, meal logging and on-target calorie days. Items without records are left out.';

  @override
  String get reportsSheetScoreNone => 'No records to score yet';

  @override
  String get reportsSheetScoreTitle => 'Weekly care score';

  @override
  String get reportsSheetScoreUnit => '/100';

  @override
  String get reportsSheetTrendDaily => 'Daily calories · goal line';

  @override
  String get reportsSheetTrendTitle => 'Trends';

  @override
  String get reportsSheetTrendWeekly => 'Weekly exercise achievement (8 weeks)';

  @override
  String get reportsTrendUnavailable =>
      'Couldn\'t load this week\'s workout records';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get routineTypeCardio => 'Cardio';

  @override
  String get routineTypeStrength => 'Strength';

  @override
  String get routineTypeStretching => 'Stretching';

  @override
  String minutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String progSetsValue(int sets) {
    String _temp0 = intl.Intl.pluralLogic(
      sets,
      locale: localeName,
      other: '$sets sets',
      one: '1 set',
    );
    return '$_temp0';
  }

  @override
  String get reportsMemberFeedbackConditionGreat => 'Great';

  @override
  String get reportsMemberFeedbackConditionGood => 'Good';

  @override
  String get reportsMemberFeedbackConditionOk => 'Okay';

  @override
  String get reportsMemberFeedbackConditionTired => 'Worn out';

  @override
  String get reportsMemberFeedbackConditionBad => 'Rough';

  @override
  String get reportsMemberFeedbackIntensityTooEasy => 'Too easy';

  @override
  String get reportsMemberFeedbackIntensityRight => 'Just right';

  @override
  String get reportsMemberFeedbackIntensityHard => 'A bit hard';

  @override
  String get reportsMemberFeedbackIntensityTooHard => 'Too hard';
}
