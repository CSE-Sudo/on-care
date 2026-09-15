/// 데모 알림 문구의 **식별자**. (#1812)
///
/// 문구 자체는 ARB(`demoAlert…`)가 ko·en 양쪽으로 갖고 있고, 데모 데이터(목업
/// 알림·로컬 시드)는 이 키만 싣는다. 화면이 키를 받아 로케일에 맞는 문장을 고른다
/// — 홈 AI 조언 데모와 같은 방식이다(`demo_ai_advice.dart`, #435).
///
/// 서버가 만든 알림은 번역본이 없으므로 키 없이 제목·본문 문자열로 온다.
library;

const String kDemoAlertSodium = 'sodium';
const String kDemoAlertDinner = 'dinner';
const String kDemoAlertRoutine = 'routine';
const String kDemoAlertReport = 'report';
const String kDemoAlertPtDone = 'pt_done';
const String kDemoAlertTrainerFeedback = 'trainer_feedback';
const String kDemoAlertWeeklyGoal = 'weekly_goal';
const String kDemoAlertMealStreak = 'meal_streak';
const String kDemoAlertMaintenance = 'maintenance';

/// 로컬 시드 알림 id → 문구 키. 시드 테이블에는 키 칸이 없어, 인터셉터가 응답을
/// 만들 때 이 표로 붙인다. 표에 없는 알림(앱에서 새로 생긴 것)은 키가 없다.
const Map<String, String> kDemoAlertKeyBySeedId = <String, String>{
  'seed-noti-1': kDemoAlertSodium,
  'seed-noti-8': kDemoAlertDinner,
  'seed-noti-5': kDemoAlertRoutine,
  'seed-noti-7': kDemoAlertReport,
  'seed-noti-2': kDemoAlertPtDone,
  'seed-noti-3': kDemoAlertTrainerFeedback,
  'seed-noti-6': kDemoAlertWeeklyGoal,
  'seed-noti-9': kDemoAlertMealStreak,
  'seed-noti-4': kDemoAlertMaintenance,
};
