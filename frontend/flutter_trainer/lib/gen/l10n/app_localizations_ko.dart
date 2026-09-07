// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'On-Care 트레이너';

  @override
  String get scheduleStatusUpcoming => '예정';

  @override
  String get scheduleStatusDone => '완료';

  @override
  String get scheduleStatusCancelled => '취소';

  @override
  String get scheduleStatusNoShow => '노쇼';

  @override
  String get schedCancel => '취소 처리';

  @override
  String get schedNoShow => '노쇼 처리';

  @override
  String get schedCancelTitle => '이 PT를 취소할까요?';

  @override
  String schedCancelConfirm(String time, String name) {
    return '$time $name 님 PT가 취소로 기록됩니다. 일정은 지워지지 않아요.';
  }

  @override
  String get schedCancelSource => '취소한 쪽';

  @override
  String get schedCancelByMember => '회원 취소';

  @override
  String get schedCancelByTrainer => '트레이너 취소';

  @override
  String get schedCancelByOther => '기타';

  @override
  String get schedCancelReasonHint => '사유 (선택, 트레이너만 봅니다)';

  @override
  String get schedCancelFailed => '취소 처리하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get schedNoShowTitle => '노쇼로 기록할까요?';

  @override
  String schedNoShowConfirm(String time, String name) {
    return '$time $name 님이 오지 않은 것으로 기록됩니다.';
  }

  @override
  String get schedNoShowFailed => '노쇼 처리하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String schedCancelledBy(String source, String date) {
    return '$source · $date';
  }

  @override
  String get schedDeleteMeansRemove => '기록이 지워집니다. 진행되지 않은 PT는 취소·노쇼로 남기세요.';

  @override
  String get schedDeleteMeansRemoveFinished =>
      '기록이 지워집니다. 이미 완료한 일정이라 되돌릴 수 없어요.';

  @override
  String get scheduleStatusGap => '공백';

  @override
  String get sessionTypePersonalTraining => '1:1 PT';

  @override
  String get sessionTypeConsultation => '상담';

  @override
  String get navDashboard => '대시보드';

  @override
  String get navClients => '회원';

  @override
  String get navSchedule => '스케줄';

  @override
  String get navCoaching => '프로그램';

  @override
  String get navReports => '리포트';

  @override
  String get navConsultations => '상담 요청';

  @override
  String get actionSave => '저장';

  @override
  String get actionSaved => '저장됨';

  @override
  String get actionCancel => '취소';

  @override
  String get actionEdit => '수정';

  @override
  String get actionDelete => '삭제';

  @override
  String get actionClose => '닫기';

  @override
  String get actionRetry => '다시 시도';

  @override
  String get actionRefresh => '새로고침';

  @override
  String get actionChange => '변경';

  @override
  String get actionBack => '뒤로';

  @override
  String get appWordmarkTrainer => '트레이너';

  @override
  String get appAvatarFallback => '트';

  @override
  String sidebarMyTooltip(String name) {
    return '$name · 내 정보';
  }

  @override
  String get authTagline => '회원 관리를 위한 트레이너 전용 앱';

  @override
  String get authEmail => '이메일';

  @override
  String get authPassword => '비밀번호';

  @override
  String get authSignIn => '로그인';

  @override
  String get authNoAccount => '계정이 없으신가요?';

  @override
  String get authSignUp => '계정 만들기';

  @override
  String get authBrowseDemo => '로그인 없이 데모 둘러보기';

  @override
  String get authOr => '또는';

  @override
  String get authContinueKakao => '카카오로 시작하기';

  @override
  String get authContinueGoogle => '구글로 시작하기';

  @override
  String get authSignUpSubtitle => 'On-Care 계정을 만들어 회원 관리를 시작하세요';

  @override
  String get authName => '이름';

  @override
  String get authPasswordHint => '비밀번호 (8자 이상)';

  @override
  String get authPasswordConfirm => '비밀번호 확인';

  @override
  String get authInviteCode => '헬스장 초대 코드';

  @override
  String get authInviteCodeHelp => '소속 헬스장에서 발급받은 코드를 입력해 주세요.';

  @override
  String get authLegalNotice => '가입하면 아래 문서에 동의하는 것으로 봅니다';

  @override
  String get authSignUpAndStart => '가입하고 시작하기';

  @override
  String get authHasAccount => '이미 계정이 있으신가요?';

  @override
  String get authErrEmptyCredentials => '이메일과 비밀번호를 입력해 주세요';

  @override
  String get authErrSocialFailed => '소셜 로그인에 실패했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get authErrSignInFailed => '로그인에 실패했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get authErrPasswordTooShort => '비밀번호는 8자 이상이어야 해요';

  @override
  String get authErrPasswordMismatch => '비밀번호가 일치하지 않아요';

  @override
  String get authErrInviteCodeRequired => '헬스장에서 받은 초대 코드를 입력해 주세요';

  @override
  String get authErrSignUpFailed => '가입에 실패했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get dashTitle => '대시보드';

  @override
  String get dashActivityRecommendRoutine => '프로그램 구성을 조정해보세요.';

  @override
  String get dashActivityRecommendChat => '메시지에서 안부를 물어보세요.';

  @override
  String get dashActivityRecommendDiet => '식단에서 피드백을 남겨보세요.';

  @override
  String get dashActivityTabProgram => '프로그램';

  @override
  String get dashActivityTabChat => '메시지';

  @override
  String get dashActivityTabDiet => '식단';

  @override
  String get dashActivityTabClient => '회원';

  @override
  String get dashLoadFailed => '대시보드를 불러오지 못했어요';

  @override
  String get dashTodayReservations => '오늘 예약';

  @override
  String get dashUnitCount => '건';

  @override
  String get dashUnitPeople => '명';

  @override
  String get dashSeeInSchedule => '스케줄에서 보기';

  @override
  String get dashMyClients => '담당 회원';

  @override
  String dashDormantClients(int count) {
    return '휴면 $count명';
  }

  @override
  String get dashAllActive => '전원 활성';

  @override
  String get dashNeedsReply => '답장 필요';

  @override
  String dashWaitingClients(int count) {
    return '회원 $count명 대기 중';
  }

  @override
  String get dashAllReplied => '모두 답장했어요';

  @override
  String get dashAttentionClients => '주의 회원';

  @override
  String get dashNoIssues => '이상 없음';

  @override
  String get dashCheckSodiumCompletion => '식단·이행률 확인';

  @override
  String get dashMessages => '메시지';

  @override
  String get dashChurnRisk => '이탈 위험';

  @override
  String get dashChurnRiskNone => '이탈 위험 없음';

  @override
  String get dashChurnRiskCheck => '이탈 신호 확인';

  @override
  String get dashChurnRiskTitle => '이탈 위험 회원';

  @override
  String get dashChurnRiskEmpty => '지금은 이탈 위험 신호가 없어요.';

  @override
  String get dashActivityDifficultyTitle => '이행률 저조·이탈 위험 감지';

  @override
  String dashActivityDifficultyDesc(String names) {
    return '$names 회원이 개인 운동 이행률이 낮거나 이탈 위험 신호(부정적 피드백 포함)를 보이고 있어요. 다음 세션 전에 난이도를 낮추고 최근 피드백을 확인해 주세요.';
  }

  @override
  String get dashActivityInactiveTitle => '7일 이상 활동 저조';

  @override
  String dashActivityInactiveDesc(String names) {
    return '$names 회원이 최근 7일 동안 운동 기록이 없어요. 이탈로 이어지기 전에 먼저 연락해서 재참여를 유도해 보세요.';
  }

  @override
  String get dashActivityDietFeedbackTitle => '식단 피드백 미완료';

  @override
  String dashActivityDietFeedbackDesc(String names) {
    return '$names 회원이 나트륨·당류 초과 등 식단 주의 신호가 있는데 최근 7일간 피드백을 받지 못했어요. 식단 코멘트를 남겨 확인했다는 걸 알려 주세요.';
  }

  @override
  String dashActivityMoreClients(String shown, int count) {
    return '$shown 외 $count명';
  }

  @override
  String get dashAiSummaryTitle => '활동 피드백';

  @override
  String get dashAiNoClients =>
      '아직 담당 회원이 없어요. 회원을 등록하면 식단·운동 데이터를 모아 코칭 포인트를 짚어 드릴게요.';

  @override
  String dashAiAllOnTrack(int total) {
    return '담당 회원 $total명 모두 목표 범위 안이에요. 지금 강도를 유지하면서 다음 주 목표를 올려 보세요.';
  }

  @override
  String get dashAiLoading => '식단·운동·최근 대화를 종합하고 있어요…';

  @override
  String get dashAiLoadFailed => '상세 코칭 요약을 불러오지 못했어요.';

  @override
  String get dashAiRateLimited => '요약 요청이 많아요. 잠시 후 다시 시도해 주세요.';

  @override
  String get dashAiStatus => '현재 상태';

  @override
  String get dashAiExerciseFocus => '오늘 운동 중심';

  @override
  String get dashAiEvidence => '판단 근거';

  @override
  String get dashAiCaution => '세션 전 확인';

  @override
  String get dashAiPriorityHigh => '우선 확인';

  @override
  String get dashAiPriorityMedium => '관찰 필요';

  @override
  String get dashAiPriorityLow => '유지';

  @override
  String dashAiRuleHeadline(String name) {
    return '$name 회원을 먼저 확인하고, 식단·컨디션 신호에 맞춰 운동 부하를 조절하세요.';
  }

  @override
  String get dashAiRuleKneeStatus =>
      '최근 대화에서 무릎·하체 불편 신호가 확인돼 하체 부하 조절이 필요합니다.';

  @override
  String get dashAiRuleKneeFocus =>
      '스쿼트·런지 고중량은 줄이고 둔근 활성화, 무릎 가동성, 평지 걷기 중심으로 구성하세요.';

  @override
  String get dashAiRuleKneeCaution => '세션 전 통증 위치와 가동 범위를 다시 확인하세요.';

  @override
  String get dashAiRuleUpperStatus => '어깨·목 불편 신호가 확인돼 상체 밀기·당기기 강도를 조절해야 합니다.';

  @override
  String get dashAiRuleUpperFocus =>
      '상체 고중량은 줄이고 흉추 가동성, 견갑 안정화, 상체 스트레칭 중심으로 구성하세요.';

  @override
  String get dashAiRuleUpperCaution => '팔을 들 때 불편한 각도를 먼저 확인하세요.';

  @override
  String get dashAiRuleFatigueStatus =>
      '야근·피로로 운동 지속에 어려움이 있어 완수 가능한 강도가 우선입니다.';

  @override
  String get dashAiRuleFatigueFocus =>
      '고강도 전신 운동은 줄이고 15~20분 저강도 유산소와 회복 스트레칭 중심으로 구성하세요.';

  @override
  String get dashAiRuleFatigueCaution => '수면과 현재 피로도를 확인한 뒤 강도를 확정하세요.';

  @override
  String get dashAiRuleSodiumStatus =>
      '오늘 나트륨 섭취가 기준을 넘어 당일 컨디션을 반영한 강도 설정이 필요합니다.';

  @override
  String get dashAiRuleSodiumFocus =>
      '고강도 인터벌보다 중강도 걷기·사이클과 안정적인 전신 근력 볼륨 중심으로 구성하세요.';

  @override
  String get dashAiRuleSodiumCaution => '수분 섭취와 어지럼·부종 여부를 확인하세요.';

  @override
  String get dashAiRuleCompletionStatus =>
      '주간 운동 이행률이 낮아 운동량·난이도와 목표를 다시 확인해야 합니다.';

  @override
  String get dashAiRuleCompletionFocus =>
      '동작 수와 운동량을 줄여 완수 가능한 난이도로 시작하고 주간 목표를 점진적으로 재구성하세요.';

  @override
  String get dashAiRuleCompletionCaution => '이번 주 운동을 방해한 일정·컨디션을 먼저 확인하세요.';

  @override
  String get dashAiRuleUnansweredStatus =>
      '확인하지 않은 메시지가 있어 오늘 운동 전 현재 상태를 먼저 확인해야 합니다.';

  @override
  String get dashAiRuleUnansweredFocus =>
      '답변으로 컨디션을 확인하기 전까지 증량은 보류하고 기존 강도의 가동성 운동으로 시작하세요.';

  @override
  String get dashAiRuleUnansweredCaution =>
      '통증·피로·수면 상태를 확인한 뒤 오늘의 부위와 강도를 확정하세요.';

  @override
  String dashAiRuleEvidenceMessage(String message) {
    return '최근 대화: “$message”';
  }

  @override
  String dashAiRuleEvidenceSodium(int value, int target) {
    return '오늘 나트륨 ${value}mg / 기준 ${target}mg';
  }

  @override
  String dashAiRuleEvidenceCompletion(int average) {
    return '이번 주 기록일 평균 이행률 $average%';
  }

  @override
  String get dashAttentionTitle => '확인 필요 회원';

  @override
  String dashMoreCount(int count) {
    return '+$count명';
  }

  @override
  String get dashNoAttention => '지금 챙길 회원이 없어요';

  @override
  String get dashTodaySchedule => '오늘의 일정';

  @override
  String get dashSeeAll => '전체 보기';

  @override
  String get dashScheduleLoadFailed => '일정을 불러오지 못했어요';

  @override
  String get dashNoScheduleToday => '오늘 등록된 일정이 없어요';

  @override
  String dashScheduleNowLabel(String time) {
    return '지금 $time';
  }

  @override
  String dashScheduleNextSession(String time, String name) {
    return '다음 일정 $time · $name';
  }

  @override
  String dashScheduleMinutesLeft(int minutes) {
    return '$minutes분 뒤';
  }

  @override
  String get dashPreparePt => 'PT 준비하기';

  @override
  String get dashLeaveMemo => '메모 남기기';

  @override
  String get dashSessionSent => '전송됨';

  @override
  String get dashSessionPrepared => '준비됨';

  @override
  String get dashSessionNoteWritten => '작성 완료';

  @override
  String get dashSessionSentNo => '전송 안됨';

  @override
  String get dashSessionPreparedNo => '준비 안됨';

  @override
  String get dashSessionNoteNotWritten => '메모 없음';

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
  String get clientsLoadFailed => '회원 정보를 불러오지 못했어요';

  @override
  String clientsCountSummary(int total, int active) {
    return '$total명 · 활성 $active명';
  }

  @override
  String get clientsNew => '신규 회원 등록';

  @override
  String get clientsTitle => '회원 관리';

  @override
  String get clientsManagementAttention => '관리 필요';

  @override
  String get clientsFiltersClearAll => '전체 초기화';

  @override
  String get clientsSortLabel => '정렬';

  @override
  String get clientsSortPriority => '관리 필요 우선';

  @override
  String get clientsSortName => '이름 오름차순';

  @override
  String get clientsSortNameDescending => '이름 내림차순';

  @override
  String get clientsSortRecentMessage => '최근 대화순';

  @override
  String get clientsSortActiveFirst => '활성 회원 우선';

  @override
  String get clientsFilterLabel => '필터';

  @override
  String clientsToolbarCount(int shown, int active) {
    return '$shown명 · 활성 $active명';
  }

  @override
  String get clientsPickHint => '왼쪽에서 회원을 선택하면\n대화·식단·운동 기록이 여기에 열려요';

  @override
  String get clientsEmpty => '아직 담당 회원이 없어요';

  @override
  String clientsEmptyForFilter(String filter) {
    return '$filter에 해당하는 회원이 없어요';
  }

  @override
  String clientsFilterSummary(String filter, int shown, int total) {
    return '$filter · $shown/$total명';
  }

  @override
  String get clientsSeeAll => '전체 보기';

  @override
  String get memberHealthLoadFailed => '회원 정보를 불러오지 못했어요. 다시 시도해 주세요';

  @override
  String get memberHealthSaveFailed => '회원 정보를 저장하지 못했어요. 다시 시도해 주세요';

  @override
  String get memberHealthSaving => '저장 중…';

  @override
  String get memberHealthGender => '성별';

  @override
  String get memberHealthGenderUnset => '미설정';

  @override
  String get memberHealthGenderMale => '남성';

  @override
  String get memberHealthGenderFemale => '여성';

  @override
  String get memberHealthGenderOther => '기타';

  @override
  String get memberHealthHeight => '키 (cm)';

  @override
  String get memberHealthWeight => '체중 (kg)';

  @override
  String get memberHealthConditions => '건강상태·주의사항';

  @override
  String get memberHealthGoals => '회원 목표';

  @override
  String get memberHealthDietGoal => '식단 목표';

  @override
  String get memberHealthExerciseGoal => '운동 목표';

  @override
  String get memberHealthGoalCalories => '일일 칼로리 제한 (kcal)';

  @override
  String get memberHealthGoalSodium => '일일 나트륨 제한 (mg)';

  @override
  String get memberHealthGoalSugar => '일일 당류 제한 (g)';

  @override
  String get memberHealthGoalCarbs => '일일 탄수화물 제한 (g)';

  @override
  String get memberHealthGoalProtein => '일일 단백질 제한 (g)';

  @override
  String get memberHealthGoalFat => '일일 지방 제한 (g)';

  @override
  String get memberHealthGoalBurnDaily => '일일 소모 칼로리 (kcal)';

  @override
  String get memberHealthGoalCardioWeekly => '주간 유산소 (분)';

  @override
  String get memberHealthGoalStrengthWeekly => '주간 근력 (세트)';

  @override
  String get memberHealthGoalFlexibilityWeekly => '주간 스트레칭 (분)';

  @override
  String get memberHealthWeeklyGoal => '주간 운동 목표';

  @override
  String get memberHealthWeeklyCount => '횟수';

  @override
  String get memberHealthWeeklyMinutes => '시간(분)';

  @override
  String get memberHealthWeeklyBurn => '소모 kcal';

  @override
  String memberHealthRange(String min, String max) {
    return '$min~$max 범위로 입력해 주세요.';
  }

  @override
  String get clientInviteTitle => '신규 회원 등록';

  @override
  String get clientInviteIntro => '회원 앱 MY 탭의 6자리 동기화 코드를 입력하면 바로 연결돼요.';

  @override
  String get clientInviteIntroImmediate =>
      '회원 앱 MY 탭의 6자리 동기화 코드를 입력하면 바로 연결돼요.';

  @override
  String get clientConnectCodeLabel => '회원 동기화 코드';

  @override
  String get clientConnectCodeRequired => '6자리를 모두 입력해 주세요';

  @override
  String get clientConnectCodeInvalid => '코드가 맞지 않거나 만료됐어요. 회원에게 새 코드를 받아 주세요';

  @override
  String get clientInviteMemberIdLabel => '회원 ID';

  @override
  String get clientInviteLookupAction => '찾기';

  @override
  String get clientInviteMessageLabel => '함께 보낼 메시지 (선택)';

  @override
  String get clientInviteSendAction => '담당 요청 보내기';

  @override
  String get clientInviteConnectAction => '회원 등록';

  @override
  String clientInviteSent(String name) {
    return '$name님에게 담당 요청을 보냈어요';
  }

  @override
  String clientInviteConnected(String name) {
    return '$name님을 회원으로 등록했어요';
  }

  @override
  String get clientInviteNotFound => '그 회원 ID를 쓰는 회원을 찾지 못했어요';

  @override
  String get clientInviteFailed => '요청을 보내지 못했어요. 다시 시도해 주세요';

  @override
  String get clientInviteMemberIdRequired => '회원 ID를 입력해 주세요';

  @override
  String get clientInviteAlreadyCoached => '이미 담당하고 있는 회원이에요';

  @override
  String get clientInviteHasTrainer => '이미 다른 트레이너가 담당 중인 회원이에요';

  @override
  String get clientInvitePendingHint => '이미 보낸 요청이 회원의 답을 기다리고 있어요';

  @override
  String get clientInvitePendingTitle => '답을 기다리는 요청';

  @override
  String get clientInvitePendingEmpty => '기다리는 요청이 없어요';

  @override
  String get clientInviteCancelAction => '요청 거두기';

  @override
  String get clientInviteCancelled => '요청을 거뒀어요';

  @override
  String get clientInviteCancelFailed => '요청을 거두지 못했어요. 다시 시도해 주세요';

  @override
  String get clientInviteConfirmPrompt => '이 회원이 맞나요?';

  @override
  String get coachTemplateNew => '새 템플릿';

  @override
  String get coachTemplateEdit => '템플릿 편집';

  @override
  String get coachTemplateSaveAsMine => '내 템플릿으로 저장';

  @override
  String get coachTemplateDelete => '삭제';

  @override
  String get coachTemplateNameLabel => '템플릿 이름';

  @override
  String get coachTemplateGoalLabel => '목표 (예: 혈압 관리 · 초급)';

  @override
  String get coachTemplateExerciseName => '운동 이름';

  @override
  String get coachTemplateExerciseMinutes => '분';

  @override
  String get coachTemplateAddExercise => '운동 추가';

  @override
  String get coachTemplateSave => '저장';

  @override
  String get coachTemplateNameRequired => '템플릿 이름을 입력해 주세요';

  @override
  String get coachTemplateExerciseRequired => '운동을 하나 이상 넣어 주세요';

  @override
  String get coachTemplateSaveFailed => '템플릿을 저장하지 못했어요. 다시 시도해 주세요';

  @override
  String get coachTemplateDeleteFailed => '템플릿을 지우지 못했어요. 다시 시도해 주세요';

  @override
  String coachTemplateDeleteConfirm(String name) {
    return '$name 템플릿을 지울까요?';
  }

  @override
  String get coachTemplateLoadFailed => '템플릿을 불러오지 못했어요';

  @override
  String get coachTemplateStarterHint => '기본 구성이에요. 고치면 내 템플릿으로 저장돼요';

  @override
  String get chatAttachImage => '사진 첨부';

  @override
  String get chatImageUnavailable => '사진을 불러오지 못했어요';

  @override
  String get chatImageSendFailed => '사진을 보내지 못했어요. 다시 시도해 주세요';

  @override
  String get clientTabDiet => '식단';

  @override
  String get clientTabWorkout => '운동';

  @override
  String get clientNotFound => '회원을 찾을 수 없어요';

  @override
  String get clientBackToList => '회원 목록으로';

  @override
  String get clientList => '회원 목록';

  @override
  String get metricCalories => '칼로리';

  @override
  String get metricSodium => '나트륨';

  @override
  String get metricSugar => '당류';

  @override
  String get clientDietMacrosMissing => '탄·단·지 기록 없음';

  @override
  String get metricCarbs => '탄수화물';

  @override
  String get metricProtein => '단백질';

  @override
  String get metricFat => '지방';

  @override
  String get clientActive => '활성';

  @override
  String get clientDormant => '휴면';

  @override
  String get clientStatusChangeFailed => '상태를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get clientClosePanel => '패널 닫기';

  @override
  String get clientChat => '채팅';

  @override
  String get chatTooLong => '메시지가 너무 길어요 (최대 2000자)';

  @override
  String get chatSendFailed => '메시지 전송에 실패했어요. 다시 시도해 주세요';

  @override
  String get chatPdfOpenFailed => 'PDF를 열지 못했어요. 다시 시도해 주세요';

  @override
  String get chatReportRegistered => '리포트가 등록되었어요';

  @override
  String get chatReportOpenInReports => '리포트 탭으로 가기';

  @override
  String get chatLoadFailed => '대화를 불러오지 못했어요';

  @override
  String chatDemoAnalyzed(String name) {
    return 'AI가 $name님의 식단·운동 데이터를 분석했어요';
  }

  @override
  String get chatDemoReportSent => '트레이너님께 요약 리포트가 전송됐어요';

  @override
  String chatDemoRoutineSent(String name) {
    return '개인 추천운동이 $name님에게 전송됐어요';
  }

  @override
  String get chatDemoNotified => '회원 앱에 알림이 전달됐어요';

  @override
  String get chatInputHint => '메시지 입력...';

  @override
  String chatInsightDiscomfortTitle(String part) {
    return '$part 불편 표현 감지';
  }

  @override
  String get chatInsightBodyPartGeneral => '신체';

  @override
  String get chatInsightNegativeTitle => '부정적 피드백 감지';

  @override
  String get chatInsightDiscomfortDescription =>
      'AI가 불편감 호소를 감지했어요. 증상을 확인하고 다음 운동 강도를 조절해 보세요.';

  @override
  String get chatInsightNegativeDescription =>
      'AI가 운동 부담 또는 수행 어려움을 감지했어요. 원인을 확인하고 프로그램 조정을 고려해 보세요.';

  @override
  String get chatInsightAddMemo => '메모에 추가';

  @override
  String get chatInsightMemoAdded => '메모 추가됨';

  @override
  String chatInsightMemoSummaryDiscomfort(String part) {
    return '$part 불편 감지';
  }

  @override
  String get chatInsightMemoSummaryNegative => '운동 부담 감지';

  @override
  String get chatInsightMemoSaved => 'AI 감지 내용을 트레이너 메모에 추가했어요.';

  @override
  String get chatInsightMemoSaveFailed => '메모에 추가하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String coachSheetTitle(String name) {
    return '$name 코칭 상담';
  }

  @override
  String get coachSheetSubtitle => '이 회원의 식단·운동 기록을 근거로 답해요.';

  @override
  String get coachSheetHint => '예) 나트륨이 계속 높은데 어떤 식단을 권할까요?';

  @override
  String get coachSheetSources => '근거';

  @override
  String get coachSheetAsk => '물어보기';

  @override
  String get coachSheetAskAgain => '다시 묻기';

  @override
  String get consultTitle => '상담 요청';

  @override
  String get consultBackToSchedule => '스케줄로 돌아가기';

  @override
  String get consultBackToDashboard => '대시보드로 돌아가기';

  @override
  String consultPendingCount(int count) {
    return '대기 중 $count건';
  }

  @override
  String get consultNoPending => '대기 중인 요청이 없어요';

  @override
  String get consultFilterAll => '전체';

  @override
  String consultFilterPendingCount(int count) {
    return '대기 $count';
  }

  @override
  String get consultLoadMore => '지난 요청 더 보기';

  @override
  String get consultLoadFailed => '상담 요청을 불러오지 못했어요';

  @override
  String get consultRetryLater => '잠시 후 다시 시도해 주세요';

  @override
  String get consultEmptyPending => '대기 중인 상담 요청이 없어요';

  @override
  String get consultEmptyHistory => '상담 요청 이력이 없어요';

  @override
  String get consultEmptyHint => '회원이 나를 지정해 상담을 신청하면 여기에 표시돼요';

  @override
  String get consultActionFailed => '상담을 처리하지 못했어요';

  @override
  String consultApproved(String name) {
    return '$name님의 상담 요청을 승인했어요. 스케줄 탭에서 일정을 추가해 주세요.';
  }

  @override
  String consultScheduleCreated(String name) {
    return '$name님의 상담 일정을 등록했어요';
  }

  @override
  String get consultRejected => '상담 요청을 거절했어요';

  @override
  String consultScheduleConflict(String name, String time) {
    return '$name님 $time 일정과 겹쳐요';
  }

  @override
  String get consultDecisionNote => '거절 사유';

  @override
  String get consultTargetTrainer => '트레이너 지정';

  @override
  String get consultExerciseGoal => '운동 목표';

  @override
  String get consultHealthPurpose => '건강관리 목적';

  @override
  String get consultPreferredTime => '희망 일시';

  @override
  String get consultMessage => '문의 내용';

  @override
  String get consultReject => '거절';

  @override
  String get consultApprove => '승인';

  @override
  String get consultRejectTitle => '상담 요청 거절';

  @override
  String get consultRejectNotice => '입력한 사유는 회원에게 알림으로 전달돼요.';

  @override
  String get consultRejectHint => '예) 요청하신 시간에 다른 일정이 있어요.';

  @override
  String get consultRejectAction => '거절하기';

  @override
  String get consultStatusPending => '대기중';

  @override
  String get consultStatusAccepted => '승인됨';

  @override
  String get workoutRecords => '운동 기록';

  @override
  String get workoutRecordsShowMore => '더보기';

  @override
  String get workoutRecordsShowLess => '접기';

  @override
  String get workoutLoadFailed => '운동 기록을 불러오지 못했어요';

  @override
  String get workoutEmpty => '아직 운동 기록이 없어요';

  @override
  String get routinesAssigned => '배정된 프로그램';

  @override
  String get routineNew => '새 프로그램';

  @override
  String get routinesLoadFailed => '프로그램을 불러오지 못했어요';

  @override
  String get routinesEmpty => '아직 이 회원에게 배정된 프로그램이 없어요';

  @override
  String minutesShort(int minutes) {
    return '$minutes분';
  }

  @override
  String get ptProgramHistory => 'PT 프로그램 이력';

  @override
  String get scheduleLoadFailed => '일정을 불러오지 못했어요';

  @override
  String get ptSessionsEmpty => '등록된 PT 세션이 없어요';

  @override
  String get labelToday => '오늘';

  @override
  String sessionTypeAndDuration(String type, int minutes) {
    return '$type · $minutes분';
  }

  @override
  String get programNone => '등록된 프로그램 없음';

  @override
  String get legendDone => '완료';

  @override
  String get clientFeedback => '회원 피드백';

  @override
  String clientFeedbackOn(String name) {
    return '$name에 대한 회원 피드백';
  }

  @override
  String get clientFeedbackPersonal => '개인 운동에 대한 회원 피드백';

  @override
  String get clientFeedbackSession => '이 세션에 대한 회원 피드백';

  @override
  String get workoutKindAiPersonal => 'AI 개인운동';

  @override
  String get trainerNote => '트레이너 메모';

  @override
  String get dietLoadFailed => '식단을 불러오지 못했어요';

  @override
  String get dietEmpty => '아직 기록된 식단이 없어요';

  @override
  String get dietDayEmpty => '기록 없음';

  @override
  String get dietMacros => '탄단지';

  @override
  String get clientNutritionSummary => '영양 요약';

  @override
  String get dietCalorieIntake => '오늘 섭취 칼로리';

  @override
  String get dietAchieveRate => '달성률';

  @override
  String dietAmountOver(String amount) {
    return '목표보다 $amount 많아요';
  }

  @override
  String dietAmountRemaining(String amount) {
    return '목표까지 $amount 남았어요';
  }

  @override
  String dietSodiumValue(int value) {
    return '나트륨 ${value}mg';
  }

  @override
  String get aiAnalysis => 'AI 분석';

  @override
  String get aiPeriodAnalysis => 'AI 기간 분석';

  @override
  String get aiAllAnalysis => 'AI 전체 분석';

  @override
  String dietAiOverSodium(int over) {
    return '나트륨이 목표치를 ${over}mg 초과했어요. 오늘 운동 프로그램에 유산소를 추가하면 도움이 돼요.';
  }

  @override
  String get dietAiBalanced => '오늘 식단은 균형이 잘 맞아요. 현재 프로그램을 유지하세요.';

  @override
  String get consultStatusRejected => '거절됨';

  @override
  String get dateToday => '오늘';

  @override
  String get dateTomorrow => '내일';

  @override
  String get dateYesterday => '어제';

  @override
  String dateMonthDayWeekday(int month, int day, String weekday) {
    return '$month월 $day일 ($weekday)';
  }

  @override
  String datePrefixed(String prefix, String date) {
    return '$prefix · $date';
  }

  @override
  String dateMonthDay(int month, int day) {
    return '$month월 $day일';
  }

  @override
  String dateRange(String start, String end) {
    return '$start – $end';
  }

  @override
  String get reportsTitle => '리포트';

  @override
  String get reportsSubtitle => '주간 변화를 확인하고 회원에게 전달하세요';

  @override
  String get reportsLoadFailed => '리포트를 불러오지 못했어요';

  @override
  String get reportsNoClients => '담당 회원이 없어 리포트를 만들 수 없어요';

  @override
  String get reportsWeekly => '주간 리포트';

  @override
  String get reportsSendFailed => '리포트 전송에 실패했어요. 다시 시도해 주세요';

  @override
  String reportsSent(String name) {
    return '$name님에게 리포트를 보냈어요';
  }

  @override
  String get reportsGoToChat => '채팅으로 이동하기';

  @override
  String get reportsScheduleWarning => '이번 주 일정을 불러오지 못해 세션 수가 비어 있을 수 있어요';

  @override
  String get unitTimes => '회';

  @override
  String get unitMinutes => '분';

  @override
  String clientTrendWorkoutDaysValue(int days) {
    return '$days일';
  }

  @override
  String get clientPeriodToday => '오늘';

  @override
  String get clientPeriodWeek => '이번 주';

  @override
  String get clientPeriodMonth => '전체';

  @override
  String get clientPeriodAverage => '하루 평균';

  @override
  String get clientPeriodGoal => '목표';

  @override
  String get exBurnTodayTitle => '오늘 소모';

  @override
  String get exBurnWeekTitle => '이번 주 소모';

  @override
  String get exBurnMonthTitle => '이번 달 소모';

  @override
  String get exBurnDayTitle => '소모';

  @override
  String get exBurnAllTitle => '평균 소모';

  @override
  String exWeekOfMonthLabel(int month, int week) {
    return '$month월 $week주차';
  }

  @override
  String exStreakCheer(int days) {
    return '$days일 연속 운동 중이에요!';
  }

  @override
  String get exStreakStart => '아직 연속 기록이 없어요';

  @override
  String get exTypeOther => '기타';

  @override
  String exSetsValue(int count) {
    return '$count세트';
  }

  @override
  String clientPeriodLoggedDays(int days) {
    return '$days일 기록';
  }

  @override
  String get clientPeriodEmpty => '이 기간에 기록이 없어요';

  @override
  String get clientDietTrendTitle => '영양 추이';

  @override
  String get unitKcal => 'kcal';

  @override
  String get clientTrendTitle => '운동 현황';

  @override
  String get clientTrendLoadFailed => '운동 추이를 불러오지 못했어요. 다시 시도해 주세요';

  @override
  String get clientTrendTodayEmpty => '오늘 기록된 운동이 없어요';

  @override
  String get clientTrendTodayTotal => '오늘 총 운동 시간';

  @override
  String get clientTrendWorkoutDays => '운동한 날';

  @override
  String get clientTrendWorkoutCount => '운동 횟수';

  @override
  String get clientTrendWorkoutMinutes => '운동 시간';

  @override
  String get clientTrendCaloriesBurned => '소모 칼로리';

  @override
  String get clientTrendSegmentTime => '시간';

  @override
  String get reportsPickClient => '회원 선택';

  @override
  String reportsClientWeekly(String name) {
    return '$name님 주간 리포트';
  }

  @override
  String get reportsCompletionAvg => '운동 이행률';

  @override
  String get reportsWeeklyCompletion => '주간 이행률';

  @override
  String get clientWeeklyRoutineAdherence => '주간 이행률';

  @override
  String get clientRoutineAdherenceUnmeasured => '미집계';

  @override
  String get reportsCompletionByDay => '주간 운동 이행률';

  @override
  String get reportsNoWorkoutsThisWeek => '이번 주 운동 기록이 없어요';

  @override
  String reportsMetricTrend(String metric) {
    return '$metric 추이';
  }

  @override
  String reportsNoLastWeekMetricTrend(String metric) {
    return '지난 주 $metric 추이는 아직 없어요';
  }

  @override
  String reportsNoMetricRecords(String metric) {
    return '이번 주 $metric 기록이 아직 없어요';
  }

  @override
  String get reportsDietTrend => '주간 식단 추이';

  @override
  String workoutDoneOfTotal(int total, int done) {
    return '$total개 중 $done개 완료';
  }

  @override
  String get chartNoRecord => '기록 없음';

  @override
  String get chartNotYet => '아직 오지 않은 날';

  @override
  String chartOverGoal(String amount, String unit) {
    return '목표 초과 +$amount $unit';
  }

  @override
  String get reportsSendStateSent => '전송됨';

  @override
  String get reportsSendStateSending => '전송 중…';

  @override
  String get reportsShare => '공유';

  @override
  String reportsShareSendTo(String name) {
    return '$name님에게 전송';
  }

  @override
  String get reportsShareNeedsFeedback => '피드백을 입력하면 전송할 수 있어요';

  @override
  String get reportsShareNoClient => '리포트를 볼 회원을 먼저 선택해 주세요';

  @override
  String reportBodyGreeting(String name, String range) {
    return '$name님, $range 주간 리포트 정리해서 보내드려요.';
  }

  @override
  String reportBodyCompletionGood(int avg) {
    return '운동은 평균 $avg%로 잘 따라오셨어요.';
  }

  @override
  String reportBodyCompletionLow(int avg) {
    return '운동 이행률은 평균 $avg%였어요. 많이 바쁘셨나 봐요.';
  }

  @override
  String reportBodySkipped(String names) {
    return '다만 $names 건너뛰셨더라고요. 컨디션 때문이었다면 다음 세션 때 말씀해 주세요. 대체 동작으로 바꿔 둘게요.';
  }

  @override
  String reportBodySodiumOver(String avg, String target, int days) {
    return '나트륨은 하루 평균 ${avg}mg이었고, 목표(${target}mg)를 넘긴 날이 $days일이었어요. 국물을 절반만 남기셔도 하루 400~500mg은 줄어듭니다.';
  }

  @override
  String reportBodySodiumOk(String avg, String target) {
    return '나트륨은 하루 평균 ${avg}mg으로 목표(${target}mg) 안에서 잘 지키고 계세요.';
  }

  @override
  String reportBodyCalories(String avg) {
    return '칼로리는 하루 평균 ${avg}kcal이에요.';
  }

  @override
  String get reportBodyPraise => '정말 잘하셨어요. 다음 주도 이 페이스 그대로 가요!';

  @override
  String get reportBodyEncourage =>
      '다음 주에는 이 부분만 같이 신경 써 봐요. 프로그램은 제가 조정해서 올려둘게요.';

  @override
  String get reportBodyNoRecords =>
      '이 주에는 남은 기록이 없어서 정리해 드릴 내용이 없네요. 다음 주 시작을 같이 잡아 봐요.';

  @override
  String get schedTitle => '스케줄';

  @override
  String get schedDetailTitle => '상세 일정';

  @override
  String get schedDeleteTitle => '일정 삭제';

  @override
  String schedDeleteConfirm(String time, String name) {
    return '$time $name님 PT 일정을 삭제할까요?';
  }

  @override
  String get schedDeleteFailed => '일정 삭제에 실패했어요. 다시 시도해 주세요';

  @override
  String get schedCompleteTitle => '일정 완료';

  @override
  String schedCompleteConfirm(String time, String name) {
    return '$time $name님 세션을 완료할까요?';
  }

  @override
  String get schedCompleteFailed => '완료 처리에 실패했어요. 다시 시도해 주세요';

  @override
  String schedTimeRange(String start, String end) {
    return '$start–$end';
  }

  @override
  String schedBlockTime(String range, String duration) {
    return '$range ($duration)';
  }

  @override
  String get schedEmptyWeek => '이번 주에는 일정이 없어요.';

  @override
  String get schedSlots => '예약 슬롯';

  @override
  String get schedNewSession => '새 일정';

  @override
  String get schedLoadFailed => '스케줄을 불러오지 못했어요';

  @override
  String get schedEmptyDay => '이 날짜에는 일정이 없어요.\n위의 「새 일정」으로 추가해 보세요.';

  @override
  String get schedSaveFailed => '일정 저장에 실패했어요. 다시 시도해 주세요';

  @override
  String get schedAddTitle => '새 일정 추가';

  @override
  String get schedEditTitle => '일정 수정';

  @override
  String get schedFieldClient => '회원';

  @override
  String get schedFieldType => '유형';

  @override
  String get schedFieldDate => '날짜';

  @override
  String get schedFieldStartDate => '시작 날짜';

  @override
  String get schedFieldDateRange => '시작 - 종료일';

  @override
  String get schedFieldTime => '시간';

  @override
  String get schedHourSuffix => '시간';

  @override
  String get schedMinuteSuffix => '분';

  @override
  String get schedFieldDuration => '소요 시간';

  @override
  String get schedFieldStart => '시작';

  @override
  String get schedFieldEnd => '종료';

  @override
  String get schedEndBeforeStart => '종료 시간은 시작 시간보다 늦어야 해요';

  @override
  String get schedReopenTitle => '예정으로 바꿀까요?';

  @override
  String get schedReopenBody =>
      '완료된 세션을 앞으로 옮기면 예정 상태로 되돌아가고, 그 완료가 남긴 운동 기록은 사라져요.';

  @override
  String get schedReopenConfirm => '예정으로 바꾸기';

  @override
  String get schedReopenPastBlocked => '완료된 세션은 미래 날짜로만 옮길 수 있어요';

  @override
  String get schedTimeRangeTitle => '시간 선택';

  @override
  String get schedTimeRangeConfirm => '확인';

  @override
  String get schedTimeRangeInvalid => '올바른 시간을 입력하세요 (HH:mm)';

  @override
  String get schedRepeat => '반복';

  @override
  String get schedRepeatWeekly => '매주';

  @override
  String get schedRepeatDays => '반복 요일';

  @override
  String schedRepeatPreview(int count, String first, String last) {
    return '총 $count회 · $first ~ $last';
  }

  @override
  String get schedRepeatNeedsDays => '반복할 요일을 골라 주세요.';

  @override
  String get schedRepeatNeedsEndDate => '반복 종료일을 골라 주세요.';

  @override
  String schedRepeatConflictTitle(int total, int count) {
    return '총 $total회 중 $count개의 일정이 겹칩니다';
  }

  @override
  String schedRepeatConflictRow(String date, String time, String name) {
    return '$date $time · 기존 일정: $name';
  }

  @override
  String get schedRepeatConflictHint =>
      '겹치는 회차가 있어 아무 일정도 만들지 않았어요. 시간을 바꾸거나 겹치는 일정을 정리해 주세요.';

  @override
  String get schedNote => '트레이너 메모';

  @override
  String get schedEditNote => '메모 수정';

  @override
  String get schedAddNote => '메모 추가';

  @override
  String get schedNoNote => '아직 남긴 메모가 없어요';

  @override
  String get schedNoteOnlyHint => '상담은 프로그램 대신 메모로 남깁니다.';

  @override
  String get schedNoteHint => '수업 준비사항이나 회원 특이사항을 입력하세요';

  @override
  String get schedAddAction => '추가';

  @override
  String get schedSaveAction => '저장';

  @override
  String get progInvalid => '운동 이름과 세트 수를 확인해 주세요';

  @override
  String get progSaveFailed => '프로그램 저장에 실패했어요. 다시 시도해 주세요';

  @override
  String get progEditTitle => '프로그램 수정';

  @override
  String get progAddTitle => '프로그램 추가';

  @override
  String get progAddExercise => '운동 추가';

  @override
  String get progNoteHint => '프로그램 진행 시 참고할 내용을 입력하세요';

  @override
  String get progSaving => '저장 중...';

  @override
  String get progSaveAction => '프로그램 저장';

  @override
  String get progSaveNoteAction => '메모 저장';

  @override
  String get progExerciseName => '운동 이름';

  @override
  String get progDeleteExercise => '운동 삭제';

  @override
  String get progSets => '세트';

  @override
  String get progReps => '횟수/시간';

  @override
  String get progWeight => '중량';

  @override
  String get progType => '유형';

  @override
  String get progDuration => '시간(분)';

  @override
  String get progOptional => '선택';

  @override
  String progSetsValue(int sets) {
    return '$sets세트';
  }

  @override
  String progRepsValue(int reps) {
    return '$reps회';
  }

  @override
  String get progEmpty => '아직 계획된 프로그램이 없어요';

  @override
  String get progEmptyHint => 'AI 추천 탭에서 프로그램을 만들어 보내거나, 채팅으로 미리 조율해 보세요.';

  @override
  String schedSentTo(String name) {
    return '$name님에게 전송됨';
  }

  @override
  String schedSentProgramTo(String name, String date) {
    return '$name님에게 $date PT 프로그램 전송';
  }

  @override
  String get slotPastTime => '현재보다 이후 시간만 예약 슬롯으로 만들 수 있어요.';

  @override
  String get slotOpened => '예약 슬롯을 열었습니다.';

  @override
  String get slotEditTitle => '예약 슬롯 수정';

  @override
  String get slotStartTime => '시작 시간';

  @override
  String get slotUpdated => '예약 슬롯을 수정했습니다.';

  @override
  String get slotCloseTitle => '예약 슬롯 닫기';

  @override
  String get slotCloseBody => '이미 잡힌 예약은 유지되고, 신규 예약만 중단됩니다.';

  @override
  String get slotClosed => '신규 예약을 닫았습니다.';

  @override
  String get slotActionFailed => '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.';

  @override
  String get slotManageTitle => '예약 슬롯 관리';

  @override
  String slotIntro(String date) {
    return '$date에 회원이 예약할 시간을 엽니다.';
  }

  @override
  String get slotOpenAction => '열기';

  @override
  String get slotReload => '다시 불러오기';

  @override
  String get slotEmpty => '이 날짜에 열린 예약 슬롯이 없습니다.';

  @override
  String get slotClosedSummary => '예약 닫힘';

  @override
  String get slotBookedSummary => '예약됨';

  @override
  String get slotOpenSummary => '비어 있음';

  @override
  String get slotCloseAction => '예약 닫기';

  @override
  String get myCareerInvalid => '경력은 0~80 사이의 연수로 입력해 주세요.';

  @override
  String get myProfileSaveFailed => '프로필을 저장하지 못했습니다.';

  @override
  String get myGymChangeFailed => '소속 헬스장 변경에 실패했습니다. 나머지 프로필 정보는 저장됐어요.';

  @override
  String get myTabProfile => '내 정보';

  @override
  String get myTabSettings => '설정';

  @override
  String get mySaving => '저장 중';

  @override
  String get myEditProfile => '프로필 수정';

  @override
  String get mySaved => '변경사항이 저장됐어요';

  @override
  String get myCertifications => '자격증 · 인증';

  @override
  String get myMonthStats => '이번 달 통계';

  @override
  String get myGym => '소속 헬스장';

  @override
  String get myNotifications => '알림';

  @override
  String get myNotifNewMessage => '새 메시지 알림';

  @override
  String get myNotifNewMessageHint => '회원이 메시지를 보내면 사이드바 뱃지로 알려드려요';

  @override
  String get myAccount => '계정';

  @override
  String get myChangePassword => '비밀번호 변경';

  @override
  String get myChangePasswordHint => '현재 비밀번호를 확인한 뒤 교체해요';

  @override
  String get myChangePasswordDemo => '데모 모드에는 계정이 없어 변경할 수 없어요';

  @override
  String get myLoginAccount => '로그인 계정';

  @override
  String get myLegal => '약관 및 정책';

  @override
  String get myLegalTermsTitle => '이용약관';

  @override
  String get myLegalTermsHint => '트레이너 계정의 서비스 이용 조건';

  @override
  String get myLegalPrivacyTitle => '개인정보 처리방침';

  @override
  String get myLegalPrivacyHint => '회원 정보를 열람하고 리포트를 보낼 때의 처리 기준';

  @override
  String get myLegalEffectiveDate => '시행일 2026. 01. 01.';

  @override
  String get myLegalTermsBody =>
      '제1조 (목적)\n이 약관은 On-Care(이하 \"회사\")가 제공하는 트레이너 콘솔(이하 \"서비스\")의 이용과 관련하여 회사와 트레이너 회원(이하 \"트레이너\") 간의 권리, 의무 및 책임사항을 규정함을 목적으로 합니다.\n\n제2조 (약관의 효력 및 변경)\n① 이 약관은 서비스를 이용하는 모든 트레이너에게 효력이 발생합니다.\n② 회사는 관련 법령을 위반하지 않는 범위에서 이 약관을 변경할 수 있으며, 변경 시 적용일자와 변경 사유를 명시하여 서비스 내에 공지합니다.\n\n제3조 (서비스의 제공)\n회사는 담당 회원 관리, 식단·운동 기록 열람, 일정 관리, 메시지, AI 코칭 프로그램 생성, 리포트 작성 및 전송 등 트레이너의 지도 업무를 돕는 기능을 제공합니다. 서비스의 구체적인 내용은 회사의 정책에 따라 변경될 수 있습니다.\n\n제4조 (계정)\n① 트레이너 계정과 회원 계정은 분리되어 있으며, 하나의 계정으로 두 서비스를 함께 이용할 수 없습니다.\n② 트레이너는 자격증·경력 등 프로필 정보를 사실대로 입력하여야 하며, 계정 정보의 관리 책임은 트레이너에게 있습니다.\n\n제5조 (회원 정보 취급 의무)\n① 트레이너는 담당 관계가 성립한 회원의 식단·운동·건강 기록에 한하여 열람할 수 있습니다.\n② 열람한 정보는 상담·코칭·리포트 작성 목적으로만 이용하여야 하며, 이를 외부에 게시하거나 제3자에게 제공·유출해서는 안 됩니다.\n③ 담당 관계가 종료되면 해당 회원 정보에 대한 열람 권한도 함께 종료됩니다.\n\n제6조 (금지 행위)\n트레이너는 의료 행위에 해당하는 진단·처방을 하거나, 회원의 동의 없이 회원 정보를 서비스 밖으로 옮기는 행위를 하여서는 안 됩니다.\n\n제7조 (책임의 제한)\n서비스가 제공하는 AI 코칭 결과와 통계는 지도를 돕기 위한 참고 자료입니다. 회원에게 전달하는 지도 내용에 대한 최종 판단과 책임은 트레이너에게 있으며, 회사는 법령이 허용하는 범위 내에서 그 결과에 대하여 책임을 부담하지 않습니다.\n\n제8조 (이용 계약의 해지)\n트레이너는 언제든지 탈퇴할 수 있습니다. 탈퇴 시 담당 회원과의 연결과 예정된 일정이 함께 종료되며, 해당 회원에게 그 사실이 안내됩니다.\n\n부칙\n이 약관은 2026년 1월 1일부터 시행합니다.';

  @override
  String get myLegalPrivacyBody =>
      'On-Care(이하 \"회사\")는 「개인정보 보호법」 등 관련 법령을 준수하며, 트레이너와 회원의 개인정보를 소중히 보호합니다.\n\n1. 수집하는 개인정보 항목\n회사는 트레이너 가입 및 서비스 제공을 위하여 이름, 이메일, 연락처와 함께 소속 헬스장, 자격증, 경력, 전문 분야 등 프로필 정보와 서비스 접속 기록을 수집합니다.\n\n2. 개인정보의 수집 및 이용 목적\n수집한 정보는 트레이너 식별과 자격 확인, 담당 회원 연결, 일정·메시지·리포트 기능 제공, 서비스 개선 및 문의 응대의 목적으로만 이용됩니다.\n\n3. 담당 회원 정보의 열람과 처리\n① 트레이너는 담당 관계가 성립한 회원에 한하여 그 회원이 기록한 식단·운동·체중 등 건강 정보를 서비스 안에서 열람할 수 있습니다.\n② 이 정보의 개인정보처리자는 회사이며, 트레이너는 회사가 정한 범위 안에서 코칭과 리포트 작성 목적으로만 이를 처리합니다.\n③ 트레이너가 작성해 전송한 리포트와 메시지는 해당 회원에게 전달되고 서비스에 기록으로 남습니다.\n④ 담당 관계가 종료되면 해당 회원 정보에 대한 열람 권한은 즉시 회수되며, 회원은 자신의 정보 제공에 대한 동의를 언제든지 철회할 수 있습니다.\n\n4. 개인정보의 보유 및 이용 기간\n트레이너의 개인정보는 원칙적으로 탈퇴 시 지체 없이 파기합니다. 다만 관련 법령에 따라 보존할 필요가 있는 경우 해당 기간 동안 안전하게 보관합니다. 회원에게 전송된 리포트와 메시지는 회원의 기록이므로 회원의 보관 기간을 따릅니다.\n\n5. 개인정보의 제3자 제공\n회사는 트레이너와 회원의 동의 없이 개인정보를 외부에 제공하지 않습니다. 다만 법령에 특별한 규정이 있는 경우는 예외로 합니다.\n\n6. 안전성 확보 조치\n회사는 회원 정보에 대한 접근 권한을 담당 관계를 기준으로 제한하고, 전송 구간을 암호화하며, 접속 기록을 보관합니다.\n\n7. 이용자의 권리\n트레이너는 언제든지 자신의 개인정보를 조회·수정하거나 처리 정지 및 삭제를 요청할 수 있습니다.\n\n8. 개인정보 보호책임자\n개인정보와 관련한 문의는 고객 지원(support@oncare.com)으로 연락하실 수 있습니다.\n\n시행일: 2026년 1월 1일';

  @override
  String get myAppInfo => '앱 정보';

  @override
  String get myService => '서비스';

  @override
  String get myVersion => '버전';

  @override
  String get myContact => '문의';

  @override
  String get myPasswordChanged => '비밀번호를 변경했어요';

  @override
  String myCareerYears(String career) {
    return '경력 $career';
  }

  @override
  String get myFieldName => '이름 (계정 정보)';

  @override
  String get myFieldEmail => '이메일 (계정 정보)';

  @override
  String get myFieldPhone => '연락처';

  @override
  String get myFieldSpecialty => '전문 분야';

  @override
  String get myFieldCareer => '경력';

  @override
  String get myFieldIntro => '소개';

  @override
  String get myAddCertification => '자격증 추가...';

  @override
  String get myAdd => '추가';

  @override
  String get myStatClients => '담당 회원';

  @override
  String get myClientManagement => '회원 관리';

  @override
  String get myClientRemove => '회원 삭제';

  @override
  String myClientRemoveTitle(String name) {
    return '$name 회원을 삭제할까요?';
  }

  @override
  String get myClientRemoveBody =>
      '이 회원의 스케줄, 프로그램·루틴, 리포트, 메시지, 메모 등이 트레이너 화면에서 모두 사라져요. 회원 앱의 기존 데이터는 삭제되지 않아요.';

  @override
  String get myClientRemoveSuccess => '회원을 삭제했어요';

  @override
  String get myClientRemoveFailed => '회원을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get myClientManagementEmpty => '담당 회원이 없어요';

  @override
  String get myStatSessionsDone => '완료 세션';

  @override
  String get myStatRoutinesSent => '프로그램 전송';

  @override
  String get myGymName => '헬스장 이름';

  @override
  String get myGymAddress => '주소';

  @override
  String get myGymHours => '운영 시간';

  @override
  String get myGymOpen => '영업 중';

  @override
  String get myGymListFailed => '헬스장 목록을 불러오지 못했습니다.';

  @override
  String get myNoGym => '소속 없음';

  @override
  String get mySignOut => '로그아웃';

  @override
  String get myPwCurrentRequired => '현재 비밀번호를 입력해 주세요';

  @override
  String myPwTooShort(int min) {
    return '새 비밀번호는 $min자 이상이어야 해요';
  }

  @override
  String get myPwMismatch => '새 비밀번호가 서로 달라요';

  @override
  String get myPwChangeFailed => '비밀번호를 변경할 수 없어요';

  @override
  String get myPwChangeRetry => '변경에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get myPwCurrent => '현재 비밀번호';

  @override
  String myPwNew(int min) {
    return '새 비밀번호 ($min자 이상)';
  }

  @override
  String get myPwConfirm => '새 비밀번호 확인';

  @override
  String get myPwChanging => '변경 중…';

  @override
  String get myPwChangeAction => '변경하기';

  @override
  String get mySettingsSaveFailed => '설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get routineTypeWalking => '걷기';

  @override
  String get routineTypeCardio => '유산소';

  @override
  String get routineTypeStrength => '근력';

  @override
  String get routineTypeYoga => '요가';

  @override
  String get routineTypeStretching => '스트레칭';

  @override
  String get routineTypeFlexibility => '스트레칭';

  @override
  String get routineTypeOther => '기타';

  @override
  String get routineFieldType => '운동 유형';

  @override
  String get routineFieldMinutes => '운동 시간';

  @override
  String get routineFieldTotalMinutes => '총 운동시간';

  @override
  String get routineFieldIntensity => '운동 강도';

  @override
  String get routineFieldDate => '날짜';

  @override
  String get routineFieldExerciseName => '운동 이름';

  @override
  String get routineFieldExerciseNameHint => '예) 스쿼트, 러닝머신';

  @override
  String get routineFieldExerciseNameHintCardio => '예) 러닝머신, 실내 자전거';

  @override
  String get routineFieldExerciseNameHintStrength => '예) 스쿼트, 벤치프레스';

  @override
  String get routineFieldExerciseNameHintFlexibility => '예) 전신 스트레칭, 요가';

  @override
  String get routineFieldExerciseNameHintOther => '예) 재활 운동, 스포츠 활동';

  @override
  String get routineFieldSets => '세트 수';

  @override
  String get routineFieldReps => '횟수';

  @override
  String get routineFieldWeight => '중량';

  @override
  String get routineFieldCalories => '예상 소모 칼로리';

  @override
  String get routineCaloriesNeedName => '운동 이름을 적어주세요';

  @override
  String get routineCaloriesRoughEstimate =>
      '운동 종류 평균으로 낸 어림값 · 회원이 수행하면 체중까지 반영된 값이 기록됩니다';

  @override
  String get routineUnitMinutes => '분';

  @override
  String get routineUnitSets => '세트';

  @override
  String get routineUnitReps => '회';

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
  String get intensityLight => '가벼움';

  @override
  String get intensityModerate => '보통';

  @override
  String get intensityHigh => '높음';

  @override
  String get coachTitle => '프로그램';

  @override
  String get coachSubtitle => '회원별 운동 프로그램을 만들고 배정·관리하세요';

  @override
  String get coachMemberSummary => '회원 요약';

  @override
  String get reportsDataInsufficient => '데이터 부족';

  @override
  String get reportsThisWeek => '이번 주';

  @override
  String get coachSendFailed => '전송에 실패했어요. 다시 시도해 주세요';

  @override
  String get coachScheduleFailed => '스케줄 등록에 실패했어요. 다시 시도해 주세요';

  @override
  String get coachNoClients => '등록된 회원이 없어요';

  @override
  String get coachRecommended => 'AI 추천안';

  @override
  String get coachBackToList => '추천 목록으로';

  @override
  String get coachReviewed => 'AI 생성 후 트레이너 검토 완료';

  @override
  String get coachTrainerAdded => '트레이너 추가';

  @override
  String coachTemplateAdded(String name) {
    return '$name 템플릿 추가';
  }

  @override
  String coachRegisteredOn(String date) {
    return '$date 스케줄에 등록됐어요';
  }

  @override
  String coachRegisteredAttachedExisting(String date) {
    return '$date에 이미 예정된 세션이 있어 그 세션에 프로그램만 추가됐어요 — 고른 시간 범위는 적용되지 않았어요';
  }

  @override
  String coachRegisterOn(String date) {
    return '$date PT 스케줄에 등록';
  }

  @override
  String get coachRegisterAction => 'PT 스케줄에 등록';

  @override
  String get coachGoToSchedule => '스케줄로 이동하기';

  @override
  String get labelTomorrow => '내일';

  @override
  String get coachRequestCustom => 'AI에게 맞춤 추천 요청하기';

  @override
  String coachRequestBlurb(String name) {
    return '$name님의 데이터를 분석해 회복형·강화형 후보를 만들고 이 화면에서 비교·수정할 수 있어요.';
  }

  @override
  String get coachTemplates => '프로그램 템플릿';

  @override
  String get coachSentHistory => '전송 이력';

  @override
  String get coachHistoryFailed => '이력을 불러오지 못했어요';

  @override
  String get coachHistoryEmpty => '아직 보낸 프로그램이 없어요';

  @override
  String get coachHomework => '개인';

  @override
  String get coachPersonalTraining => 'PT';

  @override
  String coachRoutineSummary(String name, int minutes) {
    return '$name · $minutes분';
  }

  @override
  String get coachTrainer => '트레이너';

  @override
  String coachSessionProgramSummary(String name, int count) {
    return '$name 외 $count개';
  }

  @override
  String get aiReasonSodium => '오늘 나트륨이 목표를 초과해 저강도 유산소 비중을 높이는 것이 좋아요.';

  @override
  String get aiReasonBalanced => '오늘 식단 균형이 안정적이라 기존 운동 강도를 유지해도 좋아요.';

  @override
  String aiReasonGoal(String goal, String last) {
    return '$goal 목표와 최근 $last 기록을 고려했어요.';
  }

  @override
  String get aiTagExisting => '기존 AI 추천';

  @override
  String get aiTagCustom => '맞춤';

  @override
  String get aiExistingBlurb => '회원의 최근 식단과 운동 기록을 반영한 기존 추천이에요.';

  @override
  String get aiOptionRecovery => '회복안';

  @override
  String get aiOptionPush => '강화안';

  @override
  String get aiOptionExisting => '기존안';

  @override
  String get aiGenerateFailed => 'AI 생성에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get aiGenerateRateLimited => 'AI 생성을 너무 자주 요청했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get aiExerciseNameRequired => '운동 이름을 입력해 주세요';

  @override
  String get aiKeepOneExercise => '운동을 하나 이상 남겨 주세요';

  @override
  String aiRoutineSent(String name) {
    return '$name님에게 프로그램을 전송했어요';
  }

  @override
  String aiExerciseWithMinutes(String name, int minutes) {
    return '$name $minutes분';
  }

  @override
  String aiCustomRoutineNamed(String option) {
    return 'AI 맞춤 추천안 ($option)';
  }

  @override
  String get aiAnalysing => 'AI가 분석 중…';

  @override
  String get aiGenerateCandidates => '맞춤 추천안 후보 생성';

  @override
  String get aiReviewDone => '검토 완료';

  @override
  String aiRoutineFor(String name) {
    return 'AI 추천안 · $name';
  }

  @override
  String get aiAnalysedData => '운동 목표와 최근 활동, 오늘의 식단 정보를 확인했어요';

  @override
  String get aiGoal => '목표';

  @override
  String get aiTodaySodium => '오늘 나트륨';

  @override
  String get aiOverTarget => ' · 목표 초과';

  @override
  String get aiRecentCompletion => '최근 완료율';

  @override
  String get aiNoCompletionData => '이번 주 기록 없음';

  @override
  String get aiCompletionLow => ' · 관리 필요';

  @override
  String get aiDietSignal => '식단 주의';

  @override
  String aiSodiumOverDaysSuffix(int days) {
    return ' · 최근 7일 중 $days일 초과';
  }

  @override
  String get aiSugarAlsoOver => ' · 당류도 초과';

  @override
  String get aiBasisRuleBased => ' · 규칙 기반 생성';

  @override
  String get aiChatEvidenceTitle => '참고한 최근 대화';

  @override
  String aiEditOption(String option) {
    return '$option 수정';
  }

  @override
  String get aiEditBlurb => '기존 AI 추천과 같은 방식으로 운동명·시간·구성을 수정할 수 있어요.';

  @override
  String get aiAddExerciseManually => '운동 직접 추가하기';

  @override
  String get aiExerciseNameExample => '예: 레그프레스 3세트';

  @override
  String get aiRegister => '등록';

  @override
  String get aiNoteForClient => '회원에게 함께 전달할 내용';

  @override
  String aiReviewedSuggestion(String option) {
    return '검토 완료 · AI 추천안 ($option)';
  }

  @override
  String get aiEditsApplied => '선택하고 수정한 내용이 최종 추천 목록에 반영됐어요.';

  @override
  String aiGoToChat(String name) {
    return '$name님 채팅으로 이동';
  }

  @override
  String get aiSending => '전송 중…';

  @override
  String get aiSendToClient => '회원에게 전송';

  @override
  String get aiGoToChatHint => '아래 버튼에서 회원 채팅으로 이동해 바로 안내할 수 있어요.';

  @override
  String get aiApplyToTemplate => '템플릿에 반영';

  @override
  String get aiAppliedToTemplate => 'AI 추천안이 프로그램 템플릿에 반영됐어요.';

  @override
  String get aiStepConditions => '조건 설정';

  @override
  String get aiStepReview => '프로그램 선택';

  @override
  String get aiStepDone => '최종 검토';

  @override
  String get aiStepperLabel => '맞춤 추천안 생성 진행 단계';

  @override
  String coachTemplateSummaryWithGoal(String goal, int count, int minutes) {
    return '$goal · $count개 · $minutes분';
  }

  @override
  String get aiInsightMemoTitle => '최근 7일 AI 감지 메모';

  @override
  String get aiInsightMemoEmpty => '최근 7일간 감지된 메모가 없어요';

  @override
  String get aiInsightMemoFailed => '감지 메모를 불러오지 못했어요';

  @override
  String aiRecentRoutineMore(String name, int count) {
    return '$name 외 $count개';
  }

  @override
  String get aiNoRecentRoutine => '기록 없음';

  @override
  String get aiRecentRoutine => '최근 운동';

  @override
  String get aiTrainerNoteEditable => '트레이너 메모 · 수정 가능';

  @override
  String get aiNotePlaceholderHint =>
      '회색 제안 문구는 입력 전 참고용이며, 직접 입력한 메모만 저장·전송돼요.';

  @override
  String get aiGenerateConditions => '생성 조건';

  @override
  String get aiCompareCandidates => '맞춤 추천안 후보를 비교해 보세요';

  @override
  String get aiConditionsAutoHint => '비워두면 최근 기록이나 목표를 기준으로 자동 설정돼요.';

  @override
  String get aiConditionsEditToggle => '추천 조건 수정';

  @override
  String get aiPromptTitle => 'AI에게 원하는 프로그램을 말해 주세요';

  @override
  String get aiPromptLabel => '요청 내용';

  @override
  String get aiPromptHint => '예: 하체 부담 적고 유산소 비중 높은 40분 프로그램 만들어줘';

  @override
  String get aiPromptBlurb =>
      '요청은 회원 데이터와 함께 AI에 전달돼요(최대 500자). 회원용 메모는 다음 단계에서 작성해요.';

  @override
  String get aiGenerateGoalBased => '목표 기반 추천안 생성';

  @override
  String get aiStatusTemplateTitle => '목표 기반 기본 추천';

  @override
  String get aiStatusTemplateBody => '아직 개인화하기엔 운동 기록이 부족해 목표를 기준으로 추천했어요.';

  @override
  String get aiStatusLearningTitle => '개인화 학습 중';

  @override
  String get aiStatusLearningBody => '최근 운동을 참고했지만 아직 반복 패턴이라 부르기엔 일러요.';

  @override
  String get aiStatusPersonalizedTitle => '최근 패턴 분석 완료';

  @override
  String aiStatusPersonalizedBody(int count, int days) {
    return '최근 $days일 · $count회 기록을 기준으로 분석했어요.';
  }

  @override
  String get aiFrequentExercisesLabel => '자주 한 운동';

  @override
  String get goalWeightLoss => '체중 감량';

  @override
  String get goalStrength => '근력 향상';

  @override
  String get goalFitness => '체력 증진';

  @override
  String get goalPosture => '자세 교정';

  @override
  String get goalHealth => '건강 관리';

  @override
  String get goalOther => '기타';

  @override
  String get slotAm => '오전';

  @override
  String get slotPm => '오후';

  @override
  String get slotFlexible => '조율 가능';

  @override
  String get unknownMember => '알 수 없는 회원';

  @override
  String get filterAll => '전체';

  @override
  String get alertSodiumOver => '나트륨 초과';

  @override
  String get alertSugarOver => '당류 초과';

  @override
  String get alertLowCompletion => '이행률 저조';

  @override
  String get alertAwaitingReply => '답장 대기';

  @override
  String get clientLastRoutine => '마지막 프로그램';

  @override
  String metricOverBy(String unit) {
    return '$unit 초과';
  }

  @override
  String get authErrInvalidCredentials => '이메일 또는 비밀번호가 올바르지 않습니다.';

  @override
  String get authErrEmailTaken => '이미 가입된 이메일입니다.';

  @override
  String get authErrInviteCodeInvalid => '사용할 수 없는 초대 코드예요. 헬스장에 확인해 주세요.';

  @override
  String get authErrSessionExpired => '세션이 만료됐어요. 다시 로그인해 주세요.';

  @override
  String get authErrNoSocialToken => '소셜 로그인 토큰이 없어요';

  @override
  String get authErrNetwork => '네트워크 연결을 확인해 주세요.';

  @override
  String get authErrGeneric => '로그인 중 문제가 발생했어요. 잠시 후 다시 시도해 주세요.';

  @override
  String get authErrEmptyResponse => '응답이 비어 있어요.';

  @override
  String get coachDemoUnavailable => '데모 모드에서는 AI 코칭을 사용할 수 없어요';

  @override
  String get coachNotMyClient => '담당 회원이 아니에요';

  @override
  String get coachAskFailed => '질문을 보낼 수 없어요';

  @override
  String get slotFutureOnly => '현재보다 이후 시간만 예약 슬롯으로 설정할 수 있습니다.';

  @override
  String get slotNotFound => '예약 슬롯을 찾을 수 없습니다.';

  @override
  String get slotTypeLockedByBooking => '이미 예약된 자리의 종류는 바꿀 수 없습니다.';

  @override
  String get slotSessionType => '종류';

  @override
  String get authErrNotTrainer => '트레이너 계정으로 로그인해 주세요.';

  @override
  String aiBasisGoalCompletion(String goal, int rate) {
    return '$goal · 완료율 $rate% 기준';
  }

  @override
  String aiBasisTrainerRequest(String request) {
    return '요청: \"$request\"';
  }

  @override
  String aiTotalAndIntensity(int total, String intensity) {
    return '총 $total분 · 강도 $intensity';
  }

  @override
  String aiBulletExercise(String name, int minutes) {
    return '· $name · $minutes분 ';
  }

  @override
  String schedHourLabel(String hour) {
    return '$hour시';
  }

  @override
  String schedMinuteLabel(String minute) {
    return '$minute분';
  }

  @override
  String get progDefaultReps => '10회';

  @override
  String get appTitleSpaced => 'On - Care 트레이너';

  @override
  String get navNotifications => '알림';

  @override
  String get notifTitle => '알림';

  @override
  String get notifReadAll => '모두 읽음';

  @override
  String get notifEmpty => '아직 받은 알림이 없어요';

  @override
  String get notifLoadFailed => '알림을 불러오지 못했어요';

  @override
  String get notifAllRead => '모두 확인했어요';

  @override
  String get notifReadAllFailed => '읽음 처리에 실패했어요. 잠시 후 다시 시도해 주세요';

  @override
  String notifUnreadCount(int count) {
    return '읽지 않은 알림 $count건';
  }

  @override
  String get myDeleteAccount => '계정 탈퇴';

  @override
  String get myDeleteAction => '탈퇴';

  @override
  String get myDeleteHint => '담당 회원 연결과 예약이 함께 사라져요';

  @override
  String get myDeleteDemo => '데모 모드에는 지울 계정이 없어요';

  @override
  String get myDeleteTitle => '계정을 탈퇴할까요?';

  @override
  String get myDeleteBody =>
      '담당 회원 연결과 예약이 사라지고, 회원에게 알림이 전달돼요. 이 작업은 되돌릴 수 없어요.';

  @override
  String get myDeleteFailed => '탈퇴하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String myDeleteConfirmPrompt(String name) {
    return '계속하려면 이름($name)을 입력해 주세요';
  }

  @override
  String get routineAlreadyGone => '이미 삭제된 프로그램이에요';

  @override
  String get workoutPendingTitle => '아직 하지 않은 개인 운동';

  @override
  String get workoutUndatedTitle => '날짜를 알 수 없는 기록';

  @override
  String get workoutPendingCancel => '배정 취소';

  @override
  String get routineUpdateFailed => '프로그램을 수정하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get routineUpdated => '프로그램을 수정했어요';

  @override
  String get routineDeleteTitle => '프로그램을 삭제할까요?';

  @override
  String get routineDeleteFailed => '프로그램을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get routineDeleted => '프로그램을 삭제했어요';

  @override
  String get routineEdit => '프로그램 수정';

  @override
  String get routineDelete => '프로그램 삭제';

  @override
  String get routineNameRequired => '프로그램 이름을 입력해 주세요';

  @override
  String get routineNameTooLong => '프로그램 이름은 100자 이내로 입력해 주세요';

  @override
  String get routineMinutesRange => '시간은 0~600분 사이로 입력해 주세요';

  @override
  String get routineReasonTooLong => '사유는 200자 이내로 입력해 주세요';

  @override
  String get routineFieldName => '프로그램 이름';

  @override
  String get routineFieldMinutesLabel => '시간(분)';

  @override
  String get routineFieldReason => '사유 (선택)';

  @override
  String routineDeleteBody(String name) {
    return '$name 배정이 회원 앱에서도 사라져요.';
  }

  @override
  String get searchClients => '회원 검색';

  @override
  String get searchClientsHint => '회원·목표·최근 메시지·마지막 프로그램 전송일 검색';

  @override
  String get searchClear => '검색어 지우기';

  @override
  String get searchQuickActions => '다른 탭에서 열기';

  @override
  String searchNoResults(String query) {
    return '“$query”와 일치하는 회원이 없어요';
  }

  @override
  String get searchGoClientDetail => '선택하면 회원 상세가 열려요';

  @override
  String get searchGoSchedule => '선택하면 다음 예약 날짜로 이동해요';

  @override
  String get searchGoCoaching => '선택하면 AI 코칭에 불러와요';

  @override
  String get searchGoReport => '선택하면 주간 리포트를 열어요';

  @override
  String searchDetailUnread(int count) {
    return '답장 대기 $count건';
  }

  @override
  String searchDetailMessage(String message, String time) {
    return '$message · $time';
  }

  @override
  String searchDetailNextSession(String date, String time) {
    return '다음 예약 $date $time';
  }

  @override
  String get searchDetailNoUpcoming => '예정된 예약 없음';

  @override
  String searchDetailLastRoutine(String when) {
    return '마지막 프로그램 $when';
  }

  @override
  String searchDetailCompletion(int percent) {
    return '이번 주 이행률 $percent%';
  }

  @override
  String get routineFeedbackTitle => '수행 피드백';

  @override
  String get routineFeedbackHint => '회원에게 전할 코칭 피드백을 입력해 주세요';

  @override
  String get routineFeedbackWrite => '피드백 작성';

  @override
  String get routineFeedbackEdit => '피드백 수정';

  @override
  String get routineFeedbackSaved => '피드백을 저장했어요';

  @override
  String get routineFeedbackFailed => '피드백을 저장하지 못했어요. 다시 시도해 주세요';

  @override
  String get navOperationsGroup => '운영';

  @override
  String get navCoachingGroup => '코칭';

  @override
  String get dashTodayTasks => '오늘 할 일';

  @override
  String get dashTasksReviewed => '모두 확인했어요';

  @override
  String dashTasksNeedReview(int count) {
    return '$count개 확인 필요';
  }

  @override
  String get dashTaskProgressTitle => '할 일 진행률';

  @override
  String get dashTaskProgressToday => '오늘 처리';

  @override
  String get dashTaskProgressCarriedOver => '이월 처리';

  @override
  String get dashTodoConsultation => '상담';

  @override
  String get dashTodoDiet => '식단';

  @override
  String get dashTodoWorkout => '운동';

  @override
  String get dashTodoProgram => '프로그램';

  @override
  String get dashTodoReport => '리포트';

  @override
  String dashTodoConsultationSubtitle(int month, int day) {
    return '$month/$day 상담 요청';
  }

  @override
  String dashTodoSodiumSubtitle(int sodiumMg, int targetMg) {
    return '나트륨 ${sodiumMg}mg · 목표 ${targetMg}mg';
  }

  @override
  String dashTodoSugarSubtitle(int sugarG, int targetG) {
    return '당류 ${sugarG}g · 목표 ${targetG}g';
  }

  @override
  String get dashTodoCompletionSubtitle => '이행률 저조 · 최근 기록 확인';

  @override
  String get dashTodoCarriedOverDemoSubtitle => '어제 남긴 식단 피드백';

  @override
  String get dashTodoProgramSubtitle => '최근 등록한 프로그램 없음';

  @override
  String get dashTodoReportSubtitle => '이번 주 리포트 작성 대상';

  @override
  String get dashTaskDismissTitle => '이 항목을 삭제할까요?';

  @override
  String get dashTaskDismissBody =>
      '할 일 목록에서만 사라져요. 실제 처리(상담·프로그램·리포트)는 각 화면에서 해야 해요.';

  @override
  String get dashTaskCarriedOverTitle => '지난 할 일';

  @override
  String get dashTaskCategoryDone => '완료';

  @override
  String dashTaskCategoryRemaining(int count) {
    return '+$count';
  }

  @override
  String dashTaskUncheckTitle(String name) {
    return '\'$name\' 완료를 취소할까요?';
  }

  @override
  String get dashTaskUncheckBody => '할 일 진행률에서도 빠져요.';

  @override
  String get dashTaskUncheckConfirm => '완료 취소';

  @override
  String get churnNoRecentWorkout => '최근 7일 운동 기록 없음';

  @override
  String get churnNoRecentFeedback => '최근 7일 트레이너 피드백 없음';

  @override
  String get churnConsecutiveCancel => 'PT 2회 연속 취소·노쇼';

  @override
  String get churnDietStopped => '식단 기록 중단';

  @override
  String get churnGoalStagnant => '목표 지표 장기간 정체';

  @override
  String get churnUnresolvedRequest => '미응답 메시지 있음';

  @override
  String get navMessages => '메시지';

  @override
  String get messagesSubtitle => '회원과 코칭 내용을 주고받고 빠르게 후속 조치하세요';

  @override
  String get messagesLoadFailed => '대화 목록을 불러오지 못했어요.';

  @override
  String get messagesEmpty => '조건에 맞는 대화가 없어요.';

  @override
  String get messagesFilterAll => '전체';

  @override
  String get messagesFilterUnread => '읽지 않음';

  @override
  String get messagesFilterAttention => '관리 필요';

  @override
  String messagesFilterUnreadCount(int count) {
    return '읽지 않음 $count';
  }

  @override
  String get messagesBackToList => '대화 목록';

  @override
  String get messagesNoPreview => '아직 대화가 없어요';

  @override
  String get messagesClientDetail => '회원 상세';

  @override
  String get messagesSelectPrompt => '왼쪽 목록에서 대화할 회원을 선택하세요.';

  @override
  String get clientQuickMessages => '메시지';

  @override
  String get clientQuickProgram => '프로그램';

  @override
  String get clientQuickReport => '리포트';

  @override
  String get clientHealthGoals => '회원 신체·목표 관리';

  @override
  String get clientProfileSectionTitle => '신체·목표·메모';

  @override
  String get clientTrainerMemo => '메모';

  @override
  String get clientTrainerMemoHint => '이 회원에 대해 기억할 내용을 적어 주세요';

  @override
  String get clientTrainerMemoAdd => '메모 추가';

  @override
  String get clientTrainerMemoEmpty => '아직 남긴 메모가 없어요.';

  @override
  String get clientTrainerMemoFromChat => '채팅에서 감지';

  @override
  String get clientTrainerMemoLoadFailed => '메모를 불러오지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get clientTrainerMemoSaveFailed => '메모를 저장하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get clientTrainerMemoDeleteFailed => '메모를 삭제하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get clientTrainerMemoDeleteTitle => '메모를 삭제할까요?';

  @override
  String get clientTrainerMemoDeleteBody => '지운 메모는 되돌릴 수 없어요.';

  @override
  String get followUp => '후속 관리';

  @override
  String followUpTitle(String name) {
    return '$name님 후속 관리';
  }

  @override
  String get followUpHint => '다시 확인할 내용을 적어 주세요';

  @override
  String get followUpAdd => '후속 관리 추가';

  @override
  String get followUpDue => '확인 예정일';

  @override
  String followUpDueOn(String date) {
    return '$date 확인';
  }

  @override
  String get followUpOverdue => '기한 지남';

  @override
  String get followUpContext => '관련 화면';

  @override
  String get followUpContextGeneral => '회원 상세';

  @override
  String get followUpContextDiet => '식단';

  @override
  String get followUpContextExercise => '운동';

  @override
  String get followUpContextMessage => '메시지';

  @override
  String get followUpContextProgram => '프로그램';

  @override
  String get followUpContextSchedule => '일정';

  @override
  String get followUpComplete => '완료';

  @override
  String followUpCount(int count) {
    return '$count건';
  }

  @override
  String get followUpEmpty => '남은 후속 관리가 없어요.';

  @override
  String get followUpDashboardEmpty => '오늘 처리할 후속 관리가 없어요.';

  @override
  String get followUpLoadFailed => '후속 관리를 불러오지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get followUpSaveFailed => '후속 관리를 저장하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get followUpCompleteFailed => '완료 처리하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String programEditorDefaultName(String goal) {
    return '$goal 프로그램';
  }

  @override
  String get programEditorDefaultSession => '세션 A';

  @override
  String get programEditorSaveUnsupported => '프로그램 이름을 입력해 주세요';

  @override
  String get programEditorSaveEdit => '수정 저장';

  @override
  String get programSavedTitle => '저장한 프로그램';

  @override
  String programSavedExerciseCount(int count) {
    return '운동 $count개';
  }

  @override
  String get programSavedNew => '새 프로그램';

  @override
  String get suggestionReviewTitle => 'AI 개인운동 제안';

  @override
  String suggestionReviewBadge(int count) {
    return '검토 필요 $count';
  }

  @override
  String suggestionReviewIntro(String name) {
    return '최근 PT 피드백과 운동 기록을 바탕으로 $name님에게 도움이 될 개인운동을 준비했어요. 추천한 것만 회원에게 보여요.';
  }

  @override
  String get suggestionReviewEmpty => '검토할 AI 개인운동 제안이 없어요';

  @override
  String get suggestionReviewLoadFailed => 'AI 개인운동 제안을 불러오지 못했어요';

  @override
  String get suggestionApprove => '회원에게 추천';

  @override
  String get suggestionConfirmTitle => '최종 검토 · 회원에게 추천';

  @override
  String suggestionConfirmBody(String client) {
    return '아래 내용 그대로 $client님에게 추천돼요. 추천하면 회원 앱에 바로 보여요.';
  }

  @override
  String get suggestionDismiss => '추천 안 함';

  @override
  String suggestionApproved(String name, String client) {
    return '$name을(를) $client님에게 추천했어요';
  }

  @override
  String suggestionDismissed(String name) {
    return '$name은(는) 추천하지 않아요';
  }

  @override
  String get suggestionActionFailed => '처리하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get suggestionAlreadyReviewed => '이미 검토한 제안이에요. 목록을 새로 불러왔어요';

  @override
  String get suggestionEditTitle => '개인운동 수정';

  @override
  String get suggestionEditSubmit => '수정 후 추천';

  @override
  String get suggestionEditName => '운동';

  @override
  String get suggestionEditMemo => '회원에게 전달할 메모';

  @override
  String get suggestionEditMemoHint => '오른쪽 어깨에 통증이 생기면 중단하세요';

  @override
  String get programDraftSaved => '프로그램을 저장했어요';

  @override
  String get programDraftSaveFailed => '프로그램을 저장하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String programDraftLoaded(String name) {
    return '$name을(를) 편집기로 불러왔어요';
  }

  @override
  String get programDraftLoadFailed => '저장한 프로그램을 불러오지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get programDraftDeleteFailed => '프로그램을 삭제하지 못했어요. 잠시 후 다시 시도해 주세요';

  @override
  String get programDraftDeleteTitle => '저장한 프로그램을 삭제할까요?';

  @override
  String get programDraftDeleteBody => '이미 배정한 프로그램과 등록한 일정은 그대로 남아요.';

  @override
  String get programEditorAssignUnsupported => '운동 이름과 세트 수를 확인해 주세요';

  @override
  String get programAssignConfirmTitle => '일정에 추가할까요?';

  @override
  String programAssignConfirmBody(String name, String date, String time) {
    return '$date $time에 $name님의 PT 스케줄에 이 프로그램이 추가돼요.';
  }

  @override
  String get programEditorSaveTemplate => '템플릿 저장';

  @override
  String get programEditorAddSchedule => '일정 추가';

  @override
  String get programReviewTitle => '전송 확인';

  @override
  String programReviewBlurb(String name) {
    return '아래 구성 그대로 $name님에게 전송돼요. 확인한 뒤 전송해 주세요.';
  }

  @override
  String get programReviewBack => '편집기로 돌아가 수정';

  @override
  String programReviewSessionSummary(int count) {
    return '운동 $count개';
  }

  @override
  String get programEditorInfo => '프로그램 정보';

  @override
  String get programEditorName => '프로그램명';

  @override
  String get programEditorGoal => '목표 (선택)';

  @override
  String get programEditorPeriod => '기간 (선택)';

  @override
  String get programEditorMemo => '프로그램 메모 (선택)';

  @override
  String get programEditorAiHint => 'AI 코칭 보조 제안을 첫 세션에 로컬 초안으로 반영할 수 있어요.';

  @override
  String get programEditorApply => '편집기에 반영';

  @override
  String get programEditorExerciseConfig => '운동 구성';

  @override
  String get programEditorAddSession => '세션 추가';

  @override
  String get programTemplateSessionPickerTitle => '어느 세션에 추가할까요?';

  @override
  String programTemplateSessionPickerBody(String name) {
    return '\'$name\' 템플릿을 추가할 세션을 골라 주세요.';
  }

  @override
  String programEditorSessionName(String letter) {
    return '세션 $letter';
  }

  @override
  String get programEditorSessionUp => '세션 위로 이동';

  @override
  String get programEditorSessionDown => '세션 아래로 이동';

  @override
  String get programEditorSessionReset => '세션 초기화';

  @override
  String get programEditorSessionResetTitle => '세션을 초기화할까요?';

  @override
  String programEditorSessionResetBody(String name) {
    return '\'$name\' 세션의 운동이 모두 지워져요. 세션 자체와 다른 세션은 그대로 남아요.';
  }

  @override
  String get programEditorSessionEmpty => '운동을 추가해 세션을 구성하세요.';

  @override
  String get programEditorAdd => '추가';

  @override
  String get programEditorAddExercise => '운동 추가';

  @override
  String get programEditorExercise => '운동';

  @override
  String get programEditorExerciseUp => '운동 위로 이동';

  @override
  String get programEditorExerciseDown => '운동 아래로 이동';

  @override
  String get programEditorSets => '세트';

  @override
  String get programEditorReps => '횟수';

  @override
  String get programEditorWeight => '중량 kg';

  @override
  String get programEditorDuration => '시간 분';

  @override
  String get programEditorDistance => '거리 m';

  @override
  String get programEditorRest => '휴식 초';

  @override
  String get programEditorExerciseMemo => '메모';

  @override
  String reportsComparisonTitle(String week) {
    return '$week vs 지난 주';
  }

  @override
  String get reportsGoThisWeek => '이번 주로';

  @override
  String get reportsSummaryEmptyClient =>
      '회원을 선택하면 그 주의 리포트 요약과 코칭 제안이 여기에 표시돼요';

  @override
  String get reportsLastWeek => '지난 주';

  @override
  String get reportsSelectedWeek => '선택 주';

  @override
  String get reportsBackToList => '회원 목록';

  @override
  String get reportsPreviousLoadFailed => '지난주 데이터를 불러오지 못했어요.';

  @override
  String get reportsAverageSodium => '평균 나트륨';

  @override
  String get reportsFeedbackTitle => '트레이너 피드백';

  @override
  String get reportsFeedbackDraftNote =>
      '수치에서 자동으로 채운 초안이에요. 보내기 전에 확인하고 고쳐 주세요.';

  @override
  String get reportsFeedbackRestore => '초안으로 되돌리기';

  @override
  String get reportsFeedbackSave => '피드백 저장';

  @override
  String get reportsFeedbackSaving => '저장 중…';

  @override
  String get reportsFeedbackSaved => '피드백 초안을 저장했어요.';

  @override
  String get reportsFeedbackSaveFailed => '초안을 저장하지 못했어요. 다시 시도해 주세요.';

  @override
  String get reportsFeedbackHint => '회원에게 전달할 코칭 피드백을 작성하세요.';

  @override
  String get reportsRecentWeeks => '최근 4주 평균';

  @override
  String get reportsWeekTotal => '주 합계';

  @override
  String reportsGoalOf(String value) {
    return '목표 $value';
  }

  @override
  String get reportsCompareWith => '지난 주 대비';

  @override
  String reportsMoreExercises(int count) {
    return '+$count개';
  }

  @override
  String reportsRecordedDays(int days) {
    return '기록 $days일';
  }

  @override
  String reportsAdherenceChip(String value) {
    return '이행률 평균 $value';
  }

  @override
  String get reportsBurnByDay => '주간 소모 칼로리';

  @override
  String get reportsBurnEstimateNote => '소모 칼로리는 운동 유형·시간·강도로 낸 추정치예요.';

  @override
  String chartGoalLabel(String value) {
    return '목표\n$value';
  }

  @override
  String reportsWeeksAgo(int count) {
    return '$count주 전';
  }

  @override
  String get reportsAiTitle => 'AI 코칭 보조 · 리포트 요약';

  @override
  String get reportsAiNextWeek => '다음 주 코칭 제안';

  @override
  String reportsAiMoreWatchpoints(int count) {
    return '외 $count건은 리포트 본문에서 확인하세요.';
  }

  @override
  String get reportsActionSodium => '국물·절임 반찬을 절반만 남기도록 안내해 주세요.';

  @override
  String reportsActionSugar(String target) {
    return '당류가 목표(${target}g)를 넘긴 날이 있어요. 음료·간식부터 짚어 주세요.';
  }

  @override
  String get reportsActionLowCompletion =>
      '프로그램 난이도를 한 단계 낮춰 완수 경험을 먼저 만들어 주세요.';

  @override
  String get reportsActionHighCompletion =>
      '페이스가 좋아요. 다음 주에는 세트 수나 중량을 한 단계 올려 보세요.';

  @override
  String reportsActionSkipped(String names) {
    return '$names 대체 동작을 준비해 다음 세션에서 맞춰 주세요.';
  }

  @override
  String reportsActionUnlogged(int days) {
    return '기록이 없는 날이 $days일이었어요. 기록 습관을 먼저 잡아 주세요.';
  }

  @override
  String reportsActionCalories(String target) {
    return '칼로리가 목표(${target}kcal)보다 적어요. 단백질 한 끼 보완을 제안해 주세요.';
  }

  @override
  String get reportsAiGenerated => 'AI 생성';

  @override
  String get reportsAiLoading => '이번 주 요약을 만들고 있어요…';

  @override
  String get reportsAiUseAsDraft => '피드백으로 가져오기';

  @override
  String get reportsAiRegenerate => '다시 생성';

  @override
  String get reportsAiUnavailable =>
      '실제 리포트 요약 API 연결 후 사용할 수 있어요. 현재 문구는 자동 생성하지 않습니다.';

  @override
  String get reportsPdfLabel => 'PDF 내보내기';

  @override
  String get reportsPdfGenerating => 'PDF 생성 중…';

  @override
  String get reportsPdfGenerationFailed => 'PDF를 생성하지 못했어요. 다시 시도해 주세요.';

  @override
  String reportsPdfReady(String name) {
    return '$name님의 주간 리포트가 준비됐어요.';
  }

  @override
  String get reportsPdfSending => '전송 중…';

  @override
  String get reportsPdfSendToClient => '회원에게 전송';

  @override
  String get reportsPdfSave => 'PDF 저장';

  @override
  String get reportsPdfPrint => '인쇄';

  @override
  String get reportsPdfClose => '닫기';

  @override
  String get reportsPdfActionFailed => '작업을 완료하지 못했어요. 다시 시도해 주세요.';

  @override
  String reportsPdfSent(String name) {
    return '$name님에게 PDF를 전송했어요.';
  }

  @override
  String get reportsPdfSaveStarted => 'PDF 저장을 시작했어요.';

  @override
  String get reportsPdfPrintOpened => '인쇄 창을 열었어요.';

  @override
  String get reportsPdfMessage => '이번 주 리포트를 보내드려요.';

  @override
  String get reportsPdfFallbackClient => '회원';

  @override
  String get reportsPdfDocTitle => '주간 코칭 리포트';

  @override
  String get reportsPdfDocTitleContinued => '주간 코칭 리포트 (계속)';

  @override
  String reportsPdfClient(String name) {
    return '회원  $name';
  }

  @override
  String reportsPdfPeriod(String start, String end) {
    return '기간  $start ~ $end';
  }

  @override
  String get reportsPdfSectionMetrics => '핵심 지표';

  @override
  String get reportsPdfSectionChange => '전주 대비 변화';

  @override
  String get reportsPdfSectionTrend => '주간 추이 (월~일)';

  @override
  String get reportsPdfSectionDaily => '일자별 운동';

  @override
  String reportsPdfBullet(String label, String value) {
    return '• $label: $value';
  }

  @override
  String reportsPdfDay(String weekday, String completion, String exercises) {
    return '$weekday: $completion · $exercises';
  }

  @override
  String get reportsPdfLabelCompletion => '운동 수행률';

  @override
  String get reportsPdfLabelSessions => 'PT 진행';

  @override
  String get reportsPdfLabelSessionCount => 'PT 진행 횟수';

  @override
  String get reportsPdfLabelSodiumOver => '나트륨 목표 초과';

  @override
  String get reportsPdfLabelCalories => '평균 열량';

  @override
  String get reportsPdfLabelSugar => '평균 당류';

  @override
  String get reportsPdfLabelCaloriesShort => '열량';

  @override
  String get reportsPdfLabelSodiumShort => '나트륨';

  @override
  String get reportsPdfLabelSugarShort => '당류';

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
    return '$value일';
  }

  @override
  String reportsPdfValueSessions(String value) {
    return '$value회';
  }

  @override
  String reportsPdfAttendance(String done, String booked, String rate) {
    return '$done/$booked회 ($rate%)';
  }

  @override
  String get reportsPdfNoData => '미집계';

  @override
  String get reportsPdfNoFeedback => '피드백 없음';

  @override
  String a11yChartSummary(String title, String detail) {
    return '$title. $detail';
  }

  @override
  String a11yChartEmpty(String title) {
    return '$title. 기록이 없어요';
  }

  @override
  String a11yChartPoint(String day, String value) {
    return '$day $value';
  }

  @override
  String get a11yShowPassword => '비밀번호 표시';

  @override
  String get a11yHidePassword => '비밀번호 숨기기';

  @override
  String get unitMg => 'mg';

  @override
  String get unitGram => 'g';

  @override
  String get a11yRemoveExercise => '운동 지우기';

  @override
  String get a11yRemoveCertification => '자격증 지우기';

  @override
  String get a11yPrevWeek => '이전 주';

  @override
  String get a11yNextWeek => '다음 주';

  @override
  String get a11ySendMessage => '메시지 보내기';

  @override
  String get aiManualCreate => '직접 만들기';

  @override
  String get aiReturnToWizard => 'AI 추천으로 돌아가기';
}
