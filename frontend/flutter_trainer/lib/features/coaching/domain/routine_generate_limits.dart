/// AI 루틴 생성 조건의 총 운동 시간 범위(분). (#2871)
///
/// 서버 `RoutineOptionsRequest.available_minutes`(`ge=10, le=180`)와 같은
/// 값이다 — 생성 규칙·프롬프트가 이 범위를 전제로 짜여 있어 서버를 기준으로
/// 삼는다. 마법사의 총 시간 칸, 데모 생성, 실서버 422 안내가 모두 이 값을
/// 읽는다. 개별 운동 시간 칸(1~600분)과는 다른 범위다.
library;

/// 생성 조건 총 시간의 하한(분).
const int kRoutineGenerateMinMinutes = 10;

/// 생성 조건 총 시간의 상한(분).
const int kRoutineGenerateMaxMinutes = 180;

/// [minutes] 가 서버가 받는 생성 조건 범위 안인가.
bool isRoutineGenerateMinutesInRange(int minutes) =>
    minutes >= kRoutineGenerateMinMinutes &&
    minutes <= kRoutineGenerateMaxMinutes;

/// [minutes] 를 생성 조건 범위로 당긴다. 서버가 돌려준 추천 시간을 칸에
/// 채울 때 쓴다 — 칸이 받지 않는 값이 그대로 다음 요청에 실리지 않게 한다.
int clampRoutineGenerateMinutes(int minutes) =>
    minutes.clamp(kRoutineGenerateMinMinutes, kRoutineGenerateMaxMinutes);
