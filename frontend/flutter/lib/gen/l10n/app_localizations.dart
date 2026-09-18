import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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

  /// Application name shown in window/AppBar titles.
  ///
  /// In en, this message translates to:
  /// **'On-Care'**
  String get appTitle;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navDashboard;

  /// No description provided for @navDiet.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get navDiet;

  /// No description provided for @navExercise.
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get navExercise;

  /// No description provided for @navMyHealth.
  ///
  /// In en, this message translates to:
  /// **'MY'**
  String get navMyHealth;

  /// No description provided for @pageDietTitle.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get pageDietTitle;

  /// No description provided for @pageExerciseTitle.
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get pageExerciseTitle;

  /// No description provided for @pageAiCoachTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Coach'**
  String get pageAiCoachTitle;

  /// No description provided for @pageNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get pageNotificationTitle;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network problem'**
  String get errorNetwork;

  /// No description provided for @errorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Sign in required'**
  String get errorUnauthorized;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get errorNotFound;

  /// No description provided for @errorServer.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get errorServer;

  /// No description provided for @errorCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get errorCancelled;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorUnknown;

  /// No description provided for @dashboardMetricCalories.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get dashboardMetricCalories;

  /// No description provided for @dashboardMetricExercise.
  ///
  /// In en, this message translates to:
  /// **'Weekly exercise'**
  String get dashboardMetricExercise;

  /// No description provided for @homeDashboardLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load the dashboard.'**
  String get homeDashboardLoadError;

  /// No description provided for @homeDashboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'No records yet today. Add a meal or workout to get started.'**
  String get homeDashboardEmpty;

  /// No description provided for @homeAiAdviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s combined AI advice'**
  String get homeAiAdviceTitle;

  /// Home AI advice when today's sodium is over the goal (#1943).
  ///
  /// In en, this message translates to:
  /// **'You went over the sodium target today. Try keeping the rest of your meals light.'**
  String get homeAdviceSodiumOver;

  /// Home AI advice when the weekly exercise goal is met (#1943).
  ///
  /// In en, this message translates to:
  /// **'You worked out {minutes} minutes this week. You are on track!'**
  String homeAdviceExerciseOnTrack(int minutes);

  /// Home AI advice when there is some exercise but not enough (#1943).
  ///
  /// In en, this message translates to:
  /// **'You worked out {minutes} minutes this week. A little more to go!'**
  String homeAdviceExerciseMore(int minutes);

  /// Home AI advice when nothing was logged this week (#1943).
  ///
  /// In en, this message translates to:
  /// **'Start moving this week — an easy walk is a good beginning.'**
  String get homeAdviceExerciseStart;

  /// No description provided for @homeAiAdviceBody.
  ///
  /// In en, this message translates to:
  /// **'Your breakfast and evening PT were perfect! Lunch ran high in sodium, so drink plenty of water and finish well with the shoulder stretches your coach emphasized.'**
  String get homeAiAdviceBody;

  /// No description provided for @homeSodiumExceededBadge.
  ///
  /// In en, this message translates to:
  /// **'Sodium over'**
  String get homeSodiumExceededBadge;

  /// No description provided for @homeMacroCarbs.
  ///
  /// In en, this message translates to:
  /// **'Carbs'**
  String get homeMacroCarbs;

  /// No description provided for @homeMacroProtein.
  ///
  /// In en, this message translates to:
  /// **'Protein'**
  String get homeMacroProtein;

  /// No description provided for @homeMacroFat.
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get homeMacroFat;

  /// No description provided for @homeMealChickenSalad.
  ///
  /// In en, this message translates to:
  /// **'Chicken breast salad'**
  String get homeMealChickenSalad;

  /// No description provided for @homeDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get homeDetails;

  /// No description provided for @homeGoal.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get homeGoal;

  /// No description provided for @homeDietNutritionTitle.
  ///
  /// In en, this message translates to:
  /// **'Diet & nutrition'**
  String get homeDietNutritionTitle;

  /// No description provided for @homeCalorieIntake.
  ///
  /// In en, this message translates to:
  /// **'Today\'s calories'**
  String get homeCalorieIntake;

  /// No description provided for @homeAchieveRate.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get homeAchieveRate;

  /// No description provided for @homeWeeklyMetricTrend.
  ///
  /// In en, this message translates to:
  /// **'Weekly {metric} trend'**
  String homeWeeklyMetricTrend(String metric);

  /// No description provided for @homeWeeklyExerciseTrend.
  ///
  /// In en, this message translates to:
  /// **'Exercise trend'**
  String get homeWeeklyExerciseTrend;

  /// No description provided for @homeExerciseTrendUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this week\'s workout history.'**
  String get homeExerciseTrendUnavailable;

  /// No description provided for @homeExerciseBurned.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get homeExerciseBurned;

  /// No description provided for @homeMealReasonSodium.
  ///
  /// In en, this message translates to:
  /// **'Great for sodium control'**
  String get homeMealReasonSodium;

  /// No description provided for @homeMealSourceTrainer.
  ///
  /// In en, this message translates to:
  /// **'Trainer pick'**
  String get homeMealSourceTrainer;

  /// No description provided for @homeMealSourceAi.
  ///
  /// In en, this message translates to:
  /// **'AI pick'**
  String get homeMealSourceAi;

  /// No description provided for @homeMealTagLowSodium.
  ///
  /// In en, this message translates to:
  /// **'Low sodium'**
  String get homeMealTagLowSodium;

  /// No description provided for @homeMealBrownRiceBox.
  ///
  /// In en, this message translates to:
  /// **'Brown rice lunchbox'**
  String get homeMealBrownRiceBox;

  /// No description provided for @homeMealReasonGlucose.
  ///
  /// In en, this message translates to:
  /// **'Helps steady blood sugar'**
  String get homeMealReasonGlucose;

  /// No description provided for @homeMealTagLowSugar.
  ///
  /// In en, this message translates to:
  /// **'Low sugar'**
  String get homeMealTagLowSugar;

  /// No description provided for @homeMealSalmon.
  ///
  /// In en, this message translates to:
  /// **'Grilled salmon + greens'**
  String get homeMealSalmon;

  /// No description provided for @homeMealReasonOmega.
  ///
  /// In en, this message translates to:
  /// **'Omega-3 + fiber'**
  String get homeMealReasonOmega;

  /// No description provided for @homeMealTagHighProtein.
  ///
  /// In en, this message translates to:
  /// **'High protein'**
  String get homeMealTagHighProtein;

  /// No description provided for @homeMealTofu.
  ///
  /// In en, this message translates to:
  /// **'Stir-fried tofu & veggies'**
  String get homeMealTofu;

  /// No description provided for @homeMealReasonLowCal.
  ///
  /// In en, this message translates to:
  /// **'Low calorie, keeps you full'**
  String get homeMealReasonLowCal;

  /// No description provided for @homeMealTagLowCal.
  ///
  /// In en, this message translates to:
  /// **'Low calorie'**
  String get homeMealTagLowCal;

  /// No description provided for @homeMealNamulBibimbap.
  ///
  /// In en, this message translates to:
  /// **'Namul bibimbap'**
  String get homeMealNamulBibimbap;

  /// No description provided for @homeMealReasonFiber.
  ///
  /// In en, this message translates to:
  /// **'Rich in dietary fiber'**
  String get homeMealReasonFiber;

  /// No description provided for @homeMealTagLowFat.
  ///
  /// In en, this message translates to:
  /// **'Low fat'**
  String get homeMealTagLowFat;

  /// No description provided for @homeRecBasisSodium.
  ///
  /// In en, this message translates to:
  /// **'{days}-day avg sodium {sodium}mg'**
  String homeRecBasisSodium(int days, String sodium);

  /// No description provided for @homeRecBasisOverLimit.
  ///
  /// In en, this message translates to:
  /// **'over the daily limit'**
  String get homeRecBasisOverLimit;

  /// No description provided for @homeRecMealsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recommended meals'**
  String get homeRecMealsTitle;

  /// No description provided for @homeViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get homeViewAll;

  /// No description provided for @unitKcal.
  ///
  /// In en, this message translates to:
  /// **'kcal'**
  String get unitKcal;

  /// No description provided for @unitMinutes.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get unitMinutes;

  /// No description provided for @unitSets.
  ///
  /// In en, this message translates to:
  /// **'sets'**
  String get unitSets;

  /// No description provided for @unitKcalValue.
  ///
  /// In en, this message translates to:
  /// **'{count} kcal'**
  String unitKcalValue(int count);

  /// No description provided for @unitMinutesValue.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String unitMinutesValue(int count);

  /// No description provided for @dietTitle.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get dietTitle;

  /// No description provided for @dietToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dietToday;

  /// No description provided for @dietWeekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get dietWeekdayMon;

  /// No description provided for @dietWeekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get dietWeekdayTue;

  /// No description provided for @dietWeekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get dietWeekdayWed;

  /// No description provided for @dietWeekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get dietWeekdayThu;

  /// No description provided for @dietWeekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get dietWeekdayFri;

  /// No description provided for @dietWeekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get dietWeekdaySat;

  /// No description provided for @dietWeekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get dietWeekdaySun;

  /// No description provided for @dietNutritionSummary.
  ///
  /// In en, this message translates to:
  /// **'Nutrition'**
  String get dietNutritionSummary;

  /// Label of the serving-size (g) field at the top of a food edit block; the rest of the nutrition scales with it (#1876)
  ///
  /// In en, this message translates to:
  /// **'Serving size'**
  String get dietAmount;

  /// No description provided for @dietCalories.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get dietCalories;

  /// No description provided for @dietSodium.
  ///
  /// In en, this message translates to:
  /// **'Sodium'**
  String get dietSodium;

  /// No description provided for @dietSugar.
  ///
  /// In en, this message translates to:
  /// **'Sugar'**
  String get dietSugar;

  /// No description provided for @dietUnitMg.
  ///
  /// In en, this message translates to:
  /// **'mg'**
  String get dietUnitMg;

  /// No description provided for @dietUnitG.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get dietUnitG;

  /// No description provided for @dietAiFeedback.
  ///
  /// In en, this message translates to:
  /// **'AI advice'**
  String get dietAiFeedback;

  /// Shown in the AI advice card while the selected period's advice loads (#1574)
  ///
  /// In en, this message translates to:
  /// **'Looking at this period…'**
  String get aiAdviceLoading;

  /// Shown in the AI advice card when the selected period's advice fails (#1574)
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the advice.'**
  String get aiAdviceError;

  /// No description provided for @dietMealLog.
  ///
  /// In en, this message translates to:
  /// **'Meal Log'**
  String get dietMealLog;

  /// No description provided for @dietAddMeal.
  ///
  /// In en, this message translates to:
  /// **'Add Meal'**
  String get dietAddMeal;

  /// No description provided for @dietEmptyLog.
  ///
  /// In en, this message translates to:
  /// **'No meals logged.\nAdd a meal with a photo!'**
  String get dietEmptyLog;

  /// No description provided for @dietLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your diet.'**
  String get dietLoadError;

  /// No description provided for @dietPeriodAverage.
  ///
  /// In en, this message translates to:
  /// **'Daily average'**
  String get dietPeriodAverage;

  /// No description provided for @dietPeriodEmpty.
  ///
  /// In en, this message translates to:
  /// **'No meals were logged in this period.'**
  String get dietPeriodEmpty;

  /// No description provided for @dietPeriodRange.
  ///
  /// In en, this message translates to:
  /// **'{start} - {end}'**
  String dietPeriodRange(String start, String end);

  /// No description provided for @dietPeriodNoRecord.
  ///
  /// In en, this message translates to:
  /// **'No record'**
  String get dietPeriodNoRecord;

  /// No description provided for @dietPeriodNotYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get dietPeriodNotYet;

  /// No description provided for @dietPeriodOverGoal.
  ///
  /// In en, this message translates to:
  /// **'{amount} {unit} over goal'**
  String dietPeriodOverGoal(String amount, String unit);

  /// No description provided for @otherDateEmpty.
  ///
  /// In en, this message translates to:
  /// **'No {section} records for the selected date.'**
  String otherDateEmpty(Object section);

  /// No description provided for @dietMealBreakfast.
  ///
  /// In en, this message translates to:
  /// **'Breakfast'**
  String get dietMealBreakfast;

  /// No description provided for @dietMealLunch.
  ///
  /// In en, this message translates to:
  /// **'Lunch'**
  String get dietMealLunch;

  /// No description provided for @dietMealDinner.
  ///
  /// In en, this message translates to:
  /// **'Dinner'**
  String get dietMealDinner;

  /// No description provided for @dietMealSnack.
  ///
  /// In en, this message translates to:
  /// **'Snack'**
  String get dietMealSnack;

  /// No description provided for @dietMealLateNight.
  ///
  /// In en, this message translates to:
  /// **'Late-night'**
  String get dietMealLateNight;

  /// No description provided for @dietMealSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'{meal}'**
  String dietMealSheetTitle(String meal);

  /// Representative name shown on the suggestion row when a food name matches the public nutrition DB (#1896)
  ///
  /// In en, this message translates to:
  /// **'Public DB · {name}'**
  String dietFoodDbMatch(String name);

  /// Button that fills a food's fields with the suggested public-DB nutrition (#1896)
  ///
  /// In en, this message translates to:
  /// **'Fill in'**
  String get dietFillFromDb;

  /// No description provided for @dietAddSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a Meal'**
  String get dietAddSheetTitle;

  /// No description provided for @dietAddSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Analyze your food from a photo'**
  String get dietAddSheetSubtitle;

  /// No description provided for @dietPickPhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose a Photo'**
  String get dietPickPhoto;

  /// No description provided for @dietPickPhotoSub.
  ///
  /// In en, this message translates to:
  /// **'Pick a food photo from your gallery'**
  String get dietPickPhotoSub;

  /// No description provided for @dietTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a Photo'**
  String get dietTakePhoto;

  /// No description provided for @dietTakePhotoSub.
  ///
  /// In en, this message translates to:
  /// **'Snap your food with the camera'**
  String get dietTakePhotoSub;

  /// No description provided for @dietAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a Photo'**
  String get dietAddPhoto;

  /// No description provided for @dietAddPhotoSub.
  ///
  /// In en, this message translates to:
  /// **'Choose a food photo from your library, camera, or files'**
  String get dietAddPhotoSub;

  /// No description provided for @dietPhotoLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the photo. Please try again in a moment.'**
  String get dietPhotoLoadError;

  /// No description provided for @dietCameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera permission is needed to photograph your meal. Tap Take Photo to try again.'**
  String get dietCameraPermissionDenied;

  /// No description provided for @dietCameraPermissionPermanentlyDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera access is off. Turn it on in Settings to photograph your meal.'**
  String get dietCameraPermissionPermanentlyDenied;

  /// No description provided for @dietPhotoPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Photo permission is needed to choose a meal photo. Tap Choose Photo to try again.'**
  String get dietPhotoPermissionDenied;

  /// No description provided for @dietPhotoPermissionPermanentlyDenied.
  ///
  /// In en, this message translates to:
  /// **'Photo access is off. Turn it on in Settings to choose a meal photo.'**
  String get dietPhotoPermissionPermanentlyDenied;

  /// No description provided for @dietPhotoPermissionRestricted.
  ///
  /// In en, this message translates to:
  /// **'Camera or photo access is unavailable because of this device\'s settings or management policy.'**
  String get dietPhotoPermissionRestricted;

  /// No description provided for @dietPhotoUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'That photo format isn\'t supported. Please try a JPG or PNG photo.'**
  String get dietPhotoUnsupportedFormat;

  /// No description provided for @dietPhotoTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That photo is too large. Please try a different one.'**
  String get dietPhotoTooLarge;

  /// No description provided for @dietOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get dietOpenSettings;

  /// No description provided for @dietOpenSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open Settings. Turn on camera and photo access under Settings > Oncare.'**
  String get dietOpenSettingsFailed;

  /// No description provided for @dietAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing…'**
  String get dietAnalyzing;

  /// No description provided for @dietAnalysisFailed.
  ///
  /// In en, this message translates to:
  /// **'Analysis failed'**
  String get dietAnalysisFailed;

  /// Label of the date a photo-analysed meal is logged under.
  ///
  /// In en, this message translates to:
  /// **'Record date'**
  String get dietRecordDate;

  /// Button that opens the date picker on the analysis result sheet.
  ///
  /// In en, this message translates to:
  /// **'Change date'**
  String get dietRecordDateChange;

  /// Confirmation after moving an analysed meal to another day.
  ///
  /// In en, this message translates to:
  /// **'Moved to {date}'**
  String dietRecordDateMoved(String date);

  /// Error shown when moving an analysed meal to another day fails.
  ///
  /// In en, this message translates to:
  /// **'Could not change the date. Please try again shortly.'**
  String get dietRecordDateFailed;

  /// No description provided for @dietAnalysisDone.
  ///
  /// In en, this message translates to:
  /// **'Analysis complete!'**
  String get dietAnalysisDone;

  /// No description provided for @dietAiNutritionResult.
  ///
  /// In en, this message translates to:
  /// **'AI Nutrition Result'**
  String get dietAiNutritionResult;

  /// No description provided for @dietAnalyzingBody.
  ///
  /// In en, this message translates to:
  /// **'Analyzing the food in your photo'**
  String get dietAnalyzingBody;

  /// No description provided for @dietAnalysisFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Analysis failed. Please try again in a moment.'**
  String get dietAnalysisFailedBody;

  /// No description provided for @dietAnalysisUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'This photo format can\'t be analyzed. Please pick a JPG or PNG photo instead.'**
  String get dietAnalysisUnsupportedFormat;

  /// No description provided for @dietAnalysisBadRequest.
  ///
  /// In en, this message translates to:
  /// **'The photo couldn\'t be read. Please pick a different one.'**
  String get dietAnalysisBadRequest;

  /// No description provided for @dietAnalysisUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please sign in again to log this meal.'**
  String get dietAnalysisUnauthorized;

  /// No description provided for @dietAnalysisNotImplemented.
  ///
  /// In en, this message translates to:
  /// **'Photo analysis is unavailable right now. Please log the meal manually.'**
  String get dietAnalysisNotImplemented;

  /// No description provided for @dietAnalysisPickAnother.
  ///
  /// In en, this message translates to:
  /// **'Pick another photo'**
  String get dietAnalysisPickAnother;

  /// No description provided for @dietAnalysisSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get dietAnalysisSignIn;

  /// No description provided for @dietAnalysisClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get dietAnalysisClose;

  /// No description provided for @dietRecognizedFood.
  ///
  /// In en, this message translates to:
  /// **'Recognized Food'**
  String get dietRecognizedFood;

  /// No description provided for @dietNoRecognizedFood.
  ///
  /// In en, this message translates to:
  /// **'No food recognized'**
  String get dietNoRecognizedFood;

  /// No description provided for @dietNutritionResult.
  ///
  /// In en, this message translates to:
  /// **'Nutrition Result'**
  String get dietNutritionResult;

  /// No description provided for @dietSaved.
  ///
  /// In en, this message translates to:
  /// **'Meal saved'**
  String get dietSaved;

  /// No description provided for @dietSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Please try again in a moment.'**
  String get dietSaveFailed;

  /// No description provided for @dietDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Meal Record'**
  String get dietDeleteTitle;

  /// No description provided for @dietDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this meal record?'**
  String get dietDeleteConfirm;

  /// No description provided for @dietDeleteWhenEmpty.
  ///
  /// In en, this message translates to:
  /// **'No food is left. Delete this meal record?'**
  String get dietDeleteWhenEmpty;

  /// No description provided for @dietCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dietCancel;

  /// No description provided for @dietDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get dietDelete;

  /// No description provided for @dietDeleted.
  ///
  /// In en, this message translates to:
  /// **'Meal deleted'**
  String get dietDeleted;

  /// No description provided for @dietDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete. Please try again in a moment.'**
  String get dietDeleteFailed;

  /// No description provided for @dietSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get dietSave;

  /// No description provided for @dietMealInfo.
  ///
  /// In en, this message translates to:
  /// **'Meal Info'**
  String get dietMealInfo;

  /// No description provided for @dietEatenTime.
  ///
  /// In en, this message translates to:
  /// **'Time Eaten'**
  String get dietEatenTime;

  /// No description provided for @dietEatenFood.
  ///
  /// In en, this message translates to:
  /// **'Food Eaten'**
  String get dietEatenFood;

  /// No description provided for @dietNewFood.
  ///
  /// In en, this message translates to:
  /// **'New food'**
  String get dietNewFood;

  /// No description provided for @dietAddFood.
  ///
  /// In en, this message translates to:
  /// **'Add Food'**
  String get dietAddFood;

  /// No description provided for @dietEditFoodHint.
  ///
  /// In en, this message translates to:
  /// **'Change the serving size and the nutrition follows'**
  String get dietEditFoodHint;

  /// No description provided for @dietTotalCalories.
  ///
  /// In en, this message translates to:
  /// **'Total Calories'**
  String get dietTotalCalories;

  /// No description provided for @dietNutritionInfo.
  ///
  /// In en, this message translates to:
  /// **'Nutrition Info'**
  String get dietNutritionInfo;

  /// No description provided for @dietEditNutritionHint.
  ///
  /// In en, this message translates to:
  /// **'Edit each food\'s nutrition and it adds up here'**
  String get dietEditNutritionHint;

  /// No description provided for @dietSugarOverCarbs.
  ///
  /// In en, this message translates to:
  /// **'Sugar can\'t be more than carbs'**
  String get dietSugarOverCarbs;

  /// No description provided for @dietDeleteMeal.
  ///
  /// In en, this message translates to:
  /// **'Delete Meal'**
  String get dietDeleteMeal;

  /// No description provided for @dietEditMeal.
  ///
  /// In en, this message translates to:
  /// **'Edit meal'**
  String get dietEditMeal;

  /// No description provided for @exTypeCardio.
  ///
  /// In en, this message translates to:
  /// **'Cardio'**
  String get exTypeCardio;

  /// No description provided for @exTypeStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get exTypeStrength;

  /// No description provided for @exTypeFlexibility.
  ///
  /// In en, this message translates to:
  /// **'Stretching'**
  String get exTypeFlexibility;

  /// No description provided for @exTypeOtherChip.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get exTypeOtherChip;

  /// No description provided for @exLevelLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get exLevelLight;

  /// No description provided for @exLevelModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get exLevelModerate;

  /// No description provided for @exLevelHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get exLevelHigh;

  /// No description provided for @exExerciseLog.
  ///
  /// In en, this message translates to:
  /// **'Exercise Log'**
  String get exExerciseLog;

  /// No description provided for @exGymTab.
  ///
  /// In en, this message translates to:
  /// **'Gym'**
  String get exGymTab;

  /// No description provided for @exMyGymSection.
  ///
  /// In en, this message translates to:
  /// **'My Gym'**
  String get exMyGymSection;

  /// No description provided for @exConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get exConnected;

  /// No description provided for @exRecommendedGyms.
  ///
  /// In en, this message translates to:
  /// **'Recommended Gyms'**
  String get exRecommendedGyms;

  /// No description provided for @exRecommendedTrainers.
  ///
  /// In en, this message translates to:
  /// **'Recommended Trainers'**
  String get exRecommendedTrainers;

  /// No description provided for @exSeeMore.
  ///
  /// In en, this message translates to:
  /// **'See more'**
  String get exSeeMore;

  /// No description provided for @exNoConnectedGym.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have a connected gym yet.'**
  String get exNoConnectedGym;

  /// No description provided for @exNoRecommendedGyms.
  ///
  /// In en, this message translates to:
  /// **'No gym recommendations yet.'**
  String get exNoRecommendedGyms;

  /// No description provided for @exNoRecommendedTrainers.
  ///
  /// In en, this message translates to:
  /// **'No trainer recommendations yet.'**
  String get exNoRecommendedTrainers;

  /// No description provided for @exTrainerAffiliation.
  ///
  /// In en, this message translates to:
  /// **'Gym'**
  String get exTrainerAffiliation;

  /// No description provided for @exTrainerIntroSection.
  ///
  /// In en, this message translates to:
  /// **'About the trainer'**
  String get exTrainerIntroSection;

  /// No description provided for @exTrainerCareer.
  ///
  /// In en, this message translates to:
  /// **'{career} of experience'**
  String exTrainerCareer(String career);

  /// No description provided for @exTrainerCertifications.
  ///
  /// In en, this message translates to:
  /// **'Certifications'**
  String get exTrainerCertifications;

  /// No description provided for @exTrainerRecommendationReason.
  ///
  /// In en, this message translates to:
  /// **'A great fit for reaching my health goals'**
  String get exTrainerRecommendationReason;

  /// No description provided for @exNearbyGymsMapLabel.
  ///
  /// In en, this message translates to:
  /// **'Gyms near me'**
  String get exNearbyGymsMapLabel;

  /// No description provided for @exWeekSummary.
  ///
  /// In en, this message translates to:
  /// **'This Week\'s Summary'**
  String get exWeekSummary;

  /// No description provided for @exActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get exActivityTitle;

  /// No description provided for @exWeekOfMonthLabel.
  ///
  /// In en, this message translates to:
  /// **'Week {week}, {month}/'**
  String exWeekOfMonthLabel(int month, int week);

  /// No description provided for @exBurnTodayTitle.
  ///
  /// In en, this message translates to:
  /// **'Burned today'**
  String get exBurnTodayTitle;

  /// No description provided for @exBurnWeekTitle.
  ///
  /// In en, this message translates to:
  /// **'Burned this week'**
  String get exBurnWeekTitle;

  /// No description provided for @exBurnAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Average burned'**
  String get exBurnAllTitle;

  /// No description provided for @exGoalValue.
  ///
  /// In en, this message translates to:
  /// **'Goal {value}'**
  String exGoalValue(String value);

  /// No description provided for @exLoadEmpty.
  ///
  /// In en, this message translates to:
  /// **'No records yet.'**
  String get exLoadEmpty;

  /// No description provided for @exThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get exThisWeek;

  /// No description provided for @exPeriodAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get exPeriodAll;

  /// No description provided for @exExerciseContent.
  ///
  /// In en, this message translates to:
  /// **'What you did'**
  String get exExerciseContent;

  /// No description provided for @exViewDetail.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get exViewDetail;

  /// No description provided for @exRegister.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get exRegister;

  /// No description provided for @exGymRegistered.
  ///
  /// In en, this message translates to:
  /// **'Registered {gym}'**
  String exGymRegistered(String gym);

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @exWeekNumber.
  ///
  /// In en, this message translates to:
  /// **'Week {n}'**
  String exWeekNumber(int n);

  /// No description provided for @exTodayTotalTime.
  ///
  /// In en, this message translates to:
  /// **'Today\'s total time'**
  String get exTodayTotalTime;

  /// No description provided for @exRest.
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get exRest;

  /// No description provided for @exRestSeconds.
  ///
  /// In en, this message translates to:
  /// **'Rest {seconds}s'**
  String exRestSeconds(int seconds);

  /// No description provided for @exAiRecommendedExercise.
  ///
  /// In en, this message translates to:
  /// **'AI recommended exercise'**
  String get exAiRecommendedExercise;

  /// No description provided for @exStatTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get exStatTime;

  /// No description provided for @exStatCalories.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get exStatCalories;

  /// No description provided for @exStatStreak.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get exStatStreak;

  /// No description provided for @exUnitStreakDays.
  ///
  /// In en, this message translates to:
  /// **'day streak'**
  String get exUnitStreakDays;

  /// No description provided for @exStreakCheer.
  ///
  /// In en, this message translates to:
  /// **'{days} days in a row!'**
  String exStreakCheer(int days);

  /// No description provided for @exStreakStart.
  ///
  /// In en, this message translates to:
  /// **'Start a streak with today\'s workout.'**
  String get exStreakStart;

  /// No description provided for @exToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get exToday;

  /// No description provided for @exLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your exercise data.'**
  String get exLoadError;

  /// No description provided for @exCompletedPtTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s completed PT'**
  String get exCompletedPtTitle;

  /// No description provided for @exCompletedPtTime.
  ///
  /// In en, this message translates to:
  /// **'{time} completed'**
  String exCompletedPtTime(String time);

  /// No description provided for @exCompletedPtNoProgram.
  ///
  /// In en, this message translates to:
  /// **'No workout program was recorded.'**
  String get exCompletedPtNoProgram;

  /// No description provided for @exCompletedPtFeedback.
  ///
  /// In en, this message translates to:
  /// **'{coachName} · Today\'s feedback'**
  String exCompletedPtFeedback(String coachName);

  /// No description provided for @exAddExercise.
  ///
  /// In en, this message translates to:
  /// **'Add Exercise'**
  String get exAddExercise;

  /// No description provided for @exDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String exDurationMinutes(int minutes);

  /// No description provided for @exEditExercise.
  ///
  /// In en, this message translates to:
  /// **'Edit Exercise Record'**
  String get exEditExercise;

  /// No description provided for @exSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get exSave;

  /// No description provided for @exExerciseType.
  ///
  /// In en, this message translates to:
  /// **'Exercise Type'**
  String get exExerciseType;

  /// No description provided for @exExerciseDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get exExerciseDate;

  /// No description provided for @exExerciseName.
  ///
  /// In en, this message translates to:
  /// **'Exercise Name'**
  String get exExerciseName;

  /// No description provided for @exExerciseNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Squat, Treadmill'**
  String get exExerciseNameHint;

  /// No description provided for @exExerciseNameHintCardio.
  ///
  /// In en, this message translates to:
  /// **'e.g. Treadmill, Indoor cycling'**
  String get exExerciseNameHintCardio;

  /// No description provided for @exExerciseNameHintStrength.
  ///
  /// In en, this message translates to:
  /// **'e.g. Squat, Bench press'**
  String get exExerciseNameHintStrength;

  /// No description provided for @exExerciseNameHintFlexibility.
  ///
  /// In en, this message translates to:
  /// **'e.g. Full-body stretch, Yoga'**
  String get exExerciseNameHintFlexibility;

  /// No description provided for @exExerciseNameHintOther.
  ///
  /// In en, this message translates to:
  /// **'e.g. Rehab exercise, Sports activity'**
  String get exExerciseNameHintOther;

  /// No description provided for @exExerciseReps.
  ///
  /// In en, this message translates to:
  /// **'Reps'**
  String get exExerciseReps;

  /// No description provided for @exExerciseWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get exExerciseWeight;

  /// No description provided for @exUnitMinutes.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get exUnitMinutes;

  /// No description provided for @exUnitSets.
  ///
  /// In en, this message translates to:
  /// **'sets'**
  String get exUnitSets;

  /// No description provided for @exUnitReps.
  ///
  /// In en, this message translates to:
  /// **'reps'**
  String get exUnitReps;

  /// No description provided for @exUnitKg.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get exUnitKg;

  /// No description provided for @exEnterName.
  ///
  /// In en, this message translates to:
  /// **'Please enter an exercise name'**
  String get exEnterName;

  /// No description provided for @exExerciseDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get exExerciseDuration;

  /// No description provided for @exExerciseSets.
  ///
  /// In en, this message translates to:
  /// **'Sets'**
  String get exExerciseSets;

  /// No description provided for @exSetsCount.
  ///
  /// In en, this message translates to:
  /// **'{sets, plural, =1{1 set} other{{sets} sets}}'**
  String exSetsCount(int sets);

  /// No description provided for @exRepsCount.
  ///
  /// In en, this message translates to:
  /// **'{reps, plural, =1{1 rep} other{{reps} reps}}'**
  String exRepsCount(int reps);

  /// No description provided for @exEnterSets.
  ///
  /// In en, this message translates to:
  /// **'Enter the number of sets'**
  String get exEnterSets;

  /// No description provided for @exExerciseIntensity.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get exExerciseIntensity;

  /// No description provided for @exEstimatedCalories.
  ///
  /// In en, this message translates to:
  /// **'Estimated Calories'**
  String get exEstimatedCalories;

  /// No description provided for @exCaloriesNeedName.
  ///
  /// In en, this message translates to:
  /// **'Enter an exercise name'**
  String get exCaloriesNeedName;

  /// No description provided for @exCaloriesCalculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get exCaloriesCalculating;

  /// No description provided for @exCaloriesFromCatalog.
  ///
  /// In en, this message translates to:
  /// **'Based on {activity} · uses your weight'**
  String exCaloriesFromCatalog(String activity);

  /// No description provided for @exCaloriesRoughEstimate.
  ///
  /// In en, this message translates to:
  /// **'A rough average for this exercise type'**
  String get exCaloriesRoughEstimate;

  /// No description provided for @exEnterDuration.
  ///
  /// In en, this message translates to:
  /// **'Please enter a duration'**
  String get exEnterDuration;

  /// No description provided for @exCannotEdit.
  ///
  /// In en, this message translates to:
  /// **'This record can\'t be edited'**
  String get exCannotEdit;

  /// No description provided for @exUpdated.
  ///
  /// In en, this message translates to:
  /// **'Exercise record updated'**
  String get exUpdated;

  /// No description provided for @exLogged.
  ///
  /// In en, this message translates to:
  /// **'Exercise logged'**
  String get exLogged;

  /// No description provided for @exOwnRecords.
  ///
  /// In en, this message translates to:
  /// **'Workouts you logged'**
  String get exOwnRecords;

  /// No description provided for @exOwnRecordsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No workouts logged yet'**
  String get exOwnRecordsEmpty;

  /// No description provided for @exOwnRecordSource.
  ///
  /// In en, this message translates to:
  /// **'Self-logged'**
  String get exOwnRecordSource;

  /// No description provided for @exCompletedPtDayTitle.
  ///
  /// In en, this message translates to:
  /// **'Completed PT'**
  String get exCompletedPtDayTitle;

  /// No description provided for @exCompletedRoutineDayTitle.
  ///
  /// In en, this message translates to:
  /// **'Completed solo workout'**
  String get exCompletedRoutineDayTitle;

  /// No description provided for @exPtDayFeedback.
  ///
  /// In en, this message translates to:
  /// **'{coachName} · Feedback'**
  String exPtDayFeedback(String coachName);

  /// No description provided for @exDeleteExercise.
  ///
  /// In en, this message translates to:
  /// **'Delete workout'**
  String get exDeleteExercise;

  /// No description provided for @exDeleteExerciseBody.
  ///
  /// In en, this message translates to:
  /// **'Deleting this record cannot be undone.'**
  String get exDeleteExerciseBody;

  /// No description provided for @exDeleted.
  ///
  /// In en, this message translates to:
  /// **'Workout deleted'**
  String get exDeleted;

  /// No description provided for @exDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete. Please try again in a moment'**
  String get exDeleteFailed;

  /// No description provided for @exCannotDelete.
  ///
  /// In en, this message translates to:
  /// **'This record cannot be deleted'**
  String get exCannotDelete;

  /// No description provided for @exSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Please try again in a moment'**
  String get exSaveFailed;

  /// No description provided for @exFindGym.
  ///
  /// In en, this message translates to:
  /// **'Find a Gym'**
  String get exFindGym;

  /// No description provided for @exFindTrainer.
  ///
  /// In en, this message translates to:
  /// **'Find a Trainer'**
  String get exFindTrainer;

  /// No description provided for @exGymDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Gym Details'**
  String get exGymDetailTitle;

  /// No description provided for @exTrainerDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Trainer Details'**
  String get exTrainerDetailTitle;

  /// No description provided for @exDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get exDistance;

  /// No description provided for @exRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get exRating;

  /// No description provided for @exAffiliatedTrainer.
  ///
  /// In en, this message translates to:
  /// **'Affiliated Trainer'**
  String get exAffiliatedTrainer;

  /// No description provided for @exRecommendationReason.
  ///
  /// In en, this message translates to:
  /// **'Why we recommend this trainer'**
  String get exRecommendationReason;

  /// No description provided for @exGymNotFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find this gym.'**
  String get exGymNotFound;

  /// No description provided for @exTrainerNotFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find this trainer.'**
  String get exTrainerNotFound;

  /// No description provided for @exGymSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search by area or gym name'**
  String get exGymSearchPlaceholder;

  /// No description provided for @exSortRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get exSortRecommended;

  /// No description provided for @exSortDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get exSortDistance;

  /// No description provided for @exSortRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get exSortRating;

  /// No description provided for @exResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result} other{{count} results}}'**
  String exResultCount(int count);

  /// No description provided for @exNoSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No search results.'**
  String get exNoSearchResults;

  /// No description provided for @exTrainersLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load trainers.'**
  String get exTrainersLoadError;

  /// No description provided for @exGymSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by gym or area'**
  String get exGymSearchHint;

  /// No description provided for @exNearbyGyms.
  ///
  /// In en, this message translates to:
  /// **'Nearby gyms'**
  String get exNearbyGyms;

  /// Hides the gym result list so the map fills the space
  ///
  /// In en, this message translates to:
  /// **'Collapse list'**
  String get exGymListCollapse;

  /// Brings the gym result list back under the map
  ///
  /// In en, this message translates to:
  /// **'Expand list'**
  String get exGymListExpand;

  /// No description provided for @exAiAnalysis.
  ///
  /// In en, this message translates to:
  /// **'✦ AI analysis'**
  String get exAiAnalysis;

  /// No description provided for @exNoGymMatch.
  ///
  /// In en, this message translates to:
  /// **'No gyms match \'{query}\''**
  String exNoGymMatch(String query);

  /// No description provided for @exGymsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load gyms.'**
  String get exGymsLoadError;

  /// No description provided for @exAiTopPick.
  ///
  /// In en, this message translates to:
  /// **'✦ AI top pick'**
  String get exAiTopPick;

  /// No description provided for @exGymDetailHint.
  ///
  /// In en, this message translates to:
  /// **'See trainers and request a consultation'**
  String get exGymDetailHint;

  /// No description provided for @exReasonTrainer.
  ///
  /// In en, this message translates to:
  /// **'Personal trainer {name}{role} on site'**
  String exReasonTrainer(String name, String role);

  /// No description provided for @exReasonHours.
  ///
  /// In en, this message translates to:
  /// **'Open {hours}{weekend}'**
  String exReasonHours(String hours, String weekend);

  /// No description provided for @exGymWeekdayHours.
  ///
  /// In en, this message translates to:
  /// **'Weekdays {hours}'**
  String exGymWeekdayHours(String hours);

  /// No description provided for @exGymWeekendHours.
  ///
  /// In en, this message translates to:
  /// **'Weekends {hours}'**
  String exGymWeekendHours(String hours);

  /// No description provided for @exTrainerDedicated.
  ///
  /// In en, this message translates to:
  /// **'Personal trainer'**
  String get exTrainerDedicated;

  /// No description provided for @exTrainerAvailability.
  ///
  /// In en, this message translates to:
  /// **'{trainer}\'s open booking times'**
  String exTrainerAvailability(String trainer);

  /// No description provided for @exSlotWhen.
  ///
  /// In en, this message translates to:
  /// **'{date} {time}'**
  String exSlotWhen(String date, String time);

  /// No description provided for @exSlotFull.
  ///
  /// In en, this message translates to:
  /// **'Fully booked'**
  String get exSlotFull;

  /// No description provided for @exSlotTypePersonalTraining.
  ///
  /// In en, this message translates to:
  /// **'1:1 PT'**
  String get exSlotTypePersonalTraining;

  /// No description provided for @exSlotTypeConsultation.
  ///
  /// In en, this message translates to:
  /// **'Consultation'**
  String get exSlotTypeConsultation;

  /// No description provided for @exSlotsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No times available'**
  String get exSlotsEmpty;

  /// No description provided for @exSlotsAllBooked.
  ///
  /// In en, this message translates to:
  /// **'All available times are fully booked'**
  String get exSlotsAllBooked;

  /// No description provided for @exSlotsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load available times.'**
  String get exSlotsLoadError;

  /// No description provided for @exReserveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not book that time. Please try again.'**
  String get exReserveFailed;

  /// No description provided for @exReserveConfirmedSlotGym.
  ///
  /// In en, this message translates to:
  /// **'{slot} · {gym} reservation confirmed'**
  String exReserveConfirmedSlotGym(String slot, String gym);

  /// No description provided for @exReserveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm {slot}'**
  String exReserveConfirm(String slot);

  /// No description provided for @exGymInfo.
  ///
  /// In en, this message translates to:
  /// **'Gym Info'**
  String get exGymInfo;

  /// No description provided for @exConsultButton.
  ///
  /// In en, this message translates to:
  /// **'💬 1:1 Consult'**
  String get exConsultButton;

  /// No description provided for @exAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get exAddress;

  /// No description provided for @exHours.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get exHours;

  /// No description provided for @exPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get exPhone;

  /// No description provided for @exSpecialty.
  ///
  /// In en, this message translates to:
  /// **'Specialties'**
  String get exSpecialty;

  /// No description provided for @exKakaoMapArea.
  ///
  /// In en, this message translates to:
  /// **'Kakao Map area'**
  String get exKakaoMapArea;

  /// No description provided for @myTabTitle.
  ///
  /// In en, this message translates to:
  /// **'MY'**
  String get myTabTitle;

  /// No description provided for @myDefaultUserName.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get myDefaultUserName;

  /// No description provided for @mySettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get mySettingsTitle;

  /// No description provided for @myProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get myProfileTitle;

  /// No description provided for @myNotifTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get myNotifTitle;

  /// MY tab: opens the spotlight app guide again (#1857).
  ///
  /// In en, this message translates to:
  /// **'Replay the app guide'**
  String get myGuideTitle;

  /// No description provided for @mySupportTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer Support'**
  String get mySupportTitle;

  /// No description provided for @myPointsBenefitsTitle.
  ///
  /// In en, this message translates to:
  /// **'Use Points'**
  String get myPointsBenefitsTitle;

  /// No description provided for @myPointsBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance: {points}P'**
  String myPointsBalance(int points);

  /// No description provided for @myPointsBenefitsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Benefits available with points'**
  String get myPointsBenefitsSubtitle;

  /// No description provided for @myPointsBenefitsHint.
  ///
  /// In en, this message translates to:
  /// **'Keep logging your activity to earn points and use the benefits above.'**
  String get myPointsBenefitsHint;

  /// No description provided for @myPointsDiscountTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash discount with points'**
  String get myPointsDiscountTitle;

  /// No description provided for @myPointsDiscountDescription.
  ///
  /// In en, this message translates to:
  /// **'Use points like cash for up to 10% off 1:1 coaching and personal training.'**
  String get myPointsDiscountDescription;

  /// No description provided for @myPointsDiscountCost.
  ///
  /// In en, this message translates to:
  /// **'Up to 10%'**
  String get myPointsDiscountCost;

  /// No description provided for @myPointsReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock glucose and blood pressure reports'**
  String get myPointsReportTitle;

  /// No description provided for @myPointsReportDescription.
  ///
  /// In en, this message translates to:
  /// **'View comprehensive weekly and monthly health-data reports.'**
  String get myPointsReportDescription;

  /// No description provided for @myPointsReportCost.
  ///
  /// In en, this message translates to:
  /// **'500P'**
  String get myPointsReportCost;

  /// No description provided for @myPointsRecipeTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalized healthy recipe package'**
  String get myPointsRecipeTitle;

  /// No description provided for @myPointsRecipeDescription.
  ///
  /// In en, this message translates to:
  /// **'Get PDF and interactive meal guides tailored to goals such as diabetes prevention or weight loss.'**
  String get myPointsRecipeDescription;

  /// No description provided for @myPointsRecipeCost.
  ///
  /// In en, this message translates to:
  /// **'500P'**
  String get myPointsRecipeCost;

  /// Screen reader label for an image a trainer sent in chat (#1942).
  ///
  /// In en, this message translates to:
  /// **'Photo from your trainer'**
  String get a11yCoachPhoto;

  /// Screen reader label for a saved meal photo (#1942).
  ///
  /// In en, this message translates to:
  /// **'Meal photo'**
  String get a11yMealPhoto;

  /// Screen reader label for a recommended meal photo (#1942).
  ///
  /// In en, this message translates to:
  /// **'Photo of {name}'**
  String a11yMealPhotoOf(String name);

  /// No description provided for @myLogout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get myLogout;

  /// No description provided for @myLogoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Log out of your account?'**
  String get myLogoutConfirm;

  /// Account deletion entry at the end of the MY settings list (#1935).
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get myWithdrawTitle;

  /// No description provided for @myWithdrawConfirm.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account erases the diet, exercise and health records you saved, and removes your trainer link and the messages you exchanged. This cannot be undone.'**
  String get myWithdrawConfirm;

  /// No description provided for @myWithdrawAction.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get myWithdrawAction;

  /// No description provided for @myWithdrawFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not delete your account. Please try again in a moment.'**
  String get myWithdrawFailed;

  /// First step of the two-step account deletion flow under customer support (#2019).
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete your account?'**
  String get myWithdrawReasonTitle;

  /// No description provided for @myWithdrawReasonQuestion.
  ///
  /// In en, this message translates to:
  /// **'What did not work for you?'**
  String get myWithdrawReasonQuestion;

  /// No description provided for @myWithdrawReasonHint.
  ///
  /// In en, this message translates to:
  /// **'You can pick more than one'**
  String get myWithdrawReasonHint;

  /// No description provided for @myWithdrawReasonPrivacy.
  ///
  /// In en, this message translates to:
  /// **'I am worried about my privacy'**
  String get myWithdrawReasonPrivacy;

  /// No description provided for @myWithdrawReasonRarelyUsed.
  ///
  /// In en, this message translates to:
  /// **'I hardly use it any more'**
  String get myWithdrawReasonRarelyUsed;

  /// No description provided for @myWithdrawReasonHardToUse.
  ///
  /// In en, this message translates to:
  /// **'It is awkward to use'**
  String get myWithdrawReasonHardToUse;

  /// No description provided for @myWithdrawReasonNotifications.
  ///
  /// In en, this message translates to:
  /// **'Too many notifications'**
  String get myWithdrawReasonNotifications;

  /// No description provided for @myWithdrawReasonAlternative.
  ///
  /// In en, this message translates to:
  /// **'I am using another app'**
  String get myWithdrawReasonAlternative;

  /// No description provided for @myWithdrawReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get myWithdrawReasonOther;

  /// No description provided for @myWithdrawNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get myWithdrawNext;

  /// Second step: what can be changed instead of leaving, chosen from the reasons picked (#2019).
  ///
  /// In en, this message translates to:
  /// **'Before you go'**
  String get myWithdrawKeepTitle;

  /// No description provided for @myWithdrawKeepPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Only you and your trainer can see your records. Disconnect the trainer and they are yours alone — the gym and trainer card on the MY tab does that.'**
  String get myWithdrawKeepPrivacy;

  /// No description provided for @myWithdrawKeepRarelyUsed.
  ///
  /// In en, this message translates to:
  /// **'The AI coach still lines up something worth doing on the days you record nothing. Tapping a single suggestion on the Exercise tab is enough to pick it back up.'**
  String get myWithdrawKeepRarelyUsed;

  /// No description provided for @myWithdrawKeepHardToUse.
  ///
  /// In en, this message translates to:
  /// **'Tell us what got in the way and we will fix it. The 1:1 enquiry under MY > Customer support reaches us directly.'**
  String get myWithdrawKeepHardToUse;

  /// No description provided for @myWithdrawKeepNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications can be switched off one kind at a time. Keep only what you want under MY > Notification settings.'**
  String get myWithdrawKeepNotifications;

  /// No description provided for @myWithdrawKeepAlternative.
  ///
  /// In en, this message translates to:
  /// **'Removing the app leaves your records untouched. Deleting the account is what erases them, and that cannot be undone.'**
  String get myWithdrawKeepAlternative;

  /// No description provided for @myWithdrawKeepOther.
  ///
  /// In en, this message translates to:
  /// **'Whatever it is, tell us and we will act on it. Leave it in the 1:1 enquiry under MY > Customer support.'**
  String get myWithdrawKeepOther;

  /// No description provided for @myWithdrawKeepDefault.
  ///
  /// In en, this message translates to:
  /// **'The diet and exercise records you have built up go with the account, and they cannot be restored.'**
  String get myWithdrawKeepDefault;

  /// No description provided for @myWithdrawStay.
  ///
  /// In en, this message translates to:
  /// **'Keep using On-Care'**
  String get myWithdrawStay;

  /// No description provided for @myWithdrawContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue deleting'**
  String get myWithdrawContinue;

  /// No description provided for @myCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get myCancel;

  /// No description provided for @myGymTrainerTitle.
  ///
  /// In en, this message translates to:
  /// **'My Gym & Trainer'**
  String get myGymTrainerTitle;

  /// No description provided for @myConnectionDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Connection'**
  String get myConnectionDeleteTitle;

  /// No description provided for @myDelete.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get myDelete;

  /// No description provided for @myGymDisconnectWithTrainerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Disconnect {gym}?\nYour trainer link with {trainer} will also be removed.'**
  String myGymDisconnectWithTrainerConfirm(String gym, String trainer);

  /// No description provided for @myGymDisconnectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Disconnect {gym}?'**
  String myGymDisconnectConfirm(String gym);

  /// No description provided for @myTrainerDisconnectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Disconnect trainer {trainer}?\nYour connection to {gym} will remain.'**
  String myTrainerDisconnectConfirm(String trainer, String gym);

  /// No description provided for @myGymDetailTooltip.
  ///
  /// In en, this message translates to:
  /// **'Gym details'**
  String get myGymDetailTooltip;

  /// No description provided for @myTrainerDetailTooltip.
  ///
  /// In en, this message translates to:
  /// **'Trainer details'**
  String get myTrainerDetailTooltip;

  /// No description provided for @myGymDisconnectTooltip.
  ///
  /// In en, this message translates to:
  /// **'Disconnect gym'**
  String get myGymDisconnectTooltip;

  /// No description provided for @myTrainerDisconnectTooltip.
  ///
  /// In en, this message translates to:
  /// **'Disconnect trainer'**
  String get myTrainerDisconnectTooltip;

  /// No description provided for @myNoTrainer.
  ///
  /// In en, this message translates to:
  /// **'No assigned trainer'**
  String get myNoTrainer;

  /// No description provided for @myNoGymConnected.
  ///
  /// In en, this message translates to:
  /// **'No gym connected yet'**
  String get myNoGymConnected;

  /// No description provided for @myGymLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your gym connection.'**
  String get myGymLoadFailed;

  /// No description provided for @mySave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get mySave;

  /// No description provided for @myProfileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved'**
  String get myProfileSaved;

  /// No description provided for @mySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Please try again in a moment'**
  String get mySaveFailed;

  /// No description provided for @myFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get myFieldName;

  /// No description provided for @myFieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get myFieldEmail;

  /// No description provided for @myFieldPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get myFieldPhone;

  /// No description provided for @myFieldBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get myFieldBirth;

  /// No description provided for @myFieldGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get myFieldGender;

  /// No description provided for @myFieldHeight.
  ///
  /// In en, this message translates to:
  /// **'Height (cm)'**
  String get myFieldHeight;

  /// No description provided for @myFieldWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get myFieldWeight;

  /// No description provided for @myFieldGoals.
  ///
  /// In en, this message translates to:
  /// **'Health and exercise goals'**
  String get myFieldGoals;

  /// No description provided for @myNotifDietLog.
  ///
  /// In en, this message translates to:
  /// **'Diet log reminder'**
  String get myNotifDietLog;

  /// No description provided for @myNotifExercise.
  ///
  /// In en, this message translates to:
  /// **'Exercise reminder'**
  String get myNotifExercise;

  /// No description provided for @myNotifTrainer.
  ///
  /// In en, this message translates to:
  /// **'Trainer message'**
  String get myNotifTrainer;

  /// No description provided for @myNotifAiCoaching.
  ///
  /// In en, this message translates to:
  /// **'AI coaching tips'**
  String get myNotifAiCoaching;

  /// No description provided for @myNotifWeeklyReport.
  ///
  /// In en, this message translates to:
  /// **'Weekly report'**
  String get myNotifWeeklyReport;

  /// No description provided for @mySupportFaq.
  ///
  /// In en, this message translates to:
  /// **'FAQ'**
  String get mySupportFaq;

  /// No description provided for @mySupportInquiry.
  ///
  /// In en, this message translates to:
  /// **'1:1 Inquiry'**
  String get mySupportInquiry;

  /// No description provided for @myLegalTermsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get myLegalTermsTitle;

  /// No description provided for @myLegalPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get myLegalPrivacyTitle;

  /// No description provided for @myLegalTermsBody.
  ///
  /// In en, this message translates to:
  /// **'Article 1 (Purpose)\nThese Terms govern the rights, obligations and responsibilities between On-Care (the \"Company\") and its members in connection with the use of the health management service (the \"Service\") the Company provides.\n\nArticle 2 (Effect and Amendment of the Terms)\n(1) These Terms apply to every member who uses the Service.\n(2) The Company may amend these Terms within the limits of applicable law. Any amendment is announced inside the Service together with its effective date and the reason for the change.\n\nArticle 3 (Provision of the Service)\nThe Company provides features that support a member\'s health management, including diet records, exercise records, health indicator tracking and AI coaching. The specific contents of the Service may change in line with the Company\'s policy.\n\nArticle 4 (Obligations of the Member)\nMembers must enter their own health information accurately. Information provided by the Service does not replace a medical diagnosis or treatment. If you have a health problem, please consult a qualified medical institution.\n\nArticle 5 (Limitation of Liability)\nTo the extent permitted by law, the Company is not liable for decisions a member makes on the basis of information obtained through the Service, nor for the consequences of those decisions.\n\nAddendum\nThese Terms take effect on 1 January 2026.\n\nThis is a translation of the Korean original for reference. In case of any discrepancy, the Korean version governs.'**
  String get myLegalTermsBody;

  /// No description provided for @myLegalPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'On-Care (the \"Company\") complies with the Personal Information Protection Act and other applicable laws, and protects its members\' personal information with care.\n\n1. Personal information collected\nFor membership registration and provision of the Service, the Company collects your name, email address, phone number and date of birth, together with health-related information such as diet, exercise and health indicators.\n\n2. Purpose of collection and use\nThe personal information collected is used only to identify members, provide health management features, deliver personalised AI coaching, improve the Service and respond to customer enquiries.\n\n3. Retention and use period\nAs a rule, a member\'s personal information is destroyed without delay when the member withdraws from the Service. Where applicable law requires it to be retained, it is stored securely for the period the law prescribes.\n\n4. Provision to third parties\nThe Company does not provide personal information to any third party without the member\'s consent, except where a law specifically provides otherwise.\n\n5. Rights of the user\nMembers may at any time view or correct their personal information, or request that its processing be suspended and the information deleted.\n\n6. Personal information protection officer\nFor enquiries about personal information, please contact customer support (support@oncare.com).\n\nEffective date: 1 January 2026\n\nThis is a translation of the Korean original for reference. In case of any discrepancy, the Korean version governs.'**
  String get myLegalPrivacyBody;

  /// No description provided for @myLegalEffectiveDate.
  ///
  /// In en, this message translates to:
  /// **'Effective Jan 1, 2026'**
  String get myLegalEffectiveDate;

  /// No description provided for @myAppVersion.
  ///
  /// In en, this message translates to:
  /// **'On-Care · Version 1.0.0'**
  String get myAppVersion;

  /// No description provided for @coachHeaderPill.
  ///
  /// In en, this message translates to:
  /// **'AI Health Assistant'**
  String get coachHeaderPill;

  /// No description provided for @coachHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Here are today\'s tailored tips'**
  String get coachHeaderSubtitle;

  /// No description provided for @coachCardDietTag.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get coachCardDietTag;

  /// No description provided for @coachCardDietTitle.
  ///
  /// In en, this message translates to:
  /// **'Great breakfast — watch lunch sodium'**
  String get coachCardDietTitle;

  /// No description provided for @coachCardDietBody.
  ///
  /// In en, this message translates to:
  /// **'Breakfast was nicely balanced. The jjamppong you had for lunch can be heavy on sodium and sugar, so drink plenty of water today. For the rest of the day, pair vegetables with protein to keep things balanced.'**
  String get coachCardDietBody;

  /// No description provided for @coachCardExerciseTag.
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get coachCardExerciseTag;

  /// No description provided for @coachCardExerciseTitle.
  ///
  /// In en, this message translates to:
  /// **'3 workouts this week'**
  String get coachCardExerciseTitle;

  /// No description provided for @coachCardExerciseBody.
  ///
  /// In en, this message translates to:
  /// **'You finished three workouts this week — staying consistent is what counts. Take your time with the rotator-cuff shoulder stretches and wind down with light cardio. Afterwards, rest and rehydrate rather than pushing on.'**
  String get coachCardExerciseBody;

  /// No description provided for @coachCardWaterTag.
  ///
  /// In en, this message translates to:
  /// **'Hydration'**
  String get coachCardWaterTag;

  /// No description provided for @coachInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'A trainer wants to coach you'**
  String get coachInviteTitle;

  /// No description provided for @coachInviteFrom.
  ///
  /// In en, this message translates to:
  /// **'Trainer {name}'**
  String coachInviteFrom(String name);

  /// No description provided for @coachInviteGym.
  ///
  /// In en, this message translates to:
  /// **'at {gym}'**
  String coachInviteGym(String gym);

  /// No description provided for @coachInviteExplain.
  ///
  /// In en, this message translates to:
  /// **'Accepting lets this trainer see your meal and workout records.'**
  String get coachInviteExplain;

  /// No description provided for @coachInviteAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get coachInviteAccept;

  /// No description provided for @coachInviteReject.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get coachInviteReject;

  /// No description provided for @coachInviteAccepted.
  ///
  /// In en, this message translates to:
  /// **'{name} is now your coach'**
  String coachInviteAccepted(String name);

  /// No description provided for @coachInviteRejected.
  ///
  /// In en, this message translates to:
  /// **'Request declined'**
  String get coachInviteRejected;

  /// No description provided for @coachInviteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete that. Please try again'**
  String get coachInviteFailed;

  /// No description provided for @coachImageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the photo'**
  String get coachImageUnavailable;

  /// No description provided for @coachChatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Personal trainer · Available'**
  String get coachChatSubtitle;

  /// No description provided for @coachChatBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get coachChatBack;

  /// Button above the trainer chat thread that fetches the previous page (#1943).
  ///
  /// In en, this message translates to:
  /// **'Load older messages'**
  String get coachChatLoadOlder;

  /// No description provided for @coachChatLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the conversation'**
  String get coachChatLoadFailed;

  /// No description provided for @coachChatSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send your message. Please try again'**
  String get coachChatSendFailed;

  /// No description provided for @coachChatPdfOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the PDF. Please try again'**
  String get coachChatPdfOpenFailed;

  /// No description provided for @coachChatReportRegistered.
  ///
  /// In en, this message translates to:
  /// **'Weekly report added'**
  String get coachChatReportRegistered;

  /// Week the registered report covers, shown on the report card.
  ///
  /// In en, this message translates to:
  /// **'{sm}/{sd} – {em}/{ed}'**
  String coachChatReportWeek(int sm, int sd, int em, int ed);

  /// No description provided for @coachChatReportOpenPdf.
  ///
  /// In en, this message translates to:
  /// **'Open PDF'**
  String get coachChatReportOpenPdf;

  /// No description provided for @coachChatReportPreviewPdf.
  ///
  /// In en, this message translates to:
  /// **'Preview PDF'**
  String get coachChatReportPreviewPdf;

  /// No description provided for @coachReportPdfDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly report'**
  String get coachReportPdfDocTitle;

  /// No description provided for @coachReportPdfDocTitleContinued.
  ///
  /// In en, this message translates to:
  /// **'Weekly report (cont.)'**
  String get coachReportPdfDocTitleContinued;

  /// Week the previewed report covers, printed under the title.
  ///
  /// In en, this message translates to:
  /// **'Period {from} – {to}'**
  String coachReportPdfPeriod(String from, String to);

  /// No description provided for @coachReportPdfSectionMetrics.
  ///
  /// In en, this message translates to:
  /// **'Key metrics'**
  String get coachReportPdfSectionMetrics;

  /// No description provided for @coachReportPdfSectionTrend.
  ///
  /// In en, this message translates to:
  /// **'Daily trend'**
  String get coachReportPdfSectionTrend;

  /// No description provided for @coachReportPdfSectionDaily.
  ///
  /// In en, this message translates to:
  /// **'Day by day'**
  String get coachReportPdfSectionDaily;

  /// One metric line in the previewed report.
  ///
  /// In en, this message translates to:
  /// **'· {label}: {value}'**
  String coachReportPdfBullet(String label, String value);

  /// No description provided for @coachReportPdfLabelWorkoutDays.
  ///
  /// In en, this message translates to:
  /// **'Days trained'**
  String get coachReportPdfLabelWorkoutDays;

  /// No description provided for @coachReportPdfLabelWorkoutMinutes.
  ///
  /// In en, this message translates to:
  /// **'Total workout time'**
  String get coachReportPdfLabelWorkoutMinutes;

  /// No description provided for @coachReportPdfLabelBurned.
  ///
  /// In en, this message translates to:
  /// **'Calories burned'**
  String get coachReportPdfLabelBurned;

  /// No description provided for @coachReportPdfLabelSessions.
  ///
  /// In en, this message translates to:
  /// **'PT sessions'**
  String get coachReportPdfLabelSessions;

  /// No description provided for @coachReportPdfLabelCalories.
  ///
  /// In en, this message translates to:
  /// **'Average intake'**
  String get coachReportPdfLabelCalories;

  /// No description provided for @coachReportPdfLabelSodium.
  ///
  /// In en, this message translates to:
  /// **'Average sodium'**
  String get coachReportPdfLabelSodium;

  /// No description provided for @coachReportPdfLabelSugar.
  ///
  /// In en, this message translates to:
  /// **'Average sugar'**
  String get coachReportPdfLabelSugar;

  /// No description provided for @coachReportPdfLabelMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'Workout time'**
  String get coachReportPdfLabelMinutesShort;

  /// No description provided for @coachReportPdfLabelCaloriesShort.
  ///
  /// In en, this message translates to:
  /// **'Intake'**
  String get coachReportPdfLabelCaloriesShort;

  /// No description provided for @coachReportPdfLabelSodiumShort.
  ///
  /// In en, this message translates to:
  /// **'Sodium'**
  String get coachReportPdfLabelSodiumShort;

  /// No description provided for @coachReportPdfLabelSugarShort.
  ///
  /// In en, this message translates to:
  /// **'Sugar'**
  String get coachReportPdfLabelSugarShort;

  /// No description provided for @coachReportPdfValueDays.
  ///
  /// In en, this message translates to:
  /// **'{value} days'**
  String coachReportPdfValueDays(String value);

  /// No description provided for @coachReportPdfValueMinutes.
  ///
  /// In en, this message translates to:
  /// **'{value} min'**
  String coachReportPdfValueMinutes(String value);

  /// No description provided for @coachReportPdfValueKcal.
  ///
  /// In en, this message translates to:
  /// **'{value} kcal'**
  String coachReportPdfValueKcal(String value);

  /// No description provided for @coachReportPdfValueMg.
  ///
  /// In en, this message translates to:
  /// **'{value} mg'**
  String coachReportPdfValueMg(String value);

  /// No description provided for @coachReportPdfValueGram.
  ///
  /// In en, this message translates to:
  /// **'{value} g'**
  String coachReportPdfValueGram(String value);

  /// PT sessions completed out of the ones booked that week.
  ///
  /// In en, this message translates to:
  /// **'{done} of {booked}'**
  String coachReportPdfAttendance(String done, String booked);

  /// No description provided for @coachReportPdfNoData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get coachReportPdfNoData;

  /// One weekday line in the previewed report.
  ///
  /// In en, this message translates to:
  /// **'{weekday} — workout {exercise}, intake {intake}'**
  String coachReportPdfDay(String weekday, String exercise, String intake);

  /// Section heading for the message the trainer sent with the report.
  ///
  /// In en, this message translates to:
  /// **'From your trainer'**
  String get coachReportPdfSectionTrainerNote;

  /// Shown under the trainer-message heading when the report arrived without a note.
  ///
  /// In en, this message translates to:
  /// **'No message came with this report.'**
  String get coachReportPdfNoTrainerNote;

  /// Section heading comparing this week with the previous one.
  ///
  /// In en, this message translates to:
  /// **'Change from last week'**
  String get coachReportPdfSectionChange;

  /// Section heading for average carbs / protein / fat.
  ///
  /// In en, this message translates to:
  /// **'Average macros'**
  String get coachReportPdfSectionMacros;

  /// Metric label: how many days of the week have diet records.
  ///
  /// In en, this message translates to:
  /// **'Days with meals logged'**
  String get coachReportPdfLabelLoggedDays;

  /// Metric label: days whose sodium exceeded the member's daily goal.
  ///
  /// In en, this message translates to:
  /// **'Days over the sodium goal'**
  String get coachReportPdfLabelSodiumOver;

  /// Metric label used when only completed PT sessions are known.
  ///
  /// In en, this message translates to:
  /// **'PT sessions done'**
  String get coachReportPdfLabelPtDone;

  /// A count of PT sessions with its unit.
  ///
  /// In en, this message translates to:
  /// **'{value} sessions'**
  String coachReportPdfValueSessions(String value);

  /// Metric label for cardio minutes.
  ///
  /// In en, this message translates to:
  /// **'Cardio'**
  String get coachReportPdfLabelCardio;

  /// Metric label for strength minutes.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get coachReportPdfLabelStrength;

  /// Metric label for stretching minutes.
  ///
  /// In en, this message translates to:
  /// **'Stretching'**
  String get coachReportPdfLabelStretching;

  /// Section heading breaking the week's minutes down by workout type.
  ///
  /// In en, this message translates to:
  /// **'Minutes by workout type'**
  String get coachReportPdfSectionTypes;

  /// Shown for PT when nothing was booked and nothing was recorded.
  ///
  /// In en, this message translates to:
  /// **'None booked'**
  String get coachReportPdfNoSessions;

  /// Header band cell title for the reported week.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get coachReportPdfBandPeriod;

  /// Section heading for the goal gauges.
  ///
  /// In en, this message translates to:
  /// **'Against your goals'**
  String get coachReportPdfSectionGoals;

  /// Summary table column: the metric name.
  ///
  /// In en, this message translates to:
  /// **'Metric'**
  String get coachReportPdfColumnMetric;

  /// Summary table column: this week's value.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get coachReportPdfColumnThisWeek;

  /// Summary table column: last week's value.
  ///
  /// In en, this message translates to:
  /// **'Last week'**
  String get coachReportPdfColumnLastWeek;

  /// Summary table column: the difference between the two weeks.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get coachReportPdfColumnChange;

  /// Daily table column: the weekday.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get coachReportPdfColumnWeekday;

  /// Daily table column: what was done that day.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get coachReportPdfColumnWorkout;

  /// Daily table column: calories eaten that day.
  ///
  /// In en, this message translates to:
  /// **'Intake'**
  String get coachReportPdfColumnIntake;

  /// Daily table cell for a weekday that has not happened yet.
  ///
  /// In en, this message translates to:
  /// **'Still to come'**
  String get coachReportPdfUpcoming;

  /// Text form of a gauge: the value and the goal it is measured against.
  ///
  /// In en, this message translates to:
  /// **'{value} (goal {target})'**
  String coachReportPdfGoalOf(String value, String target);

  /// Label on a chart's dashed goal line.
  ///
  /// In en, this message translates to:
  /// **'goal {value}'**
  String coachReportPdfChartTarget(String value);

  /// Daily line for a weekday that has not happened yet.
  ///
  /// In en, this message translates to:
  /// **'{weekday} — still to come'**
  String coachReportPdfDayUpcoming(String weekday);

  /// One comparison line: this week's value, last week's, and the difference.
  ///
  /// In en, this message translates to:
  /// **'· {label}: {current} (last week {previous}, {delta})'**
  String coachReportPdfChange(
    String label,
    String current,
    String previous,
    String delta,
  );

  /// Difference when this week is higher.
  ///
  /// In en, this message translates to:
  /// **'+{value}'**
  String coachReportPdfDeltaUp(String value);

  /// Difference when this week is lower.
  ///
  /// In en, this message translates to:
  /// **'-{value}'**
  String coachReportPdfDeltaDown(String value);

  /// Difference when both weeks are equal.
  ///
  /// In en, this message translates to:
  /// **'no change'**
  String get coachReportPdfDeltaSame;

  /// Shown under the comparison heading when the previous week has nothing.
  ///
  /// In en, this message translates to:
  /// **'There are no records from last week to compare with.'**
  String get coachReportPdfNoPreviousWeek;

  /// Footnote naming the sodium goal the over-days count was measured against.
  ///
  /// In en, this message translates to:
  /// **'The sodium goal is the {target}mg daily target you set on the MY screen.'**
  String coachReportPdfSodiumTargetNote(String target);

  /// No description provided for @coachReportPdfPreviewNote.
  ///
  /// In en, this message translates to:
  /// **'Built from your own records for the week the trainer\'s report covers.'**
  String get coachReportPdfPreviewNote;

  /// No description provided for @coachReportPdfFileName.
  ///
  /// In en, this message translates to:
  /// **'weekly-report_{date}.pdf'**
  String coachReportPdfFileName(String date);

  /// No description provided for @coachChatInputHint.
  ///
  /// In en, this message translates to:
  /// **'Message your trainer...'**
  String get coachChatInputHint;

  /// No description provided for @coachChatDemoAnalyzed.
  ///
  /// In en, this message translates to:
  /// **'AI analyzed your diet and exercise data'**
  String get coachChatDemoAnalyzed;

  /// No description provided for @coachChatDemoReportSent.
  ///
  /// In en, this message translates to:
  /// **'A summary report was sent to {trainer}'**
  String coachChatDemoReportSent(String trainer);

  /// No description provided for @coachChatDemoRoutineReceived.
  ///
  /// In en, this message translates to:
  /// **'You received a personalized workout recommendation'**
  String get coachChatDemoRoutineReceived;

  /// No description provided for @coachChatDemoNotified.
  ///
  /// In en, this message translates to:
  /// **'It was also delivered as a notification'**
  String get coachChatDemoNotified;

  /// Chat date divider with full date and weekday.
  ///
  /// In en, this message translates to:
  /// **'{date}'**
  String coachChatDateDivider(DateTime date);

  /// No description provided for @coachCtaChat.
  ///
  /// In en, this message translates to:
  /// **'Chat with AI'**
  String get coachCtaChat;

  /// No description provided for @navAddRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a record'**
  String get navAddRecordTitle;

  /// No description provided for @navAddRecordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose diet or exercise'**
  String get navAddRecordSubtitle;

  /// No description provided for @navDietOptionSub.
  ///
  /// In en, this message translates to:
  /// **'Nutrition analysis from a photo'**
  String get navDietOptionSub;

  /// No description provided for @navExerciseOptionSub.
  ///
  /// In en, this message translates to:
  /// **'Log the type and duration'**
  String get navExerciseOptionSub;

  /// No description provided for @aicHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ask me anytime'**
  String get aicHeaderSubtitle;

  /// No description provided for @aicDatePillToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get aicDatePillToday;

  /// No description provided for @aicMedicalDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'The AI coach is a reference for diet and exercise habits, not a diagnosis or prescription. Please consult a doctor about symptoms.'**
  String get aicMedicalDisclaimer;

  /// No description provided for @aicInputHint.
  ///
  /// In en, this message translates to:
  /// **'Ask the AI anything'**
  String get aicInputHint;

  /// No description provided for @aicQuickRepliesLabel.
  ///
  /// In en, this message translates to:
  /// **'Try asking'**
  String get aicQuickRepliesLabel;

  /// Shown in the coach bubble while a tailored reply is being generated
  ///
  /// In en, this message translates to:
  /// **'Writing your answer'**
  String get aicGeneratingReply;

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In en, this message translates to:
  /// **'{part} pain noted'**
  String aicInsightDiscomfortPart(String part);

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In en, this message translates to:
  /// **'Pain noted'**
  String get aicInsightDiscomfort;

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In en, this message translates to:
  /// **'Negative feedback noted'**
  String get aicInsightNegative;

  /// Removes one detection from the AI coach insight log (#1975).
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get aicInsightDelete;

  /// No description provided for @aicInsightDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this detection from the log? What you wrote stays in the conversation.'**
  String get aicInsightDeleteConfirm;

  /// No description provided for @aicInsightDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not remove it. Please try again in a moment.'**
  String get aicInsightDeleteFailed;

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In en, this message translates to:
  /// **'Noted signals'**
  String get aicInsightHistoryTitle;

  /// AI coach chat: header button that opens the noted-signals list; short because it sits beside the title (#1900).
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get aicInsightHistoryAction;

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In en, this message translates to:
  /// **'Pain and negative feedback noted in the last {days} days. The AI uses these when it answers'**
  String aicInsightHistorySubtitle(int days);

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In en, this message translates to:
  /// **'Nothing noted in the last {days} days'**
  String aicInsightHistoryEmpty(int days);

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load noted signals'**
  String get aicInsightHistoryFailed;

  /// AI coach chat: how long the conversation is kept (#1823).
  ///
  /// In en, this message translates to:
  /// **'AI chat history is kept for the last {days} days'**
  String aicRetentionNotice(int days);

  /// AI coach chat: shown instead of the chat when the member has a trainer (#1823).
  ///
  /// In en, this message translates to:
  /// **'Chat with your trainer'**
  String get aicTrainerConnectedTitle;

  /// AI coach chat: shown instead of the chat when the member has a trainer (#1823).
  ///
  /// In en, this message translates to:
  /// **'You\'re connected with {name}. Members with a trainer chat with their trainer instead of the AI chatbot'**
  String aicTrainerConnectedBody(String name);

  /// No description provided for @aicQuickReply1.
  ///
  /// In en, this message translates to:
  /// **'Recommend a dinner menu for today'**
  String get aicQuickReply1;

  /// No description provided for @aicQuickReply2.
  ///
  /// In en, this message translates to:
  /// **'How much should I exercise today?'**
  String get aicQuickReply2;

  /// No description provided for @aicQuickReply3.
  ///
  /// In en, this message translates to:
  /// **'How much sodium have I had today?'**
  String get aicQuickReply3;

  /// No description provided for @exConsultRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Consultation Request'**
  String get exConsultRequestTitle;

  /// No description provided for @exGymConsultRequest.
  ///
  /// In en, this message translates to:
  /// **'Request a Consultation'**
  String get exGymConsultRequest;

  /// No description provided for @exGymConsultPickTrainer.
  ///
  /// In en, this message translates to:
  /// **'Choose a trainer'**
  String get exGymConsultPickTrainer;

  /// No description provided for @exGymConsultPickTrainerHint.
  ///
  /// In en, this message translates to:
  /// **'Your request goes to one trainer.'**
  String get exGymConsultPickTrainerHint;

  /// No description provided for @exGymConsultNoTrainers.
  ///
  /// In en, this message translates to:
  /// **'No trainers are affiliated yet.'**
  String get exGymConsultNoTrainers;

  /// No description provided for @exTrainerConsultRequest.
  ///
  /// In en, this message translates to:
  /// **'Request a Trainer Consultation'**
  String get exTrainerConsultRequest;

  /// No description provided for @exConsultPendingCta.
  ///
  /// In en, this message translates to:
  /// **'Consultation Request Pending'**
  String get exConsultPendingCta;

  /// No description provided for @exViewConsultationRequest.
  ///
  /// In en, this message translates to:
  /// **'View consultation request'**
  String get exViewConsultationRequest;

  /// No description provided for @exConsultTarget.
  ///
  /// In en, this message translates to:
  /// **'Consultation Target'**
  String get exConsultTarget;

  /// No description provided for @exTrainerConsultType.
  ///
  /// In en, this message translates to:
  /// **'Trainer Consultation'**
  String get exTrainerConsultType;

  /// No description provided for @exAssignedTrainer.
  ///
  /// In en, this message translates to:
  /// **'Assigned Trainer'**
  String get exAssignedTrainer;

  /// No description provided for @exConsultDataSharingNotice.
  ///
  /// In en, this message translates to:
  /// **'Once this trainer accepts your request, they\'ll be able to see your diet log, exercise log, and body info and health goals.'**
  String get exConsultDataSharingNotice;

  /// No description provided for @exConsultDataSharingAgree.
  ///
  /// In en, this message translates to:
  /// **'I have read this and agree to share my meal and workout records and body information with this trainer'**
  String get exConsultDataSharingAgree;

  /// No description provided for @exConsultDataSharingRequired.
  ///
  /// In en, this message translates to:
  /// **'Please agree to sharing before requesting a consultation'**
  String get exConsultDataSharingRequired;

  /// No description provided for @coachInviteConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you connect'**
  String get coachInviteConsentTitle;

  /// No description provided for @coachInviteConsentBody.
  ///
  /// In en, this message translates to:
  /// **'Once {name} becomes your trainer, they can see your meal records, workout records, body information and health goals. Disconnecting also revokes that access.'**
  String coachInviteConsentBody(String name);

  /// No description provided for @coachInviteConsentAgree.
  ///
  /// In en, this message translates to:
  /// **'Agree and connect'**
  String get coachInviteConsentAgree;

  /// No description provided for @exExerciseGoal.
  ///
  /// In en, this message translates to:
  /// **'Exercise Goal'**
  String get exExerciseGoal;

  /// No description provided for @exGoalHealth.
  ///
  /// In en, this message translates to:
  /// **'Health Management'**
  String get exGoalHealth;

  /// No description provided for @exOptionOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get exOptionOther;

  /// No description provided for @exOtherGoalHint.
  ///
  /// In en, this message translates to:
  /// **'Please describe your specific exercise goal in the message.'**
  String get exOtherGoalHint;

  /// No description provided for @exPreferredDate.
  ///
  /// In en, this message translates to:
  /// **'Preferred Date'**
  String get exPreferredDate;

  /// No description provided for @exSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select a date'**
  String get exSelectDate;

  /// No description provided for @exSelectTime.
  ///
  /// In en, this message translates to:
  /// **'Select a time'**
  String get exSelectTime;

  /// No description provided for @exPreferredTime.
  ///
  /// In en, this message translates to:
  /// **'Preferred Time'**
  String get exPreferredTime;

  /// No description provided for @exTimeFlexible.
  ///
  /// In en, this message translates to:
  /// **'Discuss Later'**
  String get exTimeFlexible;

  /// No description provided for @exTimeRangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Select time'**
  String get exTimeRangeTitle;

  /// No description provided for @exTimeRangeStartTime.
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get exTimeRangeStartTime;

  /// No description provided for @exTimeRangeEndTime.
  ///
  /// In en, this message translates to:
  /// **'End time'**
  String get exTimeRangeEndTime;

  /// No description provided for @exTimeRangeStartHourStep.
  ///
  /// In en, this message translates to:
  /// **'Start hour'**
  String get exTimeRangeStartHourStep;

  /// No description provided for @exTimeRangeStartMinuteStep.
  ///
  /// In en, this message translates to:
  /// **'Start minute'**
  String get exTimeRangeStartMinuteStep;

  /// No description provided for @exTimeRangeEndHourStep.
  ///
  /// In en, this message translates to:
  /// **'End hour'**
  String get exTimeRangeEndHourStep;

  /// No description provided for @exTimeRangeEndMinuteStep.
  ///
  /// In en, this message translates to:
  /// **'End minute'**
  String get exTimeRangeEndMinuteStep;

  /// No description provided for @exSlotAm.
  ///
  /// In en, this message translates to:
  /// **'AM'**
  String get exSlotAm;

  /// No description provided for @exSlotPm.
  ///
  /// In en, this message translates to:
  /// **'PM'**
  String get exSlotPm;

  /// No description provided for @exTimeRangeInvalidEnd.
  ///
  /// In en, this message translates to:
  /// **'End time must be later than the start time.'**
  String get exTimeRangeInvalidEnd;

  /// No description provided for @exTimeRangePrevStep.
  ///
  /// In en, this message translates to:
  /// **'Previous step'**
  String get exTimeRangePrevStep;

  /// No description provided for @exTimeRangeNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get exTimeRangeNextStep;

  /// No description provided for @exConsultMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get exConsultMessage;

  /// No description provided for @exConsultMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Share your exercise experience or anything helpful for the consultation.'**
  String get exConsultMessageHint;

  /// No description provided for @exSendConsultRequest.
  ///
  /// In en, this message translates to:
  /// **'Send Consultation Request'**
  String get exSendConsultRequest;

  /// No description provided for @exGoalRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select an exercise goal.'**
  String get exGoalRequired;

  /// No description provided for @exOtherGoalDetailRequired.
  ///
  /// In en, this message translates to:
  /// **'Please describe your specific exercise goal in the message.'**
  String get exOtherGoalDetailRequired;

  /// No description provided for @exDateRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select a preferred date.'**
  String get exDateRequired;

  /// No description provided for @exTimeRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select a preferred time.'**
  String get exTimeRequired;

  /// No description provided for @exConsultTargetNotFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find the consultation target.'**
  String get exConsultTargetNotFound;

  /// No description provided for @exConsultPendingExists.
  ///
  /// In en, this message translates to:
  /// **'A consultation request is already pending.'**
  String get exConsultPendingExists;

  /// No description provided for @exConsultReceived.
  ///
  /// In en, this message translates to:
  /// **'Your consultation request was received'**
  String get exConsultReceived;

  /// No description provided for @exConsultCompletionInfo.
  ///
  /// In en, this message translates to:
  /// **'We\'ll let you know when the other party reviews your request.'**
  String get exConsultCompletionInfo;

  /// No description provided for @exConsultStatus.
  ///
  /// In en, this message translates to:
  /// **'Current Status'**
  String get exConsultStatus;

  /// No description provided for @exConsultPendingStatus.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get exConsultPendingStatus;

  /// No description provided for @exConsultAcceptedStatus.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get exConsultAcceptedStatus;

  /// No description provided for @exConsultRejectedStatus.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get exConsultRejectedStatus;

  /// No description provided for @exReturnExercise.
  ///
  /// In en, this message translates to:
  /// **'Return to Exercise'**
  String get exReturnExercise;

  /// No description provided for @exConsultStatusSection.
  ///
  /// In en, this message translates to:
  /// **'Consultation Request Status'**
  String get exConsultStatusSection;

  /// No description provided for @exConsultHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'My Consultation Requests'**
  String get exConsultHistoryTitle;

  /// No description provided for @exConsultHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t sent any consultation requests yet.'**
  String get exConsultHistoryEmpty;

  /// No description provided for @exConsultHistoryInProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get exConsultHistoryInProgress;

  /// No description provided for @exConsultRejectedReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason for decline'**
  String get exConsultRejectedReasonLabel;

  /// No description provided for @exConsultRejectedNoReason.
  ///
  /// In en, this message translates to:
  /// **'No reason was given. Try requesting a consultation with another trainer.'**
  String get exConsultRejectedNoReason;

  /// No description provided for @exConsultAcceptedGuide.
  ///
  /// In en, this message translates to:
  /// **'You\'re connected with your trainer. You can start chatting now.'**
  String get exConsultAcceptedGuide;

  /// No description provided for @exMyReservations.
  ///
  /// In en, this message translates to:
  /// **'My bookings'**
  String get exMyReservations;

  /// No description provided for @exCancelReservation.
  ///
  /// In en, this message translates to:
  /// **'Cancel booking'**
  String get exCancelReservation;

  /// No description provided for @exCancelKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get exCancelKeep;

  /// No description provided for @exCancelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this booking?'**
  String get exCancelConfirmTitle;

  /// No description provided for @exCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t cancel the booking. Please try again in a moment'**
  String get exCancelFailed;

  /// No description provided for @exReservationPast.
  ///
  /// In en, this message translates to:
  /// **'Past booking'**
  String get exReservationPast;

  /// No description provided for @exCancelConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The {when} booking is cancelled and the slot reopens.'**
  String exCancelConfirmBody(String when);

  /// No description provided for @exCancelDone.
  ///
  /// In en, this message translates to:
  /// **'Cancelled the {when} booking'**
  String exCancelDone(String when);

  /// No description provided for @mySupportOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link. Please try again in a moment'**
  String get mySupportOpenFailed;

  /// Shown under the FAQ / 1:1 inquiry rows so it is clear the tap leaves the app.
  ///
  /// In en, this message translates to:
  /// **'Opens the KakaoTalk channel'**
  String get mySupportExternalHint;

  /// Splash message while the saved session is being restored (#1944).
  ///
  /// In en, this message translates to:
  /// **'Restoring your session'**
  String get authRestoring;

  /// No description provided for @authRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not restore your session — the connection looks unstable.'**
  String get authRestoreFailed;

  /// No description provided for @authRestoreRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get authRestoreRetry;

  /// No description provided for @authRestoreSignIn.
  ///
  /// In en, this message translates to:
  /// **'Go to sign in'**
  String get authRestoreSignIn;

  /// No description provided for @authTagline.
  ///
  /// In en, this message translates to:
  /// **'Diet & exercise management app'**
  String get authTagline;

  /// No description provided for @authEmailHint.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailHint;

  /// No description provided for @authPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordHint;

  /// No description provided for @authSignInAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignInAction;

  /// No description provided for @authNoAccountQuestion.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get authNoAccountQuestion;

  /// No description provided for @authSignUpAction.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get authSignUpAction;

  /// No description provided for @authDemoAction.
  ///
  /// In en, this message translates to:
  /// **'Explore the demo without signing in'**
  String get authDemoAction;

  /// Label centered in the divider above the circular Kakao/Google sign-in buttons (#1783).
  ///
  /// In en, this message translates to:
  /// **'Sign in with a social account'**
  String get authSocialDivider;

  /// No description provided for @authKakaoAction.
  ///
  /// In en, this message translates to:
  /// **'Continue with Kakao'**
  String get authKakaoAction;

  /// No description provided for @authGoogleAction.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authGoogleAction;

  /// Red text under the email field on sign-in/sign-up when it is empty (#1784).
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get authEmailEmpty;

  /// No description provided for @authEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get authEmailInvalid;

  /// No description provided for @authPasswordEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get authPasswordEmpty;

  /// No description provided for @authSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Check your email and password'**
  String get authSignInFailed;

  /// No description provided for @authSocialSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Social sign-in failed. Please try again in a moment'**
  String get authSocialSignInFailed;

  /// No description provided for @signUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get signUpTitle;

  /// No description provided for @signUpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create an On-Care account and start managing your health'**
  String get signUpSubtitle;

  /// No description provided for @signUpNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get signUpNameHint;

  /// Red text under the name field on sign-up when it is empty or whitespace only (#1784).
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get signUpNameEmpty;

  /// Shared name-length message (#1887). The limit matches the users.name column and the server rule in profile_format.py.
  ///
  /// In en, this message translates to:
  /// **'Names can be up to 100 characters'**
  String get signUpNameTooLong;

  /// Placeholder showing the required 3-4-4 phone format; hyphens are inserted automatically (#1784).
  ///
  /// In en, this message translates to:
  /// **'010-0000-0000'**
  String get signUpPhoneHint;

  /// No description provided for @signUpPhoneHelper.
  ///
  /// In en, this message translates to:
  /// **'Your trainer uses this to confirm who you are.'**
  String get signUpPhoneHelper;

  /// No description provided for @signUpPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Password (8+ characters, letters and numbers)'**
  String get signUpPasswordHint;

  /// No description provided for @signUpPasswordConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get signUpPasswordConfirmHint;

  /// No description provided for @signUpAction.
  ///
  /// In en, this message translates to:
  /// **'Sign up and start'**
  String get signUpAction;

  /// No description provided for @signUpHaveAccountQuestion.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get signUpHaveAccountQuestion;

  /// No description provided for @signUpPasswordWeak.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters, including letters and numbers'**
  String get signUpPasswordWeak;

  /// No description provided for @signUpPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get signUpPasswordMismatch;

  /// No description provided for @signUpPhoneFormatInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number as 010-0000-0000'**
  String get signUpPhoneFormatInvalid;

  /// Shared birth-date format message (#1887). Matches the YYYY-MM-DD rule the server enforces in profile_format.py.
  ///
  /// In en, this message translates to:
  /// **'Enter your date of birth as 1996-03-21'**
  String get myFieldBirthInvalid;

  /// No description provided for @trainerSyncEntryLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync data with a trainer'**
  String get trainerSyncEntryLabel;

  /// No description provided for @trainerSyncEntryHint.
  ///
  /// In en, this message translates to:
  /// **'Connect with your trainer using a 6-digit code'**
  String get trainerSyncEntryHint;

  /// No description provided for @trainerSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync data with a trainer'**
  String get trainerSyncTitle;

  /// No description provided for @trainerSyncConsent.
  ///
  /// In en, this message translates to:
  /// **'The trainer who enters this code becomes your coach and can see your meals, workouts, and health records.'**
  String get trainerSyncConsent;

  /// No description provided for @trainerSyncHint.
  ///
  /// In en, this message translates to:
  /// **'Read these six digits out to your trainer.'**
  String get trainerSyncHint;

  /// No description provided for @trainerSyncCountdown.
  ///
  /// In en, this message translates to:
  /// **'Expires in {remaining}'**
  String trainerSyncCountdown(String remaining);

  /// No description provided for @trainerSyncExpired.
  ///
  /// In en, this message translates to:
  /// **'This code has expired.'**
  String get trainerSyncExpired;

  /// No description provided for @trainerSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not get a code.'**
  String get trainerSyncFailed;

  /// No description provided for @trainerSyncRetry.
  ///
  /// In en, this message translates to:
  /// **'Get a new code'**
  String get trainerSyncRetry;

  /// Sign-up: the account was created but the follow-up sign-in failed (#1926).
  ///
  /// In en, this message translates to:
  /// **'Your account was created. Please sign in.'**
  String get signUpCreatedSignInNeeded;

  /// No description provided for @signUpEmailTaken.
  ///
  /// In en, this message translates to:
  /// **'That email is already registered. Please sign in.'**
  String get signUpEmailTaken;

  /// No description provided for @signUpFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-up failed. Please try again in a moment.'**
  String get signUpFailed;

  /// No description provided for @onboardSkip.
  ///
  /// In en, this message translates to:
  /// **'Do this later'**
  String get onboardSkip;

  /// No description provided for @onboardPrevious.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardPrevious;

  /// No description provided for @onboardNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardNext;

  /// No description provided for @onboardDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get onboardDone;

  /// No description provided for @onboardSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save. Please try again in a moment'**
  String get onboardSaveFailed;

  /// No description provided for @onboardBasicTitle.
  ///
  /// In en, this message translates to:
  /// **'Basic information'**
  String get onboardBasicTitle;

  /// No description provided for @onboardBasicSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell us a little about yourself so we can tailor your care.'**
  String get onboardBasicSubtitle;

  /// No description provided for @onboardHeightHint.
  ///
  /// In en, this message translates to:
  /// **'Height (cm)'**
  String get onboardHeightHint;

  /// No description provided for @onboardWeightHint.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get onboardWeightHint;

  /// No description provided for @onboardHealthTitle.
  ///
  /// In en, this message translates to:
  /// **'Health goals'**
  String get onboardHealthTitle;

  /// No description provided for @onboardHealthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick what you want to focus on in your health care. (up to 2)'**
  String get onboardHealthSubtitle;

  /// No description provided for @onboardOptionalTag.
  ///
  /// In en, this message translates to:
  /// **'(optional)'**
  String get onboardOptionalTag;

  /// Spotlight guide: the guide label with the current step (#1857).
  ///
  /// In en, this message translates to:
  /// **'App guide {current}/{total}'**
  String guideBadgeWithStep(int current, int total);

  /// Spotlight guide: the screen under the guide is filled with sample data, not the member's own (#1857).
  ///
  /// In en, this message translates to:
  /// **'Sample screen'**
  String get guideSampleBadge;

  /// Spotlight guide: ends the guide without seeing the rest (#1857).
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get guideSkip;

  /// Spotlight guide: goes back one step (#1857).
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get guidePrev;

  /// Spotlight guide: goes to the next step (#1857).
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get guideNext;

  /// Spotlight guide: ends the guide on the last step (#1857).
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get guideDone;

  /// Spotlight guide step: the home AI advice card (#1857).
  ///
  /// In en, this message translates to:
  /// **'Today\'s AI summary'**
  String get guideHomeAdviceTitle;

  /// Spotlight guide step: the home AI advice card (#1857).
  ///
  /// In en, this message translates to:
  /// **'It reads your meals and workouts together and points to what to do today'**
  String get guideHomeAdviceBody;

  /// Spotlight guide step: the center add button (#1857).
  ///
  /// In en, this message translates to:
  /// **'Quick add'**
  String get guideQuickAddTitle;

  /// Spotlight guide step: the center add button (#1857).
  ///
  /// In en, this message translates to:
  /// **'The + in the middle adds a meal or a workout from any screen'**
  String get guideQuickAddBody;

  /// Spotlight guide step: the diet tab nutrition summary (#1857).
  ///
  /// In en, this message translates to:
  /// **'Nutrition summary'**
  String get guideDietNutritionTitle;

  /// Spotlight guide step: the diet tab nutrition summary (#1857).
  ///
  /// In en, this message translates to:
  /// **'Today\'s calories, macros, sodium and sugar, and how far each is from your goal'**
  String get guideDietNutritionBody;

  /// Spotlight guide step: the exercise tab weekly status (#1857).
  ///
  /// In en, this message translates to:
  /// **'Workout status'**
  String get guideExerciseStatusTitle;

  /// Spotlight guide step: the exercise tab weekly status (#1857).
  ///
  /// In en, this message translates to:
  /// **'How much you moved today and this week, and how far the goal still is'**
  String get guideExerciseStatusBody;

  /// Spotlight guide step: the exercise tab gym section (#1857).
  ///
  /// In en, this message translates to:
  /// **'Your gym and trainer'**
  String get guideGymTitle;

  /// Spotlight guide step: the exercise tab gym section (#1857).
  ///
  /// In en, this message translates to:
  /// **'The gym and trainer you are connected to — their plans and feedback arrive in the app'**
  String get guideGymBody;

  /// Spotlight guide step: the MY tab profile and settings (#1857).
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get guideMySettingsTitle;

  /// Spotlight guide step: the MY tab profile and settings (#1857).
  ///
  /// In en, this message translates to:
  /// **'Change your profile, health goals and alerts here — and replay this guide'**
  String get guideMySettingsBody;

  /// Spotlight guide step: the MY tab points card (#1857).
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get guidePointsTitle;

  /// Spotlight guide step: the MY tab points card; numbers come from the points rules (#1857).
  ///
  /// In en, this message translates to:
  /// **'Every log earns points.\nLog a meal +{diet}P, log a workout +{exercise}P, finish a recommended workout +{routine}P\nSpend them in MY › Use Points'**
  String guidePointsBody(int diet, int exercise, int routine);

  /// Onboarding step 1: the basic info step must be filled in (#1830).
  ///
  /// In en, this message translates to:
  /// **'(required)'**
  String get onboardRequiredTag;

  /// Onboarding step 1: shown under an empty field after tapping Next (#1830).
  ///
  /// In en, this message translates to:
  /// **'Choose your date of birth'**
  String get onboardBirthRequired;

  /// Onboarding step 1: shown under an empty field after tapping Next (#1830).
  ///
  /// In en, this message translates to:
  /// **'Choose your gender'**
  String get onboardGenderRequired;

  /// Onboarding step 1: shown under an empty field after tapping Next (#1830).
  ///
  /// In en, this message translates to:
  /// **'Enter your height'**
  String get onboardHeightRequired;

  /// Onboarding step 1: height outside the range the server accepts (#1830).
  ///
  /// In en, this message translates to:
  /// **'Height must be between {min} and {max} cm'**
  String onboardHeightRange(int min, int max);

  /// Onboarding step 1: shown under an empty field after tapping Next (#1830).
  ///
  /// In en, this message translates to:
  /// **'Enter your weight'**
  String get onboardWeightRequired;

  /// Onboarding step 1: weight outside the range the server accepts (#1830).
  ///
  /// In en, this message translates to:
  /// **'Weight must be between {min} and {max} kg'**
  String onboardWeightRange(int min, int max);

  /// No description provided for @onboardSkipStep.
  ///
  /// In en, this message translates to:
  /// **'Skip this step'**
  String get onboardSkipStep;

  /// No description provided for @onboardBirthLabel.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get onboardBirthLabel;

  /// No description provided for @onboardBirthYearHint.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get onboardBirthYearHint;

  /// No description provided for @onboardBirthMonthHint.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get onboardBirthMonthHint;

  /// No description provided for @onboardBirthDayHint.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get onboardBirthDayHint;

  /// One row of the birth-year dropdown in onboarding step 1.
  ///
  /// In en, this message translates to:
  /// **'{year}'**
  String onboardBirthYearValue(int year);

  /// One row of the birth-month dropdown in onboarding step 1.
  ///
  /// In en, this message translates to:
  /// **'{month}'**
  String onboardBirthMonthValue(int month);

  /// One row of the birth-day dropdown in onboarding step 1.
  ///
  /// In en, this message translates to:
  /// **'{day}'**
  String onboardBirthDayValue(int day);

  /// No description provided for @onboardGenderLabel.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get onboardGenderLabel;

  /// Age chip next to the date-of-birth field in onboarding step 1.
  ///
  /// In en, this message translates to:
  /// **'{age} years old'**
  String onboardAgeSummary(int age);

  /// BMI chip in onboarding step 1: the value and its category.
  ///
  /// In en, this message translates to:
  /// **'BMI {bmi} · {category}'**
  String onboardBmiSummary(String bmi, String category);

  /// No description provided for @onboardBmiUnderweight.
  ///
  /// In en, this message translates to:
  /// **'Underweight'**
  String get onboardBmiUnderweight;

  /// No description provided for @onboardBmiNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get onboardBmiNormal;

  /// No description provided for @onboardBmiPreObese.
  ///
  /// In en, this message translates to:
  /// **'Pre-obese'**
  String get onboardBmiPreObese;

  /// No description provided for @onboardBmiObese1.
  ///
  /// In en, this message translates to:
  /// **'Obesity class I'**
  String get onboardBmiObese1;

  /// No description provided for @onboardBmiObese2.
  ///
  /// In en, this message translates to:
  /// **'Obesity class II'**
  String get onboardBmiObese2;

  /// No description provided for @onboardBmiObese3.
  ///
  /// In en, this message translates to:
  /// **'Obesity class III'**
  String get onboardBmiObese3;

  /// No description provided for @onboardBmiSourceNote.
  ///
  /// In en, this message translates to:
  /// **'Cut-offs: Korean Society for the Study of Obesity guideline (Asia-Pacific)'**
  String get onboardBmiSourceNote;

  /// No description provided for @onboardDietTitle.
  ///
  /// In en, this message translates to:
  /// **'Diet goals'**
  String get onboardDietTitle;

  /// No description provided for @onboardDietSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We prefilled suggested goals. Change anything you like.'**
  String get onboardDietSubtitle;

  /// No description provided for @onboardExerciseTitle.
  ///
  /// In en, this message translates to:
  /// **'Exercise goals'**
  String get onboardExerciseTitle;

  /// No description provided for @onboardExerciseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prefilled from the World Health Organization guideline. Change anything you like.'**
  String get onboardExerciseSubtitle;

  /// No description provided for @onboardRecommendedPersonal.
  ///
  /// In en, this message translates to:
  /// **'Suggested from your age, gender, height and weight'**
  String get onboardRecommendedPersonal;

  /// No description provided for @onboardRecommendedFallback.
  ///
  /// In en, this message translates to:
  /// **'App defaults. Fill in step 1 to get a suggestion tailored to you'**
  String get onboardRecommendedFallback;

  /// No description provided for @onboardResetToRecommended.
  ///
  /// In en, this message translates to:
  /// **'Reset to suggested'**
  String get onboardResetToRecommended;

  /// No description provided for @onboardDietSourceNote.
  ///
  /// In en, this message translates to:
  /// **'Sources: Dietary Reference Intakes for Koreans 2020 (EER, AMDR) · WHO sodium and free-sugar guidelines'**
  String get onboardDietSourceNote;

  /// No description provided for @onboardExerciseSourceNote.
  ///
  /// In en, this message translates to:
  /// **'Source: WHO guidelines on physical activity (2020) — 150 min of moderate cardio and 2+ strength days a week'**
  String get onboardExerciseSourceNote;

  /// Shown under goal fields when the picked health goals changed the suggestion.
  ///
  /// In en, this message translates to:
  /// **'Adjusted for the health goals you picked'**
  String get onboardFocusAdjusted;

  /// Sources for the goal-based adjustments.
  ///
  /// In en, this message translates to:
  /// **'Goal adjustments: 500 kcal a day for weight loss (Korean Society for the Study of Obesity) · 1.6 g protein per kg for strength (ISSN) · sugar 5% of energy (WHO) · 150–300 min cardio a week (WHO)'**
  String get onboardFocusSourceNote;

  /// No description provided for @onboardGenderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get onboardGenderMale;

  /// No description provided for @onboardGenderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get onboardGenderFemale;

  /// No description provided for @onboardGenderOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get onboardGenderOther;

  /// Greeting bubble the app shows when the coach conversation opens.
  ///
  /// In en, this message translates to:
  /// **'Hi, I\'m Oni, your AI health coach 🙂\nI look at your diet and exercise records — ask me anything.'**
  String get aiCoachWelcome;

  /// Bubble shown when the coach reply could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again in a moment.'**
  String get aiCoachFailure;

  /// Generic cancel button in shared dialogs.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// Generic delete button in shared dialogs.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// Generic edit action in shared sheets.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// Generic acknowledge button in shared dialogs.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get actionConfirm;

  /// Tag of a sleep-related AI suggestion.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get coachCardSleepTag;

  /// Title of the health goals sheet.
  ///
  /// In en, this message translates to:
  /// **'Health goals'**
  String get myHealthGoalsTitle;

  /// No description provided for @myGoalsFocusSection.
  ///
  /// In en, this message translates to:
  /// **'What you want to focus on'**
  String get myGoalsFocusSection;

  /// No description provided for @myGoalsFocusHint.
  ///
  /// In en, this message translates to:
  /// **'Pick what you want to focus on in your health care. (up to 2)'**
  String get myGoalsFocusHint;

  /// MY health goals: who last changed the goal chips and when (#1832).
  ///
  /// In en, this message translates to:
  /// **'Last changed by {who} · {date}'**
  String myGoalsFocusLastChanged(String who, String date);

  /// MY health goals: the goals were last changed by the member's trainer (#1832).
  ///
  /// In en, this message translates to:
  /// **'your trainer'**
  String get myGoalsFocusChangedByTrainer;

  /// MY health goals: the goals were last changed by the member (#1832).
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get myGoalsFocusChangedByMe;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In en, this message translates to:
  /// **'Weight loss'**
  String get healthFocusWeightLoss;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In en, this message translates to:
  /// **'Build strength'**
  String get healthFocusStrength;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In en, this message translates to:
  /// **'Improve fitness'**
  String get healthFocusFitness;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In en, this message translates to:
  /// **'Posture correction'**
  String get healthFocusPosture;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In en, this message translates to:
  /// **'Rehab'**
  String get healthFocusRehab;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In en, this message translates to:
  /// **'Better eating habits'**
  String get healthFocusEating;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In en, this message translates to:
  /// **'Exercise habit'**
  String get healthFocusExerciseHabit;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In en, this message translates to:
  /// **'Blood pressure care'**
  String get healthFocusBloodPressure;

  /// Section label in the health goals sheet.
  ///
  /// In en, this message translates to:
  /// **'Diet goals'**
  String get myGoalsDietSection;

  /// Section label in the health goals sheet.
  ///
  /// In en, this message translates to:
  /// **'Exercise targets'**
  String get myGoalsExerciseSection;

  /// No description provided for @myGoalBurnDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily calories burned (kcal)'**
  String get myGoalBurnDaily;

  /// No description provided for @myGoalCardioWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly cardio (min)'**
  String get myGoalCardioWeekly;

  /// No description provided for @myGoalStrengthWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly strength (sets)'**
  String get myGoalStrengthWeekly;

  /// No description provided for @myGoalFlexibilityWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly stretching (min)'**
  String get myGoalFlexibilityWeekly;

  /// Explains the suggested exercise goals, adjusted for the picked health goals.
  ///
  /// In en, this message translates to:
  /// **'Suggested: {burn} kcal a day · {cardio} min cardio · {strength} sets · {flexibility} min stretching a week'**
  String myGoalExerciseSuggestionNote(
    int burn,
    int cardio,
    int strength,
    int flexibility,
  );

  /// No description provided for @myGoalExerciseApplySuggestion.
  ///
  /// In en, this message translates to:
  /// **'Use suggested goals'**
  String get myGoalExerciseApplySuggestion;

  /// Health goal field label.
  ///
  /// In en, this message translates to:
  /// **'Daily calorie limit (kcal)'**
  String get myGoalCalories;

  /// Health goal field label.
  ///
  /// In en, this message translates to:
  /// **'Daily sodium limit (mg)'**
  String get myGoalSodium;

  /// Health goal field label.
  ///
  /// In en, this message translates to:
  /// **'Daily sugar limit (g)'**
  String get myGoalSugar;

  /// Health goal field label.
  ///
  /// In en, this message translates to:
  /// **'Daily carbohydrate limit (g)'**
  String get myGoalCarbs;

  /// Health goal field label.
  ///
  /// In en, this message translates to:
  /// **'Daily protein limit (g)'**
  String get myGoalProtein;

  /// Health goal field label.
  ///
  /// In en, this message translates to:
  /// **'Daily fat limit (g)'**
  String get myGoalFat;

  /// Helper under the calorie goal field when it was derived from the macro fields.
  ///
  /// In en, this message translates to:
  /// **'Calculated from your carb, protein and fat goals'**
  String get myGoalCaloriesFromMacros;

  /// Explains the placeholder grams shown in the macro fields.
  ///
  /// In en, this message translates to:
  /// **'Suggested split for {kcal} kcal: {carbs} g carbs · {protein} g protein · {fat} g fat · {sugar} g sugar'**
  String myGoalMacroSuggestionNote(
    int kcal,
    int carbs,
    int protein,
    int fat,
    int sugar,
  );

  /// Button that fills the macro fields with the suggested grams.
  ///
  /// In en, this message translates to:
  /// **'Use suggested split'**
  String get myGoalMacroApplySuggestion;

  /// Health goal field label.
  ///
  /// In en, this message translates to:
  /// **'Weekly workout count goal'**
  String get myGoalWorkoutCount;

  /// Health goal field label.
  ///
  /// In en, this message translates to:
  /// **'Weekly workout minutes goal'**
  String get myGoalWorkoutMinutes;

  /// Health goal field label.
  ///
  /// In en, this message translates to:
  /// **'Weekly calories burned goal (kcal)'**
  String get myGoalWorkoutCalories;

  /// Shown after health goals are saved.
  ///
  /// In en, this message translates to:
  /// **'Health goals saved'**
  String get myGoalsSaved;

  /// Health-goal field outside the range the server accepts (#1888). Shared by the MY goals sheet and onboarding steps 3-4.
  ///
  /// In en, this message translates to:
  /// **'Enter a value between {min} and {max}'**
  String myGoalRange(int min, int max);

  /// Title of the banner shown when settings fail to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your settings'**
  String get mySettingsLoadFailed;

  /// Body of the banner shown when settings fail to load.
  ///
  /// In en, this message translates to:
  /// **'Editing is locked because saving now could wipe your existing settings.'**
  String get mySettingsLoadFailedBody;

  /// Shown when saving notification settings fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save notification settings'**
  String get myNotificationSaveFailed;

  /// Title of the points guide dialog.
  ///
  /// In en, this message translates to:
  /// **'How to earn points'**
  String get myPointsGuideTitle;

  /// Point-earning action in the points guide.
  ///
  /// In en, this message translates to:
  /// **'Log a meal'**
  String get myPointsDietAdd;

  /// Point-earning action in the points guide: completing a workout recommended by AI or assigned by the trainer.
  ///
  /// In en, this message translates to:
  /// **'Complete a recommended or assigned workout'**
  String get myPointsRoutineComplete;

  /// Point-earning action in the points guide.
  ///
  /// In en, this message translates to:
  /// **'Log a workout yourself'**
  String get myPointsExerciseAdd;

  /// Point-earning action in the points guide with its daily earning limit, e.g. 'Log a meal (up to 3 times a day)'.
  ///
  /// In en, this message translates to:
  /// **'{action} ({count, plural, =1{once a day} other{up to {count} times a day}})'**
  String myPointsRuleWithDailyCap(String action, int count);

  /// Header of the assigned trainer card.
  ///
  /// In en, this message translates to:
  /// **'My trainer'**
  String get coachAssignedTrainer;

  /// Section title in the coaching card.
  ///
  /// In en, this message translates to:
  /// **'This week\'s coaching points'**
  String get coachPointsTitle;

  /// Section title in the coaching card.
  ///
  /// In en, this message translates to:
  /// **'Recommended solo workouts'**
  String get coachRoutineTitle;

  /// Origin of a routine.
  ///
  /// In en, this message translates to:
  /// **'Recommended by your trainer'**
  String get coachRoutineByTrainer;

  /// Origin of a routine an AI proposed and the trainer approved.
  ///
  /// In en, this message translates to:
  /// **'AI suggestion · reviewed by {name}'**
  String coachRoutineAiChecked(String name);

  /// Origin of a routine proposed automatically.
  ///
  /// In en, this message translates to:
  /// **'AI suggestion'**
  String get coachRoutineAiAuto;

  /// Shown after a routine is marked done.
  ///
  /// In en, this message translates to:
  /// **'Added to your workout log'**
  String get coachRoutineLogged;

  /// Shown when the routine is missing.
  ///
  /// In en, this message translates to:
  /// **'This program no longer exists. Please refresh the list'**
  String get coachRoutineGone;

  /// Shown when the network is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again'**
  String get coachRoutineNetworkError;

  /// Shown when marking a routine done fails for an unexpected reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record it as done.'**
  String get coachRoutineLogFailed;

  /// Marks a routine as completed.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get coachRoutineDone;

  /// No description provided for @coachRoutineUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get coachRoutineUndo;

  /// No description provided for @coachRoutineUndoConfirm.
  ///
  /// In en, this message translates to:
  /// **'Undo completing \'{name}\'? It will be removed from your workout log too.'**
  String coachRoutineUndoConfirm(String name);

  /// No description provided for @coachRoutineUndone.
  ///
  /// In en, this message translates to:
  /// **'Completion undone'**
  String get coachRoutineUndone;

  /// No description provided for @coachRoutineUndoFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not undo the completion.'**
  String get coachRoutineUndoFailed;

  /// No description provided for @coachRoutineCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel this workout'**
  String get coachRoutineCancel;

  /// No description provided for @coachRoutineCancelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \'{name}\' from the list? Anything you already logged stays.'**
  String coachRoutineCancelConfirm(String name);

  /// Title of the dialog confirming undoing a completed recommended workout.
  ///
  /// In en, this message translates to:
  /// **'Undo completion?'**
  String get coachCardRoutineUndoTitle;

  /// Title of the dialog confirming removal of a recommended workout.
  ///
  /// In en, this message translates to:
  /// **'Cancel this workout?'**
  String get coachCardRoutineCancelTitle;

  /// Left button of the cancel/undo confirmation dialogs for a recommended workout; closes the dialog and keeps it as is.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get coachRoutineKeep;

  /// No description provided for @coachRoutineCancelled.
  ///
  /// In en, this message translates to:
  /// **'Workout cancelled'**
  String get coachRoutineCancelled;

  /// No description provided for @coachRoutineCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t cancel the workout'**
  String get coachRoutineCancelFailed;

  /// The trainer's feedback on a completed routine.
  ///
  /// In en, this message translates to:
  /// **'Trainer feedback: {feedback}'**
  String coachRoutineTrainerFeedback(String feedback);

  /// Title of the completion dialog.
  ///
  /// In en, this message translates to:
  /// **'Mark personal exercise done'**
  String get coachRoutineCompleteTitle;

  /// Field label in the completion dialog.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get coachRoutineIntensity;

  /// Intensity option.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get coachIntensityLight;

  /// Intensity option.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get coachIntensityModerate;

  /// Intensity option.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get coachIntensityHigh;

  /// Submit button of the completion dialog.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get coachRoutineSubmit;

  /// Opens the chat with the assigned trainer.
  ///
  /// In en, this message translates to:
  /// **'Chat with trainer'**
  String get coachChatWithTrainer;

  /// Tooltip while the assigned trainer is being fetched.
  ///
  /// In en, this message translates to:
  /// **'Loading your trainer…'**
  String get coachTrainerLoading;

  /// Tooltip when no trainer is assigned yet.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have a trainer yet. Connect a gym and trainer from the Exercise tab'**
  String get coachTrainerNone;

  /// Notification category badge.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get alertCategoryReminder;

  /// Notification category badge.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get alertCategoryHealth;

  /// Notification category badge.
  ///
  /// In en, this message translates to:
  /// **'Achievement'**
  String get alertCategoryAchievement;

  /// Notification category badge.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get alertCategorySystem;

  /// Marks every notification as read.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get alertMarkAllRead;

  /// Empty state of the notification list.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get alertEmpty;

  /// Shown when the notification list fails to refresh.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the latest notifications'**
  String get alertLoadFailed;

  /// Relative time for a notification less than a minute old.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get alertTimeJustNow;

  /// Relative time for a notification under an hour old.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String alertTimeMinutesAgo(int minutes);

  /// Relative time for a notification under a day old.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String alertTimeHoursAgo(int hours);

  /// Relative time for a notification from about a day ago.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get alertTimeYesterday;

  /// Relative time for a notification two or more days old.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String alertTimeDaysAgo(int days);

  /// Title of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'Watch your sodium'**
  String get demoAlertSodiumTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'Lunch jjamppong pushed today\'s sodium to 3,428mg. Drink plenty of water.'**
  String get demoAlertSodiumBody;

  /// Title of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'Log your dinner'**
  String get demoAlertDinnerTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'No dinner logged yet today. One photo is all it takes.'**
  String get demoAlertDinnerBody;

  /// Title of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'A new workout routine arrived'**
  String get demoAlertRoutineTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'Trainer Kim adjusted it to a walking routine for your knee.'**
  String get demoAlertRoutineBody;

  /// Title of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'This week\'s report is ready'**
  String get demoAlertReportTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'Trainer Kim posted your report for this week.'**
  String get demoAlertReportBody;

  /// Title of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'PT session complete'**
  String get demoAlertPtDoneTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'You finished PT session 12 with Trainer Kim at 18:00 today!'**
  String get demoAlertPtDoneBody;

  /// Title of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'Feedback from your trainer'**
  String get demoAlertTrainerFeedbackTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'Be sure to stretch your rotator cuff to finish.'**
  String get demoAlertTrainerFeedbackBody;

  /// Title of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'Almost at this week\'s workout goal'**
  String get demoAlertWeeklyGoalTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'Start with 30 minutes of low-intensity cardio (walking).'**
  String get demoAlertWeeklyGoalBody;

  /// Title of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'You\'re keeping up your meal log'**
  String get demoAlertMealStreakTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'You\'ve logged your meals every day for over a month.'**
  String get demoAlertMealStreakBody;

  /// Title of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'Scheduled maintenance'**
  String get demoAlertMaintenanceTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In en, this message translates to:
  /// **'Maintenance is scheduled for tomorrow, 02:00–03:00.'**
  String get demoAlertMaintenanceBody;

  /// Title of the completed PT session card.
  ///
  /// In en, this message translates to:
  /// **'Today\'s completed PT'**
  String get exPtLogTitle;

  /// Label above the trainer's feedback.
  ///
  /// In en, this message translates to:
  /// **'Today\'s feedback'**
  String get exPtFeedbackTitle;

  /// No description provided for @exNextPtSchedule.
  ///
  /// In en, this message translates to:
  /// **'Next PT · {when}'**
  String exNextPtSchedule(String when);

  /// No description provided for @exNextPtNone.
  ///
  /// In en, this message translates to:
  /// **'No PT scheduled yet'**
  String get exNextPtNone;

  /// Screen title carrying the selected date.
  ///
  /// In en, this message translates to:
  /// **'{title} · {month}/{day}'**
  String exDatedTitle(int month, int day, String title);

  /// No description provided for @a11yChartSummary.
  ///
  /// In en, this message translates to:
  /// **'{title}. {detail}'**
  String a11yChartSummary(String title, String detail);

  /// No description provided for @a11yChartEmpty.
  ///
  /// In en, this message translates to:
  /// **'{title}. No records yet'**
  String a11yChartEmpty(String title);

  /// No description provided for @a11yChartPoint.
  ///
  /// In en, this message translates to:
  /// **'{day} {value}'**
  String a11yChartPoint(String day, String value);

  /// No description provided for @a11yShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get a11yShowPassword;

  /// No description provided for @a11yHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get a11yHidePassword;

  /// No description provided for @a11yOpenCoaching.
  ///
  /// In en, this message translates to:
  /// **'Open coaching tips'**
  String get a11yOpenCoaching;

  /// No description provided for @a11ySendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get a11ySendMessage;

  /// No description provided for @a11yClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get a11yClearSearch;

  /// No description provided for @a11yRemoveFood.
  ///
  /// In en, this message translates to:
  /// **'Remove food'**
  String get a11yRemoveFood;

  /// No description provided for @a11yOpenCalendar.
  ///
  /// In en, this message translates to:
  /// **'Open schedule calendar'**
  String get a11yOpenCalendar;

  /// No description provided for @a11yPrevWeek.
  ///
  /// In en, this message translates to:
  /// **'Previous week'**
  String get a11yPrevWeek;

  /// No description provided for @a11yNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get a11yNextWeek;

  /// No description provided for @exConsultHistoryCancelTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this consultation request?'**
  String get exConsultHistoryCancelTitle;

  /// No description provided for @exConsultHistoryCancelBody.
  ///
  /// In en, this message translates to:
  /// **'A cancelled request can\'t be restored.'**
  String get exConsultHistoryCancelBody;

  /// No description provided for @exDemoPtSessionCount.
  ///
  /// In en, this message translates to:
  /// **'Session 12 with Trainer Kim'**
  String get exDemoPtSessionCount;

  /// No description provided for @exDemoPtTrainerName.
  ///
  /// In en, this message translates to:
  /// **'Trainer Kim'**
  String get exDemoPtTrainerName;

  /// No description provided for @exDemoPtFeedback.
  ///
  /// In en, this message translates to:
  /// **'Your right shoulder tends to lift during shoulder presses, so be sure to stretch your rotator cuff when you finish!'**
  String get exDemoPtFeedback;

  /// No description provided for @exStepperDecrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get exStepperDecrease;

  /// No description provided for @exStepperIncrease.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get exStepperIncrease;

  /// Points earned badge on the save toast (shown after a star icon), e.g. +50P.
  ///
  /// In en, this message translates to:
  /// **'+{points}P'**
  String pointsRewardBadge(int points);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
