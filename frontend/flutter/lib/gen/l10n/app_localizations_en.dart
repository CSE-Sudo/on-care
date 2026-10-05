// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get coachInviteUnavailable =>
      'This request has already been handled or cancelled.';

  @override
  String get appTitle => 'On-Care';

  @override
  String get notFoundTitle => 'Page not found';

  @override
  String get notFoundMessage =>
      'The link may be broken, or the page may no longer exist. Please check the address and try again.';

  @override
  String get notFoundGoHome => 'Go home';

  @override
  String get notFoundGoSignIn => 'Go to sign in';

  @override
  String get updateRequiredTitle => 'A new version is available';

  @override
  String get updateRequiredMessage => 'Please update On-Care to keep using it.';

  @override
  String updateRequiredVersions(String current, String min) {
    return 'Your version $current · Required $min';
  }

  @override
  String get updateRequiredAction => 'Update';

  @override
  String get updateRequiredStoreHint =>
      'Please update On-Care from the App Store.';

  @override
  String get updateRequiredOpenFailed =>
      'Couldn\'t open the store. Please update On-Care from the store app.';

  @override
  String get misconfiguredBuildTitle => 'This build is misconfigured';

  @override
  String get misconfiguredBuildMessage =>
      'This build was made with settings that can\'t be used for real users, so the app didn\'t open. Please share the details below with whoever released it.';

  @override
  String get misconfiguredBuildDetailsTitle => 'Build settings to fix';

  @override
  String get misconfiguredBuildDevEnvironment => 'ENV is not prod or staging';

  @override
  String get misconfiguredBuildMockWithoutDemo =>
      'It uses demo data without the demo build flag (USE_MOCK_API, DEMO_BUILD)';

  @override
  String get misconfiguredBuildPlaceholderApiUrl =>
      'The API address is an example or local address (API_BASE_URL)';

  @override
  String get misconfiguredBuildInsecureApiUrl =>
      'The API address does not start with https:// (API_BASE_URL)';

  @override
  String get navDashboard => 'Home';

  @override
  String get navDiet => 'Diet';

  @override
  String get navExercise => 'Exercise';

  @override
  String get navMyHealth => 'MY';

  @override
  String get pageDietTitle => 'Diet';

  @override
  String get pageExerciseTitle => 'Exercise';

  @override
  String get pageAiCoachTitle => 'AI Coach';

  @override
  String get pageNotificationTitle => 'Notifications';

  @override
  String get actionRetry => 'Retry';

  @override
  String get errorCancelled => 'Cancelled';

  @override
  String get errorUnknown => 'Something went wrong';

  @override
  String get errorForbidden =>
      'You don\'t have access to this feature. Please check the required consent or your trainer connection.';

  @override
  String get errorRateLimited =>
      'Too many requests right now. Please try again in a moment.';

  @override
  String get errorNetwork =>
      'Your connection looks unstable. Check your network and try again.';

  @override
  String get errorServer =>
      'Something went wrong on our side. Please try again in a moment.';

  @override
  String get errorInvalidRequest =>
      'We couldn\'t process that request. Please check what you entered.';

  @override
  String get dashboardMetricCalories => 'Calories';

  @override
  String get dashboardMetricExercise => 'Weekly exercise';

  @override
  String get homeDashboardLoadError => 'Could not load the dashboard.';

  @override
  String get homeDashboardEmpty =>
      'No records yet today. Add a meal or workout to get started.';

  @override
  String get homeAiAdviceTitle => 'Today\'s combined AI advice';

  @override
  String get homeAdviceSodiumOver =>
      'You went over the sodium target today. Try keeping the rest of your meals light.';

  @override
  String homeAdviceExerciseOnTrack(int minutes) {
    return 'You worked out $minutes minutes this week. You are on track!';
  }

  @override
  String homeAdviceExerciseMore(int minutes) {
    return 'You worked out $minutes minutes this week. A little more to go!';
  }

  @override
  String get homeAdviceExerciseStart =>
      'Start moving this week — an easy walk is a good beginning.';

  @override
  String homeAdviceSodiumOverSources(String foods) {
    return 'Sodium is high from $foods.';
  }

  @override
  String homeAdviceFoodPair(String first, String second) {
    return '$first and $second';
  }

  @override
  String get homeAiAdviceBody =>
      'Your breakfast and evening PT were perfect! Lunch ran high in sodium, so drink plenty of water and finish well with the shoulder stretches your coach emphasized.';

  @override
  String get homeAiAdviceNoRecord =>
      'Log today\'s meals and workouts, and we\'ll put together advice for your day.';

  @override
  String get homeMacroCarbs => 'Carbs';

  @override
  String get homeMacroProtein => 'Protein';

  @override
  String get homeMacroFat => 'Fat';

  @override
  String get homeMealChickenSalad => 'Chicken breast salad';

  @override
  String get homeDetails => 'Details';

  @override
  String get homeGoal => 'Goal';

  @override
  String get homeDietNutritionTitle => 'Diet & nutrition';

  @override
  String get homeCalorieIntake => 'Today\'s calories';

  @override
  String get homeAchieveRate => 'Progress';

  @override
  String homeWeeklyMetricTrend(String metric) {
    return 'Weekly $metric trend';
  }

  @override
  String get homeExerciseTrendUnavailable =>
      'Couldn\'t load this week\'s workout history.';

  @override
  String get homeExerciseBurned => 'Calories';

  @override
  String get homeMealReasonSodium => 'Great for sodium control';

  @override
  String get homeMealSourceTrainer => 'Trainer pick';

  @override
  String get homeMealSourceAi => 'AI pick';

  @override
  String get homeMealTagLowSodium => 'Low sodium';

  @override
  String get homeMealBrownRiceBox => 'Brown rice lunchbox';

  @override
  String get homeMealReasonGlucose => 'Helps steady blood sugar';

  @override
  String get homeMealTagLowSugar => 'Low sugar';

  @override
  String get homeMealSalmon => 'Grilled salmon + greens';

  @override
  String get homeMealReasonOmega => 'Omega-3 + fiber';

  @override
  String get homeMealTagHighProtein => 'High protein';

  @override
  String get homeMealTofu => 'Stir-fried tofu & veggies';

  @override
  String get homeMealReasonLowCal => 'Low calorie, keeps you full';

  @override
  String get homeMealTagLowCal => 'Low calorie';

  @override
  String get homeMealNamulBibimbap => 'Namul bibimbap';

  @override
  String get homeMealReasonFiber => 'Rich in dietary fiber';

  @override
  String get homeMealTagLowFat => 'Low fat';

  @override
  String get homeTrainerPickReasonSodiumLow => 'Less sodium';

  @override
  String get homeTrainerPickReasonProteinHigh => 'More protein';

  @override
  String get homeTrainerPickReasonCalorieLow => 'A lighter meal';

  @override
  String get homeTrainerPickReasonCalorieHigh => 'A filling meal';

  @override
  String get homeTrainerPickReasonSugarLow => 'Less sugar';

  @override
  String get homeTrainerPickReasonFiberHigh => 'More fiber';

  @override
  String homeRecBasisSodium(int days, String sodium) {
    return '$days-day avg sodium ${sodium}mg';
  }

  @override
  String get homeRecBasisOverLimit => 'over the daily limit';

  @override
  String get homeRecMealsTitle => 'Recommended meals';

  @override
  String get homeRecMealsErrorTitle => 'Couldn\'t load meal suggestions';

  @override
  String get unitKcal => 'kcal';

  @override
  String get unitMinutes => 'min';

  @override
  String unitKcalValue(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString kcal';
  }

  @override
  String unitMinutesValue(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString min';
  }

  @override
  String get dietTitle => 'Diet';

  @override
  String get dietToday => 'Today';

  @override
  String get dietWeekdayMon => 'Mon';

  @override
  String get dietWeekdayTue => 'Tue';

  @override
  String get dietWeekdayWed => 'Wed';

  @override
  String get dietWeekdayThu => 'Thu';

  @override
  String get dietWeekdayFri => 'Fri';

  @override
  String get dietWeekdaySat => 'Sat';

  @override
  String get dietWeekdaySun => 'Sun';

  @override
  String get dietNutritionSummary => 'Nutrition';

  @override
  String get dietAmount => 'Serving size';

  @override
  String get dietCalories => 'Calories';

  @override
  String get dietSodium => 'Sodium';

  @override
  String get dietSugar => 'Sugar';

  @override
  String get dietUnitMg => 'mg';

  @override
  String get dietUnitG => 'g';

  @override
  String get dietAiFeedback => 'AI advice';

  @override
  String get aiAdviceLoading => 'Looking at this period…';

  @override
  String get aiAdviceError => 'Couldn\'t load the advice.';

  @override
  String get dietMealLog => 'Meal Log';

  @override
  String get dietAddMeal => 'Add Meal';

  @override
  String get dietEmptyLog => 'No meals logged.\nAdd a meal with a photo!';

  @override
  String get dietLoadError => 'Couldn\'t load your diet.';

  @override
  String get dietMealNotFound => 'This meal was deleted or doesn\'t exist';

  @override
  String get dietMealNotFoundMessage =>
      'Check your meals again in the Diet tab.';

  @override
  String get dietMealNotFoundAction => 'Go to Diet';

  @override
  String get dietPeriodAverage => 'Daily average';

  @override
  String get dietPeriodEmpty => 'No meals were logged in this period.';

  @override
  String get dietPeriodNoRecord => 'No record';

  @override
  String get dietPeriodNotYet => 'Not yet';

  @override
  String dietPeriodOverGoal(String amount, String unit) {
    return '$amount $unit over goal';
  }

  @override
  String otherDateEmpty(Object section) {
    return 'No $section records for the selected date.';
  }

  @override
  String get dietMealBreakfast => 'Breakfast';

  @override
  String get dietMealLunch => 'Lunch';

  @override
  String get dietMealDinner => 'Dinner';

  @override
  String get dietMealSnack => 'Snack';

  @override
  String get dietMealLateNight => 'Late-night';

  @override
  String dietMealSheetTitle(String meal) {
    return '$meal';
  }

  @override
  String dietFoodDbMatch(String name) {
    return 'Public DB · $name';
  }

  @override
  String dietMoreFoods(String name, int count) {
    return '$name +$count';
  }

  @override
  String get dietFillFromDb => 'Fill in';

  @override
  String dietFoodFilledFromDb(String name) {
    return 'Changed to public DB · $name';
  }

  @override
  String get dietUndoFill => 'Undo';

  @override
  String get dietFoodNotInDb =>
      'Not in the public food DB. Please check the nutrition.';

  @override
  String get dietAddSheetTitle => 'Add a Meal';

  @override
  String get dietAddSheetSubtitle => 'Analyze your food from a photo';

  @override
  String get dietPickPhoto => 'Choose a Photo';

  @override
  String get dietPickPhotoSub => 'Pick a food photo from your gallery';

  @override
  String get dietTakePhoto => 'Take a Photo';

  @override
  String get dietTakePhotoSub => 'Snap your food with the camera';

  @override
  String get dietAddPhoto => 'Add a Photo';

  @override
  String get dietAddPhotoSub =>
      'Choose a food photo from your library, camera, or files';

  @override
  String get dietPhotoLoadError =>
      'Couldn\'t load the photo. Please try again in a moment.';

  @override
  String get dietCameraPermissionDenied =>
      'Camera permission is needed to photograph your meal. Tap Take Photo to try again.';

  @override
  String get dietCameraPermissionPermanentlyDenied =>
      'Camera access is off. Turn it on in Settings to photograph your meal.';

  @override
  String get dietPhotoPermissionDenied =>
      'Photo permission is needed to choose a meal photo. Tap Choose Photo to try again.';

  @override
  String get dietPhotoPermissionPermanentlyDenied =>
      'Photo access is off. Turn it on in Settings to choose a meal photo.';

  @override
  String get dietPhotoPermissionRestricted =>
      'Camera or photo access is unavailable because of this device\'s settings or management policy.';

  @override
  String get dietPhotoUnsupportedFormat =>
      'That photo format isn\'t supported. Please try a JPG or PNG photo.';

  @override
  String get dietPhotoTooLarge =>
      'That photo is too large. Please try a different one.';

  @override
  String get dietOpenSettings => 'Open Settings';

  @override
  String get dietOpenSettingsFailed =>
      'Couldn\'t open Settings. Turn on camera and photo access under Settings > Oncare.';

  @override
  String get dietAnalyzing => 'Analyzing…';

  @override
  String get dietAnalysisFailed => 'Analysis failed';

  @override
  String get dietRecordDate => 'Record date';

  @override
  String get dietRecordDateChange => 'Change date';

  @override
  String dietRecordDateMoved(String date) {
    return 'Moved to $date';
  }

  @override
  String get dietRecordDateFailed =>
      'Could not change the date. Please try again shortly.';

  @override
  String get dietMealKind => 'Meal';

  @override
  String get dietAnalysisDone => 'Analysis complete!';

  @override
  String get dietAiNutritionResult => 'AI Nutrition Result';

  @override
  String get dietAnalyzingBody => 'Analyzing the food in your photo';

  @override
  String get dietAnalysisFailedBody =>
      'Analysis failed. Please try again in a moment.';

  @override
  String get dietAnalysisUnsupportedFormat =>
      'This photo format can\'t be analyzed. Please pick a JPG or PNG photo instead.';

  @override
  String get dietAnalysisBadRequest =>
      'The photo couldn\'t be read. Please pick a different one.';

  @override
  String get dietAnalysisUnauthorized =>
      'Your session expired. Please sign in again to log this meal.';

  @override
  String get dietAnalysisNotImplemented =>
      'Photo analysis is unavailable right now. Please log the meal manually.';

  @override
  String get dietAnalysisNoFood =>
      'We couldn\'t find any food in this photo. Pick another photo or add the meal manually.';

  @override
  String get dietAnalysisDailyLimit =>
      'You\'ve used today\'s photo analyses. They reset tomorrow — for now you can add the meal manually.';

  @override
  String get dietAnalysisRateLimited =>
      'Too many photo analyses in a short time. Try again in a moment or add the meal manually.';

  @override
  String get dietAnalysisUnavailable =>
      'Photo analysis is unavailable right now. Please add the meal manually.';

  @override
  String get dietAnalysisAiCapacity =>
      'AI features are taking a break due to high demand. They reopen tomorrow — for now you can add the meal manually.';

  @override
  String get dietAnalysisPickAnother => 'Pick another photo';

  @override
  String get dietAnalysisSignIn => 'Sign in again';

  @override
  String get dietAnalysisClose => 'Close';

  @override
  String get dietRecognizedFood => 'Recognized Food';

  @override
  String get dietNoRecognizedFood => 'No food recognized';

  @override
  String get dietNutritionResult => 'Nutrition Result';

  @override
  String get dietSaved => 'Meal saved';

  @override
  String get dietSaveFailed => 'Couldn\'t save. Please try again in a moment.';

  @override
  String get dietManualAlreadySaved =>
      'An earlier version of this meal was already saved. Please check your records.';

  @override
  String get dietDeleteTitle => 'Delete Meal Record';

  @override
  String get dietDeleteConfirm => 'Delete this meal record?';

  @override
  String get dietDeleteWhenEmpty => 'No food is left. Delete this meal record?';

  @override
  String get dietCancel => 'Cancel';

  @override
  String get dietDelete => 'Delete';

  @override
  String get dietDeleted => 'Meal deleted';

  @override
  String get dietDeleteFailed =>
      'Couldn\'t delete. Please try again in a moment.';

  @override
  String get dietSave => 'Save';

  @override
  String get dietMealInfo => 'Meal Info';

  @override
  String get dietEatenFood => 'Food Eaten';

  @override
  String get dietNewFood => 'New food';

  @override
  String get dietAddFood => 'Add Food';

  @override
  String get dietManualAdd => 'Add manually';

  @override
  String get dietManualAddTitle => 'Add Meal Manually';

  @override
  String get dietManualAddHint =>
      'Type a food name and we\'ll fill in the nutrition';

  @override
  String get dietManualAddEmpty => 'Add at least one food';

  @override
  String get dietEditFoodHint =>
      'Change the serving size and the nutrition follows';

  @override
  String get dietTotalCalories => 'Total Calories';

  @override
  String get dietNutritionInfo => 'Nutrition Info';

  @override
  String get dietEditNutritionHint =>
      'Edit each food\'s nutrition and it adds up here';

  @override
  String get dietSugarOverCarbs => 'Sugar can\'t be more than carbs';

  @override
  String get dietDeleteMeal => 'Delete Meal';

  @override
  String get dietEditMeal => 'Edit meal';

  @override
  String get exTypeCardio => 'Cardio';

  @override
  String get exTypeStrength => 'Strength';

  @override
  String get exTypeFlexibility => 'Stretching';

  @override
  String get exTypeOtherChip => 'Other';

  @override
  String get exLevelLight => 'Light';

  @override
  String get exLevelModerate => 'Moderate';

  @override
  String get exLevelHigh => 'High';

  @override
  String get exExerciseLog => 'Exercise Log';

  @override
  String get exGymTab => 'Gym';

  @override
  String get exMyGymSection => 'My Gym';

  @override
  String get exConnected => 'Connected';

  @override
  String get exTrainerAffiliation => 'Gym';

  @override
  String get exTrainerIntroSection => 'About the trainer';

  @override
  String exTrainerCareer(String career) {
    return '$career of experience';
  }

  @override
  String get exTrainerCertifications => 'Certifications';

  @override
  String get exTrainerRecommendationReason =>
      'A great fit for reaching my health goals';

  @override
  String get exNearbyGymsMapLabel => 'Gyms near me';

  @override
  String get exGymMapUnavailable => 'Couldn\'t load the map';

  @override
  String get exActivityTitle => 'Activity';

  @override
  String exBurnWeekOfMonthTitle(int month, int week) {
    return 'Burned in week $week, $month/';
  }

  @override
  String get exBurnTodayTitle => 'Burned today';

  @override
  String get exBurnWeekTitle => 'Burned this week';

  @override
  String get exBurnAllTitle => 'Average burned';

  @override
  String exGoalValue(String value) {
    return 'Goal $value';
  }

  @override
  String get exLoadEmpty => 'No records yet.';

  @override
  String get exThisWeek => 'This week';

  @override
  String get exPeriodAll => 'All';

  @override
  String exRestSeconds(int seconds) {
    return 'Rest ${seconds}s';
  }

  @override
  String exStreakCheer(int days) {
    return '$days days in a row!';
  }

  @override
  String get exStreakStart => 'Start a streak with today\'s workout.';

  @override
  String get exStreakProtected => 'Kept by a shield';

  @override
  String get exToday => 'Today';

  @override
  String get exLoadError => 'Couldn\'t load your exercise data.';

  @override
  String get exCompletedPtTitle => 'Today\'s completed PT';

  @override
  String exCompletedPtTime(String time) {
    return '$time completed';
  }

  @override
  String exPtSessionNumber(int count) {
    return 'Session $count';
  }

  @override
  String get exCompletedPtNoProgram => 'No workout program was recorded.';

  @override
  String get exAddExercise => 'Add Exercise';

  @override
  String exDurationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get exEditExercise => 'Edit Exercise Record';

  @override
  String get exSave => 'Save';

  @override
  String get exExerciseType => 'Exercise Type';

  @override
  String get exExerciseDate => 'Date';

  @override
  String get exExerciseName => 'Exercise Name';

  @override
  String get exExerciseNameHintCardio => 'e.g. Treadmill, Indoor cycling';

  @override
  String get exExerciseNameHintStrength => 'e.g. Squat, Bench press';

  @override
  String get exExerciseNameHintFlexibility => 'e.g. Full-body stretch, Yoga';

  @override
  String get exExerciseNameHintOther => 'e.g. Rehab exercise, Sports activity';

  @override
  String get exExerciseReps => 'Reps';

  @override
  String get exExerciseHold => 'Hold time';

  @override
  String get exExerciseStrengthAmount => 'Sets · Reps · Weight';

  @override
  String get exExerciseStrengthAmountHold => 'Sets · Hold · Weight';

  @override
  String get exExerciseMeasure => 'Measured in';

  @override
  String get exExerciseWeight => 'Weight';

  @override
  String get exUnitMinutes => 'min';

  @override
  String get exUnitSets => 'sets';

  @override
  String get exUnitReps => 'reps';

  @override
  String get exUnitSeconds => 'sec';

  @override
  String get exUnitHours => 'hr';

  @override
  String get exUnitKg => 'kg';

  @override
  String get exEnterName => 'Please enter an exercise name';

  @override
  String get exExerciseDuration => 'Duration';

  @override
  String get exExerciseSets => 'Sets';

  @override
  String exSetsCount(int sets) {
    String _temp0 = intl.Intl.pluralLogic(
      sets,
      locale: localeName,
      other: '$sets sets',
      one: '1 set',
    );
    return '$_temp0';
  }

  @override
  String exRepsCount(int reps) {
    String _temp0 = intl.Intl.pluralLogic(
      reps,
      locale: localeName,
      other: '$reps reps',
      one: '1 rep',
    );
    return '$_temp0';
  }

  @override
  String exHoldSecondsCount(int seconds) {
    return '$seconds sec';
  }

  @override
  String get exEnterSets => 'Enter the number of sets';

  @override
  String get exExerciseIntensity => 'Intensity';

  @override
  String get exEstimatedCalories => 'Estimated Calories';

  @override
  String get exCaloriesNeedName => 'Enter an exercise name';

  @override
  String get exCaloriesCalculating => 'Calculating…';

  @override
  String exCaloriesFromCatalog(String activity) {
    return 'Based on $activity · uses your weight';
  }

  @override
  String get exCaloriesRoughEstimate =>
      'A rough average for this exercise type';

  @override
  String get exEnterDuration => 'Please enter a duration';

  @override
  String get exCannotEdit => 'This record can\'t be edited';

  @override
  String get exUpdated => 'Exercise record updated';

  @override
  String get exLogged => 'Exercise logged';

  @override
  String exQueueTitle(int count) {
    return 'To add $count';
  }

  @override
  String get exQueueRemove => 'Remove from list';

  @override
  String exQueueFull(int count) {
    return 'You can add up to $count at a time';
  }

  @override
  String exSaveCount(int count) {
    return 'Save $count';
  }

  @override
  String exLoggedCount(int count) {
    return '$count exercises logged';
  }

  @override
  String get exQueueDiscardTitle => 'Discard exercises to add?';

  @override
  String exQueueDiscardBody(int count) {
    return '$count unsaved exercises will be lost.';
  }

  @override
  String get exQueueDiscard => 'Discard';

  @override
  String get exOwnRecords => 'Workouts you logged';

  @override
  String get exOwnRecordsEmpty => 'No workouts logged';

  @override
  String get exRecordDetailOpen => 'Details';

  @override
  String get exRecordDetailInfo => 'Workout details';

  @override
  String get exRecordDetailTotalCalories => 'Total calories burned';

  @override
  String get exBurnedPrefix => 'Burned';

  @override
  String get exRecordMaxWeight => 'Heaviest yet';

  @override
  String get exRecordLongest => 'Longest yet';

  @override
  String get exRecordFirst => 'First time';

  @override
  String get exRecordDateChange => 'Change date';

  @override
  String exRecordDateMoved(String date) {
    return 'Moved to $date';
  }

  @override
  String get exRecordDateFailed =>
      'Couldn\'t change the date. Please try again shortly.';

  @override
  String get exCompletedPtDayTitle => 'Completed PT';

  @override
  String get exCompletedRoutineDayTitle => 'Completed personal exercises';

  @override
  String get exDeleteExercise => 'Delete workout';

  @override
  String get exDeleteExerciseBody => 'Deleting this record cannot be undone.';

  @override
  String get exDeleted => 'Workout deleted';

  @override
  String get exDeleteFailed => 'Could not delete. Please try again in a moment';

  @override
  String get exCannotDelete => 'This record cannot be deleted';

  @override
  String get exSaveFailed => 'Couldn\'t save. Please try again in a moment';

  @override
  String get exFindGym => 'Find a Gym';

  @override
  String get exGymDetailTitle => 'Gym Details';

  @override
  String get exTrainerDetailTitle => 'Trainer Details';

  @override
  String get exRating => 'Rating';

  @override
  String get exAffiliatedTrainer => 'Affiliated Trainer';

  @override
  String get exRecommendationReason => 'Why we recommend this trainer';

  @override
  String get exGymNotFound => 'Couldn\'t find this gym.';

  @override
  String get exTrainerNotFound => 'Couldn\'t find this trainer.';

  @override
  String get exTrainerReport => 'Report trainer';

  @override
  String get exTrainerReportShort => 'Report';

  @override
  String get exTrainerReportReasonLabel => 'Reason';

  @override
  String get exTrainerReportReasonImpersonation => 'Impersonation';

  @override
  String get exTrainerReportReasonInappropriateMessage =>
      'Inappropriate message';

  @override
  String get exTrainerReportReasonOther => 'Other';

  @override
  String get exTrainerReportMemoLabel => 'Details';

  @override
  String get exTrainerReportMemoHint => 'Tell us what happened';

  @override
  String get exTrainerReportMemoRequired =>
      'Add details to report for another reason';

  @override
  String get exTrainerReportNotice =>
      'Only operators see reports. The trainer isn\'t told who reported them.';

  @override
  String get exTrainerReportSubmit => 'Submit report';

  @override
  String get exTrainerReportSubmitted =>
      'Report received. An operator will review it.';

  @override
  String get exTrainerReportAlreadyOpen =>
      'You already have an open report. An operator is reviewing it.';

  @override
  String get exTrainerSelfRegisteredAffiliation =>
      'Affiliation registered by the trainer';

  @override
  String get exGymSearchPlaceholder => 'Search by area or gym name';

  @override
  String get exSortRecommended => 'Recommended';

  @override
  String get exSortDistance => 'Distance';

  @override
  String get exSortRating => 'Rating';

  @override
  String exResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String get exNoSearchResults => 'No search results.';

  @override
  String get exTrainersLoadError => 'Couldn\'t load trainers.';

  @override
  String get exNearbyGyms => 'Nearby gyms';

  @override
  String get exGymListCollapse => 'Collapse list';

  @override
  String get exGymListExpand => 'Expand list';

  @override
  String get exGymsLoadError => 'Couldn\'t load gyms.';

  @override
  String exGymWeekdayHours(String hours) {
    return 'Weekdays $hours';
  }

  @override
  String exGymWeekendHours(String hours) {
    return 'Weekends $hours';
  }

  @override
  String get exTrainerDedicated => 'Personal trainer';

  @override
  String exTrainerAvailability(String trainer) {
    return '$trainer\'s open booking times';
  }

  @override
  String exSlotWhen(String date, String time) {
    return '$date $time';
  }

  @override
  String get exSlotTypePersonalTraining => '1:1 PT';

  @override
  String get exSlotsEmpty => 'No times available';

  @override
  String get exSlotsAllBooked => 'All available times are fully booked';

  @override
  String get exSlotsLoadError => 'Could not load available times.';

  @override
  String get exReserveFailed => 'Could not book that time. Please try again.';

  @override
  String get exReserveTimeTaken =>
      'Your trainer already has something else at this time, so it can\'t be booked. Please pick another time.';

  @override
  String exReserveConfirmedSlotGym(String slot, String gym) {
    return '$slot · $gym reservation confirmed';
  }

  @override
  String exReserveConfirm(String slot) {
    return 'Confirm $slot';
  }

  @override
  String get exAddress => 'Address';

  @override
  String get exHours => 'Hours';

  @override
  String get exPhone => 'Phone';

  @override
  String get exSpecialty => 'Specialties';

  @override
  String get myTabTitle => 'MY';

  @override
  String get myDefaultUserName => 'User';

  @override
  String get myProfileLoadFailed => 'Couldn\'t load your profile';

  @override
  String get myPointsLoadFailed => 'Couldn\'t load your points balance';

  @override
  String get mySettingsTitle => 'Settings';

  @override
  String get myProfileTitle => 'My Profile';

  @override
  String get myNotifTitle => 'Notification Settings';

  @override
  String get myGuideTitle => 'App guide';

  @override
  String get mySupportTitle => 'Customer Support';

  @override
  String get myPointsBenefitsTitle => 'Use Points';

  @override
  String myPointsBalance(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return 'Balance: ${pointsString}P';
  }

  @override
  String get myPointsBenefitsSubtitle => 'Benefits available with points';

  @override
  String get myPointsBenefitsHint =>
      'Keep logging your activity to earn points and use the benefits above.';

  @override
  String myPointsCost(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return '${pointsString}P';
  }

  @override
  String get myPointsExchange => 'Redeem';

  @override
  String get myPointsExchangeConfirmTitle => 'Redeem points?';

  @override
  String myPointsExchangeConfirmMessage(String item, String cost) {
    return 'Use $cost for $item. You can find the coupon in My benefits.';
  }

  @override
  String get myPointsExchangeConfirmAction => 'Redeem';

  @override
  String get myPointsExchangeDone => 'Redeemed';

  @override
  String get myPointsExchangeFailed => 'Couldn\'t redeem. Please try again.';

  @override
  String myPointsShortfall(String points) {
    return '$points short';
  }

  @override
  String get myPointsNeedTrainer => 'Requires an assigned trainer';

  @override
  String get myPointsNeedGym => 'Requires a connected gym';

  @override
  String get myPointsActiveCoupon => 'You already have an unused coupon';

  @override
  String get myPointsMonthlyLimit => 'You already redeemed this month';

  @override
  String get myPointsShieldLimit => 'You can hold up to 4 shields';

  @override
  String get myShopStreakShieldTitle => 'Streak shield';

  @override
  String get myShopStreakShieldDescription =>
      'Keep your streak going on a day you logged nothing. Use it within the last 30 days; hold up to 4.';

  @override
  String get myBenefitsStreakShields => 'Streak shields';

  @override
  String myBenefitsShieldHeld(int held, int max) {
    return '$held/$max held';
  }

  @override
  String myBenefitsShieldHeldCount(int held) {
    return '$held held';
  }

  @override
  String get myBenefitsShieldGuide =>
      'Tap an empty day on the record graph to bridge it. Only days within the last 30 days.';

  @override
  String get myBenefitsShieldUsedTitle => 'Protected days';

  @override
  String get myBenefitsShieldNoneUsed => 'No protected days yet';

  @override
  String get myShopGraphColorTitle => 'Graph colour';

  @override
  String get myShopGraphColorDescription =>
      'Pick a new colour for the record graph on the points screen. Colours you unlock stay yours.';

  @override
  String get myGraphTitle => 'Record graph';

  @override
  String myGraphMonthLabel(int month) {
    return '$month';
  }

  @override
  String myGraphStreak(int days) {
    return '$days-day record streak';
  }

  @override
  String get myGraphLoadFailed => 'Couldn\'t load the record graph.';

  @override
  String myGraphDate(int month, int day) {
    return '$month/$day';
  }

  @override
  String get myGraphDayHint => 'Tap a square to see that day';

  @override
  String myGraphDayNone(String date) {
    return '$date · nothing logged';
  }

  @override
  String myGraphDayDiet(String date) {
    return '$date · meals only';
  }

  @override
  String myGraphDayExercise(String date) {
    return '$date · workout only';
  }

  @override
  String myGraphDayBoth(String date) {
    return '$date · meals and workout';
  }

  @override
  String myGraphDayProtected(String date) {
    return '$date · kept by a shield';
  }

  @override
  String get myGraphProtectAction => 'Use a shield';

  @override
  String get myGraphProtectConfirmAction => 'Use';

  @override
  String get myGraphProtectConfirmTitle => 'Use a streak shield?';

  @override
  String myGraphProtectConfirmMessage(String date, int held) {
    return 'This keeps $date in your record streak and spends one shield ($held left).';
  }

  @override
  String get myGraphProtectDone => 'Your streak is unbroken';

  @override
  String get myGraphProtectFailed => 'Couldn\'t use the shield';

  @override
  String get myGraphProtectBuyConfirmTitle => 'Buy a streak shield?';

  @override
  String myGraphProtectBuyConfirmMessage(String date, String cost) {
    return 'You don\'t have a shield. Buy one for $cost and use it right away to keep $date in your record streak.';
  }

  @override
  String get myGraphProtectBuyAction => 'Buy and use';

  @override
  String get myGraphProtectBoughtNotUsed =>
      'You bought a shield but couldn\'t use it. It\'s kept in My benefits.';

  @override
  String get myGraphColorTitle => 'Graph colour';

  @override
  String get myGraphColorPickTitle => 'Pick a colour to unlock';

  @override
  String myGraphColorLocked(String cost) {
    return 'Unlock for $cost';
  }

  @override
  String get myGraphColorDone => 'Graph colour changed';

  @override
  String myGraphColorExchangeConfirm(String color, String cost) {
    return 'Unlock the $color graph for $cost? Once unlocked it stays yours.';
  }

  @override
  String get myGraphColorUnlocked => 'Graph colour unlocked';

  @override
  String get myGraphColorFailed => 'Couldn\'t change the colour';

  @override
  String get myGraphColorBlue => 'Blue';

  @override
  String get myGraphColorGreen => 'Green';

  @override
  String get myGraphColorPurple => 'Purple';

  @override
  String get myGraphColorOrange => 'Orange';

  @override
  String get myGraphColorPink => 'Pink';

  @override
  String get myShopProfilePetTitle => 'Profile pet emoji';

  @override
  String get myShopProfilePetDescription =>
      'Pick a dog or a cat to wear next to your name on MY for 7 days.';

  @override
  String get myProfilePetDog => 'Dog';

  @override
  String get myProfilePetCat => 'Cat';

  @override
  String get myProfilePetSheetTitle => 'Pick a pet for your name';

  @override
  String myProfilePetActive(String pet, String left) {
    return '$pet · $left';
  }

  @override
  String myProfilePetDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String myProfilePetHoursLeft(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours left',
      one: '1 hour left',
    );
    return '$_temp0';
  }

  @override
  String myProfilePetExchangeConfirm(String pet, String cost) {
    return 'Wear the $pet next to your name for 7 days for $cost?';
  }

  @override
  String get myProfilePetDone => 'Your pet is next to your name';

  @override
  String get myShopWeeklyReportTitle => 'Weekly report';

  @override
  String myShopWeeklyReportDescription(String range) {
    return 'Look back on $range with a report built from your meals, workouts and reference notes.';
  }

  @override
  String get myWeeklyReportOwned => 'You already have last week\'s report';

  @override
  String myWeeklyReportExchangeConfirm(String range, String cost) {
    return 'Make the report for $range for $cost?';
  }

  @override
  String get myWeeklyReportDone => 'Last week\'s report is ready';

  @override
  String get myBenefitsWeeklyReports => 'Weekly reports';

  @override
  String get myWeeklyReportCardTitle => 'Report from points';

  @override
  String get coachReportPdfSelfMadeNote =>
      'Made with points, without a trainer — so there\'s no trainer feedback.';

  @override
  String get coachReportPdfSectionInsights => 'Reference notes';

  @override
  String get coachReportPdfNoInsights =>
      'No pain or negative feedback this week.';

  @override
  String coachReportPdfInsightSummary(String label, int count) {
    return '$label ×$count';
  }

  @override
  String coachReportPdfInsightMore(int count) {
    return '+$count more';
  }

  @override
  String myProfilePetLabel(String pet) {
    return '$pet pet emoji';
  }

  @override
  String myPointsValidDays(int days) {
    return 'Valid for $days days after redeeming';
  }

  @override
  String get myPointsShopLoadFailed => 'Couldn\'t load rewards';

  @override
  String get myShopPtRenewalTitle => '₩30,000 off PT renewal';

  @override
  String get myShopPtRenewalDescription =>
      'Get ₩30,000 off when you renew PT with your trainer.';

  @override
  String get myShopLockerTitle => 'Free personal locker for 1 month';

  @override
  String get myShopLockerDescription =>
      'Use a personal locker at your gym free for a month.';

  @override
  String get myCouponPtRenewalBenefit => '₩30,000 off PT renewal';

  @override
  String get myBenefitsTitle => 'My benefits';

  @override
  String get myPointsHistoryTitle => 'Points history';

  @override
  String get myPointsHistoryEmpty => 'No points activity yet';

  @override
  String get myPointsHistoryEmptyMessage =>
      'Log meals and workouts to earn points.';

  @override
  String get myPointsHistoryLoadFailed => 'Couldn\'t load your points history';

  @override
  String get myPointsHistoryMore => 'Load more';

  @override
  String get myPointsHistoryMoreFailed =>
      'Couldn\'t load more. Please try again';

  @override
  String get myPointsReasonDiet => 'Meal log';

  @override
  String get myPointsReasonExercise => 'Workout log';

  @override
  String get myPointsReasonRoutine => 'Recommended or assigned workout done';

  @override
  String get myPointsReasonPtRenewal => 'PT renewal discount coupon';

  @override
  String get myPointsReasonLocker => 'Personal locker coupon';

  @override
  String get myPointsReasonShield => 'Streak shield';

  @override
  String get myPointsReasonGraphColor => 'Graph colour';

  @override
  String get myPointsReasonEmotePass => 'Chat emotes for 24 hours';

  @override
  String get myPointsReasonEmoteUnlock => 'Chat emote';

  @override
  String get myPointsReasonProfilePet => 'Profile pet emoji';

  @override
  String get myPointsReasonWeeklyReport => 'Weekly report';

  @override
  String get myPointsReasonChallengeStake => 'Weekly challenge entry';

  @override
  String get myPointsReasonChallengeReward => 'Weekly challenge reward';

  @override
  String myPointsReasonAiChat(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'AI Coach chats ×$count',
      one: 'AI Coach chat',
    );
    return '$_temp0';
  }

  @override
  String get myPointsReasonOther => 'Points';

  @override
  String myPointsKindRevoked(String label) {
    return '$label · taken back after deleting the log';
  }

  @override
  String myPointsKindRefunded(String label) {
    return '$label · refunded after cancelling';
  }

  @override
  String get myBenefitsView => 'View';

  @override
  String get myBenefitsCoupons => 'Coupons';

  @override
  String get myBenefitsEmpty => 'No coupons yet';

  @override
  String get myBenefitsEmptyMessage => 'Redeem your points for a coupon.';

  @override
  String get myBenefitsLoadFailed => 'Couldn\'t load benefits';

  @override
  String get challengeTitle => 'Weekly workout challenge';

  @override
  String challengeShortWithRange(String range) {
    return 'Weekly challenge · $range';
  }

  @override
  String challengeDescription(String stake, int goal, String reward) {
    return 'Stake $stake, work out $goal times this week, and get $reward back';
  }

  @override
  String get challengeJoinWindow => 'You can join on Monday or Tuesday';

  @override
  String get challengeJoin => 'Join';

  @override
  String get challengeJoinConfirmTitle => 'Join this week\'s challenge?';

  @override
  String challengeJoinConfirmMessage(String stake, int goal, String reward) {
    return 'Stake $stake and aim for $goal workouts this week. Reach it by Sunday to get $reward back, or the stake is lost.';
  }

  @override
  String get challengeJoinConfirmAction => 'Join';

  @override
  String get challengeJoinDone => 'You joined this week\'s challenge';

  @override
  String get challengeJoinFailed => 'Couldn\'t join. Please try again.';

  @override
  String get challengeJoinClosed => 'You can join again next Monday';

  @override
  String get challengeThisWeek => 'This week';

  @override
  String challengeProgress(int progress, int goal) {
    return '$progress / $goal workouts';
  }

  @override
  String challengeRemaining(int count, String reward) {
    return '$count more by Sunday to get $reward back';
  }

  @override
  String challengeAchieved(String reward) {
    return 'Goal reached! You get $reward when the week ends';
  }

  @override
  String get myCouponStatusUsable => 'Available';

  @override
  String get myCouponStatusUsed => 'Used';

  @override
  String get myCouponStatusExpired => 'Expired';

  @override
  String get myCouponStatusCancelled => 'Cancelled';

  @override
  String myCouponDaysLeft(int days) {
    return 'D-$days';
  }

  @override
  String get myCouponDDay => 'D-day';

  @override
  String myCouponUntil(String date) {
    return 'Until $date';
  }

  @override
  String get myCouponTrainer => 'Trainer';

  @override
  String get myCouponGym => 'Gym';

  @override
  String get myCouponIssuedOn => 'Redeemed on';

  @override
  String get myCouponExpiry => 'Expires';

  @override
  String myCouponExpiryWithDday(String date, String dday) {
    return '$date ($dday)';
  }

  @override
  String get myCouponStatus => 'Status';

  @override
  String get myCouponStaffNote =>
      'Tap only after your trainer or gym staff has checked it';

  @override
  String get myCouponGymStaffNote => 'Tap only after gym staff has checked it';

  @override
  String get myCouponNoExpiry => 'No expiry';

  @override
  String get myDietTrayTitle => 'Free analysis tray';

  @override
  String get myDietTrayFree => 'Free';

  @override
  String myDietTrayDescription(int window, int days) {
    return 'Log meal photos on $days of the last $window days and we\'ll give you a standard tray made for analysis. Meals shot on the same tray are measured more accurately.';
  }

  @override
  String myDietTrayProgressLabel(int window) {
    return 'Photo logs, last $window days';
  }

  @override
  String myDietTrayProgress(int days, int required) {
    return '$days / $required days';
  }

  @override
  String myDietTrayDaysLeft(int days) {
    return '$days more days of photos to go';
  }

  @override
  String get myDietTrayNeedTrainer => 'Connect a trainer to receive it';

  @override
  String get myDietTrayClaimable =>
      'You\'re eligible! Pick it up at your trainer\'s gym';

  @override
  String myDietTrayIssued(String gym) {
    return 'Pick it up at $gym. Before you go, ask your trainer in chat whether it\'s ready';
  }

  @override
  String get myDietTrayReceived =>
      'You\'ve received your tray. Try shooting meals on it';

  @override
  String get myDietTrayClaim => 'Claim';

  @override
  String get myDietTrayViewCoupon => 'View coupon';

  @override
  String get myDietTrayClaimConfirmTitle => 'Get your tray pickup coupon?';

  @override
  String get myDietTrayClaimConfirmMessage =>
      'Pick it up at your trainer\'s gym. There\'s no deadline, and it\'s one tray per member.';

  @override
  String get myDietTrayClaimDone => 'Tray pickup coupon added';

  @override
  String get myDietTrayClaimFailed => 'Couldn\'t get the tray pickup coupon';

  @override
  String get myDietTrayNotice =>
      'One per member · Only days with meal photos count (typed meals and shield-protected days don\'t) · No pickup deadline · Check with your trainer that the tray is ready before visiting the gym · Terms may change depending on stock and operations';

  @override
  String get myDietTrayCouponBenefit => 'Standard analysis tray';

  @override
  String get myDietTrayStaffNote => 'Tap after gym staff hands you the tray';

  @override
  String get myDietTrayIssuedOn => 'Received on';

  @override
  String get myDietTrayExpireNotice =>
      'No expiry. Before you go to the gym, ask your trainer in chat whether the tray is ready.';

  @override
  String get myCouponStaffConfirmTitle => 'Mark this coupon as used?';

  @override
  String get myCouponStaffConfirmMessage =>
      'For staff · This can\'t be undone once used';

  @override
  String get myCouponUsedAt => 'Used at';

  @override
  String myCouponUsedBanner(String time) {
    return 'Used on $time';
  }

  @override
  String get myCouponExpireNotice =>
      'Points aren\'t refunded once the coupon expires.';

  @override
  String get myCouponUse => 'Mark as used';

  @override
  String get myCouponUseDone => 'Marked as used';

  @override
  String get myCouponUseFailed => 'Couldn\'t mark as used. Please try again.';

  @override
  String get myCouponNotFound => 'Coupon not found';

  @override
  String get a11yCoachPhoto => 'Photo from your trainer';

  @override
  String get a11yMealPhoto => 'Meal photo';

  @override
  String a11yMealPhotoOf(String name) {
    return 'Photo of $name';
  }

  @override
  String get myLogout => 'Log out';

  @override
  String get myLogoutConfirm => 'Log out of your account?';

  @override
  String get emoteSheetTitle => 'Emotes';

  @override
  String get emoteBuyTitle => 'Buy emote';

  @override
  String emoteBuyConfirm(int cost, int days) {
    return 'Use this emote for $days days for ${cost}P?\nThe days start the moment you buy.';
  }

  @override
  String get emoteBuyAction => 'Buy';

  @override
  String get emoteBought => 'You can send this emote now';

  @override
  String get emoteBuyFailed =>
      'We could not buy the emote. Please try again in a moment.';

  @override
  String get emoteAlreadyUnlocked =>
      'This emote is already unlocked. You can send it now';

  @override
  String get emoteTrainerRequired => 'You need a trainer to buy emotes';

  @override
  String get emoteShortfall => 'Not enough points';

  @override
  String get emoteLoadFailed => 'We could not load the emotes';

  @override
  String get emoteSendFailed => 'We could not send the emote';

  @override
  String get a11yOpenEmotes => 'Emotes';

  @override
  String get a11yEmote => 'Emote';

  @override
  String get myWithdrawTitle => 'Delete account';

  @override
  String get myWithdrawConfirm =>
      'Deleting your account erases the diet, exercise and health records you saved, removes your trainer link and the messages you exchanged, and deletes your points, unused coupons, shields and decorative items. Upcoming PT bookings and pending consultation requests are cancelled. This cannot be undone.';

  @override
  String myWithdrawLosePoints(int points) {
    final intl.NumberFormat pointsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String pointsString = pointsNumberFormat.format(points);

    return '• Your balance of ${pointsString}P will be deleted';
  }

  @override
  String myWithdrawLoseCoupons(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '• Your $count unused coupons will be deleted',
      one: '• Your unused coupon will be deleted',
    );
    return '$_temp0';
  }

  @override
  String myWithdrawCancelReservations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '• Your $count upcoming PT bookings will be cancelled',
      one: '• Your upcoming PT booking will be cancelled',
    );
    return '$_temp0';
  }

  @override
  String myWithdrawCancelConsultations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '• Your $count pending consultation requests will be cancelled',
      one: '• Your pending consultation request will be cancelled',
    );
    return '$_temp0';
  }

  @override
  String get myWithdrawAction => 'Delete account';

  @override
  String get myWithdrawFailed =>
      'We could not delete your account. Please try again in a moment.';

  @override
  String get myWithdrawReasonTitle =>
      'Are you sure you want to delete your account?';

  @override
  String get myWithdrawReasonQuestion => 'What did not work for you?';

  @override
  String get myWithdrawReasonHint => 'You can pick more than one';

  @override
  String get myWithdrawReasonPrivacy =>
      'I am worried my personal data could be exposed';

  @override
  String get myWithdrawReasonRarelyUsed => 'I do not use it often';

  @override
  String get myWithdrawReasonHardToUse => 'It is awkward to use';

  @override
  String get myWithdrawReasonNotifications => 'Too many notifications';

  @override
  String get myWithdrawReasonAlternative => 'I am using another app';

  @override
  String get myWithdrawReasonOther => 'Something else';

  @override
  String get myWithdrawNext => 'Next';

  @override
  String get myWithdrawKeepTitle => 'Before you go';

  @override
  String get myWithdrawKeepPrivacy =>
      'Your records are never shown to strangers. Only you and the trainer you are linked with can see them, and once you disconnect the trainer they are yours alone — you can do that from My Gym & Trainer on the MY tab.';

  @override
  String get myWithdrawKeepRarelyUsed =>
      'You do not have to log everything every day. The + in the middle lets you add a single meal or workout from any screen.';

  @override
  String get myWithdrawKeepHardToUse =>
      'Tell us what got in the way and we will fix it. The 1:1 Inquiry under MY > Customer Support reaches us directly.';

  @override
  String get myWithdrawKeepNotifications =>
      'Notifications can be switched off one kind at a time. Keep only what you want under MY > Notification Settings.';

  @override
  String get myWithdrawKeepAlternative =>
      'Removing the app leaves your records untouched. Deleting the account is what erases them, and that cannot be undone.';

  @override
  String get myWithdrawKeepOther =>
      'Whatever it is, tell us and we will act on it. Leave it in the 1:1 Inquiry under MY > Customer Support.';

  @override
  String get myWithdrawKeepDefault =>
      'The diet and exercise records you have built up, your points and your unused coupons go with the account, and they cannot be restored. Upcoming bookings are cancelled.';

  @override
  String get myWithdrawStay => 'Keep using On-Care';

  @override
  String get myWithdrawContinue => 'Continue deleting';

  @override
  String get myCancel => 'Cancel';

  @override
  String get myGymTrainerTitle => 'My Gym & Trainer';

  @override
  String get myConnectionDeleteTitle => 'Remove Connection';

  @override
  String get myConnectionDeleteFailed =>
      'Couldn\'t remove the connection. Please try again.';

  @override
  String get myDelete => 'Remove';

  @override
  String myGymDisconnectWithTrainerConfirm(String gym, String trainer) {
    return 'Disconnect $gym?\nYour trainer link with $trainer will also be removed.\nYour data-sharing consent will also be withdrawn, so the trainer will no longer see your new records. Messages and reports you have already exchanged are not deleted, and you can see them again if you reconnect with the same trainer.';
  }

  @override
  String myGymDisconnectConfirm(String gym) {
    return 'Disconnect $gym?';
  }

  @override
  String myTrainerDisconnectConfirm(String trainer, String gym) {
    return 'Disconnect trainer $trainer?\nYour connection to $gym will remain.\nYour data-sharing consent will also be withdrawn, so the trainer will no longer see your new records. Messages and reports you have already exchanged are not deleted, and you can see them again if you reconnect with the same trainer.';
  }

  @override
  String get myGymDetailTooltip => 'Gym details';

  @override
  String get myTrainerDetailTooltip => 'Trainer details';

  @override
  String get myGymDisconnectTooltip => 'Disconnect gym';

  @override
  String get myTrainerDisconnectTooltip => 'Disconnect trainer';

  @override
  String get myNoTrainer => 'No assigned trainer';

  @override
  String get myNoGymConnected => 'No gym connected yet';

  @override
  String get myGymLoadFailed => 'Couldn\'t load your gym connection.';

  @override
  String get mySave => 'Save';

  @override
  String get myProfileSaved => 'Profile saved';

  @override
  String get mySaveFailed => 'Couldn\'t save. Please try again in a moment';

  @override
  String get myProfileEmailTaken => 'That email is already in use';

  @override
  String get myProfilePhoneRequired => 'Your phone number can\'t be left empty';

  @override
  String get myProfileInvalid => 'Please check what you entered';

  @override
  String get myFieldName => 'Name';

  @override
  String get myFieldEmail => 'Email';

  @override
  String get myFieldPhone => 'Phone';

  @override
  String get myFieldBirth => 'Date of birth';

  @override
  String get myFieldGender => 'Gender';

  @override
  String get myFieldHeight => 'Height (cm)';

  @override
  String get myFieldWeight => 'Weight (kg)';

  @override
  String get myNotifExercise => 'Exercises & programs';

  @override
  String get myNotifTrainer => 'Trainer message';

  @override
  String get myNotifWeeklyReport => 'Trainer weekly report';

  @override
  String get myNotifExerciseDesc =>
      'When your trainer sends personal exercises or a PT program, or leaves a PT record or feedback';

  @override
  String get myNotifTrainerDesc => 'When your trainer sends you a chat message';

  @override
  String get myNotifWeeklyReportDesc =>
      'When your trainer sends your weekly report';

  @override
  String get myNotifAlwaysSent =>
      'PT session bookings, changes and cancellations, and trainer connect or disconnect notices are always sent';

  @override
  String get mySupportFaq => 'FAQ';

  @override
  String get mySupportInquiry => '1:1 Inquiry';

  @override
  String get myLegalTermsTitle => 'Terms of Service';

  @override
  String get myLegalPrivacyTitle => 'Privacy Policy';

  @override
  String get myOpenSourceLicensesTitle => 'Open-source licenses';

  @override
  String get myLegalTermsBody =>
      'Article 1 (Purpose)\nThese Terms govern the rights, obligations and responsibilities between On-Care (the \"Company\") and its members in connection with the use of the health management service (the \"Service\") the Company provides.\n\nArticle 2 (Effect and Amendment of the Terms)\n(1) These Terms apply to every member who uses the Service.\n(2) The Company may amend these Terms within the limits of applicable law. Any amendment is announced inside the Service before it takes effect, together with its effective date and the reason for the change.\n(3) Where an amendment requires consent, the Company asks for consent again. A member who does not agree to the amended Terms may terminate the agreement.\n\nArticle 3 (Membership and Accounts)\n(1) Only people aged 14 or over may sign up.\n(2) Each person uses one account. You may not sign up with someone else\'s details, or transfer or lend your account to anyone else.\n(3) You are responsible for your account details, including your password and linked social logins. If you find that someone else is using your account, change your password at once and tell the Company.\n\nArticle 4 (Provision of the Service)\nThe Company provides features that support a member\'s health management, including diet records, exercise records, health indicator tracking, AI coaching, and linking, messaging and booking with an assigned trainer. The specific contents of the Service may change in line with the Company\'s policy.\n\nArticle 5 (Points)\n(1) Members receive points for the activities described in the app, such as logging meals and workouts. The points for each activity and the daily limits follow the guidance in the app.\n(2) Points can only be exchanged for coupons and items inside the Service. Points have no cash value, cannot be cashed out or refunded, and cannot be transferred to anyone else.\n(3) If you delete a record that earned points, those points are taken back. Points obtained by abnormal means, such as uploading the same record repeatedly, may also be taken back.\n(4) The Company may change how points are earned and what items cost, and announces the change inside the Service beforehand. Coupons and items already exchanged are not affected.\n(5) When you delete your account, your remaining points and their history are deleted with it and cannot be restored.\n\nArticle 6 (Coupons and Exchange Items)\n(1) Members may exchange points for the coupons described in the app, such as a PT renewal discount coupon or a personal locker coupon. The benefit of a coupon is provided on site by the assigned trainer or gym linked to the member.\n(2) A coupon can only be used within the validity period shown in the app. A coupon exchanged for points is valid for 30 days from the day of exchange. An expired coupon lapses, and the points spent on it are not returned.\n(3) If your link to the trainer or gym where the coupon is used ends, any unused coupon for it is cancelled and the points spent on it are returned.\n(4) A coupon is used when staff on site have checked it and you then tap \"Mark as used\" on your own phone. A coupon marked as used cannot be restored.\n(5) Coupons cannot be transferred or exchanged for cash.\n\nArticle 7 (Time-Limited Items and Shields)\n(1) Decorative items such as profile pets and emotes can be used only for the period shown in the app, and disappear when it ends.\n(2) A streak shield keeps your recording streak from breaking on a day you could not record. How to use it and how many you can hold follow the guidance in the app.\n(3) The items and shields in this Article also have no cash value, cannot be transferred, and are deleted when you delete your account.\n\nArticle 8 (Bookings and Consultation Requests)\n(1) Members may book PT in the times their assigned trainer has opened, or send a trainer a consultation request. When you can request or cancel, and when a pending consultation request expires, follow the guidance in the app.\n(2) The PT contract itself, and its payment and refunds, is a separate agreement between the member and the trainer or gym. The Company provides the tools for linking and booking.\n\nArticle 9 (Obligations of the Member)\nMembers must enter their own health information accurately. Information provided by the Service does not replace a medical diagnosis or treatment. If you have a health problem, please consult a qualified medical institution.\n\nArticle 10 (Restrictions on Use)\nIf a member does any of the following, the Company may, after notice, restrict all or part of their use of the Service or suspend the account. Where it is urgent, for example to protect other users, the Company restricts first and notifies right after.\n- Using someone else\'s details or transferring an account\n- Obtaining points or using coupons by abnormal means\n- Harming trainers or other users through abuse or harassment\n- Interfering with the operation of the Service\n\nArticle 11 (Termination and Its Effects)\n(1) Members may terminate the agreement at any time by deleting their account from the MY tab.\n(2) Deleting your account erases your profile, diet, exercise and health records, AI coach conversations, and your link and messages with your assigned trainer. Your remaining points and their history, unused coupons, shields and decorative items are deleted as well. Nothing deleted can be restored.\n(3) Upcoming PT bookings and pending consultation requests are cancelled, and the trainers concerned are told that you have left.\n(4) Records that the destruction procedure of the Privacy Policy says are kept, such as sessions already on a trainer\'s schedule, remain to that extent.\n\nArticle 12 (Changes to and Suspension of the Service)\n(1) The Company may change the Service or end some of its features, and announces any change that affects members inside the Service beforehand.\n(2) The Company may suspend the Service temporarily for unavoidable reasons such as maintenance or replacement of equipment, outages or natural disasters. If notice could not be given in advance, it is given afterwards.\n(3) If the Company ends the Service as a whole, it announces this beforehand together with how remaining points and unused coupons will be handled.\n\nArticle 13 (Limitation of Liability)\nTo the extent permitted by law, the Company is not liable for decisions a member makes on the basis of information obtained through the Service, nor for the consequences of those decisions.\n\nArticle 14 (Dispute Resolution and Jurisdiction)\n(1) The Company and members will negotiate in good faith to settle any dispute about the Service amicably. Members may send questions or complaints to the contact given in the Privacy Policy.\n(2) If a dispute is not settled by negotiation and a lawsuit is filed, the court with jurisdiction under the Civil Procedure Act of Korea has jurisdiction.\n(3) These Terms and the use of the Service are governed by the laws of the Republic of Korea.\n\nAddendum\nThese Terms take effect on 3 October 2026.\n- 3 October 2026: added membership and accounts, points, coupons and exchange items, time-limited items and shields, bookings and consultation requests, restrictions on use, termination and its effects, changes to and suspension of the Service, and dispute resolution and jurisdiction\n- 1 October 2026: first issued\n\nThis is a translation of the Korean original for reference. In case of any discrepancy, the Korean version governs.';

  @override
  String myLegalPrivacyBody(String contact) {
    return 'On-Care (the \"Company\") complies with the Personal Information Protection Act and other applicable laws, and protects its members\' personal information with care.\n\n1. Personal information collected\n(1) Sign-up: email address, password (stored encrypted) and name. If you sign up with a social login (Kakao, Google, Naver or Apple), we receive the member identifier, email address and name that service passes on.\n(2) Profile and first setup: phone number, date of birth, gender, height, weight, health goals and diet and exercise targets.\n(3) Information you leave while using the Service: meal records and food photos, workout records, health indicators such as body weight, conversations with the AI coach, messages and attached photos exchanged with your trainer, and consultation and booking requests.\n(4) Information generated automatically: access logs such as sign-ins and password changes (time and IP address), and, when an error occurs, the error details, device type, operating system and app version.\n(5) Location: only if you allow your current location in gym search, we receive the device\'s current coordinates and use them to search nearby. They are not saved to your account.\n\n2. Purpose of collection and use\nThe personal information collected is used only to identify members, provide health management features such as food photo analysis and nutrition calculation, deliver personalised AI coaching, connect you with a trainer, improve the Service and respond to customer enquiries.\n\n3. Retention and use period\nA member\'s personal information is kept until the member withdraws from the Service, and is then destroyed without delay following section 10. The following records are kept for the stated period and then destroyed.\n- Access logs such as sign-ins: one year (covering the three-month retention of sign-in records required by the Protection of Communications Secrets Act)\n- Records of trainers opening members\' health information, of data-sharing consent being given or withdrawn, and of account deletion: two years (processing records kept under the Standards for Personal Information Security Measures)\nA reason chosen when deleting an account is kept only as a reason code and a time, with no link to the member.\n\n4. Provision to third parties\nThe Company does not provide personal information to any third party without the member\'s consent. Sharing with your trainer follows section 5, and processing entrusted to service providers follows sections 6 and 7. The exception is where a law specifically provides otherwise.\n\n5. Sharing with your trainer and withdrawing consent\nWhen you agree to data sharing by requesting a consultation, accepting a coaching request or issuing a pairing code, your assigned trainer can see your meal records, workout records, body information, health goals, and health notes & cautions. You can withdraw this consent at any time by removing your trainer or gym connection in the MY tab, and consent is also treated as withdrawn when the trainer ends the coaching relationship. The Company records when consent was given and when it was withdrawn. After you withdraw, the trainer can no longer see your new records, and reconnecting with the same trainer requires your consent again. Conversations you exchanged with the trainer and reports delivered before the withdrawal are not deleted.\n\n6. Entrusted processing\nThe Company entrusts the following work to outside providers to deliver the Service. If a provider changes, this policy is updated to say so.\n- Amazon Web Services, Inc.: running the servers and storing chat photos and report PDFs\n- Neon: running the database (account information and all records)\n- Google LLC: food photo recognition, generating AI coach answers and recommendations, and building the search index the AI coach uses to look up your records (Gemini API)\n- Kakao Corp.: gym and place search and map display\n- Functional Software, Inc. (Sentry): collecting and analysing app and server errors\n\n7. Transfer of personal information overseas\nTo perform its contract with members, the Company has personal information processed and stored overseas as follows, and discloses this in this policy under Article 28-8(1)(3) of the Personal Information Protection Act. Each transfer happens over an encrypted network connection whenever the Service is used.\n(1) Amazon Web Services, Inc. / Singapore / member information and records in general, chat photo attachments and report PDFs / running the servers and storing files / until the member withdraws or the contract with the provider ends\n(2) Neon / Singapore / account, profile, diet, workout and health records and conversation records / running the database / until the member withdraws or the contract with the provider ends\n(3) Google LLC / the United States and other countries where Google operates data centres / food photos, the diet and workout records, body information and health goals needed for analysis, and conversations with the AI coach / AI analysis, answer generation and search indexing / for the period set in the provider\'s terms of service after the request is processed\n(4) Functional Software, Inc. (Sentry) / the United States / error details, device type, operating system and app version (name, email address, IP address and request contents are not sent) / error analysis / the provider\'s retention period\nEach time you save a meal or workout record, its contents are sent to (3) to build the AI coach\'s search index. If you do not want your information transferred overseas, you can refuse by deleting your account, but you will then be unable to use the Service.\n\n8. Processing of sensitive (health) information\nHealth information such as diet and workout records, body information, health goals, and health notes & cautions is processed under Article 23 of the Personal Information Protection Act only with a separate consent obtained at sign-up, apart from other personal information. It is shared with your trainer only with the consent described in section 5.\n\n9. Children under 14\nThe Company does not accept sign-ups from children under 14, and confirms at sign-up that you are 14 or older.\n\n10. Destruction procedure and method\n(1) Procedure: when you delete your account in the MY tab, the Company immediately deletes the account together with your profile, meal and workout records and food photos, AI coach conversations and search index, notifications, social login links, and your trainer connection and conversations (including attached photos and report PDF files). Pending consultation requests and bookings are cancelled, and the trainers involved are told that you have left. Sessions already on a trainer\'s schedule keep your display name and the date and time as the trainer\'s work record. Records kept under section 3 are deleted automatically when their period ends.\n(2) Method: information held as electronic files is deleted from the database and file storage, and copies remaining in database recovery backups disappear when the backup retention period ends. The Company does not handle personal information on paper.\n\n11. Automatic collection tools\nThe Company does not use cookies or tracking tools for advertising or behavioural analysis. On the web, sign-in information is kept in browser storage to keep you signed in, and is removed when you sign out or clear your browser data.\n\n12. Safeguards\nThe Company stores passwords encrypted, encrypts traffic in transit, and limits trainers\' access to member information by assignment. When a trainer opens a member\'s health information, only the trainer, the member, the kind of information and the time are recorded, never the health information itself. Error reports are sent with names, email addresses, IP addresses and request contents removed.\n\n13. Rights of the user and how to exercise them\nMembers may at any time view or correct their personal information, or request that its processing be suspended and the information deleted. You can edit your profile, delete your account and withdraw trainer-sharing consent in the MY tab. For any other request, contact the address in section 14 and it will be handled without delay.\n\n14. Personal information protection officer\nThe Company has appointed a personal information protection officer who oversees the processing of personal information and handles related complaints and remedies.\n- Position: Personal information protection officer, On-Care service operations team\n- Contact: $contact\n\n15. Remedies for infringement\nFor reports or advice about an infringement of personal information, you can contact the following bodies (in Korea).\n- Personal Information Dispute Mediation Committee: 1833-6972 (www.kopico.go.kr)\n- Personal Information Infringement Report Center: 118 (privacy.kisa.or.kr)\n- Supreme Prosecutors\' Office: 1301 (www.spo.go.kr)\n- Korean National Police Agency: 182 (ecrm.police.go.kr)\n\n16. Changes to this policy\nIf this policy changes, the Company announces it in the app before the effective date, and asks for consent again where the change requires it.\n- 5 October 2026: changed the contact address of the personal information protection officer\n- 3 October 2026: added entrusted processing, overseas transfer, sensitive information, children under 14, destruction procedure, automatic collection tools, safeguards, protection officer and remedies sections\n- 1 October 2026: first issued\n\nEffective date: 5 October 2026\n\nThis is a translation of the Korean original for reference. In case of any discrepancy, the Korean version governs.';
  }

  @override
  String get myLegalTermsEffectiveDate => 'Effective Oct 3, 2026';

  @override
  String get myLegalPrivacyEffectiveDate => 'Effective Oct 5, 2026';

  @override
  String myAppVersion(String version) {
    return 'On-Care · Version $version';
  }

  @override
  String get myAppName => 'On-Care';

  @override
  String get coachHeaderPill => 'AI Health Assistant';

  @override
  String get coachHeaderSubtitle => 'Here are today\'s tailored tips';

  @override
  String get coachCardDietTag => 'Diet';

  @override
  String get coachCardDietTitle => 'Great breakfast — watch lunch sodium';

  @override
  String get coachCardDietBody =>
      'Breakfast was nicely balanced. The jjamppong you had for lunch can be heavy on sodium and sugar, so drink plenty of water today. For the rest of the day, pair vegetables with protein to keep things balanced.';

  @override
  String get coachCardExerciseTag => 'Exercise';

  @override
  String get coachCardExerciseTitle => '3 workouts this week';

  @override
  String get coachCardExerciseBody =>
      'You finished three workouts this week — staying consistent is what counts. Take your time with the rotator-cuff shoulder stretches and wind down with light cardio. Afterwards, rest and rehydrate rather than pushing on.';

  @override
  String get coachCardWaterTag => 'Hydration';

  @override
  String get coachSheetErrorTitle => 'Couldn\'t load your advice';

  @override
  String get coachSheetErrorBody => 'Check your connection and try again.';

  @override
  String get coachSheetEmptyTitle => 'Advice will appear as you log more';

  @override
  String get coachSheetEmptyBody => 'Try logging today\'s meals and workouts.';

  @override
  String get coachInviteTitle => 'A trainer wants to coach you';

  @override
  String coachInviteFrom(String name) {
    return 'Trainer $name';
  }

  @override
  String coachInviteGym(String gym) {
    return 'at $gym';
  }

  @override
  String get coachInviteExplain =>
      'Accepting lets this trainer see your meal records, workout records, body information, health goals, and health notes & cautions. You\'ll be asked to agree to sharing before you accept.';

  @override
  String get coachInviteAccept => 'Accept';

  @override
  String get coachInviteReject => 'Decline';

  @override
  String coachInviteAccepted(String name) {
    return '$name is now your coach';
  }

  @override
  String get coachInviteRejected => 'Request declined';

  @override
  String get coachInviteFailed => 'Couldn\'t complete that. Please try again';

  @override
  String get coachImageUnavailable => 'Couldn\'t load the photo';

  @override
  String get coachChatSubtitle => 'Personal trainer';

  @override
  String get coachChatLoadOlder => 'Load older messages';

  @override
  String get coachChatLoadFailed => 'Couldn\'t load the conversation';

  @override
  String get coachChatUnassigned =>
      'Your trainer is no longer assigned, so you can\'t send messages here';

  @override
  String coachChatEmptyTitle(String trainer) {
    return 'Start a conversation with $trainer';
  }

  @override
  String get coachChatEmptyBody =>
      'Send a photo of what you ate today or ask about your workouts';

  @override
  String get coachChatSendFailed =>
      'Couldn\'t send your message. Please try again';

  @override
  String get coachPhotoAttach => 'Send a photo';

  @override
  String get coachPhotoSheetSubtitle =>
      'Share a meal, form, or InBody photo with your trainer';

  @override
  String get coachPhotoPickSub => 'Choose from your photo library';

  @override
  String get coachPhotoTakeSub => 'Take one with the camera';

  @override
  String get coachPhotoSending => 'Sending';

  @override
  String get coachPhotoSendFailed => 'Couldn\'t send the photo';

  @override
  String get coachPhotoRetry => 'Retry';

  @override
  String get coachPhotoDiscard => 'Remove';

  @override
  String get coachPhotoPermissionDenied =>
      'Allow camera and photo access to send a photo';

  @override
  String get coachPhotoPermissionPermanentlyDenied =>
      'Camera and photo access is off. Turn it on in Settings to send photos';

  @override
  String get coachPhotoReadFailed =>
      'Couldn\'t read that photo. Please try a different one';

  @override
  String get a11yMyPhoto => 'Photo you sent';

  @override
  String get coachChatPdfOpenFailed =>
      'Couldn\'t open the PDF. Please try again';

  @override
  String get coachChatReportRegistered => 'Weekly report added';

  @override
  String coachChatReportWeek(int sm, int sd, int em, int ed) {
    return '$sm/$sd – $em/$ed';
  }

  @override
  String get coachChatReportPreviewPdf => 'Preview PDF';

  @override
  String coachReportPdfBullet(String label, String value) {
    return '· $label: $value';
  }

  @override
  String coachReportPdfFileName(String date) {
    return 'weekly-report_$date.pdf';
  }

  @override
  String get coachChatInputHint => 'Message your trainer...';

  @override
  String get coachChatRoutineReceived => 'Your trainer sent a workout';

  @override
  String get coachChatRoutineReceivedPt =>
      'You received a PT program and personal exercises';

  @override
  String get coachChatRoutineReceivedPersonal =>
      'You received personal exercises';

  @override
  String get coachChatRoutineReceivedAfterCancel =>
      'You received personal exercises in place of the cancelled PT';

  @override
  String get coachChatRoutineReceivedProgram => 'You received a PT program';

  @override
  String coachChatRoutineReceivedMore(String names, int count) {
    return '$names and $count more';
  }

  @override
  String coachChatDateDivider(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMEEEEd(
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get coachCtaChat => 'Chat with AI';

  @override
  String get navAddRecordTitle => 'Add a record';

  @override
  String get navAddRecordSubtitle => 'Choose diet or exercise';

  @override
  String get navDietOptionSub => 'Nutrition analysis from a photo';

  @override
  String get navExerciseOptionSub => 'Log the type and duration';

  @override
  String get aicHeaderSubtitle => 'Ask me anytime';

  @override
  String get aicMedicalDisclaimer =>
      'The AI coach is a reference for diet and exercise habits, not a diagnosis or prescription. Please consult a doctor about symptoms.';

  @override
  String get aicInputHint => 'Ask the AI anything';

  @override
  String aicQuotaFreeLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count free chats left today',
      one: '1 free chat left today',
    );
    return '$_temp0';
  }

  @override
  String aicQuotaPaidNext(String cost, int used, int limit) {
    return 'Next chat $cost · Bought today $used/$limit';
  }

  @override
  String get aicQuotaExhausted =>
      'You\'ve used today\'s chats. They reopen tomorrow';

  @override
  String get aicAiCapacity =>
      'AI features are taking a break due to high demand. Please try again tomorrow';

  @override
  String get aicQuotaFindTrainer => 'Find a trainer';

  @override
  String get aicPaidConfirmTitle => 'Keep chatting with points?';

  @override
  String aicPaidConfirmMessage(String cost, int limit, String balance) {
    return 'You\'ve used today\'s free chats. Sending this one costs $cost (up to $limit today).\n\nBalance $balance';
  }

  @override
  String get aicPaidConfirmAction => 'Send with points';

  @override
  String aicPaidInsufficient(String shortfall) {
    return 'You need $shortfall more. Log meals and workouts to earn points.';
  }

  @override
  String aicPointsSpent(String spent) {
    return '−$spent';
  }

  @override
  String get aicQuickRepliesLabel => 'Try asking';

  @override
  String get aicGeneratingReply => 'Writing your answer';

  @override
  String aicInsightDiscomfortPart(String part) {
    return '$part pain noted';
  }

  @override
  String get aicBodyPartKnee => 'Knee';

  @override
  String get aicBodyPartBack => 'Back';

  @override
  String get aicBodyPartAnkle => 'Ankle';

  @override
  String get aicBodyPartShoulder => 'Shoulder';

  @override
  String get aicBodyPartWrist => 'Wrist';

  @override
  String get aicBodyPartNeck => 'Neck';

  @override
  String get aicInsightDiscomfort => 'Pain noted';

  @override
  String get aicInsightNegative => 'Negative feedback noted';

  @override
  String get aicInsightDelete => 'Delete';

  @override
  String get aicInsightDeleteConfirm =>
      'Remove this detection from your reference notes? What you wrote stays in the conversation.';

  @override
  String get aicInsightDeleteFailed =>
      'We could not remove it. Please try again in a moment.';

  @override
  String get aicInsightHistoryTitle => 'Reference notes';

  @override
  String get aicInsightHistoryAction => 'Reference notes';

  @override
  String aicInsightHistorySubtitle(int days) {
    return 'Pain and negative feedback noted in the last $days days. The AI uses these when it answers';
  }

  @override
  String aicInsightHistoryEmpty(int days) {
    return 'Nothing noted in the last $days days';
  }

  @override
  String get aicInsightHistoryFailed => 'Couldn\'t load reference notes';

  @override
  String aicRetentionNotice(int days) {
    return 'AI chat history is kept for the last $days days';
  }

  @override
  String get aicTrainerConnectedTitle => 'Chat with your trainer';

  @override
  String aicTrainerConnectedBody(String name) {
    return 'You\'re connected with $name. Members with a trainer chat with their trainer instead of the AI chatbot';
  }

  @override
  String get aicQuickReply1 => 'Recommend a dinner menu for today';

  @override
  String get aicQuickReply2 => 'How much should I exercise today?';

  @override
  String get aicQuickReply3 => 'How much sodium have I had today?';

  @override
  String get exConsultRequestTitle => 'Consultation Request';

  @override
  String get exGymConsultRequest => 'Request a Consultation';

  @override
  String get exGymConsultPickTrainer => 'Choose a trainer';

  @override
  String get exGymConsultPickTrainerHint => 'Your request goes to one trainer.';

  @override
  String get exGymConsultNoTrainers => 'No trainers are affiliated yet.';

  @override
  String get exGymTrainersLoadError => 'Couldn\'t load this gym\'s trainers.';

  @override
  String get exTrainerConsultRequest => 'Request a Trainer Consultation';

  @override
  String get exConsultPendingCta => 'Consultation Request Pending';

  @override
  String get exConsultLinkedToOtherTrainer =>
      'You\'re connected with your trainer. To request a consultation with another trainer, disconnect from your trainer first.';

  @override
  String get exConsultGoToMyTrainer => 'View my trainer';

  @override
  String get exViewConsultationRequest => 'View consultation request';

  @override
  String get exConsultTarget => 'Consultation Target';

  @override
  String get exTrainerConsultType => 'Trainer Consultation';

  @override
  String get exAssignedTrainer => 'Assigned Trainer';

  @override
  String get exConsultDataSharingNotice =>
      'Your request details (name, exercise goal, and message) go to this trainer for the consultation and stay with the request and its schedule after you send them. If you don\'t agree, you just can\'t send this request; everything else keeps working. Your meal and workout records are shared only if you register with a connection code after the consultation, with a separate consent.';

  @override
  String get exConsultDataSharingAgree =>
      'I have read this and agree to send my request details to this trainer';

  @override
  String get exConsultDataSharingRequired =>
      'Please agree to sending your request details before requesting a consultation';

  @override
  String get exConsultDataSharingLinked =>
      'This is your trainer, so your meal and workout records and body information are already shared. No need to agree again.';

  @override
  String get exConsultGoalPrefilled =>
      'We filled this in from your health goals in MY. Feel free to change it for this consultation.';

  @override
  String get coachInviteConsentTitle => 'Before you connect';

  @override
  String coachInviteConsentBody(String name) {
    return 'Once $name becomes your trainer, they can see your meal records, workout records, body information, health goals, and health notes & cautions for coaching, consultations and writing reports. Disconnecting also revokes that access, but the conversations you had and the reports already delivered before then remain. You can keep using your personal records even if you don\'t agree.';
  }

  @override
  String get coachInviteConsentAgree => 'Agree and connect';

  @override
  String get exConsultSlotTitle => 'Available times';

  @override
  String get exConsultSlotRequired => 'Please choose an available time.';

  @override
  String get exConsultSlotsEmptyTitle =>
      'No consultation times are open right now.';

  @override
  String exConsultSlotsEmptyBody(String gym, String phone) {
    return 'Call $gym at $phone to ask for a consultation time.';
  }

  @override
  String exConsultSlotsEmptyNoPhone(String gym) {
    return 'Open the $gym details for its address and hours.';
  }

  @override
  String get exConsultSlotsError => 'Could not load the available times.';

  @override
  String get exConsultSlotTaken =>
      'Another member just took that time. Please choose another.';

  @override
  String exConsultTooManyPending(int count) {
    return 'You already have $count consultation requests waiting for a reply. Wait for an answer or cancel one, then try again.';
  }

  @override
  String exConsultRateLimitedHours(int hours) {
    return 'Too many consultation requests. Please try again in $hours hours.';
  }

  @override
  String exConsultRateLimitedMinutes(int minutes) {
    return 'Too many consultation requests. Please try again in $minutes minutes.';
  }

  @override
  String get exConsultRateLimited =>
      'Too many consultation requests. Please try again later.';

  @override
  String get exConsultTooManyPendingNoCount =>
      'You have too many consultation requests waiting for a reply. Wait for an answer or cancel one, then try again.';

  @override
  String get exGymCall => 'Call';

  @override
  String get exGymCallFailed => 'Could not open the phone app.';

  @override
  String get exGymDetail => 'View gym details';

  @override
  String get exConsultChosenSlot => 'Requested time';

  @override
  String get exConsultConfirmedAt => 'Confirmed time';

  @override
  String get exConsultExpired => 'Expired';

  @override
  String get exConsultExpiredBody =>
      'The trainer did not respond in time. Try requesting another time.';

  @override
  String get exConsultCancelledByTrainerBody =>
      'The trainer cancelled this consultation. Try requesting another time.';

  @override
  String get exExerciseGoal => 'Exercise Goal';

  @override
  String get exGoalHealth => 'Health Management';

  @override
  String get exOptionOther => 'Other';

  @override
  String get exOtherGoalHint =>
      'Please describe your specific exercise goal in the message.';

  @override
  String get exPreferredDate => 'Preferred Date';

  @override
  String get exTimeFlexible => 'Discuss Later';

  @override
  String get exConsultMessage => 'Message';

  @override
  String get exConsultMessageHint =>
      'Share your exercise experience or anything helpful for the consultation.';

  @override
  String get exSendConsultRequest => 'Send Consultation Request';

  @override
  String get exGoalRequired => 'Please select an exercise goal.';

  @override
  String get exOtherGoalDetailRequired =>
      'Please describe your specific exercise goal in the message.';

  @override
  String get exConsultTargetNotFound =>
      'Couldn\'t find the consultation target.';

  @override
  String get exConsultPendingExists =>
      'A consultation request is already pending.';

  @override
  String get exConsultReceived => 'Your consultation request was received';

  @override
  String get exConsultCompletionInfo =>
      'We\'ll let you know when the other party reviews your request.';

  @override
  String get exConsultStatus => 'Current Status';

  @override
  String get exConsultPendingStatus => 'Pending';

  @override
  String get exConsultAcceptedStatus => 'Accepted';

  @override
  String get exConsultRejectedStatus => 'Rejected';

  @override
  String get exReturnExercise => 'Return to Exercise';

  @override
  String get exConsultHistoryTitle => 'My Consultation Requests';

  @override
  String get exConsultHistoryEmpty =>
      'You haven\'t sent any consultation requests yet.';

  @override
  String get exConsultHistoryInProgress => 'In Progress';

  @override
  String get exConsultRejectedReasonLabel => 'Reason for decline';

  @override
  String get exConsultRejectedNoReason =>
      'No reason was given. Try requesting a consultation with another trainer.';

  @override
  String get exConsultAcceptedGuide =>
      'Your consultation is confirmed. If you decide to register, connect with the trainer using the code in the MY tab during the consultation.';

  @override
  String get exMyReservations => 'My bookings';

  @override
  String get exCancelReservation => 'Cancel booking';

  @override
  String get exCancelKeep => 'Keep';

  @override
  String get exCancelConfirmTitle => 'Cancel this booking?';

  @override
  String get exCancelFailed =>
      'Couldn\'t cancel the booking. Please try again in a moment';

  @override
  String get exReservationPast => 'Past booking';

  @override
  String exReservationPastMore(int count) {
    return 'Show $count more past bookings';
  }

  @override
  String get exReservationPastLess => 'Hide past bookings';

  @override
  String exCancelConfirmBody(String when) {
    return 'The $when booking is cancelled and the slot reopens.';
  }

  @override
  String exCancelDone(String when) {
    return 'Cancelled the $when booking';
  }

  @override
  String get mySupportOpenFailed =>
      'Couldn\'t open the link. Please try again in a moment';

  @override
  String get mySupportExternalHint => 'Opens the KakaoTalk channel';

  @override
  String get authRestoring => 'Restoring your session';

  @override
  String get authRestoreFailed =>
      'We could not restore your session — the connection looks unstable.';

  @override
  String get authRestoreRetry => 'Try again';

  @override
  String get authRestoreSignIn => 'Go to sign in';

  @override
  String get authTagline =>
      'Log your meals and workouts — and get coaching back';

  @override
  String get authEmailHint => 'Email';

  @override
  String get authPasswordHint => 'Password';

  @override
  String get authSignInAction => 'Sign in';

  @override
  String get authNoAccountQuestion => 'Don\'t have an account?';

  @override
  String get authSignUpAction => 'Sign up';

  @override
  String get authDemoAction => 'Explore the demo without signing in';

  @override
  String get authSocialDivider => 'Sign in with a social account';

  @override
  String get authKakaoAction => 'Continue with Kakao';

  @override
  String get authGoogleAction => 'Continue with Google';

  @override
  String get authEmailEmpty => 'Enter your email';

  @override
  String get authEmailInvalid => 'Enter a valid email address';

  @override
  String get authEmailTooLong => 'Email addresses can be up to 255 characters';

  @override
  String get authPasswordEmpty => 'Enter your password';

  @override
  String get authSignInFailed =>
      'Sign-in failed. Check your email and password';

  @override
  String get authSignInNetworkFailed =>
      'Check your internet connection and try again';

  @override
  String get authSignInUnavailable =>
      'Can\'t sign in right now. Please try again in a moment';

  @override
  String get authSessionExpired =>
      'Your session has expired. Please sign in again';

  @override
  String get authSocialSignInFailed =>
      'Social sign-in failed. Please try again in a moment';

  @override
  String get authSocialComingSoon =>
      'Social sign-in is coming soon. Please sign in with your email';

  @override
  String get authTrainerAccountTitle => 'This is a trainer account';

  @override
  String get authTrainerAccountMessage =>
      'The member app is for member accounts. Please sign in to the trainer web with your trainer account';

  @override
  String get authTrainerAccountOpenWeb => 'Open trainer web';

  @override
  String get signUpTitle => 'Sign up';

  @override
  String get signUpSubtitle =>
      'Create an On-Care account and start managing your health';

  @override
  String get signUpNameHint => 'Name';

  @override
  String get signUpNameEmpty => 'Enter your name';

  @override
  String get signUpNameTooLong => 'Names can be up to 100 characters';

  @override
  String get signUpPhoneHint => '010-0000-0000';

  @override
  String get signUpPhoneHelper =>
      'Your trainer uses this to confirm who you are.';

  @override
  String get signUpPasswordHint =>
      'Password (8+ characters, letters and numbers)';

  @override
  String get signUpPasswordConfirmHint => 'Confirm password';

  @override
  String get signUpAction => 'Sign up and start';

  @override
  String get signUpHaveAccountQuestion => 'Already have an account?';

  @override
  String get signUpPasswordWeak =>
      'Use at least 8 characters, including letters and numbers';

  @override
  String get signUpPasswordTooLong =>
      'Passwords can be up to 64 characters, or fewer if they include Korean or emoji';

  @override
  String get signUpPasswordMismatch => 'Passwords do not match';

  @override
  String get signUpPhoneFormatInvalid =>
      'Enter your phone number as 010-0000-0000';

  @override
  String get myFieldBirthInvalid => 'Enter your date of birth as 1996-03-21';

  @override
  String get trainerSyncEntryLabel => 'Sync data with a trainer';

  @override
  String get trainerSyncEntryHint =>
      'Connect with your trainer using a 6-digit code';

  @override
  String get trainerSyncTitle => 'Sync data with a trainer';

  @override
  String get trainerSyncConsent =>
      'Once the trainer who enters this code becomes your coach, they can see your meal records, workout records, body information, health goals, and health notes & cautions for coaching, consultations and writing reports. Disconnecting removes their access too, but the conversations you had and the reports already delivered before then remain. You can keep using your personal records even if you don\'t agree.';

  @override
  String get trainerShareDetailMore => 'Show details';

  @override
  String get trainerShareDetailLess => 'Hide details';

  @override
  String get trainerShareRecipientLabel => 'Shared with';

  @override
  String get trainerShareRecipient => 'The trainer connected as your coach';

  @override
  String get trainerShareItemsLabel => 'What is shared';

  @override
  String get trainerShareItems =>
      'Meal records, workout records, body information, health goals, and health notes & cautions';

  @override
  String get trainerSharePurposeLabel => 'Purpose';

  @override
  String get trainerSharePurpose =>
      'Coaching, consultations and writing reports';

  @override
  String get trainerSharePeriodLabel => 'How long';

  @override
  String get trainerSharePeriod =>
      'Until you withdraw consent by disconnecting. Deleting the trainer connection in the MY tab withdraws it, and the trainer can no longer see your new records. Conversations you had and reports already delivered before then are not deleted.';

  @override
  String get trainerShareRefuseLabel => 'Your right to refuse';

  @override
  String get trainerShareRefuse =>
      'You can say no. Without agreeing you can still use your personal records in the app; only the trainer connection won\'t be made.';

  @override
  String get trainerSyncAgree => 'Agree and get a code';

  @override
  String get trainerSyncHint => 'Read these six digits out to your trainer.';

  @override
  String trainerSyncCountdown(String remaining) {
    return 'Expires in $remaining';
  }

  @override
  String get trainerSyncExpired => 'This code has expired.';

  @override
  String get trainerSyncFailed => 'Could not get a code.';

  @override
  String get trainerSyncRetry => 'Get a new code';

  @override
  String get signUpCreatedSignInNeeded =>
      'Your account was created. Please sign in.';

  @override
  String get signUpEmailTaken =>
      'That email is already registered. Please sign in.';

  @override
  String get signUpFailed => 'Sign-up failed. Please try again in a moment.';

  @override
  String get consentAll => 'Agree to all';

  @override
  String get consentRequiredTag => '[Required]';

  @override
  String get consentOptionalTag => '[Optional]';

  @override
  String get consentView => 'View';

  @override
  String get consentTerms => 'Terms of Service';

  @override
  String get consentPrivacy => 'Collection and use of personal information';

  @override
  String get consentHealth =>
      'Processing of health information (sensitive data)';

  @override
  String get consentHealthDetail =>
      'Covers your diet and exercise logs, body data such as weight, health goals, and health notes & cautions. We ask for this separately from other personal information.';

  @override
  String get consentAge14 => 'I am 14 years of age or older';

  @override
  String get consentAge14Detail => 'You must be 14 or older to sign up.';

  @override
  String get consentRequiredHint => 'Agree to all required items to continue.';

  @override
  String get consentPageTitle => 'Agreements';

  @override
  String get consentPageSubtitle =>
      'Please review and agree to the items below to keep using On-Care.';

  @override
  String get consentPageAction => 'Agree and continue';

  @override
  String get consentPageFailed =>
      'Couldn\'t save your agreement. Please try again in a moment.';

  @override
  String get onboardSkip => 'Do this later';

  @override
  String get onboardPrevious => 'Back';

  @override
  String get onboardNext => 'Next';

  @override
  String get onboardDone => 'Done';

  @override
  String get onboardSaveFailed =>
      'Could not save. Please try again in a moment';

  @override
  String get onboardBasicTitle => 'Basic information';

  @override
  String get onboardBasicSubtitle =>
      'Tell us a little about yourself so we can tailor your care.';

  @override
  String get onboardHeightHint => 'Height (cm)';

  @override
  String get onboardWeightHint => 'Weight (kg)';

  @override
  String get onboardHealthTitle => 'Health goals';

  @override
  String get onboardHealthSubtitle =>
      'Pick what you want to focus on in your health care. (up to 2)';

  @override
  String get onboardOptionalTag => '(optional)';

  @override
  String guideBadgeWithStep(int current, int total) {
    return 'App guide $current/$total';
  }

  @override
  String get guideSampleBadge => 'Sample screen';

  @override
  String get guideSkip => 'Skip';

  @override
  String get guidePrev => 'Back';

  @override
  String get guideNext => 'Next';

  @override
  String get guideDone => 'Done';

  @override
  String get guideHomeAdviceTitle => 'Today\'s AI summary';

  @override
  String get guideHomeAdviceBody =>
      'It reads your meals and workouts together and points to what to do today';

  @override
  String get guideQuickAddTitle => 'Quick add';

  @override
  String get guideQuickAddBody =>
      'The + in the middle adds a meal or a workout from any screen';

  @override
  String get guideDietNutritionTitle => 'Nutrition summary';

  @override
  String get guideDietNutritionBody =>
      'Today\'s calories, macros, sodium and sugar, and how far each is from your goal';

  @override
  String get guideExerciseStatusTitle => 'Workout status';

  @override
  String get guideExerciseStatusBody =>
      'How much you moved today and this week, and how far the goal still is';

  @override
  String get guideGymTitle => 'Your gym and trainer';

  @override
  String get guideGymBody =>
      'The gym and trainer you are connected to — their plans and feedback arrive in the app';

  @override
  String get guideMySettingsTitle => 'Settings';

  @override
  String get guideMySettingsBody =>
      'Change your profile, health goals and alerts here — and replay this guide';

  @override
  String get guidePointsTitle => 'Points';

  @override
  String guidePointsBody(int diet, int exercise, int routine) {
    return 'Every log earns points.\nLog a meal +${diet}P, log a workout +${exercise}P, finish a personal exercise +${routine}P\nSpend them in MY › Use Points';
  }

  @override
  String get guideSampleFoodScrambledEggs => 'Scrambled eggs';

  @override
  String get guideSampleFoodWholeWheatToast => 'Whole-wheat toast';

  @override
  String get guideSampleFoodChickenSalad => 'Chicken breast salad';

  @override
  String get guideSampleFoodBrownRice => 'Brown rice';

  @override
  String get guideSampleFoodGrilledSalmon => 'Grilled salmon';

  @override
  String get guideSampleFoodRoastedVegetables => 'Roasted vegetables';

  @override
  String get onboardRequiredTag => '(required)';

  @override
  String get onboardBirthRequired => 'Choose your date of birth';

  @override
  String get onboardGenderRequired => 'Choose your gender';

  @override
  String get onboardHeightRequired => 'Enter your height';

  @override
  String onboardHeightRange(int min, int max) {
    return 'Height must be between $min and $max cm';
  }

  @override
  String get onboardWeightRequired => 'Enter your weight';

  @override
  String onboardWeightRange(int min, int max) {
    return 'Weight must be between $min and $max kg';
  }

  @override
  String get onboardSkipStep => 'Skip this step';

  @override
  String get onboardBirthLabel => 'Date of birth';

  @override
  String get onboardBirthYearHint => 'Year';

  @override
  String get onboardBirthMonthHint => 'Month';

  @override
  String get onboardBirthDayHint => 'Day';

  @override
  String onboardBirthYearValue(int year) {
    return '$year';
  }

  @override
  String onboardBirthMonthValue(int month) {
    return '$month';
  }

  @override
  String onboardBirthDayValue(int day) {
    return '$day';
  }

  @override
  String get onboardGenderLabel => 'Gender';

  @override
  String onboardAgeSummary(int age) {
    return '$age years old';
  }

  @override
  String onboardBmiSummary(String bmi, String category) {
    return 'BMI $bmi · $category';
  }

  @override
  String get onboardBmiUnderweight => 'Underweight';

  @override
  String get onboardBmiNormal => 'Normal';

  @override
  String get onboardBmiPreObese => 'Pre-obese';

  @override
  String get onboardBmiObese1 => 'Obesity class I';

  @override
  String get onboardBmiObese2 => 'Obesity class II';

  @override
  String get onboardBmiObese3 => 'Obesity class III';

  @override
  String get onboardBmiSourceNote =>
      'Cut-offs: Korean Society for the Study of Obesity guideline (Asia-Pacific)';

  @override
  String get onboardDietTitle => 'Diet goals';

  @override
  String get onboardDietSubtitle =>
      'We prefilled suggested goals. Change anything you like.';

  @override
  String get onboardExerciseTitle => 'Exercise goals';

  @override
  String get onboardExerciseSubtitle =>
      'Prefilled from the World Health Organization guideline. Change anything you like.';

  @override
  String get onboardRecommendedPersonal =>
      'Suggested from your age, gender, height and weight';

  @override
  String get onboardRecommendedFallback =>
      'App defaults. Fill in step 1 to get a suggestion tailored to you';

  @override
  String get onboardResetToRecommended => 'Reset to suggested';

  @override
  String get onboardDietSourceNote =>
      'Sources: Dietary Reference Intakes for Koreans 2020 (EER, AMDR) · WHO sodium and free-sugar guidelines';

  @override
  String get onboardExerciseSourceNote =>
      'Source: WHO guidelines on physical activity (2020) — 150 min of moderate cardio and 2+ strength days a week';

  @override
  String get onboardFocusAdjusted => 'Adjusted for the health goals you picked';

  @override
  String get onboardFocusSourceNote =>
      'Goal adjustments: 500 kcal a day for weight loss (Korean Society for the Study of Obesity) · 1.6 g protein per kg for strength (ISSN) · sugar 5% of energy (WHO) · 150–300 min cardio a week (WHO)';

  @override
  String get onboardGenderMale => 'Male';

  @override
  String get onboardGenderFemale => 'Female';

  @override
  String get onboardGenderOther => 'Other';

  @override
  String get aiCoachWelcome =>
      'Hi, I\'m Oni, your AI health coach 🙂\nI look at your diet and exercise records — ask me anything.';

  @override
  String get aiCoachFailure =>
      'Something went wrong. Please try again in a moment.';

  @override
  String get aicResend => 'Send again';

  @override
  String get aicSendFailedMine => 'Not sent · Long-press to edit';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionConfirm => 'OK';

  @override
  String get coachCardSleepTag => 'Sleep';

  @override
  String get myHealthGoalsTitle => 'Health goals';

  @override
  String get myFirstRunPromptTitle => 'Enter your basics for tailored goals';

  @override
  String get myFirstRunPromptBody =>
      'You skipped the first-time setup. Add your birth date, height and weight and we will suggest diet and exercise goals that fit you.';

  @override
  String get myFirstRunPromptAction => 'Enter basics';

  @override
  String get myGoalsFocusSection => 'What you want to focus on';

  @override
  String get myGoalsFocusHint =>
      'Pick what you want to focus on in your health care. (up to 2)';

  @override
  String myGoalsFocusLastChanged(String who, String date) {
    return 'Last changed by $who · $date';
  }

  @override
  String get myGoalsFocusChangedByTrainer => 'your trainer';

  @override
  String get myGoalsFocusChangedByMe => 'you';

  @override
  String get healthNotesLabel => 'Health notes & cautions';

  @override
  String get healthNotesHint => 'e.g. Left knee surgery, herniated disc';

  @override
  String get healthNotesHelper => 'Used for recommendations';

  @override
  String get healthFocusWeightLoss => 'Weight loss';

  @override
  String get healthFocusStrength => 'Build strength';

  @override
  String get healthFocusFitness => 'Improve fitness';

  @override
  String get healthFocusPosture => 'Posture correction';

  @override
  String get healthFocusRehab => 'Rehab';

  @override
  String get healthFocusEating => 'Better eating habits';

  @override
  String get healthFocusExerciseHabit => 'Exercise habit';

  @override
  String get healthFocusBloodPressure => 'Blood pressure care';

  @override
  String get myGoalsDietSection => 'Diet goals';

  @override
  String get myGoalsExerciseSection => 'Exercise targets';

  @override
  String get myGoalBurnDaily => 'Daily calories burned (kcal)';

  @override
  String get myGoalCardioWeekly => 'Weekly cardio (min)';

  @override
  String get myGoalStrengthWeekly => 'Weekly strength (sets)';

  @override
  String get myGoalFlexibilityWeekly => 'Weekly stretching (min)';

  @override
  String myGoalExerciseSuggestionNote(
    int burn,
    int cardio,
    int strength,
    int flexibility,
  ) {
    return 'Suggested: $burn kcal a day · $cardio min cardio · $strength sets · $flexibility min stretching a week';
  }

  @override
  String get myGoalExerciseApplySuggestion => 'Use suggested goals';

  @override
  String get myGoalCalories => 'Daily calorie limit (kcal)';

  @override
  String get myGoalSodium => 'Daily sodium limit (mg)';

  @override
  String get myGoalSugar => 'Daily sugar limit (g)';

  @override
  String get myGoalCarbs => 'Daily carbohydrate limit (g)';

  @override
  String get myGoalProtein => 'Daily protein limit (g)';

  @override
  String get myGoalFat => 'Daily fat limit (g)';

  @override
  String get myGoalCaloriesFromMacros =>
      'Calculated from your carb, protein and fat goals';

  @override
  String myGoalMacroSuggestionNote(
    int kcal,
    int carbs,
    int protein,
    int fat,
    int sugar,
  ) {
    return 'Suggested split for $kcal kcal: $carbs g carbs · $protein g protein · $fat g fat · $sugar g sugar';
  }

  @override
  String get myGoalMacroApplySuggestion => 'Use suggested split';

  @override
  String get myGoalUnsetHint =>
      'Dimmed values are the baseline used before you set a goal';

  @override
  String get myGoalsSaved => 'Health goals saved';

  @override
  String myGoalRange(int min, int max) {
    return 'Enter a value between $min and $max';
  }

  @override
  String get mySettingsLoadFailed => 'Couldn\'t load your settings';

  @override
  String get mySettingsLoadFailedBody =>
      'Editing is locked because saving now could wipe your existing settings.';

  @override
  String get myNotificationSaveFailed => 'Couldn\'t save notification settings';

  @override
  String get myNotifLoadFailed => 'Couldn\'t load notification settings';

  @override
  String get myNotifLoadFailedBody =>
      'These are default values and may differ from your saved settings';

  @override
  String get myPointsGuideTitle => 'How to earn points';

  @override
  String get myPointsDietAdd => 'Log a meal';

  @override
  String get myPointsRoutineComplete =>
      'Complete a recommended or assigned workout';

  @override
  String get myPointsExerciseAdd => 'Log a workout yourself';

  @override
  String myPointsRuleWithDailyCap(String action, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'up to $count times a day',
      one: 'once a day',
    );
    return '$action ($_temp0)';
  }

  @override
  String get coachRoutineTitle => 'Recommended personal exercises';

  @override
  String get coachRoutineAiTitle => 'AI-recommended personal exercises';

  @override
  String get coachRoutinePastEditHint =>
      'You can add a missed check now. Your trainer will see it as checked later.';

  @override
  String get coachRoutinePastEditDone => 'Done';

  @override
  String get coachRoutineLogged => 'Added to your workout log';

  @override
  String get coachRoutineGone =>
      'This program no longer exists. Please refresh the list';

  @override
  String get coachRoutineNetworkError => 'Check your connection and try again';

  @override
  String get coachRoutineLogFailed => 'Couldn\'t record it as done.';

  @override
  String get coachRoutineDone => 'Done';

  @override
  String get coachRoutineUndo => 'Undo';

  @override
  String coachRoutineUndoConfirm(String name) {
    return 'Undo completing \'$name\'? It will be removed from your workout log too.';
  }

  @override
  String get coachRoutineUndone => 'Completion undone';

  @override
  String get coachRoutineUndoFailed => 'Could not undo the completion.';

  @override
  String get coachRoutineCancel => 'Delete this personal exercise';

  @override
  String coachRoutineCancelConfirm(String name) {
    return 'Remove \'$name\' from the list? Anything you already logged stays.';
  }

  @override
  String get coachCardRoutineUndoTitle => 'Undo completion?';

  @override
  String get coachCardRoutineCancelTitle => 'Delete this personal exercise?';

  @override
  String get coachRoutineKeep => 'Keep';

  @override
  String get coachRoutineCancelled => 'Personal exercise deleted';

  @override
  String get coachRoutineCancelFailed =>
      'Couldn\'t delete the personal exercise';

  @override
  String get coachRoutineCompleteTitle => 'Mark personal exercise done';

  @override
  String get coachRoutineIntensity => 'Intensity';

  @override
  String coachRoutinePlannedIntensity(String level) {
    return 'Suggested $level';
  }

  @override
  String get coachRoutineSubmit => 'Done';

  @override
  String get coachChatWithTrainer => 'Chat with trainer';

  @override
  String get coachTrainerLoading => 'Loading your trainer…';

  @override
  String get coachTrainerNone =>
      'You don\'t have a trainer yet. Connect a gym and trainer from the Exercise tab';

  @override
  String get coachTrainerRetrying =>
      'Couldn\'t load your trainer. Trying again';

  @override
  String get alertCategoryReminder => 'Reminder';

  @override
  String get alertCategoryCoachChat => 'Trainer message';

  @override
  String get alertCategoryCoachReport => 'Weekly report';

  @override
  String get alertCategoryRoutine => 'Exercises & programs';

  @override
  String get alertCategorySchedule => 'PT schedule';

  @override
  String get alertCategoryPtDone => 'PT record';

  @override
  String get alertCategoryTrainer => 'Trainer';

  @override
  String get alertCategoryConsultation => 'Consultation request';

  @override
  String get alertCategoryHealthGoals => 'Health goals';

  @override
  String get alertCategoryBenefits => 'Benefits';

  @override
  String get alertCategoryChallenge => 'Challenge';

  @override
  String get alertCategoryAchievement => 'Achievement';

  @override
  String get alertCategorySystem => 'System';

  @override
  String get alertMarkAllRead => 'Mark all read';

  @override
  String get alertEmpty => 'No notifications';

  @override
  String get alertLoadFailed => 'Couldn\'t load the latest notifications';

  @override
  String get alertMarkAllReadFailed =>
      'Couldn\'t mark all as read. Please try again shortly';

  @override
  String get alertCoachChatFailed =>
      'Couldn\'t load your trainer, so the chat can\'t open. Please try again shortly';

  @override
  String get alertCoachChatNoTrainer =>
      'You have no assigned trainer, so the chat can\'t open';

  @override
  String get alertTimeJustNow => 'Just now';

  @override
  String alertTimeMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String alertTimeHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String get alertTimeYesterday => 'Yesterday';

  @override
  String alertTimeDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get demoAlertRoutineTitle => 'New personal exercises';

  @override
  String demoAlertRoutineBody(String trainerName) {
    return 'Trainer $trainerName adjusted them to walking-focused exercises for your knee.';
  }

  @override
  String get demoAlertReportTitle => 'This week\'s report is ready';

  @override
  String demoAlertReportBody(String trainerName) {
    return 'Trainer $trainerName posted your report for this week.';
  }

  @override
  String get demoAlertPtDoneTitle => 'PT complete';

  @override
  String demoAlertPtDoneBody(String trainerName) {
    return 'You finished your 12th PT with Trainer $trainerName at 18:00 today!';
  }

  @override
  String get demoAlertTrainerFeedbackTitle => 'Feedback from your trainer';

  @override
  String get demoAlertTrainerFeedbackBody =>
      'Be sure to stretch your rotator cuff to finish.';

  @override
  String get demoAlertWeeklyGoalTitle => 'Almost at this week\'s workout goal';

  @override
  String get demoAlertWeeklyGoalBody =>
      'Start with 30 minutes of low-intensity cardio (walking).';

  @override
  String get demoAlertMealStreakTitle => 'You\'re keeping up your meal log';

  @override
  String get demoAlertMealStreakBody =>
      'You\'ve logged your meals every day for over two weeks.';

  @override
  String get demoAlertMaintenanceTitle => 'Scheduled maintenance';

  @override
  String get demoAlertMaintenanceBody =>
      'Maintenance is scheduled for tomorrow, 02:00–03:00.';

  @override
  String get exPtFeedbackTitle => 'Today\'s feedback';

  @override
  String exNextPtSchedule(String when) {
    return 'Next PT · $when';
  }

  @override
  String get exNextPtNone => 'No PT scheduled yet';

  @override
  String exDatedTitle(int month, int day, String title) {
    return '$title · $month/$day';
  }

  @override
  String a11yChartSummary(String title, String detail) {
    return '$title. $detail';
  }

  @override
  String a11yChartEmpty(String title) {
    return '$title. No records yet';
  }

  @override
  String a11yChartPoint(String day, String value) {
    return '$day $value';
  }

  @override
  String get a11yShowPassword => 'Show password';

  @override
  String get a11yHidePassword => 'Hide password';

  @override
  String get a11yOpenCoaching => 'Open coaching tips';

  @override
  String get a11ySendMessage => 'Send message';

  @override
  String get a11yClearSearch => 'Clear search';

  @override
  String get a11yRemoveFood => 'Remove food';

  @override
  String get a11yPrevWeek => 'Previous week';

  @override
  String get a11yNextWeek => 'Next week';

  @override
  String get exConsultHistoryCancelTitle => 'Cancel this consultation request?';

  @override
  String get exConsultHistoryCancelAction => 'Cancel request';

  @override
  String get exConsultCancelFailed =>
      'Couldn\'t cancel the consultation request. Please try again.';

  @override
  String get exConsultCancelStale =>
      'This request was already handled. It now shows its latest status.';

  @override
  String get exConsultHistoryLoadError =>
      'Couldn\'t load your consultation requests.';

  @override
  String get exConsultHistoryCancelBody =>
      'A cancelled request can\'t be restored.';

  @override
  String pointsRewardBadge(int points) {
    return '+${points}P';
  }

  @override
  String get gymLocationDenied =>
      'Allow location access to find gyms near you.';

  @override
  String get gymLocationBrowserBlocked =>
      'Allow location access in your browser site settings, then try again.';

  @override
  String get gymLocationBlocked =>
      'Allow location access in app settings, then try again.';

  @override
  String get gymLocationDisabled =>
      'Turn on device location services, then try again.';

  @override
  String get gymLocationUnavailable =>
      'Could not get your location. Please try again.';

  @override
  String get gymLocateAction => 'Find near my location';

  @override
  String get gymLocationSettings => 'Settings';

  @override
  String get gymDefaultAreaTitle => 'Showing gyms around Sinchon';

  @override
  String get gymDefaultAreaMessage =>
      'Allow location access to see gyms near you.';

  @override
  String get gymUseLocation => 'Use location';

  @override
  String get gymDistanceSortNeedsLocation =>
      'Sort by distance needs your current location.';

  @override
  String get exGymCopyPhone => 'Copy phone number';

  @override
  String get exGymPhoneCopied => 'Phone number copied.';

  @override
  String get exerciseAdviceRecordEmptyToday =>
      'No workout logged today yet. How about a 10-minute walk to start?';

  @override
  String get exerciseAdviceRecordEmptyWeek =>
      'No workouts logged this week yet. How about a 10-minute walk to start?';

  @override
  String get exerciseAdviceRecordEmptyAll =>
      'Once you log more, we\'ll show how your workout volume and types are trending.';

  @override
  String exerciseAdviceRecordToday(int calories, int minutes, String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    return 'Today: $minutes min and $calories kcal, mostly $_temp0. Wrap up with a stretch.';
  }

  @override
  String exerciseAdviceRecordWeekOneDay(int minutes) {
    return 'Just one day this week ($minutes min). One more workout keeps the flow going.';
  }

  @override
  String exerciseAdviceRecordWeekSkew(
    int days,
    int minutes,
    String missing,
    String top,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    String _temp1 = intl.Intl.selectLogic(top, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    String _temp2 = intl.Intl.selectLogic(missing, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    return 'This week\'s $_temp0 and $minutes min leaned on $_temp1. Mix in some $_temp2?';
  }

  @override
  String exerciseAdviceRecordWeekBalanced(int days, int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0 and $minutes min this week, with a good mix of types.';
  }

  @override
  String get exerciseAdviceRecordAllUp =>
      'You\'ve done more over the last 4 weeks than before. This approach suits you.';

  @override
  String get exerciseAdviceRecordAllDown =>
      'Your last 4 weeks are trending down. Try to keep 3 days a week, even short ones.';

  @override
  String exerciseAdviceRecordAllSteady(int days, int minutes, int weeks) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    String _temp1 = intl.Intl.pluralLogic(
      weeks,
      locale: localeName,
      other: '$weeks weeks',
      one: '1 week',
    );
    return '$_temp0 and $minutes min over $_temp1 — nice and steady.';
  }

  @override
  String exerciseAdviceRoutineTodayAllDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'all $count personal exercises',
      one: 'your personal exercise',
    );
    return 'You finished $_temp0 today. Great job!';
  }

  @override
  String exerciseAdviceRoutineTodayDoneNextOrder(
    String done,
    String doneObj,
    String next,
    String then,
  ) {
    return '$done done. Next up: $next → $then.';
  }

  @override
  String exerciseAdviceRoutineTodayDoneNext(
    String done,
    String doneObj,
    String next,
  ) {
    return '$done done. $next is next.';
  }

  @override
  String exerciseAdviceRoutineTodayNextOrder(String next, String then) {
    return 'Next up: $next → $then.';
  }

  @override
  String exerciseAdviceRoutineTodayNext(String next) {
    return '$next is next.';
  }

  @override
  String exerciseAdviceRoutineTodayLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personal exercises left',
      one: '1 personal exercise left',
    );
    return '$_temp0. Go down the list in order.';
  }

  @override
  String exerciseAdviceRoutineTodayStartOrder(String next, String then) {
    return 'Start today\'s personal exercises with $next → $then.';
  }

  @override
  String exerciseAdviceRoutineTodayStart(String next) {
    return 'Start today with $next.';
  }

  @override
  String exerciseAdviceRoutineWeekNoneToday(String next) {
    return 'You haven\'t done your personal exercises this week yet. Start with $next today?';
  }

  @override
  String exerciseAdviceRoutineWeekNoneNext(String next) {
    return 'You haven\'t done your personal exercises this week yet. Try $next first.';
  }

  @override
  String get exerciseAdviceRoutineWeekNone =>
      'You haven\'t done your personal exercises this week yet. Try one today.';

  @override
  String exerciseAdviceRoutineWeekOnly(
    String missing,
    String rest,
    String top,
  ) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    String _temp1 = intl.Intl.selectLogic(rest, {
      'next_week': 'Next week',
      'other': 'For the rest of the week',
    });
    String _temp2 = intl.Intl.selectLogic(missing, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    return 'This week you only did $_temp0 workouts. $_temp1, start with $_temp2.';
  }

  @override
  String exerciseAdviceRoutineWeekOnlyShort(String top) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    return 'This week you only did $_temp0 workouts.';
  }

  @override
  String exerciseAdviceRoutineWeekSkew(
    String missing,
    String rest,
    int share,
    String top,
  ) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    String _temp1 = intl.Intl.selectLogic(rest, {
      'next_week': 'Next week',
      'other': 'For the rest of the week',
    });
    String _temp2 = intl.Intl.selectLogic(missing, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    return '$share% of this week\'s personal exercises were $_temp0. $_temp1, start with $_temp2.';
  }

  @override
  String exerciseAdviceRoutineWeekSkewShort(int share, String top) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    return '$share% of this week\'s personal exercises were $_temp0.';
  }

  @override
  String exerciseAdviceRoutineWeekPraise(String how) {
    String _temp0 = intl.Intl.selectLogic(how, {
      'even': 'across the board',
      'other': 'steadily',
    });
    return 'You kept up with this week\'s personal exercises $_temp0. Keep it going!';
  }

  @override
  String exerciseAdviceRoutineWeekCountsToday(
    int assigned,
    int completed,
    String next,
  ) {
    return 'You did $completed of $assigned personal exercises this week. Continue with $next today.';
  }

  @override
  String exerciseAdviceRoutineWeekCountsKeep(
    int assigned,
    int completed,
    String rest,
  ) {
    String _temp0 = intl.Intl.selectLogic(rest, {
      'next_week': 'Keep it going next week.',
      'other': 'Keep it going for the rest of the week.',
    });
    return 'You did $completed of $assigned personal exercises this week. $_temp0';
  }

  @override
  String exerciseAdviceRoutineWeekCounts(int assigned, int completed) {
    return 'You did $completed of $assigned personal exercises this week.';
  }

  @override
  String exerciseAdviceRoutineLastWeekNoneNext(String next) {
    return 'You didn\'t do your personal exercises last week. This week, start with $next.';
  }

  @override
  String get exerciseAdviceRoutineLastWeekNone =>
      'You didn\'t do your personal exercises last week. Take them one at a time this week.';

  @override
  String exerciseAdviceRoutineLastWeekOnly(String missing, String top) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    String _temp1 = intl.Intl.selectLogic(missing, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    return 'Last week you only did $_temp0 workouts. This week, start with $_temp1.';
  }

  @override
  String exerciseAdviceRoutineLastWeekOnlyShort(String top) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    return 'Last week you only did $_temp0 workouts.';
  }

  @override
  String exerciseAdviceRoutineLastWeekSkew(
    String missing,
    int share,
    String top,
  ) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    String _temp1 = intl.Intl.selectLogic(missing, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    return '$share% of last week\'s personal exercises were $_temp0. This week, start with $_temp1.';
  }

  @override
  String exerciseAdviceRoutineLastWeekSkewShort(int share, String top) {
    String _temp0 = intl.Intl.selectLogic(top, {
      'cardio': 'cardio',
      'strength': 'strength',
      'stretching': 'stretching',
      'other': 'other exercise',
    });
    return '$share% of last week\'s personal exercises were $_temp0.';
  }

  @override
  String exerciseAdviceRoutineLastWeekPraise(String how) {
    String _temp0 = intl.Intl.selectLogic(how, {
      'even': 'across the board',
      'other': 'steadily',
    });
    return 'You kept up with last week\'s personal exercises $_temp0. Keep it going this week!';
  }

  @override
  String exerciseAdviceRoutineLastWeekCountsMore(int assigned, int completed) {
    return 'You did $completed of $assigned personal exercises last week. Let\'s do more this week.';
  }

  @override
  String exerciseAdviceRoutineLastWeekCounts(int assigned, int completed) {
    return 'You did $completed of $assigned personal exercises last week.';
  }

  @override
  String exerciseAdviceRoutineAllNew(int days) {
    return 'Day $days with your personal exercises. After a week, we\'ll point out what gets skipped.';
  }

  @override
  String exerciseAdviceRoutineAllNoneNext(int days, String next) {
    return 'Day $days with your personal exercises. Start with $next today?';
  }

  @override
  String exerciseAdviceRoutineAllNone(int days) {
    return 'Day $days with your personal exercises. Try one today.';
  }

  @override
  String exerciseAdviceRoutineAllDoneTodayPart(String part) {
    String _temp0 = intl.Intl.selectLogic(part, {
      'lower': 'lower-body',
      'upper': 'upper-body',
      'core': 'core',
      'full': 'full-body',
      'other': 'full-body',
    });
    return 'You did the $_temp0 workouts you often skip today. Keep it going!';
  }

  @override
  String exerciseAdviceRoutineAllDoneTodayName(String name, String nameObj) {
    return 'You did $name today, one you often skip. Keep it going!';
  }

  @override
  String exerciseAdviceRoutineAllDoneTodayNamePlain(String name) {
    return 'You did $name today, one you often skip. Keep it going!';
  }

  @override
  String get exerciseAdviceRoutineAllDoneToday =>
      'You did a workout you often skip today. Keep it going!';

  @override
  String exerciseAdviceRoutineAllMissedPart(String part) {
    String _temp0 = intl.Intl.selectLogic(part, {
      'lower': 'Lower-body',
      'upper': 'Upper-body',
      'core': 'Core',
      'full': 'Full-body',
      'other': 'Full-body',
    });
    return '$_temp0 personal exercises get skipped often. Try doing them first?';
  }

  @override
  String exerciseAdviceRoutineAllMissedPartShort(String part) {
    String _temp0 = intl.Intl.selectLogic(part, {
      'lower': 'Lower-body',
      'upper': 'Upper-body',
      'core': 'Core',
      'full': 'Full-body',
      'other': 'Full-body',
    });
    return '$_temp0 workouts get skipped often. Move them up?';
  }

  @override
  String exerciseAdviceRoutineAllMissedName(String name, String nameSubj) {
    return '$name gets skipped often. Try doing it first next time?';
  }

  @override
  String exerciseAdviceRoutineAllMissedNameShort(String name, String nameSubj) {
    return '$name gets skipped often. Do it first?';
  }

  @override
  String exerciseAdviceRoutineAllMissedNamePlain(String name) {
    return '$name gets skipped often. Try doing it first next time?';
  }

  @override
  String exerciseAdviceRoutineAllMissedNamePlainShort(String name) {
    return '$name gets skipped often. Do it first?';
  }

  @override
  String get exerciseAdviceRoutineAllMissed =>
      'Some personal exercises get skipped often. Try reordering your list?';

  @override
  String exerciseAdviceRoutineAllPraise(int weeks) {
    String _temp0 = intl.Intl.pluralLogic(
      weeks,
      locale: localeName,
      other: '$weeks weeks',
      one: '1 week',
    );
    return '$_temp0 of keeping up with your personal exercises. Keep it up!';
  }

  @override
  String exerciseAdviceRoutineAllRate(int pct) {
    return 'You\'ve done $pct% of your personal exercises. Try not to skip a day.';
  }

  @override
  String get dietAdviceTodayEmpty => 'No meals logged today yet.';

  @override
  String get dietAdviceTodayMissingMeal => 'Missed logging a meal?';

  @override
  String dietAdviceTodaySodiumOver(int sodiumMg) {
    final intl.NumberFormat sodiumMgNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String sodiumMgString = sodiumMgNumberFormat.format(sodiumMg);

    return 'Sodium **${sodiumMgString}mg**, over the limit.';
  }

  @override
  String dietAdviceTodayCalorieOver(int kcal) {
    final intl.NumberFormat kcalNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String kcalString = kcalNumberFormat.format(kcal);

    return '**$kcalString kcal** today, over your goal.';
  }

  @override
  String dietAdviceTodayProteinLeft(int proteinG) {
    return '**${proteinG}g** more protein to go.';
  }

  @override
  String dietAdviceTodayBalanced(int kcal) {
    final intl.NumberFormat kcalNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String kcalString = kcalNumberFormat.format(kcal);

    return '**$kcalString kcal** today, nicely balanced.';
  }

  @override
  String dietAdviceNextMeal(String slot, String menu) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': 'breakfast',
      'lunch': 'lunch',
      'dinner': 'dinner',
      'other': 'meals',
    });
    return 'How about **$menu** for $_temp0?';
  }

  @override
  String dietAdviceNextSnack(String menu) {
    return 'How about **$menu** as a snack?';
  }

  @override
  String get dietAdviceTodayDone => 'You wrapped up today\'s meals well!';

  @override
  String get dietAdviceTodayLogFirst =>
      'Log it and we\'ll pick your next meal.';

  @override
  String get dietAdviceWeekEmpty => 'No meals logged this week yet.';

  @override
  String dietAdviceWeekSkipBreakfast(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': 'Last week',
      'other': 'This week',
    });
    return '$_temp0 you skipped breakfast **$days** times.';
  }

  @override
  String dietAdviceWeekSkipBreakfastSnack(
    String scope,
    int days,
    int snackDays,
  ) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': 'Last week',
      'other': 'This week',
    });
    return '$_temp0 you snacked on **$snackDays** of $days no-breakfast days.';
  }

  @override
  String dietAdviceWeekFocusSodium(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': 'Last week',
      'other': 'This week',
    });
    return '$_temp0, sodium ran high on **$days** days.';
  }

  @override
  String dietAdviceWeekFocusCalorie(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': 'Last week',
      'other': 'This week',
    });
    return '$_temp0, you went over your calorie goal on **$days** days.';
  }

  @override
  String dietAdviceWeekFocusSugar(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': 'Last week',
      'other': 'This week',
    });
    return '$_temp0, sugar ran high on **$days** days.';
  }

  @override
  String dietAdviceWeekFocusProtein(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': 'Last week',
      'other': 'This week',
    });
    return '$_temp0, protein fell short on **$days** days.';
  }

  @override
  String dietAdviceWeekGood(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': 'Last week',
      'other': 'This week',
    });
    return '$_temp0, all **$days** logged days were on target.';
  }

  @override
  String get dietAdviceWeekEmptyHint =>
      'Even one meal starts to show a pattern.';

  @override
  String get dietAdviceTipBreakfast => 'Try a boiled egg for breakfast.';

  @override
  String get dietAdviceTipSodium => 'Leave the broth and eat the solids.';

  @override
  String get dietAdviceTipCalorie => 'Try trimming dinner portions a little.';

  @override
  String get dietAdviceTipSugar => 'Swap sweet drinks for water or tea.';

  @override
  String get dietAdviceTipProtein => 'Add eggs or tofu to each meal.';

  @override
  String get dietAdviceTipKeep => 'Keep this flow going!';

  @override
  String dietAdviceAllFewRecords(int days) {
    return '**$days** days logged in the last 4 weeks.';
  }

  @override
  String dietAdviceAllSlotSodium(String slot, int days) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': 'breakfast',
      'lunch': 'lunch',
      'dinner': 'dinner',
      'other': 'meals',
    });
    return 'Sodium at $_temp0 ran high **$days** times in 4 weeks.';
  }

  @override
  String dietAdviceAllCarbHeavy(int pct) {
    return 'Carbs made up **$pct%** of the last 4 weeks.';
  }

  @override
  String dietAdviceAllProteinLight(int pct) {
    return 'Protein was only **$pct%** of the last 4 weeks.';
  }

  @override
  String dietAdviceAllProteinTrendUp(int before, int after) {
    return 'Protein goal days rose from **$before to $after**.';
  }

  @override
  String dietAdviceAllProteinTrendDown(int before, int after) {
    return 'Protein goal days fell from **$before to $after**.';
  }

  @override
  String dietAdviceAllFrequentMenu(String slot, String food, int count) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': 'breakfast',
      'lunch': 'lunch',
      'dinner': 'dinner',
      'other': 'meals',
    });
    return 'Your top $_temp0 pick in 4 weeks: **$food** ($count×).';
  }

  @override
  String dietAdviceAllRepeatedFoods(String food1, String food2) {
    return '**$food1 and $food2** dominate the last 4 weeks.';
  }

  @override
  String dietAdviceAllGood(int days) {
    return '**$days** days logged in 4 weeks, looking good.';
  }

  @override
  String get dietAdviceAllFewHint => 'After 7 days we\'ll show your patterns.';

  @override
  String get dietAdviceTipCarb => 'Try less rice and more side dishes.';

  @override
  String get dietAdviceTipSwap => 'Keep it, just switch up the sides.';

  @override
  String get dietAdviceTipVariety => 'Add fish or tofu twice a week.';

  @override
  String get weeklyFeedbackSheetTitle => 'How was your week?';

  @override
  String weeklyFeedbackSheetSubtitle(String range) {
    return 'Tell your trainer about $range';
  }

  @override
  String get weeklyFeedbackWhy =>
      'Takes 30 seconds. Next week\'s intensity comes from this answer.';

  @override
  String get weeklyFeedbackConditionQuestion => 'How did you feel this week?';

  @override
  String get weeklyFeedbackIntensityQuestion =>
      'How was the workout intensity?';

  @override
  String get weeklyFeedbackPainQuestion => 'Anywhere it hurt?';

  @override
  String get weeklyFeedbackPainHint => 'e.g. right knee';

  @override
  String get weeklyFeedbackPainDateLabel => 'When it hurt';

  @override
  String get weeklyFeedbackPainDatePick => 'Pick a date';

  @override
  String get weeklyFeedbackNoteQuestion =>
      'One-line feedback for your trainer (optional)';

  @override
  String get weeklyFeedbackNoteHint => 'Anything that shaped your week';

  @override
  String get weeklyFeedbackSend => 'Send';

  @override
  String get weeklyFeedbackResend => 'Send again';

  @override
  String get weeklyFeedbackLater => 'Later';

  @override
  String get weeklyFeedbackIncomplete => 'Pick your condition and intensity';

  @override
  String get weeklyFeedbackSent => 'Weekly feedback sent';

  @override
  String get weeklyFeedbackSendFailed =>
      'Couldn\'t send your weekly feedback. Please try again';

  @override
  String get weeklyFeedbackAlreadySent =>
      'You already answered this week. Sending again replaces it.';

  @override
  String get weekConditionGreat => 'Great';

  @override
  String get weekConditionGood => 'Good';

  @override
  String get weekConditionOk => 'Okay';

  @override
  String get weekConditionTired => 'Worn out';

  @override
  String get weekConditionBad => 'Rough';

  @override
  String get weekIntensityTooEasy => 'Too easy';

  @override
  String get weekIntensityRight => 'Just right';

  @override
  String get weekIntensityHard => 'A bit hard';

  @override
  String get weekIntensityTooHard => 'Too hard';

  @override
  String get myCoachReportsEntry => 'Trainer reports';

  @override
  String get myCoachReportsEntryHint =>
      'Reports you received and feedback you sent';

  @override
  String get coachReportsSectionTitle => 'Reports received';

  @override
  String get coachReportsEmpty => 'No reports yet';

  @override
  String get coachReportsEmptyHint =>
      'Weekly reports from your trainer land here';

  @override
  String get coachReportsLoadFailed => 'Couldn\'t load your reports';

  @override
  String get weeklyFeedbackLoadFailed =>
      'Couldn\'t load the weekly feedback you sent';

  @override
  String coachReportSentOn(int month, int day) {
    return 'Sent $month/$day';
  }

  @override
  String get myWeeklyFeedbackSectionTitle => 'Weekly feedback you sent';

  @override
  String get myWeeklyFeedbackOnlyLastWeek =>
      'Only last week\'s answer is shown';

  @override
  String get myWeeklyFeedbackEmpty => 'You haven\'t sent last week\'s feedback';

  @override
  String get myWeeklyFeedbackConditionLabel => 'Condition';

  @override
  String get myWeeklyFeedbackIntensityLabel => 'Intensity';

  @override
  String get myWeeklyFeedbackPainLabel => 'Pain';

  @override
  String get myWeeklyFeedbackPainNone => 'None';

  @override
  String myWeeklyFeedbackPainWithDate(String area, int month, int day) {
    return '$area ($month/$day)';
  }

  @override
  String get myWeeklyFeedbackNoteLabel => 'One-line feedback';

  @override
  String myWeeklyFeedbackSentAt(int month, int day) {
    return 'Sent $month/$day';
  }

  @override
  String get weeklyFeedbackNowButton => 'Send feedback now';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authFindEmail => 'Forgot email?';

  @override
  String get findEmailTitle => 'Find your email';

  @override
  String get findEmailSubtitle =>
      'Enter the name and phone number you signed up with to find your email.';

  @override
  String get findEmailAction => 'Find email';

  @override
  String get findEmailComingSoon => 'Finding your email is coming soon.';

  @override
  String get passwordChangeTitle => 'Change password';

  @override
  String get passwordChangeCurrentHint => 'Current password';

  @override
  String get passwordChangeNewHint =>
      'New password (8+ characters, letters and numbers)';

  @override
  String get passwordChangeConfirmHint => 'Confirm new password';

  @override
  String get passwordChangeNote =>
      'This device stays signed in. Other devices will need to sign in again.';

  @override
  String get passwordChangeAction => 'Change password';

  @override
  String get passwordChangeDone => 'Password changed';

  @override
  String get passwordChangeWrongCurrent => 'Your current password is incorrect';

  @override
  String get passwordChangeSameAsCurrent =>
      'Choose a password different from your current one';

  @override
  String get passwordChangeDemoTitle => 'Demo accounts can\'t change passwords';

  @override
  String get passwordChangeDemoBody =>
      'Demo mode has no server account. Sign in with a real account to change your password here.';

  @override
  String get passwordChangeSocialTitle => 'This account has no password';

  @override
  String get passwordChangeSocialBody =>
      'Accounts that sign in with Kakao or Google are managed by that service.';

  @override
  String get passwordTooManyAttempts =>
      'Too many attempts. Please try again in a moment.';

  @override
  String get passwordTemporaryFailure =>
      'Couldn\'t complete the request. Please try again shortly.';

  @override
  String get passwordResetTitle => 'Reset password';

  @override
  String get passwordResetRequestSubtitle =>
      'We\'ll email a reset code to the address you signed up with.';

  @override
  String get passwordResetSendAction => 'Send code';

  @override
  String get passwordResetHaveCode => 'I already have a code';

  @override
  String get passwordResetSentTitle => 'Check your email';

  @override
  String passwordResetSentBody(String email, int minutes) {
    return 'If an account uses $email, we\'ve sent a code you can use once within $minutes minutes.';
  }

  @override
  String get passwordResetConfirmSubtitle =>
      'Enter the code from the email and your new password.';

  @override
  String get passwordResetCodeHint => '16-character reset code';

  @override
  String get passwordResetCodeEmpty => 'Enter the code';

  @override
  String get passwordResetCodeMalformed =>
      'Enter the 16-character code from the email';

  @override
  String get passwordResetCodeInvalid =>
      'This code is wrong or has expired. Request a new one.';

  @override
  String get passwordResetConfirmAction => 'Save new password';

  @override
  String get passwordResetResend => 'Send a new code';

  @override
  String get passwordResetDemoNote =>
      'Demo mode doesn\'t send email. The code is filled in for you.';

  @override
  String get passwordResetUnavailable =>
      'We can\'t send reset emails right now. Please contact support.';

  @override
  String get passwordResetDoneTitle => 'Password reset';

  @override
  String get passwordResetDoneBody =>
      'Sign in with your new password. You\'ve been signed out on every device.';

  @override
  String get passwordResetBackToSignIn => 'Go to sign in';

  @override
  String get signUpEmailCodeSend => 'Send code';

  @override
  String get signUpEmailCodeHint => 'Verification code';

  @override
  String get signUpEmailCodeResend => 'Resend';

  @override
  String signUpEmailCodeResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String signUpEmailCodeRemaining(String time) {
    return '6-digit code from the email · expires in $time';
  }

  @override
  String get signUpEmailCodeExpired =>
      'This code has expired. Request a new one.';

  @override
  String get signUpEmailCodeEmpty => 'Enter the 6-digit code';

  @override
  String get signUpEmailCodeInvalid =>
      'This code is wrong or has expired. Request a new one.';

  @override
  String signUpEmailCodeDemoNote(String code) {
    return 'Demo mode doesn\'t send email. Enter $code as the code.';
  }

  @override
  String get signUpEmailCodeUnavailable =>
      'We can\'t send verification emails right now. Please try again later.';

  @override
  String get reauthTitle => 'Confirm it\'s you';

  @override
  String get reauthEmailMessage =>
      'Changing your email changes your sign-in ID and the address password reset emails go to.';

  @override
  String get reauthPasswordPrompt => 'Enter your current password to continue.';

  @override
  String get reauthPasswordRequired => 'Enter your current password';

  @override
  String get reauthSocialPrompt =>
      'This account has no password. Sign in again with the social account you signed up with.';

  @override
  String get reauthSocialAction => 'Sign in again with a social account';

  @override
  String get reauthSocialConfirmed => 'Social account confirmed';

  @override
  String get reauthSocialRequired => 'Sign in again with your social account';

  @override
  String get reauthSocialInvalid =>
      'We couldn\'t confirm your social account. Please sign in again.';

  @override
  String get reauthSocialUnavailable =>
      'Social sign-in isn\'t available in this version yet. Please contact support.';

  @override
  String get releaseUpdateTitle => 'A new version is available';

  @override
  String get releaseUpdateMessage =>
      'Reload to get the latest version. Save anything you\'re working on first.';

  @override
  String get releaseUpdateReload => 'Reload';

  @override
  String get releaseUpdateDismiss => 'Dismiss';
}
