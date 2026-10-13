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

  /// Trainer app title shown in the OS task switcher and browser tab.
  ///
  /// In ko, this message translates to:
  /// **'On-Care 트레이너'**
  String get appTitle;

  /// Display label for a scheduled session. The stored value stays Korean — see ScheduleStatus.
  ///
  /// In ko, this message translates to:
  /// **'예정'**
  String get scheduleStatusUpcoming;

  /// Display label for a completed session.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get scheduleStatusDone;

  /// No description provided for @scheduleStatusCancelled.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get scheduleStatusCancelled;

  /// No description provided for @scheduleStatusNoShow.
  ///
  /// In ko, this message translates to:
  /// **'노쇼'**
  String get scheduleStatusNoShow;

  /// No description provided for @schedCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get schedCancel;

  /// No description provided for @schedNoShow.
  ///
  /// In ko, this message translates to:
  /// **'노쇼 처리'**
  String get schedNoShow;

  /// No description provided for @schedCancelTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 PT를 취소할까요?'**
  String get schedCancelTitle;

  /// No description provided for @schedCancelConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{time} {name}님 PT가 취소로 기록돼요. 일정은 지워지지 않아요.'**
  String schedCancelConfirm(String time, String name);

  /// No description provided for @schedCancelSource.
  ///
  /// In ko, this message translates to:
  /// **'처리 구분'**
  String get schedCancelSource;

  /// No description provided for @schedCancelByMember.
  ///
  /// In ko, this message translates to:
  /// **'회원 취소'**
  String get schedCancelByMember;

  /// No description provided for @schedCancelByTrainer.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 취소'**
  String get schedCancelByTrainer;

  /// No description provided for @schedCancelByOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get schedCancelByOther;

  /// No description provided for @schedCancelReasonHint.
  ///
  /// In ko, this message translates to:
  /// **'사유 (선택, 트레이너만 봐요)'**
  String get schedCancelReasonHint;

  /// No description provided for @schedCancelFailed.
  ///
  /// In ko, this message translates to:
  /// **'취소 처리하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get schedCancelFailed;

  /// No description provided for @schedNoShowTitle.
  ///
  /// In ko, this message translates to:
  /// **'노쇼로 기록할까요?'**
  String get schedNoShowTitle;

  /// No description provided for @schedNoShowConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{time} {name}님이 오지 않은 것으로 기록돼요.'**
  String schedNoShowConfirm(String time, String name);

  /// No description provided for @schedNoShowFailed.
  ///
  /// In ko, this message translates to:
  /// **'노쇼 처리하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get schedNoShowFailed;

  /// No description provided for @schedCancelledBy.
  ///
  /// In ko, this message translates to:
  /// **'{source} · {date}'**
  String schedCancelledBy(String source, String date);

  /// No description provided for @schedDeleteMeansRemove.
  ///
  /// In ko, this message translates to:
  /// **'기록이 지워져요. 진행되지 않은 PT는 취소·노쇼로 남기세요.'**
  String get schedDeleteMeansRemove;

  /// No description provided for @schedDeleteMeansRemoveFinished.
  ///
  /// In ko, this message translates to:
  /// **'기록이 지워져요. 이미 완료한 일정이라 되돌릴 수 없어요.'**
  String get schedDeleteMeansRemoveFinished;

  /// No description provided for @schedDeleteDoneRemovesMemberRecord.
  ///
  /// In ko, this message translates to:
  /// **'회원 앱의 PT 기록과 운동 기록에서도 함께 사라져요. 이미 보낸 개인운동은 그대로 남아요.'**
  String get schedDeleteDoneRemovesMemberRecord;

  /// Display label for an empty slot in the trainer's day.
  ///
  /// In ko, this message translates to:
  /// **'공백'**
  String get scheduleStatusGap;

  /// Display label for a personal training session.
  ///
  /// In ko, this message translates to:
  /// **'1:1 PT'**
  String get sessionTypePersonalTraining;

  /// Display label for a consultation session.
  ///
  /// In ko, this message translates to:
  /// **'상담'**
  String get sessionTypeConsultation;

  /// No description provided for @navDashboard.
  ///
  /// In ko, this message translates to:
  /// **'대시보드'**
  String get navDashboard;

  /// No description provided for @navClients.
  ///
  /// In ko, this message translates to:
  /// **'회원'**
  String get navClients;

  /// No description provided for @navSchedule.
  ///
  /// In ko, this message translates to:
  /// **'스케줄'**
  String get navSchedule;

  /// No description provided for @navCoaching.
  ///
  /// In ko, this message translates to:
  /// **'프로그램'**
  String get navCoaching;

  /// No description provided for @navReports.
  ///
  /// In ko, this message translates to:
  /// **'리포트'**
  String get navReports;

  /// No description provided for @navConsultations.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청'**
  String get navConsultations;

  /// No description provided for @actionSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get actionSave;

  /// No description provided for @actionSaved.
  ///
  /// In ko, this message translates to:
  /// **'저장됨'**
  String get actionSaved;

  /// No description provided for @actionCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get actionCancel;

  /// No description provided for @actionEdit.
  ///
  /// In ko, this message translates to:
  /// **'수정'**
  String get actionEdit;

  /// No description provided for @actionDelete.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get actionDelete;

  /// No description provided for @actionClose.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get actionClose;

  /// No description provided for @actionDone.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get actionDone;

  /// No description provided for @actionMore.
  ///
  /// In ko, this message translates to:
  /// **'더보기'**
  String get actionMore;

  /// No description provided for @actionRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get actionRetry;

  /// No description provided for @actionChange.
  ///
  /// In ko, this message translates to:
  /// **'변경'**
  String get actionChange;

  /// No description provided for @actionAdd.
  ///
  /// In ko, this message translates to:
  /// **'추가'**
  String get actionAdd;

  /// No description provided for @actionSend.
  ///
  /// In ko, this message translates to:
  /// **'보내기'**
  String get actionSend;

  /// No description provided for @actionReset.
  ///
  /// In ko, this message translates to:
  /// **'초기화'**
  String get actionReset;

  /// Heading of the 404 page shown for a URL that matches no screen.
  ///
  /// In ko, this message translates to:
  /// **'페이지를 찾을 수 없어요'**
  String get notFoundTitle;

  /// No description provided for @notFoundMessage.
  ///
  /// In ko, this message translates to:
  /// **'주소가 잘못됐거나 더 이상 없는 페이지예요. 주소를 다시 확인해 주세요.'**
  String get notFoundMessage;

  /// Primary button on the 404 page for a signed-in trainer.
  ///
  /// In ko, this message translates to:
  /// **'대시보드로 가기'**
  String get notFoundGoDashboard;

  /// Primary button on the 404 page when no one is signed in.
  ///
  /// In ko, this message translates to:
  /// **'로그인하러 가기'**
  String get notFoundGoSignIn;

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

  /// Second word of the sidebar wordmark, rendered in the navy primary next to 'On-Care'.
  ///
  /// In ko, this message translates to:
  /// **'트레이너'**
  String get appWordmarkTrainer;

  /// Single-character avatar shown when the trainer has no name yet. Keep it one character.
  ///
  /// In ko, this message translates to:
  /// **'트'**
  String get appAvatarFallback;

  /// Tooltip on the collapsed sidebar's profile avatar.
  ///
  /// In ko, this message translates to:
  /// **'{name} · 내 정보'**
  String sidebarMyTooltip(String name);

  /// No description provided for @authTagline.
  ///
  /// In ko, this message translates to:
  /// **'회원의 식단·운동 기록을 한눈에 보고 코칭하는 트레이너 전용 공간'**
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
  /// **'로그인 없이 데모 둘러보기'**
  String get authDemoAction;

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

  /// No description provided for @authSignUpSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'On-Care 계정을 만들어 회원 관리를 시작하세요'**
  String get authSignUpSubtitle;

  /// No description provided for @authName.
  ///
  /// In ko, this message translates to:
  /// **'이름'**
  String get authName;

  /// No description provided for @signUpPasswordHint.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 (영문·숫자 포함 8자 이상)'**
  String get signUpPasswordHint;

  /// No description provided for @authPasswordConfirm.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 확인'**
  String get authPasswordConfirm;

  /// No description provided for @authSignUpAndStart.
  ///
  /// In ko, this message translates to:
  /// **'가입하고 시작하기'**
  String get authSignUpAndStart;

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

  /// No description provided for @authHasAccount.
  ///
  /// In ko, this message translates to:
  /// **'이미 계정이 있으신가요?'**
  String get authHasAccount;

  /// No description provided for @authErrEmptyCredentials.
  ///
  /// In ko, this message translates to:
  /// **'이메일과 비밀번호를 입력해 주세요'**
  String get authErrEmptyCredentials;

  /// No description provided for @authSocialSignInFailed.
  ///
  /// In ko, this message translates to:
  /// **'소셜 로그인을 하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get authSocialSignInFailed;

  /// No description provided for @authSocialComingSoon.
  ///
  /// In ko, this message translates to:
  /// **'소셜 로그인은 준비 중이에요. 이메일로 로그인해 주세요.'**
  String get authSocialComingSoon;

  /// Shown when the browser blocks the Kakao sign-in pop-up window (#330).
  ///
  /// In ko, this message translates to:
  /// **'로그인 창이 차단됐어요. 이 사이트의 팝업을 허용한 뒤 다시 시도해 주세요.'**
  String get authSocialPopupBlocked;

  /// No description provided for @authErrSignInFailed.
  ///
  /// In ko, this message translates to:
  /// **'로그인하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get authErrSignInFailed;

  /// No description provided for @authSessionExpired.
  ///
  /// In ko, this message translates to:
  /// **'로그인이 만료됐어요. 다시 로그인해 주세요.'**
  String get authSessionExpired;

  /// Red text under the name field on sign-up when it is empty or whitespace only (#1784).
  ///
  /// In ko, this message translates to:
  /// **'이름을 입력해 주세요'**
  String get authErrNameEmpty;

  /// Shared name-length message (#1887). Trainer sign-up sends a name too; the limit matches the users.name column.
  ///
  /// In ko, this message translates to:
  /// **'이름은 100자까지 입력할 수 있어요'**
  String get authErrNameTooLong;

  /// Red text under the email field on sign-in/sign-up when it is empty (#1784).
  ///
  /// In ko, this message translates to:
  /// **'이메일을 입력해 주세요'**
  String get authErrEmailEmpty;

  /// No description provided for @authErrEmailInvalid.
  ///
  /// In ko, this message translates to:
  /// **'이메일 형식이 올바르지 않아요'**
  String get authErrEmailInvalid;

  /// Red text under the email field when the address is longer than the server limit (#2908). The limit matches the users.email column and EMAIL_MAX_LENGTH in contact_format.py.
  ///
  /// In ko, this message translates to:
  /// **'이메일은 255자까지 입력할 수 있어요'**
  String get authErrEmailTooLong;

  /// No description provided for @authErrPasswordEmpty.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 입력해 주세요'**
  String get authErrPasswordEmpty;

  /// No description provided for @authErrPasswordWeak.
  ///
  /// In ko, this message translates to:
  /// **'영문과 숫자를 포함해 8자 이상 입력해 주세요'**
  String get authErrPasswordWeak;

  /// Password upper-limit message (#1555). Matches the server rule in password_policy.py: 64 characters and 72 UTF-8 bytes (bcrypt), so Korean letters and emoji use up the limit faster.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호는 64자까지 입력할 수 있어요 (한글·이모지는 더 짧게)'**
  String get authErrPasswordTooLong;

  /// Shared phone-format message (#1784). Trainer sign-up has no phone field today; kept so the shared AppInputError mapping stays exhaustive.
  ///
  /// In ko, this message translates to:
  /// **'전화번호를 010-0000-0000 형식으로 입력해 주세요'**
  String get authErrPhoneInvalid;

  /// Shared birth-date message (#1887). The trainer app has no birth-date field today; kept so the shared AppInputError mapping stays exhaustive.
  ///
  /// In ko, this message translates to:
  /// **'생년월일을 1996-03-21 형식으로 입력해 주세요'**
  String get authErrBirthDateInvalid;

  /// No description provided for @authErrPasswordMismatch.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 일치하지 않아요'**
  String get authErrPasswordMismatch;

  /// No description provided for @authErrSignUpFailed.
  ///
  /// In ko, this message translates to:
  /// **'가입하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get authErrSignUpFailed;

  /// No description provided for @dashTitle.
  ///
  /// In ko, this message translates to:
  /// **'대시보드'**
  String get dashTitle;

  /// No description provided for @dashActivityRecommendRoutine.
  ///
  /// In ko, this message translates to:
  /// **'프로그램 구성을 조정해 보세요.'**
  String get dashActivityRecommendRoutine;

  /// No description provided for @dashActivityRecommendChat.
  ///
  /// In ko, this message translates to:
  /// **'메시지에서 안부를 물어보세요.'**
  String get dashActivityRecommendChat;

  /// No description provided for @dashActivityRecommendDiet.
  ///
  /// In ko, this message translates to:
  /// **'식단에서 피드백을 남겨 보세요.'**
  String get dashActivityRecommendDiet;

  /// No description provided for @dashActivityTabProgram.
  ///
  /// In ko, this message translates to:
  /// **'프로그램'**
  String get dashActivityTabProgram;

  /// No description provided for @dashActivityTabChat.
  ///
  /// In ko, this message translates to:
  /// **'메시지'**
  String get dashActivityTabChat;

  /// No description provided for @dashActivityTabClient.
  ///
  /// In ko, this message translates to:
  /// **'회원'**
  String get dashActivityTabClient;

  /// No description provided for @dashLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'대시보드를 불러오지 못했어요'**
  String get dashLoadFailed;

  /// Unit after a booking count. Korean uses the counter 건; English omits it because the tile label already says what is being counted. Intentionally empty.
  ///
  /// In ko, this message translates to:
  /// **'건'**
  String get dashUnitCount;

  /// Unit after a person count. Korean uses the counter 명; English omits it. Intentionally empty.
  ///
  /// In ko, this message translates to:
  /// **'명'**
  String get dashUnitPeople;

  /// No description provided for @dashMyClients.
  ///
  /// In ko, this message translates to:
  /// **'담당 회원'**
  String get dashMyClients;

  /// No description provided for @dashDormantClients.
  ///
  /// In ko, this message translates to:
  /// **'휴면 {count}명'**
  String dashDormantClients(int count);

  /// No description provided for @dashAllActive.
  ///
  /// In ko, this message translates to:
  /// **'전원 활성'**
  String get dashAllActive;

  /// No description provided for @dashNeedsReply.
  ///
  /// In ko, this message translates to:
  /// **'답장 필요'**
  String get dashNeedsReply;

  /// No description provided for @dashWaitingClients.
  ///
  /// In ko, this message translates to:
  /// **'회원 {count}명 대기 중'**
  String dashWaitingClients(int count);

  /// No description provided for @dashAllReplied.
  ///
  /// In ko, this message translates to:
  /// **'모두 답장했어요'**
  String get dashAllReplied;

  /// No description provided for @dashAttentionClients.
  ///
  /// In ko, this message translates to:
  /// **'관리 필요'**
  String get dashAttentionClients;

  /// No description provided for @dashNoIssues.
  ///
  /// In ko, this message translates to:
  /// **'이상 없음'**
  String get dashNoIssues;

  /// No description provided for @dashCheckPtSignals.
  ///
  /// In ko, this message translates to:
  /// **'관리 신호 확인'**
  String get dashCheckPtSignals;

  /// No description provided for @dashMessages.
  ///
  /// In ko, this message translates to:
  /// **'메시지'**
  String get dashMessages;

  /// No description provided for @dashChurnRisk.
  ///
  /// In ko, this message translates to:
  /// **'이탈 위험'**
  String get dashChurnRisk;

  /// No description provided for @dashChurnRiskNone.
  ///
  /// In ko, this message translates to:
  /// **'이탈 위험 없음'**
  String get dashChurnRiskNone;

  /// No description provided for @dashChurnRiskCheck.
  ///
  /// In ko, this message translates to:
  /// **'이탈 신호 확인'**
  String get dashChurnRiskCheck;

  /// No description provided for @dashChurnRiskTitle.
  ///
  /// In ko, this message translates to:
  /// **'이탈 위험 회원'**
  String get dashChurnRiskTitle;

  /// No description provided for @dashChurnRiskEmpty.
  ///
  /// In ko, this message translates to:
  /// **'지금은 이탈 위험 신호가 없어요.'**
  String get dashChurnRiskEmpty;

  /// No description provided for @dashChurnRiskLoading.
  ///
  /// In ko, this message translates to:
  /// **'최근 운동 기록 확인 중'**
  String get dashChurnRiskLoading;

  /// No description provided for @dashChurnRiskUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'확인할 수 없음 · 눌러서 다시 시도'**
  String get dashChurnRiskUnavailable;

  /// No description provided for @dashActivityFeedbackLoading.
  ///
  /// In ko, this message translates to:
  /// **'최근 운동 기록을 확인하고 있어요.'**
  String get dashActivityFeedbackLoading;

  /// No description provided for @dashActivityFeedbackUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'최근 운동 기록을 불러오지 못해 활동 피드백을 확인할 수 없어요. 이탈 위험 카드를 눌러 다시 시도해 주세요.'**
  String get dashActivityFeedbackUnavailable;

  /// No description provided for @dashActivityDifficultyTitle.
  ///
  /// In ko, this message translates to:
  /// **'운동 목표 미달·개인운동 미수행'**
  String get dashActivityDifficultyTitle;

  /// No description provided for @dashActivityDifficultyDesc.
  ///
  /// In ko, this message translates to:
  /// **'{names} 회원이 이번 주 운동 목표에 못 미치거나 개인운동을 하지 않았어요. 다음 PT 전에 난이도를 낮추고 최근 피드백을 확인해 주세요.'**
  String dashActivityDifficultyDesc(String names);

  /// No description provided for @dashActivityInactiveTitle.
  ///
  /// In ko, this message translates to:
  /// **'기록 끊김'**
  String get dashActivityInactiveTitle;

  /// No description provided for @dashActivityInactiveDesc.
  ///
  /// In ko, this message translates to:
  /// **'{names} 회원이 며칠째 식단·운동 기록이 없어요. 이탈로 이어지기 전에 먼저 연락해서 재참여를 유도해 보세요.'**
  String dashActivityInactiveDesc(String names);

  /// No description provided for @dashActivityDietFeedbackTitle.
  ///
  /// In ko, this message translates to:
  /// **'식단 피드백 미완료'**
  String get dashActivityDietFeedbackTitle;

  /// No description provided for @dashActivityDietFeedbackDesc.
  ///
  /// In ko, this message translates to:
  /// **'{names} 회원이 칼로리 목표를 벗어났거나 단백질이 부족한데 최근 7일간 피드백을 받지 못했어요. 식단 피드백을 남겨 확인했다는 걸 알려 주세요.'**
  String dashActivityDietFeedbackDesc(String names);

  /// No description provided for @dashActivityMoreClients.
  ///
  /// In ko, this message translates to:
  /// **'{shown} 외 {count}명'**
  String dashActivityMoreClients(String shown, int count);

  /// No description provided for @dashAiSummaryTitle.
  ///
  /// In ko, this message translates to:
  /// **'활동 피드백'**
  String get dashAiSummaryTitle;

  /// No description provided for @dashAiNoClients.
  ///
  /// In ko, this message translates to:
  /// **'아직 담당 회원이 없어요. 회원을 등록하면 식단·운동 데이터를 모아 코칭 포인트를 짚어 드릴게요.'**
  String get dashAiNoClients;

  /// No description provided for @dashTodaySchedule.
  ///
  /// In ko, this message translates to:
  /// **'오늘의 일정'**
  String get dashTodaySchedule;

  /// No description provided for @dashSeeAll.
  ///
  /// In ko, this message translates to:
  /// **'전체 보기'**
  String get dashSeeAll;

  /// No description provided for @dashScheduleLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'일정을 불러오지 못했어요'**
  String get dashScheduleLoadFailed;

  /// No description provided for @dashNoScheduleToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘 등록된 일정이 없어요'**
  String get dashNoScheduleToday;

  /// No description provided for @dashScheduleNowLabel.
  ///
  /// In ko, this message translates to:
  /// **'지금 {time}'**
  String dashScheduleNowLabel(String time);

  /// No description provided for @dashScheduleNextSession.
  ///
  /// In ko, this message translates to:
  /// **'다음 일정 {time} · {name}'**
  String dashScheduleNextSession(String time, String name);

  /// No description provided for @dashScheduleMinutesLeft.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분 뒤'**
  String dashScheduleMinutesLeft(int minutes);

  /// Dashboard banner when today's session has started but not yet ended (#2865).
  ///
  /// In ko, this message translates to:
  /// **'진행 중 {time} · {name}'**
  String dashScheduleInProgress(String time, String name);

  /// Minutes until the in-progress session ends (#2865).
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분 남음'**
  String dashScheduleMinutesToEnd(int minutes);

  /// No description provided for @dashPreparePt.
  ///
  /// In ko, this message translates to:
  /// **'PT 준비하기'**
  String get dashPreparePt;

  /// No description provided for @dashLeaveMemo.
  ///
  /// In ko, this message translates to:
  /// **'메모 남기기'**
  String get dashLeaveMemo;

  /// No description provided for @dashLeaveFeedback.
  ///
  /// In ko, this message translates to:
  /// **'피드백 남기기'**
  String get dashLeaveFeedback;

  /// No description provided for @dashSessionSent.
  ///
  /// In ko, this message translates to:
  /// **'보냄'**
  String get dashSessionSent;

  /// No description provided for @dashSessionPrepared.
  ///
  /// In ko, this message translates to:
  /// **'준비됨'**
  String get dashSessionPrepared;

  /// No description provided for @dashSessionNoteWritten.
  ///
  /// In ko, this message translates to:
  /// **'작성 완료'**
  String get dashSessionNoteWritten;

  /// No description provided for @dashSessionSentNo.
  ///
  /// In ko, this message translates to:
  /// **'안 보냄'**
  String get dashSessionSentNo;

  /// No description provided for @dashSessionPreparedNo.
  ///
  /// In ko, this message translates to:
  /// **'준비 안됨'**
  String get dashSessionPreparedNo;

  /// No description provided for @dashSessionNoteNotWritten.
  ///
  /// In ko, this message translates to:
  /// **'메모 없음'**
  String get dashSessionNoteNotWritten;

  /// No description provided for @weekdayMon.
  ///
  /// In ko, this message translates to:
  /// **'월'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In ko, this message translates to:
  /// **'화'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In ko, this message translates to:
  /// **'수'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In ko, this message translates to:
  /// **'목'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In ko, this message translates to:
  /// **'금'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In ko, this message translates to:
  /// **'토'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In ko, this message translates to:
  /// **'일'**
  String get weekdaySun;

  /// No description provided for @clientsLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'회원 정보를 불러오지 못했어요'**
  String get clientsLoadFailed;

  /// No description provided for @clientsNew.
  ///
  /// In ko, this message translates to:
  /// **'회원 연결'**
  String get clientsNew;

  /// No description provided for @clientsTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원 관리'**
  String get clientsTitle;

  /// No description provided for @clientsManagementAttention.
  ///
  /// In ko, this message translates to:
  /// **'관리 필요'**
  String get clientsManagementAttention;

  /// No description provided for @clientsFiltersClearAll.
  ///
  /// In ko, this message translates to:
  /// **'전체 초기화'**
  String get clientsFiltersClearAll;

  /// No description provided for @clientsSortLabel.
  ///
  /// In ko, this message translates to:
  /// **'정렬'**
  String get clientsSortLabel;

  /// No description provided for @clientsSortPriority.
  ///
  /// In ko, this message translates to:
  /// **'관리 필요 우선'**
  String get clientsSortPriority;

  /// No description provided for @clientsSortName.
  ///
  /// In ko, this message translates to:
  /// **'이름 오름차순'**
  String get clientsSortName;

  /// No description provided for @clientsSortNameDescending.
  ///
  /// In ko, this message translates to:
  /// **'이름 내림차순'**
  String get clientsSortNameDescending;

  /// No description provided for @clientsSortRecentMessage.
  ///
  /// In ko, this message translates to:
  /// **'최근 메시지순'**
  String get clientsSortRecentMessage;

  /// No description provided for @clientsFilterLabel.
  ///
  /// In ko, this message translates to:
  /// **'필터'**
  String get clientsFilterLabel;

  /// No description provided for @clientsPickHint.
  ///
  /// In ko, this message translates to:
  /// **'왼쪽에서 회원을 선택하면\n대화·식단·운동 기록이 여기에 열려요'**
  String get clientsPickHint;

  /// No description provided for @clientsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 담당 회원이 없어요'**
  String get clientsEmpty;

  /// No description provided for @clientsEmptyConnectHint.
  ///
  /// In ko, this message translates to:
  /// **'연결 코드를 받거나 담당 요청을 보내 회원을 연결하세요. 회원이 상담을 신청하면 상담 요청에도 표시돼요.'**
  String get clientsEmptyConnectHint;

  /// No description provided for @clientsEmptyForFilter.
  ///
  /// In ko, this message translates to:
  /// **'{filter}에 해당하는 회원이 없어요'**
  String clientsEmptyForFilter(String filter);

  /// No description provided for @clientsEmptyForManagement.
  ///
  /// In ko, this message translates to:
  /// **'조건에 맞는 회원이 없어요'**
  String get clientsEmptyForManagement;

  /// No description provided for @clientsMemberCount.
  ///
  /// In ko, this message translates to:
  /// **'{total}명'**
  String clientsMemberCount(int total);

  /// Roster subtitle while a dashboard preset or management filter narrows the list.
  ///
  /// In ko, this message translates to:
  /// **'{total}명 중 {shown}명'**
  String clientsMemberCountFiltered(int shown, int total);

  /// No description provided for @clientWeeklyRoutineAdherence.
  ///
  /// In ko, this message translates to:
  /// **'주간 완료율'**
  String get clientWeeklyRoutineAdherence;

  /// No description provided for @clientRoutineAdherenceUnmeasured.
  ///
  /// In ko, this message translates to:
  /// **'미집계'**
  String get clientRoutineAdherenceUnmeasured;

  /// No description provided for @clientsSignalDiscomfort.
  ///
  /// In ko, this message translates to:
  /// **'통증·불편'**
  String get clientsSignalDiscomfort;

  /// No description provided for @clientsSignalRecordGap.
  ///
  /// In ko, this message translates to:
  /// **'기록 끊김'**
  String get clientsSignalRecordGap;

  /// No description provided for @clientsSignalRecordGapDays.
  ///
  /// In ko, this message translates to:
  /// **'{days}일째 기록 없음'**
  String clientsSignalRecordGapDays(int days);

  /// No description provided for @clientsSignalRecordGapLong.
  ///
  /// In ko, this message translates to:
  /// **'30일 넘게 기록 없음'**
  String get clientsSignalRecordGapLong;

  /// No description provided for @clientsSignalNoShow.
  ///
  /// In ko, this message translates to:
  /// **'노쇼·취소 반복'**
  String get clientsSignalNoShow;

  /// No description provided for @clientsSignalNoShowCount.
  ///
  /// In ko, this message translates to:
  /// **'노쇼·취소 {count}회'**
  String clientsSignalNoShowCount(int count);

  /// No description provided for @clientsSignalRoutineMissed.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 미수행'**
  String get clientsSignalRoutineMissed;

  /// No description provided for @clientsSignalExerciseGoalLow.
  ///
  /// In ko, this message translates to:
  /// **'운동 목표 미달'**
  String get clientsSignalExerciseGoalLow;

  /// No description provided for @clientsSignalExerciseGoalLowPercent.
  ///
  /// In ko, this message translates to:
  /// **'운동 목표 {percent}%'**
  String clientsSignalExerciseGoalLowPercent(int percent);

  /// No description provided for @clientsSignalCalorieOff.
  ///
  /// In ko, this message translates to:
  /// **'칼로리 목표 이탈'**
  String get clientsSignalCalorieOff;

  /// No description provided for @clientsSignalCalorieOver.
  ///
  /// In ko, this message translates to:
  /// **'칼로리 초과'**
  String get clientsSignalCalorieOver;

  /// No description provided for @clientsSignalCalorieUnder.
  ///
  /// In ko, this message translates to:
  /// **'칼로리 부족'**
  String get clientsSignalCalorieUnder;

  /// No description provided for @clientsSignalProteinLow.
  ///
  /// In ko, this message translates to:
  /// **'단백질 부족'**
  String get clientsSignalProteinLow;

  /// No description provided for @clientsSignalCalorieOverPercent.
  ///
  /// In ko, this message translates to:
  /// **'칼로리 {percent}% 초과'**
  String clientsSignalCalorieOverPercent(int percent);

  /// No description provided for @clientsSignalCalorieUnderPercent.
  ///
  /// In ko, this message translates to:
  /// **'칼로리 {percent}% 부족'**
  String clientsSignalCalorieUnderPercent(int percent);

  /// No description provided for @clientsSignalProteinPercent.
  ///
  /// In ko, this message translates to:
  /// **'단백질 목표의 {percent}%'**
  String clientsSignalProteinPercent(int percent);

  /// No description provided for @clientsSignalRoutineMissedDays.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 {days}일 미수행'**
  String clientsSignalRoutineMissedDays(int days);

  /// No description provided for @clientsSignalUnanswered.
  ///
  /// In ko, this message translates to:
  /// **'답장 대기'**
  String get clientsSignalUnanswered;

  /// No description provided for @clientsAttentionClear.
  ///
  /// In ko, this message translates to:
  /// **'관리 필요 보기 해제'**
  String get clientsAttentionClear;

  /// No description provided for @memberHealthLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'회원 정보를 불러오지 못했어요. 다시 시도해 주세요'**
  String get memberHealthLoadFailed;

  /// No description provided for @memberHealthSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'회원 정보를 저장하지 못했어요. 다시 시도해 주세요'**
  String get memberHealthSaveFailed;

  /// No description provided for @memberHealthSaving.
  ///
  /// In ko, this message translates to:
  /// **'저장 중…'**
  String get memberHealthSaving;

  /// No description provided for @memberHealthGender.
  ///
  /// In ko, this message translates to:
  /// **'성별'**
  String get memberHealthGender;

  /// No description provided for @memberHealthGenderUnset.
  ///
  /// In ko, this message translates to:
  /// **'미설정'**
  String get memberHealthGenderUnset;

  /// No description provided for @memberHealthGenderMale.
  ///
  /// In ko, this message translates to:
  /// **'남성'**
  String get memberHealthGenderMale;

  /// No description provided for @memberHealthGenderFemale.
  ///
  /// In ko, this message translates to:
  /// **'여성'**
  String get memberHealthGenderFemale;

  /// No description provided for @memberHealthGenderOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get memberHealthGenderOther;

  /// No description provided for @memberHealthHeight.
  ///
  /// In ko, this message translates to:
  /// **'키 (cm)'**
  String get memberHealthHeight;

  /// No description provided for @memberHealthWeight.
  ///
  /// In ko, this message translates to:
  /// **'체중 (kg)'**
  String get memberHealthWeight;

  /// No description provided for @memberHealthFocus.
  ///
  /// In ko, this message translates to:
  /// **'건강 목표 (최대 2개)'**
  String get memberHealthFocus;

  /// Member profile dialog: who last changed the member's goal chips and when (#1832).
  ///
  /// In ko, this message translates to:
  /// **'마지막 변경: {who} · {date}'**
  String memberHealthFocusLastChanged(String who, String date);

  /// No description provided for @memberHealthFocusChangedByTrainer.
  ///
  /// In ko, this message translates to:
  /// **'트레이너'**
  String get memberHealthFocusChangedByTrainer;

  /// No description provided for @memberHealthFocusChangedByMember.
  ///
  /// In ko, this message translates to:
  /// **'회원'**
  String get memberHealthFocusChangedByMember;

  /// No description provided for @healthFocusWeightLoss.
  ///
  /// In ko, this message translates to:
  /// **'체중 감량'**
  String get healthFocusWeightLoss;

  /// No description provided for @healthFocusStrength.
  ///
  /// In ko, this message translates to:
  /// **'근력 향상'**
  String get healthFocusStrength;

  /// No description provided for @healthFocusFitness.
  ///
  /// In ko, this message translates to:
  /// **'체력 강화'**
  String get healthFocusFitness;

  /// No description provided for @healthFocusPosture.
  ///
  /// In ko, this message translates to:
  /// **'자세 교정'**
  String get healthFocusPosture;

  /// No description provided for @healthFocusRehab.
  ///
  /// In ko, this message translates to:
  /// **'재활'**
  String get healthFocusRehab;

  /// No description provided for @healthFocusEating.
  ///
  /// In ko, this message translates to:
  /// **'식습관 개선'**
  String get healthFocusEating;

  /// No description provided for @healthFocusExerciseHabit.
  ///
  /// In ko, this message translates to:
  /// **'운동 습관'**
  String get healthFocusExerciseHabit;

  /// No description provided for @healthFocusBloodPressure.
  ///
  /// In ko, this message translates to:
  /// **'혈압 관리'**
  String get healthFocusBloodPressure;

  /// No description provided for @memberHealthConditions.
  ///
  /// In ko, this message translates to:
  /// **'건강상태·주의사항'**
  String get memberHealthConditions;

  /// No description provided for @memberHealthConditionsShared.
  ///
  /// In ko, this message translates to:
  /// **'회원에게도 보여요 · 추천할 때 참고해요'**
  String get memberHealthConditionsShared;

  /// No description provided for @memberHealthConditionsPrivateHint.
  ///
  /// In ko, this message translates to:
  /// **'트레이너만 볼 내용은 메모에 남겨 주세요.'**
  String get memberHealthConditionsPrivateHint;

  /// No description provided for @memberHealthDietGoal.
  ///
  /// In ko, this message translates to:
  /// **'식단 목표'**
  String get memberHealthDietGoal;

  /// No description provided for @memberHealthExerciseGoal.
  ///
  /// In ko, this message translates to:
  /// **'운동 목표'**
  String get memberHealthExerciseGoal;

  /// No description provided for @memberHealthGoalCalories.
  ///
  /// In ko, this message translates to:
  /// **'하루 칼로리 목표 (kcal)'**
  String get memberHealthGoalCalories;

  /// No description provided for @memberHealthGoalSodium.
  ///
  /// In ko, this message translates to:
  /// **'하루 나트륨 목표 (mg)'**
  String get memberHealthGoalSodium;

  /// No description provided for @memberHealthGoalSugar.
  ///
  /// In ko, this message translates to:
  /// **'하루 당류 목표 (g)'**
  String get memberHealthGoalSugar;

  /// No description provided for @memberHealthGoalCarbs.
  ///
  /// In ko, this message translates to:
  /// **'하루 탄수화물 목표 (g)'**
  String get memberHealthGoalCarbs;

  /// No description provided for @memberHealthGoalProtein.
  ///
  /// In ko, this message translates to:
  /// **'하루 단백질 목표 (g)'**
  String get memberHealthGoalProtein;

  /// No description provided for @memberHealthGoalFat.
  ///
  /// In ko, this message translates to:
  /// **'하루 지방 목표 (g)'**
  String get memberHealthGoalFat;

  /// No description provided for @memberHealthGoalBurnDaily.
  ///
  /// In ko, this message translates to:
  /// **'하루 소모 칼로리 (kcal)'**
  String get memberHealthGoalBurnDaily;

  /// No description provided for @memberHealthGoalCardioWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 유산소 (분)'**
  String get memberHealthGoalCardioWeekly;

  /// No description provided for @memberHealthGoalStrengthWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 근력 (세트)'**
  String get memberHealthGoalStrengthWeekly;

  /// No description provided for @memberHealthGoalFlexibilityWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 스트레칭 (분)'**
  String get memberHealthGoalFlexibilityWeekly;

  /// No description provided for @memberHealthRange.
  ///
  /// In ko, this message translates to:
  /// **'{min}~{max} 범위로 입력해 주세요.'**
  String memberHealthRange(String min, String max);

  /// No description provided for @clientInviteTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원 연결'**
  String get clientInviteTitle;

  /// No description provided for @clientInviteIntro.
  ///
  /// In ko, this message translates to:
  /// **'회원 앱 MY 탭의 6자리 연결 코드를 입력하면 바로 연결돼요.'**
  String get clientInviteIntro;

  /// No description provided for @clientInviteIntroImmediate.
  ///
  /// In ko, this message translates to:
  /// **'회원 앱 MY 탭의 6자리 연결 코드를 입력하면 바로 연결돼요.'**
  String get clientInviteIntroImmediate;

  /// No description provided for @clientConnectCodeLabel.
  ///
  /// In ko, this message translates to:
  /// **'연결 코드'**
  String get clientConnectCodeLabel;

  /// No description provided for @clientConnectCodeRequired.
  ///
  /// In ko, this message translates to:
  /// **'6자리를 모두 입력해 주세요'**
  String get clientConnectCodeRequired;

  /// No description provided for @clientConnectCodeInvalid.
  ///
  /// In ko, this message translates to:
  /// **'코드가 맞지 않거나 만료됐어요. 회원에게 새 코드를 받아 주세요'**
  String get clientConnectCodeInvalid;

  /// No description provided for @clientConnectAlreadyManaged.
  ///
  /// In ko, this message translates to:
  /// **'이미 담당하고 있는 회원이에요. 회원 목록에서 찾아 주세요'**
  String get clientConnectAlreadyManaged;

  /// No description provided for @clientInviteConnectAction.
  ///
  /// In ko, this message translates to:
  /// **'연결'**
  String get clientInviteConnectAction;

  /// No description provided for @clientInviteConnected.
  ///
  /// In ko, this message translates to:
  /// **'{name}님과 연결했어요'**
  String clientInviteConnected(String name);

  /// No description provided for @clientInviteFailed.
  ///
  /// In ko, this message translates to:
  /// **'요청을 보내지 못했어요. 다시 시도해 주세요'**
  String get clientInviteFailed;

  /// No description provided for @clientInvitePendingTitle.
  ///
  /// In ko, this message translates to:
  /// **'답을 기다리는 요청'**
  String get clientInvitePendingTitle;

  /// No description provided for @clientInvitePendingEmpty.
  ///
  /// In ko, this message translates to:
  /// **'기다리는 요청이 없어요'**
  String get clientInvitePendingEmpty;

  /// No description provided for @clientInviteCancelAction.
  ///
  /// In ko, this message translates to:
  /// **'요청 거두기'**
  String get clientInviteCancelAction;

  /// No description provided for @clientInviteCancelled.
  ///
  /// In ko, this message translates to:
  /// **'요청을 거뒀어요'**
  String get clientInviteCancelled;

  /// No description provided for @clientInviteCancelFailed.
  ///
  /// In ko, this message translates to:
  /// **'요청을 거두지 못했어요. 다시 시도해 주세요'**
  String get clientInviteCancelFailed;

  /// No description provided for @clientInviteConfirmPrompt.
  ///
  /// In ko, this message translates to:
  /// **'이 회원이 맞나요?'**
  String get clientInviteConfirmPrompt;

  /// No description provided for @coachTemplateNew.
  ///
  /// In ko, this message translates to:
  /// **'새 템플릿'**
  String get coachTemplateNew;

  /// No description provided for @coachTemplateEdit.
  ///
  /// In ko, this message translates to:
  /// **'템플릿 수정'**
  String get coachTemplateEdit;

  /// No description provided for @coachTemplateDelete.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get coachTemplateDelete;

  /// No description provided for @coachTemplateNameLabel.
  ///
  /// In ko, this message translates to:
  /// **'템플릿 이름'**
  String get coachTemplateNameLabel;

  /// No description provided for @coachTemplateGoalLabel.
  ///
  /// In ko, this message translates to:
  /// **'목표 (예: 혈압 관리 · 초급)'**
  String get coachTemplateGoalLabel;

  /// No description provided for @coachTemplateExerciseName.
  ///
  /// In ko, this message translates to:
  /// **'운동 이름'**
  String get coachTemplateExerciseName;

  /// No description provided for @coachTemplateAddExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동 추가'**
  String get coachTemplateAddExercise;

  /// No description provided for @coachTemplateSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get coachTemplateSave;

  /// No description provided for @coachTemplateNameRequired.
  ///
  /// In ko, this message translates to:
  /// **'템플릿 이름을 입력해 주세요'**
  String get coachTemplateNameRequired;

  /// No description provided for @coachTemplateExerciseRequired.
  ///
  /// In ko, this message translates to:
  /// **'운동을 하나 이상 넣어 주세요'**
  String get coachTemplateExerciseRequired;

  /// No description provided for @coachTemplateExerciseNameRequired.
  ///
  /// In ko, this message translates to:
  /// **'운동 이름을 적어 주세요'**
  String get coachTemplateExerciseNameRequired;

  /// No description provided for @coachTemplateSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'템플릿을 저장하지 못했어요. 다시 시도해 주세요'**
  String get coachTemplateSaveFailed;

  /// No description provided for @coachTemplateDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'템플릿을 삭제하지 못했어요. 다시 시도해 주세요'**
  String get coachTemplateDeleteFailed;

  /// No description provided for @coachTemplateAlreadyDeleted.
  ///
  /// In ko, this message translates to:
  /// **'이미 지워진 템플릿이에요'**
  String get coachTemplateAlreadyDeleted;

  /// No description provided for @coachTemplateDeleteConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{name} 템플릿을 삭제할까요?'**
  String coachTemplateDeleteConfirm(String name);

  /// No description provided for @coachTemplateLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'템플릿을 불러오지 못했어요'**
  String get coachTemplateLoadFailed;

  /// No description provided for @chatEmoteLabel.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘'**
  String get chatEmoteLabel;

  /// No description provided for @chatAttachImage.
  ///
  /// In ko, this message translates to:
  /// **'사진 첨부'**
  String get chatAttachImage;

  /// No description provided for @chatImageUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'사진을 불러오지 못했어요'**
  String get chatImageUnavailable;

  /// No description provided for @chatImageSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'사진을 보내지 못했어요. 다시 시도해 주세요'**
  String get chatImageSendFailed;

  /// No description provided for @chatImageAlreadySent.
  ///
  /// In ko, this message translates to:
  /// **'앞서 보낸 사진이 이미 전송돼 있어요. 대화를 확인해 주세요'**
  String get chatImageAlreadySent;

  /// No description provided for @clientTabDiet.
  ///
  /// In ko, this message translates to:
  /// **'식단'**
  String get clientTabDiet;

  /// No description provided for @clientTabWorkout.
  ///
  /// In ko, this message translates to:
  /// **'운동'**
  String get clientTabWorkout;

  /// No description provided for @clientNotFound.
  ///
  /// In ko, this message translates to:
  /// **'회원을 찾을 수 없어요'**
  String get clientNotFound;

  /// No description provided for @clientBackToList.
  ///
  /// In ko, this message translates to:
  /// **'회원 목록으로'**
  String get clientBackToList;

  /// No description provided for @clientList.
  ///
  /// In ko, this message translates to:
  /// **'회원 목록'**
  String get clientList;

  /// No description provided for @metricCalories.
  ///
  /// In ko, this message translates to:
  /// **'칼로리'**
  String get metricCalories;

  /// No description provided for @metricSodium.
  ///
  /// In ko, this message translates to:
  /// **'나트륨'**
  String get metricSodium;

  /// No description provided for @metricSugar.
  ///
  /// In ko, this message translates to:
  /// **'당류'**
  String get metricSugar;

  /// No description provided for @clientDietMacrosMissing.
  ///
  /// In ko, this message translates to:
  /// **'탄단지 기록 없음'**
  String get clientDietMacrosMissing;

  /// No description provided for @clientDietDayTotal.
  ///
  /// In ko, this message translates to:
  /// **'하루 합계'**
  String get clientDietDayTotal;

  /// Shown under the day total when the expanded day's meals fail to load (#2892)
  ///
  /// In ko, this message translates to:
  /// **'끼니 기록을 불러오지 못했어요'**
  String get clientDietDayMealsFailed;

  /// 트레이너 웹 식단 합계 kcal — 오늘 끼니 카드의 네 칸 오른쪽 끝과 펼친 날 하루 합계 줄 오른쪽 끝. 음식 kcal 과 구분되게 총을 붙인다. calories 는 천 단위 구분이 된 숫자. (#2421)
  ///
  /// In ko, this message translates to:
  /// **'총 {calories}kcal'**
  String clientDietTotalCalories(String calories);

  /// 끼니 카드 탄단지 범례 한 칸 — 이름과 그 끼니 칼로리에서 차지하는 비중(%). g 은 오른쪽 세부 줄에 있다. (#2333)
  ///
  /// In ko, this message translates to:
  /// **'{name} {percent}%'**
  String clientDietMacroShare(String name, int percent);

  /// No description provided for @metricCarbs.
  ///
  /// In ko, this message translates to:
  /// **'탄수화물'**
  String get metricCarbs;

  /// No description provided for @metricProtein.
  ///
  /// In ko, this message translates to:
  /// **'단백질'**
  String get metricProtein;

  /// No description provided for @metricFat.
  ///
  /// In ko, this message translates to:
  /// **'지방'**
  String get metricFat;

  /// No description provided for @clientDormant.
  ///
  /// In ko, this message translates to:
  /// **'휴면'**
  String get clientDormant;

  /// No description provided for @clientDormantActivate.
  ///
  /// In ko, this message translates to:
  /// **'눌러서 활성으로 전환'**
  String get clientDormantActivate;

  /// No description provided for @clientSignalLess.
  ///
  /// In ko, this message translates to:
  /// **'접기'**
  String get clientSignalLess;

  /// No description provided for @clientSignalMore.
  ///
  /// In ko, this message translates to:
  /// **'+{count}'**
  String clientSignalMore(int count);

  /// No description provided for @clientStatusChangeFailed.
  ///
  /// In ko, this message translates to:
  /// **'상태를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get clientStatusChangeFailed;

  /// No description provided for @chatTooLong.
  ///
  /// In ko, this message translates to:
  /// **'메시지가 너무 길어요 (최대 1000자)'**
  String get chatTooLong;

  /// No description provided for @chatSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'메시지를 보내지 못했어요. 다시 시도해 주세요'**
  String get chatSendFailed;

  /// No description provided for @chatLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'대화를 불러오지 못했어요'**
  String get chatLoadFailed;

  /// 회원 메시지 맨 위 — 서버가 주는 최신 50건 앞의 메시지를 한 쪽 더 받는 버튼(#2749). 위로 끝까지 스크롤해도 같은 일이 일어난다.
  ///
  /// In ko, this message translates to:
  /// **'이전 메시지 더 보기'**
  String get chatLoadOlder;

  /// 이전 메시지 한 쪽을 받지 못했을 때 같은 자리의 버튼. 누르면 다시 받는다(#2749).
  ///
  /// In ko, this message translates to:
  /// **'이전 메시지를 불러오지 못했어요 · 다시 시도'**
  String get chatLoadOlderFailed;

  /// No description provided for @chatPdfOpenFailed.
  ///
  /// In ko, this message translates to:
  /// **'PDF를 열지 못했어요. 다시 시도해 주세요'**
  String get chatPdfOpenFailed;

  /// No description provided for @chatReportRegistered.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트를 보냈어요'**
  String get chatReportRegistered;

  /// No description provided for @chatReportOpenInReports.
  ///
  /// In ko, this message translates to:
  /// **'리포트 탭으로 가기'**
  String get chatReportOpenInReports;

  /// No description provided for @chatRoutineDelivered.
  ///
  /// In ko, this message translates to:
  /// **'운동을 보냈어요'**
  String get chatRoutineDelivered;

  /// No description provided for @chatRoutineDeliveredPt.
  ///
  /// In ko, this message translates to:
  /// **'PT 프로그램과 개인운동을 보냈어요'**
  String get chatRoutineDeliveredPt;

  /// No description provided for @chatRoutineDeliveredPersonal.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 보냈어요'**
  String get chatRoutineDeliveredPersonal;

  /// No description provided for @chatRoutineDeliveredAfterCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소된 PT 대신 개인운동을 보냈어요'**
  String get chatRoutineDeliveredAfterCancel;

  /// No description provided for @chatRoutineDeliveredProgram.
  ///
  /// In ko, this message translates to:
  /// **'PT 프로그램을 보냈어요'**
  String get chatRoutineDeliveredProgram;

  /// No description provided for @chatRoutineDeliveredMore.
  ///
  /// In ko, this message translates to:
  /// **'{names} 외 {count}개'**
  String chatRoutineDeliveredMore(String names, int count);

  /// No description provided for @chatInputHint.
  ///
  /// In ko, this message translates to:
  /// **'메시지 입력...'**
  String get chatInputHint;

  /// No description provided for @chatInsightDiscomfortTitle.
  ///
  /// In ko, this message translates to:
  /// **'{part} 불편 표현 감지'**
  String chatInsightDiscomfortTitle(String part);

  /// No description provided for @chatInsightBodyPartGeneral.
  ///
  /// In ko, this message translates to:
  /// **'신체'**
  String get chatInsightBodyPartGeneral;

  /// No description provided for @chatInsightBodyPartKnee.
  ///
  /// In ko, this message translates to:
  /// **'무릎'**
  String get chatInsightBodyPartKnee;

  /// No description provided for @chatInsightBodyPartBack.
  ///
  /// In ko, this message translates to:
  /// **'허리'**
  String get chatInsightBodyPartBack;

  /// No description provided for @chatInsightBodyPartAnkle.
  ///
  /// In ko, this message translates to:
  /// **'발목'**
  String get chatInsightBodyPartAnkle;

  /// No description provided for @chatInsightBodyPartShoulder.
  ///
  /// In ko, this message translates to:
  /// **'어깨'**
  String get chatInsightBodyPartShoulder;

  /// No description provided for @chatInsightBodyPartWrist.
  ///
  /// In ko, this message translates to:
  /// **'손목'**
  String get chatInsightBodyPartWrist;

  /// No description provided for @chatInsightBodyPartNeck.
  ///
  /// In ko, this message translates to:
  /// **'목'**
  String get chatInsightBodyPartNeck;

  /// No description provided for @chatInsightNegativeTitle.
  ///
  /// In ko, this message translates to:
  /// **'부정적 피드백 감지'**
  String get chatInsightNegativeTitle;

  /// No description provided for @chatInsightDiscomfortDescription.
  ///
  /// In ko, this message translates to:
  /// **'AI가 불편감 호소를 감지했어요. 증상을 확인하고 다음 운동 강도를 조절해 보세요.'**
  String get chatInsightDiscomfortDescription;

  /// No description provided for @chatInsightNegativeDescription.
  ///
  /// In ko, this message translates to:
  /// **'AI가 운동 부담 또는 수행 어려움을 감지했어요. 원인을 확인하고 프로그램 조정을 고려해 보세요.'**
  String get chatInsightNegativeDescription;

  /// No description provided for @chatInsightAddMemo.
  ///
  /// In ko, this message translates to:
  /// **'메모에 추가'**
  String get chatInsightAddMemo;

  /// No description provided for @chatInsightMemoAdded.
  ///
  /// In ko, this message translates to:
  /// **'메모 추가됨'**
  String get chatInsightMemoAdded;

  /// No description provided for @chatInsightMemoSummaryDiscomfort.
  ///
  /// In ko, this message translates to:
  /// **'{part} 불편 감지'**
  String chatInsightMemoSummaryDiscomfort(String part);

  /// No description provided for @chatInsightMemoSummaryNegative.
  ///
  /// In ko, this message translates to:
  /// **'운동 부담 감지'**
  String get chatInsightMemoSummaryNegative;

  /// No description provided for @chatInsightMemoSaved.
  ///
  /// In ko, this message translates to:
  /// **'AI 감지 내용을 메모에 추가했어요.'**
  String get chatInsightMemoSaved;

  /// No description provided for @chatInsightMemoSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'메모에 추가하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get chatInsightMemoSaveFailed;

  /// No description provided for @consultTitle.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청'**
  String get consultTitle;

  /// No description provided for @consultFilterAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get consultFilterAll;

  /// No description provided for @consultFilterPendingCount.
  ///
  /// In ko, this message translates to:
  /// **'대기 {count}'**
  String consultFilterPendingCount(int count);

  /// No description provided for @consultLoadMore.
  ///
  /// In ko, this message translates to:
  /// **'지난 요청 더 보기'**
  String get consultLoadMore;

  /// No description provided for @consultLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청을 불러오지 못했어요'**
  String get consultLoadFailed;

  /// No description provided for @consultRetryLater.
  ///
  /// In ko, this message translates to:
  /// **'잠시 후 다시 시도해 주세요'**
  String get consultRetryLater;

  /// No description provided for @consultEmptyPending.
  ///
  /// In ko, this message translates to:
  /// **'대기 중인 상담 요청이 없어요'**
  String get consultEmptyPending;

  /// No description provided for @consultEmptyHistory.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청 이력이 없어요'**
  String get consultEmptyHistory;

  /// No description provided for @consultEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'회원이 나를 지정해 상담을 신청하면 여기에 표시돼요'**
  String get consultEmptyHint;

  /// No description provided for @consultActionFailed.
  ///
  /// In ko, this message translates to:
  /// **'상담을 처리하지 못했어요'**
  String get consultActionFailed;

  /// No description provided for @consultApproved.
  ///
  /// In ko, this message translates to:
  /// **'{name}님의 상담 요청을 승인했어요. 스케줄 탭에서 일정을 추가해 주세요.'**
  String consultApproved(String name);

  /// No description provided for @consultScheduleCreated.
  ///
  /// In ko, this message translates to:
  /// **'{name}님의 상담 일정을 등록했어요'**
  String consultScheduleCreated(String name);

  /// No description provided for @consultRejected.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청을 거절했어요'**
  String get consultRejected;

  /// No description provided for @consultDecisionNote.
  ///
  /// In ko, this message translates to:
  /// **'거절 사유'**
  String get consultDecisionNote;

  /// No description provided for @consultExerciseGoal.
  ///
  /// In ko, this message translates to:
  /// **'운동 목표'**
  String get consultExerciseGoal;

  /// No description provided for @consultChosenSlot.
  ///
  /// In ko, this message translates to:
  /// **'고른 시간'**
  String get consultChosenSlot;

  /// No description provided for @consultSlotDuration.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분'**
  String consultSlotDuration(int minutes);

  /// No description provided for @consultStatusCancelled.
  ///
  /// In ko, this message translates to:
  /// **'취소됨'**
  String get consultStatusCancelled;

  /// No description provided for @consultStatusCancelledByTrainer.
  ///
  /// In ko, this message translates to:
  /// **'일정 취소로 철회'**
  String get consultStatusCancelledByTrainer;

  /// No description provided for @consultStatusExpired.
  ///
  /// In ko, this message translates to:
  /// **'만료됨'**
  String get consultStatusExpired;

  /// No description provided for @consultPreferredTime.
  ///
  /// In ko, this message translates to:
  /// **'희망 일시'**
  String get consultPreferredTime;

  /// No description provided for @consultMessage.
  ///
  /// In ko, this message translates to:
  /// **'문의 내용'**
  String get consultMessage;

  /// No description provided for @schedConsultRequest.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청 내용'**
  String get schedConsultRequest;

  /// No description provided for @consultReject.
  ///
  /// In ko, this message translates to:
  /// **'거절'**
  String get consultReject;

  /// No description provided for @consultApprove.
  ///
  /// In ko, this message translates to:
  /// **'승인'**
  String get consultApprove;

  /// No description provided for @consultRejectTitle.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청 거절'**
  String get consultRejectTitle;

  /// No description provided for @consultRejectNotice.
  ///
  /// In ko, this message translates to:
  /// **'입력한 사유는 회원에게 알림으로 전달돼요.'**
  String get consultRejectNotice;

  /// No description provided for @consultRejectHint.
  ///
  /// In ko, this message translates to:
  /// **'예) 요청하신 시간에 다른 일정이 있어요.'**
  String get consultRejectHint;

  /// No description provided for @consultStatusPending.
  ///
  /// In ko, this message translates to:
  /// **'대기 중'**
  String get consultStatusPending;

  /// No description provided for @consultStatusAccepted.
  ///
  /// In ko, this message translates to:
  /// **'승인됨'**
  String get consultStatusAccepted;

  /// No description provided for @workoutRecords.
  ///
  /// In ko, this message translates to:
  /// **'운동 기록'**
  String get workoutRecords;

  /// No description provided for @workoutRecordsShowMore.
  ///
  /// In ko, this message translates to:
  /// **'더 보기'**
  String get workoutRecordsShowMore;

  /// No description provided for @workoutRecordsShowLess.
  ///
  /// In ko, this message translates to:
  /// **'접기'**
  String get workoutRecordsShowLess;

  /// No description provided for @workoutLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'운동 기록을 불러오지 못했어요'**
  String get workoutLoadFailed;

  /// No description provided for @workoutEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 운동 기록이 없어요'**
  String get workoutEmpty;

  /// No description provided for @routinesLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'프로그램을 불러오지 못했어요'**
  String get routinesLoadFailed;

  /// No description provided for @minutesShort.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분'**
  String minutesShort(int minutes);

  /// Hours part of an exercise duration, e.g. `1 hr 30 min` (#2221).
  ///
  /// In ko, this message translates to:
  /// **'{hours}시간'**
  String hoursShort(int hours);

  /// Seconds part of an exercise duration, e.g. `45 sec` (#2221).
  ///
  /// In ko, this message translates to:
  /// **'{seconds}초'**
  String secondsShort(int seconds);

  /// No description provided for @labelToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get labelToday;

  /// No description provided for @sessionTypeAndDuration.
  ///
  /// In ko, this message translates to:
  /// **'{type} · {minutes}분'**
  String sessionTypeAndDuration(String type, int minutes);

  /// No description provided for @legendDone.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get legendDone;

  /// No description provided for @clientFeedback.
  ///
  /// In ko, this message translates to:
  /// **'회원 피드백'**
  String get clientFeedback;

  /// Workout history kind for a completed PT session (server kind code pt_session).
  ///
  /// In ko, this message translates to:
  /// **'PT · 트레이너 지도'**
  String get workoutKindPtSession;

  /// Workout history kind for a completed assigned routine that has no name (server kind code assigned_routine).
  ///
  /// In ko, this message translates to:
  /// **'개인운동 수행'**
  String get workoutKindAssignedRoutine;

  /// No description provided for @dietLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'식단을 불러오지 못했어요'**
  String get dietLoadFailed;

  /// No description provided for @dietEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 기록된 식단이 없어요'**
  String get dietEmpty;

  /// No description provided for @dietDayEmpty.
  ///
  /// In ko, this message translates to:
  /// **'기록 없음'**
  String get dietDayEmpty;

  /// No description provided for @clientNutritionSummary.
  ///
  /// In ko, this message translates to:
  /// **'영양 요약'**
  String get clientNutritionSummary;

  /// No description provided for @dietCalorieIntake.
  ///
  /// In ko, this message translates to:
  /// **'오늘 섭취 칼로리'**
  String get dietCalorieIntake;

  /// No description provided for @dietAchieveRate.
  ///
  /// In ko, this message translates to:
  /// **'달성률'**
  String get dietAchieveRate;

  /// No description provided for @consultStatusRejected.
  ///
  /// In ko, this message translates to:
  /// **'거절됨'**
  String get consultStatusRejected;

  /// No description provided for @dateToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get dateToday;

  /// No description provided for @dateTomorrow.
  ///
  /// In ko, this message translates to:
  /// **'내일'**
  String get dateTomorrow;

  /// No description provided for @dateYesterday.
  ///
  /// In ko, this message translates to:
  /// **'어제'**
  String get dateYesterday;

  /// Relative day label, used for two or more days ago (e.g. when the last routine was sent).
  ///
  /// In ko, this message translates to:
  /// **'{count}일 전'**
  String dateDaysAgo(int count);

  /// Short date on a workout history card.
  ///
  /// In ko, this message translates to:
  /// **'{month}/{day}'**
  String historyDate(int month, int day);

  /// Workout history date with Today/Yesterday, e.g. 9/27 (Today).
  ///
  /// In ko, this message translates to:
  /// **'{date} ({relative})'**
  String historyDateRelative(String date, String relative);

  /// No description provided for @dateMonthDayWeekday.
  ///
  /// In ko, this message translates to:
  /// **'{month}/{day} ({weekday})'**
  String dateMonthDayWeekday(int month, int day, String weekday);

  /// No description provided for @datePrefixed.
  ///
  /// In ko, this message translates to:
  /// **'{prefix} · {date}'**
  String datePrefixed(String prefix, String date);

  /// No description provided for @dateMonthDay.
  ///
  /// In ko, this message translates to:
  /// **'{month}월 {day}일'**
  String dateMonthDay(int month, int day);

  /// No description provided for @dateRange.
  ///
  /// In ko, this message translates to:
  /// **'{start} ~ {end}'**
  String dateRange(String start, String end);

  /// No description provided for @reportsTitle.
  ///
  /// In ko, this message translates to:
  /// **'리포트'**
  String get reportsTitle;

  /// No description provided for @reportsSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'주간 변화를 확인하고 회원에게 전달하세요'**
  String get reportsSubtitle;

  /// No description provided for @reportsLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'리포트를 불러오지 못했어요'**
  String get reportsLoadFailed;

  /// No description provided for @reportsNoClients.
  ///
  /// In ko, this message translates to:
  /// **'담당 회원이 없어 리포트를 만들 수 없어요'**
  String get reportsNoClients;

  /// No description provided for @reportsWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트'**
  String get reportsWeekly;

  /// No description provided for @reportsSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'리포트를 보내지 못했어요. 다시 시도해 주세요'**
  String get reportsSendFailed;

  /// No description provided for @reportsSendStaleTitle.
  ///
  /// In ko, this message translates to:
  /// **'그사이 회원 기록이 바뀌었어요'**
  String get reportsSendStaleTitle;

  /// No description provided for @reportsSendStaleBody.
  ///
  /// In ko, this message translates to:
  /// **'아직 보내지 않았어요. 새 수치로 다시 만든 리포트를 확인한 뒤 보내 주세요'**
  String get reportsSendStaleBody;

  /// No description provided for @reportsSendFeedbackFailedTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원 피드백을 불러오지 못했어요'**
  String get reportsSendFeedbackFailedTitle;

  /// Notice on the send step when the member feedback request failed; sending is blocked (#3246).
  ///
  /// In ko, this message translates to:
  /// **'이대로 보내면 답한 회원도 미응답으로 실려요. 다시 불러온 뒤 보내 주세요'**
  String get reportsSendFeedbackFailedBody;

  /// Toast when the server says this report send was already processed (409, #2773).
  ///
  /// In ko, this message translates to:
  /// **'이미 전송된 리포트예요. 전송 기록을 다시 불러왔어요'**
  String get reportsSendAlreadyDone;

  /// No description provided for @reportsSent.
  ///
  /// In ko, this message translates to:
  /// **'{name}님에게 리포트를 보냈어요'**
  String reportsSent(String name);

  /// No description provided for @reportsGoToChat.
  ///
  /// In ko, this message translates to:
  /// **'메시지로 가기'**
  String get reportsGoToChat;

  /// No description provided for @reportsScheduleWarning.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 일정을 불러오지 못해 PT 횟수가 비어 있을 수 있어요'**
  String get reportsScheduleWarning;

  /// No description provided for @unitTimes.
  ///
  /// In ko, this message translates to:
  /// **'회'**
  String get unitTimes;

  /// No description provided for @unitMinutes.
  ///
  /// In ko, this message translates to:
  /// **'분'**
  String get unitMinutes;

  /// No description provided for @clientPeriodToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get clientPeriodToday;

  /// No description provided for @clientPeriodWeek.
  ///
  /// In ko, this message translates to:
  /// **'이번 주'**
  String get clientPeriodWeek;

  /// No description provided for @clientPeriodMonth.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get clientPeriodMonth;

  /// No description provided for @clientPeriodAverage.
  ///
  /// In ko, this message translates to:
  /// **'하루 평균'**
  String get clientPeriodAverage;

  /// No description provided for @clientPeriodGoal.
  ///
  /// In ko, this message translates to:
  /// **'목표'**
  String get clientPeriodGoal;

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

  /// No description provided for @exWeekOfMonthLabel.
  ///
  /// In ko, this message translates to:
  /// **'{month}월 {week}주차 소모'**
  String exWeekOfMonthLabel(int month, int week);

  /// No description provided for @exStreakCheer.
  ///
  /// In ko, this message translates to:
  /// **'{days}일 연속 운동 중이에요!'**
  String exStreakCheer(int days);

  /// No description provided for @exStreakStart.
  ///
  /// In ko, this message translates to:
  /// **'아직 연속 운동이 없어요'**
  String get exStreakStart;

  /// No description provided for @exTypeOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get exTypeOther;

  /// No description provided for @clientPeriodEmpty.
  ///
  /// In ko, this message translates to:
  /// **'이 기간에 기록이 없어요'**
  String get clientPeriodEmpty;

  /// No description provided for @unitKcal.
  ///
  /// In ko, this message translates to:
  /// **'kcal'**
  String get unitKcal;

  /// No description provided for @clientTrendTitle.
  ///
  /// In ko, this message translates to:
  /// **'운동 현황'**
  String get clientTrendTitle;

  /// No description provided for @clientTrendLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'운동 추이를 불러오지 못했어요. 다시 시도해 주세요'**
  String get clientTrendLoadFailed;

  /// No description provided for @clientTrendTodayEmpty.
  ///
  /// In ko, this message translates to:
  /// **'오늘 기록된 운동이 없어요'**
  String get clientTrendTodayEmpty;

  /// No description provided for @clientTrendWorkoutMinutes.
  ///
  /// In ko, this message translates to:
  /// **'운동 시간'**
  String get clientTrendWorkoutMinutes;

  /// No description provided for @clientTrendCaloriesBurned.
  ///
  /// In ko, this message translates to:
  /// **'소모 칼로리'**
  String get clientTrendCaloriesBurned;

  /// No description provided for @reportsPickClient.
  ///
  /// In ko, this message translates to:
  /// **'회원 선택'**
  String get reportsPickClient;

  /// No description provided for @reportsClientWeekly.
  ///
  /// In ko, this message translates to:
  /// **'{name}님 주간 리포트'**
  String reportsClientWeekly(String name);

  /// No description provided for @reportsCompletionByDay.
  ///
  /// In ko, this message translates to:
  /// **'주간 운동 완료율'**
  String get reportsCompletionByDay;

  /// No description provided for @reportsNoWorkoutsThisWeek.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 운동 기록이 없어요'**
  String get reportsNoWorkoutsThisWeek;

  /// No description provided for @chartNoRecord.
  ///
  /// In ko, this message translates to:
  /// **'기록 없음'**
  String get chartNoRecord;

  /// No description provided for @chartNotYet.
  ///
  /// In ko, this message translates to:
  /// **'아직 오지 않은 날'**
  String get chartNotYet;

  /// No description provided for @chartOverGoal.
  ///
  /// In ko, this message translates to:
  /// **'목표 초과 +{amount} {unit}'**
  String chartOverGoal(String amount, String unit);

  /// No description provided for @reportsSendNeedsFeedback.
  ///
  /// In ko, this message translates to:
  /// **'피드백을 입력하면 전송할 수 있어요'**
  String get reportsSendNeedsFeedback;

  /// No description provided for @reportBodyGreeting.
  ///
  /// In ko, this message translates to:
  /// **'{name}님, {range} 주간 리포트 정리해서 보내 드려요.'**
  String reportBodyGreeting(String name, String range);

  /// No description provided for @reportBodyCompletionGood.
  ///
  /// In ko, this message translates to:
  /// **'운동은 평균 {avg}%로 잘 따라오셨어요.'**
  String reportBodyCompletionGood(int avg);

  /// No description provided for @reportBodyCompletionSteady.
  ///
  /// In ko, this message translates to:
  /// **'운동은 평균 {avg}%로 꾸준히 해 주셨어요.'**
  String reportBodyCompletionSteady(int avg);

  /// No description provided for @reportBodyCompletionLow.
  ///
  /// In ko, this message translates to:
  /// **'운동 완료율은 평균 {avg}%였어요. 많이 바쁘셨나 봐요.'**
  String reportBodyCompletionLow(int avg);

  /// No description provided for @reportBodySilentDays.
  ///
  /// In ko, this message translates to:
  /// **'{days}에는 기록이 하나도 없었어요. 그 요일이 늘 바쁘시면 15분짜리 짧은 프로그램으로 바꿔 둘게요.'**
  String reportBodySilentDays(String days);

  /// No description provided for @reportBodySteadyDays.
  ///
  /// In ko, this message translates to:
  /// **'{days}요일까지 한 번도 끊기지 않은 게 이번 주에서 가장 좋았어요.'**
  String reportBodySteadyDays(String days);

  /// No description provided for @reportBodySkipped.
  ///
  /// In ko, this message translates to:
  /// **'다만 {names} 건너뛰셨더라고요. 컨디션 때문이었다면 다음 PT 때 말씀해 주세요. 대체 운동으로 바꿔 둘게요.'**
  String reportBodySkipped(String names);

  /// No description provided for @reportBodySodiumOver.
  ///
  /// In ko, this message translates to:
  /// **'나트륨은 하루 평균 {avg}mg이었고, 목표({target}mg)를 넘긴 날이 {days}일이었어요. 국물을 절반만 남기셔도 하루 400~500mg은 줄어요.'**
  String reportBodySodiumOver(String avg, String target, int days);

  /// No description provided for @reportBodySodiumOk.
  ///
  /// In ko, this message translates to:
  /// **'나트륨은 하루 평균 {avg}mg으로 목표({target}mg) 안에서 잘 지키고 계세요.'**
  String reportBodySodiumOk(String avg, String target);

  /// No description provided for @reportBodyPraise.
  ///
  /// In ko, this message translates to:
  /// **'정말 잘하셨어요. 다음 주도 이 페이스 그대로 가요!'**
  String get reportBodyPraise;

  /// No description provided for @reportBodyEncourage.
  ///
  /// In ko, this message translates to:
  /// **'위 내용만 하나씩 같이 챙겨 가면 충분히 좋아질 거예요. 프로그램은 제가 조정해서 올려둘게요.'**
  String get reportBodyEncourage;

  /// No description provided for @reportBodyNoRecords.
  ///
  /// In ko, this message translates to:
  /// **'이 주에는 남은 기록이 없어서 정리해 드릴 내용이 없네요. 다음 주 시작을 같이 잡아 봐요.'**
  String get reportBodyNoRecords;

  /// No description provided for @reportBodySessionsAll.
  ///
  /// In ko, this message translates to:
  /// **'PT는 예약된 {booked}회를 모두 진행했어요.'**
  String reportBodySessionsAll(int booked);

  /// No description provided for @reportBodySessionsSome.
  ///
  /// In ko, this message translates to:
  /// **'PT는 예약된 {booked}회 중 {done}회 진행했어요.'**
  String reportBodySessionsSome(int booked, int done);

  /// No description provided for @reportBodySessionsNone.
  ///
  /// In ko, this message translates to:
  /// **'이 주에는 진행한 PT가 없었어요.'**
  String get reportBodySessionsNone;

  /// No description provided for @reportBodyExerciseCount.
  ///
  /// In ko, this message translates to:
  /// **'배정된 개인운동 {total}개 중 {done}개를 완료하셨어요.'**
  String reportBodyExerciseCount(int total, int done);

  /// No description provided for @reportBodyMealDaysAll.
  ///
  /// In ko, this message translates to:
  /// **'식단은 {total}일 모두 빠짐없이 기록해 주셨어요.'**
  String reportBodyMealDaysAll(int total);

  /// No description provided for @reportBodyMealDays.
  ///
  /// In ko, this message translates to:
  /// **'식단은 {total}일 중 {days}일 기록해 주셨어요.'**
  String reportBodyMealDays(int total, int days);

  /// No description provided for @reportBodyCaloriesOver.
  ///
  /// In ko, this message translates to:
  /// **'칼로리는 하루 평균 {avg}kcal로 목표({target}kcal)보다 {pct}% 많았고, 목표를 넘긴 날이 {days}일이었어요.'**
  String reportBodyCaloriesOver(
    String avg,
    String target,
    String pct,
    int days,
  );

  /// No description provided for @reportBodyCaloriesUnder.
  ///
  /// In ko, this message translates to:
  /// **'칼로리는 하루 평균 {avg}kcal로 목표({target}kcal)보다 {pct}% 적었어요. 너무 적게 드시면 근육이 먼저 빠질 수 있어요.'**
  String reportBodyCaloriesUnder(String avg, String target, String pct);

  /// No description provided for @reportBodyCaloriesNearOver.
  ///
  /// In ko, this message translates to:
  /// **'칼로리는 하루 평균 {avg}kcal로 목표({target}kcal) 근처였지만, 목표를 넘긴 날이 {days}일 있었어요.'**
  String reportBodyCaloriesNearOver(String avg, String target, int days);

  /// No description provided for @reportBodyCaloriesOk.
  ///
  /// In ko, this message translates to:
  /// **'칼로리는 하루 평균 {avg}kcal로 목표({target}kcal)에 맞게 잘 조절해 주셨어요.'**
  String reportBodyCaloriesOk(String avg, String target);

  /// No description provided for @reportBodySugarOver.
  ///
  /// In ko, this message translates to:
  /// **'당류는 하루 평균 {avg}g이었고, 목표({target}g)를 넘긴 날이 {days}일이었어요.'**
  String reportBodySugarOver(String avg, String target, int days);

  /// No description provided for @reportBodySugarOk.
  ///
  /// In ko, this message translates to:
  /// **'당류는 하루 평균 {avg}g으로 목표({target}g) 안이었어요.'**
  String reportBodySugarOk(String avg, String target);

  /// No description provided for @reportBodyMemberPain.
  ///
  /// In ko, this message translates to:
  /// **'{area} 아프셨다고 남겨 주셨는데, 다음 PT 전에 상태를 꼭 다시 알려 주세요. 그 부위는 강도를 낮춰 둘게요.'**
  String reportBodyMemberPain(String area);

  /// No description provided for @reportBodyMemberTooHard.
  ///
  /// In ko, this message translates to:
  /// **'운동이 많이 힘들었다고 남겨 주셔서, 다음 주 강도는 한 단계 낮춰 둘게요.'**
  String get reportBodyMemberTooHard;

  /// No description provided for @reportBodyMemberTooEasy.
  ///
  /// In ko, this message translates to:
  /// **'운동이 쉬웠다고 남겨 주셔서, 다음 주에는 강도를 한 단계 올려 볼게요.'**
  String get reportBodyMemberTooEasy;

  /// No description provided for @reportBodyMemberNoted.
  ///
  /// In ko, this message translates to:
  /// **'보내 주신 이번 주 피드백도 잘 읽었어요.'**
  String get reportBodyMemberNoted;

  /// No description provided for @reportBodyNextWeek.
  ///
  /// In ko, this message translates to:
  /// **'다음 주에는 이렇게 해 봐요.'**
  String get reportBodyNextWeek;

  /// No description provided for @reportTipCaloriesOver.
  ///
  /// In ko, this message translates to:
  /// **'저녁 밥 양을 3분의 2로 줄이고, 간식은 단백질 위주로 바꿔 보세요.'**
  String get reportTipCaloriesOver;

  /// No description provided for @reportTipCaloriesUnder.
  ///
  /// In ko, this message translates to:
  /// **'끼니를 거르지 말고, 운동한 날에는 단백질 간식을 하나 더 챙겨 주세요.'**
  String get reportTipCaloriesUnder;

  /// No description provided for @reportTipSugar.
  ///
  /// In ko, this message translates to:
  /// **'단 음료와 디저트는 하루 한 번까지만 드셔 보세요.'**
  String get reportTipSugar;

  /// No description provided for @reportTipSodium.
  ///
  /// In ko, this message translates to:
  /// **'배달 음식과 가공식품은 주 2회까지로 줄여 보세요.'**
  String get reportTipSodium;

  /// No description provided for @reportTipWorkout.
  ///
  /// In ko, this message translates to:
  /// **'운동은 한 번에 20분이라도 주 3회를 먼저 채우는 걸 목표로 해요.'**
  String get reportTipWorkout;

  /// No description provided for @reportTipMeals.
  ///
  /// In ko, this message translates to:
  /// **'식사는 사진 한 장이라도 매 끼니 남겨 주시면 더 정확하게 봐 드릴 수 있어요.'**
  String get reportTipMeals;

  /// No description provided for @reportTipSessionsNone.
  ///
  /// In ko, this message translates to:
  /// **'다음 주 PT 일정도 이번에 같이 잡아 둘게요.'**
  String get reportTipSessionsNone;

  /// No description provided for @reportTipSessionsMissed.
  ///
  /// In ko, this message translates to:
  /// **'빠진 PT는 다음 주에 보강 일정으로 잡아 드릴게요.'**
  String get reportTipSessionsMissed;

  /// No description provided for @reportTipKeep.
  ///
  /// In ko, this message translates to:
  /// **'지금 루틴은 그대로 유지하면서, 운동 강도만 조금씩 올려 볼게요.'**
  String get reportTipKeep;

  /// No description provided for @schedTitle.
  ///
  /// In ko, this message translates to:
  /// **'스케줄'**
  String get schedTitle;

  /// No description provided for @schedDetailTitle.
  ///
  /// In ko, this message translates to:
  /// **'상세 일정'**
  String get schedDetailTitle;

  /// No description provided for @schedDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'일정 삭제'**
  String get schedDeleteTitle;

  /// No description provided for @schedDeleteConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{time} {name}님 PT 일정을 삭제할까요?'**
  String schedDeleteConfirm(String time, String name);

  /// No description provided for @schedDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'일정을 삭제하지 못했어요. 다시 시도해 주세요'**
  String get schedDeleteFailed;

  /// No description provided for @schedCompleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'일정 완료'**
  String get schedCompleteTitle;

  /// No description provided for @schedCompleteConfirm.
  ///
  /// In ko, this message translates to:
  /// **'{time} {name}님 PT를 완료할까요?'**
  String schedCompleteConfirm(String time, String name);

  /// No description provided for @schedCompleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'완료 처리하지 못했어요. 다시 시도해 주세요'**
  String get schedCompleteFailed;

  /// No description provided for @schedGroupProgram.
  ///
  /// In ko, this message translates to:
  /// **'PT 프로그램'**
  String get schedGroupProgram;

  /// 담당이 끊긴 회원의 일정에 이름 대신 쓰는 말 (#2589)
  ///
  /// In ko, this message translates to:
  /// **'해제 회원'**
  String get schedDetachedMember;

  /// No description provided for @schedDetachedMemberHint.
  ///
  /// In ko, this message translates to:
  /// **'담당이 끝난 회원이라 회원 정보는 볼 수 없어요'**
  String get schedDetachedMemberHint;

  /// Hint on a session card for a session the member booked through a reservation slot (#2756). Edit schedule and Delete are disabled.
  ///
  /// In ko, this message translates to:
  /// **'회원이 예약한 일정이에요. 시간을 바꾸거나 지울 수 없고, 약속을 거두려면 취소해 주세요.'**
  String get schedReservationLockedHint;

  /// No description provided for @schedEndedLockedHint.
  ///
  /// In ko, this message translates to:
  /// **'끝난 PT는 피드백·프로그램만 고칠 수 있어요.'**
  String get schedEndedLockedHint;

  /// No description provided for @schedDoneLockedHint.
  ///
  /// In ko, this message translates to:
  /// **'완료한 PT는 피드백·프로그램만 고칠 수 있어요. 날짜를 앞으로 옮기면 예정으로 되돌릴 수 있어요.'**
  String get schedDoneLockedHint;

  /// No description provided for @schedGroupPersonal.
  ///
  /// In ko, this message translates to:
  /// **'개인운동'**
  String get schedGroupPersonal;

  /// No description provided for @schedRoutinesGoesOnComplete.
  ///
  /// In ko, this message translates to:
  /// **'이 PT 의 프로그램을 보낼 때 회원에게 함께 가요.'**
  String get schedRoutinesGoesOnComplete;

  /// No description provided for @schedRoutinesNotSentYet.
  ///
  /// In ko, this message translates to:
  /// **'아직 회원에게 가지 않았어요.'**
  String get schedRoutinesNotSentYet;

  /// No description provided for @schedRoutinesSendTitle.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 보낼까요?'**
  String get schedRoutinesSendTitle;

  /// No description provided for @schedEditRoutines.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 수정'**
  String get schedEditRoutines;

  /// No description provided for @schedEditRoutinesTitle.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 수정'**
  String get schedEditRoutinesTitle;

  /// No description provided for @schedEditRoutinesBody.
  ///
  /// In ko, this message translates to:
  /// **'PT 프로그램과 함께 나갈 개인운동이에요. 아직 보내지 않아 지금은 마음껏 고칠 수 있어요.'**
  String get schedEditRoutinesBody;

  /// No description provided for @schedRoutinesSendBody.
  ///
  /// In ko, this message translates to:
  /// **'이 PT 는 열리지 않았지만 짜 둔 개인운동은 보낼 수 있어요. 보낸 날부터 7일 동안 회원 앱에 매일 떠요.'**
  String get schedRoutinesSendBody;

  /// No description provided for @schedRoutinesSend.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 보내기'**
  String get schedRoutinesSend;

  /// No description provided for @schedRoutinesSkip.
  ///
  /// In ko, this message translates to:
  /// **'보내지 않음'**
  String get schedRoutinesSkip;

  /// No description provided for @schedSendProgramWithRoutines.
  ///
  /// In ko, this message translates to:
  /// **'{date} PT 프로그램 · 개인운동 보내기'**
  String schedSendProgramWithRoutines(String date);

  /// No description provided for @schedRoutineSent.
  ///
  /// In ko, this message translates to:
  /// **'보냄'**
  String get schedRoutineSent;

  /// No description provided for @schedRoutinesSent.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 회원에게 보냈어요.'**
  String get schedRoutinesSent;

  /// No description provided for @schedRoutinesSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 보내지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get schedRoutinesSendFailed;

  /// No description provided for @schedRoutinesSkipped.
  ///
  /// In ko, this message translates to:
  /// **'보내지 않기로 했어요.'**
  String get schedRoutinesSkipped;

  /// No description provided for @schedRoutinesSkipFailed.
  ///
  /// In ko, this message translates to:
  /// **'보내지 않기로 처리하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get schedRoutinesSkipFailed;

  /// No description provided for @schedRoutinesLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 불러오지 못했어요'**
  String get schedRoutinesLoadFailed;

  /// No description provided for @schedClientUnresolved.
  ///
  /// In ko, this message translates to:
  /// **'이 일정의 회원을 특정할 수 없어요. 회원을 골라 주세요.'**
  String get schedClientUnresolved;

  /// No description provided for @schedRoutinesUpdated.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 고쳤어요.'**
  String get schedRoutinesUpdated;

  /// No description provided for @schedRoutinesUpdateFailed.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 고치지 못했어요. 다시 시도해 주세요.'**
  String get schedRoutinesUpdateFailed;

  /// No description provided for @schedAddRoutines.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 추가'**
  String get schedAddRoutines;

  /// No description provided for @schedRoutinesAdded.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 붙였어요.'**
  String get schedRoutinesAdded;

  /// No description provided for @schedNoRoutines.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 없음'**
  String get schedNoRoutines;

  /// No description provided for @schedNoRoutinesSendTitle.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 없이 보낼까요?'**
  String get schedNoRoutinesSendTitle;

  /// No description provided for @schedNoRoutinesSendBody.
  ///
  /// In ko, this message translates to:
  /// **'이 PT에는 개인운동이 없어요. 보낸 뒤에는 이 PT에 개인운동을 붙일 수 없어요.'**
  String get schedNoRoutinesSendBody;

  /// No description provided for @schedNoRoutinesSendSkip.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 없이 보내기'**
  String get schedNoRoutinesSendSkip;

  /// No description provided for @schedTimeRange.
  ///
  /// In ko, this message translates to:
  /// **'{start}–{end}'**
  String schedTimeRange(String start, String end);

  /// No description provided for @schedEmptyWeek.
  ///
  /// In ko, this message translates to:
  /// **'이번 주에는 일정이 없어요.'**
  String get schedEmptyWeek;

  /// No description provided for @schedSlots.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간'**
  String get schedSlots;

  /// No description provided for @schedNewSession.
  ///
  /// In ko, this message translates to:
  /// **'새 일정'**
  String get schedNewSession;

  /// No description provided for @schedLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'스케줄을 불러오지 못했어요'**
  String get schedLoadFailed;

  /// No description provided for @schedEmptyDay.
  ///
  /// In ko, this message translates to:
  /// **'이 날짜에는 일정이 없어요.\n위의 「새 일정」으로 추가해 보세요.'**
  String get schedEmptyDay;

  /// No description provided for @schedSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'일정을 저장하지 못했어요. 다시 시도해 주세요'**
  String get schedSaveFailed;

  /// No description provided for @schedAddTitle.
  ///
  /// In ko, this message translates to:
  /// **'새 일정 추가'**
  String get schedAddTitle;

  /// No description provided for @schedEditTitle.
  ///
  /// In ko, this message translates to:
  /// **'일정 수정'**
  String get schedEditTitle;

  /// No description provided for @schedFieldClient.
  ///
  /// In ko, this message translates to:
  /// **'회원'**
  String get schedFieldClient;

  /// No description provided for @schedFieldType.
  ///
  /// In ko, this message translates to:
  /// **'유형'**
  String get schedFieldType;

  /// No description provided for @schedFieldDate.
  ///
  /// In ko, this message translates to:
  /// **'날짜'**
  String get schedFieldDate;

  /// No description provided for @schedFieldDateRange.
  ///
  /// In ko, this message translates to:
  /// **'시작 - 종료일'**
  String get schedFieldDateRange;

  /// No description provided for @schedFieldTime.
  ///
  /// In ko, this message translates to:
  /// **'시간'**
  String get schedFieldTime;

  /// No description provided for @schedEndBeforeStart.
  ///
  /// In ko, this message translates to:
  /// **'종료 시간은 시작 시간보다 늦어야 해요'**
  String get schedEndBeforeStart;

  /// No description provided for @schedReopenTitle.
  ///
  /// In ko, this message translates to:
  /// **'예정으로 바꿀까요?'**
  String get schedReopenTitle;

  /// No description provided for @schedReopenBody.
  ///
  /// In ko, this message translates to:
  /// **'완료된 PT를 앞으로 옮기면 예정 상태로 되돌아가고, 그 완료가 남긴 운동 기록은 사라져요.'**
  String get schedReopenBody;

  /// No description provided for @schedReopenConfirm.
  ///
  /// In ko, this message translates to:
  /// **'예정으로 바꾸기'**
  String get schedReopenConfirm;

  /// No description provided for @schedReopenPastBlocked.
  ///
  /// In ko, this message translates to:
  /// **'완료된 PT는 미래 날짜로만 옮길 수 있어요'**
  String get schedReopenPastBlocked;

  /// No description provided for @schedTimeRangeTitle.
  ///
  /// In ko, this message translates to:
  /// **'시간 선택'**
  String get schedTimeRangeTitle;

  /// No description provided for @schedTimeRangeConfirm.
  ///
  /// In ko, this message translates to:
  /// **'확인'**
  String get schedTimeRangeConfirm;

  /// No description provided for @schedTimePickerTimeLabel.
  ///
  /// In ko, this message translates to:
  /// **'시각'**
  String get schedTimePickerTimeLabel;

  /// No description provided for @schedTimePickerEndTime.
  ///
  /// In ko, this message translates to:
  /// **'종료 시간'**
  String get schedTimePickerEndTime;

  /// No description provided for @schedTimePickerHour.
  ///
  /// In ko, this message translates to:
  /// **'시'**
  String get schedTimePickerHour;

  /// No description provided for @schedTimePickerMinute.
  ///
  /// In ko, this message translates to:
  /// **'분'**
  String get schedTimePickerMinute;

  /// No description provided for @schedTimePickerStartHour.
  ///
  /// In ko, this message translates to:
  /// **'시작 시'**
  String get schedTimePickerStartHour;

  /// No description provided for @schedTimePickerStartMinute.
  ///
  /// In ko, this message translates to:
  /// **'시작 분'**
  String get schedTimePickerStartMinute;

  /// No description provided for @schedTimePickerEndHour.
  ///
  /// In ko, this message translates to:
  /// **'종료 시'**
  String get schedTimePickerEndHour;

  /// No description provided for @schedTimePickerEndMinute.
  ///
  /// In ko, this message translates to:
  /// **'종료 분'**
  String get schedTimePickerEndMinute;

  /// No description provided for @schedTimePickerPrevStep.
  ///
  /// In ko, this message translates to:
  /// **'이전 단계'**
  String get schedTimePickerPrevStep;

  /// No description provided for @schedTimePickerNextStep.
  ///
  /// In ko, this message translates to:
  /// **'다음 단계'**
  String get schedTimePickerNextStep;

  /// No description provided for @schedTimePickerEndBeforeStart.
  ///
  /// In ko, this message translates to:
  /// **'종료 시간이 시작 시간보다 빨라요'**
  String get schedTimePickerEndBeforeStart;

  /// No description provided for @schedClockHourSemantics.
  ///
  /// In ko, this message translates to:
  /// **'{hour}시'**
  String schedClockHourSemantics(String hour);

  /// No description provided for @schedRepeat.
  ///
  /// In ko, this message translates to:
  /// **'반복'**
  String get schedRepeat;

  /// No description provided for @schedRepeatWeekly.
  ///
  /// In ko, this message translates to:
  /// **'매주'**
  String get schedRepeatWeekly;

  /// No description provided for @schedRepeatPreview.
  ///
  /// In ko, this message translates to:
  /// **'총 {count}회 · {first} ~ {last}'**
  String schedRepeatPreview(int count, String first, String last);

  /// No description provided for @schedRepeatNeedsDays.
  ///
  /// In ko, this message translates to:
  /// **'반복할 요일을 골라 주세요.'**
  String get schedRepeatNeedsDays;

  /// No description provided for @schedRepeatNeedsEndDate.
  ///
  /// In ko, this message translates to:
  /// **'반복 종료일을 골라 주세요.'**
  String get schedRepeatNeedsEndDate;

  /// No description provided for @schedRepeatNoOccurrences.
  ///
  /// In ko, this message translates to:
  /// **'고른 요일이 반복 기간 안에 없어요. 요일이나 종료일을 바꿔 주세요.'**
  String get schedRepeatNoOccurrences;

  /// No description provided for @schedNewNeedsClient.
  ///
  /// In ko, this message translates to:
  /// **'담당 회원이 없어 일정을 만들 수 없어요. 회원을 먼저 연결해 주세요.'**
  String get schedNewNeedsClient;

  /// No description provided for @schedClientsLoading.
  ///
  /// In ko, this message translates to:
  /// **'회원 목록을 불러오는 중이에요. 잠시 후 다시 눌러 주세요.'**
  String get schedClientsLoading;

  /// No description provided for @schedRepeatConflictTitle.
  ///
  /// In ko, this message translates to:
  /// **'총 {total}회 중 {count}개의 일정이 겹쳐요'**
  String schedRepeatConflictTitle(int total, int count);

  /// No description provided for @schedRepeatConflictRow.
  ///
  /// In ko, this message translates to:
  /// **'{date} {time} · 기존 일정: {name}'**
  String schedRepeatConflictRow(String date, String time, String name);

  /// No description provided for @schedRepeatConflictHint.
  ///
  /// In ko, this message translates to:
  /// **'겹치는 회차가 있어 아무 일정도 만들지 않았어요. 시간을 바꾸거나 겹치는 일정을 정리해 주세요.'**
  String get schedRepeatConflictHint;

  /// No description provided for @schedOverlapTitle.
  ///
  /// In ko, this message translates to:
  /// **'다른 일정과 시간이 겹쳐요'**
  String get schedOverlapTitle;

  /// No description provided for @schedOverlapHint.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 않았어요. 시간을 바꾸거나 겹치는 일정을 옮긴 뒤 다시 저장해 주세요.'**
  String get schedOverlapHint;

  /// No description provided for @slotOverlapHint.
  ///
  /// In ko, this message translates to:
  /// **'자리를 열지 않았어요. 다른 시간을 고르거나 겹치는 일정을 옮겨 주세요.'**
  String get slotOverlapHint;

  /// No description provided for @consultOverlapHint.
  ///
  /// In ko, this message translates to:
  /// **'회원이 고른 시간에 이미 다른 일정이 있어 승인하지 않았어요. 겹치는 일정을 옮긴 뒤 다시 승인해 주세요.'**
  String get consultOverlapHint;

  /// No description provided for @schedNote.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 피드백'**
  String get schedNote;

  /// No description provided for @schedEditNote.
  ///
  /// In ko, this message translates to:
  /// **'피드백 수정'**
  String get schedEditNote;

  /// No description provided for @schedAddNote.
  ///
  /// In ko, this message translates to:
  /// **'피드백 추가'**
  String get schedAddNote;

  /// No description provided for @schedNoNote.
  ///
  /// In ko, this message translates to:
  /// **'아직 남긴 메모가 없어요'**
  String get schedNoNote;

  /// No description provided for @schedNoteOnlyHint.
  ///
  /// In ko, this message translates to:
  /// **'상담은 프로그램 대신 메모로 남겨요.'**
  String get schedNoteOnlyHint;

  /// No description provided for @schedNoteHint.
  ///
  /// In ko, this message translates to:
  /// **'회원에게 전할 피드백을 입력하세요. 회원 특이사항은 회원 상세 메모에 남겨 주세요'**
  String get schedNoteHint;

  /// No description provided for @schedNoteVisibleToMember.
  ///
  /// In ko, this message translates to:
  /// **'PT를 마치면 회원 앱에 피드백으로 보여요'**
  String get schedNoteVisibleToMember;

  /// No description provided for @schedConsultNote.
  ///
  /// In ko, this message translates to:
  /// **'상담 메모'**
  String get schedConsultNote;

  /// No description provided for @schedEditConsultNote.
  ///
  /// In ko, this message translates to:
  /// **'메모 수정'**
  String get schedEditConsultNote;

  /// No description provided for @schedAddConsultNote.
  ///
  /// In ko, this message translates to:
  /// **'메모 추가'**
  String get schedAddConsultNote;

  /// No description provided for @schedConsultNoteHint.
  ///
  /// In ko, this message translates to:
  /// **'상담에서 나눈 이야기를 적어 두세요'**
  String get schedConsultNoteHint;

  /// No description provided for @schedConsultNotePrivate.
  ///
  /// In ko, this message translates to:
  /// **'나만 보는 메모예요. 회원에게는 보이지 않아요.'**
  String get schedConsultNotePrivate;

  /// No description provided for @schedAddAction.
  ///
  /// In ko, this message translates to:
  /// **'추가'**
  String get schedAddAction;

  /// No description provided for @schedSaveAction.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get schedSaveAction;

  /// No description provided for @progInvalid.
  ///
  /// In ko, this message translates to:
  /// **'운동 이름과 세트 수를 확인해 주세요'**
  String get progInvalid;

  /// No description provided for @progSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'프로그램을 저장하지 못했어요. 다시 시도해 주세요'**
  String get progSaveFailed;

  /// No description provided for @progEditTitle.
  ///
  /// In ko, this message translates to:
  /// **'프로그램 수정'**
  String get progEditTitle;

  /// No description provided for @progAddTitle.
  ///
  /// In ko, this message translates to:
  /// **'프로그램 추가'**
  String get progAddTitle;

  /// No description provided for @progAddExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동 추가'**
  String get progAddExercise;

  /// No description provided for @progNoteHint.
  ///
  /// In ko, this message translates to:
  /// **'회원에게 전할 피드백을 입력하세요. 회원 특이사항은 회원 상세 메모에 남겨 주세요'**
  String get progNoteHint;

  /// No description provided for @progSaving.
  ///
  /// In ko, this message translates to:
  /// **'저장 중…'**
  String get progSaving;

  /// No description provided for @progSaveAction.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get progSaveAction;

  /// No description provided for @progSaveNoteAction.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get progSaveNoteAction;

  /// No description provided for @progExerciseName.
  ///
  /// In ko, this message translates to:
  /// **'운동 이름'**
  String get progExerciseName;

  /// No description provided for @progDeleteExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동 삭제'**
  String get progDeleteExercise;

  /// No description provided for @progSetsValue.
  ///
  /// In ko, this message translates to:
  /// **'{sets}세트'**
  String progSetsValue(int sets);

  /// No description provided for @progRepsValue.
  ///
  /// In ko, this message translates to:
  /// **'{reps}회'**
  String progRepsValue(int reps);

  /// No description provided for @progHoldValue.
  ///
  /// In ko, this message translates to:
  /// **'{seconds}초'**
  String progHoldValue(int seconds);

  /// No description provided for @progEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 계획된 프로그램이 없어요'**
  String get progEmpty;

  /// No description provided for @progEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'AI 추천 탭에서 프로그램을 만들어 보내거나, 메시지로 미리 조율해 보세요.'**
  String get progEmptyHint;

  /// No description provided for @schedSentTo.
  ///
  /// In ko, this message translates to:
  /// **'{name}님에게 보냄'**
  String schedSentTo(String name);

  /// No description provided for @schedSentProgramTo.
  ///
  /// In ko, this message translates to:
  /// **'{date} PT 프로그램 보내기'**
  String schedSentProgramTo(String date);

  /// No description provided for @slotPastTime.
  ///
  /// In ko, this message translates to:
  /// **'현재보다 이후 시간만 예약 가능 시간으로 열 수 있어요.'**
  String get slotPastTime;

  /// No description provided for @slotOpened.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간을 열었어요.'**
  String get slotOpened;

  /// No description provided for @slotStartTime.
  ///
  /// In ko, this message translates to:
  /// **'시작 시간'**
  String get slotStartTime;

  /// No description provided for @slotCloseTitle.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간 닫기'**
  String get slotCloseTitle;

  /// No description provided for @slotCloseBody.
  ///
  /// In ko, this message translates to:
  /// **'이미 잡힌 예약은 유지되고, 신규 예약만 멈춰요.'**
  String get slotCloseBody;

  /// No description provided for @slotClosed.
  ///
  /// In ko, this message translates to:
  /// **'신규 예약을 닫았어요.'**
  String get slotClosed;

  /// No description provided for @slotActionFailed.
  ///
  /// In ko, this message translates to:
  /// **'요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get slotActionFailed;

  /// No description provided for @slotManageTitle.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간 관리'**
  String get slotManageTitle;

  /// No description provided for @slotIntro.
  ///
  /// In ko, this message translates to:
  /// **'회원이 예약할 시간을 열어요. 아래에 앞으로 열린 시간이 날짜별로 모여요.'**
  String get slotIntro;

  /// No description provided for @slotOpenAction.
  ///
  /// In ko, this message translates to:
  /// **'열기'**
  String get slotOpenAction;

  /// No description provided for @slotReload.
  ///
  /// In ko, this message translates to:
  /// **'다시 불러오기'**
  String get slotReload;

  /// No description provided for @slotLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간을 불러오지 못했어요'**
  String get slotLoadFailed;

  /// No description provided for @slotEmpty.
  ///
  /// In ko, this message translates to:
  /// **'열린 예약 가능 시간이 없어요.'**
  String get slotEmpty;

  /// No description provided for @slotClosedSummary.
  ///
  /// In ko, this message translates to:
  /// **'예약 닫힘'**
  String get slotClosedSummary;

  /// No description provided for @slotBookedSummary.
  ///
  /// In ko, this message translates to:
  /// **'예약됨'**
  String get slotBookedSummary;

  /// No description provided for @slotOverlappedSummary.
  ///
  /// In ko, this message translates to:
  /// **'일정과 겹침'**
  String get slotOverlappedSummary;

  /// No description provided for @slotOverlappedHint.
  ///
  /// In ko, this message translates to:
  /// **'이 시간에 다른 일정이 있어 회원에게는 마감으로 보여요. 쓰지 않을 자리면 닫아 주세요.'**
  String get slotOverlappedHint;

  /// No description provided for @slotCloseAction.
  ///
  /// In ko, this message translates to:
  /// **'예약 닫기'**
  String get slotCloseAction;

  /// No description provided for @myCareerInvalid.
  ///
  /// In ko, this message translates to:
  /// **'경력은 0~80 사이의 연수로 입력해 주세요.'**
  String get myCareerInvalid;

  /// No description provided for @myProfileSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'프로필을 저장하지 못했어요.'**
  String get myProfileSaveFailed;

  /// No description provided for @myGymChangeFailed.
  ///
  /// In ko, this message translates to:
  /// **'소속 헬스장을 바꾸지 못했어요.'**
  String get myGymChangeFailed;

  /// No description provided for @myTabProfile.
  ///
  /// In ko, this message translates to:
  /// **'내 정보'**
  String get myTabProfile;

  /// No description provided for @myTabSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get myTabSettings;

  /// No description provided for @mySaving.
  ///
  /// In ko, this message translates to:
  /// **'저장 중…'**
  String get mySaving;

  /// No description provided for @myEditProfile.
  ///
  /// In ko, this message translates to:
  /// **'프로필 수정'**
  String get myEditProfile;

  /// No description provided for @mySaved.
  ///
  /// In ko, this message translates to:
  /// **'변경사항이 저장됐어요'**
  String get mySaved;

  /// No description provided for @myCertifications.
  ///
  /// In ko, this message translates to:
  /// **'자격증 · 인증'**
  String get myCertifications;

  /// No description provided for @myGym.
  ///
  /// In ko, this message translates to:
  /// **'소속 헬스장'**
  String get myGym;

  /// No description provided for @myNotifications.
  ///
  /// In ko, this message translates to:
  /// **'알림'**
  String get myNotifications;

  /// No description provided for @myNotifNewMessage.
  ///
  /// In ko, this message translates to:
  /// **'새 메시지 알림'**
  String get myNotifNewMessage;

  /// No description provided for @myNotifNotReady.
  ///
  /// In ko, this message translates to:
  /// **'곧 끌 수 있어요 — 지금은 항상 받아요'**
  String get myNotifNotReady;

  /// Notification settings card row shown while the saved settings are loading; switches stay disabled.
  ///
  /// In ko, this message translates to:
  /// **'알림 설정을 불러오는 중이에요'**
  String get myNotifLoading;

  /// Notification settings card row when loading the saved settings failed; shown with a retry button and switches stay disabled.
  ///
  /// In ko, this message translates to:
  /// **'알림 설정을 불러오지 못했어요. 다시 시도해 주세요'**
  String get myNotifLoadFailed;

  /// No description provided for @myNotifNewMessageHint.
  ///
  /// In ko, this message translates to:
  /// **'회원이 보낸 메시지'**
  String get myNotifNewMessageHint;

  /// No description provided for @myAccount.
  ///
  /// In ko, this message translates to:
  /// **'계정'**
  String get myAccount;

  /// No description provided for @myChangePassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 변경'**
  String get myChangePassword;

  /// No description provided for @myChangePasswordHint.
  ///
  /// In ko, this message translates to:
  /// **'현재 비밀번호를 확인한 뒤 교체해요'**
  String get myChangePasswordHint;

  /// No description provided for @myChangePasswordDemo.
  ///
  /// In ko, this message translates to:
  /// **'데모 모드에는 계정이 없어 변경할 수 없어요'**
  String get myChangePasswordDemo;

  /// No description provided for @myLoginAccount.
  ///
  /// In ko, this message translates to:
  /// **'로그인 계정'**
  String get myLoginAccount;

  /// No description provided for @mySupportTitle.
  ///
  /// In ko, this message translates to:
  /// **'고객 지원'**
  String get mySupportTitle;

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

  /// No description provided for @mySupportExternalHint.
  ///
  /// In ko, this message translates to:
  /// **'카카오톡 채널로 연결돼요'**
  String get mySupportExternalHint;

  /// No description provided for @mySupportOpenFailed.
  ///
  /// In ko, this message translates to:
  /// **'링크를 열지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get mySupportOpenFailed;

  /// No description provided for @myAppVersion.
  ///
  /// In ko, this message translates to:
  /// **'On-Care 트레이너 · 버전 {version}'**
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

  /// No description provided for @myAppName.
  ///
  /// In ko, this message translates to:
  /// **'On-Care 트레이너'**
  String get myAppName;

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

  /// No description provided for @myLegalTermsEffectiveDate.
  ///
  /// In ko, this message translates to:
  /// **'시행일 2026. 10. 03.'**
  String get myLegalTermsEffectiveDate;

  /// No description provided for @myLegalPrivacyEffectiveDate.
  ///
  /// In ko, this message translates to:
  /// **'시행일 2026. 10. 05.'**
  String get myLegalPrivacyEffectiveDate;

  /// No description provided for @myLegalTermsBody.
  ///
  /// In ko, this message translates to:
  /// **'제1조 (목적)\n이 약관은 On-Care(이하 \"회사\")가 제공하는 트레이너 콘솔(이하 \"서비스\")의 이용과 관련하여 회사와 트레이너 회원(이하 \"트레이너\") 간의 권리, 의무 및 책임사항을 규정함을 목적으로 합니다.\n\n제2조 (약관의 효력 및 변경)\n① 이 약관은 서비스를 이용하는 모든 트레이너에게 효력이 발생합니다.\n② 회사는 관련 법령을 위반하지 않는 범위에서 이 약관을 변경할 수 있으며, 변경 시 적용일자와 변경 사유를 명시하여 적용일 전에 서비스 내에 공지합니다.\n③ 동의가 필요한 변경은 다시 동의를 받습니다. 트레이너는 변경된 약관에 동의하지 않으면 이용 계약을 해지할 수 있습니다.\n\n제3조 (서비스의 제공)\n회사는 담당 회원 관리, 식단·운동 기록 열람, 일정 관리, 메시지, AI 코칭 프로그램 생성, 리포트 작성 및 전송 등 트레이너의 지도 업무를 돕는 기능을 제공합니다. 서비스의 구체적인 내용은 회사의 정책에 따라 변경될 수 있습니다.\n\n제4조 (계정)\n① 트레이너 계정과 회원 계정은 분리되어 있으며, 하나의 계정으로 두 서비스를 함께 이용할 수 없습니다.\n② 트레이너는 자격증·경력 등 프로필 정보를 사실대로 입력하여야 하며, 계정 정보의 관리 책임은 트레이너에게 있습니다.\n\n제5조 (회원 신고)\n① 트레이너는 가입하고 소속 헬스장을 고르면 별도의 승인 절차 없이 회원 앱의 트레이너 목록과 상담 신청 대상에 나타나고 회원과 연결할 수 있습니다.\n② 회원은 사칭, 사실과 다른 프로필, 부적절한 메시지 등을 이유로 트레이너를 신고할 수 있으며, 회사 운영자는 신고 내용을 확인해 제9조에 따라 이용을 제한할 수 있습니다.\n\n제6조 (회원 정보 취급 의무)\n① 트레이너는 담당 관계가 성립한 회원의 식단·운동·건강 기록에 한하여 열람할 수 있습니다.\n② 열람한 정보는 상담·코칭·리포트 작성 목적으로만 이용하여야 하며, 이를 외부에 게시하거나 제3자에게 제공·유출해서는 안 됩니다.\n③ 담당 관계가 종료되면 해당 회원 정보에 대한 열람 권한도 함께 종료됩니다.\n\n제7조 (회원 쿠폰의 사용 처리)\n① 회원이 포인트로 교환한 PT 재등록 할인 쿠폰은 그 회원의 담당 트레이너와 소속 헬스장에서 쓰입니다. 트레이너와 소속 헬스장은 쿠폰에 표시된 할인을 현장에서 제공합니다.\n② 쿠폰은 트레이너 또는 헬스장 직원이 회원 휴대폰의 쿠폰 화면에서 쿠폰 종류와 유효기간을 확인한 뒤, 회원이 사용 완료를 눌러 사용합니다. 사용 처리한 쿠폰은 되돌릴 수 없습니다.\n③ 담당 관계가 끝나거나 트레이너가 탈퇴하면 그 회원의 사용 전 PT 재등록 쿠폰은 취소되고 회원에게 포인트가 돌아갑니다.\n\n제8조 (금지 행위)\n트레이너는 의료 행위에 해당하는 진단·처방을 하거나, 회원의 동의 없이 회원 정보를 서비스 밖으로 옮기는 행위를 하여서는 안 됩니다.\n\n제9조 (이용 제한)\n회사는 트레이너가 이 약관을 어기거나, 사실과 다른 프로필로 회원을 모으거나, 회원에게 피해를 주면 미리 알린 뒤 서비스 이용의 일부 또는 전부를 제한하거나 계정을 정지할 수 있습니다. 회원의 피해를 막아야 하는 등 급한 경우에는 먼저 제한한 뒤 바로 알립니다.\n\n제10조 (책임의 제한)\n서비스가 제공하는 AI 코칭 결과와 통계는 지도를 돕기 위한 참고 자료입니다. 회원에게 전달하는 지도 내용에 대한 최종 판단과 책임은 트레이너에게 있으며, 회사는 법령이 허용하는 범위 내에서 그 결과에 대하여 책임을 부담하지 않습니다.\n\n제11조 (이용 계약의 해지)\n① 트레이너는 언제든지 MY 메뉴에서 탈퇴할 수 있습니다.\n② 탈퇴하면 계정과 함께 프로필, 회원과의 대화, 배정한 루틴, 일정과 예약 가능 시간이 지워지고, 담당 회원과의 연결과 예정된 예약이 함께 종료되며 해당 회원에게 그 사실이 안내됩니다.\n③ 담당 회원의 사용 전 PT 재등록 쿠폰은 취소되고 회원에게 포인트가 돌아갑니다.\n\n제12조 (서비스의 변경과 중단)\n회사는 서비스의 내용을 바꾸거나 설비 점검·장애 등 부득이한 사유로 서비스를 일시 중단할 수 있으며, 트레이너에게 영향이 있는 경우 미리 알리고, 미리 알릴 수 없었던 경우에는 사후에 알립니다.\n\n제13조 (분쟁 해결과 관할)\n① 회사와 트레이너는 서비스와 관련한 분쟁을 원만하게 해결하기 위해 성실히 협의합니다.\n② 협의로 해결되지 않아 소송이 제기되는 경우 민사소송법에 따른 관할 법원을 관할 법원으로 합니다.\n③ 이 약관과 서비스 이용에는 대한민국 법을 적용합니다.\n\n부칙\n이 약관은 2026년 10월 3일부터 시행합니다.\n- 2026년 10월 3일: 회원 신고, 회원 쿠폰의 사용 처리, 이용 제한, 이용 계약 해지의 효과, 서비스의 변경과 중단, 분쟁 해결과 관할 조항 추가\n- 2026년 10월 1일: 제정'**
  String get myLegalTermsBody;

  /// Privacy policy body. {contact} is the privacy officer contact, filled from LegalContact.privacyOfficerEmail in shared/oncare_core (the single definition point, #3005).
  ///
  /// In ko, this message translates to:
  /// **'On-Care(이하 \"회사\")는 「개인정보 보호법」 등 관련 법령을 준수하며, 트레이너와 회원의 개인정보를 소중히 보호합니다.\n\n1. 수집하는 개인정보 항목\n① 트레이너 가입: 이메일, 비밀번호(암호화하여 저장), 이름, 연락처.\n② 프로필과 자격 확인: 소속 헬스장, 자격증, 경력, 전문 분야 등 프로필 정보.\n③ 서비스 이용 중 남기는 정보: 회원에게 보낸 메시지와 첨부 사진, 리포트와 코칭 내용, 일정·예약 정보, 회원 메모.\n④ 자동으로 생성되는 정보: 로그인·비밀번호 변경 등 접속 기록(일시, IP 주소)과, 오류가 났을 때의 오류 내용·브라우저와 운영체제 종류·앱 버전.\n⑤ 위치 정보: 트레이너 웹은 기기의 위치정보를 받지 않습니다.\n\n2. 개인정보의 수집 및 이용 목적\n수집한 정보는 트레이너 식별과 운영자의 신고 처리와 계정 관리, 담당 회원 연결, 일정·메시지·리포트 기능 제공, 서비스 개선 및 문의 응대의 목적으로만 이용됩니다.\n\n3. 담당 회원 정보의 열람과 처리\n① 트레이너는 담당 관계가 성립한 회원에 한하여 그 회원이 기록한 식단·운동·체중 등 건강 정보를 서비스 안에서 열람할 수 있습니다.\n② 이 정보의 개인정보처리자는 회사이며, 트레이너는 회사가 정한 범위 안에서 코칭과 리포트 작성 목적으로만 이를 처리합니다. 회원의 건강정보는 민감정보로서 회원의 별도 동의와 데이터 공유 동의가 있을 때만 열람할 수 있습니다.\n③ 트레이너가 작성해 전송한 리포트와 메시지는 해당 회원에게 전달되고 서비스에 기록으로 남습니다.\n④ 담당 관계가 종료되면 해당 회원 정보에 대한 열람 권한은 즉시 회수되며, 회원은 자신의 정보 제공에 대한 동의를 언제든지 철회할 수 있습니다.\n\n4. 개인정보의 보유 및 이용 기간\n트레이너의 개인정보는 탈퇴 시까지 보유·이용하며, 탈퇴하면 8항의 절차에 따라 지체 없이 파기합니다. 다만 다음 기록은 정해진 기간 동안 보관한 뒤 파기합니다.\n- 로그인 등 접속 기록: 1년(「통신비밀보호법」상 로그인 기록 보존 의무 3개월 포함)\n- 트레이너의 회원 건강정보 열람 기록, 정보 제공 동의·철회 기록, 탈퇴 기록: 2년(「개인정보의 안전성 확보조치 기준」에 따른 처리 기록 보관)\n회원에게 전송된 리포트와 메시지는 회원의 기록이므로 회원의 보관 기간을 따릅니다.\n\n5. 개인정보의 제3자 제공\n회사는 트레이너와 회원의 동의 없이 개인정보를 외부에 제공하지 않습니다. 업무 처리를 맡기는 위탁은 6항과 7항을 따릅니다. 다만 법령에 특별한 규정이 있는 경우는 예외로 합니다.\n\n6. 개인정보 처리의 위탁\n회사는 서비스 제공을 위해 다음 업무를 외부 업체에 위탁합니다. 수탁자가 바뀌면 이 처리방침을 고쳐 알립니다.\n- Amazon Web Services, Inc.: 서버 운영, 채팅 사진·리포트 PDF 파일 보관\n- Neon: 데이터베이스 운영(계정 정보와 모든 기록 보관)\n- Google LLC: AI 코칭 프로그램·루틴 후보와 리포트 요약 생성(Gemini API)\n- 주식회사 카카오: 헬스장 검색과 지도 표시\n- Functional Software, Inc.(Sentry): 웹·서버 오류 수집과 분석\n\n7. 개인정보의 국외 이전\n회사는 트레이너와의 계약을 이행하기 위해 다음과 같이 개인정보를 국외에서 처리·보관하도록 위탁하며, 「개인정보 보호법」 제28조의8 제1항 제3호에 따라 이 처리방침으로 알립니다. 이전은 서비스를 이용할 때마다 암호화된 네트워크로 전송하는 방법으로 이루어집니다.\n① Amazon Web Services, Inc. / 싱가포르 / 트레이너 정보와 기록 전반, 채팅 첨부 사진과 리포트 PDF / 서버 운영과 파일 보관 / 탈퇴 또는 위탁 계약 종료 시까지\n② Neon / 싱가포르 / 계정·프로필, 메시지·리포트·일정 기록 / 데이터베이스 운영 / 탈퇴 또는 위탁 계약 종료 시까지\n③ Google LLC / 미국 등 Google이 운영하는 데이터센터 소재 국가 / AI 기능을 쓸 때 입력한 코칭 조건과 담당 회원의 운동 기록·주간 리포트 수치 / AI 프로그램·요약 생성 / 요청 처리 후 수탁자의 서비스 약관에서 정한 기간\n④ Functional Software, Inc.(Sentry) / 미국 / 오류 내용, 브라우저와 운영체제 종류·앱 버전(이름·이메일·IP 주소·요청 내용은 보내지 않음) / 오류 분석 / 수탁자의 보관 기간\n국외 이전을 원하지 않으면 탈퇴로 거부할 수 있으나, 이 경우 서비스를 이용할 수 없습니다.\n\n8. 개인정보의 파기 절차 및 방법\n① 절차: 트레이너가 탈퇴하면 즉시 계정과 함께 프로필, 담당 회원과의 연결과 대화(첨부 사진·리포트 PDF 파일 포함), 루틴·프로그램, 일정과 예약 가능 시간, 알림을 삭제하고, 담당 회원과 예약한 회원에게 그 사실을 알립니다. 회원이 보낸 상담 요청은 회원의 기록이므로 트레이너 정보만 지운 채 남습니다. 4항에 따라 보관하는 기록은 기간이 지나면 자동으로 삭제합니다.\n② 방법: 전자적 파일 형태의 정보는 데이터베이스와 파일 저장소에서 삭제하며, 데이터베이스 복구용 백업에 남은 사본은 백업 보관 기간이 지나면 함께 사라집니다. 회사는 개인정보를 종이 문서로 처리하지 않습니다.\n\n9. 개인정보 자동 수집 장치의 설치·운영 및 거부\n회사는 광고·행태 분석을 위한 쿠키나 추적 도구를 쓰지 않습니다. 로그인 상태를 유지하기 위해 브라우저 저장소에 인증 정보를 보관하며, 로그아웃하거나 브라우저 데이터를 지우면 삭제됩니다.\n\n10. 안전성 확보 조치\n회사는 비밀번호를 암호화하여 저장하고, 회원 정보에 대한 접근 권한을 담당 관계를 기준으로 제한하며, 전송 구간을 암호화합니다. 열람 기록에는 열람한 트레이너, 대상 회원, 정보의 종류와 시각만 남기며 건강정보의 내용은 담지 않습니다. 오류 보고에서는 이름·이메일·IP 주소와 요청 내용을 지우고 보냅니다.\n\n11. 만 14세 미만 아동의 개인정보\n회사는 만 14세 미만 아동의 가입을 받지 않으며, 가입할 때 만 14세 이상인지 확인합니다.\n\n12. 이용자의 권리\n트레이너는 언제든지 자신의 개인정보를 조회·수정하거나 처리 정지 및 삭제를 요청할 수 있습니다. 프로필 수정과 탈퇴는 MY 메뉴에서 할 수 있고, 그 밖의 요청은 13항의 연락처로 보내 주시면 지체 없이 조치합니다.\n\n13. 개인정보 보호책임자\n회사는 개인정보 처리에 관한 업무를 총괄하고 관련 불만 처리와 피해 구제를 위해 개인정보 보호책임자를 지정하고 있습니다.\n- 직책: On-Care 서비스 운영팀 개인정보 보호책임자\n- 연락처: {contact}\n\n14. 권익침해 구제 방법\n개인정보 침해에 대한 신고나 상담이 필요하면 다음 기관에 문의할 수 있습니다.\n- 개인정보분쟁조정위원회: 국번없이 1833-6972 (www.kopico.go.kr)\n- 개인정보침해신고센터: 국번없이 118 (privacy.kisa.or.kr)\n- 대검찰청: 국번없이 1301 (www.spo.go.kr)\n- 경찰청: 국번없이 182 (ecrm.police.go.kr)\n\n15. 처리방침의 변경\n이 처리방침을 바꾸면 시행일 전에 서비스 안에 알리며, 동의가 필요한 변경은 다시 동의를 받습니다.\n- 2026년 10월 5일: 개인정보 보호책임자 연락처 변경, 트레이너 웹이 위치정보를 받지 않는다는 항목 추가(1항 ⑤)\n- 2026년 10월 3일: 처리 위탁·국외 이전·파기 절차·자동 수집 장치·만 14세 미만·보호책임자·권익침해 구제 항목 추가\n- 2026년 10월 1일: 제정\n\n시행일: 2026년 10월 5일'**
  String myLegalPrivacyBody(String contact);

  /// No description provided for @myPasswordChanged.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 바꿨어요'**
  String get myPasswordChanged;

  /// Career tag on the trainer profile. The value is stored as a number of years.
  ///
  /// In ko, this message translates to:
  /// **'경력 {years}년'**
  String myCareerYears(int years);

  /// Career value under the 경력 label — the label already says it is career, so only the years.
  ///
  /// In ko, this message translates to:
  /// **'{years}년'**
  String myCareerYearsValue(int years);

  /// No description provided for @myFieldName.
  ///
  /// In ko, this message translates to:
  /// **'이름 (계정 정보)'**
  String get myFieldName;

  /// No description provided for @myFieldEmail.
  ///
  /// In ko, this message translates to:
  /// **'이메일 (계정 정보)'**
  String get myFieldEmail;

  /// No description provided for @myFieldPhone.
  ///
  /// In ko, this message translates to:
  /// **'연락처'**
  String get myFieldPhone;

  /// No description provided for @myFieldSpecialty.
  ///
  /// In ko, this message translates to:
  /// **'전문 분야'**
  String get myFieldSpecialty;

  /// No description provided for @myFieldCareer.
  ///
  /// In ko, this message translates to:
  /// **'경력'**
  String get myFieldCareer;

  /// No description provided for @myFieldIntro.
  ///
  /// In ko, this message translates to:
  /// **'소개'**
  String get myFieldIntro;

  /// No description provided for @myAddCertification.
  ///
  /// In ko, this message translates to:
  /// **'자격증 추가...'**
  String get myAddCertification;

  /// No description provided for @myAdd.
  ///
  /// In ko, this message translates to:
  /// **'추가'**
  String get myAdd;

  /// No description provided for @myStatClients.
  ///
  /// In ko, this message translates to:
  /// **'담당 회원'**
  String get myStatClients;

  /// No description provided for @myClientManagement.
  ///
  /// In ko, this message translates to:
  /// **'회원 관리'**
  String get myClientManagement;

  /// No description provided for @myClientRemove.
  ///
  /// In ko, this message translates to:
  /// **'연결 해제'**
  String get myClientRemove;

  /// Confirm button of the disconnect-member dialog. Noun form per the button rule (#3117); the row tooltip keeps myClientRemove.
  ///
  /// In ko, this message translates to:
  /// **'해제'**
  String get myClientRemoveConfirm;

  /// No description provided for @myClientRemoveTitle.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원과 연결을 해제할까요?'**
  String myClientRemoveTitle(String name);

  /// No description provided for @myClientRemoveBody.
  ///
  /// In ko, this message translates to:
  /// **'연결을 해제하면 이 회원의 스케줄, 프로그램·개인운동, 리포트, 메시지, 메모가 트레이너 화면에서 보이지 않아요. 회원 계정과 회원 앱의 기록은 그대로 남아요.'**
  String get myClientRemoveBody;

  /// No description provided for @myClientRemoveSuccess.
  ///
  /// In ko, this message translates to:
  /// **'회원과 연결을 해제했어요'**
  String get myClientRemoveSuccess;

  /// No description provided for @myClientRemoveFailed.
  ///
  /// In ko, this message translates to:
  /// **'연결을 해제하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get myClientRemoveFailed;

  /// No description provided for @myClientManagementEmpty.
  ///
  /// In ko, this message translates to:
  /// **'담당 회원이 없어요'**
  String get myClientManagementEmpty;

  /// No description provided for @myClientManagementSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'이름으로 회원 검색'**
  String get myClientManagementSearchHint;

  /// No description provided for @myBasicInfo.
  ///
  /// In ko, this message translates to:
  /// **'기본 정보'**
  String get myBasicInfo;

  /// No description provided for @myStatSessionsDone.
  ///
  /// In ko, this message translates to:
  /// **'완료 PT'**
  String get myStatSessionsDone;

  /// No description provided for @myStatRoutinesSent.
  ///
  /// In ko, this message translates to:
  /// **'프로그램 전송'**
  String get myStatRoutinesSent;

  /// No description provided for @myGymName.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 이름'**
  String get myGymName;

  /// No description provided for @myGymAddress.
  ///
  /// In ko, this message translates to:
  /// **'주소'**
  String get myGymAddress;

  /// No description provided for @myGymHours.
  ///
  /// In ko, this message translates to:
  /// **'운영 시간'**
  String get myGymHours;

  /// No description provided for @myGymRequired.
  ///
  /// In ko, this message translates to:
  /// **'검색 결과에서 소속 헬스장을 골라 주세요'**
  String get myGymRequired;

  /// No description provided for @myGymSearchLabel.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 찾기'**
  String get myGymSearchLabel;

  /// No description provided for @myGymSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 이름이나 주소'**
  String get myGymSearchHint;

  /// No description provided for @myGymSearching.
  ///
  /// In ko, this message translates to:
  /// **'찾는 중이에요'**
  String get myGymSearching;

  /// No description provided for @myGymSearchEmpty.
  ///
  /// In ko, this message translates to:
  /// **'찾는 헬스장이 없어요. 이름을 다르게 적거나 동네 이름을 붙여 보세요.'**
  String get myGymSearchEmpty;

  /// No description provided for @myGymSearchFailed.
  ///
  /// In ko, this message translates to:
  /// **'헬스장을 찾지 못했어요. 잠시 뒤 다시 시도해 주세요.'**
  String get myGymSearchFailed;

  /// No description provided for @myGymLocateAction.
  ///
  /// In ko, this message translates to:
  /// **'현재 위치로 찾기'**
  String get myGymLocateAction;

  /// No description provided for @myGymNearbyCaption.
  ///
  /// In ko, this message translates to:
  /// **'현재 위치에서 가까운 헬스장이에요. 위치는 저장하지 않아요.'**
  String get myGymNearbyCaption;

  /// No description provided for @myGymNearbyEmpty.
  ///
  /// In ko, this message translates to:
  /// **'현재 위치 2km 안에서 헬스장을 찾지 못했어요. 이름으로 찾아 보세요.'**
  String get myGymNearbyEmpty;

  /// No description provided for @myGymLocationDenied.
  ///
  /// In ko, this message translates to:
  /// **'위치 사용을 허용하면 주변 헬스장을 찾을 수 있어요.'**
  String get myGymLocationDenied;

  /// No description provided for @myGymLocationBlocked.
  ///
  /// In ko, this message translates to:
  /// **'브라우저 사이트 설정에서 위치 사용을 허용한 뒤 다시 눌러 주세요.'**
  String get myGymLocationBlocked;

  /// No description provided for @myGymLocationDisabled.
  ///
  /// In ko, this message translates to:
  /// **'기기의 위치 서비스를 켠 뒤 다시 눌러 주세요.'**
  String get myGymLocationDisabled;

  /// No description provided for @myGymLocationUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'현재 위치를 가져오지 못했어요. 다시 시도하거나 이름으로 찾아 보세요.'**
  String get myGymLocationUnavailable;

  /// No description provided for @myGymCurrent.
  ///
  /// In ko, this message translates to:
  /// **'현재 소속'**
  String get myGymCurrent;

  /// No description provided for @myGymPicked.
  ///
  /// In ko, this message translates to:
  /// **'저장하면 이 헬스장으로 바뀌어요'**
  String get myGymPicked;

  /// No description provided for @myGymNone.
  ///
  /// In ko, this message translates to:
  /// **'아직 없어요'**
  String get myGymNone;

  /// No description provided for @myGymHiddenTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원에게 아직 보이지 않아요'**
  String get myGymHiddenTitle;

  /// No description provided for @myGymHiddenBody.
  ///
  /// In ko, this message translates to:
  /// **'소속 헬스장을 설정해야 회원 앱의 헬스장 찾기와 상담 신청에 나와요.'**
  String get myGymHiddenBody;

  /// No description provided for @myGymHiddenAction.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 설정'**
  String get myGymHiddenAction;

  /// No description provided for @navAdminGroup.
  ///
  /// In ko, this message translates to:
  /// **'운영'**
  String get navAdminGroup;

  /// No description provided for @navAdminReports.
  ///
  /// In ko, this message translates to:
  /// **'신고·계정 관리'**
  String get navAdminReports;

  /// No description provided for @adminReportsTitle.
  ///
  /// In ko, this message translates to:
  /// **'신고·계정 관리'**
  String get adminReportsTitle;

  /// No description provided for @adminReportsSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'회원이 보낸 트레이너 신고를 확인하고, 필요하면 트레이너 계정을 정지하거나 풀어요.'**
  String get adminReportsSubtitle;

  /// No description provided for @adminSectionReports.
  ///
  /// In ko, this message translates to:
  /// **'신고'**
  String get adminSectionReports;

  /// No description provided for @adminSectionTrainers.
  ///
  /// In ko, this message translates to:
  /// **'트레이너'**
  String get adminSectionTrainers;

  /// No description provided for @adminReportFilterOpen.
  ///
  /// In ko, this message translates to:
  /// **'처리 전'**
  String get adminReportFilterOpen;

  /// No description provided for @adminReportFilterClosed.
  ///
  /// In ko, this message translates to:
  /// **'처리됨'**
  String get adminReportFilterClosed;

  /// No description provided for @adminReportStatusResolved.
  ///
  /// In ko, this message translates to:
  /// **'조치함'**
  String get adminReportStatusResolved;

  /// No description provided for @adminReportStatusDismissed.
  ///
  /// In ko, this message translates to:
  /// **'넘김'**
  String get adminReportStatusDismissed;

  /// No description provided for @adminReasonImpersonation.
  ///
  /// In ko, this message translates to:
  /// **'소속·신원 사칭'**
  String get adminReasonImpersonation;

  /// No description provided for @adminReasonInappropriateMessage.
  ///
  /// In ko, this message translates to:
  /// **'부적절한 메시지'**
  String get adminReasonInappropriateMessage;

  /// No description provided for @adminReasonOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get adminReasonOther;

  /// No description provided for @adminFieldTarget.
  ///
  /// In ko, this message translates to:
  /// **'대상'**
  String get adminFieldTarget;

  /// No description provided for @adminFieldReason.
  ///
  /// In ko, this message translates to:
  /// **'사유'**
  String get adminFieldReason;

  /// No description provided for @adminFieldMemo.
  ///
  /// In ko, this message translates to:
  /// **'내용'**
  String get adminFieldMemo;

  /// No description provided for @adminFieldReportedAt.
  ///
  /// In ko, this message translates to:
  /// **'신고일'**
  String get adminFieldReportedAt;

  /// No description provided for @adminFieldResolvedAt.
  ///
  /// In ko, this message translates to:
  /// **'처리일'**
  String get adminFieldResolvedAt;

  /// No description provided for @adminFieldOpenReports.
  ///
  /// In ko, this message translates to:
  /// **'처리 전 신고'**
  String get adminFieldOpenReports;

  /// No description provided for @adminOpenReportsCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}건'**
  String adminOpenReportsCount(int count);

  /// No description provided for @adminReportsLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'신고 목록을 불러오지 못했어요'**
  String get adminReportsLoadFailed;

  /// No description provided for @adminReportsEmptyOpen.
  ///
  /// In ko, this message translates to:
  /// **'처리할 신고가 없어요'**
  String get adminReportsEmptyOpen;

  /// No description provided for @adminReportsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'해당하는 신고가 없어요'**
  String get adminReportsEmpty;

  /// No description provided for @adminTrainerSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'이름이나 이메일로 찾기'**
  String get adminTrainerSearchHint;

  /// No description provided for @adminStateActive.
  ///
  /// In ko, this message translates to:
  /// **'이용 중'**
  String get adminStateActive;

  /// No description provided for @adminResolve.
  ///
  /// In ko, this message translates to:
  /// **'조치함'**
  String get adminResolve;

  /// No description provided for @adminDismiss.
  ///
  /// In ko, this message translates to:
  /// **'넘김'**
  String get adminDismiss;

  /// No description provided for @adminResolveTitle.
  ///
  /// In ko, this message translates to:
  /// **'{name} 신고를 조치함으로 닫을까요?'**
  String adminResolveTitle(String name);

  /// No description provided for @adminResolveBody.
  ///
  /// In ko, this message translates to:
  /// **'계정 정지 같은 조치를 마친 신고를 닫아요. 신고를 닫아도 계정 상태는 바뀌지 않아요.'**
  String get adminResolveBody;

  /// No description provided for @adminDismissTitle.
  ///
  /// In ko, this message translates to:
  /// **'{name} 신고를 넘길까요?'**
  String adminDismissTitle(String name);

  /// No description provided for @adminDismissBody.
  ///
  /// In ko, this message translates to:
  /// **'조치가 필요 없는 신고를 닫아요. 계정 상태는 바뀌지 않아요.'**
  String get adminDismissBody;

  /// No description provided for @adminReportResolved.
  ///
  /// In ko, this message translates to:
  /// **'신고를 조치함으로 닫았어요'**
  String get adminReportResolved;

  /// No description provided for @adminReportDismissed.
  ///
  /// In ko, this message translates to:
  /// **'신고를 넘겼어요'**
  String get adminReportDismissed;

  /// No description provided for @adminRefresh.
  ///
  /// In ko, this message translates to:
  /// **'새로고침'**
  String get adminRefresh;

  /// No description provided for @adminFilterAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get adminFilterAll;

  /// No description provided for @adminStatusSuspended.
  ///
  /// In ko, this message translates to:
  /// **'정지됨'**
  String get adminStatusSuspended;

  /// No description provided for @adminTrainersLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 목록을 불러오지 못했어요'**
  String get adminTrainersLoadFailed;

  /// No description provided for @adminActionRetryLater.
  ///
  /// In ko, this message translates to:
  /// **'잠시 뒤 다시 시도해 주세요.'**
  String get adminActionRetryLater;

  /// No description provided for @adminTrainersEmpty.
  ///
  /// In ko, this message translates to:
  /// **'해당하는 트레이너가 없어요'**
  String get adminTrainersEmpty;

  /// No description provided for @adminTrainerUnnamed.
  ///
  /// In ko, this message translates to:
  /// **'이름 없는 트레이너'**
  String get adminTrainerUnnamed;

  /// No description provided for @adminFieldEmail.
  ///
  /// In ko, this message translates to:
  /// **'이메일'**
  String get adminFieldEmail;

  /// No description provided for @adminFieldGym.
  ///
  /// In ko, this message translates to:
  /// **'소속'**
  String get adminFieldGym;

  /// No description provided for @adminFieldSignedUp.
  ///
  /// In ko, this message translates to:
  /// **'가입일'**
  String get adminFieldSignedUp;

  /// No description provided for @adminGymNone.
  ///
  /// In ko, this message translates to:
  /// **'소속 헬스장이 없어요'**
  String get adminGymNone;

  /// No description provided for @adminSuspend.
  ///
  /// In ko, this message translates to:
  /// **'계정 정지'**
  String get adminSuspend;

  /// No description provided for @adminUnsuspend.
  ///
  /// In ko, this message translates to:
  /// **'정지 해제'**
  String get adminUnsuspend;

  /// No description provided for @adminSuspendTitle.
  ///
  /// In ko, this message translates to:
  /// **'{name} 계정을 정지할까요?'**
  String adminSuspendTitle(String name);

  /// No description provided for @adminSuspendBody.
  ///
  /// In ko, this message translates to:
  /// **'정지하면 바로 로그아웃되고 다시 로그인할 수 없어요. 담당 회원 연결은 모두 해제되어 회원에게 알림이 가고, 시작 전 PT 일정은 취소돼요. 정지를 풀어도 연결은 돌아오지 않아요.'**
  String get adminSuspendBody;

  /// No description provided for @adminUnsuspendTitle.
  ///
  /// In ko, this message translates to:
  /// **'{name} 계정 정지를 풀까요?'**
  String adminUnsuspendTitle(String name);

  /// No description provided for @adminUnsuspendBody.
  ///
  /// In ko, this message translates to:
  /// **'다시 로그인할 수 있어요. 해제된 담당 회원 연결은 회원이 다시 동의해야 이어져요.'**
  String get adminUnsuspendBody;

  /// No description provided for @adminSuspended.
  ///
  /// In ko, this message translates to:
  /// **'{name} 계정을 정지했어요'**
  String adminSuspended(String name);

  /// No description provided for @adminSuspendedReleased.
  ///
  /// In ko, this message translates to:
  /// **'{name} 계정을 정지하고 담당 회원 {count}명의 연결을 해제했어요'**
  String adminSuspendedReleased(String name, int count);

  /// No description provided for @adminUnsuspended.
  ///
  /// In ko, this message translates to:
  /// **'{name} 계정 정지를 풀었어요'**
  String adminUnsuspended(String name);

  /// No description provided for @adminActionFailed.
  ///
  /// In ko, this message translates to:
  /// **'처리하지 못했어요. 잠시 뒤 다시 시도해 주세요.'**
  String get adminActionFailed;

  /// No description provided for @myGymEditHint.
  ///
  /// In ko, this message translates to:
  /// **'이름으로 찾아 소속 헬스장을 골라 주세요. 회원은 이 헬스장으로 트레이너님을 찾아요.'**
  String get myGymEditHint;

  /// No description provided for @mySignOut.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃'**
  String get mySignOut;

  /// No description provided for @myPwCurrentRequired.
  ///
  /// In ko, this message translates to:
  /// **'현재 비밀번호를 입력해 주세요'**
  String get myPwCurrentRequired;

  /// No description provided for @myPwMismatch.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호가 서로 달라요'**
  String get myPwMismatch;

  /// No description provided for @myPwChangeFailed.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 바꾸지 못했어요'**
  String get myPwChangeFailed;

  /// No description provided for @myPwChangeRetry.
  ///
  /// In ko, this message translates to:
  /// **'바꾸지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get myPwChangeRetry;

  /// No description provided for @myPwCurrent.
  ///
  /// In ko, this message translates to:
  /// **'현재 비밀번호'**
  String get myPwCurrent;

  /// No description provided for @myPwNew.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호 (영문·숫자 포함 {min}자 이상)'**
  String myPwNew(int min);

  /// No description provided for @myPwConfirm.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호 확인'**
  String get myPwConfirm;

  /// No description provided for @myPwChanging.
  ///
  /// In ko, this message translates to:
  /// **'변경 중…'**
  String get myPwChanging;

  /// No description provided for @mySettingsSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get mySettingsSaveFailed;

  /// No description provided for @myProfileSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'담당 회원에게 보이는 내 소개와 이번 달 활동이에요'**
  String get myProfileSubtitle;

  /// No description provided for @myClientsSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'담당 회원 연결을 정리해요'**
  String get myClientsSubtitle;

  /// No description provided for @myAccountSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'로그인 계정과 비밀번호를 관리해요'**
  String get myAccountSubtitle;

  /// No description provided for @mySupportSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'궁금한 점을 묻거나 약관을 확인해요'**
  String get mySupportSubtitle;

  /// No description provided for @myWithdrawSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴하기 전에 한 번만 확인해 주세요'**
  String get myWithdrawSubtitle;

  /// No description provided for @myPageTitle.
  ///
  /// In ko, this message translates to:
  /// **'내 정보 · 설정'**
  String get myPageTitle;

  /// No description provided for @myProfileTitle.
  ///
  /// In ko, this message translates to:
  /// **'프로필'**
  String get myProfileTitle;

  /// No description provided for @myEmail.
  ///
  /// In ko, this message translates to:
  /// **'이메일'**
  String get myEmail;

  /// No description provided for @myBasicInfoHint.
  ///
  /// In ko, this message translates to:
  /// **'담당 회원이 트레이너 소개에서 보는 정보예요'**
  String get myBasicInfoHint;

  /// No description provided for @myNotificationsHint.
  ///
  /// In ko, this message translates to:
  /// **'어떤 알림을 받을지 골라요'**
  String get myNotificationsHint;

  /// No description provided for @myAccountInfo.
  ///
  /// In ko, this message translates to:
  /// **'계정 정보'**
  String get myAccountInfo;

  /// No description provided for @myAccountInfoHint.
  ///
  /// In ko, this message translates to:
  /// **'이름·이메일을 바꾸려면 고객 지원으로 문의해 주세요.'**
  String get myAccountInfoHint;

  /// No description provided for @mySecurity.
  ///
  /// In ko, this message translates to:
  /// **'보안'**
  String get mySecurity;

  /// No description provided for @myDiscardTitle.
  ///
  /// In ko, this message translates to:
  /// **'변경사항을 저장할까요?'**
  String get myDiscardTitle;

  /// No description provided for @myDiscardBody.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 않고 나가면 고친 내용이 사라져요.'**
  String get myDiscardBody;

  /// No description provided for @myKeepEditing.
  ///
  /// In ko, this message translates to:
  /// **'계속 수정'**
  String get myKeepEditing;

  /// No description provided for @myDiscardAction.
  ///
  /// In ko, this message translates to:
  /// **'저장 안 함'**
  String get myDiscardAction;

  /// No description provided for @mySaveAndLeave.
  ///
  /// In ko, this message translates to:
  /// **'저장하고 나가기'**
  String get mySaveAndLeave;

  /// No description provided for @mySignOutConfirm.
  ///
  /// In ko, this message translates to:
  /// **'이 브라우저에서 로그아웃할까요?'**
  String get mySignOutConfirm;

  /// No description provided for @myThisMonth.
  ///
  /// In ko, this message translates to:
  /// **'이번 달'**
  String get myThisMonth;

  /// No description provided for @myIntroEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 소개가 없어요. 프로필 수정에서 회원에게 보일 소개를 적어 주세요.'**
  String get myIntroEmpty;

  /// No description provided for @myCertsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'등록한 자격증이 없어요'**
  String get myCertsEmpty;

  /// No description provided for @myGymEmpty.
  ///
  /// In ko, this message translates to:
  /// **'소속 헬스장이 아직 없어요. 헬스장 설정에서 골라 주세요.'**
  String get myGymEmpty;

  /// No description provided for @myEditVisibleBody.
  ///
  /// In ko, this message translates to:
  /// **'전문 분야·경력·소개·자격증은 회원 앱의 트레이너 소개에 그대로 나와요.'**
  String get myEditVisibleBody;

  /// No description provided for @myClientManagementNoteTitle.
  ///
  /// In ko, this message translates to:
  /// **'연결을 해제해도 회원 기록은 남아요'**
  String get myClientManagementNoteTitle;

  /// No description provided for @myClientManagementNote.
  ///
  /// In ko, this message translates to:
  /// **'회원 앱의 기록은 남아요. 다시 담당하려면 회원 탭의 회원 연결에서 회원에게 받은 연결 코드를 입력해 주세요.'**
  String get myClientManagementNote;

  /// No description provided for @myNotifConsultation.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청'**
  String get myNotifConsultation;

  /// No description provided for @myNotifConsultationHint.
  ///
  /// In ko, this message translates to:
  /// **'상담 신청·취소, 담당 요청 수락·거절'**
  String get myNotifConsultationHint;

  /// No description provided for @myNotifReservation.
  ///
  /// In ko, this message translates to:
  /// **'예약'**
  String get myNotifReservation;

  /// No description provided for @myNotifReservationHint.
  ///
  /// In ko, this message translates to:
  /// **'예약 신청·취소'**
  String get myNotifReservationHint;

  /// No description provided for @myNotifMemberUpdates.
  ///
  /// In ko, this message translates to:
  /// **'담당 회원 소식'**
  String get myNotifMemberUpdates;

  /// No description provided for @myNotifMemberUpdatesHint.
  ///
  /// In ko, this message translates to:
  /// **'주간 피드백, 목표·이름 변경, 연결 해제'**
  String get myNotifMemberUpdatesHint;

  /// No description provided for @myNotifKindsTitle.
  ///
  /// In ko, this message translates to:
  /// **'받을 알림'**
  String get myNotifKindsTitle;

  /// No description provided for @myNotifDesktopTitle.
  ///
  /// In ko, this message translates to:
  /// **'데스크톱 알림'**
  String get myNotifDesktopTitle;

  /// No description provided for @myNotifDesktopHint.
  ///
  /// In ko, this message translates to:
  /// **'콘솔 탭을 열어 두면 다른 탭이나 프로그램을 쓰는 중에도 새 알림이 화면 구석에 떠요. 탭 제목의 안 읽은 수는 이 설정과 상관없이 보여요.'**
  String get myNotifDesktopHint;

  /// No description provided for @myNotifDesktopSwitch.
  ///
  /// In ko, this message translates to:
  /// **'이 브라우저에서 알림 받기'**
  String get myNotifDesktopSwitch;

  /// No description provided for @myNotifDesktopGranted.
  ///
  /// In ko, this message translates to:
  /// **'이 탭을 보고 있지 않을 때 새 알림을 띄워요'**
  String get myNotifDesktopGranted;

  /// No description provided for @myNotifDesktopNotAsked.
  ///
  /// In ko, this message translates to:
  /// **'켜면 브라우저가 알림을 허용할지 물어요'**
  String get myNotifDesktopNotAsked;

  /// No description provided for @myNotifDesktopDenied.
  ///
  /// In ko, this message translates to:
  /// **'브라우저에서 알림이 차단돼 있어요. 주소창 왼쪽 아이콘 › 알림을 \'허용\'으로 바꾼 뒤 새로 고쳐 주세요'**
  String get myNotifDesktopDenied;

  /// No description provided for @myNotifDesktopUnsupported.
  ///
  /// In ko, this message translates to:
  /// **'이 브라우저에서는 쓸 수 없어요. 컴퓨터의 Chrome·Edge·Whale 에서 켤 수 있어요'**
  String get myNotifDesktopUnsupported;

  /// No description provided for @myNotifDesktopOsHint.
  ///
  /// In ko, this message translates to:
  /// **'알림이 보이지 않으면 컴퓨터 설정에서 이 브라우저의 알림을 켜 주세요(Mac: 시스템 설정 › 알림). 바꾼 뒤에는 브라우저를 다시 켜야 할 수 있어요.'**
  String get myNotifDesktopOsHint;

  /// No description provided for @myNotifDesktopTest.
  ///
  /// In ko, this message translates to:
  /// **'시험 알림'**
  String get myNotifDesktopTest;

  /// No description provided for @myNotifDesktopTestTitle.
  ///
  /// In ko, this message translates to:
  /// **'On-Care 트레이너 알림이 켜졌어요'**
  String get myNotifDesktopTestTitle;

  /// No description provided for @myNotifDesktopTestBody.
  ///
  /// In ko, this message translates to:
  /// **'새 알림이 오면 이렇게 떠요'**
  String get myNotifDesktopTestBody;

  /// No description provided for @desktopAlertMessageBody.
  ///
  /// In ko, this message translates to:
  /// **'새 메시지가 왔어요'**
  String get desktopAlertMessageBody;

  /// No description provided for @desktopAlertSummaryTitle.
  ///
  /// In ko, this message translates to:
  /// **'새 알림 {count}건'**
  String desktopAlertSummaryTitle(int count);

  /// No description provided for @desktopAlertSummaryBody.
  ///
  /// In ko, this message translates to:
  /// **'알림함에서 확인해 보세요'**
  String get desktopAlertSummaryBody;

  /// No description provided for @routineTypeCardio.
  ///
  /// In ko, this message translates to:
  /// **'유산소'**
  String get routineTypeCardio;

  /// No description provided for @routineTypeStrength.
  ///
  /// In ko, this message translates to:
  /// **'근력'**
  String get routineTypeStrength;

  /// No description provided for @routineTypeStretching.
  ///
  /// In ko, this message translates to:
  /// **'스트레칭'**
  String get routineTypeStretching;

  /// No description provided for @routineTypeFlexibility.
  ///
  /// In ko, this message translates to:
  /// **'스트레칭'**
  String get routineTypeFlexibility;

  /// No description provided for @routineTypeOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get routineTypeOther;

  /// No description provided for @routineFieldType.
  ///
  /// In ko, this message translates to:
  /// **'운동 유형'**
  String get routineFieldType;

  /// No description provided for @routineFieldMinutes.
  ///
  /// In ko, this message translates to:
  /// **'운동 시간'**
  String get routineFieldMinutes;

  /// No description provided for @routineFieldTotalMinutes.
  ///
  /// In ko, this message translates to:
  /// **'총 운동 시간'**
  String get routineFieldTotalMinutes;

  /// No description provided for @routineFieldIntensity.
  ///
  /// In ko, this message translates to:
  /// **'운동 강도'**
  String get routineFieldIntensity;

  /// No description provided for @routineFieldDate.
  ///
  /// In ko, this message translates to:
  /// **'날짜'**
  String get routineFieldDate;

  /// No description provided for @routineFieldExerciseName.
  ///
  /// In ko, this message translates to:
  /// **'운동 이름'**
  String get routineFieldExerciseName;

  /// No description provided for @routineFieldExerciseNameHint.
  ///
  /// In ko, this message translates to:
  /// **'예) 스쿼트, 러닝머신'**
  String get routineFieldExerciseNameHint;

  /// No description provided for @routineFieldExerciseNameHintCardio.
  ///
  /// In ko, this message translates to:
  /// **'예) 러닝머신, 실내 자전거'**
  String get routineFieldExerciseNameHintCardio;

  /// No description provided for @routineFieldExerciseNameHintStrength.
  ///
  /// In ko, this message translates to:
  /// **'예) 스쿼트, 벤치프레스'**
  String get routineFieldExerciseNameHintStrength;

  /// No description provided for @routineFieldExerciseNameHintFlexibility.
  ///
  /// In ko, this message translates to:
  /// **'예) 전신 스트레칭, 요가'**
  String get routineFieldExerciseNameHintFlexibility;

  /// No description provided for @routineFieldExerciseNameHintOther.
  ///
  /// In ko, this message translates to:
  /// **'예) 재활 운동, 스포츠 활동'**
  String get routineFieldExerciseNameHintOther;

  /// Label of the one-line benefit field on a personal routine row. Left empty, the auto-filled benefit (shown as the placeholder) is sent (#2570).
  ///
  /// In ko, this message translates to:
  /// **'회원에게 보일 효과'**
  String get routineFieldEffect;

  /// No description provided for @routineFieldEffectHint.
  ///
  /// In ko, this message translates to:
  /// **'예) 오른쪽 어깨 보호'**
  String get routineFieldEffectHint;

  /// No description provided for @routineFieldSets.
  ///
  /// In ko, this message translates to:
  /// **'세트 수'**
  String get routineFieldSets;

  /// No description provided for @routineFieldReps.
  ///
  /// In ko, this message translates to:
  /// **'횟수'**
  String get routineFieldReps;

  /// No description provided for @routineFieldHold.
  ///
  /// In ko, this message translates to:
  /// **'버티는 시간'**
  String get routineFieldHold;

  /// No description provided for @routineFieldMeasure.
  ///
  /// In ko, this message translates to:
  /// **'재는 방법'**
  String get routineFieldMeasure;

  /// No description provided for @routineFieldWeight.
  ///
  /// In ko, this message translates to:
  /// **'중량'**
  String get routineFieldWeight;

  /// No description provided for @routineFieldCalories.
  ///
  /// In ko, this message translates to:
  /// **'예상 소모 칼로리'**
  String get routineFieldCalories;

  /// 이름을 적기 전에는 확정된 소모 칼로리를 띄우지 않는다 (#1312)
  ///
  /// In ko, this message translates to:
  /// **'운동 이름을 적어 주세요'**
  String get routineCaloriesNeedName;

  /// 트레이너 폼은 수행할 회원의 체중을 모르므로 늘 어림값이다 (#1312)
  ///
  /// In ko, this message translates to:
  /// **'운동 유형 평균으로 낸 어림값 · 회원이 수행하면 체중까지 반영된 값이 기록돼요'**
  String get routineCaloriesRoughEstimate;

  /// No description provided for @routineUnitHours.
  ///
  /// In ko, this message translates to:
  /// **'시간'**
  String get routineUnitHours;

  /// No description provided for @routineUnitMinutes.
  ///
  /// In ko, this message translates to:
  /// **'분'**
  String get routineUnitMinutes;

  /// No description provided for @routineUnitSets.
  ///
  /// In ko, this message translates to:
  /// **'세트'**
  String get routineUnitSets;

  /// No description provided for @routineUnitReps.
  ///
  /// In ko, this message translates to:
  /// **'회'**
  String get routineUnitReps;

  /// No description provided for @routineUnitSeconds.
  ///
  /// In ko, this message translates to:
  /// **'초'**
  String get routineUnitSeconds;

  /// No description provided for @routineUnitKg.
  ///
  /// In ko, this message translates to:
  /// **'kg'**
  String get routineUnitKg;

  /// No description provided for @routineKcalValue.
  ///
  /// In ko, this message translates to:
  /// **'{count}kcal'**
  String routineKcalValue(int count);

  /// No description provided for @intensityLight.
  ///
  /// In ko, this message translates to:
  /// **'가벼움'**
  String get intensityLight;

  /// No description provided for @intensityModerate.
  ///
  /// In ko, this message translates to:
  /// **'보통'**
  String get intensityModerate;

  /// No description provided for @intensityHigh.
  ///
  /// In ko, this message translates to:
  /// **'높음'**
  String get intensityHigh;

  /// No description provided for @coachTitle.
  ///
  /// In ko, this message translates to:
  /// **'프로그램'**
  String get coachTitle;

  /// No description provided for @coachSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'회원별 운동 프로그램을 만들고 배정·관리하세요'**
  String get coachSubtitle;

  /// No description provided for @coachSendFailed.
  ///
  /// In ko, this message translates to:
  /// **'보내지 못했어요. 다시 시도해 주세요'**
  String get coachSendFailed;

  /// No description provided for @coachSwitchClientTitle.
  ///
  /// In ko, this message translates to:
  /// **'다른 회원으로 바꿀까요?'**
  String get coachSwitchClientTitle;

  /// No description provided for @coachSwitchClientBody.
  ///
  /// In ko, this message translates to:
  /// **'아직 보내지 않은 작성 내용이 있어요. 회원을 바꾸면 지금 짠 프로그램과 개인운동이 사라져요.'**
  String get coachSwitchClientBody;

  /// No description provided for @coachSwitchClientConfirm.
  ///
  /// In ko, this message translates to:
  /// **'바꾸기'**
  String get coachSwitchClientConfirm;

  /// No description provided for @coachDraftResumeTitle.
  ///
  /// In ko, this message translates to:
  /// **'저장해 둔 작성 내용이 있어요'**
  String get coachDraftResumeTitle;

  /// Body of the coaching screen's resume prompt for an autosaved draft.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원에게 짜던 프로그램이 자동으로 저장되어 있어요. 이어서 쓸까요?'**
  String coachDraftResumeBody(String name);

  /// No description provided for @coachDraftResume.
  ///
  /// In ko, this message translates to:
  /// **'이어서 쓰기'**
  String get coachDraftResume;

  /// No description provided for @coachDraftDiscard.
  ///
  /// In ko, this message translates to:
  /// **'버리기'**
  String get coachDraftDiscard;

  /// No description provided for @personalRoutineTargetLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'PT 일정을 불러오지 못했어요'**
  String get personalRoutineTargetLoadFailed;

  /// No description provided for @personalRoutineStartPast.
  ///
  /// In ko, this message translates to:
  /// **'시작일이 지나 오늘로 바꿨어요. 확인하고 다시 보내 주세요'**
  String get personalRoutineStartPast;

  /// No description provided for @schedRoutinesReadFailed.
  ///
  /// In ko, this message translates to:
  /// **'붙어 있는 개인운동을 확인하지 못했어요. 다시 시도해 주세요'**
  String get schedRoutinesReadFailed;

  /// No description provided for @coachNoClients.
  ///
  /// In ko, this message translates to:
  /// **'등록된 회원이 없어요'**
  String get coachNoClients;

  /// No description provided for @coachTrainerAdded.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 추가'**
  String get coachTrainerAdded;

  /// No description provided for @coachTemplateAdded.
  ///
  /// In ko, this message translates to:
  /// **'{name} 템플릿 추가'**
  String coachTemplateAdded(String name);

  /// No description provided for @coachRegisteredOn.
  ///
  /// In ko, this message translates to:
  /// **'{date} 일정에 추가했어요'**
  String coachRegisteredOn(String date);

  /// No description provided for @coachRegisteredAttachedExisting.
  ///
  /// In ko, this message translates to:
  /// **'{date}에 이미 예정된 PT가 있어 그 PT에 프로그램만 추가됐어요 — 고른 시간 범위는 적용되지 않았어요'**
  String coachRegisteredAttachedExisting(String date);

  /// No description provided for @coachGoToSchedule.
  ///
  /// In ko, this message translates to:
  /// **'스케줄로 가기'**
  String get coachGoToSchedule;

  /// No description provided for @labelTomorrow.
  ///
  /// In ko, this message translates to:
  /// **'내일'**
  String get labelTomorrow;

  /// No description provided for @coachTemplates.
  ///
  /// In ko, this message translates to:
  /// **'프로그램 템플릿'**
  String get coachTemplates;

  /// No description provided for @coachMemberRecords.
  ///
  /// In ko, this message translates to:
  /// **'회원 기록'**
  String get coachMemberRecords;

  /// No description provided for @coachSentHistory.
  ///
  /// In ko, this message translates to:
  /// **'전송 이력'**
  String get coachSentHistory;

  /// No description provided for @coachLastDelivery.
  ///
  /// In ko, this message translates to:
  /// **'직전 전송'**
  String get coachLastDelivery;

  /// No description provided for @coachDeliveryPtWithRoutine.
  ///
  /// In ko, this message translates to:
  /// **'PT · 개인운동'**
  String get coachDeliveryPtWithRoutine;

  /// No description provided for @coachDeliveryRoutineOnly.
  ///
  /// In ko, this message translates to:
  /// **'개인운동만'**
  String get coachDeliveryRoutineOnly;

  /// No description provided for @coachDeliveryCancelledRoutineOnly.
  ///
  /// In ko, this message translates to:
  /// **'PT 취소 · 개인운동만'**
  String get coachDeliveryCancelledRoutineOnly;

  /// No description provided for @coachDeliveryOn.
  ///
  /// In ko, this message translates to:
  /// **'{date} 보냄'**
  String coachDeliveryOn(String date);

  /// No description provided for @coachUnsentRoutines.
  ///
  /// In ko, this message translates to:
  /// **'아직 보내지 않은 개인운동 {count}개'**
  String coachUnsentRoutines(int count);

  /// No description provided for @coachUnsentRoutinesBody.
  ///
  /// In ko, this message translates to:
  /// **'PT 가 끝났는데 아직 회원에게 가지 않았어요. 스케줄에서 그 일정을 열어 보낼 수 있어요.'**
  String get coachUnsentRoutinesBody;

  /// No description provided for @coachSendUnsentRoutines.
  ///
  /// In ko, this message translates to:
  /// **'스케줄에서 보내기'**
  String get coachSendUnsentRoutines;

  /// No description provided for @coachDeliveryProgramSection.
  ///
  /// In ko, this message translates to:
  /// **'프로그램'**
  String get coachDeliveryProgramSection;

  /// No description provided for @coachDeliveryRoutineSection.
  ///
  /// In ko, this message translates to:
  /// **'개인운동'**
  String get coachDeliveryRoutineSection;

  /// No description provided for @coachDeliveryNothing.
  ///
  /// In ko, this message translates to:
  /// **'보낸 것 없음'**
  String get coachDeliveryNothing;

  /// No description provided for @coachHistoryFailed.
  ///
  /// In ko, this message translates to:
  /// **'이력을 불러오지 못했어요'**
  String get coachHistoryFailed;

  /// No description provided for @coachHistoryEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 보낸 프로그램이 없어요'**
  String get coachHistoryEmpty;

  /// No description provided for @aiOptionRecovery.
  ///
  /// In ko, this message translates to:
  /// **'회복안'**
  String get aiOptionRecovery;

  /// No description provided for @aiOptionPush.
  ///
  /// In ko, this message translates to:
  /// **'강화안'**
  String get aiOptionPush;

  /// No description provided for @aiGenerateFailed.
  ///
  /// In ko, this message translates to:
  /// **'AI로 만들지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get aiGenerateFailed;

  /// No description provided for @aiGenerateInvalidConditions.
  ///
  /// In ko, this message translates to:
  /// **'생성 조건을 확인해 주세요. 총 운동 시간은 {min}~{max}분 사이여야 해요'**
  String aiGenerateInvalidConditions(int min, int max);

  /// No description provided for @aiGenerateMinutesHelper.
  ///
  /// In ko, this message translates to:
  /// **'{min}~{max}분 사이로 입력해 주세요'**
  String aiGenerateMinutesHelper(int min, int max);

  /// 429 when the trainer taps 생성 repeatedly. Not a failure — it works again shortly (#582).
  ///
  /// In ko, this message translates to:
  /// **'AI 생성을 너무 자주 요청했어요. 잠시 후 다시 시도해 주세요'**
  String get aiGenerateRateLimited;

  /// 429 daily_limit — the trainer used today's AI calls (coach, routine options, report summary). Opens again at KST midnight (#3032).
  ///
  /// In ko, this message translates to:
  /// **'오늘 AI 생성 한도를 다 썼어요. 내일 다시 이용해 주세요'**
  String get aiGenerateDailyLimit;

  /// No description provided for @aiExerciseNameRequired.
  ///
  /// In ko, this message translates to:
  /// **'운동 이름을 입력해 주세요'**
  String get aiExerciseNameRequired;

  /// No description provided for @aiKeepOneExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동을 하나 이상 남겨 주세요'**
  String get aiKeepOneExercise;

  /// No description provided for @aiAnalysing.
  ///
  /// In ko, this message translates to:
  /// **'AI가 분석 중…'**
  String get aiAnalysing;

  /// No description provided for @aiGenerateCandidates.
  ///
  /// In ko, this message translates to:
  /// **'맞춤 추천안 후보 생성'**
  String get aiGenerateCandidates;

  /// No description provided for @aiReviewDone.
  ///
  /// In ko, this message translates to:
  /// **'검토 완료'**
  String get aiReviewDone;

  /// No description provided for @aiRoutineFor.
  ///
  /// In ko, this message translates to:
  /// **'AI 추천안 · {name}'**
  String aiRoutineFor(String name);

  /// No description provided for @aiAnalysedData.
  ///
  /// In ko, this message translates to:
  /// **'회원 현황'**
  String get aiAnalysedData;

  /// No description provided for @aiGoal.
  ///
  /// In ko, this message translates to:
  /// **'목표'**
  String get aiGoal;

  /// No description provided for @aiOverTarget.
  ///
  /// In ko, this message translates to:
  /// **' · 목표 초과'**
  String get aiOverTarget;

  /// No description provided for @aiRecentCompletion.
  ///
  /// In ko, this message translates to:
  /// **'최근 완료율'**
  String get aiRecentCompletion;

  /// No description provided for @aiNoCompletionData.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 기록 없음'**
  String get aiNoCompletionData;

  /// No description provided for @aiCompletionLow.
  ///
  /// In ko, this message translates to:
  /// **' · 관리 필요'**
  String get aiCompletionLow;

  /// No description provided for @aiDietSignal.
  ///
  /// In ko, this message translates to:
  /// **'식단 주의'**
  String get aiDietSignal;

  /// No description provided for @aiSodiumOverDaysSuffix.
  ///
  /// In ko, this message translates to:
  /// **' · 최근 7일 중 {days}일 초과'**
  String aiSodiumOverDaysSuffix(int days);

  /// No description provided for @aiSugarAlsoOver.
  ///
  /// In ko, this message translates to:
  /// **' · 당류도 초과'**
  String get aiSugarAlsoOver;

  /// No description provided for @aiDirectionLabel.
  ///
  /// In ko, this message translates to:
  /// **'권장 방향'**
  String get aiDirectionLabel;

  /// No description provided for @aiDirectionLower.
  ///
  /// In ko, this message translates to:
  /// **'강도 낮춤 — 최근 완료율이 낮아요'**
  String get aiDirectionLower;

  /// No description provided for @aiDirectionCardio.
  ///
  /// In ko, this message translates to:
  /// **'유산소 비중 확대 — 나트륨 초과가 잦아요'**
  String get aiDirectionCardio;

  /// No description provided for @aiDirectionLowerAndCardio.
  ///
  /// In ko, this message translates to:
  /// **'강도 낮춤 · 유산소 비중 확대'**
  String get aiDirectionLowerAndCardio;

  /// No description provided for @aiDirectionKeep.
  ///
  /// In ko, this message translates to:
  /// **'현재 강도 유지'**
  String get aiDirectionKeep;

  /// No description provided for @aiDirectionNoData.
  ///
  /// In ko, this message translates to:
  /// **'기록이 쌓이면 판단해요'**
  String get aiDirectionNoData;

  /// No description provided for @aiBasisGoalLabel.
  ///
  /// In ko, this message translates to:
  /// **'목표'**
  String get aiBasisGoalLabel;

  /// No description provided for @aiBasisCompletionLabel.
  ///
  /// In ko, this message translates to:
  /// **'평균 완료율'**
  String get aiBasisCompletionLabel;

  /// No description provided for @aiBasisCompletionValue.
  ///
  /// In ko, this message translates to:
  /// **'{rate}%'**
  String aiBasisCompletionValue(int rate);

  /// No description provided for @aiBasisMethodLabel.
  ///
  /// In ko, this message translates to:
  /// **'생성 방식'**
  String get aiBasisMethodLabel;

  /// No description provided for @aiBasisMethodRule.
  ///
  /// In ko, this message translates to:
  /// **'규칙 기반'**
  String get aiBasisMethodRule;

  /// No description provided for @aiBasisMethodAi.
  ///
  /// In ko, this message translates to:
  /// **'AI 생성'**
  String get aiBasisMethodAi;

  /// No description provided for @aiBasisRequestLabel.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 요청'**
  String get aiBasisRequestLabel;

  /// No description provided for @aiBasisRequestValue.
  ///
  /// In ko, this message translates to:
  /// **'\"{request}\"'**
  String aiBasisRequestValue(String request);

  /// No description provided for @aiBasisConditionLabel.
  ///
  /// In ko, this message translates to:
  /// **'생성 조건'**
  String get aiBasisConditionLabel;

  /// No description provided for @aiBasisConditionMax.
  ///
  /// In ko, this message translates to:
  /// **'최대 {total}분 · 강도 {intensity}'**
  String aiBasisConditionMax(int total, String intensity);

  /// No description provided for @aiBasisConditionValue.
  ///
  /// In ko, this message translates to:
  /// **'{conditions} ({source})'**
  String aiBasisConditionValue(String conditions, String source);

  /// No description provided for @aiBasisConditionByTrainer.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 지정'**
  String get aiBasisConditionByTrainer;

  /// No description provided for @aiBasisConditionAuto.
  ///
  /// In ko, this message translates to:
  /// **'기록 기반 자동'**
  String get aiBasisConditionAuto;

  /// No description provided for @aiBasisConditionMixed.
  ///
  /// In ko, this message translates to:
  /// **'일부 지정'**
  String get aiBasisConditionMixed;

  /// No description provided for @aiFindingsTitle.
  ///
  /// In ko, this message translates to:
  /// **'이번 분석에서 찾은 것'**
  String get aiFindingsTitle;

  /// No description provided for @aiFindingSource.
  ///
  /// In ko, this message translates to:
  /// **' · {source}'**
  String aiFindingSource(String source);

  /// No description provided for @aiFindingAction.
  ///
  /// In ko, this message translates to:
  /// **'→ {action}'**
  String aiFindingAction(String action);

  /// No description provided for @aiOptionNext.
  ///
  /// In ko, this message translates to:
  /// **'연계안'**
  String get aiOptionNext;

  /// No description provided for @aiChatEvidenceTitle.
  ///
  /// In ko, this message translates to:
  /// **'참고한 최근 대화'**
  String get aiChatEvidenceTitle;

  /// No description provided for @aiChatEvidenceLink.
  ///
  /// In ko, this message translates to:
  /// **'참고한 대화 {count}줄'**
  String aiChatEvidenceLink(int count);

  /// No description provided for @aiEditOption.
  ///
  /// In ko, this message translates to:
  /// **'{option} 수정'**
  String aiEditOption(String option);

  /// No description provided for @aiEditBlurb.
  ///
  /// In ko, this message translates to:
  /// **'기존 AI 추천과 같은 방식으로 운동 이름·시간·구성을 수정할 수 있어요.'**
  String get aiEditBlurb;

  /// No description provided for @aiAddExerciseManually.
  ///
  /// In ko, this message translates to:
  /// **'운동 직접 추가하기'**
  String get aiAddExerciseManually;

  /// No description provided for @aiExerciseNameExample.
  ///
  /// In ko, this message translates to:
  /// **'예: 레그프레스 3세트'**
  String get aiExerciseNameExample;

  /// No description provided for @aiRegister.
  ///
  /// In ko, this message translates to:
  /// **'추가'**
  String get aiRegister;

  /// No description provided for @aiReviewedSuggestion.
  ///
  /// In ko, this message translates to:
  /// **'확정한 구성 · {option}'**
  String aiReviewedSuggestion(String option);

  /// No description provided for @aiReviewSummary.
  ///
  /// In ko, this message translates to:
  /// **'총 {total}분 · {count}종목 · 근력 {strength} · 유산소 {cardio}'**
  String aiReviewSummary(int total, int count, int strength, int cardio);

  /// No description provided for @aiReviewIntensityWarning.
  ///
  /// In ko, this message translates to:
  /// **'최근 완료율이 낮은데 강도가 높음이에요. 강도를 낮출지 확인해 주세요'**
  String get aiReviewIntensityWarning;

  /// No description provided for @aiEditsApplied.
  ///
  /// In ko, this message translates to:
  /// **'선택하고 수정한 내용이 최종 추천 목록에 반영됐어요.'**
  String get aiEditsApplied;

  /// No description provided for @aiApplyToTemplate.
  ///
  /// In ko, this message translates to:
  /// **'프로그램에 반영'**
  String get aiApplyToTemplate;

  /// No description provided for @aiAppliedToTemplate.
  ///
  /// In ko, this message translates to:
  /// **'AI 추천안이 프로그램에 반영됐어요.'**
  String get aiAppliedToTemplate;

  /// No description provided for @aiStepConditions.
  ///
  /// In ko, this message translates to:
  /// **'조건 설정'**
  String get aiStepConditions;

  /// No description provided for @aiStepReview.
  ///
  /// In ko, this message translates to:
  /// **'프로그램 선택'**
  String get aiStepReview;

  /// No description provided for @aiStepDone.
  ///
  /// In ko, this message translates to:
  /// **'프로그램 검토'**
  String get aiStepDone;

  /// No description provided for @aiSkipPtProgram.
  ///
  /// In ko, this message translates to:
  /// **'개인운동만 짜기'**
  String get aiSkipPtProgram;

  /// Evidence chip on an AI personal-exercise suggestion; server code recent_pt_feedback (#2301).
  ///
  /// In ko, this message translates to:
  /// **'최근 PT 피드백 반영'**
  String get routineEvidenceRecentPtFeedback;

  /// Evidence chip; server code strength_heavy (#2301).
  ///
  /// In ko, this message translates to:
  /// **'최근 근력 운동 비중 높음'**
  String get routineEvidenceStrengthHeavy;

  /// Evidence chip; server code blood_pressure_goal (#2301).
  ///
  /// In ko, this message translates to:
  /// **'혈압 관리 목표'**
  String get routineEvidenceBloodPressureGoal;

  /// Evidence chip; server code low_cardio (#2301).
  ///
  /// In ko, this message translates to:
  /// **'최근 유산소 비중 낮음'**
  String get routineEvidenceLowCardio;

  /// Evidence chip; server code recent_record (#2301).
  ///
  /// In ko, this message translates to:
  /// **'최근 운동 기록 반영'**
  String get routineEvidenceRecentRecord;

  /// Intensity of an AI A/B plan whose contract value is 낮음 (#2301).
  ///
  /// In ko, this message translates to:
  /// **'가벼움'**
  String get aiPlanIntensityLow;

  /// No description provided for @aiPersonalStepFull.
  ///
  /// In ko, this message translates to:
  /// **'개인운동은 한 번에 {count}개까지 정할 수 있어요.'**
  String aiPersonalStepFull(int count);

  /// No description provided for @aiPersonalEditDone.
  ///
  /// In ko, this message translates to:
  /// **'수정 완료'**
  String get aiPersonalEditDone;

  /// No description provided for @aiPersonalStepBadge.
  ///
  /// In ko, this message translates to:
  /// **'AI 제안 {count}'**
  String aiPersonalStepBadge(int count);

  /// No description provided for @aiPersonalStepIntro.
  ///
  /// In ko, this message translates to:
  /// **'최근 PT 피드백과 운동 기록을 바탕으로 {name}님에게 도움이 될 개인운동을 준비했어요. 여기 남긴 것만 회원에게 가요.'**
  String aiPersonalStepIntro(String name);

  /// No description provided for @aiPersonalStepLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'AI 개인운동 제안을 불러오지 못했어요'**
  String get aiPersonalStepLoadFailed;

  /// No description provided for @aiPersonalStepNoSuggestion.
  ///
  /// In ko, this message translates to:
  /// **'오늘은 AI 제안이 없어요. 아래에서 직접 더해 주세요.'**
  String get aiPersonalStepNoSuggestion;

  /// No description provided for @aiProgramExerciseRemoveBody.
  ///
  /// In ko, this message translates to:
  /// **'{name} 이번 프로그램 구성에서 빼요.'**
  String aiProgramExerciseRemoveBody(String name);

  /// No description provided for @aiPersonalDismissTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 운동을 뺄까요?'**
  String get aiPersonalDismissTitle;

  /// No description provided for @aiPersonalDismissBody.
  ///
  /// In ko, this message translates to:
  /// **'{name} 이번 개인운동에서 빼요. AI 제안이면 다시 올라오지 않아요.'**
  String aiPersonalDismissBody(String name);

  /// No description provided for @aiPersonalDismissTooltip.
  ///
  /// In ko, this message translates to:
  /// **'이 제안 빼기'**
  String get aiPersonalDismissTooltip;

  /// No description provided for @aiPersonalDismissed.
  ///
  /// In ko, this message translates to:
  /// **'{name} 추천하지 않아요'**
  String aiPersonalDismissed(String name);

  /// No description provided for @aiPersonalDismissFailed.
  ///
  /// In ko, this message translates to:
  /// **'처리하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get aiPersonalDismissFailed;

  /// No description provided for @aiStepSkipped.
  ///
  /// In ko, this message translates to:
  /// **'건너뜀'**
  String get aiStepSkipped;

  /// No description provided for @aiStepPersonal.
  ///
  /// In ko, this message translates to:
  /// **'개인운동'**
  String get aiStepPersonal;

  /// No description provided for @aiStepPrev.
  ///
  /// In ko, this message translates to:
  /// **'이전'**
  String get aiStepPrev;

  /// No description provided for @aiStepNext.
  ///
  /// In ko, this message translates to:
  /// **'다음'**
  String get aiStepNext;

  /// No description provided for @aiPersonalStepTitle.
  ///
  /// In ko, this message translates to:
  /// **'PT 사이에 할 개인운동'**
  String get aiPersonalStepTitle;

  /// No description provided for @aiPersonalStepTitleRoutineOnly.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 개인운동'**
  String get aiPersonalStepTitleRoutineOnly;

  /// No description provided for @aiPersonalStepBlurb.
  ///
  /// In ko, this message translates to:
  /// **'이 PT에 붙여 두었다가 PT를 완료할 때 회원에게 보내요. 최소 한 개를 정해 주세요.'**
  String get aiPersonalStepBlurb;

  /// No description provided for @aiPersonalStepBlurbRoutineOnly.
  ///
  /// In ko, this message translates to:
  /// **'회원이 혼자 할 운동이에요. 시작일에 PT가 있으면 그 PT에 붙고, 없으면 바로 한 주 동안 보내요. 최소 한 개를 정해 주세요.'**
  String get aiPersonalStepBlurbRoutineOnly;

  /// No description provided for @aiPersonalStepEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 정한 개인운동이 없어요. 아래에서 직접 더해 주세요.'**
  String get aiPersonalStepEmpty;

  /// No description provided for @aiKeepOnePersonalRoutine.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 최소 한 개는 정해 주세요.'**
  String get aiKeepOnePersonalRoutine;

  /// No description provided for @aiRoutineOnlyStartDate.
  ///
  /// In ko, this message translates to:
  /// **'시작일'**
  String get aiRoutineOnlyStartDate;

  /// No description provided for @aiRoutineOnlyWeeklyHint.
  ///
  /// In ko, this message translates to:
  /// **'{start}부터 {end}까지 7일간 회원 앱에 매일 떠요. 다음 주 분은 그때 다시 보내 주세요.'**
  String aiRoutineOnlyWeeklyHint(String start, String end);

  /// No description provided for @aiRoutineOnlySend.
  ///
  /// In ko, this message translates to:
  /// **'회원에게 보내기'**
  String get aiRoutineOnlySend;

  /// No description provided for @aiRoutineOnlySentLabel.
  ///
  /// In ko, this message translates to:
  /// **'보냈어요'**
  String get aiRoutineOnlySentLabel;

  /// No description provided for @aiRoutineOnlySent.
  ///
  /// In ko, this message translates to:
  /// **'개인운동을 회원에게 보냈어요.'**
  String get aiRoutineOnlySent;

  /// No description provided for @aiRoutineOnlyProgramName.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 개인운동'**
  String get aiRoutineOnlyProgramName;

  /// Program name stored when a trainer sends personal exercises only. No time span — the list stays up 7 days from the send date, not the calendar week (#2581).
  ///
  /// In ko, this message translates to:
  /// **'개인운동'**
  String get aiRoutineOnlyDeliveryName;

  /// No description provided for @progPersonalRoutinesWhen.
  ///
  /// In ko, this message translates to:
  /// **'이 PT를 완료할 때 회원에게 함께 가요.'**
  String get progPersonalRoutinesWhen;

  /// No description provided for @progNoRoutinesRegisterTitle.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 없이 일정을 추가할까요?'**
  String get progNoRoutinesRegisterTitle;

  /// No description provided for @progNoRoutinesRegisterBody.
  ///
  /// In ko, this message translates to:
  /// **'PT마다 개인운동을 최소 한 개 붙여 주세요. 지금 붙이지 않으면 PT 프로그램을 보내기 전에 스케줄의 일정 상세에서 붙일 수 있어요.'**
  String get progNoRoutinesRegisterBody;

  /// No description provided for @progNoRoutinesRegisterSkip.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 없이 추가'**
  String get progNoRoutinesRegisterSkip;

  /// No description provided for @progPersonalRoutinesEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 개인운동이 없어요. PT마다 최소 한 개를 붙여 주세요.'**
  String get progPersonalRoutinesEmpty;

  /// No description provided for @aiAttachTargetPt.
  ///
  /// In ko, this message translates to:
  /// **'지금 짜는 PT에 붙일 개인운동이에요.'**
  String get aiAttachTargetPt;

  /// No description provided for @aiAttachRoutines.
  ///
  /// In ko, this message translates to:
  /// **'PT에 반영'**
  String get aiAttachRoutines;

  /// No description provided for @aiAttachedLabel.
  ///
  /// In ko, this message translates to:
  /// **'반영했어요'**
  String get aiAttachedLabel;

  /// No description provided for @aiRoutineTargetPt.
  ///
  /// In ko, this message translates to:
  /// **'{date} {time} PT에 붙이기'**
  String aiRoutineTargetPt(String date, String time);

  /// No description provided for @aiRoutineOnlyAttachHint.
  ///
  /// In ko, this message translates to:
  /// **'{date} {time} PT에 붙어요. 회원에게는 스케줄에서 이 PT를 보낼 때 함께 가요.'**
  String aiRoutineOnlyAttachHint(String date, String time);

  /// No description provided for @aiReplaceRoutinesTitle.
  ///
  /// In ko, this message translates to:
  /// **'이미 개인운동이 있어요'**
  String get aiReplaceRoutinesTitle;

  /// No description provided for @aiReplaceRoutinesBody.
  ///
  /// In ko, this message translates to:
  /// **'이 PT에 개인운동 {count}개({names})가 붙어 있어요. 새로 짠 것으로 교체할까요?'**
  String aiReplaceRoutinesBody(int count, String names);

  /// No description provided for @aiReplaceRoutinesConfirm.
  ///
  /// In ko, this message translates to:
  /// **'교체'**
  String get aiReplaceRoutinesConfirm;

  /// No description provided for @programRoutineOnlyConfirmBody.
  ///
  /// In ko, this message translates to:
  /// **'{client}님에게 개인운동을 보내요. {start}부터 {end}까지 회원 앱에 매일 떠요.'**
  String programRoutineOnlyConfirmBody(String client, String start, String end);

  /// No description provided for @progPersonalRoutinesTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 PT에 붙일 개인운동'**
  String get progPersonalRoutinesTitle;

  /// No description provided for @aiStepperLabel.
  ///
  /// In ko, this message translates to:
  /// **'맞춤 추천안 생성 진행 단계'**
  String get aiStepperLabel;

  /// No description provided for @coachTemplateSummaryWithGoal.
  ///
  /// In ko, this message translates to:
  /// **'{goal} · {count}개 · {duration}'**
  String coachTemplateSummaryWithGoal(String goal, int count, String duration);

  /// No description provided for @aiInsightMemoTitle.
  ///
  /// In ko, this message translates to:
  /// **'최근 7일 확인 필요'**
  String get aiInsightMemoTitle;

  /// No description provided for @aiInsightMemoEmpty.
  ///
  /// In ko, this message translates to:
  /// **'최근 7일간 감지된 메모가 없어요'**
  String get aiInsightMemoEmpty;

  /// No description provided for @aiInsightMemoFailed.
  ///
  /// In ko, this message translates to:
  /// **'감지 메모를 불러오지 못했어요'**
  String get aiInsightMemoFailed;

  /// No description provided for @aiRecentRoutineMore.
  ///
  /// In ko, this message translates to:
  /// **'{name} 외 {count}개'**
  String aiRecentRoutineMore(String name, int count);

  /// No description provided for @aiNoRecentRoutine.
  ///
  /// In ko, this message translates to:
  /// **'기록 없음'**
  String get aiNoRecentRoutine;

  /// No description provided for @aiRecentRoutine.
  ///
  /// In ko, this message translates to:
  /// **'최근 운동'**
  String get aiRecentRoutine;

  /// No description provided for @aiGenerateConditions.
  ///
  /// In ko, this message translates to:
  /// **'생성 조건'**
  String get aiGenerateConditions;

  /// No description provided for @aiCompareCandidates.
  ///
  /// In ko, this message translates to:
  /// **'맞춤 추천안 후보를 비교해 보세요'**
  String get aiCompareCandidates;

  /// No description provided for @aiConditionsAutoHint.
  ///
  /// In ko, this message translates to:
  /// **'비워두면 최근 기록이나 목표를 기준으로 자동 설정돼요.'**
  String get aiConditionsAutoHint;

  /// No description provided for @aiPromptTitle.
  ///
  /// In ko, this message translates to:
  /// **'AI에게 원하는 프로그램을 말해 주세요'**
  String get aiPromptTitle;

  /// No description provided for @aiPromptLabel.
  ///
  /// In ko, this message translates to:
  /// **'요청 내용'**
  String get aiPromptLabel;

  /// No description provided for @aiPromptHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 하체 부담 적고 유산소 비중 높은 40분 프로그램 만들어줘'**
  String get aiPromptHint;

  /// No description provided for @aiPromptBlurb.
  ///
  /// In ko, this message translates to:
  /// **'요청은 회원 데이터와 함께 AI에 전달돼요(최대 500자). 트레이너 피드백은 다음 단계에서 작성해요.'**
  String get aiPromptBlurb;

  /// No description provided for @aiSourcesTitle.
  ///
  /// In ko, this message translates to:
  /// **'AI가 참고할 자료'**
  String get aiSourcesTitle;

  /// No description provided for @aiSourcesBlurb.
  ///
  /// In ko, this message translates to:
  /// **'고른 자료만 회원 데이터와 함께 AI에 전달돼요. 선택은 다음에도 그대로 남아요.'**
  String get aiSourcesBlurb;

  /// No description provided for @aiSourcePtFeedback.
  ///
  /// In ko, this message translates to:
  /// **'최근 PT 피드백'**
  String get aiSourcePtFeedback;

  /// No description provided for @aiSourceConsultMemo.
  ///
  /// In ko, this message translates to:
  /// **'상담 메모'**
  String get aiSourceConsultMemo;

  /// No description provided for @aiSourceTrainerMemo.
  ///
  /// In ko, this message translates to:
  /// **'회원 메모(직접 작성)'**
  String get aiSourceTrainerMemo;

  /// No description provided for @aiSourceChatInsight.
  ///
  /// In ko, this message translates to:
  /// **'채팅 감지 메모'**
  String get aiSourceChatInsight;

  /// Source the AI may read — the raw recent chat with the member (last 14 days, up to 10, #2794)
  ///
  /// In ko, this message translates to:
  /// **'최근 대화'**
  String get aiSourceRecentChat;

  /// No description provided for @aiSourceWeeklyFeedback.
  ///
  /// In ko, this message translates to:
  /// **'회원 주간 피드백'**
  String get aiSourceWeeklyFeedback;

  /// No description provided for @aiSourceRangeDays.
  ///
  /// In ko, this message translates to:
  /// **'최근 {days}일 · 최대 {count}건'**
  String aiSourceRangeDays(int days, int count);

  /// No description provided for @aiSourceRangeWeeks.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 · 지난주'**
  String get aiSourceRangeWeeks;

  /// No description provided for @aiGenerateGoalBased.
  ///
  /// In ko, this message translates to:
  /// **'목표 기반 추천안 생성'**
  String get aiGenerateGoalBased;

  /// No description provided for @aiStatusTemplateTitle.
  ///
  /// In ko, this message translates to:
  /// **'목표 기반 기본 추천'**
  String get aiStatusTemplateTitle;

  /// No description provided for @aiStatusTemplateBody.
  ///
  /// In ko, this message translates to:
  /// **'아직 개인화하기엔 운동 기록이 부족해 목표를 기준으로 추천했어요.'**
  String get aiStatusTemplateBody;

  /// No description provided for @aiStatusLearningTitle.
  ///
  /// In ko, this message translates to:
  /// **'개인화 학습 중'**
  String get aiStatusLearningTitle;

  /// No description provided for @aiStatusLearningBody.
  ///
  /// In ko, this message translates to:
  /// **'최근 운동을 참고했지만 아직 반복 패턴이라 부르기엔 일러요.'**
  String get aiStatusLearningBody;

  /// No description provided for @aiStatusPersonalizedTitle.
  ///
  /// In ko, this message translates to:
  /// **'최근 패턴 분석 완료'**
  String get aiStatusPersonalizedTitle;

  /// No description provided for @aiStatusPersonalizedBody.
  ///
  /// In ko, this message translates to:
  /// **'최근 {days}일 · {count}회 기록을 기준으로 분석했어요.'**
  String aiStatusPersonalizedBody(int count, int days);

  /// No description provided for @aiFrequentExercisesLabel.
  ///
  /// In ko, this message translates to:
  /// **'자주 한 운동'**
  String get aiFrequentExercisesLabel;

  /// No description provided for @goalWeightLoss.
  ///
  /// In ko, this message translates to:
  /// **'체중 감량'**
  String get goalWeightLoss;

  /// No description provided for @goalHealth.
  ///
  /// In ko, this message translates to:
  /// **'건강 관리'**
  String get goalHealth;

  /// No description provided for @goalOther.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get goalOther;

  /// No description provided for @slotAm.
  ///
  /// In ko, this message translates to:
  /// **'오전'**
  String get slotAm;

  /// No description provided for @slotPm.
  ///
  /// In ko, this message translates to:
  /// **'오후'**
  String get slotPm;

  /// No description provided for @slotFlexible.
  ///
  /// In ko, this message translates to:
  /// **'조율 가능'**
  String get slotFlexible;

  /// No description provided for @unknownMember.
  ///
  /// In ko, this message translates to:
  /// **'알 수 없는 회원'**
  String get unknownMember;

  /// No description provided for @filterAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get filterAll;

  /// No description provided for @authErrInvalidCredentials.
  ///
  /// In ko, this message translates to:
  /// **'이메일 또는 비밀번호가 올바르지 않아요.'**
  String get authErrInvalidCredentials;

  /// No description provided for @authErrEmailTaken.
  ///
  /// In ko, this message translates to:
  /// **'이미 가입된 이메일이에요.'**
  String get authErrEmailTaken;

  /// No description provided for @authErrSessionExpired.
  ///
  /// In ko, this message translates to:
  /// **'로그인이 만료됐어요. 다시 로그인해 주세요.'**
  String get authErrSessionExpired;

  /// No description provided for @authErrNoSocialToken.
  ///
  /// In ko, this message translates to:
  /// **'소셜 로그인 토큰이 없어요'**
  String get authErrNoSocialToken;

  /// No description provided for @authErrNetwork.
  ///
  /// In ko, this message translates to:
  /// **'네트워크 연결을 확인해 주세요.'**
  String get authErrNetwork;

  /// No description provided for @authErrGeneric.
  ///
  /// In ko, this message translates to:
  /// **'로그인 중 문제가 발생했어요. 잠시 후 다시 시도해 주세요.'**
  String get authErrGeneric;

  /// No description provided for @authErrEmptyResponse.
  ///
  /// In ko, this message translates to:
  /// **'응답이 비어 있어요.'**
  String get authErrEmptyResponse;

  /// No description provided for @slotFutureOnly.
  ///
  /// In ko, this message translates to:
  /// **'지금보다 이후 시간만 예약 가능 시간으로 열 수 있어요.'**
  String get slotFutureOnly;

  /// No description provided for @slotNotFound.
  ///
  /// In ko, this message translates to:
  /// **'예약 가능 시간을 찾을 수 없어요.'**
  String get slotNotFound;

  /// No description provided for @slotTypeLockedByBooking.
  ///
  /// In ko, this message translates to:
  /// **'이미 예약된 자리의 종류는 바꿀 수 없어요.'**
  String get slotTypeLockedByBooking;

  /// No description provided for @authErrNotTrainer.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 계정으로 로그인해 주세요.'**
  String get authErrNotTrainer;

  /// Error toast on trainer sign-in when the social account's unverified email matches an existing account (409 social_email_in_use, #1551).
  ///
  /// In ko, this message translates to:
  /// **'이 이메일로 가입한 계정이 있어요. 처음 가입한 방법으로 로그인해 주세요.'**
  String get authErrSocialEmailInUse;

  /// No description provided for @authErrTooManyAttempts.
  ///
  /// In ko, this message translates to:
  /// **'시도가 너무 많아 잠시 막혔어요. 잠시 후 다시 시도해 주세요.'**
  String get authErrTooManyAttempts;

  /// No description provided for @authErrTooManyAttemptsMinutes.
  ///
  /// In ko, this message translates to:
  /// **'시도가 너무 많아 잠시 막혔어요. {minutes}분 뒤에 다시 시도해 주세요.'**
  String authErrTooManyAttemptsMinutes(int minutes);

  /// No description provided for @authErrSignedUpSignInFailed.
  ///
  /// In ko, this message translates to:
  /// **'가입은 완료됐어요. 로그인해 주세요.'**
  String get authErrSignedUpSignInFailed;

  /// No description provided for @aiTotalAndIntensity.
  ///
  /// In ko, this message translates to:
  /// **'총 {total}분 · 강도 {intensity}'**
  String aiTotalAndIntensity(int total, String intensity);

  /// No description provided for @aiBulletExercise.
  ///
  /// In ko, this message translates to:
  /// **'· {name} · {minutes}분 '**
  String aiBulletExercise(String name, int minutes);

  /// Login screen wordmark with the spaced hyphen used in the visual design.
  ///
  /// In ko, this message translates to:
  /// **'On - Care 트레이너'**
  String get appTitleSpaced;

  /// No description provided for @navNotifications.
  ///
  /// In ko, this message translates to:
  /// **'알림'**
  String get navNotifications;

  /// No description provided for @notifTitle.
  ///
  /// In ko, this message translates to:
  /// **'알림'**
  String get notifTitle;

  /// No description provided for @notifSeeAll.
  ///
  /// In ko, this message translates to:
  /// **'전체 보기'**
  String get notifSeeAll;

  /// No description provided for @notifGroupAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get notifGroupAll;

  /// No description provided for @notifGroupMessages.
  ///
  /// In ko, this message translates to:
  /// **'메시지'**
  String get notifGroupMessages;

  /// No description provided for @notifGroupEmpty.
  ///
  /// In ko, this message translates to:
  /// **'이 종류의 알림이 없어요'**
  String get notifGroupEmpty;

  /// No description provided for @notifReadAll.
  ///
  /// In ko, this message translates to:
  /// **'모두 읽음'**
  String get notifReadAll;

  /// No description provided for @notifEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 받은 알림이 없어요'**
  String get notifEmpty;

  /// No description provided for @notifLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'알림을 불러오지 못했어요'**
  String get notifLoadFailed;

  /// No description provided for @notifLoadMore.
  ///
  /// In ko, this message translates to:
  /// **'지난 알림 더 보기'**
  String get notifLoadMore;

  /// No description provided for @notifLoadMoreFailed.
  ///
  /// In ko, this message translates to:
  /// **'지난 알림을 불러오지 못했어요'**
  String get notifLoadMoreFailed;

  /// No description provided for @notifNoEarlier.
  ///
  /// In ko, this message translates to:
  /// **'더 지난 알림이 없어요'**
  String get notifNoEarlier;

  /// No description provided for @notifTplHealthGoalTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원 건강 목표가 바뀌었어요'**
  String get notifTplHealthGoalTitle;

  /// goals is the member's health goals joined with ' · '.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원이 건강 목표를 바꿨어요: {goals}'**
  String notifTplHealthGoalBody(String name, String goals);

  /// No description provided for @notifTplHealthNotesTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원 주의사항이 바뀌었어요'**
  String get notifTplHealthNotesTitle;

  /// No description provided for @notifTplHealthNotesBody.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원이 건강상태·주의사항을 바꿨어요'**
  String notifTplHealthNotesBody(String name);

  /// No description provided for @notifTplHealthNotesWithGoalsBody.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원이 건강 목표와 건강상태·주의사항을 바꿨어요'**
  String notifTplHealthNotesWithGoalsBody(String name);

  /// Shown in place of the goal list when the member cleared every health goal.
  ///
  /// In ko, this message translates to:
  /// **'목표 없음'**
  String get notifTplNoGoals;

  /// No description provided for @notifTplMemberRenamedTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원 이름이 바뀌었어요'**
  String get notifTplMemberRenamedTitle;

  /// No description provided for @notifTplMemberRenamedBody.
  ///
  /// In ko, this message translates to:
  /// **'{oldName} 회원이 이름을 바꿨어요: {newName}'**
  String notifTplMemberRenamedBody(String oldName, String newName);

  /// No description provided for @notifTplMemberWithdrawnTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원이 탈퇴했어요'**
  String get notifTplMemberWithdrawnTitle;

  /// No description provided for @notifTplMemberWithdrawnBody.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원이 탈퇴했어요.'**
  String notifTplMemberWithdrawnBody(String name);

  /// No description provided for @notifTplMemberDisconnectedTitle.
  ///
  /// In ko, this message translates to:
  /// **'담당 연결이 해제됐어요'**
  String get notifTplMemberDisconnectedTitle;

  /// No description provided for @notifTplMemberDisconnectedBody.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원이 담당 연결을 해제했어요.'**
  String notifTplMemberDisconnectedBody(String name);

  /// No description provided for @notifTplConsultRequestedTitle.
  ///
  /// In ko, this message translates to:
  /// **'새 상담 요청이 도착했어요'**
  String get notifTplConsultRequestedTitle;

  /// No description provided for @notifTplConsultCancelledTitle.
  ///
  /// In ko, this message translates to:
  /// **'상담 요청이 취소됐어요'**
  String get notifTplConsultCancelledTitle;

  /// No description provided for @notifTplConsultBookingCancelledTitle.
  ///
  /// In ko, this message translates to:
  /// **'확정된 상담이 취소됐어요'**
  String get notifTplConsultBookingCancelledTitle;

  /// No description provided for @notifTplConsultWithdrawnTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원 탈퇴로 상담 요청이 취소됐어요'**
  String get notifTplConsultWithdrawnTitle;

  /// No description provided for @notifTplInviteAcceptedTitle.
  ///
  /// In ko, this message translates to:
  /// **'담당 요청이 수락됐어요'**
  String get notifTplInviteAcceptedTitle;

  /// No description provided for @notifTplInviteAcceptedBody.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원이 담당으로 연결됐어요.'**
  String notifTplInviteAcceptedBody(String name);

  /// No description provided for @notifTplInviteRejectedTitle.
  ///
  /// In ko, this message translates to:
  /// **'담당 요청이 거절됐어요'**
  String get notifTplInviteRejectedTitle;

  /// No description provided for @notifTplInviteRejectedBody.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원이 담당 요청을 거절했어요.'**
  String notifTplInviteRejectedBody(String name);

  /// No description provided for @notifTplReservationBookedTitle.
  ///
  /// In ko, this message translates to:
  /// **'새 예약이 들어왔어요'**
  String get notifTplReservationBookedTitle;

  /// No description provided for @notifTplReservationCancelledTitle.
  ///
  /// In ko, this message translates to:
  /// **'예약이 취소됐어요'**
  String get notifTplReservationCancelledTitle;

  /// A member's name followed by a date or time, e.g. for a booking.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원 · {detail}'**
  String notifTplMemberWithDetail(String name, String detail);

  /// Just the member's name, used when a cancelled booking has no time.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원'**
  String notifTplMemberOnly(String name);

  /// Seoul wall-clock date and time of a session. month and day have no leading zero, time is 24-hour HH:mm.
  ///
  /// In ko, this message translates to:
  /// **'{month}월 {day}일 {time}'**
  String notifTplWhen(String month, String day, String time);

  /// No description provided for @notifTplMemberMessageTitle.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원의 메시지'**
  String notifTplMemberMessageTitle(String name);

  /// Body of the new-message notification when a member sent only a photo in the coach chat.
  ///
  /// In ko, this message translates to:
  /// **'사진을 보냈어요'**
  String get notifTplMemberPhotoBody;

  /// Trainer notification title when a member submits their weekly feedback (#3026).
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원이 주간 피드백을 보냈어요'**
  String notifTplWeeklyFeedbackTitle(String name);

  /// Title when a member re-submits weekly feedback the trainer has already read (#3026).
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원이 주간 피드백을 수정했어요'**
  String notifTplWeeklyFeedbackRevisedTitle(String name);

  /// Title when the weekly feedback reports pain. The pain area itself is never shown in the notification (#3026).
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원이 통증을 알렸어요'**
  String notifTplWeeklyFeedbackPainTitle(String name);

  /// No description provided for @notifTplWeeklyFeedbackCondition.
  ///
  /// In ko, this message translates to:
  /// **'컨디션 {value}'**
  String notifTplWeeklyFeedbackCondition(String value);

  /// No description provided for @notifTplWeeklyFeedbackIntensity.
  ///
  /// In ko, this message translates to:
  /// **'운동 강도 {value}'**
  String notifTplWeeklyFeedbackIntensity(String value);

  /// No description provided for @notifTplWeeklyFeedbackPain.
  ///
  /// In ko, this message translates to:
  /// **'통증 있음'**
  String get notifTplWeeklyFeedbackPain;

  /// No description provided for @notifAllRead.
  ///
  /// In ko, this message translates to:
  /// **'모두 확인했어요'**
  String get notifAllRead;

  /// No description provided for @notifReadAllFailed.
  ///
  /// In ko, this message translates to:
  /// **'읽음 처리하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get notifReadAllFailed;

  /// No description provided for @notifUnreadCount.
  ///
  /// In ko, this message translates to:
  /// **'읽지 않은 알림 {count}건'**
  String notifUnreadCount(int count);

  /// No description provided for @myDeleteAccount.
  ///
  /// In ko, this message translates to:
  /// **'계정 탈퇴'**
  String get myDeleteAccount;

  /// No description provided for @myDeleteAction.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴'**
  String get myDeleteAction;

  /// No description provided for @myDeleteDemo.
  ///
  /// In ko, this message translates to:
  /// **'데모 모드에는 지울 계정이 없어요'**
  String get myDeleteDemo;

  /// No description provided for @myDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'계정을 탈퇴할까요?'**
  String get myDeleteTitle;

  /// No description provided for @myDeleteBody.
  ///
  /// In ko, this message translates to:
  /// **'프로필과 회원과의 대화, 보낸 PT 프로그램·개인운동, 일정과 예약 가능 시간이 지워지고, 담당 회원 연결과 예정된 예약이 종료되며 회원에게 알림이 전달돼요. 담당 회원의 사용 전 PT 재등록 쿠폰은 취소되고 포인트가 회원에게 돌아가요. 이 작업은 되돌릴 수 없어요.'**
  String get myDeleteBody;

  /// No description provided for @myDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get myDeleteFailed;

  /// No description provided for @myDeleteReauthPrompt.
  ///
  /// In ko, this message translates to:
  /// **'본인 확인을 위해 현재 비밀번호를 입력해 주세요'**
  String get myDeleteReauthPrompt;

  /// No description provided for @myDeleteReauthWrongPassword.
  ///
  /// In ko, this message translates to:
  /// **'현재 비밀번호가 일치하지 않아요'**
  String get myDeleteReauthWrongPassword;

  /// No description provided for @myDeleteReauthSocialPrompt.
  ///
  /// In ko, this message translates to:
  /// **'소셜 계정으로 가입한 계정이에요. 본인 확인을 위해 소셜 계정으로 다시 로그인해 주세요.'**
  String get myDeleteReauthSocialPrompt;

  /// No description provided for @myDeleteReauthSocialAction.
  ///
  /// In ko, this message translates to:
  /// **'소셜 계정으로 다시 로그인'**
  String get myDeleteReauthSocialAction;

  /// No description provided for @myDeleteReauthKakao.
  ///
  /// In ko, this message translates to:
  /// **'카카오로 다시 로그인'**
  String get myDeleteReauthKakao;

  /// No description provided for @myDeleteReauthGoogle.
  ///
  /// In ko, this message translates to:
  /// **'구글로 다시 로그인'**
  String get myDeleteReauthGoogle;

  /// No description provided for @myDeleteReauthSocialDone.
  ///
  /// In ko, this message translates to:
  /// **'소셜 계정을 확인했어요. 탈퇴를 누르면 진행돼요.'**
  String get myDeleteReauthSocialDone;

  /// No description provided for @myDeleteReauthSocialFailed.
  ///
  /// In ko, this message translates to:
  /// **'소셜 계정을 확인하지 못했어요. 다시 로그인해 주세요.'**
  String get myDeleteReauthSocialFailed;

  /// Shown in the account-deletion confirmation when no social sign-in is configured for this build (#330).
  ///
  /// In ko, this message translates to:
  /// **'이 버전에서는 아직 소셜 계정 확인을 할 수 없어요. 고객 지원으로 문의해 주세요.'**
  String get myDeleteReauthSocialUnavailable;

  /// No description provided for @myWithdrawReasonTitle.
  ///
  /// In ko, this message translates to:
  /// **'정말 탈퇴할까요?'**
  String get myWithdrawReasonTitle;

  /// No description provided for @myWithdrawReasonQuestion.
  ///
  /// In ko, this message translates to:
  /// **'어떤 점이 아쉬우셨나요?'**
  String get myWithdrawReasonQuestion;

  /// No description provided for @myWithdrawReasonHint.
  ///
  /// In ko, this message translates to:
  /// **'여러 개 골라도 되고, 고르지 않아도 넘어갈 수 있어요.'**
  String get myWithdrawReasonHint;

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

  /// No description provided for @myWithdrawReasonMissingFeature.
  ///
  /// In ko, this message translates to:
  /// **'회원 관리에 필요한 기능이 없어요'**
  String get myWithdrawReasonMissingFeature;

  /// No description provided for @myWithdrawReasonLeavingWork.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 일을 쉬거나 그만둬요'**
  String get myWithdrawReasonLeavingWork;

  /// No description provided for @myWithdrawReasonAlternative.
  ///
  /// In ko, this message translates to:
  /// **'다른 도구를 쓰고 있어요'**
  String get myWithdrawReasonAlternative;

  /// No description provided for @myWithdrawReasonOther.
  ///
  /// In ko, this message translates to:
  /// **'그 밖의 이유'**
  String get myWithdrawReasonOther;

  /// No description provided for @myWithdrawKeepTitle.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴하기 전에'**
  String get myWithdrawKeepTitle;

  /// No description provided for @myWithdrawKeepRarelyUsed.
  ///
  /// In ko, this message translates to:
  /// **'알림을 켜 두면 회원 메시지와 예약을 놓치지 않아요. 설정 › 알림에서 바꿀 수 있어요.'**
  String get myWithdrawKeepRarelyUsed;

  /// No description provided for @myWithdrawKeepHardToUse.
  ///
  /// In ko, this message translates to:
  /// **'불편했던 점을 1:1 문의로 알려 주시면 고쳐 볼게요.'**
  String get myWithdrawKeepHardToUse;

  /// No description provided for @myWithdrawKeepMissingFeature.
  ///
  /// In ko, this message translates to:
  /// **'필요한 기능을 1:1 문의로 알려 주세요. 다음 개선에 반영할게요.'**
  String get myWithdrawKeepMissingFeature;

  /// No description provided for @myWithdrawKeepLeavingWork.
  ///
  /// In ko, this message translates to:
  /// **'잠시 쉬는 거라면 계정을 그대로 두어도 돼요. 탈퇴하면 담당 회원 연결이 모두 끊겨요.'**
  String get myWithdrawKeepLeavingWork;

  /// No description provided for @myWithdrawKeepAlternative.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴하면 회원 기록·프로그램·리포트가 트레이너 화면에서 모두 사라지고 되살릴 수 없어요.'**
  String get myWithdrawKeepAlternative;

  /// No description provided for @myWithdrawKeepOther.
  ///
  /// In ko, this message translates to:
  /// **'더 나은 서비스를 위해 1:1 문의로 의견을 남겨 주시면 큰 도움이 돼요.'**
  String get myWithdrawKeepOther;

  /// No description provided for @myWithdrawKeepDefault.
  ///
  /// In ko, this message translates to:
  /// **'탈퇴하면 담당 회원 연결과 예약이 사라지고, 회원에게 알림이 가요. 되돌릴 수 없어요.'**
  String get myWithdrawKeepDefault;

  /// No description provided for @myWithdrawNext.
  ///
  /// In ko, this message translates to:
  /// **'다음'**
  String get myWithdrawNext;

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

  /// No description provided for @workoutKindPersonal.
  ///
  /// In ko, this message translates to:
  /// **'개인운동'**
  String get workoutKindPersonal;

  /// No description provided for @workoutRoutineDay.
  ///
  /// In ko, this message translates to:
  /// **'{month}/{day}({weekday})'**
  String workoutRoutineDay(int month, int day, String weekday);

  /// No description provided for @workoutRoutineDoneOf.
  ///
  /// In ko, this message translates to:
  /// **'{total}개 중 {done}개 완료'**
  String workoutRoutineDoneOf(int done, int total);

  /// No description provided for @workoutRoutineSentUntil.
  ///
  /// In ko, this message translates to:
  /// **'{sent} 보냄 · {end}까지'**
  String workoutRoutineSentUntil(String sent, String end);

  /// No description provided for @workoutRoutineWeekSummary.
  ///
  /// In ko, this message translates to:
  /// **'{days}일 중 모두 완료 {full}일'**
  String workoutRoutineWeekSummary(int days, int full);

  /// No description provided for @workoutRoutineWeekLate.
  ///
  /// In ko, this message translates to:
  /// **'{weekday} {count}건 늦게'**
  String workoutRoutineWeekLate(String weekday, int count);

  /// No description provided for @workoutRoutineWeekFirstDay.
  ///
  /// In ko, this message translates to:
  /// **'오늘 시작'**
  String get workoutRoutineWeekFirstDay;

  /// No description provided for @workoutRoutineWeekSent.
  ///
  /// In ko, this message translates to:
  /// **'{date} 보냄 · {names}'**
  String workoutRoutineWeekSent(String date, String names);

  /// No description provided for @workoutRoutineWeekOngoing.
  ///
  /// In ko, this message translates to:
  /// **'계속 · {names}'**
  String workoutRoutineWeekOngoing(String names);

  /// No description provided for @workoutRoutineWeekMore.
  ///
  /// In ko, this message translates to:
  /// **'{names} 외 {count}개'**
  String workoutRoutineWeekMore(String names, int count);

  /// No description provided for @workoutRoutineAllCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}회 보냄'**
  String workoutRoutineAllCount(int count);

  /// No description provided for @workoutRoutineAllAverage.
  ///
  /// In ko, this message translates to:
  /// **'평균 {percent}%'**
  String workoutRoutineAllAverage(int percent);

  /// No description provided for @workoutRoutineAllSent.
  ///
  /// In ko, this message translates to:
  /// **'{date} 보냄'**
  String workoutRoutineAllSent(String date);

  /// No description provided for @workoutRoutineAllUntil.
  ///
  /// In ko, this message translates to:
  /// **'~{date}'**
  String workoutRoutineAllUntil(String date);

  /// No description provided for @workoutRoutineAllUntilShort.
  ///
  /// In ko, this message translates to:
  /// **'~{date} · {days}일'**
  String workoutRoutineAllUntilShort(String date, int days);

  /// No description provided for @workoutRoutineAllOngoing.
  ///
  /// In ko, this message translates to:
  /// **'진행 중 · {day}일째'**
  String workoutRoutineAllOngoing(int day);

  /// No description provided for @workoutRoutineAllFirstDay.
  ///
  /// In ko, this message translates to:
  /// **'오늘 시작'**
  String get workoutRoutineAllFirstDay;

  /// No description provided for @workoutRoutineAllRing.
  ///
  /// In ko, this message translates to:
  /// **'{date} 보낸 개인운동, {percent}% 완료'**
  String workoutRoutineAllRing(String date, int percent);

  /// No description provided for @coachRoutineAdherenceTitle.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 완료'**
  String get coachRoutineAdherenceTitle;

  /// No description provided for @coachRoutineAdherenceCell.
  ///
  /// In ko, this message translates to:
  /// **'{date}: {done}/{total} 완료'**
  String coachRoutineAdherenceCell(String date, int done, int total);

  /// No description provided for @workoutTotalBurned.
  ///
  /// In ko, this message translates to:
  /// **'총 소모 {calories}kcal'**
  String workoutTotalBurned(String calories);

  /// No description provided for @workoutLineBurned.
  ///
  /// In ko, this message translates to:
  /// **'소모 {calories}kcal'**
  String workoutLineBurned(String calories);

  /// No description provided for @workoutLineEstimated.
  ///
  /// In ko, this message translates to:
  /// **'예상 소모 {calories}kcal'**
  String workoutLineEstimated(String calories);

  /// No description provided for @workoutIntensityPerformed.
  ///
  /// In ko, this message translates to:
  /// **'수행 {level}'**
  String workoutIntensityPerformed(String level);

  /// No description provided for @workoutDaySourcePt.
  ///
  /// In ko, this message translates to:
  /// **'PT'**
  String get workoutDaySourcePt;

  /// No description provided for @workoutUndatedTitle.
  ///
  /// In ko, this message translates to:
  /// **'날짜를 알 수 없는 기록'**
  String get workoutUndatedTitle;

  /// No description provided for @workoutMemberLogTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원 추가'**
  String get workoutMemberLogTitle;

  /// Shown in the expanded day when its workouts fail to load (#2892)
  ///
  /// In ko, this message translates to:
  /// **'운동 기록을 불러오지 못했어요'**
  String get workoutDayExercisesFailed;

  /// Label/tooltip of the console header's client search.
  ///
  /// In ko, this message translates to:
  /// **'회원 검색'**
  String get searchClients;

  /// No description provided for @searchClientsHint.
  ///
  /// In ko, this message translates to:
  /// **'회원·목표·최근 메시지·마지막 프로그램 전송일 검색'**
  String get searchClientsHint;

  /// No description provided for @searchClear.
  ///
  /// In ko, this message translates to:
  /// **'검색어 지우기'**
  String get searchClear;

  /// No description provided for @searchQuickActions.
  ///
  /// In ko, this message translates to:
  /// **'다른 탭에서 열기'**
  String get searchQuickActions;

  /// No description provided for @searchNoResults.
  ///
  /// In ko, this message translates to:
  /// **'“{query}”와 일치하는 회원이 없어요'**
  String searchNoResults(String query);

  /// Search dropdown footer: what picking a result does on this tab.
  ///
  /// In ko, this message translates to:
  /// **'선택하면 회원 상세가 열려요'**
  String get searchGoClientDetail;

  /// No description provided for @searchGoSchedule.
  ///
  /// In ko, this message translates to:
  /// **'선택하면 다음 예약 날짜로 이동해요'**
  String get searchGoSchedule;

  /// No description provided for @searchGoCoaching.
  ///
  /// In ko, this message translates to:
  /// **'선택하면 AI 코칭에 불러와요'**
  String get searchGoCoaching;

  /// No description provided for @searchGoReport.
  ///
  /// In ko, this message translates to:
  /// **'선택하면 주간 리포트를 열어요'**
  String get searchGoReport;

  /// No description provided for @searchDetailUnread.
  ///
  /// In ko, this message translates to:
  /// **'답장 대기 {count}건'**
  String searchDetailUnread(int count);

  /// No description provided for @searchDetailMessage.
  ///
  /// In ko, this message translates to:
  /// **'{message} · {time}'**
  String searchDetailMessage(String message, String time);

  /// No description provided for @searchDetailNextSession.
  ///
  /// In ko, this message translates to:
  /// **'다음 예약 {date} {time}'**
  String searchDetailNextSession(String date, String time);

  /// No description provided for @searchDetailNoUpcoming.
  ///
  /// In ko, this message translates to:
  /// **'예정된 예약 없음'**
  String get searchDetailNoUpcoming;

  /// No description provided for @searchDetailLastRoutine.
  ///
  /// In ko, this message translates to:
  /// **'마지막 프로그램 {when}'**
  String searchDetailLastRoutine(String when);

  /// No description provided for @searchDetailCompletion.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 완료율 {percent}%'**
  String searchDetailCompletion(int percent);

  /// No description provided for @navOperationsGroup.
  ///
  /// In ko, this message translates to:
  /// **'운영'**
  String get navOperationsGroup;

  /// No description provided for @navCoachingGroup.
  ///
  /// In ko, this message translates to:
  /// **'코칭'**
  String get navCoachingGroup;

  /// No description provided for @dashTodayTasks.
  ///
  /// In ko, this message translates to:
  /// **'오늘 할 일'**
  String get dashTodayTasks;

  /// No description provided for @dashTasksReviewed.
  ///
  /// In ko, this message translates to:
  /// **'모두 확인했어요'**
  String get dashTasksReviewed;

  /// No description provided for @dashTasksNeedReview.
  ///
  /// In ko, this message translates to:
  /// **'{count}개 확인 필요'**
  String dashTasksNeedReview(int count);

  /// No description provided for @dashTaskProgressTitle.
  ///
  /// In ko, this message translates to:
  /// **'할 일 진행률'**
  String get dashTaskProgressTitle;

  /// No description provided for @dashTaskProgressToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘 할 일'**
  String get dashTaskProgressToday;

  /// No description provided for @dashTaskProgressCarriedOver.
  ///
  /// In ko, this message translates to:
  /// **'지난 할 일'**
  String get dashTaskProgressCarriedOver;

  /// No description provided for @dashTodoConsultation.
  ///
  /// In ko, this message translates to:
  /// **'상담'**
  String get dashTodoConsultation;

  /// No description provided for @dashTodoDiet.
  ///
  /// In ko, this message translates to:
  /// **'식단'**
  String get dashTodoDiet;

  /// No description provided for @dashTodoWorkout.
  ///
  /// In ko, this message translates to:
  /// **'운동'**
  String get dashTodoWorkout;

  /// No description provided for @dashTodoProgram.
  ///
  /// In ko, this message translates to:
  /// **'프로그램'**
  String get dashTodoProgram;

  /// No description provided for @dashTodoReport.
  ///
  /// In ko, this message translates to:
  /// **'리포트'**
  String get dashTodoReport;

  /// Subtitle of a consultation-request task: the member's preferred (or chosen slot) date and time, not the date the request arrived.
  ///
  /// In ko, this message translates to:
  /// **'희망 {when}'**
  String dashTodoConsultationSubtitle(String when);

  /// Subtitle of the demo carried-over task shown before real history exists.
  ///
  /// In ko, this message translates to:
  /// **'어제 남긴 식단 피드백'**
  String get dashTodoCarriedOverDemoSubtitle;

  /// No description provided for @dashTodoProgramSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'최근 보낸 프로그램 없음'**
  String get dashTodoProgramSubtitle;

  /// No description provided for @dashTodoReportSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 리포트 작성 대상'**
  String get dashTodoReportSubtitle;

  /// No description provided for @dashTaskSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'할 일 상태를 저장하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get dashTaskSaveFailed;

  /// No description provided for @dashTaskLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'할 일 상태를 불러오지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get dashTaskLoadFailed;

  /// Toast when a task tap arrives after midnight on a dashboard opened the previous day; the tap is ignored and today's list is reloaded.
  ///
  /// In ko, this message translates to:
  /// **'날짜가 바뀌어 오늘 할 일로 새로 불러왔어요. 다시 눌러 주세요'**
  String get dashTaskDayChanged;

  /// No description provided for @dashTaskDismissTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 항목을 삭제할까요?'**
  String get dashTaskDismissTitle;

  /// No description provided for @dashTaskDismissBody.
  ///
  /// In ko, this message translates to:
  /// **'할 일 목록에서만 사라져요. 실제 처리(상담·프로그램·리포트)는 각 화면에서 해야 해요.'**
  String get dashTaskDismissBody;

  /// No description provided for @dashTaskCarriedOverTitle.
  ///
  /// In ko, this message translates to:
  /// **'지난 할 일'**
  String get dashTaskCarriedOverTitle;

  /// No description provided for @dashTaskCategoryDone.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get dashTaskCategoryDone;

  /// No description provided for @dashTaskCategoryEmpty.
  ///
  /// In ko, this message translates to:
  /// **'없음'**
  String get dashTaskCategoryEmpty;

  /// No description provided for @dashTaskCategoryRemaining.
  ///
  /// In ko, this message translates to:
  /// **'+{count}'**
  String dashTaskCategoryRemaining(int count);

  /// No description provided for @dashTaskUncheckTitle.
  ///
  /// In ko, this message translates to:
  /// **'\'{name}\' 완료를 취소할까요?'**
  String dashTaskUncheckTitle(String name);

  /// No description provided for @dashTaskUncheckBody.
  ///
  /// In ko, this message translates to:
  /// **'할 일 진행률에서도 빠져요.'**
  String get dashTaskUncheckBody;

  /// No description provided for @dashTaskUncheckConfirm.
  ///
  /// In ko, this message translates to:
  /// **'완료 취소'**
  String get dashTaskUncheckConfirm;

  /// No description provided for @churnNoRecentFeedback.
  ///
  /// In ko, this message translates to:
  /// **'최근 7일 트레이너 피드백 없음'**
  String get churnNoRecentFeedback;

  /// No description provided for @navMessages.
  ///
  /// In ko, this message translates to:
  /// **'메시지'**
  String get navMessages;

  /// No description provided for @messagesSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'회원과 코칭 내용을 주고받고 빠르게 후속 조치하세요'**
  String get messagesSubtitle;

  /// No description provided for @messagesLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'대화 목록을 불러오지 못했어요.'**
  String get messagesLoadFailed;

  /// No description provided for @messagesEmpty.
  ///
  /// In ko, this message translates to:
  /// **'조건에 맞는 대화가 없어요.'**
  String get messagesEmpty;

  /// No description provided for @messagesFilterAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get messagesFilterAll;

  /// No description provided for @messagesFilterUnread.
  ///
  /// In ko, this message translates to:
  /// **'읽지 않음'**
  String get messagesFilterUnread;

  /// No description provided for @messagesFilterAttention.
  ///
  /// In ko, this message translates to:
  /// **'관리 필요'**
  String get messagesFilterAttention;

  /// No description provided for @messagesFilterUnreadCount.
  ///
  /// In ko, this message translates to:
  /// **'읽지 않음 {count}'**
  String messagesFilterUnreadCount(int count);

  /// No description provided for @messagesNoPreview.
  ///
  /// In ko, this message translates to:
  /// **'아직 대화가 없어요'**
  String get messagesNoPreview;

  /// No description provided for @messagesPreviewEmote.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘을 보냈어요'**
  String get messagesPreviewEmote;

  /// No description provided for @messagesPreviewPhoto.
  ///
  /// In ko, this message translates to:
  /// **'사진'**
  String get messagesPreviewPhoto;

  /// No description provided for @messagesTimeJustNow.
  ///
  /// In ko, this message translates to:
  /// **'방금'**
  String get messagesTimeJustNow;

  /// No description provided for @messagesClientDetail.
  ///
  /// In ko, this message translates to:
  /// **'회원 상세'**
  String get messagesClientDetail;

  /// No description provided for @messagesSelectPrompt.
  ///
  /// In ko, this message translates to:
  /// **'왼쪽 목록에서 대화할 회원을 선택하세요.'**
  String get messagesSelectPrompt;

  /// No description provided for @clientQuickMessages.
  ///
  /// In ko, this message translates to:
  /// **'메시지'**
  String get clientQuickMessages;

  /// No description provided for @clientQuickProgram.
  ///
  /// In ko, this message translates to:
  /// **'프로그램'**
  String get clientQuickProgram;

  /// No description provided for @clientQuickReport.
  ///
  /// In ko, this message translates to:
  /// **'리포트'**
  String get clientQuickReport;

  /// No description provided for @clientProfileSectionTitle.
  ///
  /// In ko, this message translates to:
  /// **'신체·목표'**
  String get clientProfileSectionTitle;

  /// No description provided for @clientMemoDialogTitle.
  ///
  /// In ko, this message translates to:
  /// **'메모·피드백'**
  String get clientMemoDialogTitle;

  /// No description provided for @clientTrainerMemo.
  ///
  /// In ko, this message translates to:
  /// **'메모'**
  String get clientTrainerMemo;

  /// No description provided for @clientHealthUnset.
  ///
  /// In ko, this message translates to:
  /// **'미입력'**
  String get clientHealthUnset;

  /// No description provided for @clientHealthTabBody.
  ///
  /// In ko, this message translates to:
  /// **'신체'**
  String get clientHealthTabBody;

  /// No description provided for @clientHealthTabFocus.
  ///
  /// In ko, this message translates to:
  /// **'건강 목표'**
  String get clientHealthTabFocus;

  /// No description provided for @clientGoalPerDay.
  ///
  /// In ko, this message translates to:
  /// **'하루 기준'**
  String get clientGoalPerDay;

  /// No description provided for @clientGoalCalories.
  ///
  /// In ko, this message translates to:
  /// **'칼로리'**
  String get clientGoalCalories;

  /// No description provided for @clientGoalSodium.
  ///
  /// In ko, this message translates to:
  /// **'나트륨'**
  String get clientGoalSodium;

  /// No description provided for @clientGoalSugar.
  ///
  /// In ko, this message translates to:
  /// **'당류'**
  String get clientGoalSugar;

  /// No description provided for @clientGoalCarbs.
  ///
  /// In ko, this message translates to:
  /// **'탄수화물'**
  String get clientGoalCarbs;

  /// No description provided for @clientGoalProtein.
  ///
  /// In ko, this message translates to:
  /// **'단백질'**
  String get clientGoalProtein;

  /// No description provided for @clientGoalFat.
  ///
  /// In ko, this message translates to:
  /// **'지방'**
  String get clientGoalFat;

  /// No description provided for @clientGoalBurnDaily.
  ///
  /// In ko, this message translates to:
  /// **'하루 소모 칼로리'**
  String get clientGoalBurnDaily;

  /// No description provided for @clientGoalCardioWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 유산소'**
  String get clientGoalCardioWeekly;

  /// No description provided for @clientGoalStrengthWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 근력'**
  String get clientGoalStrengthWeekly;

  /// No description provided for @clientGoalStretchWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 스트레칭'**
  String get clientGoalStretchWeekly;

  /// No description provided for @clientBodyHeight.
  ///
  /// In ko, this message translates to:
  /// **'키'**
  String get clientBodyHeight;

  /// No description provided for @clientBodyWeight.
  ///
  /// In ko, this message translates to:
  /// **'체중'**
  String get clientBodyWeight;

  /// No description provided for @clientUnitCm.
  ///
  /// In ko, this message translates to:
  /// **'cm'**
  String get clientUnitCm;

  /// No description provided for @clientGoalDefaultHint.
  ///
  /// In ko, this message translates to:
  /// **'흐린 값은 회원이 목표를 세우기 전의 기본 기준이에요. 비워 두면 이 값으로 계산해요.'**
  String get clientGoalDefaultHint;

  /// No description provided for @clientGoalSuggestionDiet.
  ///
  /// In ko, this message translates to:
  /// **'권장: {kcal}kcal · 탄수화물 {carbs}g · 당류 {sugar}g · 단백질 {protein}g · 지방 {fat}g · 나트륨 {sodium}mg'**
  String clientGoalSuggestionDiet(
    int kcal,
    int carbs,
    int sugar,
    int protein,
    int fat,
    int sodium,
  );

  /// No description provided for @clientGoalSuggestionExercise.
  ///
  /// In ko, this message translates to:
  /// **'권장: 하루 소모 {burn}kcal · 주 유산소 {cardio}분 · 근력 {strength}세트 · 스트레칭 {flexibility}분'**
  String clientGoalSuggestionExercise(
    int burn,
    int cardio,
    int strength,
    int flexibility,
  );

  /// No description provided for @clientGoalSuggestionPersonal.
  ///
  /// In ko, this message translates to:
  /// **'나이·성별·키·체중과 건강 목표로 계산했어요 (2020 한국인 영양소 섭취기준·WHO 권고)'**
  String get clientGoalSuggestionPersonal;

  /// No description provided for @clientGoalSuggestionFallback.
  ///
  /// In ko, this message translates to:
  /// **'나이·키·체중이 없어 기본 기준에 건강 목표만 반영했어요'**
  String get clientGoalSuggestionFallback;

  /// No description provided for @clientGoalApplySuggestion.
  ///
  /// In ko, this message translates to:
  /// **'권장값으로 채우기'**
  String get clientGoalApplySuggestion;

  /// No description provided for @clientTrainerMemoHint.
  ///
  /// In ko, this message translates to:
  /// **'이 회원에 대해 기억할 내용을 적어 주세요'**
  String get clientTrainerMemoHint;

  /// No description provided for @clientTrainerMemoPrivate.
  ///
  /// In ko, this message translates to:
  /// **'나만 보는 메모예요. 회원에게는 보이지 않아요.'**
  String get clientTrainerMemoPrivate;

  /// No description provided for @clientTrainerMemoAdd.
  ///
  /// In ko, this message translates to:
  /// **'메모 추가'**
  String get clientTrainerMemoAdd;

  /// No description provided for @clientTrainerMemoEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 남긴 메모가 없어요.'**
  String get clientTrainerMemoEmpty;

  /// No description provided for @clientTrainerMemoFromChat.
  ///
  /// In ko, this message translates to:
  /// **'채팅에서 감지'**
  String get clientTrainerMemoFromChat;

  /// No description provided for @clientTrainerMemoLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'메모를 불러오지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get clientTrainerMemoLoadFailed;

  /// No description provided for @clientTrainerMemoSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'메모를 저장하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get clientTrainerMemoSaveFailed;

  /// No description provided for @clientTrainerMemoDeleteFailed.
  ///
  /// In ko, this message translates to:
  /// **'메모를 삭제하지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get clientTrainerMemoDeleteFailed;

  /// No description provided for @clientTrainerMemoDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'메모를 삭제할까요?'**
  String get clientTrainerMemoDeleteTitle;

  /// No description provided for @clientTrainerMemoDeleteBody.
  ///
  /// In ko, this message translates to:
  /// **'삭제한 메모는 되돌릴 수 없어요.'**
  String get clientTrainerMemoDeleteBody;

  /// No description provided for @clientExerciseMemoAdd.
  ///
  /// In ko, this message translates to:
  /// **'메모 남기기'**
  String get clientExerciseMemoAdd;

  /// No description provided for @clientExerciseMemoCount.
  ///
  /// In ko, this message translates to:
  /// **'메모 {count}개'**
  String clientExerciseMemoCount(int count);

  /// No description provided for @clientExerciseMemoHint.
  ///
  /// In ko, this message translates to:
  /// **'이 운동 기록에서 기억할 내용을 적어 주세요'**
  String get clientExerciseMemoHint;

  /// No description provided for @clientExerciseMemoSaved.
  ///
  /// In ko, this message translates to:
  /// **'메모에 남겼어요.'**
  String get clientExerciseMemoSaved;

  /// No description provided for @clientMemoTagManual.
  ///
  /// In ko, this message translates to:
  /// **'직접 작성'**
  String get clientMemoTagManual;

  /// No description provided for @clientMemoTagPtSession.
  ///
  /// In ko, this message translates to:
  /// **'PT · {date}'**
  String clientMemoTagPtSession(String date);

  /// No description provided for @clientMemoTagPersonal.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 · {date}'**
  String clientMemoTagPersonal(String date);

  /// No description provided for @clientMemoTagPersonalNamed.
  ///
  /// In ko, this message translates to:
  /// **'개인운동 · {date} {name}'**
  String clientMemoTagPersonalNamed(String date, String name);

  /// No description provided for @clientMemoTagMemberLog.
  ///
  /// In ko, this message translates to:
  /// **'회원 추가 · {date}'**
  String clientMemoTagMemberLog(String date);

  /// No description provided for @clientMemoTagDay.
  ///
  /// In ko, this message translates to:
  /// **'운동 기록 · {date}'**
  String clientMemoTagDay(String date);

  /// No description provided for @clientMemoEdited.
  ///
  /// In ko, this message translates to:
  /// **'수정됨'**
  String get clientMemoEdited;

  /// No description provided for @clientMemoSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'메모 검색 (본문·태그)'**
  String get clientMemoSearchHint;

  /// No description provided for @clientMemoSearchEmpty.
  ///
  /// In ko, this message translates to:
  /// **'찾는 메모가 없어요.'**
  String get clientMemoSearchEmpty;

  /// No description provided for @clientMemoCategoryExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동'**
  String get clientMemoCategoryExercise;

  /// No description provided for @clientMemoCategoryDiet.
  ///
  /// In ko, this message translates to:
  /// **'식단'**
  String get clientMemoCategoryDiet;

  /// No description provided for @clientMemoCategoryPain.
  ///
  /// In ko, this message translates to:
  /// **'통증·부상'**
  String get clientMemoCategoryPain;

  /// No description provided for @clientMemoCategoryLife.
  ///
  /// In ko, this message translates to:
  /// **'생활·일정'**
  String get clientMemoCategoryLife;

  /// No description provided for @clientMemoRecordLink.
  ///
  /// In ko, this message translates to:
  /// **'운동 기록 연결 (선택)'**
  String get clientMemoRecordLink;

  /// No description provided for @clientMemoRecordNone.
  ///
  /// In ko, this message translates to:
  /// **'연결 안 함'**
  String get clientMemoRecordNone;

  /// No description provided for @clientMemoRecordEmpty.
  ///
  /// In ko, this message translates to:
  /// **'최근 14일 운동 기록이 없어요'**
  String get clientMemoRecordEmpty;

  /// No description provided for @clientMemoRecordDay.
  ///
  /// In ko, this message translates to:
  /// **'{month}/{day} ({weekday})'**
  String clientMemoRecordDay(String month, String day, String weekday);

  /// No description provided for @clientMemoRecordPtSession.
  ///
  /// In ko, this message translates to:
  /// **'{date} PT'**
  String clientMemoRecordPtSession(String date);

  /// No description provided for @clientMemoRecordPersonal.
  ///
  /// In ko, this message translates to:
  /// **'{date} 개인운동'**
  String clientMemoRecordPersonal(String date);

  /// No description provided for @clientMemoRecordPersonalNamed.
  ///
  /// In ko, this message translates to:
  /// **'{date} 개인운동 · {name}'**
  String clientMemoRecordPersonalNamed(String date, String name);

  /// No description provided for @clientMemoRecordMemberLog.
  ///
  /// In ko, this message translates to:
  /// **'{date} 회원 추가'**
  String clientMemoRecordMemberLog(String date);

  /// No description provided for @clientMemoRecordExerciseDay.
  ///
  /// In ko, this message translates to:
  /// **'{date} 운동 기록'**
  String clientMemoRecordExerciseDay(String date);

  /// No description provided for @clientMemoTabMemo.
  ///
  /// In ko, this message translates to:
  /// **'메모'**
  String get clientMemoTabMemo;

  /// No description provided for @clientMemoTabFeedback.
  ///
  /// In ko, this message translates to:
  /// **'피드백'**
  String get clientMemoTabFeedback;

  /// No description provided for @clientFeedbackPrivate.
  ///
  /// In ko, this message translates to:
  /// **'회원과 주고받은 피드백이에요. 누르면 쓴 자리로 가서 고칠 수 있어요.'**
  String get clientFeedbackPrivate;

  /// No description provided for @clientFeedbackToMember.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 → 회원'**
  String get clientFeedbackToMember;

  /// No description provided for @clientFeedbackFromMember.
  ///
  /// In ko, this message translates to:
  /// **'회원 → 트레이너'**
  String get clientFeedbackFromMember;

  /// No description provided for @clientFeedbackSourcePt.
  ///
  /// In ko, this message translates to:
  /// **'PT · {date}'**
  String clientFeedbackSourcePt(String date);

  /// No description provided for @clientFeedbackSourceReport.
  ///
  /// In ko, this message translates to:
  /// **'리포트 · {date} 주'**
  String clientFeedbackSourceReport(String date);

  /// No description provided for @clientFeedbackSourceWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간 피드백 · {date} 주'**
  String clientFeedbackSourceWeekly(String date);

  /// No description provided for @clientFeedbackWeeklyNoNote.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 피드백 없음'**
  String get clientFeedbackWeeklyNoNote;

  /// No description provided for @clientFeedbackEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 주고받은 피드백이 없어요.'**
  String get clientFeedbackEmpty;

  /// No description provided for @clientFeedbackLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'피드백을 불러오지 못했어요. 잠시 후 다시 시도해 주세요'**
  String get clientFeedbackLoadFailed;

  /// No description provided for @clientFeedbackSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'피드백 검색 (본문·출처·방향)'**
  String get clientFeedbackSearchHint;

  /// No description provided for @clientFeedbackSearchEmpty.
  ///
  /// In ko, this message translates to:
  /// **'찾는 피드백이 없어요.'**
  String get clientFeedbackSearchEmpty;

  /// No description provided for @programEditorDefaultName.
  ///
  /// In ko, this message translates to:
  /// **'{goal} 프로그램'**
  String programEditorDefaultName(String goal);

  /// No description provided for @programEditorSaveUnsupported.
  ///
  /// In ko, this message translates to:
  /// **'프로그램 이름을 입력해 주세요'**
  String get programEditorSaveUnsupported;

  /// No description provided for @programDraftSaved.
  ///
  /// In ko, this message translates to:
  /// **'프로그램을 저장했어요'**
  String get programDraftSaved;

  /// No description provided for @programAssignConfirmAttachBody.
  ///
  /// In ko, this message translates to:
  /// **'{date} {session}에 이미 예정된 {name}님의 PT에 이 프로그램이 연결돼요. 고른 시간({selected})은 적용되지 않아요.'**
  String programAssignConfirmAttachBody(
    String name,
    String date,
    String session,
    String selected,
  );

  /// No description provided for @programAssignConfirmChooseBody.
  ///
  /// In ko, this message translates to:
  /// **'{date}에 고른 시간({selected})과 겹치는 {name}님의 PT가 여러 개예요. 프로그램을 연결할 회차를 골라 주세요. 고른 시간은 적용되지 않아요.'**
  String programAssignConfirmChooseBody(
    String name,
    String date,
    String selected,
  );

  /// No description provided for @coachAttachTargetChanged.
  ///
  /// In ko, this message translates to:
  /// **'연결할 PT 일정이 그 사이 바뀌었어요. 일정 추가를 다시 눌러 확인해 주세요'**
  String get coachAttachTargetChanged;

  /// No description provided for @coachScheduleOverlap.
  ///
  /// In ko, this message translates to:
  /// **'고른 시간에 이미 다른 일정이 있어 등록하지 않았어요. 시간을 바꿔 다시 보내 주세요'**
  String get coachScheduleOverlap;

  /// No description provided for @programEditorNoExercises.
  ///
  /// In ko, this message translates to:
  /// **'운동을 하나 이상 추가해 주세요'**
  String get programEditorNoExercises;

  /// No description provided for @programEditorExerciseNameInvalid.
  ///
  /// In ko, this message translates to:
  /// **'이름이 비었거나 100자를 넘는 운동이 있어요'**
  String get programEditorExerciseNameInvalid;

  /// No description provided for @programEditorRegisterDatePast.
  ///
  /// In ko, this message translates to:
  /// **'지난 날짜예요. 오늘 이후 날짜를 골라 주세요'**
  String get programEditorRegisterDatePast;

  /// No description provided for @programEditorSending.
  ///
  /// In ko, this message translates to:
  /// **'일정에 추가하는 중이에요'**
  String get programEditorSending;

  /// No description provided for @programEditorAlreadySent.
  ///
  /// In ko, this message translates to:
  /// **'방금 보낸 구성이에요. 새 구성을 반영하면 다시 보낼 수 있어요'**
  String get programEditorAlreadySent;

  /// No description provided for @coachSendNetworkFailed.
  ///
  /// In ko, this message translates to:
  /// **'네트워크 연결을 확인한 뒤 다시 시도해 주세요'**
  String get coachSendNetworkFailed;

  /// No description provided for @coachSendClientNotFound.
  ///
  /// In ko, this message translates to:
  /// **'담당 회원을 찾을 수 없어요. 회원 연결 상태를 확인해 주세요'**
  String get coachSendClientNotFound;

  /// No description provided for @coachSendInvalid.
  ///
  /// In ko, this message translates to:
  /// **'서버가 이 일정을 받지 않았어요. 날짜·시간·운동 구성을 확인해 주세요'**
  String get coachSendInvalid;

  /// No description provided for @coachSendUnverified.
  ///
  /// In ko, this message translates to:
  /// **'등록 결과를 확인하지 못했어요. 스케줄에서 등록 여부를 확인해 주세요'**
  String get coachSendUnverified;

  /// No description provided for @programEditorSessionLimitReached.
  ///
  /// In ko, this message translates to:
  /// **'세션은 최대 {max}개까지 만들 수 있어요'**
  String programEditorSessionLimitReached(int max);

  /// No description provided for @programEditorExerciseLimitReached.
  ///
  /// In ko, this message translates to:
  /// **'운동은 프로그램 전체에서 최대 {max}개까지 넣을 수 있어요'**
  String programEditorExerciseLimitReached(int max);

  /// No description provided for @programEditorSizeExceeded.
  ///
  /// In ko, this message translates to:
  /// **'세션 {sessions}/{maxSessions}개 · 운동 {exercises}/{maxExercises}개 — 한도를 넘은 만큼 줄여야 일정에 추가할 수 있어요'**
  String programEditorSizeExceeded(
    int sessions,
    int maxSessions,
    int exercises,
    int maxExercises,
  );

  /// No description provided for @programAssignConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'일정에 추가할까요?'**
  String get programAssignConfirmTitle;

  /// No description provided for @programAssignConfirmBody.
  ///
  /// In ko, this message translates to:
  /// **'{date} {time}에 {name}님의 PT 일정을 새로 만들고 이 프로그램을 추가해요.'**
  String programAssignConfirmBody(String name, String date, String time);

  /// No description provided for @programEditorSaveTemplate.
  ///
  /// In ko, this message translates to:
  /// **'템플릿 저장'**
  String get programEditorSaveTemplate;

  /// No description provided for @programEditorAddSchedule.
  ///
  /// In ko, this message translates to:
  /// **'일정 추가'**
  String get programEditorAddSchedule;

  /// No description provided for @programEditorExerciseConfig.
  ///
  /// In ko, this message translates to:
  /// **'운동 구성'**
  String get programEditorExerciseConfig;

  /// No description provided for @programEditorAddSession.
  ///
  /// In ko, this message translates to:
  /// **'세션 추가'**
  String get programEditorAddSession;

  /// No description provided for @programTemplateSessionPickerTitle.
  ///
  /// In ko, this message translates to:
  /// **'어느 세션에 추가할까요?'**
  String get programTemplateSessionPickerTitle;

  /// No description provided for @programTemplateSessionPickerBody.
  ///
  /// In ko, this message translates to:
  /// **'\'{name}\' 템플릿을 추가할 세션을 골라 주세요.'**
  String programTemplateSessionPickerBody(String name);

  /// No description provided for @programEditorAiReapplyTitle.
  ///
  /// In ko, this message translates to:
  /// **'AI 운동을 새 안으로 바꿀까요?'**
  String get programEditorAiReapplyTitle;

  /// No description provided for @programEditorAiReapplyBody.
  ///
  /// In ko, this message translates to:
  /// **'앞서 반영한 AI 운동 {count}개를 새 안으로 바꿔요. 직접 추가하거나 고친 운동은 그대로 남아요.'**
  String programEditorAiReapplyBody(int count);

  /// No description provided for @programEditorAiReapplyReplace.
  ///
  /// In ko, this message translates to:
  /// **'바꾸기'**
  String get programEditorAiReapplyReplace;

  /// No description provided for @programEditorAiReapplyAppend.
  ///
  /// In ko, this message translates to:
  /// **'뒤에 추가'**
  String get programEditorAiReapplyAppend;

  /// No description provided for @programEditorSessionNameTyped.
  ///
  /// In ko, this message translates to:
  /// **'{type} 세션'**
  String programEditorSessionNameTyped(String type);

  /// No description provided for @programEditorSessionNameNumbered.
  ///
  /// In ko, this message translates to:
  /// **'{type} 세션 {index}'**
  String programEditorSessionNameNumbered(String type, int index);

  /// No description provided for @programEditorSessionUp.
  ///
  /// In ko, this message translates to:
  /// **'세션 위로 이동'**
  String get programEditorSessionUp;

  /// No description provided for @programEditorSessionDown.
  ///
  /// In ko, this message translates to:
  /// **'세션 아래로 이동'**
  String get programEditorSessionDown;

  /// No description provided for @programEditorSessionReset.
  ///
  /// In ko, this message translates to:
  /// **'세션 초기화'**
  String get programEditorSessionReset;

  /// No description provided for @programEditorSessionResetTitle.
  ///
  /// In ko, this message translates to:
  /// **'세션을 초기화할까요?'**
  String get programEditorSessionResetTitle;

  /// No description provided for @programEditorSessionResetBody.
  ///
  /// In ko, this message translates to:
  /// **'\'{name}\' 세션의 운동이 모두 지워져요. 세션 자체와 다른 세션은 그대로 남아요.'**
  String programEditorSessionResetBody(String name);

  /// No description provided for @programEditorSessionEmpty.
  ///
  /// In ko, this message translates to:
  /// **'운동을 추가해 세션을 구성하세요.'**
  String get programEditorSessionEmpty;

  /// No description provided for @programEditorAdd.
  ///
  /// In ko, this message translates to:
  /// **'추가'**
  String get programEditorAdd;

  /// No description provided for @programEditorAddExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동 추가'**
  String get programEditorAddExercise;

  /// No description provided for @programEditorExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동'**
  String get programEditorExercise;

  /// No description provided for @programEditorExerciseUp.
  ///
  /// In ko, this message translates to:
  /// **'운동 위로 이동'**
  String get programEditorExerciseUp;

  /// No description provided for @programEditorExerciseDown.
  ///
  /// In ko, this message translates to:
  /// **'운동 아래로 이동'**
  String get programEditorExerciseDown;

  /// No description provided for @programEditorExerciseMoveSession.
  ///
  /// In ko, this message translates to:
  /// **'다른 세션으로'**
  String get programEditorExerciseMoveSession;

  /// No description provided for @programEditorExerciseMoveTitle.
  ///
  /// In ko, this message translates to:
  /// **'어느 세션으로 옮길까요?'**
  String get programEditorExerciseMoveTitle;

  /// No description provided for @programEditorExerciseMoveBody.
  ///
  /// In ko, this message translates to:
  /// **'\'{name}\' 운동을 옮길 세션을 골라 주세요.'**
  String programEditorExerciseMoveBody(String name);

  /// No description provided for @programEditorSets.
  ///
  /// In ko, this message translates to:
  /// **'세트 수'**
  String get programEditorSets;

  /// No description provided for @programEditorReps.
  ///
  /// In ko, this message translates to:
  /// **'횟수'**
  String get programEditorReps;

  /// No description provided for @programEditorWeight.
  ///
  /// In ko, this message translates to:
  /// **'중량 (kg)'**
  String get programEditorWeight;

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님은 이번 주 운동과 식단을 계획대로 잘 이어 갔어요. 지금 리듬을 지키면서 다음 주에는 운동 강도를 조금 올려 봐도 좋겠어요.'**
  String reportsDemoSummarySteadyThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님은 그 주 운동과 식단을 계획대로 잘 이어 갔어요. 이 리듬을 지키면서 운동 강도를 조금씩 올려 봐도 좋겠어요.'**
  String reportsDemoSummarySteadyPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님은 이번 주 운동 완료율이 주춤했어요. 일정이 빠듯했는지 먼저 물어보고, 다음 주는 짧은 루틴부터 다시 붙여 보는 것을 권해 드려요.'**
  String reportsDemoSummaryCompletionThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님은 그 주 운동 완료율이 주춤했어요. 일정이 빠듯했는지 먼저 물어보고, 짧은 루틴부터 다시 붙여 보는 것을 권해 드려요.'**
  String reportsDemoSummaryCompletionPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님이 이번 주 몇몇 운동을 건너뛰었어요. 통증이나 난이도 때문인지 확인하고, 대신할 동작을 함께 정해 두면 좋겠어요.'**
  String reportsDemoSummarySkippedThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님이 그 주 몇몇 운동을 건너뛰었어요. 통증이나 난이도 때문인지 확인하고, 대신할 동작을 함께 정해 두면 좋겠어요.'**
  String reportsDemoSummarySkippedPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님은 이번 주 짠 식사가 잦았어요. 국물과 가공식품을 줄이는 작은 목표 하나를 함께 정해 보세요.'**
  String reportsDemoSummarySodiumThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님은 그 주 짠 식사가 잦았어요. 국물과 가공식품을 줄이는 작은 목표 하나를 함께 정해 보세요.'**
  String reportsDemoSummarySodiumPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님은 이번 주 단 음식과 음료가 잦았어요. 간식을 과일이나 견과로 바꾸는 것부터 제안해 보세요.'**
  String reportsDemoSummarySugarThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님은 그 주 단 음식과 음료가 잦았어요. 간식을 과일이나 견과로 바꾸는 것부터 제안해 보세요.'**
  String reportsDemoSummarySugarPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님의 이번 주 섭취 칼로리가 목표에서 벗어났어요. 끼니를 거르거나 몰아 먹은 날이 있었는지 식단 기록을 함께 짚어 보세요.'**
  String reportsDemoSummaryCaloriesThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님의 그 주 섭취 칼로리가 목표에서 벗어났어요. 끼니를 거르거나 몰아 먹은 날이 있었는지 식단 기록을 함께 짚어 보세요.'**
  String reportsDemoSummaryCaloriesPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님은 이번 주 탄수화물·단백질·지방 배분이 목표와 달랐어요. 끼니 구성을 함께 점검해 균형을 맞춰 보세요.'**
  String reportsDemoSummaryMacroThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In ko, this message translates to:
  /// **'{name}님은 그 주 탄수화물·단백질·지방 배분이 목표와 달랐어요. 끼니 구성을 함께 점검해 균형을 맞춰 보세요.'**
  String reportsDemoSummaryMacroPastWeek(String name);

  /// No description provided for @reportsBackToList.
  ///
  /// In ko, this message translates to:
  /// **'회원 목록'**
  String get reportsBackToList;

  /// No description provided for @reportsAverageSodium.
  ///
  /// In ko, this message translates to:
  /// **'평균 나트륨'**
  String get reportsAverageSodium;

  /// No description provided for @reportsFeedbackTitle.
  ///
  /// In ko, this message translates to:
  /// **'트레이너 피드백'**
  String get reportsFeedbackTitle;

  /// No description provided for @reportsFeedbackDraftNote.
  ///
  /// In ko, this message translates to:
  /// **'수치에서 자동으로 채운 초안이에요. 보내기 전에 확인하고 고쳐 주세요.'**
  String get reportsFeedbackDraftNote;

  /// No description provided for @reportsFeedbackUndo.
  ///
  /// In ko, this message translates to:
  /// **'되돌리기'**
  String get reportsFeedbackUndo;

  /// No description provided for @reportsFeedbackRedo.
  ///
  /// In ko, this message translates to:
  /// **'다시 실행'**
  String get reportsFeedbackRedo;

  /// No description provided for @reportsFeedbackSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get reportsFeedbackSave;

  /// No description provided for @reportsFeedbackSaving.
  ///
  /// In ko, this message translates to:
  /// **'저장 중…'**
  String get reportsFeedbackSaving;

  /// No description provided for @reportsFeedbackSaved.
  ///
  /// In ko, this message translates to:
  /// **'피드백 초안을 저장했어요.'**
  String get reportsFeedbackSaved;

  /// No description provided for @reportsFeedbackSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'초안을 저장하지 못했어요. 다시 시도해 주세요.'**
  String get reportsFeedbackSaveFailed;

  /// No description provided for @reportsFeedbackHint.
  ///
  /// In ko, this message translates to:
  /// **'회원에게 전달할 코칭 피드백을 작성하세요.'**
  String get reportsFeedbackHint;

  /// No description provided for @reportsAiTitle.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 요약'**
  String get reportsAiTitle;

  /// No description provided for @reportsAiNextWeek.
  ///
  /// In ko, this message translates to:
  /// **'다음 주 코칭 제안'**
  String get reportsAiNextWeek;

  /// No description provided for @reportsAiMoreWatchpoints.
  ///
  /// In ko, this message translates to:
  /// **'외 {count}건은 리포트 본문에서 확인하세요.'**
  String reportsAiMoreWatchpoints(int count);

  /// No description provided for @reportsActionSodium.
  ///
  /// In ko, this message translates to:
  /// **'국물·절임 반찬을 절반만 남기도록 안내해 주세요.'**
  String get reportsActionSodium;

  /// No description provided for @reportsActionSugar.
  ///
  /// In ko, this message translates to:
  /// **'당류가 목표({target}g)를 넘긴 날이 있어요. 음료·간식부터 짚어 주세요.'**
  String reportsActionSugar(String target);

  /// No description provided for @reportsActionLowCompletion.
  ///
  /// In ko, this message translates to:
  /// **'프로그램 난이도를 한 단계 낮춰 완수 경험을 먼저 만들어 주세요.'**
  String get reportsActionLowCompletion;

  /// No description provided for @reportsActionHighCompletion.
  ///
  /// In ko, this message translates to:
  /// **'페이스가 좋아요. 다음 주에는 세트 수나 중량을 한 단계 올려 보세요.'**
  String get reportsActionHighCompletion;

  /// No description provided for @reportsActionSkipped.
  ///
  /// In ko, this message translates to:
  /// **'{names} 대체 운동을 준비해 다음 PT에서 맞춰 주세요.'**
  String reportsActionSkipped(String names);

  /// No description provided for @reportsActionUnlogged.
  ///
  /// In ko, this message translates to:
  /// **'기록이 없는 날이 {days}일이었어요. 기록 습관을 먼저 잡아 주세요.'**
  String reportsActionUnlogged(int days);

  /// No description provided for @reportsActionCalories.
  ///
  /// In ko, this message translates to:
  /// **'칼로리가 목표({target}kcal)보다 적어요. 단백질 한 끼 보완을 제안해 주세요.'**
  String reportsActionCalories(String target);

  /// No description provided for @reportsAiGenerated.
  ///
  /// In ko, this message translates to:
  /// **'AI 생성'**
  String get reportsAiGenerated;

  /// No description provided for @reportsAiUseAsDraft.
  ///
  /// In ko, this message translates to:
  /// **'피드백으로 가져오기'**
  String get reportsAiUseAsDraft;

  /// No description provided for @reportsAiRegenerate.
  ///
  /// In ko, this message translates to:
  /// **'다시 생성'**
  String get reportsAiRegenerate;

  /// No description provided for @reportsAiFailed.
  ///
  /// In ko, this message translates to:
  /// **'요약을 만들지 못했어요. 다시 시도해 주세요.'**
  String get reportsAiFailed;

  /// Report AI card when the summary returns 429 daily_limit. No retry button — retrying gives the same result today (#3032).
  ///
  /// In ko, this message translates to:
  /// **'오늘 AI 생성 한도를 다 썼어요. 내일 다시 이용해 주세요.'**
  String get reportsAiDailyLimit;

  /// No description provided for @reportsPdfFallbackClient.
  ///
  /// In ko, this message translates to:
  /// **'회원'**
  String get reportsPdfFallbackClient;

  /// No description provided for @reportsPdfDocTitle.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트'**
  String get reportsPdfDocTitle;

  /// No description provided for @reportsPdfClient.
  ///
  /// In ko, this message translates to:
  /// **'회원  {name}'**
  String reportsPdfClient(String name);

  /// No description provided for @reportsPdfPeriod.
  ///
  /// In ko, this message translates to:
  /// **'기간  {start} ~ {end}'**
  String reportsPdfPeriod(String start, String end);

  /// No description provided for @reportsPdfSectionMetrics.
  ///
  /// In ko, this message translates to:
  /// **'핵심 지표'**
  String get reportsPdfSectionMetrics;

  /// No description provided for @reportsPdfSectionChange.
  ///
  /// In ko, this message translates to:
  /// **'지난주 대비 변화'**
  String get reportsPdfSectionChange;

  /// No description provided for @reportsPdfSectionTrend.
  ///
  /// In ko, this message translates to:
  /// **'주간 추이 (월~일)'**
  String get reportsPdfSectionTrend;

  /// No description provided for @reportsPdfSectionDaily.
  ///
  /// In ko, this message translates to:
  /// **'요일별 운동'**
  String get reportsPdfSectionDaily;

  /// No description provided for @reportsPdfBullet.
  ///
  /// In ko, this message translates to:
  /// **'• {label}: {value}'**
  String reportsPdfBullet(String label, String value);

  /// No description provided for @reportsPdfDay.
  ///
  /// In ko, this message translates to:
  /// **'{weekday}: {completion} · {exercises}'**
  String reportsPdfDay(String weekday, String completion, String exercises);

  /// No description provided for @reportsPdfLabelCompletion.
  ///
  /// In ko, this message translates to:
  /// **'운동 완료율'**
  String get reportsPdfLabelCompletion;

  /// No description provided for @reportsPdfLabelSessions.
  ///
  /// In ko, this message translates to:
  /// **'완료 PT'**
  String get reportsPdfLabelSessions;

  /// No description provided for @reportsPdfLabelSessionCount.
  ///
  /// In ko, this message translates to:
  /// **'완료 PT'**
  String get reportsPdfLabelSessionCount;

  /// No description provided for @reportsPdfLabelSodiumOver.
  ///
  /// In ko, this message translates to:
  /// **'나트륨 목표 초과'**
  String get reportsPdfLabelSodiumOver;

  /// No description provided for @reportsPdfLabelCalories.
  ///
  /// In ko, this message translates to:
  /// **'평균 칼로리'**
  String get reportsPdfLabelCalories;

  /// No description provided for @reportsPdfLabelSugar.
  ///
  /// In ko, this message translates to:
  /// **'평균 당류'**
  String get reportsPdfLabelSugar;

  /// No description provided for @reportsPdfLabelCaloriesShort.
  ///
  /// In ko, this message translates to:
  /// **'칼로리'**
  String get reportsPdfLabelCaloriesShort;

  /// No description provided for @reportsPdfLabelSodiumShort.
  ///
  /// In ko, this message translates to:
  /// **'나트륨'**
  String get reportsPdfLabelSodiumShort;

  /// No description provided for @reportsPdfLabelSugarShort.
  ///
  /// In ko, this message translates to:
  /// **'당류'**
  String get reportsPdfLabelSugarShort;

  /// No description provided for @reportsPdfValuePercent.
  ///
  /// In ko, this message translates to:
  /// **'{value}%'**
  String reportsPdfValuePercent(String value);

  /// No description provided for @reportsPdfValueMg.
  ///
  /// In ko, this message translates to:
  /// **'{value}mg'**
  String reportsPdfValueMg(String value);

  /// No description provided for @reportsPdfValueKcal.
  ///
  /// In ko, this message translates to:
  /// **'{value}kcal'**
  String reportsPdfValueKcal(String value);

  /// No description provided for @reportsPdfValueGram.
  ///
  /// In ko, this message translates to:
  /// **'{value}g'**
  String reportsPdfValueGram(String value);

  /// No description provided for @reportsPdfValueDays.
  ///
  /// In ko, this message translates to:
  /// **'{value}일'**
  String reportsPdfValueDays(String value);

  /// No description provided for @reportsPdfValueSessions.
  ///
  /// In ko, this message translates to:
  /// **'{value}회'**
  String reportsPdfValueSessions(String value);

  /// No description provided for @reportsPdfAttendance.
  ///
  /// In ko, this message translates to:
  /// **'{done}/{booked}회 ({rate}%)'**
  String reportsPdfAttendance(String done, String booked, String rate);

  /// No description provided for @reportsPdfNoData.
  ///
  /// In ko, this message translates to:
  /// **'미집계'**
  String get reportsPdfNoData;

  /// No description provided for @reportsPdfNoFeedback.
  ///
  /// In ko, this message translates to:
  /// **'피드백 없음'**
  String get reportsPdfNoFeedback;

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

  /// No description provided for @unitMg.
  ///
  /// In ko, this message translates to:
  /// **'mg'**
  String get unitMg;

  /// No description provided for @unitGram.
  ///
  /// In ko, this message translates to:
  /// **'g'**
  String get unitGram;

  /// No description provided for @a11yRemoveExercise.
  ///
  /// In ko, this message translates to:
  /// **'운동 삭제'**
  String get a11yRemoveExercise;

  /// No description provided for @a11yRemoveCertification.
  ///
  /// In ko, this message translates to:
  /// **'자격증 삭제'**
  String get a11yRemoveCertification;

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

  /// No description provided for @a11ySendMessage.
  ///
  /// In ko, this message translates to:
  /// **'메시지 보내기'**
  String get a11ySendMessage;

  /// AI 1~3단계 화면에서 AI 추천 대신 빈 템플릿으로 바로 넘어가는 버튼.
  ///
  /// In ko, this message translates to:
  /// **'직접 만들기'**
  String get aiManualCreate;

  /// 직접 만들기로 넘어간 뒤 다시 AI 마법사 화면으로 돌아가는 링크.
  ///
  /// In ko, this message translates to:
  /// **'AI 추천으로 돌아가기'**
  String get aiReturnToWizard;

  /// 채팅 스레드에서 날이 바뀌는 자리의 날짜 구분선. 요일까지 적는다(ko: 2026년 9월 14일 월요일, en: Monday, September 14, 2026).
  ///
  /// In ko, this message translates to:
  /// **'{date}'**
  String chatDateDivider(DateTime date);

  /// No description provided for @coachClientDemographics.
  ///
  /// In ko, this message translates to:
  /// **'{gender} · {age}세'**
  String coachClientDemographics(String gender, int age);

  /// Age-only identity label when the member has no gender on file or the server hides it (#2814, #2870).
  ///
  /// In ko, this message translates to:
  /// **'{age}세'**
  String coachClientAge(int age);

  /// No description provided for @routineFormDecrease.
  ///
  /// In ko, this message translates to:
  /// **'줄이기'**
  String get routineFormDecrease;

  /// No description provided for @routineFormIncrease.
  ///
  /// In ko, this message translates to:
  /// **'늘리기'**
  String get routineFormIncrease;

  /// No description provided for @reportsPending.
  ///
  /// In ko, this message translates to:
  /// **'안 보냄'**
  String get reportsPending;

  /// No description provided for @reportsCountPeople.
  ///
  /// In ko, this message translates to:
  /// **'{count}명'**
  String reportsCountPeople(int count);

  /// No description provided for @reportsSortLabel.
  ///
  /// In ko, this message translates to:
  /// **'정렬'**
  String get reportsSortLabel;

  /// No description provided for @reportsSortPriority.
  ///
  /// In ko, this message translates to:
  /// **'관리 필요 우선'**
  String get reportsSortPriority;

  /// No description provided for @reportsSortName.
  ///
  /// In ko, this message translates to:
  /// **'이름 오름차순'**
  String get reportsSortName;

  /// No description provided for @reportsSortNameDescending.
  ///
  /// In ko, this message translates to:
  /// **'이름 내림차순'**
  String get reportsSortNameDescending;

  /// No description provided for @reportsSentSortUnread.
  ///
  /// In ko, this message translates to:
  /// **'안 읽은 회원 먼저'**
  String get reportsSentSortUnread;

  /// No description provided for @reportsSendProgress.
  ///
  /// In ko, this message translates to:
  /// **'{done} / {total} 보냄'**
  String reportsSendProgress(int done, int total);

  /// No description provided for @reportsSendPercent.
  ///
  /// In ko, this message translates to:
  /// **'{percent}%'**
  String reportsSendPercent(int percent);

  /// No description provided for @reportsQueueAllSent.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 리포트를 모두 보냈어요'**
  String get reportsQueueAllSent;

  /// No description provided for @reportsSentColumn.
  ///
  /// In ko, this message translates to:
  /// **'보냄'**
  String get reportsSentColumn;

  /// No description provided for @reportsSentColumnEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 보낸 리포트가 없어요'**
  String get reportsSentColumnEmpty;

  /// No description provided for @reportsSentSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'보낸 리포트 보기'**
  String get reportsSentSubtitle;

  /// No description provided for @reportsOpenDraft.
  ///
  /// In ko, this message translates to:
  /// **'열기'**
  String get reportsOpenDraft;

  /// No description provided for @reportsReasonUnknown.
  ///
  /// In ko, this message translates to:
  /// **'수치를 불러오는 중'**
  String get reportsReasonUnknown;

  /// No description provided for @reportsReasonCompletion.
  ///
  /// In ko, this message translates to:
  /// **'완료율 {percent}%'**
  String reportsReasonCompletion(int percent);

  /// No description provided for @reportsReasonSessionDone.
  ///
  /// In ko, this message translates to:
  /// **'완료 PT {count}회'**
  String reportsReasonSessionDone(int count);

  /// No description provided for @reportsReasonSlump.
  ///
  /// In ko, this message translates to:
  /// **'주 후반 {points}%p 하락'**
  String reportsReasonSlump(int points);

  /// No description provided for @reportsReasonRising.
  ///
  /// In ko, this message translates to:
  /// **'주 후반 {points}%p 상승'**
  String reportsReasonRising(int points);

  /// No description provided for @reportsReasonFullLog.
  ///
  /// In ko, this message translates to:
  /// **'7일 전량 기록'**
  String get reportsReasonFullLog;

  /// No description provided for @reportsReasonOnboarding.
  ///
  /// In ko, this message translates to:
  /// **'신규 · 적응 중'**
  String get reportsReasonOnboarding;

  /// No description provided for @reportsReasonSteady.
  ///
  /// In ko, this message translates to:
  /// **'순조로움'**
  String get reportsReasonSteady;

  /// No description provided for @reportsSentOn.
  ///
  /// In ko, this message translates to:
  /// **'{date} 보냄'**
  String reportsSentOn(String date);

  /// No description provided for @reportsSentRead.
  ///
  /// In ko, this message translates to:
  /// **'읽음'**
  String get reportsSentRead;

  /// No description provided for @reportsSentUnread.
  ///
  /// In ko, this message translates to:
  /// **'안 읽음'**
  String get reportsSentUnread;

  /// No description provided for @reportsBackToWorkbench.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 리포트'**
  String get reportsBackToWorkbench;

  /// No description provided for @reportsSentHeadline.
  ///
  /// In ko, this message translates to:
  /// **'{name}님에게 보낸 리포트'**
  String reportsSentHeadline(String name);

  /// No description provided for @reportsSentAt.
  ///
  /// In ko, this message translates to:
  /// **'{date} {time} 보냄'**
  String reportsSentAt(String date, String time);

  /// No description provided for @reportsSentRewrite.
  ///
  /// In ko, this message translates to:
  /// **'이 내용으로 다시 작성'**
  String get reportsSentRewrite;

  /// No description provided for @reportsHistoryButton.
  ///
  /// In ko, this message translates to:
  /// **'지난 리포트'**
  String get reportsHistoryButton;

  /// No description provided for @reportsViewSent.
  ///
  /// In ko, this message translates to:
  /// **'보기'**
  String get reportsViewSent;

  /// No description provided for @reportsHistoryTitle.
  ///
  /// In ko, this message translates to:
  /// **'{name}님의 지난 리포트'**
  String reportsHistoryTitle(String name);

  /// No description provided for @reportsHistoryBack.
  ///
  /// In ko, this message translates to:
  /// **'지난 리포트'**
  String get reportsHistoryBack;

  /// No description provided for @reportsHistoryUnsent.
  ///
  /// In ko, this message translates to:
  /// **'안 보냄'**
  String get reportsHistoryUnsent;

  /// No description provided for @reportsHistoryThisWeek.
  ///
  /// In ko, this message translates to:
  /// **'이번 주'**
  String get reportsHistoryThisWeek;

  /// No description provided for @reportsHistoryEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 보낸 리포트가 없어요'**
  String get reportsHistoryEmpty;

  /// No description provided for @reportsHistoryLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'지난 리포트를 불러오지 못했어요'**
  String get reportsHistoryLoadFailed;

  /// No description provided for @reportsHistoryMore.
  ///
  /// In ko, this message translates to:
  /// **'더 보기'**
  String get reportsHistoryMore;

  /// No description provided for @reportsHistoryMoreFailed.
  ///
  /// In ko, this message translates to:
  /// **'더 불러오지 못했어요. 다시 눌러 주세요.'**
  String get reportsHistoryMoreFailed;

  /// No description provided for @reportsHistorySendCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}회 보냄'**
  String reportsHistorySendCount(int count);

  /// No description provided for @reportsHistoryPdf.
  ///
  /// In ko, this message translates to:
  /// **'PDF'**
  String get reportsHistoryPdf;

  /// No description provided for @reportsResendTitle.
  ///
  /// In ko, this message translates to:
  /// **'이미 보낸 리포트예요'**
  String get reportsResendTitle;

  /// No description provided for @reportsResendBody.
  ///
  /// In ko, this message translates to:
  /// **'{name}님에게 {date} {time}에 이 주 리포트를 보냈어요. 다시 보내면 회원에게 메시지로 한 번 더 도착해요.'**
  String reportsResendBody(String name, String date, String time);

  /// No description provided for @reportsResendConfirm.
  ///
  /// In ko, this message translates to:
  /// **'다시 보내기'**
  String get reportsResendConfirm;

  /// No description provided for @reportsSendHistoryFailed.
  ///
  /// In ko, this message translates to:
  /// **'전송 이력을 불러오지 못했어요. 이미 보낸 회원이 안 보냄으로 보일 수 있어요.'**
  String get reportsSendHistoryFailed;

  /// No description provided for @reportsStepReview.
  ///
  /// In ko, this message translates to:
  /// **'확인'**
  String get reportsStepReview;

  /// No description provided for @reportsStepWrite.
  ///
  /// In ko, this message translates to:
  /// **'작성'**
  String get reportsStepWrite;

  /// No description provided for @reportsStepSend.
  ///
  /// In ko, this message translates to:
  /// **'보내기'**
  String get reportsStepSend;

  /// No description provided for @reportsStepPrint.
  ///
  /// In ko, this message translates to:
  /// **'인쇄'**
  String get reportsStepPrint;

  /// No description provided for @reportsPrintNeedsPdf.
  ///
  /// In ko, this message translates to:
  /// **'미리보기 PDF가 준비되면 인쇄할 수 있어요'**
  String get reportsPrintNeedsPdf;

  /// No description provided for @reportsPrintFailed.
  ///
  /// In ko, this message translates to:
  /// **'인쇄 창을 열지 못했어요. 다시 시도해 주세요'**
  String get reportsPrintFailed;

  /// No description provided for @reportsStepperLabel.
  ///
  /// In ko, this message translates to:
  /// **'주간 리포트 작성 진행 단계'**
  String get reportsStepperLabel;

  /// No description provided for @reportsStepNext.
  ///
  /// In ko, this message translates to:
  /// **'다음'**
  String get reportsStepNext;

  /// No description provided for @reportsStepPrev.
  ///
  /// In ko, this message translates to:
  /// **'이전'**
  String get reportsStepPrev;

  /// No description provided for @reportsPreviewTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원이 받는 리포트'**
  String get reportsPreviewTitle;

  /// No description provided for @reportsPreviewRecipient.
  ///
  /// In ko, this message translates to:
  /// **'받는 사람'**
  String get reportsPreviewRecipient;

  /// No description provided for @reportsPreviewWeek.
  ///
  /// In ko, this message translates to:
  /// **'대상 주'**
  String get reportsPreviewWeek;

  /// No description provided for @reportsPreviewDelivery.
  ///
  /// In ko, this message translates to:
  /// **'{name}님에게 메시지로 PDF 파일이 전송돼요'**
  String reportsPreviewDelivery(String name);

  /// No description provided for @reportsPreviewEditHint.
  ///
  /// In ko, this message translates to:
  /// **'글을 고치려면 이전을 눌러 작성 단계로 돌아가세요'**
  String get reportsPreviewEditHint;

  /// No description provided for @reportsPreviewGenerating.
  ///
  /// In ko, this message translates to:
  /// **'미리보기를 만드는 중이에요'**
  String get reportsPreviewGenerating;

  /// No description provided for @reportsPreviewFailed.
  ///
  /// In ko, this message translates to:
  /// **'미리보기를 만들지 못했어요'**
  String get reportsPreviewFailed;

  /// No description provided for @reportsPreviewPage.
  ///
  /// In ko, this message translates to:
  /// **'{current} / {total}쪽'**
  String reportsPreviewPage(int current, int total);

  /// No description provided for @reportsPreviewPrevPage.
  ///
  /// In ko, this message translates to:
  /// **'이전 쪽'**
  String get reportsPreviewPrevPage;

  /// No description provided for @reportsPreviewNextPage.
  ///
  /// In ko, this message translates to:
  /// **'다음 쪽'**
  String get reportsPreviewNextPage;

  /// No description provided for @reportsPreviewZoomIn.
  ///
  /// In ko, this message translates to:
  /// **'확대'**
  String get reportsPreviewZoomIn;

  /// No description provided for @reportsPreviewZoomOut.
  ///
  /// In ko, this message translates to:
  /// **'축소'**
  String get reportsPreviewZoomOut;

  /// No description provided for @reportsGridPtSession.
  ///
  /// In ko, this message translates to:
  /// **'PT'**
  String get reportsGridPtSession;

  /// No description provided for @reportsGridPtPerWeek.
  ///
  /// In ko, this message translates to:
  /// **'주 {count}회'**
  String reportsGridPtPerWeek(int count);

  /// No description provided for @reportsGridPersonal.
  ///
  /// In ko, this message translates to:
  /// **'개인운동'**
  String get reportsGridPersonal;

  /// No description provided for @reportsGridPersonalUnit.
  ///
  /// In ko, this message translates to:
  /// **'수행 / 배정'**
  String get reportsGridPersonalUnit;

  /// No description provided for @reportsGridDoneOfAssigned.
  ///
  /// In ko, this message translates to:
  /// **'{done} / {total}회'**
  String reportsGridDoneOfAssigned(int done, int total);

  /// No description provided for @reportsGridMeals.
  ///
  /// In ko, this message translates to:
  /// **'식단 기록'**
  String get reportsGridMeals;

  /// No description provided for @reportsGridMealsUnit.
  ///
  /// In ko, this message translates to:
  /// **'기록 횟수'**
  String get reportsGridMealsUnit;

  /// No description provided for @reportsGridMealCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}회'**
  String reportsGridMealCount(int count);

  /// No description provided for @reportsGridCalories.
  ///
  /// In ko, this message translates to:
  /// **'섭취 칼로리'**
  String get reportsGridCalories;

  /// No description provided for @reportsGridCalorieTarget.
  ///
  /// In ko, this message translates to:
  /// **'목표 {value}'**
  String reportsGridCalorieTarget(String value);

  /// No description provided for @reportsMacroNone.
  ///
  /// In ko, this message translates to:
  /// **'아직 끼니 기록이 없어 탄단지를 볼 수 없어요'**
  String get reportsMacroNone;

  /// No description provided for @reportsMacroValueOfTarget.
  ///
  /// In ko, this message translates to:
  /// **'{name} {value} / {target}g'**
  String reportsMacroValueOfTarget(String name, int value, int target);

  /// Shortfall line under the report macro bars. {name} is metricCarbs, metricProtein or metricFat; in Korean all three end with a final consonant, so the copy uses the subject particle '이' only (no two-form '이(가)', #1177).
  ///
  /// In ko, this message translates to:
  /// **'{name}이 목표보다 많이 부족해요 — 피드백에서 짚어 보세요'**
  String reportsMacroShortfall(String name);

  /// No description provided for @reportsMemberFeedbackTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원 주간 피드백'**
  String get reportsMemberFeedbackTitle;

  /// No description provided for @reportsMemberFeedbackAttention.
  ///
  /// In ko, this message translates to:
  /// **'확인 필요'**
  String get reportsMemberFeedbackAttention;

  /// No description provided for @reportsMemberFeedbackNone.
  ///
  /// In ko, this message translates to:
  /// **'아직 받지 못했어요'**
  String get reportsMemberFeedbackNone;

  /// No description provided for @reportsMemberFeedbackNoneHint.
  ///
  /// In ko, this message translates to:
  /// **'회원이 주간 피드백을 보내면 여기에 표시돼요'**
  String get reportsMemberFeedbackNoneHint;

  /// No description provided for @reportsMemberFeedbackConditionLabel.
  ///
  /// In ko, this message translates to:
  /// **'컨디션'**
  String get reportsMemberFeedbackConditionLabel;

  /// No description provided for @reportsMemberFeedbackIntensityLabel.
  ///
  /// In ko, this message translates to:
  /// **'운동 강도'**
  String get reportsMemberFeedbackIntensityLabel;

  /// No description provided for @reportsMemberFeedbackPainLabel.
  ///
  /// In ko, this message translates to:
  /// **'통증'**
  String get reportsMemberFeedbackPainLabel;

  /// No description provided for @reportsMemberFeedbackPainNone.
  ///
  /// In ko, this message translates to:
  /// **'없음'**
  String get reportsMemberFeedbackPainNone;

  /// No description provided for @reportsMemberFeedbackUnanswered.
  ///
  /// In ko, this message translates to:
  /// **'미응답'**
  String get reportsMemberFeedbackUnanswered;

  /// Member feedback card value when the feedback request failed, kept apart from 'No answer' (#3246).
  ///
  /// In ko, this message translates to:
  /// **'불러오지 못했어요'**
  String get reportsMemberFeedbackLoadFailed;

  /// No description provided for @reportsMemberFeedbackLoadFailedHint.
  ///
  /// In ko, this message translates to:
  /// **'회원이 답했는지 확인하지 못했어요. 잠시 후 리포트를 다시 불러와 주세요'**
  String get reportsMemberFeedbackLoadFailedHint;

  /// No description provided for @reportsMemberFeedbackNoteLabel.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 피드백'**
  String get reportsMemberFeedbackNoteLabel;

  /// No description provided for @reportsMemberFeedbackNoteNone.
  ///
  /// In ko, this message translates to:
  /// **'한 줄 피드백 없음'**
  String get reportsMemberFeedbackNoteNone;

  /// No description provided for @reportsMemberFeedbackPainOn.
  ///
  /// In ko, this message translates to:
  /// **'{area} ({date})'**
  String reportsMemberFeedbackPainOn(String area, String date);

  /// No description provided for @reportsMemberFeedbackConditionGreat.
  ///
  /// In ko, this message translates to:
  /// **'아주 좋았어요'**
  String get reportsMemberFeedbackConditionGreat;

  /// No description provided for @reportsMemberFeedbackConditionGood.
  ///
  /// In ko, this message translates to:
  /// **'좋았어요'**
  String get reportsMemberFeedbackConditionGood;

  /// No description provided for @reportsMemberFeedbackConditionOk.
  ///
  /// In ko, this message translates to:
  /// **'보통이었어요'**
  String get reportsMemberFeedbackConditionOk;

  /// No description provided for @reportsMemberFeedbackConditionTired.
  ///
  /// In ko, this message translates to:
  /// **'지쳤어요'**
  String get reportsMemberFeedbackConditionTired;

  /// No description provided for @reportsMemberFeedbackConditionBad.
  ///
  /// In ko, this message translates to:
  /// **'많이 안 좋았어요'**
  String get reportsMemberFeedbackConditionBad;

  /// No description provided for @reportsMemberFeedbackIntensityTooEasy.
  ///
  /// In ko, this message translates to:
  /// **'너무 쉬웠어요'**
  String get reportsMemberFeedbackIntensityTooEasy;

  /// No description provided for @reportsMemberFeedbackIntensityRight.
  ///
  /// In ko, this message translates to:
  /// **'딱 맞았어요'**
  String get reportsMemberFeedbackIntensityRight;

  /// No description provided for @reportsMemberFeedbackIntensityHard.
  ///
  /// In ko, this message translates to:
  /// **'조금 힘들었어요'**
  String get reportsMemberFeedbackIntensityHard;

  /// No description provided for @reportsMemberFeedbackIntensityTooHard.
  ///
  /// In ko, this message translates to:
  /// **'너무 힘들었어요'**
  String get reportsMemberFeedbackIntensityTooHard;

  /// No description provided for @reportsTrendUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'이 주의 운동 기록을 불러오지 못했어요'**
  String get reportsTrendUnavailable;

  /// No description provided for @reportsTrendNoGoal.
  ///
  /// In ko, this message translates to:
  /// **'목표 없음'**
  String get reportsTrendNoGoal;

  /// No description provided for @reportsExerciseTrend.
  ///
  /// In ko, this message translates to:
  /// **'운동 추이'**
  String get reportsExerciseTrend;

  /// No description provided for @reportsWriteFromScratch.
  ///
  /// In ko, this message translates to:
  /// **'직접 작성하기'**
  String get reportsWriteFromScratch;

  /// No description provided for @reportsCardWeekTitle.
  ///
  /// In ko, this message translates to:
  /// **'이번 주'**
  String get reportsCardWeekTitle;

  /// No description provided for @reportsCardWeekSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'한 축에 겹쳐 보면 같이 무너진 날이 보여요'**
  String get reportsCardWeekSubtitle;

  /// No description provided for @reportsAiSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'AI가 수치에서 자동 작성'**
  String get reportsAiSubtitle;

  /// No description provided for @reportsMemberFeedbackMeta.
  ///
  /// In ko, this message translates to:
  /// **'주 1회 · {date} 제출'**
  String reportsMemberFeedbackMeta(String date);

  /// No description provided for @reportsTrendSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'유형별 · 최근 {weeks}주'**
  String reportsTrendSubtitle(int weeks);

  /// No description provided for @reportsTrendCenterLabel.
  ///
  /// In ko, this message translates to:
  /// **'목표의'**
  String get reportsTrendCenterLabel;

  /// No description provided for @reportsTrendWeeklyGoal.
  ///
  /// In ko, this message translates to:
  /// **'주간 목표 {goal}'**
  String reportsTrendWeeklyGoal(String goal);

  /// No description provided for @reportsTrendRunDown.
  ///
  /// In ko, this message translates to:
  /// **'{weeks}주 연속 감소'**
  String reportsTrendRunDown(int weeks);

  /// No description provided for @reportsTrendRunUp.
  ///
  /// In ko, this message translates to:
  /// **'{weeks}주 연속 상승'**
  String reportsTrendRunUp(int weeks);

  /// No description provided for @reportsTrendVsLastWeek.
  ///
  /// In ko, this message translates to:
  /// **'지난주 대비 {delta}%'**
  String reportsTrendVsLastWeek(String delta);

  /// No description provided for @reportsTrendFlat.
  ///
  /// In ko, this message translates to:
  /// **'지난주와 비슷'**
  String get reportsTrendFlat;

  /// No description provided for @reportsTrendNoHistory.
  ///
  /// In ko, this message translates to:
  /// **'견줄 지난주가 없어요'**
  String get reportsTrendNoHistory;

  /// No description provided for @reportsTrendRate.
  ///
  /// In ko, this message translates to:
  /// **'주간 달성률'**
  String get reportsTrendRate;

  /// No description provided for @reportsTrendAverage.
  ///
  /// In ko, this message translates to:
  /// **'{weeks}주 평균'**
  String reportsTrendAverage(int weeks);

  /// No description provided for @reportsTrendRateFalling.
  ///
  /// In ko, this message translates to:
  /// **'달성률 {weeks}주 연속 하락'**
  String reportsTrendRateFalling(int weeks);

  /// No description provided for @reportsTrendTracked.
  ///
  /// In ko, this message translates to:
  /// **'추적 운동 {count}개 — 자동 선별됨'**
  String reportsTrendTracked(int count);

  /// No description provided for @reportsTrendTrackedTimes.
  ///
  /// In ko, this message translates to:
  /// **'{count}회'**
  String reportsTrendTrackedTimes(int count);

  /// No description provided for @reportsCalorieThisWeekAvg.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 평균 {kcal}kcal'**
  String reportsCalorieThisWeekAvg(String kcal);

  /// No description provided for @reportsCalorieBaselineAvg.
  ///
  /// In ko, this message translates to:
  /// **'지난 {weeks}주 평균 {kcal}kcal'**
  String reportsCalorieBaselineAvg(int weeks, String kcal);

  /// No description provided for @reportsGridCalorieTargetDefault.
  ///
  /// In ko, this message translates to:
  /// **'기본 목표 {kcal}'**
  String reportsGridCalorieTargetDefault(String kcal);

  /// No description provided for @summaryBasisDefault.
  ///
  /// In ko, this message translates to:
  /// **'기본 목표'**
  String get summaryBasisDefault;

  /// No description provided for @summaryBasisPersonal.
  ///
  /// In ko, this message translates to:
  /// **'개인 목표'**
  String get summaryBasisPersonal;

  /// No description provided for @summaryDirOver.
  ///
  /// In ko, this message translates to:
  /// **'초과'**
  String get summaryDirOver;

  /// No description provided for @summaryDirUnder.
  ///
  /// In ko, this message translates to:
  /// **'부족'**
  String get summaryDirUnder;

  /// No description provided for @summaryCompletionLow.
  ///
  /// In ko, this message translates to:
  /// **'운동 완료율 평균 {pct}% · 기준 {threshold}% 미만'**
  String summaryCompletionLow(String pct, String threshold);

  /// No description provided for @summaryCompletionTopic.
  ///
  /// In ko, this message translates to:
  /// **'운동 완료율 {pct}%'**
  String summaryCompletionTopic(String pct);

  /// No description provided for @summaryCompletionAvg.
  ///
  /// In ko, this message translates to:
  /// **'운동 완료율 평균 {pct}%'**
  String summaryCompletionAvg(String pct);

  /// No description provided for @summarySkipped.
  ///
  /// In ko, this message translates to:
  /// **'건너뛴 운동: {names}'**
  String summarySkipped(String names);

  /// No description provided for @summarySkippedTopic.
  ///
  /// In ko, this message translates to:
  /// **'건너뛴 운동 {count}가지'**
  String summarySkippedTopic(String count);

  /// No description provided for @summarySodium.
  ///
  /// In ko, this message translates to:
  /// **'나트륨 평균 {avg}mg · {basis} {target}mg 초과 {days}일'**
  String summarySodium(String avg, String basis, String target, String days);

  /// No description provided for @summarySodiumOverTopic.
  ///
  /// In ko, this message translates to:
  /// **'나트륨 목표 초과 {days}일'**
  String summarySodiumOverTopic(String days);

  /// No description provided for @summarySodiumAvgTopic.
  ///
  /// In ko, this message translates to:
  /// **'나트륨 평균 {avg}mg'**
  String summarySodiumAvgTopic(String avg);

  /// No description provided for @summarySugar.
  ///
  /// In ko, this message translates to:
  /// **'당류 평균 {avg}g · {basis} {target}g 초과 {days}일'**
  String summarySugar(String avg, String basis, String target, String days);

  /// No description provided for @summarySugarOverTopic.
  ///
  /// In ko, this message translates to:
  /// **'당류 목표 초과 {days}일'**
  String summarySugarOverTopic(String days);

  /// No description provided for @summarySugarAvgTopic.
  ///
  /// In ko, this message translates to:
  /// **'당류 평균 {avg}g'**
  String summarySugarAvgTopic(String avg);

  /// No description provided for @summaryCalories.
  ///
  /// In ko, this message translates to:
  /// **'칼로리 평균 {avg}kcal · {basis} {target}kcal 대비 {direction} {pct}%'**
  String summaryCalories(
    String avg,
    String basis,
    String target,
    String direction,
    String pct,
  );

  /// No description provided for @summaryCaloriesTopic.
  ///
  /// In ko, this message translates to:
  /// **'칼로리 {direction}'**
  String summaryCaloriesTopic(String direction);

  /// No description provided for @summaryCaloriesAvg.
  ///
  /// In ko, this message translates to:
  /// **'칼로리 평균 {avg}kcal'**
  String summaryCaloriesAvg(String avg);

  /// No description provided for @summaryMacro.
  ///
  /// In ko, this message translates to:
  /// **'{label} 평균 {avg}g · 개인 목표 {target}g 대비 {direction} {pct}%'**
  String summaryMacro(
    String label,
    String avg,
    String target,
    String direction,
    String pct,
  );

  /// No description provided for @summaryMacroTopic.
  ///
  /// In ko, this message translates to:
  /// **'{label} {direction}'**
  String summaryMacroTopic(String label, String direction);

  /// No description provided for @summaryMorePoints.
  ///
  /// In ko, this message translates to:
  /// **'외 {count}건 — 리포트 본문에서 확인'**
  String summaryMorePoints(String count);

  /// No description provided for @summaryHeadlineNoData.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원은 그 주 기록이 없어 다음 주 시작을 함께 잡아 주세요.'**
  String summaryHeadlineNoData(String name);

  /// No description provided for @summaryHeadlineSteady.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원은 기록이 목표 범위 안에 있어 지금 강도를 유지해도 좋아요.'**
  String summaryHeadlineSteady(String name);

  /// No description provided for @summaryHeadlineRest.
  ///
  /// In ko, this message translates to:
  /// **' 그 밖에 {count}가지도 함께 보세요.'**
  String summaryHeadlineRest(String count);

  /// No description provided for @summaryHeadlineGoodCare.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원은 {kept} 잘 지켰고, 다음 주는 {top} 함께 챙기면 좋겠어요.{rest}'**
  String summaryHeadlineGoodCare(
    String name,
    String kept,
    String top,
    String rest,
  );

  /// No description provided for @summaryHeadlineNeedsAdjust.
  ///
  /// In ko, this message translates to:
  /// **'{name} 회원은 {top} 목표를 벗어나 다음 주 조정이 필요해요.{rest}'**
  String summaryHeadlineNeedsAdjust(String name, String top, String rest);

  /// No description provided for @reportsPdfFileSuffix.
  ///
  /// In ko, this message translates to:
  /// **'주간리포트'**
  String get reportsPdfFileSuffix;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'식단 분석'**
  String get clientDietAnalysisTitle;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'오늘 식단 기록이 아직 없어요.'**
  String get clientDietAnalysisTodayEmpty;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{slot, select, breakfast{아침} lunch{점심} dinner{저녁} lateNight{야식} other{간식}}에 먹은 {food}({foodValue}) 때문에 오늘 {nutrient, select, sodium{나트륨이} sugar{당류가} other{칼로리가}} {value}까지 올라 목표 {target}의 {ratio}배가 됐어요.'**
  String clientDietAnalysisTodayOver(
    String slot,
    String food,
    String foodValue,
    String nutrient,
    String value,
    String target,
    String ratio,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{slot, select, breakfast{아침} lunch{점심} dinner{저녁} lateNight{야식} other{간식}} 식사({foodValue}) 때문에 오늘 {nutrient, select, sodium{나트륨이} sugar{당류가} other{칼로리가}} {value}까지 올라 목표 {target}의 {ratio}배가 됐어요.'**
  String clientDietAnalysisTodayOverMeal(
    String slot,
    String foodValue,
    String nutrient,
    String value,
    String target,
    String ratio,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'단백질은 {value}으로 목표보다 {gap} 부족해요.'**
  String clientDietAnalysisTodayProteinShort(String value, String gap);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'단백질은 {value}으로 목표보다 {gap} 모자라고, 최근 4주 평균도 하루 {avg}이라 꾸준히 부족한 편이에요.'**
  String clientDietAnalysisTodayProteinChronic(
    String value,
    String gap,
    String avg,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{slot, select, breakfast{아침} lunch{점심} dinner{저녁} lateNight{야식} other{간식}} 기록이 아직 없어요.'**
  String clientDietAnalysisTodayMissing(String slot);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'오늘 {kcal}, 목표 안에서 고르게 드셨어요.'**
  String clientDietAnalysisTodayGood(String kcal);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'이번 주 식단 기록이 아직 없어요.'**
  String get clientDietAnalysisWeekEmpty;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 기록한 {logged}일 중 {days}일 아침을 걸렀어요.'**
  String clientDietAnalysisWeekSkipBreakfast(
    String scope,
    int logged,
    int days,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 기록한 {logged}일 중 {days}일 아침을 걸렀고, 그중 {snackDays}일은 간식으로 채웠어요.'**
  String clientDietAnalysisWeekSkipBreakfastSnack(
    String scope,
    int logged,
    int days,
    int snackDays,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 기록한 {logged}일 중 {days}일 {nutrient, select, sodium{나트륨이} sugar{당류가} other{칼로리가}} 목표를 넘었어요.'**
  String clientDietAnalysisWeekOver(
    String scope,
    int logged,
    int days,
    String nutrient,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{weekday, select, 0{월요일} 1{화요일} 2{수요일} 3{목요일} 4{금요일} 5{토요일} other{일요일}} {slot, select, breakfast{아침} lunch{점심} dinner{저녁} lateNight{야식} other{간식}}에 먹은 {food}({foodValue}) 영향이 가장 컸어요.'**
  String clientDietAnalysisWeekCause(
    String weekday,
    String slot,
    String food,
    String foodValue,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 기록한 {logged}일 중 {days}일 단백질이 목표의 80%에 못 미쳤어요.'**
  String clientDietAnalysisWeekProteinShort(String scope, int logged, int days);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{scope, select, last{지난주} other{이번 주}} 기록한 {days}일 모두 목표 안에서 드셨어요.'**
  String clientDietAnalysisWeekGood(String scope, int days);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석` — 이번 주 근거·비교 문장.
  ///
  /// In ko, this message translates to:
  /// **'아침 대신 먹은 것은 {food} {count}회가 가장 많았어요.'**
  String clientDietAnalysisWeekBreakfastSnackFood(String food, int count);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석` — 이번 주 근거·비교 문장.
  ///
  /// In ko, this message translates to:
  /// **'모자란 날은 하루 평균 {value} 정도였어요.'**
  String clientDietAnalysisWeekProteinAvg(String value);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석` — 이번 주 근거·비교 문장.
  ///
  /// In ko, this message translates to:
  /// **'하루 평균 {kcal}, 단백질 {protein}을 드셨어요.'**
  String clientDietAnalysisWeekGoodAvg(String kcal, String protein);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석` — 이번 주 근거·비교 문장.
  ///
  /// In ko, this message translates to:
  /// **'지난주({prevLogged}일 중 {prevDays}일){way, select, more{보다 늘었어요} less{보다 줄었어요} other{와 비슷해요}}.'**
  String clientDietAnalysisWeekVsLast(int prevLogged, int prevDays, String way);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 기록이 {days}일이라, 7일이 넘으면 흐름을 짚어 드릴게요.'**
  String clientDietAnalysisAllFew(int days);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 동안 {slot, select, breakfast{아침} lunch{점심} dinner{저녁} lateNight{야식} other{간식}} 나트륨이 {days}회 목표의 절반을 넘었어요.'**
  String clientDietAnalysisAllSlotSodium(String slot, int days);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 섭취 칼로리 중 탄수화물이 {pct}%로 높은 편이에요.'**
  String clientDietAnalysisAllCarbHeavy(int pct);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 섭취 칼로리 중 단백질이 {pct}%로 낮은 편이에요.'**
  String clientDietAnalysisAllProteinLight(int pct);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'단백질 목표를 채운 날이 앞선 2주 {before}일에서 최근 2주 {after}일로 늘었어요.'**
  String clientDietAnalysisAllProteinTrendUp(int before, int after);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'단백질 목표를 채운 날이 앞선 2주 {before}일에서 최근 2주 {after}일로 줄었어요.'**
  String clientDietAnalysisAllProteinTrendDown(int before, int after);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 동안 {slot, select, breakfast{아침} lunch{점심} dinner{저녁} lateNight{야식} other{간식}} 메뉴로 {food} {count}회가 가장 많았어요.'**
  String clientDietAnalysisAllFrequent(String slot, String food, int count);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 음식 기록에서 {food1}·{food2} 비중이 높아요.'**
  String clientDietAnalysisAllRepeated(String food1, String food2);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'최근 4주 동안 {days}일 기록했고, 흐름이 고른 편이에요.'**
  String clientDietAnalysisAllGood(int days);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{food1} {count1}회가 대부분이에요.'**
  String clientDietAnalysisFoodsOne(String food1, int count1);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{food1} {count1}회, {food2} {count2}회가 대부분이에요.'**
  String clientDietAnalysisFoodsTwo(
    String food1,
    int count1,
    String food2,
    int count2,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{slot, select, breakfast{아침으로} lunch{점심으로} dinner{저녁으로} lateNight{야식으로} other{간식으로}} 이 메뉴를 회원에게 추천할까요?'**
  String clientDietRecQuestion(String slot);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'다음 식사로 이 메뉴를 회원에게 추천할까요?'**
  String get clientDietRecQuestionNext;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'AI 추천 {index} / {total}'**
  String clientDietRecCounter(int index, int total);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'아니요'**
  String get clientDietRecNo;

  /// AI 식단 추천 카운터 왼쪽 꺾쇠 툴팁 — 같은 묶음 안 앞 후보로.
  ///
  /// In ko, this message translates to:
  /// **'이전 추천'**
  String get clientDietRecPrev;

  /// AI 식단 추천 카운터 오른쪽 꺾쇠 툴팁 — 같은 묶음 안 다음 후보로(거절 아님).
  ///
  /// In ko, this message translates to:
  /// **'다음 추천'**
  String get clientDietRecForward;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'예, 추천할게요'**
  String get clientDietRecYes;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'AI 추천 메뉴 {count}개를 모두 넘겼어요.'**
  String clientDietRecExhausted(int count);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'처음부터 다시 보기'**
  String get clientDietRecRestart;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'다른 메뉴 보기'**
  String get clientDietRecMore;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{date}에 이 메뉴를 추천했어요. 회원 앱 홈에 트레이너 추천으로 떠 있어요.'**
  String clientDietRecActive(String date);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'바꾸기'**
  String get clientDietRecChange;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'회원이 {date} {slot, select, breakfast{아침} lunch{점심} dinner{저녁} lateNight{야식} other{간식}}에 추천한 메뉴({name})를 먹었어요.'**
  String clientDietRecResolved(String name, String date, String slot);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'회원이 {date}에 추천한 메뉴({name})를 먹었어요.'**
  String clientDietRecResolvedNoSlot(String name, String date);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'다음 추천 보기'**
  String get clientDietRecNext;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'추천을 저장하지 못했어요. 다시 시도해 주세요.'**
  String get clientDietRecConfirmFailed;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{kcal}kcal · 단백질 {protein}g · 나트륨 {sodium}mg'**
  String clientDietRecNutrition(String kcal, String protein, String sodium);

  /// 트레이너웹 AI 식단 추천의 끼니 배지 (#2379).
  ///
  /// In ko, this message translates to:
  /// **'{slot, select, breakfast{아침} lunch{점심} dinner{저녁} lateNight{야식} other{간식}}'**
  String clientDietRecSlot(String slot);

  /// No description provided for @authForgotPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 찾기'**
  String get authForgotPassword;

  /// Text button next to 'Forgot password?' on sign-in that opens the find-email screen.
  ///
  /// In ko, this message translates to:
  /// **'아이디 찾기'**
  String get authFindEmail;

  /// No description provided for @findEmailTitle.
  ///
  /// In ko, this message translates to:
  /// **'아이디 찾기'**
  String get findEmailTitle;

  /// No description provided for @findEmailSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'가입할 때 입력한 이름과 휴대폰 번호로 가입 이메일을 찾아요.'**
  String get findEmailSubtitle;

  /// No description provided for @findEmailAction.
  ///
  /// In ko, this message translates to:
  /// **'아이디 찾기'**
  String get findEmailAction;

  /// Toast shown when the find-email button is pressed while the lookup is not available yet.
  ///
  /// In ko, this message translates to:
  /// **'아이디 찾기는 준비 중이에요.'**
  String get findEmailComingSoon;

  /// Placeholder of the phone field on trainer sign-up and find-email.
  ///
  /// In ko, this message translates to:
  /// **'010-0000-0000'**
  String get signUpPhoneHint;

  /// No description provided for @signUpPhoneHelper.
  ///
  /// In ko, this message translates to:
  /// **'가입한 이메일을 잊었을 때 찾는 데 쓰는 연락처예요'**
  String get signUpPhoneHelper;

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

  /// No description provided for @passwordResetTooMany.
  ///
  /// In ko, this message translates to:
  /// **'시도가 너무 많아요. 잠시 후 다시 시도해 주세요.'**
  String get passwordResetTooMany;

  /// No description provided for @passwordResetTemporaryFailure.
  ///
  /// In ko, this message translates to:
  /// **'요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get passwordResetTemporaryFailure;

  /// No description provided for @signUpCodeSend.
  ///
  /// In ko, this message translates to:
  /// **'인증 코드 받기'**
  String get signUpCodeSend;

  /// No description provided for @signUpCodeLabel.
  ///
  /// In ko, this message translates to:
  /// **'인증 코드'**
  String get signUpCodeLabel;

  /// Same text whether or not the email already has an account.
  ///
  /// In ko, this message translates to:
  /// **'메일로 받은 6자리 코드를 입력해 주세요. 이미 가입된 이메일이면 코드 대신 안내 메일이 가요.'**
  String get signUpCodeSentNotice;

  /// Remaining validity of the sign-up email code; time looks like 9:41.
  ///
  /// In ko, this message translates to:
  /// **'남은 시간 {time}'**
  String signUpCodeRemaining(String time);

  /// No description provided for @signUpCodeExpired.
  ///
  /// In ko, this message translates to:
  /// **'코드가 만료됐어요. 다시 받아 주세요.'**
  String get signUpCodeExpired;

  /// No description provided for @signUpCodeResend.
  ///
  /// In ko, this message translates to:
  /// **'다시 받기'**
  String get signUpCodeResend;

  /// No description provided for @signUpCodeResendIn.
  ///
  /// In ko, this message translates to:
  /// **'{seconds}초 뒤 다시 받기'**
  String signUpCodeResendIn(int seconds);

  /// No description provided for @signUpCodeDemoNote.
  ///
  /// In ko, this message translates to:
  /// **'데모 모드에서는 메일이 가지 않아요. 인증 코드로 {code} 를 입력해 주세요.'**
  String signUpCodeDemoNote(String code);

  /// No description provided for @signUpCodeInvalid.
  ///
  /// In ko, this message translates to:
  /// **'인증 코드가 맞지 않거나 만료됐어요. 코드를 다시 받아 주세요.'**
  String get signUpCodeInvalid;

  /// No description provided for @signUpCodeRequired.
  ///
  /// In ko, this message translates to:
  /// **'이메일 인증 코드를 입력해 주세요.'**
  String get signUpCodeRequired;

  /// No description provided for @signUpCodeTooMany.
  ///
  /// In ko, this message translates to:
  /// **'요청이 너무 많아요. 잠시 후 다시 시도해 주세요.'**
  String get signUpCodeTooMany;

  /// No description provided for @signUpCodeUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'지금은 인증 메일을 보낼 수 없어요. 잠시 후 다시 시도해 주세요.'**
  String get signUpCodeUnavailable;

  /// No description provided for @signUpCodeRequestFailed.
  ///
  /// In ko, this message translates to:
  /// **'인증 코드를 보내지 못했어요. 잠시 후 다시 시도해 주세요.'**
  String get signUpCodeRequestFailed;

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

  /// Shown in error toasts and error states when a request failed because of a network error or timeout, instead of the HTTP library's own English message.
  ///
  /// In ko, this message translates to:
  /// **'연결이 불안정합니다. 네트워크를 확인하고 다시 시도해 주세요.'**
  String get errorNetworkUnstable;

  /// Shown in error toasts and error states when the server answered with a 5xx status and gave no reason of its own.
  ///
  /// In ko, this message translates to:
  /// **'서버에 일시적인 문제가 있어요. 잠시 후 다시 시도해 주세요.'**
  String get errorServerTemporary;

  /// Button on the gym card and title of the screen where a trainer picks a different gym to be affiliated with.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 변경'**
  String get myGymChange;

  /// Button on the gym card and title of the screen where an affiliated trainer edits the gym hours, phone and tags (#2700).
  ///
  /// In ko, this message translates to:
  /// **'영업시간·연락처 수정'**
  String get myGymInfoEdit;

  /// No description provided for @myGymInfoSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'회원 앱 헬스장 목록과 상세에 그대로 보여요. 같은 헬스장 트레이너 누구나 고칠 수 있고, 마지막에 저장한 내용이 남아요.'**
  String get myGymInfoSubtitle;

  /// No description provided for @myGymInfoCardTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원에게 보이는 헬스장 정보'**
  String get myGymInfoCardTitle;

  /// No description provided for @myGymWeekdayHours.
  ///
  /// In ko, this message translates to:
  /// **'평일 영업시간'**
  String get myGymWeekdayHours;

  /// No description provided for @myGymWeekendHours.
  ///
  /// In ko, this message translates to:
  /// **'주말 영업시간'**
  String get myGymWeekendHours;

  /// No description provided for @myGymHoursHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 06:00 - 23:00'**
  String get myGymHoursHint;

  /// No description provided for @myGymPhone.
  ///
  /// In ko, this message translates to:
  /// **'대표 전화'**
  String get myGymPhone;

  /// No description provided for @myGymPhoneHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 02-123-4567'**
  String get myGymPhoneHint;

  /// No description provided for @myGymTags.
  ///
  /// In ko, this message translates to:
  /// **'태그'**
  String get myGymTags;

  /// No description provided for @myGymAddTag.
  ///
  /// In ko, this message translates to:
  /// **'태그 추가...'**
  String get myGymAddTag;

  /// No description provided for @myGymTagsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 태그가 없어요.'**
  String get myGymTagsEmpty;

  /// No description provided for @myGymInfoLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 정보를 불러오지 못했어요.'**
  String get myGymInfoLoadFailed;

  /// No description provided for @myGymInfoSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'헬스장 정보를 저장하지 못했어요.'**
  String get myGymInfoSaveFailed;

  /// No description provided for @a11yRemoveGymTag.
  ///
  /// In ko, this message translates to:
  /// **'태그 삭제'**
  String get a11yRemoveGymTag;

  /// No description provided for @myGymTagsHint.
  ///
  /// In ko, this message translates to:
  /// **'회원 앱 헬스장 카드에 칩으로 보여요. 최대 {max}개, 한 개에 {length}자까지 적을 수 있어요.'**
  String myGymTagsHint(int max, int length);

  /// No description provided for @myGymTagsFull.
  ///
  /// In ko, this message translates to:
  /// **'태그는 {max}개까지 넣을 수 있어요'**
  String myGymTagsFull(int max);

  /// No description provided for @myGymTagTooLong.
  ///
  /// In ko, this message translates to:
  /// **'태그는 {length}자까지 적을 수 있어요'**
  String myGymTagTooLong(int length);

  /// No description provided for @myGymHoursWeekday.
  ///
  /// In ko, this message translates to:
  /// **'평일 {hours}'**
  String myGymHoursWeekday(String hours);

  /// No description provided for @myGymHoursWeekend.
  ///
  /// In ko, this message translates to:
  /// **'주말 {hours}'**
  String myGymHoursWeekend(String hours);
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
