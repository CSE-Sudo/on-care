import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'report_sheet_localizations_en.dart';
import 'report_sheet_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of ReportSheetLocalizations
/// returned by `ReportSheetLocalizations.of(context)`.
///
/// Applications need to include `ReportSheetLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/report_sheet_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: ReportSheetLocalizations.localizationsDelegates,
///   supportedLocales: ReportSheetLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the ReportSheetLocalizations.supportedLocales
/// property.
abstract class ReportSheetLocalizations {
  ReportSheetLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static ReportSheetLocalizations of(BuildContext context) {
    return Localizations.of<ReportSheetLocalizations>(
      context,
      ReportSheetLocalizations,
    )!;
  }

  static const LocalizationsDelegate<ReportSheetLocalizations> delegate =
      _ReportSheetLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @chartNoRecord.
  ///
  /// In en, this message translates to:
  /// **'Not logged'**
  String get chartNoRecord;

  /// No description provided for @dateMonthDay.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day}'**
  String dateMonthDay(int month, int day);

  /// No description provided for @metricCalories.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get metricCalories;

  /// No description provided for @metricCarbs.
  ///
  /// In en, this message translates to:
  /// **'Carbs'**
  String get metricCarbs;

  /// No description provided for @metricFat.
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get metricFat;

  /// No description provided for @metricProtein.
  ///
  /// In en, this message translates to:
  /// **'Protein'**
  String get metricProtein;

  /// No description provided for @metricSodium.
  ///
  /// In en, this message translates to:
  /// **'Sodium'**
  String get metricSodium;

  /// No description provided for @metricSugar.
  ///
  /// In en, this message translates to:
  /// **'Sugar'**
  String get metricSugar;

  /// No description provided for @reportsFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Trainer feedback'**
  String get reportsFeedbackTitle;

  /// No description provided for @reportsMemberFeedbackConditionLabel.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get reportsMemberFeedbackConditionLabel;

  /// No description provided for @reportsMemberFeedbackIntensityLabel.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get reportsMemberFeedbackIntensityLabel;

  /// No description provided for @reportsMemberFeedbackNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'One-line feedback'**
  String get reportsMemberFeedbackNoteLabel;

  /// No description provided for @reportsMemberFeedbackNoteNone.
  ///
  /// In en, this message translates to:
  /// **'No one-line feedback'**
  String get reportsMemberFeedbackNoteNone;

  /// No description provided for @reportsMemberFeedbackPainLabel.
  ///
  /// In en, this message translates to:
  /// **'Pain'**
  String get reportsMemberFeedbackPainLabel;

  /// No description provided for @reportsMemberFeedbackPainNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get reportsMemberFeedbackPainNone;

  /// No description provided for @reportsMemberFeedbackPainOn.
  ///
  /// In en, this message translates to:
  /// **'{area} ({date})'**
  String reportsMemberFeedbackPainOn(String area, String date);

  /// No description provided for @reportsMemberFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Member\'s weekly feedback'**
  String get reportsMemberFeedbackTitle;

  /// No description provided for @reportsMemberFeedbackUnanswered.
  ///
  /// In en, this message translates to:
  /// **'No answer'**
  String get reportsMemberFeedbackUnanswered;

  /// No description provided for @reportsPdfAttendance.
  ///
  /// In en, this message translates to:
  /// **'{done}/{booked} ({rate}%)'**
  String reportsPdfAttendance(String done, String booked, String rate);

  /// No description provided for @reportsPdfDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly coaching report'**
  String get reportsPdfDocTitle;

  /// No description provided for @reportsPdfLabelCompletion.
  ///
  /// In en, this message translates to:
  /// **'Workout completion'**
  String get reportsPdfLabelCompletion;

  /// No description provided for @reportsPdfLabelSessions.
  ///
  /// In en, this message translates to:
  /// **'PT'**
  String get reportsPdfLabelSessions;

  /// No description provided for @reportsPdfNoData.
  ///
  /// In en, this message translates to:
  /// **'Not measured'**
  String get reportsPdfNoData;

  /// No description provided for @reportsPdfNoFeedback.
  ///
  /// In en, this message translates to:
  /// **'No feedback'**
  String get reportsPdfNoFeedback;

  /// No description provided for @reportsPdfValueDays.
  ///
  /// In en, this message translates to:
  /// **'{value} days'**
  String reportsPdfValueDays(String value);

  /// No description provided for @reportsPdfValueGram.
  ///
  /// In en, this message translates to:
  /// **'{value}g'**
  String reportsPdfValueGram(String value);

  /// No description provided for @reportsPdfValueKcal.
  ///
  /// In en, this message translates to:
  /// **'{value}kcal'**
  String reportsPdfValueKcal(String value);

  /// No description provided for @reportsPdfValueMg.
  ///
  /// In en, this message translates to:
  /// **'{value}mg'**
  String reportsPdfValueMg(String value);

  /// No description provided for @reportsPdfValuePercent.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String reportsPdfValuePercent(String value);

  /// No description provided for @reportsPdfValueSessions.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String reportsPdfValueSessions(String value);

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'PT attendance'**
  String get reportsSheetAttendance;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'4-wk avg'**
  String get reportsSheetAverageBase;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get reportsSheetAverageChange;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get reportsSheetAverageNow;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'vs. 4-week average'**
  String get reportsSheetAverageTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'On target'**
  String get reportsSheetBandNormal;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get reportsSheetBandOver;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get reportsSheetBandUnder;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'On-target calorie days'**
  String get reportsSheetCalorieDays;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get reportsSheetDailyCalories;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get reportsSheetDailyCompletion;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Meals'**
  String get reportsSheetDailyMeals;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Daily log'**
  String get reportsSheetDailyTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Workouts'**
  String get reportsSheetDailyWorkouts;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'{days}/{due} days'**
  String reportsSheetDaysOf(String days, String due);

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Daily average vs. goal'**
  String get reportsSheetDietHint;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Diet analysis'**
  String get reportsSheetDietTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Evaluation'**
  String get reportsSheetEvalTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'This week vs. goal'**
  String get reportsSheetExerciseHint;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Exercise analysis'**
  String get reportsSheetExerciseTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Ranges compare this week with the member\'s goals. Items without records show as Not measured.'**
  String get reportsSheetFootnote;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Goal {value}'**
  String reportsSheetGoal(String value);

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Meal logs'**
  String get reportsSheetInfoMealDays;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get reportsSheetInfoMember;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get reportsSheetInfoPeriod;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Meal log days'**
  String get reportsSheetMealDaysLabel;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'{start} – {end}'**
  String reportsSheetPeriodValue(String start, String end);

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Average of workout completion, PT attendance, meal logging and on-target calorie days. Items without records are left out.'**
  String get reportsSheetScoreFormula;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'No records to score yet'**
  String get reportsSheetScoreNone;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Weekly care score'**
  String get reportsSheetScoreTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'/100'**
  String get reportsSheetScoreUnit;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Daily calories · goal line'**
  String get reportsSheetTrendDaily;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Trends'**
  String get reportsSheetTrendTitle;

  /// 리포트 PDF 한 장 결과지 (#2485).
  ///
  /// In en, this message translates to:
  /// **'Weekly exercise achievement (8 weeks)'**
  String get reportsSheetTrendWeekly;

  /// No description provided for @reportsTrendUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this week\'s workout records'**
  String get reportsTrendUnavailable;

  /// No description provided for @weekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdaySun;

  /// No description provided for @routineTypeCardio.
  ///
  /// In en, this message translates to:
  /// **'Cardio'**
  String get routineTypeCardio;

  /// No description provided for @routineTypeStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get routineTypeStrength;

  /// No description provided for @routineTypeStretching.
  ///
  /// In en, this message translates to:
  /// **'Stretching'**
  String get routineTypeStretching;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String minutesShort(int minutes);

  /// No description provided for @progSetsValue.
  ///
  /// In en, this message translates to:
  /// **'{sets, plural, =1{1 set} other{{sets} sets}}'**
  String progSetsValue(int sets);

  /// No description provided for @reportsMemberFeedbackConditionGreat.
  ///
  /// In en, this message translates to:
  /// **'Great'**
  String get reportsMemberFeedbackConditionGreat;

  /// No description provided for @reportsMemberFeedbackConditionGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get reportsMemberFeedbackConditionGood;

  /// No description provided for @reportsMemberFeedbackConditionOk.
  ///
  /// In en, this message translates to:
  /// **'Okay'**
  String get reportsMemberFeedbackConditionOk;

  /// No description provided for @reportsMemberFeedbackConditionTired.
  ///
  /// In en, this message translates to:
  /// **'Worn out'**
  String get reportsMemberFeedbackConditionTired;

  /// No description provided for @reportsMemberFeedbackConditionBad.
  ///
  /// In en, this message translates to:
  /// **'Really rough'**
  String get reportsMemberFeedbackConditionBad;

  /// No description provided for @reportsMemberFeedbackIntensityTooEasy.
  ///
  /// In en, this message translates to:
  /// **'Too easy'**
  String get reportsMemberFeedbackIntensityTooEasy;

  /// No description provided for @reportsMemberFeedbackIntensityRight.
  ///
  /// In en, this message translates to:
  /// **'About right'**
  String get reportsMemberFeedbackIntensityRight;

  /// No description provided for @reportsMemberFeedbackIntensityHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get reportsMemberFeedbackIntensityHard;

  /// No description provided for @reportsMemberFeedbackIntensityTooHard.
  ///
  /// In en, this message translates to:
  /// **'Too hard'**
  String get reportsMemberFeedbackIntensityTooHard;
}

class _ReportSheetLocalizationsDelegate
    extends LocalizationsDelegate<ReportSheetLocalizations> {
  const _ReportSheetLocalizationsDelegate();

  @override
  Future<ReportSheetLocalizations> load(Locale locale) {
    return SynchronousFuture<ReportSheetLocalizations>(
      lookupReportSheetLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_ReportSheetLocalizationsDelegate old) => false;
}

ReportSheetLocalizations lookupReportSheetLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return ReportSheetLocalizationsEn();
    case 'ko':
      return ReportSheetLocalizationsKo();
  }

  throw FlutterError(
    'ReportSheetLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
