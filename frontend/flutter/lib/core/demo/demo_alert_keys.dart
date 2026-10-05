/// 데모 알림 문구의 **식별자**. (#1812)
///
/// 문구 자체는 ARB(`demoAlert…`)가 ko·en 양쪽으로 갖고 있고, 데모 데이터(목업
/// 알림·로컬 시드)는 이 키만 싣는다. 화면이 키를 받아 로케일에 맞는 문장을 고른다
/// — 홈 AI 조언 데모와 같은 방식이다(`demo_ai_advice.dart`, #435).
///
/// 서버가 만든 알림은 번역본이 없으므로 키 없이 제목·본문 문자열로 온다.
library;

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
  'seed-noti-5': kDemoAlertRoutine,
  'seed-noti-7': kDemoAlertReport,
  'seed-noti-2': kDemoAlertPtDone,
  'seed-noti-3': kDemoAlertTrainerFeedback,
  'seed-noti-6': kDemoAlertWeeklyGoal,
  'seed-noti-9': kDemoAlertMealStreak,
  'seed-noti-4': kDemoAlertMaintenance,
};

/// 로컬 시드 알림 id → 화면에 보이는 경과 시간. (#2660)
///
/// 시드는 그날 처음 켤 때 오늘로 옮겨지지만, 같은 날 안에서 실제 경과로 셈하면
/// "10분 전" 이 몇 시간 뒤 "5시간 전" 이 되어 "오늘 18:00 PT를 마쳤어요" 같은 문구와
/// 어긋난다. 예전 데모 목록처럼 언제 열어도 같은 시각으로 보이게 인터셉터가 이 값으로
/// `time_ago` 를 셈한다. 시드가 넣는 `created_at` 과 같은 값이다(순서·커서는 그쪽).
const Map<String, Duration> kDemoAlertAgeBySeedId = <String, Duration>{
  'seed-noti-5': Duration(minutes: 30),
  'seed-noti-7': Duration(minutes: 45),
  'seed-noti-2': Duration(hours: 1),
  'seed-noti-3': Duration(hours: 2),
  'seed-noti-6': Duration(hours: 3),
  'seed-noti-9': Duration(hours: 26),
  'seed-noti-4': Duration(hours: 28),
};

/// 로컬 시드 알림 id → 누르면 갈 곳(서버 `action` 과 같은 모양). (#2660)
///
/// 예전 데모 목록이 알림마다 정해 둔 목적지다 — 운동 목표·PT 완료는 운동. 서버는 갈래별 표로만 정해 이 알림들이 모두 홈으로 가는데, 데모
/// 화면이 기준이라 데모 목적지를 그대로 둔다(서버를 맞추는 일은 #2690). 표에 없는
/// 시드(점검 공지)는 갈 곳이 없다.
const Map<String, ({String label, String target})> kDemoAlertActionBySeedId =
    <String, ({String label, String target})>{
      'seed-noti-5': (label: '운동 보기', target: 'exercise'),
      'seed-noti-7': (label: '리포트 보기', target: 'coach_chat'),
      // 서버 `pt_done` 갈래의 라벨과 같다(#3027).
      'seed-noti-2': (label: 'PT 기록 보기', target: 'exercise'),
      'seed-noti-3': (label: '대화 보기', target: 'coach_chat'),
      'seed-noti-6': (label: '운동 보기', target: 'exercise'),
      'seed-noti-9': (label: '홈 보기', target: 'dashboard'),
    };

/// 실서버가 만들지 않는 식단 알림(나트륨 주의·저녁 기록 독려)이라 뺀 시드
/// id(#2854). 데모에서만 보이면 실서비스로 옮긴 회원에게 기능이 사라진 것으로
/// 보인다. 오늘 이미 시드된 설치에도 남지 않도록 시드가 먼저 지운다.
const Set<String> kRetiredDemoAlertSeedIds = <String>{
  'seed-noti-1',
  'seed-noti-8',
};

/// 시드할 때 이미 읽은 알림. 데모에 다시 로그인하면 시드 알림이 이 상태로 돌아간다.
const Set<String> kDemoAlertReadSeedIds = <String>{
  'seed-noti-9',
  'seed-noti-4',
};
