import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

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
  static const List<Locale> supportedLocales = <Locale>[Locale('ko')];

  /// No description provided for @coachInviteUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'이미 처리됐거나 취소된 요청이에요.'**
  String get coachInviteUnavailable;

  /// Application name shown in window/AppBar titles.
  ///
  /// In ko, this message translates to:
  /// **'On-Care'**
  String get appTitle;

  /// Title of the 404 page shown for an address that matches no screen (#2633).
  ///
  /// In ko, this message translates to:
  /// **'페이지를 찾을 수 없어요'**
  String get notFoundTitle;

  /// No description provided for @notFoundMessage.
  ///
  /// In ko, this message translates to:
  /// **'주소가 잘못됐거나 더 이상 없는 페이지예요. 주소를 다시 확인해 주세요.'**
  String get notFoundMessage;

  /// 404 page button for a signed-in (or demo) member; goes to the home dashboard.
  ///
  /// In ko, this message translates to:
  /// **'홈으로'**
  String get notFoundGoHome;

  /// 404 page button when nobody is signed in; goes to the sign-in screen.
  ///
  /// In ko, this message translates to:
  /// **'로그인하러 가기'**
  String get notFoundGoSignIn;

  /// Title of the full-screen page shown when this build is older than the server's minimum supported version (#3045).
  ///
  /// In ko, this message translates to:
  /// **'새 버전이 나왔어요'**
  String get updateRequiredTitle;

  /// No description provided for @updateRequiredMessage.
  ///
  /// In ko, this message translates to:
  /// **'계속 쓰려면 On-Care 를 업데이트해 주세요.'**
  String get updateRequiredMessage;

  /// Current and minimum versions on the update page (#3045).
  ///
  /// In ko, this message translates to:
  /// **'지금 버전 {current} · 필요한 버전 {min}'**
  String updateRequiredVersions(String current, String min);

  /// Button on the update page; opens the store page of the app.
  ///
  /// In ko, this message translates to:
  /// **'업데이트'**
  String get updateRequiredAction;

  /// Shown instead of the button when there is no store link to open (App Store ID not configured).
  ///
  /// In ko, this message translates to:
  /// **'App Store 에서 On-Care 를 업데이트해 주세요.'**
  String get updateRequiredStoreHint;

  /// No description provided for @updateRequiredOpenFailed.
  ///
  /// In ko, this message translates to:
  /// **'스토어를 열지 못했어요. 스토어 앱에서 On-Care 를 업데이트해 주세요.'**
  String get updateRequiredOpenFailed;

  /// Heading of the startup screen shown instead of the app when a release build was made with development or demo settings.
  ///
  /// In ko, this message translates to:
  /// **'이 빌드는 잘못 구성됐어요'**
  String get misconfiguredBuildTitle;

  /// No description provided for @misconfiguredBuildMessage.
  ///
  /// In ko, this message translates to:
  /// **'실제 사용자에게 쓸 수 없는 설정으로 빌드되어 앱을 열지 않았어요. 배포 담당자에게 아래 내용을 알려 주세요.'**
  String get misconfiguredBuildMessage;

  /// No description provided for @misconfiguredBuildDetailsTitle.
  ///
  /// In ko, this message translates to:
  /// **'고쳐야 할 빌드 설정'**
  String get misconfiguredBuildDetailsTitle;

  /// No description provided for @misconfiguredBuildDevEnvironment.
  ///
  /// In ko, this message translates to:
  /// **'ENV 가 prod 또는 staging 이 아니에요'**
  String get misconfiguredBuildDevEnvironment;

  /// No description provided for @misconfiguredBuildMockWithoutDemo.
  ///
  /// In ko, this message translates to:
  /// **'데모 빌드 표시 없이 데모 데이터를 쓰고 있어요 (USE_MOCK_API, DEMO_BUILD)'**
  String get misconfiguredBuildMockWithoutDemo;

  /// No description provided for @misconfiguredBuildPlaceholderApiUrl.
  ///
  /// In ko, this message translates to:
  /// **'API 주소가 예시·로컬 주소예요 (API_BASE_URL)'**
  String get misconfiguredBuildPlaceholderApiUrl;

  /// No description provided for @misconfiguredBuildInsecureApiUrl.
  ///
  /// In ko, this message translates to:
  /// **'API 주소가 https:// 로 시작하지 않아요 (API_BASE_URL)'**
  String get misconfiguredBuildInsecureApiUrl;

  /// Startup guard item: a release build without DEMO_BUILD turned on the sign-in screen's demo entry button. Keep the define names in parentheses as-is.
  ///
  /// In ko, this message translates to:
  /// **'데모 빌드 표시 없이 로그인 화면에 데모 진입이 켜져 있어요 (SHOW_DEMO_ENTRY, DEMO_BUILD)'**
  String get misconfiguredBuildDemoEntry;

  /// Startup guard item: a release build without DEMO_BUILD still has REAL_API, a demo-only switch that sends some mock-build requests to the real server. Keep the define names in parentheses as-is.
  ///
  /// In ko, this message translates to:
  /// **'데모 빌드 표시 없이 일부 기능 실연동 스위치가 남아 있어요 (REAL_API, DEMO_BUILD)'**
  String get misconfiguredBuildRealApi;

  /// No description provided for @navDashboard.
  ///
  /// In ko, this message translates to:
  /// **'홈'**
  String get navDashboard;

  /// No description provided for @navDiet.
  ///
  /// In ko, this message translates to:
  /// **'식단'**
  String get navDiet;

  /// No description provided for @navExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동'**
  String get navExercise;

  /// No description provided for @navMyHealth.
  ///
  /// In ko, this message translates to:
  /// **'MY'**
  String get navMyHealth;

  /// No description provided for @pageDietTitle.
  ///
  /// In ko, this message translates to:
  /// **'식단'**
  String get pageDietTitle;

  /// No description provided for @pageExerciseTitle.
  ///
  /// In ko, this message translates to:
  /// **'운동'**
  String get pageExerciseTitle;

  /// No description provided for @pageAiCoachTitle.
  ///
  /// In ko, this message translates to:
  /// **'AI 코치'**
  String get pageAiCoachTitle;

  /// No description provided for @pageNotificationTitle.
  ///
  /// In ko, this message translates to:
  /// **'알림'**
  String get pageNotificationTitle;

  /// No description provided for @actionRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get actionRetry;

  /// No description provided for @errorCancelled.
  ///
  /// In ko, this message translates to:
  /// **'취소됨'**
  String get errorCancelled;

  /// No description provided for @errorUnknown.
  ///
  /// In ko, this message translates to:
  /// **'알 수 없는 오류'**
  String get errorUnknown;

  /// 403 from the server: signed in, but not allowed to use this feature (missing consent or trainer link). Never suggests signing in again (#2859).
  ///
  /// In ko, this message translates to:
  /// **'이 기능을 쓸 권한이 없어요. 필요한 동의나 트레이너 연결을 확인해 주세요.'**
  String get errorForbidden;

  /// 429 from the server: too many requests; it will work again shortly (#2859).
  ///
  /// In ko, this message translates to:
  /// **'요청이 많아 잠시 멈췄어요. 잠시 뒤 다시 시도해 주세요.'**
  String get errorRateLimited;

  /// Connection lost or timed out — the member should check the network (#3140).
  ///
  /// In ko, this message translates to:
  /// **'인터넷 연결이 불안정해요. 연결을 확인한 뒤 다시 시도해 주세요.'**
  String get errorNetwork;

  /// 5xx from the server: a temporary server problem the member cannot fix (#3140).
  ///
  /// In ko, this message translates to:
  /// **'서버에 잠시 문제가 생겼어요. 조금 뒤 다시 시도해 주세요.'**
  String get errorServer;

  /// 400/422 without a usable server reason: the request was rejected (#3140).
  ///
  /// In ko, this message translates to:
  /// **'요청을 처리하지 못했어요. 입력한 내용을 확인해 주세요.'**
  String get errorInvalidRequest;

  /// No description provided for @dashboardMetricCalories.
  ///
  /// In ko, this message translates to:
  /// **'칼로리'**
  String get dashboardMetricCalories;

  /// No description provided for @dashboardMetricExercise.
  ///
  /// In ko, this message translates to:
  /// **'주간 운동'**
  String get dashboardMetricExercise;

  /// No description provided for @homeDashboardLoadError.
  ///
  /// In ko, this message translates to:
  /// **'대시보드 정보를 불러오지 못했어요.'**
  String get homeDashboardLoadError;

  /// No description provided for @homeDashboardEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 오늘 기록이 없어요. 식단이나 운동을 기록해 보세요.'**
  String get homeDashboardEmpty;

  /// No description provided for @homeAiAdviceTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘의 AI 통합 조언'**
  String get homeAiAdviceTitle;

  /// Home AI advice when today's sodium is over the goal (#1943).
  ///
  /// In ko, this message translates to:
  /// **'오늘 나트륨이 목표를 넘었어요. 남은 끼니는 담백하게 드셔 보세요.'**
  String get homeAdviceSodiumOver;

  /// Home AI advice when this week's cardio minutes meet the member's weekly cardio goal (#1943, #3350).
  ///
  /// In ko, this message translates to:
  /// **'이번 주 유산소 {minutes}분 운동했어요. 목표 달성 중이에요!'**
  String homeAdviceExerciseOnTrack(int minutes);

  /// Home AI advice when there is exercise this week but cardio minutes are under the weekly cardio goal (#1943, #3350).
  ///
  /// In ko, this message translates to:
  /// **'이번 주 유산소 {minutes}분 운동했어요. 조금만 더 힘내요!'**
  String homeAdviceExerciseMore(int minutes);

  /// Home AI advice when the member exercised this week but logged no cardio (#3350).
  ///
  /// In ko, this message translates to:
  /// **'이번 주 유산소 기록은 아직 없어요. 가볍게 걷기부터 시작해 볼까요?'**
  String get homeAdviceExerciseCardioStart;

  /// Home AI advice when nothing was logged this week (#1943).
  ///
  /// In ko, this message translates to:
  /// **'이번 주 운동을 시작해 보세요. 가벼운 걷기부터 좋아요.'**
  String get homeAdviceExerciseStart;

  /// Home AI advice when today's sodium is over the goal, naming the foods that added the most sodium. {foods} is the member's own food names, not translated (#2644).
  ///
  /// In ko, this message translates to:
  /// **'{foods} 섭취로 나트륨이 높아요.'**
  String homeAdviceSodiumOverSources(String foods);

  /// Joins the two top sodium foods in the home AI advice (#2644).
  ///
  /// In ko, this message translates to:
  /// **'{first}·{second}'**
  String homeAdviceFoodPair(String first, String second);

  /// No description provided for @homeAiAdviceBody.
  ///
  /// In ko, this message translates to:
  /// **'아침 식단과 저녁 PT는 완벽했어요! 점심 짬뽕으로 나트륨이 높았으니 물을 충분히 마시고, 담당 트레이너가 강조한 어깨 스트레칭으로 건강하게 마무리해 보세요.'**
  String get homeAiAdviceBody;

  /// No description provided for @homeAiAdviceNoRecord.
  ///
  /// In ko, this message translates to:
  /// **'오늘 식단과 운동을 기록하면 하루를 돌아보는 AI 조언을 드릴게요.'**
  String get homeAiAdviceNoRecord;

  /// No description provided for @homeMacroCarbs.
  ///
  /// In ko, this message translates to:
  /// **'탄수화물'**
  String get homeMacroCarbs;

  /// No description provided for @homeMacroProtein.
  ///
  /// In ko, this message translates to:
  /// **'단백질'**
  String get homeMacroProtein;

  /// No description provided for @homeMacroFat.
  ///
  /// In ko, this message translates to:
  /// **'지방'**
  String get homeMacroFat;

  /// No description provided for @homeMealChickenSalad.
  ///
  /// In ko, this message translates to:
  /// **'닭가슴살 샐러드'**
  String get homeMealChickenSalad;

  /// No description provided for @homeDetails.
  ///
  /// In ko, this message translates to:
  /// **'자세히'**
  String get homeDetails;

  /// No description provided for @homeGoal.
  ///
  /// In ko, this message translates to:
  /// **'목표'**
  String get homeGoal;

  /// No description provided for @homeDietNutritionTitle.
  ///
  /// In ko, this message translates to:
  /// **'식단 · 영양'**
  String get homeDietNutritionTitle;

  /// No description provided for @homeCalorieIntake.
  ///
  /// In ko, this message translates to:
  /// **'오늘 섭취 칼로리'**
  String get homeCalorieIntake;

  /// No description provided for @homeAchieveRate.
  ///
  /// In ko, this message translates to:
  /// **'달성률'**
  String get homeAchieveRate;

  /// No description provided for @homeWeeklyMetricTrend.
  ///
  /// In ko, this message translates to:
  /// **'주간 {metric} 추이'**
  String homeWeeklyMetricTrend(String metric);

  /// No description provided for @homeExerciseTrendUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'주간 운동 기록을 불러오지 못했어요.'**
  String get homeExerciseTrendUnavailable;

  /// No description provided for @homeExerciseBurned.
  ///
  /// In ko, this message translates to:
  /// **'소모 칼로리'**
  String get homeExerciseBurned;

  /// No description provided for @homeMealSourceTrainer.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 추천'**
  String get homeMealSourceTrainer;

  /// No description provided for @homeMealSourceAi.
  ///
  /// In ko, this message translates to:
  /// **'AI 추천'**
  String get homeMealSourceAi;

  /// No description provided for @homeMealReasonSodium.
  ///
  /// In ko, this message translates to:
  /// **'나트륨 조절에 좋아요'**
  String get homeMealReasonSodium;

  /// No description provided for @homeMealTagLowSodium.
  ///
  /// In ko, this message translates to:
  /// **'저나트륨'**
  String get homeMealTagLowSodium;

  /// No description provided for @homeMealBrownRiceBox.
  ///
  /// In ko, this message translates to:
  /// **'현미 도시락'**
  String get homeMealBrownRiceBox;

  /// No description provided for @homeMealReasonGlucose.
  ///
  /// In ko, this message translates to:
  /// **'혈당 안정에 도움돼요'**
  String get homeMealReasonGlucose;

  /// No description provided for @homeMealTagLowSugar.
  ///
  /// In ko, this message translates to:
  /// **'저당'**
  String get homeMealTagLowSugar;

  /// No description provided for @homeMealSalmon.
  ///
  /// In ko, this message translates to:
  /// **'연어 구이 + 나물'**
  String get homeMealSalmon;

  /// No description provided for @homeMealReasonOmega.
  ///
  /// In ko, this message translates to:
  /// **'오메가3 + 식이섬유'**
  String get homeMealReasonOmega;

  /// No description provided for @homeMealTagHighProtein.
  ///
  /// In ko, this message translates to:
  /// **'고단백'**
  String get homeMealTagHighProtein;

  /// No description provided for @homeMealTofu.
  ///
  /// In ko, this message translates to:
  /// **'두부 채소 볶음'**
  String get homeMealTofu;

  /// No description provided for @homeMealReasonLowCal.
  ///
  /// In ko, this message translates to:
  /// **'칼로리 낮고 포만감↑'**
  String get homeMealReasonLowCal;

  /// No description provided for @homeMealTagLowCal.
  ///
  /// In ko, this message translates to:
  /// **'저칼로리'**
  String get homeMealTagLowCal;

  /// No description provided for @homeMealNamulBibimbap.
  ///
  /// In ko, this message translates to:
  /// **'나물 비빔밥'**
  String get homeMealNamulBibimbap;

  /// No description provided for @homeMealReasonFiber.
  ///
  /// In ko, this message translates to:
  /// **'식이섬유가 풍부해요'**
  String get homeMealReasonFiber;

  /// No description provided for @homeMealTagLowFat.
  ///
  /// In ko, this message translates to:
  /// **'저지방'**
  String get homeMealTagLowFat;

  /// No description provided for @homeTrainerPickReasonSodiumLow.
  ///
  /// In ko, this message translates to:
  /// **'나트륨을 줄여 줘요'**
  String get homeTrainerPickReasonSodiumLow;

  /// No description provided for @homeTrainerPickReasonProteinHigh.
  ///
  /// In ko, this message translates to:
  /// **'단백질을 채워 줘요'**
  String get homeTrainerPickReasonProteinHigh;

  /// No description provided for @homeTrainerPickReasonCalorieLow.
  ///
  /// In ko, this message translates to:
  /// **'가볍게 먹기 좋아요'**
  String get homeTrainerPickReasonCalorieLow;

  /// No description provided for @homeTrainerPickReasonCalorieHigh.
  ///
  /// In ko, this message translates to:
  /// **'든든하게 채워 줘요'**
  String get homeTrainerPickReasonCalorieHigh;

  /// No description provided for @homeTrainerPickReasonSugarLow.
  ///
  /// In ko, this message translates to:
  /// **'당류를 줄여 줘요'**
  String get homeTrainerPickReasonSugarLow;

  /// No description provided for @homeTrainerPickReasonFiberHigh.
  ///
  /// In ko, this message translates to:
  /// **'식이섬유를 채워 줘요'**
  String get homeTrainerPickReasonFiberHigh;

  /// No description provided for @homeRecBasisSodium.
  ///
  /// In ko, this message translates to:
  /// **'최근 {days}일 평균 나트륨 {sodium}mg'**
  String homeRecBasisSodium(int days, String sodium);

  /// No description provided for @homeRecBasisOverLimit.
  ///
  /// In ko, this message translates to:
  /// **'목표 초과'**
  String get homeRecBasisOverLimit;

  /// No description provided for @homeRecMealsTitle.
  ///
  /// In ko, this message translates to:
  /// **'추천 식단'**
  String get homeRecMealsTitle;

  /// No description provided for @homeRecMealsErrorTitle.
  ///
  /// In ko, this message translates to:
  /// **'추천 식단을 불러오지 못했어요'**
  String get homeRecMealsErrorTitle;

  /// No description provided for @unitKcal.
  ///
  /// In ko, this message translates to:
  /// **'kcal'**
  String get unitKcal;

  /// No description provided for @unitMinutes.
  ///
  /// In ko, this message translates to:
  /// **'분'**
  String get unitMinutes;

  /// No description provided for @unitKcalValue.
  ///
  /// In ko, this message translates to:
  /// **'{count}kcal'**
  String unitKcalValue(int count);

  /// No description provided for @unitMinutesValue.
  ///
  /// In ko, this message translates to:
  /// **'{count}분'**
  String unitMinutesValue(int count);

  /// No description provided for @dietTitle.
  ///
  /// In ko, this message translates to:
  /// **'식단'**
  String get dietTitle;

  /// No description provided for @dietToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘로'**
  String get dietToday;

  /// No description provided for @dietWeekdayMon.
  ///
  /// In ko, this message translates to:
  /// **'월'**
  String get dietWeekdayMon;

  /// No description provided for @dietWeekdayTue.
  ///
  /// In ko, this message translates to:
  /// **'화'**
  String get dietWeekdayTue;

  /// No description provided for @dietWeekdayWed.
  ///
  /// In ko, this message translates to:
  /// **'수'**
  String get dietWeekdayWed;

  /// No description provided for @dietWeekdayThu.
  ///
  /// In ko, this message translates to:
  /// **'목'**
  String get dietWeekdayThu;

  /// No description provided for @dietWeekdayFri.
  ///
  /// In ko, this message translates to:
  /// **'금'**
  String get dietWeekdayFri;

  /// No description provided for @dietWeekdaySat.
  ///
  /// In ko, this message translates to:
  /// **'토'**
  String get dietWeekdaySat;

  /// No description provided for @dietWeekdaySun.
  ///
  /// In ko, this message translates to:
  /// **'일'**
  String get dietWeekdaySun;

  /// No description provided for @dietNutritionSummary.
  ///
  /// In ko, this message translates to:
  /// **'영양 요약'**
  String get dietNutritionSummary;

  /// 음식 수정 칸 맨 위의 섭취량(g) 라벨. 이 값이 나머지 영양의 기준이다 (#1876)
  ///
  /// In ko, this message translates to:
  /// **'내용량'**
  String get dietAmount;

  /// No description provided for @dietCalories.
  ///
  /// In ko, this message translates to:
  /// **'칼로리'**
  String get dietCalories;

  /// No description provided for @dietSodium.
  ///
  /// In ko, this message translates to:
  /// **'나트륨'**
  String get dietSodium;

  /// No description provided for @dietSugar.
  ///
  /// In ko, this message translates to:
  /// **'당류'**
  String get dietSugar;

  /// No description provided for @dietUnitMg.
  ///
  /// In ko, this message translates to:
  /// **'mg'**
  String get dietUnitMg;

  /// No description provided for @dietUnitG.
  ///
  /// In ko, this message translates to:
  /// **'g'**
  String get dietUnitG;

  /// No description provided for @dietAiFeedback.
  ///
  /// In ko, this message translates to:
  /// **'AI 맞춤 조언'**
  String get dietAiFeedback;

  /// 기간별 AI 조언을 불러오는 동안 카드에 남는 문구 (#1574)
  ///
  /// In ko, this message translates to:
  /// **'이 기간의 조언을 살펴보는 중이에요…'**
  String get aiAdviceLoading;

  /// 기간별 AI 조언 요청이 실패했을 때 카드에 남는 문구 (#1574)
  ///
  /// In ko, this message translates to:
  /// **'조언을 불러오지 못했어요.'**
  String get aiAdviceError;

  /// No description provided for @dietMealLog.
  ///
  /// In ko, this message translates to:
  /// **'식단 기록'**
  String get dietMealLog;

  /// No description provided for @dietAddMeal.
  ///
  /// In ko, this message translates to:
  /// **'식단 추가'**
  String get dietAddMeal;

  /// No description provided for @dietEmptyLog.
  ///
  /// In ko, this message translates to:
  /// **'기록된 식단이 없어요.\n사진으로 끼니를 추가해 보세요!'**
  String get dietEmptyLog;

  /// No description provided for @dietLoadError.
  ///
  /// In ko, this message translates to:
  /// **'식단 정보를 불러오지 못했어요.'**
  String get dietLoadError;

  /// No description provided for @dietMealNotFound.
  ///
  /// In ko, this message translates to:
  /// **'삭제됐거나 없는 기록이에요'**
  String get dietMealNotFound;

  /// No description provided for @dietMealNotFoundMessage.
  ///
  /// In ko, this message translates to:
  /// **'식단 탭에서 기록을 다시 확인해 주세요.'**
  String get dietMealNotFoundMessage;

  /// No description provided for @dietMealNotFoundAction.
  ///
  /// In ko, this message translates to:
  /// **'식단 탭으로'**
  String get dietMealNotFoundAction;

  /// No description provided for @dietPeriodAverage.
  ///
  /// In ko, this message translates to:
  /// **'하루 평균'**
  String get dietPeriodAverage;

  /// No description provided for @dietPeriodEmpty.
  ///
  /// In ko, this message translates to:
  /// **'이 기간에 기록된 식단이 없어요.'**
  String get dietPeriodEmpty;

  /// No description provided for @dietPeriodNoRecord.
  ///
  /// In ko, this message translates to:
  /// **'기록 없음'**
  String get dietPeriodNoRecord;

  /// No description provided for @dietPeriodNotYet.
  ///
  /// In ko, this message translates to:
  /// **'아직 오지 않은 날'**
  String get dietPeriodNotYet;

  /// No description provided for @dietPeriodOverGoal.
  ///
  /// In ko, this message translates to:
  /// **'목표 초과 +{amount} {unit}'**
  String dietPeriodOverGoal(String amount, String unit);

  /// No description provided for @otherDateEmpty.
  ///
  /// In ko, this message translates to:
  /// **'선택한 날짜에 기록된 {section}이 없어요.'**
  String otherDateEmpty(Object section);

  /// No description provided for @dietMealBreakfast.
  ///
  /// In ko, this message translates to:
  /// **'아침'**
  String get dietMealBreakfast;

  /// No description provided for @dietMealLunch.
  ///
  /// In ko, this message translates to:
  /// **'점심'**
  String get dietMealLunch;

  /// No description provided for @dietMealDinner.
  ///
  /// In ko, this message translates to:
  /// **'저녁'**
  String get dietMealDinner;

  /// No description provided for @dietMealSnack.
  ///
  /// In ko, this message translates to:
  /// **'간식'**
  String get dietMealSnack;

  /// No description provided for @dietMealLateNight.
  ///
  /// In ko, this message translates to:
  /// **'야식'**
  String get dietMealLateNight;

  /// No description provided for @dietMealSheetTitle.
  ///
  /// In ko, this message translates to:
  /// **'{meal} 식단'**
  String dietMealSheetTitle(String meal);

  /// 음식 이름이 공공 영양 DB 에 붙었을 때 제안 줄에 적는 대표 이름 (#1896)
  ///
  /// In ko, this message translates to:
  /// **'공공 DB · {name}'**
  String dietFoodDbMatch(String name);

  /// 끼니 카드가 음식 이름을 두 줄까지만 적을 때, 마지막 줄에 남은 개수를 붙인 말 (#1990)
  ///
  /// In ko, this message translates to:
  /// **'{name} 외 {count}'**
  String dietMoreFoods(String name, int count);

  /// 제안한 공공 DB 영양으로 그 음식의 칸을 채우는 버튼 (#1896)
  ///
  /// In ko, this message translates to:
  /// **'값 채우기'**
  String get dietFillFromDb;

  /// 이름을 바꾼 음식이 같은 음식의 공공 DB 값으로 채워졌을 때 이름 칸 아래 안내 (#2107)
  ///
  /// In ko, this message translates to:
  /// **'공공 DB · {name} 값으로 바꿨어요'**
  String dietFoodFilledFromDb(String name);

  /// 이름을 바꿔 채운 공공 DB 값을 바꾸기 전으로 되돌리는 버튼 (#2107)
  ///
  /// In ko, this message translates to:
  /// **'되돌리기'**
  String get dietUndoFill;

  /// 이름을 바꾼 음식이 공공 DB 에 없어 옛 음식의 값이 남았을 때 이름 칸 아래 안내 (#2107)
  ///
  /// In ko, this message translates to:
  /// **'공공 DB에 없는 음식이에요. 영양 값을 확인해 주세요'**
  String get dietFoodNotInDb;

  /// No description provided for @dietAddSheetTitle.
  ///
  /// In ko, this message translates to:
  /// **'식단 추가'**
  String get dietAddSheetTitle;

  /// No description provided for @dietAddSheetSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'사진으로 음식을 분석해요'**
  String get dietAddSheetSubtitle;

  /// No description provided for @dietPickPhoto.
  ///
  /// In ko, this message translates to:
  /// **'사진 선택'**
  String get dietPickPhoto;

  /// No description provided for @dietPickPhotoSub.
  ///
  /// In ko, this message translates to:
  /// **'갤러리에서 음식 사진 선택'**
  String get dietPickPhotoSub;

  /// No description provided for @dietTakePhoto.
  ///
  /// In ko, this message translates to:
  /// **'사진 찍기'**
  String get dietTakePhoto;

  /// No description provided for @dietTakePhotoSub.
  ///
  /// In ko, this message translates to:
  /// **'카메라로 음식 촬영'**
  String get dietTakePhotoSub;

  /// No description provided for @dietAddPhoto.
  ///
  /// In ko, this message translates to:
  /// **'사진 추가'**
  String get dietAddPhoto;

  /// No description provided for @dietAddPhotoSub.
  ///
  /// In ko, this message translates to:
  /// **'앨범·카메라·파일에서 음식 사진 선택'**
  String get dietAddPhotoSub;

  /// No description provided for @dietSamplePhoto.
  ///
  /// In ko, this message translates to:
  /// **'샘플 사진으로 체험'**
  String get dietSamplePhoto;

  /// No description provided for @dietSamplePhotoSub.
  ///
  /// In ko, this message translates to:
  /// **'준비된 음식 사진으로 분석해 보기'**
  String get dietSamplePhotoSub;

  /// No description provided for @dietSamplePhotoBack.
  ///
  /// In ko, this message translates to:
  /// **'뒤로'**
  String get dietSamplePhotoBack;

  /// No description provided for @dietExampleResultTitle.
  ///
  /// In ko, this message translates to:
  /// **'사진을 분석하지 않은 예시 결과예요'**
  String get dietExampleResultTitle;

  /// No description provided for @dietExampleResultMessage.
  ///
  /// In ko, this message translates to:
  /// **'체험 버전은 샘플 사진을 골라야 사진에 맞는 결과가 나와요'**
  String get dietExampleResultMessage;

  /// No description provided for @dietPhotoLoadError.
  ///
  /// In ko, this message translates to:
  /// **'사진을 불러오지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get dietPhotoLoadError;

  /// No description provided for @dietCameraPermissionDenied.
  ///
  /// In ko, this message translates to:
  /// **'음식 사진을 촬영하려면 카메라 권한이 필요해요. 사진 찍기를 눌러 다시 시도해 주세요'**
  String get dietCameraPermissionDenied;

  /// No description provided for @dietCameraPermissionPermanentlyDenied.
  ///
  /// In ko, this message translates to:
  /// **'카메라 접근이 꺼져 있어요. 설정에서 카메라를 켜면 음식 사진을 촬영할 수 있어요'**
  String get dietCameraPermissionPermanentlyDenied;

  /// No description provided for @dietPhotoPermissionDenied.
  ///
  /// In ko, this message translates to:
  /// **'음식 사진을 고르려면 사진 권한이 필요해요. 사진 선택을 눌러 다시 시도해 주세요'**
  String get dietPhotoPermissionDenied;

  /// No description provided for @dietPhotoPermissionPermanentlyDenied.
  ///
  /// In ko, this message translates to:
  /// **'사진 접근이 꺼져 있어요. 설정에서 사진을 켜면 보관함에서 음식 사진을 고를 수 있어요'**
  String get dietPhotoPermissionPermanentlyDenied;

  /// No description provided for @dietPhotoPermissionRestricted.
  ///
  /// In ko, this message translates to:
  /// **'기기 설정이나 관리 정책으로 카메라·사진을 사용할 수 없어요'**
  String get dietPhotoPermissionRestricted;

  /// No description provided for @dietPhotoUnsupportedFormat.
  ///
  /// In ko, this message translates to:
  /// **'지원하지 않는 사진 형식이에요. JPG 또는 PNG 사진으로 다시 시도해 주세요'**
  String get dietPhotoUnsupportedFormat;

  /// No description provided for @dietPhotoTooLarge.
  ///
  /// In ko, this message translates to:
  /// **'사진 용량이 너무 커요. 다른 사진으로 다시 시도해 주세요'**
  String get dietPhotoTooLarge;

  /// No description provided for @dietOpenSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정 열기'**
  String get dietOpenSettings;

  /// No description provided for @dietOpenSettingsFailed.
  ///
  /// In ko, this message translates to:
  /// **'설정을 열지 못했어요. 설정 › Oncare에서 카메라·사진 접근을 켜 주세요'**
  String get dietOpenSettingsFailed;

  /// No description provided for @dietAnalyzing.
  ///
  /// In ko, this message translates to:
  /// **'분석 중…'**
  String get dietAnalyzing;

  /// No description provided for @dietAnalysisFailed.
  ///
  /// In ko, this message translates to:
  /// **'분석 실패'**
  String get dietAnalysisFailed;

  /// Label of the date a photo-analysed meal is logged under.
  ///
  /// In ko, this message translates to:
  /// **'기록 날짜'**
  String get dietRecordDate;

  /// Button on the record-date row of the analysis result sheet and the meal detail. Moves the meal to the picked day on its own (#1241, #1947).
  ///
  /// In ko, this message translates to:
  /// **'날짜 변경'**
  String get dietRecordDateChange;

  /// Confirmation after moving a meal to another day.
  ///
  /// In ko, this message translates to:
  /// **'{date} 식단으로 옮겼어요'**
  String dietRecordDateMoved(String date);

  /// Error shown when moving a meal to another day fails.
  ///
  /// In ko, this message translates to:
  /// **'날짜를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get dietRecordDateFailed;

  /// Label of the meal-type row next to the record date in the meal detail (#1947).
  ///
  /// In ko, this message translates to:
  /// **'끼니'**
  String get dietMealKind;

  /// No description provided for @dietAnalysisDone.
  ///
  /// In ko, this message translates to:
  /// **'분석 완료!'**
  String get dietAnalysisDone;

  /// No description provided for @dietAiNutritionResult.
  ///
  /// In ko, this message translates to:
  /// **'AI 영양 분석 결과'**
  String get dietAiNutritionResult;

  /// No description provided for @dietAnalyzingBody.
  ///
  /// In ko, this message translates to:
  /// **'사진 속 음식을 분석하고 있어요'**
  String get dietAnalyzingBody;

  /// No description provided for @dietAnalysisFailedBody.
  ///
  /// In ko, this message translates to:
  /// **'분석하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get dietAnalysisFailedBody;

  /// No description provided for @dietAnalysisUnsupportedFormat.
  ///
  /// In ko, this message translates to:
  /// **'이 사진 형식은 분석할 수 없어요. JPG 또는 PNG 사진으로 다시 골라 주세요.'**
  String get dietAnalysisUnsupportedFormat;

  /// No description provided for @dietAnalysisBadRequest.
  ///
  /// In ko, this message translates to:
  /// **'사진을 읽지 못했어요. 다른 사진으로 다시 골라 주세요.'**
  String get dietAnalysisBadRequest;

  /// No description provided for @dietAnalysisUnauthorized.
  ///
  /// In ko, this message translates to:
  /// **'로그인이 만료됐어요. 다시 로그인한 뒤 기록해 주세요.'**
  String get dietAnalysisUnauthorized;

  /// No description provided for @dietAnalysisNotImplemented.
  ///
  /// In ko, this message translates to:
  /// **'지금은 사진 분석을 쓸 수 없어요. 직접 추가로 기록해 주세요.'**
  String get dietAnalysisNotImplemented;

  /// No description provided for @dietAnalysisNoFood.
  ///
  /// In ko, this message translates to:
  /// **'사진에서 음식을 찾지 못했어요. 다른 사진을 고르거나 직접 추가해 주세요.'**
  String get dietAnalysisNoFood;

  /// No description provided for @dietAnalysisDailyLimit.
  ///
  /// In ko, this message translates to:
  /// **'오늘 사진 분석 횟수를 다 썼어요. 내일 다시 쓸 수 있고, 지금은 직접 추가로 기록할 수 있어요.'**
  String get dietAnalysisDailyLimit;

  /// No description provided for @dietAnalysisRateLimited.
  ///
  /// In ko, this message translates to:
  /// **'사진 분석 요청이 너무 잦아요. 잠시 후 다시 시도하거나 직접 추가해 주세요.'**
  String get dietAnalysisRateLimited;

  /// No description provided for @dietAnalysisUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'지금은 사진 분석을 쓸 수 없어요. 직접 추가로 기록해 주세요.'**
  String get dietAnalysisUnavailable;

  /// No description provided for @dietAnalysisAiCapacity.
  ///
  /// In ko, this message translates to:
  /// **'지금은 AI 기능 이용이 많아 잠시 쉬어요. 내일 다시 쓸 수 있고, 지금은 직접 추가로 기록할 수 있어요.'**
  String get dietAnalysisAiCapacity;

  /// No description provided for @dietAnalysisPickAnother.
  ///
  /// In ko, this message translates to:
  /// **'다른 사진 고르기'**
  String get dietAnalysisPickAnother;

  /// No description provided for @dietAnalysisSignIn.
  ///
  /// In ko, this message translates to:
  /// **'다시 로그인'**
  String get dietAnalysisSignIn;

  /// No description provided for @dietAnalysisClose.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get dietAnalysisClose;

  /// No description provided for @dietRecognizedFood.
  ///
  /// In ko, this message translates to:
  /// **'인식된 음식'**
  String get dietRecognizedFood;

  /// No description provided for @dietNoRecognizedFood.
  ///
  /// In ko, this message translates to:
  /// **'인식된 음식이 없어요'**
  String get dietNoRecognizedFood;

  /// No description provided for @dietNutritionResult.
  ///
  /// In ko, this message translates to:
  /// **'영양 정보'**
  String get dietNutritionResult;

  /// No description provided for @dietSaved.
  ///
  /// In ko, this message translates to:
  /// **'식단을 저장했어요'**
  String get dietSaved;

  /// No description provided for @dietSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get dietSaveFailed;

  /// No description provided for @dietManualAlreadySaved.
  ///
  /// In ko, this message translates to:
  /// **'앞서 보낸 끼니가 이미 저장돼 있어요. 기록을 확인해 주세요'**
  String get dietManualAlreadySaved;

  /// No description provided for @dietDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'식단 기록 삭제'**
  String get dietDeleteTitle;

  /// No description provided for @dietDeleteConfirm.
  ///
  /// In ko, this message translates to:
  /// **'이 식단 기록을 삭제할까요?'**
  String get dietDeleteConfirm;

  /// No description provided for @dietDeleteWhenEmpty.
  ///
  /// In ko, this message translates to:
  /// **'음식이 하나도 남지 않았어요. 이 식단 기록을 삭제할까요?'**
  String get dietDeleteWhenEmpty;

  /// No description provided for @dietCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get dietCancel;

  /// No description provided for @dietDelete.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get dietDelete;

  /// No description provided for @dietDeleted.
  ///
  /// In ko, this message translates to:
  /// **'식단을 삭제했어요'**
  String get dietDeleted;

  /// No description provided for @dietDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'삭제하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get dietDeleteFailed;

  /// No description provided for @dietSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get dietSave;

  /// No description provided for @dietMealInfo.
  ///
  /// In ko, this message translates to:
  /// **'끼니 정보'**
  String get dietMealInfo;

  /// No description provided for @dietEatenFood.
  ///
  /// In ko, this message translates to:
  /// **'먹은 음식'**
  String get dietEatenFood;

  /// No description provided for @dietNewFood.
  ///
  /// In ko, this message translates to:
  /// **'새 음식'**
  String get dietNewFood;

  /// No description provided for @dietAddFood.
  ///
  /// In ko, this message translates to:
  /// **'음식 추가'**
  String get dietAddFood;

  /// No description provided for @dietManualAdd.
  ///
  /// In ko, this message translates to:
  /// **'직접 추가'**
  String get dietManualAdd;

  /// No description provided for @dietManualAddTitle.
  ///
  /// In ko, this message translates to:
  /// **'식단 직접 추가'**
  String get dietManualAddTitle;

  /// No description provided for @dietManualAddHint.
  ///
  /// In ko, this message translates to:
  /// **'음식 이름을 적으면 영양 정보를 찾아 채워요. 포인트는 사진으로 기록한 끼니에만 쌓여요'**
  String get dietManualAddHint;

  /// No description provided for @dietManualAddEmpty.
  ///
  /// In ko, this message translates to:
  /// **'음식을 하나 이상 적어 주세요'**
  String get dietManualAddEmpty;

  /// No description provided for @dietEditFoodHint.
  ///
  /// In ko, this message translates to:
  /// **'내용량을 고치면 영양이 비례해 따라와요'**
  String get dietEditFoodHint;

  /// No description provided for @dietTotalCalories.
  ///
  /// In ko, this message translates to:
  /// **'총 칼로리'**
  String get dietTotalCalories;

  /// No description provided for @dietNutritionInfo.
  ///
  /// In ko, this message translates to:
  /// **'영양 정보'**
  String get dietNutritionInfo;

  /// No description provided for @dietEditNutritionHint.
  ///
  /// In ko, this message translates to:
  /// **'음식별 영양을 고치면 여기에 합쳐져요'**
  String get dietEditNutritionHint;

  /// No description provided for @dietSugarOverCarbs.
  ///
  /// In ko, this message translates to:
  /// **'당류는 탄수화물보다 클 수 없어요'**
  String get dietSugarOverCarbs;

  /// No description provided for @dietDeleteMeal.
  ///
  /// In ko, this message translates to:
  /// **'식단 삭제'**
  String get dietDeleteMeal;

  /// No description provided for @dietEditMeal.
  ///
  /// In ko, this message translates to:
  /// **'식단 수정'**
  String get dietEditMeal;

  /// No description provided for @exTypeCardio.
  ///
  /// In ko, this message translates to:
  /// **'유산소'**
  String get exTypeCardio;

  /// No description provided for @exTypeStrength.
  ///
  /// In ko, this message translates to:
  /// **'근력'**
  String get exTypeStrength;

  /// No description provided for @exTypeFlexibility.
  ///
  /// In ko, this message translates to:
  /// **'스트레칭'**
  String get exTypeFlexibility;

  /// No description provided for @exTypeOtherChip.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get exTypeOtherChip;

  /// No description provided for @exLevelLight.
  ///
  /// In ko, this message translates to:
  /// **'가벼움'**
  String get exLevelLight;

  /// No description provided for @exLevelModerate.
  ///
  /// In ko, this message translates to:
  /// **'보통'**
  String get exLevelModerate;

  /// No description provided for @exLevelHigh.
  ///
  /// In ko, this message translates to:
  /// **'높음'**
  String get exLevelHigh;

  /// No description provided for @exExerciseLog.
  ///
  /// In ko, this message translates to:
  /// **'운동 기록'**
  String get exExerciseLog;

  /// No description provided for @exGymTab.
  ///
  /// In ko, this message translates to:
  /// **'헬스장'**
  String get exGymTab;

  /// No description provided for @exMyGymSection.
  ///
  /// In ko, this message translates to:
  /// **'내 헬스장'**
  String get exMyGymSection;

  /// No description provided for @exConnected.
  ///
  /// In ko, this message translates to:
  /// **'연결됨'**
  String get exConnected;

  /// No description provided for @exTrainerAffiliation.
  ///
  /// In ko, this message translates to:
  /// **'소속 헬스장'**
  String get exTrainerAffiliation;

  /// No description provided for @exTrainerIntroSection.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 소개'**
  String get exTrainerIntroSection;

  /// No description provided for @exTrainerCareer.
  ///
  /// In ko, this message translates to:
  /// **'경력 {career}'**
  String exTrainerCareer(String career);

  /// No description provided for @exTrainerCertifications.
  ///
  /// In ko, this message translates to:
  /// **'자격증 · 인증'**
  String get exTrainerCertifications;

  /// No description provided for @exNearbyGymsMapLabel.
  ///
  /// In ko, this message translates to:
  /// **'내 주변 헬스장'**
  String get exNearbyGymsMapLabel;

  /// No description provided for @exGymMapUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'지도를 불러오지 못했어요'**
  String get exGymMapUnavailable;

  /// No description provided for @exActivityTitle.
  ///
  /// In ko, this message translates to:
  /// **'운동 현황'**
  String get exActivityTitle;

  /// No description provided for @exBurnWeekOfMonthTitle.
  ///
  /// In ko, this message translates to:
  /// **'{month}월 {week}주차 소모'**
  String exBurnWeekOfMonthTitle(int month, int week);

  /// No description provided for @exBurnTodayTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘 소모'**
  String get exBurnTodayTitle;

  /// No description provided for @exBurnWeekTitle.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 소모'**
  String get exBurnWeekTitle;

  /// No description provided for @exBurnAllTitle.
  ///
  /// In ko, this message translates to:
  /// **'평균 소모'**
  String get exBurnAllTitle;

  /// No description provided for @exGoalValue.
  ///
  /// In ko, this message translates to:
  /// **'목표 {value}'**
  String exGoalValue(String value);

  /// No description provided for @exLoadEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 기록이 없어요.'**
  String get exLoadEmpty;

  /// No description provided for @exThisWeek.
  ///
  /// In ko, this message translates to:
  /// **'이번 주'**
  String get exThisWeek;

  /// No description provided for @exPeriodAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get exPeriodAll;

  /// No description provided for @exRestSeconds.
  ///
  /// In ko, this message translates to:
  /// **'휴식 {seconds}초'**
  String exRestSeconds(int seconds);

  /// No description provided for @exStreakCheer.
  ///
  /// In ko, this message translates to:
  /// **'{days}일 연속 운동 중이에요!'**
  String exStreakCheer(int days);

  /// No description provided for @exStreakStart.
  ///
  /// In ko, this message translates to:
  /// **'오늘 운동으로 연속 운동을 시작해 봐요.'**
  String get exStreakStart;

  /// No description provided for @exStreakProtected.
  ///
  /// In ko, this message translates to:
  /// **'보호권으로 이어짐'**
  String get exStreakProtected;

  /// No description provided for @exToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get exToday;

  /// No description provided for @exLoadError.
  ///
  /// In ko, this message translates to:
  /// **'운동 정보를 불러오지 못했어요.'**
  String get exLoadError;

  /// No description provided for @exCompletedPtTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘 완료한 PT'**
  String get exCompletedPtTitle;

  /// No description provided for @exCompletedPtTime.
  ///
  /// In ko, this message translates to:
  /// **'{time} 완료'**
  String exCompletedPtTime(String time);

  /// PT card chip — which session with the assigned trainer this was (#2666).
  ///
  /// In ko, this message translates to:
  /// **'{count}회차'**
  String exPtSessionNumber(int count);

  /// No description provided for @exCompletedPtNoProgram.
  ///
  /// In ko, this message translates to:
  /// **'기록된 PT 프로그램이 없어요.'**
  String get exCompletedPtNoProgram;

  /// No description provided for @exAddExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동 추가'**
  String get exAddExercise;

  /// No description provided for @exDurationMinutes.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분'**
  String exDurationMinutes(int minutes);

  /// No description provided for @exEditExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동 기록 수정'**
  String get exEditExercise;

  /// No description provided for @exSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get exSave;

  /// No description provided for @exExerciseType.
  ///
  /// In ko, this message translates to:
  /// **'운동 유형'**
  String get exExerciseType;

  /// No description provided for @exExerciseDate.
  ///
  /// In ko, this message translates to:
  /// **'날짜'**
  String get exExerciseDate;

  /// No description provided for @exExerciseName.
  ///
  /// In ko, this message translates to:
  /// **'운동 이름'**
  String get exExerciseName;

  /// No description provided for @exExerciseNameHintCardio.
  ///
  /// In ko, this message translates to:
  /// **'예) 러닝머신, 실내 자전거'**
  String get exExerciseNameHintCardio;

  /// No description provided for @exExerciseNameHintStrength.
  ///
  /// In ko, this message translates to:
  /// **'예) 스쿼트, 벤치프레스'**
  String get exExerciseNameHintStrength;

  /// No description provided for @exExerciseNameHintFlexibility.
  ///
  /// In ko, this message translates to:
  /// **'예) 전신 스트레칭, 요가'**
  String get exExerciseNameHintFlexibility;

  /// No description provided for @exExerciseNameHintOther.
  ///
  /// In ko, this message translates to:
  /// **'예) 재활 운동, 스포츠 활동'**
  String get exExerciseNameHintOther;

  /// No description provided for @exExerciseReps.
  ///
  /// In ko, this message translates to:
  /// **'횟수'**
  String get exExerciseReps;

  /// No description provided for @exExerciseHold.
  ///
  /// In ko, this message translates to:
  /// **'버티는 시간'**
  String get exExerciseHold;

  /// No description provided for @exExerciseStrengthAmount.
  ///
  /// In ko, this message translates to:
  /// **'세트 · 횟수 · 중량'**
  String get exExerciseStrengthAmount;

  /// No description provided for @exExerciseStrengthAmountHold.
  ///
  /// In ko, this message translates to:
  /// **'세트 · 버티는 시간 · 중량'**
  String get exExerciseStrengthAmountHold;

  /// No description provided for @exExerciseMeasure.
  ///
  /// In ko, this message translates to:
  /// **'재는 방법'**
  String get exExerciseMeasure;

  /// No description provided for @exExerciseWeight.
  ///
  /// In ko, this message translates to:
  /// **'중량'**
  String get exExerciseWeight;

  /// No description provided for @exUnitMinutes.
  ///
  /// In ko, this message translates to:
  /// **'분'**
  String get exUnitMinutes;

  /// No description provided for @exUnitSets.
  ///
  /// In ko, this message translates to:
  /// **'세트'**
  String get exUnitSets;

  /// No description provided for @exUnitReps.
  ///
  /// In ko, this message translates to:
  /// **'회'**
  String get exUnitReps;

  /// No description provided for @exUnitSeconds.
  ///
  /// In ko, this message translates to:
  /// **'초'**
  String get exUnitSeconds;

  /// No description provided for @exUnitHours.
  ///
  /// In ko, this message translates to:
  /// **'시간'**
  String get exUnitHours;

  /// No description provided for @exUnitKg.
  ///
  /// In ko, this message translates to:
  /// **'kg'**
  String get exUnitKg;

  /// No description provided for @exEnterName.
  ///
  /// In ko, this message translates to:
  /// **'운동 이름을 입력해 주세요'**
  String get exEnterName;

  /// No description provided for @exExerciseDuration.
  ///
  /// In ko, this message translates to:
  /// **'운동 시간'**
  String get exExerciseDuration;

  /// No description provided for @exExerciseSets.
  ///
  /// In ko, this message translates to:
  /// **'세트 수'**
  String get exExerciseSets;

  /// No description provided for @exSetsCount.
  ///
  /// In ko, this message translates to:
  /// **'{sets}세트'**
  String exSetsCount(int sets);

  /// No description provided for @exRepsCount.
  ///
  /// In ko, this message translates to:
  /// **'{reps}회'**
  String exRepsCount(int reps);

  /// One set of a hold exercise in seconds (#3138). Same shape as the trainer web progHoldValue
  ///
  /// In ko, this message translates to:
  /// **'{seconds}초'**
  String exHoldSecondsCount(int seconds);

  /// No description provided for @exEnterSets.
  ///
  /// In ko, this message translates to:
  /// **'세트 수를 입력해 주세요'**
  String get exEnterSets;

  /// No description provided for @exExerciseIntensity.
  ///
  /// In ko, this message translates to:
  /// **'운동 강도'**
  String get exExerciseIntensity;

  /// No description provided for @exEstimatedCalories.
  ///
  /// In ko, this message translates to:
  /// **'예상 소모 칼로리'**
  String get exEstimatedCalories;

  /// 이름을 적기 전에는 확정된 소모 칼로리를 띄우지 않는다 (#1312)
  ///
  /// In ko, this message translates to:
  /// **'운동 이름을 적어 주세요'**
  String get exCaloriesNeedName;

  /// No description provided for @exCaloriesCalculating.
  ///
  /// In ko, this message translates to:
  /// **'계산 중…'**
  String get exCaloriesCalculating;

  /// 종목 참조표와 회원 체중으로 계산한 값의 근거 표시 (#1312)
  ///
  /// In ko, this message translates to:
  /// **'{activity} 기준 · 체중 반영'**
  String exCaloriesFromCatalog(String activity);

  /// 이름이 종목으로 접히지 않아 유형 평균으로 때운 값 (#1312)
  ///
  /// In ko, this message translates to:
  /// **'운동 유형 평균으로 낸 어림값이에요'**
  String get exCaloriesRoughEstimate;

  /// No description provided for @exEnterDuration.
  ///
  /// In ko, this message translates to:
  /// **'운동 시간을 입력해 주세요'**
  String get exEnterDuration;

  /// No description provided for @exUpdated.
  ///
  /// In ko, this message translates to:
  /// **'운동 기록이 수정됐어요'**
  String get exUpdated;

  /// No description provided for @exLogged.
  ///
  /// In ko, this message translates to:
  /// **'운동이 기록됐어요'**
  String get exLogged;

  /// No description provided for @exQueueTitle.
  ///
  /// In ko, this message translates to:
  /// **'추가할 운동 {count}'**
  String exQueueTitle(int count);

  /// No description provided for @exQueueRemove.
  ///
  /// In ko, this message translates to:
  /// **'목록에서 빼기'**
  String get exQueueRemove;

  /// No description provided for @exQueueFull.
  ///
  /// In ko, this message translates to:
  /// **'한 번에 {count}개까지 추가할 수 있어요'**
  String exQueueFull(int count);

  /// No description provided for @exSaveCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}개 저장'**
  String exSaveCount(int count);

  /// No description provided for @exLoggedCount.
  ///
  /// In ko, this message translates to:
  /// **'운동 {count}개가 기록됐어요'**
  String exLoggedCount(int count);

  /// No description provided for @exQueueDiscardTitle.
  ///
  /// In ko, this message translates to:
  /// **'추가할 운동을 버릴까요?'**
  String get exQueueDiscardTitle;

  /// No description provided for @exQueueDiscardBody.
  ///
  /// In ko, this message translates to:
  /// **'아직 저장하지 않은 운동 {count}개가 사라져요.'**
  String exQueueDiscardBody(int count);

  /// No description provided for @exQueueDiscard.
  ///
  /// In ko, this message translates to:
  /// **'버리기'**
  String get exQueueDiscard;

  /// No description provided for @exOwnRecords.
  ///
  /// In ko, this message translates to:
  /// **'직접 기록한 운동'**
  String get exOwnRecords;

  /// No description provided for @exOwnRecordsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'직접 기록한 운동이 없어요'**
  String get exOwnRecordsEmpty;

  /// Text link at the bottom of the self-logged workouts card — opens that day's workout detail; same wording as the home card link (#2507).
  ///
  /// In ko, this message translates to:
  /// **'자세히'**
  String get exRecordDetailOpen;

  /// No description provided for @exRecordDetailInfo.
  ///
  /// In ko, this message translates to:
  /// **'운동 정보'**
  String get exRecordDetailInfo;

  /// No description provided for @exRecordDetailTotalCalories.
  ///
  /// In ko, this message translates to:
  /// **'총 소모 칼로리'**
  String get exRecordDetailTotalCalories;

  /// No description provided for @exBurnedPrefix.
  ///
  /// In ko, this message translates to:
  /// **'소모'**
  String get exBurnedPrefix;

  /// No description provided for @exRecordMaxWeight.
  ///
  /// In ko, this message translates to:
  /// **'최고 중량'**
  String get exRecordMaxWeight;

  /// No description provided for @exRecordLongest.
  ///
  /// In ko, this message translates to:
  /// **'최장 시간'**
  String get exRecordLongest;

  /// No description provided for @exRecordFirst.
  ///
  /// In ko, this message translates to:
  /// **'첫 기록'**
  String get exRecordFirst;

  /// No description provided for @exRecordDateChange.
  ///
  /// In ko, this message translates to:
  /// **'날짜 변경'**
  String get exRecordDateChange;

  /// Confirmation after moving a day's self-logged workouts to another day.
  ///
  /// In ko, this message translates to:
  /// **'{date} 운동으로 옮겼어요'**
  String exRecordDateMoved(String date);

  /// No description provided for @exRecordDateFailed.
  ///
  /// In ko, this message translates to:
  /// **'날짜를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get exRecordDateFailed;

  /// No description provided for @exCompletedPtDayTitle.
  ///
  /// In ko, this message translates to:
  /// **'완료한 PT'**
  String get exCompletedPtDayTitle;

  /// No description provided for @exCompletedRoutineDayTitle.
  ///
  /// In ko, this message translates to:
  /// **'완료한 개인운동'**
  String get exCompletedRoutineDayTitle;

  /// No description provided for @exDeleteExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동 기록 삭제'**
  String get exDeleteExercise;

  /// No description provided for @exDeleteExerciseBody.
  ///
  /// In ko, this message translates to:
  /// **'이 기록을 삭제하면 되돌릴 수 없어요.'**
  String get exDeleteExerciseBody;

  /// No description provided for @exDeleted.
  ///
  /// In ko, this message translates to:
  /// **'운동 기록을 삭제했어요'**
  String get exDeleted;

  /// No description provided for @exDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'삭제하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get exDeleteFailed;

  /// No description provided for @exCannotDelete.
  ///
  /// In ko, this message translates to:
  /// **'이 기록은 삭제할 수 없어요'**
  String get exCannotDelete;

  /// No description provided for @exSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get exSaveFailed;

  /// No description provided for @exFindGym.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 찾기'**
  String get exFindGym;

  /// No description provided for @exGymDetailTitle.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 상세'**
  String get exGymDetailTitle;

  /// No description provided for @exTrainerDetailTitle.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 상세'**
  String get exTrainerDetailTitle;

  /// No description provided for @exRating.
  ///
  /// In ko, this message translates to:
  /// **'평점'**
  String get exRating;

  /// No description provided for @exAffiliatedTrainer.
  ///
  /// In ko, this message translates to:
  /// **'소속 트레이너'**
  String get exAffiliatedTrainer;

  /// No description provided for @exRecommendationReason.
  ///
  /// In ko, this message translates to:
  /// **'추천 이유'**
  String get exRecommendationReason;

  /// No description provided for @exGymNotFound.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 정보를 찾을 수 없어요.'**
  String get exGymNotFound;

  /// No description provided for @exTrainerNotFound.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 정보를 찾을 수 없어요.'**
  String get exTrainerNotFound;

  /// No description provided for @exTrainerReport.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 신고'**
  String get exTrainerReport;

  /// No description provided for @exTrainerReportShort.
  ///
  /// In ko, this message translates to:
  /// **'신고'**
  String get exTrainerReportShort;

  /// No description provided for @exTrainerReportReasonLabel.
  ///
  /// In ko, this message translates to:
  /// **'신고 사유'**
  String get exTrainerReportReasonLabel;

  /// No description provided for @exTrainerReportReasonImpersonation.
  ///
  /// In ko, this message translates to:
  /// **'사칭'**
  String get exTrainerReportReasonImpersonation;

  /// No description provided for @exTrainerReportReasonInappropriateMessage.
  ///
  /// In ko, this message translates to:
  /// **'부적절한 메시지'**
  String get exTrainerReportReasonInappropriateMessage;

  /// No description provided for @exTrainerReportReasonOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get exTrainerReportReasonOther;

  /// No description provided for @exTrainerReportMemoLabel.
  ///
  /// In ko, this message translates to:
  /// **'내용'**
  String get exTrainerReportMemoLabel;

  /// No description provided for @exTrainerReportMemoHint.
  ///
  /// In ko, this message translates to:
  /// **'어떤 일이 있었는지 적어 주세요'**
  String get exTrainerReportMemoHint;

  /// No description provided for @exTrainerReportMemoRequired.
  ///
  /// In ko, this message translates to:
  /// **'기타 사유는 내용을 적어야 보낼 수 있어요'**
  String get exTrainerReportMemoRequired;

  /// No description provided for @exTrainerReportNotice.
  ///
  /// In ko, this message translates to:
  /// **'신고는 운영자만 확인해요. 누가 신고했는지 트레이너에게 알리지 않아요.'**
  String get exTrainerReportNotice;

  /// No description provided for @exTrainerReportSubmit.
  ///
  /// In ko, this message translates to:
  /// **'신고하기'**
  String get exTrainerReportSubmit;

  /// No description provided for @exTrainerReportSubmitted.
  ///
  /// In ko, this message translates to:
  /// **'신고를 접수했어요. 운영자가 확인할게요.'**
  String get exTrainerReportSubmitted;

  /// No description provided for @exTrainerReportAlreadyOpen.
  ///
  /// In ko, this message translates to:
  /// **'이미 접수된 신고가 있어요. 운영자가 확인하고 있어요.'**
  String get exTrainerReportAlreadyOpen;

  /// No description provided for @exTrainerSelfRegisteredAffiliation.
  ///
  /// In ko, this message translates to:
  /// **'트레이너가 직접 등록한 소속이에요'**
  String get exTrainerSelfRegisteredAffiliation;

  /// No description provided for @exGymSearchPlaceholder.
  ///
  /// In ko, this message translates to:
  /// **'지역이나 헬스장 이름 검색'**
  String get exGymSearchPlaceholder;

  /// No description provided for @exSortRecommended.
  ///
  /// In ko, this message translates to:
  /// **'추천순'**
  String get exSortRecommended;

  /// No description provided for @exSortDistance.
  ///
  /// In ko, this message translates to:
  /// **'거리순'**
  String get exSortDistance;

  /// No description provided for @exSortRating.
  ///
  /// In ko, this message translates to:
  /// **'평점순'**
  String get exSortRating;

  /// No description provided for @exResultCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}개 결과'**
  String exResultCount(int count);

  /// No description provided for @exNoSearchResults.
  ///
  /// In ko, this message translates to:
  /// **'검색 결과가 없어요.'**
  String get exNoSearchResults;

  /// No description provided for @exTrainersLoadError.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 정보를 불러오지 못했어요.'**
  String get exTrainersLoadError;

  /// No description provided for @exNearbyGyms.
  ///
  /// In ko, this message translates to:
  /// **'주변 헬스장'**
  String get exNearbyGyms;

  /// No description provided for @exGymSearchResults.
  ///
  /// In ko, this message translates to:
  /// **'검색 결과'**
  String get exGymSearchResults;

  /// Hides the gym result list so the map fills the space
  ///
  /// In ko, this message translates to:
  /// **'목록 접기'**
  String get exGymListCollapse;

  /// Brings the gym result list back under the map
  ///
  /// In ko, this message translates to:
  /// **'목록 펼치기'**
  String get exGymListExpand;

  /// No description provided for @exGymsLoadError.
  ///
  /// In ko, this message translates to:
  /// **'헬스장을 불러오지 못했어요.'**
  String get exGymsLoadError;

  /// No description provided for @exGymSearchError.
  ///
  /// In ko, this message translates to:
  /// **'헬스장을 검색하지 못했어요.'**
  String get exGymSearchError;

  /// No description provided for @exGymWeekdayHours.
  ///
  /// In ko, this message translates to:
  /// **'평일 {hours}'**
  String exGymWeekdayHours(String hours);

  /// No description provided for @exGymWeekendHours.
  ///
  /// In ko, this message translates to:
  /// **'주말 {hours}'**
  String exGymWeekendHours(String hours);

  /// No description provided for @exTrainerDedicated.
  ///
  /// In ko, this message translates to:
  /// **'전담 트레이너'**
  String get exTrainerDedicated;

  /// No description provided for @exTrainerAvailability.
  ///
  /// In ko, this message translates to:
  /// **'{trainer} 예약 가능 시간'**
  String exTrainerAvailability(String trainer);

  /// No description provided for @exSlotWhen.
  ///
  /// In ko, this message translates to:
  /// **'{date} {time}'**
  String exSlotWhen(String date, String time);

  /// No description provided for @exSlotTypePersonalTraining.
  ///
  /// In ko, this message translates to:
  /// **'1:1 PT'**
  String get exSlotTypePersonalTraining;

  /// No description provided for @exSlotsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간이 없어요'**
  String get exSlotsEmpty;

  /// No description provided for @exSlotsAllBooked.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간이 모두 찼어요'**
  String get exSlotsAllBooked;

  /// No description provided for @exSlotsLoadError.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간을 불러오지 못했어요.'**
  String get exSlotsLoadError;

  /// No description provided for @exReserveFailed.
  ///
  /// In ko, this message translates to:
  /// **'예약하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get exReserveFailed;

  /// No description provided for @exReserveTimeTaken.
  ///
  /// In ko, this message translates to:
  /// **'트레이너의 다른 일정과 겹쳐 이 시간은 예약할 수 없어요. 다른 시간을 골라 주세요'**
  String get exReserveTimeTaken;

  /// No description provided for @exReserveUpcomingExists.
  ///
  /// In ko, this message translates to:
  /// **'이미 다가오는 예약이 있어요. 다른 시간으로 바꾸려면 먼저 예약을 취소해 주세요'**
  String get exReserveUpcomingExists;

  /// No description provided for @exReserveConfirmedSlotGym.
  ///
  /// In ko, this message translates to:
  /// **'{slot} · {gym} 예약이 확정됐어요'**
  String exReserveConfirmedSlotGym(String slot, String gym);

  /// No description provided for @exReserveConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{slot} 예약 확정'**
  String exReserveConfirm(String slot);

  /// No description provided for @exAddress.
  ///
  /// In ko, this message translates to:
  /// **'주소'**
  String get exAddress;

  /// No description provided for @exHours.
  ///
  /// In ko, this message translates to:
  /// **'운영시간'**
  String get exHours;

  /// No description provided for @exPhone.
  ///
  /// In ko, this message translates to:
  /// **'전화'**
  String get exPhone;

  /// No description provided for @exSpecialty.
  ///
  /// In ko, this message translates to:
  /// **'전문 분야'**
  String get exSpecialty;

  /// No description provided for @myTabTitle.
  ///
  /// In ko, this message translates to:
  /// **'MY'**
  String get myTabTitle;

  /// No description provided for @myDefaultUserName.
  ///
  /// In ko, this message translates to:
  /// **'사용자'**
  String get myDefaultUserName;

  /// Shown instead of the email when the account only has the internal placeholder address from a social sign-up.
  ///
  /// In ko, this message translates to:
  /// **'{provider, select, kakao{카카오로 가입} google{구글로 가입} other{소셜 로그인으로 가입}} · 이메일 미등록'**
  String myEmailUnregistered(String provider);

  /// No description provided for @myProfileLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'내 정보를 불러오지 못했어요'**
  String get myProfileLoadFailed;

  /// No description provided for @myPointsLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'포인트 잔액을 불러오지 못했어요'**
  String get myPointsLoadFailed;

  /// No description provided for @mySettingsTitle.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get mySettingsTitle;

  /// No description provided for @myProfileTitle.
  ///
  /// In ko, this message translates to:
  /// **'내 프로필'**
  String get myProfileTitle;

  /// No description provided for @myNotifTitle.
  ///
  /// In ko, this message translates to:
  /// **'알림 설정'**
  String get myNotifTitle;

  /// MY tab: opens the spotlight app guide again (#1857).
  ///
  /// In ko, this message translates to:
  /// **'앱 사용 가이드'**
  String get myGuideTitle;

  /// No description provided for @mySupportTitle.
  ///
  /// In ko, this message translates to:
  /// **'고객 지원'**
  String get mySupportTitle;

  /// No description provided for @myPointsBenefitsTitle.
  ///
  /// In ko, this message translates to:
  /// **'포인트 사용처'**
  String get myPointsBenefitsTitle;

  /// The balance shown on the rewards screen, with thousands separators, e.g. 25,000P.
  ///
  /// In ko, this message translates to:
  /// **'보유 {points}P'**
  String myPointsBalance(int points);

  /// No description provided for @myPointsBenefitsSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'포인트로 받을 수 있는 혜택'**
  String get myPointsBenefitsSubtitle;

  /// No description provided for @myPointsBenefitsHint.
  ///
  /// In ko, this message translates to:
  /// **'기록을 꾸준히 남기면 포인트가 쌓이고, 위 혜택에 사용할 수 있어요.'**
  String get myPointsBenefitsHint;

  /// A point amount with thousands separators, e.g. 5,000P.
  ///
  /// In ko, this message translates to:
  /// **'{points}P'**
  String myPointsCost(int points);

  /// No description provided for @myPointsExchange.
  ///
  /// In ko, this message translates to:
  /// **'교환'**
  String get myPointsExchange;

  /// No description provided for @myPointsExchangeConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'포인트로 교환할까요?'**
  String get myPointsExchangeConfirmTitle;

  /// No description provided for @myPointsExchangeConfirmMessage.
  ///
  /// In ko, this message translates to:
  /// **'{item}에 {cost}를 사용해요. 교환한 쿠폰은 내 혜택에서 볼 수 있어요.'**
  String myPointsExchangeConfirmMessage(String item, String cost);

  /// No description provided for @myPointsExchangeConfirmAction.
  ///
  /// In ko, this message translates to:
  /// **'교환'**
  String get myPointsExchangeConfirmAction;

  /// No description provided for @myPointsExchangeDone.
  ///
  /// In ko, this message translates to:
  /// **'교환했어요'**
  String get myPointsExchangeDone;

  /// No description provided for @myPointsExchangeFailed.
  ///
  /// In ko, this message translates to:
  /// **'교환하지 못했어요. 다시 시도해 주세요.'**
  String get myPointsExchangeFailed;

  /// No description provided for @myPointsExchangeBlocked.
  ///
  /// In ko, this message translates to:
  /// **'지금은 교환할 수 없어요'**
  String get myPointsExchangeBlocked;

  /// No description provided for @myPointsInsufficient.
  ///
  /// In ko, this message translates to:
  /// **'포인트가 부족해요'**
  String get myPointsInsufficient;

  /// No description provided for @myBenefitAlreadyReceived.
  ///
  /// In ko, this message translates to:
  /// **'이미 받았어요'**
  String get myBenefitAlreadyReceived;

  /// No description provided for @myPointsShortfall.
  ///
  /// In ko, this message translates to:
  /// **'{points} 부족해요'**
  String myPointsShortfall(String points);

  /// No description provided for @myPointsNeedTrainer.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너가 있어야 교환할 수 있어요'**
  String get myPointsNeedTrainer;

  /// No description provided for @myPointsNeedGym.
  ///
  /// In ko, this message translates to:
  /// **'헬스장을 연결해야 교환할 수 있어요'**
  String get myPointsNeedGym;

  /// No description provided for @myPointsActiveCoupon.
  ///
  /// In ko, this message translates to:
  /// **'사용하지 않은 쿠폰이 있어요'**
  String get myPointsActiveCoupon;

  /// No description provided for @myPointsMonthlyLimit.
  ///
  /// In ko, this message translates to:
  /// **'이번 달에는 이미 교환했어요'**
  String get myPointsMonthlyLimit;

  /// No description provided for @myPointsShieldLimit.
  ///
  /// In ko, this message translates to:
  /// **'보호권은 최대 4개까지 가질 수 있어요'**
  String get myPointsShieldLimit;

  /// No description provided for @myShopStreakShieldTitle.
  ///
  /// In ko, this message translates to:
  /// **'연속 기록 보호권'**
  String get myShopStreakShieldTitle;

  /// No description provided for @myShopStreakShieldDescription.
  ///
  /// In ko, this message translates to:
  /// **'아무것도 기록하지 못한 날을 연속 기록에 이어 붙여요. 최근 30일 안에서 쓰고, 최대 4개까지 가질 수 있어요.'**
  String get myShopStreakShieldDescription;

  /// No description provided for @myBenefitsStreakShields.
  ///
  /// In ko, this message translates to:
  /// **'연속 기록 보호권'**
  String get myBenefitsStreakShields;

  /// No description provided for @myBenefitsShieldHeld.
  ///
  /// In ko, this message translates to:
  /// **'보유 {held}/{max}개'**
  String myBenefitsShieldHeld(int held, int max);

  /// No description provided for @myBenefitsShieldHeldCount.
  ///
  /// In ko, this message translates to:
  /// **'보유 {held}개'**
  String myBenefitsShieldHeldCount(int held);

  /// No description provided for @myBenefitsShieldGuide.
  ///
  /// In ko, this message translates to:
  /// **'기록이 빈 날을 기록 그래프에서 눌러 이어 붙여요. 최근 30일 안의 날만 돼요.'**
  String get myBenefitsShieldGuide;

  /// No description provided for @myBenefitsShieldUsedTitle.
  ///
  /// In ko, this message translates to:
  /// **'보호한 날'**
  String get myBenefitsShieldUsedTitle;

  /// No description provided for @myBenefitsShieldNoneUsed.
  ///
  /// In ko, this message translates to:
  /// **'아직 보호한 날이 없어요'**
  String get myBenefitsShieldNoneUsed;

  /// No description provided for @myShopGraphColorTitle.
  ///
  /// In ko, this message translates to:
  /// **'그래프 색 바꾸기'**
  String get myShopGraphColorTitle;

  /// No description provided for @myShopGraphColorDescription.
  ///
  /// In ko, this message translates to:
  /// **'포인트 화면 기록 그래프의 색을 골라 바꿔요. 한 번 연 색은 계속 쓸 수 있어요.'**
  String get myShopGraphColorDescription;

  /// No description provided for @myGraphTitle.
  ///
  /// In ko, this message translates to:
  /// **'기록 그래프'**
  String get myGraphTitle;

  /// No description provided for @myGraphMonthLabel.
  ///
  /// In ko, this message translates to:
  /// **'{month}월'**
  String myGraphMonthLabel(int month);

  /// No description provided for @myGraphStreak.
  ///
  /// In ko, this message translates to:
  /// **'연속 기록 {days}일'**
  String myGraphStreak(int days);

  /// No description provided for @myGraphLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'기록 그래프를 불러오지 못했어요.'**
  String get myGraphLoadFailed;

  /// No description provided for @myGraphDate.
  ///
  /// In ko, this message translates to:
  /// **'{month}월 {day}일'**
  String myGraphDate(int month, int day);

  /// No description provided for @myGraphDayHint.
  ///
  /// In ko, this message translates to:
  /// **'칸을 누르면 그날 기록이 보여요'**
  String get myGraphDayHint;

  /// No description provided for @myGraphDayNone.
  ///
  /// In ko, this message translates to:
  /// **'{date} · 기록 없음'**
  String myGraphDayNone(String date);

  /// No description provided for @myGraphDayDiet.
  ///
  /// In ko, this message translates to:
  /// **'{date} · 식단만 기록'**
  String myGraphDayDiet(String date);

  /// No description provided for @myGraphDayExercise.
  ///
  /// In ko, this message translates to:
  /// **'{date} · 운동만 기록'**
  String myGraphDayExercise(String date);

  /// No description provided for @myGraphDayBoth.
  ///
  /// In ko, this message translates to:
  /// **'{date} · 식단 · 운동 모두 기록'**
  String myGraphDayBoth(String date);

  /// No description provided for @myGraphDayProtected.
  ///
  /// In ko, this message translates to:
  /// **'{date} · 보호권으로 이어짐'**
  String myGraphDayProtected(String date);

  /// No description provided for @myGraphProtectAction.
  ///
  /// In ko, this message translates to:
  /// **'보호권 사용'**
  String get myGraphProtectAction;

  /// Confirm button of the use-a-shield dialog. The dialog title already names the shield (#2554).
  ///
  /// In ko, this message translates to:
  /// **'사용'**
  String get myGraphProtectConfirmAction;

  /// No description provided for @myGraphProtectConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'보호권을 사용할까요?'**
  String get myGraphProtectConfirmTitle;

  /// No description provided for @myGraphProtectConfirmMessage.
  ///
  /// In ko, this message translates to:
  /// **'{date}을 연속 기록에 이어 붙여요. 보호권 한 개를 사용해요(남은 보호권 {held}개).'**
  String myGraphProtectConfirmMessage(String date, int held);

  /// No description provided for @myGraphProtectDone.
  ///
  /// In ko, this message translates to:
  /// **'연속을 이어 붙였어요'**
  String get myGraphProtectDone;

  /// No description provided for @myGraphProtectFailed.
  ///
  /// In ko, this message translates to:
  /// **'보호권을 사용하지 못했어요'**
  String get myGraphProtectFailed;

  /// No description provided for @myGraphProtectBuyConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'보호권을 구매할까요?'**
  String get myGraphProtectBuyConfirmTitle;

  /// No description provided for @myGraphProtectBuyConfirmMessage.
  ///
  /// In ko, this message translates to:
  /// **'지금 가진 보호권이 없어요. {cost}로 보호권을 구매하고 {date}을 바로 연속 기록에 이어 붙여요.'**
  String myGraphProtectBuyConfirmMessage(String date, String cost);

  /// No description provided for @myGraphProtectBuyAction.
  ///
  /// In ko, this message translates to:
  /// **'구매하고 사용'**
  String get myGraphProtectBuyAction;

  /// No description provided for @myGraphProtectBoughtNotUsed.
  ///
  /// In ko, this message translates to:
  /// **'보호권은 구매했지만 사용하지 못했어요. 내 혜택에 보관돼요.'**
  String get myGraphProtectBoughtNotUsed;

  /// No description provided for @myGraphColorTitle.
  ///
  /// In ko, this message translates to:
  /// **'그래프 색'**
  String get myGraphColorTitle;

  /// No description provided for @myGraphColorPickTitle.
  ///
  /// In ko, this message translates to:
  /// **'열 색 고르기'**
  String get myGraphColorPickTitle;

  /// No description provided for @myGraphColorLocked.
  ///
  /// In ko, this message translates to:
  /// **'{cost}로 열기'**
  String myGraphColorLocked(String cost);

  /// No description provided for @myGraphColorDone.
  ///
  /// In ko, this message translates to:
  /// **'그래프 색을 바꿨어요'**
  String get myGraphColorDone;

  /// No description provided for @myGraphColorExchangeConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{color} 그래프를 {cost}로 열까요? 한 번 열면 계속 쓸 수 있어요.'**
  String myGraphColorExchangeConfirm(String color, String cost);

  /// No description provided for @myGraphColorUnlocked.
  ///
  /// In ko, this message translates to:
  /// **'그래프 색을 열었어요'**
  String get myGraphColorUnlocked;

  /// No description provided for @myGraphColorFailed.
  ///
  /// In ko, this message translates to:
  /// **'그래프 색을 바꾸지 못했어요'**
  String get myGraphColorFailed;

  /// No description provided for @myGraphColorBlue.
  ///
  /// In ko, this message translates to:
  /// **'파랑'**
  String get myGraphColorBlue;

  /// No description provided for @myGraphColorGreen.
  ///
  /// In ko, this message translates to:
  /// **'초록'**
  String get myGraphColorGreen;

  /// No description provided for @myGraphColorPurple.
  ///
  /// In ko, this message translates to:
  /// **'보라'**
  String get myGraphColorPurple;

  /// No description provided for @myGraphColorOrange.
  ///
  /// In ko, this message translates to:
  /// **'주황'**
  String get myGraphColorOrange;

  /// No description provided for @myGraphColorPink.
  ///
  /// In ko, this message translates to:
  /// **'분홍'**
  String get myGraphColorPink;

  /// No description provided for @myShopProfilePetTitle.
  ///
  /// In ko, this message translates to:
  /// **'프로필 펫 이모지'**
  String get myShopProfilePetTitle;

  /// No description provided for @myShopProfilePetDescription.
  ///
  /// In ko, this message translates to:
  /// **'강아지나 고양이를 골라 7일 동안 MY 프로필 이름 옆에 달아요.'**
  String get myShopProfilePetDescription;

  /// No description provided for @myProfilePetDog.
  ///
  /// In ko, this message translates to:
  /// **'강아지'**
  String get myProfilePetDog;

  /// No description provided for @myProfilePetCat.
  ///
  /// In ko, this message translates to:
  /// **'고양이'**
  String get myProfilePetCat;

  /// No description provided for @myProfilePetSheetTitle.
  ///
  /// In ko, this message translates to:
  /// **'이름 옆에 달 펫을 골라요'**
  String get myProfilePetSheetTitle;

  /// No description provided for @myProfilePetActive.
  ///
  /// In ko, this message translates to:
  /// **'{pet} · {left}'**
  String myProfilePetActive(String pet, String left);

  /// No description provided for @myProfilePetDaysLeft.
  ///
  /// In ko, this message translates to:
  /// **'{days}일 남음'**
  String myProfilePetDaysLeft(int days);

  /// No description provided for @myProfilePetHoursLeft.
  ///
  /// In ko, this message translates to:
  /// **'{hours}시간 남음'**
  String myProfilePetHoursLeft(int hours);

  /// No description provided for @myProfilePetExchangeConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{pet}를 {cost}로 7일 동안 이름 옆에 달까요?'**
  String myProfilePetExchangeConfirm(String pet, String cost);

  /// No description provided for @myProfilePetDone.
  ///
  /// In ko, this message translates to:
  /// **'이름 옆에 펫을 달았어요'**
  String get myProfilePetDone;

  /// No description provided for @myShopWeeklyReportTitle.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트'**
  String get myShopWeeklyReportTitle;

  /// No description provided for @myShopWeeklyReportDescription.
  ///
  /// In ko, this message translates to:
  /// **'{range} 식단·운동 기록과 참고 기록으로 한 주를 돌아보는 리포트를 만들어요.'**
  String myShopWeeklyReportDescription(String range);

  /// No description provided for @myWeeklyReportOwned.
  ///
  /// In ko, this message translates to:
  /// **'지난주 리포트는 이미 받았어요'**
  String get myWeeklyReportOwned;

  /// No description provided for @myWeeklyReportExchangeConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{range} 리포트를 {cost}로 만들까요?'**
  String myWeeklyReportExchangeConfirm(String range, String cost);

  /// No description provided for @myWeeklyReportDone.
  ///
  /// In ko, this message translates to:
  /// **'지난주 리포트를 만들었어요'**
  String get myWeeklyReportDone;

  /// No description provided for @myBenefitsWeeklyReports.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트'**
  String get myBenefitsWeeklyReports;

  /// No description provided for @myWeeklyReportCardTitle.
  ///
  /// In ko, this message translates to:
  /// **'포인트로 받은 리포트'**
  String get myWeeklyReportCardTitle;

  /// No description provided for @coachReportPdfSelfMadeNote.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너 없이 포인트로 받은 리포트라 트레이너 피드백이 없어요.'**
  String get coachReportPdfSelfMadeNote;

  /// No description provided for @coachReportPdfSectionInsights.
  ///
  /// In ko, this message translates to:
  /// **'참고 기록'**
  String get coachReportPdfSectionInsights;

  /// No description provided for @coachReportPdfNoInsights.
  ///
  /// In ko, this message translates to:
  /// **'이 주의 AI 코치 대화에서 감지된 통증·부정적 반응이 없어요.'**
  String get coachReportPdfNoInsights;

  /// No description provided for @coachReportPdfInsightSummary.
  ///
  /// In ko, this message translates to:
  /// **'{label} {count}회'**
  String coachReportPdfInsightSummary(String label, int count);

  /// No description provided for @coachReportPdfInsightMore.
  ///
  /// In ko, this message translates to:
  /// **'외 {count}건'**
  String coachReportPdfInsightMore(int count);

  /// No description provided for @myProfilePetLabel.
  ///
  /// In ko, this message translates to:
  /// **'{pet} 펫 이모지'**
  String myProfilePetLabel(String pet);

  /// No description provided for @myPointsValidDays.
  ///
  /// In ko, this message translates to:
  /// **'교환 후 {days}일 동안 사용'**
  String myPointsValidDays(int days);

  /// No description provided for @myPointsShopLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'사용처를 불러오지 못했어요'**
  String get myPointsShopLoadFailed;

  /// No description provided for @myShopPtRenewalTitle.
  ///
  /// In ko, this message translates to:
  /// **'PT 재등록 3만원 할인'**
  String get myShopPtRenewalTitle;

  /// No description provided for @myShopPtRenewalDescription.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너에게 PT를 다시 등록할 때 30,000원을 할인받아요.'**
  String get myShopPtRenewalDescription;

  /// No description provided for @myShopLockerTitle.
  ///
  /// In ko, this message translates to:
  /// **'개인 락커 1개월 무료'**
  String get myShopLockerTitle;

  /// No description provided for @myShopLockerDescription.
  ///
  /// In ko, this message translates to:
  /// **'연결한 헬스장에서 개인 락커를 한 달 동안 무료로 써요.'**
  String get myShopLockerDescription;

  /// No description provided for @myCouponPtRenewalBenefit.
  ///
  /// In ko, this message translates to:
  /// **'PT 재등록 30,000원 할인'**
  String get myCouponPtRenewalBenefit;

  /// No description provided for @myBenefitsTitle.
  ///
  /// In ko, this message translates to:
  /// **'내 혜택'**
  String get myBenefitsTitle;

  /// No description provided for @myPointsHistoryTitle.
  ///
  /// In ko, this message translates to:
  /// **'포인트 내역'**
  String get myPointsHistoryTitle;

  /// No description provided for @myPointsHistoryEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 포인트 내역이 없어요'**
  String get myPointsHistoryEmpty;

  /// No description provided for @myPointsHistoryEmptyMessage.
  ///
  /// In ko, this message translates to:
  /// **'사진으로 식단을 기록하거나 운동을 기록하면 포인트가 쌓여요.'**
  String get myPointsHistoryEmptyMessage;

  /// No description provided for @myPointsHistoryLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'포인트 내역을 불러오지 못했어요'**
  String get myPointsHistoryLoadFailed;

  /// No description provided for @myPointsHistoryMore.
  ///
  /// In ko, this message translates to:
  /// **'더 보기'**
  String get myPointsHistoryMore;

  /// No description provided for @myPointsHistoryMoreFailed.
  ///
  /// In ko, this message translates to:
  /// **'더 불러오지 못했어요. 다시 시도해 주세요'**
  String get myPointsHistoryMoreFailed;

  /// No description provided for @myPointsReasonDiet.
  ///
  /// In ko, this message translates to:
  /// **'식단 기록'**
  String get myPointsReasonDiet;

  /// No description provided for @myPointsReasonExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동 기록'**
  String get myPointsReasonExercise;

  /// No description provided for @myPointsReasonRoutine.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 완료'**
  String get myPointsReasonRoutine;

  /// No description provided for @myPointsReasonPtRenewal.
  ///
  /// In ko, this message translates to:
  /// **'PT 재등록 할인 쿠폰'**
  String get myPointsReasonPtRenewal;

  /// No description provided for @myPointsReasonLocker.
  ///
  /// In ko, this message translates to:
  /// **'개인 락커 쿠폰'**
  String get myPointsReasonLocker;

  /// No description provided for @myPointsReasonShield.
  ///
  /// In ko, this message translates to:
  /// **'연속 기록 보호권'**
  String get myPointsReasonShield;

  /// No description provided for @myPointsReasonGraphColor.
  ///
  /// In ko, this message translates to:
  /// **'그래프 색'**
  String get myPointsReasonGraphColor;

  /// No description provided for @myPointsReasonEmotePass.
  ///
  /// In ko, this message translates to:
  /// **'채팅 이모티콘 24시간'**
  String get myPointsReasonEmotePass;

  /// No description provided for @myPointsReasonEmoteUnlock.
  ///
  /// In ko, this message translates to:
  /// **'채팅 이모티콘'**
  String get myPointsReasonEmoteUnlock;

  /// No description provided for @myPointsReasonProfilePet.
  ///
  /// In ko, this message translates to:
  /// **'프로필 펫 이모지'**
  String get myPointsReasonProfilePet;

  /// No description provided for @myPointsReasonWeeklyReport.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트'**
  String get myPointsReasonWeeklyReport;

  /// No description provided for @myPointsReasonChallengeStake.
  ///
  /// In ko, this message translates to:
  /// **'주간 챌린지 참가'**
  String get myPointsReasonChallengeStake;

  /// No description provided for @myPointsReasonChallengeReward.
  ///
  /// In ko, this message translates to:
  /// **'주간 챌린지 보상'**
  String get myPointsReasonChallengeReward;

  /// No description provided for @myPointsReasonAiChat.
  ///
  /// In ko, this message translates to:
  /// **'AI 코치 대화 {count}회'**
  String myPointsReasonAiChat(int count);

  /// No description provided for @myPointsReasonOther.
  ///
  /// In ko, this message translates to:
  /// **'포인트'**
  String get myPointsReasonOther;

  /// No description provided for @myPointsKindRevoked.
  ///
  /// In ko, this message translates to:
  /// **'{label} · 기록 삭제로 회수'**
  String myPointsKindRevoked(String label);

  /// No description provided for @myPointsKindRefunded.
  ///
  /// In ko, this message translates to:
  /// **'{label} · 취소로 반환'**
  String myPointsKindRefunded(String label);

  /// No description provided for @myBenefitsView.
  ///
  /// In ko, this message translates to:
  /// **'보기'**
  String get myBenefitsView;

  /// No description provided for @myBenefitsCoupons.
  ///
  /// In ko, this message translates to:
  /// **'쿠폰'**
  String get myBenefitsCoupons;

  /// No description provided for @myBenefitsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'보유한 쿠폰이 없어요'**
  String get myBenefitsEmpty;

  /// No description provided for @myBenefitsEmptyMessage.
  ///
  /// In ko, this message translates to:
  /// **'포인트로 쿠폰을 교환해 보세요.'**
  String get myBenefitsEmptyMessage;

  /// No description provided for @myBenefitsLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'혜택을 불러오지 못했어요'**
  String get myBenefitsLoadFailed;

  /// No description provided for @challengeTitle.
  ///
  /// In ko, this message translates to:
  /// **'주간 운동 챌린지'**
  String get challengeTitle;

  /// 운동 탭 진행 줄 제목 — 이 진행이 어느 주의 것인지 함께 적는다.
  ///
  /// In ko, this message translates to:
  /// **'주간 챌린지 · {range}'**
  String challengeShortWithRange(String range);

  /// Challenge card summary. stake and reward are point amounts such as 100P.
  ///
  /// In ko, this message translates to:
  /// **'{stake}를 걸고 이번 주 {goal}회 운동하면 {reward}를 돌려받아요'**
  String challengeDescription(String stake, int goal, String reward);

  /// No description provided for @challengeJoinWindow.
  ///
  /// In ko, this message translates to:
  /// **'월·화요일에만 참가할 수 있어요'**
  String get challengeJoinWindow;

  /// No description provided for @challengeJoin.
  ///
  /// In ko, this message translates to:
  /// **'참가'**
  String get challengeJoin;

  /// No description provided for @challengeJoinConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'주간 챌린지에 참가할까요?'**
  String get challengeJoinConfirmTitle;

  /// No description provided for @challengeJoinConfirmMessage.
  ///
  /// In ko, this message translates to:
  /// **'{stake}를 걸고 이번 주 {goal}회 운동에 도전해요. 일요일까지 채우면 {reward}를 돌려받고, 못 채우면 건 포인트는 사라져요.'**
  String challengeJoinConfirmMessage(String stake, int goal, String reward);

  /// No description provided for @challengeJoinConfirmAction.
  ///
  /// In ko, this message translates to:
  /// **'참가'**
  String get challengeJoinConfirmAction;

  /// No description provided for @challengeJoinDone.
  ///
  /// In ko, this message translates to:
  /// **'챌린지에 참가했어요'**
  String get challengeJoinDone;

  /// No description provided for @challengeJoinFailed.
  ///
  /// In ko, this message translates to:
  /// **'참가하지 못했어요. 다시 시도해 주세요.'**
  String get challengeJoinFailed;

  /// No description provided for @challengeJoinAlready.
  ///
  /// In ko, this message translates to:
  /// **'이미 참가했어요'**
  String get challengeJoinAlready;

  /// No description provided for @challengeJoinBlocked.
  ///
  /// In ko, this message translates to:
  /// **'지금은 참가할 수 없어요'**
  String get challengeJoinBlocked;

  /// No description provided for @challengeJoinClosed.
  ///
  /// In ko, this message translates to:
  /// **'다음 주 월요일에 다시 참가할 수 있어요'**
  String get challengeJoinClosed;

  /// No description provided for @challengeSettling.
  ///
  /// In ko, this message translates to:
  /// **'지난주 결과 집계 중이에요. 오늘까지 적은 지난주 운동 기록이 반영돼요'**
  String get challengeSettling;

  /// No description provided for @challengeThisWeek.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 진행'**
  String get challengeThisWeek;

  /// Challenge progress: days with a workout record out of the goal.
  ///
  /// In ko, this message translates to:
  /// **'{progress} / {goal}회'**
  String challengeProgress(int progress, int goal);

  /// No description provided for @challengeRemaining.
  ///
  /// In ko, this message translates to:
  /// **'일요일까지 {count}회 더 운동하면 {reward}를 돌려받아요'**
  String challengeRemaining(int count, String reward);

  /// No description provided for @challengeAchieved.
  ///
  /// In ko, this message translates to:
  /// **'목표 달성! 주가 끝나면 {reward}를 받아요'**
  String challengeAchieved(String reward);

  /// No description provided for @challengeGoalSource.
  ///
  /// In ko, this message translates to:
  /// **'목표 횟수는 MY 건강 목표의 주간 운동 횟수를 따라요'**
  String get challengeGoalSource;

  /// No description provided for @challengeHistoryAction.
  ///
  /// In ko, this message translates to:
  /// **'지난 결과'**
  String get challengeHistoryAction;

  /// No description provided for @challengeHistoryTitle.
  ///
  /// In ko, this message translates to:
  /// **'지난 챌린지 결과'**
  String get challengeHistoryTitle;

  /// No description provided for @challengeHistoryEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 참가한 챌린지가 없어요'**
  String get challengeHistoryEmpty;

  /// No description provided for @challengeHistoryEmptyMessage.
  ///
  /// In ko, this message translates to:
  /// **'월·화요일에 주간 운동 챌린지에 참가하면 결과가 여기에 쌓여요.'**
  String get challengeHistoryEmptyMessage;

  /// No description provided for @challengeHistoryLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'챌린지 결과를 불러오지 못했어요'**
  String get challengeHistoryLoadFailed;

  /// No description provided for @challengeHistoryResult.
  ///
  /// In ko, this message translates to:
  /// **'목표 {goal}회 · {progress}회 운동'**
  String challengeHistoryResult(int goal, int progress);

  /// No description provided for @challengeStatusSucceeded.
  ///
  /// In ko, this message translates to:
  /// **'성공'**
  String get challengeStatusSucceeded;

  /// No description provided for @challengeStatusFailed.
  ///
  /// In ko, this message translates to:
  /// **'실패'**
  String get challengeStatusFailed;

  /// No description provided for @challengeStatusActive.
  ///
  /// In ko, this message translates to:
  /// **'진행 중'**
  String get challengeStatusActive;

  /// No description provided for @challengeStatusSettling.
  ///
  /// In ko, this message translates to:
  /// **'집계 중'**
  String get challengeStatusSettling;

  /// No description provided for @myCouponStatusUsable.
  ///
  /// In ko, this message translates to:
  /// **'사용 가능'**
  String get myCouponStatusUsable;

  /// No description provided for @myCouponStatusUsed.
  ///
  /// In ko, this message translates to:
  /// **'사용 완료'**
  String get myCouponStatusUsed;

  /// No description provided for @myCouponStatusExpired.
  ///
  /// In ko, this message translates to:
  /// **'만료'**
  String get myCouponStatusExpired;

  /// No description provided for @myCouponStatusCancelled.
  ///
  /// In ko, this message translates to:
  /// **'취소됨'**
  String get myCouponStatusCancelled;

  /// No description provided for @myCouponDaysLeft.
  ///
  /// In ko, this message translates to:
  /// **'D-{days}'**
  String myCouponDaysLeft(int days);

  /// No description provided for @myCouponDDay.
  ///
  /// In ko, this message translates to:
  /// **'D-day'**
  String get myCouponDDay;

  /// No description provided for @myCouponUntil.
  ///
  /// In ko, this message translates to:
  /// **'{date}까지'**
  String myCouponUntil(String date);

  /// No description provided for @myCouponTrainer.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너'**
  String get myCouponTrainer;

  /// No description provided for @myCouponGym.
  ///
  /// In ko, this message translates to:
  /// **'헬스장'**
  String get myCouponGym;

  /// No description provided for @myCouponIssuedOn.
  ///
  /// In ko, this message translates to:
  /// **'교환일'**
  String get myCouponIssuedOn;

  /// No description provided for @myCouponExpiry.
  ///
  /// In ko, this message translates to:
  /// **'만료일'**
  String get myCouponExpiry;

  /// No description provided for @myCouponExpiryWithDday.
  ///
  /// In ko, this message translates to:
  /// **'{date} ({dday})'**
  String myCouponExpiryWithDday(String date, String dday);

  /// No description provided for @myCouponStatus.
  ///
  /// In ko, this message translates to:
  /// **'상태'**
  String get myCouponStatus;

  /// No description provided for @myCouponStaffNote.
  ///
  /// In ko, this message translates to:
  /// **'트레이너·헬스장 직원이 확인한 뒤 눌러 주세요'**
  String get myCouponStaffNote;

  /// No description provided for @myCouponGymStaffNote.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 직원이 확인한 뒤 눌러 주세요'**
  String get myCouponGymStaffNote;

  /// No description provided for @myCouponNoExpiry.
  ///
  /// In ko, this message translates to:
  /// **'기한 없음'**
  String get myCouponNoExpiry;

  /// No description provided for @myDietTrayTitle.
  ///
  /// In ko, this message translates to:
  /// **'분석용 식판 무료 제공'**
  String get myDietTrayTitle;

  /// No description provided for @myDietTrayFree.
  ///
  /// In ko, this message translates to:
  /// **'무료'**
  String get myDietTrayFree;

  /// No description provided for @myDietTrayDescription.
  ///
  /// In ko, this message translates to:
  /// **'최근 {window}일 중 {days}일 식단 사진을 남기면 분석에 맞춘 규격 식판을 드려요. 같은 식판에 담아 찍으면 양을 더 정확하게 분석해요.'**
  String myDietTrayDescription(int window, int days);

  /// No description provided for @myDietTrayProgressLabel.
  ///
  /// In ko, this message translates to:
  /// **'최근 {window}일 사진 기록'**
  String myDietTrayProgressLabel(int window);

  /// No description provided for @myDietTrayProgress.
  ///
  /// In ko, this message translates to:
  /// **'{days} / {required}일'**
  String myDietTrayProgress(int days, int required);

  /// No description provided for @myDietTrayDaysLeft.
  ///
  /// In ko, this message translates to:
  /// **'{days}일 더 찍으면 받을 수 있어요'**
  String myDietTrayDaysLeft(int days);

  /// No description provided for @myDietTrayNeedTrainer.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너를 연결하면 받을 수 있어요'**
  String get myDietTrayNeedTrainer;

  /// No description provided for @myDietTrayClaimable.
  ///
  /// In ko, this message translates to:
  /// **'조건을 채웠어요! 담당 트레이너의 헬스장에서 받아요'**
  String get myDietTrayClaimable;

  /// No description provided for @myDietTrayIssued.
  ///
  /// In ko, this message translates to:
  /// **'{gym}에서 받아요. 가기 전에 담당 트레이너에게 준비됐는지 메시지로 물어보세요'**
  String myDietTrayIssued(String gym);

  /// No description provided for @myDietTrayReceived.
  ///
  /// In ko, this message translates to:
  /// **'식판을 받았어요. 식판에 담아 찍어 보세요'**
  String get myDietTrayReceived;

  /// No description provided for @myDietTrayClaim.
  ///
  /// In ko, this message translates to:
  /// **'받기'**
  String get myDietTrayClaim;

  /// No description provided for @myDietTrayViewCoupon.
  ///
  /// In ko, this message translates to:
  /// **'쿠폰 보기'**
  String get myDietTrayViewCoupon;

  /// No description provided for @myDietTrayClaimConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'식판 수령 쿠폰을 받을까요?'**
  String get myDietTrayClaimConfirmTitle;

  /// No description provided for @myDietTrayClaimConfirmMessage.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너의 헬스장에서 받아요. 기한은 없고, 식판은 한 사람당 한 번 받을 수 있어요.'**
  String get myDietTrayClaimConfirmMessage;

  /// No description provided for @myDietTrayClaimDone.
  ///
  /// In ko, this message translates to:
  /// **'식판 수령 쿠폰을 받았어요'**
  String get myDietTrayClaimDone;

  /// No description provided for @myDietTrayClaimFailed.
  ///
  /// In ko, this message translates to:
  /// **'식판 수령 쿠폰을 받지 못했어요'**
  String get myDietTrayClaimFailed;

  /// No description provided for @myDietTrayNotice.
  ///
  /// In ko, this message translates to:
  /// **'1인 1회 · 사진으로 기록한 날만 세요(손으로 적은 끼니, 보호권으로 이은 날 제외) · 수령 기한 없음 · 헬스장에 가기 전에 담당 트레이너에게 식판이 준비됐는지 확인해 주세요 · 재고와 운영 사정에 따라 조건이 바뀔 수 있어요'**
  String get myDietTrayNotice;

  /// No description provided for @myDietTrayCouponBenefit.
  ///
  /// In ko, this message translates to:
  /// **'분석용 규격 식판'**
  String get myDietTrayCouponBenefit;

  /// No description provided for @myDietTrayStaffNote.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 직원에게 식판을 받은 뒤 눌러 주세요'**
  String get myDietTrayStaffNote;

  /// No description provided for @myDietTrayIssuedOn.
  ///
  /// In ko, this message translates to:
  /// **'받은 날'**
  String get myDietTrayIssuedOn;

  /// No description provided for @myDietTrayExpireNotice.
  ///
  /// In ko, this message translates to:
  /// **'기한 없이 쓸 수 있어요. 헬스장에 가기 전에 담당 트레이너에게 식판이 준비됐는지 메시지로 물어보세요.'**
  String get myDietTrayExpireNotice;

  /// No description provided for @myCouponStaffConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'쿠폰을 사용 처리할까요?'**
  String get myCouponStaffConfirmTitle;

  /// No description provided for @myCouponStaffConfirmMessage.
  ///
  /// In ko, this message translates to:
  /// **'직원 확인용 · 사용 후 되돌릴 수 없어요'**
  String get myCouponStaffConfirmMessage;

  /// No description provided for @myCouponUsedAt.
  ///
  /// In ko, this message translates to:
  /// **'사용 시각'**
  String get myCouponUsedAt;

  /// No description provided for @myCouponUsedBanner.
  ///
  /// In ko, this message translates to:
  /// **'{time}에 사용 완료했어요'**
  String myCouponUsedBanner(String time);

  /// No description provided for @myCouponExpireNotice.
  ///
  /// In ko, this message translates to:
  /// **'만료되면 포인트는 돌려받을 수 없어요.'**
  String get myCouponExpireNotice;

  /// No description provided for @myCouponUse.
  ///
  /// In ko, this message translates to:
  /// **'사용 처리'**
  String get myCouponUse;

  /// No description provided for @myCouponUseDone.
  ///
  /// In ko, this message translates to:
  /// **'사용 완료로 바꿨어요'**
  String get myCouponUseDone;

  /// No description provided for @myCouponUseFailed.
  ///
  /// In ko, this message translates to:
  /// **'사용 처리하지 못했어요. 다시 시도해 주세요.'**
  String get myCouponUseFailed;

  /// No description provided for @myCouponNotFound.
  ///
  /// In ko, this message translates to:
  /// **'쿠폰을 찾을 수 없어요'**
  String get myCouponNotFound;

  /// Screen reader label for an image a trainer sent in chat (#1942).
  ///
  /// In ko, this message translates to:
  /// **'트레이너가 보낸 사진'**
  String get a11yCoachPhoto;

  /// Screen reader label for a saved meal photo (#1942).
  ///
  /// In ko, this message translates to:
  /// **'끼니 사진'**
  String get a11yMealPhoto;

  /// Screen reader label for a recommended meal photo (#1942).
  ///
  /// In ko, this message translates to:
  /// **'{name} 사진'**
  String a11yMealPhotoOf(String name);

  /// No description provided for @myLogout.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃'**
  String get myLogout;

  /// No description provided for @myLogoutConfirm.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃할까요?'**
  String get myLogoutConfirm;

  /// No description provided for @emoteSheetTitle.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘'**
  String get emoteSheetTitle;

  /// No description provided for @emoteBuyTitle.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘 구매'**
  String get emoteBuyTitle;

  /// No description provided for @emoteBuyConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{cost}P로 {days}일 동안 쓸까요?\n구매한 때부터 기간이 흘러가요.'**
  String emoteBuyConfirm(int cost, int days);

  /// No description provided for @emoteBuyAction.
  ///
  /// In ko, this message translates to:
  /// **'구매'**
  String get emoteBuyAction;

  /// No description provided for @emoteBought.
  ///
  /// In ko, this message translates to:
  /// **'이제 이 이모티콘을 보낼 수 있어요'**
  String get emoteBought;

  /// No description provided for @emoteBuyFailed.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘을 구매하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get emoteBuyFailed;

  /// No description provided for @emoteAlreadyUnlocked.
  ///
  /// In ko, this message translates to:
  /// **'이미 열려 있는 이모티콘이에요. 바로 보낼 수 있어요'**
  String get emoteAlreadyUnlocked;

  /// No description provided for @emoteTrainerRequired.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너가 있어야 이모티콘을 구매할 수 있어요'**
  String get emoteTrainerRequired;

  /// No description provided for @emoteShortfall.
  ///
  /// In ko, this message translates to:
  /// **'포인트가 부족해요'**
  String get emoteShortfall;

  /// No description provided for @emoteLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘을 불러오지 못했어요'**
  String get emoteLoadFailed;

  /// No description provided for @emoteSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘을 보내지 못했어요'**
  String get emoteSendFailed;

  /// Toast when the server refuses an emote because the member's unlock ran out (402); the emote shows as locked again (#3346).
  ///
  /// In ko, this message translates to:
  /// **'이용 기간이 끝난 이모티콘이에요. 다시 사면 보낼 수 있어요'**
  String get emoteSendLocked;

  /// No description provided for @emoteSendRejected.
  ///
  /// In ko, this message translates to:
  /// **'보낼 수 없는 이모티콘이에요'**
  String get emoteSendRejected;

  /// No description provided for @a11yOpenEmotes.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘'**
  String get a11yOpenEmotes;

  /// No description provided for @a11yEmote.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘'**
  String get a11yEmote;

  /// Account deletion entry at the end of the MY settings list (#1935).
  ///
  /// In ko, this message translates to:
  /// **'계정 탈퇴'**
  String get myWithdrawTitle;

  /// No description provided for @myWithdrawConfirm.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴하면 계정과 함께 기록한 식단·운동·건강 지표가 모두 지워지고, 트레이너와의 연결과 주고받은 대화, 포인트와 사용 전 쿠폰·보호권·꾸밈 아이템도 사라져요. 예정된 PT 예약과 대기 중인 상담 요청은 취소돼요. 되돌릴 수 없어요.'**
  String get myWithdrawConfirm;

  /// Withdrawal confirmation line, shown only when the member has points left (#3006).
  ///
  /// In ko, this message translates to:
  /// **'• 보유 포인트 {points}P가 사라져요'**
  String myWithdrawLosePoints(int points);

  /// Withdrawal confirmation line, shown only when the member has usable coupons (#3006).
  ///
  /// In ko, this message translates to:
  /// **'• 사용 전 쿠폰 {count}장이 사라져요'**
  String myWithdrawLoseCoupons(int count);

  /// Withdrawal confirmation line, shown only when the member has upcoming bookings (#3006).
  ///
  /// In ko, this message translates to:
  /// **'• 예정된 PT 예약 {count}건이 취소돼요'**
  String myWithdrawCancelReservations(int count);

  /// Withdrawal confirmation line, shown only when a trainer has scheduled upcoming sessions with the member (#3341).
  ///
  /// In ko, this message translates to:
  /// **'• 트레이너가 잡은 PT 일정 {count}건이 취소돼요'**
  String myWithdrawCancelSessions(int count);

  /// Withdrawal confirmation line, shown only when the member has pending consultation requests (#3006).
  ///
  /// In ko, this message translates to:
  /// **'• 대기 중인 상담 요청 {count}건이 취소돼요'**
  String myWithdrawCancelConsultations(int count);

  /// No description provided for @myWithdrawAction.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴'**
  String get myWithdrawAction;

  /// No description provided for @myWithdrawFailed.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get myWithdrawFailed;

  /// First step of the two-step account deletion flow under customer support (#2019).
  ///
  /// In ko, this message translates to:
  /// **'정말 탈퇴할까요?'**
  String get myWithdrawReasonTitle;

  /// No description provided for @myWithdrawReasonQuestion.
  ///
  /// In ko, this message translates to:
  /// **'어떤 부분이 불편하셨나요?'**
  String get myWithdrawReasonQuestion;

  /// No description provided for @myWithdrawReasonHint.
  ///
  /// In ko, this message translates to:
  /// **'복수 선택 가능'**
  String get myWithdrawReasonHint;

  /// No description provided for @myWithdrawReasonPrivacy.
  ///
  /// In ko, this message translates to:
  /// **'개인정보 노출이 걱정돼요'**
  String get myWithdrawReasonPrivacy;

  /// No description provided for @myWithdrawReasonRarelyUsed.
  ///
  /// In ko, this message translates to:
  /// **'자주 사용하지 않아요'**
  String get myWithdrawReasonRarelyUsed;

  /// No description provided for @myWithdrawReasonHardToUse.
  ///
  /// In ko, this message translates to:
  /// **'쓰기가 불편해요'**
  String get myWithdrawReasonHardToUse;

  /// No description provided for @myWithdrawReasonNotifications.
  ///
  /// In ko, this message translates to:
  /// **'알림이 너무 많아요'**
  String get myWithdrawReasonNotifications;

  /// No description provided for @myWithdrawReasonAlternative.
  ///
  /// In ko, this message translates to:
  /// **'다른 앱을 쓰고 있어요'**
  String get myWithdrawReasonAlternative;

  /// No description provided for @myWithdrawReasonOther.
  ///
  /// In ko, this message translates to:
  /// **'그 밖의 이유'**
  String get myWithdrawReasonOther;

  /// No description provided for @myWithdrawNext.
  ///
  /// In ko, this message translates to:
  /// **'다음'**
  String get myWithdrawNext;

  /// Second step: what can be changed instead of leaving, chosen from the reasons picked (#2019).
  ///
  /// In ko, this message translates to:
  /// **'탈퇴하기 전에'**
  String get myWithdrawKeepTitle;

  /// No description provided for @myWithdrawKeepPrivacy.
  ///
  /// In ko, this message translates to:
  /// **'회원님의 기록은 절대 불특정 타인에게 공개하지 않아요. 볼 수 있는 사람은 회원님과 연결된 담당 트레이너뿐이고, 트레이너 연결을 해제하면 회원님만 볼 수 있어요 — MY 탭의 내 헬스장 · 트레이너에서 바로 해제할 수 있어요.'**
  String get myWithdrawKeepPrivacy;

  /// No description provided for @myWithdrawKeepRarelyUsed.
  ///
  /// In ko, this message translates to:
  /// **'매일 다 적지 않아도 괜찮아요. 가운데 + 를 누르면 어느 화면에서든 끼니 하나, 운동 하나를 바로 남길 수 있어요.'**
  String get myWithdrawKeepRarelyUsed;

  /// No description provided for @myWithdrawKeepHardToUse.
  ///
  /// In ko, this message translates to:
  /// **'어디가 불편했는지 알려 주시면 고칠게요. MY › 고객 지원의 1:1 문의로 바로 닿아요.'**
  String get myWithdrawKeepHardToUse;

  /// No description provided for @myWithdrawKeepNotifications.
  ///
  /// In ko, this message translates to:
  /// **'알림은 종류별로 끌 수 있어요. MY › 알림 설정에서 받고 싶은 것만 남겨 보세요.'**
  String get myWithdrawKeepNotifications;

  /// No description provided for @myWithdrawKeepAlternative.
  ///
  /// In ko, this message translates to:
  /// **'앱을 지워도 기록은 그대로 남아요. 탈퇴하면 그때 사라지고 되살릴 수 없어요.'**
  String get myWithdrawKeepAlternative;

  /// No description provided for @myWithdrawKeepOther.
  ///
  /// In ko, this message translates to:
  /// **'무엇이든 알려 주시면 반영할게요. MY › 고객 지원의 1:1 문의로 남겨 주세요.'**
  String get myWithdrawKeepOther;

  /// No description provided for @myWithdrawKeepDefault.
  ///
  /// In ko, this message translates to:
  /// **'지금까지 쌓은 식단·운동 기록과 포인트, 사용 전 쿠폰은 탈퇴와 함께 사라지고 되살릴 수 없어요. 예정된 예약도 취소돼요.'**
  String get myWithdrawKeepDefault;

  /// No description provided for @myWithdrawStay.
  ///
  /// In ko, this message translates to:
  /// **'계속 사용하기'**
  String get myWithdrawStay;

  /// No description provided for @myWithdrawContinue.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴 계속'**
  String get myWithdrawContinue;

  /// No description provided for @myCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get myCancel;

  /// No description provided for @myGymTrainerTitle.
  ///
  /// In ko, this message translates to:
  /// **'내 헬스장 · 트레이너'**
  String get myGymTrainerTitle;

  /// No description provided for @myConnectionDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'연결 해제'**
  String get myConnectionDeleteTitle;

  /// No description provided for @myConnectionDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'연결을 해제하지 못했어요. 다시 시도해 주세요.'**
  String get myConnectionDeleteFailed;

  /// No description provided for @myDelete.
  ///
  /// In ko, this message translates to:
  /// **'해제'**
  String get myDelete;

  /// No description provided for @myGymDisconnectWithTrainerConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{gym} 연결을 해제할까요?\n{trainer} 트레이너와의 연결도 함께 해제돼요.\n데이터 공유 동의도 함께 철회되어 트레이너가 회원님의 새 기록을 더는 볼 수 없어요. 이미 주고받은 대화와 리포트는 지워지지 않고, 같은 트레이너와 다시 연결하면 다시 볼 수 있어요.'**
  String myGymDisconnectWithTrainerConfirm(String gym, String trainer);

  /// No description provided for @myGymDisconnectConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{gym} 연결을 해제할까요?'**
  String myGymDisconnectConfirm(String gym);

  /// No description provided for @myTrainerDisconnectConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{trainer} 트레이너와의 연결을 해제할까요?\n{gym} 헬스장 연결은 유지돼요.\n데이터 공유 동의도 함께 철회되어 트레이너가 회원님의 새 기록을 더는 볼 수 없어요. 이미 주고받은 대화와 리포트는 지워지지 않고, 같은 트레이너와 다시 연결하면 다시 볼 수 있어요.'**
  String myTrainerDisconnectConfirm(String trainer, String gym);

  /// No description provided for @myGymDetailTooltip.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 상세 보기'**
  String get myGymDetailTooltip;

  /// No description provided for @myTrainerDetailTooltip.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 상세 보기'**
  String get myTrainerDetailTooltip;

  /// No description provided for @myGymDisconnectTooltip.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 연결 해제'**
  String get myGymDisconnectTooltip;

  /// No description provided for @myTrainerDisconnectTooltip.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 연결 해제'**
  String get myTrainerDisconnectTooltip;

  /// No description provided for @myNoTrainer.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너 없음'**
  String get myNoTrainer;

  /// No description provided for @myNoGymConnected.
  ///
  /// In ko, this message translates to:
  /// **'아직 연결한 헬스장이 없어요'**
  String get myNoGymConnected;

  /// No description provided for @myGymLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 연결 정보를 불러오지 못했어요.'**
  String get myGymLoadFailed;

  /// No description provided for @mySave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get mySave;

  /// No description provided for @myProfileSaved.
  ///
  /// In ko, this message translates to:
  /// **'프로필을 저장했어요'**
  String get myProfileSaved;

  /// No description provided for @mySaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get mySaveFailed;

  /// No description provided for @myProfileEmailTaken.
  ///
  /// In ko, this message translates to:
  /// **'이미 사용 중인 이메일이에요'**
  String get myProfileEmailTaken;

  /// No description provided for @myProfileEmailEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'사용할 이메일 주소'**
  String get myProfileEmailEmptyHint;

  /// No description provided for @myProfilePhoneRequired.
  ///
  /// In ko, this message translates to:
  /// **'등록된 전화번호는 비울 수 없어요'**
  String get myProfilePhoneRequired;

  /// No description provided for @myProfileInvalid.
  ///
  /// In ko, this message translates to:
  /// **'입력한 내용을 다시 확인해 주세요'**
  String get myProfileInvalid;

  /// No description provided for @myFieldName.
  ///
  /// In ko, this message translates to:
  /// **'이름'**
  String get myFieldName;

  /// No description provided for @myFieldEmail.
  ///
  /// In ko, this message translates to:
  /// **'이메일'**
  String get myFieldEmail;

  /// No description provided for @myFieldPhone.
  ///
  /// In ko, this message translates to:
  /// **'전화번호'**
  String get myFieldPhone;

  /// No description provided for @myFieldBirth.
  ///
  /// In ko, this message translates to:
  /// **'생년월일'**
  String get myFieldBirth;

  /// No description provided for @myFieldGender.
  ///
  /// In ko, this message translates to:
  /// **'성별'**
  String get myFieldGender;

  /// No description provided for @myFieldHeight.
  ///
  /// In ko, this message translates to:
  /// **'키 (cm)'**
  String get myFieldHeight;

  /// No description provided for @myFieldWeight.
  ///
  /// In ko, this message translates to:
  /// **'체중 (kg)'**
  String get myFieldWeight;

  /// No description provided for @myNotifExercise.
  ///
  /// In ko, this message translates to:
  /// **'개인운동·프로그램'**
  String get myNotifExercise;

  /// No description provided for @myNotifTrainer.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 메시지'**
  String get myNotifTrainer;

  /// No description provided for @myNotifWeeklyReport.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 주간 리포트'**
  String get myNotifWeeklyReport;

  /// No description provided for @myNotifExerciseDesc.
  ///
  /// In ko, this message translates to:
  /// **'트레이너가 개인운동·PT 프로그램을 보내거나 PT 기록·피드백을 남기면 알려요'**
  String get myNotifExerciseDesc;

  /// No description provided for @myNotifTrainerDesc.
  ///
  /// In ko, this message translates to:
  /// **'트레이너가 보낸 메시지를 알려요'**
  String get myNotifTrainerDesc;

  /// No description provided for @myNotifWeeklyReportDesc.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너가 주간 리포트를 보내면 알려요'**
  String get myNotifWeeklyReportDesc;

  /// No description provided for @myNotifAlwaysSent.
  ///
  /// In ko, this message translates to:
  /// **'PT 일정 등록·변경·취소, 담당 트레이너 요청·연결·해제, 상담 요청 결과, 건강 목표 변경, 쿠폰 만료·취소, 주간 챌린지 결과 알림은 항상 보내요'**
  String get myNotifAlwaysSent;

  /// No description provided for @mySupportFaq.
  ///
  /// In ko, this message translates to:
  /// **'자주 묻는 질문'**
  String get mySupportFaq;

  /// No description provided for @mySupportInquiry.
  ///
  /// In ko, this message translates to:
  /// **'1:1 문의'**
  String get mySupportInquiry;

  /// No description provided for @myLegalTermsTitle.
  ///
  /// In ko, this message translates to:
  /// **'이용약관'**
  String get myLegalTermsTitle;

  /// No description provided for @myLegalPrivacyTitle.
  ///
  /// In ko, this message translates to:
  /// **'개인정보 처리방침'**
  String get myLegalPrivacyTitle;

  /// MY support row that opens the open-source license list (packages and the bundled Pretendard font, #3150).
  ///
  /// In ko, this message translates to:
  /// **'오픈소스 라이선스'**
  String get myOpenSourceLicensesTitle;

  /// No description provided for @myLegalTermsBody.
  ///
  /// In ko, this message translates to:
  /// **'제1조 (목적)\n이 약관은 On-Care(이하 \"회사\")가 제공하는 건강 관리 서비스(이하 \"서비스\")의 이용과 관련하여 회사와 회원 간의 권리, 의무 및 책임사항을 규정함을 목적으로 합니다.\n\n제2조 (약관의 효력 및 변경)\n① 이 약관은 서비스를 이용하는 모든 회원에게 효력이 발생합니다.\n② 회사는 관련 법령을 위반하지 않는 범위에서 이 약관을 변경할 수 있으며, 변경 시 적용일자와 변경 사유를 명시하여 적용일 전에 서비스 내에 공지합니다.\n③ 동의가 필요한 변경은 다시 동의를 받습니다. 회원은 변경된 약관에 동의하지 않으면 이용 계약을 해지할 수 있습니다.\n\n제3조 (회원 가입과 계정)\n① 회원 가입은 만 14세 이상만 할 수 있습니다.\n② 회원은 한 사람이 하나의 계정을 쓰며, 다른 사람의 정보로 가입하거나 계정을 다른 사람에게 넘기거나 빌려줄 수 없습니다.\n③ 비밀번호와 소셜 로그인 연결 등 계정 정보의 관리 책임은 회원에게 있습니다. 다른 사람이 계정을 쓰고 있다는 것을 알게 되면 바로 비밀번호를 바꾸고 회사에 알려야 합니다.\n\n제4조 (서비스의 제공)\n회사는 식단 기록, 운동 기록, 건강 지표 관리, AI 코칭, 담당 트레이너와의 연결·메시지·예약 등 회원의 건강 관리를 돕는 기능을 제공합니다. 서비스의 구체적인 내용은 회사의 정책에 따라 변경될 수 있습니다.\n\n제5조 (포인트)\n① 회원은 식단·운동 기록 등 앱에 안내된 활동으로 포인트를 받습니다. 활동마다 받는 포인트와 하루 한도는 앱의 안내를 따릅니다.\n② 포인트는 서비스 안에서 쿠폰·교환 상품으로 바꾸는 데에만 쓸 수 있습니다. 포인트는 현금 가치가 없어 현금으로 바꾸거나 환불받을 수 없고, 다른 사람에게 넘길 수 없습니다.\n③ 포인트를 받은 기록을 지우면 받은 포인트를 회수합니다. 같은 기록을 되풀이해 올리는 등 정상적이지 않은 방법으로 받은 포인트도 회수할 수 있습니다.\n④ 회사는 적립 기준과 교환 가격을 바꿀 수 있으며, 바꾸기 전에 서비스 안에 알립니다. 이미 교환한 쿠폰과 상품에는 바뀐 기준을 적용하지 않습니다.\n⑤ 탈퇴하면 남은 포인트와 그 내역은 함께 사라지고 되살릴 수 없습니다.\n\n제6조 (쿠폰과 교환 상품)\n① 회원은 포인트로 PT 재등록 할인 쿠폰, 개인 락커 이용 쿠폰 등 앱에 안내된 쿠폰을 교환할 수 있습니다. 쿠폰의 혜택은 회원과 연결된 담당 트레이너 또는 헬스장이 현장에서 제공합니다.\n② 쿠폰은 앱에 표시된 유효기간 안에만 쓸 수 있으며, 포인트로 교환한 쿠폰의 유효기간은 교환한 날부터 30일입니다. 유효기간이 지난 쿠폰은 소멸하고, 교환에 쓴 포인트는 돌려주지 않습니다.\n③ 쿠폰을 쓸 곳인 담당 트레이너 또는 헬스장과의 연결이 끊기면 사용 전 쿠폰은 취소되고, 교환에 쓴 포인트를 돌려줍니다.\n④ 쿠폰은 현장 직원이 확인한 뒤 회원이 자기 휴대폰에서 사용 완료를 눌러 사용합니다. 사용 처리한 쿠폰은 되돌릴 수 없습니다.\n⑤ 쿠폰은 다른 사람에게 넘기거나 현금으로 바꿀 수 없습니다.\n\n제7조 (기간제 아이템과 보호권)\n① 프로필 펫·이모티콘 등 꾸밈 아이템은 앱에 표시된 기간 동안만 쓸 수 있으며, 기간이 끝나면 사라집니다.\n② 연속 기록 보호권은 기록하지 못한 날에도 연속 기록이 끊기지 않게 지켜 주는 데 쓰이며, 쓰는 방법과 보유 한도는 앱의 안내를 따릅니다.\n③ 이 조의 아이템과 보호권도 현금 가치가 없고 다른 사람에게 넘길 수 없으며, 탈퇴하면 함께 사라집니다.\n\n제8조 (예약과 상담 신청)\n① 회원은 담당 트레이너가 열어 둔 시간에 PT를 예약하거나, 트레이너에게 상담을 신청할 수 있습니다. 신청과 취소를 할 수 있는 때와 대기 중인 상담 요청이 만료되는 때는 앱의 안내를 따릅니다.\n② PT 이용 계약과 그 결제·환불은 회원과 트레이너 또는 헬스장 사이의 별도 계약입니다. 회사는 이를 위한 연결·예약 도구를 제공합니다.\n\n제9조 (회원의 의무)\n회원은 본인의 건강 정보를 정확하게 입력하여야 하며, 서비스가 제공하는 정보는 의학적 진단이나 치료를 대체하지 않습니다. 건강상 문제가 있는 경우 반드시 전문 의료기관의 진료를 받으시기 바랍니다.\n\n제10조 (이용 제한)\n회사는 회원이 다음 행위를 하면 미리 알린 뒤 서비스 이용의 일부 또는 전부를 제한하거나 계정을 정지할 수 있습니다. 다른 이용자의 피해를 막아야 하는 등 급한 경우에는 먼저 제한한 뒤 바로 알립니다.\n- 다른 사람의 정보를 도용하거나 계정을 넘기는 행위\n- 정상적이지 않은 방법으로 포인트를 받거나 쿠폰을 쓰는 행위\n- 트레이너나 다른 이용자에게 욕설·괴롭힘 등으로 피해를 주는 행위\n- 서비스의 운영을 방해하는 행위\n\n제11조 (이용 계약의 해지와 그 효과)\n① 회원은 언제든지 MY 탭의 회원 탈퇴로 이용 계약을 해지할 수 있습니다.\n② 탈퇴하면 계정과 함께 프로필, 식단·운동·건강 기록, AI 코치 대화, 담당 트레이너와의 연결과 대화가 지워지고, 남은 포인트와 그 내역, 사용 전 쿠폰, 보호권과 꾸밈 아이템도 함께 사라집니다. 사라진 것은 되살릴 수 없습니다.\n③ 예정된 PT 예약과 대기 중인 상담 요청은 취소되고, 관련 트레이너에게 탈퇴 사실이 안내됩니다.\n④ 트레이너의 일정표에 이미 잡혀 있던 수업 기록처럼 개인정보 처리방침의 파기 절차에서 남는다고 정한 기록은 그 범위에서 남습니다.\n\n제12조 (서비스의 변경과 중단)\n① 회사는 서비스의 내용을 바꾸거나 일부 기능을 끝낼 수 있으며, 회원에게 영향이 있는 변경은 미리 서비스 안에 알립니다.\n② 회사는 설비 점검·교체, 장애, 천재지변 등 부득이한 사유가 있으면 서비스를 일시 중단할 수 있으며, 미리 알릴 수 없었던 경우에는 사후에 알립니다.\n③ 서비스 전체를 끝내는 경우 회사는 미리 알리고, 남은 포인트와 사용 전 쿠폰을 어떻게 처리하는지 함께 안내합니다.\n\n제13조 (책임의 제한)\n회사는 회원이 서비스를 통해 얻은 정보에 기반하여 내린 판단과 그 결과에 대하여 법령이 허용하는 범위 내에서 책임을 부담하지 않습니다.\n\n제14조 (분쟁 해결과 관할)\n① 회사와 회원은 서비스와 관련한 분쟁을 원만하게 해결하기 위해 성실히 협의합니다. 회원은 개인정보 처리방침에 적힌 연락처로 문의나 불만을 보낼 수 있습니다.\n② 협의로 해결되지 않아 소송이 제기되는 경우 민사소송법에 따른 관할 법원을 관할 법원으로 합니다.\n③ 이 약관과 서비스 이용에는 대한민국 법을 적용합니다.\n\n부칙\n이 약관은 2026년 10월 3일부터 시행합니다.\n- 2026년 10월 3일: 회원 가입과 계정, 포인트, 쿠폰과 교환 상품, 기간제 아이템과 보호권, 예약과 상담 신청, 이용 제한, 이용 계약의 해지와 그 효과, 서비스의 변경과 중단, 분쟁 해결과 관할 조항 추가\n- 2026년 10월 1일: 제정'**
  String get myLegalTermsBody;

  /// Privacy policy body. {contact} is the privacy officer contact, filled from LegalContact.privacyOfficerEmail in shared/oncare_core (the single definition point, #3005).
  ///
  /// In ko, this message translates to:
  /// **'On-Care(이하 \"회사\")는 「개인정보 보호법」 등 관련 법령을 준수하며, 회원의 개인정보를 소중히 보호합니다.\n\n1. 수집하는 개인정보 항목\n① 회원가입: 이메일, 비밀번호(암호화하여 저장), 이름. 소셜 로그인(카카오·구글)으로 가입하면 해당 서비스가 넘겨주는 회원 식별자와 이메일·이름을 받습니다.\n② 프로필과 첫 설정: 전화번호, 생년월일, 성별, 키, 체중, 건강 목표와 식단·운동 목표.\n③ 서비스 이용 중 회원이 남기는 정보: 식단 기록과 음식 사진, 운동 기록, 체중 등 건강 지표, AI 코치와의 대화, 트레이너와 주고받은 메시지와 첨부 사진, 상담·예약 신청 내용.\n④ 자동으로 생성되는 정보: 로그인·비밀번호 변경 등 접속 기록(일시, IP 주소)과, 오류가 났을 때의 오류 내용·기기 종류·운영체제·앱 버전.\n⑤ 위치 정보: 헬스장 찾기에서 위치정보 이용에 동의하고 현재 위치 사용을 허용한 경우에만 기기의 현재 좌표를 받아 주변 헬스장 검색에 씁니다. 좌표는 주변 검색을 위해 주식회사 카카오의 장소 검색에 전달되고, 요청을 처리한 뒤 바로 파기하며 계정에 저장하지 않습니다. 위치정보 이용 동의는 MY 탭에서 언제든지 철회할 수 있고, 동의하지 않아도 기본 검색 영역으로 헬스장 찾기를 쓸 수 있습니다. 자세한 내용은 위치기반서비스 이용약관을 따릅니다.\n\n2. 개인정보의 수집 및 이용 목적\n수집한 개인정보는 회원 식별, 음식 사진 분석과 영양 계산 등 건강 관리 기능 제공, 맞춤형 AI 코칭, 담당 트레이너 연결, 서비스 개선 및 고객 문의 응대의 목적으로만 이용됩니다.\n\n3. 개인정보의 보유 및 이용 기간\n회원의 개인정보는 회원 탈퇴 시까지 보유·이용하며, 탈퇴하면 10항의 절차에 따라 지체 없이 파기합니다. 다만 다음 기록은 정해진 기간 동안 보관한 뒤 파기합니다.\n- 로그인 등 접속 기록: 1년(「통신비밀보호법」상 로그인 기록 보존 의무 3개월 포함)\n- 트레이너의 회원 건강정보 열람 기록, 데이터 공유 동의·철회 기록, 탈퇴 기록: 2년(「개인정보의 안전성 확보조치 기준」에 따른 처리 기록 보관)\n탈퇴할 때 고른 탈퇴 사유는 회원과 연결되지 않는 사유 항목과 시각만 남깁니다.\n\n4. 개인정보의 제3자 제공\n회사는 회원의 동의 없이 개인정보를 외부에 제공하지 않습니다. 담당 트레이너와의 공유는 5항, 업무 처리를 맡기는 위탁은 6항과 7항을 따릅니다. 다만 법령에 특별한 규정이 있는 경우는 예외로 합니다.\n\n5. 담당 트레이너와의 정보 공유 및 동의 철회\n회원이 상담 신청, 담당 요청 수락, 연결 코드 발급 중 하나로 데이터 공유에 동의하면 담당 트레이너는 회원의 식단 기록·운동 기록·신체 정보, 건강 목표와 건강상태·주의사항을 볼 수 있습니다. 회원은 MY 탭에서 담당 트레이너 또는 헬스장 연결을 해제하여 언제든지 동의를 철회할 수 있으며, 트레이너가 담당을 해제한 경우에도 동의는 철회된 것으로 봅니다. 회사는 동의한 시각과 철회한 시각을 기록합니다. 철회한 뒤에는 트레이너가 회원의 새 기록을 볼 수 없고, 같은 트레이너와 다시 연결하려면 새로 동의해야 합니다. 다만 철회 전에 트레이너와 주고받은 대화와 전달된 리포트는 삭제되지 않고 남습니다.\n\n6. 개인정보 처리의 위탁\n회사는 서비스 제공을 위해 다음 업무를 외부 업체에 위탁합니다. 수탁자가 바뀌면 이 처리방침을 고쳐 알립니다.\n- Amazon Web Services, Inc.: 서버 운영, 채팅 사진·리포트 PDF 파일 보관\n- Neon: 데이터베이스 운영(계정 정보와 모든 기록 보관)\n- Google LLC: 음식 사진 인식, AI 코치 답변·추천 생성, AI 코치가 회원 기록을 찾아 쓰기 위한 검색 색인 생성(Gemini API)\n- Google LLC: 가입 인증 코드, 비밀번호 재설정, 로그인 이메일 변경 인증·안내 메일 발송(Gmail)\n- 주식회사 카카오: 헬스장·장소 검색과 지도 표시\n- Functional Software, Inc.(Sentry): 앱·서버 오류 수집과 분석\n\n7. 개인정보의 국외 이전\n회사는 회원과의 계약을 이행하기 위해 다음과 같이 개인정보를 국외에서 처리·보관하도록 위탁하며, 「개인정보 보호법」 제28조의8 제1항 제3호에 따라 이 처리방침으로 알립니다. 이전은 서비스를 이용할 때마다 암호화된 네트워크로 전송하는 방법으로 이루어집니다.\n① Amazon Web Services, Inc. / 싱가포르 / 회원 정보와 기록 전반, 채팅 첨부 사진과 리포트 PDF / 서버 운영과 파일 보관 / 회원 탈퇴 또는 위탁 계약 종료 시까지\n② Neon / 싱가포르 / 계정·프로필·식단·운동·건강 기록과 대화 기록 / 데이터베이스 운영 / 회원 탈퇴 또는 위탁 계약 종료 시까지\n③ Google LLC / 미국 등 Google이 운영하는 데이터센터 소재 국가 / 음식 사진, 분석에 필요한 식단·운동 기록·신체 정보·건강 목표, AI 코치와의 대화 내용 / AI 분석·답변 생성과 검색 색인 생성 / 요청 처리 후 수탁자의 서비스 약관에서 정한 기간\n④ Functional Software, Inc.(Sentry) / 미국 / 오류 내용, 기기 종류·운영체제·앱 버전(이름·이메일·IP 주소·요청 내용은 보내지 않음) / 오류 분석 / 수탁자의 보관 기간\n⑤ Google LLC(Gmail) / 미국 등 Google이 운영하는 데이터센터 소재 국가 / 받는 사람의 이메일 주소와 메일 내용(인증 코드, 비밀번호 재설정 코드와 재설정 링크, 이메일 변경 안내에 적는 일부를 가린 새 이메일 주소) / 가입 인증·비밀번호 재설정·이메일 변경 안내 메일 발송 / 발송일로부터 30일(발신 계정 보낸편지함의 사본을 30일이 지나면 삭제)\n식단·운동 기록을 저장할 때마다 AI 코치용 검색 색인을 만들기 위해 그 내용이 ③으로 전송됩니다. 가입 인증 코드나 비밀번호 재설정을 요청하거나 로그인 이메일을 바꿀 때에는 그 메일을 보내기 위해 ⑤로 전송됩니다. 국외 이전을 원하지 않으면 탈퇴로 거부할 수 있으나, 이 경우 서비스를 이용할 수 없습니다.\n\n8. 민감정보(건강정보)의 처리\n식단·운동 기록, 신체 정보, 건강 목표, 건강상태·주의사항 등 건강에 관한 정보는 「개인정보 보호법」 제23조에 따라 가입할 때 다른 개인정보와 구분하여 별도로 동의를 받아 처리합니다. 담당 트레이너와의 공유는 5항의 동의가 있을 때만 이루어집니다.\n\n9. 만 14세 미만 아동의 개인정보\n회사는 만 14세 미만 아동의 회원가입을 받지 않으며, 가입할 때 만 14세 이상인지 확인합니다.\n\n10. 개인정보의 파기 절차 및 방법\n① 절차: 회원이 MY 탭에서 탈퇴하면 즉시 계정과 함께 프로필, 식단·운동 기록과 음식 사진, AI 코치 대화와 검색 색인, 알림, 소셜 로그인 연결, 담당 트레이너와의 연결과 대화(첨부 사진·리포트 PDF 파일 포함)를 삭제합니다. 대기 중인 상담 요청과 예약은 취소되고, 관련 트레이너에게 탈퇴 사실이 안내됩니다. 트레이너의 일정표에 이미 잡혀 있던 수업 기록에는 회원 표시 이름과 일시가 트레이너의 업무 기록으로 남습니다. 3항에 따라 보관하는 기록은 기간이 지나면 자동으로 삭제합니다.\n② 방법: 전자적 파일 형태의 정보는 데이터베이스와 파일 저장소에서 삭제하며, 데이터베이스 복구용 백업에 남은 사본은 백업 보관 기간이 지나면 함께 사라집니다. 회사는 개인정보를 종이 문서로 처리하지 않습니다.\n\n11. 개인정보 자동 수집 장치의 설치·운영 및 거부\n회사는 광고·행태 분석을 위한 쿠키나 추적 도구를 쓰지 않습니다. 웹에서는 로그인 상태를 유지하기 위해 브라우저 저장소에 인증 정보를 보관하며, 로그아웃하거나 브라우저 데이터를 지우면 삭제됩니다.\n\n12. 개인정보의 안전성 확보 조치\n회사는 비밀번호를 암호화하여 저장하고, 전송 구간을 암호화하며, 회원 정보에 대한 트레이너의 접근을 담당 관계를 기준으로 제한합니다. 트레이너가 회원의 건강정보를 열람하면 열람한 트레이너, 대상 회원, 정보의 종류와 시각만 기록하며 건강정보의 내용은 담지 않습니다. 오류 보고에서는 이름·이메일·IP 주소와 요청 내용을 지우고 보냅니다.\n\n13. 이용자의 권리와 행사 방법\n회원은 언제든지 자신의 개인정보를 조회·수정하거나 처리 정지 및 삭제를 요청할 수 있습니다. 프로필은 MY 탭에서 직접 고칠 수 있고, 탈퇴와 트레이너 공유 동의 철회도 MY 탭에서 할 수 있습니다. 그 밖의 요청은 14항의 연락처로 보내 주시면 지체 없이 조치합니다.\n\n14. 개인정보 보호책임자\n회사는 개인정보 처리에 관한 업무를 총괄하고 관련 불만 처리와 피해 구제를 위해 개인정보 보호책임자를 지정하고 있습니다.\n- 직책: On-Care 서비스 운영팀 개인정보 보호책임자\n- 연락처: {contact}\n\n15. 권익침해 구제 방법\n개인정보 침해에 대한 신고나 상담이 필요하면 다음 기관에 문의할 수 있습니다.\n- 개인정보분쟁조정위원회: 국번없이 1833-6972 (www.kopico.go.kr)\n- 개인정보침해신고센터: 국번없이 118 (privacy.kisa.or.kr)\n- 대검찰청: 국번없이 1301 (www.spo.go.kr)\n- 경찰청: 국번없이 182 (ecrm.police.go.kr)\n\n16. 처리방침의 변경\n이 처리방침을 바꾸면 시행일 전에 앱 안에 알리며, 동의가 필요한 변경은 다시 동의를 받습니다.\n- 2026년 10월 14일: 메일 발송 업체(Google LLC, Gmail)의 처리 위탁과 국외 이전 추가(6항·7항)\n- 2026년 10월 5일: 개인정보 보호책임자 연락처 변경, 위치정보 이용 동의 절차와 위치기반서비스 이용약관 안내 추가(1항 ⑤), 소셜 로그인 수단에서 네이버·애플 제외, 동의 철회 방법을 앱 화면과 같은 말(연결 해제)로 정리(5항)\n- 2026년 10월 3일: 처리 위탁·국외 이전·민감정보·만 14세 미만·파기 절차·자동 수집 장치·안전성 확보 조치·보호책임자·권익침해 구제 항목 추가\n- 2026년 10월 1일: 제정\n\n시행일: 2026년 10월 14일'**
  String myLegalPrivacyBody(String contact);

  /// No description provided for @myLegalTermsEffectiveDate.
  ///
  /// In ko, this message translates to:
  /// **'시행일 2026. 10. 03.'**
  String get myLegalTermsEffectiveDate;

  /// No description provided for @myLegalPrivacyEffectiveDate.
  ///
  /// In ko, this message translates to:
  /// **'시행일 2026. 10. 14.'**
  String get myLegalPrivacyEffectiveDate;

  /// No description provided for @myLegalLocationTitle.
  ///
  /// In ko, this message translates to:
  /// **'위치기반서비스 이용약관'**
  String get myLegalLocationTitle;

  /// Location-Based Services Terms body (#3136). {contact} is the location information manager contact, filled from LegalContact.privacyOfficerEmail in shared/oncare_core.
  ///
  /// In ko, this message translates to:
  /// **'제1조 (목적)\n이 약관은 On-Care(이하 \"회사\")가 회원 앱에서 제공하는 위치기반서비스를 이용할 때 회사와 회원의 권리·의무와 책임, 그 밖에 필요한 사항을 정합니다.\n\n제2조 (약관의 효력과 변경)\n① 이 약관은 회원이 헬스장 찾기에서 위치정보 이용에 동의한 때부터 효력이 생깁니다.\n② 회사는 관련 법령을 위반하지 않는 범위에서 이 약관을 바꿀 수 있으며, 바꾸면 시행일과 바뀐 내용을 시행일 전에 앱 안에 알리고 다음 이용 때 다시 동의를 받습니다.\n③ 이 약관에 정하지 않은 사항은 「위치정보의 보호 및 이용 등에 관한 법률」 등 관련 법령과 On-Care 이용약관, 개인정보 처리방침을 따릅니다.\n\n제3조 (서비스의 내용)\n회사는 회원 기기의 현재 위치를 이용해 다음 서비스를 무료로 제공합니다.\n- 헬스장 찾기: 현재 위치 주변의 헬스장을 찾아 거리와 함께 목록과 지도에 보여 줍니다.\n\n제4조 (이용하는 위치정보와 수집 방법)\n① 회사가 이용하는 위치정보는 회원이 헬스장 찾기를 쓸 때 기기가 알려 주는 현재 좌표(위도·경도)입니다.\n② 회사는 회원이 이 약관에 동의하고 기기의 위치 권한을 허용한 경우에만, 헬스장 찾기 화면이 열려 있는 동안 위치정보를 받습니다. 앱을 쓰지 않을 때(백그라운드)에는 위치정보를 받지 않습니다.\n\n제5조 (위치정보의 이용·보유 기간과 파기)\n① 회사는 받은 좌표를 주변 헬스장 검색 요청을 처리하는 데에만 쓰고, 요청을 처리한 뒤 바로 파기합니다. 좌표와 위치 이력은 계정이나 서버에 저장하지 않습니다.\n② 앱은 회원이 앱을 쓰는 동안에만 마지막 좌표를 기기 메모리에 두며, 앱을 닫으면 사라집니다.\n③ 회사는 위치정보 이용 동의와 철회 사실(약관 버전과 시각)을 기록하며, 이 기록은 회원 탈퇴 시 함께 삭제합니다.\n\n제6조 (위치정보의 제공)\n① 회사는 회원의 동의 없이 위치정보를 제3자에게 제공하지 않습니다. 다만 법령에 특별한 규정이 있는 경우는 예외로 합니다.\n② 회사는 주변 헬스장을 찾기 위해 좌표를 주식회사 카카오의 장소 검색 서비스(카카오 로컬)에 전달합니다. 전달한 좌표는 검색 결과를 받는 데에만 쓰입니다.\n\n제7조 (이용자의 권리)\n① 회원은 언제든지 위치정보 이용 동의를 철회할 수 있습니다. MY 탭의 고객 지원에서 \"위치정보 이용 동의\"를 끄면 철회되며, 그 뒤로 회사는 위치정보를 받지 않습니다. 기기 설정에서 위치 권한을 거둘 수도 있습니다.\n② 회원은 언제든지 위치정보 이용의 일시적인 중지를 요구할 수 있습니다. 헬스장 찾기에서 현재 위치를 쓰지 않으면 회사는 위치정보를 받지 않습니다.\n③ 회원은 자신의 위치정보 이용과 관련한 자료의 열람이나 고지를 요구할 수 있고, 회사는 정당한 사유 없이 거절하지 않습니다. 회사는 좌표를 저장하지 않으므로 열람할 수 있는 자료는 동의·철회 기록입니다.\n\n제8조 (동의하지 않을 때)\n위치정보 이용에 동의하지 않아도 헬스장 찾기를 기본 검색 영역과 헬스장 이름 검색으로 쓸 수 있습니다. 다만 현재 위치 기준의 거리와 거리순 정렬은 쓸 수 없습니다.\n\n제9조 (만 14세 미만 아동)\n회사는 만 14세 미만 아동의 가입을 받지 않으므로 만 14세 미만 아동의 위치정보를 이용하지 않습니다.\n\n제10조 (위치정보관리책임자)\n회사는 위치정보를 보호하고 관련 불만을 처리하기 위해 위치정보관리책임자를 지정하고 있습니다.\n- 직책: On-Care 서비스 운영팀 위치정보관리책임자(개인정보 보호책임자 겸임)\n- 연락처: {contact}\n\n제11조 (손해배상과 분쟁 해결)\n① 회사가 위치정보 관련 법령을 위반하여 회원에게 손해가 생기면 회원은 회사에 손해배상을 청구할 수 있으며, 회사는 고의나 과실이 없음을 증명하지 못하면 책임을 집니다.\n② 위치정보와 관련한 분쟁은 당사자가 협의로 해결하며, 협의가 이루어지지 않으면 「위치정보의 보호 및 이용 등에 관한 법률」에 따라 방송통신위원회에 재정을 신청하거나 개인정보분쟁조정위원회(국번없이 1833-6972)에 조정을 신청할 수 있습니다.\n\n부칙\n이 약관은 2026년 10월 5일부터 시행합니다.'**
  String myLegalLocationBody(String contact);

  /// No description provided for @myLegalLocationEffectiveDate.
  ///
  /// In ko, this message translates to:
  /// **'시행일 2026. 10. 05.'**
  String get myLegalLocationEffectiveDate;

  /// No description provided for @locationConsentTitle.
  ///
  /// In ko, this message translates to:
  /// **'위치정보 이용 동의'**
  String get locationConsentTitle;

  /// No description provided for @locationConsentLead.
  ///
  /// In ko, this message translates to:
  /// **'주변 헬스장을 찾으려면 기기의 현재 위치가 필요해요. 아래 내용에 동의하면 위치 권한을 요청할게요.'**
  String get locationConsentLead;

  /// No description provided for @locationConsentPurposeLabel.
  ///
  /// In ko, this message translates to:
  /// **'이용 목적'**
  String get locationConsentPurposeLabel;

  /// No description provided for @locationConsentPurpose.
  ///
  /// In ko, this message translates to:
  /// **'현재 위치 주변의 헬스장 검색'**
  String get locationConsentPurpose;

  /// No description provided for @locationConsentItemsLabel.
  ///
  /// In ko, this message translates to:
  /// **'이용 항목'**
  String get locationConsentItemsLabel;

  /// No description provided for @locationConsentItems.
  ///
  /// In ko, this message translates to:
  /// **'기기의 현재 좌표(위도·경도)'**
  String get locationConsentItems;

  /// No description provided for @locationConsentRetentionLabel.
  ///
  /// In ko, this message translates to:
  /// **'보관'**
  String get locationConsentRetentionLabel;

  /// No description provided for @locationConsentRetention.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 않아요. 검색 요청을 처리한 뒤 바로 파기해요.'**
  String get locationConsentRetention;

  /// No description provided for @locationConsentRecipientLabel.
  ///
  /// In ko, this message translates to:
  /// **'제공'**
  String get locationConsentRecipientLabel;

  /// No description provided for @locationConsentRecipient.
  ///
  /// In ko, this message translates to:
  /// **'주변 검색을 위해 카카오 로컬 검색에 전달해요.'**
  String get locationConsentRecipient;

  /// No description provided for @locationConsentRefuseLabel.
  ///
  /// In ko, this message translates to:
  /// **'동의하지 않으면'**
  String get locationConsentRefuseLabel;

  /// No description provided for @locationConsentRefuse.
  ///
  /// In ko, this message translates to:
  /// **'신촌 주변 결과와 헬스장 이름 검색으로 계속 찾을 수 있어요. 동의는 MY > 고객 지원에서 언제든 바꿀 수 있어요.'**
  String get locationConsentRefuse;

  /// No description provided for @locationConsentViewTerms.
  ///
  /// In ko, this message translates to:
  /// **'위치기반서비스 이용약관 보기'**
  String get locationConsentViewTerms;

  /// No description provided for @locationConsentAgree.
  ///
  /// In ko, this message translates to:
  /// **'동의하고 위치 사용'**
  String get locationConsentAgree;

  /// No description provided for @locationConsentDecline.
  ///
  /// In ko, this message translates to:
  /// **'동의 안 함'**
  String get locationConsentDecline;

  /// No description provided for @locationConsentSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'위치정보 이용 동의를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get locationConsentSaveFailed;

  /// No description provided for @myLocationConsentTitle.
  ///
  /// In ko, this message translates to:
  /// **'위치정보 이용 동의'**
  String get myLocationConsentTitle;

  /// No description provided for @myLocationConsentHint.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 찾기에서 현재 위치를 써요'**
  String get myLocationConsentHint;

  /// No description provided for @myLocationConsentAgreed.
  ///
  /// In ko, this message translates to:
  /// **'위치정보 이용에 동의했어요.'**
  String get myLocationConsentAgreed;

  /// No description provided for @myLocationConsentRevoked.
  ///
  /// In ko, this message translates to:
  /// **'위치정보 이용 동의를 철회했어요.'**
  String get myLocationConsentRevoked;

  /// Footer of the support page. The version is read from the build (pubspec.yaml), never hard-coded (#3047).
  ///
  /// In ko, this message translates to:
  /// **'On-Care · 버전 {version}'**
  String myAppVersion(String version);

  /// Shown after the app version in the version row when the build has no build number (local run or test build) (#3226).
  ///
  /// In ko, this message translates to:
  /// **'개발 빌드'**
  String get buildInfoDevelopment;

  /// Deploy time in the version row. The date is the build time converted to Korea Standard Time and formatted for the current locale (#3226).
  ///
  /// In ko, this message translates to:
  /// **'{date} KST 배포'**
  String buildInfoReleasedAt(String date);

  /// Support page footer when the build version cannot be read — the app name only (#3047).
  ///
  /// In ko, this message translates to:
  /// **'On-Care'**
  String get myAppName;

  /// No description provided for @coachHeaderPill.
  ///
  /// In ko, this message translates to:
  /// **'AI 코치'**
  String get coachHeaderPill;

  /// No description provided for @coachHeaderSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘의 맞춤 조언을 모아봤어요'**
  String get coachHeaderSubtitle;

  /// No description provided for @coachCardDietTag.
  ///
  /// In ko, this message translates to:
  /// **'식단'**
  String get coachCardDietTag;

  /// No description provided for @coachCardDietTitle.
  ///
  /// In ko, this message translates to:
  /// **'아침 식단 훌륭, 점심 나트륨 주의'**
  String get coachCardDietTitle;

  /// No description provided for @coachCardDietBody.
  ///
  /// In ko, this message translates to:
  /// **'아침 식단은 균형 있게 잘 챙겼어요. 다만 점심으로 드신 짬뽕은 나트륨과 당류 부담이 있을 수 있으니, 오늘은 물을 충분히 섭취해 주세요. 이후 식사에서는 채소와 단백질을 함께 챙겨 균형을 맞춰 보세요.'**
  String get coachCardDietBody;

  /// No description provided for @coachCardExerciseTag.
  ///
  /// In ko, this message translates to:
  /// **'운동'**
  String get coachCardExerciseTag;

  /// No description provided for @coachCardExerciseTitle.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 운동 3회 완료'**
  String get coachCardExerciseTitle;

  /// No description provided for @coachCardExerciseBody.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 운동을 세 번 마쳤어요. 꾸준히 이어가고 있는 점이 좋아요. 어깨 회전근개 스트레칭을 충분히 진행하고, 가벼운 유산소 운동으로 마무리해 주세요. 운동 후에는 무리한 활동보다 충분한 휴식과 수분 섭취로 회복을 도와주세요.'**
  String get coachCardExerciseBody;

  /// No description provided for @coachCardWaterTag.
  ///
  /// In ko, this message translates to:
  /// **'수분'**
  String get coachCardWaterTag;

  /// No description provided for @coachSheetErrorTitle.
  ///
  /// In ko, this message translates to:
  /// **'조언을 불러오지 못했어요'**
  String get coachSheetErrorTitle;

  /// No description provided for @coachSheetErrorBody.
  ///
  /// In ko, this message translates to:
  /// **'연결 상태를 확인하고 다시 시도해 주세요.'**
  String get coachSheetErrorBody;

  /// No description provided for @coachSheetEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'기록이 쌓이면 조언을 드릴게요'**
  String get coachSheetEmptyTitle;

  /// No description provided for @coachSheetEmptyBody.
  ///
  /// In ko, this message translates to:
  /// **'오늘 먹은 음식과 운동을 기록해 보세요.'**
  String get coachSheetEmptyBody;

  /// No description provided for @coachInviteTitle.
  ///
  /// In ko, this message translates to:
  /// **'담당 요청이 도착했어요'**
  String get coachInviteTitle;

  /// No description provided for @coachInviteFrom.
  ///
  /// In ko, this message translates to:
  /// **'{name} 트레이너'**
  String coachInviteFrom(String name);

  /// No description provided for @coachInviteGym.
  ///
  /// In ko, this message translates to:
  /// **'{gym} 소속'**
  String coachInviteGym(String gym);

  /// No description provided for @coachInviteExplain.
  ///
  /// In ko, this message translates to:
  /// **'수락하면 내 식단 기록·운동 기록·신체 정보, 건강 목표와 건강상태·주의사항을 이 트레이너가 볼 수 있어요. 수락하기 전에 공유 동의를 받아요.'**
  String get coachInviteExplain;

  /// No description provided for @coachInviteAccept.
  ///
  /// In ko, this message translates to:
  /// **'수락'**
  String get coachInviteAccept;

  /// No description provided for @coachInviteReject.
  ///
  /// In ko, this message translates to:
  /// **'거절'**
  String get coachInviteReject;

  /// No description provided for @coachInviteAccepted.
  ///
  /// In ko, this message translates to:
  /// **'{name} 트레이너가 담당으로 연결됐어요'**
  String coachInviteAccepted(String name);

  /// No description provided for @coachInviteRejected.
  ///
  /// In ko, this message translates to:
  /// **'요청을 거절했어요'**
  String get coachInviteRejected;

  /// No description provided for @coachInviteFailed.
  ///
  /// In ko, this message translates to:
  /// **'처리하지 못했어요. 다시 시도해 주세요'**
  String get coachInviteFailed;

  /// No description provided for @coachImageUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'사진을 불러오지 못했어요'**
  String get coachImageUnavailable;

  /// Second line under a chat photo that failed to download; tapping the placeholder fetches it again (#3346).
  ///
  /// In ko, this message translates to:
  /// **'눌러서 다시 불러오기'**
  String get coachImageRetry;

  /// Line under the trainer's name in the chat header. States the relationship only — nothing tracks whether the trainer is online or working, so it must not promise availability (#2089).
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너'**
  String get coachChatSubtitle;

  /// Button above the trainer chat thread that fetches the previous page (#1943).
  ///
  /// In ko, this message translates to:
  /// **'이전 메시지 더 보기'**
  String get coachChatLoadOlder;

  /// No description provided for @coachChatLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'대화를 불러오지 못했어요'**
  String get coachChatLoadFailed;

  /// Trainer chat notice shown instead of the thread once the server reports the assignment ended; the input is disabled (#2843).
  ///
  /// In ko, this message translates to:
  /// **'담당이 해제되어 더 이상 메시지를 보낼 수 없어요'**
  String get coachChatUnassigned;

  /// No description provided for @coachChatEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'{trainer}님과 대화를 시작해 보세요'**
  String coachChatEmptyTitle(String trainer);

  /// No description provided for @coachChatEmptyBody.
  ///
  /// In ko, this message translates to:
  /// **'오늘 먹은 식단 사진이나 운동하며 궁금한 점을 보내 보세요'**
  String get coachChatEmptyBody;

  /// No description provided for @coachChatSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'메시지를 보내지 못했어요. 다시 시도해 주세요'**
  String get coachChatSendFailed;

  /// Toast when the server rejects the message content itself (400/422); sending the same text again would fail the same way, so it does not suggest retrying (#3346).
  ///
  /// In ko, this message translates to:
  /// **'보낼 수 없는 메시지예요. 내용을 확인해 주세요'**
  String get coachChatSendRejected;

  /// Tooltip of the photo button in the trainer chat input bar and title of the sheet it opens (#1665).
  ///
  /// In ko, this message translates to:
  /// **'사진 보내기'**
  String get coachPhotoAttach;

  /// No description provided for @coachPhotoSheetSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'식사·자세·인바디 사진을 트레이너에게 보내요'**
  String get coachPhotoSheetSubtitle;

  /// No description provided for @coachPhotoPickSub.
  ///
  /// In ko, this message translates to:
  /// **'보관함에서 사진 고르기'**
  String get coachPhotoPickSub;

  /// No description provided for @coachPhotoTakeSub.
  ///
  /// In ko, this message translates to:
  /// **'카메라로 바로 찍기'**
  String get coachPhotoTakeSub;

  /// Status under a photo the member is still uploading to the trainer chat (#1665).
  ///
  /// In ko, this message translates to:
  /// **'보내는 중'**
  String get coachPhotoSending;

  /// No description provided for @coachPhotoSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'사진을 보내지 못했어요'**
  String get coachPhotoSendFailed;

  /// Status under a chat photo the server refused (unsupported format etc.); only Delete is offered, not Send again (#3346).
  ///
  /// In ko, this message translates to:
  /// **'보낼 수 없는 사진이에요'**
  String get coachPhotoSendRejected;

  /// No description provided for @coachPhotoRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 보내기'**
  String get coachPhotoRetry;

  /// Drops a photo that failed to send from the chat; nothing reaches the trainer (#1665).
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get coachPhotoDiscard;

  /// No description provided for @coachPhotoPermissionDenied.
  ///
  /// In ko, this message translates to:
  /// **'사진을 보내려면 카메라·사진 접근을 허용해 주세요'**
  String get coachPhotoPermissionDenied;

  /// No description provided for @coachPhotoPermissionPermanentlyDenied.
  ///
  /// In ko, this message translates to:
  /// **'카메라·사진 접근이 꺼져 있어요. 설정에서 켜면 사진을 보낼 수 있어요'**
  String get coachPhotoPermissionPermanentlyDenied;

  /// No description provided for @coachPhotoReadFailed.
  ///
  /// In ko, this message translates to:
  /// **'사진을 읽지 못했어요. 다른 사진으로 다시 시도해 주세요'**
  String get coachPhotoReadFailed;

  /// Screen reader label for a photo the member sent in the trainer chat (#1665).
  ///
  /// In ko, this message translates to:
  /// **'내가 보낸 사진'**
  String get a11yMyPhoto;

  /// No description provided for @coachChatPdfOpenFailed.
  ///
  /// In ko, this message translates to:
  /// **'PDF를 열지 못했어요. 다시 시도해 주세요'**
  String get coachChatPdfOpenFailed;

  /// Toast when the server refuses a weekly report the member has neither received nor bought (403).
  ///
  /// In ko, this message translates to:
  /// **'아직 받지 않은 리포트예요'**
  String get coachReportNotReceived;

  /// No description provided for @coachChatReportRegistered.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트를 받았어요'**
  String get coachChatReportRegistered;

  /// Week the registered report covers, shown on the report card.
  ///
  /// In ko, this message translates to:
  /// **'{sm}월 {sd}일 ~ {em}월 {ed}일'**
  String coachChatReportWeek(int sm, int sd, int em, int ed);

  /// No description provided for @coachChatReportPreviewPdf.
  ///
  /// In ko, this message translates to:
  /// **'PDF 미리보기'**
  String get coachChatReportPreviewPdf;

  /// One metric line in the previewed report.
  ///
  /// In ko, this message translates to:
  /// **'· {label}: {value}'**
  String coachReportPdfBullet(String label, String value);

  /// No description provided for @coachReportPdfFileName.
  ///
  /// In ko, this message translates to:
  /// **'주간리포트_{date}.pdf'**
  String coachReportPdfFileName(String date);

  /// No description provided for @coachChatInputHint.
  ///
  /// In ko, this message translates to:
  /// **'트레이너에게 메시지 보내기...'**
  String get coachChatInputHint;

  /// No description provided for @coachChatRoutineReceived.
  ///
  /// In ko, this message translates to:
  /// **'트레이너가 운동을 보냈어요'**
  String get coachChatRoutineReceived;

  /// No description provided for @coachChatRoutineReceivedPt.
  ///
  /// In ko, this message translates to:
  /// **'PT 프로그램과 개인운동을 받았어요'**
  String get coachChatRoutineReceivedPt;

  /// No description provided for @coachChatRoutineReceivedPersonal.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 받았어요'**
  String get coachChatRoutineReceivedPersonal;

  /// No description provided for @coachChatRoutineReceivedAfterCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소된 PT 대신 개인운동을 받았어요'**
  String get coachChatRoutineReceivedAfterCancel;

  /// No description provided for @coachChatRoutineReceivedProgram.
  ///
  /// In ko, this message translates to:
  /// **'PT 프로그램을 받았어요'**
  String get coachChatRoutineReceivedProgram;

  /// Routine delivery notice: first names, then how many more.
  ///
  /// In ko, this message translates to:
  /// **'{names} 외 {count}개'**
  String coachChatRoutineReceivedMore(String names, int count);

  /// Chat date divider with full date and weekday.
  ///
  /// In ko, this message translates to:
  /// **'{date}'**
  String coachChatDateDivider(DateTime date);

  /// No description provided for @coachCtaChat.
  ///
  /// In ko, this message translates to:
  /// **'AI와 대화하기'**
  String get coachCtaChat;

  /// No description provided for @navAddRecordTitle.
  ///
  /// In ko, this message translates to:
  /// **'새 기록 추가'**
  String get navAddRecordTitle;

  /// No description provided for @navAddRecordSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'식단 또는 운동을 선택해 주세요'**
  String get navAddRecordSubtitle;

  /// No description provided for @navDietOptionSub.
  ///
  /// In ko, this message translates to:
  /// **'사진으로 영양 분석'**
  String get navDietOptionSub;

  /// No description provided for @navExerciseOptionSub.
  ///
  /// In ko, this message translates to:
  /// **'종류와 시간 기록'**
  String get navExerciseOptionSub;

  /// No description provided for @aicHeaderSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'언제든 물어보세요'**
  String get aicHeaderSubtitle;

  /// No description provided for @aicMedicalDisclaimer.
  ///
  /// In ko, this message translates to:
  /// **'AI 코치는 식단·운동 관리를 돕는 참고용이에요. 진단·처방이 아니니 증상이 있으면 전문의와 상담해 주세요.'**
  String get aicMedicalDisclaimer;

  /// No description provided for @aicInputHint.
  ///
  /// In ko, this message translates to:
  /// **'AI에게 무엇이든 물어보세요'**
  String get aicInputHint;

  /// No description provided for @aicQuotaFreeLeft.
  ///
  /// In ko, this message translates to:
  /// **'오늘 무료 대화 {count}회 남음'**
  String aicQuotaFreeLeft(int count);

  /// No description provided for @aicQuotaPaidNext.
  ///
  /// In ko, this message translates to:
  /// **'다음 대화 {cost} · 오늘 구매 {used}/{limit}'**
  String aicQuotaPaidNext(String cost, int used, int limit);

  /// No description provided for @aicQuotaExhausted.
  ///
  /// In ko, this message translates to:
  /// **'오늘 대화를 다 썼어요. 내일 다시 열려요'**
  String get aicQuotaExhausted;

  /// No description provided for @aicAiCapacity.
  ///
  /// In ko, this message translates to:
  /// **'지금은 AI 기능 이용이 많아 잠시 쉬어요. 내일 다시 이용해 주세요'**
  String get aicAiCapacity;

  /// No description provided for @aicQuotaFindTrainer.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 찾기'**
  String get aicQuotaFindTrainer;

  /// No description provided for @aicPaidConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'포인트로 대화를 이어갈까요?'**
  String get aicPaidConfirmTitle;

  /// No description provided for @aicPaidConfirmMessage.
  ///
  /// In ko, this message translates to:
  /// **'오늘 무료 대화를 다 썼어요. 이 대화를 보내면 {cost}가 차감돼요 (오늘 {limit}회까지).\n\n현재 포인트 {balance}'**
  String aicPaidConfirmMessage(String cost, int limit, String balance);

  /// No description provided for @aicPaidConfirmAction.
  ///
  /// In ko, this message translates to:
  /// **'포인트로 보내기'**
  String get aicPaidConfirmAction;

  /// No description provided for @aicPaidInsufficient.
  ///
  /// In ko, this message translates to:
  /// **'포인트가 {shortfall} 부족해요. 사진으로 식단을 기록하거나 운동을 기록하면 포인트가 쌓여요.'**
  String aicPaidInsufficient(String shortfall);

  /// No description provided for @aicPointsSpent.
  ///
  /// In ko, this message translates to:
  /// **'−{spent}'**
  String aicPointsSpent(String spent);

  /// No description provided for @aicQuickRepliesLabel.
  ///
  /// In ko, this message translates to:
  /// **'이런 걸 물어보세요'**
  String get aicQuickRepliesLabel;

  /// Shown in the coach bubble while a tailored reply is being generated
  ///
  /// In ko, this message translates to:
  /// **'맞춤 답변 생성 중'**
  String get aicGeneratingReply;

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In ko, this message translates to:
  /// **'{part} 통증 감지'**
  String aicInsightDiscomfortPart(String part);

  /// Body part name filled into aicInsightDiscomfortPart (#2736). The detector reports it as "무릎" or "Knee".
  ///
  /// In ko, this message translates to:
  /// **'무릎'**
  String get aicBodyPartKnee;

  /// Body part name filled into aicInsightDiscomfortPart (#2736). The detector reports it as "허리" or "Back".
  ///
  /// In ko, this message translates to:
  /// **'허리'**
  String get aicBodyPartBack;

  /// Body part name filled into aicInsightDiscomfortPart (#2736). The detector reports it as "발목" or "Ankle".
  ///
  /// In ko, this message translates to:
  /// **'발목'**
  String get aicBodyPartAnkle;

  /// Body part name filled into aicInsightDiscomfortPart (#2736). The detector reports it as "어깨" or "Shoulder".
  ///
  /// In ko, this message translates to:
  /// **'어깨'**
  String get aicBodyPartShoulder;

  /// Body part name filled into aicInsightDiscomfortPart (#2736). The detector reports it as "손목" or "Wrist".
  ///
  /// In ko, this message translates to:
  /// **'손목'**
  String get aicBodyPartWrist;

  /// Body part name filled into aicInsightDiscomfortPart (#2736). The detector reports it as "목" or "Neck".
  ///
  /// In ko, this message translates to:
  /// **'목'**
  String get aicBodyPartNeck;

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In ko, this message translates to:
  /// **'통증 감지'**
  String get aicInsightDiscomfort;

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In ko, this message translates to:
  /// **'부정적 반응 감지'**
  String get aicInsightNegative;

  /// Removes one detection from the AI coach insight log (#1975).
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get aicInsightDelete;

  /// No description provided for @aicInsightDeleteConfirm.
  ///
  /// In ko, this message translates to:
  /// **'이 감지를 참고 기록에서 삭제할까요? 대화에 쓴 말은 그대로 남아요.'**
  String get aicInsightDeleteConfirm;

  /// No description provided for @aicInsightDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'삭제하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get aicInsightDeleteFailed;

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In ko, this message translates to:
  /// **'참고 기록'**
  String get aicInsightHistoryTitle;

  /// AI coach chat: header button that opens the noted-signals list; short because it sits beside the title (#1900).
  ///
  /// In ko, this message translates to:
  /// **'참고 기록'**
  String get aicInsightHistoryAction;

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In ko, this message translates to:
  /// **'최근 {days}일 동안 감지한 통증·부정적 반응이에요. AI가 답할 때 참고해요'**
  String aicInsightHistorySubtitle(int days);

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In ko, this message translates to:
  /// **'최근 {days}일 동안 감지된 내용이 없어요'**
  String aicInsightHistoryEmpty(int days);

  /// AI coach chat: pain / negative feedback the AI takes into account when answering (#1824, #1973).
  ///
  /// In ko, this message translates to:
  /// **'참고 기록을 불러오지 못했어요'**
  String get aicInsightHistoryFailed;

  /// AI coach chat: how long the conversation is kept (#1823).
  ///
  /// In ko, this message translates to:
  /// **'AI 코치 대화는 최근 {days}일 동안만 보관돼요'**
  String aicRetentionNotice(int days);

  /// AI coach chat: shown instead of the chat when the member has a trainer (#1823).
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너에게 메시지를 보내 주세요'**
  String get aicTrainerConnectedTitle;

  /// AI coach chat: shown instead of the chat when the member has a trainer (#1823).
  ///
  /// In ko, this message translates to:
  /// **'{name} 트레이너와 연결되어 있어요. 담당 트레이너가 있는 회원은 AI 코치 대신 트레이너와 메시지를 주고받아요'**
  String aicTrainerConnectedBody(String name);

  /// No description provided for @aicQuickReply1.
  ///
  /// In ko, this message translates to:
  /// **'오늘 저녁 메뉴 추천해줘'**
  String get aicQuickReply1;

  /// No description provided for @aicQuickReply2.
  ///
  /// In ko, this message translates to:
  /// **'오늘 운동은 얼마나 하면 좋을까?'**
  String get aicQuickReply2;

  /// No description provided for @aicQuickReply3.
  ///
  /// In ko, this message translates to:
  /// **'오늘 나트륨 얼마나 먹었어?'**
  String get aicQuickReply3;

  /// No description provided for @exConsultRequestTitle.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청'**
  String get exConsultRequestTitle;

  /// No description provided for @exGymConsultRequest.
  ///
  /// In ko, this message translates to:
  /// **'상담 신청'**
  String get exGymConsultRequest;

  /// No description provided for @exGymConsultPickTrainer.
  ///
  /// In ko, this message translates to:
  /// **'상담받을 트레이너 선택'**
  String get exGymConsultPickTrainer;

  /// No description provided for @exGymConsultPickTrainerHint.
  ///
  /// In ko, this message translates to:
  /// **'상담은 트레이너 한 분에게 전달돼요.'**
  String get exGymConsultPickTrainerHint;

  /// No description provided for @exGymConsultNoTrainers.
  ///
  /// In ko, this message translates to:
  /// **'아직 소속 트레이너가 없어요.'**
  String get exGymConsultNoTrainers;

  /// No description provided for @exGymNoTrainersCallHint.
  ///
  /// In ko, this message translates to:
  /// **'아직 가입한 트레이너가 없어 앱에서 상담을 신청할 수 없어요. 헬스장에 전화로 문의해 주세요.'**
  String get exGymNoTrainersCallHint;

  /// No description provided for @exGymNoTrainersHint.
  ///
  /// In ko, this message translates to:
  /// **'아직 가입한 트레이너가 없어 앱에서 상담을 신청할 수 없어요.'**
  String get exGymNoTrainersHint;

  /// No description provided for @exGymCallInquiry.
  ///
  /// In ko, this message translates to:
  /// **'전화 문의'**
  String get exGymCallInquiry;

  /// No description provided for @exGymTrainersLoadError.
  ///
  /// In ko, this message translates to:
  /// **'소속 트레이너를 불러오지 못했어요.'**
  String get exGymTrainersLoadError;

  /// No description provided for @exTrainerConsultRequest.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 상담 신청'**
  String get exTrainerConsultRequest;

  /// No description provided for @exConsultPendingCta.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청 대기 중'**
  String get exConsultPendingCta;

  /// No description provided for @exViewConsultationRequest.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청 확인'**
  String get exViewConsultationRequest;

  /// No description provided for @exConsultTarget.
  ///
  /// In ko, this message translates to:
  /// **'상담 대상'**
  String get exConsultTarget;

  /// No description provided for @exTrainerConsultType.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 상담'**
  String get exTrainerConsultType;

  /// No description provided for @exAssignedTrainer.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너'**
  String get exAssignedTrainer;

  /// No description provided for @exConsultDataSharingNotice.
  ///
  /// In ko, this message translates to:
  /// **'상담 신청 정보(이름·운동 목표·문의 내용)는 상담을 위해 이 트레이너에게 전달되고, 보낸 뒤에는 상담 요청과 일정에 남아요. 동의하지 않으면 상담 신청만 보낼 수 없고 다른 기능은 그대로 쓸 수 있어요. 식단·운동 기록은 상담 뒤 연결 코드로 등록할 때 따로 동의를 받아요.'**
  String get exConsultDataSharingNotice;

  /// No description provided for @exConsultDataSharingAgree.
  ///
  /// In ko, this message translates to:
  /// **'위 내용을 확인했고, 상담 신청 정보를 이 트레이너에게 전달하는 데 동의해요'**
  String get exConsultDataSharingAgree;

  /// No description provided for @exConsultDataSharingRequired.
  ///
  /// In ko, this message translates to:
  /// **'전달에 동의해야 상담을 신청할 수 있어요'**
  String get exConsultDataSharingRequired;

  /// No description provided for @exConsultDataSharingLinked.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너라 식단·운동 기록과 신체 정보를 이미 공유하고 있어요. 다시 동의하지 않아도 돼요.'**
  String get exConsultDataSharingLinked;

  /// No description provided for @exConsultGoalPrefilled.
  ///
  /// In ko, this message translates to:
  /// **'MY 건강 목표를 채워 두었어요. 이번 상담에 맞게 바꿔도 돼요.'**
  String get exConsultGoalPrefilled;

  /// No description provided for @coachInviteConsentTitle.
  ///
  /// In ko, this message translates to:
  /// **'담당 연결 전에 확인해 주세요'**
  String get coachInviteConsentTitle;

  /// No description provided for @coachInviteConsentBody.
  ///
  /// In ko, this message translates to:
  /// **'{name} 트레이너와 담당으로 연결되면, 코칭·상담·리포트 작성을 위해 회원님의 식단 기록·운동 기록·신체 정보, 건강 목표와 건강상태·주의사항을 이 트레이너가 볼 수 있어요. 연결을 해제하면 열람 권한도 함께 사라지지만, 그 전에 주고받은 대화와 전달된 리포트는 남아요. 동의하지 않아도 개인 기록 기능은 그대로 쓸 수 있어요.'**
  String coachInviteConsentBody(String name);

  /// No description provided for @coachInviteConsentAgree.
  ///
  /// In ko, this message translates to:
  /// **'동의하고 연결'**
  String get coachInviteConsentAgree;

  /// No description provided for @exConsultSlotTitle.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간'**
  String get exConsultSlotTitle;

  /// No description provided for @exConsultSlotRequired.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간을 선택해 주세요.'**
  String get exConsultSlotRequired;

  /// No description provided for @exConsultSlotsEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'지금은 예약 가능한 상담 시간이 없어요.'**
  String get exConsultSlotsEmptyTitle;

  /// No description provided for @exConsultSlotsEmptyBody.
  ///
  /// In ko, this message translates to:
  /// **'{gym} {phone} 로 문의해 상담 시간을 요청해 주세요.'**
  String exConsultSlotsEmptyBody(String gym, String phone);

  /// No description provided for @exConsultSlotsEmptyNoPhone.
  ///
  /// In ko, this message translates to:
  /// **'{gym} 상세에서 위치와 영업시간을 확인해 문의해 주세요.'**
  String exConsultSlotsEmptyNoPhone(String gym);

  /// No description provided for @exConsultSlotsError.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간을 불러오지 못했어요.'**
  String get exConsultSlotsError;

  /// No description provided for @exConsultSlotTaken.
  ///
  /// In ko, this message translates to:
  /// **'방금 다른 회원이 그 시간을 예약했어요. 다른 시간을 선택해 주세요.'**
  String get exConsultSlotTaken;

  /// No description provided for @exConsultTooManyPending.
  ///
  /// In ko, this message translates to:
  /// **'답을 기다리는 상담 요청이 이미 {count}건 있어요. 답을 받거나 요청을 취소한 뒤 다시 신청해 주세요.'**
  String exConsultTooManyPending(int count);

  /// No description provided for @exConsultRateLimitedHours.
  ///
  /// In ko, this message translates to:
  /// **'상담 신청이 너무 잦아요. {hours}시간 뒤에 다시 신청해 주세요.'**
  String exConsultRateLimitedHours(int hours);

  /// No description provided for @exConsultRateLimitedMinutes.
  ///
  /// In ko, this message translates to:
  /// **'상담 신청이 너무 잦아요. {minutes}분 뒤에 다시 신청해 주세요.'**
  String exConsultRateLimitedMinutes(int minutes);

  /// No description provided for @exConsultRateLimited.
  ///
  /// In ko, this message translates to:
  /// **'상담 신청이 너무 잦아요. 잠시 후 다시 신청해 주세요.'**
  String get exConsultRateLimited;

  /// No description provided for @exConsultTooManyPendingNoCount.
  ///
  /// In ko, this message translates to:
  /// **'답을 기다리는 상담 요청이 너무 많아요. 답을 받거나 요청을 취소한 뒤 다시 신청해 주세요.'**
  String get exConsultTooManyPendingNoCount;

  /// No description provided for @exGymCall.
  ///
  /// In ko, this message translates to:
  /// **'전화 걸기'**
  String get exGymCall;

  /// No description provided for @exGymCallFailed.
  ///
  /// In ko, this message translates to:
  /// **'전화 앱을 열 수 없어요.'**
  String get exGymCallFailed;

  /// No description provided for @exGymDetail.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 상세 보기'**
  String get exGymDetail;

  /// No description provided for @exConsultChosenSlot.
  ///
  /// In ko, this message translates to:
  /// **'신청한 시간'**
  String get exConsultChosenSlot;

  /// No description provided for @exConsultConfirmedAt.
  ///
  /// In ko, this message translates to:
  /// **'확정 일시'**
  String get exConsultConfirmedAt;

  /// No description provided for @exConsultExpired.
  ///
  /// In ko, this message translates to:
  /// **'만료됨'**
  String get exConsultExpired;

  /// No description provided for @exConsultExpiredBody.
  ///
  /// In ko, this message translates to:
  /// **'트레이너가 시간 안에 확인하지 않았어요. 다른 시간으로 다시 신청해 보세요.'**
  String get exConsultExpiredBody;

  /// No description provided for @exConsultCancelledByTrainerBody.
  ///
  /// In ko, this message translates to:
  /// **'트레이너가 상담 일정을 취소했어요. 다른 시간으로 다시 신청해 보세요.'**
  String get exConsultCancelledByTrainerBody;

  /// No description provided for @exConsultTrainerNameMissing.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 정보 없음'**
  String get exConsultTrainerNameMissing;

  /// No description provided for @exExerciseGoal.
  ///
  /// In ko, this message translates to:
  /// **'운동 목표'**
  String get exExerciseGoal;

  /// No description provided for @exGoalHealth.
  ///
  /// In ko, this message translates to:
  /// **'건강 관리'**
  String get exGoalHealth;

  /// No description provided for @exOptionOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get exOptionOther;

  /// No description provided for @exOtherGoalHint.
  ///
  /// In ko, this message translates to:
  /// **'구체적인 운동 목표는 문의 내용에 작성해 주세요.'**
  String get exOtherGoalHint;

  /// No description provided for @exPreferredDate.
  ///
  /// In ko, this message translates to:
  /// **'희망 날짜'**
  String get exPreferredDate;

  /// No description provided for @exTimeFlexible.
  ///
  /// In ko, this message translates to:
  /// **'시간 협의'**
  String get exTimeFlexible;

  /// No description provided for @exConsultMessage.
  ///
  /// In ko, this message translates to:
  /// **'문의 내용'**
  String get exConsultMessage;

  /// No description provided for @exConsultMessageHint.
  ///
  /// In ko, this message translates to:
  /// **'운동 경험이나 상담 시 참고할 내용을 자유롭게 작성해 주세요.'**
  String get exConsultMessageHint;

  /// No description provided for @exSendConsultRequest.
  ///
  /// In ko, this message translates to:
  /// **'상담 신청'**
  String get exSendConsultRequest;

  /// No description provided for @exGoalRequired.
  ///
  /// In ko, this message translates to:
  /// **'운동 목표를 선택해 주세요.'**
  String get exGoalRequired;

  /// No description provided for @exOtherGoalDetailRequired.
  ///
  /// In ko, this message translates to:
  /// **'구체적인 운동 목표를 문의 내용에 입력해 주세요.'**
  String get exOtherGoalDetailRequired;

  /// No description provided for @exConsultTargetNotFound.
  ///
  /// In ko, this message translates to:
  /// **'상담 대상 정보를 찾을 수 없어요.'**
  String get exConsultTargetNotFound;

  /// No description provided for @exConsultPendingExists.
  ///
  /// In ko, this message translates to:
  /// **'이미 확인 대기 중인 상담 요청이 있어요.'**
  String get exConsultPendingExists;

  /// No description provided for @exConsultReceived.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청이 접수됐어요'**
  String get exConsultReceived;

  /// No description provided for @exConsultCompletionInfo.
  ///
  /// In ko, this message translates to:
  /// **'상대방이 요청을 확인하면 안내해 드릴게요.'**
  String get exConsultCompletionInfo;

  /// No description provided for @exConsultStatus.
  ///
  /// In ko, this message translates to:
  /// **'현재 상태'**
  String get exConsultStatus;

  /// No description provided for @exConsultPendingStatus.
  ///
  /// In ko, this message translates to:
  /// **'대기 중'**
  String get exConsultPendingStatus;

  /// No description provided for @exConsultAcceptedStatus.
  ///
  /// In ko, this message translates to:
  /// **'승인됨'**
  String get exConsultAcceptedStatus;

  /// No description provided for @exConsultRejectedStatus.
  ///
  /// In ko, this message translates to:
  /// **'거절됨'**
  String get exConsultRejectedStatus;

  /// No description provided for @exReturnExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동 탭으로 돌아가기'**
  String get exReturnExercise;

  /// No description provided for @exConsultHistoryTitle.
  ///
  /// In ko, this message translates to:
  /// **'내 상담 요청'**
  String get exConsultHistoryTitle;

  /// No description provided for @exConsultHistoryEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 보낸 상담 요청이 없어요.'**
  String get exConsultHistoryEmpty;

  /// No description provided for @exConsultHistoryInProgress.
  ///
  /// In ko, this message translates to:
  /// **'진행 중'**
  String get exConsultHistoryInProgress;

  /// No description provided for @exConsultRejectedReasonLabel.
  ///
  /// In ko, this message translates to:
  /// **'거절 사유'**
  String get exConsultRejectedReasonLabel;

  /// No description provided for @exConsultRejectedNoReason.
  ///
  /// In ko, this message translates to:
  /// **'사유를 남기지 않았어요. 다른 트레이너에게 상담을 신청해 보세요.'**
  String get exConsultRejectedNoReason;

  /// No description provided for @exConsultAcceptedGuide.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청이 승인됐어요. 등록하기로 하면 상담 때 MY 탭의 연결 코드로 트레이너와 연결할 수 있어요.'**
  String get exConsultAcceptedGuide;

  /// No description provided for @exMyReservations.
  ///
  /// In ko, this message translates to:
  /// **'내 예약'**
  String get exMyReservations;

  /// No description provided for @exCancelReservation.
  ///
  /// In ko, this message translates to:
  /// **'예약 취소'**
  String get exCancelReservation;

  /// No description provided for @exCancelKeep.
  ///
  /// In ko, this message translates to:
  /// **'유지'**
  String get exCancelKeep;

  /// No description provided for @exCancelConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'예약을 취소할까요?'**
  String get exCancelConfirmTitle;

  /// No description provided for @exCancelFailed.
  ///
  /// In ko, this message translates to:
  /// **'예약을 취소하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get exCancelFailed;

  /// No description provided for @exReservationPast.
  ///
  /// In ko, this message translates to:
  /// **'지난 예약'**
  String get exReservationPast;

  /// No description provided for @exReservationPastMore.
  ///
  /// In ko, this message translates to:
  /// **'지난 예약 {count}건 더 보기'**
  String exReservationPastMore(int count);

  /// No description provided for @exReservationPastLess.
  ///
  /// In ko, this message translates to:
  /// **'지난 예약 접기'**
  String get exReservationPastLess;

  /// No description provided for @exCancelConfirmBody.
  ///
  /// In ko, this message translates to:
  /// **'{when} 예약이 취소되고 그 자리가 다시 열려요.'**
  String exCancelConfirmBody(String when);

  /// No description provided for @exCancelDone.
  ///
  /// In ko, this message translates to:
  /// **'{when} 예약을 취소했어요'**
  String exCancelDone(String when);

  /// No description provided for @mySupportOpenFailed.
  ///
  /// In ko, this message translates to:
  /// **'링크를 열지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get mySupportOpenFailed;

  /// Shown under the FAQ / 1:1 inquiry rows so it is clear the tap leaves the app.
  ///
  /// In ko, this message translates to:
  /// **'카카오톡 채널로 연결돼요'**
  String get mySupportExternalHint;

  /// Splash message while the saved session is being restored (#1944).
  ///
  /// In ko, this message translates to:
  /// **'로그인 정보를 불러오는 중이에요'**
  String get authRestoring;

  /// No description provided for @authRestoreFailed.
  ///
  /// In ko, this message translates to:
  /// **'연결이 불안정해 로그인 정보를 불러오지 못했어요.'**
  String get authRestoreFailed;

  /// No description provided for @authRestoreRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get authRestoreRetry;

  /// No description provided for @authRestoreSignIn.
  ///
  /// In ko, this message translates to:
  /// **'로그인 화면으로'**
  String get authRestoreSignIn;

  /// No description provided for @authTagline.
  ///
  /// In ko, this message translates to:
  /// **'기록하면 코칭이 돌아오는 식단·운동 관리'**
  String get authTagline;

  /// No description provided for @authEmailHint.
  ///
  /// In ko, this message translates to:
  /// **'이메일'**
  String get authEmailHint;

  /// No description provided for @authPasswordHint.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호'**
  String get authPasswordHint;

  /// No description provided for @authSignInAction.
  ///
  /// In ko, this message translates to:
  /// **'로그인'**
  String get authSignInAction;

  /// No description provided for @authNoAccountQuestion.
  ///
  /// In ko, this message translates to:
  /// **'계정이 없으신가요?'**
  String get authNoAccountQuestion;

  /// No description provided for @authSignUpAction.
  ///
  /// In ko, this message translates to:
  /// **'회원가입'**
  String get authSignUpAction;

  /// No description provided for @authDemoAction.
  ///
  /// In ko, this message translates to:
  /// **'체험하기'**
  String get authDemoAction;

  /// No description provided for @authDemoNote.
  ///
  /// In ko, this message translates to:
  /// **'예시 데이터 사용 · 트레이너 연동은 로그인 후'**
  String get authDemoNote;

  /// Label centered in the divider above the circular Kakao/Google sign-in buttons (#1783).
  ///
  /// In ko, this message translates to:
  /// **'SNS 계정으로 로그인'**
  String get authSocialDivider;

  /// No description provided for @authKakaoAction.
  ///
  /// In ko, this message translates to:
  /// **'카카오로 시작하기'**
  String get authKakaoAction;

  /// No description provided for @authGoogleAction.
  ///
  /// In ko, this message translates to:
  /// **'구글로 시작하기'**
  String get authGoogleAction;

  /// Red text under the email field on sign-in/sign-up when it is empty (#1784).
  ///
  /// In ko, this message translates to:
  /// **'이메일을 입력해 주세요'**
  String get authEmailEmpty;

  /// No description provided for @authEmailInvalid.
  ///
  /// In ko, this message translates to:
  /// **'이메일 형식이 올바르지 않아요'**
  String get authEmailInvalid;

  /// Red text under the email field when the address is longer than the server limit (#2908). The limit matches the users.email column and EMAIL_MAX_LENGTH in contact_format.py.
  ///
  /// In ko, this message translates to:
  /// **'이메일은 255자까지 입력할 수 있어요'**
  String get authEmailTooLong;

  /// No description provided for @authPasswordEmpty.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 입력해 주세요'**
  String get authPasswordEmpty;

  /// No description provided for @authSignInFailed.
  ///
  /// In ko, this message translates to:
  /// **'로그인하지 못했어요. 이메일·비밀번호를 확인해 주세요'**
  String get authSignInFailed;

  /// No description provided for @authSignInNetworkFailed.
  ///
  /// In ko, this message translates to:
  /// **'인터넷 연결을 확인하고 다시 시도해 주세요'**
  String get authSignInNetworkFailed;

  /// No description provided for @authSignInUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'지금은 로그인할 수 없어요. 잠시 후 다시 시도해 주세요'**
  String get authSignInUnavailable;

  /// No description provided for @authSessionExpired.
  ///
  /// In ko, this message translates to:
  /// **'로그인이 만료됐어요. 다시 로그인해 주세요'**
  String get authSessionExpired;

  /// No description provided for @authSocialSignInFailed.
  ///
  /// In ko, this message translates to:
  /// **'소셜 로그인을 하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get authSocialSignInFailed;

  /// Error toast on sign-in when the social account's unverified email matches an existing account (409 social_email_in_use, #1551).
  ///
  /// In ko, this message translates to:
  /// **'이 이메일로 가입한 계정이 있어요. 처음 가입한 방법으로 로그인해 주세요.'**
  String get authSocialEmailInUse;

  /// No description provided for @authSocialComingSoon.
  ///
  /// In ko, this message translates to:
  /// **'소셜 로그인은 준비 중이에요. 이메일로 로그인해 주세요'**
  String get authSocialComingSoon;

  /// Shown when the browser blocks the Kakao sign-in pop-up window on the web (#330).
  ///
  /// In ko, this message translates to:
  /// **'로그인 창이 차단됐어요. 이 사이트의 팝업을 허용한 뒤 다시 시도해 주세요'**
  String get authSocialPopupBlocked;

  /// Title of the sign-in banner shown when a trainer account tries to sign in to the member app (#3137).
  ///
  /// In ko, this message translates to:
  /// **'트레이너 계정이에요'**
  String get authTrainerAccountTitle;

  /// Body of the trainer-account sign-in banner. The issued tokens are discarded (#3137).
  ///
  /// In ko, this message translates to:
  /// **'회원 앱은 회원 계정으로 이용해요. 트레이너 계정은 트레이너 웹에서 로그인해 주세요'**
  String get authTrainerAccountMessage;

  /// Banner action that opens the trainer web on the same origin. Shown on web builds only (#3137).
  ///
  /// In ko, this message translates to:
  /// **'트레이너 웹 열기'**
  String get authTrainerAccountOpenWeb;

  /// No description provided for @signUpTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원가입'**
  String get signUpTitle;

  /// No description provided for @signUpSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'On-Care 계정을 만들어 건강 관리를 시작하세요'**
  String get signUpSubtitle;

  /// No description provided for @signUpNameHint.
  ///
  /// In ko, this message translates to:
  /// **'이름'**
  String get signUpNameHint;

  /// Red text under the name field on sign-up when it is empty or whitespace only (#1784).
  ///
  /// In ko, this message translates to:
  /// **'이름을 입력해 주세요'**
  String get signUpNameEmpty;

  /// Shared name-length message (#1887). The limit matches the users.name column and the server rule in profile_format.py.
  ///
  /// In ko, this message translates to:
  /// **'이름은 100자까지 입력할 수 있어요'**
  String get signUpNameTooLong;

  /// Placeholder showing the required 3-4-4 phone format; hyphens are inserted automatically (#1784).
  ///
  /// In ko, this message translates to:
  /// **'010-0000-0000'**
  String get signUpPhoneHint;

  /// No description provided for @signUpPhoneHelper.
  ///
  /// In ko, this message translates to:
  /// **'트레이너가 회원님을 확인할 때 쓰는 연락처예요'**
  String get signUpPhoneHelper;

  /// No description provided for @signUpPasswordHint.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 (영문·숫자 포함 8자 이상)'**
  String get signUpPasswordHint;

  /// No description provided for @signUpPasswordConfirmHint.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 확인'**
  String get signUpPasswordConfirmHint;

  /// No description provided for @signUpAction.
  ///
  /// In ko, this message translates to:
  /// **'가입하고 시작하기'**
  String get signUpAction;

  /// No description provided for @signUpHaveAccountQuestion.
  ///
  /// In ko, this message translates to:
  /// **'이미 계정이 있으신가요?'**
  String get signUpHaveAccountQuestion;

  /// No description provided for @signUpPasswordWeak.
  ///
  /// In ko, this message translates to:
  /// **'영문과 숫자를 포함해 8자 이상 입력해 주세요'**
  String get signUpPasswordWeak;

  /// Password upper-limit message (#1555). Matches the server rule in password_policy.py: 64 characters and 72 UTF-8 bytes (bcrypt), so Korean letters and emoji use up the limit faster.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호는 64자까지 입력할 수 있어요 (한글·이모지는 더 짧게)'**
  String get signUpPasswordTooLong;

  /// No description provided for @signUpPasswordMismatch.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 일치하지 않아요'**
  String get signUpPasswordMismatch;

  /// No description provided for @signUpPhoneFormatInvalid.
  ///
  /// In ko, this message translates to:
  /// **'전화번호를 010-0000-0000 형식으로 입력해 주세요'**
  String get signUpPhoneFormatInvalid;

  /// Shared birth-date format message (#1887). Matches the YYYY-MM-DD rule the server enforces in profile_format.py.
  ///
  /// In ko, this message translates to:
  /// **'생년월일을 1996-03-21 형식으로 입력해 주세요'**
  String get myFieldBirthInvalid;

  /// No description provided for @trainerSyncEntryLabel.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 연결 코드'**
  String get trainerSyncEntryLabel;

  /// No description provided for @trainerSyncEntryHint.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너와 연결해 기록을 공유하는 6자리 코드예요'**
  String get trainerSyncEntryHint;

  /// No description provided for @trainerSyncTitle.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 연결 코드'**
  String get trainerSyncTitle;

  /// No description provided for @trainerSyncConsent.
  ///
  /// In ko, this message translates to:
  /// **'이 코드를 입력한 트레이너가 담당이 되면, 코칭·상담·리포트 작성을 위해 회원님의 식단 기록·운동 기록·신체 정보, 건강 목표와 건강상태·주의사항을 볼 수 있어요. 연결을 해제하면 열람 권한도 함께 사라지지만, 그 전에 주고받은 대화와 전달된 리포트는 남아요. 동의하지 않아도 개인 기록 기능은 그대로 쓸 수 있어요.'**
  String get trainerSyncConsent;

  /// No description provided for @trainerShareDetailMore.
  ///
  /// In ko, this message translates to:
  /// **'자세히 보기'**
  String get trainerShareDetailMore;

  /// No description provided for @trainerShareDetailLess.
  ///
  /// In ko, this message translates to:
  /// **'접기'**
  String get trainerShareDetailLess;

  /// No description provided for @trainerShareRecipientLabel.
  ///
  /// In ko, this message translates to:
  /// **'받는 사람'**
  String get trainerShareRecipientLabel;

  /// No description provided for @trainerShareRecipient.
  ///
  /// In ko, this message translates to:
  /// **'담당으로 연결된 트레이너'**
  String get trainerShareRecipient;

  /// No description provided for @trainerShareItemsLabel.
  ///
  /// In ko, this message translates to:
  /// **'공유 항목'**
  String get trainerShareItemsLabel;

  /// No description provided for @trainerShareItems.
  ///
  /// In ko, this message translates to:
  /// **'식단 기록·운동 기록·신체 정보, 건강 목표와 건강상태·주의사항'**
  String get trainerShareItems;

  /// No description provided for @trainerSharePurposeLabel.
  ///
  /// In ko, this message translates to:
  /// **'이용 목적'**
  String get trainerSharePurposeLabel;

  /// No description provided for @trainerSharePurpose.
  ///
  /// In ko, this message translates to:
  /// **'코칭·상담·리포트 작성'**
  String get trainerSharePurpose;

  /// No description provided for @trainerSharePeriodLabel.
  ///
  /// In ko, this message translates to:
  /// **'이용 기간'**
  String get trainerSharePeriodLabel;

  /// No description provided for @trainerSharePeriod.
  ///
  /// In ko, this message translates to:
  /// **'연결을 해제해 동의를 철회할 때까지예요. MY 탭에서 담당 트레이너 연결을 해제하면 철회되고, 그 뒤로 트레이너는 새 기록을 볼 수 없어요. 다만 철회 전에 주고받은 대화와 전달된 리포트는 지워지지 않고 남아요.'**
  String get trainerSharePeriod;

  /// No description provided for @trainerShareRefuseLabel.
  ///
  /// In ko, this message translates to:
  /// **'거부할 권리'**
  String get trainerShareRefuseLabel;

  /// No description provided for @trainerShareRefuse.
  ///
  /// In ko, this message translates to:
  /// **'동의하지 않을 수 있어요. 동의하지 않아도 앱의 개인 기록 기능은 그대로 쓸 수 있고, 트레이너 연결만 되지 않아요.'**
  String get trainerShareRefuse;

  /// No description provided for @trainerSyncAgree.
  ///
  /// In ko, this message translates to:
  /// **'동의하고 코드 받기'**
  String get trainerSyncAgree;

  /// No description provided for @trainerSyncHint.
  ///
  /// In ko, this message translates to:
  /// **'트레이너에게 이 연결 코드 6자리를 불러 주세요.'**
  String get trainerSyncHint;

  /// No description provided for @trainerSyncCountdown.
  ///
  /// In ko, this message translates to:
  /// **'{remaining} 뒤에 만료돼요'**
  String trainerSyncCountdown(String remaining);

  /// No description provided for @trainerSyncExpired.
  ///
  /// In ko, this message translates to:
  /// **'코드가 만료됐어요.'**
  String get trainerSyncExpired;

  /// No description provided for @trainerSyncFailed.
  ///
  /// In ko, this message translates to:
  /// **'코드를 받지 못했어요.'**
  String get trainerSyncFailed;

  /// No description provided for @trainerSyncRetry.
  ///
  /// In ko, this message translates to:
  /// **'새 코드 받기'**
  String get trainerSyncRetry;

  /// No description provided for @trainerSyncConnected.
  ///
  /// In ko, this message translates to:
  /// **'{name} 트레이너와 연결됐어요'**
  String trainerSyncConnected(String name);

  /// No description provided for @trainerSyncConnectedBody.
  ///
  /// In ko, this message translates to:
  /// **'이제 트레이너가 회원님의 기록을 보고 코칭할 수 있어요.'**
  String get trainerSyncConnectedBody;

  /// Sign-up: the account was created but the follow-up sign-in failed (#1926).
  ///
  /// In ko, this message translates to:
  /// **'계정이 만들어졌어요. 로그인해 주세요'**
  String get signUpCreatedSignInNeeded;

  /// No description provided for @signUpEmailTaken.
  ///
  /// In ko, this message translates to:
  /// **'이미 가입된 이메일이에요. 로그인해 주세요.'**
  String get signUpEmailTaken;

  /// No description provided for @signUpFailed.
  ///
  /// In ko, this message translates to:
  /// **'회원가입을 하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get signUpFailed;

  /// No description provided for @consentAll.
  ///
  /// In ko, this message translates to:
  /// **'전체 동의'**
  String get consentAll;

  /// No description provided for @consentRequiredTag.
  ///
  /// In ko, this message translates to:
  /// **'[필수]'**
  String get consentRequiredTag;

  /// No description provided for @consentOptionalTag.
  ///
  /// In ko, this message translates to:
  /// **'[선택]'**
  String get consentOptionalTag;

  /// No description provided for @consentView.
  ///
  /// In ko, this message translates to:
  /// **'보기'**
  String get consentView;

  /// No description provided for @consentTerms.
  ///
  /// In ko, this message translates to:
  /// **'이용약관 동의'**
  String get consentTerms;

  /// No description provided for @consentPrivacy.
  ///
  /// In ko, this message translates to:
  /// **'개인정보 수집·이용 동의'**
  String get consentPrivacy;

  /// No description provided for @consentHealth.
  ///
  /// In ko, this message translates to:
  /// **'건강정보(민감정보) 처리 동의'**
  String get consentHealth;

  /// No description provided for @consentHealthDetail.
  ///
  /// In ko, this message translates to:
  /// **'식단·운동 기록, 체중 같은 신체 정보, 건강 목표와 건강상태·주의사항이 여기에 해당해요. 다른 개인정보와 따로 동의를 받아요.'**
  String get consentHealthDetail;

  /// No description provided for @consentAge14.
  ///
  /// In ko, this message translates to:
  /// **'만 14세 이상이에요'**
  String get consentAge14;

  /// No description provided for @consentAge14Detail.
  ///
  /// In ko, this message translates to:
  /// **'만 14세 미만은 가입할 수 없어요.'**
  String get consentAge14Detail;

  /// No description provided for @consentRequiredHint.
  ///
  /// In ko, this message translates to:
  /// **'필수 항목에 모두 동의해야 다음으로 넘어갈 수 있어요.'**
  String get consentRequiredHint;

  /// No description provided for @consentPageTitle.
  ///
  /// In ko, this message translates to:
  /// **'서비스 이용 동의'**
  String get consentPageTitle;

  /// No description provided for @consentPageSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'계속 이용하려면 아래 항목을 확인하고 동의해 주세요.'**
  String get consentPageSubtitle;

  /// No description provided for @consentPageAction.
  ///
  /// In ko, this message translates to:
  /// **'동의하고 계속하기'**
  String get consentPageAction;

  /// No description provided for @consentPageFailed.
  ///
  /// In ko, this message translates to:
  /// **'동의를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get consentPageFailed;

  /// No description provided for @onboardSkip.
  ///
  /// In ko, this message translates to:
  /// **'나중에 하기'**
  String get onboardSkip;

  /// No description provided for @onboardPrevious.
  ///
  /// In ko, this message translates to:
  /// **'이전'**
  String get onboardPrevious;

  /// No description provided for @onboardNext.
  ///
  /// In ko, this message translates to:
  /// **'다음'**
  String get onboardNext;

  /// No description provided for @onboardDone.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get onboardDone;

  /// No description provided for @onboardSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get onboardSaveFailed;

  /// No description provided for @onboardBasicTitle.
  ///
  /// In ko, this message translates to:
  /// **'기본 정보'**
  String get onboardBasicTitle;

  /// No description provided for @onboardBasicSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'맞춤 건강 관리를 위해 기본 정보를 알려주세요.'**
  String get onboardBasicSubtitle;

  /// No description provided for @onboardHeightHint.
  ///
  /// In ko, this message translates to:
  /// **'키 (cm)'**
  String get onboardHeightHint;

  /// No description provided for @onboardWeightHint.
  ///
  /// In ko, this message translates to:
  /// **'체중 (kg)'**
  String get onboardWeightHint;

  /// No description provided for @onboardHealthTitle.
  ///
  /// In ko, this message translates to:
  /// **'건강 목표'**
  String get onboardHealthTitle;

  /// No description provided for @onboardHealthSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'건강 관리에서 더 집중하고 싶은 항목을 선택해 주세요. (최대 2개)'**
  String get onboardHealthSubtitle;

  /// No description provided for @onboardOptionalTag.
  ///
  /// In ko, this message translates to:
  /// **'(선택)'**
  String get onboardOptionalTag;

  /// Spotlight guide: the guide label with the current step (#1857).
  ///
  /// In ko, this message translates to:
  /// **'앱 사용 가이드 {current}/{total}'**
  String guideBadgeWithStep(int current, int total);

  /// Spotlight guide: the screen under the guide is filled with sample data, not the member's own (#1857).
  ///
  /// In ko, this message translates to:
  /// **'예시 화면'**
  String get guideSampleBadge;

  /// Spotlight guide: ends the guide without seeing the rest (#1857).
  ///
  /// In ko, this message translates to:
  /// **'건너뛰기'**
  String get guideSkip;

  /// Spotlight guide: goes back one step (#1857).
  ///
  /// In ko, this message translates to:
  /// **'이전'**
  String get guidePrev;

  /// Spotlight guide: goes to the next step (#1857).
  ///
  /// In ko, this message translates to:
  /// **'다음'**
  String get guideNext;

  /// Spotlight guide: ends the guide on the last step (#1857).
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get guideDone;

  /// Spotlight guide step: the home AI advice card (#1857).
  ///
  /// In ko, this message translates to:
  /// **'오늘의 AI 통합 조언'**
  String get guideHomeAdviceTitle;

  /// Spotlight guide step: the home AI advice card (#1857).
  ///
  /// In ko, this message translates to:
  /// **'식단과 운동을 함께 읽고, 오늘 무엇을 하면 좋을지 짚어 줘요'**
  String get guideHomeAdviceBody;

  /// Spotlight guide step: the center add button (#1857).
  ///
  /// In ko, this message translates to:
  /// **'빠른 기록'**
  String get guideQuickAddTitle;

  /// Spotlight guide step: the center add button (#1857).
  ///
  /// In ko, this message translates to:
  /// **'가운데 + 로 식단과 운동을 어느 화면에서든 바로 추가해요'**
  String get guideQuickAddBody;

  /// Spotlight guide step: the diet tab nutrition summary (#1857).
  ///
  /// In ko, this message translates to:
  /// **'영양 요약'**
  String get guideDietNutritionTitle;

  /// Spotlight guide step: the diet tab nutrition summary (#1857).
  ///
  /// In ko, this message translates to:
  /// **'오늘 먹은 것의 칼로리와 탄단지, 나트륨·당류가 목표까지 얼마나 남았는지 봐요'**
  String get guideDietNutritionBody;

  /// Spotlight guide step: the exercise tab weekly status (#1857).
  ///
  /// In ko, this message translates to:
  /// **'운동 현황'**
  String get guideExerciseStatusTitle;

  /// Spotlight guide step: the exercise tab weekly status (#1857).
  ///
  /// In ko, this message translates to:
  /// **'오늘과 이번 주에 얼마나 움직였는지, 목표까지 얼마나 남았는지 봐요'**
  String get guideExerciseStatusBody;

  /// Spotlight guide step: the exercise tab gym section (#1857).
  ///
  /// In ko, this message translates to:
  /// **'내 헬스장과 트레이너'**
  String get guideGymTitle;

  /// Spotlight guide step: the exercise tab gym section (#1857).
  ///
  /// In ko, this message translates to:
  /// **'연결한 헬스장과 담당 트레이너예요. 트레이너가 짠 운동과 피드백이 앱으로 와요'**
  String get guideGymBody;

  /// Spotlight guide step: the MY tab profile and settings (#1857).
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get guideMySettingsTitle;

  /// Spotlight guide step: the MY tab profile and settings (#1857).
  ///
  /// In ko, this message translates to:
  /// **'프로필과 건강 목표, 알림을 여기서 바꿔요. 이 안내도 여기서 다시 볼 수 있어요'**
  String get guideMySettingsBody;

  /// Spotlight guide step: the MY tab points card (#1857).
  ///
  /// In ko, this message translates to:
  /// **'포인트'**
  String get guidePointsTitle;

  /// Spotlight guide step: the MY tab points card; numbers come from the points rules (#1857).
  ///
  /// In ko, this message translates to:
  /// **'기록하면 포인트가 쌓여요.\n사진으로 식단 기록 +{diet}P(직접 추가는 제외), 운동 직접 기록 +{exercise}P, 개인운동 완료 +{routine}P\n모은 포인트는 MY › 포인트 사용처에서 써요'**
  String guidePointsBody(int diet, int exercise, int routine);

  /// No description provided for @guideSampleFoodScrambledEggs.
  ///
  /// In ko, this message translates to:
  /// **'스크램블에그'**
  String get guideSampleFoodScrambledEggs;

  /// No description provided for @guideSampleFoodWholeWheatToast.
  ///
  /// In ko, this message translates to:
  /// **'통밀 토스트'**
  String get guideSampleFoodWholeWheatToast;

  /// No description provided for @guideSampleFoodChickenSalad.
  ///
  /// In ko, this message translates to:
  /// **'닭가슴살 샐러드'**
  String get guideSampleFoodChickenSalad;

  /// No description provided for @guideSampleFoodBrownRice.
  ///
  /// In ko, this message translates to:
  /// **'현미밥'**
  String get guideSampleFoodBrownRice;

  /// No description provided for @guideSampleFoodGrilledSalmon.
  ///
  /// In ko, this message translates to:
  /// **'연어구이'**
  String get guideSampleFoodGrilledSalmon;

  /// No description provided for @guideSampleFoodRoastedVegetables.
  ///
  /// In ko, this message translates to:
  /// **'구운 채소'**
  String get guideSampleFoodRoastedVegetables;

  /// Onboarding step 1: the basic info step must be filled in (#1830).
  ///
  /// In ko, this message translates to:
  /// **'(필수)'**
  String get onboardRequiredTag;

  /// Onboarding step 1: shown under an empty field after tapping Next (#1830).
  ///
  /// In ko, this message translates to:
  /// **'생년월일을 골라 주세요'**
  String get onboardBirthRequired;

  /// Onboarding step 1: shown under an empty field after tapping Next (#1830).
  ///
  /// In ko, this message translates to:
  /// **'성별을 골라 주세요'**
  String get onboardGenderRequired;

  /// Onboarding step 1: shown under an empty field after tapping Next (#1830).
  ///
  /// In ko, this message translates to:
  /// **'키를 입력해 주세요'**
  String get onboardHeightRequired;

  /// Onboarding step 1: height outside the range the server accepts (#1830).
  ///
  /// In ko, this message translates to:
  /// **'키는 {min}~{max}cm 사이로 입력해 주세요'**
  String onboardHeightRange(int min, int max);

  /// Onboarding step 1: shown under an empty field after tapping Next (#1830).
  ///
  /// In ko, this message translates to:
  /// **'체중을 입력해 주세요'**
  String get onboardWeightRequired;

  /// Onboarding step 1: weight outside the range the server accepts (#1830).
  ///
  /// In ko, this message translates to:
  /// **'체중은 {min}~{max}kg 사이로 입력해 주세요'**
  String onboardWeightRange(int min, int max);

  /// No description provided for @onboardSkipStep.
  ///
  /// In ko, this message translates to:
  /// **'이 단계 건너뛰기'**
  String get onboardSkipStep;

  /// No description provided for @onboardBirthLabel.
  ///
  /// In ko, this message translates to:
  /// **'생년월일'**
  String get onboardBirthLabel;

  /// No description provided for @onboardBirthYearHint.
  ///
  /// In ko, this message translates to:
  /// **'년'**
  String get onboardBirthYearHint;

  /// No description provided for @onboardBirthMonthHint.
  ///
  /// In ko, this message translates to:
  /// **'월'**
  String get onboardBirthMonthHint;

  /// No description provided for @onboardBirthDayHint.
  ///
  /// In ko, this message translates to:
  /// **'일'**
  String get onboardBirthDayHint;

  /// One row of the birth-year dropdown in onboarding step 1.
  ///
  /// In ko, this message translates to:
  /// **'{year}년'**
  String onboardBirthYearValue(int year);

  /// One row of the birth-month dropdown in onboarding step 1.
  ///
  /// In ko, this message translates to:
  /// **'{month}월'**
  String onboardBirthMonthValue(int month);

  /// One row of the birth-day dropdown in onboarding step 1.
  ///
  /// In ko, this message translates to:
  /// **'{day}일'**
  String onboardBirthDayValue(int day);

  /// No description provided for @onboardGenderLabel.
  ///
  /// In ko, this message translates to:
  /// **'성별'**
  String get onboardGenderLabel;

  /// Age chip next to the date-of-birth field in onboarding step 1.
  ///
  /// In ko, this message translates to:
  /// **'만 {age}세'**
  String onboardAgeSummary(int age);

  /// BMI chip in onboarding step 1: the value and its category.
  ///
  /// In ko, this message translates to:
  /// **'BMI {bmi} · {category}'**
  String onboardBmiSummary(String bmi, String category);

  /// No description provided for @onboardBmiUnderweight.
  ///
  /// In ko, this message translates to:
  /// **'저체중'**
  String get onboardBmiUnderweight;

  /// No description provided for @onboardBmiNormal.
  ///
  /// In ko, this message translates to:
  /// **'정상'**
  String get onboardBmiNormal;

  /// No description provided for @onboardBmiPreObese.
  ///
  /// In ko, this message translates to:
  /// **'비만 전단계'**
  String get onboardBmiPreObese;

  /// No description provided for @onboardBmiObese1.
  ///
  /// In ko, this message translates to:
  /// **'1단계 비만'**
  String get onboardBmiObese1;

  /// No description provided for @onboardBmiObese2.
  ///
  /// In ko, this message translates to:
  /// **'2단계 비만'**
  String get onboardBmiObese2;

  /// No description provided for @onboardBmiObese3.
  ///
  /// In ko, this message translates to:
  /// **'3단계 비만'**
  String get onboardBmiObese3;

  /// No description provided for @onboardBmiSourceNote.
  ///
  /// In ko, this message translates to:
  /// **'기준: 대한비만학회 비만 진료지침(아시아·태평양 기준)'**
  String get onboardBmiSourceNote;

  /// No description provided for @onboardDietTitle.
  ///
  /// In ko, this message translates to:
  /// **'식단 목표'**
  String get onboardDietTitle;

  /// No description provided for @onboardDietSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'권장값을 미리 채워 뒀어요. 원하는 값으로 바꿔도 괜찮아요.'**
  String get onboardDietSubtitle;

  /// No description provided for @onboardExerciseTitle.
  ///
  /// In ko, this message translates to:
  /// **'운동 목표'**
  String get onboardExerciseTitle;

  /// No description provided for @onboardExerciseSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'세계보건기구 권고를 기준으로 채워 뒀어요. 원하는 값으로 바꿔도 괜찮아요.'**
  String get onboardExerciseSubtitle;

  /// No description provided for @onboardRecommendedPersonal.
  ///
  /// In ko, this message translates to:
  /// **'나이·성별·키·체중으로 계산한 권장값이에요'**
  String get onboardRecommendedPersonal;

  /// No description provided for @onboardRecommendedFallback.
  ///
  /// In ko, this message translates to:
  /// **'기본 권장값이에요. 1단계에서 생년월일·성별·키·체중을 채우면 더 정확해져요'**
  String get onboardRecommendedFallback;

  /// No description provided for @onboardResetToRecommended.
  ///
  /// In ko, this message translates to:
  /// **'권장값으로 되돌리기'**
  String get onboardResetToRecommended;

  /// No description provided for @onboardDietSourceNote.
  ///
  /// In ko, this message translates to:
  /// **'출처: 2020 한국인 영양소 섭취기준(에너지필요추정량·에너지적정비율) · WHO 나트륨·자유당 섭취 권고'**
  String get onboardDietSourceNote;

  /// No description provided for @onboardExerciseSourceNote.
  ///
  /// In ko, this message translates to:
  /// **'출처: WHO 신체활동 지침(2020) — 주 150분 중강도 유산소, 주 2회 이상 근력'**
  String get onboardExerciseSourceNote;

  /// Shown under goal fields when the picked health goals changed the suggestion.
  ///
  /// In ko, this message translates to:
  /// **'고른 건강 목표를 반영한 값이에요'**
  String get onboardFocusAdjusted;

  /// Sources for the goal-based adjustments.
  ///
  /// In ko, this message translates to:
  /// **'목표 반영 기준: 감량 하루 500kcal(대한비만학회 진료지침) · 근력 단백질 체중 1kg당 1.6g(국제스포츠영양학회) · 당류 총열량 5%(WHO) · 유산소 주 150~300분(WHO)'**
  String get onboardFocusSourceNote;

  /// No description provided for @onboardGenderMale.
  ///
  /// In ko, this message translates to:
  /// **'남성'**
  String get onboardGenderMale;

  /// No description provided for @onboardGenderFemale.
  ///
  /// In ko, this message translates to:
  /// **'여성'**
  String get onboardGenderFemale;

  /// No description provided for @onboardGenderOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get onboardGenderOther;

  /// Greeting bubble the app shows when the coach conversation opens.
  ///
  /// In ko, this message translates to:
  /// **'안녕하세요, AI 건강 코치 온이에요 🙂\n식단·운동 기록을 보고 도와드릴게요. 무엇이든 편하게 물어보세요.'**
  String get aiCoachWelcome;

  /// Bubble shown when the coach reply could not be fetched.
  ///
  /// In ko, this message translates to:
  /// **'앗, 잠시 문제가 생겼어요. 잠시 후 다시 시도해 주세요.'**
  String get aiCoachFailure;

  /// No description provided for @aicResend.
  ///
  /// In ko, this message translates to:
  /// **'다시 보내기'**
  String get aicResend;

  /// No description provided for @aicSendFailedMine.
  ///
  /// In ko, this message translates to:
  /// **'보내지 못했어요 · 길게 누르면 고쳐 쓸 수 있어요'**
  String get aicSendFailedMine;

  /// Generic cancel button in shared dialogs.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get actionCancel;

  /// Generic delete button in shared dialogs.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get actionDelete;

  /// Generic edit action in shared sheets.
  ///
  /// In ko, this message translates to:
  /// **'수정'**
  String get actionEdit;

  /// Generic acknowledge button in shared dialogs.
  ///
  /// In ko, this message translates to:
  /// **'확인'**
  String get actionConfirm;

  /// Tag of a sleep-related AI suggestion.
  ///
  /// In ko, this message translates to:
  /// **'수면'**
  String get coachCardSleepTag;

  /// Title of the health goals sheet.
  ///
  /// In ko, this message translates to:
  /// **'건강 목표'**
  String get myHealthGoalsTitle;

  /// No description provided for @myFirstRunPromptTitle.
  ///
  /// In ko, this message translates to:
  /// **'기본 정보를 입력하면 맞춤 목표를 계산해요'**
  String get myFirstRunPromptTitle;

  /// No description provided for @myFirstRunPromptBody.
  ///
  /// In ko, this message translates to:
  /// **'첫 설정을 건너뛰었어요. 생년월일·키·체중을 넣으면 식단·운동 목표를 몸에 맞게 추천해요.'**
  String get myFirstRunPromptBody;

  /// No description provided for @myFirstRunPromptAction.
  ///
  /// In ko, this message translates to:
  /// **'기본 정보 입력'**
  String get myFirstRunPromptAction;

  /// No description provided for @myGoalsFocusSection.
  ///
  /// In ko, this message translates to:
  /// **'주로 관리하고 싶은 항목'**
  String get myGoalsFocusSection;

  /// No description provided for @myGoalsFocusHint.
  ///
  /// In ko, this message translates to:
  /// **'건강 관리에서 더 집중하고 싶은 항목을 골라 주세요. (최대 2개)'**
  String get myGoalsFocusHint;

  /// MY health goals: who last changed the goal chips and when (#1832).
  ///
  /// In ko, this message translates to:
  /// **'마지막 변경: {who} · {date}'**
  String myGoalsFocusLastChanged(String who, String date);

  /// MY health goals: the goals were last changed by the member's trainer (#1832).
  ///
  /// In ko, this message translates to:
  /// **'트레이너'**
  String get myGoalsFocusChangedByTrainer;

  /// MY health goals: the goals were last changed by the member (#1832).
  ///
  /// In ko, this message translates to:
  /// **'나'**
  String get myGoalsFocusChangedByMe;

  /// No description provided for @healthNotesLabel.
  ///
  /// In ko, this message translates to:
  /// **'건강상태·주의사항'**
  String get healthNotesLabel;

  /// No description provided for @healthNotesHint.
  ///
  /// In ko, this message translates to:
  /// **'예) 왼쪽 무릎 수술 이력, 허리 디스크'**
  String get healthNotesHint;

  /// No description provided for @healthNotesHelper.
  ///
  /// In ko, this message translates to:
  /// **'추천할 때 참고해요'**
  String get healthNotesHelper;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In ko, this message translates to:
  /// **'체중 감량'**
  String get healthFocusWeightLoss;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In ko, this message translates to:
  /// **'근력 향상'**
  String get healthFocusStrength;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In ko, this message translates to:
  /// **'체력 강화'**
  String get healthFocusFitness;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In ko, this message translates to:
  /// **'자세 교정'**
  String get healthFocusPosture;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In ko, this message translates to:
  /// **'재활'**
  String get healthFocusRehab;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In ko, this message translates to:
  /// **'식습관 개선'**
  String get healthFocusEating;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In ko, this message translates to:
  /// **'운동 습관'**
  String get healthFocusExerciseHabit;

  /// Health goal chip in onboarding and MY health goals.
  ///
  /// In ko, this message translates to:
  /// **'혈압 관리'**
  String get healthFocusBloodPressure;

  /// Section label in the health goals sheet.
  ///
  /// In ko, this message translates to:
  /// **'식단 목표'**
  String get myGoalsDietSection;

  /// Section label in the health goals sheet.
  ///
  /// In ko, this message translates to:
  /// **'운동 수치 목표'**
  String get myGoalsExerciseSection;

  /// No description provided for @myGoalBurnDaily.
  ///
  /// In ko, this message translates to:
  /// **'하루 소모 칼로리 (kcal)'**
  String get myGoalBurnDaily;

  /// No description provided for @myGoalCardioWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 유산소 (분)'**
  String get myGoalCardioWeekly;

  /// No description provided for @myGoalStrengthWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 근력 (세트)'**
  String get myGoalStrengthWeekly;

  /// No description provided for @myGoalFlexibilityWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 스트레칭 (분)'**
  String get myGoalFlexibilityWeekly;

  /// No description provided for @myGoalWorkoutsWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 운동 횟수 (일)'**
  String get myGoalWorkoutsWeekly;

  /// No description provided for @myGoalWorkoutsWeeklyHint.
  ///
  /// In ko, this message translates to:
  /// **'주간 운동 챌린지의 목표가 돼요. 정하지 않으면 {days}일이고, 이미 참가한 주의 목표는 바뀌지 않아요.'**
  String myGoalWorkoutsWeeklyHint(int days);

  /// Explains the suggested exercise goals, adjusted for the picked health goals.
  ///
  /// In ko, this message translates to:
  /// **'권장: 하루 {burn}kcal · 주 유산소 {cardio}분 · 근력 {strength}세트 · 스트레칭 {flexibility}분'**
  String myGoalExerciseSuggestionNote(
    int burn,
    int cardio,
    int strength,
    int flexibility,
  );

  /// No description provided for @myGoalExerciseApplySuggestion.
  ///
  /// In ko, this message translates to:
  /// **'권장값으로 채우기'**
  String get myGoalExerciseApplySuggestion;

  /// Health goal field label.
  ///
  /// In ko, this message translates to:
  /// **'하루 칼로리 목표 (kcal)'**
  String get myGoalCalories;

  /// Health goal field label.
  ///
  /// In ko, this message translates to:
  /// **'하루 나트륨 목표 (mg)'**
  String get myGoalSodium;

  /// Health goal field label.
  ///
  /// In ko, this message translates to:
  /// **'하루 당류 목표 (g)'**
  String get myGoalSugar;

  /// Health goal field label.
  ///
  /// In ko, this message translates to:
  /// **'하루 탄수화물 목표 (g)'**
  String get myGoalCarbs;

  /// Health goal field label.
  ///
  /// In ko, this message translates to:
  /// **'하루 단백질 목표 (g)'**
  String get myGoalProtein;

  /// Health goal field label.
  ///
  /// In ko, this message translates to:
  /// **'하루 지방 목표 (g)'**
  String get myGoalFat;

  /// Helper under the calorie goal field when it was derived from the macro fields.
  ///
  /// In ko, this message translates to:
  /// **'탄단지 목표로 계산한 값이에요'**
  String get myGoalCaloriesFromMacros;

  /// Explains the placeholder grams shown in the macro fields.
  ///
  /// In ko, this message translates to:
  /// **'{kcal}kcal 기준 권장 배분: 탄수화물 {carbs}g · 단백질 {protein}g · 지방 {fat}g · 당류 {sugar}g'**
  String myGoalMacroSuggestionNote(
    int kcal,
    int carbs,
    int protein,
    int fat,
    int sugar,
  );

  /// Button that fills the macro fields with the suggested grams.
  ///
  /// In ko, this message translates to:
  /// **'권장값으로 채우기'**
  String get myGoalMacroApplySuggestion;

  /// Edit-mode line under the calorie goal: the daily calories estimated from the member's age, sex, height and weight (same estimate as onboarding). Shown only when all four are known. Pressing the button fills calories and the macro split, which are then saved as real goals.
  ///
  /// In ko, this message translates to:
  /// **'내 정보로 계산한 권장: 하루 {kcal}kcal · 탄·단·지·당류도 이 칼로리에 맞춰 채워요'**
  String myGoalPersonalCaloriesNote(int kcal);

  /// Button that fills the calorie, carbs, protein, fat and sugar goals with the personalized suggestion.
  ///
  /// In ko, this message translates to:
  /// **'권장 칼로리로 채우기'**
  String get myGoalPersonalCaloriesApply;

  /// Footnote under a read-only health-goal card that has fields the member has never set. The number shown is the app-wide baseline in force, not the personalized recommendation the edit form offers.
  ///
  /// In ko, this message translates to:
  /// **'흐린 값은 목표를 세우기 전의 기본 기준이에요'**
  String get myGoalUnsetHint;

  /// Shown after health goals are saved.
  ///
  /// In ko, this message translates to:
  /// **'건강 목표를 저장했어요'**
  String get myGoalsSaved;

  /// Health-goal field outside the range the server accepts (#1888). Shared by the MY goals sheet and onboarding steps 3-4.
  ///
  /// In ko, this message translates to:
  /// **'{min}~{max} 사이로 입력해 주세요'**
  String myGoalRange(int min, int max);

  /// Title of the banner shown when settings fail to load.
  ///
  /// In ko, this message translates to:
  /// **'설정을 불러오지 못했어요'**
  String get mySettingsLoadFailed;

  /// Body of the banner shown when settings fail to load.
  ///
  /// In ko, this message translates to:
  /// **'지금 저장하면 기존 설정이 지워질 수 있어 편집을 잠갔어요.'**
  String get mySettingsLoadFailedBody;

  /// Shown when saving notification settings fails.
  ///
  /// In ko, this message translates to:
  /// **'알림 설정을 저장하지 못했어요'**
  String get myNotificationSaveFailed;

  /// No description provided for @myNotifLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'알림 설정을 불러오지 못했어요'**
  String get myNotifLoadFailed;

  /// No description provided for @myNotifLoadFailedBody.
  ///
  /// In ko, this message translates to:
  /// **'지금 보이는 값은 기본값이라 저장된 설정과 다를 수 있어요'**
  String get myNotifLoadFailedBody;

  /// Title of the points guide dialog.
  ///
  /// In ko, this message translates to:
  /// **'포인트 적립 안내'**
  String get myPointsGuideTitle;

  /// Point-earning action in the points guide.
  ///
  /// In ko, this message translates to:
  /// **'사진으로 식단 기록'**
  String get myPointsDietAdd;

  /// Point-earning action in the points guide: finishing a personal exercise (sent by the trainer or recommended by AI).
  ///
  /// In ko, this message translates to:
  /// **'개인운동 완료'**
  String get myPointsRoutineComplete;

  /// Point-earning action in the points guide.
  ///
  /// In ko, this message translates to:
  /// **'운동 직접 기록'**
  String get myPointsExerciseAdd;

  /// Point-earning action in the points guide with its daily earning limit, e.g. 'Log a meal (up to 3 times a day)'.
  ///
  /// In ko, this message translates to:
  /// **'{action} (하루 {count}회)'**
  String myPointsRuleWithDailyCap(String action, int count);

  /// Section title in the coaching card.
  ///
  /// In ko, this message translates to:
  /// **'개인운동'**
  String get coachRoutineTitle;

  /// Card title when the member has no trainer — every line is AI recommended (#2015).
  ///
  /// In ko, this message translates to:
  /// **'AI 추천 개인운동'**
  String get coachRoutineAiTitle;

  /// Start date in the upcoming personal exercise line under today's list (#3106). ko: 8/22(토), en: Sat 8/22.
  ///
  /// In ko, this message translates to:
  /// **'{month}/{day}({weekday})'**
  String coachUpcomingDate(int month, int day, String weekday);

  /// Start of the upcoming line — personal exercises a trainer sent with a future start date (#3106). Shown in the accent color.
  ///
  /// In ko, this message translates to:
  /// **'{date}부터'**
  String coachUpcomingStarts(String date);

  /// Folds the rest of the upcoming exercise names after the first three (#3106).
  ///
  /// In ko, this message translates to:
  /// **'외 {count}개'**
  String coachUpcomingMore(int count);

  /// Shown after tapping the pencil on a past day's recommended exercises — past checks are allowed and marked as late for the trainer (#2506).
  ///
  /// In ko, this message translates to:
  /// **'빠뜨린 체크를 지금 할 수 있어요. 트레이너에게는 나중에 체크한 것으로 보여요.'**
  String get coachRoutinePastEditHint;

  /// Leaves the past-day check editing mode (#2506).
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get coachRoutinePastEditDone;

  /// Shown after a routine is marked done.
  ///
  /// In ko, this message translates to:
  /// **'운동 기록에 반영했어요'**
  String get coachRoutineLogged;

  /// Shown when the routine is missing.
  ///
  /// In ko, this message translates to:
  /// **'이 개인운동은 더 이상 없어요. 목록을 새로 불러와 주세요'**
  String get coachRoutineGone;

  /// Shown when the network is unavailable.
  ///
  /// In ko, this message translates to:
  /// **'네트워크 연결을 확인하고 다시 시도해 주세요'**
  String get coachRoutineNetworkError;

  /// Shown when marking a routine done fails for an unexpected reason.
  ///
  /// In ko, this message translates to:
  /// **'완료로 기록하지 못했어요.'**
  String get coachRoutineLogFailed;

  /// Marks a routine as completed.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get coachRoutineDone;

  /// No description provided for @coachRoutineUndo.
  ///
  /// In ko, this message translates to:
  /// **'완료 취소'**
  String get coachRoutineUndo;

  /// No description provided for @coachRoutineUndoConfirm.
  ///
  /// In ko, this message translates to:
  /// **'\'{name}\' 완료를 취소할까요? 운동 기록에서도 빠져요.'**
  String coachRoutineUndoConfirm(String name);

  /// No description provided for @coachRoutineUndone.
  ///
  /// In ko, this message translates to:
  /// **'완료를 취소했어요'**
  String get coachRoutineUndone;

  /// No description provided for @coachRoutineUndoFailed.
  ///
  /// In ko, this message translates to:
  /// **'완료를 취소하지 못했어요.'**
  String get coachRoutineUndoFailed;

  /// No description provided for @coachRoutineCancel.
  ///
  /// In ko, this message translates to:
  /// **'이 개인운동 삭제'**
  String get coachRoutineCancel;

  /// Confirm deleting a recommended workout. {nameObj} is the Korean object particle for {name} ('을' or '를', from oncare_rules josa) (#1177).
  ///
  /// In ko, this message translates to:
  /// **'\'{name}\'{nameObj} 목록에서 삭제할까요? 이미 수행한 기록은 그대로 남아요.'**
  String coachRoutineCancelConfirm(String name, String nameObj);

  /// Title of the dialog confirming undoing a completed recommended workout.
  ///
  /// In ko, this message translates to:
  /// **'완료를 취소할까요?'**
  String get coachCardRoutineUndoTitle;

  /// Title of the dialog confirming removal of a recommended workout.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 삭제할까요?'**
  String get coachCardRoutineCancelTitle;

  /// Left button of the cancel/undo confirmation dialogs for a recommended workout; closes the dialog and keeps it as is.
  ///
  /// In ko, this message translates to:
  /// **'유지'**
  String get coachRoutineKeep;

  /// No description provided for @coachRoutineCancelled.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 삭제했어요'**
  String get coachRoutineCancelled;

  /// No description provided for @coachRoutineCancelFailed.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 삭제하지 못했어요'**
  String get coachRoutineCancelFailed;

  /// Title of the completion dialog.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 완료'**
  String get coachRoutineCompleteTitle;

  /// Field label in the completion dialog.
  ///
  /// In ko, this message translates to:
  /// **'수행 강도'**
  String get coachRoutineIntensity;

  /// The intensity the trainer suggests for a routine.
  ///
  /// In ko, this message translates to:
  /// **'권장 {level}'**
  String coachRoutinePlannedIntensity(String level);

  /// Submit button of the completion dialog.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get coachRoutineSubmit;

  /// Opens the chat with the assigned trainer.
  ///
  /// In ko, this message translates to:
  /// **'트레이너에게 메시지'**
  String get coachChatWithTrainer;

  /// Tooltip while the assigned trainer is being fetched.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너를 불러오는 중이에요'**
  String get coachTrainerLoading;

  /// Tooltip when no trainer is assigned yet.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너가 아직 없어요. 운동 탭에서 헬스장·트레이너를 연결해 보세요'**
  String get coachTrainerNone;

  /// Toast from the header chat button when the assigned-trainer lookup failed; tapping also retries (#2843).
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너 정보를 불러오지 못해 다시 불러오고 있어요'**
  String get coachTrainerRetrying;

  /// Notification category badge.
  ///
  /// In ko, this message translates to:
  /// **'리마인더'**
  String get alertCategoryReminder;

  /// Notification category label for screen readers.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 메시지'**
  String get alertCategoryCoachChat;

  /// Notification category label for screen readers.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트'**
  String get alertCategoryCoachReport;

  /// Notification category label for screen readers.
  ///
  /// In ko, this message translates to:
  /// **'개인운동·프로그램'**
  String get alertCategoryRoutine;

  /// Notification category label for screen readers.
  ///
  /// In ko, this message translates to:
  /// **'PT 일정'**
  String get alertCategorySchedule;

  /// Notification category label for screen readers: a finished PT session or the trainer's feedback on it (#3027).
  ///
  /// In ko, this message translates to:
  /// **'PT 기록'**
  String get alertCategoryPtDone;

  /// Notification category label for screen readers.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너'**
  String get alertCategoryTrainer;

  /// Notification category label for screen readers.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청'**
  String get alertCategoryConsultation;

  /// Notification category label for screen readers.
  ///
  /// In ko, this message translates to:
  /// **'건강 목표'**
  String get alertCategoryHealthGoals;

  /// Notification category label for screen readers.
  ///
  /// In ko, this message translates to:
  /// **'혜택'**
  String get alertCategoryBenefits;

  /// Notification category label for screen readers.
  ///
  /// In ko, this message translates to:
  /// **'챌린지'**
  String get alertCategoryChallenge;

  /// Notification category badge.
  ///
  /// In ko, this message translates to:
  /// **'달성'**
  String get alertCategoryAchievement;

  /// Notification category badge.
  ///
  /// In ko, this message translates to:
  /// **'시스템'**
  String get alertCategorySystem;

  /// Marks every notification as read.
  ///
  /// In ko, this message translates to:
  /// **'모두 읽음'**
  String get alertMarkAllRead;

  /// Empty state of the notification list.
  ///
  /// In ko, this message translates to:
  /// **'아직 받은 알림이 없어요'**
  String get alertEmpty;

  /// Shown when the notification list fails to refresh.
  ///
  /// In ko, this message translates to:
  /// **'최신 알림을 불러오지 못했어요'**
  String get alertLoadFailed;

  /// No description provided for @alertMarkAllReadFailed.
  ///
  /// In ko, this message translates to:
  /// **'모두 읽음 처리하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get alertMarkAllReadFailed;

  /// No description provided for @alertCoachChatFailed.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 정보를 불러오지 못해 대화를 열 수 없어요. 잠시 후 다시 시도해 주세요'**
  String get alertCoachChatFailed;

  /// No description provided for @alertCoachChatNoTrainer.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너가 없어 대화를 열 수 없어요'**
  String get alertCoachChatNoTrainer;

  /// Relative time for a notification less than a minute old.
  ///
  /// In ko, this message translates to:
  /// **'방금'**
  String get alertTimeJustNow;

  /// Relative time for a notification under an hour old.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분 전'**
  String alertTimeMinutesAgo(int minutes);

  /// Relative time for a notification under a day old.
  ///
  /// In ko, this message translates to:
  /// **'{hours}시간 전'**
  String alertTimeHoursAgo(int hours);

  /// Relative time for a notification from about a day ago.
  ///
  /// In ko, this message translates to:
  /// **'어제'**
  String get alertTimeYesterday;

  /// Relative time for a notification two or more days old.
  ///
  /// In ko, this message translates to:
  /// **'{days}일 전'**
  String alertTimeDaysAgo(int days);

  /// Title of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'새 개인운동이 왔어요'**
  String get demoAlertRoutineTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'{trainerName} 트레이너가 무릎 상태에 맞춰 걷기 위주 개인운동으로 조정해 보냈어요.'**
  String demoAlertRoutineBody(String trainerName);

  /// Title of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트가 도착했어요'**
  String get demoAlertReportTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'{trainerName} 트레이너가 주간 리포트를 보냈어요.'**
  String demoAlertReportBody(String trainerName);

  /// Title of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'12회차 PT를 마쳤어요'**
  String get demoAlertPtDoneTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'오늘 18:00 {trainerName} 트레이너와 한 PT를 운동 기록에 남겼어요.'**
  String demoAlertPtDoneBody(String trainerName);

  /// Title of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 피드백이 도착했어요'**
  String get demoAlertTrainerFeedbackTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'마무리로 어깨 회전근개 스트레칭을 꼭 해 주세요.'**
  String get demoAlertTrainerFeedbackBody;

  /// Title of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 운동 목표까지 조금 남았어요'**
  String get demoAlertWeeklyGoalTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'저강도 유산소(걷기) 30분부터 채워 봐요.'**
  String get demoAlertWeeklyGoalBody;

  /// Title of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'식단 기록을 꾸준히 이어가고 있어요'**
  String get demoAlertMealStreakTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'보름 넘게 하루도 빠짐없이 식단을 기록하고 있어요.'**
  String get demoAlertMealStreakBody;

  /// Title of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'서비스 점검이 예정돼 있어요'**
  String get demoAlertMaintenanceTitle;

  /// Body of a demo notification shown in tour mode.
  ///
  /// In ko, this message translates to:
  /// **'내일 02:00~03:00에 점검해요.'**
  String get demoAlertMaintenanceBody;

  /// Label above the trainer's feedback.
  ///
  /// In ko, this message translates to:
  /// **'오늘의 피드백'**
  String get exPtFeedbackTitle;

  /// No description provided for @exNextPtSchedule.
  ///
  /// In ko, this message translates to:
  /// **'다음 PT · {when}'**
  String exNextPtSchedule(String when);

  /// No description provided for @exNextPtNone.
  ///
  /// In ko, this message translates to:
  /// **'다음 PT 일정이 아직 없어요'**
  String get exNextPtNone;

  /// Screen title carrying the selected date.
  ///
  /// In ko, this message translates to:
  /// **'{month}월 {day}일 {title}'**
  String exDatedTitle(int month, int day, String title);

  /// No description provided for @a11yChartSummary.
  ///
  /// In ko, this message translates to:
  /// **'{title}. {detail}'**
  String a11yChartSummary(String title, String detail);

  /// No description provided for @a11yChartEmpty.
  ///
  /// In ko, this message translates to:
  /// **'{title}. 기록이 없어요'**
  String a11yChartEmpty(String title);

  /// No description provided for @a11yChartPoint.
  ///
  /// In ko, this message translates to:
  /// **'{day} {value}'**
  String a11yChartPoint(String day, String value);

  /// No description provided for @a11yShowPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 표시'**
  String get a11yShowPassword;

  /// No description provided for @a11yHidePassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 숨기기'**
  String get a11yHidePassword;

  /// No description provided for @a11yOpenCoaching.
  ///
  /// In ko, this message translates to:
  /// **'코칭 조언 열기'**
  String get a11yOpenCoaching;

  /// No description provided for @a11ySendMessage.
  ///
  /// In ko, this message translates to:
  /// **'메시지 보내기'**
  String get a11ySendMessage;

  /// No description provided for @a11yClearSearch.
  ///
  /// In ko, this message translates to:
  /// **'검색어 지우기'**
  String get a11yClearSearch;

  /// No description provided for @a11yRemoveFood.
  ///
  /// In ko, this message translates to:
  /// **'음식 삭제'**
  String get a11yRemoveFood;

  /// No description provided for @a11yPrevWeek.
  ///
  /// In ko, this message translates to:
  /// **'지난주'**
  String get a11yPrevWeek;

  /// No description provided for @a11yNextWeek.
  ///
  /// In ko, this message translates to:
  /// **'다음 주'**
  String get a11yNextWeek;

  /// No description provided for @exConsultHistoryCancelTitle.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청을 취소할까요?'**
  String get exConsultHistoryCancelTitle;

  /// Confirm button of the cancel-consultation dialog. Sits next to Keep, like Cancel booking (#2554).
  ///
  /// In ko, this message translates to:
  /// **'요청 취소'**
  String get exConsultHistoryCancelAction;

  /// No description provided for @exConsultCancelFailed.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청을 취소하지 못했어요. 다시 시도해 주세요.'**
  String get exConsultCancelFailed;

  /// No description provided for @exConsultCancelStale.
  ///
  /// In ko, this message translates to:
  /// **'이미 처리된 요청이에요. 최신 상태로 바꿨어요.'**
  String get exConsultCancelStale;

  /// No description provided for @exConsultHistoryLoadError.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청을 불러오지 못했어요.'**
  String get exConsultHistoryLoadError;

  /// No description provided for @exConsultHistoryCancelBody.
  ///
  /// In ko, this message translates to:
  /// **'취소한 요청은 다시 되돌릴 수 없어요.'**
  String get exConsultHistoryCancelBody;

  /// Title of the confirm dialog when a member cancels a consultation the trainer already accepted, before it starts (#3359).
  ///
  /// In ko, this message translates to:
  /// **'확정된 상담을 취소할까요?'**
  String get exConsultAcceptedCancelTitle;

  /// No description provided for @exConsultAcceptedCancelBody.
  ///
  /// In ko, this message translates to:
  /// **'트레이너에게 취소를 알리고 잡아 둔 시간을 비워요. 취소한 상담은 다시 되돌릴 수 없어요.'**
  String get exConsultAcceptedCancelBody;

  /// Confirm button of the cancel dialog for an accepted consultation. Sits next to Keep.
  ///
  /// In ko, this message translates to:
  /// **'상담 취소'**
  String get exConsultAcceptedCancelAction;

  /// No description provided for @exConsultCancelStarted.
  ///
  /// In ko, this message translates to:
  /// **'시작 시각이 지난 상담은 취소할 수 없어요.'**
  String get exConsultCancelStarted;

  /// Points earned badge on the save toast (shown after a star icon), e.g. +50P.
  ///
  /// In ko, this message translates to:
  /// **'+{points}P'**
  String pointsRewardBadge(int points);

  /// No description provided for @gymLocationDenied.
  ///
  /// In ko, this message translates to:
  /// **'위치 사용을 허용하면 주변 헬스장을 찾을 수 있어요.'**
  String get gymLocationDenied;

  /// No description provided for @gymLocationBrowserBlocked.
  ///
  /// In ko, this message translates to:
  /// **'브라우저 사이트 설정에서 위치 사용을 허용한 뒤 다시 눌러 주세요.'**
  String get gymLocationBrowserBlocked;

  /// No description provided for @gymLocationBlocked.
  ///
  /// In ko, this message translates to:
  /// **'앱 설정에서 위치 사용을 허용한 뒤 다시 눌러 주세요.'**
  String get gymLocationBlocked;

  /// No description provided for @gymLocationDisabled.
  ///
  /// In ko, this message translates to:
  /// **'기기의 위치 서비스를 켠 뒤 다시 눌러 주세요.'**
  String get gymLocationDisabled;

  /// No description provided for @gymLocationUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'현재 위치를 가져오지 못했어요. 다시 시도해 주세요.'**
  String get gymLocationUnavailable;

  /// No description provided for @gymLocateAction.
  ///
  /// In ko, this message translates to:
  /// **'현재 위치로 찾기'**
  String get gymLocateAction;

  /// No description provided for @gymLocationSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get gymLocationSettings;

  /// No description provided for @gymDefaultAreaTitle.
  ///
  /// In ko, this message translates to:
  /// **'신촌 주변 결과예요'**
  String get gymDefaultAreaTitle;

  /// No description provided for @gymDefaultAreaMessage.
  ///
  /// In ko, this message translates to:
  /// **'현재 위치를 허용하면 내 주변으로 바뀌어요.'**
  String get gymDefaultAreaMessage;

  /// No description provided for @gymUseLocation.
  ///
  /// In ko, this message translates to:
  /// **'위치 사용'**
  String get gymUseLocation;

  /// No description provided for @gymDistanceSortNeedsLocation.
  ///
  /// In ko, this message translates to:
  /// **'거리순은 현재 위치를 쓸 때 볼 수 있어요.'**
  String get gymDistanceSortNeedsLocation;

  /// No description provided for @exGymCopyPhone.
  ///
  /// In ko, this message translates to:
  /// **'전화번호 복사'**
  String get exGymCopyPhone;

  /// No description provided for @exGymPhoneCopied.
  ///
  /// In ko, this message translates to:
  /// **'전화번호를 복사했어요.'**
  String get exGymPhoneCopied;

  /// Exercise tab AI advice sentence `record_empty_today` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'오늘 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?'**
  String get exerciseAdviceRecordEmptyToday;

  /// Exercise tab AI advice sentence `record_empty_week` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 운동 기록이 아직 없어요. 10분 걷기부터 시작해 볼까요?'**
  String get exerciseAdviceRecordEmptyWeek;

  /// Exercise tab AI advice sentence `record_empty_all` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'기록이 쌓이면 운동량과 유형의 흐름을 짚어 드릴게요.'**
  String get exerciseAdviceRecordEmptyAll;

  /// Exercise tab AI advice sentence `record_today` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'오늘 {type, select, cardio{유산소} strength{근력} stretching{스트레칭} other{기타}} 위주로 {minutes}분, {calories}kcal 썼어요. 스트레칭으로 마무리해요.'**
  String exerciseAdviceRecordToday(int calories, int minutes, String type);

  /// Exercise tab AI advice sentence `record_week_one_day` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주는 {minutes}분 하루뿐이에요. 한 번 더 나가면 흐름이 이어져요.'**
  String exerciseAdviceRecordWeekOneDay(int minutes);

  /// Exercise tab AI advice sentence `record_week_skew` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 {days}일 {minutes}분이 {top, select, cardio{유산소} strength{근력} stretching{스트레칭} other{기타}}에 몰렸어요. {missing, select, cardio{유산소} strength{근력} stretching{스트레칭} other{기타}}도 섞어 볼까요?'**
  String exerciseAdviceRecordWeekSkew(
    int days,
    int minutes,
    String missing,
    String top,
  );

  /// Exercise tab AI advice sentence `record_week_balanced` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 {days}일 {minutes}분, 유형도 고르게 섞였어요.'**
  String exerciseAdviceRecordWeekBalanced(int days, int minutes);

  /// Exercise tab AI advice sentence `record_all_up` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 운동량이 그 전보다 늘었어요. 지금 방식이 잘 맞아요.'**
  String get exerciseAdviceRecordAllUp;

  /// Exercise tab AI advice sentence `record_all_down` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 운동량이 줄고 있어요. 짧게라도 주 3일을 지켜 봐요.'**
  String get exerciseAdviceRecordAllDown;

  /// Exercise tab AI advice sentence `record_all_steady` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'{weeks}주 동안 {days}일 {minutes}분, 기복 없이 이어가고 있어요.'**
  String exerciseAdviceRecordAllSteady(int days, int minutes, int weeks);

  /// Exercise tab AI advice sentence `routine_today_all_done` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'오늘 개인운동 {count}개를 모두 마쳤어요. 잘했어요!'**
  String exerciseAdviceRoutineTodayAllDone(int count);

  /// Exercise tab AI advice sentence `routine_today_done_next_order` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'{done}{doneObj} 마쳤어요. 다음은 {next} → {then} 순서로 해 보세요.'**
  String exerciseAdviceRoutineTodayDoneNextOrder(
    String done,
    String doneObj,
    String next,
    String then,
  );

  /// Exercise tab AI advice sentence `routine_today_done_next` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'{done}{doneObj} 마쳤어요. 다음은 {next} 차례예요.'**
  String exerciseAdviceRoutineTodayDoneNext(
    String done,
    String doneObj,
    String next,
  );

  /// Exercise tab AI advice sentence `routine_today_next_order` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'다음은 {next} → {then} 순서로 해 보세요.'**
  String exerciseAdviceRoutineTodayNextOrder(String next, String then);

  /// Exercise tab AI advice sentence `routine_today_next` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'다음은 {next} 차례예요.'**
  String exerciseAdviceRoutineTodayNext(String next);

  /// Exercise tab AI advice sentence `routine_today_left` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'남은 개인운동이 {count}개예요. 목록 순서대로 해 보세요.'**
  String exerciseAdviceRoutineTodayLeft(int count);

  /// Exercise tab AI advice sentence `routine_today_start_order` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'오늘 개인운동은 {next} → {then} 순서로 시작해 보세요.'**
  String exerciseAdviceRoutineTodayStartOrder(String next, String then);

  /// Exercise tab AI advice sentence `routine_today_start` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'오늘은 {next}부터 시작해 보세요.'**
  String exerciseAdviceRoutineTodayStart(String next);

  /// Exercise tab AI advice sentence `routine_week_none_today` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주엔 개인운동을 아직 안 했어요. 오늘 {next}부터 해 볼까요?'**
  String exerciseAdviceRoutineWeekNoneToday(String next);

  /// Exercise tab AI advice sentence `routine_week_none_next` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주엔 개인운동을 아직 안 했어요. {next}부터 해 봐요.'**
  String exerciseAdviceRoutineWeekNoneNext(String next);

  /// Exercise tab AI advice sentence `routine_week_none` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주엔 개인운동을 아직 안 했어요. 오늘 하나부터 해 봐요.'**
  String get exerciseAdviceRoutineWeekNone;

  /// Exercise tab AI advice sentence `routine_week_only` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주엔 {top, select, cardio{유산소} strength{근력} stretching{스트레칭} other{기타}} 개인운동만 했어요. {rest, select, next_week{다음 주엔} other{남은 날엔}} {missing, select, cardio{유산소} strength{근력} stretching{스트레칭} other{기타}}부터 해 보세요.'**
  String exerciseAdviceRoutineWeekOnly(String missing, String rest, String top);

  /// Exercise tab AI advice sentence `routine_week_only_short` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주엔 {top, select, cardio{유산소} strength{근력} stretching{스트레칭} other{기타}} 개인운동만 했어요.'**
  String exerciseAdviceRoutineWeekOnlyShort(String top);

  /// Exercise tab AI advice sentence `routine_week_skew` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 개인운동 중 {top, select, cardio{유산소가} strength{근력이} stretching{스트레칭이} other{기타가}} {share}%예요. {rest, select, next_week{다음 주엔} other{남은 날엔}} {missing, select, cardio{유산소} strength{근력} stretching{스트레칭} other{기타}}부터 해 보세요.'**
  String exerciseAdviceRoutineWeekSkew(
    String missing,
    String rest,
    int share,
    String top,
  );

  /// Exercise tab AI advice sentence `routine_week_skew_short` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 개인운동은 {top, select, cardio{유산소가} strength{근력이} stretching{스트레칭이} other{기타가}} {share}%예요.'**
  String exerciseAdviceRoutineWeekSkewShort(int share, String top);

  /// Exercise tab AI advice sentence `routine_week_praise` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 개인운동을 {how, select, even{고르게} other{꾸준히}} 해냈어요. 이대로 이어 가요!'**
  String exerciseAdviceRoutineWeekPraise(String how);

  /// Exercise tab AI advice sentence `routine_week_counts_today` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 개인운동 {assigned}개 중 {completed}개를 했어요. 오늘 {next}부터 이어 가요.'**
  String exerciseAdviceRoutineWeekCountsToday(
    int assigned,
    int completed,
    String next,
  );

  /// Exercise tab AI advice sentence `routine_week_counts_keep` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 개인운동 {assigned}개 중 {completed}개를 했어요. {rest, select, next_week{다음 주도 이어 가요.} other{남은 날도 이어 가요.}}'**
  String exerciseAdviceRoutineWeekCountsKeep(
    int assigned,
    int completed,
    String rest,
  );

  /// Exercise tab AI advice sentence `routine_week_counts` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 개인운동 {assigned}개 중 {completed}개를 했어요.'**
  String exerciseAdviceRoutineWeekCounts(int assigned, int completed);

  /// Exercise tab AI advice sentence `routine_last_week_none_next` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'지난주엔 개인운동을 못 했어요. 이번 주는 {next}부터 해 봐요.'**
  String exerciseAdviceRoutineLastWeekNoneNext(String next);

  /// Exercise tab AI advice sentence `routine_last_week_none` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'지난주엔 개인운동을 못 했어요. 이번 주는 하나씩 해 봐요.'**
  String get exerciseAdviceRoutineLastWeekNone;

  /// Exercise tab AI advice sentence `routine_last_week_only` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'지난주엔 {top, select, cardio{유산소} strength{근력} stretching{스트레칭} other{기타}} 개인운동만 했어요. 이번 주는 {missing, select, cardio{유산소} strength{근력} stretching{스트레칭} other{기타}}부터 해 보세요.'**
  String exerciseAdviceRoutineLastWeekOnly(String missing, String top);

  /// Exercise tab AI advice sentence `routine_last_week_only_short` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'지난주엔 {top, select, cardio{유산소} strength{근력} stretching{스트레칭} other{기타}} 개인운동만 했어요.'**
  String exerciseAdviceRoutineLastWeekOnlyShort(String top);

  /// Exercise tab AI advice sentence `routine_last_week_skew` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'지난주 개인운동 중 {top, select, cardio{유산소가} strength{근력이} stretching{스트레칭이} other{기타가}} {share}%였어요. 이번 주는 {missing, select, cardio{유산소} strength{근력} stretching{스트레칭} other{기타}}부터 해 보세요.'**
  String exerciseAdviceRoutineLastWeekSkew(
    String missing,
    int share,
    String top,
  );

  /// Exercise tab AI advice sentence `routine_last_week_skew_short` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'지난주 개인운동은 {top, select, cardio{유산소가} strength{근력이} stretching{스트레칭이} other{기타가}} {share}%였어요.'**
  String exerciseAdviceRoutineLastWeekSkewShort(int share, String top);

  /// Exercise tab AI advice sentence `routine_last_week_praise` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'지난주 개인운동을 {how, select, even{고르게} other{꾸준히}} 해냈어요. 이번 주도 이어 가요!'**
  String exerciseAdviceRoutineLastWeekPraise(String how);

  /// Exercise tab AI advice sentence `routine_last_week_counts_more` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'지난주 개인운동 {assigned}개 중 {completed}개를 했어요. 이번 주는 더 채워 봐요.'**
  String exerciseAdviceRoutineLastWeekCountsMore(int assigned, int completed);

  /// Exercise tab AI advice sentence `routine_last_week_counts` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'지난주 개인운동 {assigned}개 중 {completed}개를 했어요.'**
  String exerciseAdviceRoutineLastWeekCounts(int assigned, int completed);

  /// Exercise tab AI advice sentence `routine_all_new` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 받은 지 {days}일째예요. 일주일 뒤 빠진 운동을 짚어 드릴게요.'**
  String exerciseAdviceRoutineAllNew(int days);

  /// Exercise tab AI advice sentence `routine_all_none_next` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 받은 지 {days}일째예요. 오늘 {next}부터 시작해 볼까요?'**
  String exerciseAdviceRoutineAllNoneNext(int days, String next);

  /// Exercise tab AI advice sentence `routine_all_none` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 받은 지 {days}일째예요. 오늘 하나부터 시작해 봐요.'**
  String exerciseAdviceRoutineAllNone(int days);

  /// Exercise tab AI advice sentence `routine_all_done_today_part` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'자주 빠지던 {part, select, lower{하체} upper{상체} core{코어} full{전신} other{전신}} 운동을 오늘 해냈어요. 이대로 이어 가요!'**
  String exerciseAdviceRoutineAllDoneTodayPart(String part);

  /// Exercise tab AI advice sentence `routine_all_done_today_name` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'자주 빠지던 {name}{nameObj} 오늘 해냈어요. 이대로 이어 가요!'**
  String exerciseAdviceRoutineAllDoneTodayName(String name, String nameObj);

  /// Exercise tab AI advice sentence `routine_all_done_today_name_plain` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'자주 빠지던 {name}, 오늘 해냈어요. 이대로 이어 가요!'**
  String exerciseAdviceRoutineAllDoneTodayNamePlain(String name);

  /// Exercise tab AI advice sentence `routine_all_done_today` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'자주 빠지던 운동을 오늘 해냈어요. 이대로 이어 가요!'**
  String get exerciseAdviceRoutineAllDoneToday;

  /// Exercise tab AI advice sentence `routine_all_missed_part` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 중 {part, select, lower{하체} upper{상체} core{코어} full{전신} other{전신}} 운동이 자주 빠졌어요. {part, select, lower{하체} upper{상체} core{코어} full{전신} other{전신}} 운동을 먼저 해 볼까요?'**
  String exerciseAdviceRoutineAllMissedPart(String part);

  /// Exercise tab AI advice sentence `routine_all_missed_part_short` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'{part, select, lower{하체} upper{상체} core{코어} full{전신} other{전신}} 개인운동이 자주 빠졌어요. 먼저 하는 순서로 바꿔 볼까요?'**
  String exerciseAdviceRoutineAllMissedPartShort(String part);

  /// Exercise tab AI advice sentence `routine_all_missed_name` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 중 {name}{nameSubj} 자주 빠졌어요. 다음엔 먼저 해 볼까요?'**
  String exerciseAdviceRoutineAllMissedName(String name, String nameSubj);

  /// Exercise tab AI advice sentence `routine_all_missed_name_short` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'{name}{nameSubj} 자주 빠졌어요. 먼저 해 볼까요?'**
  String exerciseAdviceRoutineAllMissedNameShort(String name, String nameSubj);

  /// Exercise tab AI advice sentence `routine_all_missed_name_plain` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 {name}, 자주 빠졌어요. 다음엔 먼저 해 볼까요?'**
  String exerciseAdviceRoutineAllMissedNamePlain(String name);

  /// Exercise tab AI advice sentence `routine_all_missed_name_plain_short` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'{name}, 자주 빠졌어요. 먼저 해 볼까요?'**
  String exerciseAdviceRoutineAllMissedNamePlainShort(String name);

  /// Exercise tab AI advice sentence `routine_all_missed` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'자주 빠진 개인운동이 있어요. 목록 순서를 바꿔 볼까요?'**
  String get exerciseAdviceRoutineAllMissed;

  /// Exercise tab AI advice sentence `routine_all_praise` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 {weeks}주째 꾸준히 하고 있어요. 앞으로도 화이팅!'**
  String exerciseAdviceRoutineAllPraise(int weeks);

  /// Exercise tab AI advice sentence `routine_all_rate` (#2210). The server sends this key and its params; the Korean copy must match backend exercise_advice._KO.
  ///
  /// In ko, this message translates to:
  /// **'지금 개인운동의 {pct}%를 했어요. 빠지는 날 없이 이어 가 봐요.'**
  String exerciseAdviceRoutineAllRate(int pct);

  /// Diet tab AI advice sentence `today_empty` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'오늘 식단 기록이 아직 없어요.'**
  String get dietAdviceTodayEmpty;

  /// Diet tab AI advice sentence `today_missing_meal` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'적지 않은 끼니가 있나요?'**
  String get dietAdviceTodayMissingMeal;

  /// Diet tab AI advice sentence `today_sodium_over` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'나트륨 **{sodiumMg}mg**, 목표 초과예요.'**
  String dietAdviceTodaySodiumOver(int sodiumMg);

  /// Diet tab AI advice sentence `today_calorie_over` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'오늘 **{kcal}kcal**, 목표 초과예요.'**
  String dietAdviceTodayCalorieOver(int kcal);

  /// Diet tab AI advice sentence `today_protein_left` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'단백질 **{proteinG}g** 더 필요해요.'**
  String dietAdviceTodayProteinLeft(int proteinG);

  /// Diet tab AI advice sentence `today_balanced` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'오늘 **{kcal}kcal**, 균형이 좋아요.'**
  String dietAdviceTodayBalanced(int kcal);

  /// Diet tab AI advice sentence `next_meal` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'{slot, select, breakfast{아침} lunch{점심} dinner{저녁} other{끼니}}은 **{menu}** 어때요?'**
  String dietAdviceNextMeal(String slot, String menu);

  /// Diet tab AI advice sentence `next_snack` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'간식으로 **{menu}** 어때요?'**
  String dietAdviceNextSnack(String menu);

  /// Diet tab AI advice sentence `today_done` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'오늘 식단을 잘 마무리했어요!'**
  String get dietAdviceTodayDone;

  /// Diet tab AI advice sentence `today_log_first` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'기록하면 다음 메뉴를 골라 드릴게요.'**
  String get dietAdviceTodayLogFirst;

  /// Diet tab AI advice sentence `week_empty` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 식단 기록이 아직 없어요.'**
  String get dietAdviceWeekEmpty;

  /// Diet tab AI advice sentence `week_skip_breakfast` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 아침을 **{days}번** 걸렀어요.'**
  String dietAdviceWeekSkipBreakfast(String scope, int days);

  /// Diet tab AI advice sentence `week_skip_breakfast_snack` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 아침 거른 {days}일 중 **{snackDays}일** 간식을 드셨어요.'**
  String dietAdviceWeekSkipBreakfastSnack(
    String scope,
    int days,
    int snackDays,
  );

  /// Diet tab AI advice sentence `week_focus_sodium` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 나트륨을 **{days}일** 넘겼어요.'**
  String dietAdviceWeekFocusSodium(String scope, int days);

  /// Diet tab AI advice sentence `week_focus_calorie` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 칼로리 목표를 **{days}일** 넘겼어요.'**
  String dietAdviceWeekFocusCalorie(String scope, int days);

  /// Diet tab AI advice sentence `week_focus_sugar` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 당류를 **{days}일** 넘겼어요.'**
  String dietAdviceWeekFocusSugar(String scope, int days);

  /// Diet tab AI advice sentence `week_focus_protein` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 단백질이 **{days}일** 부족했어요.'**
  String dietAdviceWeekFocusProtein(String scope, int days);

  /// Diet tab AI advice sentence `week_good` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 기록한 **{days}일** 모두 목표 안이에요.'**
  String dietAdviceWeekGood(String scope, int days);

  /// Diet tab AI advice sentence `week_empty_hint` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'한 끼만 남겨도 흐름이 보여요.'**
  String get dietAdviceWeekEmptyHint;

  /// Diet tab AI advice sentence `tip_breakfast` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'삶은 달걀로 아침을 챙겨요.'**
  String get dietAdviceTipBreakfast;

  /// Diet tab AI advice sentence `tip_sodium` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'국물은 남기고 건더기 위주로 드세요.'**
  String get dietAdviceTipSodium;

  /// Diet tab AI advice sentence `tip_calorie` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'저녁 양을 조금만 줄여 봐요.'**
  String get dietAdviceTipCalorie;

  /// Diet tab AI advice sentence `tip_sugar` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'단 음료 대신 물이나 차를 드세요.'**
  String get dietAdviceTipSugar;

  /// Diet tab AI advice sentence `tip_protein` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'끼니마다 달걀·두부를 더해 봐요.'**
  String get dietAdviceTipProtein;

  /// Diet tab AI advice sentence `tip_keep` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'지금 흐름을 그대로 이어 가요!'**
  String get dietAdviceTipKeep;

  /// Diet tab AI advice sentence `all_few_records` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 기록이 **{days}일**이에요.'**
  String dietAdviceAllFewRecords(int days);

  /// Diet tab AI advice sentence `all_slot_sodium` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 {slot, select, breakfast{아침} lunch{점심} dinner{저녁} other{끼니}} 나트륨이 **{days}번** 높았어요.'**
  String dietAdviceAllSlotSodium(String slot, int days);

  /// Diet tab AI advice sentence `all_carb_heavy` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 탄수화물 비중이 **{pct}%**예요.'**
  String dietAdviceAllCarbHeavy(int pct);

  /// Diet tab AI advice sentence `all_protein_light` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 단백질 비중이 **{pct}%**로 낮아요.'**
  String dietAdviceAllProteinLight(int pct);

  /// Diet tab AI advice sentence `all_protein_trend_up` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'단백질 목표 달성일이 **{before}일→{after}일**로 늘었어요.'**
  String dietAdviceAllProteinTrendUp(int before, int after);

  /// Diet tab AI advice sentence `all_protein_trend_down` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'단백질 목표 달성일이 **{before}일→{after}일**로 줄었어요.'**
  String dietAdviceAllProteinTrendDown(int before, int after);

  /// Diet tab AI advice sentence `all_frequent_menu` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'4주간 {slot, select, breakfast{아침} lunch{점심} dinner{저녁} other{끼니}} 1위 메뉴는 **{food}**({count}회)예요.'**
  String dietAdviceAllFrequentMenu(String slot, String food, int count);

  /// Diet tab AI advice sentence `all_repeated_foods` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'4주간 **{food1}·{food2}** 비중이 높아요.'**
  String dietAdviceAllRepeatedFoods(String food1, String food2);

  /// Diet tab AI advice sentence `all_good` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 **{days}일** 기록, 흐름이 좋아요.'**
  String dietAdviceAllGood(int days);

  /// Diet tab AI advice sentence `all_few_hint` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'7일이 넘으면 흐름을 짚어 드릴게요.'**
  String get dietAdviceAllFewHint;

  /// Diet tab AI advice sentence `tip_carb` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'밥 양을 줄이고 반찬을 늘려 봐요.'**
  String get dietAdviceTipCarb;

  /// Diet tab AI advice sentence `tip_swap` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'곁들임 반찬만 바꿔 봐요.'**
  String get dietAdviceTipSwap;

  /// Diet tab AI advice sentence `tip_variety` (#2255). The server sends this key and its params; the Korean copy must match backend diet_advice_copy._KO. Text inside ** marks emphasis; the card strips the marks and shows plain text.
  ///
  /// In ko, this message translates to:
  /// **'생선·두부를 주 2회 더해요.'**
  String get dietAdviceTipVariety;

  /// No description provided for @weeklyFeedbackSheetTitle.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 어땠어요?'**
  String get weeklyFeedbackSheetTitle;

  /// No description provided for @weeklyFeedbackSheetSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'{range} 한 주를 담당 트레이너에게 알려 주세요'**
  String weeklyFeedbackSheetSubtitle(String range);

  /// No description provided for @weeklyFeedbackWhy.
  ///
  /// In ko, this message translates to:
  /// **'30초면 끝나요. 다음 주 운동 강도가 이 답에서 정해져요.'**
  String get weeklyFeedbackWhy;

  /// No description provided for @weeklyFeedbackConditionQuestion.
  ///
  /// In ko, this message translates to:
  /// **'한 주 컨디션은 어땠나요?'**
  String get weeklyFeedbackConditionQuestion;

  /// No description provided for @weeklyFeedbackIntensityQuestion.
  ///
  /// In ko, this message translates to:
  /// **'운동 강도는 어땠나요?'**
  String get weeklyFeedbackIntensityQuestion;

  /// No description provided for @weeklyFeedbackPainQuestion.
  ///
  /// In ko, this message translates to:
  /// **'아팠던 곳이 있나요?'**
  String get weeklyFeedbackPainQuestion;

  /// No description provided for @weeklyFeedbackPainHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 오른 무릎'**
  String get weeklyFeedbackPainHint;

  /// No description provided for @weeklyFeedbackPainDateLabel.
  ///
  /// In ko, this message translates to:
  /// **'아팠던 날'**
  String get weeklyFeedbackPainDateLabel;

  /// No description provided for @weeklyFeedbackPainDatePick.
  ///
  /// In ko, this message translates to:
  /// **'날짜 고르기'**
  String get weeklyFeedbackPainDatePick;

  /// No description provided for @weeklyFeedbackNoteQuestion.
  ///
  /// In ko, this message translates to:
  /// **'트레이너에게 한 줄 피드백 (선택)'**
  String get weeklyFeedbackNoteQuestion;

  /// No description provided for @weeklyFeedbackNoteHint.
  ///
  /// In ko, this message translates to:
  /// **'그 주에 있었던 일을 적어 주세요'**
  String get weeklyFeedbackNoteHint;

  /// No description provided for @weeklyFeedbackSend.
  ///
  /// In ko, this message translates to:
  /// **'보내기'**
  String get weeklyFeedbackSend;

  /// No description provided for @weeklyFeedbackResend.
  ///
  /// In ko, this message translates to:
  /// **'다시 보내기'**
  String get weeklyFeedbackResend;

  /// No description provided for @weeklyFeedbackLater.
  ///
  /// In ko, this message translates to:
  /// **'나중에'**
  String get weeklyFeedbackLater;

  /// No description provided for @weeklyFeedbackIncomplete.
  ///
  /// In ko, this message translates to:
  /// **'컨디션과 운동 강도를 골라 주세요'**
  String get weeklyFeedbackIncomplete;

  /// No description provided for @weeklyFeedbackSent.
  ///
  /// In ko, this message translates to:
  /// **'주간 피드백을 보냈어요'**
  String get weeklyFeedbackSent;

  /// No description provided for @weeklyFeedbackSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'주간 피드백을 보내지 못했어요. 다시 시도해 주세요'**
  String get weeklyFeedbackSendFailed;

  /// No description provided for @weeklyFeedbackSendUnassigned.
  ///
  /// In ko, this message translates to:
  /// **'담당이 해제되어 주간 피드백을 보낼 수 없어요'**
  String get weeklyFeedbackSendUnassigned;

  /// No description provided for @weeklyFeedbackSendRejected.
  ///
  /// In ko, this message translates to:
  /// **'이 주에는 주간 피드백을 보낼 수 없어요'**
  String get weeklyFeedbackSendRejected;

  /// No description provided for @weeklyFeedbackAlreadySent.
  ///
  /// In ko, this message translates to:
  /// **'이미 보낸 주예요. 다시 보내면 마지막 답으로 바뀌어요.'**
  String get weeklyFeedbackAlreadySent;

  /// No description provided for @weekConditionGreat.
  ///
  /// In ko, this message translates to:
  /// **'아주 좋았어요'**
  String get weekConditionGreat;

  /// No description provided for @weekConditionGood.
  ///
  /// In ko, this message translates to:
  /// **'좋았어요'**
  String get weekConditionGood;

  /// No description provided for @weekConditionOk.
  ///
  /// In ko, this message translates to:
  /// **'보통이었어요'**
  String get weekConditionOk;

  /// No description provided for @weekConditionTired.
  ///
  /// In ko, this message translates to:
  /// **'지쳤어요'**
  String get weekConditionTired;

  /// No description provided for @weekConditionBad.
  ///
  /// In ko, this message translates to:
  /// **'많이 안 좋았어요'**
  String get weekConditionBad;

  /// No description provided for @weekIntensityTooEasy.
  ///
  /// In ko, this message translates to:
  /// **'너무 쉬웠어요'**
  String get weekIntensityTooEasy;

  /// No description provided for @weekIntensityRight.
  ///
  /// In ko, this message translates to:
  /// **'딱 맞았어요'**
  String get weekIntensityRight;

  /// No description provided for @weekIntensityHard.
  ///
  /// In ko, this message translates to:
  /// **'조금 힘들었어요'**
  String get weekIntensityHard;

  /// No description provided for @weekIntensityTooHard.
  ///
  /// In ko, this message translates to:
  /// **'너무 힘들었어요'**
  String get weekIntensityTooHard;

  /// No description provided for @myCoachReportsEntry.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트'**
  String get myCoachReportsEntry;

  /// No description provided for @myCoachReportsEntryHint.
  ///
  /// In ko, this message translates to:
  /// **'받은 리포트와 보낸 주간 피드백'**
  String get myCoachReportsEntryHint;

  /// No description provided for @coachReportsSectionTitle.
  ///
  /// In ko, this message translates to:
  /// **'받은 리포트'**
  String get coachReportsSectionTitle;

  /// No description provided for @coachReportsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 받은 리포트가 없어요'**
  String get coachReportsEmpty;

  /// No description provided for @coachReportsEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'담당 트레이너가 주간 리포트를 보내면 여기에 쌓여요'**
  String get coachReportsEmptyHint;

  /// No description provided for @coachReportsLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'받은 리포트를 불러오지 못했어요'**
  String get coachReportsLoadFailed;

  /// No description provided for @coachReportsLoadMore.
  ///
  /// In ko, this message translates to:
  /// **'이전 리포트 더 보기'**
  String get coachReportsLoadMore;

  /// No description provided for @weeklyFeedbackLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'보낸 주간 피드백을 불러오지 못했어요'**
  String get weeklyFeedbackLoadFailed;

  /// No description provided for @coachReportSentOn.
  ///
  /// In ko, this message translates to:
  /// **'{month}월 {day}일 보냄'**
  String coachReportSentOn(int month, int day);

  /// No description provided for @coachReportSentBy.
  ///
  /// In ko, this message translates to:
  /// **'{name} · {sentOn}'**
  String coachReportSentBy(String name, String sentOn);

  /// No description provided for @myWeeklyFeedbackSectionTitle.
  ///
  /// In ko, this message translates to:
  /// **'보낸 주간 피드백'**
  String get myWeeklyFeedbackSectionTitle;

  /// No description provided for @myWeeklyFeedbackOnlyLastWeek.
  ///
  /// In ko, this message translates to:
  /// **'직전 주에 보낸 답만 보여 드려요'**
  String get myWeeklyFeedbackOnlyLastWeek;

  /// No description provided for @myWeeklyFeedbackEmpty.
  ///
  /// In ko, this message translates to:
  /// **'직전 주 피드백을 아직 보내지 않았어요'**
  String get myWeeklyFeedbackEmpty;

  /// No description provided for @myWeeklyFeedbackConditionLabel.
  ///
  /// In ko, this message translates to:
  /// **'컨디션'**
  String get myWeeklyFeedbackConditionLabel;

  /// No description provided for @myWeeklyFeedbackIntensityLabel.
  ///
  /// In ko, this message translates to:
  /// **'운동 강도'**
  String get myWeeklyFeedbackIntensityLabel;

  /// No description provided for @myWeeklyFeedbackPainLabel.
  ///
  /// In ko, this message translates to:
  /// **'통증'**
  String get myWeeklyFeedbackPainLabel;

  /// No description provided for @myWeeklyFeedbackPainNone.
  ///
  /// In ko, this message translates to:
  /// **'없음'**
  String get myWeeklyFeedbackPainNone;

  /// No description provided for @myWeeklyFeedbackPainWithDate.
  ///
  /// In ko, this message translates to:
  /// **'{area} ({month}월 {day}일)'**
  String myWeeklyFeedbackPainWithDate(String area, int month, int day);

  /// No description provided for @myWeeklyFeedbackNoteLabel.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 피드백'**
  String get myWeeklyFeedbackNoteLabel;

  /// No description provided for @myWeeklyFeedbackSentAt.
  ///
  /// In ko, this message translates to:
  /// **'{month}월 {day}일 보냄'**
  String myWeeklyFeedbackSentAt(int month, int day);

  /// No description provided for @weeklyFeedbackNowButton.
  ///
  /// In ko, this message translates to:
  /// **'지금 피드백 보내기'**
  String get weeklyFeedbackNowButton;

  /// No description provided for @authForgotPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 찾기'**
  String get authForgotPassword;

  /// Text button next to 'Forgot your password?' on sign-in that opens the find-email screen.
  ///
  /// In ko, this message translates to:
  /// **'이메일 찾기'**
  String get authFindEmail;

  /// No description provided for @findEmailTitle.
  ///
  /// In ko, this message translates to:
  /// **'이메일 찾기'**
  String get findEmailTitle;

  /// No description provided for @findEmailSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'가입할 때 입력한 이름과 휴대폰 번호로 가입 이메일을 찾아요.'**
  String get findEmailSubtitle;

  /// No description provided for @findEmailAction.
  ///
  /// In ko, this message translates to:
  /// **'이메일 찾기'**
  String get findEmailAction;

  /// No description provided for @findEmailFoundSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'입력한 정보로 가입한 계정이에요.'**
  String get findEmailFoundSubtitle;

  /// No description provided for @findEmailMaskedNote.
  ///
  /// In ko, this message translates to:
  /// **'개인정보 보호를 위해 이메일 일부를 가렸어요.'**
  String get findEmailMaskedNote;

  /// Find-email result for an account that signs in through a social provider only. provider is findEmailProviderKakao / Google / Other.
  ///
  /// In ko, this message translates to:
  /// **'{provider} 계정으로 가입했어요'**
  String findEmailSocialTitle(String provider);

  /// No description provided for @findEmailSocialBody.
  ///
  /// In ko, this message translates to:
  /// **'로그인 화면에서 가입한 방법으로 로그인해 주세요.'**
  String get findEmailSocialBody;

  /// No description provided for @findEmailProviderKakao.
  ///
  /// In ko, this message translates to:
  /// **'카카오'**
  String get findEmailProviderKakao;

  /// No description provided for @findEmailProviderGoogle.
  ///
  /// In ko, this message translates to:
  /// **'구글'**
  String get findEmailProviderGoogle;

  /// No description provided for @findEmailProviderOther.
  ///
  /// In ko, this message translates to:
  /// **'소셜'**
  String get findEmailProviderOther;

  /// No description provided for @findEmailNotFoundTitle.
  ///
  /// In ko, this message translates to:
  /// **'일치하는 계정을 찾지 못했어요'**
  String get findEmailNotFoundTitle;

  /// No description provided for @findEmailNotFoundBody.
  ///
  /// In ko, this message translates to:
  /// **'이름과 휴대폰 번호를 다시 확인해 주세요. 가입할 때 번호를 넣지 않았거나 나중에 바꿨다면 찾을 수 없어요.'**
  String get findEmailNotFoundBody;

  /// No description provided for @findEmailRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 찾기'**
  String get findEmailRetry;

  /// No description provided for @passwordChangeTitle.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 변경'**
  String get passwordChangeTitle;

  /// No description provided for @passwordChangeCurrentHint.
  ///
  /// In ko, this message translates to:
  /// **'현재 비밀번호'**
  String get passwordChangeCurrentHint;

  /// No description provided for @passwordChangeNewHint.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호 (영문·숫자 포함 8자 이상)'**
  String get passwordChangeNewHint;

  /// No description provided for @passwordChangeConfirmHint.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호 확인'**
  String get passwordChangeConfirmHint;

  /// No description provided for @passwordChangeNote.
  ///
  /// In ko, this message translates to:
  /// **'이 기기는 로그인이 유지되고, 다른 기기에서는 다시 로그인해야 해요.'**
  String get passwordChangeNote;

  /// No description provided for @passwordChangeAction.
  ///
  /// In ko, this message translates to:
  /// **'변경'**
  String get passwordChangeAction;

  /// No description provided for @passwordChangeDone.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 바꿨어요'**
  String get passwordChangeDone;

  /// No description provided for @passwordChangeWrongCurrent.
  ///
  /// In ko, this message translates to:
  /// **'현재 비밀번호가 맞지 않아요'**
  String get passwordChangeWrongCurrent;

  /// No description provided for @passwordChangeSameAsCurrent.
  ///
  /// In ko, this message translates to:
  /// **'현재와 다른 비밀번호를 입력해 주세요'**
  String get passwordChangeSameAsCurrent;

  /// No description provided for @passwordChangeDemoTitle.
  ///
  /// In ko, this message translates to:
  /// **'데모 계정은 비밀번호를 바꿀 수 없어요'**
  String get passwordChangeDemoTitle;

  /// No description provided for @passwordChangeDemoBody.
  ///
  /// In ko, this message translates to:
  /// **'데모 모드에는 서버 계정이 없어요. 실제 계정으로 로그인하면 여기서 바꿀 수 있어요.'**
  String get passwordChangeDemoBody;

  /// No description provided for @passwordChangeSocialTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 계정에는 비밀번호가 없어요'**
  String get passwordChangeSocialTitle;

  /// No description provided for @passwordChangeSocialBody.
  ///
  /// In ko, this message translates to:
  /// **'카카오·구글로 로그인한 계정은 그 서비스에서 계정을 관리해요.'**
  String get passwordChangeSocialBody;

  /// No description provided for @passwordTooManyAttempts.
  ///
  /// In ko, this message translates to:
  /// **'시도가 너무 많아요. 잠시 후 다시 시도해 주세요.'**
  String get passwordTooManyAttempts;

  /// No description provided for @passwordTemporaryFailure.
  ///
  /// In ko, this message translates to:
  /// **'요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get passwordTemporaryFailure;

  /// No description provided for @passwordResetTitle.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 재설정'**
  String get passwordResetTitle;

  /// No description provided for @passwordResetRequestSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'가입한 이메일로 재설정 코드를 보내 드려요.'**
  String get passwordResetRequestSubtitle;

  /// No description provided for @passwordResetSendAction.
  ///
  /// In ko, this message translates to:
  /// **'코드 받기'**
  String get passwordResetSendAction;

  /// No description provided for @passwordResetHaveCode.
  ///
  /// In ko, this message translates to:
  /// **'이미 코드가 있어요'**
  String get passwordResetHaveCode;

  /// No description provided for @passwordResetSentTitle.
  ///
  /// In ko, this message translates to:
  /// **'메일을 확인해 주세요'**
  String get passwordResetSentTitle;

  /// Shown after a reset request. Same text whether or not the account exists.
  ///
  /// In ko, this message translates to:
  /// **'{email} 로 가입된 계정이 있다면 {minutes}분 동안 한 번 쓸 수 있는 코드를 보냈어요.'**
  String passwordResetSentBody(String email, int minutes);

  /// No description provided for @passwordResetConfirmSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'메일로 받은 코드와 새 비밀번호를 입력해 주세요.'**
  String get passwordResetConfirmSubtitle;

  /// No description provided for @passwordResetSocialNote.
  ///
  /// In ko, this message translates to:
  /// **'카카오·구글 같은 소셜 로그인으로 가입했다면 메일이 오지 않아요. 가입한 방법으로 로그인해 주세요.'**
  String get passwordResetSocialNote;

  /// No description provided for @passwordResetCodeHint.
  ///
  /// In ko, this message translates to:
  /// **'재설정 코드 16자리'**
  String get passwordResetCodeHint;

  /// No description provided for @passwordResetCodeEmpty.
  ///
  /// In ko, this message translates to:
  /// **'코드를 입력해 주세요'**
  String get passwordResetCodeEmpty;

  /// No description provided for @passwordResetCodeMalformed.
  ///
  /// In ko, this message translates to:
  /// **'메일에 적힌 16자리 코드를 입력해 주세요'**
  String get passwordResetCodeMalformed;

  /// No description provided for @passwordResetCodeInvalid.
  ///
  /// In ko, this message translates to:
  /// **'코드가 맞지 않거나 만료됐어요. 코드를 다시 받아 주세요.'**
  String get passwordResetCodeInvalid;

  /// No description provided for @passwordResetConfirmAction.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호 저장'**
  String get passwordResetConfirmAction;

  /// No description provided for @passwordResetResend.
  ///
  /// In ko, this message translates to:
  /// **'코드 다시 받기'**
  String get passwordResetResend;

  /// No description provided for @passwordResetDemoNote.
  ///
  /// In ko, this message translates to:
  /// **'데모 모드에서는 메일이 가지 않아요. 코드 칸을 미리 채워 두었어요.'**
  String get passwordResetDemoNote;

  /// No description provided for @passwordResetUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'지금은 재설정 메일을 보낼 수 없어요. 고객 지원으로 문의해 주세요.'**
  String get passwordResetUnavailable;

  /// No description provided for @passwordResetDoneTitle.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 바꿨어요'**
  String get passwordResetDoneTitle;

  /// No description provided for @passwordResetDoneBody.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호로 다시 로그인해 주세요. 모든 기기의 로그인이 끝났어요.'**
  String get passwordResetDoneBody;

  /// No description provided for @passwordResetBackToSignIn.
  ///
  /// In ko, this message translates to:
  /// **'로그인하러 가기'**
  String get passwordResetBackToSignIn;

  /// No description provided for @signUpEmailCodeSend.
  ///
  /// In ko, this message translates to:
  /// **'인증 코드 받기'**
  String get signUpEmailCodeSend;

  /// No description provided for @signUpEmailCodeHint.
  ///
  /// In ko, this message translates to:
  /// **'인증 코드'**
  String get signUpEmailCodeHint;

  /// No description provided for @signUpEmailCodeResend.
  ///
  /// In ko, this message translates to:
  /// **'다시 받기'**
  String get signUpEmailCodeResend;

  /// Resend button while the cooldown runs (#3038)
  ///
  /// In ko, this message translates to:
  /// **'{seconds}초 뒤 다시 받기'**
  String signUpEmailCodeResendIn(int seconds);

  /// Helper under the sign-up code field with the time left, m:ss (#3038)
  ///
  /// In ko, this message translates to:
  /// **'메일로 받은 6자리 코드 · 남은 시간 {time}'**
  String signUpEmailCodeRemaining(String time);

  /// No description provided for @signUpEmailCodeExpired.
  ///
  /// In ko, this message translates to:
  /// **'코드가 만료됐어요. 다시 받아 주세요.'**
  String get signUpEmailCodeExpired;

  /// No description provided for @signUpEmailCodeEmpty.
  ///
  /// In ko, this message translates to:
  /// **'인증 코드 6자리를 입력해 주세요'**
  String get signUpEmailCodeEmpty;

  /// No description provided for @signUpEmailCodeInvalid.
  ///
  /// In ko, this message translates to:
  /// **'인증 코드가 맞지 않거나 만료됐어요. 코드를 다시 받아 주세요.'**
  String get signUpEmailCodeInvalid;

  /// Demo-only hint with the code the mock accepts (#3038)
  ///
  /// In ko, this message translates to:
  /// **'데모 모드에서는 메일이 가지 않아요. 인증 코드 {code} 을 입력해 주세요.'**
  String signUpEmailCodeDemoNote(String code);

  /// No description provided for @signUpEmailCodeUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'지금은 인증 메일을 보낼 수 없어요. 잠시 후 다시 시도해 주세요.'**
  String get signUpEmailCodeUnavailable;

  /// No description provided for @reauthTitle.
  ///
  /// In ko, this message translates to:
  /// **'본인 확인'**
  String get reauthTitle;

  /// Title of the dialog that checks the new address before an email change (#3230)
  ///
  /// In ko, this message translates to:
  /// **'새 이메일 인증'**
  String get emailChangeCodeTitle;

  /// Body of the new-email code dialog; email is the new address (#3230)
  ///
  /// In ko, this message translates to:
  /// **'{email} 로 6자리 인증 코드를 보냈어요. 이 주소가 내 것인지 확인하려면 코드를 입력해 주세요.'**
  String emailChangeCodeMessage(String email);

  /// Confirm button of the new-email code dialog; the re-auth dialog follows (#3230)
  ///
  /// In ko, this message translates to:
  /// **'다음'**
  String get emailChangeCodeNext;

  /// Re-auth dialog text before an email change (#3039)
  ///
  /// In ko, this message translates to:
  /// **'이메일을 바꾸면 로그인 아이디와 비밀번호 재설정 메일 주소가 바뀌어요.'**
  String get reauthEmailMessage;

  /// No description provided for @reauthPasswordPrompt.
  ///
  /// In ko, this message translates to:
  /// **'계속하려면 현재 비밀번호를 입력해 주세요.'**
  String get reauthPasswordPrompt;

  /// No description provided for @reauthPasswordRequired.
  ///
  /// In ko, this message translates to:
  /// **'현재 비밀번호를 입력해 주세요'**
  String get reauthPasswordRequired;

  /// No description provided for @reauthSocialPrompt.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 없는 계정이에요. 가입한 소셜 계정으로 다시 로그인해 주세요.'**
  String get reauthSocialPrompt;

  /// No description provided for @reauthSocialAction.
  ///
  /// In ko, this message translates to:
  /// **'소셜 계정으로 다시 로그인'**
  String get reauthSocialAction;

  /// No description provided for @reauthSocialConfirmed.
  ///
  /// In ko, this message translates to:
  /// **'소셜 계정을 확인했어요'**
  String get reauthSocialConfirmed;

  /// No description provided for @reauthSocialRequired.
  ///
  /// In ko, this message translates to:
  /// **'소셜 계정으로 다시 로그인해 주세요'**
  String get reauthSocialRequired;

  /// No description provided for @reauthSocialInvalid.
  ///
  /// In ko, this message translates to:
  /// **'소셜 계정을 확인하지 못했어요. 다시 로그인해 주세요.'**
  String get reauthSocialInvalid;

  /// No description provided for @reauthSocialUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'이 버전에서는 아직 소셜 계정 확인을 할 수 없어요. 고객 지원으로 문의해 주세요.'**
  String get reauthSocialUnavailable;

  /// Title of the banner shown when a newer web release has been deployed while this tab is open (#3023). Plain wording for members and trainers, not deployment jargon (#3204).
  ///
  /// In ko, this message translates to:
  /// **'앱이 업데이트됐어요'**
  String get releaseUpdateTitle;

  /// Body of the new-release banner.
  ///
  /// In ko, this message translates to:
  /// **'새로고침하면 최신 버전으로 바뀌어요. 작성 중인 내용이 있으면 먼저 저장해 주세요.'**
  String get releaseUpdateMessage;

  /// Button that hides the banner and reloads the page with the new release's files (#3204).
  ///
  /// In ko, this message translates to:
  /// **'새로고침'**
  String get releaseUpdateReload;

  /// Tooltip of the button that hides the new-release banner for this release.
  ///
  /// In ko, this message translates to:
  /// **'안내 닫기'**
  String get releaseUpdateDismiss;
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
      <String>['ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
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
