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
  String get schedCancel => 'Cancel session';

  @override
  String get schedNoShow => 'Mark no-show';

  @override
  String get schedCancelTitle => 'Cancel this PT?';

  @override
  String schedCancelConfirm(String time, String name) {
    return 'The $time session with $name will be recorded as cancelled. The entry stays.';
  }

  @override
  String get schedCancelSource => 'Cancelled by';

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
  String get actionRefresh => 'Refresh';

  @override
  String get actionChange => 'Change';

  @override
  String get actionBack => 'Back';

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
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authNoAccount => 'Don\'t have an account?';

  @override
  String get authSignUp => 'Sign up';

  @override
  String get authBrowseDemo => 'Explore the demo without signing in';

  @override
  String get authOr => 'or';

  @override
  String get authContinueKakao => 'Continue with Kakao';

  @override
  String get authContinueGoogle => 'Continue with Google';

  @override
  String get authSignUpSubtitle =>
      'Create an On-Care account and start managing members';

  @override
  String get authName => 'Name';

  @override
  String get authPasswordHint => 'Password (8+ characters)';

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
  String get authErrSocialFailed =>
      'Social sign-in failed. Please try again in a moment.';

  @override
  String get authErrSignInFailed =>
      'Sign-in failed. Please try again in a moment.';

  @override
  String get authErrPasswordTooShort =>
      'Password must be at least 8 characters';

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
  String get dashCheckSodiumCompletion => 'Check diet & completion';

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
      'Low completion / churn risk detected';

  @override
  String dashActivityDifficultyDesc(String names) {
    return '$names have low workout completion or a churn-risk signal (including negative feedback). Lower the difficulty before the next session and check whether recent feedback was negative.';
  }

  @override
  String get dashActivityInactiveTitle => 'Inactive 7+ days';

  @override
  String dashActivityInactiveDesc(String names) {
    return '$names haven\'t logged a workout in the last 7 days. Reach out before it turns into churn.';
  }

  @override
  String get dashActivityDietFeedbackTitle => 'Diet feedback pending';

  @override
  String dashActivityDietFeedbackDesc(String names) {
    return '$names have a diet warning (sodium/sugar over target) but haven\'t gotten trainer feedback in 7 days. Leave a comment so they know it was seen.';
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
  String dashAiAllOnTrack(int total) {
    return 'All $total members are within target. Hold this intensity and raise next week\'s goal.';
  }

  @override
  String get dashAiLoading =>
      'Reviewing diet, workouts, and recent conversations…';

  @override
  String get dashAiLoadFailed =>
      'Couldn\'t load the detailed coaching summary.';

  @override
  String get dashAiRateLimited =>
      'There are too many summary requests. Try again shortly.';

  @override
  String get dashAiStatus => 'Current status';

  @override
  String get dashAiExerciseFocus => 'Today\'s exercise focus';

  @override
  String get dashAiEvidence => 'Evidence';

  @override
  String get dashAiCaution => 'Check before session';

  @override
  String get dashAiPriorityHigh => 'Check first';

  @override
  String get dashAiPriorityMedium => 'Monitor';

  @override
  String get dashAiPriorityLow => 'Maintain';

  @override
  String dashAiRuleHeadline(String name) {
    return 'Check $name first and adjust training load to the diet and condition signals.';
  }

  @override
  String get dashAiRuleKneeStatus =>
      'A recent message indicates knee or lower-body discomfort, so lower-body load should be adjusted.';

  @override
  String get dashAiRuleKneeFocus =>
      'Reduce heavy squats and lunges; focus on glute activation, knee mobility, and level walking.';

  @override
  String get dashAiRuleKneeCaution =>
      'Confirm the pain location and range of motion before the session.';

  @override
  String get dashAiRuleUpperStatus =>
      'Shoulder or neck discomfort indicates that upper-body pushing and pulling intensity should be adjusted.';

  @override
  String get dashAiRuleUpperFocus =>
      'Reduce heavy upper-body work; focus on thoracic mobility, scapular stability, and stretching.';

  @override
  String get dashAiRuleUpperCaution =>
      'Check which arm elevation angles feel uncomfortable.';

  @override
  String get dashAiRuleFatigueStatus =>
      'Overtime or fatigue is making exercise harder to sustain, so a manageable intensity comes first.';

  @override
  String get dashAiRuleFatigueFocus =>
      'Reduce high-intensity full-body work and focus on 15–20 minutes of easy cardio and recovery stretching.';

  @override
  String get dashAiRuleFatigueCaution =>
      'Confirm sleep and current fatigue before setting the intensity.';

  @override
  String get dashAiRuleSodiumStatus =>
      'Today\'s sodium intake is over the target, so set intensity with the current condition in mind.';

  @override
  String get dashAiRuleSodiumFocus =>
      'Prefer moderate walking or cycling and steady full-body strength volume over high-intensity intervals.';

  @override
  String get dashAiRuleSodiumCaution =>
      'Check hydration, dizziness, and swelling.';

  @override
  String get dashAiRuleCompletionStatus =>
      'Weekly workout adherence is low, so review exercise volume, difficulty, and goals.';

  @override
  String get dashAiRuleCompletionFocus =>
      'Reduce exercise count and volume, start at a manageable difficulty, and rebuild the weekly goal gradually.';

  @override
  String get dashAiRuleCompletionCaution =>
      'Check which schedule or condition issues disrupted exercise this week.';

  @override
  String get dashAiRuleUnansweredStatus =>
      'There is an unread message, so confirm the member\'s current condition before today\'s workout.';

  @override
  String get dashAiRuleUnansweredFocus =>
      'Hold off on increasing load until they reply, and begin with mobility work at the existing intensity.';

  @override
  String get dashAiRuleUnansweredCaution =>
      'Confirm pain, fatigue, and sleep before choosing today\'s body area and intensity.';

  @override
  String dashAiRuleEvidenceMessage(String message) {
    return 'Recent message: “$message”';
  }

  @override
  String dashAiRuleEvidenceSodium(int value, int target) {
    return 'Sodium today: ${value}mg / target: ${target}mg';
  }

  @override
  String dashAiRuleEvidenceCompletion(int average) {
    return 'Average completion on recorded days this week: $average%';
  }

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
  String clientsCountSummary(int total, int active) {
    return '$total members · $active active';
  }

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
  String get clientsSortActiveFirst => 'Active members first';

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
  String clientsFilterSummary(String filter, int shown, int total) {
    return '$filter · $shown/$total';
  }

  @override
  String get clientsSeeAll => 'See all';

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
  String get memberHealthConditions => 'Conditions and cautions';

  @override
  String get memberHealthGoals => 'Member goals';

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
  String get clientConnectCodeLabel => 'Member sync code';

  @override
  String get clientConnectCodeRequired => 'Enter all six digits';

  @override
  String get clientConnectCodeInvalid =>
      'That code is wrong or expired. Ask the member for a new one';

  @override
  String get clientInviteMemberIdLabel => 'Member ID';

  @override
  String get clientInviteLookupAction => 'Find';

  @override
  String get clientInviteMessageLabel => 'Message (optional)';

  @override
  String get clientInviteSendAction => 'Send request';

  @override
  String get clientInviteConnectAction => 'Register member';

  @override
  String clientInviteSent(String name) {
    return 'Sent a coaching request to $name';
  }

  @override
  String clientInviteConnected(String name) {
    return 'Registered $name as a member';
  }

  @override
  String get clientInviteNotFound => 'No member uses that member ID';

  @override
  String get clientInviteFailed =>
      'Couldn\'t send the request. Please try again';

  @override
  String get clientInviteMemberIdRequired => 'Enter a member ID';

  @override
  String get clientInviteAlreadyCoached => 'You already coach this member';

  @override
  String get clientInviteHasTrainer =>
      'Another trainer already coaches this member';

  @override
  String get clientInvitePendingHint =>
      'A request you sent is still waiting for an answer';

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
  String get clientStatusChangeFailed =>
      'Couldn\'t change the status. Please try again.';

  @override
  String get clientClosePanel => 'Close panel';

  @override
  String get clientChat => 'Chat';

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
  String get consultRejectAction => 'Decline';

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
  String clientFeedbackOn(String name) {
    return 'Member feedback on $name';
  }

  @override
  String get clientFeedbackPersonal =>
      'Member feedback on this personal exercise';

  @override
  String get clientFeedbackSession => 'Member feedback on this session';

  @override
  String get workoutKindAiPersonal => 'AI personal exercise';

  @override
  String get trainerNote => 'Trainer\'s note';

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
  String dietSodiumValue(int value) {
    return 'Sodium ${value}mg';
  }

  @override
  String get aiAnalysis => 'AI analysis';

  @override
  String get aiPeriodAnalysis => 'AI period analysis';

  @override
  String get aiAllAnalysis => 'AI all-time analysis';

  @override
  String dietAiOverSodium(int over) {
    return 'Sodium is ${over}mg over target. Adding cardio to today\'s program would help.';
  }

  @override
  String get dietAiBalanced =>
      'Today\'s meals are well balanced. Keep the current program.';

  @override
  String get consultStatusRejected => 'Declined';

  @override
  String get dateToday => 'Today';

  @override
  String get dateTomorrow => 'Tomorrow';

  @override
  String get dateYesterday => 'Yesterday';

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
    return 'Week $week, $month/';
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
  String exSetsValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sets',
      one: '1 set',
    );
    return '$_temp0';
  }

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
  String get clientWeeklyRoutineAdherence => 'Weekly adherence';

  @override
  String get clientRoutineAdherenceUnmeasured => 'Not measured';

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
  String get reportsSendStateSent => 'Sent';

  @override
  String get reportsSendStateSending => 'Sending…';

  @override
  String get reportsShare => 'Share';

  @override
  String reportsShareSendTo(String name) {
    return 'Send to $name';
  }

  @override
  String get reportsShareNeedsFeedback => 'Write feedback first to send it.';

  @override
  String get reportsShareNoClient => 'Pick a member to see their report first.';

  @override
  String reportBodyGreeting(String name, String range) {
    return '$name, here\'s your weekly report for $range.';
  }

  @override
  String reportBodyCompletionGood(int avg) {
    return 'You kept up well — $avg% of your workouts done.';
  }

  @override
  String reportBodyCompletionLow(int avg) {
    return 'Workout completion came in at $avg%. Sounds like a busy one.';
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
  String reportBodyCalories(String avg) {
    return 'Calories averaged ${avg}kcal a day.';
  }

  @override
  String get reportBodyPraise =>
      'Great work — let\'s keep this pace next week!';

  @override
  String get reportBodyEncourage =>
      'Let\'s focus on just that one thing next week. I\'ll adjust your program and send it over.';

  @override
  String get reportBodyNoRecords =>
      'There\'s nothing logged for this week, so nothing to sum up. Let\'s plan next week\'s start together.';

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
    return '$sets sets';
  }

  @override
  String progRepsValue(int reps) {
    return '$reps reps';
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
  String schedSentProgramTo(String name, String date) {
    return 'Sent $name the PT program for $date';
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
  String slotIntro(String date) {
    return 'Open times for members to book on $date.';
  }

  @override
  String get slotOpenAction => 'Open';

  @override
  String get slotReload => 'Reload';

  @override
  String get slotEmpty => 'No booking slots open on this day.';

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
  String get myMonthStats => 'This month';

  @override
  String get myGym => 'My gym';

  @override
  String get myNotifications => 'Notifications';

  @override
  String get myNotifNewMessage => 'New message alerts';

  @override
  String get myNotifNewMessageHint =>
      'A sidebar badge appears when a member messages you';

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
  String get myLegalTermsTitle => 'Terms of Service';

  @override
  String get myLegalTermsHint => 'The terms your trainer account runs under';

  @override
  String get myLegalPrivacyTitle => 'Privacy Policy';

  @override
  String get myLegalPrivacyHint =>
      'How member records and sent reports are handled';

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
  String get myContact => 'Contact';

  @override
  String get myPasswordChanged => 'Password changed';

  @override
  String myCareerYears(String career) {
    return '$career experience';
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
  String get myGymOpen => 'Open now';

  @override
  String get myGymListFailed => 'Couldn\'t load the gym list.';

  @override
  String get myNoGym => 'No gym';

  @override
  String get mySignOut => 'Sign out';

  @override
  String get myPwCurrentRequired => 'Enter your current password';

  @override
  String myPwTooShort(int min) {
    return 'The new password must be at least $min characters';
  }

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
    return 'New password ($min+ characters)';
  }

  @override
  String get myPwConfirm => 'Confirm new password';

  @override
  String get myPwChanging => 'Changing…';

  @override
  String get myPwChangeAction => 'Change';

  @override
  String get mySettingsSaveFailed =>
      'Couldn\'t save your settings. Please try again in a moment';

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
  String get reportsThisWeek => 'This week';

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
  String get coachReviewed => 'AI-generated, reviewed by you';

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
  String get aiAnalysedData =>
      'Reviewed the workout goal, recent activity, and today\'s nutrition';

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
    return 'Reviewed · AI suggestion ($option)';
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
  String get aiStepDone => 'Final review';

  @override
  String get aiStepperLabel => 'Custom suggestion progress';

  @override
  String coachTemplateSummaryWithGoal(String goal, int count, int minutes) {
    return '$goal · $count exercises · $minutes min';
  }

  @override
  String get aiInsightMemoTitle => 'AI insights (last 7 days)';

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
  String get goalStrength => 'Strength';

  @override
  String get goalFitness => 'Fitness';

  @override
  String get goalPosture => 'Posture';

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
  String get alertSodiumOver => 'Sodium over';

  @override
  String get alertSugarOver => 'Sugar over target';

  @override
  String get alertLowCompletion => 'Low completion';

  @override
  String get alertAwaitingReply => 'Awaiting reply';

  @override
  String get clientLastRoutine => 'Last program';

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
  String get myDeleteHint => 'Your member links and bookings go with it';

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
  String get routineAlreadyGone => 'That program is already gone';

  @override
  String get workoutPendingTitle => 'Not done yet';

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
  String get routineFeedbackTitle => 'Workout feedback';

  @override
  String get routineFeedbackHint => 'Write coaching feedback for the member';

  @override
  String get routineFeedbackWrite => 'Write feedback';

  @override
  String get routineFeedbackEdit => 'Edit feedback';

  @override
  String get routineFeedbackSaved => 'Feedback saved';

  @override
  String get routineFeedbackFailed =>
      'Could not save feedback. Please try again';

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
  String get dashTaskProgressToday => 'Done today';

  @override
  String get dashTaskProgressCarriedOver => 'Done (carried over)';

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
  String dashTodoSodiumSubtitle(int sodiumMg, int targetMg) {
    return 'Sodium ${sodiumMg}mg · target ${targetMg}mg';
  }

  @override
  String dashTodoSugarSubtitle(int sugarG, int targetG) {
    return 'Sugar ${sugarG}g · target ${targetG}g';
  }

  @override
  String get dashTodoCompletionSubtitle =>
      'Low completion · check recent records';

  @override
  String get dashTodoCarriedOverDemoSubtitle =>
      'Diet feedback left over from yesterday';

  @override
  String get dashTodoProgramSubtitle => 'No recent program sent';

  @override
  String get dashTodoReportSubtitle => 'This week\'s report is due';

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
  String get churnNoRecentWorkout => 'No workout logged in 7 days';

  @override
  String get churnNoRecentFeedback => 'No trainer feedback in 7 days';

  @override
  String get churnConsecutiveCancel => '2 consecutive cancellations/no-shows';

  @override
  String get churnDietStopped => 'Diet logging stopped';

  @override
  String get churnGoalStagnant => 'Goal metric stagnant long-term';

  @override
  String get churnUnresolvedRequest => 'Unanswered message';

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
  String get clientHealthGoals => 'Body profile & goals';

  @override
  String get clientProfileSectionTitle => 'Body, goals & memo';

  @override
  String get clientTrainerMemo => 'Memo';

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
  String get suggestionReviewTitle => 'AI personal exercises';

  @override
  String suggestionReviewBadge(int count) {
    return '$count to review';
  }

  @override
  String suggestionReviewIntro(String name) {
    return 'Prepared for $name from recent PT feedback and exercise records. The member sees only what you recommend.';
  }

  @override
  String get suggestionReviewEmpty =>
      'No AI personal exercises are waiting for review.';

  @override
  String get suggestionReviewLoadFailed => 'Couldn\'t load the AI suggestions.';

  @override
  String get suggestionApprove => 'Recommend to member';

  @override
  String get suggestionConfirmTitle => 'Final review · recommend to member';

  @override
  String suggestionConfirmBody(String client) {
    return 'Exactly what you see below is what $client receives. Once recommended it shows up in their app.';
  }

  @override
  String get suggestionDismiss => 'Don\'t recommend';

  @override
  String suggestionApproved(String name, String client) {
    return 'Recommended $name to $client.';
  }

  @override
  String suggestionDismissed(String name) {
    return '$name won\'t be recommended.';
  }

  @override
  String get suggestionActionFailed =>
      'Couldn\'t finish that. Please try again.';

  @override
  String get suggestionAlreadyReviewed =>
      'This suggestion was already reviewed. The list has been refreshed.';

  @override
  String get suggestionEditTitle => 'Edit personal exercise';

  @override
  String get suggestionEditSubmit => 'Edit and recommend';

  @override
  String get suggestionEditName => 'Exercise';

  @override
  String get suggestionEditMemo => 'Note for the member';

  @override
  String get suggestionEditMemoHint => 'Stop if your right shoulder hurts.';

  @override
  String get programDraftSaved => 'Program saved.';

  @override
  String get programDraftSaveFailed =>
      'Couldn\'t save the program. Please try again.';

  @override
  String programDraftLoaded(String name) {
    return 'Opened $name in the editor.';
  }

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
  String get programEditorAssignUnsupported =>
      'Check each exercise\'s name and set count.';

  @override
  String get programAssignConfirmTitle => 'Add to the schedule?';

  @override
  String programAssignConfirmBody(String name, String date, String time) {
    return 'This program will be added to $name\'s PT schedule on $date at $time.';
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
  String programEditorSessionName(String letter) {
    return 'Session $letter';
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
  String get programEditorRest => 'Rest sec';

  @override
  String get programEditorExerciseMemo => 'Memo';

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
  String get reportsFeedbackRestore => 'Restore draft';

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
  String get reportsAiTitle => 'AI coaching assistant · Report summary';

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
  String get reportsPdfLabel => 'Export PDF';

  @override
  String get reportsPdfGenerating => 'Generating PDF…';

  @override
  String get reportsPdfGenerationFailed =>
      'Couldn\'t generate the PDF. Please try again.';

  @override
  String reportsPdfReady(String name) {
    return '$name\'s weekly report is ready.';
  }

  @override
  String get reportsPdfSending => 'Sending…';

  @override
  String get reportsPdfSendToClient => 'Send to member';

  @override
  String get reportsPdfSave => 'Save PDF';

  @override
  String get reportsPdfPrint => 'Print';

  @override
  String get reportsPdfClose => 'Close';

  @override
  String get reportsPdfActionFailed =>
      'Couldn\'t complete the action. Please try again.';

  @override
  String reportsPdfSent(String name) {
    return 'Sent the PDF to $name.';
  }

  @override
  String get reportsPdfSaveStarted => 'Started saving the PDF.';

  @override
  String get reportsPdfPrintOpened => 'Opened the print dialog.';

  @override
  String get reportsPdfMessage => 'Here\'s your weekly report.';

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
}
