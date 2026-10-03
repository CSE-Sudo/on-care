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

  /// Trainer app title shown in the OS task switcher and browser tab.
  ///
  /// In en, this message translates to:
  /// **'On-Care Trainer'**
  String get appTitle;

  /// Display label for a scheduled session. The stored value stays Korean — see ScheduleStatus.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get scheduleStatusUpcoming;

  /// Display label for a completed session.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get scheduleStatusDone;

  /// No description provided for @scheduleStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get scheduleStatusCancelled;

  /// No description provided for @scheduleStatusNoShow.
  ///
  /// In en, this message translates to:
  /// **'No-show'**
  String get scheduleStatusNoShow;

  /// No description provided for @schedCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get schedCancel;

  /// No description provided for @schedNoShow.
  ///
  /// In en, this message translates to:
  /// **'Mark no-show'**
  String get schedNoShow;

  /// No description provided for @schedCancelTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this PT?'**
  String get schedCancelTitle;

  /// No description provided for @schedCancelConfirm.
  ///
  /// In en, this message translates to:
  /// **'The {time} session with {name} will be recorded as cancelled. The entry stays.'**
  String schedCancelConfirm(String time, String name);

  /// No description provided for @schedCancelSource.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get schedCancelSource;

  /// No description provided for @schedCancelByMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get schedCancelByMember;

  /// No description provided for @schedCancelByTrainer.
  ///
  /// In en, this message translates to:
  /// **'Trainer'**
  String get schedCancelByTrainer;

  /// No description provided for @schedCancelByOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get schedCancelByOther;

  /// No description provided for @schedCancelReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional, only you see it)'**
  String get schedCancelReasonHint;

  /// No description provided for @schedCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t cancel the session. Please try again.'**
  String get schedCancelFailed;

  /// No description provided for @schedNoShowTitle.
  ///
  /// In en, this message translates to:
  /// **'Record as a no-show?'**
  String get schedNoShowTitle;

  /// No description provided for @schedNoShowConfirm.
  ///
  /// In en, this message translates to:
  /// **'The {time} session with {name} will be recorded as a no-show.'**
  String schedNoShowConfirm(String time, String name);

  /// No description provided for @schedNoShowFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record the no-show. Please try again.'**
  String get schedNoShowFailed;

  /// No description provided for @schedCancelledBy.
  ///
  /// In en, this message translates to:
  /// **'{source} · {date}'**
  String schedCancelledBy(String source, String date);

  /// No description provided for @schedDeleteMeansRemove.
  ///
  /// In en, this message translates to:
  /// **'Deleting erases the record. Use cancel or no-show for a PT that didn\'t happen.'**
  String get schedDeleteMeansRemove;

  /// No description provided for @schedDeleteMeansRemoveFinished.
  ///
  /// In en, this message translates to:
  /// **'Deleting erases the record. This session is already complete and can\'t be undone.'**
  String get schedDeleteMeansRemoveFinished;

  /// Display label for an empty slot in the trainer's day.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get scheduleStatusGap;

  /// Display label for a personal training session.
  ///
  /// In en, this message translates to:
  /// **'1:1 PT'**
  String get sessionTypePersonalTraining;

  /// Display label for a consultation session.
  ///
  /// In en, this message translates to:
  /// **'Consultation'**
  String get sessionTypeConsultation;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navClients.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get navClients;

  /// No description provided for @navSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get navSchedule;

  /// No description provided for @navCoaching.
  ///
  /// In en, this message translates to:
  /// **'Programs'**
  String get navCoaching;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navConsultations.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get navConsultations;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get actionSaved;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get actionChange;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @actionSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get actionSend;

  /// No description provided for @actionReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get actionReset;

  /// Heading of the 404 page shown for a URL that matches no screen.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get notFoundTitle;

  /// No description provided for @notFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'The link may be broken, or the page may no longer exist. Please check the address and try again.'**
  String get notFoundMessage;

  /// Primary button on the 404 page for a signed-in trainer.
  ///
  /// In en, this message translates to:
  /// **'Go to dashboard'**
  String get notFoundGoDashboard;

  /// Primary button on the 404 page when no one is signed in.
  ///
  /// In en, this message translates to:
  /// **'Go to sign in'**
  String get notFoundGoSignIn;

  /// Heading of the startup screen shown instead of the app when a release build was made with development or demo settings.
  ///
  /// In en, this message translates to:
  /// **'This build is misconfigured'**
  String get misconfiguredBuildTitle;

  /// No description provided for @misconfiguredBuildMessage.
  ///
  /// In en, this message translates to:
  /// **'This build was made with settings that can\'t be used for real users, so the app didn\'t open. Please share the details below with whoever released it.'**
  String get misconfiguredBuildMessage;

  /// No description provided for @misconfiguredBuildDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Build settings to fix'**
  String get misconfiguredBuildDetailsTitle;

  /// No description provided for @misconfiguredBuildDevEnvironment.
  ///
  /// In en, this message translates to:
  /// **'ENV is not prod or staging'**
  String get misconfiguredBuildDevEnvironment;

  /// No description provided for @misconfiguredBuildMockWithoutDemo.
  ///
  /// In en, this message translates to:
  /// **'It uses demo data without the demo build flag (USE_MOCK_API, DEMO_BUILD)'**
  String get misconfiguredBuildMockWithoutDemo;

  /// No description provided for @misconfiguredBuildPlaceholderApiUrl.
  ///
  /// In en, this message translates to:
  /// **'The API address is an example or local address (API_BASE_URL)'**
  String get misconfiguredBuildPlaceholderApiUrl;

  /// No description provided for @misconfiguredBuildInsecureApiUrl.
  ///
  /// In en, this message translates to:
  /// **'The API address does not start with https:// (API_BASE_URL)'**
  String get misconfiguredBuildInsecureApiUrl;

  /// Second word of the sidebar wordmark, rendered in the navy primary next to 'On-Care'.
  ///
  /// In en, this message translates to:
  /// **'Trainer'**
  String get appWordmarkTrainer;

  /// Single-character avatar shown when the trainer has no name yet. Keep it one character.
  ///
  /// In en, this message translates to:
  /// **'T'**
  String get appAvatarFallback;

  /// Tooltip on the collapsed sidebar's profile avatar.
  ///
  /// In en, this message translates to:
  /// **'{name} · My page'**
  String sidebarMyTooltip(String name);

  /// No description provided for @authTagline.
  ///
  /// In en, this message translates to:
  /// **'See your members\' meals and workouts in one place — and coach them'**
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

  /// No description provided for @authSignUpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create an On-Care account and start managing members'**
  String get authSignUpSubtitle;

  /// No description provided for @authName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get authName;

  /// No description provided for @signUpPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Password (8+ characters, letters and numbers)'**
  String get signUpPasswordHint;

  /// No description provided for @authPasswordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get authPasswordConfirm;

  /// No description provided for @authSignUpAndStart.
  ///
  /// In en, this message translates to:
  /// **'Sign up and start'**
  String get authSignUpAndStart;

  /// No description provided for @consentAll.
  ///
  /// In en, this message translates to:
  /// **'Agree to all'**
  String get consentAll;

  /// No description provided for @consentRequiredTag.
  ///
  /// In en, this message translates to:
  /// **'[Required]'**
  String get consentRequiredTag;

  /// No description provided for @consentOptionalTag.
  ///
  /// In en, this message translates to:
  /// **'[Optional]'**
  String get consentOptionalTag;

  /// No description provided for @consentView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get consentView;

  /// No description provided for @consentTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get consentTerms;

  /// No description provided for @consentPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Collection and use of personal information'**
  String get consentPrivacy;

  /// No description provided for @consentAge14.
  ///
  /// In en, this message translates to:
  /// **'I am 14 years of age or older'**
  String get consentAge14;

  /// No description provided for @consentAge14Detail.
  ///
  /// In en, this message translates to:
  /// **'You must be 14 or older to sign up.'**
  String get consentAge14Detail;

  /// No description provided for @consentRequiredHint.
  ///
  /// In en, this message translates to:
  /// **'Agree to all required items to continue.'**
  String get consentRequiredHint;

  /// No description provided for @consentPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Agreements'**
  String get consentPageTitle;

  /// No description provided for @consentPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Please review and agree to the items below to keep using On-Care.'**
  String get consentPageSubtitle;

  /// No description provided for @consentPageAction.
  ///
  /// In en, this message translates to:
  /// **'Agree and continue'**
  String get consentPageAction;

  /// No description provided for @consentPageFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your agreement. Please try again in a moment.'**
  String get consentPageFailed;

  /// No description provided for @authHasAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get authHasAccount;

  /// No description provided for @authErrEmptyCredentials.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and password'**
  String get authErrEmptyCredentials;

  /// No description provided for @authSocialSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Social sign-in failed. Please try again in a moment.'**
  String get authSocialSignInFailed;

  /// No description provided for @authSocialComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Social sign-in is coming soon. Please sign in with your email.'**
  String get authSocialComingSoon;

  /// No description provided for @authErrSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Please try again in a moment.'**
  String get authErrSignInFailed;

  /// No description provided for @authSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get authSessionExpired;

  /// Red text under the name field on sign-up when it is empty or whitespace only (#1784).
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get authErrNameEmpty;

  /// Shared name-length message (#1887). Trainer sign-up sends a name too; the limit matches the users.name column.
  ///
  /// In en, this message translates to:
  /// **'Names can be up to 100 characters'**
  String get authErrNameTooLong;

  /// Red text under the email field on sign-in/sign-up when it is empty (#1784).
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get authErrEmailEmpty;

  /// No description provided for @authErrEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get authErrEmailInvalid;

  /// Red text under the email field when the address is longer than the server limit (#2908). The limit matches the users.email column and EMAIL_MAX_LENGTH in contact_format.py.
  ///
  /// In en, this message translates to:
  /// **'Email addresses can be up to 255 characters'**
  String get authErrEmailTooLong;

  /// No description provided for @authErrPasswordEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get authErrPasswordEmpty;

  /// No description provided for @authErrPasswordWeak.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters, including letters and numbers'**
  String get authErrPasswordWeak;

  /// Password upper-limit message (#1555). Matches the server rule in password_policy.py: 64 characters and 72 UTF-8 bytes (bcrypt), so Korean letters and emoji use up the limit faster.
  ///
  /// In en, this message translates to:
  /// **'Passwords can be up to 64 characters, or fewer if they include Korean or emoji'**
  String get authErrPasswordTooLong;

  /// Shared phone-format message (#1784). Trainer sign-up has no phone field today; kept so the shared AppInputError mapping stays exhaustive.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number as 010-0000-0000'**
  String get authErrPhoneInvalid;

  /// Shared birth-date message (#1887). The trainer app has no birth-date field today; kept so the shared AppInputError mapping stays exhaustive.
  ///
  /// In en, this message translates to:
  /// **'Enter the date of birth as 1996-03-21'**
  String get authErrBirthDateInvalid;

  /// No description provided for @authErrPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match'**
  String get authErrPasswordMismatch;

  /// No description provided for @authErrSignUpFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-up failed. Please try again in a moment.'**
  String get authErrSignUpFailed;

  /// No description provided for @dashTitle.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashTitle;

  /// No description provided for @dashActivityRecommendRoutine.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting the program setup.'**
  String get dashActivityRecommendRoutine;

  /// No description provided for @dashActivityRecommendChat.
  ///
  /// In en, this message translates to:
  /// **'Try checking in over Messages.'**
  String get dashActivityRecommendChat;

  /// No description provided for @dashActivityRecommendDiet.
  ///
  /// In en, this message translates to:
  /// **'Try leaving feedback in Diet.'**
  String get dashActivityRecommendDiet;

  /// No description provided for @dashActivityTabProgram.
  ///
  /// In en, this message translates to:
  /// **'Program'**
  String get dashActivityTabProgram;

  /// No description provided for @dashActivityTabChat.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get dashActivityTabChat;

  /// No description provided for @dashActivityTabClient.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get dashActivityTabClient;

  /// No description provided for @dashLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the dashboard'**
  String get dashLoadFailed;

  /// Unit after a booking count. Korean uses the counter 건; English omits it because the tile label already says what is being counted. Intentionally empty.
  ///
  /// In en, this message translates to:
  /// **''**
  String get dashUnitCount;

  /// Unit after a person count. Korean uses the counter 명; English omits it. Intentionally empty.
  ///
  /// In en, this message translates to:
  /// **''**
  String get dashUnitPeople;

  /// No description provided for @dashMyClients.
  ///
  /// In en, this message translates to:
  /// **'My members'**
  String get dashMyClients;

  /// No description provided for @dashDormantClients.
  ///
  /// In en, this message translates to:
  /// **'{count} dormant'**
  String dashDormantClients(int count);

  /// No description provided for @dashAllActive.
  ///
  /// In en, this message translates to:
  /// **'All active'**
  String get dashAllActive;

  /// No description provided for @dashNeedsReply.
  ///
  /// In en, this message translates to:
  /// **'Awaiting reply'**
  String get dashNeedsReply;

  /// No description provided for @dashWaitingClients.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting'**
  String dashWaitingClients(int count);

  /// No description provided for @dashAllReplied.
  ///
  /// In en, this message translates to:
  /// **'All replied'**
  String get dashAllReplied;

  /// No description provided for @dashAttentionClients.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get dashAttentionClients;

  /// No description provided for @dashNoIssues.
  ///
  /// In en, this message translates to:
  /// **'No issues'**
  String get dashNoIssues;

  /// No description provided for @dashCheckPtSignals.
  ///
  /// In en, this message translates to:
  /// **'Check PT signals'**
  String get dashCheckPtSignals;

  /// No description provided for @dashMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get dashMessages;

  /// No description provided for @dashChurnRisk.
  ///
  /// In en, this message translates to:
  /// **'Churn risk'**
  String get dashChurnRisk;

  /// No description provided for @dashChurnRiskNone.
  ///
  /// In en, this message translates to:
  /// **'No churn risk'**
  String get dashChurnRiskNone;

  /// No description provided for @dashChurnRiskCheck.
  ///
  /// In en, this message translates to:
  /// **'Review churn signals'**
  String get dashChurnRiskCheck;

  /// No description provided for @dashChurnRiskTitle.
  ///
  /// In en, this message translates to:
  /// **'Members at churn risk'**
  String get dashChurnRiskTitle;

  /// No description provided for @dashChurnRiskEmpty.
  ///
  /// In en, this message translates to:
  /// **'No members are at churn risk right now.'**
  String get dashChurnRiskEmpty;

  /// No description provided for @dashChurnRiskLoading.
  ///
  /// In en, this message translates to:
  /// **'Checking recent workouts'**
  String get dashChurnRiskLoading;

  /// No description provided for @dashChurnRiskUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable · Tap to retry'**
  String get dashChurnRiskUnavailable;

  /// No description provided for @dashActivityFeedbackLoading.
  ///
  /// In en, this message translates to:
  /// **'Checking recent workouts.'**
  String get dashActivityFeedbackLoading;

  /// No description provided for @dashActivityFeedbackUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load recent workouts, so activity feedback is unavailable. Tap the churn risk card to retry.'**
  String get dashActivityFeedbackUnavailable;

  /// No description provided for @dashActivityDifficultyTitle.
  ///
  /// In en, this message translates to:
  /// **'Behind exercise goal / routine skipped'**
  String get dashActivityDifficultyTitle;

  /// No description provided for @dashActivityDifficultyDesc.
  ///
  /// In en, this message translates to:
  /// **'{names} are behind this week\'s exercise goal or skipped an assigned routine. Lower the difficulty before the next PT and check recent feedback.'**
  String dashActivityDifficultyDesc(String names);

  /// No description provided for @dashActivityInactiveTitle.
  ///
  /// In en, this message translates to:
  /// **'No logs'**
  String get dashActivityInactiveTitle;

  /// No description provided for @dashActivityInactiveDesc.
  ///
  /// In en, this message translates to:
  /// **'{names} haven\'t logged meals or workouts for a few days. Reach out before it turns into churn.'**
  String dashActivityInactiveDesc(String names);

  /// No description provided for @dashActivityDietFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Diet feedback pending'**
  String get dashActivityDietFeedbackTitle;

  /// No description provided for @dashActivityDietFeedbackDesc.
  ///
  /// In en, this message translates to:
  /// **'{names} are off their calorie goal or low on protein but haven\'t gotten trainer feedback in 7 days. Leave diet feedback so they know it was seen.'**
  String dashActivityDietFeedbackDesc(String names);

  /// No description provided for @dashActivityMoreClients.
  ///
  /// In en, this message translates to:
  /// **'{shown} and {count} more'**
  String dashActivityMoreClients(String shown, int count);

  /// No description provided for @dashAiSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity feedback'**
  String get dashAiSummaryTitle;

  /// No description provided for @dashAiNoClients.
  ///
  /// In en, this message translates to:
  /// **'No members yet. Once you add one, I\'ll gather their diet and workout data and point out what to coach.'**
  String get dashAiNoClients;

  /// No description provided for @dashTodaySchedule.
  ///
  /// In en, this message translates to:
  /// **'Today\'s schedule'**
  String get dashTodaySchedule;

  /// No description provided for @dashSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get dashSeeAll;

  /// No description provided for @dashScheduleLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the schedule'**
  String get dashScheduleLoadFailed;

  /// No description provided for @dashNoScheduleToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled today'**
  String get dashNoScheduleToday;

  /// No description provided for @dashScheduleNowLabel.
  ///
  /// In en, this message translates to:
  /// **'Now {time}'**
  String dashScheduleNowLabel(String time);

  /// No description provided for @dashScheduleNextSession.
  ///
  /// In en, this message translates to:
  /// **'Next: {time} · {name}'**
  String dashScheduleNextSession(String time, String name);

  /// No description provided for @dashScheduleMinutesLeft.
  ///
  /// In en, this message translates to:
  /// **'in {minutes} min'**
  String dashScheduleMinutesLeft(int minutes);

  /// Dashboard banner when today's session has started but not yet ended (#2865).
  ///
  /// In en, this message translates to:
  /// **'In progress: {time} · {name}'**
  String dashScheduleInProgress(String time, String name);

  /// Minutes until the in-progress session ends (#2865).
  ///
  /// In en, this message translates to:
  /// **'{minutes} min left'**
  String dashScheduleMinutesToEnd(int minutes);

  /// No description provided for @dashPreparePt.
  ///
  /// In en, this message translates to:
  /// **'Prepare PT'**
  String get dashPreparePt;

  /// No description provided for @dashLeaveMemo.
  ///
  /// In en, this message translates to:
  /// **'Leave a memo'**
  String get dashLeaveMemo;

  /// No description provided for @dashLeaveFeedback.
  ///
  /// In en, this message translates to:
  /// **'Leave feedback'**
  String get dashLeaveFeedback;

  /// No description provided for @dashSessionSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get dashSessionSent;

  /// No description provided for @dashSessionPrepared.
  ///
  /// In en, this message translates to:
  /// **'Prepared'**
  String get dashSessionPrepared;

  /// No description provided for @dashSessionNoteWritten.
  ///
  /// In en, this message translates to:
  /// **'Written'**
  String get dashSessionNoteWritten;

  /// No description provided for @dashSessionSentNo.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get dashSessionSentNo;

  /// No description provided for @dashSessionPreparedNo.
  ///
  /// In en, this message translates to:
  /// **'Not prepared'**
  String get dashSessionPreparedNo;

  /// No description provided for @dashSessionNoteNotWritten.
  ///
  /// In en, this message translates to:
  /// **'No memo'**
  String get dashSessionNoteNotWritten;

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

  /// No description provided for @clientsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load member data'**
  String get clientsLoadFailed;

  /// No description provided for @clientsNew.
  ///
  /// In en, this message translates to:
  /// **'Register new member'**
  String get clientsNew;

  /// No description provided for @clientsTitle.
  ///
  /// In en, this message translates to:
  /// **'Member management'**
  String get clientsTitle;

  /// No description provided for @clientsManagementAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get clientsManagementAttention;

  /// No description provided for @clientsFiltersClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clientsFiltersClearAll;

  /// No description provided for @clientsSortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get clientsSortLabel;

  /// No description provided for @clientsSortPriority.
  ///
  /// In en, this message translates to:
  /// **'Needs attention first'**
  String get clientsSortPriority;

  /// No description provided for @clientsSortName.
  ///
  /// In en, this message translates to:
  /// **'Name A–Z'**
  String get clientsSortName;

  /// No description provided for @clientsSortNameDescending.
  ///
  /// In en, this message translates to:
  /// **'Name Z–A'**
  String get clientsSortNameDescending;

  /// No description provided for @clientsSortRecentMessage.
  ///
  /// In en, this message translates to:
  /// **'Recent conversations'**
  String get clientsSortRecentMessage;

  /// No description provided for @clientsFilterLabel.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get clientsFilterLabel;

  /// No description provided for @clientsPickHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a member on the left to open\ntheir chat, meals and workouts here'**
  String get clientsPickHint;

  /// No description provided for @clientsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No members yet'**
  String get clientsEmpty;

  /// No description provided for @clientsEmptyConnectHint.
  ///
  /// In en, this message translates to:
  /// **'Connect members with the code they show you or by sending a coaching request. Consultation requests from members also appear in your inbox.'**
  String get clientsEmptyConnectHint;

  /// No description provided for @clientsEmptyForFilter.
  ///
  /// In en, this message translates to:
  /// **'No members match {filter}'**
  String clientsEmptyForFilter(String filter);

  /// No description provided for @clientsMemberCount.
  ///
  /// In en, this message translates to:
  /// **'{total} members'**
  String clientsMemberCount(int total);

  /// Roster subtitle while a dashboard preset or management filter narrows the list.
  ///
  /// In en, this message translates to:
  /// **'{shown} of {total} members'**
  String clientsMemberCountFiltered(int shown, int total);

  /// No description provided for @clientWeeklyRoutineAdherence.
  ///
  /// In en, this message translates to:
  /// **'Weekly adherence'**
  String get clientWeeklyRoutineAdherence;

  /// No description provided for @clientRoutineAdherenceUnmeasured.
  ///
  /// In en, this message translates to:
  /// **'Not measured'**
  String get clientRoutineAdherenceUnmeasured;

  /// No description provided for @clientsSignalDiscomfort.
  ///
  /// In en, this message translates to:
  /// **'Pain'**
  String get clientsSignalDiscomfort;

  /// No description provided for @clientsSignalRecordGap.
  ///
  /// In en, this message translates to:
  /// **'No logs'**
  String get clientsSignalRecordGap;

  /// No description provided for @clientsSignalRecordGapDays.
  ///
  /// In en, this message translates to:
  /// **'No logs {days}d'**
  String clientsSignalRecordGapDays(int days);

  /// No description provided for @clientsSignalRecordGapLong.
  ///
  /// In en, this message translates to:
  /// **'No logs 30d+'**
  String get clientsSignalRecordGapLong;

  /// No description provided for @clientsSignalNoShow.
  ///
  /// In en, this message translates to:
  /// **'No-shows'**
  String get clientsSignalNoShow;

  /// No description provided for @clientsSignalNoShowCount.
  ///
  /// In en, this message translates to:
  /// **'{count} no-shows'**
  String clientsSignalNoShowCount(int count);

  /// No description provided for @clientsSignalRoutineMissed.
  ///
  /// In en, this message translates to:
  /// **'Routine skipped'**
  String get clientsSignalRoutineMissed;

  /// No description provided for @clientsSignalExerciseGoalLow.
  ///
  /// In en, this message translates to:
  /// **'Low exercise'**
  String get clientsSignalExerciseGoalLow;

  /// No description provided for @clientsSignalExerciseGoalLowPercent.
  ///
  /// In en, this message translates to:
  /// **'Exercise {percent}%'**
  String clientsSignalExerciseGoalLowPercent(int percent);

  /// No description provided for @clientsSignalCalorieOff.
  ///
  /// In en, this message translates to:
  /// **'Off calorie goal'**
  String get clientsSignalCalorieOff;

  /// No description provided for @clientsSignalCalorieOver.
  ///
  /// In en, this message translates to:
  /// **'Calories over'**
  String get clientsSignalCalorieOver;

  /// No description provided for @clientsSignalCalorieUnder.
  ///
  /// In en, this message translates to:
  /// **'Calories under'**
  String get clientsSignalCalorieUnder;

  /// No description provided for @clientsSignalProteinLow.
  ///
  /// In en, this message translates to:
  /// **'Low protein'**
  String get clientsSignalProteinLow;

  /// No description provided for @clientsSignalCalorieOverPercent.
  ///
  /// In en, this message translates to:
  /// **'Calories {percent}% over'**
  String clientsSignalCalorieOverPercent(int percent);

  /// No description provided for @clientsSignalCalorieUnderPercent.
  ///
  /// In en, this message translates to:
  /// **'Calories {percent}% under'**
  String clientsSignalCalorieUnderPercent(int percent);

  /// No description provided for @clientsSignalProteinPercent.
  ///
  /// In en, this message translates to:
  /// **'Protein {percent}% of goal'**
  String clientsSignalProteinPercent(int percent);

  /// No description provided for @clientsSignalRoutineMissedDays.
  ///
  /// In en, this message translates to:
  /// **'Routine skipped {days}d'**
  String clientsSignalRoutineMissedDays(int days);

  /// No description provided for @clientsSignalUnanswered.
  ///
  /// In en, this message translates to:
  /// **'Awaiting reply'**
  String get clientsSignalUnanswered;

  /// No description provided for @clientsAttentionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear attention filter'**
  String get clientsAttentionClear;

  /// No description provided for @memberHealthLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the member profile. Please try again'**
  String get memberHealthLoadFailed;

  /// No description provided for @memberHealthSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the member profile. Please try again'**
  String get memberHealthSaveFailed;

  /// No description provided for @memberHealthSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get memberHealthSaving;

  /// No description provided for @memberHealthGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get memberHealthGender;

  /// No description provided for @memberHealthGenderUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get memberHealthGenderUnset;

  /// No description provided for @memberHealthGenderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get memberHealthGenderMale;

  /// No description provided for @memberHealthGenderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get memberHealthGenderFemale;

  /// No description provided for @memberHealthGenderOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get memberHealthGenderOther;

  /// No description provided for @memberHealthHeight.
  ///
  /// In en, this message translates to:
  /// **'Height (cm)'**
  String get memberHealthHeight;

  /// No description provided for @memberHealthWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get memberHealthWeight;

  /// No description provided for @memberHealthFocus.
  ///
  /// In en, this message translates to:
  /// **'Health goals (up to 2)'**
  String get memberHealthFocus;

  /// Member profile dialog: who last changed the member's goal chips and when (#1832).
  ///
  /// In en, this message translates to:
  /// **'Last changed by {who} · {date}'**
  String memberHealthFocusLastChanged(String who, String date);

  /// No description provided for @memberHealthFocusChangedByTrainer.
  ///
  /// In en, this message translates to:
  /// **'Trainer'**
  String get memberHealthFocusChangedByTrainer;

  /// No description provided for @memberHealthFocusChangedByMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get memberHealthFocusChangedByMember;

  /// No description provided for @healthFocusWeightLoss.
  ///
  /// In en, this message translates to:
  /// **'Weight loss'**
  String get healthFocusWeightLoss;

  /// No description provided for @healthFocusStrength.
  ///
  /// In en, this message translates to:
  /// **'Build strength'**
  String get healthFocusStrength;

  /// No description provided for @healthFocusFitness.
  ///
  /// In en, this message translates to:
  /// **'Improve fitness'**
  String get healthFocusFitness;

  /// No description provided for @healthFocusPosture.
  ///
  /// In en, this message translates to:
  /// **'Posture correction'**
  String get healthFocusPosture;

  /// No description provided for @healthFocusRehab.
  ///
  /// In en, this message translates to:
  /// **'Rehab'**
  String get healthFocusRehab;

  /// No description provided for @healthFocusEating.
  ///
  /// In en, this message translates to:
  /// **'Better eating habits'**
  String get healthFocusEating;

  /// No description provided for @healthFocusExerciseHabit.
  ///
  /// In en, this message translates to:
  /// **'Exercise habit'**
  String get healthFocusExerciseHabit;

  /// No description provided for @healthFocusBloodPressure.
  ///
  /// In en, this message translates to:
  /// **'Blood pressure care'**
  String get healthFocusBloodPressure;

  /// No description provided for @memberHealthConditions.
  ///
  /// In en, this message translates to:
  /// **'Conditions and cautions'**
  String get memberHealthConditions;

  /// No description provided for @memberHealthConditionsShared.
  ///
  /// In en, this message translates to:
  /// **'The member sees this too · Used for recommendations'**
  String get memberHealthConditionsShared;

  /// No description provided for @memberHealthConditionsPrivateHint.
  ///
  /// In en, this message translates to:
  /// **'Keep trainer-only notes in Memo.'**
  String get memberHealthConditionsPrivateHint;

  /// No description provided for @memberHealthDietGoal.
  ///
  /// In en, this message translates to:
  /// **'Nutrition goals'**
  String get memberHealthDietGoal;

  /// No description provided for @memberHealthExerciseGoal.
  ///
  /// In en, this message translates to:
  /// **'Exercise goals'**
  String get memberHealthExerciseGoal;

  /// No description provided for @memberHealthGoalCalories.
  ///
  /// In en, this message translates to:
  /// **'Daily calories (kcal)'**
  String get memberHealthGoalCalories;

  /// No description provided for @memberHealthGoalSodium.
  ///
  /// In en, this message translates to:
  /// **'Daily sodium (mg)'**
  String get memberHealthGoalSodium;

  /// No description provided for @memberHealthGoalSugar.
  ///
  /// In en, this message translates to:
  /// **'Daily sugar (g)'**
  String get memberHealthGoalSugar;

  /// No description provided for @memberHealthGoalCarbs.
  ///
  /// In en, this message translates to:
  /// **'Daily carbs (g)'**
  String get memberHealthGoalCarbs;

  /// No description provided for @memberHealthGoalProtein.
  ///
  /// In en, this message translates to:
  /// **'Daily protein (g)'**
  String get memberHealthGoalProtein;

  /// No description provided for @memberHealthGoalFat.
  ///
  /// In en, this message translates to:
  /// **'Daily fat (g)'**
  String get memberHealthGoalFat;

  /// No description provided for @memberHealthGoalBurnDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily burn (kcal)'**
  String get memberHealthGoalBurnDaily;

  /// No description provided for @memberHealthGoalCardioWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly cardio (min)'**
  String get memberHealthGoalCardioWeekly;

  /// No description provided for @memberHealthGoalStrengthWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly strength (sets)'**
  String get memberHealthGoalStrengthWeekly;

  /// No description provided for @memberHealthGoalFlexibilityWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly stretching (min)'**
  String get memberHealthGoalFlexibilityWeekly;

  /// No description provided for @memberHealthRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a value between {min} and {max}.'**
  String memberHealthRange(String min, String max);

  /// No description provided for @clientInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a new member'**
  String get clientInviteTitle;

  /// No description provided for @clientInviteIntro.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit sync code from the member\'s MY tab to connect right away.'**
  String get clientInviteIntro;

  /// No description provided for @clientInviteIntroImmediate.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit sync code from the member\'s MY tab to connect right away.'**
  String get clientInviteIntroImmediate;

  /// No description provided for @clientConnectCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync code'**
  String get clientConnectCodeLabel;

  /// No description provided for @clientConnectCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter all six digits'**
  String get clientConnectCodeRequired;

  /// No description provided for @clientConnectCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'That code is wrong or expired. Ask the member for a new one'**
  String get clientConnectCodeInvalid;

  /// No description provided for @clientConnectAlreadyManaged.
  ///
  /// In en, this message translates to:
  /// **'You already manage this member. Find them in your member list'**
  String get clientConnectAlreadyManaged;

  /// No description provided for @clientInviteConnectAction.
  ///
  /// In en, this message translates to:
  /// **'Register member'**
  String get clientInviteConnectAction;

  /// No description provided for @clientInviteConnected.
  ///
  /// In en, this message translates to:
  /// **'Registered {name} as a member'**
  String clientInviteConnected(String name);

  /// No description provided for @clientInviteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the request. Please try again'**
  String get clientInviteFailed;

  /// No description provided for @clientInvitePendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for an answer'**
  String get clientInvitePendingTitle;

  /// No description provided for @clientInvitePendingEmpty.
  ///
  /// In en, this message translates to:
  /// **'No requests are waiting'**
  String get clientInvitePendingEmpty;

  /// No description provided for @clientInviteCancelAction.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get clientInviteCancelAction;

  /// No description provided for @clientInviteCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request withdrawn'**
  String get clientInviteCancelled;

  /// No description provided for @clientInviteCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t withdraw the request. Please try again'**
  String get clientInviteCancelFailed;

  /// No description provided for @clientInviteConfirmPrompt.
  ///
  /// In en, this message translates to:
  /// **'Is this the right member?'**
  String get clientInviteConfirmPrompt;

  /// No description provided for @coachTemplateNew.
  ///
  /// In en, this message translates to:
  /// **'New template'**
  String get coachTemplateNew;

  /// No description provided for @coachTemplateEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit template'**
  String get coachTemplateEdit;

  /// No description provided for @coachTemplateDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get coachTemplateDelete;

  /// No description provided for @coachTemplateNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Template name'**
  String get coachTemplateNameLabel;

  /// No description provided for @coachTemplateGoalLabel.
  ///
  /// In en, this message translates to:
  /// **'Goal (e.g. blood pressure · beginner)'**
  String get coachTemplateGoalLabel;

  /// No description provided for @coachTemplateExerciseName.
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get coachTemplateExerciseName;

  /// No description provided for @coachTemplateAddExercise.
  ///
  /// In en, this message translates to:
  /// **'Add exercise'**
  String get coachTemplateAddExercise;

  /// No description provided for @coachTemplateSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get coachTemplateSave;

  /// No description provided for @coachTemplateNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a template name'**
  String get coachTemplateNameRequired;

  /// No description provided for @coachTemplateExerciseRequired.
  ///
  /// In en, this message translates to:
  /// **'Add at least one exercise'**
  String get coachTemplateExerciseRequired;

  /// No description provided for @coachTemplateExerciseNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the exercise name'**
  String get coachTemplateExerciseNameRequired;

  /// No description provided for @coachTemplateSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the template. Please try again'**
  String get coachTemplateSaveFailed;

  /// No description provided for @coachTemplateDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the template. Please try again'**
  String get coachTemplateDeleteFailed;

  /// No description provided for @coachTemplateDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the {name} template?'**
  String coachTemplateDeleteConfirm(String name);

  /// No description provided for @coachTemplateLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load templates'**
  String get coachTemplateLoadFailed;

  /// No description provided for @chatEmoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Emote'**
  String get chatEmoteLabel;

  /// No description provided for @chatAttachImage.
  ///
  /// In en, this message translates to:
  /// **'Attach a photo'**
  String get chatAttachImage;

  /// No description provided for @chatImageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the photo'**
  String get chatImageUnavailable;

  /// No description provided for @chatImageSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the photo. Please try again'**
  String get chatImageSendFailed;

  /// No description provided for @clientTabDiet.
  ///
  /// In en, this message translates to:
  /// **'Meals'**
  String get clientTabDiet;

  /// No description provided for @clientTabWorkout.
  ///
  /// In en, this message translates to:
  /// **'Workouts'**
  String get clientTabWorkout;

  /// No description provided for @clientNotFound.
  ///
  /// In en, this message translates to:
  /// **'Member not found'**
  String get clientNotFound;

  /// No description provided for @clientBackToList.
  ///
  /// In en, this message translates to:
  /// **'Back to members'**
  String get clientBackToList;

  /// No description provided for @clientList.
  ///
  /// In en, this message translates to:
  /// **'Member list'**
  String get clientList;

  /// No description provided for @metricCalories.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get metricCalories;

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

  /// No description provided for @clientDietMacrosMissing.
  ///
  /// In en, this message translates to:
  /// **'No carbs/protein/fat recorded'**
  String get clientDietMacrosMissing;

  /// No description provided for @clientDietDayTotal.
  ///
  /// In en, this message translates to:
  /// **'Day total'**
  String get clientDietDayTotal;

  /// Shown under the day total when the expanded day's meals fail to load (#2892)
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this day\'s meals'**
  String get clientDietDayMealsFailed;

  /// 트레이너 웹 식단 합계 kcal — 오늘 끼니 카드의 네 칸 오른쪽 끝과 펼친 날 하루 합계 줄 오른쪽 끝. 음식 kcal 과 구분되게 총을 붙인다. calories 는 천 단위 구분이 된 숫자. (#2421)
  ///
  /// In en, this message translates to:
  /// **'Total {calories} kcal'**
  String clientDietTotalCalories(String calories);

  /// 끼니 카드 탄단지 범례 한 칸 — 이름과 그 끼니 칼로리에서 차지하는 비중(%). g 은 오른쪽 세부 줄에 있다. (#2333)
  ///
  /// In en, this message translates to:
  /// **'{name} {percent}%'**
  String clientDietMacroShare(String name, int percent);

  /// No description provided for @metricCarbs.
  ///
  /// In en, this message translates to:
  /// **'Carbs'**
  String get metricCarbs;

  /// No description provided for @metricProtein.
  ///
  /// In en, this message translates to:
  /// **'Protein'**
  String get metricProtein;

  /// No description provided for @metricFat.
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get metricFat;

  /// No description provided for @clientDormant.
  ///
  /// In en, this message translates to:
  /// **'Dormant'**
  String get clientDormant;

  /// No description provided for @clientDormantActivate.
  ///
  /// In en, this message translates to:
  /// **'Tap to mark active'**
  String get clientDormantActivate;

  /// No description provided for @clientSignalLess.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get clientSignalLess;

  /// No description provided for @clientSignalMore.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String clientSignalMore(int count);

  /// No description provided for @clientStatusChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change the status. Please try again.'**
  String get clientStatusChangeFailed;

  /// No description provided for @chatTooLong.
  ///
  /// In en, this message translates to:
  /// **'Message is too long (1000 characters max)'**
  String get chatTooLong;

  /// No description provided for @chatSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the message. Please try again'**
  String get chatSendFailed;

  /// No description provided for @chatPdfOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the PDF. Please try again'**
  String get chatPdfOpenFailed;

  /// No description provided for @chatReportRegistered.
  ///
  /// In en, this message translates to:
  /// **'Weekly report added'**
  String get chatReportRegistered;

  /// No description provided for @chatReportOpenInReports.
  ///
  /// In en, this message translates to:
  /// **'Go to Reports'**
  String get chatReportOpenInReports;

  /// No description provided for @chatLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the conversation'**
  String get chatLoadFailed;

  /// 회원 메시지 맨 위 — 서버가 주는 최신 50건 앞의 메시지를 한 쪽 더 받는 버튼(#2749). 위로 끝까지 스크롤해도 같은 일이 일어난다.
  ///
  /// In en, this message translates to:
  /// **'Load earlier messages'**
  String get chatLoadOlder;

  /// 이전 메시지 한 쪽을 받지 못했을 때 같은 자리의 버튼. 누르면 다시 받는다(#2749).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load earlier messages · Retry'**
  String get chatLoadOlderFailed;

  /// No description provided for @chatRoutineDelivered.
  ///
  /// In en, this message translates to:
  /// **'Workout sent'**
  String get chatRoutineDelivered;

  /// No description provided for @chatRoutineDeliveredPt.
  ///
  /// In en, this message translates to:
  /// **'PT program and personal exercises sent'**
  String get chatRoutineDeliveredPt;

  /// No description provided for @chatRoutineDeliveredPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal exercises sent'**
  String get chatRoutineDeliveredPersonal;

  /// No description provided for @chatRoutineDeliveredAfterCancel.
  ///
  /// In en, this message translates to:
  /// **'Personal exercises sent in place of the cancelled PT'**
  String get chatRoutineDeliveredAfterCancel;

  /// No description provided for @chatRoutineDeliveredProgram.
  ///
  /// In en, this message translates to:
  /// **'Workout program sent'**
  String get chatRoutineDeliveredProgram;

  /// No description provided for @chatRoutineDeliveredMore.
  ///
  /// In en, this message translates to:
  /// **'{names} and {count} more'**
  String chatRoutineDeliveredMore(String names, int count);

  /// No description provided for @chatInputHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get chatInputHint;

  /// No description provided for @chatInsightDiscomfortTitle.
  ///
  /// In en, this message translates to:
  /// **'{part} discomfort detected'**
  String chatInsightDiscomfortTitle(String part);

  /// No description provided for @chatInsightBodyPartGeneral.
  ///
  /// In en, this message translates to:
  /// **'Physical'**
  String get chatInsightBodyPartGeneral;

  /// No description provided for @chatInsightBodyPartKnee.
  ///
  /// In en, this message translates to:
  /// **'Knee'**
  String get chatInsightBodyPartKnee;

  /// No description provided for @chatInsightBodyPartBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get chatInsightBodyPartBack;

  /// No description provided for @chatInsightBodyPartAnkle.
  ///
  /// In en, this message translates to:
  /// **'Ankle'**
  String get chatInsightBodyPartAnkle;

  /// No description provided for @chatInsightBodyPartShoulder.
  ///
  /// In en, this message translates to:
  /// **'Shoulder'**
  String get chatInsightBodyPartShoulder;

  /// No description provided for @chatInsightBodyPartWrist.
  ///
  /// In en, this message translates to:
  /// **'Wrist'**
  String get chatInsightBodyPartWrist;

  /// No description provided for @chatInsightBodyPartNeck.
  ///
  /// In en, this message translates to:
  /// **'Neck'**
  String get chatInsightBodyPartNeck;

  /// No description provided for @chatInsightNegativeTitle.
  ///
  /// In en, this message translates to:
  /// **'Negative feedback detected'**
  String get chatInsightNegativeTitle;

  /// No description provided for @chatInsightDiscomfortDescription.
  ///
  /// In en, this message translates to:
  /// **'AI detected a report of discomfort. Check the symptoms and consider adjusting the next workout\'s intensity.'**
  String get chatInsightDiscomfortDescription;

  /// No description provided for @chatInsightNegativeDescription.
  ///
  /// In en, this message translates to:
  /// **'AI detected workout strain or difficulty completing the plan. Check the cause and consider adjusting the program.'**
  String get chatInsightNegativeDescription;

  /// No description provided for @chatInsightAddMemo.
  ///
  /// In en, this message translates to:
  /// **'Add to memo'**
  String get chatInsightAddMemo;

  /// No description provided for @chatInsightMemoAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to memo'**
  String get chatInsightMemoAdded;

  /// No description provided for @chatInsightMemoSummaryDiscomfort.
  ///
  /// In en, this message translates to:
  /// **'{part} discomfort detected'**
  String chatInsightMemoSummaryDiscomfort(String part);

  /// No description provided for @chatInsightMemoSummaryNegative.
  ///
  /// In en, this message translates to:
  /// **'Workout strain detected'**
  String get chatInsightMemoSummaryNegative;

  /// No description provided for @chatInsightMemoSaved.
  ///
  /// In en, this message translates to:
  /// **'The AI insight was added to your memos.'**
  String get chatInsightMemoSaved;

  /// No description provided for @chatInsightMemoSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add the memo. Please try again.'**
  String get chatInsightMemoSaveFailed;

  /// No description provided for @consultTitle.
  ///
  /// In en, this message translates to:
  /// **'Consultation requests'**
  String get consultTitle;

  /// No description provided for @consultFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get consultFilterAll;

  /// No description provided for @consultFilterPendingCount.
  ///
  /// In en, this message translates to:
  /// **'Pending {count}'**
  String consultFilterPendingCount(int count);

  /// No description provided for @consultLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load earlier requests'**
  String get consultLoadMore;

  /// No description provided for @consultLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load consultation requests'**
  String get consultLoadFailed;

  /// No description provided for @consultRetryLater.
  ///
  /// In en, this message translates to:
  /// **'Please try again in a moment'**
  String get consultRetryLater;

  /// No description provided for @consultEmptyPending.
  ///
  /// In en, this message translates to:
  /// **'No pending consultation requests'**
  String get consultEmptyPending;

  /// No description provided for @consultEmptyHistory.
  ///
  /// In en, this message translates to:
  /// **'No consultation history'**
  String get consultEmptyHistory;

  /// No description provided for @consultEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Requests appear here when a member asks for a consultation with your gym or with you'**
  String get consultEmptyHint;

  /// No description provided for @consultActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t process the request'**
  String get consultActionFailed;

  /// No description provided for @consultApproved.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s request was approved. Add a session from the Schedule tab.'**
  String consultApproved(String name);

  /// No description provided for @consultScheduleCreated.
  ///
  /// In en, this message translates to:
  /// **'Added a consultation session for {name}'**
  String consultScheduleCreated(String name);

  /// No description provided for @consultRejected.
  ///
  /// In en, this message translates to:
  /// **'Request declined'**
  String get consultRejected;

  /// No description provided for @consultDecisionNote.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get consultDecisionNote;

  /// No description provided for @consultExerciseGoal.
  ///
  /// In en, this message translates to:
  /// **'Training goal'**
  String get consultExerciseGoal;

  /// No description provided for @consultChosenSlot.
  ///
  /// In en, this message translates to:
  /// **'Chosen time'**
  String get consultChosenSlot;

  /// No description provided for @consultSlotDuration.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String consultSlotDuration(int minutes);

  /// No description provided for @consultStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get consultStatusCancelled;

  /// No description provided for @consultStatusCancelledByTrainer.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn (session cancelled)'**
  String get consultStatusCancelledByTrainer;

  /// No description provided for @consultStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get consultStatusExpired;

  /// No description provided for @consultPreferredTime.
  ///
  /// In en, this message translates to:
  /// **'Preferred time'**
  String get consultPreferredTime;

  /// No description provided for @consultMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get consultMessage;

  /// No description provided for @schedConsultRequest.
  ///
  /// In en, this message translates to:
  /// **'Consultation request'**
  String get schedConsultRequest;

  /// No description provided for @consultReject.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get consultReject;

  /// No description provided for @consultApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get consultApprove;

  /// No description provided for @consultRejectTitle.
  ///
  /// In en, this message translates to:
  /// **'Decline request'**
  String get consultRejectTitle;

  /// No description provided for @consultRejectNotice.
  ///
  /// In en, this message translates to:
  /// **'The reason you write is sent to the member as a notification.'**
  String get consultRejectNotice;

  /// No description provided for @consultRejectHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. I have another appointment at your requested time.'**
  String get consultRejectHint;

  /// No description provided for @consultStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get consultStatusPending;

  /// No description provided for @consultStatusAccepted.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get consultStatusAccepted;

  /// No description provided for @workoutRecords.
  ///
  /// In en, this message translates to:
  /// **'Workout log'**
  String get workoutRecords;

  /// No description provided for @workoutRecordsShowMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get workoutRecordsShowMore;

  /// No description provided for @workoutRecordsShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get workoutRecordsShowLess;

  /// No description provided for @workoutLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the workout log'**
  String get workoutLoadFailed;

  /// No description provided for @workoutEmpty.
  ///
  /// In en, this message translates to:
  /// **'No workouts logged yet'**
  String get workoutEmpty;

  /// No description provided for @routinesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load programs'**
  String get routinesLoadFailed;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String minutesShort(int minutes);

  /// Hours part of an exercise duration, e.g. `1 hr 30 min` (#2221).
  ///
  /// In en, this message translates to:
  /// **'{hours} hr'**
  String hoursShort(int hours);

  /// Seconds part of an exercise duration, e.g. `45 sec` (#2221).
  ///
  /// In en, this message translates to:
  /// **'{seconds} sec'**
  String secondsShort(int seconds);

  /// No description provided for @labelToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get labelToday;

  /// No description provided for @sessionTypeAndDuration.
  ///
  /// In en, this message translates to:
  /// **'{type} · {minutes} min'**
  String sessionTypeAndDuration(String type, int minutes);

  /// No description provided for @legendDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get legendDone;

  /// No description provided for @clientFeedback.
  ///
  /// In en, this message translates to:
  /// **'Member feedback'**
  String get clientFeedback;

  /// No description provided for @workoutKindAiPersonal.
  ///
  /// In en, this message translates to:
  /// **'AI personal exercise'**
  String get workoutKindAiPersonal;

  /// Workout history kind for a completed PT session (server kind code pt_session).
  ///
  /// In en, this message translates to:
  /// **'PT · Trainer-led'**
  String get workoutKindPtSession;

  /// Workout history kind for a completed assigned routine that has no name (server kind code assigned_routine).
  ///
  /// In en, this message translates to:
  /// **'Assigned routine'**
  String get workoutKindAssignedRoutine;

  /// No description provided for @dietLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load meals'**
  String get dietLoadFailed;

  /// No description provided for @dietEmpty.
  ///
  /// In en, this message translates to:
  /// **'No meals logged yet'**
  String get dietEmpty;

  /// No description provided for @dietDayEmpty.
  ///
  /// In en, this message translates to:
  /// **'No record'**
  String get dietDayEmpty;

  /// No description provided for @clientNutritionSummary.
  ///
  /// In en, this message translates to:
  /// **'Nutrition summary'**
  String get clientNutritionSummary;

  /// No description provided for @dietCalorieIntake.
  ///
  /// In en, this message translates to:
  /// **'Calories today'**
  String get dietCalorieIntake;

  /// No description provided for @dietAchieveRate.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get dietAchieveRate;

  /// No description provided for @consultStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get consultStatusRejected;

  /// No description provided for @dateToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateToday;

  /// No description provided for @dateTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get dateTomorrow;

  /// No description provided for @dateYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dateYesterday;

  /// Relative day label, used for two or more days ago (e.g. when the last routine was sent).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String dateDaysAgo(int count);

  /// No description provided for @dateWeeksAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 week ago} other{{count} weeks ago}}'**
  String dateWeeksAgo(int count);

  /// Short date on a workout history card.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day}'**
  String historyDate(int month, int day);

  /// Workout history date with Today/Yesterday, e.g. 9/27 (Today).
  ///
  /// In en, this message translates to:
  /// **'{date} ({relative})'**
  String historyDateRelative(String date, String relative);

  /// No description provided for @dateMonthDayWeekday.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day} ({weekday})'**
  String dateMonthDayWeekday(int month, int day, String weekday);

  /// No description provided for @datePrefixed.
  ///
  /// In en, this message translates to:
  /// **'{prefix} · {date}'**
  String datePrefixed(String prefix, String date);

  /// No description provided for @dateMonthDay.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day}'**
  String dateMonthDay(int month, int day);

  /// No description provided for @dateRange.
  ///
  /// In en, this message translates to:
  /// **'{start} – {end}'**
  String dateRange(String start, String end);

  /// No description provided for @reportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// No description provided for @reportsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review the week\'s changes and share them with your member'**
  String get reportsSubtitle;

  /// No description provided for @reportsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load reports'**
  String get reportsLoadFailed;

  /// No description provided for @reportsNoClients.
  ///
  /// In en, this message translates to:
  /// **'No members yet, so there\'s nothing to report on'**
  String get reportsNoClients;

  /// No description provided for @reportsWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly report'**
  String get reportsWeekly;

  /// No description provided for @reportsSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the report. Please try again'**
  String get reportsSendFailed;

  /// Toast when the server says this report send was already processed (409, #2773).
  ///
  /// In en, this message translates to:
  /// **'This report was already sent. Send history has been refreshed'**
  String get reportsSendAlreadyDone;

  /// No description provided for @reportsSent.
  ///
  /// In en, this message translates to:
  /// **'Report sent to {name}'**
  String reportsSent(String name);

  /// No description provided for @reportsGoToChat.
  ///
  /// In en, this message translates to:
  /// **'Go to chat'**
  String get reportsGoToChat;

  /// No description provided for @reportsScheduleWarning.
  ///
  /// In en, this message translates to:
  /// **'This week\'s schedule didn\'t load, so PT counts may be missing'**
  String get reportsScheduleWarning;

  /// No description provided for @unitTimes.
  ///
  /// In en, this message translates to:
  /// **''**
  String get unitTimes;

  /// No description provided for @unitMinutes.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get unitMinutes;

  /// No description provided for @clientPeriodToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get clientPeriodToday;

  /// No description provided for @clientPeriodWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get clientPeriodWeek;

  /// No description provided for @clientPeriodMonth.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get clientPeriodMonth;

  /// No description provided for @clientPeriodAverage.
  ///
  /// In en, this message translates to:
  /// **'Daily average'**
  String get clientPeriodAverage;

  /// No description provided for @clientPeriodGoal.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get clientPeriodGoal;

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

  /// No description provided for @exWeekOfMonthLabel.
  ///
  /// In en, this message translates to:
  /// **'Burned in week {week}, {month}/'**
  String exWeekOfMonthLabel(int month, int week);

  /// No description provided for @exStreakCheer.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day in a row!} other{{days} days in a row!}}'**
  String exStreakCheer(int days);

  /// No description provided for @exStreakStart.
  ///
  /// In en, this message translates to:
  /// **'No streak yet'**
  String get exStreakStart;

  /// No description provided for @exTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get exTypeOther;

  /// No description provided for @clientPeriodEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing was logged in this period'**
  String get clientPeriodEmpty;

  /// No description provided for @unitKcal.
  ///
  /// In en, this message translates to:
  /// **'kcal'**
  String get unitKcal;

  /// No description provided for @clientTrendTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get clientTrendTitle;

  /// No description provided for @clientTrendLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the workout trend. Please try again'**
  String get clientTrendLoadFailed;

  /// No description provided for @clientTrendTodayEmpty.
  ///
  /// In en, this message translates to:
  /// **'No workout logged today'**
  String get clientTrendTodayEmpty;

  /// No description provided for @clientTrendWorkoutMinutes.
  ///
  /// In en, this message translates to:
  /// **'Exercise time'**
  String get clientTrendWorkoutMinutes;

  /// No description provided for @clientTrendCaloriesBurned.
  ///
  /// In en, this message translates to:
  /// **'Calories burned'**
  String get clientTrendCaloriesBurned;

  /// No description provided for @reportsPickClient.
  ///
  /// In en, this message translates to:
  /// **'Pick a member'**
  String get reportsPickClient;

  /// No description provided for @reportsClientWeekly.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s weekly report'**
  String reportsClientWeekly(String name);

  /// No description provided for @reportsCompletionByDay.
  ///
  /// In en, this message translates to:
  /// **'Weekly workout completion'**
  String get reportsCompletionByDay;

  /// No description provided for @reportsNoWorkoutsThisWeek.
  ///
  /// In en, this message translates to:
  /// **'No workouts logged this week'**
  String get reportsNoWorkoutsThisWeek;

  /// No description provided for @chartNoRecord.
  ///
  /// In en, this message translates to:
  /// **'Not logged'**
  String get chartNoRecord;

  /// No description provided for @chartNotYet.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get chartNotYet;

  /// No description provided for @chartOverGoal.
  ///
  /// In en, this message translates to:
  /// **'{amount} {unit} over goal'**
  String chartOverGoal(String amount, String unit);

  /// No description provided for @reportsSendNeedsFeedback.
  ///
  /// In en, this message translates to:
  /// **'Write feedback first to send it.'**
  String get reportsSendNeedsFeedback;

  /// No description provided for @reportBodyGreeting.
  ///
  /// In en, this message translates to:
  /// **'{name}, here\'s your weekly report for {range}.'**
  String reportBodyGreeting(String name, String range);

  /// No description provided for @reportBodyCompletionGood.
  ///
  /// In en, this message translates to:
  /// **'You kept up well — {avg}% of your workouts done.'**
  String reportBodyCompletionGood(int avg);

  /// No description provided for @reportBodyCompletionSteady.
  ///
  /// In en, this message translates to:
  /// **'You stayed steady — {avg}% of your workouts done.'**
  String reportBodyCompletionSteady(int avg);

  /// No description provided for @reportBodyCompletionLow.
  ///
  /// In en, this message translates to:
  /// **'Workout completion came in at {avg}%. Sounds like a busy one.'**
  String reportBodyCompletionLow(int avg);

  /// No description provided for @reportBodySilentDays.
  ///
  /// In en, this message translates to:
  /// **'Nothing was logged on {days}. If those days are always packed, I\'ll swap in a short 15-minute version.'**
  String reportBodySilentDays(String days);

  /// No description provided for @reportBodySteadyDays.
  ///
  /// In en, this message translates to:
  /// **'Keeping it going all the way through {days} was the best part of this week.'**
  String reportBodySteadyDays(String days);

  /// No description provided for @reportBodySkipped.
  ///
  /// In en, this message translates to:
  /// **'One thing — {names} got skipped. If that was a condition thing, tell me at our next PT and I\'ll swap in an alternative.'**
  String reportBodySkipped(String names);

  /// No description provided for @reportBodySodiumOver.
  ///
  /// In en, this message translates to:
  /// **'Sodium averaged {avg}mg a day, and went over the {target}mg target on {days} days. Leaving half the broth behind saves 400-500mg a day.'**
  String reportBodySodiumOver(String avg, String target, int days);

  /// No description provided for @reportBodySodiumOk.
  ///
  /// In en, this message translates to:
  /// **'Sodium averaged {avg}mg a day — comfortably inside the {target}mg target.'**
  String reportBodySodiumOk(String avg, String target);

  /// No description provided for @reportBodyPraise.
  ///
  /// In en, this message translates to:
  /// **'Great work — let\'s keep this pace next week!'**
  String get reportBodyPraise;

  /// No description provided for @reportBodyEncourage.
  ///
  /// In en, this message translates to:
  /// **'Take those one at a time and you\'ll see it come together. I\'ll adjust your program and send it over.'**
  String get reportBodyEncourage;

  /// No description provided for @reportBodyNoRecords.
  ///
  /// In en, this message translates to:
  /// **'There\'s nothing logged for this week, so nothing to sum up. Let\'s plan next week\'s start together.'**
  String get reportBodyNoRecords;

  /// No description provided for @reportBodySessionsAll.
  ///
  /// In en, this message translates to:
  /// **'For PT, you made all {booked} that were booked.'**
  String reportBodySessionsAll(int booked);

  /// No description provided for @reportBodySessionsSome.
  ///
  /// In en, this message translates to:
  /// **'For PT, you made {done} of the {booked} that were booked.'**
  String reportBodySessionsSome(int booked, int done);

  /// No description provided for @reportBodySessionsNone.
  ///
  /// In en, this message translates to:
  /// **'There was no PT this week.'**
  String get reportBodySessionsNone;

  /// No description provided for @reportBodyExerciseCount.
  ///
  /// In en, this message translates to:
  /// **'You finished {done} of the {total} assigned exercises.'**
  String reportBodyExerciseCount(int total, int done);

  /// No description provided for @reportBodyMealDaysAll.
  ///
  /// In en, this message translates to:
  /// **'You logged your meals on all {total} days.'**
  String reportBodyMealDaysAll(int total);

  /// No description provided for @reportBodyMealDays.
  ///
  /// In en, this message translates to:
  /// **'You logged your meals on {days} of {total} days.'**
  String reportBodyMealDays(int total, int days);

  /// No description provided for @reportBodyCaloriesOver.
  ///
  /// In en, this message translates to:
  /// **'Calories averaged {avg}kcal a day — {pct}% above your {target}kcal target, and over it on {days} days.'**
  String reportBodyCaloriesOver(
    String avg,
    String target,
    String pct,
    int days,
  );

  /// No description provided for @reportBodyCaloriesUnder.
  ///
  /// In en, this message translates to:
  /// **'Calories averaged {avg}kcal a day — {pct}% below your {target}kcal target. Eating too little tends to cost muscle first.'**
  String reportBodyCaloriesUnder(String avg, String target, String pct);

  /// No description provided for @reportBodyCaloriesNearOver.
  ///
  /// In en, this message translates to:
  /// **'Calories averaged {avg}kcal a day, close to your {target}kcal target, but went over it on {days} days.'**
  String reportBodyCaloriesNearOver(String avg, String target, int days);

  /// No description provided for @reportBodyCaloriesOk.
  ///
  /// In en, this message translates to:
  /// **'Calories averaged {avg}kcal a day — right around your {target}kcal target.'**
  String reportBodyCaloriesOk(String avg, String target);

  /// No description provided for @reportBodySugarOver.
  ///
  /// In en, this message translates to:
  /// **'Sugar averaged {avg}g a day and went over the {target}g limit on {days} days.'**
  String reportBodySugarOver(String avg, String target, int days);

  /// No description provided for @reportBodySugarOk.
  ///
  /// In en, this message translates to:
  /// **'Sugar averaged {avg}g a day, inside the {target}g limit.'**
  String reportBodySugarOk(String avg, String target);

  /// No description provided for @reportBodyMemberPain.
  ///
  /// In en, this message translates to:
  /// **'You mentioned pain in your {area}. Let me know how it feels before our next PT — I\'ll ease off that area.'**
  String reportBodyMemberPain(String area);

  /// No description provided for @reportBodyMemberTooHard.
  ///
  /// In en, this message translates to:
  /// **'You said the workouts felt too hard, so I\'ll drop next week\'s intensity a notch.'**
  String get reportBodyMemberTooHard;

  /// No description provided for @reportBodyMemberTooEasy.
  ///
  /// In en, this message translates to:
  /// **'You said the workouts felt easy, so I\'ll raise next week\'s intensity a notch.'**
  String get reportBodyMemberTooEasy;

  /// No description provided for @reportBodyMemberNoted.
  ///
  /// In en, this message translates to:
  /// **'Thanks for your weekly feedback — I read it.'**
  String get reportBodyMemberNoted;

  /// No description provided for @reportBodyNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Here\'s the plan for next week.'**
  String get reportBodyNextWeek;

  /// No description provided for @reportTipCaloriesOver.
  ///
  /// In en, this message translates to:
  /// **'Cut dinner carbs to about two-thirds and switch snacks to protein.'**
  String get reportTipCaloriesOver;

  /// No description provided for @reportTipCaloriesUnder.
  ///
  /// In en, this message translates to:
  /// **'Don\'t skip meals, and add one protein snack on workout days.'**
  String get reportTipCaloriesUnder;

  /// No description provided for @reportTipSugar.
  ///
  /// In en, this message translates to:
  /// **'Keep sweet drinks and desserts to once a day.'**
  String get reportTipSugar;

  /// No description provided for @reportTipSodium.
  ///
  /// In en, this message translates to:
  /// **'Keep takeout and processed foods to twice a week.'**
  String get reportTipSodium;

  /// No description provided for @reportTipWorkout.
  ///
  /// In en, this message translates to:
  /// **'Aim to get three workouts in first, even if each is only 20 minutes.'**
  String get reportTipWorkout;

  /// No description provided for @reportTipMeals.
  ///
  /// In en, this message translates to:
  /// **'Log every meal, even with just a photo, so I can give you sharper feedback.'**
  String get reportTipMeals;

  /// No description provided for @reportTipSessionsNone.
  ///
  /// In en, this message translates to:
  /// **'Let\'s book next week\'s PT together now.'**
  String get reportTipSessionsNone;

  /// No description provided for @reportTipSessionsMissed.
  ///
  /// In en, this message translates to:
  /// **'I\'ll set up make-up slots next week for the PT we missed.'**
  String get reportTipSessionsMissed;

  /// No description provided for @reportTipKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep the current routine as it is, and I\'ll raise the intensity step by step.'**
  String get reportTipKeep;

  /// No description provided for @schedTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedTitle;

  /// No description provided for @schedDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Session detail'**
  String get schedDetailTitle;

  /// No description provided for @schedDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete session'**
  String get schedDeleteTitle;

  /// No description provided for @schedDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}\'s {time} PT appointment?'**
  String schedDeleteConfirm(String time, String name);

  /// No description provided for @schedDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the session. Please try again'**
  String get schedDeleteFailed;

  /// No description provided for @schedCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete session'**
  String get schedCompleteTitle;

  /// No description provided for @schedCompleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Mark {name}\'s {time} PT as complete?'**
  String schedCompleteConfirm(String time, String name);

  /// No description provided for @schedCompleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t mark it complete. Please try again'**
  String get schedCompleteFailed;

  /// No description provided for @schedGroupProgram.
  ///
  /// In en, this message translates to:
  /// **'PT program'**
  String get schedGroupProgram;

  /// 담당이 끊긴 회원의 일정에 이름 대신 쓰는 말 (#2589)
  ///
  /// In en, this message translates to:
  /// **'Former client'**
  String get schedDetachedMember;

  /// No description provided for @schedDetachedMemberHint.
  ///
  /// In en, this message translates to:
  /// **'Coaching has ended, so client details are hidden'**
  String get schedDetachedMemberHint;

  /// Hint on a session card for a session the member booked through a reservation slot (#2756). Edit schedule and Delete are disabled.
  ///
  /// In en, this message translates to:
  /// **'Booked by the member. It can\'t be moved or deleted here; use Cancel to call it off.'**
  String get schedReservationLockedHint;

  /// No description provided for @schedEndedLockedHint.
  ///
  /// In en, this message translates to:
  /// **'A finished PT can only have its note and program edited.'**
  String get schedEndedLockedHint;

  /// No description provided for @schedDoneLockedHint.
  ///
  /// In en, this message translates to:
  /// **'A completed PT can only have its note and program edited. Move the date forward to reopen it as upcoming.'**
  String get schedDoneLockedHint;

  /// No description provided for @schedGroupPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal exercise'**
  String get schedGroupPersonal;

  /// No description provided for @schedRoutinesGoesOnComplete.
  ///
  /// In en, this message translates to:
  /// **'Goes to the member together with this PT\'s program.'**
  String get schedRoutinesGoesOnComplete;

  /// No description provided for @schedRoutinesNotSentYet.
  ///
  /// In en, this message translates to:
  /// **'Not sent to the member yet.'**
  String get schedRoutinesNotSentYet;

  /// No description provided for @schedRoutinesSendTitle.
  ///
  /// In en, this message translates to:
  /// **'Send the personal exercise?'**
  String get schedRoutinesSendTitle;

  /// No description provided for @schedEditRoutines.
  ///
  /// In en, this message translates to:
  /// **'Edit personal exercise'**
  String get schedEditRoutines;

  /// No description provided for @schedEditRoutinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit personal exercise'**
  String get schedEditRoutinesTitle;

  /// No description provided for @schedEditRoutinesBody.
  ///
  /// In en, this message translates to:
  /// **'This personal exercise goes out with the PT program. It has not been sent yet, so you can still change it freely.'**
  String get schedEditRoutinesBody;

  /// No description provided for @schedRoutinesSendBody.
  ///
  /// In en, this message translates to:
  /// **'This PT did not happen, but you can still send the personal exercise you composed. It shows in the member app every day for 7 days.'**
  String get schedRoutinesSendBody;

  /// No description provided for @schedRoutinesSend.
  ///
  /// In en, this message translates to:
  /// **'Send personal exercise'**
  String get schedRoutinesSend;

  /// No description provided for @schedRoutinesSkip.
  ///
  /// In en, this message translates to:
  /// **'Don\'t send'**
  String get schedRoutinesSkip;

  /// No description provided for @schedSendProgramWithRoutines.
  ///
  /// In en, this message translates to:
  /// **'Send the {date} PT program and personal exercise'**
  String schedSendProgramWithRoutines(String date);

  /// No description provided for @schedRoutineSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get schedRoutineSent;

  /// No description provided for @schedRoutinesSent.
  ///
  /// In en, this message translates to:
  /// **'Sent the personal exercise to the member.'**
  String get schedRoutinesSent;

  /// No description provided for @schedRoutinesSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the personal exercise. Please try again.'**
  String get schedRoutinesSendFailed;

  /// No description provided for @schedRoutinesSkipped.
  ///
  /// In en, this message translates to:
  /// **'Marked as not sent.'**
  String get schedRoutinesSkipped;

  /// No description provided for @schedRoutinesSkipFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t mark the personal exercise as not sent. Please try again.'**
  String get schedRoutinesSkipFailed;

  /// No description provided for @schedRoutinesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load personal exercises'**
  String get schedRoutinesLoadFailed;

  /// No description provided for @schedClientUnresolved.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t tell which member this session is for. Please pick the member.'**
  String get schedClientUnresolved;

  /// No description provided for @schedRoutinesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Personal exercise updated.'**
  String get schedRoutinesUpdated;

  /// No description provided for @schedRoutinesUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update the personal exercise. Please try again.'**
  String get schedRoutinesUpdateFailed;

  /// No description provided for @schedAddRoutines.
  ///
  /// In en, this message translates to:
  /// **'Add personal exercise'**
  String get schedAddRoutines;

  /// No description provided for @schedRoutinesAdded.
  ///
  /// In en, this message translates to:
  /// **'Personal exercise added.'**
  String get schedRoutinesAdded;

  /// No description provided for @schedNoRoutines.
  ///
  /// In en, this message translates to:
  /// **'No personal exercise'**
  String get schedNoRoutines;

  /// No description provided for @schedNoRoutinesSendTitle.
  ///
  /// In en, this message translates to:
  /// **'Send without personal exercise?'**
  String get schedNoRoutinesSendTitle;

  /// No description provided for @schedNoRoutinesSendBody.
  ///
  /// In en, this message translates to:
  /// **'This PT has no personal exercise. Once sent, you can no longer add personal exercise to this PT.'**
  String get schedNoRoutinesSendBody;

  /// No description provided for @schedNoRoutinesSendSkip.
  ///
  /// In en, this message translates to:
  /// **'Send without it'**
  String get schedNoRoutinesSendSkip;

  /// No description provided for @schedTimeRange.
  ///
  /// In en, this message translates to:
  /// **'{start}–{end}'**
  String schedTimeRange(String start, String end);

  /// No description provided for @schedEmptyWeek.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled this week.'**
  String get schedEmptyWeek;

  /// No description provided for @schedSlots.
  ///
  /// In en, this message translates to:
  /// **'Booking slots'**
  String get schedSlots;

  /// No description provided for @schedNewSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get schedNewSession;

  /// No description provided for @schedLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the schedule'**
  String get schedLoadFailed;

  /// No description provided for @schedEmptyDay.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled for this day.\nUse New session above to add one.'**
  String get schedEmptyDay;

  /// No description provided for @schedSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the session. Please try again'**
  String get schedSaveFailed;

  /// No description provided for @schedAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add a session'**
  String get schedAddTitle;

  /// No description provided for @schedEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit session'**
  String get schedEditTitle;

  /// No description provided for @schedFieldClient.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get schedFieldClient;

  /// No description provided for @schedFieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get schedFieldType;

  /// No description provided for @schedFieldDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get schedFieldDate;

  /// No description provided for @schedFieldDateRange.
  ///
  /// In en, this message translates to:
  /// **'Start - end date'**
  String get schedFieldDateRange;

  /// No description provided for @schedFieldTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get schedFieldTime;

  /// No description provided for @schedEndBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'End time must be after the start time'**
  String get schedEndBeforeStart;

  /// No description provided for @schedReopenTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch back to upcoming?'**
  String get schedReopenTitle;

  /// No description provided for @schedReopenBody.
  ///
  /// In en, this message translates to:
  /// **'Moving a completed PT forward switches it back to upcoming, and the workout log it created will be removed.'**
  String get schedReopenBody;

  /// No description provided for @schedReopenConfirm.
  ///
  /// In en, this message translates to:
  /// **'Switch to upcoming'**
  String get schedReopenConfirm;

  /// No description provided for @schedReopenPastBlocked.
  ///
  /// In en, this message translates to:
  /// **'A completed PT can only move to a future date'**
  String get schedReopenPastBlocked;

  /// No description provided for @schedTimeRangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Select time'**
  String get schedTimeRangeTitle;

  /// No description provided for @schedTimeRangeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get schedTimeRangeConfirm;

  /// No description provided for @schedTimePickerTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get schedTimePickerTimeLabel;

  /// No description provided for @schedTimePickerEndTime.
  ///
  /// In en, this message translates to:
  /// **'End time'**
  String get schedTimePickerEndTime;

  /// No description provided for @schedTimePickerHour.
  ///
  /// In en, this message translates to:
  /// **'Hour'**
  String get schedTimePickerHour;

  /// No description provided for @schedTimePickerMinute.
  ///
  /// In en, this message translates to:
  /// **'Minute'**
  String get schedTimePickerMinute;

  /// No description provided for @schedTimePickerStartHour.
  ///
  /// In en, this message translates to:
  /// **'Start hour'**
  String get schedTimePickerStartHour;

  /// No description provided for @schedTimePickerStartMinute.
  ///
  /// In en, this message translates to:
  /// **'Start minute'**
  String get schedTimePickerStartMinute;

  /// No description provided for @schedTimePickerEndHour.
  ///
  /// In en, this message translates to:
  /// **'End hour'**
  String get schedTimePickerEndHour;

  /// No description provided for @schedTimePickerEndMinute.
  ///
  /// In en, this message translates to:
  /// **'End minute'**
  String get schedTimePickerEndMinute;

  /// No description provided for @schedTimePickerPrevStep.
  ///
  /// In en, this message translates to:
  /// **'Previous step'**
  String get schedTimePickerPrevStep;

  /// No description provided for @schedTimePickerNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get schedTimePickerNextStep;

  /// No description provided for @schedTimePickerEndBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'End time is earlier than the start time'**
  String get schedTimePickerEndBeforeStart;

  /// No description provided for @schedClockHourSemantics.
  ///
  /// In en, this message translates to:
  /// **'{hour} o\'clock'**
  String schedClockHourSemantics(String hour);

  /// No description provided for @schedRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get schedRepeat;

  /// No description provided for @schedRepeatWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get schedRepeatWeekly;

  /// No description provided for @schedRepeatPreview.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions · {first} – {last}'**
  String schedRepeatPreview(int count, String first, String last);

  /// No description provided for @schedRepeatNeedsDays.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one weekday.'**
  String get schedRepeatNeedsDays;

  /// No description provided for @schedRepeatNeedsEndDate.
  ///
  /// In en, this message translates to:
  /// **'Pick an end date for the repeat.'**
  String get schedRepeatNeedsEndDate;

  /// No description provided for @schedRepeatConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} sessions clash'**
  String schedRepeatConflictTitle(int total, int count);

  /// No description provided for @schedRepeatConflictRow.
  ///
  /// In en, this message translates to:
  /// **'{date} {time} · already booked: {name}'**
  String schedRepeatConflictRow(String date, String time, String name);

  /// No description provided for @schedRepeatConflictHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing was created. Change the time, or clear the sessions that clash.'**
  String get schedRepeatConflictHint;

  /// No description provided for @schedOverlapTitle.
  ///
  /// In en, this message translates to:
  /// **'This time overlaps another session'**
  String get schedOverlapTitle;

  /// No description provided for @schedOverlapHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing was saved. Change the time or move the overlapping session, then save again.'**
  String get schedOverlapHint;

  /// No description provided for @slotOverlapHint.
  ///
  /// In en, this message translates to:
  /// **'The slot wasn\'t opened. Pick another time or move the overlapping session.'**
  String get slotOverlapHint;

  /// No description provided for @consultOverlapHint.
  ///
  /// In en, this message translates to:
  /// **'The member\'s chosen time is already booked, so the request wasn\'t approved. Move the overlapping session, then approve again.'**
  String get consultOverlapHint;

  /// No description provided for @schedNote.
  ///
  /// In en, this message translates to:
  /// **'Trainer feedback'**
  String get schedNote;

  /// No description provided for @schedEditNote.
  ///
  /// In en, this message translates to:
  /// **'Edit feedback'**
  String get schedEditNote;

  /// No description provided for @schedAddNote.
  ///
  /// In en, this message translates to:
  /// **'Add feedback'**
  String get schedAddNote;

  /// No description provided for @schedNoNote.
  ///
  /// In en, this message translates to:
  /// **'No memo yet'**
  String get schedNoNote;

  /// No description provided for @schedNoteOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'A consultation is recorded as a memo, not a program.'**
  String get schedNoteOnlyHint;

  /// No description provided for @schedNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Feedback for the member. Keep member notes in the client memo'**
  String get schedNoteHint;

  /// No description provided for @schedNoteVisibleToMember.
  ///
  /// In en, this message translates to:
  /// **'Shown to the member as feedback once the PT is done'**
  String get schedNoteVisibleToMember;

  /// No description provided for @schedConsultNote.
  ///
  /// In en, this message translates to:
  /// **'Consultation memo'**
  String get schedConsultNote;

  /// No description provided for @schedEditConsultNote.
  ///
  /// In en, this message translates to:
  /// **'Edit memo'**
  String get schedEditConsultNote;

  /// No description provided for @schedAddConsultNote.
  ///
  /// In en, this message translates to:
  /// **'Add memo'**
  String get schedAddConsultNote;

  /// No description provided for @schedConsultNoteHint.
  ///
  /// In en, this message translates to:
  /// **'What you talked about in the consultation'**
  String get schedConsultNoteHint;

  /// No description provided for @schedConsultNotePrivate.
  ///
  /// In en, this message translates to:
  /// **'Only you can see this memo. It\'s hidden from the member.'**
  String get schedConsultNotePrivate;

  /// No description provided for @schedAddAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get schedAddAction;

  /// No description provided for @schedSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get schedSaveAction;

  /// No description provided for @progInvalid.
  ///
  /// In en, this message translates to:
  /// **'Check the exercise name and set count'**
  String get progInvalid;

  /// No description provided for @progSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the program. Please try again'**
  String get progSaveFailed;

  /// No description provided for @progEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit program'**
  String get progEditTitle;

  /// No description provided for @progAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add program'**
  String get progAddTitle;

  /// No description provided for @progAddExercise.
  ///
  /// In en, this message translates to:
  /// **'Add exercise'**
  String get progAddExercise;

  /// No description provided for @progNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Feedback for the member. Keep member notes in the client memo'**
  String get progNoteHint;

  /// No description provided for @progSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get progSaving;

  /// No description provided for @progSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get progSaveAction;

  /// No description provided for @progSaveNoteAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get progSaveNoteAction;

  /// No description provided for @progExerciseName.
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get progExerciseName;

  /// No description provided for @progDeleteExercise.
  ///
  /// In en, this message translates to:
  /// **'Remove exercise'**
  String get progDeleteExercise;

  /// No description provided for @progSetsValue.
  ///
  /// In en, this message translates to:
  /// **'{sets, plural, =1{1 set} other{{sets} sets}}'**
  String progSetsValue(int sets);

  /// No description provided for @progHoldValue.
  ///
  /// In en, this message translates to:
  /// **'{seconds} sec'**
  String progHoldValue(int seconds);

  /// No description provided for @progRepsValue.
  ///
  /// In en, this message translates to:
  /// **'{reps, plural, =1{1 rep} other{{reps} reps}}'**
  String progRepsValue(int reps);

  /// No description provided for @progEmpty.
  ///
  /// In en, this message translates to:
  /// **'No program planned yet'**
  String get progEmpty;

  /// No description provided for @progEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Build one in the AI suggestions tab, or agree on it over chat first.'**
  String get progEmptyHint;

  /// No description provided for @schedSentTo.
  ///
  /// In en, this message translates to:
  /// **'Sent to {name}'**
  String schedSentTo(String name);

  /// No description provided for @schedSentProgramTo.
  ///
  /// In en, this message translates to:
  /// **'Send the {date} PT program'**
  String schedSentProgramTo(String date);

  /// No description provided for @slotPastTime.
  ///
  /// In en, this message translates to:
  /// **'Booking slots can only be opened for future times.'**
  String get slotPastTime;

  /// No description provided for @slotOpened.
  ///
  /// In en, this message translates to:
  /// **'Booking slot opened.'**
  String get slotOpened;

  /// No description provided for @slotStartTime.
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get slotStartTime;

  /// No description provided for @slotCloseTitle.
  ///
  /// In en, this message translates to:
  /// **'Close booking slot'**
  String get slotCloseTitle;

  /// No description provided for @slotCloseBody.
  ///
  /// In en, this message translates to:
  /// **'Any existing booking stays; only new bookings stop.'**
  String get slotCloseBody;

  /// No description provided for @slotClosed.
  ///
  /// In en, this message translates to:
  /// **'New bookings closed.'**
  String get slotClosed;

  /// No description provided for @slotActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete the request. Please try again in a moment.'**
  String get slotActionFailed;

  /// No description provided for @slotManageTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage booking slots'**
  String get slotManageTitle;

  /// No description provided for @slotIntro.
  ///
  /// In en, this message translates to:
  /// **'Open times for members to book. Every upcoming slot is listed below by date.'**
  String get slotIntro;

  /// No description provided for @slotOpenAction.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get slotOpenAction;

  /// No description provided for @slotReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get slotReload;

  /// No description provided for @slotLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load reservation slots'**
  String get slotLoadFailed;

  /// No description provided for @slotEmpty.
  ///
  /// In en, this message translates to:
  /// **'No booking slots are open.'**
  String get slotEmpty;

  /// No description provided for @slotClosedSummary.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get slotClosedSummary;

  /// No description provided for @slotBookedSummary.
  ///
  /// In en, this message translates to:
  /// **'Booked'**
  String get slotBookedSummary;

  /// No description provided for @slotOverlappedSummary.
  ///
  /// In en, this message translates to:
  /// **'Overlaps a session'**
  String get slotOverlappedSummary;

  /// No description provided for @slotOverlappedHint.
  ///
  /// In en, this message translates to:
  /// **'Another session is booked at this time, so members see it as full. Close it if you will not use it.'**
  String get slotOverlappedHint;

  /// No description provided for @slotCloseAction.
  ///
  /// In en, this message translates to:
  /// **'Close bookings'**
  String get slotCloseAction;

  /// No description provided for @myCareerInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter years of experience between 0 and 80.'**
  String get myCareerInvalid;

  /// No description provided for @myProfileSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your profile.'**
  String get myProfileSaveFailed;

  /// No description provided for @myGymChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change your gym. The rest of your profile was saved.'**
  String get myGymChangeFailed;

  /// No description provided for @myTabProfile.
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get myTabProfile;

  /// No description provided for @myTabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get myTabSettings;

  /// No description provided for @mySaving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get mySaving;

  /// No description provided for @myEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get myEditProfile;

  /// No description provided for @mySaved.
  ///
  /// In en, this message translates to:
  /// **'Changes saved'**
  String get mySaved;

  /// No description provided for @myCertifications.
  ///
  /// In en, this message translates to:
  /// **'Certifications'**
  String get myCertifications;

  /// No description provided for @myGym.
  ///
  /// In en, this message translates to:
  /// **'My gym'**
  String get myGym;

  /// No description provided for @myNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get myNotifications;

  /// No description provided for @myNotifNewMessage.
  ///
  /// In en, this message translates to:
  /// **'New message alerts'**
  String get myNotifNewMessage;

  /// No description provided for @myNotifNotReady.
  ///
  /// In en, this message translates to:
  /// **'Coming soon — always on for now'**
  String get myNotifNotReady;

  /// Notification settings card row shown while the saved settings are loading; switches stay disabled.
  ///
  /// In en, this message translates to:
  /// **'Loading notification settings…'**
  String get myNotifLoading;

  /// Notification settings card row when loading the saved settings failed; shown with a retry button and switches stay disabled.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load notification settings. Please try again'**
  String get myNotifLoadFailed;

  /// No description provided for @myNotifNewMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Get an inbox alert and a sidebar count when a member messages you'**
  String get myNotifNewMessageHint;

  /// No description provided for @myLanguageApp.
  ///
  /// In en, this message translates to:
  /// **'Display language'**
  String get myLanguageApp;

  /// No description provided for @myLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'Your choice is saved in this browser only. Other devices follow their own browser setting.'**
  String get myLanguageHint;

  /// No description provided for @myLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'Match browser'**
  String get myLanguageSystem;

  /// Korean, written in Korean so it can be found from either language.
  ///
  /// In en, this message translates to:
  /// **'한국어'**
  String get myLanguageKorean;

  /// English, written in English so it can be found from either language.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get myLanguageEnglish;

  /// No description provided for @myAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get myAccount;

  /// No description provided for @myChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get myChangePassword;

  /// No description provided for @myChangePasswordHint.
  ///
  /// In en, this message translates to:
  /// **'We\'ll confirm your current password first'**
  String get myChangePasswordHint;

  /// No description provided for @myChangePasswordDemo.
  ///
  /// In en, this message translates to:
  /// **'Demo mode has no account, so this is unavailable'**
  String get myChangePasswordDemo;

  /// No description provided for @myLoginAccount.
  ///
  /// In en, this message translates to:
  /// **'Signed in as'**
  String get myLoginAccount;

  /// No description provided for @mySupportTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer Support'**
  String get mySupportTitle;

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

  /// No description provided for @mySupportExternalHint.
  ///
  /// In en, this message translates to:
  /// **'Opens the KakaoTalk channel'**
  String get mySupportExternalHint;

  /// No description provided for @mySupportOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link. Please try again in a moment'**
  String get mySupportOpenFailed;

  /// No description provided for @myAppVersion.
  ///
  /// In en, this message translates to:
  /// **'On-Care Trainer · Version {version}'**
  String myAppVersion(String version);

  /// No description provided for @myAppName.
  ///
  /// In en, this message translates to:
  /// **'On-Care Trainer'**
  String get myAppName;

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

  /// No description provided for @myLegalTermsEffectiveDate.
  ///
  /// In en, this message translates to:
  /// **'Effective Oct 1, 2026'**
  String get myLegalTermsEffectiveDate;

  /// No description provided for @myLegalPrivacyEffectiveDate.
  ///
  /// In en, this message translates to:
  /// **'Effective Oct 3, 2026'**
  String get myLegalPrivacyEffectiveDate;

  /// No description provided for @myLegalTermsBody.
  ///
  /// In en, this message translates to:
  /// **'This English text is provided for convenience; the Korean original governs.\n\n1. Purpose\nThese terms govern the rights, obligations and responsibilities between On-Care (the \"Company\") and trainers using the On-Care trainer console (the \"Service\").\n\n2. Effect and amendment\nThese terms apply to every trainer using the Service. The Company may amend them within the limits of applicable law, announcing the effective date and the reason inside the Service.\n\n3. The Service\nThe Company provides member management, access to diet and workout records, scheduling, messaging, AI coaching programs, and report writing and delivery. The details may change with Company policy.\n\n4. Accounts\nTrainer accounts and member accounts are separate; one account cannot be used for both. Trainers must enter certification and career details truthfully and are responsible for keeping their credentials safe.\n\n5. Handling member information\nTrainers may open the diet, workout and health records only of members they are assigned to. Those records may be used solely for coaching, consultation and reports, and must never be published or handed to a third party. When an assignment ends, the access ends with it.\n\n6. Prohibited conduct\nTrainers must not make medical diagnoses or prescriptions, and must not move member information outside the Service without that member\'s consent.\n\n7. Limitation of liability\nAI coaching output and statistics are reference material. The final judgement about the guidance given to a member rests with the trainer, and the Company bears no liability for that outcome to the extent permitted by law.\n\n8. Termination\nA trainer may delete their account at any time. Doing so ends their member assignments and upcoming sessions, and the affected members are notified.\n\nAddendum\nThese terms take effect on October 1, 2026.'**
  String get myLegalTermsBody;

  /// No description provided for @myLegalPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'This English text is provided for convenience; the Korean original governs.\n\n1. Information collected\n(1) Trainer sign-up: email, password (stored encrypted), name and phone number.\n(2) Profile and credential check: gym affiliation, certifications, career, speciality and other profile details.\n(3) Information you leave while using the Service: messages and attached photos sent to members, reports and coaching content, schedules and bookings, and member notes.\n(4) Information generated automatically: access logs such as sign-ins and password changes (time and IP address), and, when an error occurs, the error details, browser and operating system type and app version.\n\n2. Purpose of collection and use\nThe information is used only to identify trainers and to let an operator check their gym affiliation and credentials (trainers are not shown to members until approved), to connect them with assigned members, to provide scheduling, messaging and reports, and to improve the service and answer enquiries.\n\n3. Access to and processing of member information\nA trainer may open the diet, workout and body-weight records of members they are assigned to, inside the Service. The Company is the controller of those records; the trainer processes them only for coaching and reports, within the scope the Company sets. Members\' health information is sensitive information and can be opened only with the member\'s separate consent and data-sharing consent. Reports and messages a trainer sends are delivered to that member and kept in the Service as a record. When an assignment ends, the trainer\'s access is revoked immediately, and a member may withdraw consent to share their information at any time.\n\n4. Retention\nA trainer\'s personal information is kept until account deletion, and is then destroyed without delay following section 8. The following records are kept for the stated period and then destroyed.\n- Access logs such as sign-ins: one year (covering the three-month retention of sign-in records required by the Protection of Communications Secrets Act)\n- Records of trainers opening members\' health information, of consent being given or withdrawn, and of account deletion: two years (processing records kept under the Standards for Personal Information Security Measures)\nReports and messages already delivered belong to the member\'s record and follow the member\'s retention period.\n\n5. Provision to third parties\nThe Company does not provide personal information to outside parties without consent. Processing entrusted to service providers follows sections 6 and 7. The exception is where the law specifically requires it.\n\n6. Entrusted processing\nThe Company entrusts the following work to outside providers to deliver the Service. If a provider changes, this policy is updated to say so.\n- Amazon Web Services, Inc.: running the servers and storing chat photos and report PDFs\n- Neon: running the database (account information and all records)\n- Google LLC: generating AI coaching programs, routine suggestions and report summaries (Gemini API)\n- Kakao Corp.: gym search and map display\n- Functional Software, Inc. (Sentry): collecting and analysing web and server errors\n\n7. Transfer of personal information overseas\nTo perform its contract with trainers, the Company has personal information processed and stored overseas as follows, and discloses this in this policy under Article 28-8(1)(3) of the Personal Information Protection Act. Each transfer happens over an encrypted network connection whenever the Service is used.\n(1) Amazon Web Services, Inc. / Singapore / trainer information and records in general, chat photo attachments and report PDFs / running the servers and storing files / until account deletion or the end of the contract with the provider\n(2) Neon / Singapore / account and profile, message, report and schedule records / running the database / until account deletion or the end of the contract with the provider\n(3) Google LLC / the United States and other countries where Google operates data centres / coaching conditions entered when using AI features, and assigned members\' workout records and weekly report figures / generating AI programs and summaries / for the period set in the provider\'s terms of service after the request is processed\n(4) Functional Software, Inc. (Sentry) / the United States / error details, browser and operating system type and app version (name, email address, IP address and request contents are not sent) / error analysis / the provider\'s retention period\nIf you do not want your information transferred overseas, you can refuse by deleting your account, but you will then be unable to use the Service.\n\n8. Destruction procedure and method\n(1) Procedure: when a trainer deletes their account, the Company immediately deletes the account together with the profile, member connections and conversations (including attached photos and report PDF files), routines and programs, schedules and bookable times, and notifications, and tells assigned and booked members. Consultation requests sent by members belong to the members\' records and remain with the trainer\'s details removed. Records kept under section 4 are deleted automatically when their period ends.\n(2) Method: information held as electronic files is deleted from the database and file storage, and copies remaining in database recovery backups disappear when the backup retention period ends. The Company does not handle personal information on paper.\n\n9. Automatic collection tools\nThe Company does not use cookies or tracking tools for advertising or behavioural analysis. Sign-in information is kept in browser storage to keep you signed in, and is removed when you sign out or clear your browser data.\n\n10. Safeguards\nPasswords are stored encrypted, access to member information is limited by assignment, and traffic is encrypted in transit. An access record holds only the trainer, the member, the kind of information and the time, never the health information itself. Error reports are sent with names, email addresses, IP addresses and request contents removed.\n\n11. Children under 14\nThe Company does not accept sign-ups from children under 14, and confirms at sign-up that you are 14 or older.\n\n12. Your rights\nA trainer may review or correct their personal information, or request that its processing stop and that it be deleted, at any time. You can edit your profile and delete your account from the MY menu; for any other request, contact the address in section 13 and it will be handled without delay.\n\n13. Privacy officer\nThe Company has appointed a personal information protection officer who oversees the processing of personal information and handles related complaints and remedies.\n- Position: Personal information protection officer, On-Care service operations team\n- Contact: support@oncare.com\n\n14. Remedies for infringement\nFor reports or advice about an infringement of personal information, you can contact the following bodies (in Korea).\n- Personal Information Dispute Mediation Committee: 1833-6972 (www.kopico.go.kr)\n- Personal Information Infringement Report Center: 118 (privacy.kisa.or.kr)\n- Supreme Prosecutors\' Office: 1301 (www.spo.go.kr)\n- Korean National Police Agency: 182 (ecrm.police.go.kr)\n\n15. Changes to this policy\nIf this policy changes, the Company announces it in the Service before the effective date, and asks for consent again where the change requires it.\n- October 3, 2026: added entrusted processing, overseas transfer, destruction procedure, automatic collection tools, children under 14, protection officer and remedies sections\n- October 1, 2026: first issued\n\nEffective: October 3, 2026'**
  String get myLegalPrivacyBody;

  /// No description provided for @myPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get myPasswordChanged;

  /// Career tag on the trainer profile. The value is stored as a number of years.
  ///
  /// In en, this message translates to:
  /// **'{years, plural, =1{1 year} other{{years} years}} of experience'**
  String myCareerYears(int years);

  /// Career value under the 경력 label — the label already says it is career, so only the years.
  ///
  /// In en, this message translates to:
  /// **'{years, plural, =1{1 year} other{{years} years}}'**
  String myCareerYearsValue(int years);

  /// No description provided for @myFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name (account)'**
  String get myFieldName;

  /// No description provided for @myFieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email (account)'**
  String get myFieldEmail;

  /// No description provided for @myFieldPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get myFieldPhone;

  /// No description provided for @myFieldSpecialty.
  ///
  /// In en, this message translates to:
  /// **'Specialty'**
  String get myFieldSpecialty;

  /// No description provided for @myFieldCareer.
  ///
  /// In en, this message translates to:
  /// **'Experience'**
  String get myFieldCareer;

  /// No description provided for @myFieldIntro.
  ///
  /// In en, this message translates to:
  /// **'About me'**
  String get myFieldIntro;

  /// No description provided for @myAddCertification.
  ///
  /// In en, this message translates to:
  /// **'Add a certification...'**
  String get myAddCertification;

  /// No description provided for @myAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get myAdd;

  /// No description provided for @myStatClients.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get myStatClients;

  /// No description provided for @myClientManagement.
  ///
  /// In en, this message translates to:
  /// **'Member management'**
  String get myClientManagement;

  /// No description provided for @myClientRemove.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get myClientRemove;

  /// No description provided for @myClientRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect from {name}?'**
  String myClientRemoveTitle(String name);

  /// No description provided for @myClientRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'After you disconnect, this member\'s schedules, programs and routines, reports, messages, and notes won\'t show in the trainer app. Their account and member app records stay as they are.'**
  String get myClientRemoveBody;

  /// No description provided for @myClientRemoveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Disconnected from the member'**
  String get myClientRemoveSuccess;

  /// No description provided for @myClientRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t disconnect. Please try again'**
  String get myClientRemoveFailed;

  /// No description provided for @myClientManagementEmpty.
  ///
  /// In en, this message translates to:
  /// **'No members assigned'**
  String get myClientManagementEmpty;

  /// No description provided for @myClientManagementSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search members by name'**
  String get myClientManagementSearchHint;

  /// No description provided for @myBasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic info'**
  String get myBasicInfo;

  /// No description provided for @myStatSessionsDone.
  ///
  /// In en, this message translates to:
  /// **'PT done'**
  String get myStatSessionsDone;

  /// No description provided for @myStatRoutinesSent.
  ///
  /// In en, this message translates to:
  /// **'Programs sent'**
  String get myStatRoutinesSent;

  /// No description provided for @myGymName.
  ///
  /// In en, this message translates to:
  /// **'Gym name'**
  String get myGymName;

  /// No description provided for @myGymAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get myGymAddress;

  /// No description provided for @myGymHours.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get myGymHours;

  /// No description provided for @myGymRequired.
  ///
  /// In en, this message translates to:
  /// **'Pick your gym from the search results'**
  String get myGymRequired;

  /// No description provided for @myGymSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Find your gym'**
  String get myGymSearchLabel;

  /// No description provided for @myGymSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Gym name or address'**
  String get myGymSearchHint;

  /// No description provided for @myGymSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get myGymSearching;

  /// No description provided for @myGymSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No gyms found. Try a different name or add the neighborhood.'**
  String get myGymSearchEmpty;

  /// No description provided for @myGymSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t search gyms. Please try again in a moment.'**
  String get myGymSearchFailed;

  /// No description provided for @myGymCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current gym'**
  String get myGymCurrent;

  /// No description provided for @myGymPicked.
  ///
  /// In en, this message translates to:
  /// **'Saving will switch you to this gym'**
  String get myGymPicked;

  /// No description provided for @myGymNone.
  ///
  /// In en, this message translates to:
  /// **'None yet'**
  String get myGymNone;

  /// No description provided for @myGymHiddenTitle.
  ///
  /// In en, this message translates to:
  /// **'Members can\'t find you yet'**
  String get myGymHiddenTitle;

  /// No description provided for @myGymHiddenBody.
  ///
  /// In en, this message translates to:
  /// **'Set your gym to appear in the member app\'s gym finder and consultation requests.'**
  String get myGymHiddenBody;

  /// No description provided for @myGymHiddenAction.
  ///
  /// In en, this message translates to:
  /// **'Set gym'**
  String get myGymHiddenAction;

  /// No description provided for @verifyPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get verifyPendingTitle;

  /// No description provided for @verifyPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Until an operator approves your account, you won\'t appear in the member app\'s trainer finder and can\'t receive consultation requests or connect members. Fill in your profile and gym meanwhile — they\'re used for the review.'**
  String get verifyPendingBody;

  /// No description provided for @verifyRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your approval was declined'**
  String get verifyRejectedTitle;

  /// No description provided for @verifyRejectedBody.
  ///
  /// In en, this message translates to:
  /// **'You don\'t appear in the member app and can\'t receive consultation requests or connect members. Update your profile, then ask support to review it again.'**
  String get verifyRejectedBody;

  /// No description provided for @verifyRejectedReason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String verifyRejectedReason(String reason);

  /// No description provided for @verifyConnectDisabled.
  ///
  /// In en, this message translates to:
  /// **'You can connect members once an operator approves your account. New member registration is off until then.'**
  String get verifyConnectDisabled;

  /// No description provided for @verifyConsultDisabled.
  ///
  /// In en, this message translates to:
  /// **'Members can request consultations once an operator approves your account.'**
  String get verifyConsultDisabled;

  /// No description provided for @myGymEditHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name and pick your gym. Members find you through this gym.'**
  String get myGymEditHint;

  /// No description provided for @mySignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get mySignOut;

  /// No description provided for @myPwCurrentRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password'**
  String get myPwCurrentRequired;

  /// No description provided for @myPwMismatch.
  ///
  /// In en, this message translates to:
  /// **'The new passwords don\'t match'**
  String get myPwMismatch;

  /// No description provided for @myPwChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change your password'**
  String get myPwChangeFailed;

  /// No description provided for @myPwChangeRetry.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t work. Please try again in a moment'**
  String get myPwChangeRetry;

  /// No description provided for @myPwCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get myPwCurrent;

  /// No description provided for @myPwNew.
  ///
  /// In en, this message translates to:
  /// **'New password ({min}+ characters, letters and numbers)'**
  String myPwNew(int min);

  /// No description provided for @myPwConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get myPwConfirm;

  /// No description provided for @myPwChanging.
  ///
  /// In en, this message translates to:
  /// **'Changing…'**
  String get myPwChanging;

  /// No description provided for @mySettingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your settings. Please try again in a moment'**
  String get mySettingsSaveFailed;

  /// No description provided for @myProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How members see you, and this month\'s activity'**
  String get myProfileSubtitle;

  /// No description provided for @myClientsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tidy up your member connections'**
  String get myClientsSubtitle;

  /// No description provided for @myLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the console language'**
  String get myLanguageSubtitle;

  /// No description provided for @myAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your sign-in account and password'**
  String get myAccountSubtitle;

  /// No description provided for @mySupportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ask a question or read our policies'**
  String get mySupportSubtitle;

  /// No description provided for @myWithdrawSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Please check once before you leave'**
  String get myWithdrawSubtitle;

  /// No description provided for @myPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile & settings'**
  String get myPageTitle;

  /// No description provided for @myProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get myProfileTitle;

  /// No description provided for @myEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get myEmail;

  /// No description provided for @myBasicInfoHint.
  ///
  /// In en, this message translates to:
  /// **'Members see this on your trainer profile'**
  String get myBasicInfoHint;

  /// No description provided for @myNotificationsHint.
  ///
  /// In en, this message translates to:
  /// **'Choose which alerts you get'**
  String get myNotificationsHint;

  /// No description provided for @myAccountInfo.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get myAccountInfo;

  /// No description provided for @myAccountInfoHint.
  ///
  /// In en, this message translates to:
  /// **'To change your name or email, contact support.'**
  String get myAccountInfoHint;

  /// No description provided for @mySecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get mySecurity;

  /// No description provided for @myDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop editing?'**
  String get myDiscardTitle;

  /// No description provided for @myDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'Your changes won\'t be saved.'**
  String get myDiscardBody;

  /// No description provided for @myKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get myKeepEditing;

  /// No description provided for @myDiscardAction.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get myDiscardAction;

  /// No description provided for @mySignOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Log out of this browser?'**
  String get mySignOutConfirm;

  /// No description provided for @myThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get myThisMonth;

  /// No description provided for @myIntroEmpty.
  ///
  /// In en, this message translates to:
  /// **'No introduction yet. Add one in Edit profile — members see it.'**
  String get myIntroEmpty;

  /// No description provided for @myCertsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No certifications yet'**
  String get myCertsEmpty;

  /// No description provided for @myGymEmpty.
  ///
  /// In en, this message translates to:
  /// **'No gym yet. Set yours in Edit profile.'**
  String get myGymEmpty;

  /// No description provided for @myEditVisibleBody.
  ///
  /// In en, this message translates to:
  /// **'Your specialty, career, introduction, certifications and gym appear on your trainer profile in the member app.'**
  String get myEditVisibleBody;

  /// No description provided for @myClientManagementNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting keeps member records'**
  String get myClientManagementNoteTitle;

  /// No description provided for @myClientManagementNote.
  ///
  /// In en, this message translates to:
  /// **'Their records stay in the member app. To coach them again, add them by member ID from New member on the Members tab.'**
  String get myClientManagementNote;

  /// No description provided for @myNotifConsultation.
  ///
  /// In en, this message translates to:
  /// **'Consultation requests'**
  String get myNotifConsultation;

  /// No description provided for @myNotifConsultationHint.
  ///
  /// In en, this message translates to:
  /// **'When a member requests a consultation or answers your invite'**
  String get myNotifConsultationHint;

  /// No description provided for @myNotifReservation.
  ///
  /// In en, this message translates to:
  /// **'Bookings'**
  String get myNotifReservation;

  /// No description provided for @myNotifReservationHint.
  ///
  /// In en, this message translates to:
  /// **'When a member books or changes a session'**
  String get myNotifReservationHint;

  /// No description provided for @myNotifMemberUpdates.
  ///
  /// In en, this message translates to:
  /// **'Member updates'**
  String get myNotifMemberUpdates;

  /// No description provided for @myNotifMemberUpdatesHint.
  ///
  /// In en, this message translates to:
  /// **'When a member changes goals or name, or disconnects'**
  String get myNotifMemberUpdatesHint;

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

  /// No description provided for @routineTypeFlexibility.
  ///
  /// In en, this message translates to:
  /// **'Stretching'**
  String get routineTypeFlexibility;

  /// No description provided for @routineTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get routineTypeOther;

  /// No description provided for @routineFieldType.
  ///
  /// In en, this message translates to:
  /// **'Exercise type'**
  String get routineFieldType;

  /// No description provided for @routineFieldMinutes.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get routineFieldMinutes;

  /// No description provided for @routineFieldTotalMinutes.
  ///
  /// In en, this message translates to:
  /// **'Total workout time'**
  String get routineFieldTotalMinutes;

  /// No description provided for @routineFieldIntensity.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get routineFieldIntensity;

  /// No description provided for @routineFieldDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get routineFieldDate;

  /// No description provided for @routineFieldExerciseName.
  ///
  /// In en, this message translates to:
  /// **'Exercise name'**
  String get routineFieldExerciseName;

  /// No description provided for @routineFieldExerciseNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Squat, Treadmill'**
  String get routineFieldExerciseNameHint;

  /// No description provided for @routineFieldExerciseNameHintCardio.
  ///
  /// In en, this message translates to:
  /// **'e.g. Treadmill, Indoor cycling'**
  String get routineFieldExerciseNameHintCardio;

  /// No description provided for @routineFieldExerciseNameHintStrength.
  ///
  /// In en, this message translates to:
  /// **'e.g. Squat, Bench press'**
  String get routineFieldExerciseNameHintStrength;

  /// No description provided for @routineFieldExerciseNameHintFlexibility.
  ///
  /// In en, this message translates to:
  /// **'e.g. Full-body stretch, Yoga'**
  String get routineFieldExerciseNameHintFlexibility;

  /// No description provided for @routineFieldExerciseNameHintOther.
  ///
  /// In en, this message translates to:
  /// **'e.g. Rehab exercise, Sports activity'**
  String get routineFieldExerciseNameHintOther;

  /// Label of the one-line benefit field on a personal routine row. Left empty, the auto-filled benefit (shown as the placeholder) is sent (#2570).
  ///
  /// In en, this message translates to:
  /// **'Benefit shown to member'**
  String get routineFieldEffect;

  /// No description provided for @routineFieldEffectHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Protect right shoulder'**
  String get routineFieldEffectHint;

  /// No description provided for @routineFieldSets.
  ///
  /// In en, this message translates to:
  /// **'Sets'**
  String get routineFieldSets;

  /// No description provided for @routineFieldReps.
  ///
  /// In en, this message translates to:
  /// **'Reps'**
  String get routineFieldReps;

  /// No description provided for @routineFieldHold.
  ///
  /// In en, this message translates to:
  /// **'Hold time'**
  String get routineFieldHold;

  /// No description provided for @routineFieldMeasure.
  ///
  /// In en, this message translates to:
  /// **'Measured in'**
  String get routineFieldMeasure;

  /// No description provided for @routineFieldWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get routineFieldWeight;

  /// No description provided for @routineFieldCalories.
  ///
  /// In en, this message translates to:
  /// **'Estimated calories'**
  String get routineFieldCalories;

  /// No description provided for @routineCaloriesNeedName.
  ///
  /// In en, this message translates to:
  /// **'Enter an exercise name'**
  String get routineCaloriesNeedName;

  /// No description provided for @routineCaloriesRoughEstimate.
  ///
  /// In en, this message translates to:
  /// **'A rough average for this exercise type · the saved record will also use the member\'s weight'**
  String get routineCaloriesRoughEstimate;

  /// No description provided for @routineUnitHours.
  ///
  /// In en, this message translates to:
  /// **'hr'**
  String get routineUnitHours;

  /// No description provided for @routineUnitMinutes.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get routineUnitMinutes;

  /// No description provided for @routineUnitSets.
  ///
  /// In en, this message translates to:
  /// **'sets'**
  String get routineUnitSets;

  /// No description provided for @routineUnitReps.
  ///
  /// In en, this message translates to:
  /// **'reps'**
  String get routineUnitReps;

  /// No description provided for @routineUnitSeconds.
  ///
  /// In en, this message translates to:
  /// **'sec'**
  String get routineUnitSeconds;

  /// No description provided for @routineUnitKg.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get routineUnitKg;

  /// No description provided for @routineKcalValue.
  ///
  /// In en, this message translates to:
  /// **'{count} kcal'**
  String routineKcalValue(int count);

  /// No description provided for @intensityLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get intensityLight;

  /// No description provided for @intensityModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get intensityModerate;

  /// No description provided for @intensityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get intensityHigh;

  /// No description provided for @coachTitle.
  ///
  /// In en, this message translates to:
  /// **'Programs'**
  String get coachTitle;

  /// No description provided for @coachSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create, assign, and manage exercise programs for each member'**
  String get coachSubtitle;

  /// No description provided for @coachSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send. Please try again'**
  String get coachSendFailed;

  /// No description provided for @coachSwitchClientTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to another client?'**
  String get coachSwitchClientTitle;

  /// No description provided for @coachSwitchClientBody.
  ///
  /// In en, this message translates to:
  /// **'You have unsent work. Switching clients discards the program and personal exercises you are building.'**
  String get coachSwitchClientBody;

  /// No description provided for @coachSwitchClientConfirm.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get coachSwitchClientConfirm;

  /// No description provided for @coachDraftResumeTitle.
  ///
  /// In en, this message translates to:
  /// **'You have saved work'**
  String get coachDraftResumeTitle;

  /// Body of the coaching screen's resume prompt for an autosaved draft.
  ///
  /// In en, this message translates to:
  /// **'The program you were building for {name} was saved automatically. Continue where you left off?'**
  String coachDraftResumeBody(String name);

  /// No description provided for @coachDraftResume.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get coachDraftResume;

  /// No description provided for @coachDraftDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get coachDraftDiscard;

  /// No description provided for @personalRoutineTargetLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load PT appointments'**
  String get personalRoutineTargetLoadFailed;

  /// No description provided for @personalRoutineStartPast.
  ///
  /// In en, this message translates to:
  /// **'The start date has passed, so it\'s now set to today. Check it and send again'**
  String get personalRoutineStartPast;

  /// No description provided for @schedRoutinesReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check the attached personal exercises. Please try again'**
  String get schedRoutinesReadFailed;

  /// No description provided for @coachNoClients.
  ///
  /// In en, this message translates to:
  /// **'No members yet'**
  String get coachNoClients;

  /// No description provided for @coachTrainerAdded.
  ///
  /// In en, this message translates to:
  /// **'Added by trainer'**
  String get coachTrainerAdded;

  /// No description provided for @coachTemplateAdded.
  ///
  /// In en, this message translates to:
  /// **'Added from {name} template'**
  String coachTemplateAdded(String name);

  /// No description provided for @coachRegisteredOn.
  ///
  /// In en, this message translates to:
  /// **'Added to the {date} schedule'**
  String coachRegisteredOn(String date);

  /// No description provided for @coachRegisteredAttachedExisting.
  ///
  /// In en, this message translates to:
  /// **'There was already a PT planned on {date}, so the program was only attached to it — the time range you picked wasn\'t applied'**
  String coachRegisteredAttachedExisting(String date);

  /// No description provided for @coachGoToSchedule.
  ///
  /// In en, this message translates to:
  /// **'Go to schedule'**
  String get coachGoToSchedule;

  /// No description provided for @labelTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get labelTomorrow;

  /// No description provided for @coachTemplates.
  ///
  /// In en, this message translates to:
  /// **'Program templates'**
  String get coachTemplates;

  /// No description provided for @coachSentHistory.
  ///
  /// In en, this message translates to:
  /// **'Sent history'**
  String get coachSentHistory;

  /// No description provided for @coachLastDelivery.
  ///
  /// In en, this message translates to:
  /// **'Last send'**
  String get coachLastDelivery;

  /// No description provided for @coachDeliveryPtWithRoutine.
  ///
  /// In en, this message translates to:
  /// **'PT · personal'**
  String get coachDeliveryPtWithRoutine;

  /// No description provided for @coachDeliveryRoutineOnly.
  ///
  /// In en, this message translates to:
  /// **'Personal only'**
  String get coachDeliveryRoutineOnly;

  /// No description provided for @coachDeliveryCancelledRoutineOnly.
  ///
  /// In en, this message translates to:
  /// **'PT cancelled · personal only'**
  String get coachDeliveryCancelledRoutineOnly;

  /// No description provided for @coachDeliveryOn.
  ///
  /// In en, this message translates to:
  /// **'Sent {date}'**
  String coachDeliveryOn(String date);

  /// No description provided for @coachUnsentRoutines.
  ///
  /// In en, this message translates to:
  /// **'{count} personal exercise(s) not sent yet'**
  String coachUnsentRoutines(int count);

  /// No description provided for @coachUnsentRoutinesBody.
  ///
  /// In en, this message translates to:
  /// **'The PT has ended but this has not reached the member yet. Open that session in the schedule to send it.'**
  String get coachUnsentRoutinesBody;

  /// No description provided for @coachSendUnsentRoutines.
  ///
  /// In en, this message translates to:
  /// **'Open in schedule'**
  String get coachSendUnsentRoutines;

  /// No description provided for @coachDeliveryProgramSection.
  ///
  /// In en, this message translates to:
  /// **'Program'**
  String get coachDeliveryProgramSection;

  /// No description provided for @coachDeliveryRoutineSection.
  ///
  /// In en, this message translates to:
  /// **'Personal workout'**
  String get coachDeliveryRoutineSection;

  /// No description provided for @coachDeliveryNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing sent'**
  String get coachDeliveryNothing;

  /// No description provided for @coachHistoryFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load history'**
  String get coachHistoryFailed;

  /// No description provided for @coachHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t sent any programs yet'**
  String get coachHistoryEmpty;

  /// No description provided for @coachTrainer.
  ///
  /// In en, this message translates to:
  /// **'Trainer'**
  String get coachTrainer;

  /// No description provided for @aiReasonSodium.
  ///
  /// In en, this message translates to:
  /// **'Sodium is over target today, so lean into low-intensity cardio.'**
  String get aiReasonSodium;

  /// No description provided for @aiReasonBalanced.
  ///
  /// In en, this message translates to:
  /// **'Today\'s meals are balanced, so the current intensity is fine to keep.'**
  String get aiReasonBalanced;

  /// No description provided for @aiReasonGoal.
  ///
  /// In en, this message translates to:
  /// **'Based on the {goal} goal and recent {last} activity.'**
  String aiReasonGoal(String goal, String last);

  /// No description provided for @aiTagExisting.
  ///
  /// In en, this message translates to:
  /// **'Existing suggestion'**
  String get aiTagExisting;

  /// No description provided for @aiTagCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get aiTagCustom;

  /// No description provided for @aiExistingBlurb.
  ///
  /// In en, this message translates to:
  /// **'The existing suggestion, based on their recent meals and workouts.'**
  String get aiExistingBlurb;

  /// No description provided for @aiOptionRecovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get aiOptionRecovery;

  /// No description provided for @aiOptionPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get aiOptionPush;

  /// No description provided for @aiOptionExisting.
  ///
  /// In en, this message translates to:
  /// **'Existing'**
  String get aiOptionExisting;

  /// No description provided for @aiGenerateFailed.
  ///
  /// In en, this message translates to:
  /// **'AI generation failed. Please try again in a moment'**
  String get aiGenerateFailed;

  /// No description provided for @aiGenerateInvalidConditions.
  ///
  /// In en, this message translates to:
  /// **'Check the generation conditions. Total time must be between {min} and {max} minutes'**
  String aiGenerateInvalidConditions(int min, int max);

  /// No description provided for @aiGenerateMinutesHelper.
  ///
  /// In en, this message translates to:
  /// **'Enter between {min} and {max} minutes'**
  String aiGenerateMinutesHelper(int min, int max);

  /// No description provided for @aiGenerateRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many generation requests. Please try again shortly'**
  String get aiGenerateRateLimited;

  /// No description provided for @aiExerciseNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter an exercise name'**
  String get aiExerciseNameRequired;

  /// No description provided for @aiKeepOneExercise.
  ///
  /// In en, this message translates to:
  /// **'Keep at least one exercise'**
  String get aiKeepOneExercise;

  /// Routine name sent when the trainer leaves the name blank (#2301).
  ///
  /// In en, this message translates to:
  /// **'AI custom suggestion'**
  String get aiCustomRoutineName;

  /// No description provided for @aiAnalysing.
  ///
  /// In en, this message translates to:
  /// **'AI is analysing…'**
  String get aiAnalysing;

  /// No description provided for @aiGenerateCandidates.
  ///
  /// In en, this message translates to:
  /// **'Generate candidates'**
  String get aiGenerateCandidates;

  /// No description provided for @aiReviewDone.
  ///
  /// In en, this message translates to:
  /// **'Finish review'**
  String get aiReviewDone;

  /// No description provided for @aiRoutineFor.
  ///
  /// In en, this message translates to:
  /// **'AI suggestion · {name}'**
  String aiRoutineFor(String name);

  /// No description provided for @aiAnalysedData.
  ///
  /// In en, this message translates to:
  /// **'Member status'**
  String get aiAnalysedData;

  /// No description provided for @aiGoal.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get aiGoal;

  /// No description provided for @aiOverTarget.
  ///
  /// In en, this message translates to:
  /// **' · over target'**
  String get aiOverTarget;

  /// No description provided for @aiRecentCompletion.
  ///
  /// In en, this message translates to:
  /// **'Recent completion'**
  String get aiRecentCompletion;

  /// No description provided for @aiNoCompletionData.
  ///
  /// In en, this message translates to:
  /// **'No activity logged this week'**
  String get aiNoCompletionData;

  /// No description provided for @aiCompletionLow.
  ///
  /// In en, this message translates to:
  /// **' · needs attention'**
  String get aiCompletionLow;

  /// No description provided for @aiDietSignal.
  ///
  /// In en, this message translates to:
  /// **'Diet warning'**
  String get aiDietSignal;

  /// No description provided for @aiSodiumOverDaysSuffix.
  ///
  /// In en, this message translates to:
  /// **' · over target on {days} of the last 7 days'**
  String aiSodiumOverDaysSuffix(int days);

  /// No description provided for @aiSugarAlsoOver.
  ///
  /// In en, this message translates to:
  /// **' · sugar also over'**
  String get aiSugarAlsoOver;

  /// No description provided for @aiDirectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get aiDirectionLabel;

  /// No description provided for @aiDirectionLower.
  ///
  /// In en, this message translates to:
  /// **'Lower intensity — recent completion is low'**
  String get aiDirectionLower;

  /// No description provided for @aiDirectionCardio.
  ///
  /// In en, this message translates to:
  /// **'More cardio — sodium is often over target'**
  String get aiDirectionCardio;

  /// No description provided for @aiDirectionLowerAndCardio.
  ///
  /// In en, this message translates to:
  /// **'Lower intensity · more cardio'**
  String get aiDirectionLowerAndCardio;

  /// No description provided for @aiDirectionKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep current intensity'**
  String get aiDirectionKeep;

  /// No description provided for @aiDirectionNoData.
  ///
  /// In en, this message translates to:
  /// **'Not enough records yet'**
  String get aiDirectionNoData;

  /// No description provided for @aiBasisRuleBased.
  ///
  /// In en, this message translates to:
  /// **' · rule-based'**
  String get aiBasisRuleBased;

  /// No description provided for @aiChatEvidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent conversation used'**
  String get aiChatEvidenceTitle;

  /// No description provided for @aiEditOption.
  ///
  /// In en, this message translates to:
  /// **'Edit {option}'**
  String aiEditOption(String option);

  /// No description provided for @aiEditBlurb.
  ///
  /// In en, this message translates to:
  /// **'Edit names, durations and structure just like the existing suggestion.'**
  String get aiEditBlurb;

  /// No description provided for @aiAddExerciseManually.
  ///
  /// In en, this message translates to:
  /// **'Add exercise manually'**
  String get aiAddExerciseManually;

  /// No description provided for @aiExerciseNameExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. leg press, 3 sets'**
  String get aiExerciseNameExample;

  /// No description provided for @aiRegister.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get aiRegister;

  /// No description provided for @aiNoteForClient.
  ///
  /// In en, this message translates to:
  /// **'Feedback to send with it'**
  String get aiNoteForClient;

  /// No description provided for @aiReviewedSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Confirmed plan · {option}'**
  String aiReviewedSuggestion(String option);

  /// No description provided for @aiEditsApplied.
  ///
  /// In en, this message translates to:
  /// **'Your choice and edits are now in the final suggestion list.'**
  String get aiEditsApplied;

  /// No description provided for @aiApplyToTemplate.
  ///
  /// In en, this message translates to:
  /// **'Apply to program'**
  String get aiApplyToTemplate;

  /// No description provided for @aiAppliedToTemplate.
  ///
  /// In en, this message translates to:
  /// **'The AI suggestion was applied to the program.'**
  String get aiAppliedToTemplate;

  /// No description provided for @aiStepConditions.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get aiStepConditions;

  /// No description provided for @aiStepReview.
  ///
  /// In en, this message translates to:
  /// **'Program selection'**
  String get aiStepReview;

  /// No description provided for @aiStepDone.
  ///
  /// In en, this message translates to:
  /// **'Program review'**
  String get aiStepDone;

  /// No description provided for @aiSkipPtProgram.
  ///
  /// In en, this message translates to:
  /// **'Personal exercise only'**
  String get aiSkipPtProgram;

  /// Evidence chip on an AI personal-exercise suggestion; server code recent_pt_feedback (#2301).
  ///
  /// In en, this message translates to:
  /// **'Recent PT feedback'**
  String get routineEvidenceRecentPtFeedback;

  /// Evidence chip; server code strength_heavy (#2301).
  ///
  /// In en, this message translates to:
  /// **'Mostly strength lately'**
  String get routineEvidenceStrengthHeavy;

  /// Evidence chip; server code blood_pressure_goal (#2301).
  ///
  /// In en, this message translates to:
  /// **'Blood pressure goal'**
  String get routineEvidenceBloodPressureGoal;

  /// Evidence chip; server code low_cardio (#2301).
  ///
  /// In en, this message translates to:
  /// **'Little cardio lately'**
  String get routineEvidenceLowCardio;

  /// Evidence chip; server code recent_record (#2301).
  ///
  /// In en, this message translates to:
  /// **'Recent workout log'**
  String get routineEvidenceRecentRecord;

  /// Intensity of an AI A/B plan whose contract value is 낮음 (#2301).
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get aiPlanIntensityLow;

  /// No description provided for @aiPersonalStepFull.
  ///
  /// In en, this message translates to:
  /// **'You can set up to {count} personal exercises at once.'**
  String aiPersonalStepFull(int count);

  /// No description provided for @aiPersonalEditDone.
  ///
  /// In en, this message translates to:
  /// **'Done editing'**
  String get aiPersonalEditDone;

  /// No description provided for @aiPersonalStepBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} AI suggested'**
  String aiPersonalStepBadge(int count);

  /// No description provided for @aiPersonalStepIntro.
  ///
  /// In en, this message translates to:
  /// **'Based on recent PT feedback and workout history, here is personal exercise for {name}. Only what stays here goes to the member.'**
  String aiPersonalStepIntro(String name);

  /// No description provided for @aiPersonalStepLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the AI personal-exercise suggestions'**
  String get aiPersonalStepLoadFailed;

  /// No description provided for @aiPersonalStepNoSuggestion.
  ///
  /// In en, this message translates to:
  /// **'No AI suggestion today. Add one below.'**
  String get aiPersonalStepNoSuggestion;

  /// No description provided for @aiProgramExerciseRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'Removes {name} from this program.'**
  String aiProgramExerciseRemoveBody(String name);

  /// No description provided for @aiPersonalDismissTitle.
  ///
  /// In en, this message translates to:
  /// **'Drop this exercise?'**
  String get aiPersonalDismissTitle;

  /// No description provided for @aiPersonalDismissBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will be dropped from this personal exercise. An AI suggestion will not come back.'**
  String aiPersonalDismissBody(String name);

  /// No description provided for @aiPersonalDismissTooltip.
  ///
  /// In en, this message translates to:
  /// **'Drop this suggestion'**
  String get aiPersonalDismissTooltip;

  /// No description provided for @aiPersonalDismissed.
  ///
  /// In en, this message translates to:
  /// **'{name} will not be recommended'**
  String aiPersonalDismissed(String name);

  /// No description provided for @aiPersonalDismissFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not complete that. Please try again shortly.'**
  String get aiPersonalDismissFailed;

  /// No description provided for @aiStepSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get aiStepSkipped;

  /// No description provided for @aiStepPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal exercise'**
  String get aiStepPersonal;

  /// No description provided for @aiStepPrev.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get aiStepPrev;

  /// No description provided for @aiStepNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get aiStepNext;

  /// No description provided for @aiPersonalStepTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal exercise between PT'**
  String get aiPersonalStepTitle;

  /// No description provided for @aiPersonalStepTitleRoutineOnly.
  ///
  /// In en, this message translates to:
  /// **'This week\'s personal exercise'**
  String get aiPersonalStepTitleRoutineOnly;

  /// No description provided for @aiPersonalStepBlurb.
  ///
  /// In en, this message translates to:
  /// **'Attached to this PT and sent to the member when you complete it. Pick at least one.'**
  String get aiPersonalStepBlurb;

  /// No description provided for @aiPersonalStepBlurbRoutineOnly.
  ///
  /// In en, this message translates to:
  /// **'What the member does on their own. If there is a PT on the start date it attaches to that PT; otherwise it goes out now for a week. Pick at least one.'**
  String get aiPersonalStepBlurbRoutineOnly;

  /// No description provided for @aiPersonalStepEmpty.
  ///
  /// In en, this message translates to:
  /// **'No personal exercise yet. Add one below.'**
  String get aiPersonalStepEmpty;

  /// No description provided for @aiKeepOnePersonalRoutine.
  ///
  /// In en, this message translates to:
  /// **'Keep at least one personal exercise.'**
  String get aiKeepOnePersonalRoutine;

  /// No description provided for @aiRoutineOnlyStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get aiRoutineOnlyStartDate;

  /// No description provided for @aiRoutineOnlyWeeklyHint.
  ///
  /// In en, this message translates to:
  /// **'Appears in the member app every day for 7 days from today. Send next week\'s set again then.'**
  String get aiRoutineOnlyWeeklyHint;

  /// No description provided for @aiRoutineOnlySend.
  ///
  /// In en, this message translates to:
  /// **'Send to member'**
  String get aiRoutineOnlySend;

  /// No description provided for @aiRoutineOnlySentLabel.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get aiRoutineOnlySentLabel;

  /// No description provided for @aiRoutineOnlySent.
  ///
  /// In en, this message translates to:
  /// **'Personal exercise sent to the member.'**
  String get aiRoutineOnlySent;

  /// No description provided for @aiRoutineOnlyProgramName.
  ///
  /// In en, this message translates to:
  /// **'This week\'s personal exercise'**
  String get aiRoutineOnlyProgramName;

  /// Program name stored when a trainer sends personal exercises only. No time span — the list stays up 7 days from the send date, not the calendar week (#2581).
  ///
  /// In en, this message translates to:
  /// **'Personal exercise'**
  String get aiRoutineOnlyDeliveryName;

  /// No description provided for @progPersonalRoutinesWhen.
  ///
  /// In en, this message translates to:
  /// **'Goes to the member when you complete this PT.'**
  String get progPersonalRoutinesWhen;

  /// No description provided for @progNoRoutinesRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Add to schedule without personal exercise?'**
  String get progNoRoutinesRegisterTitle;

  /// No description provided for @progNoRoutinesRegisterBody.
  ///
  /// In en, this message translates to:
  /// **'Each PT should come with at least one personal exercise. If you skip it now, you can still add it from the session details in Schedule before sending the PT program.'**
  String get progNoRoutinesRegisterBody;

  /// No description provided for @progNoRoutinesRegisterSkip.
  ///
  /// In en, this message translates to:
  /// **'Add without it'**
  String get progNoRoutinesRegisterSkip;

  /// No description provided for @progPersonalRoutinesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No personal exercise yet. Add at least one for each PT.'**
  String get progPersonalRoutinesEmpty;

  /// No description provided for @aiAttachTargetPt.
  ///
  /// In en, this message translates to:
  /// **'Personal exercise for the PT you are putting together.'**
  String get aiAttachTargetPt;

  /// No description provided for @aiAttachRoutines.
  ///
  /// In en, this message translates to:
  /// **'Apply to PT'**
  String get aiAttachRoutines;

  /// No description provided for @aiAttachedLabel.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get aiAttachedLabel;

  /// No description provided for @aiRoutineTargetPt.
  ///
  /// In en, this message translates to:
  /// **'Attach to the {date} {time} PT'**
  String aiRoutineTargetPt(String date, String time);

  /// No description provided for @aiRoutineOnlyAttachHint.
  ///
  /// In en, this message translates to:
  /// **'Attaches to the {date} {time} PT. It reaches the member when you send that PT from Schedule.'**
  String aiRoutineOnlyAttachHint(String date, String time);

  /// No description provided for @aiReplaceRoutinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal exercise already attached'**
  String get aiReplaceRoutinesTitle;

  /// No description provided for @aiReplaceRoutinesBody.
  ///
  /// In en, this message translates to:
  /// **'This PT already has {count} personal exercise(s) ({names}). Replace them with the new ones?'**
  String aiReplaceRoutinesBody(int count, String names);

  /// No description provided for @aiReplaceRoutinesConfirm.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get aiReplaceRoutinesConfirm;

  /// No description provided for @programRoutineOnlyConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Sends personal exercise to {client}. Appears daily from {start} to {end}.'**
  String programRoutineOnlyConfirmBody(String client, String start, String end);

  /// No description provided for @progPersonalRoutinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal exercise for this PT'**
  String get progPersonalRoutinesTitle;

  /// No description provided for @aiStepperLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom suggestion progress'**
  String get aiStepperLabel;

  /// No description provided for @coachTemplateSummaryWithGoal.
  ///
  /// In en, this message translates to:
  /// **'{goal} · {count} exercises · {duration}'**
  String coachTemplateSummaryWithGoal(String goal, int count, String duration);

  /// No description provided for @aiInsightMemoTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs attention (last 7 days)'**
  String get aiInsightMemoTitle;

  /// No description provided for @aiInsightMemoEmpty.
  ///
  /// In en, this message translates to:
  /// **'No insights detected in the last 7 days'**
  String get aiInsightMemoEmpty;

  /// No description provided for @aiInsightMemoFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the detected memos'**
  String get aiInsightMemoFailed;

  /// No description provided for @aiRecentRoutineMore.
  ///
  /// In en, this message translates to:
  /// **'{name} and {count} more'**
  String aiRecentRoutineMore(String name, int count);

  /// No description provided for @aiNoRecentRoutine.
  ///
  /// In en, this message translates to:
  /// **'No record'**
  String get aiNoRecentRoutine;

  /// No description provided for @aiRecentRoutine.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get aiRecentRoutine;

  /// No description provided for @aiNotePlaceholderHint.
  ///
  /// In en, this message translates to:
  /// **'The grey suggestion is only a prompt — only what you type is saved and sent.'**
  String get aiNotePlaceholderHint;

  /// No description provided for @aiGenerateConditions.
  ///
  /// In en, this message translates to:
  /// **'Conditions'**
  String get aiGenerateConditions;

  /// No description provided for @aiCompareCandidates.
  ///
  /// In en, this message translates to:
  /// **'Compare the candidates'**
  String get aiCompareCandidates;

  /// No description provided for @aiConditionsAutoHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to auto-fill from recent history or goals.'**
  String get aiConditionsAutoHint;

  /// No description provided for @aiPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Tell the AI what program you want'**
  String get aiPromptTitle;

  /// No description provided for @aiPromptLabel.
  ///
  /// In en, this message translates to:
  /// **'Your request'**
  String get aiPromptLabel;

  /// No description provided for @aiPromptHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Build a 40-minute program that goes easy on the legs and leans on cardio'**
  String get aiPromptHint;

  /// No description provided for @aiPromptBlurb.
  ///
  /// In en, this message translates to:
  /// **'Your request goes to the AI with the member\'s data (up to 500 characters). Write the trainer feedback in the next step.'**
  String get aiPromptBlurb;

  /// No description provided for @aiSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Sources for the AI'**
  String get aiSourcesTitle;

  /// No description provided for @aiSourcesBlurb.
  ///
  /// In en, this message translates to:
  /// **'Only the checked sources are sent to the AI with the member\'s data. Your choice is kept for next time.'**
  String get aiSourcesBlurb;

  /// No description provided for @aiSourcePtFeedback.
  ///
  /// In en, this message translates to:
  /// **'Recent PT feedback'**
  String get aiSourcePtFeedback;

  /// No description provided for @aiSourceConsultMemo.
  ///
  /// In en, this message translates to:
  /// **'Consultation memos'**
  String get aiSourceConsultMemo;

  /// No description provided for @aiSourceTrainerMemo.
  ///
  /// In en, this message translates to:
  /// **'Member memos (written by you)'**
  String get aiSourceTrainerMemo;

  /// No description provided for @aiSourceChatInsight.
  ///
  /// In en, this message translates to:
  /// **'Chat-detected memos'**
  String get aiSourceChatInsight;

  /// Source the AI may read — the raw recent chat with the member (last 14 days, up to 10, #2794)
  ///
  /// In en, this message translates to:
  /// **'Recent chat'**
  String get aiSourceRecentChat;

  /// No description provided for @aiSourceWeeklyFeedback.
  ///
  /// In en, this message translates to:
  /// **'Member weekly feedback'**
  String get aiSourceWeeklyFeedback;

  /// No description provided for @aiSourceRangeDays.
  ///
  /// In en, this message translates to:
  /// **'Last {days} days · up to {count}'**
  String aiSourceRangeDays(int days, int count);

  /// No description provided for @aiSourceRangeWeeks.
  ///
  /// In en, this message translates to:
  /// **'This week · last week'**
  String get aiSourceRangeWeeks;

  /// No description provided for @aiGenerateGoalBased.
  ///
  /// In en, this message translates to:
  /// **'Generate goal-based suggestion'**
  String get aiGenerateGoalBased;

  /// No description provided for @aiStatusTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'Goal-based starter suggestion'**
  String get aiStatusTemplateTitle;

  /// No description provided for @aiStatusTemplateBody.
  ///
  /// In en, this message translates to:
  /// **'Not enough workout history yet to personalize — this starts from a goal-based default.'**
  String get aiStatusTemplateBody;

  /// No description provided for @aiStatusLearningTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalizing (learning)'**
  String get aiStatusLearningTitle;

  /// No description provided for @aiStatusLearningBody.
  ///
  /// In en, this message translates to:
  /// **'Recent workouts were used, but there isn\'t a clear repeated pattern yet.'**
  String get aiStatusLearningBody;

  /// No description provided for @aiStatusPersonalizedTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalized from recent patterns'**
  String get aiStatusPersonalizedTitle;

  /// No description provided for @aiStatusPersonalizedBody.
  ///
  /// In en, this message translates to:
  /// **'Based on {count} sessions over the last {days} days.'**
  String aiStatusPersonalizedBody(int count, int days);

  /// No description provided for @aiFrequentExercisesLabel.
  ///
  /// In en, this message translates to:
  /// **'Frequently done'**
  String get aiFrequentExercisesLabel;

  /// No description provided for @goalWeightLoss.
  ///
  /// In en, this message translates to:
  /// **'Weight loss'**
  String get goalWeightLoss;

  /// No description provided for @goalHealth.
  ///
  /// In en, this message translates to:
  /// **'General health'**
  String get goalHealth;

  /// No description provided for @goalOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get goalOther;

  /// No description provided for @slotAm.
  ///
  /// In en, this message translates to:
  /// **'AM'**
  String get slotAm;

  /// No description provided for @slotPm.
  ///
  /// In en, this message translates to:
  /// **'PM'**
  String get slotPm;

  /// No description provided for @slotFlexible.
  ///
  /// In en, this message translates to:
  /// **'Flexible'**
  String get slotFlexible;

  /// No description provided for @unknownMember.
  ///
  /// In en, this message translates to:
  /// **'Unknown member'**
  String get unknownMember;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @authErrInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'That email or password isn\'t right.'**
  String get authErrInvalidCredentials;

  /// No description provided for @authErrEmailTaken.
  ///
  /// In en, this message translates to:
  /// **'That email is already registered.'**
  String get authErrEmailTaken;

  /// No description provided for @authErrSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your sign-in expired. Please sign in again.'**
  String get authErrSessionExpired;

  /// No description provided for @authErrNoSocialToken.
  ///
  /// In en, this message translates to:
  /// **'No social sign-in token'**
  String get authErrNoSocialToken;

  /// No description provided for @authErrNetwork.
  ///
  /// In en, this message translates to:
  /// **'Please check your network connection.'**
  String get authErrNetwork;

  /// No description provided for @authErrGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong signing in. Please try again in a moment.'**
  String get authErrGeneric;

  /// No description provided for @authErrEmptyResponse.
  ///
  /// In en, this message translates to:
  /// **'The response was empty.'**
  String get authErrEmptyResponse;

  /// No description provided for @slotFutureOnly.
  ///
  /// In en, this message translates to:
  /// **'Booking slots can only be set for future times.'**
  String get slotFutureOnly;

  /// No description provided for @slotNotFound.
  ///
  /// In en, this message translates to:
  /// **'Booking slot not found.'**
  String get slotNotFound;

  /// No description provided for @slotTypeLockedByBooking.
  ///
  /// In en, this message translates to:
  /// **'Can\'t change the type of a slot that\'s already booked.'**
  String get slotTypeLockedByBooking;

  /// No description provided for @authErrNotTrainer.
  ///
  /// In en, this message translates to:
  /// **'Please sign in with a trainer account.'**
  String get authErrNotTrainer;

  /// No description provided for @aiBasisGoalCompletion.
  ///
  /// In en, this message translates to:
  /// **'{goal} · based on {rate}% completion'**
  String aiBasisGoalCompletion(String goal, int rate);

  /// No description provided for @aiBasisTrainerRequest.
  ///
  /// In en, this message translates to:
  /// **'Request: \"{request}\"'**
  String aiBasisTrainerRequest(String request);

  /// No description provided for @aiTotalAndIntensity.
  ///
  /// In en, this message translates to:
  /// **'{total} min total · {intensity}'**
  String aiTotalAndIntensity(int total, String intensity);

  /// No description provided for @aiBulletExercise.
  ///
  /// In en, this message translates to:
  /// **'· {name} · {minutes} min '**
  String aiBulletExercise(String name, int minutes);

  /// Login screen wordmark with the spaced hyphen used in the visual design.
  ///
  /// In en, this message translates to:
  /// **'On - Care Trainer'**
  String get appTitleSpaced;

  /// No description provided for @navNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get navNotifications;

  /// No description provided for @notifTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifTitle;

  /// No description provided for @notifSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get notifSeeAll;

  /// No description provided for @notifGroupAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get notifGroupAll;

  /// No description provided for @notifGroupMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get notifGroupMessages;

  /// No description provided for @notifGroupEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications of this kind'**
  String get notifGroupEmpty;

  /// No description provided for @notifReadAll.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get notifReadAll;

  /// No description provided for @notifEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get notifEmpty;

  /// No description provided for @notifLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load notifications'**
  String get notifLoadFailed;

  /// No description provided for @notifLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load earlier notifications'**
  String get notifLoadMore;

  /// No description provided for @notifLoadMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load earlier notifications'**
  String get notifLoadMoreFailed;

  /// No description provided for @notifNoEarlier.
  ///
  /// In en, this message translates to:
  /// **'No earlier notifications'**
  String get notifNoEarlier;

  /// No description provided for @notifTplHealthGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Member goals changed'**
  String get notifTplHealthGoalTitle;

  /// goals is the member's health goals joined with ' · '.
  ///
  /// In en, this message translates to:
  /// **'{name} changed their health goals: {goals}'**
  String notifTplHealthGoalBody(String name, String goals);

  /// No description provided for @notifTplHealthNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Member health notes changed'**
  String get notifTplHealthNotesTitle;

  /// No description provided for @notifTplHealthNotesBody.
  ///
  /// In en, this message translates to:
  /// **'{name} updated their health notes'**
  String notifTplHealthNotesBody(String name);

  /// No description provided for @notifTplHealthNotesWithGoalsBody.
  ///
  /// In en, this message translates to:
  /// **'{name} updated their health goals and health notes'**
  String notifTplHealthNotesWithGoalsBody(String name);

  /// Shown in place of the goal list when the member cleared every health goal.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get notifTplNoGoals;

  /// No description provided for @notifTplMemberRenamedTitle.
  ///
  /// In en, this message translates to:
  /// **'Member renamed'**
  String get notifTplMemberRenamedTitle;

  /// No description provided for @notifTplMemberRenamedBody.
  ///
  /// In en, this message translates to:
  /// **'{oldName} changed their name to {newName}.'**
  String notifTplMemberRenamedBody(String oldName, String newName);

  /// No description provided for @notifTplMemberWithdrawnTitle.
  ///
  /// In en, this message translates to:
  /// **'Member account deleted'**
  String get notifTplMemberWithdrawnTitle;

  /// No description provided for @notifTplMemberWithdrawnBody.
  ///
  /// In en, this message translates to:
  /// **'{name} deleted their account.'**
  String notifTplMemberWithdrawnBody(String name);

  /// No description provided for @notifTplMemberDisconnectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Client disconnected'**
  String get notifTplMemberDisconnectedTitle;

  /// No description provided for @notifTplMemberDisconnectedBody.
  ///
  /// In en, this message translates to:
  /// **'{name} ended their connection with you.'**
  String notifTplMemberDisconnectedBody(String name);

  /// No description provided for @notifTplConsultRequestedTitle.
  ///
  /// In en, this message translates to:
  /// **'New consultation request'**
  String get notifTplConsultRequestedTitle;

  /// No description provided for @notifTplConsultCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'Consultation request cancelled'**
  String get notifTplConsultCancelledTitle;

  /// No description provided for @notifTplConsultWithdrawnTitle.
  ///
  /// In en, this message translates to:
  /// **'Consultation request cancelled: member account deleted'**
  String get notifTplConsultWithdrawnTitle;

  /// No description provided for @notifTplInviteAcceptedTitle.
  ///
  /// In en, this message translates to:
  /// **'Coaching request accepted'**
  String get notifTplInviteAcceptedTitle;

  /// No description provided for @notifTplInviteAcceptedBody.
  ///
  /// In en, this message translates to:
  /// **'{name} is now your client.'**
  String notifTplInviteAcceptedBody(String name);

  /// No description provided for @notifTplInviteRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Coaching request declined'**
  String get notifTplInviteRejectedTitle;

  /// No description provided for @notifTplInviteRejectedBody.
  ///
  /// In en, this message translates to:
  /// **'{name} declined your coaching request.'**
  String notifTplInviteRejectedBody(String name);

  /// No description provided for @notifTplReservationBookedTitle.
  ///
  /// In en, this message translates to:
  /// **'New booking'**
  String get notifTplReservationBookedTitle;

  /// No description provided for @notifTplReservationCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'Booking cancelled'**
  String get notifTplReservationCancelledTitle;

  /// A member's name followed by a date or time, e.g. for a booking.
  ///
  /// In en, this message translates to:
  /// **'{name} · {detail}'**
  String notifTplMemberWithDetail(String name, String detail);

  /// Just the member's name, used when a cancelled booking has no time.
  ///
  /// In en, this message translates to:
  /// **'{name}'**
  String notifTplMemberOnly(String name);

  /// Seoul wall-clock date and time of a session. month and day are two digits, time is HH:mm.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day} {time}'**
  String notifTplWhen(String month, String day, String time);

  /// No description provided for @notifTplMemberMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Message from {name}'**
  String notifTplMemberMessageTitle(String name);

  /// Body of the new-message notification when a member sent only a photo in the coach chat.
  ///
  /// In en, this message translates to:
  /// **'Sent a photo'**
  String get notifTplMemberPhotoBody;

  /// Trainer notification title when a member submits their weekly feedback (#3026).
  ///
  /// In en, this message translates to:
  /// **'{name} sent their weekly feedback'**
  String notifTplWeeklyFeedbackTitle(String name);

  /// Title when a member re-submits weekly feedback the trainer has already read (#3026).
  ///
  /// In en, this message translates to:
  /// **'{name} updated their weekly feedback'**
  String notifTplWeeklyFeedbackRevisedTitle(String name);

  /// Title when the weekly feedback reports pain. The pain area itself is never shown in the notification (#3026).
  ///
  /// In en, this message translates to:
  /// **'{name} reported pain'**
  String notifTplWeeklyFeedbackPainTitle(String name);

  /// No description provided for @notifTplWeeklyFeedbackCondition.
  ///
  /// In en, this message translates to:
  /// **'Condition: {value}'**
  String notifTplWeeklyFeedbackCondition(String value);

  /// No description provided for @notifTplWeeklyFeedbackIntensity.
  ///
  /// In en, this message translates to:
  /// **'Intensity: {value}'**
  String notifTplWeeklyFeedbackIntensity(String value);

  /// No description provided for @notifTplWeeklyFeedbackPain.
  ///
  /// In en, this message translates to:
  /// **'Pain reported'**
  String get notifTplWeeklyFeedbackPain;

  /// No description provided for @notifAllRead.
  ///
  /// In en, this message translates to:
  /// **'All caught up'**
  String get notifAllRead;

  /// No description provided for @notifReadAllFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t mark them read. Please try again in a moment'**
  String get notifReadAllFailed;

  /// No description provided for @notifUnreadCount.
  ///
  /// In en, this message translates to:
  /// **'{count} unread'**
  String notifUnreadCount(int count);

  /// No description provided for @myDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get myDeleteAccount;

  /// No description provided for @myDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get myDeleteAction;

  /// No description provided for @myDeleteDemo.
  ///
  /// In en, this message translates to:
  /// **'Demo mode has no account to delete'**
  String get myDeleteDemo;

  /// No description provided for @myDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get myDeleteTitle;

  /// No description provided for @myDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Your member links and bookings are removed and your members are notified. This can\'t be undone.'**
  String get myDeleteBody;

  /// No description provided for @myDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete your account. Please try again in a moment'**
  String get myDeleteFailed;

  /// No description provided for @myDeleteConfirmPrompt.
  ///
  /// In en, this message translates to:
  /// **'Type your name ({name}) to continue'**
  String myDeleteConfirmPrompt(String name);

  /// No description provided for @myWithdrawReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to leave?'**
  String get myWithdrawReasonTitle;

  /// No description provided for @myWithdrawReasonQuestion.
  ///
  /// In en, this message translates to:
  /// **'What didn\'t work for you?'**
  String get myWithdrawReasonQuestion;

  /// No description provided for @myWithdrawReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Pick as many as you like, or skip.'**
  String get myWithdrawReasonHint;

  /// No description provided for @myWithdrawReasonRarelyUsed.
  ///
  /// In en, this message translates to:
  /// **'I rarely use it'**
  String get myWithdrawReasonRarelyUsed;

  /// No description provided for @myWithdrawReasonHardToUse.
  ///
  /// In en, this message translates to:
  /// **'It\'s hard to use'**
  String get myWithdrawReasonHardToUse;

  /// No description provided for @myWithdrawReasonMissingFeature.
  ///
  /// In en, this message translates to:
  /// **'It lacks features I need for members'**
  String get myWithdrawReasonMissingFeature;

  /// No description provided for @myWithdrawReasonLeavingWork.
  ///
  /// In en, this message translates to:
  /// **'I\'m taking a break from training'**
  String get myWithdrawReasonLeavingWork;

  /// No description provided for @myWithdrawReasonAlternative.
  ///
  /// In en, this message translates to:
  /// **'I use another tool'**
  String get myWithdrawReasonAlternative;

  /// No description provided for @myWithdrawReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get myWithdrawReasonOther;

  /// No description provided for @myWithdrawKeepTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you go'**
  String get myWithdrawKeepTitle;

  /// No description provided for @myWithdrawKeepRarelyUsed.
  ///
  /// In en, this message translates to:
  /// **'Turn on alerts so you don\'t miss member messages and bookings. Change them in Settings › Notifications.'**
  String get myWithdrawKeepRarelyUsed;

  /// No description provided for @myWithdrawKeepHardToUse.
  ///
  /// In en, this message translates to:
  /// **'Tell us what felt awkward via 1:1 inquiry and we\'ll work on it.'**
  String get myWithdrawKeepHardToUse;

  /// No description provided for @myWithdrawKeepMissingFeature.
  ///
  /// In en, this message translates to:
  /// **'Tell us which feature you need via 1:1 inquiry — we\'ll consider it next.'**
  String get myWithdrawKeepMissingFeature;

  /// No description provided for @myWithdrawKeepLeavingWork.
  ///
  /// In en, this message translates to:
  /// **'If it\'s just a break, you can keep your account. Leaving disconnects all your members.'**
  String get myWithdrawKeepLeavingWork;

  /// No description provided for @myWithdrawKeepAlternative.
  ///
  /// In en, this message translates to:
  /// **'Leaving removes member records, programs and reports from your console for good.'**
  String get myWithdrawKeepAlternative;

  /// No description provided for @myWithdrawKeepOther.
  ///
  /// In en, this message translates to:
  /// **'Your feedback via 1:1 inquiry would help us a lot.'**
  String get myWithdrawKeepOther;

  /// No description provided for @myWithdrawKeepDefault.
  ///
  /// In en, this message translates to:
  /// **'Leaving removes your member connections and bookings, and your members are notified. This can\'t be undone.'**
  String get myWithdrawKeepDefault;

  /// No description provided for @myWithdrawNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get myWithdrawNext;

  /// No description provided for @myWithdrawStay.
  ///
  /// In en, this message translates to:
  /// **'Keep using'**
  String get myWithdrawStay;

  /// No description provided for @myWithdrawContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue leaving'**
  String get myWithdrawContinue;

  /// No description provided for @routineAlreadyGone.
  ///
  /// In en, this message translates to:
  /// **'That program is already gone'**
  String get routineAlreadyGone;

  /// No description provided for @workoutPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily personal exercises'**
  String get workoutPendingTitle;

  /// No description provided for @workoutRoutineDoneToday.
  ///
  /// In en, this message translates to:
  /// **'Done today'**
  String get workoutRoutineDoneToday;

  /// No description provided for @workoutUndatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Records without a date'**
  String get workoutUndatedTitle;

  /// No description provided for @workoutMemberLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Logged by member'**
  String get workoutMemberLogTitle;

  /// Shown in the expanded day when its workouts fail to load (#2892)
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this day\'s workouts'**
  String get workoutDayExercisesFailed;

  /// No description provided for @workoutPendingCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel assignment'**
  String get workoutPendingCancel;

  /// No description provided for @routineDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this program?'**
  String get routineDeleteTitle;

  /// No description provided for @routineDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the program. Please try again in a moment'**
  String get routineDeleteFailed;

  /// No description provided for @routineDeleted.
  ///
  /// In en, this message translates to:
  /// **'Program deleted'**
  String get routineDeleted;

  /// No description provided for @routineDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'{name} disappears from the member\'s app too.'**
  String routineDeleteBody(String name);

  /// Label/tooltip of the console header's client search.
  ///
  /// In en, this message translates to:
  /// **'Search members'**
  String get searchClients;

  /// No description provided for @searchClientsHint.
  ///
  /// In en, this message translates to:
  /// **'Members, goals, recent messages, last program sent date'**
  String get searchClientsHint;

  /// No description provided for @searchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get searchClear;

  /// No description provided for @searchQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Open in another tab'**
  String get searchQuickActions;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No member matches “{query}”'**
  String searchNoResults(String query);

  /// Search dropdown footer: what picking a result does on this tab.
  ///
  /// In en, this message translates to:
  /// **'Picking one opens their detail'**
  String get searchGoClientDetail;

  /// No description provided for @searchGoSchedule.
  ///
  /// In en, this message translates to:
  /// **'Picking one jumps to their next booked day'**
  String get searchGoSchedule;

  /// No description provided for @searchGoCoaching.
  ///
  /// In en, this message translates to:
  /// **'Picking one loads them into AI coaching'**
  String get searchGoCoaching;

  /// No description provided for @searchGoReport.
  ///
  /// In en, this message translates to:
  /// **'Picking one opens their weekly report'**
  String get searchGoReport;

  /// No description provided for @searchDetailUnread.
  ///
  /// In en, this message translates to:
  /// **'{count} awaiting a reply'**
  String searchDetailUnread(int count);

  /// No description provided for @searchDetailMessage.
  ///
  /// In en, this message translates to:
  /// **'{message} · {time}'**
  String searchDetailMessage(String message, String time);

  /// No description provided for @searchDetailNextSession.
  ///
  /// In en, this message translates to:
  /// **'Next session {date} {time}'**
  String searchDetailNextSession(String date, String time);

  /// No description provided for @searchDetailNoUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Nothing booked'**
  String get searchDetailNoUpcoming;

  /// No description provided for @searchDetailLastRoutine.
  ///
  /// In en, this message translates to:
  /// **'Last program {when}'**
  String searchDetailLastRoutine(String when);

  /// No description provided for @searchDetailCompletion.
  ///
  /// In en, this message translates to:
  /// **'{percent}% completion this week'**
  String searchDetailCompletion(int percent);

  /// No description provided for @navOperationsGroup.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get navOperationsGroup;

  /// No description provided for @navCoachingGroup.
  ///
  /// In en, this message translates to:
  /// **'Coaching'**
  String get navCoachingGroup;

  /// No description provided for @dashTodayTasks.
  ///
  /// In en, this message translates to:
  /// **'Today\'s tasks'**
  String get dashTodayTasks;

  /// No description provided for @dashTasksReviewed.
  ///
  /// In en, this message translates to:
  /// **'All reviewed'**
  String get dashTasksReviewed;

  /// No description provided for @dashTasksNeedReview.
  ///
  /// In en, this message translates to:
  /// **'{count} to review'**
  String dashTasksNeedReview(int count);

  /// No description provided for @dashTaskProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Task completion'**
  String get dashTaskProgressTitle;

  /// No description provided for @dashTaskProgressToday.
  ///
  /// In en, this message translates to:
  /// **'Today\'s tasks'**
  String get dashTaskProgressToday;

  /// No description provided for @dashTaskProgressCarriedOver.
  ///
  /// In en, this message translates to:
  /// **'Carried over'**
  String get dashTaskProgressCarriedOver;

  /// No description provided for @dashTodoConsultation.
  ///
  /// In en, this message translates to:
  /// **'Consult'**
  String get dashTodoConsultation;

  /// No description provided for @dashTodoDiet.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get dashTodoDiet;

  /// No description provided for @dashTodoWorkout.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get dashTodoWorkout;

  /// No description provided for @dashTodoProgram.
  ///
  /// In en, this message translates to:
  /// **'Program'**
  String get dashTodoProgram;

  /// No description provided for @dashTodoReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get dashTodoReport;

  /// Subtitle of a consultation-request task: the member's preferred (or chosen slot) date and time, not the date the request arrived.
  ///
  /// In en, this message translates to:
  /// **'Preferred: {when}'**
  String dashTodoConsultationSubtitle(String when);

  /// Subtitle of the demo carried-over task shown before real history exists.
  ///
  /// In en, this message translates to:
  /// **'Diet feedback left over from yesterday'**
  String get dashTodoCarriedOverDemoSubtitle;

  /// No description provided for @dashTodoProgramSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No recent program sent'**
  String get dashTodoProgramSubtitle;

  /// No description provided for @dashTodoReportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This week\'s report is due'**
  String get dashTodoReportSubtitle;

  /// No description provided for @dashTaskSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your task status. Please try again in a moment'**
  String get dashTaskSaveFailed;

  /// No description provided for @dashTaskLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your task status. Please try again in a moment'**
  String get dashTaskLoadFailed;

  /// Toast when a task tap arrives after midnight on a dashboard opened the previous day; the tap is ignored and today's list is reloaded.
  ///
  /// In en, this message translates to:
  /// **'The date changed, so today\'s tasks were reloaded. Please tap again'**
  String get dashTaskDayChanged;

  /// No description provided for @dashTaskDismissTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this item?'**
  String get dashTaskDismissTitle;

  /// No description provided for @dashTaskDismissBody.
  ///
  /// In en, this message translates to:
  /// **'It only disappears from the task list. Actually handling it (consultation, program, report) still happens on its own screen.'**
  String get dashTaskDismissBody;

  /// No description provided for @dashTaskCarriedOverTitle.
  ///
  /// In en, this message translates to:
  /// **'Carried over'**
  String get dashTaskCarriedOverTitle;

  /// No description provided for @dashTaskCategoryDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get dashTaskCategoryDone;

  /// No description provided for @dashTaskCategoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get dashTaskCategoryEmpty;

  /// No description provided for @dashTaskCategoryRemaining.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String dashTaskCategoryRemaining(int count);

  /// No description provided for @dashTaskUncheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Undo completion of \'{name}\'?'**
  String dashTaskUncheckTitle(String name);

  /// No description provided for @dashTaskUncheckBody.
  ///
  /// In en, this message translates to:
  /// **'It also drops off the task progress chart.'**
  String get dashTaskUncheckBody;

  /// No description provided for @dashTaskUncheckConfirm.
  ///
  /// In en, this message translates to:
  /// **'Undo completion'**
  String get dashTaskUncheckConfirm;

  /// No description provided for @churnNoRecentFeedback.
  ///
  /// In en, this message translates to:
  /// **'No trainer feedback in 7 days'**
  String get churnNoRecentFeedback;

  /// No description provided for @navMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get navMessages;

  /// No description provided for @messagesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Exchange coaching updates with members and follow up quickly'**
  String get messagesSubtitle;

  /// No description provided for @messagesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load conversations.'**
  String get messagesLoadFailed;

  /// No description provided for @messagesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No conversations match these filters.'**
  String get messagesEmpty;

  /// No description provided for @messagesFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get messagesFilterAll;

  /// No description provided for @messagesFilterUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get messagesFilterUnread;

  /// No description provided for @messagesFilterAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get messagesFilterAttention;

  /// No description provided for @messagesFilterUnreadCount.
  ///
  /// In en, this message translates to:
  /// **'Unread {count}'**
  String messagesFilterUnreadCount(int count);

  /// No description provided for @messagesNoPreview.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get messagesNoPreview;

  /// No description provided for @messagesPreviewEmote.
  ///
  /// In en, this message translates to:
  /// **'Sent an emote'**
  String get messagesPreviewEmote;

  /// No description provided for @messagesPreviewPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get messagesPreviewPhoto;

  /// No description provided for @messagesTimeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get messagesTimeJustNow;

  /// No description provided for @messagesClientDetail.
  ///
  /// In en, this message translates to:
  /// **'Member details'**
  String get messagesClientDetail;

  /// No description provided for @messagesSelectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select a member from the list to start a conversation.'**
  String get messagesSelectPrompt;

  /// No description provided for @clientQuickMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get clientQuickMessages;

  /// No description provided for @clientQuickProgram.
  ///
  /// In en, this message translates to:
  /// **'Program'**
  String get clientQuickProgram;

  /// No description provided for @clientQuickReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get clientQuickReport;

  /// No description provided for @clientProfileSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Body and goals'**
  String get clientProfileSectionTitle;

  /// No description provided for @clientMemoDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Memos & feedback'**
  String get clientMemoDialogTitle;

  /// No description provided for @clientTrainerMemo.
  ///
  /// In en, this message translates to:
  /// **'Memo'**
  String get clientTrainerMemo;

  /// No description provided for @clientHealthUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get clientHealthUnset;

  /// No description provided for @clientHealthTabBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get clientHealthTabBody;

  /// No description provided for @clientHealthTabFocus.
  ///
  /// In en, this message translates to:
  /// **'Health goals'**
  String get clientHealthTabFocus;

  /// No description provided for @clientGoalPerDay.
  ///
  /// In en, this message translates to:
  /// **'Per day'**
  String get clientGoalPerDay;

  /// No description provided for @clientGoalCalories.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get clientGoalCalories;

  /// No description provided for @clientGoalSodium.
  ///
  /// In en, this message translates to:
  /// **'Sodium'**
  String get clientGoalSodium;

  /// No description provided for @clientGoalSugar.
  ///
  /// In en, this message translates to:
  /// **'Sugar'**
  String get clientGoalSugar;

  /// No description provided for @clientGoalCarbs.
  ///
  /// In en, this message translates to:
  /// **'Carbs'**
  String get clientGoalCarbs;

  /// No description provided for @clientGoalProtein.
  ///
  /// In en, this message translates to:
  /// **'Protein'**
  String get clientGoalProtein;

  /// No description provided for @clientGoalFat.
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get clientGoalFat;

  /// No description provided for @clientGoalBurnDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily burn'**
  String get clientGoalBurnDaily;

  /// No description provided for @clientGoalCardioWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly cardio'**
  String get clientGoalCardioWeekly;

  /// No description provided for @clientGoalStrengthWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly strength'**
  String get clientGoalStrengthWeekly;

  /// No description provided for @clientGoalStretchWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly stretching'**
  String get clientGoalStretchWeekly;

  /// No description provided for @clientBodyHeight.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get clientBodyHeight;

  /// No description provided for @clientBodyWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get clientBodyWeight;

  /// No description provided for @clientUnitCm.
  ///
  /// In en, this message translates to:
  /// **'cm'**
  String get clientUnitCm;

  /// No description provided for @clientGoalDefaultHint.
  ///
  /// In en, this message translates to:
  /// **'Faded values are the defaults used until a goal is set. Empty fields use them.'**
  String get clientGoalDefaultHint;

  /// No description provided for @clientGoalSuggestionDiet.
  ///
  /// In en, this message translates to:
  /// **'Suggested: {kcal} kcal · carbs {carbs} g · sugar {sugar} g · protein {protein} g · fat {fat} g · sodium {sodium} mg'**
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
  /// In en, this message translates to:
  /// **'Suggested: {burn} kcal burned a day · {cardio} min cardio · {strength} strength sets · {flexibility} min stretching a week'**
  String clientGoalSuggestionExercise(
    int burn,
    int cardio,
    int strength,
    int flexibility,
  );

  /// No description provided for @clientGoalSuggestionPersonal.
  ///
  /// In en, this message translates to:
  /// **'Based on age, sex, height, weight, and health goals (2020 KDRIs and WHO guidelines)'**
  String get clientGoalSuggestionPersonal;

  /// No description provided for @clientGoalSuggestionFallback.
  ///
  /// In en, this message translates to:
  /// **'Age, height, or weight is missing, so only the health goals adjust the defaults'**
  String get clientGoalSuggestionFallback;

  /// No description provided for @clientGoalApplySuggestion.
  ///
  /// In en, this message translates to:
  /// **'Fill with suggestion'**
  String get clientGoalApplySuggestion;

  /// No description provided for @clientTrainerMemoHint.
  ///
  /// In en, this message translates to:
  /// **'Note what you want to remember about this member'**
  String get clientTrainerMemoHint;

  /// No description provided for @clientTrainerMemoPrivate.
  ///
  /// In en, this message translates to:
  /// **'Only you can see this memo. It\'s hidden from the member.'**
  String get clientTrainerMemoPrivate;

  /// No description provided for @clientTrainerMemoAdd.
  ///
  /// In en, this message translates to:
  /// **'Add memo'**
  String get clientTrainerMemoAdd;

  /// No description provided for @clientTrainerMemoEmpty.
  ///
  /// In en, this message translates to:
  /// **'No memos yet.'**
  String get clientTrainerMemoEmpty;

  /// No description provided for @clientTrainerMemoFromChat.
  ///
  /// In en, this message translates to:
  /// **'From chat'**
  String get clientTrainerMemoFromChat;

  /// No description provided for @clientTrainerMemoLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load memos. Please try again.'**
  String get clientTrainerMemoLoadFailed;

  /// No description provided for @clientTrainerMemoSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the memo. Please try again.'**
  String get clientTrainerMemoSaveFailed;

  /// No description provided for @clientTrainerMemoDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the memo. Please try again.'**
  String get clientTrainerMemoDeleteFailed;

  /// No description provided for @clientTrainerMemoDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this memo?'**
  String get clientTrainerMemoDeleteTitle;

  /// No description provided for @clientTrainerMemoDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'A deleted memo can\'t be restored.'**
  String get clientTrainerMemoDeleteBody;

  /// No description provided for @clientExerciseMemoAdd.
  ///
  /// In en, this message translates to:
  /// **'Leave a memo'**
  String get clientExerciseMemoAdd;

  /// No description provided for @clientExerciseMemoCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 memo} other{{count} memos}}'**
  String clientExerciseMemoCount(int count);

  /// No description provided for @clientExerciseMemoHint.
  ///
  /// In en, this message translates to:
  /// **'Note what to remember from this workout'**
  String get clientExerciseMemoHint;

  /// No description provided for @clientExerciseMemoSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to memos.'**
  String get clientExerciseMemoSaved;

  /// No description provided for @clientMemoTagManual.
  ///
  /// In en, this message translates to:
  /// **'Written by you'**
  String get clientMemoTagManual;

  /// No description provided for @clientMemoTagPtSession.
  ///
  /// In en, this message translates to:
  /// **'PT session · {date}'**
  String clientMemoTagPtSession(String date);

  /// No description provided for @clientMemoTagPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal workout · {date}'**
  String clientMemoTagPersonal(String date);

  /// No description provided for @clientMemoTagPersonalNamed.
  ///
  /// In en, this message translates to:
  /// **'Personal workout · {date} {name}'**
  String clientMemoTagPersonalNamed(String date, String name);

  /// No description provided for @clientMemoTagMemberLog.
  ///
  /// In en, this message translates to:
  /// **'Member\'s log · {date}'**
  String clientMemoTagMemberLog(String date);

  /// No description provided for @clientMemoEdited.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get clientMemoEdited;

  /// No description provided for @clientMemoSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search memos (text or tag)'**
  String get clientMemoSearchHint;

  /// No description provided for @clientMemoSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No memos match your search.'**
  String get clientMemoSearchEmpty;

  /// No description provided for @clientMemoCategoryExercise.
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get clientMemoCategoryExercise;

  /// No description provided for @clientMemoCategoryDiet.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get clientMemoCategoryDiet;

  /// No description provided for @clientMemoCategoryPain.
  ///
  /// In en, this message translates to:
  /// **'Pain · injury'**
  String get clientMemoCategoryPain;

  /// No description provided for @clientMemoCategoryLife.
  ///
  /// In en, this message translates to:
  /// **'Life · schedule'**
  String get clientMemoCategoryLife;

  /// No description provided for @clientMemoRecordLink.
  ///
  /// In en, this message translates to:
  /// **'Link a workout (optional)'**
  String get clientMemoRecordLink;

  /// No description provided for @clientMemoRecordNone.
  ///
  /// In en, this message translates to:
  /// **'No link'**
  String get clientMemoRecordNone;

  /// No description provided for @clientMemoRecordEmpty.
  ///
  /// In en, this message translates to:
  /// **'No workouts in the last 14 days'**
  String get clientMemoRecordEmpty;

  /// No description provided for @clientMemoRecordDay.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day} ({weekday})'**
  String clientMemoRecordDay(String month, String day, String weekday);

  /// No description provided for @clientMemoRecordPtSession.
  ///
  /// In en, this message translates to:
  /// **'{date} PT session'**
  String clientMemoRecordPtSession(String date);

  /// No description provided for @clientMemoRecordPersonal.
  ///
  /// In en, this message translates to:
  /// **'{date} Personal workout'**
  String clientMemoRecordPersonal(String date);

  /// No description provided for @clientMemoRecordPersonalNamed.
  ///
  /// In en, this message translates to:
  /// **'{date} Personal workout · {name}'**
  String clientMemoRecordPersonalNamed(String date, String name);

  /// No description provided for @clientMemoRecordMemberLog.
  ///
  /// In en, this message translates to:
  /// **'{date} Member log'**
  String clientMemoRecordMemberLog(String date);

  /// No description provided for @clientMemoTabMemo.
  ///
  /// In en, this message translates to:
  /// **'Memos'**
  String get clientMemoTabMemo;

  /// No description provided for @clientMemoTabFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get clientMemoTabFeedback;

  /// No description provided for @clientFeedbackPrivate.
  ///
  /// In en, this message translates to:
  /// **'Feedback you and the member exchanged. Tap one to edit it where it was written.'**
  String get clientFeedbackPrivate;

  /// No description provided for @clientFeedbackToMember.
  ///
  /// In en, this message translates to:
  /// **'Trainer → member'**
  String get clientFeedbackToMember;

  /// No description provided for @clientFeedbackFromMember.
  ///
  /// In en, this message translates to:
  /// **'Member → trainer'**
  String get clientFeedbackFromMember;

  /// No description provided for @clientFeedbackSourcePt.
  ///
  /// In en, this message translates to:
  /// **'PT session · {date}'**
  String clientFeedbackSourcePt(String date);

  /// No description provided for @clientFeedbackSourceReport.
  ///
  /// In en, this message translates to:
  /// **'Report · week of {date}'**
  String clientFeedbackSourceReport(String date);

  /// No description provided for @clientFeedbackSourceWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly check-in · week of {date}'**
  String clientFeedbackSourceWeekly(String date);

  /// No description provided for @clientFeedbackWeeklyNoNote.
  ///
  /// In en, this message translates to:
  /// **'No note'**
  String get clientFeedbackWeeklyNoNote;

  /// No description provided for @clientFeedbackEmpty.
  ///
  /// In en, this message translates to:
  /// **'No feedback exchanged yet.'**
  String get clientFeedbackEmpty;

  /// No description provided for @clientFeedbackLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load feedback. Try again in a moment'**
  String get clientFeedbackLoadFailed;

  /// No description provided for @clientFeedbackSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search feedback (text, source, direction)'**
  String get clientFeedbackSearchHint;

  /// No description provided for @clientFeedbackSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No feedback matches your search.'**
  String get clientFeedbackSearchEmpty;

  /// No description provided for @followUp.
  ///
  /// In en, this message translates to:
  /// **'Follow-ups'**
  String get followUp;

  /// No description provided for @followUpOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get followUpOverdue;

  /// No description provided for @followUpComplete.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get followUpComplete;

  /// No description provided for @followUpCount.
  ///
  /// In en, this message translates to:
  /// **'{count} left'**
  String followUpCount(int count);

  /// No description provided for @followUpDashboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to follow up on today.'**
  String get followUpDashboardEmpty;

  /// No description provided for @followUpLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load follow-ups. Please try again.'**
  String get followUpLoadFailed;

  /// No description provided for @followUpCompleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t mark it done. Please try again.'**
  String get followUpCompleteFailed;

  /// No description provided for @programEditorDefaultName.
  ///
  /// In en, this message translates to:
  /// **'{goal} program'**
  String programEditorDefaultName(String goal);

  /// No description provided for @programEditorSaveUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Give the program a name first.'**
  String get programEditorSaveUnsupported;

  /// No description provided for @programDraftSaved.
  ///
  /// In en, this message translates to:
  /// **'Program saved.'**
  String get programDraftSaved;

  /// No description provided for @programAssignConfirmAttachBody.
  ///
  /// In en, this message translates to:
  /// **'This program will be attached to {name}\'s PT already planned for {date} {session}. The time you picked ({selected}) won\'t be applied.'**
  String programAssignConfirmAttachBody(
    String name,
    String date,
    String session,
    String selected,
  );

  /// No description provided for @programAssignConfirmChooseBody.
  ///
  /// In en, this message translates to:
  /// **'{name} has several PT appointments on {date} that overlap the time you picked ({selected}). Choose which one to attach this program to. The picked time won\'t be applied.'**
  String programAssignConfirmChooseBody(
    String name,
    String date,
    String selected,
  );

  /// No description provided for @coachAttachTargetChanged.
  ///
  /// In en, this message translates to:
  /// **'The PT appointment to attach to has changed. Tap Add to schedule again to check'**
  String get coachAttachTargetChanged;

  /// No description provided for @coachScheduleOverlap.
  ///
  /// In en, this message translates to:
  /// **'Another session is already booked at that time, so nothing was added. Pick a different time and try again'**
  String get coachScheduleOverlap;

  /// No description provided for @programEditorNoExercises.
  ///
  /// In en, this message translates to:
  /// **'Add at least one exercise'**
  String get programEditorNoExercises;

  /// No description provided for @programEditorExerciseNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'An exercise name is empty or longer than 100 characters'**
  String get programEditorExerciseNameInvalid;

  /// No description provided for @programEditorRegisterDatePast.
  ///
  /// In en, this message translates to:
  /// **'That date has passed. Pick today or a later date'**
  String get programEditorRegisterDatePast;

  /// No description provided for @programEditorSending.
  ///
  /// In en, this message translates to:
  /// **'Adding to the schedule'**
  String get programEditorSending;

  /// No description provided for @programEditorAlreadySent.
  ///
  /// In en, this message translates to:
  /// **'You just sent this setup. Apply a new one to send again'**
  String get programEditorAlreadySent;

  /// No description provided for @coachSendNetworkFailed.
  ///
  /// In en, this message translates to:
  /// **'Check your network connection and try again'**
  String get coachSendNetworkFailed;

  /// No description provided for @coachSendClientNotFound.
  ///
  /// In en, this message translates to:
  /// **'This member isn\'t linked to you. Check the member\'s connection'**
  String get coachSendClientNotFound;

  /// No description provided for @coachSendInvalid.
  ///
  /// In en, this message translates to:
  /// **'The server didn\'t accept this schedule. Check the date, time and exercises'**
  String get coachSendInvalid;

  /// No description provided for @coachSendUnverified.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t confirm the result. Check the schedule to see whether it was added'**
  String get coachSendUnverified;

  /// No description provided for @programEditorSessionLimitReached.
  ///
  /// In en, this message translates to:
  /// **'A program can have up to {max} sessions'**
  String programEditorSessionLimitReached(int max);

  /// No description provided for @programEditorExerciseLimitReached.
  ///
  /// In en, this message translates to:
  /// **'A program can have up to {max} exercises in total'**
  String programEditorExerciseLimitReached(int max);

  /// No description provided for @programEditorSizeExceeded.
  ///
  /// In en, this message translates to:
  /// **'{sessions}/{maxSessions} sessions · {exercises}/{maxExercises} exercises — remove the extra to add it to the schedule'**
  String programEditorSizeExceeded(
    int sessions,
    int maxSessions,
    int exercises,
    int maxExercises,
  );

  /// No description provided for @programAssignConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Add to the schedule?'**
  String get programAssignConfirmTitle;

  /// No description provided for @programAssignConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'A new PT appointment will be created for {name} on {date} at {time} with this program.'**
  String programAssignConfirmBody(String name, String date, String time);

  /// No description provided for @programEditorSaveTemplate.
  ///
  /// In en, this message translates to:
  /// **'Save as template'**
  String get programEditorSaveTemplate;

  /// No description provided for @programEditorAddSchedule.
  ///
  /// In en, this message translates to:
  /// **'Add to schedule'**
  String get programEditorAddSchedule;

  /// No description provided for @programEditorExerciseConfig.
  ///
  /// In en, this message translates to:
  /// **'Workout structure'**
  String get programEditorExerciseConfig;

  /// No description provided for @programEditorAddSession.
  ///
  /// In en, this message translates to:
  /// **'Add session'**
  String get programEditorAddSession;

  /// No description provided for @programTemplateSessionPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add to which session?'**
  String get programTemplateSessionPickerTitle;

  /// No description provided for @programTemplateSessionPickerBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a session for the \'{name}\' template.'**
  String programTemplateSessionPickerBody(String name);

  /// No description provided for @programEditorAiReapplyTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace the AI exercises with the new plan?'**
  String get programEditorAiReapplyTitle;

  /// No description provided for @programEditorAiReapplyBody.
  ///
  /// In en, this message translates to:
  /// **'Replaces the AI exercises added earlier ({count}) with the new plan. Exercises you added or edited stay.'**
  String programEditorAiReapplyBody(int count);

  /// No description provided for @programEditorAiReapplyReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get programEditorAiReapplyReplace;

  /// No description provided for @programEditorAiReapplyAppend.
  ///
  /// In en, this message translates to:
  /// **'Add after'**
  String get programEditorAiReapplyAppend;

  /// No description provided for @programEditorSessionNameTyped.
  ///
  /// In en, this message translates to:
  /// **'{type} session'**
  String programEditorSessionNameTyped(String type);

  /// No description provided for @programEditorSessionNameNumbered.
  ///
  /// In en, this message translates to:
  /// **'{type} session {index}'**
  String programEditorSessionNameNumbered(String type, int index);

  /// No description provided for @programEditorSessionUp.
  ///
  /// In en, this message translates to:
  /// **'Move session up'**
  String get programEditorSessionUp;

  /// No description provided for @programEditorSessionDown.
  ///
  /// In en, this message translates to:
  /// **'Move session down'**
  String get programEditorSessionDown;

  /// No description provided for @programEditorSessionReset.
  ///
  /// In en, this message translates to:
  /// **'Reset session'**
  String get programEditorSessionReset;

  /// No description provided for @programEditorSessionResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset this session?'**
  String get programEditorSessionResetTitle;

  /// No description provided for @programEditorSessionResetBody.
  ///
  /// In en, this message translates to:
  /// **'Every exercise in \'{name}\' will be cleared. The session itself and other sessions stay.'**
  String programEditorSessionResetBody(String name);

  /// No description provided for @programEditorSessionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add exercises to build this session.'**
  String get programEditorSessionEmpty;

  /// No description provided for @programEditorAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get programEditorAdd;

  /// No description provided for @programEditorAddExercise.
  ///
  /// In en, this message translates to:
  /// **'Add exercise'**
  String get programEditorAddExercise;

  /// No description provided for @programEditorExercise.
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get programEditorExercise;

  /// No description provided for @programEditorExerciseUp.
  ///
  /// In en, this message translates to:
  /// **'Move exercise up'**
  String get programEditorExerciseUp;

  /// No description provided for @programEditorExerciseDown.
  ///
  /// In en, this message translates to:
  /// **'Move exercise down'**
  String get programEditorExerciseDown;

  /// No description provided for @programEditorExerciseMoveSession.
  ///
  /// In en, this message translates to:
  /// **'Move to another session'**
  String get programEditorExerciseMoveSession;

  /// No description provided for @programEditorExerciseMoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Which session should it move to?'**
  String get programEditorExerciseMoveTitle;

  /// No description provided for @programEditorExerciseMoveBody.
  ///
  /// In en, this message translates to:
  /// **'Pick the session to move \'{name}\' into.'**
  String programEditorExerciseMoveBody(String name);

  /// No description provided for @programEditorSets.
  ///
  /// In en, this message translates to:
  /// **'Sets'**
  String get programEditorSets;

  /// No description provided for @programEditorReps.
  ///
  /// In en, this message translates to:
  /// **'Reps'**
  String get programEditorReps;

  /// No description provided for @programEditorWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight kg'**
  String get programEditorWeight;

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name} kept workouts and meals on plan this week. Hold this rhythm and consider nudging the training intensity up next week.'**
  String reportsDemoSummarySteadyThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name} kept workouts and meals on plan that week. Hold this rhythm and consider nudging the training intensity up gradually.'**
  String reportsDemoSummarySteadyPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s workouts slipped this week. Ask whether the schedule was tight, then rebuild with a shorter routine next week.'**
  String reportsDemoSummaryCompletionThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s workouts slipped that week. Ask whether the schedule was tight, then rebuild with a shorter routine.'**
  String reportsDemoSummaryCompletionPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name} skipped a few exercises this week. Check whether pain or difficulty was the reason and agree on substitutes together.'**
  String reportsDemoSummarySkippedThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name} skipped a few exercises that week. Check whether pain or difficulty was the reason and agree on substitutes together.'**
  String reportsDemoSummarySkippedPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name} had salty meals often this week. Set one small goal together, such as cutting back on soups and processed foods.'**
  String reportsDemoSummarySodiumThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name} had salty meals often that week. Set one small goal together, such as cutting back on soups and processed foods.'**
  String reportsDemoSummarySodiumPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name} had sweets and sugary drinks often this week. Start by suggesting fruit or nuts as snacks instead.'**
  String reportsDemoSummarySugarThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name} had sweets and sugary drinks often that week. Start by suggesting fruit or nuts as snacks instead.'**
  String reportsDemoSummarySugarPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s intake drifted from the calorie goal this week. Review the meal log together for skipped or oversized meals.'**
  String reportsDemoSummaryCaloriesThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s intake drifted from the calorie goal that week. Review the meal log together for skipped or oversized meals.'**
  String reportsDemoSummaryCaloriesPastWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s carb, protein and fat split differed from the goals this week. Go over meal composition together to rebalance it.'**
  String reportsDemoSummaryMacroThisWeek(String name);

  /// 데모 AI 요약 머리 문장(#2669, #2775). 그 주 가장 위험한 주의사항 종류마다 하나, 이번 주(ThisWeek)와 지난 주(PastWeek) 변형.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s carb, protein and fat split differed from the goals that week. Go over meal composition together to rebalance it.'**
  String reportsDemoSummaryMacroPastWeek(String name);

  /// No description provided for @reportsBackToList.
  ///
  /// In en, this message translates to:
  /// **'Member list'**
  String get reportsBackToList;

  /// No description provided for @reportsAverageSodium.
  ///
  /// In en, this message translates to:
  /// **'Average sodium'**
  String get reportsAverageSodium;

  /// No description provided for @reportsFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Trainer feedback'**
  String get reportsFeedbackTitle;

  /// No description provided for @reportsFeedbackDraftNote.
  ///
  /// In en, this message translates to:
  /// **'A draft filled in from this week\'s figures. Check it over before sending.'**
  String get reportsFeedbackDraftNote;

  /// No description provided for @reportsFeedbackUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get reportsFeedbackUndo;

  /// No description provided for @reportsFeedbackRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get reportsFeedbackRedo;

  /// No description provided for @reportsFeedbackSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get reportsFeedbackSave;

  /// No description provided for @reportsFeedbackSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get reportsFeedbackSaving;

  /// No description provided for @reportsFeedbackSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved the feedback draft.'**
  String get reportsFeedbackSaved;

  /// No description provided for @reportsFeedbackSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the draft. Please try again.'**
  String get reportsFeedbackSaveFailed;

  /// No description provided for @reportsFeedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Write coaching feedback for the member.'**
  String get reportsFeedbackHint;

  /// No description provided for @reportsAiTitle.
  ///
  /// In en, this message translates to:
  /// **'This week\'s summary'**
  String get reportsAiTitle;

  /// No description provided for @reportsAiNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week\'s coaching'**
  String get reportsAiNextWeek;

  /// No description provided for @reportsAiMoreWatchpoints.
  ///
  /// In en, this message translates to:
  /// **'{count} more — see the full report.'**
  String reportsAiMoreWatchpoints(int count);

  /// No description provided for @reportsActionSodium.
  ///
  /// In en, this message translates to:
  /// **'Ask them to leave half the broth and the pickled sides.'**
  String get reportsActionSodium;

  /// No description provided for @reportsActionSugar.
  ///
  /// In en, this message translates to:
  /// **'Some days went over the {target}g sugar target. Start with drinks and snacks.'**
  String reportsActionSugar(String target);

  /// No description provided for @reportsActionLowCompletion.
  ///
  /// In en, this message translates to:
  /// **'Drop the program a notch so they finish it first.'**
  String get reportsActionLowCompletion;

  /// No description provided for @reportsActionHighCompletion.
  ///
  /// In en, this message translates to:
  /// **'Good pace. Add a set or a little weight next week.'**
  String get reportsActionHighCompletion;

  /// No description provided for @reportsActionSkipped.
  ///
  /// In en, this message translates to:
  /// **'Prepare alternatives for {names} for the next PT.'**
  String reportsActionSkipped(String names);

  /// No description provided for @reportsActionUnlogged.
  ///
  /// In en, this message translates to:
  /// **'{days} days went unlogged. Build the logging habit first.'**
  String reportsActionUnlogged(int days);

  /// No description provided for @reportsActionCalories.
  ///
  /// In en, this message translates to:
  /// **'Intake is under the {target}kcal target. Suggest one protein-led meal.'**
  String reportsActionCalories(String target);

  /// No description provided for @reportsAiGenerated.
  ///
  /// In en, this message translates to:
  /// **'AI generated'**
  String get reportsAiGenerated;

  /// No description provided for @reportsAiUseAsDraft.
  ///
  /// In en, this message translates to:
  /// **'Use as feedback'**
  String get reportsAiUseAsDraft;

  /// No description provided for @reportsAiRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get reportsAiRegenerate;

  /// No description provided for @reportsAiFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the summary. Please try again.'**
  String get reportsAiFailed;

  /// No description provided for @reportsPdfFallbackClient.
  ///
  /// In en, this message translates to:
  /// **'member'**
  String get reportsPdfFallbackClient;

  /// No description provided for @reportsPdfDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly coaching report'**
  String get reportsPdfDocTitle;

  /// No description provided for @reportsPdfClient.
  ///
  /// In en, this message translates to:
  /// **'Member  {name}'**
  String reportsPdfClient(String name);

  /// No description provided for @reportsPdfPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period  {start} – {end}'**
  String reportsPdfPeriod(String start, String end);

  /// No description provided for @reportsPdfSectionMetrics.
  ///
  /// In en, this message translates to:
  /// **'Key metrics'**
  String get reportsPdfSectionMetrics;

  /// No description provided for @reportsPdfSectionChange.
  ///
  /// In en, this message translates to:
  /// **'Change from last week'**
  String get reportsPdfSectionChange;

  /// No description provided for @reportsPdfSectionTrend.
  ///
  /// In en, this message translates to:
  /// **'Weekly trend (Mon–Sun)'**
  String get reportsPdfSectionTrend;

  /// No description provided for @reportsPdfSectionDaily.
  ///
  /// In en, this message translates to:
  /// **'Workouts by day'**
  String get reportsPdfSectionDaily;

  /// No description provided for @reportsPdfBullet.
  ///
  /// In en, this message translates to:
  /// **'• {label}: {value}'**
  String reportsPdfBullet(String label, String value);

  /// No description provided for @reportsPdfDay.
  ///
  /// In en, this message translates to:
  /// **'{weekday}: {completion} · {exercises}'**
  String reportsPdfDay(String weekday, String completion, String exercises);

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

  /// No description provided for @reportsPdfLabelSessionCount.
  ///
  /// In en, this message translates to:
  /// **'PT completed'**
  String get reportsPdfLabelSessionCount;

  /// No description provided for @reportsPdfLabelSodiumOver.
  ///
  /// In en, this message translates to:
  /// **'Days over sodium target'**
  String get reportsPdfLabelSodiumOver;

  /// No description provided for @reportsPdfLabelCalories.
  ///
  /// In en, this message translates to:
  /// **'Average calories'**
  String get reportsPdfLabelCalories;

  /// No description provided for @reportsPdfLabelSugar.
  ///
  /// In en, this message translates to:
  /// **'Average sugar'**
  String get reportsPdfLabelSugar;

  /// No description provided for @reportsPdfLabelCaloriesShort.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get reportsPdfLabelCaloriesShort;

  /// No description provided for @reportsPdfLabelSodiumShort.
  ///
  /// In en, this message translates to:
  /// **'Sodium'**
  String get reportsPdfLabelSodiumShort;

  /// No description provided for @reportsPdfLabelSugarShort.
  ///
  /// In en, this message translates to:
  /// **'Sugar'**
  String get reportsPdfLabelSugarShort;

  /// No description provided for @reportsPdfValuePercent.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String reportsPdfValuePercent(String value);

  /// No description provided for @reportsPdfValueMg.
  ///
  /// In en, this message translates to:
  /// **'{value}mg'**
  String reportsPdfValueMg(String value);

  /// No description provided for @reportsPdfValueKcal.
  ///
  /// In en, this message translates to:
  /// **'{value}kcal'**
  String reportsPdfValueKcal(String value);

  /// No description provided for @reportsPdfValueGram.
  ///
  /// In en, this message translates to:
  /// **'{value}g'**
  String reportsPdfValueGram(String value);

  /// No description provided for @reportsPdfValueDays.
  ///
  /// In en, this message translates to:
  /// **'{value} days'**
  String reportsPdfValueDays(String value);

  /// No description provided for @reportsPdfValueSessions.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String reportsPdfValueSessions(String value);

  /// No description provided for @reportsPdfAttendance.
  ///
  /// In en, this message translates to:
  /// **'{done}/{booked} ({rate}%)'**
  String reportsPdfAttendance(String done, String booked, String rate);

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

  /// No description provided for @unitMg.
  ///
  /// In en, this message translates to:
  /// **'mg'**
  String get unitMg;

  /// No description provided for @unitGram.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get unitGram;

  /// No description provided for @a11yRemoveExercise.
  ///
  /// In en, this message translates to:
  /// **'Remove exercise'**
  String get a11yRemoveExercise;

  /// No description provided for @a11yRemoveCertification.
  ///
  /// In en, this message translates to:
  /// **'Remove certification'**
  String get a11yRemoveCertification;

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

  /// No description provided for @a11ySendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get a11ySendMessage;

  /// AI 1~3단계 화면에서 AI 추천 대신 빈 템플릿으로 바로 넘어가는 버튼.
  ///
  /// In en, this message translates to:
  /// **'Build manually'**
  String get aiManualCreate;

  /// 직접 만들기로 넘어간 뒤 다시 AI 마법사 화면으로 돌아가는 링크.
  ///
  /// In en, this message translates to:
  /// **'Back to AI suggestions'**
  String get aiReturnToWizard;

  /// 채팅 스레드에서 날이 바뀌는 자리의 날짜 구분선. 요일까지 적는다(ko: 2026년 9월 14일 월요일, en: Monday, September 14, 2026).
  ///
  /// In en, this message translates to:
  /// **'{date}'**
  String chatDateDivider(DateTime date);

  /// Tag on a pending assigned routine that the AI suggested.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get clientWorkoutSourceAi;

  /// No description provided for @coachClientDemographics.
  ///
  /// In en, this message translates to:
  /// **'{gender} · Age {age}'**
  String coachClientDemographics(String gender, int age);

  /// Age-only identity label when the member has no gender on file or the server hides it (#2814, #2870).
  ///
  /// In en, this message translates to:
  /// **'Age {age}'**
  String coachClientAge(int age);

  /// No description provided for @coachTemplateMenu.
  ///
  /// In en, this message translates to:
  /// **'Template menu'**
  String get coachTemplateMenu;

  /// No description provided for @routineFormDecrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get routineFormDecrease;

  /// No description provided for @routineFormIncrease.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get routineFormIncrease;

  /// No description provided for @reportsPending.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get reportsPending;

  /// No description provided for @reportsCountPeople.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String reportsCountPeople(int count);

  /// No description provided for @reportsSortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get reportsSortLabel;

  /// No description provided for @reportsSortPriority.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get reportsSortPriority;

  /// No description provided for @reportsSortName.
  ///
  /// In en, this message translates to:
  /// **'Name A–Z'**
  String get reportsSortName;

  /// No description provided for @reportsSortNameDescending.
  ///
  /// In en, this message translates to:
  /// **'Name Z–A'**
  String get reportsSortNameDescending;

  /// No description provided for @reportsSentSortUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread first'**
  String get reportsSentSortUnread;

  /// No description provided for @reportsSendProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total} sent'**
  String reportsSendProgress(int done, int total);

  /// No description provided for @reportsSendPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String reportsSendPercent(int percent);

  /// No description provided for @reportsQueueAllSent.
  ///
  /// In en, this message translates to:
  /// **'Every report for this week has been sent'**
  String get reportsQueueAllSent;

  /// No description provided for @reportsSentColumn.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get reportsSentColumn;

  /// No description provided for @reportsSentColumnEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reports sent yet'**
  String get reportsSentColumnEmpty;

  /// No description provided for @reportsSentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View sent report'**
  String get reportsSentSubtitle;

  /// No description provided for @reportsOpenDraft.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get reportsOpenDraft;

  /// No description provided for @reportsReasonUnknown.
  ///
  /// In en, this message translates to:
  /// **'Loading figures'**
  String get reportsReasonUnknown;

  /// No description provided for @reportsReasonCompletion.
  ///
  /// In en, this message translates to:
  /// **'{percent}% complete'**
  String reportsReasonCompletion(int percent);

  /// No description provided for @reportsReasonSessionDone.
  ///
  /// In en, this message translates to:
  /// **'PT {count} done'**
  String reportsReasonSessionDone(int count);

  /// No description provided for @reportsReasonSlump.
  ///
  /// In en, this message translates to:
  /// **'Down {points}%p late'**
  String reportsReasonSlump(int points);

  /// No description provided for @reportsReasonRising.
  ///
  /// In en, this message translates to:
  /// **'Up {points}%p late'**
  String reportsReasonRising(int points);

  /// No description provided for @reportsReasonFullLog.
  ///
  /// In en, this message translates to:
  /// **'Logged all 7 days'**
  String get reportsReasonFullLog;

  /// No description provided for @reportsReasonOnboarding.
  ///
  /// In en, this message translates to:
  /// **'New · settling in'**
  String get reportsReasonOnboarding;

  /// No description provided for @reportsReasonSteady.
  ///
  /// In en, this message translates to:
  /// **'On track'**
  String get reportsReasonSteady;

  /// No description provided for @reportsSentOn.
  ///
  /// In en, this message translates to:
  /// **'Sent {date}'**
  String reportsSentOn(String date);

  /// No description provided for @reportsSentRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get reportsSentRead;

  /// No description provided for @reportsSentUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get reportsSentUnread;

  /// No description provided for @reportsBackToWorkbench.
  ///
  /// In en, this message translates to:
  /// **'This week\'s reports'**
  String get reportsBackToWorkbench;

  /// No description provided for @reportsSentHeadline.
  ///
  /// In en, this message translates to:
  /// **'Report sent to {name}'**
  String reportsSentHeadline(String name);

  /// No description provided for @reportsSentAt.
  ///
  /// In en, this message translates to:
  /// **'Sent {date} {time}'**
  String reportsSentAt(String date, String time);

  /// No description provided for @reportsSentRewrite.
  ///
  /// In en, this message translates to:
  /// **'Rewrite from this'**
  String get reportsSentRewrite;

  /// No description provided for @reportsHistoryButton.
  ///
  /// In en, this message translates to:
  /// **'Past reports'**
  String get reportsHistoryButton;

  /// No description provided for @reportsViewSent.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get reportsViewSent;

  /// No description provided for @reportsHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s past reports'**
  String reportsHistoryTitle(String name);

  /// No description provided for @reportsHistoryBack.
  ///
  /// In en, this message translates to:
  /// **'Past reports'**
  String get reportsHistoryBack;

  /// No description provided for @reportsHistoryUnsent.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get reportsHistoryUnsent;

  /// No description provided for @reportsHistoryThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get reportsHistoryThisWeek;

  /// No description provided for @reportsHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reports sent yet'**
  String get reportsHistoryEmpty;

  /// No description provided for @reportsHistoryLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load past reports'**
  String get reportsHistoryLoadFailed;

  /// No description provided for @reportsHistoryMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get reportsHistoryMore;

  /// No description provided for @reportsHistoryMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load more. Tap to try again.'**
  String get reportsHistoryMoreFailed;

  /// No description provided for @reportsHistorySendCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Sent once} other{Sent {count} times}}'**
  String reportsHistorySendCount(int count);

  /// No description provided for @reportsHistoryPdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get reportsHistoryPdf;

  /// No description provided for @reportsResendTitle.
  ///
  /// In en, this message translates to:
  /// **'Already sent'**
  String get reportsResendTitle;

  /// No description provided for @reportsResendBody.
  ///
  /// In en, this message translates to:
  /// **'You already sent {name} this report on {date} at {time}. Sending it again delivers a second copy to their chat.'**
  String reportsResendBody(String name, String date, String time);

  /// No description provided for @reportsResendConfirm.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get reportsResendConfirm;

  /// No description provided for @reportsSendHistoryFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load send history. Members you\'ve already sent to may show as not sent.'**
  String get reportsSendHistoryFailed;

  /// No description provided for @reportsStepReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reportsStepReview;

  /// No description provided for @reportsStepWrite.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get reportsStepWrite;

  /// No description provided for @reportsStepSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get reportsStepSend;

  /// No description provided for @reportsStepPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get reportsStepPrint;

  /// No description provided for @reportsPrintNeedsPdf.
  ///
  /// In en, this message translates to:
  /// **'You can print once the preview PDF is ready'**
  String get reportsPrintNeedsPdf;

  /// No description provided for @reportsPrintFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the print dialog. Please try again'**
  String get reportsPrintFailed;

  /// No description provided for @reportsStepperLabel.
  ///
  /// In en, this message translates to:
  /// **'Weekly report steps'**
  String get reportsStepperLabel;

  /// No description provided for @reportsStepNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get reportsStepNext;

  /// No description provided for @reportsStepPrev.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get reportsStepPrev;

  /// No description provided for @reportsPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'What the member receives'**
  String get reportsPreviewTitle;

  /// No description provided for @reportsPreviewRecipient.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get reportsPreviewRecipient;

  /// No description provided for @reportsPreviewWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get reportsPreviewWeek;

  /// No description provided for @reportsPreviewDelivery.
  ///
  /// In en, this message translates to:
  /// **'Sent to {name}\'s chat as a PDF file'**
  String reportsPreviewDelivery(String name);

  /// No description provided for @reportsPreviewEditHint.
  ///
  /// In en, this message translates to:
  /// **'To change the text, tap Back to return to the Write step'**
  String get reportsPreviewEditHint;

  /// No description provided for @reportsPreviewGenerating.
  ///
  /// In en, this message translates to:
  /// **'Preparing the preview'**
  String get reportsPreviewGenerating;

  /// No description provided for @reportsPreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t prepare the preview'**
  String get reportsPreviewFailed;

  /// No description provided for @reportsPreviewPage.
  ///
  /// In en, this message translates to:
  /// **'Page {current} of {total}'**
  String reportsPreviewPage(int current, int total);

  /// No description provided for @reportsPreviewPrevPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get reportsPreviewPrevPage;

  /// No description provided for @reportsPreviewNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get reportsPreviewNextPage;

  /// No description provided for @reportsPreviewZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get reportsPreviewZoomIn;

  /// No description provided for @reportsPreviewZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get reportsPreviewZoomOut;

  /// No description provided for @reportsGridPtSession.
  ///
  /// In en, this message translates to:
  /// **'PT'**
  String get reportsGridPtSession;

  /// No description provided for @reportsGridPtPerWeek.
  ///
  /// In en, this message translates to:
  /// **'{count}/week'**
  String reportsGridPtPerWeek(int count);

  /// No description provided for @reportsGridPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal workouts'**
  String get reportsGridPersonal;

  /// No description provided for @reportsGridPersonalUnit.
  ///
  /// In en, this message translates to:
  /// **'Done / assigned'**
  String get reportsGridPersonalUnit;

  /// No description provided for @reportsGridDoneOfAssigned.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total}'**
  String reportsGridDoneOfAssigned(int done, int total);

  /// No description provided for @reportsGridMeals.
  ///
  /// In en, this message translates to:
  /// **'Meal logs'**
  String get reportsGridMeals;

  /// No description provided for @reportsGridMealsUnit.
  ///
  /// In en, this message translates to:
  /// **'Times logged'**
  String get reportsGridMealsUnit;

  /// No description provided for @reportsGridMealCount.
  ///
  /// In en, this message translates to:
  /// **'{count}x'**
  String reportsGridMealCount(int count);

  /// No description provided for @reportsGridCalories.
  ///
  /// In en, this message translates to:
  /// **'Calories eaten'**
  String get reportsGridCalories;

  /// No description provided for @reportsGridCalorieTarget.
  ///
  /// In en, this message translates to:
  /// **'Target {value}'**
  String reportsGridCalorieTarget(String value);

  /// No description provided for @reportsMacroNone.
  ///
  /// In en, this message translates to:
  /// **'No meals logged yet, so macros can\'t be shown'**
  String get reportsMacroNone;

  /// No description provided for @reportsMacroValueOfTarget.
  ///
  /// In en, this message translates to:
  /// **'{name} {value} / {target}g'**
  String reportsMacroValueOfTarget(String name, int value, int target);

  /// No description provided for @reportsMacroShortfall.
  ///
  /// In en, this message translates to:
  /// **'{name} is well under target — worth raising in your feedback'**
  String reportsMacroShortfall(String name);

  /// No description provided for @reportsMemberFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Member\'s weekly feedback'**
  String get reportsMemberFeedbackTitle;

  /// No description provided for @reportsMemberFeedbackAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get reportsMemberFeedbackAttention;

  /// No description provided for @reportsMemberFeedbackNone.
  ///
  /// In en, this message translates to:
  /// **'Not received yet'**
  String get reportsMemberFeedbackNone;

  /// No description provided for @reportsMemberFeedbackNoneHint.
  ///
  /// In en, this message translates to:
  /// **'It shows up here once the member sends their weekly feedback'**
  String get reportsMemberFeedbackNoneHint;

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

  /// No description provided for @reportsMemberFeedbackUnanswered.
  ///
  /// In en, this message translates to:
  /// **'No answer'**
  String get reportsMemberFeedbackUnanswered;

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

  /// No description provided for @reportsMemberFeedbackPainOn.
  ///
  /// In en, this message translates to:
  /// **'{area} ({date})'**
  String reportsMemberFeedbackPainOn(String area, String date);

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

  /// No description provided for @reportsTrendUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this week\'s workout records'**
  String get reportsTrendUnavailable;

  /// No description provided for @reportsTrendNoGoal.
  ///
  /// In en, this message translates to:
  /// **'No goal'**
  String get reportsTrendNoGoal;

  /// No description provided for @reportsExerciseTrend.
  ///
  /// In en, this message translates to:
  /// **'Workout trend'**
  String get reportsExerciseTrend;

  /// No description provided for @reportsWriteFromScratch.
  ///
  /// In en, this message translates to:
  /// **'Write from scratch'**
  String get reportsWriteFromScratch;

  /// No description provided for @reportsCardWeekTitle.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get reportsCardWeekTitle;

  /// No description provided for @reportsCardWeekSubtitle.
  ///
  /// In en, this message translates to:
  /// **'On one axis you can see the days that fell together'**
  String get reportsCardWeekSubtitle;

  /// No description provided for @reportsAiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Written automatically from the figures'**
  String get reportsAiSubtitle;

  /// No description provided for @reportsMemberFeedbackMeta.
  ///
  /// In en, this message translates to:
  /// **'Weekly · submitted {date}'**
  String reportsMemberFeedbackMeta(String date);

  /// No description provided for @reportsTrendSubtitle.
  ///
  /// In en, this message translates to:
  /// **'By type · last {weeks} weeks'**
  String reportsTrendSubtitle(int weeks);

  /// No description provided for @reportsTrendCenterLabel.
  ///
  /// In en, this message translates to:
  /// **'of goal'**
  String get reportsTrendCenterLabel;

  /// No description provided for @reportsTrendWeeklyGoal.
  ///
  /// In en, this message translates to:
  /// **'Weekly goal {goal}'**
  String reportsTrendWeeklyGoal(String goal);

  /// No description provided for @reportsTrendRunDown.
  ///
  /// In en, this message translates to:
  /// **'Down {weeks} weeks running'**
  String reportsTrendRunDown(int weeks);

  /// No description provided for @reportsTrendRunUp.
  ///
  /// In en, this message translates to:
  /// **'Up {weeks} weeks running'**
  String reportsTrendRunUp(int weeks);

  /// No description provided for @reportsTrendVsLastWeek.
  ///
  /// In en, this message translates to:
  /// **'{delta}% vs last week'**
  String reportsTrendVsLastWeek(String delta);

  /// No description provided for @reportsTrendFlat.
  ///
  /// In en, this message translates to:
  /// **'About the same as last week'**
  String get reportsTrendFlat;

  /// No description provided for @reportsTrendNoHistory.
  ///
  /// In en, this message translates to:
  /// **'No earlier week to compare'**
  String get reportsTrendNoHistory;

  /// No description provided for @reportsTrendRate.
  ///
  /// In en, this message translates to:
  /// **'Weekly goal rate'**
  String get reportsTrendRate;

  /// No description provided for @reportsTrendAverage.
  ///
  /// In en, this message translates to:
  /// **'{weeks}-week average'**
  String reportsTrendAverage(int weeks);

  /// No description provided for @reportsTrendRateFalling.
  ///
  /// In en, this message translates to:
  /// **'Goal rate down {weeks} weeks running'**
  String reportsTrendRateFalling(int weeks);

  /// No description provided for @reportsTrendTracked.
  ///
  /// In en, this message translates to:
  /// **'{count} tracked exercises — picked automatically'**
  String reportsTrendTracked(int count);

  /// No description provided for @reportsTrendTrackedTimes.
  ///
  /// In en, this message translates to:
  /// **'{count}×'**
  String reportsTrendTrackedTimes(int count);

  /// No description provided for @reportsCalorieThisWeekAvg.
  ///
  /// In en, this message translates to:
  /// **'This week {kcal} kcal/day'**
  String reportsCalorieThisWeekAvg(String kcal);

  /// No description provided for @reportsCalorieBaselineAvg.
  ///
  /// In en, this message translates to:
  /// **'Past {weeks} weeks {kcal} kcal/day'**
  String reportsCalorieBaselineAvg(int weeks, String kcal);

  /// No description provided for @reportsGridCalorieTargetDefault.
  ///
  /// In en, this message translates to:
  /// **'Default {kcal}'**
  String reportsGridCalorieTargetDefault(String kcal);

  /// No description provided for @summaryBasisDefault.
  ///
  /// In en, this message translates to:
  /// **'default target'**
  String get summaryBasisDefault;

  /// No description provided for @summaryBasisPersonal.
  ///
  /// In en, this message translates to:
  /// **'personal target'**
  String get summaryBasisPersonal;

  /// No description provided for @summaryDirOver.
  ///
  /// In en, this message translates to:
  /// **'above'**
  String get summaryDirOver;

  /// No description provided for @summaryDirUnder.
  ///
  /// In en, this message translates to:
  /// **'below'**
  String get summaryDirUnder;

  /// No description provided for @summaryCompletionLow.
  ///
  /// In en, this message translates to:
  /// **'Avg workout completion {pct}% · below the {threshold}% bar'**
  String summaryCompletionLow(String pct, String threshold);

  /// No description provided for @summaryCompletionTopic.
  ///
  /// In en, this message translates to:
  /// **'workout completion at {pct}%'**
  String summaryCompletionTopic(String pct);

  /// No description provided for @summaryCompletionAvg.
  ///
  /// In en, this message translates to:
  /// **'Avg workout completion {pct}%'**
  String summaryCompletionAvg(String pct);

  /// No description provided for @summarySkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped: {names}'**
  String summarySkipped(String names);

  /// No description provided for @summarySkippedTopic.
  ///
  /// In en, this message translates to:
  /// **'{count} skipped exercise(s)'**
  String summarySkippedTopic(String count);

  /// No description provided for @summarySodium.
  ///
  /// In en, this message translates to:
  /// **'Avg sodium {avg}mg · over the {basis} of {target}mg on {days} day(s)'**
  String summarySodium(String avg, String basis, String target, String days);

  /// No description provided for @summarySodiumOverTopic.
  ///
  /// In en, this message translates to:
  /// **'sodium over target on {days} day(s)'**
  String summarySodiumOverTopic(String days);

  /// No description provided for @summarySodiumAvgTopic.
  ///
  /// In en, this message translates to:
  /// **'avg sodium {avg}mg'**
  String summarySodiumAvgTopic(String avg);

  /// No description provided for @summarySugar.
  ///
  /// In en, this message translates to:
  /// **'Avg sugar {avg}g · over the {basis} of {target}g on {days} day(s)'**
  String summarySugar(String avg, String basis, String target, String days);

  /// No description provided for @summarySugarOverTopic.
  ///
  /// In en, this message translates to:
  /// **'sugar over target on {days} day(s)'**
  String summarySugarOverTopic(String days);

  /// No description provided for @summarySugarAvgTopic.
  ///
  /// In en, this message translates to:
  /// **'avg sugar {avg}g'**
  String summarySugarAvgTopic(String avg);

  /// No description provided for @summaryCalories.
  ///
  /// In en, this message translates to:
  /// **'Avg calories {avg}kcal · {pct}% {direction} the {basis} of {target}kcal'**
  String summaryCalories(
    String avg,
    String basis,
    String target,
    String direction,
    String pct,
  );

  /// No description provided for @summaryCaloriesTopic.
  ///
  /// In en, this message translates to:
  /// **'calories {direction} target'**
  String summaryCaloriesTopic(String direction);

  /// No description provided for @summaryCaloriesAvg.
  ///
  /// In en, this message translates to:
  /// **'Avg calories {avg}kcal'**
  String summaryCaloriesAvg(String avg);

  /// No description provided for @summaryMacro.
  ///
  /// In en, this message translates to:
  /// **'Avg {label} {avg}g · {pct}% {direction} the personal target of {target}g'**
  String summaryMacro(
    String label,
    String avg,
    String target,
    String direction,
    String pct,
  );

  /// No description provided for @summaryMacroTopic.
  ///
  /// In en, this message translates to:
  /// **'{label} {direction} target'**
  String summaryMacroTopic(String label, String direction);

  /// No description provided for @summaryMorePoints.
  ///
  /// In en, this message translates to:
  /// **'{count} more — see the report'**
  String summaryMorePoints(String count);

  /// No description provided for @summaryHeadlineNoData.
  ///
  /// In en, this message translates to:
  /// **'{name} has no records for the week — plan next week\'s start together.'**
  String summaryHeadlineNoData(String name);

  /// No description provided for @summaryHeadlineSteady.
  ///
  /// In en, this message translates to:
  /// **'{name} stayed within target — the current intensity can stay as is.'**
  String summaryHeadlineSteady(String name);

  /// No description provided for @summaryHeadlineRest.
  ///
  /// In en, this message translates to:
  /// **' Also look at {count} more.'**
  String summaryHeadlineRest(String count);

  /// No description provided for @summaryHeadlineGoodCare.
  ///
  /// In en, this message translates to:
  /// **'{name} kept {kept} on track; next week, let\'s also work on {top}.{rest}'**
  String summaryHeadlineGoodCare(
    String name,
    String kept,
    String top,
    String rest,
  );

  /// No description provided for @summaryHeadlineNeedsAdjust.
  ///
  /// In en, this message translates to:
  /// **'{name} was off target on {top} — next week needs adjusting.{rest}'**
  String summaryHeadlineNeedsAdjust(String name, String top, String rest);

  /// No description provided for @reportsPdfFileSuffix.
  ///
  /// In en, this message translates to:
  /// **'weekly_report'**
  String get reportsPdfFileSuffix;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Diet analysis'**
  String get clientDietAnalysisTitle;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'No meals logged today yet.'**
  String get clientDietAnalysisTodayEmpty;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'{food} at {slot, select, breakfast{breakfast} lunch{lunch} dinner{dinner} lateNight{late-night snack} other{snack}} ({foodValue}) pushed today\'s {nutrient, select, sodium{sodium} sugar{sugar} other{calories}} to {value}, {ratio}x the {target} goal.'**
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
  /// In en, this message translates to:
  /// **'{slot, select, breakfast{Breakfast} lunch{Lunch} dinner{Dinner} lateNight{Late-night snack} other{Snack}} ({foodValue}) pushed today\'s {nutrient, select, sodium{sodium} sugar{sugar} other{calories}} to {value}, {ratio}x the {target} goal.'**
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
  /// In en, this message translates to:
  /// **'Protein is at {value}, {gap} short of the goal.'**
  String clientDietAnalysisTodayProteinShort(String value, String gap);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Protein is at {value}, {gap} short of the goal, and the 4-week average of {avg} a day stays low.'**
  String clientDietAnalysisTodayProteinChronic(
    String value,
    String gap,
    String avg,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'No {slot, select, breakfast{breakfast} lunch{lunch} dinner{dinner} lateNight{late-night snack} other{snack}} logged yet.'**
  String clientDietAnalysisTodayMissing(String slot);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'{kcal} today, evenly within the goals.'**
  String clientDietAnalysisTodayGood(String kcal);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'No meals logged this week yet.'**
  String get clientDietAnalysisWeekEmpty;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Skipped breakfast on {days} of {logged} logged days {scope, select, last{last week} other{this week}}.'**
  String clientDietAnalysisWeekSkipBreakfast(
    String scope,
    int logged,
    int days,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Skipped breakfast on {days} of {logged} logged days {scope, select, last{last week} other{this week}}, snacking instead on {snackDays}.'**
  String clientDietAnalysisWeekSkipBreakfastSnack(
    String scope,
    int logged,
    int days,
    int snackDays,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'{nutrient, select, sodium{Sodium} sugar{Sugar} other{Calories}} went over the goal on {days} of {logged} logged days {scope, select, last{last week} other{this week}}.'**
  String clientDietAnalysisWeekOver(
    String scope,
    int logged,
    int days,
    String nutrient,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'The biggest was {food} at {weekday, select, 0{Monday} 1{Tuesday} 2{Wednesday} 3{Thursday} 4{Friday} 5{Saturday} other{Sunday}} {slot, select, breakfast{breakfast} lunch{lunch} dinner{dinner} lateNight{late-night snack} other{snack}} ({foodValue}).'**
  String clientDietAnalysisWeekCause(
    String weekday,
    String slot,
    String food,
    String foodValue,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Protein fell below 80% of the goal on {days} of {logged} logged days {scope, select, last{last week} other{this week}}.'**
  String clientDietAnalysisWeekProteinShort(String scope, int logged, int days);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'All {days} logged days {scope, select, last{last week} other{this week}} stayed within the goals.'**
  String clientDietAnalysisWeekGood(String scope, int days);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석` — 이번 주 근거·비교 문장.
  ///
  /// In en, this message translates to:
  /// **'{food} replaced breakfast most often ({count} times).'**
  String clientDietAnalysisWeekBreakfastSnackFood(String food, int count);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석` — 이번 주 근거·비교 문장.
  ///
  /// In en, this message translates to:
  /// **'Those days averaged {value} a day.'**
  String clientDietAnalysisWeekProteinAvg(String value);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석` — 이번 주 근거·비교 문장.
  ///
  /// In en, this message translates to:
  /// **'Averaged {kcal} and {protein} protein a day.'**
  String clientDietAnalysisWeekGoodAvg(String kcal, String protein);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석` — 이번 주 근거·비교 문장.
  ///
  /// In en, this message translates to:
  /// **'{way, select, more{Up from last week} less{Down from last week} other{About the same as last week}} ({prevDays} of {prevLogged} days).'**
  String clientDietAnalysisWeekVsLast(int prevLogged, int prevDays, String way);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Only {days} days logged in the last 4 weeks. The trend shows after 7.'**
  String clientDietAnalysisAllFew(int days);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'In the last 4 weeks, {slot, select, breakfast{breakfast} lunch{lunch} dinner{dinner} lateNight{late-night snack} other{snack}} sodium went over half the goal {days} times.'**
  String clientDietAnalysisAllSlotSodium(String slot, int days);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Carbs made up {pct}% of calories in the last 4 weeks.'**
  String clientDietAnalysisAllCarbHeavy(int pct);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Protein made up only {pct}% of calories in the last 4 weeks.'**
  String clientDietAnalysisAllProteinLight(int pct);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Days meeting the protein goal rose from {before} in the prior 2 weeks to {after} in the last 2 weeks.'**
  String clientDietAnalysisAllProteinTrendUp(int before, int after);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Days meeting the protein goal fell from {before} in the prior 2 weeks to {after} in the last 2 weeks.'**
  String clientDietAnalysisAllProteinTrendDown(int before, int after);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'{food} was the most common {slot, select, breakfast{breakfast} lunch{lunch} dinner{dinner} lateNight{late-night snack} other{snack}} in the last 4 weeks ({count} times).'**
  String clientDietAnalysisAllFrequent(String slot, String food, int count);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'{food1} and {food2} make up much of the last 4 weeks\' log.'**
  String clientDietAnalysisAllRepeated(String food1, String food2);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'{days} days logged in the last 4 weeks, with an even trend.'**
  String clientDietAnalysisAllGood(int days);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Mostly {food1} ({count1} times).'**
  String clientDietAnalysisFoodsOne(String food1, int count1);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Mostly {food1} ({count1} times) and {food2} ({count2} times).'**
  String clientDietAnalysisFoodsTwo(
    String food1,
    int count1,
    String food2,
    int count2,
  );

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Recommend this {slot, select, breakfast{for breakfast} lunch{for lunch} dinner{for dinner} lateNight{as a late-night snack} other{as a snack}} to the member?'**
  String clientDietRecQuestion(String slot);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Recommend this for the next meal to the member?'**
  String get clientDietRecQuestionNext;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'AI pick {index} / {total}'**
  String clientDietRecCounter(int index, int total);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get clientDietRecNo;

  /// AI 식단 추천 카운터 왼쪽 꺾쇠 툴팁 — 같은 묶음 안 앞 후보로.
  ///
  /// In en, this message translates to:
  /// **'Previous pick'**
  String get clientDietRecPrev;

  /// AI 식단 추천 카운터 오른쪽 꺾쇠 툴팁 — 같은 묶음 안 다음 후보로(거절 아님).
  ///
  /// In en, this message translates to:
  /// **'Next pick'**
  String get clientDietRecForward;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Yes, recommend'**
  String get clientDietRecYes;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'You passed on all {count} AI picks.'**
  String clientDietRecExhausted(int count);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get clientDietRecRestart;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'See other menus'**
  String get clientDietRecMore;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'You recommended this on {date}. It\'s on the member\'s home as a trainer pick.'**
  String clientDietRecActive(String date);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get clientDietRecChange;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'The member had the recommended {name} for {slot, select, breakfast{breakfast} lunch{lunch} dinner{dinner} lateNight{late-night snack} other{snack}} on {date}.'**
  String clientDietRecResolved(String name, String date, String slot);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'The member had the recommended {name} on {date}.'**
  String clientDietRecResolvedNoSlot(String name, String date);

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'See next pick'**
  String get clientDietRecNext;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the pick. Please try again.'**
  String get clientDietRecConfirmFailed;

  /// 트레이너웹 회원 상세 식단 탭 `식단 분석`·`AI 식단 추천` (#2379).
  ///
  /// In en, this message translates to:
  /// **'{kcal}kcal · protein {protein}g · sodium {sodium}mg'**
  String clientDietRecNutrition(String kcal, String protein, String sodium);

  /// 트레이너웹 AI 식단 추천의 끼니 배지 (#2379).
  ///
  /// In en, this message translates to:
  /// **'{slot, select, breakfast{Breakfast} lunch{Lunch} dinner{Dinner} lateNight{Late-night snack} other{Snack}}'**
  String clientDietRecSlot(String slot);

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password?'**
  String get authForgotPassword;

  /// No description provided for @passwordResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get passwordResetTitle;

  /// No description provided for @passwordResetRequestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll email a reset code to the address you signed up with.'**
  String get passwordResetRequestSubtitle;

  /// No description provided for @passwordResetSendAction.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get passwordResetSendAction;

  /// No description provided for @passwordResetHaveCode.
  ///
  /// In en, this message translates to:
  /// **'I already have a code'**
  String get passwordResetHaveCode;

  /// No description provided for @passwordResetSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get passwordResetSentTitle;

  /// Shown after a reset request. Same text whether or not the account exists.
  ///
  /// In en, this message translates to:
  /// **'If an account uses {email}, we\'ve sent a code you can use once within {minutes} minutes.'**
  String passwordResetSentBody(String email, int minutes);

  /// No description provided for @passwordResetConfirmSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code from the email and your new password.'**
  String get passwordResetConfirmSubtitle;

  /// No description provided for @passwordResetCodeHint.
  ///
  /// In en, this message translates to:
  /// **'16-character reset code'**
  String get passwordResetCodeHint;

  /// No description provided for @passwordResetCodeEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get passwordResetCodeEmpty;

  /// No description provided for @passwordResetCodeMalformed.
  ///
  /// In en, this message translates to:
  /// **'Enter the 16-character code from the email'**
  String get passwordResetCodeMalformed;

  /// No description provided for @passwordResetCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'This code is wrong or has expired. Request a new one.'**
  String get passwordResetCodeInvalid;

  /// No description provided for @passwordResetConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Save new password'**
  String get passwordResetConfirmAction;

  /// No description provided for @passwordResetResend.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get passwordResetResend;

  /// No description provided for @passwordResetDemoNote.
  ///
  /// In en, this message translates to:
  /// **'Demo mode doesn\'t send email. The code is filled in for you.'**
  String get passwordResetDemoNote;

  /// No description provided for @passwordResetUnavailable.
  ///
  /// In en, this message translates to:
  /// **'We can\'t send reset emails right now. Please contact support.'**
  String get passwordResetUnavailable;

  /// No description provided for @passwordResetDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Password reset'**
  String get passwordResetDoneTitle;

  /// No description provided for @passwordResetDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your new password. You\'ve been signed out on every device.'**
  String get passwordResetDoneBody;

  /// No description provided for @passwordResetBackToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Go to sign in'**
  String get passwordResetBackToSignIn;

  /// No description provided for @passwordResetTooMany.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again in a moment.'**
  String get passwordResetTooMany;

  /// No description provided for @passwordResetTemporaryFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete the request. Please try again shortly.'**
  String get passwordResetTemporaryFailure;

  /// Title of the banner shown when a newer web release has been deployed while this tab is open (#3023).
  ///
  /// In en, this message translates to:
  /// **'A new version is available'**
  String get releaseUpdateTitle;

  /// Body of the new-release banner.
  ///
  /// In en, this message translates to:
  /// **'Reload to get the latest version. Save anything you\'re working on first.'**
  String get releaseUpdateMessage;

  /// Button that reloads the page to load the new release.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get releaseUpdateReload;

  /// Tooltip of the button that hides the new-release banner for this release.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
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
