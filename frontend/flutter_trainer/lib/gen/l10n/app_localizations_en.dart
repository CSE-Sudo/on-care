// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'On-Care Trainer';

  @override
  String get scheduleStatusUpcoming => 'Upcoming';

  @override
  String get scheduleStatusDone => 'Done';

  @override
  String get scheduleStatusCancelled => 'Cancelled';

  @override
  String get scheduleStatusNoShow => 'No-show';

  @override
  String get schedCancel => 'Cancel';

  @override
  String get schedNoShow => 'Mark no-show';

  @override
  String get schedCancelTitle => 'Cancel this PT?';

  @override
  String schedCancelConfirm(String time, String name) {
    return 'The $time session with $name will be recorded as cancelled. The entry stays.';
  }

  @override
  String get schedCancelSource => 'Type';

  @override
  String get schedCancelByMember => 'Member';

  @override
  String get schedCancelByTrainer => 'Trainer';

  @override
  String get schedCancelByOther => 'Other';

  @override
  String get schedCancelReasonHint => 'Reason (optional, only you see it)';

  @override
  String get schedCancelFailed =>
      'Couldn\'t cancel the session. Please try again.';

  @override
  String get schedNoShowTitle => 'Record as a no-show?';

  @override
  String schedNoShowConfirm(String time, String name) {
    return 'The $time session with $name will be recorded as a no-show.';
  }

  @override
  String get schedNoShowFailed =>
      'Couldn\'t record the no-show. Please try again.';

  @override
  String schedCancelledBy(String source, String date) {
    return '$source · $date';
  }

  @override
  String get schedDeleteMeansRemove =>
      'Deleting erases the record. Use cancel or no-show for a PT that didn\'t happen.';

  @override
  String get schedDeleteMeansRemoveFinished =>
      'Deleting erases the record. This session is already complete and can\'t be undone.';

  @override
  String get scheduleStatusGap => 'Open';

  @override
  String get sessionTypePersonalTraining => '1:1 PT';

  @override
  String get sessionTypeConsultation => 'Consultation';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navClients => 'Members';

  @override
  String get navSchedule => 'Schedule';

  @override
  String get navCoaching => 'Programs';

  @override
  String get navReports => 'Reports';

  @override
  String get navConsultations => 'Requests';

  @override
  String get actionSave => 'Save';

  @override
  String get actionSaved => 'Saved';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionClose => 'Close';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionChange => 'Change';

  @override
  String get actionBack => 'Back';

  @override
  String get notFoundTitle => 'Page not found';

  @override
  String get notFoundMessage =>
      'The link may be broken, or the page may no longer exist. Please check the address and try again.';

  @override
  String get notFoundGoDashboard => 'Go to dashboard';

  @override
  String get notFoundGoSignIn => 'Go to sign in';

  @override
  String get appWordmarkTrainer => 'Trainer';

  @override
  String get appAvatarFallback => 'T';

  @override
  String sidebarMyTooltip(String name) {
    return '$name · My page';
  }

  @override
  String get authTagline => 'The trainer-only app for managing your members';

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
  String get authSignUpSubtitle =>
      'Create an On-Care account and start managing members';

  @override
  String get authName => 'Name';

  @override
  String get signUpPasswordHint =>
      'Password (8+ characters, letters and numbers)';

  @override
  String get authPasswordConfirm => 'Confirm password';

  @override
  String get authInviteCode => 'Gym invite code';

  @override
  String get authInviteCodeHelp =>
      'Enter the code issued by the gym you work at.';

  @override
  String get authLegalNotice => 'By signing up you agree to';

  @override
  String get authSignUpAndStart => 'Sign up and start';

  @override
  String get authHasAccount => 'Already have an account?';

  @override
  String get authErrEmptyCredentials => 'Enter your email and password';

  @override
  String get authSocialSignInFailed =>
      'Social sign-in failed. Please try again in a moment.';

  @override
  String get authErrSignInFailed =>
      'Sign-in failed. Please try again in a moment.';

  @override
  String get authSessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String get authErrNameEmpty => 'Enter your name';

  @override
  String get authErrNameTooLong => 'Names can be up to 100 characters';

  @override
  String get authErrEmailEmpty => 'Enter your email';

  @override
  String get authErrEmailInvalid => 'Enter a valid email address';

  @override
  String get authErrPasswordEmpty => 'Enter your password';

  @override
  String get authErrPasswordWeak =>
      'Use at least 8 characters, including letters and numbers';

  @override
  String get authErrPasswordTooLong =>
      'Passwords can be up to 64 characters, or fewer if they include Korean or emoji';

  @override
  String get authErrPhoneInvalid => 'Enter your phone number as 010-0000-0000';

  @override
  String get authErrBirthDateInvalid => 'Enter the date of birth as 1996-03-21';

  @override
  String get authErrPasswordMismatch => 'Passwords don\'t match';

  @override
  String get authErrInviteCodeRequired =>
      'Enter the invite code you received from your gym';

  @override
  String get authErrSignUpFailed =>
      'Sign-up failed. Please try again in a moment.';

  @override
  String get dashTitle => 'Dashboard';

  @override
  String get dashActivityRecommendRoutine => 'Try adjusting the program setup.';

  @override
  String get dashActivityRecommendChat => 'Try checking in over Messages.';

  @override
  String get dashActivityRecommendDiet => 'Try leaving feedback in Diet.';

  @override
  String get dashActivityTabProgram => 'Program';

  @override
  String get dashActivityTabChat => 'Messages';

  @override
  String get dashActivityTabDiet => 'Diet';

  @override
  String get dashActivityTabClient => 'Member';

  @override
  String get dashLoadFailed => 'Couldn\'t load the dashboard';

  @override
  String get dashTodayReservations => 'Today\'s bookings';

  @override
  String get dashUnitCount => '';

  @override
  String get dashUnitPeople => '';

  @override
  String get dashSeeInSchedule => 'View in schedule';

  @override
  String get dashMyClients => 'My members';

  @override
  String dashDormantClients(int count) {
    return '$count dormant';
  }

  @override
  String get dashAllActive => 'All active';

  @override
  String get dashNeedsReply => 'Awaiting reply';

  @override
  String dashWaitingClients(int count) {
    return '$count waiting';
  }

  @override
  String get dashAllReplied => 'All replied';

  @override
  String get dashAttentionClients => 'Needs attention';

  @override
  String get dashNoIssues => 'No issues';

  @override
  String get dashCheckPtSignals => 'Check PT signals';

  @override
  String get dashMessages => 'Messages';

  @override
  String get dashChurnRisk => 'Churn risk';

  @override
  String get dashChurnRiskNone => 'No churn risk';

  @override
  String get dashChurnRiskCheck => 'Review churn signals';

  @override
  String get dashChurnRiskTitle => 'Members at churn risk';

  @override
  String get dashChurnRiskEmpty => 'No members are at churn risk right now.';

  @override
  String get dashActivityDifficultyTitle =>
      'Behind exercise goal / routine skipped';

  @override
  String dashActivityDifficultyDesc(String names) {
    return '$names are behind this week\'s exercise goal or skipped an assigned routine. Lower the difficulty before the next session and check recent feedback.';
  }

  @override
  String get dashActivityInactiveTitle => 'No logs';

  @override
  String dashActivityInactiveDesc(String names) {
    return '$names haven\'t logged meals or workouts for a few days. Reach out before it turns into churn.';
  }

  @override
  String get dashActivityDietFeedbackTitle => 'Diet feedback pending';

  @override
  String dashActivityDietFeedbackDesc(String names) {
    return '$names are off their calorie goal or low on protein but haven\'t gotten trainer feedback in 7 days. Leave a comment so they know it was seen.';
  }

  @override
  String dashActivityMoreClients(String shown, int count) {
    return '$shown and $count more';
  }

  @override
  String get dashAiSummaryTitle => 'Activity feedback';

  @override
  String get dashAiNoClients =>
      'No members yet. Once you add one, I\'ll gather their diet and workout data and point out what to coach.';

  @override
  String get dashAttentionTitle => 'Members to check';

  @override
  String dashMoreCount(int count) {
    return '+$count';
  }

  @override
  String get dashNoAttention => 'No one needs attention right now';

  @override
  String get dashTodaySchedule => 'Today\'s schedule';

  @override
  String get dashSeeAll => 'See all';

  @override
  String get dashScheduleLoadFailed => 'Couldn\'t load the schedule';

  @override
  String get dashNoScheduleToday => 'Nothing scheduled today';

  @override
  String dashScheduleNowLabel(String time) {
    return 'Now $time';
  }

  @override
  String dashScheduleNextSession(String time, String name) {
    return 'Next: $time · $name';
  }

  @override
  String dashScheduleMinutesLeft(int minutes) {
    return 'in $minutes min';
  }

  @override
  String get dashPreparePt => 'Prepare PT';

  @override
  String get dashLeaveMemo => 'Leave a memo';

  @override
  String get dashSessionSent => 'Sent';

  @override
  String get dashSessionPrepared => 'Prepared';

  @override
  String get dashSessionNoteWritten => 'Written';

  @override
  String get dashSessionSentNo => 'Not sent';

  @override
  String get dashSessionPreparedNo => 'Not prepared';

  @override
  String get dashSessionNoteNotWritten => 'Not written';

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
  String get clientsLoadFailed => 'Couldn\'t load member data';

  @override
  String get clientsNew => 'Register new member';

  @override
  String get clientsTitle => 'Member management';

  @override
  String get clientsManagementAttention => 'Needs attention';

  @override
  String get clientsFiltersClearAll => 'Clear all';

  @override
  String get clientsSortLabel => 'Sort';

  @override
  String get clientsSortPriority => 'Needs attention first';

  @override
  String get clientsSortName => 'Name A–Z';

  @override
  String get clientsSortNameDescending => 'Name Z–A';

  @override
  String get clientsSortRecentMessage => 'Recent conversations';

  @override
  String get clientsFilterLabel => 'Filters';

  @override
  String clientsToolbarCount(int shown, int active) {
    return '$shown members · $active active';
  }

  @override
  String get clientsPickHint =>
      'Pick a member on the left to open\ntheir chat, meals and workouts here';

  @override
  String get clientsEmpty => 'No members yet';

  @override
  String clientsEmptyForFilter(String filter) {
    return 'No members match $filter';
  }

  @override
  String clientsMemberCount(int total) {
    return '$total members';
  }

  @override
  String clientsMemberCountFiltered(int shown, int total) {
    return '$shown of $total members';
  }

  @override
  String get clientWeeklyRoutineAdherence => 'Weekly adherence';

  @override
  String get clientRoutineAdherenceUnmeasured => 'Not measured';

  @override
  String get clientsSignalDiscomfort => 'Pain';

  @override
  String get clientsSignalRecordGap => 'No logs';

  @override
  String clientsSignalRecordGapDays(int days) {
    return 'No logs ${days}d';
  }

  @override
  String get clientsSignalRecordGapLong => 'No logs 30d+';

  @override
  String get clientsSignalNoShow => 'No-shows';

  @override
  String clientsSignalNoShowCount(int count) {
    return '$count no-shows';
  }

  @override
  String get clientsSignalRoutineMissed => 'Routine skipped';

  @override
  String get clientsSignalExerciseGoalLow => 'Low exercise';

  @override
  String clientsSignalExerciseGoalLowPercent(int percent) {
    return 'Exercise $percent%';
  }

  @override
  String get clientsSignalCalorieOff => 'Off calorie goal';

  @override
  String get clientsSignalCalorieOver => 'Calories over';

  @override
  String get clientsSignalCalorieUnder => 'Calories under';

  @override
  String get clientsSignalProteinLow => 'Low protein';

  @override
  String clientsSignalCalorieOverPercent(int percent) {
    return 'Calories $percent% over';
  }

  @override
  String clientsSignalCalorieUnderPercent(int percent) {
    return 'Calories $percent% under';
  }

  @override
  String clientsSignalProteinPercent(int percent) {
    return 'Protein $percent% of goal';
  }

  @override
  String clientsSignalRoutineMissedDays(int days) {
    return 'Routine skipped ${days}d';
  }

  @override
  String get clientsSignalUnanswered => 'Awaiting reply';

  @override
  String get clientsAttentionClear => 'Clear attention filter';

  @override
  String get memberHealthLoadFailed =>
      'Couldn\'t load the member profile. Please try again';

  @override
  String get memberHealthSaveFailed =>
      'Couldn\'t save the member profile. Please try again';

  @override
  String get memberHealthSaving => 'Saving…';

  @override
  String get memberHealthGender => 'Gender';

  @override
  String get memberHealthGenderUnset => 'Not set';

  @override
  String get memberHealthGenderMale => 'Male';

  @override
  String get memberHealthGenderFemale => 'Female';

  @override
  String get memberHealthGenderOther => 'Other';

  @override
  String get memberHealthHeight => 'Height (cm)';

  @override
  String get memberHealthWeight => 'Weight (kg)';

  @override
  String get memberHealthFocus => 'Health goals (up to 2)';

  @override
  String memberHealthFocusLastChanged(String who, String date) {
    return 'Last changed by $who · $date';
  }

  @override
  String get memberHealthFocusChangedByTrainer => 'Trainer';

  @override
  String get memberHealthFocusChangedByMember => 'Member';

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
  String get memberHealthConditions => 'Conditions and cautions';

  @override
  String get memberHealthDietGoal => 'Nutrition goals';

  @override
  String get memberHealthExerciseGoal => 'Exercise goals';

  @override
  String get memberHealthGoalCalories => 'Daily calories (kcal)';

  @override
  String get memberHealthGoalSodium => 'Daily sodium (mg)';

  @override
  String get memberHealthGoalSugar => 'Daily sugar (g)';

  @override
  String get memberHealthGoalCarbs => 'Daily carbs (g)';

  @override
  String get memberHealthGoalProtein => 'Daily protein (g)';

  @override
  String get memberHealthGoalFat => 'Daily fat (g)';

  @override
  String get memberHealthGoalBurnDaily => 'Daily burn (kcal)';

  @override
  String get memberHealthGoalCardioWeekly => 'Weekly cardio (min)';

  @override
  String get memberHealthGoalStrengthWeekly => 'Weekly strength (sets)';

  @override
  String get memberHealthGoalFlexibilityWeekly => 'Weekly stretching (min)';

  @override
  String get memberHealthWeeklyGoal => 'Weekly exercise goal';

  @override
  String get memberHealthWeeklyCount => 'Sessions';

  @override
  String get memberHealthWeeklyMinutes => 'Minutes';

  @override
  String get memberHealthWeeklyBurn => 'Calories burned';

  @override
  String memberHealthRange(String min, String max) {
    return 'Enter a value between $min and $max.';
  }

  @override
  String get clientInviteTitle => 'Add a new member';

  @override
  String get clientInviteIntro =>
      'Enter the 6-digit sync code from the member\'s MY tab to connect right away.';

  @override
  String get clientInviteIntroImmediate =>
      'Enter the 6-digit sync code from the member\'s MY tab to connect right away.';

  @override
  String get clientConnectCodeLabel => 'Sync code';

  @override
  String get clientConnectCodeRequired => 'Enter all six digits';

  @override
  String get clientConnectCodeInvalid =>
      'That code is wrong or expired. Ask the member for a new one';

  @override
  String get clientInviteConnectAction => 'Register member';

  @override
  String clientInviteConnected(String name) {
    return 'Registered $name as a member';
  }

  @override
  String get clientInviteFailed =>
      'Couldn\'t send the request. Please try again';

  @override
  String get clientInvitePendingTitle => 'Waiting for an answer';

  @override
  String get clientInvitePendingEmpty => 'No requests are waiting';

  @override
  String get clientInviteCancelAction => 'Withdraw';

  @override
  String get clientInviteCancelled => 'Request withdrawn';

  @override
  String get clientInviteCancelFailed =>
      'Couldn\'t withdraw the request. Please try again';

  @override
  String get clientInviteConfirmPrompt => 'Is this the right member?';

  @override
  String get coachTemplateNew => 'New template';

  @override
  String get coachTemplateEdit => 'Edit template';

  @override
  String get coachTemplateSaveAsMine => 'Save as my template';

  @override
  String get coachTemplateDelete => 'Delete';

  @override
  String get coachTemplateNameLabel => 'Template name';

  @override
  String get coachTemplateGoalLabel => 'Goal (e.g. blood pressure · beginner)';

  @override
  String get coachTemplateExerciseName => 'Exercise';

  @override
  String get coachTemplateExerciseMinutes => 'min';

  @override
  String get coachTemplateAddExercise => 'Add exercise';

  @override
  String get coachTemplateSave => 'Save';

  @override
  String get coachTemplateNameRequired => 'Enter a template name';

  @override
  String get coachTemplateExerciseRequired => 'Add at least one exercise';

  @override
  String get coachTemplateExerciseNameRequired => 'Enter the exercise name';

  @override
  String get coachTemplateSaveFailed =>
      'Couldn\'t save the template. Please try again';

  @override
  String get coachTemplateDeleteFailed =>
      'Couldn\'t delete the template. Please try again';

  @override
  String coachTemplateDeleteConfirm(String name) {
    return 'Delete the $name template?';
  }

  @override
  String get coachTemplateLoadFailed => 'Couldn\'t load templates';

  @override
  String get coachTemplateStarterHint =>
      'A starter block. Editing saves it as your own';

  @override
  String get chatEmoteLabel => 'Emote';

  @override
  String get chatAttachImage => 'Attach a photo';

  @override
  String get chatImageUnavailable => 'Couldn\'t load the photo';

  @override
  String get chatImageSendFailed =>
      'Couldn\'t send the photo. Please try again';

  @override
  String get clientTabDiet => 'Meals';

  @override
  String get clientTabWorkout => 'Workouts';

  @override
  String get clientNotFound => 'Member not found';

  @override
  String get clientBackToList => 'Back to members';

  @override
  String get clientList => 'Member list';

  @override
  String get metricCalories => 'Calories';

  @override
  String get metricSodium => 'Sodium';

  @override
  String get metricSugar => 'Sugar';

  @override
  String get clientDietMacrosMissing => 'No carbs/protein/fat recorded';

  @override
  String get clientDietTotalCalories => 'Total calories';

  @override
  String get clientDietDayTotal => 'Day total';

  @override
  String clientDietDayTotalCalories(String calories) {
    return 'Total $calories kcal';
  }

  @override
  String clientDietMacroShare(String name, int percent) {
    return '$name $percent%';
  }

  @override
  String get metricCarbs => 'Carbs';

  @override
  String get metricProtein => 'Protein';

  @override
  String get metricFat => 'Fat';

  @override
  String get clientActive => 'Active';

  @override
  String get clientDormant => 'Dormant';

  @override
  String get clientDormantActivate => 'Tap to mark active';

  @override
  String get clientSignalLess => 'Less';

  @override
  String clientSignalMore(int count) {
    return '+$count';
  }

  @override
  String get clientStatusChangeFailed =>
      'Couldn\'t change the status. Please try again.';

  @override
  String get chatTooLong => 'Message is too long (2000 characters max)';

  @override
  String get chatSendFailed => 'Couldn\'t send the message. Please try again';

  @override
  String get chatPdfOpenFailed => 'Couldn\'t open the PDF. Please try again';

  @override
  String get chatReportRegistered => 'Weekly report added';

  @override
  String get chatReportOpenInReports => 'Go to Reports';

  @override
  String get chatLoadFailed => 'Couldn\'t load the conversation';

  @override
  String chatDemoAnalyzed(String name) {
    return 'AI analysed $name\'s meals and workouts';
  }

  @override
  String get chatDemoReportSent => 'A summary report was sent to you';

  @override
  String chatDemoRoutineSent(String name) {
    return 'A personalized workout recommendation was sent to $name';
  }

  @override
  String get chatDemoNotified => 'The member app was notified';

  @override
  String get chatInputHint => 'Type a message...';

  @override
  String chatInsightDiscomfortTitle(String part) {
    return '$part discomfort detected';
  }

  @override
  String get chatInsightBodyPartGeneral => 'Physical';

  @override
  String get chatInsightBodyPartKnee => 'Knee';

  @override
  String get chatInsightBodyPartBack => 'Back';

  @override
  String get chatInsightBodyPartAnkle => 'Ankle';

  @override
  String get chatInsightBodyPartShoulder => 'Shoulder';

  @override
  String get chatInsightBodyPartWrist => 'Wrist';

  @override
  String get chatInsightBodyPartNeck => 'Neck';

  @override
  String get chatInsightNegativeTitle => 'Negative feedback detected';

  @override
  String get chatInsightDiscomfortDescription =>
      'AI detected a report of discomfort. Check the symptoms and consider adjusting the next workout\'s intensity.';

  @override
  String get chatInsightNegativeDescription =>
      'AI detected workout strain or difficulty completing the plan. Check the cause and consider adjusting the program.';

  @override
  String get chatInsightAddMemo => 'Add to memo';

  @override
  String get chatInsightMemoAdded => 'Added to memo';

  @override
  String chatInsightMemoSummaryDiscomfort(String part) {
    return '$part discomfort detected';
  }

  @override
  String get chatInsightMemoSummaryNegative => 'Workout strain detected';

  @override
  String get chatInsightMemoSaved =>
      'The AI insight was added to the trainer memo.';

  @override
  String get chatInsightMemoSaveFailed =>
      'Couldn\'t add the memo. Please try again.';

  @override
  String coachSheetTitle(String name) {
    return 'Coaching for $name';
  }

  @override
  String get coachSheetSubtitle =>
      'Answers are grounded in this member\'s meals and workouts.';

  @override
  String get coachSheetHint =>
      'e.g. Sodium keeps running high — what meals should I suggest?';

  @override
  String get coachSheetSources => 'Sources';

  @override
  String get coachSheetAsk => 'Ask';

  @override
  String get coachSheetAskAgain => 'Ask again';

  @override
  String get consultTitle => 'Consultation requests';

  @override
  String get consultBackToSchedule => 'Back to schedule';

  @override
  String get consultBackToDashboard => 'Back to dashboard';

  @override
  String consultPendingCount(int count) {
    return '$count pending';
  }

  @override
  String get consultNoPending => 'No pending requests';

  @override
  String get consultFilterAll => 'All';

  @override
  String consultFilterPendingCount(int count) {
    return 'Pending $count';
  }

  @override
  String get consultLoadMore => 'Load earlier requests';

  @override
  String get consultLoadFailed => 'Couldn\'t load consultation requests';

  @override
  String get consultRetryLater => 'Please try again in a moment';

  @override
  String get consultEmptyPending => 'No pending consultation requests';

  @override
  String get consultEmptyHistory => 'No consultation history';

  @override
  String get consultEmptyHint =>
      'Requests appear here when a member asks for a consultation with your gym or with you';

  @override
  String get consultActionFailed => 'Couldn\'t process the request';

  @override
  String consultApproved(String name) {
    return '$name\'s request was approved. Add a session from the Schedule tab.';
  }

  @override
  String consultScheduleCreated(String name) {
    return 'Added a consultation session for $name';
  }

  @override
  String get consultRejected => 'Request declined';

  @override
  String consultScheduleConflict(String name, String time) {
    return 'Overlaps $name\'s $time session';
  }

  @override
  String get consultDecisionNote => 'Reason';

  @override
  String get consultTargetTrainer => 'Direct request';

  @override
  String get consultExerciseGoal => 'Training goal';

  @override
  String get consultHealthPurpose => 'Health management purpose';

  @override
  String get consultChosenSlot => 'Chosen time';

  @override
  String consultSlotDuration(int minutes) {
    return '$minutes min';
  }

  @override
  String get consultStatusExpired => 'Expired';

  @override
  String get consultPreferredTime => 'Preferred time';

  @override
  String get consultMessage => 'Message';

  @override
  String get consultReject => 'Decline';

  @override
  String get consultApprove => 'Approve';

  @override
  String get consultRejectTitle => 'Decline request';

  @override
  String get consultRejectNotice =>
      'The reason you write is sent to the member as a notification.';

  @override
  String get consultRejectHint =>
      'e.g. I have another appointment at your requested time.';

  @override
  String get consultStatusPending => 'Pending';

  @override
  String get consultStatusAccepted => 'Approved';

  @override
  String get workoutRecords => 'Workout log';

  @override
  String get workoutRecordsShowMore => 'Show more';

  @override
  String get workoutRecordsShowLess => 'Show less';

  @override
  String get workoutLoadFailed => 'Couldn\'t load the workout log';

  @override
  String get workoutEmpty => 'No workouts logged yet';

  @override
  String get routinesAssigned => 'Assigned programs';

  @override
  String get routineNew => 'New program';

  @override
  String get routinesLoadFailed => 'Couldn\'t load programs';

  @override
  String get routinesEmpty => 'No programs assigned to this member yet';

  @override
  String minutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String get ptProgramHistory => 'PT program history';

  @override
  String get scheduleLoadFailed => 'Couldn\'t load the schedule';

  @override
  String get ptSessionsEmpty => 'No PT sessions yet';

  @override
  String get labelToday => 'Today';

  @override
  String sessionTypeAndDuration(String type, int minutes) {
    return '$type · $minutes min';
  }

  @override
  String get programNone => 'No program recorded';

  @override
  String get legendDone => 'Done';

  @override
  String get clientFeedback => 'Member feedback';

  @override
  String get workoutKindAiPersonal => 'AI personal exercise';

  @override
  String get workoutKindPtSession => 'PT session · Trainer-led';

  @override
  String get workoutKindAssignedRoutine => 'Assigned routine';

  @override
  String get dietLoadFailed => 'Couldn\'t load meals';

  @override
  String get dietEmpty => 'No meals logged yet';

  @override
  String get dietDayEmpty => 'No record';

  @override
  String get dietMacros => 'Macros';

  @override
  String get clientNutritionSummary => 'Nutrition summary';

  @override
  String get dietCalorieIntake => 'Calories today';

  @override
  String get dietAchieveRate => 'Progress';

  @override
  String dietAmountOver(String amount) {
    return '$amount over the goal';
  }

  @override
  String dietAmountRemaining(String amount) {
    return '$amount remaining to the goal';
  }

  @override
  String get consultStatusRejected => 'Declined';

  @override
  String get dateToday => 'Today';

  @override
  String get dateTomorrow => 'Tomorrow';

  @override
  String get dateYesterday => 'Yesterday';

  @override
  String dateDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String dateWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks ago',
      one: '1 week ago',
    );
    return '$_temp0';
  }

  @override
  String historyDate(int month, int day) {
    return '$month/$day';
  }

  @override
  String historyDateRelative(String date, String relative) {
    return '$date ($relative)';
  }

  @override
  String dateMonthDayWeekday(int month, int day, String weekday) {
    return '$month/$day ($weekday)';
  }

  @override
  String datePrefixed(String prefix, String date) {
    return '$prefix · $date';
  }

  @override
  String dateMonthDay(int month, int day) {
    return '$month/$day';
  }

  @override
  String dateRange(String start, String end) {
    return '$start – $end';
  }

  @override
  String get reportsTitle => 'Reports';

  @override
  String get reportsSubtitle =>
      'Review the week\'s changes and share them with your member';

  @override
  String get reportsLoadFailed => 'Couldn\'t load reports';

  @override
  String get reportsNoClients =>
      'No members yet, so there\'s nothing to report on';

  @override
  String get reportsWeekly => 'Weekly report';

  @override
  String get reportsSendFailed => 'Couldn\'t send the report. Please try again';

  @override
  String reportsSent(String name) {
    return 'Report sent to $name';
  }

  @override
  String get reportsGoToChat => 'Go to chat';

  @override
  String get reportsScheduleWarning =>
      'This week\'s schedule didn\'t load, so session counts may be missing';

  @override
  String get unitTimes => '';

  @override
  String get unitMinutes => 'min';

  @override
  String clientTrendWorkoutDaysValue(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get clientPeriodToday => 'Today';

  @override
  String get clientPeriodWeek => 'This week';

  @override
  String get clientPeriodMonth => 'All';

  @override
  String get clientPeriodAverage => 'Daily average';

  @override
  String get clientPeriodGoal => 'Goal';

  @override
  String get exBurnTodayTitle => 'Burned today';

  @override
  String get exBurnWeekTitle => 'Burned this week';

  @override
  String get exBurnMonthTitle => 'Burned this month';

  @override
  String get exBurnDayTitle => 'Burned';

  @override
  String get exBurnAllTitle => 'Average burned';

  @override
  String exWeekOfMonthLabel(int month, int week) {
    return 'Burned in week $week, $month/';
  }

  @override
  String exStreakCheer(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days in a row!',
      one: '1 day in a row!',
    );
    return '$_temp0';
  }

  @override
  String get exStreakStart => 'No streak yet';

  @override
  String get exTypeOther => 'Other';

  @override
  String clientPeriodLoggedDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days logged',
      one: '1 day logged',
    );
    return '$_temp0';
  }

  @override
  String get clientPeriodEmpty => 'Nothing was logged in this period';

  @override
  String get clientDietTrendTitle => 'Nutrition trend';

  @override
  String get unitKcal => 'kcal';

  @override
  String get clientTrendTitle => 'Activity';

  @override
  String get clientTrendLoadFailed =>
      'Couldn\'t load the workout trend. Please try again';

  @override
  String get clientTrendTodayEmpty => 'No workout logged today';

  @override
  String get clientTrendTodayTotal => 'Today\'s total';

  @override
  String get clientTrendWorkoutDays => 'Active days';

  @override
  String get clientTrendWorkoutCount => 'Workouts';

  @override
  String get clientTrendWorkoutMinutes => 'Exercise time';

  @override
  String get clientTrendCaloriesBurned => 'Calories burned';

  @override
  String get clientTrendSegmentTime => 'Time';

  @override
  String get reportsPickClient => 'Pick a member';

  @override
  String reportsClientWeekly(String name) {
    return '$name\'s weekly report';
  }

  @override
  String get reportsCompletionAvg => 'Workout completion';

  @override
  String get reportsWeeklyCompletion => 'Weekly completion';

  @override
  String get reportsCompletionByDay => 'Weekly workout completion';

  @override
  String get reportsNoWorkoutsThisWeek => 'No workouts logged this week';

  @override
  String reportsMetricTrend(String metric) {
    return '$metric trend';
  }

  @override
  String reportsNoLastWeekMetricTrend(String metric) {
    return 'No $metric trend for last week yet';
  }

  @override
  String reportsNoMetricRecords(String metric) {
    return 'No $metric logged this week yet';
  }

  @override
  String get reportsDietTrend => 'Weekly diet trend';

  @override
  String workoutDoneOfTotal(int total, int done) {
    return '$done of $total done';
  }

  @override
  String get chartNoRecord => 'Not logged';

  @override
  String get chartNotYet => 'Not yet';

  @override
  String chartOverGoal(String amount, String unit) {
    return '$amount $unit over goal';
  }

  @override
  String get reportsSendNeedsFeedback => 'Write feedback first to send it.';

  @override
  String reportBodyGreeting(String name, String range) {
    return '$name, here\'s your weekly report for $range.';
  }

  @override
  String reportBodyCompletionGood(int avg) {
    return 'You kept up well — $avg% of your workouts done.';
  }

  @override
  String reportBodyCompletionSteady(int avg) {
    return 'You stayed steady — $avg% of your workouts done.';
  }

  @override
  String reportBodyCompletionLow(int avg) {
    return 'Workout completion came in at $avg%. Sounds like a busy one.';
  }

  @override
  String reportBodySilentDays(String days) {
    return 'Nothing was logged on $days. If those days are always packed, I\'ll swap in a short 15-minute version.';
  }

  @override
  String reportBodySteadyDays(String days) {
    return 'Keeping it going all the way through $days was the best part of this week.';
  }

  @override
  String reportBodySkipped(String names) {
    return 'One thing — $names got skipped. If that was a condition thing, tell me at the next session and I\'ll swap in an alternative.';
  }

  @override
  String reportBodySodiumOver(String avg, String target, int days) {
    return 'Sodium averaged ${avg}mg a day, and went over the ${target}mg target on $days days. Leaving half the broth behind saves 400-500mg a day.';
  }

  @override
  String reportBodySodiumOk(String avg, String target) {
    return 'Sodium averaged ${avg}mg a day — comfortably inside the ${target}mg target.';
  }

  @override
  String get reportBodyPraise =>
      'Great work — let\'s keep this pace next week!';

  @override
  String get reportBodyEncourage =>
      'Take those one at a time and you\'ll see it come together. I\'ll adjust your program and send it over.';

  @override
  String get reportBodyNoRecords =>
      'There\'s nothing logged for this week, so nothing to sum up. Let\'s plan next week\'s start together.';

  @override
  String reportBodySessionsAll(int booked) {
    return 'You made all $booked of your booked PT sessions.';
  }

  @override
  String reportBodySessionsSome(int booked, int done) {
    return 'You made $done of your $booked booked PT sessions.';
  }

  @override
  String get reportBodySessionsNone => 'There were no PT sessions this week.';

  @override
  String reportBodyExerciseCount(int total, int done) {
    return 'You finished $done of the $total assigned exercises.';
  }

  @override
  String reportBodyMealDaysAll(int total) {
    return 'You logged your meals on all $total days.';
  }

  @override
  String reportBodyMealDays(int total, int days) {
    return 'You logged your meals on $days of $total days.';
  }

  @override
  String reportBodyCaloriesOver(
    String avg,
    String target,
    String pct,
    int days,
  ) {
    return 'Calories averaged ${avg}kcal a day — $pct% above your ${target}kcal target, and over it on $days days.';
  }

  @override
  String reportBodyCaloriesUnder(String avg, String target, String pct) {
    return 'Calories averaged ${avg}kcal a day — $pct% below your ${target}kcal target. Eating too little tends to cost muscle first.';
  }

  @override
  String reportBodyCaloriesNearOver(String avg, String target, int days) {
    return 'Calories averaged ${avg}kcal a day, close to your ${target}kcal target, but went over it on $days days.';
  }

  @override
  String reportBodyCaloriesOk(String avg, String target) {
    return 'Calories averaged ${avg}kcal a day — right around your ${target}kcal target.';
  }

  @override
  String reportBodySugarOver(String avg, String target, int days) {
    return 'Sugar averaged ${avg}g a day and went over the ${target}g limit on $days days.';
  }

  @override
  String reportBodySugarOk(String avg, String target) {
    return 'Sugar averaged ${avg}g a day, inside the ${target}g limit.';
  }

  @override
  String reportBodyMemberPain(String area) {
    return 'You mentioned pain in your $area. Let me know how it feels before the next session — I\'ll ease off that area.';
  }

  @override
  String get reportBodyMemberTooHard =>
      'You said the workouts felt too hard, so I\'ll drop next week\'s intensity a notch.';

  @override
  String get reportBodyMemberTooEasy =>
      'You said the workouts felt easy, so I\'ll raise next week\'s intensity a notch.';

  @override
  String get reportBodyMemberNoted =>
      'Thanks for the weekly check-in — I read it.';

  @override
  String get reportBodyNextWeek => 'Here\'s the plan for next week.';

  @override
  String get reportTipCaloriesOver =>
      'Cut dinner carbs to about two-thirds and switch snacks to protein.';

  @override
  String get reportTipCaloriesUnder =>
      'Don\'t skip meals, and add one protein snack on workout days.';

  @override
  String get reportTipSugar => 'Keep sweet drinks and desserts to once a day.';

  @override
  String get reportTipSodium =>
      'Keep takeout and processed foods to twice a week.';

  @override
  String get reportTipWorkout =>
      'Aim to get three workouts in first, even if each is only 20 minutes.';

  @override
  String get reportTipMeals =>
      'Log every meal, even with just a photo, so I can give you sharper feedback.';

  @override
  String get reportTipSessionsNone =>
      'Let\'s book next week\'s PT sessions together now.';

  @override
  String get reportTipSessionsMissed =>
      'I\'ll set up make-up slots next week for the sessions we missed.';

  @override
  String get reportTipKeep =>
      'Keep the current routine as it is, and I\'ll raise the intensity step by step.';

  @override
  String get schedTitle => 'Schedule';

  @override
  String get schedDetailTitle => 'Session detail';

  @override
  String get schedDeleteTitle => 'Delete session';

  @override
  String schedDeleteConfirm(String time, String name) {
    return 'Delete the $time PT session with $name?';
  }

  @override
  String get schedDeleteFailed =>
      'Couldn\'t delete the session. Please try again';

  @override
  String get schedCompleteTitle => 'Complete session';

  @override
  String schedCompleteConfirm(String time, String name) {
    return 'Mark the $time session with $name as complete?';
  }

  @override
  String get schedCompleteFailed =>
      'Couldn\'t mark it complete. Please try again';

  @override
  String get schedGroupProgram => 'PT program';

  @override
  String get schedGroupPersonal => 'Personal exercise';

  @override
  String get schedRoutinesGoesOnComplete =>
      'Goes to the member together with this PT\'s program.';

  @override
  String get schedRoutinesNotSentYet => 'Not sent to the member yet.';

  @override
  String get schedRoutinesSendTitle => 'Send the personal exercise?';

  @override
  String get schedEditRoutines => 'Edit personal exercise';

  @override
  String get schedEditRoutinesTitle => 'Edit personal exercise';

  @override
  String get schedEditRoutinesBody =>
      'This personal exercise goes out with the PT program. It has not been sent yet, so you can still change it freely.';

  @override
  String get schedRoutinesSendBody =>
      'This PT did not happen, but you can still send the personal exercise you composed. It shows in the member app every day for 7 days.';

  @override
  String get schedRoutinesSend => 'Send personal exercise';

  @override
  String get schedRoutinesSkip => 'Don\'t send';

  @override
  String schedSendProgramWithRoutines(String date) {
    return 'Send the $date PT program and personal exercise';
  }

  @override
  String get schedRoutineSent => 'Sent';

  @override
  String get schedRoutinesSent => 'Sent the personal exercise to the member.';

  @override
  String get schedRoutinesSendFailed =>
      'Couldn\'t send the personal exercise. Please try again.';

  @override
  String get schedRoutinesSkipped => 'Marked as not sent.';

  @override
  String get schedRoutinesUpdated => 'Personal exercise updated.';

  @override
  String get schedRoutinesUpdateFailed =>
      'Couldn\'t update the personal exercise. Please try again.';

  @override
  String schedTimeRange(String start, String end) {
    return '$start–$end';
  }

  @override
  String schedBlockTime(String range, String duration) {
    return '$range ($duration)';
  }

  @override
  String get schedEmptyWeek => 'Nothing scheduled this week.';

  @override
  String get schedSlots => 'Booking slots';

  @override
  String get schedNewSession => 'New session';

  @override
  String get schedLoadFailed => 'Couldn\'t load the schedule';

  @override
  String get schedEmptyDay =>
      'Nothing scheduled for this day.\nUse New session above to add one.';

  @override
  String get schedSaveFailed => 'Couldn\'t save the session. Please try again';

  @override
  String get schedAddTitle => 'Add a session';

  @override
  String get schedEditTitle => 'Edit session';

  @override
  String get schedFieldClient => 'Member';

  @override
  String get schedFieldType => 'Type';

  @override
  String get schedFieldDate => 'Date';

  @override
  String get schedFieldStartDate => 'Start date';

  @override
  String get schedFieldDateRange => 'Start - end date';

  @override
  String get schedFieldTime => 'Time';

  @override
  String get schedHourSuffix => 'hr';

  @override
  String get schedMinuteSuffix => 'min';

  @override
  String get schedFieldDuration => 'Duration';

  @override
  String get schedFieldStart => 'Start';

  @override
  String get schedFieldEnd => 'End';

  @override
  String get schedEndBeforeStart => 'End time must be after the start time';

  @override
  String get schedReopenTitle => 'Switch back to upcoming?';

  @override
  String get schedReopenBody =>
      'Moving a completed session forward switches it back to upcoming, and the workout log it created will be removed.';

  @override
  String get schedReopenConfirm => 'Switch to upcoming';

  @override
  String get schedReopenPastBlocked =>
      'A completed session can only move to a future date';

  @override
  String get schedTimeRangeTitle => 'Select time';

  @override
  String get schedTimeRangeConfirm => 'Confirm';

  @override
  String get schedTimeRangeInvalid => 'Enter a valid time (HH:mm)';

  @override
  String get schedTimePickerTimeLabel => 'Time';

  @override
  String get schedTimePickerEndTime => 'End time';

  @override
  String get schedTimePickerHour => 'Hour';

  @override
  String get schedTimePickerMinute => 'Minute';

  @override
  String get schedTimePickerStartHour => 'Start hour';

  @override
  String get schedTimePickerStartMinute => 'Start minute';

  @override
  String get schedTimePickerEndHour => 'End hour';

  @override
  String get schedTimePickerEndMinute => 'End minute';

  @override
  String get schedTimePickerPrevStep => 'Previous step';

  @override
  String get schedTimePickerNextStep => 'Next step';

  @override
  String get schedTimePickerEndBeforeStart =>
      'End time is earlier than the start time';

  @override
  String schedClockHourSemantics(String hour) {
    return '$hour o\'clock';
  }

  @override
  String get schedRepeat => 'Repeat';

  @override
  String get schedRepeatWeekly => 'Weekly';

  @override
  String get schedRepeatDays => 'Repeat on';

  @override
  String schedRepeatPreview(int count, String first, String last) {
    return '$count sessions · $first – $last';
  }

  @override
  String get schedRepeatNeedsDays => 'Pick at least one weekday.';

  @override
  String get schedRepeatNeedsEndDate => 'Pick an end date for the repeat.';

  @override
  String schedRepeatConflictTitle(int total, int count) {
    return '$count of $total sessions clash';
  }

  @override
  String schedRepeatConflictRow(String date, String time, String name) {
    return '$date $time · already booked: $name';
  }

  @override
  String get schedRepeatConflictHint =>
      'Nothing was created. Change the time, or clear the sessions that clash.';

  @override
  String get schedOverlapTitle => 'This time overlaps another session';

  @override
  String get schedOverlapHint =>
      'Nothing was saved. Change the time or move the overlapping session, then save again.';

  @override
  String get slotOverlapHint =>
      'The slot wasn\'t opened. Pick another time or move the overlapping session.';

  @override
  String get consultOverlapHint =>
      'The member\'s chosen time is already booked, so the request wasn\'t approved. Move the overlapping session, then approve again.';

  @override
  String get schedNote => 'Trainer\'s note';

  @override
  String get schedEditNote => 'Edit note';

  @override
  String get schedAddNote => 'Add note';

  @override
  String get schedNoNote => 'No note yet';

  @override
  String get schedNoteOnlyHint =>
      'A consultation is recorded as a note, not a program.';

  @override
  String get schedNoteHint => 'Anything to prepare, or notes about this member';

  @override
  String get schedAddAction => 'Add';

  @override
  String get schedSaveAction => 'Save';

  @override
  String get progInvalid => 'Check the exercise name and set count';

  @override
  String get progSaveFailed => 'Couldn\'t save the program. Please try again';

  @override
  String get progEditTitle => 'Edit program';

  @override
  String get progAddTitle => 'Add program';

  @override
  String get progAddExercise => 'Add exercise';

  @override
  String get progNoteHint => 'Notes to follow while running this program';

  @override
  String get progSaving => 'Saving...';

  @override
  String get progSaveAction => 'Save program';

  @override
  String get progSaveNoteAction => 'Save note';

  @override
  String get progExerciseName => 'Exercise';

  @override
  String get progDeleteExercise => 'Remove exercise';

  @override
  String get progSets => 'Sets';

  @override
  String get progReps => 'Reps/time';

  @override
  String get progWeight => 'Weight';

  @override
  String get progType => 'Type';

  @override
  String get progDuration => 'Duration (min)';

  @override
  String get progOptional => 'Optional';

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
  String progHoldValue(int seconds) {
    return '$seconds sec';
  }

  @override
  String progRepsValue(int reps) {
    String _temp0 = intl.Intl.pluralLogic(
      reps,
      locale: localeName,
      other: '$reps reps',
      one: '1 rep',
    );
    return '$_temp0';
  }

  @override
  String get progEmpty => 'No program planned yet';

  @override
  String get progEmptyHint =>
      'Build one in the AI suggestions tab, or agree on it over chat first.';

  @override
  String schedSentTo(String name) {
    return 'Sent to $name';
  }

  @override
  String schedSentProgramTo(String date) {
    return 'Send the $date PT program';
  }

  @override
  String get slotPastTime =>
      'Booking slots can only be opened for future times.';

  @override
  String get slotOpened => 'Booking slot opened.';

  @override
  String get slotEditTitle => 'Edit booking slot';

  @override
  String get slotStartTime => 'Start time';

  @override
  String get slotUpdated => 'Booking slot updated.';

  @override
  String get slotCloseTitle => 'Close booking slot';

  @override
  String get slotCloseBody =>
      'Any existing booking stays; only new bookings stop.';

  @override
  String get slotClosed => 'New bookings closed.';

  @override
  String get slotActionFailed =>
      'Couldn\'t complete the request. Please try again in a moment.';

  @override
  String get slotManageTitle => 'Manage booking slots';

  @override
  String get slotIntro =>
      'Open times for members to book. Every upcoming slot is listed below by date.';

  @override
  String get slotOpenAction => 'Open';

  @override
  String get slotReload => 'Reload';

  @override
  String get slotEmpty => 'No booking slots are open.';

  @override
  String get slotClosedSummary => 'Closed';

  @override
  String get slotBookedSummary => 'Booked';

  @override
  String get slotOpenSummary => 'Open';

  @override
  String get slotCloseAction => 'Close bookings';

  @override
  String get myCareerInvalid => 'Enter years of experience between 0 and 80.';

  @override
  String get myProfileSaveFailed => 'Couldn\'t save your profile.';

  @override
  String get myGymChangeFailed =>
      'Couldn\'t change your gym. The rest of your profile was saved.';

  @override
  String get myTabProfile => 'My profile';

  @override
  String get myTabSettings => 'Settings';

  @override
  String get mySaving => 'Saving';

  @override
  String get myEditProfile => 'Edit profile';

  @override
  String get mySaved => 'Changes saved';

  @override
  String get myCertifications => 'Certifications';

  @override
  String get myGym => 'My gym';

  @override
  String get myNotifications => 'Notifications';

  @override
  String get myNotifNewMessage => 'New message alerts';

  @override
  String get myNotifNotReady => 'Coming soon — always on for now';

  @override
  String get myNotifNewMessageHint =>
      'Get an inbox alert and a sidebar count when a member messages you';

  @override
  String get myLanguageApp => 'Display language';

  @override
  String get myLanguageHint =>
      'Your choice is saved in this browser only. Other devices follow their own browser setting.';

  @override
  String get myLanguageSystem => 'Match browser';

  @override
  String get myLanguageKorean => '한국어';

  @override
  String get myLanguageEnglish => 'English';

  @override
  String get myAccount => 'Account';

  @override
  String get myChangePassword => 'Change password';

  @override
  String get myChangePasswordHint =>
      'We\'ll confirm your current password first';

  @override
  String get myChangePasswordDemo =>
      'Demo mode has no account, so this is unavailable';

  @override
  String get myLoginAccount => 'Signed in as';

  @override
  String get myLegal => 'Terms & policies';

  @override
  String get mySupportTitle => 'Customer Support';

  @override
  String get mySupportFaq => 'FAQ';

  @override
  String get mySupportInquiry => '1:1 Inquiry';

  @override
  String get mySupportExternalHint => 'Opens the KakaoTalk channel';

  @override
  String get mySupportOpenFailed =>
      'Couldn\'t open the link. Please try again in a moment';

  @override
  String get mySupportEntryHint =>
      'FAQ, inquiries, policies and account clean-up in one place';

  @override
  String myAppVersion(String version) {
    return 'On-Care Trainer · Version $version';
  }

  @override
  String get myAppName => 'On-Care Trainer';

  @override
  String get myLegalTermsTitle => 'Terms of Service';

  @override
  String get myLegalPrivacyTitle => 'Privacy Policy';

  @override
  String get myLegalEffectiveDate => 'Effective Jan 1, 2026';

  @override
  String get myLegalTermsBody =>
      'This English text is provided for convenience; the Korean original governs.\n\n1. Purpose\nThese terms govern the rights, obligations and responsibilities between On-Care (the \"Company\") and trainers using the On-Care trainer console (the \"Service\").\n\n2. Effect and amendment\nThese terms apply to every trainer using the Service. The Company may amend them within the limits of applicable law, announcing the effective date and the reason inside the Service.\n\n3. The Service\nThe Company provides member management, access to diet and workout records, scheduling, messaging, AI coaching programs, and report writing and delivery. The details may change with Company policy.\n\n4. Accounts\nTrainer accounts and member accounts are separate; one account cannot be used for both. Trainers must enter certification and career details truthfully and are responsible for keeping their credentials safe.\n\n5. Handling member information\nTrainers may open the diet, workout and health records only of members they are assigned to. Those records may be used solely for coaching, consultation and reports, and must never be published or handed to a third party. When an assignment ends, the access ends with it.\n\n6. Prohibited conduct\nTrainers must not make medical diagnoses or prescriptions, and must not move member information outside the Service without that member\'s consent.\n\n7. Limitation of liability\nAI coaching output and statistics are reference material. The final judgement about the guidance given to a member rests with the trainer, and the Company bears no liability for that outcome to the extent permitted by law.\n\n8. Termination\nA trainer may delete their account at any time. Doing so ends their member assignments and upcoming sessions, and the affected members are notified.\n\nAddendum\nThese terms take effect on January 1, 2026.';

  @override
  String get myLegalPrivacyBody =>
      'This English text is provided for convenience; the Korean original governs.\n\n1. Information collected\nFor trainer sign-up and service delivery, On-Care (the \"Company\") collects name, email and phone number, along with gym affiliation, certifications, career, speciality and service access logs.\n\n2. Purpose of collection and use\nThe information is used only to identify trainers and verify their credentials, to connect them with assigned members, to provide scheduling, messaging and reports, and to improve the service and answer enquiries.\n\n3. Access to and processing of member information\nA trainer may open the diet, workout and body-weight records of members they are assigned to, inside the Service. The Company is the controller of those records; the trainer processes them only for coaching and reports, within the scope the Company sets. Reports and messages a trainer sends are delivered to that member and kept in the Service as a record. When an assignment ends, the trainer\'s access is revoked immediately, and a member may withdraw consent to share their information at any time.\n\n4. Retention\nA trainer\'s personal information is destroyed without delay on account deletion, unless the law requires it to be kept, in which case it is stored securely for that period. Reports and messages already delivered belong to the member\'s record and follow the member\'s retention period.\n\n5. Provision to third parties\nThe Company does not provide personal information to outside parties without consent, except where the law specifically requires it.\n\n6. Safeguards\nAccess to member information is limited by assignment, traffic is encrypted in transit, and access logs are retained.\n\n7. Your rights\nA trainer may review or correct their personal information, or request that its processing stop and that it be deleted, at any time.\n\n8. Privacy officer\nFor privacy enquiries, contact customer support (support@oncare.com).\n\nEffective: January 1, 2026';

  @override
  String get myAppInfo => 'About';

  @override
  String get myService => 'Service';

  @override
  String get myVersion => 'Version';

  @override
  String get myPasswordChanged => 'Password changed';

  @override
  String myCareerYears(int years) {
    String _temp0 = intl.Intl.pluralLogic(
      years,
      locale: localeName,
      other: '$years years',
      one: '1 year',
    );
    return '$_temp0 of experience';
  }

  @override
  String myCareerYearsValue(int years) {
    String _temp0 = intl.Intl.pluralLogic(
      years,
      locale: localeName,
      other: '$years years',
      one: '1 year',
    );
    return '$_temp0';
  }

  @override
  String get myFieldName => 'Name (account)';

  @override
  String get myFieldEmail => 'Email (account)';

  @override
  String get myFieldPhone => 'Phone';

  @override
  String get myFieldSpecialty => 'Specialty';

  @override
  String get myFieldCareer => 'Experience';

  @override
  String get myFieldIntro => 'About me';

  @override
  String get myAddCertification => 'Add a certification...';

  @override
  String get myAdd => 'Add';

  @override
  String get myStatClients => 'Members';

  @override
  String get myClientManagement => 'Member management';

  @override
  String get myClientRemove => 'Remove member';

  @override
  String myClientRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get myClientRemoveBody =>
      'This member\'s schedules, programs and routines, reports, messages, and notes will all disappear from the trainer app. Existing data in the member app is not deleted.';

  @override
  String get myClientRemoveSuccess => 'Member removed';

  @override
  String get myClientRemoveFailed =>
      'Couldn\'t remove the member. Please try again';

  @override
  String get myClientManagementEmpty => 'No members assigned';

  @override
  String get myBasicInfo => 'Basic info';

  @override
  String get myStatSessionsDone => 'Sessions done';

  @override
  String get myStatRoutinesSent => 'Programs sent';

  @override
  String get myGymName => 'Gym name';

  @override
  String get myGymAddress => 'Address';

  @override
  String get myGymHours => 'Hours';

  @override
  String get myGymListFailed => 'Couldn\'t load the gym list.';

  @override
  String get myGymNoMatch =>
      'This gym isn\'t listed. Please add its address and hours yourself.';

  @override
  String get myGymLinked => 'Registered gym';

  @override
  String get myGymUnlink => 'Unlink';

  @override
  String get myGymNameHint => 'Type to find a registered gym';

  @override
  String get myGymRequired => 'Enter your gym';

  @override
  String get myGymEditHint =>
      'Pick a registered gym to fill in its address and hours. Not listed? Enter it yourself.';

  @override
  String get myGymListLoading => 'Loading gyms…';

  @override
  String get mySignOut => 'Sign out';

  @override
  String get myPwCurrentRequired => 'Enter your current password';

  @override
  String get myPwMismatch => 'The new passwords don\'t match';

  @override
  String get myPwChangeFailed => 'Couldn\'t change your password';

  @override
  String get myPwChangeRetry =>
      'That didn\'t work. Please try again in a moment';

  @override
  String get myPwCurrent => 'Current password';

  @override
  String myPwNew(int min) {
    return 'New password ($min+ characters, letters and numbers)';
  }

  @override
  String get myPwConfirm => 'Confirm new password';

  @override
  String get myPwChanging => 'Changing…';

  @override
  String get mySettingsSaveFailed =>
      'Couldn\'t save your settings. Please try again in a moment';

  @override
  String get myProfileSubtitle =>
      'How members see you, and this month\'s activity';

  @override
  String get myClientsSubtitle => 'Tidy up your member connections';

  @override
  String get myLanguageSubtitle => 'Choose the console language';

  @override
  String get myAccountSubtitle => 'Manage your sign-in account and password';

  @override
  String get mySupportSubtitle => 'Ask a question or read our policies';

  @override
  String get myWithdrawSubtitle => 'Please check once before you leave';

  @override
  String get myPageTitle => 'Profile & settings';

  @override
  String get myProfileTitle => 'Profile';

  @override
  String get myEmail => 'Email';

  @override
  String get myBasicInfoHint => 'Members see this on your trainer profile';

  @override
  String get myNotificationsHint => 'Choose which alerts you get';

  @override
  String get myAccountInfo => 'Account';

  @override
  String get myAccountInfoHint =>
      'To change your name or email, contact support.';

  @override
  String get mySecurity => 'Security';

  @override
  String get myDiscardTitle => 'Stop editing?';

  @override
  String get myDiscardBody => 'Your changes won\'t be saved.';

  @override
  String get myKeepEditing => 'Keep editing';

  @override
  String get myDiscardAction => 'Leave';

  @override
  String get mySignOutConfirm => 'Log out of this browser?';

  @override
  String get myThisMonth => 'This month';

  @override
  String get myIntroEmpty =>
      'No introduction yet. Add one in Edit profile — members see it.';

  @override
  String get myCertsEmpty => 'No certifications yet';

  @override
  String get myGymEmpty => 'No gym yet. Add yours in Edit profile.';

  @override
  String get myEditVisibleBody =>
      'Your specialty, career, introduction, certifications and gym appear on your trainer profile in the member app.';

  @override
  String get myClientManagementNoteTitle => 'Removing only hides members here';

  @override
  String get myClientManagementNote =>
      'Their records stay in the member app. To coach them again, add them by member ID from New member on the Members tab.';

  @override
  String get myNotifConsultation => 'Consultation requests';

  @override
  String get myNotifConsultationHint =>
      'When a member requests a consultation or answers your invite';

  @override
  String get myNotifReservation => 'Bookings';

  @override
  String get myNotifReservationHint =>
      'When a member books or changes a session';

  @override
  String get myNotifMemberUpdates => 'Member updates';

  @override
  String get myNotifMemberUpdatesHint =>
      'When a member changes goals or name, or disconnects';

  @override
  String get routineTypeWalking => 'Walking';

  @override
  String get routineTypeCardio => 'Cardio';

  @override
  String get routineTypeStrength => 'Strength';

  @override
  String get routineTypeYoga => 'Yoga';

  @override
  String get routineTypeStretching => 'Stretching';

  @override
  String get routineTypeFlexibility => 'Stretching';

  @override
  String get routineTypeOther => 'Other';

  @override
  String get routineFieldType => 'Exercise type';

  @override
  String get routineFieldMinutes => 'Duration';

  @override
  String get routineFieldTotalMinutes => 'Total workout time';

  @override
  String get routineFieldIntensity => 'Intensity';

  @override
  String get routineFieldDate => 'Date';

  @override
  String get routineFieldExerciseName => 'Exercise name';

  @override
  String get routineFieldExerciseNameHint => 'e.g. Squat, Treadmill';

  @override
  String get routineFieldExerciseNameHintCardio =>
      'e.g. Treadmill, Indoor cycling';

  @override
  String get routineFieldExerciseNameHintStrength => 'e.g. Squat, Bench press';

  @override
  String get routineFieldExerciseNameHintFlexibility =>
      'e.g. Full-body stretch, Yoga';

  @override
  String get routineFieldExerciseNameHintOther =>
      'e.g. Rehab exercise, Sports activity';

  @override
  String get routineFieldSets => 'Sets';

  @override
  String get routineFieldReps => 'Reps';

  @override
  String get routineFieldHold => 'Hold time';

  @override
  String get routineFieldMeasure => 'Measured in';

  @override
  String get routineFieldWeight => 'Weight';

  @override
  String get routineFieldCalories => 'Estimated calories';

  @override
  String get routineCaloriesNeedName => 'Enter an exercise name';

  @override
  String get routineCaloriesRoughEstimate =>
      'A rough average for this exercise type · the saved record will also use the member\'s weight';

  @override
  String get routineUnitMinutes => 'min';

  @override
  String get routineUnitSets => 'sets';

  @override
  String get routineUnitReps => 'reps';

  @override
  String get routineUnitSeconds => 'sec';

  @override
  String get routineUnitKg => 'kg';

  @override
  String routineKcalValue(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString kcal';
  }

  @override
  String get intensityLight => 'Light';

  @override
  String get intensityModerate => 'Moderate';

  @override
  String get intensityHigh => 'High';

  @override
  String get coachTitle => 'Programs';

  @override
  String get coachSubtitle =>
      'Create, assign, and manage exercise programs for each member';

  @override
  String get coachMemberSummary => 'Member summary';

  @override
  String get reportsDataInsufficient => 'Insufficient data';

  @override
  String get coachSendFailed => 'Couldn\'t send. Please try again';

  @override
  String get coachScheduleFailed =>
      'Couldn\'t add it to the schedule. Please try again';

  @override
  String get coachNoClients => 'No members yet';

  @override
  String get coachRecommended => 'AI suggestions';

  @override
  String get coachBackToList => 'Back to suggestions';

  @override
  String get coachTrainerAdded => 'Added by trainer';

  @override
  String coachTemplateAdded(String name) {
    return 'Added from $name template';
  }

  @override
  String coachRegisteredOn(String date) {
    return 'Added to the $date schedule';
  }

  @override
  String coachRegisteredAttachedExisting(String date) {
    return 'There was already a session planned on $date, so the program was only attached to it — the time range you picked wasn\'t applied';
  }

  @override
  String coachRegisterOn(String date) {
    return 'Add to the $date PT schedule';
  }

  @override
  String get coachRegisterAction => 'Add to PT schedule';

  @override
  String get coachGoToSchedule => 'Go to schedule';

  @override
  String get labelTomorrow => 'Tomorrow';

  @override
  String get coachRequestCustom => 'Ask AI for a custom suggestion';

  @override
  String coachRequestBlurb(String name) {
    return 'We\'ll analyse $name\'s data, draft a recovery and a push option, and let you compare and edit them here.';
  }

  @override
  String get coachTemplates => 'Program templates';

  @override
  String get coachSentHistory => 'Sent history';

  @override
  String get coachHistoryFailed => 'Couldn\'t load history';

  @override
  String get coachHistoryEmpty => 'You haven\'t sent any programs yet';

  @override
  String get coachHomework => 'Personal';

  @override
  String get coachPersonalTraining => 'PT';

  @override
  String coachRoutineSummary(String name, int minutes) {
    return '$name · $minutes min';
  }

  @override
  String get coachTrainer => 'Trainer';

  @override
  String coachSessionProgramSummary(String name, int count) {
    return '$name + $count more';
  }

  @override
  String get aiReasonSodium =>
      'Sodium is over target today, so lean into low-intensity cardio.';

  @override
  String get aiReasonBalanced =>
      'Today\'s meals are balanced, so the current intensity is fine to keep.';

  @override
  String aiReasonGoal(String goal, String last) {
    return 'Based on the $goal goal and recent $last activity.';
  }

  @override
  String get aiTagExisting => 'Existing suggestion';

  @override
  String get aiTagCustom => 'Custom';

  @override
  String get aiExistingBlurb =>
      'The existing suggestion, based on their recent meals and workouts.';

  @override
  String get aiOptionRecovery => 'Recovery';

  @override
  String get aiOptionPush => 'Push';

  @override
  String get aiOptionExisting => 'Existing';

  @override
  String get aiGenerateFailed =>
      'AI generation failed. Please try again in a moment';

  @override
  String get aiGenerateRateLimited =>
      'Too many generation requests. Please try again shortly';

  @override
  String get aiExerciseNameRequired => 'Enter an exercise name';

  @override
  String get aiKeepOneExercise => 'Keep at least one exercise';

  @override
  String aiRoutineSent(String name) {
    return 'Program sent to $name';
  }

  @override
  String aiExerciseWithMinutes(String name, int minutes) {
    return '$name · $minutes min';
  }

  @override
  String aiCustomRoutineNamed(String option) {
    return 'AI custom suggestion ($option)';
  }

  @override
  String get aiCustomRoutineName => 'AI custom suggestion';

  @override
  String get aiAnalysing => 'AI is analysing…';

  @override
  String get aiGenerateCandidates => 'Generate candidates';

  @override
  String get aiReviewDone => 'Reviewed';

  @override
  String aiRoutineFor(String name) {
    return 'AI suggestion · $name';
  }

  @override
  String get aiAnalysedData => 'Member status';

  @override
  String get aiGoal => 'Goal';

  @override
  String get aiTodaySodium => 'Sodium today';

  @override
  String get aiOverTarget => ' · over target';

  @override
  String get aiRecentCompletion => 'Recent completion';

  @override
  String get aiNoCompletionData => 'No activity logged this week';

  @override
  String get aiCompletionLow => ' · needs attention';

  @override
  String get aiDietSignal => 'Diet warning';

  @override
  String aiSodiumOverDaysSuffix(int days) {
    return ' · over target on $days of the last 7 days';
  }

  @override
  String get aiSugarAlsoOver => ' · sugar also over';

  @override
  String get aiDirectionLabel => 'Direction';

  @override
  String get aiDirectionLower => 'Lower intensity — recent completion is low';

  @override
  String get aiDirectionCardio => 'More cardio — sodium is often over target';

  @override
  String get aiDirectionLowerAndCardio => 'Lower intensity · more cardio';

  @override
  String get aiDirectionKeep => 'Keep current intensity';

  @override
  String get aiDirectionNoData => 'Not enough records yet';

  @override
  String get aiBasisRuleBased => ' · rule-based';

  @override
  String get aiChatEvidenceTitle => 'Recent conversation used';

  @override
  String aiEditOption(String option) {
    return 'Edit $option';
  }

  @override
  String get aiEditBlurb =>
      'Edit names, durations and structure just like the existing suggestion.';

  @override
  String get aiAddExerciseManually => 'Add exercise manually';

  @override
  String get aiExerciseNameExample => 'e.g. leg press, 3 sets';

  @override
  String get aiRegister => 'Add';

  @override
  String get aiNoteForClient => 'A note to send with it';

  @override
  String aiReviewedSuggestion(String option) {
    return 'Confirmed plan · $option';
  }

  @override
  String get aiEditsApplied =>
      'Your choice and edits are now in the final suggestion list.';

  @override
  String aiGoToChat(String name) {
    return 'Open chat with $name';
  }

  @override
  String get aiSending => 'Sending…';

  @override
  String get aiSendToClient => 'Send to member';

  @override
  String get aiGoToChatHint =>
      'Use the button below to jump into their chat and explain it.';

  @override
  String get aiApplyToTemplate => 'Apply to template';

  @override
  String get aiAppliedToTemplate =>
      'The AI suggestion was applied to the program template.';

  @override
  String get aiStepConditions => 'Set up';

  @override
  String get aiStepReview => 'Program selection';

  @override
  String get aiStepDone => 'Program review';

  @override
  String get aiSkipPtProgram => 'Skip PT — personal exercise only';

  @override
  String get aiPersonalRationaleLabel => 'Why AI picked this';

  @override
  String get routineEvidenceRecentPtFeedback => 'Recent PT feedback';

  @override
  String get routineEvidenceStrengthHeavy => 'Mostly strength lately';

  @override
  String get routineEvidenceBloodPressureGoal => 'Blood pressure goal';

  @override
  String get routineEvidenceLowCardio => 'Little cardio lately';

  @override
  String get routineEvidenceRecentRecord => 'Recent workout log';

  @override
  String get aiPlanIntensityLow => 'Low';

  @override
  String aiPersonalStepFull(int count) {
    return 'You can set up to $count personal exercises at once.';
  }

  @override
  String get aiPersonalEditDone => 'Done editing';

  @override
  String aiPersonalStepBadge(int count) {
    return '$count AI suggested';
  }

  @override
  String aiPersonalStepIntro(String name) {
    return 'Based on recent PT feedback and workout history, here is personal exercise for $name. Only what stays here goes to the member.';
  }

  @override
  String get aiPersonalStepLoadFailed =>
      'Could not load the AI personal-exercise suggestions';

  @override
  String get aiPersonalStepNoSuggestion =>
      'No AI suggestion today. Add one below.';

  @override
  String aiProgramExerciseRemoveBody(String name) {
    return 'Removes $name from this program.';
  }

  @override
  String get aiPersonalDismissTitle => 'Drop this exercise?';

  @override
  String aiPersonalDismissBody(String name) {
    return '$name will be dropped from this personal exercise. An AI suggestion will not come back.';
  }

  @override
  String get aiPersonalDismissTooltip => 'Drop this suggestion';

  @override
  String aiPersonalDismissed(String name) {
    return '$name will not be recommended';
  }

  @override
  String get aiPersonalDismissFailed =>
      'Could not complete that. Please try again shortly.';

  @override
  String get aiStepSkipped => 'Skipped';

  @override
  String get aiStepPersonal => 'Personal exercise';

  @override
  String get aiGoToPersonalStep => 'Next · plan personal exercise';

  @override
  String get aiPersonalStepTitle => 'Personal exercise between PT';

  @override
  String get aiPersonalStepTitleRoutineOnly => 'This week\'s personal exercise';

  @override
  String get aiPersonalStepBlurb =>
      'Attached to this PT and sent to the member when you complete it. Pick at least one.';

  @override
  String get aiPersonalStepBlurbRoutineOnly =>
      'What the member does on their own this week. Pick at least one.';

  @override
  String get aiPersonalStepEmpty => 'No personal exercise yet. Add one below.';

  @override
  String get aiPersonalStepNext => 'Next';

  @override
  String get aiKeepOnePersonalRoutine => 'Keep at least one personal exercise.';

  @override
  String get aiRoutineOnlyReviewTitle => 'Sending this to the member';

  @override
  String get aiRoutineOnlyStartDate => 'Start date';

  @override
  String aiRoutineOnlyWeekRange(String start, String end) {
    return 'Shown daily $start – $end';
  }

  @override
  String get aiRoutineOnlyWeeklyHint =>
      'Appears in the member app every day for 7 days from today. Send next week\'s set again then.';

  @override
  String get aiRoutineOnlySend => 'Send to member';

  @override
  String get aiRoutineOnlySentLabel => 'Sent';

  @override
  String get aiRoutineOnlySent => 'Personal exercise sent to the member.';

  @override
  String get aiRoutineOnlySendFailed =>
      'Could not send the personal exercise. Please try again shortly.';

  @override
  String get aiRoutineOnlyProgramName => 'This week\'s personal exercise';

  @override
  String get progPersonalRoutinesWhen =>
      'Goes to the member when you complete this PT.';

  @override
  String programRoutineOnlyConfirmBody(
    String client,
    String start,
    String end,
  ) {
    return 'Sends personal exercise to $client. Appears daily from $start to $end.';
  }

  @override
  String get progPersonalRoutinesTitle => 'Personal exercise for this PT';

  @override
  String progPersonalRoutinesCount(int count) {
    return '$count personal exercises going with it';
  }

  @override
  String get aiStepperLabel => 'Custom suggestion progress';

  @override
  String coachTemplateSummaryWithGoal(String goal, int count, int minutes) {
    return '$goal · $count exercises · $minutes min';
  }

  @override
  String get aiInsightMemoTitle => 'Needs attention (last 7 days)';

  @override
  String get aiInsightMemoEmpty => 'No insights detected in the last 7 days';

  @override
  String get aiInsightMemoFailed => 'Couldn\'t load the detected memos';

  @override
  String aiRecentRoutineMore(String name, int count) {
    return '$name and $count more';
  }

  @override
  String get aiNoRecentRoutine => 'No record';

  @override
  String get aiRecentRoutine => 'Recent activity';

  @override
  String get aiTrainerNoteEditable => 'Trainer\'s note · editable';

  @override
  String get aiNotePlaceholderHint =>
      'The grey suggestion is only a prompt — only what you type is saved and sent.';

  @override
  String get aiGenerateConditions => 'Conditions';

  @override
  String get aiCompareCandidates => 'Compare the candidates';

  @override
  String get aiConditionsAutoHint =>
      'Leave blank to auto-fill from recent history or goals.';

  @override
  String get aiConditionsEditToggle => 'Edit recommended conditions';

  @override
  String get aiPromptTitle => 'Tell the AI what program you want';

  @override
  String get aiPromptLabel => 'Your request';

  @override
  String get aiPromptHint =>
      'e.g. Build a 40-minute program that goes easy on the legs and leans on cardio';

  @override
  String get aiPromptBlurb =>
      'Your request goes to the AI with the member\'s data (up to 500 characters). Write the member note in the next step.';

  @override
  String get aiGenerateGoalBased => 'Generate goal-based suggestion';

  @override
  String get aiStatusTemplateTitle => 'Goal-based starter suggestion';

  @override
  String get aiStatusTemplateBody =>
      'Not enough workout history yet to personalize — this starts from a goal-based default.';

  @override
  String get aiStatusLearningTitle => 'Personalizing (learning)';

  @override
  String get aiStatusLearningBody =>
      'Recent workouts were used, but there isn\'t a clear repeated pattern yet.';

  @override
  String get aiStatusPersonalizedTitle => 'Personalized from recent patterns';

  @override
  String aiStatusPersonalizedBody(int count, int days) {
    return 'Based on $count sessions over the last $days days.';
  }

  @override
  String get aiFrequentExercisesLabel => 'Frequently done';

  @override
  String get goalWeightLoss => 'Weight loss';

  @override
  String get goalHealth => 'General health';

  @override
  String get goalOther => 'Other';

  @override
  String get slotAm => 'AM';

  @override
  String get slotPm => 'PM';

  @override
  String get slotFlexible => 'Flexible';

  @override
  String get unknownMember => 'Unknown member';

  @override
  String get filterAll => 'All';

  @override
  String metricOverBy(String unit) {
    return '$unit over';
  }

  @override
  String get authErrInvalidCredentials =>
      'That email or password isn\'t right.';

  @override
  String get authErrEmailTaken => 'That email is already registered.';

  @override
  String get authErrInviteCodeInvalid =>
      'That invite code isn\'t valid. Please check with your gym.';

  @override
  String get authErrSessionExpired =>
      'Your session expired. Please sign in again.';

  @override
  String get authErrNoSocialToken => 'No social sign-in token';

  @override
  String get authErrNetwork => 'Please check your network connection.';

  @override
  String get authErrGeneric =>
      'Something went wrong signing in. Please try again in a moment.';

  @override
  String get authErrEmptyResponse => 'The response was empty.';

  @override
  String get coachDemoUnavailable =>
      'AI coaching isn\'t available in demo mode';

  @override
  String get coachNotMyClient => 'That isn\'t one of your members';

  @override
  String get coachAskFailed => 'Couldn\'t send your question';

  @override
  String get coachRateLimited =>
      'You\'ve sent too many questions. Please try again in a minute';

  @override
  String get slotFutureOnly =>
      'Booking slots can only be set for future times.';

  @override
  String get slotNotFound => 'Booking slot not found.';

  @override
  String get slotTypeLockedByBooking =>
      'Can\'t change the type of a slot that\'s already booked.';

  @override
  String get slotSessionType => 'Type';

  @override
  String get authErrNotTrainer => 'Please sign in with a trainer account.';

  @override
  String aiBasisGoalCompletion(String goal, int rate) {
    return '$goal · based on $rate% completion';
  }

  @override
  String aiBasisTrainerRequest(String request) {
    return 'Request: \"$request\"';
  }

  @override
  String aiTotalAndIntensity(int total, String intensity) {
    return '$total min total · $intensity';
  }

  @override
  String aiBulletExercise(String name, int minutes) {
    return '· $name · $minutes min ';
  }

  @override
  String schedHourLabel(String hour) {
    return '$hour:00';
  }

  @override
  String schedMinuteLabel(String minute) {
    return '$minute min';
  }

  @override
  String get progDefaultReps => '10 reps';

  @override
  String get appTitleSpaced => 'On - Care Trainer';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get notifTitle => 'Notifications';

  @override
  String get notifReadAll => 'Mark all read';

  @override
  String get notifEmpty => 'No notifications yet';

  @override
  String get notifLoadFailed => 'Couldn\'t load notifications';

  @override
  String get notifLoadMore => 'Load earlier notifications';

  @override
  String get notifLoadMoreFailed => 'Couldn\'t load earlier notifications';

  @override
  String get notifNoEarlier => 'No earlier notifications';

  @override
  String get notifTplHealthGoalTitle => 'Member goals changed';

  @override
  String notifTplHealthGoalBody(String name, String goals) {
    return '$name changed their health goals: $goals';
  }

  @override
  String get notifTplNoGoals => 'none';

  @override
  String get notifTplMemberRenamedTitle => 'Member renamed';

  @override
  String notifTplMemberRenamedBody(String oldName, String newName) {
    return '$oldName changed their name to $newName.';
  }

  @override
  String get notifTplMemberWithdrawnTitle => 'Member account deleted';

  @override
  String notifTplMemberWithdrawnBody(String name) {
    return '$name deleted their account.';
  }

  @override
  String get notifTplMemberDisconnectedTitle => 'Client disconnected';

  @override
  String notifTplMemberDisconnectedBody(String name) {
    return '$name ended their connection with you.';
  }

  @override
  String get notifTplConsultRequestedTitle => 'New consultation request';

  @override
  String get notifTplConsultCancelledTitle => 'Consultation request cancelled';

  @override
  String get notifTplConsultWithdrawnTitle =>
      'Consultation request cancelled: member account deleted';

  @override
  String get notifTplInviteAcceptedTitle => 'Coaching request accepted';

  @override
  String notifTplInviteAcceptedBody(String name) {
    return '$name is now your client.';
  }

  @override
  String get notifTplInviteRejectedTitle => 'Coaching request declined';

  @override
  String notifTplInviteRejectedBody(String name) {
    return '$name declined your coaching request.';
  }

  @override
  String get notifTplReservationBookedTitle => 'New booking';

  @override
  String get notifTplReservationCancelledTitle => 'Booking cancelled';

  @override
  String notifTplMemberWithDetail(String name, String detail) {
    return '$name · $detail';
  }

  @override
  String notifTplMemberOnly(String name) {
    return '$name';
  }

  @override
  String notifTplWhen(String month, String day, String time) {
    return '$month/$day $time';
  }

  @override
  String notifTplMemberMessageTitle(String name) {
    return 'Message from $name';
  }

  @override
  String get notifTplMemberPhotoBody => 'Sent a photo';

  @override
  String get notifAllRead => 'All caught up';

  @override
  String get notifReadAllFailed =>
      'Couldn\'t mark them read. Please try again in a moment';

  @override
  String notifUnreadCount(int count) {
    return '$count unread';
  }

  @override
  String get myDeleteAccount => 'Delete account';

  @override
  String get myDeleteAction => 'Delete';

  @override
  String get myDeleteDemo => 'Demo mode has no account to delete';

  @override
  String get myDeleteTitle => 'Delete your account?';

  @override
  String get myDeleteBody =>
      'Your member links and bookings are removed and your members are notified. This can\'t be undone.';

  @override
  String get myDeleteFailed =>
      'Couldn\'t delete your account. Please try again in a moment';

  @override
  String myDeleteConfirmPrompt(String name) {
    return 'Type your name ($name) to continue';
  }

  @override
  String get myWithdrawReasonTitle => 'Are you sure you want to leave?';

  @override
  String get myWithdrawReasonQuestion => 'What didn\'t work for you?';

  @override
  String get myWithdrawReasonHint => 'Pick as many as you like, or skip.';

  @override
  String get myWithdrawReasonRarelyUsed => 'I rarely use it';

  @override
  String get myWithdrawReasonHardToUse => 'It\'s hard to use';

  @override
  String get myWithdrawReasonMissingFeature =>
      'It lacks features I need for members';

  @override
  String get myWithdrawReasonLeavingWork => 'I\'m taking a break from training';

  @override
  String get myWithdrawReasonAlternative => 'I use another tool';

  @override
  String get myWithdrawReasonOther => 'Something else';

  @override
  String get myWithdrawKeepTitle => 'Before you go';

  @override
  String get myWithdrawKeepRarelyUsed =>
      'Turn on alerts so you don\'t miss member messages and bookings. Change them in Settings › Notifications.';

  @override
  String get myWithdrawKeepHardToUse =>
      'Tell us what felt awkward via 1:1 inquiry and we\'ll work on it.';

  @override
  String get myWithdrawKeepMissingFeature =>
      'Tell us which feature you need via 1:1 inquiry — we\'ll consider it next.';

  @override
  String get myWithdrawKeepLeavingWork =>
      'If it\'s just a break, you can keep your account. Leaving disconnects all your members.';

  @override
  String get myWithdrawKeepAlternative =>
      'Leaving removes member records, programs and reports from your console for good.';

  @override
  String get myWithdrawKeepOther =>
      'Your feedback via 1:1 inquiry would help us a lot.';

  @override
  String get myWithdrawKeepDefault =>
      'Leaving removes your member connections and bookings, and your members are notified. This can\'t be undone.';

  @override
  String get myWithdrawNext => 'Next';

  @override
  String get myWithdrawStay => 'Keep using';

  @override
  String get myWithdrawContinue => 'Continue leaving';

  @override
  String get routineAlreadyGone => 'That program is already gone';

  @override
  String get workoutPendingTitle => 'Daily personal exercises';

  @override
  String get workoutRoutineDoneToday => 'Done today';

  @override
  String get workoutUndatedTitle => 'Records without a date';

  @override
  String get workoutPendingCancel => 'Cancel assignment';

  @override
  String get routineUpdateFailed =>
      'Couldn\'t update the program. Please try again in a moment';

  @override
  String get routineUpdated => 'Program updated';

  @override
  String get routineDeleteTitle => 'Delete this program?';

  @override
  String get routineDeleteFailed =>
      'Couldn\'t delete the program. Please try again in a moment';

  @override
  String get routineDeleted => 'Program deleted';

  @override
  String get routineEdit => 'Edit program';

  @override
  String get routineDelete => 'Delete program';

  @override
  String get routineNameRequired => 'Enter a program name';

  @override
  String get routineNameTooLong => 'Keep the name to 100 characters or fewer';

  @override
  String get routineMinutesRange =>
      'Duration must be between 0 and 600 minutes';

  @override
  String get routineReasonTooLong =>
      'Keep the reason to 200 characters or fewer';

  @override
  String get routineFieldName => 'Program name';

  @override
  String get routineFieldMinutesLabel => 'Duration (min)';

  @override
  String get routineFieldReason => 'Reason (optional)';

  @override
  String routineDeleteBody(String name) {
    return '$name disappears from the member\'s app too.';
  }

  @override
  String get searchClients => 'Search members';

  @override
  String get searchClientsHint =>
      'Members, goals, recent messages, last program sent date';

  @override
  String get searchClear => 'Clear search';

  @override
  String get searchQuickActions => 'Open in another tab';

  @override
  String searchNoResults(String query) {
    return 'No member matches “$query”';
  }

  @override
  String get searchGoClientDetail => 'Picking one opens their detail';

  @override
  String get searchGoSchedule => 'Picking one jumps to their next booked day';

  @override
  String get searchGoCoaching => 'Picking one loads them into AI coaching';

  @override
  String get searchGoReport => 'Picking one opens their weekly report';

  @override
  String searchDetailUnread(int count) {
    return '$count awaiting a reply';
  }

  @override
  String searchDetailMessage(String message, String time) {
    return '$message · $time';
  }

  @override
  String searchDetailNextSession(String date, String time) {
    return 'Next session $date $time';
  }

  @override
  String get searchDetailNoUpcoming => 'Nothing booked';

  @override
  String searchDetailLastRoutine(String when) {
    return 'Last program $when';
  }

  @override
  String searchDetailCompletion(int percent) {
    return '$percent% completion this week';
  }

  @override
  String get navOperationsGroup => 'Operations';

  @override
  String get navCoachingGroup => 'Coaching';

  @override
  String get dashTodayTasks => 'Today\'s tasks';

  @override
  String get dashTasksReviewed => 'All reviewed';

  @override
  String dashTasksNeedReview(int count) {
    return '$count to review';
  }

  @override
  String get dashTaskProgressTitle => 'Task completion';

  @override
  String get dashTaskProgressToday => 'Today\'s tasks';

  @override
  String get dashTaskProgressCarriedOver => 'Carried over';

  @override
  String get dashTodoConsultation => 'Consult';

  @override
  String get dashTodoDiet => 'Diet';

  @override
  String get dashTodoWorkout => 'Workout';

  @override
  String get dashTodoProgram => 'Program';

  @override
  String get dashTodoReport => 'Report';

  @override
  String dashTodoConsultationSubtitle(int month, int day) {
    return 'Consultation request for $month/$day';
  }

  @override
  String get dashTodoCarriedOverDemoSubtitle =>
      'Diet feedback left over from yesterday';

  @override
  String get dashTodoProgramSubtitle => 'No recent program sent';

  @override
  String get dashTodoReportSubtitle => 'This week\'s report is due';

  @override
  String get dashTaskSaveFailed =>
      'Couldn\'t save your task status. Please try again in a moment';

  @override
  String get dashTaskLoadFailed =>
      'Couldn\'t load your task status. Please try again in a moment';

  @override
  String get dashTaskDismissTitle => 'Delete this item?';

  @override
  String get dashTaskDismissBody =>
      'It only disappears from the task list. Actually handling it (consultation, program, report) still happens on its own screen.';

  @override
  String get dashTaskCarriedOverTitle => 'Carried over';

  @override
  String get dashTaskCategoryDone => 'Done';

  @override
  String get dashTaskCategoryEmpty => 'None';

  @override
  String dashTaskCategoryRemaining(int count) {
    return '+$count';
  }

  @override
  String dashTaskUncheckTitle(String name) {
    return 'Undo completion of \'$name\'?';
  }

  @override
  String get dashTaskUncheckBody =>
      'It also drops off the task progress chart.';

  @override
  String get dashTaskUncheckConfirm => 'Undo completion';

  @override
  String get churnNoRecentFeedback => 'No trainer feedback in 7 days';

  @override
  String get navMessages => 'Messages';

  @override
  String get messagesSubtitle =>
      'Exchange coaching updates with members and follow up quickly';

  @override
  String get messagesLoadFailed => 'Couldn\'t load conversations.';

  @override
  String get messagesEmpty => 'No conversations match these filters.';

  @override
  String get messagesFilterAll => 'All';

  @override
  String get messagesFilterUnread => 'Unread';

  @override
  String get messagesFilterAttention => 'Needs attention';

  @override
  String messagesFilterUnreadCount(int count) {
    return 'Unread $count';
  }

  @override
  String get messagesBackToList => 'Conversation list';

  @override
  String get messagesNoPreview => 'No messages yet';

  @override
  String get messagesPreviewEmote => 'Sent an emote';

  @override
  String get messagesTimeJustNow => 'Just now';

  @override
  String get messagesClientDetail => 'Member details';

  @override
  String get messagesSelectPrompt =>
      'Select a member from the list to start a conversation.';

  @override
  String get clientQuickMessages => 'Messages';

  @override
  String get clientQuickProgram => 'Program';

  @override
  String get clientQuickReport => 'Report';

  @override
  String get clientProfileSectionTitle => 'Body and goals';

  @override
  String get clientTrainerMemo => 'Memo';

  @override
  String get clientHealthUnset => 'Not set';

  @override
  String get clientHealthTabBody => 'Body';

  @override
  String get clientHealthTabFocus => 'Health goals';

  @override
  String get clientGoalPerDay => 'Per day';

  @override
  String get clientGoalCalories => 'Calories';

  @override
  String get clientGoalSodium => 'Sodium';

  @override
  String get clientGoalSugar => 'Sugar';

  @override
  String get clientGoalCarbs => 'Carbs';

  @override
  String get clientGoalProtein => 'Protein';

  @override
  String get clientGoalFat => 'Fat';

  @override
  String get clientGoalBurnDaily => 'Daily burn';

  @override
  String get clientGoalCardioWeekly => 'Weekly cardio';

  @override
  String get clientGoalStrengthWeekly => 'Weekly strength';

  @override
  String get clientGoalStretchWeekly => 'Weekly stretching';

  @override
  String get clientBodyHeight => 'Height';

  @override
  String get clientBodyWeight => 'Weight';

  @override
  String get clientUnitCm => 'cm';

  @override
  String get clientGoalDefaultHint =>
      'Faded values are the defaults used until a goal is set. Empty fields use them.';

  @override
  String clientGoalSuggestionDiet(
    int kcal,
    int carbs,
    int sugar,
    int protein,
    int fat,
    int sodium,
  ) {
    return 'Suggested: $kcal kcal · carbs $carbs g · sugar $sugar g · protein $protein g · fat $fat g · sodium $sodium mg';
  }

  @override
  String clientGoalSuggestionExercise(
    int burn,
    int cardio,
    int strength,
    int flexibility,
  ) {
    return 'Suggested: $burn kcal burned a day · $cardio min cardio · $strength strength sets · $flexibility min stretching a week';
  }

  @override
  String get clientGoalSuggestionPersonal =>
      'Based on age, sex, height, weight, and health goals (2020 KDRIs and WHO guidelines)';

  @override
  String get clientGoalSuggestionFallback =>
      'Age, height, or weight is missing, so only the health goals adjust the defaults';

  @override
  String get clientGoalApplySuggestion => 'Fill with suggestion';

  @override
  String get clientTrainerMemoHint =>
      'Note what you want to remember about this member';

  @override
  String get clientTrainerMemoAdd => 'Add memo';

  @override
  String get clientTrainerMemoEmpty => 'No memos yet.';

  @override
  String get clientTrainerMemoFromChat => 'From chat';

  @override
  String get clientTrainerMemoLoadFailed =>
      'Couldn\'t load memos. Please try again.';

  @override
  String get clientTrainerMemoSaveFailed =>
      'Couldn\'t save the memo. Please try again.';

  @override
  String get clientTrainerMemoDeleteFailed =>
      'Couldn\'t delete the memo. Please try again.';

  @override
  String get clientTrainerMemoDeleteTitle => 'Delete this memo?';

  @override
  String get clientTrainerMemoDeleteBody =>
      'A deleted memo can\'t be restored.';

  @override
  String get followUp => 'Follow-ups';

  @override
  String followUpTitle(String name) {
    return 'Follow-ups on $name';
  }

  @override
  String get followUpHint => 'Note what you want to check again';

  @override
  String get followUpAdd => 'Add follow-up';

  @override
  String get followUpDue => 'Check on';

  @override
  String followUpDueOn(String date) {
    return 'Check on $date';
  }

  @override
  String get followUpOverdue => 'Overdue';

  @override
  String get followUpContext => 'Opens';

  @override
  String get followUpContextGeneral => 'Member detail';

  @override
  String get followUpContextDiet => 'Diet';

  @override
  String get followUpContextExercise => 'Workout';

  @override
  String get followUpContextMessage => 'Messages';

  @override
  String get followUpContextProgram => 'Program';

  @override
  String get followUpContextSchedule => 'Schedule';

  @override
  String get followUpComplete => 'Done';

  @override
  String followUpCount(int count) {
    return '$count left';
  }

  @override
  String get followUpEmpty => 'No follow-ups left.';

  @override
  String get followUpDashboardEmpty => 'Nothing to follow up on today.';

  @override
  String get followUpLoadFailed =>
      'Couldn\'t load follow-ups. Please try again.';

  @override
  String get followUpSaveFailed =>
      'Couldn\'t save the follow-up. Please try again.';

  @override
  String get followUpCompleteFailed =>
      'Couldn\'t mark it done. Please try again.';

  @override
  String programEditorDefaultName(String goal) {
    return '$goal program';
  }

  @override
  String get programEditorDefaultSession => 'Session A';

  @override
  String get programEditorSaveUnsupported => 'Give the program a name first.';

  @override
  String get programEditorSaveEdit => 'Save changes';

  @override
  String get programSavedTitle => 'Saved programs';

  @override
  String programSavedExerciseCount(int count) {
    return '$count exercises';
  }

  @override
  String get programSavedNew => 'New program';

  @override
  String get programDraftSaved => 'Program saved.';

  @override
  String get programDraftSaveFailed =>
      'Couldn\'t save the program. Please try again.';

  @override
  String get programDraftLoadFailed =>
      'Couldn\'t open the saved program. Please try again.';

  @override
  String get programDraftDeleteFailed =>
      'Couldn\'t delete the program. Please try again.';

  @override
  String get programDraftDeleteTitle => 'Delete this saved program?';

  @override
  String get programDraftDeleteBody =>
      'Programs you already assigned and sessions you scheduled stay as they are.';

  @override
  String programAssignConfirmAttachBody(
    String name,
    String date,
    String session,
    String selected,
  ) {
    return 'This program will be attached to $name\'s PT already planned for $date $session. The time you picked ($selected) won\'t be applied.';
  }

  @override
  String programAssignConfirmChooseBody(
    String name,
    String date,
    String selected,
  ) {
    return '$name has several PT sessions on $date that overlap the time you picked ($selected). Choose the session to attach this program to. The picked time won\'t be applied.';
  }

  @override
  String get coachAttachTargetChanged =>
      'The PT session to attach to has changed. Tap Add to schedule again to check';

  @override
  String get coachScheduleOverlap =>
      'Another session is already booked at that time, so nothing was added. Pick a different time and try again';

  @override
  String get programEditorNoExercises => 'Add at least one exercise';

  @override
  String get programEditorExerciseNameInvalid =>
      'An exercise name is empty or longer than 100 characters';

  @override
  String get programEditorRegisterDatePast =>
      'That date has passed. Pick today or a later date';

  @override
  String get coachSendNetworkFailed =>
      'Check your network connection and try again';

  @override
  String get coachSendClientNotFound =>
      'This member isn\'t linked to you. Check the member\'s connection';

  @override
  String get coachSendInvalid =>
      'The server didn\'t accept this schedule. Check the date, time and exercises';

  @override
  String get coachSendUnverified =>
      'Couldn\'t confirm the result. Check the schedule to see whether it was added';

  @override
  String programEditorSessionLimitReached(int max) {
    return 'A program can have up to $max sessions';
  }

  @override
  String programEditorExerciseLimitReached(int max) {
    return 'A program can have up to $max exercises in total';
  }

  @override
  String programEditorSizeExceeded(
    int sessions,
    int maxSessions,
    int exercises,
    int maxExercises,
  ) {
    return '$sessions/$maxSessions sessions · $exercises/$maxExercises exercises — remove the extra to add it to the schedule';
  }

  @override
  String get programAssignConfirmTitle => 'Add to the schedule?';

  @override
  String programAssignConfirmBody(String name, String date, String time) {
    return 'A new PT session will be created for $name on $date at $time with this program.';
  }

  @override
  String get programEditorSaveTemplate => 'Save as template';

  @override
  String get programEditorAddSchedule => 'Add to schedule';

  @override
  String get programReviewTitle => 'Confirm & send';

  @override
  String programReviewBlurb(String name) {
    return 'Exactly what you see below is what $name receives. Check it, then send.';
  }

  @override
  String get programReviewBack => 'Back to the editor';

  @override
  String programReviewSessionSummary(int count) {
    return '$count exercises';
  }

  @override
  String get programEditorInfo => 'Program information';

  @override
  String get programEditorName => 'Program name';

  @override
  String get programEditorGoal => 'Goal (optional)';

  @override
  String get programEditorPeriod => 'Period (optional)';

  @override
  String get programEditorMemo => 'Program memo (optional)';

  @override
  String get programEditorAiHint =>
      'Apply AI coaching suggestions to the first session as a local draft.';

  @override
  String get programEditorApply => 'Apply to editor';

  @override
  String get programEditorExerciseConfig => 'Workout structure';

  @override
  String get programEditorAddSession => 'Add session';

  @override
  String get programTemplateSessionPickerTitle => 'Add to which session?';

  @override
  String programTemplateSessionPickerBody(String name) {
    return 'Choose a session for the \'$name\' template.';
  }

  @override
  String programEditorSessionNameTyped(String type) {
    return '$type session';
  }

  @override
  String programEditorSessionNameNumbered(String type, int index) {
    return '$type session $index';
  }

  @override
  String get programEditorSessionUp => 'Move session up';

  @override
  String get programEditorSessionDown => 'Move session down';

  @override
  String get programEditorSessionReset => 'Reset session';

  @override
  String get programEditorSessionResetTitle => 'Reset this session?';

  @override
  String programEditorSessionResetBody(String name) {
    return 'Every exercise in \'$name\' will be cleared. The session itself and other sessions stay.';
  }

  @override
  String get programEditorSessionEmpty =>
      'Add exercises to build this session.';

  @override
  String get programEditorAdd => 'Add';

  @override
  String get programEditorAddExercise => 'Add exercise';

  @override
  String get programEditorExercise => 'Exercise';

  @override
  String get programEditorExerciseUp => 'Move exercise up';

  @override
  String get programEditorExerciseDown => 'Move exercise down';

  @override
  String get programEditorExerciseMoveSession => 'Move to another session';

  @override
  String get programEditorExerciseMoveTitle =>
      'Which session should it move to?';

  @override
  String programEditorExerciseMoveBody(String name) {
    return 'Pick the session to move \'$name\' into.';
  }

  @override
  String get programEditorSets => 'Sets';

  @override
  String get programEditorReps => 'Reps';

  @override
  String get programEditorWeight => 'Weight kg';

  @override
  String get programEditorDuration => 'Time min';

  @override
  String get programEditorDistance => 'Distance m';

  @override
  String reportsComparisonTitle(String week) {
    return '$week vs last week';
  }

  @override
  String get reportsGoThisWeek => 'Go to this week';

  @override
  String get reportsSummaryEmptyClient =>
      'Select a member to see their weekly summary and coaching suggestions here';

  @override
  String get reportsLastWeek => 'Last week';

  @override
  String get reportsSelectedWeek => 'Selected week';

  @override
  String get reportsBackToList => 'Member list';

  @override
  String get reportsPreviousLoadFailed => 'Couldn\'t load last week\'s data.';

  @override
  String get reportsAverageSodium => 'Average sodium';

  @override
  String get reportsFeedbackTitle => 'Trainer feedback';

  @override
  String get reportsFeedbackDraftNote =>
      'A draft filled in from this week\'s figures. Check it over before sending.';

  @override
  String get reportsFeedbackUndo => 'Undo';

  @override
  String get reportsFeedbackRedo => 'Redo';

  @override
  String get reportsFeedbackSave => 'Save feedback';

  @override
  String get reportsFeedbackSaving => 'Saving…';

  @override
  String get reportsFeedbackSaved => 'Saved the feedback draft.';

  @override
  String get reportsFeedbackSaveFailed =>
      'Couldn\'t save the draft. Please try again.';

  @override
  String get reportsFeedbackHint => 'Write coaching feedback for the member.';

  @override
  String get reportsRecentWeeks => 'Last 4 weekly averages';

  @override
  String get reportsWeekTotal => 'Week total';

  @override
  String reportsGoalOf(String value) {
    return 'Goal $value';
  }

  @override
  String get reportsCompareWith => 'vs last week';

  @override
  String reportsMoreExercises(int count) {
    return '+$count more';
  }

  @override
  String reportsRecordedDays(int days) {
    return '$days days logged';
  }

  @override
  String reportsAdherenceChip(String value) {
    return 'Adherence avg $value';
  }

  @override
  String get reportsBurnByDay => 'Weekly calories burned';

  @override
  String get reportsBurnEstimateNote =>
      'Calories burned are estimated from workout type, duration, and intensity.';

  @override
  String chartGoalLabel(String value) {
    return 'Goal\n$value';
  }

  @override
  String reportsWeeksAgo(int count) {
    return '${count}w ago';
  }

  @override
  String get reportsAiTitle => 'This week\'s summary';

  @override
  String get reportsAiNextWeek => 'Next week\'s coaching';

  @override
  String reportsAiMoreWatchpoints(int count) {
    return '$count more — see the full report.';
  }

  @override
  String get reportsActionSodium =>
      'Ask them to leave half the broth and the pickled sides.';

  @override
  String reportsActionSugar(String target) {
    return 'Some days went over the ${target}g sugar target. Start with drinks and snacks.';
  }

  @override
  String get reportsActionLowCompletion =>
      'Drop the program a notch so they finish it first.';

  @override
  String get reportsActionHighCompletion =>
      'Good pace. Add a set or a little weight next week.';

  @override
  String reportsActionSkipped(String names) {
    return 'Prepare alternatives for $names for the next session.';
  }

  @override
  String reportsActionUnlogged(int days) {
    return '$days days went unlogged. Build the logging habit first.';
  }

  @override
  String reportsActionCalories(String target) {
    return 'Intake is under the ${target}kcal target. Suggest one protein-led meal.';
  }

  @override
  String get reportsAiGenerated => 'AI generated';

  @override
  String get reportsAiLoading => 'Writing this week\'s summary…';

  @override
  String get reportsAiUseAsDraft => 'Use as feedback';

  @override
  String get reportsAiRegenerate => 'Regenerate';

  @override
  String get reportsAiUnavailable =>
      'Available after the report summary API is connected. No summary is generated now.';

  @override
  String get reportsPdfGenerationFailed =>
      'Couldn\'t generate the PDF. Please try again.';

  @override
  String get reportsPdfFallbackClient => 'member';

  @override
  String get reportsPdfDocTitle => 'Weekly coaching report';

  @override
  String get reportsPdfDocTitleContinued =>
      'Weekly coaching report (continued)';

  @override
  String reportsPdfClient(String name) {
    return 'Member  $name';
  }

  @override
  String reportsPdfPeriod(String start, String end) {
    return 'Period  $start – $end';
  }

  @override
  String get reportsPdfSectionMetrics => 'Key metrics';

  @override
  String get reportsPdfSectionChange => 'Change from last week';

  @override
  String get reportsPdfSectionTrend => 'Weekly trend (Mon–Sun)';

  @override
  String get reportsPdfSectionDaily => 'Workouts by day';

  @override
  String reportsPdfBullet(String label, String value) {
    return '• $label: $value';
  }

  @override
  String reportsPdfDay(String weekday, String completion, String exercises) {
    return '$weekday: $completion · $exercises';
  }

  @override
  String get reportsPdfLabelCompletion => 'Workout completion';

  @override
  String get reportsPdfLabelSessions => 'PT sessions';

  @override
  String get reportsPdfLabelSessionCount => 'PT sessions completed';

  @override
  String get reportsPdfLabelSodiumOver => 'Days over sodium target';

  @override
  String get reportsPdfLabelCalories => 'Average calories';

  @override
  String get reportsPdfLabelSugar => 'Average sugar';

  @override
  String get reportsPdfLabelCaloriesShort => 'Calories';

  @override
  String get reportsPdfLabelSodiumShort => 'Sodium';

  @override
  String get reportsPdfLabelSugarShort => 'Sugar';

  @override
  String reportsPdfValuePercent(String value) {
    return '$value%';
  }

  @override
  String reportsPdfValueMg(String value) {
    return '${value}mg';
  }

  @override
  String reportsPdfValueKcal(String value) {
    return '${value}kcal';
  }

  @override
  String reportsPdfValueGram(String value) {
    return '${value}g';
  }

  @override
  String reportsPdfValueDays(String value) {
    return '$value days';
  }

  @override
  String reportsPdfValueSessions(String value) {
    return '$value';
  }

  @override
  String reportsPdfAttendance(String done, String booked, String rate) {
    return '$done/$booked ($rate%)';
  }

  @override
  String get reportsPdfNoData => 'Not measured';

  @override
  String get reportsPdfNoFeedback => 'No feedback';

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
  String get unitMg => 'mg';

  @override
  String get unitGram => 'g';

  @override
  String get a11yRemoveExercise => 'Remove exercise';

  @override
  String get a11yRemoveCertification => 'Remove certification';

  @override
  String get a11yPrevWeek => 'Previous week';

  @override
  String get a11yNextWeek => 'Next week';

  @override
  String get a11ySendMessage => 'Send message';

  @override
  String get aiManualCreate => 'Build manually';

  @override
  String get aiReturnToWizard => 'Back to AI suggestions';

  @override
  String chatDateDivider(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMEEEEd(
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get clientWorkoutSourceAi => 'AI';

  @override
  String coachClientDemographics(String gender, int age) {
    return '$gender · Age $age';
  }

  @override
  String get coachTemplateMenu => 'Template menu';

  @override
  String aiStrengthSummary(int sets, int reps, String weight) {
    return '$sets sets · $reps reps · ${weight}kg';
  }

  @override
  String aiHoldSummary(int sets, int seconds, String weight) {
    return '$sets sets · $seconds sec · ${weight}kg';
  }

  @override
  String get routineFormDecrease => 'Decrease';

  @override
  String get routineFormIncrease => 'Increase';

  @override
  String get reportsWorkbenchTitle => 'This week\'s reports';

  @override
  String get reportsPending => 'Not sent';

  @override
  String reportsCountPeople(int count) {
    return '$count';
  }

  @override
  String get reportsSortLabel => 'Sort';

  @override
  String get reportsSortPriority => 'Needs attention';

  @override
  String get reportsSortName => 'Name A–Z';

  @override
  String get reportsSortNameDescending => 'Name Z–A';

  @override
  String get reportsSentSortUnread => 'Unread first';

  @override
  String reportsSendProgress(int done, int total) {
    return '$done / $total sent';
  }

  @override
  String reportsSendPercent(int percent) {
    return '$percent%';
  }

  @override
  String get reportsQueueAllSent => 'Every report for this week has been sent';

  @override
  String get reportsSentColumn => 'Sent';

  @override
  String get reportsSentColumnEmpty => 'No reports sent yet';

  @override
  String get reportsSentSubtitle => 'View sent report';

  @override
  String get reportsOpenDraft => 'Open';

  @override
  String get reportsReasonUnknown => 'Loading figures';

  @override
  String reportsReasonCompletion(int percent) {
    return '$percent% complete';
  }

  @override
  String reportsReasonSessionDone(int count) {
    return 'PT $count done';
  }

  @override
  String reportsReasonSlump(int points) {
    return 'Down $points%p late';
  }

  @override
  String reportsReasonRising(int points) {
    return 'Up $points%p late';
  }

  @override
  String get reportsReasonFullLog => 'Logged all 7 days';

  @override
  String get reportsReasonOnboarding => 'New · settling in';

  @override
  String get reportsReasonSteady => 'On track';

  @override
  String reportsSentOn(String date) {
    return 'Sent $date';
  }

  @override
  String get reportsSentRead => 'Read';

  @override
  String get reportsSentUnread => 'Unread';

  @override
  String get reportsBackToWorkbench => 'This week\'s reports';

  @override
  String reportsSentHeadline(String name) {
    return 'Report sent to $name';
  }

  @override
  String reportsSentAt(String date, String time) {
    return 'Sent $date $time';
  }

  @override
  String get reportsSentRewrite => 'Rewrite from this';

  @override
  String get reportsHistoryButton => 'Past reports';

  @override
  String get reportsViewSent => 'View';

  @override
  String reportsHistoryTitle(String name) {
    return '$name\'s past reports';
  }

  @override
  String get reportsHistoryBack => 'Past reports';

  @override
  String get reportsHistoryUnsent => 'Not sent';

  @override
  String get reportsHistoryThisWeek => 'This week';

  @override
  String get reportsHistoryEmpty => 'No reports sent yet';

  @override
  String get reportsHistoryLoadFailed => 'Couldn\'t load past reports';

  @override
  String get reportsHistoryMore => 'Load more';

  @override
  String get reportsHistoryMoreFailed =>
      'Couldn\'t load more. Tap to try again.';

  @override
  String reportsHistorySendCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sent $count times',
      one: 'Sent once',
    );
    return '$_temp0';
  }

  @override
  String get reportsHistoryPdf => 'PDF';

  @override
  String get reportsResendTitle => 'Already sent';

  @override
  String reportsResendBody(String name, String date, String time) {
    return 'You already sent $name this report on $date at $time. Sending it again delivers a second copy to their chat.';
  }

  @override
  String get reportsResendConfirm => 'Send again';

  @override
  String get reportsSendHistoryFailed =>
      'Couldn\'t load send history. Members you\'ve already sent to may show as not sent.';

  @override
  String get reportsStepReview => 'Review';

  @override
  String get reportsStepWrite => 'Write';

  @override
  String get reportsStepSend => 'Send';

  @override
  String get reportsStepperLabel => 'Weekly report steps';

  @override
  String get reportsStepNext => 'Next';

  @override
  String get reportsStepPrev => 'Back';

  @override
  String get reportsPreviewTitle => 'What the member receives';

  @override
  String get reportsPreviewRecipient => 'To';

  @override
  String get reportsPreviewWeek => 'Week';

  @override
  String reportsPreviewDelivery(String name) {
    return 'Sent to $name\'s chat as a PDF file';
  }

  @override
  String get reportsPreviewEditHint =>
      'To change the text, tap Back to return to the Write step';

  @override
  String get reportsPreviewGenerating => 'Preparing the preview';

  @override
  String get reportsPreviewFailed => 'Couldn\'t prepare the preview';

  @override
  String reportsPreviewPage(int current, int total) {
    return 'Page $current of $total';
  }

  @override
  String get reportsPreviewPrevPage => 'Previous page';

  @override
  String get reportsPreviewNextPage => 'Next page';

  @override
  String get reportsPreviewZoomIn => 'Zoom in';

  @override
  String get reportsPreviewZoomOut => 'Zoom out';

  @override
  String get reportsGridPtSession => 'PT sessions';

  @override
  String reportsGridPtPerWeek(int count) {
    return '$count/week';
  }

  @override
  String get reportsGridPersonal => 'Personal workouts';

  @override
  String get reportsGridPersonalUnit => 'Done / assigned';

  @override
  String reportsGridDoneOfAssigned(int done, int total) {
    return '$done / $total';
  }

  @override
  String get reportsGridMeals => 'Meal logs';

  @override
  String get reportsGridMealsUnit => 'Times logged';

  @override
  String reportsGridMealCount(int count) {
    return '${count}x';
  }

  @override
  String get reportsGridCalories => 'Calories eaten';

  @override
  String reportsGridCalorieTarget(String value) {
    return 'Target $value';
  }

  @override
  String get reportsMacroNone =>
      'No meals logged yet, so macros can\'t be shown';

  @override
  String reportsMacroValueOfTarget(String name, int value, int target) {
    return '$name $value / ${target}g';
  }

  @override
  String reportsMacroNoValue(String name) {
    return '$name not logged';
  }

  @override
  String reportsMacroShortfall(String name) {
    return '$name is well under target — worth raising in your feedback';
  }

  @override
  String get reportsMemberFeedbackTitle => 'Member\'s weekly feedback';

  @override
  String get reportsMemberFeedbackAttention => 'Needs attention';

  @override
  String get reportsMemberFeedbackNone => 'Not received yet';

  @override
  String get reportsMemberFeedbackNoneHint =>
      'It shows up here once the member sends their weekly feedback';

  @override
  String get reportsMemberFeedbackConditionLabel => 'Condition';

  @override
  String get reportsMemberFeedbackIntensityLabel => 'Intensity';

  @override
  String get reportsMemberFeedbackPainLabel => 'Pain';

  @override
  String get reportsMemberFeedbackPainNone => 'None';

  @override
  String get reportsMemberFeedbackUnanswered => 'No answer';

  @override
  String get reportsMemberFeedbackNoteLabel => 'Note';

  @override
  String get reportsMemberFeedbackNoteNone => 'No note';

  @override
  String reportsMemberFeedbackPainOn(String area, String date) {
    return '$area ($date)';
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
  String get reportsMemberFeedbackConditionBad => 'Really rough';

  @override
  String get reportsMemberFeedbackIntensityTooEasy => 'Too easy';

  @override
  String get reportsMemberFeedbackIntensityRight => 'About right';

  @override
  String get reportsMemberFeedbackIntensityHard => 'Hard';

  @override
  String get reportsMemberFeedbackIntensityTooHard => 'Too hard';

  @override
  String get reportsTrendUnavailable =>
      'Couldn\'t load this week\'s workout records';

  @override
  String get reportsTrendNoGoal => 'No goal';

  @override
  String reportsTrendOfGoal(String value, String goal) {
    return '$value / $goal';
  }

  @override
  String get reportsTrendCompliance => 'Weekly completion';

  @override
  String get reportsTrendBurn => 'Weekly burn';

  @override
  String get reportsTrendStreak => 'Streak';

  @override
  String reportsTrendStreakDays(int days) {
    return '$days days';
  }

  @override
  String get reportsExerciseTrend => 'Workout trend';

  @override
  String get reportsWriteFromScratch => 'Write from scratch';

  @override
  String get reportsCardWeekTitle => 'This week';

  @override
  String get reportsCardWeekSubtitle =>
      'On one axis you can see the days that fell together';

  @override
  String get reportsAiSubtitle => 'Written automatically from the figures';

  @override
  String reportsMemberFeedbackMeta(String date) {
    return 'Weekly · submitted $date';
  }

  @override
  String reportsTrendSubtitle(int weeks) {
    return 'By type · last $weeks weeks';
  }

  @override
  String get reportsTrendCenterLabel => 'of goal';

  @override
  String reportsTrendWeeklyGoal(String goal) {
    return 'Weekly goal $goal';
  }

  @override
  String reportsTrendRunDown(int weeks) {
    return 'Down $weeks weeks running';
  }

  @override
  String reportsTrendRunUp(int weeks) {
    return 'Up $weeks weeks running';
  }

  @override
  String reportsTrendVsLastWeek(String delta) {
    return '$delta% vs last week';
  }

  @override
  String get reportsTrendFlat => 'About the same as last week';

  @override
  String get reportsTrendNoHistory => 'No earlier week to compare';

  @override
  String get reportsTrendRate => 'Weekly goal rate';

  @override
  String reportsTrendAverage(int weeks) {
    return '$weeks-week average';
  }

  @override
  String reportsTrendRateFalling(int weeks) {
    return 'Goal rate down $weeks weeks running';
  }

  @override
  String reportsTrendTracked(int count) {
    return '$count tracked exercises — picked automatically';
  }

  @override
  String reportsTrendTrackedTimes(int count) {
    return '$count×';
  }

  @override
  String get reportsSkipToWrite => 'Write without a draft';

  @override
  String reportsCalorieThisWeekAvg(String kcal) {
    return 'This week $kcal kcal/day';
  }

  @override
  String reportsCalorieBaselineAvg(int weeks, String kcal) {
    return 'Past $weeks weeks $kcal kcal/day';
  }

  @override
  String reportsGridCalorieTargetDefault(String kcal) {
    return 'Default $kcal';
  }

  @override
  String get summaryBasisDefault => 'default target';

  @override
  String get summaryBasisPersonal => 'personal target';

  @override
  String get summaryDirOver => 'above';

  @override
  String get summaryDirUnder => 'below';

  @override
  String summaryCompletionLow(String pct, String threshold) {
    return 'Avg workout completion $pct% · below the $threshold% bar';
  }

  @override
  String summaryCompletionTopic(String pct) {
    return 'workout completion at $pct%';
  }

  @override
  String summaryCompletionAvg(String pct) {
    return 'Avg workout completion $pct%';
  }

  @override
  String summarySkipped(String names) {
    return 'Skipped: $names';
  }

  @override
  String summarySkippedTopic(String count) {
    return '$count skipped exercise(s)';
  }

  @override
  String summarySodium(String avg, String basis, String target, String days) {
    return 'Avg sodium ${avg}mg · over the $basis of ${target}mg on $days day(s)';
  }

  @override
  String summarySodiumOverTopic(String days) {
    return 'sodium over target on $days day(s)';
  }

  @override
  String summarySodiumAvgTopic(String avg) {
    return 'avg sodium ${avg}mg';
  }

  @override
  String summarySugar(String avg, String basis, String target, String days) {
    return 'Avg sugar ${avg}g · over the $basis of ${target}g on $days day(s)';
  }

  @override
  String summarySugarOverTopic(String days) {
    return 'sugar over target on $days day(s)';
  }

  @override
  String summarySugarAvgTopic(String avg) {
    return 'avg sugar ${avg}g';
  }

  @override
  String summaryCalories(
    String avg,
    String basis,
    String target,
    String direction,
    String pct,
  ) {
    return 'Avg calories ${avg}kcal · $pct% $direction the $basis of ${target}kcal';
  }

  @override
  String summaryCaloriesTopic(String direction) {
    return 'calories $direction target';
  }

  @override
  String summaryCaloriesAvg(String avg) {
    return 'Avg calories ${avg}kcal';
  }

  @override
  String summaryMacro(
    String label,
    String avg,
    String target,
    String direction,
    String pct,
  ) {
    return 'Avg $label ${avg}g · $pct% $direction the personal target of ${target}g';
  }

  @override
  String summaryMacroTopic(String label, String direction) {
    return '$label $direction target';
  }

  @override
  String summaryMorePoints(String count) {
    return '$count more — see the report';
  }

  @override
  String summaryHeadlineNoData(String name) {
    return '$name has no records for the week — plan next week\'s start together.';
  }

  @override
  String summaryHeadlineSteady(String name) {
    return '$name stayed within target — the current intensity can stay as is.';
  }

  @override
  String summaryHeadlineRest(String count) {
    return ' Also look at $count more.';
  }

  @override
  String summaryHeadlineGoodCare(
    String name,
    String kept,
    String top,
    String rest,
  ) {
    return '$name kept $kept on track; next week, let\'s also work on $top.$rest';
  }

  @override
  String summaryHeadlineNeedsAdjust(String name, String top, String rest) {
    return '$name was off target on $top — next week needs adjusting.$rest';
  }

  @override
  String get reportsPdfFileSuffix => 'weekly_report';

  @override
  String get clientDietAnalysisTitle => 'Diet analysis';

  @override
  String get clientDietAnalysisTodayEmpty => 'No meals logged today yet.';

  @override
  String clientDietAnalysisTodayOver(
    String slot,
    String food,
    String foodValue,
    String nutrient,
    String value,
    String target,
    String ratio,
  ) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': 'breakfast',
      'lunch': 'lunch',
      'dinner': 'dinner',
      'lateNight': 'late-night snack',
      'other': 'snack',
    });
    String _temp1 = intl.Intl.selectLogic(nutrient, {
      'sodium': 'sodium',
      'sugar': 'sugar',
      'other': 'calories',
    });
    return '$food at $_temp0 ($foodValue) pushed today\'s $_temp1 to $value, ${ratio}x the $target goal.';
  }

  @override
  String clientDietAnalysisTodayOverMeal(
    String slot,
    String foodValue,
    String nutrient,
    String value,
    String target,
    String ratio,
  ) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': 'Breakfast',
      'lunch': 'Lunch',
      'dinner': 'Dinner',
      'lateNight': 'Late-night snack',
      'other': 'Snack',
    });
    String _temp1 = intl.Intl.selectLogic(nutrient, {
      'sodium': 'sodium',
      'sugar': 'sugar',
      'other': 'calories',
    });
    return '$_temp0 ($foodValue) pushed today\'s $_temp1 to $value, ${ratio}x the $target goal.';
  }

  @override
  String clientDietAnalysisTodayProteinShort(String value, String gap) {
    return 'Protein is at $value, $gap short of the goal.';
  }

  @override
  String clientDietAnalysisTodayProteinChronic(
    String value,
    String gap,
    String avg,
  ) {
    return 'Protein is at $value, $gap short of the goal, and the 4-week average of $avg a day stays low.';
  }

  @override
  String clientDietAnalysisTodayMissing(String slot) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': 'breakfast',
      'lunch': 'lunch',
      'dinner': 'dinner',
      'lateNight': 'late-night snack',
      'other': 'snack',
    });
    return 'No $_temp0 logged yet.';
  }

  @override
  String clientDietAnalysisTodayGood(String kcal) {
    return '$kcal today, evenly within the goals.';
  }

  @override
  String get clientDietAnalysisWeekEmpty => 'No meals logged this week yet.';

  @override
  String clientDietAnalysisWeekSkipBreakfast(
    String scope,
    int logged,
    int days,
  ) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': 'last week',
      'other': 'this week',
    });
    return 'Skipped breakfast on $days of $logged logged days $_temp0.';
  }

  @override
  String clientDietAnalysisWeekSkipBreakfastSnack(
    String scope,
    int logged,
    int days,
    int snackDays,
  ) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': 'last week',
      'other': 'this week',
    });
    return 'Skipped breakfast on $days of $logged logged days $_temp0, snacking instead on $snackDays.';
  }

  @override
  String clientDietAnalysisWeekOver(
    String scope,
    int logged,
    int days,
    String nutrient,
  ) {
    String _temp0 = intl.Intl.selectLogic(nutrient, {
      'sodium': 'Sodium',
      'sugar': 'Sugar',
      'other': 'Calories',
    });
    String _temp1 = intl.Intl.selectLogic(scope, {
      'last': 'last week',
      'other': 'this week',
    });
    return '$_temp0 went over the goal on $days of $logged logged days $_temp1.';
  }

  @override
  String clientDietAnalysisWeekCause(
    String weekday,
    String slot,
    String food,
    String foodValue,
  ) {
    String _temp0 = intl.Intl.selectLogic(weekday, {
      '0': 'Monday',
      '1': 'Tuesday',
      '2': 'Wednesday',
      '3': 'Thursday',
      '4': 'Friday',
      '5': 'Saturday',
      'other': 'Sunday',
    });
    String _temp1 = intl.Intl.selectLogic(slot, {
      'breakfast': 'breakfast',
      'lunch': 'lunch',
      'dinner': 'dinner',
      'lateNight': 'late-night snack',
      'other': 'snack',
    });
    return 'The biggest was $food at $_temp0 $_temp1 ($foodValue).';
  }

  @override
  String clientDietAnalysisWeekProteinShort(
    String scope,
    int logged,
    int days,
  ) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': 'last week',
      'other': 'this week',
    });
    return 'Protein fell below 80% of the goal on $days of $logged logged days $_temp0.';
  }

  @override
  String clientDietAnalysisWeekGood(String scope, int days) {
    String _temp0 = intl.Intl.selectLogic(scope, {
      'last': 'last week',
      'other': 'this week',
    });
    return 'All $days logged days $_temp0 stayed within the goals.';
  }

  @override
  String clientDietAnalysisAllFew(int days) {
    return 'Only $days days logged in the last 4 weeks. The trend shows after 7.';
  }

  @override
  String clientDietAnalysisAllSlotSodium(String slot, int days) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': 'breakfast',
      'lunch': 'lunch',
      'dinner': 'dinner',
      'lateNight': 'late-night snack',
      'other': 'snack',
    });
    return 'In the last 4 weeks, $_temp0 sodium went over half the goal $days times.';
  }

  @override
  String clientDietAnalysisAllCarbHeavy(int pct) {
    return 'Carbs made up $pct% of calories in the last 4 weeks.';
  }

  @override
  String clientDietAnalysisAllProteinLight(int pct) {
    return 'Protein made up only $pct% of calories in the last 4 weeks.';
  }

  @override
  String clientDietAnalysisAllProteinTrendUp(int before, int after) {
    return 'Days meeting the protein goal rose from $before to $after over the last 2 weeks.';
  }

  @override
  String clientDietAnalysisAllProteinTrendDown(int before, int after) {
    return 'Days meeting the protein goal fell from $before to $after over the last 2 weeks.';
  }

  @override
  String clientDietAnalysisAllFrequent(String slot, String food, int count) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': 'breakfast',
      'lunch': 'lunch',
      'dinner': 'dinner',
      'lateNight': 'late-night snack',
      'other': 'snack',
    });
    return '$food was the most common $_temp0 in the last 4 weeks ($count times).';
  }

  @override
  String clientDietAnalysisAllRepeated(String food1, String food2) {
    return '$food1 and $food2 make up much of the last 4 weeks\' log.';
  }

  @override
  String clientDietAnalysisAllGood(int days) {
    return '$days days logged in the last 4 weeks, with an even trend.';
  }

  @override
  String clientDietAnalysisFoodsOne(String food1, int count1) {
    return 'Mostly $food1 ($count1 times).';
  }

  @override
  String clientDietAnalysisFoodsTwo(
    String food1,
    int count1,
    String food2,
    int count2,
  ) {
    return 'Mostly $food1 ($count1 times) and $food2 ($count2 times).';
  }

  @override
  String clientDietRecQuestion(String slot) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': 'for breakfast',
      'lunch': 'for lunch',
      'dinner': 'for dinner',
      'lateNight': 'as a late-night snack',
      'other': 'as a snack',
    });
    return 'Recommend this $_temp0 to the member?';
  }

  @override
  String get clientDietRecQuestionNext =>
      'Recommend this for the next meal to the member?';

  @override
  String clientDietRecCounter(int index, int total) {
    return 'AI pick $index / $total';
  }

  @override
  String get clientDietRecNo => 'No';

  @override
  String get clientDietRecYes => 'Yes, recommend';

  @override
  String clientDietRecExhausted(int count) {
    return 'You passed on all $count AI picks.';
  }

  @override
  String get clientDietRecRestart => 'Start over';

  @override
  String get clientDietRecMore => 'See other menus';

  @override
  String clientDietRecActive(String date) {
    return 'You recommended this on $date. It\'s on the member\'s home as a trainer pick.';
  }

  @override
  String get clientDietRecChange => 'Change';

  @override
  String clientDietRecResolved(String name, String date, String slot) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': 'breakfast',
      'lunch': 'lunch',
      'dinner': 'dinner',
      'lateNight': 'late-night snack',
      'other': 'snack',
    });
    return 'The member had the recommended $name for $_temp0 on $date.';
  }

  @override
  String clientDietRecResolvedNoSlot(String name, String date) {
    return 'The member had the recommended $name on $date.';
  }

  @override
  String get clientDietRecNext => 'See next pick';

  @override
  String get clientDietRecConfirmFailed =>
      'Couldn\'t save the pick. Please try again.';

  @override
  String clientDietRecNutrition(String kcal, String protein, String sodium) {
    return '${kcal}kcal · protein ${protein}g · sodium ${sodium}mg';
  }

  @override
  String clientDietRecSlot(String slot) {
    String _temp0 = intl.Intl.selectLogic(slot, {
      'breakfast': 'Breakfast',
      'lunch': 'Lunch',
      'dinner': 'Dinner',
      'lateNight': 'Late-night snack',
      'other': 'Snack',
    });
    return '$_temp0';
  }
}
