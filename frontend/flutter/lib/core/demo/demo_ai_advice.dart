/// 홈 '오늘의 AI 통합 조언' 데모 문구의 **식별자**.
///
/// 문구 자체는 ARB(`homeAiAdviceBody`)가 갖고 있고, 데모 데이터(목 요약·시드
/// KV)는 이 키만 싣는다. 화면이 키를 받아 ARB 문장을 고른다(#435).
///
/// 서버가 만든 문장(나트륨 급원 기반 경고 등)은 지금처럼
/// `sodium_warning` 문자열로 온다 — 이 키는 데모 전용 통로다.
library;

/// 식단·운동·코치 피드백을 한 문장으로 엮은 하루 통합 조언.
const String kDailyCombinedAdviceKey = 'daily_combined';
